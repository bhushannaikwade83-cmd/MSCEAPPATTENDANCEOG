import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/app_db.dart';
import '../../core/attendance_presence_rules.dart';
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/error_handler.dart';
import '../../services/institute_realtime_sync_service.dart';
// Institute open/close/holiday removed.
import '../../services/pdf_export_service.dart';
// ===== NEW IMPORTS FOR DATE RANGE FILTERING =====
import '../../models/date_range_filter.dart';
import '../../presentation/widgets/date_range_selector.dart';
// ===============================================

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  const AttendanceReportsScreen({super.key});

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen>
    with WidgetsBindingObserver {
  static const int _maxRangeDays = 184; // ~6 months
  static const Duration _autoRefreshInterval = Duration(seconds: 5);
  String? _instituteId;
  List<Map<String, dynamic>> _allInstitutes = [];

  // ===== NEW: Date range filtering state =====
  late DateRangeFilter _selectedDateRange;
  // ===========================================

  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _selectedEndDate = DateTime.now();
  String? _selectedSubject = 'All Subjects';
  bool _isLoading = false;
  Map<String, dynamic> _reportData = {};
  String _reportMode = 'all'; // all
  String _searchQuery = '';
  List<Map<String, dynamic>> _defaultersList = []; // Students with 0 attendance
  Timer? _autoRefreshTimer;
  StreamSubscription<InstituteSyncEvent>? _syncSubscription;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ===== NEW: Initialize date range =====
    _selectedDateRange = DateRangeFilter.oneWeek();
    // ======================================

    _loadInstituteId();
  }

  void _handleAppResumed() {
    if (!mounted || _instituteId == null || _isLoading || _reportData.isEmpty) return;
    _generateReport(showLoader: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleAppResumed();
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshInterval, (_) {
      if (!mounted || _instituteId == null || _isLoading || _reportData.isEmpty) return;
      _generateReport(showLoader: false);
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _syncDebounce?.cancel();
    _syncSubscription?.cancel();
    final iid = _instituteId;
    if (iid != null && iid.isNotEmpty) {
      InstituteRealtimeSyncService.instance.release(iid);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ===== NEW: Date range change handler =====
  void _onDateRangeChanged(DateRangeFilter newRange) {
    setState(() {
      _selectedDateRange = newRange;
      // Update the old start/end date variables for compatibility
      _selectedStartDate = newRange.startDate;
      _selectedEndDate = newRange.endDate;
    });
    // Regenerate report with new date range
    _generateReport();
  }
  // ==========================================

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) return;

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final iid = row?['institute_id'] as String?;
      if (iid != null && iid.isNotEmpty) {
        // Load current institute
        setState(() {
          _instituteId = iid;
        });
        await InstituteRealtimeSyncService.instance.retain(iid);
        _syncSubscription?.cancel();
        _syncSubscription = InstituteRealtimeSyncService.instance
            .watch(iid)
            .listen((event) {
          if (!mounted) return;
          if (event.type == 'students' || event.type == 'attendance') {
            _syncDebounce?.cancel();
            _syncDebounce = Timer(const Duration(milliseconds: 600), () {
              if (!mounted) return;
              _generateReport(showLoader: false);
            });
          }
        });

        // Load all institutes for multi-institute report
        await _loadAllInstitutes();
        _generateReport();
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'loadInstituteId');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _loadAllInstitutes() async {
    try {
      final institutes = await appDb
          .from('institutes')
          .select('id, name, institute_code')
          .order('name')
          .limit(8000);
      if (mounted) {
        setState(() {
          _allInstitutes = institutes.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) debugPrint('⚠️ Error loading institutes: $e');
    }
  }

  Future<void> _generateReport({bool showLoader = true}) async {
    if (_instituteId == null) return;

    // Validate date range (max 6 months)
    final daysDifference = _selectedEndDate.difference(_selectedStartDate).inDays;
    if (daysDifference > _maxRangeDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Date range cannot exceed 6 months. Please select a shorter range.'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_selectedEndDate.isBefore(_selectedStartDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('End date must be after start date'),
          backgroundColor: AppTheme.accentRed,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (showLoader) {
      setState(() => _isLoading = true);
    }

    try {
      final startDateStr = DateFormat('yyyy-MM-dd').format(_selectedStartDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(_selectedEndDate);
      // Holiday system removed.
      final holidayReasons = <String, String>{};

      // Load ALL students from THIS institute ONLY
      List<Map<String, dynamic>> allStudents = (await appDb
          .from('students')
          .select('id,institute_id,user_id,sr_no,name')
          .eq('institute_id', _instituteId!))
          .cast<Map<String, dynamic>>();

      // Get student IDs for filtering attendance
      final studentIds = allStudents.map((s) => s['id']).toList();

      // Load attendance records for ONLY these institute's students
      // FILTERED BY DATE RANGE ===
      List<dynamic> rows = [];
      if (studentIds.isNotEmpty) {
        rows = await appDb
            .from('attendance_in_out')
            .select()
            .inFilter('student_id', studentIds)
            .gte('attendance_date', startDateStr)  // Start date filter
            .lte('attendance_date', endDateStr);   // End date filter
      }

      print('🔍 REPORT: Fetched ${rows.length} records from $startDateStr to $endDateStr');
      print('📅 Date Range: ${_selectedDateRange.formatRange()}');
      print('📊 Days in range: ${_selectedDateRange.getDayCount()}');

      // Count one session per student per day (entry + exit are a single attendance, not two).
      final Map<String, Set<String>> rollsAnyByDate = {};
      final Map<String, Set<String>> rollsPresentByDate = {};
      final Map<String, Set<String>> presentDatesByRoll = {};

      final Map<String, Map<String, List<Map<String, dynamic>>>> rollDateRows = {};

      for (final raw in rows) {
        final data = Map<String, dynamic>.from(raw as Map);
        final date = data['attendance_date']?.toString() ?? '';
        if (date.isEmpty) continue;

        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final rollNumber = sid.isNotEmpty ? sid : sr;
        if (rollNumber.isEmpty) continue;

        rollDateRows.putIfAbsent(rollNumber, () => {});
        rollDateRows[rollNumber]!.putIfAbsent(date, () => []).add(data);
      }

      for (final rollEntry in rollDateRows.entries) {
        final rollNumber = rollEntry.key;
        for (final dateEntry in rollEntry.value.entries) {
          final date = dateEntry.key;
          final list = dateEntry.value;
          rollsAnyByDate.putIfAbsent(date, () => <String>{}).add(rollNumber);

          final isPresent = studentDayPresentFromInOutRows(list);

          print('📝 $rollNumber on $date: rows=${list.length}, PRESENT=$isPresent');

          if (isPresent) {
            rollsPresentByDate.putIfAbsent(date, () => <String>{}).add(rollNumber);
            presentDatesByRoll.putIfAbsent(rollNumber, () => <String>{}).add(date);
          }
        }
      }

      print('✅ RESULT: ${rollsPresentByDate.length} students marked present');

      final dailyPresent = <String, int>{};
      final dailyTotal = <String, int>{};
      for (final date in rollsAnyByDate.keys) {
        dailyTotal[date] = rollsAnyByDate[date]!.length;
        dailyPresent[date] = rollsPresentByDate[date]?.length ?? 0;
      }

      final studentsByDate = rollsPresentByDate;

      var totalPresent = 0;
      var totalRecords = 0;
      for (final date in rollsAnyByDate.keys) {
        totalRecords += rollsAnyByDate[date]!.length;
        totalPresent += rollsPresentByDate[date]?.length ?? 0;
      }

      // ✅ Use allStudents loaded above (multi-institute support)
      final rollByStudentId = <String, String>{};
      final nameByRoll = <String, String>{};
      final srNoByRoll = <String, String>{};
      final studentInstituteMap = <String, String>{}; // track which institute each student belongs to

      print('📊 TOTAL allStudents from DB: ${allStudents.length}');

      for (final m in allStudents) {
        final id = m['id'] as String?;
        if (id == null) continue;
        final u = m['user_id'] as String?;
        final sr = m['sr_no'] as String?;
        final iid = m['institute_id'] as String?;
        final rk = (u != null && u.isNotEmpty) ? u : (sr ?? '');
        final nm = m['name']?.toString().trim() ?? '';
        if (rk.isNotEmpty) {
          rollByStudentId[id] = rk;
          if (nm.isNotEmpty) nameByRoll[rk] = nm;
          if (sr != null && sr.trim().isNotEmpty) {
            srNoByRoll[rk] = sr.trim();
          }
          if (iid != null) {
            studentInstituteMap[rk] = iid;
          }
        }
      }

      print('📊 UNIQUE nameByRoll keys: ${nameByRoll.length}');
      print('📊 UNIQUE rollByStudentId keys: ${rollByStudentId.length}');

      // FIX: Remap presentDatesByRoll keys from student_id to roll numbers
      final presentDatesByRollFixed = <String, Set<String>>{};
      for (final entry in presentDatesByRoll.entries) {
        final studentIdOrSrNo = entry.key;
        final roll = rollByStudentId[studentIdOrSrNo] ?? studentIdOrSrNo;
        presentDatesByRollFixed[roll] = entry.value;
        print('✅ REMAP: $studentIdOrSrNo → $roll (${entry.value.length} days present)');
      }
      // Replace with fixed version
      presentDatesByRoll.clear();
      presentDatesByRoll.addAll(presentDatesByRollFixed);

      final studentAttendanceCount = <String, int>{
        for (final e in presentDatesByRoll.entries) e.key: e.value.length,
      };

      final Map<String, List<Map<String, dynamic>>> rawByStudent = {};
      for (final raw in rows) {
        final data = raw as Map<String, dynamic>;
        final sid = (data['student_id'] as String?)?.trim() ?? '';
        final sr = (data['sr_no'] as String?)?.trim() ?? '';
        final key = sid.isNotEmpty ? sid : sr;
        if (key.isEmpty) continue;
        rawByStudent.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(data));
      }

      final dailySeatedSeconds = <String, int>{};
      final studentSeatedSeconds = <String, int>{};
      for (final e in rawByStudent.entries) {
        final merged = PdfExportService.mergeAttendanceInOutRowsByDate(e.value);
        for (final day in merged) {
          final date = day['date'] as String? ?? '';
          if (date.isEmpty) continue;
          final dur = seatedDurationFromMergedAttendanceDay(day);
          if (dur == null || dur <= Duration.zero) continue;
          final sec = dur.inSeconds;
          dailySeatedSeconds[date] = (dailySeatedSeconds[date] ?? 0) + sec;
          studentSeatedSeconds[e.key] = (studentSeatedSeconds[e.key] ?? 0) + sec;
        }
      }

      final totalSeatedSeconds = dailySeatedSeconds.values.fold<int>(0, (a, b) => a + b);

      if (!mounted) return;

      setState(() {
        _reportData = {
          'dailyPresent': dailyPresent,
          'dailyTotal': dailyTotal,
          'holidayReasons': holidayReasons,
          'dailySeatedSeconds': dailySeatedSeconds,
          'studentsByDate': studentsByDate,
          'studentAttendanceCount': studentAttendanceCount,
          'studentSeatedSeconds': studentSeatedSeconds,
          'rollByStudentId': rollByStudentId,
          'nameByRoll': nameByRoll,
          'srNoByRoll': srNoByRoll,
          'totalPresent': totalPresent,
          'totalRecords': totalRecords,
          'totalSeatedSeconds': totalSeatedSeconds,
          'averageAttendance': totalRecords > 0 ? (totalPresent / totalRecords * 100) : 0.0,
          // NEW: Add date range info to report data
          'dateRange': _selectedDateRange.formatRange(),
          'dayCount': _selectedDateRange.getDayCount(),
        };
        _isLoading = false;
      });
      _startAutoRefresh();
    } catch (e) {
      if (!mounted) return;
      if (showLoader || _isLoading) {
        setState(() => _isLoading = false);
      }
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'generateReport', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  void _applyQuickRange(int months) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = DateTime(end.year, end.month - months, end.day + 1);
    setState(() {
      _selectedStartDate = start;
      _selectedEndDate = end;
    });
    _generateReport();
  }

  Future<Map<String, String>> _loadHolidayReasons(String startDate, String endDate) async {
    // Holiday system removed.
    return <String, String>{};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Reports'),
        elevation: 0,
        centerTitle: false,
        backgroundColor: AppTheme.primaryBlue,
      ),
      body: _reportData.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // ===== NEW: Date Range Selector Widget =====
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: DateRangeSelector(
                      initialRange: _selectedDateRange,
                      onDateRangeSelected: _onDateRangeChanged,
                    ),
                  ),

                  // Divider
                  Divider(
                    height: 1,
                    color: Colors.grey[300],
                  ),
                  // =============================================

                  // Report header info
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attendance Summary',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Date Range: ${_reportData['dateRange'] ?? "N/A"}',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: 12.h),
                        // Summary stats
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                label: 'Total Present',
                                value: '${_reportData['totalPresent'] ?? 0}',
                                color: AppTheme.primaryGreen,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: _buildStatCard(
                                label: 'Average',
                                value: '${(_reportData['averageAttendance'] ?? 0).toStringAsFixed(1)}%',
                                color: AppTheme.primaryBlue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Existing report content continues here...
                  // (Your existing build code goes here)
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            value,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
