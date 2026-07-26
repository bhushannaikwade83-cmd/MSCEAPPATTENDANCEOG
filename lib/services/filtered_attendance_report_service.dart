import 'package:intl/intl.dart';
import '../models/date_range_filter.dart';
import '../core/app_db.dart';
import 'attendance_report_service.dart';

/// Service for filtering attendance reports by date range
class FilteredAttendanceReportService {
  /// Calculate filtered student statistics based on date range
  static Future<List<StudentAttendanceStats>> getFilteredStudentStats({
    required String instituteCode,
    required DateRangeFilter dateRange,
    String? subjectFilter,
  }) async {
    try {
      // Get all stats for the date range
      final allStats = await AttendanceReportService.calculateStudentStats(
        instituteCode: instituteCode,
        startDate: dateRange.startDate,
        endDate: dateRange.endDate,
        subjectFilter: subjectFilter,
      );

      return allStats;
    } catch (e) {
      print('Error filtering student stats: $e');
      return [];
    }
  }

  /// Get filtered daily attendance details for a specific student
  static Future<List<DailyAttendanceDetail>> getFilteredStudentDetails({
    required String studentId,
    required String instituteCode,
    required DateRangeFilter dateRange,
  }) async {
    try {
      final db = AppDB();
      final startDateStr = DateFormat('yyyy-MM-dd').format(dateRange.startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(dateRange.endDate);

      // Fetch attendance records within date range
      final records = await db.rawQuery(
        '''
        SELECT * FROM INOUT_ATTENDANCE
        WHERE STUDENT_ID = ?
          AND INSTITUTE_CODE = ?
          AND DATE(ATTENDANCE_DATE) >= ?
          AND DATE(ATTENDANCE_DATE) <= ?
        ORDER BY ATTENDANCE_DATE DESC
        ''',
        [studentId, instituteCode, startDateStr, endDateStr],
      );

      // Convert to DailyAttendanceDetail objects
      List<DailyAttendanceDetail> details = [];
      for (var record in records) {
        // Build detail from record
        // This would use existing logic from AttendanceReportService
        details.add(_buildDetailFromRecord(record));
      }

      return details;
    } catch (e) {
      print('Error filtering student details: $e');
      return [];
    }
  }

  /// Get institute attendance summary for date range
  static Future<Map<String, dynamic>> getInstituteSummary({
    required String instituteCode,
    required DateRangeFilter dateRange,
  }) async {
    try {
      final db = AppDB();
      final startDateStr = DateFormat('yyyy-MM-dd').format(dateRange.startDate);

      // Cap end date at yesterday (only show complete days, not today's incomplete data)
      var endDate = dateRange.endDate;
      final today = DateTime.now();
      final yesterday = today.subtract(const Duration(days: 1));
      if (endDate.isAfter(yesterday)) {
        endDate = yesterday;
      }
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      // Get all students from students table (including those with no entry/exit records)
      final students = await db.rawQuery(
        '''
        SELECT DISTINCT s.STUDENT_ID, s.STUDENT_NAME, s.ROLL_NUMBER
        FROM STUDENTS s
        WHERE s.INSTITUTE_CODE = ?
        ORDER BY s.ROLL_NUMBER ASC
        ''',
        [instituteCode],
      );

      // Calculate summary stats using capped date range
      int totalDaysInRange = 0;
      var current = DateTime(dateRange.startDate.year, dateRange.startDate.month, dateRange.startDate.day);
      var endDateOnly = DateTime(endDate.year, endDate.month, endDate.day);
      while (current.isBefore(endDateOnly) || current.isAtSameMomentAs(endDateOnly)) {
        totalDaysInRange++;
        current = current.add(const Duration(days: 1));
      }
      int totalStudents = students.length;
      int totalPresent = 0;
      int totalAbsent = 0;
      double totalHours = 0;

      List<Map<String, dynamic>> studentData = [];

      for (var student in students) {
        final studentId = student['STUDENT_ID'];
        final studentName = student['STUDENT_NAME'];
        final rollNumber = student['ROLL_NUMBER'];

        // Get attendance records for this student in date range
        final attendanceRecords = await db.rawQuery(
          '''
          SELECT * FROM INOUT_ATTENDANCE
          WHERE STUDENT_ID = ?
            AND INSTITUTE_CODE = ?
            AND DATE(ATTENDANCE_DATE) >= ?
            AND DATE(ATTENDANCE_DATE) <= ?
          ''',
          [studentId, instituteCode, startDateStr, endDateStr],
        );

        // Count unique days with attendance
        final uniqueDays = <String>{};
        int subjectCount = 0;
        double studentTotalHours = 0;

        for (var record in attendanceRecords) {
          final date = record['ATTENDANCE_DATE'] ?? '';
          uniqueDays.add(date.toString().split(' ')[0]);

          // Accumulate hours
          final hoursPerSubject = (record['HOURS_CREDITED'] ?? 0.0) as double;
          studentTotalHours += hoursPerSubject;
          subjectCount = record['SUBJECTS_COUNT'] ?? 1;
        }

        int presentDays = uniqueDays.length;
        int absentDays = totalDaysInRange - presentDays;
        double attendancePercentage = totalDaysInRange > 0
            ? (presentDays / totalDaysInRange) * 100
            : 0;

        totalPresent += presentDays;
        totalAbsent += absentDays;
        totalHours += studentTotalHours;

        studentData.add({
          'studentId': studentId,
          'studentName': studentName,
          'rollNumber': rollNumber,
          'subjectCount': subjectCount,
          'presentDays': presentDays,
          'absentDays': absentDays,
          'totalHours': studentTotalHours,
          'attendancePercentage': attendancePercentage,
        });
      }

      // Calculate averages
      double avgPresent = totalStudents > 0 ? totalPresent / totalStudents : 0;
      double avgAbsent = totalStudents > 0 ? totalAbsent / totalStudents : 0;
      double avgHours = totalStudents > 0 ? totalHours / totalStudents : 0;
      double avgPercentage = totalStudents > 0
          ? (totalPresent / (totalStudents * totalDaysInRange)) * 100
          : 0;

      return {
        'dateRange': dateRange.formatRange(),
        'totalStudents': totalStudents,
        'totalDaysInRange': totalDaysInRange,
        'totalPresent': totalPresent,
        'totalAbsent': totalAbsent,
        'totalHours': totalHours,
        'averagePresent': avgPresent,
        'averageAbsent': avgAbsent,
        'averageHours': avgHours,
        'averagePercentage': avgPercentage,
        'studentData': studentData,
      };
    } catch (e) {
      print('Error calculating institute summary: $e');
      return {};
    }
  }

  /// Helper to build DailyAttendanceDetail from database record
  static DailyAttendanceDetail _buildDetailFromRecord(
      Map<String, dynamic> record) {
    // Extract data from record
    final date = record['ATTENDANCE_DATE'] ?? '';
    final subject = record['SUBJECT_NAME'] ?? '';
    final entryTime = record['ENTRY_TIME'];
    final exitTime = record['EXIT_TIME'];
    final creditedHours = (record['HOURS_CREDITED'] ?? 0.0) as double;
    final totalHours = (record['TOTAL_HOURS_DAY'] ?? creditedHours) as double;
    final status = record['STATUS'] ?? 'Absent';
    final remark = record['REMARKS'] ?? '';

    // Determine if within window
    bool isWithinWindow = record['IS_WITHIN_WINDOW'] == 1 ? true : false;

    return DailyAttendanceDetail(
      date: date.toString(),
      subject: subject,
      entryTime: entryTime?.toString(),
      exitTime: exitTime?.toString(),
      creditedHours: creditedHours,
      totalHours: totalHours,
      creditedHMS: _formatHours(creditedHours),
      status: status,
      remark: remark,
      isWithinWindow: isWithinWindow,
    );
  }

  /// Helper to format hours to "Xh Ym Zs" format
  static String _formatHours(double hours) {
    final h = hours.toInt();
    final remainingMinutes = ((hours - h) * 60).toInt();
    final s = ((((hours - h) * 60) - remainingMinutes) * 60).toInt();

    return "${h}h ${remainingMinutes}m ${s}s";
  }
}
