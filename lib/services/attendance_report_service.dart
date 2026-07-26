import 'package:intl/intl.dart';
import '../core/app_db.dart';
import '../core/attendance_presence_rules.dart';
import '../core/time_parse.dart';

/// Model for student attendance statistics
class StudentAttendanceStats {
  final String rollNumber;
  final String studentName;
  final int totalDays;
  final int presentDays;
  final int absentDays;
  final double attendancePercentage;

  StudentAttendanceStats({
    required this.rollNumber,
    required this.studentName,
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.attendancePercentage,
  });

  /// Get status badge based on attendance percentage
  String getStatus() {
    if (attendancePercentage >= 75) return 'Good';
    if (attendancePercentage >= 50) return 'Average';
    return 'Poor';
  }

  /// Get status color
  String getStatusColor() {
    if (attendancePercentage >= 75) return 'green';
    if (attendancePercentage >= 50) return 'orange';
    return 'red';
  }
}

/// Model for daily attendance summary
class DailyAttendanceSummary {
  final String date;
  final int totalStudents;
  final int presentCount;
  final int absentCount;
  final double attendancePercentage;

  DailyAttendanceSummary({
    required this.date,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
    required this.attendancePercentage,
  });
}

/// Model for daily attendance details (per student per day)
class DailyAttendanceDetail {
  final String date;
  final String subject;
  final String? entryTime;           // Real timestamp (e.g., 09:05 AM)
  final String? exitTime;            // Real timestamp (e.g., 10:30 AM)
  final double creditedHours;        // Credited hours per subject (based on rules)
  final double totalHours;           // Total credited for the day (sum of all subjects)
  final double? hoursRaw;            // Original seated hours (if within window)
  final String? hoursRawHMS;         // Formatted original seated hours (e.g., "1h 21m 38s")
  final String creditedHMS;          // Formatted credited hours: "1h 30m 0s"
  final String status;               // "Present", "Absent", "Holiday"
  final String remark;               // e.g., "Exit within policy window" or "No exit marked"
  final bool isWithinWindow;         // TRUE = show hoursRaw, FALSE = show credited

  DailyAttendanceDetail({
    required this.date,
    required this.subject,
    this.entryTime,
    this.exitTime,
    required this.creditedHours,
    required this.totalHours,
    this.hoursRaw,
    this.hoursRawHMS,
    required this.creditedHMS,
    required this.status,
    required this.remark,
    required this.isWithinWindow,
  });
}

/// Service for calculating attendance statistics
class AttendanceReportService {
  /// Calculate attendance statistics for all students in date range
  static Future<List<StudentAttendanceStats>> calculateStudentStats({
    required String instituteCode,
    required DateTime startDate,
    required DateTime endDate,
    String? subjectFilter,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      print('\n📊 DEBUG: Fetching attendance records...');
      print('Institute: $instituteCode, From: $startDateStr, To: $endDateStr');

      // Fetch attendance records from database
      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      print('Total records fetched: ${rows.length}');

      if (rows.isEmpty) {
        print('⚠️  No records found');
        return [];
      }

      // Structure: student → date → rows for that day
      final Map<String, Map<String, List<Map<String, dynamic>>>> studentDatesRows = {};
      final Map<String, String> studentNames = {};

      // Parse all records
      for (final row in rows) {
        final data = row as Map<String, dynamic>;

        // Get student identifier
        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final studentId = sid.isNotEmpty ? sid : sr;

        if (studentId.isEmpty) continue;

        final date = data['attendance_date']?.toString() ?? '';
        if (date.isEmpty) continue;

        // Store student name
        if (!studentNames.containsKey(studentId)) {
          studentNames[studentId] = data['student_name']?.toString() ?? 'Unknown';
        }

        // Get type value and normalize it
        final rawType = data['type'];
        String typeStr = rawType?.toString().toLowerCase().trim() ?? '';

        // DEBUG: Log actual values
        print('🔍 DEBUG RAW: student=$studentId, date=$date, rawType="$rawType", typeStr="$typeStr"');

        studentDatesRows.putIfAbsent(studentId, () => {});
        studentDatesRows[studentId]!.putIfAbsent(date, () => []).add(Map<String, dynamic>.from(data));

        // DEBUG types list no longer stored per cell (presence uses full rows).
      }

      print('Parsed ${studentDatesRows.length} unique students');

      // Calculate stats for each student
      final List<StudentAttendanceStats> stats = [];

      for (final studentId in studentDatesRows.keys) {
        final dateMap = studentDatesRows[studentId]!;
        final totalDays = dateMap.length;

        int presentCount = 0;

        for (final date in dateMap.keys) {
          final dayRows = dateMap[date]!;
          final isPresent = studentDayPresentFromInOutRows(dayRows);
          if (isPresent) {
            presentCount++;
          }
          print('📅 $studentId - $date: rows=${dayRows.length}, PRESENT=$isPresent');
        }

        final absentCount = totalDays - presentCount;
        final percentage = totalDays > 0 ? (presentCount / totalDays) * 100 : 0.0;

        print('Student: $studentId | Days: $totalDays | Present: $presentCount | Absent: $absentCount | %: ${percentage.toStringAsFixed(1)}%');

        stats.add(StudentAttendanceStats(
          rollNumber: studentId,
          studentName: studentNames[studentId] ?? 'Unknown',
          totalDays: totalDays,
          presentDays: presentCount,
          absentDays: absentCount,
          attendancePercentage: percentage,
        ));
      }

      // Sort by roll number
      stats.sort((a, b) => a.rollNumber.compareTo(b.rollNumber));

      print('\n✅ Calculation complete: ${stats.length} students\n');
      return stats;
    } catch (e) {
      print('❌ Error calculating student stats: $e');
      return [];
    }
  }

