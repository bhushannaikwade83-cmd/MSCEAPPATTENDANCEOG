import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';
import '../core/attendance_presence_rules.dart';
import 'security_ops_service.dart';

/// Institute daily status in `institute_daily_status` (payload + date_key).
/// Rows with [kInstituteStatusStudentId] hold institute-wide open/close/holiday.
class InstituteStatusService {
  static const String kInstituteStatusStudentId = '__institute__';

  SupabaseClient get _db => appDb;
  final SecurityOpsService _securityOps = SecurityOpsService();

  Future<Map<String, dynamic>?> _rowPayload(String instituteId, String today) async {
    final row = await _db
        .from('institute_daily_status')
        .select()
        .eq('institute_id', instituteId)
        .eq('student_id', kInstituteStatusStudentId)
        .eq('date_key', today)
        .maybeSingle();
    if (row == null) return null;
    final payload = row['payload'];
    if (payload is Map<String, dynamic>) return Map<String, dynamic>.from(payload);
    if (payload is Map) return payload.map((k, v) => MapEntry(k.toString(), v));
    return null;
  }

  /// Get today's institute status (merged with top-level row fields).
  Future<Map<String, dynamic>?> getTodayStatus(String instituteId) async {
    // Status system removed: attendance is always available every day.
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return <String, dynamic>{
      'status': 'open',
      'date': today,
      'statusSystemDisabled': true,
    };
  }

  Future<void> _upsertStatus(String instituteId, String today, Map<String, dynamic> payload) async {
    await _db.from('institute_daily_status').upsert(
      {
        'institute_id': instituteId,
        'student_id': kInstituteStatusStudentId,
        'date_key': today,
        'payload': payload,
      },
      onConflict: 'institute_id,student_id,date_key',
    );
  }

  /// Mark institute as open for today
  Future<Map<String, dynamic>> markOpen(String instituteId) async {
    return {'success': true, 'message': 'Status system disabled (always open)'};
  }

  /// Mark institute as closed for today
  Future<Map<String, dynamic>> markClosed(String instituteId) async {
    return {'success': true, 'message': 'Status system disabled (always open)'};
  }

  /// Mark today as holiday
  Future<Map<String, dynamic>> markHoliday(String instituteId, {String? reason}) async {
    return {'success': true, 'message': 'Status system disabled (no holidays)'};
  }

  /// Auto-close institute if not manually closed
  Future<Map<String, dynamic>> autoClose(String instituteId) async {
    return {'success': true, 'message': 'Status system disabled (no auto-close)'};
  }

  Future<bool> isHoliday(String instituteId) async {
    return false;
  }

  Future<bool> isOpen(String instituteId) async {
    return true;
  }

  Future<String?> attendanceBlockMessage(String instituteId) async {
    return null;
  }

