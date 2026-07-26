import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/attendance_auto_close_policy.dart';
import '../core/attendance_presence_rules.dart';
import '../core/time_parse.dart';
import '../core/supabase_maps.dart';
import 'hierarchical_attendance_service.dart';
import 'attendance_hours_calculator_service.dart';
import 'attendance_hours_persistence_service.dart';

/// Closes teacher_attendance sessions that passed the exit deadline without exit,
/// credits fixed hours based on subject count, writes `attendance_in_out` exit rows for reporting,
/// and flags rows with `autoClosedMissingExit` (subject labels are display-only).
class StaleAttendanceReconciliationService {
  StaleAttendanceReconciliationService._();

  static String teacherDocId(String instituteId, String srNo, String date) =>
      '${instituteId}_${srNo}_$date';

  static Future<Map<String, dynamic>?> _fetchPayload(
    SupabaseClient db,
    String instituteId,
    String srNo,
    String date,
  ) async {
    final row = await db
        .from('teacher_attendance')
        .select()
        .eq('id', teacherDocId(instituteId, srNo, date))
        .maybeSingle();
    if (row == null) return null;
    final p = row['payload'];
    if (p is Map<String, dynamic>) return Map<String, dynamic>.from(p);
    if (p is Map) return p.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  static Future<void> _upsertTeacherPayload(
    SupabaseClient db,
    String instituteId,
    String srNo,
    String date,
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.from('teacher_attendance').upsert(
      {
        'id': teacherDocId(instituteId, srNo, date),
        'institute_id': instituteId,
        'student_id': srNo,
        'date': date,
        'status': payload['status']?.toString(),
        'payload': payload,
        'updated_at': now,
      },
      onConflict: 'id',
    );
  }

  static Future<void> _syncAutoClosedExit({
    required String instituteId,
    required String srNo,
    required String date,
    required AutoCloseSyncHint hint,
    required int enrolledSubjectCount,
  }) async {
    try {
      final key = srNo.trim();
      var row = await appDb
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId)
          .eq('sr_no', key)
          .maybeSingle();
      row ??= await appDb
          .from('students')
          .select('id,name,user_id,sr_no')
          .eq('institute_id', instituteId)
          .eq('user_id', key)
          .maybeSingle();
      if (row == null) {
        if (kDebugMode) {
          debugPrint('⚠️ auto-close sync: no student row for srNo $srNo');
        }
        return;
      }
      final sid = row['id'] as String;
      final name = row['name'] as String? ?? '';
      final studentSrNo = attendanceSrNoFromStudentRow(row);
      if (studentSrNo == null) return;

      final code = await instituteCodeForId(instituteId);

      final existing = await appDb
          .from('attendance_in_out')
          .select('additional,type')
          .eq('institute_code', code)
          .eq('student_id', sid)
          .eq('attendance_date', date)
          .eq('type', 'exit');

      for (final raw in existing) {
        final add = raw['additional'];
        if (add is! Map) continue;
        final am = Map<String, dynamic>.from(add.cast<String, dynamic>());
        if (am['autoClosedMissingExit'] == true &&
            (am['subject']?.toString() ?? '') == hint.subjectLabel) {
          return;
        }
      }

      // Calculate fixed credited hours based on subject count
      final fixedCreditedHours = attendanceFixedCreditHoursForSubjectCount(enrolledSubjectCount);
      final creditedPerSubject = enrolledSubjectCount <= 0
          ? fixedCreditedHours
          : fixedCreditedHours / enrolledSubjectCount;

      await HierarchicalAttendanceService().saveAttendance(
        instituteCode: instituteId,
        studentId: sid,
        studentName: name,
        srNo: studentSrNo,
        date: date,
        type: 'exit',
        photoUrl: '',
        recordedAtUtcIso: hint.syntheticExitUtc,
        additionalData: {
          'srNo': studentSrNo,
          'source': 'auto_close_missing_exit',
          'subject': hint.subjectLabel,
          'entryTime': hint.sessionEntryUtc,
          'exitTime': hint.syntheticExitUtc,
          'hours': creditedPerSubject,
          'status': 'present',
          'autoClosedMissingExit': true,
          'autoClosedNote': autoClosedMissingExitNote(fixedCreditedHours),
        },
      );

      // Calculate and save credited hours to database
      try {
        final recordRow = await appDb
            .from('attendance_in_out')
            .select('id')
            .eq('student_id', sid)
            .eq('attendance_date', date)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (recordRow != null) {
          final recordId = recordRow['id'] as String;
          final entryTime = parseAnyTimestamp(hint.sessionEntryUtc);
          final exitTime = parseAnyTimestamp(hint.syntheticExitUtc);

          if (entryTime != null && exitTime != null) {
            final calculation = AttendanceHoursCalculatorService.calculateCreditedHours(
              entryTime: entryTime,
              exitTime: exitTime,
              subjectCount: enrolledSubjectCount,
            );

            await AttendanceHoursPersistenceService.saveHoursToRecord(
              recordId: recordId,
              creditedHours: calculation['creditedHours'] as double,
              calculationNote: calculation['calculationNote'] as String,
            );
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ auto-close hours persistence failed: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ auto-close attendance_in_out sync failed: $e');
    }
  }

  /// Returns the payload to use (possibly updated after reconciliation).
  static Future<Map<String, dynamic>?> ensureReconciled({
    required SupabaseClient db,
    required String instituteId,
    required String srNo,
    required String date,
    required List<String> enrolledSubjects,
    Map<String, dynamic>? existingPayload,
  }) async {
    if (enrolledSubjects.isEmpty) return existingPayload;

    var payload = existingPayload ?? await _fetchPayload(db, instituteId, srNo, date);
    if (payload == null || payload.isEmpty) return existingPayload ?? payload;

    final applied = applyMissingExitAutoClose(
      payload: payload,
      enrolledSubjects: enrolledSubjects,
      nowUtc: DateTime.now().toUtc(),
    );

    if (!applied.changed) {
      return payload;
    }

    await _upsertTeacherPayload(db, instituteId, srNo, date, applied.payload);

    for (final h in applied.syncHints) {
      await _syncAutoClosedExit(
        instituteId: instituteId,
        srNo: srNo,
        date: date,
        hint: h,
        enrolledSubjectCount: enrolledSubjects.length,
      );
    }

    return applied.payload;
  }

  /// Midnight job: auto-close missing exits (1h credit) for all rows on [dateKey],
  /// and sync an `attendance_in_out` exit marker for reporting.
  static Future<void> ensureInstituteDateReconciled({
    required String instituteId,
    required String dateKey,
  }) async {
    final rows = await appDb
        .from('teacher_attendance')
        .select('student_id,payload')
        .eq('institute_id', instituteId)
        .eq('date', dateKey);

    for (final r in rows) {
      final srNo = (r['student_id'] as String?)?.trim() ?? '';
      if (srNo.isEmpty) continue;
      final raw = r['payload'];
      Map<String, dynamic>? payload;
      if (raw is Map<String, dynamic>) {
        payload = Map<String, dynamic>.from(raw);
      } else if (raw is Map) {
        payload = raw.map((k, v) => MapEntry(k.toString(), v));
      }
      if (payload == null || payload.isEmpty) continue;

      // Daily policy: reconcile legacy top-level entry/exit; subject sessions are ignored in new flow.
      final applied = applyMissingExitAutoClose(
        payload: payload,
        enrolledSubjects: const ['all'],
        nowUtc: DateTime.now().toUtc(),
      );
      if (!applied.changed) continue;

      await _upsertTeacherPayload(appDb, instituteId, srNo, dateKey, applied.payload);

      for (final h in applied.syncHints) {
        await _syncAutoClosedExit(
          instituteId: instituteId,
          srNo: srNo,
          date: dateKey,
          hint: h,
          enrolledSubjectCount: 1,
        );
      }
    }
  }
}
