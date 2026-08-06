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

  // Date filters
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _selectedFilter = '1month'; // 1month, 3month, 6month, custom

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

  /// Parse HH:MM:SS string to total seconds
  int _timeStringToSeconds(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 0;
    try {
      final parts = timeStr.split(':');
      if (parts.length != 3) return 0;
      final hours = int.tryParse(parts[0]) ?? 0;
      final minutes = int.tryParse(parts[1]) ?? 0;
      final seconds = int.tryParse(parts[2]) ?? 0;
      return (hours * 3600) + (minutes * 60) + seconds;
    } catch (e) {
      return 0;
    }
  }

  /// Convert total seconds to HH:MM:SS string
  String _secondsToTimeString(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Set date range based on filter
  void _setDateFilter(String filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      if (filter == '1month') {
        _filterStartDate = now.subtract(const Duration(days: 30));
        _filterEndDate = now;
      } else if (filter == '3month') {
        _filterStartDate = now.subtract(const Duration(days: 90));
        _filterEndDate = now;
      } else if (filter == '6month') {
        _filterStartDate = now.subtract(const Duration(days: 180));
        _filterEndDate = now;
      }
    });
  }

  /// Show custom date range picker
  Future<void> _showCustomDatePicker() async {
    final startDate = await showDatePicker(
      context: context,
      initialDate: _filterStartDate ?? DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (startDate != null) {
      final endDate = await showDatePicker(
        context: context,
        initialDate: _filterEndDate ?? DateTime.now(),
        firstDate: startDate,
        lastDate: DateTime.now(),
      );

      if (endDate != null) {
        setState(() {
          _selectedFilter = 'custom';
          _filterStartDate = startDate;
          _filterEndDate = endDate;
        });
      }
    }
  }

  /// Build filter button
  Widget _buildFilterButton(String label, String filter, bool isDark) {
    final isSelected = _selectedFilter == filter;
    return GestureDetector(
      onTap: () {
        if (filter == 'custom') {
          _showCustomDatePicker();
        } else {
          _setDateFilter(filter);
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF0F2F7)),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppTheme.textGray),
          ),
        ),
      ),
    );
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
        if (hrsStr != null && hrsStr.isNotEmpty) {
          exitTime = DateTime.parse(exitRec['marked_time'] as String);
          print('✅ PRESENT (Entry+Exit) - Hours: $hrsStr');
          return {
            'status': 'PRESENT',
            'entry_time': entryTime.toIso8601String(),
            'exit_time': exitTime.toIso8601String(),
            'credited_hours': hrsStr,
            'allocated_hours': hrsStr,
          };
        }
      } else {
        // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
        final hrsStr = entryRec['attendance_alloted_hr'] as String?;
        if (hrsStr != null && hrsStr.isNotEmpty) {
          print('✅ PRESENT (Entry only) - Hours: $hrsStr');
          return {
            'status': 'PRESENT',
            'entry_time': entryTime.toIso8601String(),
            'exit_time': null,
            'credited_hours': hrsStr,
            'allocated_hours': hrsStr,
          };
        }
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
      int totalSeconds = 0;

      // Process each day
      for (final MapEntry(key: dateStr, value: dayRecs) in byDate.entries) {
        try {
          final dateObj = DateTime.parse(dateStr);

          // Apply date filter
          if (_filterStartDate != null && _filterEndDate != null) {
            if (dateObj.isBefore(_filterStartDate!) || dateObj.isAfter(_filterEndDate!)) {
              continue; // Skip records outside date range
            }
          }

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
            if (hrsStr != null && hrsStr.isNotEmpty) {
              print('✅ PRESENT (Entry+Exit): $dateStr → $hrsStr${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalSeconds += _timeStringToSeconds(hrsStr);
            }
          } else {
            // Entry only (no exit) → check ENTRY record's attendance_alloted_hr
            final hrsStr = entryRec['attendance_alloted_hr'] as String?;
            if (hrsStr != null && hrsStr.isNotEmpty) {
              print('✅ PRESENT (Entry only): $dateStr → $hrsStr${isSunday ? ' [Sunday]' : ''}');
              present++;
              totalSeconds += _timeStringToSeconds(hrsStr);
            }
          }
        } catch (e) {
          print('⚠️ Error processing $dateStr: $e');
        }
      }

      final total = present + absent;
      final totalTimeStr = _secondsToTimeString(totalSeconds);

      print('📊 Summary - Present: $present, Absent: $absent, Total: $total, Total Hours: $totalTimeStr');

      return {
        'present': present,
        'absent': absent,
        'total': total,
        'hours': totalTimeStr,
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

                      // 📅 DATE FILTERS
                      Text(
                        "FILTER BY DATE",
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : AppTheme.textGray,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterButton('1 Month', '1month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('3 Months', '3month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('6 Months', '6month', isDark),
                            SizedBox(width: 10.w),
                            _buildFilterButton('Custom', 'custom', isDark),
                          ],
                        ),
                      ),
                      SizedBox(height: 20.h),

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
                          final present = data['present'] as int? ?? 0;
                          final absent = data['absent'] as int? ?? 0;
                          final total = data['total'] as int? ?? 0;
                          final hours = data['hours'] as String? ?? '00:00:00';

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
                                          '-',
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
                                          hours,
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
