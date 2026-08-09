import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../core/attendance_hours_db_reader.dart';
import '../../core/attendance_presence_rules.dart';
import '../../core/time_parse.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/pdf_export_service.dart';
import '../../presentation/widgets/institute_report_table.dart';
import '../../presentation/widgets/date_range_selector.dart';
import '../../models/date_range_filter.dart';

class InstituteReportScreen extends StatefulWidget {
  static const routeName = '/institute-report';
  final String? instituteId;
  final DateTime? startDate;
  final DateTime? endDate;

  const InstituteReportScreen({
    super.key,
    this.instituteId,
    this.startDate,
    this.endDate,
  });

  @override
  State<InstituteReportScreen> createState() => _InstituteReportScreenState();
}

class _InstituteReportScreenState extends State<InstituteReportScreen> {
  String? _instituteId;
  String? _instituteName;
  late DateTime _startDate;
  late DateTime _endDate;
  bool _isLoading = false;
  Map<String, dynamic> _reportData = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _startDate = widget.startDate ?? DateTime.now().subtract(const Duration(days: 7));
    _endDate = widget.endDate ?? DateTime.now();
    _instituteId = widget.instituteId;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      if (_instituteId == null || _instituteId!.isEmpty) {
        final user = appDb.auth.currentUser;
        if (user != null) {
          final profile = await appDb
              .from('profiles')
              .select('institute_id, institutes(name)')
              .eq('id', user.id)
              .maybeSingle();
          if (profile != null) {
            _instituteId = profile['institute_id'] as String?;
            _instituteName = (profile['institutes'] as Map?)?['name'] as String?;
          }
        }
      } else if (_instituteName == null) {
        final inst = await appDb
            .from('institutes')
            .select('name')
            .eq('id', _instituteId!)
            .maybeSingle();
        _instituteName = inst?['name'] as String?;
      }

