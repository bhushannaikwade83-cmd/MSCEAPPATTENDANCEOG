import 'package:smart_attendance_app/services/attendance_report_service.dart';
import 'package:smart_attendance_app/services/attendance_debug_service.dart';

/// Quick test to verify attendance calculation is working
///
/// Add this to your app's test file or run manually:
///
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await testAttendanceCalculation();
/// }

Future<void> testAttendanceCalculation() async {
  print('\n' + '='*60);
  print('ATTENDANCE CALCULATION TEST');
  print('='*60 + '\n');

  try {
    final instituteCode = 'INST_CODE'; // Replace with your institute code
    final startDate = DateTime(2024, 4, 1);
    final endDate = DateTime(2024, 4, 30);

    print('📊 Testing Attendance Calculation\n');
    print('Institute: $instituteCode');
    print('Period: ${startDate.toString().split(' ')[0]} to ${endDate.toString().split(' ')[0]}\n');

    // Step 1: Run diagnostics to see what's in database
    print('STEP 1: Checking database type values...\n');
    await AttendanceDebugService.debugUniqueTypeValues(
      instituteCode: instituteCode,
      startDate: startDate,
      endDate: endDate,
    );

    print('\n' + '-'*60 + '\n');

    // Step 2: Calculate student stats (this is what the widget uses)
    print('STEP 2: Calculating student attendance stats...\n');
    final stats = await AttendanceReportService.calculateStudentStats(
      instituteCode: instituteCode,
      startDate: startDate,
      endDate: endDate,
    );

    if (stats.isEmpty) {
      print('⚠️  No attendance data found for this period');
      return;
    }

    print('Found ${stats.length} students\n');

    // Step 3: Show results
    print('RESULTS:\n');
    for (final stat in stats.take(5)) {
      // Show first 5 students
      print('Student: ${stat.studentName} (${stat.rollNumber})');
      print('  Total Days: ${stat.totalDays}');
      print('  Present: ${stat.presentDays}');
      print('  Absent: ${stat.absentDays}');
      print('  Percentage: ${stat.attendancePercentage.toStringAsFixed(1)}%');
      print('  Status: ${stat.getStatus()}');
      print('');
    }

    if (stats.length > 5) {
      print('... and ${stats.length - 5} more students\n');
    }

    // Step 4: Overall stats
    print('-'*60 + '\n');
    print('OVERALL STATISTICS:\n');
    final overall = AttendanceReportService.calculateOverallStats(studentStats: stats);
    print('Total Students: ${overall['totalStudents']}');
    print('Average Attendance: ${(overall['averageAttendance'] as double).toStringAsFixed(1)}%');
    print('Total Present Days: ${overall['totalPresentDays']}');
    print('Total Absent Days: ${overall['totalAbsentDays']}');

    print('\n' + '='*60);
    print('✅ TEST COMPLETE - Widget should display this data correctly');
    print('='*60 + '\n');
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