  /// Calculate daily attendance summary for date range
  static Future<List<DailyAttendanceSummary>> calculateDailyStats({
    required String instituteCode,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      // Fetch attendance records
      List<dynamic> rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr);

      if (rows.isEmpty) {
        return [];
      }

      // Structure: date → student → rows that day
      final Map<String, Map<String, List<Map<String, dynamic>>>> dateStudentRows = {};

      for (final row in rows) {
        final data = row as Map<String, dynamic>;

        final date = data['attendance_date']?.toString() ?? '';
        if (date.isEmpty) continue;

        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final studentId = sid.isNotEmpty ? sid : sr;
        if (studentId.isEmpty) continue;

        dateStudentRows.putIfAbsent(date, () => {});
        dateStudentRows[date]!.putIfAbsent(studentId, () => []).add(Map<String, dynamic>.from(data));
      }

      // Create daily summaries
      final List<DailyAttendanceSummary> summaries = [];

      for (final date in dateStudentRows.keys) {
        final students = dateStudentRows[date]!;
        final totalStudents = students.length;

        int presentCount = 0;

        for (final studentId in students.keys) {
          final dayRows = students[studentId]!;
          if (studentDayPresentFromInOutRows(dayRows)) {
            presentCount++;
          }
        }

        final absentCount = totalStudents - presentCount;
        final percentage = totalStudents > 0 ? (presentCount / totalStudents) * 100 : 0.0;

        summaries.add(DailyAttendanceSummary(
          date: date,
          totalStudents: totalStudents,
          presentCount: presentCount,
          absentCount: absentCount,
          attendancePercentage: percentage,
        ));
      }

      // Sort by date (descending - newest first)
      summaries.sort((a, b) => b.date.compareTo(a.date));
      return summaries;
    } catch (e) {
      print('Error calculating daily stats: $e');
      return [];
    }
  }

  /// Get overall statistics for the period
  static Map<String, dynamic> calculateOverallStats({
    required List<StudentAttendanceStats> studentStats,
  }) {
    if (studentStats.isEmpty) {
      return {
        'totalStudents': 0,
        'totalPresentDays': 0,
        'totalAbsentDays': 0,
        'averageAttendance': 0.0,
        'highestAttendance': 0.0,
        'lowestAttendance': 0.0,
      };
    }

    int totalPresentDays = 0;
    int totalAbsentDays = 0;
    double totalAttendance = 0.0;
    double highest = 0.0;
    double lowest = 100.0;

    for (final stat in studentStats) {
      totalPresentDays += stat.presentDays;
      totalAbsentDays += stat.absentDays;
      totalAttendance += stat.attendancePercentage;
      highest = stat.attendancePercentage > highest ? stat.attendancePercentage : highest;
      lowest = stat.attendancePercentage < lowest ? stat.attendancePercentage : lowest;
    }

    return {
      'totalStudents': studentStats.length,
      'totalPresentDays': totalPresentDays,
      'totalAbsentDays': totalAbsentDays,
      'averageAttendance': totalAttendance / studentStats.length,
      'highestAttendance': highest,
      'lowestAttendance': lowest,
    };
  }

  /// Export stats to CSV format
  static String exportToCSV({
    required List<StudentAttendanceStats> stats,
    required String startDate,
    required String endDate,
  }) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('Attendance Report');
    buffer.writeln('Period: $startDate to $endDate');
    buffer.writeln('');
    buffer.writeln('Roll Number,Student Name,Total Days,Present,Absent,Percentage,Status');

    // Data rows
    for (final stat in stats) {
      buffer.writeln(
        '${stat.rollNumber},${stat.studentName},${stat.totalDays},${stat.presentDays},${stat.absentDays},${stat.attendancePercentage.toStringAsFixed(2)}%,${stat.getStatus()}',
      );
    }

    return buffer.toString();
  }

  /// Filter students by status
  static List<StudentAttendanceStats> filterByStatus({
    required List<StudentAttendanceStats> stats,
    required String status,
  }) {
    if (status == 'all') return stats;

    return stats.where((stat) => stat.getStatus().toLowerCase() == status.toLowerCase()).toList();
  }

  /// Search students by name or roll number
  static List<StudentAttendanceStats> searchStudents({
    required List<StudentAttendanceStats> stats,
    required String query,
  }) {
    if (query.isEmpty) return stats;

    final lowerQuery = query.toLowerCase();
    return stats
        .where((stat) =>
            stat.rollNumber.toLowerCase().contains(lowerQuery) ||
            stat.studentName.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Get daily attendance details for a specific student
  /// Shows entry time, exit time, credited hours in H:M:S format
  static Future<List<DailyAttendanceDetail>> getDailyAttendanceDetails({
    required String instituteCode,
    required String studentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      // Fetch attendance records
      final rows = await appDb
          .from('attendance_in_out')
          .select()
          .eq('institute_code', instituteCode)
          .or('student_id.eq.$studentId,sr_no.eq.$studentId')
          .gte('attendance_date', startDateStr)
          .lte('attendance_date', endDateStr)
          .order('attendance_date', ascending: true);

      // Group by date
      final Map<String, List<Map<String, dynamic>>> dateRows = {};
      for (final row in rows) {
        final data = row as Map<String, dynamic>;
        final date = data['attendance_date']?.toString() ?? '';
        if (date.isNotEmpty) {
          dateRows.putIfAbsent(date, () => []).add(data);
        }
      }

      // Convert to DailyAttendanceDetail
      final details = <DailyAttendanceDetail>[];

      for (final date in dateRows.keys) {
        final dayRows = dateRows[date]!;

        // ✅ FIXED: Calculate daily total hours (sum of all subjects for this day)
        double dailyTotalHours = 0.0;
        double dailyRawHours = 0.0;
        for (final row in dayRows) {
          final add = row['additional'] as Map<String, dynamic>? ?? {};
          final hours = add['hours'] as num?;
          final hoursRaw = add['hoursRaw'] as num?;
          dailyTotalHours += hours?.toDouble() ?? 0.0;
          dailyRawHours += hoursRaw?.toDouble() ?? 0.0;
        }

        for (final row in dayRows) {
          final add = row['additional'] as Map<String, dynamic>? ?? {};
          final subject = add['subject']?.toString() ?? 'Unknown';
          final entryTime = add['entryTime']?.toString();
          final exitTime = add['exitTime']?.toString();
          final hours = add['hours'] as num?;
          final hoursRaw = add['hoursRaw'] as num?;
          final status = add['status']?.toString() ?? '';
          final remark = add['autoClosedNote']?.toString() ??
              add['attendanceReason']?.toString() ??
              (status == 'present' ? 'Present' : 'Absent');

          // ✅ NEW: Determine if within window (if hoursRaw exists, it means entry/exit were within the policy window)
          final isWithinWindow = hoursRaw != null && hoursRaw > 0;

          // Format times
          String? formattedEntryTime;
          if (entryTime != null && entryTime.isNotEmpty) {
            try {
              final dt = parseAnyTimestamp(entryTime);
              if (dt != null) {
                formattedEntryTime = DateFormat('hh:mm a').format(dt.toLocal());
              }
            } catch (e) {
              formattedEntryTime = entryTime;
            }
          }

          String? formattedExitTime;
          if (exitTime != null && exitTime.isNotEmpty) {
            try {
              final dt = parseAnyTimestamp(exitTime);
              if (dt != null) {
                formattedExitTime = DateFormat('hh:mm a').format(dt.toLocal());
              }
            } catch (e) {
              formattedExitTime = exitTime;
            }
          }

          // ✅ CONFIRMED: IF within window → show original seated hours, ELSE → show credited hours
          final displayHours = isWithinWindow ? hoursRaw?.toDouble() ?? 0.0 : hours?.toDouble() ?? 0.0;
          final creditedHMS = formatCreditedHoursHMS(displayHours);
          final hoursRawHMS = isWithinWindow ? formatCreditedHoursHMS(hoursRaw?.toDouble() ?? 0.0) : null;

          details.add(DailyAttendanceDetail(
            date: date,
            subject: subject,
            entryTime: formattedEntryTime,
            exitTime: formattedExitTime,
            creditedHours: hours?.toDouble() ?? 0.0,
            totalHours: isWithinWindow ? dailyRawHours : dailyTotalHours,
            hoursRaw: isWithinWindow ? hoursRaw?.toDouble() : null,
            hoursRawHMS: hoursRawHMS,
            creditedHMS: creditedHMS,
            status: status.isEmpty ? 'Pending' : status,
            remark: remark,
            isWithinWindow: isWithinWindow,
          ));
        }
      }

      return details;
    } catch (e) {
      print('❌ Error fetching daily attendance details: $e');
      return [];
    }
  }
}