      if (_instituteId != null && _instituteId!.isNotEmpty) {
        await _generateReport();
      }
    } catch (e) {
      debugPrint('Error loading institute report: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateReport() async {
    if (_instituteId == null) return;

    final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);

    // 1. Fetch all students with registration dates
    final allStudents = await appDb
        .from('students')
        .select('id, sr_no, fname, mname, lname, face_registered_at, old_face_registered_at')
        .eq('institute_id', _instituteId!);

    final studentIds = allStudents.map((s) => s['id'] as String).toList();
    final rollByStudentId = <String, String>{};
    final nameByRoll = <String, String>{};
    final srNoByRoll = <String, String>{};
    final subjectCountByRoll = <String, int>{};
    final registrationDateByRoll = <String, String>{};
    final firstRegistrationDateByRoll = <String, DateTime>{};

    for (final s in allStudents) {
      final sid = s['id'] as String;
      final roll = s['sr_no'] as String? ?? '';

      if (roll.isNotEmpty) {
        rollByStudentId[sid] = roll;
        final fname = (s['fname'] as String?)?.trim() ?? '';
        final mname = (s['mname'] as String?)?.trim() ?? '';
        final lname = (s['lname'] as String?)?.trim() ?? '';
        final name = [fname, mname, lname].where((e) => e.isNotEmpty).join(' ').trim();
        nameByRoll[roll] = name.isNotEmpty ? name : 'Unknown';
        srNoByRoll[roll] = s['sr_no'] as String? ?? roll;

        // Parse registration date - use old_face_registered_at if exists (first registration)
        final oldRegisteredAtRaw = s['old_face_registered_at'] as String?;
        final currentRegisteredAtRaw = s['face_registered_at'] as String?;

        DateTime? dateToUse;
        String displayText = '-';

        if (oldRegisteredAtRaw != null && oldRegisteredAtRaw.isNotEmpty) {
          // Face was reset - use old date for attendance counting
          try {
            dateToUse = DateTime.parse(oldRegisteredAtRaw);
            final oldDate = DateFormat('dd MMM yyyy').format(dateToUse);
            final newDate = currentRegisteredAtRaw != null && currentRegisteredAtRaw.isNotEmpty
                ? DateFormat('dd MMM yyyy').format(DateTime.parse(currentRegisteredAtRaw))
                : '-';
            displayText = '$oldDate (Reset: $newDate)';
          } catch (_) {
            displayText = '-';
          }
        } else if (currentRegisteredAtRaw != null && currentRegisteredAtRaw.isNotEmpty) {
          // First registration
          try {
            dateToUse = DateTime.parse(currentRegisteredAtRaw);
            displayText = DateFormat('dd MMM yyyy').format(dateToUse);
          } catch (_) {
            displayText = '-';
          }
        }

        if (dateToUse != null) {
          firstRegistrationDateByRoll[roll] = dateToUse;
        }
        registrationDateByRoll[roll] = displayText;

        final subjectCount = [
          s['sub1'], s['sub2'], s['sub3'], s['sub4'],
          s['sub5'], s['sub6'], s['sub7'], s['sub8'],
        ].where((v) => (v as String?)?.trim().isNotEmpty == true).length;
        subjectCountByRoll[roll] = (subjectCount == 0 ? 1 : subjectCount).clamp(1, 4);
      }
    }

    // 2. Fetch attendance records (SAME RULES AS STUDENT REPORT)
    final records = await appDb
        .from('attendance')
        .select()
        .eq('institute_id', _instituteId!)
        .gte('attendance_date', startDateStr)
        .lte('attendance_date', endDateStr)
        .order('attendance_date, marked_time');

    // Group by date and student
    Map<String, Map<String, List<Map<String, dynamic>>>> byStudent = {};
    for (final rec in records) {
      final srNo = rec['sr_no'] as String?;
      final date = rec['attendance_date'] as String?;
      if (srNo != null && date != null) {
        byStudent.putIfAbsent(srNo, () => {}).putIfAbsent(date, () => []).add(rec);
      }
    }

    // Calculate present/absent using SAME RULES
    final studentPresentCount = <String, int>{};
    final studentCreditedHoursByRoll = <String, double>{};
    final studentWorkingDaysByRoll = <String, int>{};

    print('📊 [INSTITUTE REPORT] Calculating hours for ${nameByRoll.length} students');

    for (final roll in nameByRoll.keys) {
      int presentDays = 0;
      double totalHours = 0.0;

      print('🔍 [STUDENT] Roll: $roll (${nameByRoll[roll]})');

      // Get student's first registration date (from firstRegistrationDateByRoll)
      final registrationDate = firstRegistrationDateByRoll[roll];

      if (registrationDate != null) {
        print('   📅 Registration date: $registrationDate');
      }

      // Calculate working days for this student (from registration date or start date, whichever is later)
      DateTime effectiveStartDate = _startDate;
      if (registrationDate != null && registrationDate.isAfter(_startDate)) {
        effectiveStartDate = registrationDate;
      }
      final workingDaysForStudent = _calculateWorkingDaysExcludingSundayFromTo(effectiveStartDate, _endDate);
      studentWorkingDaysByRoll[roll] = workingDaysForStudent;
      print('   📋 Working days for $roll (from ${effectiveStartDate.toString().split(' ')[0]} to ${_endDate.toString().split(' ')[0]}): $workingDaysForStudent');

      if (byStudent.containsKey(roll)) {
        final studentRecords = byStudent[roll]!;
        print('   📋 Found ${studentRecords.length} days of records');

        for (final dateStr in studentRecords.keys) {
          final dateObj = DateTime.parse(dateStr);

          // Filter by registration date - only count attendance from registration date onwards
          if (registrationDate != null && dateObj.isBefore(registrationDate)) {
            print('   ⏭️ Skipping (before registration): $dateStr');
            continue;
          }

          // Exclude Sundays
          if (dateObj.weekday == DateTime.sunday) {
            print('   ⏭️ Skipping Sunday: $dateStr');
            continue;
          }

          final dayRecs = studentRecords[dateStr]!;
          final entryRec =
              dayRecs.firstWhere((r) => (r['record_type'] as String?) == 'entry', orElse: () => <String, dynamic>{});
          final exitRec =
              dayRecs.firstWhere((r) => (r['record_type'] as String?) == 'exit', orElse: () => <String, dynamic>{});

          print('   📅 $dateStr - Entry: ${entryRec.isNotEmpty} Exit: ${exitRec.isNotEmpty}');

          // Apply rules: Entry + Exit = Present, Entry only = Present, No Entry = Absent
          if (entryRec.isNotEmpty) {
            presentDays++;
            // Get hours from allocated_hr
            final hrs = exitRec.isNotEmpty
                ? (exitRec['attendance_alloted_hr'] as String? ?? '0.0')
                : (entryRec['attendance_alloted_hr'] as String? ?? '0.0');
            final hrsDouble = _parseHoursString(hrs);
            totalHours += hrsDouble;
            print('      ✅ PRESENT | Hours: $hrs | Parsed: $hrsDouble | Total so far: $totalHours');
          } else {
            print('      ❌ ABSENT');
          }
        }
      } else {
        print('   ⏭️ No records found for this student');
      }

      print('   📊 Final: Present=$presentDays, Total Hours=$totalHours');
      studentPresentCount[roll] = presentDays;
      studentCreditedHoursByRoll[roll] = totalHours;
    }

    print('✅ [INSTITUTE REPORT] Calculation complete');
    print('📊 Hours map: $studentCreditedHoursByRoll');

    final totalWorkingDays = _calculateWorkingDaysExcludingSunday();

    if (mounted) {
      setState(() {
        _reportData = {
          'nameByRoll': nameByRoll,
          'srNoByRoll': srNoByRoll,
          'presentCount': studentPresentCount,
          'creditedHours': studentCreditedHoursByRoll,
          'creditedHoursFormatted': <String, String>{
            for (final roll in studentCreditedHoursByRoll.keys)
              roll: _formatHours(studentCreditedHoursByRoll[roll]!)
          },
          'subjectCount': subjectCountByRoll,
          'registrationDateByRoll': registrationDateByRoll,
          'totalWorkingDays': totalWorkingDays,
          'studentWorkingDaysByRoll': studentWorkingDaysByRoll,
        };
      });
    }
  }

  String _formatHours(double hours) {
    final h = hours.toInt();
    final m = ((hours - h) * 60).toInt();
    final s = (((hours - h) * 60 - m) * 60).toInt();
    return '${h}h ${m}m ${s}s';
  }

  double _parseHoursString(String timeStr) {
    if (timeStr.isEmpty || timeStr == '0.0') return 0.0;
    try {
      final parts = timeStr.split(':');
      if (parts.length == 3) {
        final hours = int.tryParse(parts[0]) ?? 0;
        final minutes = int.tryParse(parts[1]) ?? 0;
        final seconds = int.tryParse(parts[2]) ?? 0;
        return hours + (minutes / 60) + (seconds / 3600);
      }
    } catch (_) {}
    return 0.0;
  }

  int _calculateWorkingDaysExcludingSunday() {
    int days = 0;
    var curr = DateTime(_startDate.year, _startDate.month, _startDate.day);
    var end = DateTime(_endDate.year, _endDate.month, _endDate.day);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    if (end.isAfter(yesterday)) end = DateTime(yesterday.year, yesterday.month, yesterday.day);

    while (curr.isBefore(end) || curr.isAtSameMomentAs(end)) {
      if (curr.weekday != DateTime.sunday) {
        days++;
      }
      curr = curr.add(const Duration(days: 1));
    }
    return days;
  }

  int _calculateWorkingDaysExcludingSundayFromTo(DateTime startDate, DateTime endDate) {
    int days = 0;
    var curr = DateTime(startDate.year, startDate.month, startDate.day);
    var end = DateTime(endDate.year, endDate.month, endDate.day);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    if (end.isAfter(yesterday)) end = DateTime(yesterday.year, yesterday.month, yesterday.day);

    while (curr.isBefore(end) || curr.isAtSameMomentAs(end)) {
      if (curr.weekday != DateTime.sunday) {
        days++;
      }
      curr = curr.add(const Duration(days: 1));
    }
    return days;
  }

  int _calculateWorkingDays() {
    int days = 0;
    var curr = DateTime(_startDate.year, _startDate.month, _startDate.day);
    var end = DateTime(_endDate.year, _endDate.month, _endDate.day);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    if (end.isAfter(yesterday)) end = DateTime(yesterday.year, yesterday.month, yesterday.day);

    while (curr.isBefore(end) || curr.isAtSameMomentAs(end)) {
      days++;
      curr = curr.add(const Duration(days: 1));
    }
    return days;
  }

  void _onDateRangeChanged(DateRangeFilter range) {
    setState(() {
      _startDate = range.startDate;
      _endDate = range.endDate;
    });
    _generateReport();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: AppTheme.primaryBlue),
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildHeaderBar(isDark),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildReportHeaderCard(isDark),
                          SizedBox(height: 16.h),
                          DateRangeSelector(
                            initialRange: DateRangeFilter.custom(_startDate, _endDate),
                            onDateRangeSelected: _onDateRangeChanged,
                          ),
                          SizedBox(height: 16.h),
                          _buildActionButtons(isDark),
                          SizedBox(height: 20.h),
                          if (_reportData.isEmpty)
                            _buildEmptyState(isDark)
                          else
                            _buildTable(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.03),
          ],
        ),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
            width: 1.5,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_rounded, size: 24.sp),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📊 Institute Report',
                  style: TextStyle(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.textDark,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Attendance Summary',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportHeaderCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
          width: 1.5,
        ),
      ),
      padding: EdgeInsets.all(14.w),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue.withOpacity(0.3),
                  AppTheme.primaryBlue.withOpacity(0.15),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.assessment_rounded, color: AppTheme.primaryBlue, size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _instituteName ?? 'Institute Report',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  '${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDark) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlue.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(_reportData.isEmpty ? 0 : 0.3),
                blurRadius: 12,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_isLoading || _reportData.isEmpty) ? null : _exportPDF,
              borderRadius: BorderRadius.circular(12.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'Export as PDF',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryGreen,
                AppTheme.primaryGreen.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withOpacity(_reportData.isEmpty ? 0 : 0.3),
                blurRadius: 12,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: (_isLoading || _reportData.isEmpty) ? null : _shareInstituteReportPdf,
              borderRadius: BorderRadius.circular(12.r),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 12.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.share_rounded, color: Colors.white, size: 20.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'Share Report',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 48.h, horizontal: 20.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.04),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.04 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            '📋',
            style: TextStyle(fontSize: 48.sp),
          ),
          SizedBox(height: 16.h),
          Text(
            'No Data Available',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'No attendance records found for the selected date range',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              color: isDark ? Colors.white70 : AppTheme.textGray,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final nameByRoll = _reportData['nameByRoll'] as Map<String, String>;
    final srNoByRoll = _reportData['srNoByRoll'] as Map<String, String>;
    final presentCount = _reportData['presentCount'] as Map<String, int>;
    final creditedHours = _reportData['creditedHours'] as Map<String, double>;
    final creditedHoursFormatted = _reportData['creditedHoursFormatted'] as Map<String, String>? ?? {};
    final subjectCount = _reportData['subjectCount'] as Map<String, int>;
    final registrationDateByRoll = _reportData['registrationDateByRoll'] as Map<String, String>? ?? {};
    final totalWorkingDays = _reportData['totalWorkingDays'] as int;
    final studentWorkingDaysByRoll = _reportData['studentWorkingDaysByRoll'] as Map<String, int>? ?? {};

    final studentRecords = <Map<String, dynamic>>[];
    double totalAllHours = 0;
    int totalAllPresent = 0;
    int totalAllAbsent = 0;
    int totalAllSubjects = 0;

    final sortedRolls = nameByRoll.keys.toList()..sort((a, b) => (srNoByRoll[a] ?? a).compareTo(srNoByRoll[b] ?? b));

    for (final roll in sortedRolls) {
      final name = nameByRoll[roll]!;
      final present = presentCount[roll] ?? 0;
      final hours = creditedHours[roll] ?? 0.0;
      final subjects = subjectCount[roll] ?? 1;
      // Use per-student working days if available, otherwise fall back to global total
      final workingDaysForStudent = studentWorkingDaysByRoll[roll] ?? totalWorkingDays;
      final absent = (workingDaysForStudent - present).clamp(0, workingDaysForStudent);
      final totalDaysForStudent = present + absent;
      final percent = totalDaysForStudent > 0 ? (present / totalDaysForStudent * 100) : 0.0;

      studentRecords.add({
        'roll': roll,
        'name': name,
        'registered': registrationDateByRoll[roll] ?? '-',
        'subjects': subjects,
        'present': present,
        'absent': absent,
        'totalDays': totalDaysForStudent,
        'totalHours': creditedHoursFormatted[roll] ?? '0h 0m 0s',
        'attendancePercent': percent,
      });

      totalAllHours += hours;
      totalAllPresent += present;
      totalAllAbsent += absent;
      totalAllSubjects += subjects;
    }

    final totalDays = totalAllPresent + totalAllAbsent;
    final totals = {
      'totalDays': totalDays,
      'totalSubjects': totalAllSubjects,
      'totalPresent': totalAllPresent,
      'totalAbsent': totalAllAbsent,
      'totalHours': _formatHours(totalAllHours),
      'totalAttendancePercent': studentRecords.isNotEmpty
          ? (totalAllPresent / (totalAllPresent + totalAllAbsent) * 100)
          : 0.0,
    };

    final avgHrsPerStudent = studentRecords.isNotEmpty ? totalAllHours / studentRecords.length : 0.0;
    final averages = {
      'avgSubjects': studentRecords.isNotEmpty ? totalAllSubjects / studentRecords.length : 0.0,
      'avgPresent': studentRecords.isNotEmpty ? totalAllPresent / studentRecords.length : 0.0,
      'avgAbsent': studentRecords.isNotEmpty ? totalAllAbsent / studentRecords.length : 0.0,
      'avgHours': _formatHours(avgHrsPerStudent),
      'avgAttendancePercent': totals['totalAttendancePercent'],
    };

    return InstituteReportTable(
      studentRecords: studentRecords,
      totals: totals,
      averages: averages,
      periodText: '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}',
      onStudentTap: (s) {},
    );
  }

  String _reportPdfFileName() {
    final from = DateFormat('yyyyMMdd').format(_startDate);
    final to = DateFormat('yyyyMMdd').format(_endDate);
    final safeName = (_instituteName ?? _instituteId ?? 'institute')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'Institute_Report_${safeName}_${from}_$to.pdf';
  }

  Future<Uint8List> _generateReportPdfBytes() {
    return PdfExportService.generateInstituteReport(
      instituteId: _instituteId!,
      instituteName: _instituteName,
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  Future<void> _shareInstituteReportPdf() async {
    if (_instituteId == null || _reportData.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final pdfBytes = await _generateReportPdfBytes();
      final fileName = _reportPdfFileName();

      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF ready. Choose WhatsApp or another app to share.'),
            backgroundColor: AppTheme.primaryGreen,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sharing institute report PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share report: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportPDF() async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);
    try {
      final pdfBytes = await _generateReportPdfBytes();
      final fileName = _reportPdfFileName();

      // 1. Show the layout/print dialog (This is the "View" part)
      // This allows viewing and saving via system dialog regardless of app storage permissions.
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: fileName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Report preview opened. Use the system Save, Share, or Print option to keep a copy.',
            ),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error exporting PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export PDF: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
