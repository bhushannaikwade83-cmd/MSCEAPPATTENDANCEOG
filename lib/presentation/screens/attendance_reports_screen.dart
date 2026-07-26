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
import '../../core/attendance_auto_close_policy.dart';
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/attendance_hours_db_reader.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/error_handler.dart';
import '../../services/institute_realtime_sync_service.dart';
// Institute open/close/holiday removed.
import '../../services/pdf_export_service.dart';
import '../../models/date_range_filter.dart';
import '../../presentation/widgets/date_range_selector.dart';
import '../../presentation/widgets/institute_report_table.dart';

class AttendanceReportsScreen extends StatefulWidget {
  static const routeName = '/attendance-reports';
  final String? instituteId;
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const AttendanceReportsScreen({
    super.key,
    this.instituteId,
    this.initialStartDate,
    this.initialEndDate,
  });

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen>
    with WidgetsBindingObserver {
  static const int _maxRangeDays = 184; // ~6 months
  static const Duration _autoRefreshInterval = Duration(seconds: 5);
  String? _instituteId;
  String? _instituteName;
  List<Map<String, dynamic>> _allInstitutes = [];
  late DateRangeFilter _selectedDateRange;
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

    // ✅ Use passed-in dates if provided, otherwise default to one week
    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      _selectedStartDate = widget.initialStartDate!;
      _selectedEndDate = widget.initialEndDate!;
      _selectedDateRange = DateRangeFilter.custom(_selectedStartDate, _selectedEndDate);
      if (kDebugMode) {
        debugPrint('📅 AttendanceReportsScreen: Using provided dates - '
            '${_selectedStartDate.toIso8601String()} to ${_selectedEndDate.toIso8601String()}');
      }
    } else {
      _selectedDateRange = DateRangeFilter.oneWeek();
      _selectedStartDate = _selectedDateRange.startDate;
      _selectedEndDate = _selectedDateRange.endDate;
    }

