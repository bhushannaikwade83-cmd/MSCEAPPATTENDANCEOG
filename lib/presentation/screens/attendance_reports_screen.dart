import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  final String? instituteId;

  const AttendanceReportsScreen({
    super.key,
    this.instituteId,
  });

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen> {
  String? _instituteId;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = true;

  @override
  void initState() {
    super.initState();
    _instituteId = widget.instituteId;
    print('📚 Reports Screen Init - instituteId: $_instituteId');
    _loadStudents();
  }

  /// Load all students from institute
  Future<void> _loadStudents() async {
    if (_instituteId == null || _instituteId!.isEmpty) {
      print('❌ No instituteId provided');
      return;
    }

    try {
      print('🔄 Loading students for institute: $_instituteId');
      final response = await appDb
          .from('students')
          .select('id,sr_no,fname,lname,sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8')
          .eq('institute_id', _instituteId!)
          .order('sr_no');

      print('✅ Loaded ${response.length} students');
      if (mounted) {
        setState(() {
          _students = List<Map<String, dynamic>>.from(response);
          _loadingStudents = false;
        });
      }
    } catch (e) {
      print('❌ Error loading students: $e');
      if (mounted) setState(() => _loadingStudents = false);
    }
  }

  /// Get student's subjects
  List<String> _getStudentSubjects(Map<String, dynamic> student) {
    final subjects = <String>[];
    for (int i = 1; i <= 8; i++) {
      final sub = student['sub$i'] as String?;
      if (sub != null && sub.isNotEmpty) subjects.add(sub);
    }
    return subjects;
  }

  /// Fetch today's attendance for selected student
  Future<Map<String, dynamic>> _fetchTodayAttendance() async {
    if (_selectedStudent == null) {
      print('❌ No student selected for today attendance');
      return {};
    }

    try {
      print('🔄 Fetching today attendance for: ${_selectedStudent!['sr_no']}');
      final today = DateTime.now().toIso8601String().split('T')[0];
      final srNo = _selectedStudent!['sr_no'] as String;

      final records = await appDb
          .from('attendance_records')
          .select()
          .eq('sr_no', srNo)
          .eq('date', today)
          .order('timestamp');

      if (records.isEmpty) {
        return {
          'status': 'ABSENT',
          'entry_time': null,
          'exit_time': null,
          'credited_hours': 0.0,
          'allocated_hours': 8.0,
        };
      }

      // Get entry and exit times
      final entry = records.first;
      final exit = records.length > 1 ? records.last : null;

      final entryTime = DateTime.parse(entry['timestamp'] as String);
      final exitTime = exit != null ? DateTime.parse(exit['timestamp'] as String) : null;

      // Calculate hours
      double creditedHours = 0.0;
      if (exitTime != null) {
        creditedHours = exitTime.difference(entryTime).inMinutes / 60.0;
      } else {
        creditedHours = DateTime.now().difference(entryTime).inMinutes / 60.0;
      }

      // Get allocated hours based on subjects
      final subjects = _getStudentSubjects(_selectedStudent!);
      double allocatedHours = 8.0;
      if (subjects.length <= 2) allocatedHours = 8.0;
      else if (subjects.length <= 4) allocatedHours = 6.0;
      else allocatedHours = 5.0;

      // Determine status
      String status = 'SEATED';
      if (creditedHours < allocatedHours) status = 'SHORT';

      return {
        'status': status,
        'entry_time': entryTime.toIso8601String(),
        'exit_time': exitTime?.toIso8601String(),
        'credited_hours': creditedHours,
        'allocated_hours': allocatedHours,
      };
    } catch (e) {
      print('Error fetching today attendance: $e');
      return {
        'status': 'ERROR',
        'credited_hours': 0.0,
        'allocated_hours': 0.0,
      };
    }
  }

  /// Fetch attendance history for selected student
  /// Logic:
  /// 1. Entry + Exit both marked → Use hours from EXIT
  /// 2. Entry marked but NO Exit (after 12 AM) → "NOT EXITED BUT ENTRY" + Add allotted hours
  /// 3. No Entry + No Exit → ABSENT
  Future<Map<String, dynamic>> _fetchAttendanceHistory() async {
    if (_selectedStudent == null) {
      print('❌ No student selected for history');
      return {};
    }

    try {
      final srNo = _selectedStudent!['sr_no'] as String;
      final subjects = _getStudentSubjects(_selectedStudent!);
      print('🔄 Fetching history for: $srNo, subjects: ${subjects.length}');

      // Get allocated hours for this student based on subject count
      double allocatedHours = 8.0;
      if (subjects.length <= 2) allocatedHours = 8.0;
      else if (subjects.length <= 4) allocatedHours = 6.0;
      else allocatedHours = 5.0;

      // Group records by date
      final records = await appDb
          .from('attendance_records')
          .select()
          .eq('sr_no', srNo)
          .order('attendance_date, marked_time');

      print('✅ Got ${records.length} records for $srNo');

      Map<String, List<Map<String, dynamic>>> recordsByDate = {};
      for (final record in records) {
        final date = record['attendance_date'] as String?;
        if (date == null) continue;
        recordsByDate.putIfAbsent(date, () => []);
        recordsByDate[date]!.add(record as Map<String, dynamic>);
      }

      int presentCount = 0;
      int absentCount = 0;
      double totalHours = 0.0;

      // Analyze each day's attendance
      for (final MapEntry(key: date, value: dayRecords) in recordsByDate.entries) {
        print('📅 Processing date: $date with ${dayRecords.length} records');

        // Find entry and exit records
        final entryRecord = dayRecords.firstWhere(
          (r) => (r['record_type'] as String?) == 'entry',
          orElse: () => <String, dynamic>{},
        );
        final exitRecord = dayRecords.firstWhere(
          (r) => (r['record_type'] as String?) == 'exit',
          orElse: () => <String, dynamic>{},
        );

        if (entryRecord.isNotEmpty && exitRecord.isNotEmpty) {
          // ✅ Case 1: BOTH Entry and Exit marked - Use hours from exit record
          print('✅ Entry + Exit found for $date');
          presentCount++;

          final entryTime = DateTime.parse(entryRecord['marked_time'] as String);
          final exitTime = DateTime.parse(exitRecord['marked_time'] as String);

          final dayHours = exitTime.difference(entryTime).inMinutes / 60.0;
          totalHours += dayHours;
        } else if (entryRecord.isNotEmpty && exitRecord.isEmpty) {
          // ⏱️ Case 2: Entry marked but NO Exit - "NOT EXITED BUT ENTRY" + Add allotted hours
          print('⏱️ Entry only (no exit) for $date - marking as NOT EXITED');
          presentCount++;
          totalHours += allocatedHours; // Add allotted hours
        } else if (entryRecord.isEmpty && exitRecord.isEmpty) {
          // ❌ Case 3: No entry and no exit - ABSENT
          print('❌ No entry/exit for $date - marking as ABSENT');
          absentCount++;
        }
      }

      final total = recordsByDate.length;
      double avgHours = presentCount > 0 ? totalHours / presentCount : 0.0;

      return {
        'present': presentCount,
        'absent': absentCount,
        'total': total,
        'hours': avgHours,
        'subjects': subjects.join(', '),
      };
    } catch (e) {
      print('Error fetching history: $e');
      return {
        'present': 0,
        'absent': 0,
        'total': 0,
        'hours': 0.0,
        'subjects': '-',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D1B2E) : AppTheme.backgroundGrey,
      body: _loadingStudents
          ? Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue))
          : SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),

                    // 👥 Student Selector
                    Text(
                      'Select Student',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
                            AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButton<Map<String, dynamic>>(
                        value: _selectedStudent,
                        hint: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.w),
                          child: Text(
                            'Choose a student...',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                              fontSize: 13.sp,
                            ),
                          ),
                        ),
                        isExpanded: true,
                        underline: SizedBox.shrink(),
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        items: _students.map((student) {
                          final fname = student['fname'] as String? ?? '';
                          final lname = student['lname'] as String? ?? '';
                          final srNo = student['sr_no'] as String? ?? '';
                          final label = '$srNo - $fname $lname'.trim();

                          return DropdownMenuItem(
                            value: student,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12.w),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: isDark ? Colors.white : AppTheme.textDark,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (student) {
                          setState(() => _selectedStudent = student);
                        },
                      ),
                    ),

                    if (_selectedStudent != null) ...[
                      SizedBox(height: 32.h),

                      // 📅 TODAY'S ATTENDANCE
                      Text(
                        "TODAY'S ATTENDANCE",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchTodayAttendance(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.h),
                                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                              ),
                            );
                          }

                          final data = snapshot.data ?? {};
                          final status = data['status'] as String? ?? 'ERROR';
                          final creditedHours = data['credited_hours'] as double? ?? 0.0;
                          final allocatedHours = data['allocated_hours'] as double? ?? 0.0;

                          Color statusColor = AppTheme.accentRed;
                          IconData statusIcon = Icons.cancel;

                          if (status == 'SEATED') {
                            statusColor = AppTheme.primaryGreen;
                            statusIcon = Icons.check_circle;
                          } else if (status == 'SHORT') {
                            statusColor = AppTheme.accentOrange;
                            statusIcon = Icons.schedule;
                          }

                          return Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  statusColor.withOpacity(isDark ? 0.12 : 0.06),
                                  statusColor.withOpacity(isDark ? 0.06 : 0.02),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: statusColor.withOpacity(isDark ? 0.3 : 0.15),
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(statusIcon, color: statusColor, size: 24.sp),
                                    SizedBox(width: 12.w),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 16.sp,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16.h),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Credited Hours',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white70 : AppTheme.textGray,
                                          ),
                                        ),
                                        Text(
                                          '${creditedHours.toStringAsFixed(1)}h',
                                          style: TextStyle(
                                            fontSize: 18.sp,
                                            fontWeight: FontWeight.w800,
                                            color: statusColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Allocated Hours',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white70 : AppTheme.textGray,
                                          ),
                                        ),
                                        Text(
                                          '${allocatedHours.toStringAsFixed(1)}h',
                                          style: TextStyle(
                                            fontSize: 18.sp,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 32.h),

                      // 📊 ATTENDANCE HISTORY
                      Text(
                        "ATTENDANCE HISTORY",
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                      SizedBox(height: 12.h),
                      FutureBuilder<Map<String, dynamic>>(
                        future: _fetchAttendanceHistory(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(24.h),
                                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
                              ),
                            );
                          }

                          final data = snapshot.data ?? {};
                          final subjects = data['subjects'] as String? ?? '-';
                          final present = data['present'] as int? ?? 0;
                          final absent = data['absent'] as int? ?? 0;
                          final total = data['total'] as int? ?? 0;
                          final hours = data['hours'] as double? ?? 0.0;

                          return Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
                                  AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
                                width: 1.5,
                              ),
                            ),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                dataRowMinHeight: 48.h,
                                dataRowMaxHeight: 56.h,
                                headingRowColor: MaterialStateColor.resolveWith(
                                  (_) => AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
                                ),
                                columns: [
                                  DataColumn(
                                    label: Text(
                                      'Subjects',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Present',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Absent',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.accentRed,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                  DataColumn(
                                    label: Text(
                                      'Hours',
                                      style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.primaryBlue,
                                      ),
                                    ),
                                  ),
                                ],
                                rows: [
                                  DataRow(
                                    cells: [
                                      DataCell(
                                        Text(
                                          subjects,
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryGreen.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(
                                            '$present',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primaryGreen,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentRed.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(6.r),
                                          ),
                                          child: Text(
                                            '$absent',
                                            style: TextStyle(
                                              fontSize: 12.sp,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.accentRed,
                                            ),
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '$total',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : AppTheme.textDark,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${hours.toStringAsFixed(1)}h',
                                          style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primaryBlue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      SizedBox(height: 32.h),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
