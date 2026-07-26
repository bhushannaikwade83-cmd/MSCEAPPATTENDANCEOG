import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'app_db.dart';
import 'time_parse.dart';

/// Read credited hours directly from database instead of calculating
/// This is more efficient and consistent than recalculating every time
class AttendanceHoursDbReader {
  /// Get all credited hours for a date range grouped by student
  static Future<Map<String, double>> getStudentCreditedHours({
    required List<String> studentIds,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final records = await appDb
          .from('attendance_in_out')
          .select('student_id, credited_hours')
          .eq('type', 'exit') // Only count exit records to avoid double counting
          .inFilter('student_id', studentIds)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);

      final result = <String, double>{};

      for (final record in records) {
        final studentId = record['student_id'] as String;
        final hours = (record['credited_hours'] as num?)?.toDouble() ?? 0.0;

        result[studentId] = (result[studentId] ?? 0.0) + hours;
      }

      if (kDebugMode) {
        debugPrint('📖 Read ${records.length} records, ${result.length} students with hours from DB');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error reading student credited hours: $e');
      return {};
    }
  }

  /// Get daily credited hours breakdown
  static Future<Map<String, double>> getDailyCreditedHours({
    required List<String> studentIds,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final records = await appDb
          .from('attendance_in_out')
          .select('attendance_date, credited_hours')
          .eq('type', 'exit') // Only count exit records to avoid double counting
          .inFilter('student_id', studentIds)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);

      final result = <String, double>{};

      for (final record in records) {
        final date = record['attendance_date'] as String;
        final hours = (record['credited_hours'] as num?)?.toDouble() ?? 0.0;

        result[date] = (result[date] ?? 0.0) + hours;
      }

      if (kDebugMode) {
        debugPrint('📖 Read daily hours for ${result.length} dates from DB');
      }

      return result;
    } catch (e) {
      debugPrint('❌ Error reading daily credited hours: $e');
      return {};
    }
  }

  /// Get credited hours with calculation notes for transparency
  static Future<List<Map<String, dynamic>>> getCreditedHoursWithNotes({
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final records = await appDb
          .from('attendance_in_out')
          .select(
            'attendance_date, credited_hours, hours_calculation_note, hours_calculated_at, additional',
          )
          .eq('student_id', studentId)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr)
          .order('attendance_date');

      return records.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Error reading hours with notes: $e');
      return [];
    }
  }

  /// Calculate total credited hours for a student (from stored values)
  static Future<double> getTotalCreditedHours({
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final hours = await getStudentCreditedHours(
        studentIds: [studentId],
        startDate: startDate,
        endDate: endDate,
      );

      return hours[studentId] ?? 0.0;
    } catch (e) {
      debugPrint('❌ Error getting total credited hours: $e');
      return 0.0;
    }
  }

  /// Get all credited hours across all students for a date range
  static Future<double> getTotalInstituteCreditedHours({
    required List<String> studentIds,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final hours = await getStudentCreditedHours(
        studentIds: studentIds,
        startDate: startDate,
        endDate: endDate,
      );

      double total = 0.0;
      for (final h in hours.values) {
        total += h;
      }

      if (kDebugMode) {
        debugPrint('📖 Total institute hours: ${total.toStringAsFixed(2)}h');
      }

      return total;
    } catch (e) {
      debugPrint('❌ Error getting institute total: $e');
      return 0.0;
    }
  }

  /// Check if a record has credited hours calculated
  static Future<bool> hasHoursCalculated(String recordId) async {
    try {
      final result = await appDb
          .from('attendance_in_out')
          .select('credited_hours')
          .eq('id', recordId)
          .maybeSingle();

      return result != null && result['credited_hours'] != null;
    } catch (e) {
      debugPrint('❌ Error checking if hours calculated: $e');
      return false;
    }
  }

  /// Get records that don't have credited hours yet (for backfilling)
  static Future<List<Map<String, dynamic>>> getRecordsWithoutHours({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startStr = startDate.toIso8601String().split('T')[0];
      final endStr = endDate.toIso8601String().split('T')[0];

      final records = await appDb
          .from('attendance_in_out')
          .select()
          .filter('credited_hours', 'is', null)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);

      if (kDebugMode) {
        debugPrint('📖 Found ${records.length} records without hours');
      }

      return records.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('❌ Error getting records without hours: $e');
      return [];
    }
  }
}