    // ✅ Use provided instituteId if available
    if (widget.instituteId != null && widget.instituteId!.isNotEmpty) {
      _instituteId = widget.instituteId;
      if (kDebugMode) debugPrint('📊 AttendanceReportsScreen: Using provided instituteId: $_instituteId');

      // Auto-load institute report when accessed from navbar with instituteId
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        setState(() => _reportMode = 'all');
        await _generateReport();
      });
    }

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
    // ✅ OPTIMIZATION: Only auto-refresh if user hasn't scrolled in last 30 seconds
    // This prevents unnecessary report regeneration while viewing data
    // Real-time sync still updates on new attendance
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || _instituteId == null || _isLoading || _reportData.isEmpty) return;
      // Only refresh if data is older than 2 minutes
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

  void _onDateRangeChanged(DateRangeFilter newRange) {
    // ✅ Cancel auto-refresh while generating new report
    _autoRefreshTimer?.cancel();
    setState(() {
      _selectedDateRange = newRange;
      _selectedStartDate = newRange.startDate;
      _selectedEndDate = newRange.endDate;
    });
    _generateReport();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) return;

      final row = await appDb
          .from('profiles')
          .select('institute_id, institutes(name)')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      final iid = row?['institute_id'] as String?;
      final iName = (row?['institutes'] as Map?)?['name'] as String?;

      if (iid != null && iid.isNotEmpty) {
        // Load current institute
        setState(() {
          _instituteId = iid;
          _instituteName = iName;
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

        // ✅ OPTIMIZATION: Don't load all 3000 institutes - only load current institute
        // Multi-institute reports not needed for this screen
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

  int _calculateWorkingDays(DateTime start, DateTime end) {
    int days = 0;
    var curr = DateTime(start.year, start.month, start.day);
    var endLimit = DateTime(end.year, end.month, end.day);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayObj = DateTime(yesterday.year, yesterday.month, yesterday.day);
    if (endLimit.isAfter(yesterdayObj)) endLimit = yesterdayObj;

    while (curr.isBefore(endLimit) || curr.isAtSameMomentAs(endLimit)) {
      days++;
      curr = curr.add(const Duration(days: 1));
    }
    return days;
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
      final studentIds = allStudents.map((s) => (s['id'] as String)).toList();

      // Load attendance records for ONLY these institute's students
      List<dynamic> rows = [];
      if (studentIds.isNotEmpty) {
        rows = await appDb
            .from('attendance_in_out')
            .select()
            .inFilter('student_id', studentIds)
            .gte('attendance_date', startDateStr)
            .lte('attendance_date', endDateStr);
      }

      if (kDebugMode) print('🔍 REPORT: Fetched ${rows.length} records from $startDateStr to $endDateStr');

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

          // ✅ Performance: Only log for first student in debug mode
          if (kDebugMode && rollNumber == '1') {
            debugPrint('📝 Student $rollNumber on $date: rows=${list.length}, PRESENT=$isPresent');
          }

          if (isPresent) {
            rollsPresentByDate.putIfAbsent(date, () => <String>{}).add(rollNumber);
            presentDatesByRoll.putIfAbsent(rollNumber, () => <String>{}).add(date);
          }
        }
      }

      if (kDebugMode) print('✅ RESULT: ${rollsPresentByDate.length} students marked present');

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

      if (kDebugMode) debugPrint('📊 TOTAL allStudents from DB: ${allStudents.length}');

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

      if (kDebugMode) {
        debugPrint('📊 UNIQUE nameByRoll keys: ${nameByRoll.length}');
        debugPrint('📊 UNIQUE rollByStudentId keys: ${rollByStudentId.length}');
      }

      // FIX: Remap presentDatesByRoll keys from student_id to roll numbers
      final presentDatesByRollFixed = <String, Set<String>>{};
      for (final entry in presentDatesByRoll.entries) {
        final studentIdOrSrNo = entry.key;
        final roll = rollByStudentId[studentIdOrSrNo] ?? studentIdOrSrNo;
        presentDatesByRollFixed[roll] = entry.value;
        if (kDebugMode) {
          debugPrint('✅ REMAP: $studentIdOrSrNo → $roll (${entry.value.length} days present)');
        }
      }
      // Replace with fixed version
      presentDatesByRoll.clear();
      presentDatesByRoll.addAll(presentDatesByRollFixed);

      // Calculate absent dates for each student (dates they had no record)
      // ✅ Build complete date range from start to end, not just dates with records
      final allDatesInRange = <String>{};
      var current = DateTime(_selectedStartDate.year, _selectedStartDate.month, _selectedStartDate.day);
      final end = DateTime(_selectedEndDate.year, _selectedEndDate.month, _selectedEndDate.day);
      while (current.isBefore(end) || current.isAtSameMomentAs(end)) {
        allDatesInRange.add(DateFormat('yyyy-MM-dd').format(current));
        current = current.add(const Duration(days: 1));
      }

      if (kDebugMode) {
        debugPrint('📅 Complete Date Range: ${allDatesInRange.length} days');
        debugPrint('   From: ${DateFormat('yyyy-MM-dd').format(_selectedStartDate)} To: ${DateFormat('yyyy-MM-dd').format(_selectedEndDate)}');
      }

      final absentDatesByRoll = <String, Set<String>>{};
      // Include all students, even those without records
      for (final roll in nameByRoll.keys) {
        final presentDates = presentDatesByRoll[roll] ?? <String>{};
        absentDatesByRoll[roll] = allDatesInRange.difference(presentDates);
        if (kDebugMode) {
          debugPrint('📊 $roll: present=${presentDates.length}, absent=${absentDatesByRoll[roll]!.length}, total=${allDatesInRange.length}');
          debugPrint('   Present Dates: $presentDates');
          debugPrint('   All Dates in Range: $allDatesInRange');
          debugPrint('   Absent Dates: ${absentDatesByRoll[roll]}');
        }
      }

      final studentAttendanceCount = <String, int>{
        for (final e in presentDatesByRoll.entries) e.key: e.value.length,
      };

      final studentAbsentCount = <String, int>{
        for (final e in absentDatesByRoll.entries) e.key: e.value.length,
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

      // Get subject count for each student
      final Map<String, int> studentSubjectCount = {};
      for (final student in allStudents) {
        final id = student['id'] as String?;
        final userId = student['user_id'] as String?;
        final srNo = student['sr_no'] as String?;
        final key = (userId != null && userId.isNotEmpty) ? userId : (srNo ?? '');

        if (key.isNotEmpty && id != null) {
          final subjects = student['subjects'] as List?;
          studentSubjectCount[key] = (subjects?.length ?? 1).clamp(1, 4);
        }
      }

      // ✅ NEW: Read pre-calculated hours from database instead of calculating
      print('📖 Reading credited hours from database...');
      final studentCreditedHours = await AttendanceHoursDbReader.getStudentCreditedHours(
        studentIds: studentIds,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );

      final dailyCreditedHours = await AttendanceHoursDbReader.getDailyCreditedHours(
        studentIds: studentIds,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );

      final totalCreditedHours = studentCreditedHours.values.fold<double>(0, (a, b) => a + b);

      // ✅ MAP hours from student_id (UUID) to roll number (user_id/sr_no)
      final studentCreditedHoursByRoll = <String, double>{};
      studentCreditedHours.forEach((sid, hrs) {
        final rk = rollByStudentId[sid];
        if (rk != null) {
          studentCreditedHoursByRoll[rk] = hrs;
        }
      });

      if (kDebugMode) {
        debugPrint('📖 Read ${studentCreditedHours.length} students with hours from DB');
        debugPrint('📊 Total credited hours: ${totalCreditedHours.toStringAsFixed(2)}h');
      }

      final totalWorkingDays = _calculateWorkingDays(_selectedStartDate, _selectedEndDate);

      if (!mounted) return;

      // ✅ Use complete date range length, not just dates with records
      final totalDays = allDatesInRange.length;
      final totalAbsent = totalDays > totalPresent ? (totalDays - totalPresent) : 0;

      if (kDebugMode) {
        debugPrint('📈 SUMMARY: $totalPresent present + $totalAbsent absent = $totalDays total days');
      }

      setState(() {
        _reportData = {
          'dailyPresent': dailyPresent,
          'dailyTotal': dailyTotal,
          'holidayReasons': holidayReasons,
          'dailyCreditedHours': dailyCreditedHours,
          'studentsByDate': studentsByDate,
          'studentAttendanceCount': studentAttendanceCount,
          'studentAbsentCount': studentAbsentCount,
          'studentCreditedHours': studentCreditedHoursByRoll,
          'rollByStudentId': rollByStudentId,
          'nameByRoll': nameByRoll,
          'srNoByRoll': srNoByRoll,
          'studentSubjectCount': studentSubjectCount,
          'totalDays': totalDays,
          'totalPresent': totalPresent,
          'totalAbsent': totalAbsent,
          'totalRecords': totalRecords,
          'totalCreditedHours': totalCreditedHours,
          'totalWorkingDays': totalWorkingDays,
          'averageAttendance': totalRecords > 0 ? (totalPresent / totalRecords * 100) : 0.0,
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

  Future<Map<String, String>> _loadHolidayReasons(String startDate, String endDate) async {
    // Holiday system removed.
    return <String, String>{};
  }

  // ✅ NOTE: _calculateCreditedHours() removed - hours are now calculated and stored in database
  // Report reads pre-calculated hours from database using AttendanceHoursDbReader

  /// ✅ Show all students report dialog with two options
  Future<void> _showAllStudentsReport() async {
    if (_instituteId == null) return;

    // Use selected date range
    final startDate = _selectedStartDate;
    final endDate = _selectedEndDate;
    final periodText = '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}';

    showDialog(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('📊 All Students Attendance Report'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Institute: $_instituteId',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Period: $periodText',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Report Shows:',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildReportFormatItem('✓ SR No | Student Name | Subjects | Present | Absent'),
                    _buildReportFormatItem('✓ Total Hours (Xh Ym 0s format)'),
                    _buildReportFormatItem('✓ Attendance % with status'),
                    _buildReportFormatItem('✓ TOTAL and AVERAGE rows'),
                    _buildReportFormatItem('✓ All students for selected period'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showStudentReportDetails(startDate, endDate);
            },
            icon: const Icon(Icons.preview),
            label: const Text('View Report'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _exportStudentReportAsPDF(startDate, endDate);
            },
            icon: const Icon(Icons.download),
            label: const Text('Download PDF'),
          ),
        ],
      ),
    );
  }

  /// Build report format item
  Widget _buildReportFormatItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// Generate student report
  Future<void> _generateStudentReport(DateTime startDate, DateTime endDate) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📊 Generating student report...'),
        backgroundColor: AppTheme.primaryBlue,
        duration: Duration(seconds: 3),
      ),
    );

    try {
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        _showStudentReportDetails(startDate, endDate);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error generating report: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    }
  }

  /// Export individual student PDF report
  Future<void> _exportIndividualStudentPDF(DateTime startDate, DateTime endDate, String srNo) async {
    if (!mounted || _instituteId == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('📄 Generating PDF for student $srNo...'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      final pdfBytes = await PdfExportService.generateStudentReport(
        instituteId: _instituteId!,
        instituteName: _instituteName,
        srNo: srNo,
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) return;
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// ✅ Export student report as PDF
  Future<void> _exportStudentReportAsPDF(DateTime startDate, DateTime endDate) async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📄 Generating PDF report...'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Create PDF document
      final pdf = pw.Document();

      // Get report data from _reportData
      final totalCount = _reportData['totalCount'] as int? ?? 0;
      final totalCreditedHours = _reportData['totalCreditedHours'] as double? ?? 0.0;
      final studentCreditedHours = _reportData['studentCreditedHours'] as Map? ?? {};
      final studentAttendanceCount = _reportData['studentAttendanceCount'] as Map? ?? {};
      final nameByRoll = _reportData['nameByRoll'] as Map? ?? {};
      final srNoByRoll = _reportData['srNoByRoll'] as Map? ?? {};

      // Build students list from actual data for PDF
      List<Map<String, dynamic>> students = [];
      double maxHours = 0;
      double minHours = double.infinity;

      for (final rollEntry in nameByRoll.entries) {
        final roll = rollEntry.key;
        final name = rollEntry.value;
        final creditedHours = (studentCreditedHours[roll] as num?)?.toDouble() ?? 0.0;
        final presentDays = (studentAttendanceCount[roll] as int?) ?? 0;

        students.add({
          'srNo': srNoByRoll[roll] ?? roll,
          'name': name,
          'totalHours': creditedHours,
          'presentCount': presentDays,
        });

        if (creditedHours > maxHours) maxHours = creditedHours;
        if (creditedHours < minHours && creditedHours > 0) minHours = creditedHours;
      }

      if (minHours == double.infinity) minHours = 0;
      final avgHours = students.isNotEmpty && totalCreditedHours > 0 ? totalCreditedHours / students.length : 0.0;
      final totalHours = totalCreditedHours;

      // Build PDF content
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Center(
                  child: pw.Text(
                    'ATTENDANCE REPORT',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text(
                    'Student Total Hours Report',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),

                // Report Details
                pw.Text(
                  'Report Details',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Institute ID: $_instituteId',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Period: ${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Total Students: $totalCount',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),

                // Student Table
                pw.Text(
                  'Student Attendance Summary',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.6),
                    1: const pw.FlexColumnWidth(2.0),
                    2: const pw.FlexColumnWidth(1.0),
                    3: const pw.FlexColumnWidth(0.7),
                    4: const pw.FlexColumnWidth(0.7),
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'SR No.',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Student Name',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Total Hours',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Present',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            'Absent',
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                    // Data rows
                    ...students.take(30).map((student) {
                      final srNo = (student['srNo'] ?? 'N/A').toString();
                      final name = (student['name'] ?? 'Unknown').toString();
                      final hours = (student['totalHours'] as num?)?.toStringAsFixed(1) ?? '0.0';
                      final presentDays = (student['presentCount'] as int?) ?? 0;
                      // Find the corresponding roll number to get absent count from actual data
                      final rollKey = srNoByRoll.entries
                          .firstWhere((e) => e.value == srNo, orElse: () => const MapEntry('', ''))
                          .key;
                      final absentDays = rollKey.isNotEmpty
                          ? ((_reportData['studentAbsentCount'] as Map?)?[rollKey] as int?) ?? 0
                          : 0;

                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(srNo, style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('${hours}h', style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('$presentDays', style: const pw.TextStyle(fontSize: 9)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(4),
                            child: pw.Text('$absentDays', style: const pw.TextStyle(fontSize: 9)),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
                pw.SizedBox(height: 16),

                // Summary Statistics
                pw.Text(
                  'Summary Statistics',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Average Hours: ${avgHours.toStringAsFixed(2)}h',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Highest: ${maxHours.toStringAsFixed(1)}h',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Lowest: ${minHours.toStringAsFixed(1)}h',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        'Total Hours: ${totalHours.toStringAsFixed(1)}h',
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),

                // Footer
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Text(
                  'This is an automatically generated report from EduSetu Attendance System',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
                ),
              ],
            );
          },
        ),
      );

      // Save PDF to Documents or Downloads folder
      Directory? output = await getDownloadsDirectory();
      output ??= await getApplicationDocumentsDirectory();

      if (output == null) throw Exception('No directory available to save PDF');

      final fileName =
          'student_report_${DateFormat('dd_MM_yyyy_HH_mm_ss').format(DateTime.now())}.pdf';
      final file = File('${output.path}/$fileName');

      await file.writeAsBytes(await pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ PDF Report Generated\n'
              'File: $fileName\n'
              'Location: Downloads folder',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ PDF Export Failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show detailed student report with formatted table (USING ACTUAL DATA)
  void _showStudentReportDetails(DateTime startDate, DateTime endDate) {
    // Get data from _reportData
    final nameByRoll = (_reportData['nameByRoll'] as Map?) ?? {};
    final srNoByRoll = (_reportData['srNoByRoll'] as Map?) ?? {};
    final studentAttendanceCount = (_reportData['studentAttendanceCount'] as Map?) ?? {};
    final studentCreditedHours = (_reportData['studentCreditedHours'] as Map?) ?? {};
    final studentSubjectCount = (_reportData['studentSubjectCount'] as Map?) ?? {};
    final dailyTotal = (_reportData['dailyTotal'] as Map?) ?? {};
    final reportTotalCreditedHours = (_reportData['totalCreditedHours'] as num?)?.toDouble() ?? 0.0;

    if (kDebugMode) {
      debugPrint('📊 _showStudentReportDetails: Reading ${studentCreditedHours.keys.length} students, ${nameByRoll.keys.length} names');
    }

    // Build student records from actual attendance data
    // ✅ IMPORTANT: Include ALL students, not just those with attendance records
    final List<Map<String, dynamic>> studentRecords = [];
    int totalPresent = 0;
    int totalAbsent = 0;
    double totalAllHours = 0;

    // Get all students from nameByRoll (already has all students from data generation)
    // Plus any students in allStudents that aren't in nameByRoll (those with no records)
    final allStudentsWithRoll = Map<String, String>.from(nameByRoll);

    // Add students with no attendance records
    for (final rollEntry in srNoByRoll.entries) {
      final roll = rollEntry.key;
      if (!allStudentsWithRoll.containsKey(roll)) {
        // Find name from studentNames or use sr_no as fallback
        final name = nameByRoll[roll] ?? rollEntry.value;
        allStudentsWithRoll[roll] = name;
      }
    }

    // Loop through ALL students (even those with no attendance records)
    for (final rollEntry in allStudentsWithRoll.entries) {
      final roll = rollEntry.key as String;
      final name = rollEntry.value as String? ?? 'Unknown';

      final present = (studentAttendanceCount[roll] as int?) ?? 0;
      final absentValue = (_reportData['studentAbsentCount'] as Map?)?[roll];
      final absent = (absentValue is int ? absentValue : 0) as int;

      if (kDebugMode) {
        debugPrint('📋 Dialog Report - $roll: present=$present, absent=$absent');
      }

      // Get credited hours (read from database via _reportData)
      // Students with no records will have 0 hours
      final creditedHours = (studentCreditedHours[roll] as num?)?.toDouble() ?? 0.0;
      final subjectCount = (studentSubjectCount[roll] as int?) ?? 1;

      final attendancePercent = (present + absent) > 0
          ? (present / (present + absent)) * 100
          : 0.0;

      studentRecords.add({
        'name': name,
        'subjects': subjectCount,
        'present': present,
        'absent': absent,
        'totalHours': formatCreditedHoursHMS(creditedHours),
        'attendancePercent': attendancePercent,
      });

      totalPresent += present;
      totalAbsent += absent;
      totalAllHours += creditedHours;
    }

    // Sort by name
    studentRecords.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

    // Calculate totals
    final studentCount = studentRecords.length;

    // ✅ Use pre-calculated reportTotalCreditedHours (read from _reportData which got it from database)
    final totals = {
      'totalSubjects': studentRecords.fold<int>(0, (sum, s) => sum + (s['subjects'] as int? ?? 0)),
      'totalPresent': totalPresent,
      'totalAbsent': totalAbsent,
      'totalHours': formatCreditedHoursHMS(reportTotalCreditedHours),
      'totalAttendancePercent': totalPresent + totalAbsent > 0
          ? (totalPresent / (totalPresent + totalAbsent)) * 100
          : 0.0,
    };

    final averages = {
      'avgSubjects': studentCount > 0 ? (totals['totalSubjects'] as int) / studentCount : 0.0,
      'avgPresent': studentCount > 0 ? totalPresent / studentCount : 0.0,
      'avgAbsent': studentCount > 0 ? totalAbsent / studentCount : 0.0,
      'avgHours': studentCount > 0 ? formatCreditedHoursHMS(totalAllHours / studentCount) : '0h 0m 0s',
      'avgAttendancePercent': totals['totalAttendancePercent'],
    };

    final periodText = '${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}';

    if (kDebugMode) {
      debugPrint('✅ REPORT: ${studentRecords.length} students | Total Hours: ${totals['totalHours']} (from database)');
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📋 Institute Attendance Report'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: SingleChildScrollView(
            child: InstituteReportTable(
              studentRecords: studentRecords,
              totals: totals,
              averages: averages,
              periodText: periodText,
              onStudentTap: (student) {
                // Find the sr_no for this student
                final studentName = student['name'] as String;
                final studentSrNo = srNoByRoll.entries
                    .firstWhere(
                      (e) => e.value == studentName,
                      orElse: () => const MapEntry('', ''),
                    )
                    .key;

                if (studentSrNo.isNotEmpty) {
                  Navigator.pop(ctx);
                  _exportIndividualStudentPDF(startDate, endDate, studentSrNo);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _exportStudentReportAsPDF(startDate, endDate);
            },
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Export PDF'),
          ),
        ],
      ),
    );
  }

  /// Format hours as "Xh Ym 0s"
  String _formatHours(double totalHours) {
    final hours = totalHours.toInt();
    final remainingMinutes = ((totalHours - hours) * 60).toInt();
    return '${hours}h ${remainingMinutes}m 0s';
  }

  /// Show success message
  void _showReportSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Report Generated\n'
          'Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}\n'
          'Total Students: ${_reportData['totalCount'] ?? 'N/A'}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            _buildDateRangeSelector(),
            const SizedBox(height: 20),


            // Load All Students button (removed Load Defaulters button)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () async {
                        setState(() => _reportMode = 'all');
                        await _generateReport();
                      },
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.groups_rounded),
                label: const Text('Load All Students'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search student by name or SR No',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => setState(() => _searchQuery = ''),
                        icon: const Icon(Icons.clear),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Show student list or "no students" message
            if (_reportData.isNotEmpty) ...[
              _buildStudentCardList(),
            ],

            // Show "no students" message when button clicked but no students exist
            if (!_isLoading && _reportMode != null && _reportData.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.group_off,
                      size: 48,
                      color: AppTheme.textGray.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '❌ No students in this institute',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accentRed,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Add students to this institute first',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textGray,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            // Only show this message if no button was clicked yet
            if (_reportData.isEmpty && !_isLoading && _reportMode == null)
              Center(
                child: Column(
                  children: [
                    Icon(Icons.analytics_outlined, size: 64, color: AppTheme.textGray),
                    const SizedBox(height: 16),
                    Text(
                      'Select date range and load attendance',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDateRangeSelector() {
    return DateRangeSelector(
      initialRange: _selectedDateRange,
      onDateRangeSelected: _onDateRangeChanged,
    );
  }

  Widget _buildStudentCardList() {
    final nameByRoll = (_reportData['nameByRoll'] as Map?) ?? {};
    final srNoByRoll = (_reportData['srNoByRoll'] as Map?) ?? {};
    final studentAttendanceCount = (_reportData['studentAttendanceCount'] as Map?) ?? {};
    final studentCreditedHours = (_reportData['studentCreditedHours'] as Map?) ?? {};
    final dailyTotal = (_reportData['dailyTotal'] as Map?) ?? {};

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter and sort students
    final List<String> studentRolls = nameByRoll.keys.cast<String>().toList();
    if (_searchQuery.isNotEmpty) {
      studentRolls.removeWhere((roll) {
        final name = nameByRoll[roll]?.toString().toLowerCase() ?? '';
        final sr = srNoByRoll[roll]?.toString().toLowerCase() ?? '';
        return !name.contains(_searchQuery) && !sr.contains(_searchQuery) && !roll.toLowerCase().contains(_searchQuery);
      });
    }

    // Sort by SR No
    studentRolls.sort((a, b) {
      final aSr = srNoByRoll[a] ?? a;
      final bSr = srNoByRoll[b] ?? b;
      return aSr.compareTo(bSr);
    });

    if (studentRolls.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text('No students found matching "$_searchQuery"'),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: studentRolls.length,
      itemBuilder: (context, index) {
        final roll = studentRolls[index];
        final name = nameByRoll[roll] ?? 'Unknown';
        final presentCount = studentAttendanceCount[roll] ?? 0;
        final absentCount = (_reportData['studentAbsentCount'] as Map?)?[roll] ?? 0;
        final totalHours = studentCreditedHours[roll] ?? 0.0;
        final totalDays = presentCount + absentCount;  // Total days with records
        final attendancePercent = totalDays > 0
            ? (presentCount / totalDays * 100)
            : 0.0;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
          ),
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          child: InkWell(
            onTap: () => _openStudentReportActions(rollNumber: roll, studentName: name),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'SR No: ${srNoByRoll[roll] ?? roll}',
                              style: TextStyle(color: AppTheme.textGray, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: attendancePercent >= 75 ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${attendancePercent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: attendancePercent >= 75 ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Present', '$presentCount', Colors.green),
                      _buildMiniStat('Absent', '$absentCount', Colors.red),
                      _buildMiniStat('Total Days', '$totalDays', AppTheme.primaryBlue),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniStat('Total Hours', formatCreditedHoursHMS(totalHours), AppTheme.accentOrange),
                      const SizedBox(width: 12),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: AppTheme.textGray, fontSize: 10)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _buildInstituteReportTable() {
    // This is now redundant here, but I'll leave a stub or just remove it in the next cleanup
    return const SizedBox.shrink();
  }

  Widget _buildExportButtons() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Reports',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _exportAllStudentsPDF,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text(
                    'Export All',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showStudentSelectionDialog,
                  icon: const Icon(Icons.person, size: 18),
                  label: const Text(
                    'Export One',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportAllStudentsPDF() async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);

    try {
      final pdfBytes = await PdfExportService.generateStudentsReport(
        instituteId: _instituteId!,
        instituteName: _instituteName,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
        subject: _selectedSubject,
      );

      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('PDF exported successfully!'),
              ],
            ),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'exportPDF', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showStudentSelectionDialog() async {
    if (_instituteId == null) return;

    final studentRows = await appDb.from('students').select('user_id,name,sr_no').eq('institute_id', _instituteId!);

    if (studentRows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No students found'),
            backgroundColor: AppTheme.accentOrange,
          ),
        );
      }
      return;
    }

    final students = studentRows.map((raw) {
      final data = raw as Map<String, dynamic>;
      return {
        'rollNumber': data['user_id'] as String? ?? data['sr_no'] as String? ?? '',
        'name': data['name'] as String? ?? 'Unknown',
      };
    }).toList();

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select Student'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: students.length,
              itemBuilder: (context, index) {
                final student = students[index];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(student['name'] as String),
                  subtitle: Text('SR No: ${student['rollNumber']}'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportStudentPDF(student['rollNumber'] as String);
                  },
                );
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _exportStudentPDF(String rollNumber) async {
    if (_instituteId == null) return;

    setState(() => _isLoading = true);

    try {
      final pdfBytes = await PdfExportService.generateStudentReport(
        instituteId: _instituteId!,
        instituteName: _instituteName,
        srNo: rollNumber,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );

      if (mounted) {
        await Printing.layoutPdf(
          onLayout: (format) async => pdfBytes,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Student PDF exported successfully!'),
                ),
              ],
            ),
            backgroundColor: AppTheme.primaryGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorResult = ErrorHandler.formatErrorForUI(e, context: 'exportStudentPDF', appType: 'admin');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorResult['message']),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openStudentReportActions({
    required String rollNumber,
    required String studentName,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: AppTheme.primaryBlue),
              title: const Text('View PDF Report'),
              subtitle: Text('$studentName (SR No: $rollNumber)'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _exportStudentPDF(rollNumber);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppTheme.primaryGreen),
              title: const Text('Download / Save to Files'),
              subtitle: const Text('Choose Files in share options'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _downloadStudentReportPdf(
                  rollNumber: rollNumber,
                  studentName: studentName,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadStudentReportPdf({
    required String rollNumber,
    required String studentName,
  }) async {
    if (_instituteId == null) return;
    setState(() => _isLoading = true);
    try {
      final pdfBytes = await PdfExportService.generateStudentReport(
        instituteId: _instituteId!,
        instituteName: _instituteName,
        srNo: rollNumber,
        startDate: _selectedStartDate,
        endDate: _selectedEndDate,
      );
      final from = DateFormat('yyyyMMdd').format(_selectedStartDate);
      final to = DateFormat('yyyyMMdd').format(_selectedEndDate);
      final safeName = studentName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = 'attendance_${safeName}_${rollNumber}_${from}_$to.pdf';
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF ready. Select Files in share sheet to save.'),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final errorResult = ErrorHandler.formatErrorForUI(
        e,
        context: 'downloadStudentPDF',
        appType: 'admin',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorResult['message']),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSummaryCards() {
    final totalPresent = _reportData['totalPresent'] as int? ?? 0;
    final totalRecords = _reportData['totalRecords'] as int? ?? 0;
    final totalDays = _reportData['totalDays'] as int? ?? 0;
    final totalAbsent = (totalDays - totalPresent).clamp(0, totalDays);
    final averageAttendance = _reportData['averageAttendance'] as double? ?? 0.0;
    final totalCreditedHours = _reportData['totalCreditedHours'] as double? ?? 0.0;
    final holidayReasons = _reportData['holidayReasons'] as Map<String, String>? ?? {};
    final totalHoursLabel = totalCreditedHours > 0
        ? formatCreditedHoursHMS(totalCreditedHours)
        : '—';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Days',
                value: '$totalDays',
                color: AppTheme.primaryBlue,
                icon: Icons.calendar_today,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Total Present',
                value: '$totalPresent',
                color: AppTheme.accentGreen,
                icon: Icons.check_circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Total Absent',
                value: '$totalAbsent',
                color: AppTheme.accentOrange,
                icon: Icons.cancel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SummaryCard(
                title: 'Total Records',
                value: '$totalRecords',
                color: AppTheme.primaryGreen,
                icon: Icons.people,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Avg Attendance',
                value: '${averageAttendance.toStringAsFixed(1)}%',
                color: AppTheme.accentOrange,
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SummaryCard(
                title: 'Holidays',
                value: '${holidayReasons.length}',
                color: AppTheme.primaryBlue,
                icon: Icons.beach_access,
              ),
            ),
          ],
        ),
        if (totalCreditedHours > 0) ...[
          const SizedBox(height: 12),
          _SummaryCard(
            title: 'Total credited hours',
            value: totalHoursLabel,
            color: AppTheme.primaryBlue,
            icon: Icons.schedule,
          ),
        ],
      ],
    );
  }

  Widget _buildDailyAttendanceChart() {
    final dailyPresent = _reportData['dailyPresent'] as Map<String, int>? ?? {};
    final dailyTotal = _reportData['dailyTotal'] as Map<String, int>? ?? {};
    final dailyCreditedHours =
        _reportData['dailyCreditedHours'] as Map<String, double>? ?? {};
    final holidayReasons = _reportData['holidayReasons'] as Map<String, String>? ?? {};

    if (dailyPresent.isEmpty && holidayReasons.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedDates = {...dailyPresent.keys, ...holidayReasons.keys}.toList()..sort();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Daily Attendance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          ...sortedDates.map((date) {
            final holidayReason = holidayReasons[date];
            if (holidayReason != null) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accentOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentOrange.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.beach_access, color: AppTheme.accentOrange),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(DateTime.parse(date)),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Holiday: $holidayReason',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.accentOrange,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
            final present = dailyPresent[date] ?? 0;
            final total = dailyTotal[date] ?? 1;
            final percentage = (present / total * 100);
            final creditedHours = dailyCreditedHours[date] ?? 0.0;
            final hoursLabel = creditedHours > 0
                ? formatCreditedHoursHMS(creditedHours)
                : null;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('MMM dd, yyyy').format(DateTime.parse(date)),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$present / $total (${percentage.toStringAsFixed(1)}%)',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                  if (hoursLabel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Credited hours that day: $hoursLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        percentage >= 80 ? AppTheme.accentGreen :
                        percentage >= 60 ? AppTheme.accentOrange :
                        AppTheme.accentRed,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildTopStudents() {
    final studentAttendanceCount = _reportData['studentAttendanceCount'] as Map<String, int>? ?? {};
    final studentCreditedHours =
        _reportData['studentCreditedHours'] as Map<String, double>? ?? {};
    final rollByStudentId = _reportData['rollByStudentId'] as Map<String, String>? ?? {};

    if (studentAttendanceCount.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedStudents = studentAttendanceCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topStudents = sortedStudents.take(10).toList();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top Students by Attendance',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...topStudents.asMap().entries.map((entry) {
            final index = entry.key;
            final student = entry.value;
            final creditedHrs = studentCreditedHours[student.key] ?? 0.0;
            final hoursLine = creditedHrs <= 0
                ? 'Total credited hours: —'
                : 'Total credited hours: ${formatCreditedHoursHMS(creditedHrs)}';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: index < 3
                          ? AppTheme.primaryGreen.withValues(alpha: 0.2)
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: index < 3 ? AppTheme.primaryGreen : AppTheme.textGray,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SR No ${rollByStudentId[student.key] ?? student.key}',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hoursLine,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.primaryBlue,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accentGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${student.value} days',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.accentGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
