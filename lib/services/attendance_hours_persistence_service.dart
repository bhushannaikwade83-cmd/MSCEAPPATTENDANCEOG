import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_db.dart';
import '../core/supabase_maps.dart';
import 'attendance_hours_calculator_service.dart';

/// Service to persist credited hours to database
/// Handles both saving new hours and backfilling existing records
class AttendanceHoursPersistenceService {
  static const _backfillCompleteKey = 'credited_hours_backfill_v1_complete';
  static const _backfillLastRunKey = 'credited_hours_backfill_v1_last_run_ms';

  /// One small batch after login — avoids Supabase statement timeout on large tables.
  static Future<void> maybeBackfillOnLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_backfillCompleteKey) == true) return;

      final lastRunMs = prefs.getInt(_backfillLastRunKey) ?? 0;
      final sinceLastRun = DateTime.now().millisecondsSinceEpoch - lastRunMs;
      if (sinceLastRun < const Duration(hours: 6).inMilliseconds) return;

      final uid = currentUserId;
      if (uid == null) return;

      final profile = await appDb
          .from('profiles')
          .select('institute_id')
          .eq('id', uid)
          .maybeSingle();
      final instituteId = (profile?['institute_id'] as String?)?.trim();
      if (instituteId == null || instituteId.isEmpty) return;

      if (kDebugMode) {
        debugPrint('🔄 Credited-hours backfill (one batch, institute $instituteId)...');
      }

      final result = await backfillCreditedHours(
        instituteId: instituteId,
        batchSize: 20,
        maxBatches: 1,
      );

      await prefs.setInt(
        _backfillLastRunKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (result['batchFetched'] == 0) {
        await prefs.setBool(_backfillCompleteKey, true);
        if (kDebugMode) debugPrint('✅ Credited-hours backfill: nothing left to do');
      } else if (kDebugMode) {
        debugPrint(
          '✅ Credited-hours backfill batch: '
          '${result['successCount']} saved, ${result['errorCount']} errors',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Credited-hours backfill skipped: $e');
    }
  }
  /// Save credited hours to a single attendance record
  /// Used when student marks exit or auto-close updates record
  static Future<void> saveHoursToRecord({
    required String recordId,
    required double creditedHours,
    required String calculationNote,
  }) async {
    try {
      await appDb
          .from('attendance_in_out')
          .update({
            'credited_hours': creditedHours,
            'hours_calculation_note': calculationNote,
            'hours_calculated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', recordId);

      if (kDebugMode) {
        debugPrint('✅ Saved hours to record $recordId: ${creditedHours}h');
      }
    } catch (e) {
      debugPrint('❌ Error saving hours to record $recordId: $e');
      rethrow;
    }
  }

  /// Backfill credited hours for existing exit attendance records (batched).
  /// Prefer [maybeBackfillOnLogin] on the app; call this manually for larger runs.
  static Future<Map<String, int>> backfillCreditedHours({
    String? instituteId,
    int batchSize = 20,
    int maxBatches = 1,
  }) async {
    if (batchSize < 1) batchSize = 1;
    if (maxBatches < 1) maxBatches = 1;

    var successCount = 0;
    var errorCount = 0;
    var batchFetched = 0;

    try {
      if (kDebugMode) {
        debugPrint(
          '🔄 Backfill credited hours (batchSize=$batchSize, maxBatches=$maxBatches)',
        );
      }

      final instituteKeys = await _attendanceInstituteKeys(instituteId);

      for (var batch = 0; batch < maxBatches; batch++) {
        var query = appDb
            .from('attendance_in_out')
            .select('''
              id,
              student_id,
              attendance_date,
              additional,
              credited_hours
            ''')
            .eq('type', 'exit')
            .filter('credited_hours', 'is', null);

        if (instituteKeys.isNotEmpty) {
          query = query.inFilter('institute_code', instituteKeys);
        }

        final records = await query
            .order('attendance_date', ascending: true)
            .limit(batchSize);
        if (records.isEmpty) break;

        batchFetched += records.length;

        for (final record in records) {
          try {
            final recordId = record['id'] as String;
            final additional = record['additional'];

            DateTime? entryTime;
            DateTime? exitTime;

            if (additional is Map<String, dynamic>) {
              final entryStr = additional['entryTime'] as String?;
              final exitStr = additional['exitTime'] as String?;

              if (entryStr != null) {
                entryTime =
                    DateTime.tryParse(entryStr) ?? DateTime.parse(entryStr);
              }
              if (exitStr != null) {
                exitTime =
                    DateTime.tryParse(exitStr) ?? DateTime.parse(exitStr);
              }
            }

            if (entryTime == null) continue;

            exitTime ??=
                DateTime.parse('${record['attendance_date']}T23:59:59Z');

            final calculation =
                AttendanceHoursCalculatorService.calculateCreditedHours(
              entryTime: entryTime,
              exitTime: exitTime,
              subjectCount: 1,
            );

            await saveHoursToRecord(
              recordId: recordId,
              creditedHours: calculation['creditedHours'] as double,
              calculationNote: calculation['calculationNote'] as String,
            );

            successCount++;
          } catch (e) {
            errorCount++;
            debugPrint('❌ Error processing record: $e');
          }
        }

        if (records.length < batchSize) break;
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Backfill batch done: $successCount saved, $errorCount errors '
          '($batchFetched fetched)',
        );
      }

      return {
        'successCount': successCount,
        'errorCount': errorCount,
        'batchFetched': batchFetched,
      };
    } catch (e) {
      debugPrint('❌ Backfill failed: $e');
      rethrow;
    }
  }

  static Future<List<String>> _attendanceInstituteKeys(String? instituteId) async {
    final trimmed = instituteId?.trim() ?? '';
    if (trimmed.isEmpty) return const [];

    final keys = <String>{trimmed};
    try {
      final canonical = await resolveCanonicalInstituteId(trimmed);
      if (canonical != null && canonical.isNotEmpty) keys.add(canonical);
      final code = await instituteCodeForId(trimmed);
      if (code.isNotEmpty) keys.add(code);
    } catch (e) {
      if (kDebugMode) debugPrint('_attendanceInstituteKeys: $e');
    }
    keys.removeWhere((s) => s.isEmpty);
    return keys.toList();
  }

  /// Get total credited hours for a student in a date range
  /// This replaces the old calculation approach
  static Future<double> getTotalCreditedHoursForStudent({
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final records = await appDb
          .from('attendance_in_out')
          .select('credited_hours')
          .eq('student_id', studentId)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);

      double total = 0.0;
      for (final record in records) {
        final hours = (record['credited_hours'] as num?)?.toDouble() ?? 0.0;
        total += hours;
      }

      return total;
    } catch (e) {
      debugPrint('❌ Error getting credited hours for student: $e');
      return 0.0;
    }
  }

  /// Get daily total credited hours
  static Future<double> getDailyCreditedHours({
    required String date,
    String? instituteId,
  }) async {
    try {
      var query = appDb
          .from('attendance_in_out')
          .select('credited_hours')
          .eq('attendance_date', date);

      if (instituteId != null) {
        query = query.filter('students.institute_id', 'eq', instituteId);
      }

      final records = await query;

      double total = 0.0;
      for (final record in records) {
        final hours = (record['credited_hours'] as num?)?.toDouble() ?? 0.0;
        total += hours;
      }

      return total;
    } catch (e) {
      debugPrint('❌ Error getting daily credited hours: $e');
      return 0.0;
    }
  }

  /// Validate that all records have credited hours calculated
  /// Use to verify backfill was successful
  static Future<Map<String, dynamic>> validateCreditedHours({
    String? instituteId,
  }) async {
    try {
      // Get all records
      final allRecords = await appDb
          .from('attendance_in_out')
          .select('id, credited_hours');

      // Get records with null credited_hours
      final nullRecords = await appDb
          .from('attendance_in_out')
          .select('id')
          .filter('credited_hours', 'is', null);

      final totalCount = allRecords.length;
      final nullCount = nullRecords.length;
      final withHours = totalCount - nullCount;

      return {
        'total': totalCount,
        'withoutHours': nullCount,
        'withHours': withHours,
        'coverage': totalCount > 0 ? (withHours / totalCount) * 100 : 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error validating credited hours: $e');
      return {
        'error': e.toString(),
      };
    }
  }
}
