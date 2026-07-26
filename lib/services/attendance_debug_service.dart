import 'package:intl/intl.dart';
import '../core/app_db.dart';
import '../core/attendance_presence_rules.dart';

/// Debug service to check actual database records and verify calculations
class AttendanceDebugService {
  /// Get raw attendance records for a specific student in a date range
  static Future<void> debugStudentAttendance({
    required String instituteCode,
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      print('=== DEBUG: Student Attendance ===');
      print('Institute Code: $instituteCode');
      print('Student ID: $studentId');
      print('Date Range: $startDateStr to $endDateStr');
      print('');

      // Fetch raw records
      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .eq('student_id', studentId)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr)
          .order('attendance_date');

      print('Total Raw Records: ${rows.length}');
      print('');

      if (rows.isEmpty) {
        print('⚠️  No records found in database!');
        return;
      }

      // Print each record
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i] as Map<String, dynamic>;
        print('Record $i:');
        print('  Date: ${row['attendance_date']}');
        print('  Type: ${row['type']}');
        print('  Status: ${row['additional'] is Map ? row['additional']['status'] : 'N/A'}');
        print('  Created: ${row['created_at']}');
        print('');
      }

      // Group by date and analyze
      print('=== Analysis by Date ===');
      final Map<String, List<Map<String, dynamic>>> byDateRows = {};
      for (final row in rows) {
        final m = Map<String, dynamic>.from(row as Map);
        final date = m['attendance_date']?.toString() ?? '';
        if (date.isEmpty) continue;
        byDateRows.putIfAbsent(date, () => []).add(m);
      }

      int presentCount = 0;
      int absentCount = 0;

      for (final date in byDateRows.keys.toList()..sort()) {
        final dayRows = byDateRows[date]!;
        final types = dayRows.map((r) => (r['type']?.toString() ?? '').toLowerCase()).toList();
        final hasEntry = types.contains('entry');
        final hasExit = types.contains('exit');
        final isPresent = studentDayPresentFromInOutRows(dayRows);

        print('$date:');
        print('  Entry: $hasEntry, Exit: $hasExit');
        print('  Status: ${isPresent ? '✓ PRESENT' : '✗ ABSENT'}');

        if (isPresent) {
          presentCount++;
        } else {
          absentCount++;
        }
      }

      print('');
      print('=== SUMMARY ===');
      print('Total Days: ${byDateRows.length}');
      print('Present: $presentCount');
      print('Absent: $absentCount');
      print('Percentage: ${byDateRows.isEmpty ? '0.0' : (presentCount / byDateRows.length * 100).toStringAsFixed(1)}%');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  /// Alternative calculation: Direct query without grouping logic
  static Future<Map<String, int>> simpleCalculation({
    required String instituteCode,
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .eq('student_id', studentId)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      if (rows.isEmpty) {
        return {'total': 0, 'present': 0, 'absent': 0};
      }

      // Method 1: Count unique dates
      final Set<String> allDates = {};
      for (final row in rows) {
        final date = (row as Map<String, dynamic>)['attendance_date']?.toString() ?? '';
        if (date.isNotEmpty) allDates.add(date);
      }

      return {
        'total': allDates.length,
        'present': 0,  // Will calculate below
        'absent': 0,
      };
    } catch (e) {
      print('Error in simple calculation: $e');
      return {'total': 0, 'present': 0, 'absent': 0};
    }
  }

  /// Check if database has both entry and exit for each date
  static Future<Map<String, dynamic>> analyzeEntryExit({
    required String instituteCode,
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .eq('student_id', studentId)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      final Map<String, Map<String, bool>> analysis = {};

      for (final row in rows) {
        final data = row as Map<String, dynamic>;
        final date = data['attendance_date']?.toString() ?? '';
        final type = data['type']?.toString().toLowerCase() ?? '';

        if (date.isNotEmpty) {
          analysis.putIfAbsent(date, () => {'entry': false, 'exit': false});
          if (type == 'entry') analysis[date]!['entry'] = true;
          if (type == 'exit') analysis[date]!['exit'] = true;
        }
      }

      return analysis;
    } catch (e) {
      print('Error in analysis: $e');
      return {};
    }
  }

  /// Diagnostic: Print all unique type values in database
  static Future<void> debugUniqueTypeValues({
    required String instituteCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      print('=== DEBUG: Unique Type Values ===');
      print('Institute Code: $instituteCode');
      print('Date Range: $startDateStr to $endDateStr');
      print('');

      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      final Set<String> uniqueTypes = {};
      final Set<dynamic> rawTypeValues = {};

      for (final row in rows) {
        final data = row as Map<String, dynamic>;
        final rawType = data['type'];
        final typeStr = rawType?.toString() ?? 'NULL';

        rawTypeValues.add(rawType);
        uniqueTypes.add('Raw: $rawType (Type: ${rawType.runtimeType}) -> String: "$typeStr" -> Lowercase: "${typeStr.toLowerCase()}"');
      }

      print('Found ${uniqueTypes.length} unique type value(s):');
      for (final typeInfo in uniqueTypes) {
        print('  $typeInfo');
      }

      print('\n=== MATCHING LOGIC TEST ===');
      print('Testing type matching:');
      for (final rawVal in rawTypeValues) {
        final typeStr = rawVal?.toString() ?? '';
        final lowercase = typeStr.toLowerCase();
        final matchesEntry = lowercase == 'entry';
        final matchesExit = lowercase == 'exit';
        print('  "$rawVal" -> lowercase: "$lowercase" -> entry: $matchesEntry, exit: $matchesExit');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  /// Diagnostic: Check actual status values in additional field
  static Future<void> debugStatusValues({
    required String instituteCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      print('=== DEBUG: Status Values in Additional Field ===');
      print('Institute Code: $instituteCode');
      print('Date Range: $startDateStr to $endDateStr');
      print('');

      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr)
          .limit(20); // Limit to first 20 for debugging

      final Set<String> statusValues = {};

      for (int i = 0; i < rows.length; i++) {
        final data = rows[i] as Map<String, dynamic>;
        final additional = data['additional'];
        final status = additional is Map ? additional['status'] : null;

        statusValues.add('Status: $status (Type: ${status.runtimeType})');

        print('Record $i:');
        print('  additional field: $additional');
        print('  additional.runtimeType: ${additional.runtimeType}');
        if (additional is Map) {
          print('  status value: ${additional['status']}');
          print('  status type: ${additional['status'].runtimeType}');
        }
        print('');
      }

      print('Unique status values found:');
      for (final status in statusValues) {
        print('  $status');
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }
}
