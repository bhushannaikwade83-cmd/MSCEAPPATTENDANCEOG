import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';

/// Attendance Calendar Screen - Shows monthly calendar with attendance
class AttendanceCalendarScreen extends StatefulWidget {
  final String instituteId;
  final String? rollNumber;

  const AttendanceCalendarScreen({
    super.key,
    required this.instituteId,
    this.rollNumber,
  });

  @override
  State<AttendanceCalendarScreen> createState() =>
      _AttendanceCalendarScreenState();
}

class _AttendanceCalendarScreenState extends State<AttendanceCalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _rangeEndMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _rangeMonths = 1;
  Map<String, int> _attendanceMap = {}; // date -> count

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    final startMonth = DateTime(
      _rangeEndMonth.year,
      _rangeEndMonth.month - (_rangeMonths - 1),
      1,
    );
    final endMonth = DateTime(_rangeEndMonth.year, _rangeEndMonth.month + 1, 0);
    final startStr = DateFormat('yyyy-MM-dd').format(startMonth);
    final endStr = DateFormat('yyyy-MM-dd').format(endMonth);

    final code = await instituteCodeForId(widget.instituteId);
    if (!mounted) return;
    final List<dynamic> rows;
    if (widget.rollNumber != null && widget.rollNumber!.isNotEmpty) {
      rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date,student_id,sr_no,type,additional')
          .eq('institute_code', code)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr)
          .eq('sr_no', widget.rollNumber!);
    } else {
      rows = await appDb
          .from('attendance_in_out')
          .select('attendance_date,student_id,sr_no,type,additional')
          .eq('institute_code', code)
          .gte('attendance_date', startStr)
          .lte('attendance_date', endStr);
    }
    if (!mounted) return;
    final Map<String, Set<String>> presentByDate = {};

    for (final r in rows) {
      final data = r as Map<String, dynamic>;
      final date = data['attendance_date']?.toString();
      if (date == null || date.isEmpty) continue;
      final sid = (data['student_id'] as String?)?.trim() ?? '';
      final sr = (data['sr_no'] as String?)?.trim() ?? '';
      final key = sid.isNotEmpty ? sid : sr;
      if (key.isEmpty) continue;

      final type = (data['type']?.toString() ?? '').toLowerCase();
      final add = data['additional'];
      final status = (add is Map ? add['status'] : null)?.toString().toLowerCase();
      final isPresent = status == 'present' || (status == null && type == 'exit');
      if (!isPresent) continue;

      presentByDate.putIfAbsent(date, () => <String>{}).add(key);
    }

    setState(() {
      _attendanceMap = {
        for (final e in presentByDate.entries) e.key: e.value.length,
      };
    });
  }

  Future<int> _countForDate(String dateStr) async {
    final code = await instituteCodeForId(widget.instituteId);
    final List<dynamic> rows;
    if (widget.rollNumber != null && widget.rollNumber!.isNotEmpty) {
      rows = await appDb
          .from('attendance_in_out')
          .select('student_id,sr_no,type,additional')
          .eq('institute_code', code)
          .eq('attendance_date', dateStr)
          .eq('sr_no', widget.rollNumber!);
    } else {
      rows = await appDb
          .from('attendance_in_out')
          .select('student_id,sr_no,type,additional')
          .eq('institute_code', code)
          .eq('attendance_date', dateStr);
    }
    final presentStudents = <String>{};
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final sid = (row['student_id'] as String?)?.trim() ?? '';
      final sr = (row['sr_no'] as String?)?.trim() ?? '';
      final key = sid.isNotEmpty ? sid : sr;
      if (key.isEmpty) continue;
      final type = (row['type']?.toString() ?? '').toLowerCase();
      final add = row['additional'];
      final status = (add is Map ? add['status'] : null)?.toString().toLowerCase();
      final isPresent = status == 'present' || (status == null && type == 'exit');
      if (isPresent) presentStudents.add(key);
    }
    return presentStudents.length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () {
              setState(() {
                _rangeEndMonth = DateTime(
                  _rangeEndMonth.year,
                  _rangeEndMonth.month - 1,
                  1,
                );
                _loadAttendanceData();
              });
            },
          ),
          Text(
            '${_rangeMonths}M · ${DateFormat('MMM yyyy').format(_rangeEndMonth)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: () {
              setState(() {
                _rangeEndMonth = DateTime(
                  _rangeEndMonth.year,
                  _rangeEndMonth.month + 1,
                  1,
                );
                _loadAttendanceData();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildRangeSelector(isDark),
          Expanded(child: _buildRangeCalendars(isDark)),
          // Selected Date Info
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.grey.shade300,
                ),
              ),
            ),
            child: _buildDateInfo(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [1, 3, 6].map((months) {
          final isSelected = _rangeMonths == months;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text('$months Month${months > 1 ? 's' : ''}'),
                selected: isSelected,
                onSelected: (_) {
                  setState(() {
                    _rangeMonths = months;
                    _loadAttendanceData();
                  });
                },
                selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                backgroundColor:
                    isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade100,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<DateTime> _monthsToDisplay() {
    final months = <DateTime>[];
    for (int i = _rangeMonths - 1; i >= 0; i--) {
      months.add(DateTime(_rangeEndMonth.year, _rangeEndMonth.month - i, 1));
    }
    return months;
  }

  Widget _buildRangeCalendars(bool isDark) {
    final months = _monthsToDisplay();
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      itemCount: months.length,
      itemBuilder: (context, index) => _buildCalendarGridForMonth(isDark, months[index]),
    );
  }

  Widget _buildCalendarGridForMonth(bool isDark, DateTime monthStart) {
    final firstDay = DateTime(monthStart.year, monthStart.month, 1);
    final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0);
    final firstDayOfWeek = firstDay.weekday;
    final daysInMonth = lastDay.day;

    // Weekday headers
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300,
        ),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              DateFormat('MMMM yyyy').format(monthStart),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Weekday headers
          Row(
            children: weekdays.map((day) {
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.6)
                          : AppTheme.textGray,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Calendar days
          SizedBox(
            height: 230,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: firstDayOfWeek - 1 + daysInMonth,
              itemBuilder: (context, index) {
                if (index < firstDayOfWeek - 1) {
                  return const SizedBox.shrink();
                }

                final day = index - firstDayOfWeek + 2;
                final date = DateTime(
                  monthStart.year,
                  monthStart.month,
                  day,
                );
                final dateStr = DateFormat('yyyy-MM-dd').format(date);
                final hasAttendance = _attendanceMap.containsKey(dateStr);
                final isSelected =
                    _selectedDate.year == date.year &&
                    _selectedDate.month == date.month &&
                    _selectedDate.day == date.day;
                final isToday =
                    date.year == DateTime.now().year &&
                    date.month == DateTime.now().month &&
                    date.day == DateTime.now().day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryBlue
                          : isToday
                          ? AppTheme.primaryBlue.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday
                            ? AppTheme.primaryBlue
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected || isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : isDark
                                ? Colors.white
                                : AppTheme.textDark,
                          ),
                        ),
                        if (hasAttendance)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateInfo(bool isDark) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final hasAttendance = _attendanceMap.containsKey(dateStr);

    return FutureBuilder<int>(
      future: _countForDate(dateStr),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasAttendance ? Icons.check_circle : Icons.cancel,
                  color: hasAttendance
                      ? AppTheme.primaryGreen
                      : AppTheme.accentRed,
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              hasAttendance
                  ? '$count student${count > 1 ? 's' : ''} present'
                  : 'No student present',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : AppTheme.textGray,
              ),
            ),
          ],
        );
      },
    );
  }
}
