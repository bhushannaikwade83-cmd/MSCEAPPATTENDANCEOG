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
  /// TODAY'S ATTENDANCE
  /// Logic:
  /// 1. Entry + Exit both → Check EXIT record's attendance_alloted_hr NOT NULL → PRESENT
  /// 2. Entry only (no exit) → Check ENTRY record's attendance_alloted_hr NOT NULL → PRESENT
  /// 3. No Entry → ABSENT
  Future<Map<String, dynamic>> _fetchTodayAttendance() async {
    if (_selectedStudent == null) {
      print('❌ No student selected');
      return {};
    }

    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final srNo = _selectedStudent!['sr_no'] as String;

      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .eq('attendance_date', today)
          .order('marked_time');

      print('✅ Got ${records.length} records for today');

      // Check if entry and exit exist
      final entryRec = records.firstWhere(
        (r) => (r['record_type'] as String?) == 'entry',
        orElse: () => <String, dynamic>{},
      );
      final exitRec = records.firstWhere(
        (r) => (r['record_type'] as String?) == 'exit',
        orElse: () => <String, dynamic>{},
      );

      // No entry = ABSENT
      if (entryRec.isEmpty) {
        print('❌ ABSENT - No entry');
        return {
          'status': 'ABSENT',
          'entry_time': null,
          'exit_time': null,
          'credited_hours': 0.0,
          'allocated_hours': 0.0,
        };
      }

      double? hrs;
      DateTime? entryTime = DateTime.parse(entryRec['marked_time'] as String);
      DateTime? exitTime;

      if (exitRec.isNotEmpty) {
        // Entry + Exit both → check EXIT record's attendance_alloted_hr
        final hrsStr = exitRec['attendance_alloted_hr'] as String?;
        hrs = hrsStr != null ? double.tryParse(hrsStr) : null;
        exitTime = DateTime.parse(exitRec['marked_time'] as String);
        print('✅ PRESENT (Entry+Exit) - Hours: $hrs');
      } else {
        // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
        final hrsStr = entryRec['attendance_alloted_hr'] as String?;
        hrs = hrsStr != null ? double.tryParse(hrsStr) : null;
        print('✅ PRESENT (Entry only) - Hours: $hrs');
      }

      final allocatedHours = hrs ?? 0.0;

      return {
        'status': 'PRESENT',
        'entry_time': entryTime.toIso8601String(),
        'exit_time': exitTime?.toIso8601String(),
        'credited_hours': allocatedHours,
        'allocated_hours': allocatedHours,
      };
    } catch (e) {
      print('❌ Error: $e');
      return {
        'status': 'ERROR',
        'credited_hours': 0.0,
        'allocated_hours': 0.0,
      };
    }
  }

  /// Fetch attendance history
  /// Logic:
  /// 1. Entry + Exit both → Check EXIT record's attendance_alloted_hr NOT NULL → PRESENT
  /// 2. Entry only (no exit) → Check ENTRY record's attendance_alloted_hr NOT NULL → PRESENT
  /// 3. No Entry on weekday → ABSENT
  /// 4. No Entry on Sunday → SKIP (don't count)
  /// 5. If Sunday has entry → apply same logic as step 1-2 → PRESENT
  Future<Map<String, dynamic>> _fetchAttendanceHistory() async {
    if (_selectedStudent == null) {
      print('❌ No student selected for history');
      return {};
    }

    try {
      final srNo = _selectedStudent!['sr_no'] as String;
      print('🔄 Fetching history for: $srNo');

      // Get all records ordered by date and time
      final records = await appDb
          .from('attendance')
          .select()
          .eq('sr_no', srNo)
          .order('attendance_date, marked_time');

      print('✅ Got ${records.length} records');

      // Group by date
      Map<String, List<Map<String, dynamic>>> byDate = {};
      for (final rec in records) {
        final date = rec['attendance_date'] as String?;
        if (date == null) continue;
        byDate.putIfAbsent(date, () => []);
        byDate[date]!.add(rec as Map<String, dynamic>);
      }

      int present = 0, absent = 0;
      double totalHours = 0.0;

      // Process each day
      for (final MapEntry(key: dateStr, value: dayRecs) in byDate.entries) {
        try {
          final dateObj = DateTime.parse(dateStr);
          final isSunday = dateObj.weekday == DateTime.sunday;

          // Check if entry and exit exist
          final entryRec = dayRecs.firstWhere(
            (r) => (r['record_type'] as String?) == 'entry',
            orElse: () => <String, dynamic>{},
          );
          final exitRec = dayRecs.firstWhere(
            (r) => (r['record_type'] as String?) == 'exit',
            orElse: () => <String, dynamic>{},
          );

          // CASE 1: No entry at all
          if (entryRec.isEmpty) {
            if (isSunday) {
              // Sunday with no entry = SKIP
              print('⏸️ SKIP: $dateStr [Sunday, no entry]');
            } else {
              // Weekday with no entry = ABSENT
              print('❌ ABSENT: $dateStr');
              absent++;
            }
            continue;
          }

          // CASE 2: Entry exists
          double? hrs;

          if (exitRec.isNotEmpty) {
            // Entry + Exit both → check EXIT record's attendance_alloted_hr
            final hrsStr = exitRec['attendance_alloted_hr'] as String?;
            hrs = hrsStr != null ? double.tryParse(hrsStr) : null;
            if (hrs != null) {
              print('✅ PRESENT (Entry+Exit): $dateStr → $hrs hrs${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalHours += hrs;
            }
          } else {
            // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
            final hrsStr = entryRec['attendance_alloted_hr'] as String?;
            hrs = hrsStr != null ? double.tryParse(hrsStr) : null;
            if (hrs != null) {
              print('✅ PRESENT (Entry only): $dateStr → $hrs hrs${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalHours += hrs;
            }
          }
        } catch (e) {
          print('⚠️ Error processing $dateStr: $e');
        }
      }

      final total = present + absent;
      final avgHrs = present > 0 ? totalHours / present : 0.0;

      print('📊 Summary - Present: $present, Absent: $absent, Total: $total, Avg: ${avgHrs.toStringAsFixed(2)} hrs');

      return {
        'present': present,
        'absent': absent,
        'total': total,
        'hours': avgHrs,
      };
    } catch (e) {
      print('❌ Error: $e');
      return {'present': 0, 'absent': 0, 'total': 0, 'hours': 0.0};
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