  /// Mark students **absent** only when they have **no entry on any subject** today.
  /// Entry without exit stays hours-based (handled elsewhere); not overwritten here.
  /// Called automatically when the institute is closed for the day.
  /// Returns { 'success', 'updated', 'inserted', 'total' }.
  Future<Map<String, dynamic>> markAbsentAllUnmarkedStudents(
    String instituteId, {
    String? dateKey,
  }) async {
    try {
      final today = dateKey ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now().toUtc().toIso8601String();

      // All students in the institute
      final students = await _db
          .from('students')
          .select('user_id, sr_no, created_at')
          .eq('institute_id', instituteId);

      // Today's existing attendance rows
      final attendanceRows = await _db
          .from('teacher_attendance')
          .select('id,student_id,status,payload,updated_at')
          .eq('institute_id', instituteId)
          .eq('date', today);

      // student_id → {row, payload}
      final attendanceMap = <String, Map<String, dynamic>>{};
      for (final row in attendanceRows) {
        final sid = row['student_id'] as String?;
        if (sid == null) continue;
        final data = row['payload'];
        final Map<String, dynamic> payload;
        if (data is Map<String, dynamic>) {
          payload = Map<String, dynamic>.from(data);
        } else if (data is Map) {
          payload = data.map((k, v) => MapEntry(k.toString(), v));
        } else {
          payload = {};
        }
        attendanceMap[sid] = {'row': row, 'payload': payload};
      }

      int updated = 0;
      int inserted = 0;

      for (final student in students) {
        final srNo =
            (student['user_id'] as String?)?.trim() ??
            (student['sr_no'] as String?)?.trim();
        if (srNo == null || srNo.isEmpty) continue;

        final existing = attendanceMap[srNo];

        if (existing != null) {
          final row = Map<String, dynamic>.from(existing['row'] as Map);
          final map = existing['payload'] as Map<String, dynamic>;
          final currentStatus = map['status'] as String?;

          // Already finalised → skip
          if (currentStatus == 'present' || currentStatus == 'absent') {
            continue;
          }

          if (!teacherPayloadHasAnySubjectEntry(map)) {
            map['status'] = 'absent';
            map['absentReason'] =
                'Auto-marked absent: no entry on any subject when institute closed';
            map['markedAbsentAt'] = now;
            map['autoMarkedOnInstituteClose'] = true;

            await _db.from('teacher_attendance').update({
              'payload': map,
              'status': 'absent',
              'updated_at': now,
            }).eq('id', row['id'] as String);
            updated++;
          }
        } else {
          // Do not auto-mark a newly added student absent on day 1.
          // If the student record was created today, skip absent insertion.
          final createdAtRaw = student['created_at']?.toString();
          final createdAt = createdAtRaw == null
              ? null
              : DateTime.tryParse(createdAtRaw)?.toLocal();
          if (createdAt != null) {
            final createdDate =
                DateFormat('yyyy-MM-dd').format(createdAt);
            if (createdDate == today) {
              continue;
            }
          }

          // No record at all for today → insert absent
          final docId = '${instituteId}_${srNo}_$today';
          await _db.from('teacher_attendance').upsert(
            {
              'id': docId,
              'institute_id': instituteId,
              'student_id': srNo,
              'date': today,
              'status': 'absent',
              'payload': {
                'status': 'absent',
                'absentReason':
                    'Auto-marked absent: no attendance recorded when institute closed',
                'markedAbsentAt': now,
                'autoMarkedOnInstituteClose': true,
                'isManual': false,
              },
              'updated_at': now,
            },
            onConflict: 'id',
          );
          inserted++;
        }
      }

      if (kDebugMode) {
        debugPrint(
            '✅ Auto-absent on close: updated=$updated, inserted=$inserted');
      }
      return {
        'success': true,
        'updated': updated,
        'inserted': inserted,
        'total': updated + inserted,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error marking absent on institute close: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Institute daily open/close windows from `institutes.lecture_open_time` /
  /// `lecture_close_time` (jsonb).
  Future<Map<String, dynamic>?> getInstituteTiming(String instituteId) async {
    try {
      final row = await _db
          .from('institutes')
          .select('lecture_open_time, lecture_close_time')
          .eq('id', instituteId)
          .maybeSingle();

      if (row == null) return null;

      final openTime = row['lecture_open_time'];
      final closeTime = row['lecture_close_time'];

      if (openTime == null || closeTime == null) {
        return null;
      }

      Map<String, dynamic> asMap(dynamic v) {
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return v.map((k, e) => MapEntry(k.toString(), e));
        return {};
      }

      final o = asMap(openTime);
      final c = asMap(closeTime);

      return {
        'openTime': {
          'hour': o['hour'] ?? 8,
          'minute': o['minute'] ?? 0,
        },
        'closeTime': {
          'hour': c['hour'] ?? 22,
          'minute': c['minute'] ?? 0,
        },
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting institute timing: $e');
      return null;
    }
  }

  /// Poll-based stream of today's status payload (replaces Firestore snapshots).
  Stream<Map<String, dynamic>?> getTodayStatusStream(String instituteId) {
    late StreamController<Map<String, dynamic>?> controller;
    Timer? timer;

    Future<void> emit() async {
      final m = await getTodayStatus(instituteId);
      if (!controller.isClosed) controller.add(m);
    }

    controller = StreamController<Map<String, dynamic>?>(
      onListen: () {
        emit();
        // getTodayStatus returns hardcoded data (status system disabled) —
        // polling every 30 s was pure DB waste. Reduced to 5 minutes.
        timer = Timer.periodic(const Duration(minutes: 5), (_) => emit());
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  /// Create a dual-approval request for sensitive override actions.
  /// Example actions:
  /// - `reopen_finalized_day`
  /// - `attendance_status_override`
  Future<Map<String, dynamic>> requestAdminOverride({
    required String instituteId,
    required String actionType,
    required String targetTable,
    required String targetId,
    required String reason,
  }) async {
    try {
      final result = await _db.rpc('request_admin_override', params: {
        'p_institute_id': instituteId,
        'p_action_type': actionType,
        'p_target_table': targetTable,
        'p_target_id': targetId,
        'p_reason': reason,
      });
      return {
        'success': true,
        'requestId': result?.toString(),
        'message': 'Override request submitted',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error creating admin override request: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Approve a dual-approval request (requires MFA AAL2 session on backend).
  Future<Map<String, dynamic>> approveAdminOverride({
    required String requestId,
    String? note,
  }) async {
    try {
      final result = await _db.rpc('approve_admin_override', params: {
        'p_request_id': requestId,
        'p_note': note,
      });
      if (result is Map<String, dynamic>) {
        await _securityOps.reportIncident(
          instituteId: (result['institute_id'] ?? '').toString(),
          category: 'admin_override_approved',
          severity: 'high',
          title: 'Sensitive admin override approved',
          description: 'Dual-approval override has been approved.',
          metadata: result,
        );
        return {'success': true, ...result};
      }
      if (result is Map) {
        final mapped = result.map((k, v) => MapEntry(k.toString(), v));
        await _securityOps.reportIncident(
          instituteId: (mapped['institute_id'] ?? '').toString(),
          category: 'admin_override_approved',
          severity: 'high',
          title: 'Sensitive admin override approved',
          description: 'Dual-approval override has been approved.',
          metadata: mapped,
        );
        return {
          'success': true,
          ...mapped,
        };
      }
      return {'success': true, 'message': 'Approval processed'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error approving admin override request: $e');
      }
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// List pending override requests for the institute (newest first).
  Future<List<Map<String, dynamic>>> getPendingOverrideRequests(
      String instituteId) async {
    try {
      final rows = await _db
          .from('admin_override_requests')
          .select()
          .eq('institute_id', instituteId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => (e as Map).map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error loading pending override requests: $e');
      }
      return [];
    }
  }
}
