import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/app_db.dart';
import 'b2b_storage_service.dart';

/// Deletes per-institute data in Postgres. **Keeps** `institutes` rows and admin `profiles`.
class DatabaseCleanupService {
  static Future<String?> _instituteCode(String instituteId) async {
    final row = await appDb
        .from('institutes')
        .select('institute_code')
        .eq('id', instituteId)
        .maybeSingle();
    return row?['institute_code'] as String?;
  }

  /// Delete students, attendance, leaves, etc. for every institute; reset counters.
  static Future<Map<String, dynamic>> deleteAllInstitutesData() async {
    try {
      if (kDebugMode) {
        debugPrint(
          '🗑️ Starting deletion of all institute-linked data (Supabase)...',
        );
      }

      int totalInstitutesProcessed = 0;
      int totalStudentsDeleted = 0;
      int totalAttendanceDeleted = 0;
      int totalErrors = 0;
      final List<String> errors = [];

      final institutes = await appDb.from('institutes').select('id');

      for (final row in institutes) {
        final instituteId = row['id'] as String?;
        if (instituteId == null || instituteId.isEmpty) continue;

        try {
          if (kDebugMode) debugPrint('🗑️ Cleaning institute: $instituteId');

          final code = await _instituteCode(instituteId);

          final studentRows = await appDb
              .from('students')
              .select('id')
              .eq('institute_id', instituteId);
          final studentIds = studentRows
              .map((student) => student['id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList();

          if (studentIds.isNotEmpty) {
            await appDb
                .from('student_registrations')
                .delete()
                .inFilter('student_id', studentIds);
          }
          await appDb
              .from('attendance_records')
              .delete()
              .eq('institute_id', instituteId);

          totalStudentsDeleted += studentRows.length;
          await appDb.from('students').delete().eq('institute_id', instituteId);

          await appDb
              .from('institute_subjects')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('institute_daily_status')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('student_leaves')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('gps_settings')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('institute_geofence')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('teacher_attendance')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('user_devices')
              .delete()
              .eq('institute_id', instituteId);

          await appDb
              .from('suspicious_activity')
              .delete()
              .eq('institute_id', instituteId);

          if (code != null && code.isNotEmpty) {
            final attRows = await appDb
                .from('attendance_in_out')
                .select('id')
                .eq('institute_code', code);
            totalAttendanceDeleted += attRows.length;
            await appDb
                .from('attendance_in_out')
                .delete()
                .eq('institute_code', code);
          }

          await appDb.from('cached_photo_urls').delete().not('id', 'is', null);
          await B2BStorageService.clearAllB2Storage(instituteId: instituteId);

          await appDb
              .from('institutes')
              .update({
                'student_count': 0,
                'user_count': 0,
                'last_user_added': null,
                'sr_no_migration_completed': false,
                'sr_no_migration_date': null,
                'sr_no_migration_count': 0,
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', instituteId);

          totalInstitutesProcessed++;
        } catch (e) {
          totalErrors++;
          final msg = 'Error processing institute $instituteId: $e';
          errors.add(msg);
          if (kDebugMode) debugPrint('   ❌ $msg');
        }
      }

      if (kDebugMode) {
        debugPrint('✅ Deletion complete!');
        debugPrint('   Institutes processed: $totalInstitutesProcessed');
        debugPrint('   Students deleted: $totalStudentsDeleted');
        debugPrint('   Attendance rows deleted: $totalAttendanceDeleted');
        debugPrint('   Errors: $totalErrors');
      }

      return {
        'success': true,
        'message': 'Institute-linked data deleted. Institute rows kept.',
        'totalInstitutesProcessed': totalInstitutesProcessed,
        'totalStudentsDeleted': totalStudentsDeleted,
        'totalAttendanceDeleted': totalAttendanceDeleted,
        'totalUsersDeleted': 0,
        'totalErrors': totalErrors,
        'errors': errors,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error during deletion: $e');
      return {
        'success': false,
        'message': 'Deletion failed: ${e.toString()}',
        'totalInstitutesDeleted': 0,
        'totalStudentsDeleted': 0,
        'totalAttendanceDeleted': 0,
        'totalUsersDeleted': 0,
        'totalErrors': 0,
        'errors': [e.toString()],
      };
    }
  }
}
