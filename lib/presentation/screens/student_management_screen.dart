import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/root_navigator.dart' show rootNavigatorKey, scaffoldMessengerOr;
import '../../core/supabase_maps.dart';
import '../../core/time_parse.dart';
import '../../core/utils/responsive.dart';
import '../../config/supabase_env.dart';

import '../../core/student_face_embedding_utils.dart';
import '../../core/attendance_presence_rules.dart';
import '../../core/attendance_auto_close_policy.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/shimmer_effect.dart';
import '../widgets/enhanced_animations.dart';
import '../widgets/empty_state.dart';
import 'login_screen.dart';
import 'staff_attendance_portal_screen.dart';
import 'student_photos_screen.dart';
import 'instructions_screen.dart';
import '../../services/stale_attendance_reconciliation_service.dart';
import '../../services/session_manager.dart';
import '../../services/shared_stats_service.dart';
import '../../services/pin_session_manager.dart';
import '../../services/location_monitor_service.dart' show LocationVerificationService;
import '../widgets/secure_network_image.dart';
import '../../services/distance_check_service.dart';
import 'auto_face_scan_screen.dart';
import 'student_face_registration_wrapper.dart';
import 'live_anti_spoof_camera_screen.dart';

enum _StudentAttendanceFilter { all, present, absent }

class StudentManagementScreen extends StatefulWidget {
  static const routeName = '/student-management';

  /// When true, shows the same UI as in admin main nav, but for `attendance_user`:
  /// sign-out control, no system back to leave the portal (use Sign out).
  final bool forAttendanceStaffPortal;

  const StudentManagementScreen({
    super.key,
    this.forAttendanceStaffPortal = false,
  });

  @override
  State<StudentManagementScreen> createState() =>
      _StudentManagementScreenState();
}

class _StudentManagementScreenState extends State<StudentManagementScreen>
    with TickerProviderStateMixin {
  String? _instituteId;
  String? _instituteName;
  bool _isLoadingInstitute = true;

  // Search with debounce (server-side)
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Paginated student list state (server-side range; scroll loads next page)
  static const int _pageSize = 20;
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingStudents = false;
  bool _isLoadingMore = false;
  List<Map<String, dynamic>> _students = [];
  int _studentCount = 0;
  final ScrollController _scrollController = ScrollController();
  _StudentAttendanceFilter _attendanceFilter = _StudentAttendanceFilter.all;

  /// Omit `face_embedding` / `photo_thumbnail` — they are large JSON and slow every list page.
  static const String _studentSelectCols =
      'id,sr_no,fname,lname,mname,sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8,form_serial_no,mother_nm,ctcd,identy_no,face_photo_url,face_embedding_front,face_embedding_left,face_embedding_right,face_registered_at,face_registration_status,is_face_real,created_at,updated_at';

  /// Today's entry/exit UI state keyed by [students.id] only (avoids roll/userId collisions).
  Map<String, Map<String, dynamic>> _todayPayloadByStudentId = {};

  /// 🔄 Cache for fresh subjects fetched from database (not stale display data)
  /// Maps student srNo/userId to their current subjects
  final Map<String, List<String>> _freshSubjectsCache = {};

  /// Selected subject on each row for per-subject entry / exit.

  static const Color _exitAttendanceMarkColor = Color(0xFFFFC107);

  Timer? _timerUpdateTimer;  // ✅ Periodic timer to update countdown

  int _statsTotal = 0;
  int _statsPresentToday = 0;
  int _statsAbsentToday = 0;
  RealtimeChannel? _studentsChannel;
  RealtimeChannel? _attendanceChannel;
  Timer? _realtimeRefreshDebounce;
  // ✅ Auto-refresh stats every 2 seconds for real-time sync
  Timer? _statsRefreshTimer;

  String _supabaseHostForLogs() {
    try {
      return Uri.parse(SupabaseEnv.url).host;
    } catch (_) {
      return 'unknown-host';
    }
  }

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  AnimationController? _statsAnimController;
  Animation<double>? _statsScaleAnimation;

  // Photo gallery view toggle (#5)
  bool _photoGridViewEnabled = false;

  // Error state tracking (#9)
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fadeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    // Stats animation (#7)
    _statsAnimController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _statsScaleAnimation =
        CurvedAnimation(parent: _statsAnimController!, curve: Curves.elasticOut);
    _statsAnimController?.forward();
    _loadInstituteId();
    // ✅ Setup stats auto-refresh (2 sec interval for real-time sync)
    _setupStatsAutoRefresh();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);

    // ⏱️ Live countdown for entry->exit allotted-hours timer on student cards
    _timerUpdateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});  // Rebuild to recalculate remaining time
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _statsAnimController?.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    _realtimeRefreshDebounce?.cancel();
    _timerUpdateTimer?.cancel();  // ✅ Cancel timer countdown
    // _statsRefreshTimer already disabled - no cleanup needed
    if (_studentsChannel != null) appDb.removeChannel(_studentsChannel!);
    if (_attendanceChannel != null) appDb.removeChannel(_attendanceChannel!);
    _scrollController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = _sanitizeStudentSearchToken(_searchController.text);
      if (q == _searchQuery) return;
      setState(() {
        _searchQuery = q;
        _page = 0;
        _students.clear();
        _hasMore = true;
      });
      _loadStudents(reset: true);
    });
  }

  void _onScroll() {
    // Auto-scroll pagination disabled - use manual "Load More" button instead
    // This prevents loading multiple pages automatically when list fits on screen
    // User must explicitly click "Load More" to load next batch
  }

  static String _formatSrDisplay(String? sr) {
    final s = (sr ?? '').trim();
    if (s.isEmpty) return '—';
    final n = int.tryParse(s);
    if (n != null) return n.toString().padLeft(3, '0');
    return s;
  }

  /// PostgREST `.or()` splits on commas; user `%` / `_` widen ilike patterns.
  static String _sanitizeStudentSearchToken(String raw) {
    var s = raw.trim().replaceAll(',', ' ');
    s = s.replaceAll(RegExp(r'[%_]'), '');
    return s.trim();
  }

  /// Server-side match across common student columns (institute already scoped).
  static String? _studentSearchOrFilter(String rawQuery) {
    final q = _sanitizeStudentSearchToken(rawQuery);
    if (q.isEmpty) return null;
    const cols = [
      'name',
      'user_id',
      'sr_no',
      'year',
    ];
    return cols.map((c) => '$c.ilike.%$q%').join(',');
  }

  /// Collapse duplicate DB rows (same roll / auth id) in the visible list.
  static String _studentRowDedupeKey(Map<String, dynamic> mapped) {
    final id = mapped['id']?.toString().trim() ?? '';
    final uid = mapped['userId']?.toString().trim() ?? '';
    final sr = mapped['srNo']?.toString().trim() ?? '';
    if (sr.isNotEmpty) return 's:$sr';
    if (uid.isNotEmpty) return 'u:$uid';
    return 'id:$id';
  }

  static List<Map<String, dynamic>> _dedupeMergedStudents(
    List<Map<String, dynamic>> list,
  ) {
    final keys = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final s in list) {
      final k = _studentRowDedupeKey(s);
      if (keys.contains(k)) continue;
      keys.add(k);
      out.add(s);
    }
    return out;
  }

  List<String> _attendanceLookupKeysForStudent(Map<String, dynamic> student) {
    final userId = student['userId']?.toString().trim() ?? '';
    final srNo = student['srNo']?.toString().trim() ?? '';
    final keys = <String>[];
    if (srNo.isNotEmpty) keys.add(srNo);
    if (keys.isEmpty && userId.isNotEmpty) keys.add(userId);
    return keys;
  }

  /// Official SR only — used for saving attendance (never user_id).
  String _canonicalAttendanceRollKey(Map<String, dynamic> student) {
    return student['srNo']?.toString().trim() ?? '';
  }

  int _compareStudentsBySrNo(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aSr = a['srNo']?.toString().trim() ?? '';
    final bSr = b['srNo']?.toString().trim() ?? '';

    if (aSr.isEmpty != bSr.isEmpty) return aSr.isEmpty ? 1 : -1;

    final aNum = int.tryParse(aSr);
    final bNum = int.tryParse(bSr);
    if (aNum != null && bNum != null) {
      final byNumber = aNum.compareTo(bNum);
      if (byNumber != 0) return byNumber;
    } else {
      final byText = aSr.toLowerCase().compareTo(bSr.toLowerCase());
      if (byText != 0) return byText;
    }

    final aName = a['name']?.toString().trim().toLowerCase() ?? '';
    final bName = b['name']?.toString().trim().toLowerCase() ?? '';
    return aName.compareTo(bName);
  }

  bool _payloadHasAnyExit(Map<String, dynamic>? payload) {
    if (payload == null || payload.isEmpty) return false;
    if (sessionHasExitMap(payload)) return true;
    for (final session in mapSubjectSessions(payload).values) {
      if (sessionHasExitMap(session)) return true;
    }
    return false;
  }

  String? _attendancePhotoUrl(Map<String, dynamic> p, {required bool isEntry}) {
    final photoKey = isEntry ? 'entryPhoto' : 'exitPhoto';
    final fallbacks = isEntry ? const ['photoUrl'] : const <String>[];

    String? pick(Map<String, dynamic> m) {
      for (final k in [photoKey, ...fallbacks]) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final root = pick(p);
    if (root != null) return root;

    final active = teacherPayloadActiveSessionSlice(p);
    if (active != null) {
      final fromActive = pick(active);
      if (fromActive != null) return fromActive;
    }

    for (final s in mapSubjectSessions(p).values) {
      final fromSession = pick(s);
      if (fromSession != null) return fromSession;
    }
    return null;
  }

  String? _attendancePhotoPath(Map<String, dynamic> p, {required bool isEntry}) {
    final pathKey = isEntry ? 'entryPhotoPath' : 'exitPhotoPath';

    String? pick(Map<String, dynamic> m) {
      final v = m[pathKey];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    final root = pick(p);
    if (root != null) return root;

    final active = teacherPayloadActiveSessionSlice(p);
    if (active != null) {
      final fromActive = pick(active);
      if (fromActive != null) return fromActive;
    }

    for (final s in mapSubjectSessions(p).values) {
      final fromSession = pick(s);
      if (fromSession != null) return fromSession;
    }
    return null;
  }

  DateTime? _attendanceTimestamp(Map<String, dynamic> p, {required bool isEntry}) {
    DateTime? pick(Map<String, dynamic> m) {
      if (isEntry) {
        return parseAnyTimestamp(m['entryTime']) ?? parseAnyTimestamp(m['timestamp']);
      }
      return parseAnyTimestamp(m['exitTime']);
    }

    final root = pick(p);
    if (root != null) return root;

    final active = teacherPayloadActiveSessionSlice(p);
    if (active != null) {
      final fromActive = pick(active);
      if (fromActive != null) return fromActive;
    }

    for (final s in mapSubjectSessions(p).values) {
      final fromSession = pick(s);
      if (fromSession != null) return fromSession;
    }
    return null;
  }

  bool _studentMatchesAttendanceFilter(Map<String, dynamic> student) {
    if (_attendanceFilter == _StudentAttendanceFilter.all) return true;

    final studentId = student['id']?.toString().trim() ?? '';
    final payload =
        studentId.isEmpty ? null : _todayPayloadByStudentId[studentId];
    final hasEntry = payload != null && teacherPayloadHasAnySubjectEntry(payload);
    final hasExit = _payloadHasAnyExit(payload);

    switch (_attendanceFilter) {
      case _StudentAttendanceFilter.all:
        return true;
      case _StudentAttendanceFilter.present:
        return hasEntry;
      case _StudentAttendanceFilter.absent:
        return !hasEntry && !hasExit;
    }
  }

  String _attendanceFilterLabel(_StudentAttendanceFilter filter) {
    switch (filter) {
      case _StudentAttendanceFilter.all:
        return 'all';
      case _StudentAttendanceFilter.present:
        return 'present';
      case _StudentAttendanceFilter.absent:
        return 'absent';
    }
  }

  List<Map<String, dynamic>> get _visibleStudents {
    final visible = _students
        .where(_studentMatchesAttendanceFilter)
        .map((student) => Map<String, dynamic>.from(student))
        .toList();
    visible.sort(_compareStudentsBySrNo);
    return visible;
  }

  /// Map legacy attendance rows (sr_no / user_id in wrong columns) to one student, or skip if ambiguous.
  String? _resolveStudentIdForLegacyKey(
    String key,
    Map<String, Map<String, dynamic>> idToStudent,
  ) {
    final k = key.trim();
    if (k.isEmpty) return null;
    if (idToStudent.containsKey(k)) return k;

    final matches = <String>[];
    for (final e in idToStudent.entries) {
      final sr = e.value['srNo']?.toString().trim() ?? '';
      final uid = e.value['userId']?.toString().trim() ?? '';
      if (sr == k || (sr.isEmpty && uid == k)) matches.add(e.key);
    }
    return matches.length == 1 ? matches.first : null;
  }

  void _mergePayloadIntoStudent(
    Map<String, Map<String, dynamic>> map,
    String studentId,
    Map<String, dynamic> incoming,
  ) {
    if (studentId.isEmpty || incoming.isEmpty) return;
    final existing = map[studentId];
    if (existing == null) {
      map[studentId] = Map<String, dynamic>.from(incoming);
      return;
    }
    final merged = Map<String, dynamic>.from(existing);
    _mergeTeacherAttendanceIntoSlice(merged, incoming);
    map[studentId] = merged;
  }

  /// Stats for header (total students, present/absent today).
  /// ✅ Load stats using shared service (unified logic with home dashboard)
  Future<void> _loadHeaderStats() async {
    if (_instituteId == null) return;
    try {
      // ✅ Use SharedStatsService for consistent calculation
      final stats = await SharedStatsService.getTodayStats(_instituteId!);

      if (mounted) {
        // ⚡ Use addPostFrameCallback to prevent "reentrantly" painting errors
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _statsTotal = stats['total'] ?? 0;
              _statsPresentToday = stats['present'] ?? 0;
              _statsAbsentToday = stats['absent'] ?? 0;
            });
          }
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Header stats error: $e');
    }
  }

  /// ✅ Setup one-time stats load (no periodic refresh to avoid lag)
  void _setupStatsAutoRefresh() {
    // Load stats once on init only
    _loadHeaderStats();

    // ⏸️ DISABLED: Periodic refresh was causing repeated rebuilds and memory thrashing
    // Users can pull-to-refresh if they need latest stats
    // Real-time updates come from real-time sync on attendance changes

    if (kDebugMode) debugPrint('✅ Stats loaded once on init (no auto-refresh to prevent lag)');
  }

  Future<void> _refreshTodayPayloadsForVisibleStudents() async {
    if (!mounted || _instituteId == null) return;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_students.isEmpty) {
      if (mounted) setState(() => _todayPayloadByStudentId = {});
      return;
    }
    try {
      final ids = <String>[];
      final idToStudent = <String, Map<String, dynamic>>{};
      final idToLookupKeys = <String, List<String>>{};
      for (final student in _students) {
        final studentId = student['id']?.toString().trim() ?? '';
        final lookupKeys = _attendanceLookupKeysForStudent(student);

        if (studentId.isEmpty || lookupKeys.isEmpty) {
          if (kDebugMode) debugPrint('   ⏭️ SKIPPED: studentId or rollKey is empty');
          continue;
        }
        ids.add(studentId);
        idToStudent[studentId] = student;
        idToLookupKeys[studentId] = lookupKeys;
      }

      if (ids.isEmpty) {
        if (mounted) setState(() => _todayPayloadByStudentId = {});
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '🔍 Today thumbnails: ${_students.length} listed, ${ids.length} with id+roll — institute_id=$_instituteId',
        );
      }

      final instituteKey = _instituteId!;
      // ❌ DISABLED: ensureReconciled was running 20+ database queries per page load, causing lag
      // This happens during display and blocked scrolling. Reconciliation is not needed just to show the list.
      // It will still happen when attendance is actually marked.
      // for (final student in _students) {
      //   final userId = student['userId']?.toString().trim() ?? '';
      //   final srNo = student['srNo']?.toString().trim() ?? '';
      //   final rk = userId.isNotEmpty ? userId : srNo;
      //   final rawSubs = student['subjectsList'];
      //   final subjectsList = rawSubs is List
      //       ? rawSubs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
      //       : <String>[];
      //   if (rk.isEmpty || subjectsList.isEmpty) continue;
      //   await StaleAttendanceReconciliationService.ensureReconciled(
      //     db: appDb,
      //     instituteId: instituteKey,
      //     srNo: rk,
      //     date: today,
      //     enrolledSubjects: subjectsList,
      //   );
      // }

      void mergeAttendanceRow(Map<String, dynamic> payload, Map<String, dynamic> row) {
        final type = (row['record_type']?.toString() ?? '').toLowerCase();
        final photoUrl = (row['photo_url'] ?? '').toString().trim();
        final markedTime = row['marked_time'];
        final allottedTargetHr = row['allotted_target_hr'];
        final creditedHr = row['attendance_alloted_hr'];
        final remark = row['remark'];

        // Store record_type in payload for status determination
        if (type == 'entry' && payload['record_type'] == null) {
          payload['record_type'] = 'entry';
        }

        if (type == 'exit') {
          if (payload['exitPhoto'] == null && photoUrl.isNotEmpty) {
            payload['exitPhoto'] = photoUrl;
          }
          if (payload['exitTime'] == null) {
            payload['exitTime'] = markedTime;
          }
          // Exit row carries the final credited duration + remark (set by DB trigger).
          if (creditedHr != null) payload['creditedHr'] = creditedHr;
          if (remark != null) payload['remark'] = remark;
          if (allottedTargetHr != null) payload['allottedTargetHr'] = allottedTargetHr;
          payload['status'] = row['status'];
        } else {
          if (payload['entryPhoto'] == null && photoUrl.isNotEmpty) {
            payload['entryPhoto'] = photoUrl;
          }
          if (payload['photoUrl'] == null && photoUrl.isNotEmpty) {
            payload['photoUrl'] = photoUrl;
          }
          if (payload['entryTime'] == null) {
            payload['entryTime'] = markedTime;
          }
          // Entry row carries the frozen target hours (drives the countdown).
          if (allottedTargetHr != null) payload['allottedTargetHr'] = allottedTargetHr;
          // Entry may also have late/no-exit remark set by the nightly job.
          if (creditedHr != null) payload['creditedHr'] ??= creditedHr;
          if (remark != null) payload['remark'] ??= remark;
          payload['status'] = row['status'];
        }
      }

      // `attendance` table keys by sr_no (no student_id column) — build sr_no lookup.
      final srNoToStudentId = <String, String>{};
      for (final sid in ids) {
        for (final key in idToLookupKeys[sid] ?? const <String>[]) {
          if (key.isNotEmpty) srNoToStudentId[key] = sid;
        }
      }
      final srNos = srNoToStudentId.keys.toList();

      final map = <String, Map<String, dynamic>>{};
      const chunk = 100;
      for (var offset = 0; offset < srNos.length; offset += chunk) {
        final end = (offset + chunk) > srNos.length ? srNos.length : offset + chunk;
        final slice = srNos.sublist(offset, end);

        final rows = await appDb
            .from('attendance')
            .select('sr_no,record_type,photo_url,marked_time,status,allotted_target_hr,attendance_alloted_hr,remark')
            .eq('institute_id', instituteKey)
            .eq('attendance_date', today)
            .inFilter('sr_no', slice)
            .order('marked_time', ascending: false);

        if (kDebugMode) {
          debugPrint('📋 Attendance query (attendance table): institute_id=$instituteKey, date=$today, sr_no count=${slice.length}');
          debugPrint('   Found ${rows.length} attendance records from database');
          for (final raw in rows) {
            debugPrint('   row: sr_no=${raw['sr_no']} type=${raw['record_type']} marked_time=${raw['marked_time']} (${raw['marked_time']?.runtimeType})');
          }
        }

        final byStudent = <String, List<Map<String, dynamic>>>{};
        for (final raw in rows) {
          final row = Map<String, dynamic>.from(raw as Map);
          final sr = row['sr_no']?.toString().trim() ?? '';
          if (sr.isEmpty) continue;
          final sid = srNoToStudentId[sr];
          if (sid == null) continue;
          byStudent.putIfAbsent(sid, () => []).add(row);
        }

        for (final sid in slice.map((sr) => srNoToStudentId[sr]).whereType<String>()) {
          final list = byStudent[sid];
          if (list == null || list.isEmpty) continue;

          final payload = <String, dynamic>{};
          for (final row in list) {
            mergeAttendanceRow(payload, row);
          }
          if (payload.isNotEmpty) {
            _mergePayloadIntoStudent(map, sid, payload);
          }
        }
      }

      final docIdToStudentId = <String, String>{};
      for (final student in _students) {
        final sid = student['id']?.toString().trim() ?? '';
        final roll = _canonicalAttendanceRollKey(student);
        if (sid.isEmpty || roll.isEmpty) continue;
        docIdToStudentId['${instituteKey}_${roll}_$today'] = sid;
      }
      final docIds = docIdToStudentId.keys.toList();
      const tChunk = 40;
      for (var o = 0; o < docIds.length; o += tChunk) {
        final end = (o + tChunk > docIds.length) ? docIds.length : o + tChunk;
        final sub = docIds.sublist(o, end);
        try {
          final trows = await appDb
              .from('teacher_attendance')
              .select('id,student_id,payload')
              .inFilter('id', sub);
          for (final raw in trows) {
            final row = Map<String, dynamic>.from(raw as Map);
            final docId = row['id']?.toString().trim() ?? '';
            final p = row['payload'];
            if (docId.isEmpty || p is! Map) continue;
            final tp = Map<String, dynamic>.from(p.cast<String, dynamic>());
            final sid = docIdToStudentId[docId] ??
                _resolveStudentIdForLegacyKey(
                  row['student_id']?.toString() ?? '',
                  idToStudent,
                );
            if (sid == null) continue;
            _mergePayloadIntoStudent(map, sid, tp);
          }
        } catch (e) {
          if (kDebugMode) debugPrint('teacher_attendance UI merge: $e');
        }
      }

      if (mounted) setState(() => _todayPayloadByStudentId = map);
    } catch (e) {
      if (kDebugMode) debugPrint('Today payloads: $e');
    }
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        setState(() => _isLoadingInstitute = false);
        return;
      }

      if (kDebugMode) {
        debugPrint('🔐 Loading institute ID for user: ${user.id}');
        debugPrint('   📱 Device/Phone Info for debugging cross-device sync');
      }

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final foundInstituteId = row?['institute_id'] as String?;

      if (foundInstituteId != null && foundInstituteId.isNotEmpty) {
        // Fetch institute name
        String? instituteName;
        try {
          if (kDebugMode) debugPrint('🔍 Fetching institute data for ID: $foundInstituteId');
          final instRow = await appDb
              .from('institutes')
              .select('*')
              .eq('id', foundInstituteId)
              .maybeSingle();
          if (kDebugMode) debugPrint('📋 Institute row: $instRow');
          instituteName = instRow?['name'] as String?;
          if (kDebugMode) debugPrint('✅ Extracted name: $instituteName');
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Could not fetch institute name: $e');
        }

        if (kDebugMode) {
          debugPrint('✅ User found in institute: $foundInstituteId');
          debugPrint('   📊 Profile institute_id: $foundInstituteId');
          debugPrint('   📛 Institute name final: $instituteName');

          // DIAGNOSTIC: Check if students table has entries for this institute
          try {
            final studentCount = await appDb
                .from('students')
                .select('id')
                .eq('institute_id', foundInstituteId)
                .count(CountOption.exact);
            debugPrint('   📚 Total students in institute: ${studentCount.count}');
          } catch (e) {
            debugPrint('   ⚠️ Could not count students: $e');
          }
        }
        setState(() {
          _instituteId = foundInstituteId;
          _instituteName = instituteName;
          _isLoadingInstitute = false;
        });
        await _subscribeRealtime();
        await _bootstrapStudentList();
        return;
      }

      if (kDebugMode) {
        debugPrint('❌ CRITICAL: User not found in any institute!');
        debugPrint('   User ID: ${user.id}');
        debugPrint('   Profile row: $row');
        debugPrint('   This means the profile institute_id is NULL or EMPTY');
      }
      if (mounted) setState(() => _isLoadingInstitute = false);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Institute load error: $e');
      if (mounted) setState(() => _isLoadingInstitute = false);
    }
  }

  Future<void> _bootstrapStudentList() async {
    if (_instituteId == null) return;
    final instituteId = _instituteId!;
    var page = const _StudentPage(rows: [], total: 0, hasMore: false);

    try {
      page = await _fetchStudentPage(pageIndex: 0, query: '', previousTotal: null);
      if (kDebugMode) {
        debugPrint(
          '📚 Student list bootstrap for institute $instituteId: ${page.total} total, ${page.rows.length} first-page rows',
        );
        debugPrint('   Supabase host: ${_supabaseHostForLogs()}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Student bootstrap load error for institute $instituteId: $e');
    }

    if (!mounted) return;
    _applyStudentPage(page, reset: true);
  }

  Future<void> _subscribeRealtime() async {
    if (_instituteId == null || _instituteId!.isEmpty) return;

    if (_studentsChannel != null) {
      await appDb.removeChannel(_studentsChannel!);
      _studentsChannel = null;
    }
    if (_attendanceChannel != null) {
      await appDb.removeChannel(_attendanceChannel!);
      _attendanceChannel = null;
    }

    void scheduleRefresh({bool attendanceOnly = false}) {
      _realtimeRefreshDebounce?.cancel();
      _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 600), () async {
        if (!mounted) return;
        if (attendanceOnly) {
          await _refreshTodayPayloadsForVisibleStudents();
          // ⏸️ Don't call _loadHeaderStats() here - prevents reentrancy
        } else {
          await _loadStudents(reset: true);
          // ⏸️ Don't call _loadHeaderStats() here - prevents reentrancy
          // Stats are loaded once on init only
        }
      });
    }

    // ⏸️ DISABLED: Real-time sync was causing full list rebuilds every 600ms during scroll
    // Users can pull-to-refresh to get latest data
    // Real-time updates happen on AdminHomeScreen where it's appropriate

    // _studentsChannel = appDb
    //     .channel('student-management-students-${_instituteId!}')
    //     .onPostgresChanges(...)
    //     .subscribe();
    // _attendanceChannel = appDb
    //     .channel('student-management-attendance-$code')
    //     .onPostgresChanges(...)
    //     .subscribe();
  }

  Future<_StudentPage> _fetchStudentPage({
    required int pageIndex,
    required String query,
    required int? previousTotal,
  }) async {
    if (_instituteId == null) {
      return const _StudentPage(rows: [], total: 0, hasMore: false);
    }
    final instituteId = _instituteId!;

    dynamic dataQ = appDb.from('students').select(_studentSelectCols).eq('institute_id', instituteId);
    dynamic countQ = appDb.from('students').select('id').eq('institute_id', instituteId);
    final searchFilter = _studentSearchOrFilter(query);
    if (searchFilter != null) {
      dataQ = dataQ.or(searchFilter);
      countQ = countQ.or(searchFilter);
    }

    final total = (pageIndex > 0 && previousTotal != null)
        ? previousTotal
        : (await countQ.count(CountOption.exact)).count;

    final from = pageIndex * _pageSize;
    if (from >= total) {
      return _StudentPage(rows: [], total: total, hasMore: false);
    }

    final rows = await dataQ
        .order('sr_no', ascending: true, nullsFirst: false)
        .order('id', ascending: true)
        .range(from, from + _pageSize - 1);

    final list =
        (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final row in list) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isNotEmpty && !seen.contains(id)) {
        seen.add(id);
        deduped.add(row);
      }
    }

    final hasMore = from + deduped.length < total;

    if (kDebugMode) {
      debugPrint(
        '📋 Students page $pageIndex: ${deduped.length} row(s), total=$total, hasMore=$hasMore',
      );
    }

    return _StudentPage(rows: deduped, total: total, hasMore: hasMore);
  }

  /// 🔄 Fetch FRESH photo URLs from database (never cached, always current)
  Future<Map<String, String>> _fetchFreshPhotos(List<String> studentIds) async {
    if (studentIds.isEmpty || _instituteId == null) return {};

    try {
      final students = await appDb
          .from('students')
          .select('id, face_photo_url')
          .eq('institute_id', _instituteId!)
          .inFilter('id', studentIds);

      final photoMap = <String, String>{};
      for (final s in students) {
        final id = s['id']?.toString() ?? '';
        final url = s['face_photo_url']?.toString().trim() ?? '';
        if (id.isNotEmpty) photoMap[id] = url;
      }

      if (kDebugMode) {
        debugPrint('📷 Fresh photos fetched: ${photoMap.length} students');
      }

      return photoMap;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching fresh photos: $e');
      return {};
    }
  }

  /// Lightweight: ids only, no embedding JSON over the wire.
  Future<Set<String>> _studentIdsWithFaceEmbedding(List<String> studentIds) async {
    if (studentIds.isEmpty || _instituteId == null) return {};
    final out = <String>{};
    const chunk = 80;
    for (var i = 0; i < studentIds.length; i += chunk) {
      final slice = studentIds.sublist(i, i + chunk > studentIds.length ? studentIds.length : i + chunk);
      try {
        final rows = await appDb
            .from('students')
            .select('id')
            .eq('institute_id', _instituteId!)
            .inFilter('id', slice)
            .not('face_embedding', 'is', null);
        for (final raw in rows) {
          final id = (raw as Map)['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) out.add(id);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ embedding-id batch: $e');
      }
    }
    return out;
  }

  void _applyStudentPage(_StudentPage page, {required bool reset}) {
    if (!mounted) return;
    final mapped = page.rows.map(_mapStudentRow).toList();

    setState(() {
      if (reset) {
        _students = _dedupeMergedStudents(mapped);
      } else {
        _students = _dedupeMergedStudents([..._students, ...mapped]);
      }
      _page = reset ? 1 : _page + 1;
      _hasMore = page.hasMore;
      _studentCount = page.total;
      _isLoadingStudents = false;
      _isLoadingMore = false;
    });

    final studentIds = mapped
        .map((s) => s['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    _studentIdsWithFaceEmbedding(studentIds).then((withEmb) {
      if (!mounted || withEmb.isEmpty) return;
      setState(() {
        _students = _students.map((student) {
          final id = student['id']?.toString() ?? '';
          if (id.isEmpty || !withEmb.contains(id)) return student;
          if (student['hasFaceEmbedding'] == true) return student;
          return Map<String, dynamic>.from(student)..['hasFaceEmbedding'] = true;
        }).toList();
      });
    });

    // Merge fresh URLs by student id (avoids race when pages load out of order).
    _fetchFreshPhotos(studentIds).then((photoMap) {
      if (!mounted || photoMap.isEmpty) return;
      setState(() {
        _students = _students.map((student) {
          final id = student['id']?.toString() ?? '';
          if (id.isEmpty || !photoMap.containsKey(id)) return student;
          return Map<String, dynamic>.from(student)..['photoUrl'] = photoMap[id];
        }).toList();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshTodayPayloadsForVisibleStudents();
          if (reset) _loadHeaderStats();
        }
      });
    });
  }

  Future<void> _loadStudents({bool reset = false}) async {
    if (_instituteId == null) return;
    if (reset) {
      if (!mounted) return;
      // Clear Flutter + disk cache so list rows never show another student's file.
      imageCache.clear();
      imageCache.clearLiveImages();
      DefaultCacheManager().emptyCache();
      setState(() {
        _isLoadingStudents = true;
        _page = 0;
        _students.clear();
        _hasMore = true;
      });
      debugPrint('🔄 Loading students from RESET... (image cache cleared)');
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
      debugPrint('🔄 Loading students page: ${_page + 1}...');
    }

    try {
      final pageData = await _fetchStudentPage(
        pageIndex: reset ? 0 : _page,
        query: _searchQuery,
        previousTotal: reset ? null : _studentCount,
      );
      debugPrint('✅ Loaded ${pageData.rows.length} students for page ${reset ? 0 : _page}, total: ${pageData.total}, hasMore: ${pageData.hasMore}');
      _applyStudentPage(pageData, reset: reset);
    } catch (e) {
      if (kDebugMode) debugPrint('Student load error: $e');
      if (mounted) setState(() { _isLoadingStudents = false; _isLoadingMore = false; });
    }
  }

  Map<String, dynamic> _mapStudentRow(Map<String, dynamic> row) {
    // Construct name from fname, lname, mname
    final fname = row['fname']?.toString().trim() ?? '';
    final lname = row['lname']?.toString().trim() ?? '';
    final mname = row['mname']?.toString().trim() ?? '';
    final name = [fname, mname, lname].where((e) => e.isNotEmpty).join(' ').trim();

    final srRaw = row['sr_no']?.toString().trim() ?? '';
    final regUrl = (row['face_photo_url'] as String?)?.trim();
    final url = regUrl ?? '';

    final parsedSubs = _parseSubjectsList(row);
    final subject = parsedSubs.join(', ');
    // Full embedding is loaded in a separate small id-only query after the page fetch.
    final hasFaceEmb = false;

    if (kDebugMode && url.isEmpty) {
      debugPrint('⚠️ Student has no photo URL:');
      debugPrint('   Name: $name');
      debugPrint('   face_photo_url: EMPTY');
    } else if (kDebugMode && url.isNotEmpty) {
      debugPrint('✅ Student photo found:');
      debugPrint('   Name: $name');
      debugPrint('   Photo URL: $url');
    }


    return {
      'id': row['id'],
      'name': name,
      'userId': row['sr_no'] ?? '',
      'srNo': srRaw,
      'subject': subject,
      'subjectsList': parsedSubs,
      'year': '',
      'photoUrl': url,
      'photoThumbnail': null,
      'photoVersion': null,
      'hasFaceEmbedding': hasFaceEmb,
      'facePhotoChangedOnce': false,
      // ✅ NEW: Add face registration columns to the mapped row
      'face_registration_status': row['face_registration_status'] ?? 'pending',
      'is_face_real': row['is_face_real'] ?? false,
      'form_serial_no': row['form_serial_no'] ?? '',
    };
  }

  // Polling removed — data is loaded on demand with server-side pagination.

  @override
  Widget build(BuildContext context) {
    if (_isLoadingInstitute) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue)),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleStudents = _visibleStudents;

    return PopScope(
      canPop: !widget.forAttendanceStaffPortal,
      onPopInvokedWithResult: (didPop, result) {
        if (widget.forAttendanceStaffPortal) return;
        if (didPop) return;
        // Check if we're in a PageView (main navigation) or as a separate route
        // If we can pop, do it normally
        if (Navigator.of(context).canPop()) {
          Navigator.pop(context);
        }
        // If we can't pop (likely in PageView), do nothing - let user use bottom nav
        // Don't force navigation to home
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        floatingActionButton: _instituteId == null
            ? null
            : ScaleTransition(
                scale: Tween<double>(begin: 0.5, end: 1).animate(
                  CurvedAnimation(parent: _fadeController, curve: Curves.elasticOut),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGreen.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: () => _openAutoFaceScan(),
                    backgroundColor: AppTheme.primaryGreen,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    icon: const Icon(Icons.face_retouching_natural, color: Colors.white),
                    label: const Text(
                      'Mark Attendance',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadStudents(reset: true);
                await _loadHeaderStats();
              },
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(child: _buildBlueStudentsHeader()),
                  SliverToBoxAdapter(child: _buildPhotoInstructionsCard()),
                  SliverToBoxAdapter(child: _buildSearchBar()),
                  if (_instituteId != null)
                    SliverToBoxAdapter(child: _buildSummaryStatCards()),
                  ..._buildStudentContentSlivers(
                    context,
                    isDark,
                    visibleStudents,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBlueStudentsHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 10.w, 12.h),
      color: AppTheme.primaryBlue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row with logout button
          Row(
            children: [
              if (widget.forAttendanceStaffPortal) ...[
                IconButton(
                  icon: Icon(Icons.logout, color: Colors.white, size: 22.sp),
                  tooltip: 'Sign out',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
                  onPressed: () async {
                    if (!context.mounted) return;
                    await StaffAttendancePortalScreen.signOutToLogin(context);
                  },
                ),
                SizedBox(width: 4.w),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Welcome message (animated marquee - right to left)
                    _ScrollingWelcomeMessage(
                      instituteId: _instituteId,
                      instituteName: _instituteName,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStatCards() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
          child: Row(
            children: [
              // 1️⃣ Absent (Orange) - Animated
              Expanded(
                child: _statsAnimController != null
                    ? ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1).animate(
                          CurvedAnimation(parent: _statsAnimController!, curve: Curves.elasticOut),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _attendanceFilter = _StudentAttendanceFilter.absent;
                            });
                          },
                          child: _bigStatCard(
                            label: 'Absent',
                            value: _statsAbsentToday,
                            icon: Icons.cancel_rounded,
                            color: AppTheme.accentRed,
                            isDark: isDark,
                            isActive: _attendanceFilter == _StudentAttendanceFilter.absent,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _attendanceFilter = _StudentAttendanceFilter.absent;
                          });
                        },
                        child: _bigStatCard(
                          label: 'Absent',
                          value: _statsAbsentToday,
                          icon: Icons.cancel_rounded,
                          color: AppTheme.accentRed,
                          isDark: isDark,
                          isActive: _attendanceFilter == _StudentAttendanceFilter.absent,
                        ),
                      ),
              ),
              SizedBox(width: 10.w),
              // 2️⃣ Total (White/Neutral) - Animated
              Expanded(
                child: _statsAnimController != null
                    ? ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1).animate(
                          CurvedAnimation(parent: _statsAnimController!, curve: Curves.elasticOut),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _attendanceFilter = _StudentAttendanceFilter.all;
                            });
                          },
                          child: _bigStatCard(
                            label: 'Total',
                            value: _statsTotal,
                            icon: Icons.people_alt_rounded,
                            color: Colors.grey,
                            isDark: isDark,
                            isActive: _attendanceFilter == _StudentAttendanceFilter.all,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _attendanceFilter = _StudentAttendanceFilter.all;
                          });
                        },
                        child: _bigStatCard(
                          label: 'Total',
                          value: _statsTotal,
                          icon: Icons.people_alt_rounded,
                          color: Colors.grey,
                          isDark: isDark,
                          isActive: _attendanceFilter == _StudentAttendanceFilter.all,
                        ),
                      ),
              ),
              SizedBox(width: 10.w),
              // 3️⃣ Present (Green) - Animated
              Expanded(
                child: _statsAnimController != null
                    ? ScaleTransition(
                        scale: Tween<double>(begin: 0.9, end: 1).animate(
                          CurvedAnimation(parent: _statsAnimController!, curve: Curves.elasticOut),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _attendanceFilter = _StudentAttendanceFilter.present;
                            });
                          },
                          child: _bigStatCard(
                            label: 'Present',
                            value: _statsPresentToday,
                            icon: Icons.check_circle_rounded,
                            color: AppTheme.primaryGreen,
                            isDark: isDark,
                            isActive: _attendanceFilter == _StudentAttendanceFilter.present,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () {
                          setState(() {
                            _attendanceFilter = _StudentAttendanceFilter.present;
                          });
                        },
                        child: _bigStatCard(
                          label: 'Present',
                          value: _statsPresentToday,
                          icon: Icons.check_circle_rounded,
                          color: AppTheme.primaryGreen,
                          isDark: isDark,
                          isActive: _attendanceFilter == _StudentAttendanceFilter.present,
                        ),
                      ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // ✨ Bottom border/divider
        Container(
          height: 1.5.h,
          margin: EdgeInsets.symmetric(horizontal: 16.w),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                AppTheme.primaryBlue.withValues(alpha: 0.3),
                AppTheme.primaryBlue.withValues(alpha: 0.3),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(1.r),
          ),
        ),
      ],
    );
  }

  Widget _bigStatCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required bool isDark,
    bool isActive = false,
  }) {
    // Modern gradient based on color
    final gradientColors = _getGradientForColor(color);

    // Determine text color: dark for white card, white for colored cards
    final isWhiteCard = color == Colors.grey;
    final textColor = isWhiteCard ? const Color(0xFF333333) : Colors.white;
    final textColorLight = isWhiteCard
        ? const Color(0xFF666666)
        : Colors.white.withValues(alpha: 0.85);
    final iconColor = isWhiteCard ? const Color(0xFF555555) : Colors.white;
    final iconBgColor = isWhiteCard
        ? const Color(0xFFCCCCCC).withValues(alpha: 0.3)
        : Colors.white.withValues(alpha: 0.25);

    return Container(
      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 12.w),
      decoration: BoxDecoration(
        // 🎨 Modern gradient background
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(18.r),
        // ✨ Highlight active filter with bright border
        border: isActive
            ? Border.all(
                color: Colors.white,
                width: 3.w,
              )
            : null,
        boxShadow: [
          // Modern depth shadow
          BoxShadow(
            color: isActive ? color.withValues(alpha: 0.6) : color.withValues(alpha: 0.3),
            blurRadius: isActive ? 20 : 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✨ Icon with background circle
          Container(
            width: 50.r,
            height: 50.r,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: iconColor, size: 28.sp),
          ),
          SizedBox(height: 12.h),
          // 📊 Big number
          Text(
            '$value',
            style: TextStyle(
              fontSize: 28.sp,
              fontWeight: FontWeight.w900,
              color: textColor,
              letterSpacing: -0.5,
            ),
          ),
          SizedBox(height: 4.h),
          // 📝 Label
          Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              color: textColorLight,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  /// Get gradient colors based on stat type (orange, green, white theme)
  List<Color> _getGradientForColor(Color baseColor) {
    if (baseColor == AppTheme.primaryGreen) {
      // Present: Green (Indian tricolor green)
      return [
        const Color(0xFF138808),
        const Color(0xFF006600),
      ];
    } else if (baseColor == AppTheme.accentRed) {
      // Absent: Orange/Saffron (Indian tricolor orange)
      return [
        const Color(0xFFFF9933),
        const Color(0xFFFF6600),
      ];
    } else if (baseColor == Colors.grey) {
      // Total: White/Grey neutral
      return [
        const Color(0xFFF5F5F5),
        const Color(0xFFE0E0E0),
      ];
    } else {
      // Default fallback
      return [
        const Color(0xFFFF9933),
        const Color(0xFFE8871A),
      ];
    }
  }

  String? _entryPhotoUrl(Map<String, dynamic> p) =>
      _attendancePhotoUrl(p, isEntry: true);

  String? _exitPhotoUrl(Map<String, dynamic> p) =>
      _attendancePhotoUrl(p, isEntry: false);

  String _formatPayloadTime(Map<String, dynamic>? p, bool isEntry) {
    if (p == null) return '—';
    final t = _attendanceTimestamp(p, isEntry: isEntry);
    if (t == null) return '—';
    final loc = t.toLocal();
    return DateFormat('HH:mm:ss').format(loc);
  }

  List<String> _parseSubjectsList(Map<String, dynamic> row) {
    final out = <String>[];

    // ✅ NEW: Parse sub1, sub2, sub3, ... sub8 columns
    for (int i = 1; i <= 8; i++) {
      final key = 'sub$i';
      final sub = row[key]?.toString().trim() ?? '';
      if (sub.isNotEmpty && !out.contains(sub)) {
        out.add(sub);
        if (kDebugMode) debugPrint('  ✓ Added from $key: "$sub"');
      }
    }


    // Remove duplicates (case-insensitive comparison)
    final deduplicated = <String>[];
    for (final s in out) {
      if (!deduplicated.any((existing) => existing.toLowerCase() == s.toLowerCase())) {
        deduplicated.add(s);
      }
    }

    if (kDebugMode && deduplicated.isNotEmpty) {
      debugPrint('✅ Final ${deduplicated.length} subjects for ${row['name']}: $deduplicated');
    }

    return deduplicated;
  }

  /// 🔄 Fetch CURRENT student subjects from database (FRESH, not cached)
  /// Call this BEFORE calculating exit window to ensure allocation is based on CURRENT data
  /// If student subjects change in database, we'll get the updated count here
  Future<List<String>> _fetchCurrentStudentSubjectsFromDb(String srNo) async {
    try {
      if (_instituteId == null || srNo.trim().isEmpty) return [];

      // Query current student data
      var student = await appDb
          .from('students')
          .select('sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8')
          .eq('institute_id', _instituteId!)
          .eq('sr_no', srNo.trim())
          .maybeSingle();

      // Fallback: try by user_id
      student ??= await appDb
          .from('students')
          .select('sub1,sub2,sub3,sub4,sub5,sub6,sub7,sub8')
          .eq('institute_id', _instituteId!)
          .eq('user_id', srNo.trim())
          .maybeSingle();

      if (student == null) {
        if (kDebugMode) debugPrint('⚠️ Student not found for fresh subject fetch: $srNo');
        return [];
      }

      final freshSubjects = [
        student['sub1'], student['sub2'], student['sub3'], student['sub4'],
        student['sub5'], student['sub6'], student['sub7'], student['sub8'],
      ].map((s) => s?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();

      if (freshSubjects.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ Fresh subjects fetched: $freshSubjects (count=${freshSubjects.length})');
        }
        _freshSubjectsCache[srNo] = freshSubjects;
        return freshSubjects;
      }

      if (kDebugMode) debugPrint('⚠️ No subjects found for $srNo');
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching fresh subjects: $e');
      return [];
    }
  }

  /// Get fresh subject count (from cache if available, fallback to display data)
  int _getFreshSubjectCount(String rollKey, List<String> displaySubjectsList) {
    // If we have cached fresh subjects, use them
    if (_freshSubjectsCache.containsKey(rollKey)) {
      final cached = _freshSubjectsCache[rollKey]!;
      if (cached.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ Using cached fresh subjects for $rollKey: ${cached.length}');
        }
        return cached.length;
      }
    }
    // Fallback to display data
    return displaySubjectsList.length;
  }

  bool _sliceHasEntry(Map<String, dynamic>? slice) {
    if (slice == null) return false;
    return teacherPayloadHasAnySubjectEntry(slice);
  }

  bool _sliceComplete(Map<String, dynamic>? slice) {
    if (slice == null) return false;
    if (!teacherPayloadHasAnySubjectEntry(slice)) return false;
    // If top-level exitTime is present the exit row is in attendance_in_out —
    // treat as complete regardless of subjectSessions (which only track teacher_attendance entries).
    if (sessionHasExitMap(slice)) return true;
    return !teacherPayloadHasPendingExit(slice);
  }

  /// Merge `teacher_attendance.payload` so Entry/Exit match [InlineStudentAttendanceService.markForRoll].
  void _mergeTeacherAttendanceIntoSlice(Map<String, dynamic> slice, Map<String, dynamic> tp) {
    const keys = <String>[
      'entryPhoto',
      'entryPhotoPath',
      'photoUrl',
      'entryTime',
      'timestamp',
      'exitPhoto',
      'exitPhotoPath',
      'exitTime',
      'status',
      'subjectSessions',
    ];
    for (final k in keys) {
      if (!tp.containsKey(k)) continue;
      final v = tp[k];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      slice[k] = v;
    }
    final active = teacherPayloadActiveSessionSlice(tp);
    if (active != null) {
      for (final k in keys) {
        if (k == 'subjectSessions') continue;
        if (!active.containsKey(k)) continue;
        final v = active[k];
        if (v == null) continue;
        if (v is String && v.trim().isEmpty) continue;
        if (!slice.containsKey(k)) slice[k] = v;
      }
    }
  }

  Future<void> _openAutoFaceScan({String? studentName}) async {
    if (_instituteId == null || _instituteId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Institute not loaded. Pull to refresh and try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final hasPinSession = await PinSessionManager.hasActivePinSession();
    if (hasPinSession) {
      final verification = await LocationVerificationService.verifyLocationNow(
        instituteId: _instituteId!,
      );
      if (!verification.isWithinRadius) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                verification.error ??
                    'Cannot open auto face attendance outside institute GPS zone.',
              ),
              backgroundColor: AppTheme.accentRed,
            ),
          );
        }
        return;
      }
    }

    if (studentName != null && studentName.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Auto scan — ask $studentName to stand in front of the camera'),
          duration: const Duration(seconds: 3),
          backgroundColor: AppTheme.primaryGreen,
        ),
      );
    }

    if (!mounted) return;

    // ✅ Use old LiveAntiSpoofCameraScreen (simple, manual capture)
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveAntiSpoofCameraScreen(
          studentName: studentName,
          studentId: 'ATTENDANCE_MARK',
          isRegistration: false,
          instituteId: _instituteId!,
        ),
      ),
    );

    if (mounted) {
      await _loadHeaderStats();
      _refreshTodayPayloadsForVisibleStudents();
    }
  }

  String? _durationChipText(Map<String, dynamic>? p) {
    if (p == null) return null;
    Duration? dur;
    final h = p['hours'];
    if (h is num) {
      dur = Duration(seconds: (h.toDouble() * 3600).round());
    } else {
      final et = parseAnyTimestamp(p['entryTime']);
      final xt = parseAnyTimestamp(p['exitTime']);
      if (et != null && xt != null && !xt.isBefore(et)) {
        dur = xt.difference(et);
      }
    }
    if (dur == null) return null;
    return 'Duration: ${formatSeatedDurationHuman(dur)}';
  }

  /// Calculate remaining time in exit window (using fresh subject count from cache)
  String? _getExitTimeRemaining(Map<String, dynamic>? slice, String rollKey, List<String> displaySubjectsList) {
    if (slice == null) return null;
    final entryTime = parseAnyTimestamp(slice['entryTime']) ?? parseAnyTimestamp(slice['timestamp']);
    if (entryTime == null) return null;

    // 🔄 Use fresh subject count from cache (or fallback to display data)
    final enrolledSubjectCount = _getFreshSubjectCount(rollKey, displaySubjectsList);

    final windowHours = attendanceWindowHoursForSubjectCount(enrolledSubjectCount);
    final windowDuration = Duration(minutes: (windowHours * 60).round());
    final deadlineUtc = entryTime.toUtc().add(windowDuration);
    final nowUtc = DateTime.now().toUtc();

    if (nowUtc.isAfter(deadlineUtc)) return '⏰ Time is up';

    final remaining = deadlineUtc.difference(nowUtc);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  bool _isExitWindowExpired(Map<String, dynamic>? slice, String rollKey, List<String> displaySubjectsList) {
    if (slice == null) return false;
    final entryTime =
        parseAnyTimestamp(slice['entryTime']) ?? parseAnyTimestamp(slice['timestamp']);
    if (entryTime == null) return false;

    // 🔄 Use fresh subject count from cache (or fallback to display data)
    final enrolledSubjectCount = _getFreshSubjectCount(rollKey, displaySubjectsList);

    return isPastAttendanceExitDeadline(
      entryTime.toUtc(),
      DateTime.now().toUtc(),
      enrolledSubjectCount,
    );
  }

  /// Live countdown from entry using the frozen `allottedTargetHr` (attendance table policy).
  /// Returns null once exit is marked (creditedHr present) or if there's no entry yet.
  ({String label, bool overdue})? _newAttendanceCountdown(Map<String, dynamic>? slice) {
    if (slice == null) return null;
    if (slice['creditedHr'] != null) return null; // exit already credited
    final entryTime = parseAnyTimestamp(slice['entryTime']);
    if (entryTime == null) return null;

    final allotted = (slice['allottedTargetHr'] as num?)?.toDouble() ?? 1.0;
    final deadline = entryTime.toUtc().add(Duration(seconds: (allotted * 3600).round()));
    final now = DateTime.now().toUtc();

    if (now.isAfter(deadline)) return (label: '⏰ Time up', overdue: true);

    final remaining = deadline.difference(now);
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    return (label: '${h}h ${m}m left', overdue: false);
  }

  /// Final credited duration text once exit is marked (or nightly no-exit close ran).
  String? _creditedHrLabel(Map<String, dynamic>? slice) {
    if (slice == null) return null;
    final raw = slice['creditedHr']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return raw;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${h}h ${m}m';
  }

  Widget _buildAttendanceThumb({
    required String label,
    required Color borderColor,
    required String? imageUrl,
    String? storagePath,
    required String time,
    required bool isDark,
    VoidCallback? onTap,
    bool dimmed = false,
  }) {
    const thumbHeight = 110.0;
    final hasImage = (imageUrl != null && imageUrl.isNotEmpty) ||
        (storagePath != null && storagePath.isNotEmpty);
    final box = Container(
      height: thumbHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 2.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? SecureNetworkImage(
              imageUrl: (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
              storagePath: (storagePath != null && storagePath.isNotEmpty) ? storagePath : null,
              width: double.infinity,
              height: thumbHeight,
              fit: BoxFit.cover,
              placeholder: ColoredBox(color: borderColor.withValues(alpha: 0.08)),
              errorWidget: ColoredBox(
                color: borderColor.withValues(alpha: 0.08),
                child: Icon(Icons.broken_image_outlined, color: borderColor, size: 36),
              ),
            )
          : ColoredBox(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : AppTheme.backgroundGrey,
              child: Icon(Icons.photo_camera_outlined, color: borderColor.withValues(alpha: 0.65), size: 36),
            ),
    );

    Widget thumb = onTap != null
        ? Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: box,
            ),
          )
        : box;

    if (dimmed) {
      thumb = Opacity(opacity: 0.42, child: thumb);
    }

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: borderColor,
            ),
          ),
          const SizedBox(height: 6),
          thumb,
          const SizedBox(height: 4),
          Text(
            time,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : AppTheme.textGray,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Bottom inset for scroll content above the bottom nav / gesture bar.
  EdgeInsets _studentListOuterPadding(BuildContext context) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final horizontal = context.vw(4).clamp(12.0, 24.0);
    final top = context.vh(1.5).clamp(10.0, 20.0);
    final bottomBase = context.vh(2).clamp(12.0, 24.0);
    return EdgeInsets.fromLTRB(
      horizontal,
      top,
      horizontal,
      bottomBase + safeBottom,
    );
  }

  List<Widget> _buildStudentContentSlivers(
    BuildContext context,
    bool isDark,
    List<Map<String, dynamic>> visibleStudents,
  ) {
    if (_instituteId == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildModernCard(
                isDark: isDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 60, color: AppTheme.accentRed),
                    const SizedBox(height: 16),
                    Text(
                      'Institute not found',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please login again or contact support',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (_isLoadingStudents) {
      return [
        SliverPadding(
          padding: _studentListOuterPadding(context),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ShimmerListItem().stagger(index: index),
              ),
              childCount: 5,
            ),
          ),
        ),
      ];
    }

    if (_students.isEmpty && !_isLoadingStudents) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildModernCard(
                isDark: isDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_searchQuery.isNotEmpty ? Icons.search_off : Icons.school,
                        size: 60, color: AppTheme.primaryBlue),
                    const SizedBox(height: 16),
                    Text(
                      _searchQuery.isNotEmpty ? 'No students found' : 'No students yet',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _searchQuery.isNotEmpty
                          ? 'Try a different search term'
                          : 'Student records from your institute appear here.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (visibleStudents.isEmpty) {
      final filterLabel = _attendanceFilterLabel(_attendanceFilter);
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _buildModernCard(
                isDark: isDark,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _attendanceFilter == _StudentAttendanceFilter.present
                          ? Icons.check_circle_outline
                          : Icons.person_off_outlined,
                      size: 60,
                      color: AppTheme.primaryBlue,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No $filterLabel students found',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _hasMore
                          ? 'Load more students to check more records.'
                          : 'No students match this filter right now.',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: _studentListOuterPadding(context),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (ctx, index) {
              if (index == visibleStudents.length) {
                // Show pagination control instead of just spinner
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Column(
                    children: [
                      if (_isLoadingMore)
                        const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      else if (_hasMore)
                        Center(
                          child: ElevatedButton.icon(
                            onPressed: _loadStudents,
                            icon: const Icon(Icons.arrow_downward),
                            label: Text(
                              'Load More Students (${_students.length}/${_studentCount})',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                          ),
                        )
                      else
                        Center(
                          child: Text(
                            _attendanceFilter == _StudentAttendanceFilter.all
                                ? '✅ Showing all ${visibleStudents.length} students'
                                : '✅ Checked all loaded students for ${_attendanceFilterLabel(_attendanceFilter)}',
                            style: TextStyle(
                              color: AppTheme.textGray,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }
              return _buildStudentListItem(
                context,
                visibleStudents[index],
                isDark,
              );
            },
            childCount:
                visibleStudents.length + 1, // Always show pagination control at bottom
          ),
        ),
      ),
    ];
  }

  Widget _buildStudentListItem(
    BuildContext context,
    Map<String, dynamic> data,
    bool isDark,
  ) {
    final name = data['name'] ?? 'Unknown';
    final srNo = data['srNo']?.toString() ?? data['sr_no']?.toString() ?? '';
    final rollNumber = srNo.isNotEmpty ? srNo : (data['userId'] ?? '');
    final subject = data['subject'] ?? '';
    // ✅ FIXED: Use 'photoUrl' key (from _mapStudentRow), not 'face_photo_url'
    final profileUrl = (data['photoUrl'] as String?) ?? (data['face_photo_url'] as String?) ?? '';
    final hasPhoto = profileUrl.isNotEmpty;
    final studentId = data['id']?.toString() ?? '';
    final markRollKey = _canonicalAttendanceRollKey(data);
    final rollKey = markRollKey.isNotEmpty ? markRollKey : rollNumber.toString().trim();
    final payload = studentId.isNotEmpty ? _todayPayloadByStudentId[studentId] : null;
    final hasFaceEmbedding = data['hasFaceEmbedding'] == true;
    final facePhotoChangedOnce = data['facePhotoChangedOnce'] == true;
    final canChangePhotoOnce = hasFaceEmbedding && !facePhotoChangedOnce;
    final rawSubs = data['subjectsList'];
    final photoThumbnail = data['photoThumbnail'] as String?;
    final photoVersion = data['photoVersion'] as String? ?? (data['photo_version'] as String?);
    final subjectsList = rawSubs is List
        ? rawSubs.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
        : <String>[];

    // ✅ NEW: Face registration columns
    final faceRegistrationStatus = data['face_registration_status'] ?? 'pending';
    final isFaceReal = data['is_face_real'] ?? false;
    final averageFaceQuality = 0.0; // Column not in DB yet, default to 0
    final formSerialNo = data['form_serial_no'] ?? '';

    // ⏸️ DISABLED: Background subject fetch was firing DB query for EVERY student during scroll!
    // This blocked the main thread (nativePoll 99% CPU)
    // Subjects are fetched only when needed (marking attendance)
    // if (_freshSubjectsCache[rollKey] == null && rollKey.isNotEmpty) {
    //   _fetchCurrentStudentSubjectsFromDb(rollKey).catchError((e) {...});
    // }
    final slice = payload;
    final newAttendanceCountdown = _newAttendanceCountdown(slice);
    final creditedHrLabel = _creditedHrLabel(slice);
    final attendanceRemarkRaw = slice?['remark']?.toString().trim();
    final attendanceRemark = (attendanceRemarkRaw != null && attendanceRemarkRaw.isNotEmpty) ? attendanceRemarkRaw : null;
    final entryPhotoUrl = slice != null ? _entryPhotoUrl(slice) : null;
    final exitPhotoUrl = slice != null ? _exitPhotoUrl(slice) : null;
    final hasEntryPhoto = entryPhotoUrl != null && entryPhotoUrl.isNotEmpty;
    final hasExitPhoto = exitPhotoUrl != null && exitPhotoUrl.isNotEmpty;

    // Determine attendance status based on face registration
    final isFaceRegistered = faceRegistrationStatus == 'registered';
    final isPresent = slice != null && slice.containsKey('record_type') && slice['record_type'] == 'entry';

    final statusColor = isFaceRegistered
        ? (isPresent ? const Color(0xFF138808) : const Color(0xFFFF9933))
        : const Color(0xFFB0B0B0); // Grey for unregistered

    final statusIcon = isFaceRegistered
        ? (isPresent ? Icons.check_circle : Icons.cancel)
        : Icons.person_add_outlined;

    final statusLabel = isFaceRegistered
        ? (isPresent ? 'PRESENT' : 'ABSENT')
        : 'NOT REGISTERED';

    return Padding(
      padding: EdgeInsets.only(bottom: 14.h, left: 16.w, right: 16.w),
      child: RepaintBoundary(
        child: Container(
        decoration: BoxDecoration(
          // ✨ Modern gradient background
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isDark ? const Color(0xFF1F2937) : Colors.white,
              isDark ? const Color(0xFF111827) : const Color(0xFFFAFAFA),
            ],
          ),
          borderRadius: BorderRadius.circular(20.r),
          // 🎯 Beautiful shadow with depth
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          // Border with status color accent
          border: Border(
            left: BorderSide(
              color: statusColor,
              width: 5.w,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 14.w, 14.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Photo + Name + Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 📸 Modern profile photo with badge
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16.r),
                        child: SizedBox(
                          width: 100.w,
                          height: 100.h,
                          child: hasPhoto
                              ? SecureNetworkImage(
                                  key: ValueKey('student_face_$studentId'),
                                  cacheKey: 'student_face_$studentId',
                                  imageUrl: profileUrl.isNotEmpty ? profileUrl : null,
                                  width: 100.w,
                                  height: 100.h,
                                  version: photoVersion ?? '0',
                                  fit: BoxFit.cover,
                                  placeholder: photoThumbnail != null && photoThumbnail.isNotEmpty
                                      ? Image.memory(
                                          base64Decode(photoThumbnail),
                                          width: 80.w,
                                          height: 80.h,
                                          fit: BoxFit.cover,
                                          cacheWidth: 80,
                                          cacheHeight: 80,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    statusColor.withValues(alpha: 0.2),
                                                    statusColor.withValues(alpha: 0.05),
                                                  ],
                                                ),
                                              ),
                                              child: Icon(Icons.person, color: statusColor, size: 40.sp),
                                            );
                                          },
                                        )
                                      : Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                statusColor.withValues(alpha: 0.2),
                                                statusColor.withValues(alpha: 0.05),
                                              ],
                                            ),
                                          ),
                                          child: Center(
                                            child: SizedBox(
                                              width: 24.w,
                                              height: 24.h,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor: AlwaysStoppedAnimation(statusColor),
                                              ),
                                            ),
                                          ),
                                        ),
                                  errorWidget: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          statusColor.withValues(alpha: 0.2),
                                          statusColor.withValues(alpha: 0.05),
                                        ],
                                      ),
                                    ),
                                    child: Icon(Icons.person, color: statusColor, size: 40.sp),
                                  ),
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        statusColor.withValues(alpha: 0.2),
                                        statusColor.withValues(alpha: 0.05),
                                      ],
                                    ),
                                  ),
                                  child: Icon(Icons.person, color: statusColor, size: 40.sp),
                                ),
                        ),
                      ),
                      // Status badge on photo corner
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            statusIcon,
                            color: Colors.white,
                            size: 20.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: 14.w),
                  // Name, SR NO, and Status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name with status badge
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: isDark ? Colors.white : AppTheme.textDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16.sp,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20.r),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.4),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10.sp,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        // SR NO
                        Row(
                          children: [
                            Icon(Icons.tag, size: 14.sp, color: statusColor.withValues(alpha: 0.6)),
                            SizedBox(width: 4.w),
                            Expanded(
                              child: Text(
                                'SR NO: ${_formatSrDisplay(srNo)}',
                                style: TextStyle(
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        if (formSerialNo.isNotEmpty) ...[
                          SizedBox(height: 6.h),
                          Row(
                            children: [
                              Icon(Icons.document_scanner, size: 13.sp, color: statusColor.withValues(alpha: 0.5)),
                              SizedBox(width: 4.w),
                              Text(
                                'Form: $formSerialNo',
                                style: TextStyle(
                                  color: isDark ? Colors.white60 : AppTheme.textGray,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                        // 📖 Subjects Display
                        if (subjectsList.isNotEmpty) ...[
                          SizedBox(height: 8.h),
                          Row(
                            children: [
                              Icon(Icons.school, size: 14.sp, color: AppTheme.primaryBlue.withValues(alpha: 0.7)),
                              SizedBox(width: 6.w),
                              Expanded(
                                child: Text(
                                  subjectsList.join(', '),
                                  style: TextStyle(
                                    color: isDark ? Colors.white70 : AppTheme.textGray,
                                    fontSize: 12.sp,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              // Divider
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      statusColor.withValues(alpha: 0.1),
                      statusColor.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              // Bottom row: Entry/Exit photos + Timer + Face status
              Row(
                children: [
                  // Entry photo
                  if (hasEntryPhoto)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '📸 Entry',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: 6.h),
                          GestureDetector(
                            onTap: hasEntryPhoto
                                ? () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        backgroundColor: Colors.transparent,
                                        child: GestureDetector(
                                          onTap: () => Navigator.pop(context),
                                          child: InteractiveViewer(
                                            child: SecureNetworkImage(
                                              imageUrl: entryPhotoUrl,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.r),
                              child: SizedBox(
                                height: 100.h,
                                child: SecureNetworkImage(
                                key: ValueKey('entry_$studentId'),
                                cacheKey: 'entry_$studentId',
                                imageUrl: entryPhotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  color: statusColor.withValues(alpha: 0.1),
                                  child: Icon(Icons.image_not_supported, color: statusColor, size: 24.sp),
                                ),
                              ),
                            ),
                            ),
                          ),
                          SizedBox(height: 6.h),
                          // Entry timestamp
                          Text(
                            '🕐 ${_formatPayloadTime(slice, true)}',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  if (hasEntryPhoto && hasExitPhoto) SizedBox(width: 10.w),
                  // Exit photo
                  if (hasExitPhoto)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🚪 Exit',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                          SizedBox(height: 6.h),
                          GestureDetector(
                            onTap: hasExitPhoto
                                ? () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        backgroundColor: Colors.transparent,
                                        child: GestureDetector(
                                          onTap: () => Navigator.pop(context),
                                          child: InteractiveViewer(
                                            child: SecureNetworkImage(
                                              imageUrl: exitPhotoUrl,
                                              fit: BoxFit.contain,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10.r),
                              child: SizedBox(
                                height: 100.h,
                                child: SecureNetworkImage(
                                key: ValueKey('exit_$studentId'),
                                cacheKey: 'exit_$studentId',
                                imageUrl: exitPhotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  color: statusColor.withValues(alpha: 0.1),
                                  child: Icon(Icons.image_not_supported, color: statusColor, size: 24.sp),
                                ),
                              ),
                            ),
                            ),
                          ),
                          SizedBox(height: 6.h),
                          // Exit timestamp
                          Text(
                            '🕐 ${_formatPayloadTime(slice, false)}',
                            style: TextStyle(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppTheme.textGray,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              // Timer or Credits section - moved below photos
              if (newAttendanceCountdown != null || creditedHrLabel != null) ...[
                SizedBox(height: 14.h),
                Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (newAttendanceCountdown != null) ...[
                        Text(
                          '⏱️',
                          style: TextStyle(fontSize: 22.sp),
                        ),
                        SizedBox(width: 10.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Countdown',
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                            Text(
                              newAttendanceCountdown.label,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w900,
                                color: newAttendanceCountdown.overdue ? Colors.red : statusColor,
                              ),
                            ),
                          ],
                        ),
                      ] else if (creditedHrLabel != null) ...[
                        Text(
                          '✅',
                          style: TextStyle(fontSize: 22.sp),
                        ),
                        SizedBox(width: 10.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Credited',
                              style: TextStyle(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                            Text(
                              creditedHrLabel,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                            if (attendanceRemark != null)
                              Text(
                                attendanceRemark,
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SizedBox(height: 14.h),
              // Divider before action buttons
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      statusColor.withValues(alpha: 0.1),
                      statusColor.withValues(alpha: 0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              // Action buttons row
              Row(
                children: [
                  // 📸 View Photos button
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Navigate to student photos screen
                          if (!context.mounted || _instituteId == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentPhotosScreen(
                                studentId: studentId,
                                studentName: name,
                                rollNumber: _formatSrDisplay(srNo),
                                instituteId: _instituteId!,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library, color: statusColor, size: 20.sp),
                              SizedBox(height: 4.h),
                              Text(
                                'Photos',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  // 👤 Face Registration button
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          // Navigate to face registration camera
                          if (!context.mounted || _instituteId == null) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StudentFaceRegistrationWrapper(
                                studentId: studentId,
                                studentName: name,
                                srNo: _formatSrDisplay(srNo),
                                instituteId: _instituteId!,
                                onRegistrationSuccess: () {
                                  // Refresh student list after registration
                                  if (mounted) {
                                    _bootstrapStudentList();
                                  }
                                },
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 8.w),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_add, color: statusColor, size: 20.sp),
                              SizedBox(height: 4.h),
                              Text(
                                'Register',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
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
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }


  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [Colors.white.withOpacity(0.08), Colors.white.withOpacity(0.04)]
              : [Colors.white, Colors.grey.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
        controller: _searchController,
        onChanged: (_) {
          if (mounted) setState(() {});
        },
        decoration: InputDecoration(
          hintText: '🔍 Search name, SR no., year…',
          hintStyle: TextStyle(
            color: isDark ? Colors.white.withOpacity(0.5) : AppTheme.textGray,
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.6 : 0.7),
            size: 24.sp,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark ? Colors.white.withOpacity(0.7) : AppTheme.textGray,
                    size: 20.sp,
                  ),
                  onPressed: () {
                    _debounce?.cancel();
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _page = 0;
                      _students.clear();
                      _hasMore = true;
                    });
                    _loadStudents(reset: true);
                  },
                )
              : null,
          filled: true,
          fillColor: isDark 
              ? Colors.white.withOpacity(0.1) 
              : AppTheme.backgroundGrey,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark 
                  ? Colors.white.withOpacity(0.2) 
                  : AppTheme.primaryBlue.withOpacity(0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark 
                  ? Colors.white.withOpacity(0.2) 
                  : AppTheme.primaryBlue.withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide(
              color: isDark ? Colors.white : AppTheme.primaryBlue,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        ),
        style: TextStyle(
          color: isDark ? Colors.white : AppTheme.textDark,
          fontSize: 14.sp,
        ),
      ),
            ),
          SizedBox(width: 8.w),
          // #5: Photo gallery view toggle
          Tooltip(
            message: _photoGridViewEnabled ? 'List view' : 'Grid view',
            child: IconButton(
              icon: Icon(
                _photoGridViewEnabled ? Icons.list_rounded : Icons.grid_3x3_rounded,
                color: AppTheme.primaryBlue,
                size: 22.sp,
              ),
              onPressed: () {
                setState(() {
                  _photoGridViewEnabled = !_photoGridViewEnabled;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceFilterBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget chip({
      required _StudentAttendanceFilter filter,
      required String label,
      required int count,
    }) {
      final selected = _attendanceFilter == filter;
      return ChoiceChip(
        label: Text('$label ($count)'),
        selected: selected,
        onSelected: (_) {
          if (_attendanceFilter == filter) return;
          setState(() => _attendanceFilter = filter);
        },
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected
              ? Colors.white
              : (isDark ? Colors.white70 : AppTheme.primaryBlue),
        ),
        selectedColor: AppTheme.primaryBlue,
        backgroundColor:
            isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        side: BorderSide(
          color: selected
              ? AppTheme.primaryBlue
              : AppTheme.primaryBlue.withValues(alpha: 0.25),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        showCheckmark: false,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(
            filter: _StudentAttendanceFilter.all,
            label: 'All',
            count: _statsTotal,
          ),
          chip(
            filter: _StudentAttendanceFilter.present,
            label: 'Present',
            count: _statsPresentToday,
          ),
          chip(
            filter: _StudentAttendanceFilter.absent,
            label: 'Absent',
            count: _statsAbsentToday,
          ),
        ],
      ),
    );
  }

  /// ✅ Permanent static photo instructions card
  Widget _buildPhotoInstructionsCard() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => InstructionsScreen(),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryBlue,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.r),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.info_rounded, size: 18),
        label: const Text(
          '📸 View Photo Instructions',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildListProgressHint(int visibleCount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searching = _searchQuery.trim().isNotEmpty;
    final tail = _hasMore
        ? (_attendanceFilter == _StudentAttendanceFilter.all
            ? ' · Scroll for more'
            : ' · Load more to check more')
        : '';
    final noun = searching ? 'matches' : 'students';
    final text = _attendanceFilter == _StudentAttendanceFilter.all
        ? 'Showing $visibleCount of $_studentCount $noun$tail'
        : 'Showing $visibleCount ${_attendanceFilterLabel(_attendanceFilter)} students from ${_students.length} loaded$tail';
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.sp,
          color: isDark ? Colors.white54 : AppTheme.textGray,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildModernCard({required Widget child, required bool isDark}) {
    return Container(
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
          child: child,
    );
  }

  // #8: Better Dialog - Modern dialog with rounded corners and shadow
  Future<T?> _showModernDialog<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    Widget? actions,
    bool dismissible = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppTheme.textDark,
          ),
        ),
        content: content,
        actions: actions != null ? [actions] : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
        elevation: 8,
      ),
    );
  }

  // #9: Error State Handler
  void _handleError(String message) {
    setState(() {
      _errorMessage = message;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        margin: EdgeInsets.all(16.w),
        behavior: SnackBarBehavior.floating,
      ),
    );

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    });
  }

}

/// 📜 Animated scrolling welcome message (marquee - right to left loop)
class _ScrollingWelcomeMessage extends StatefulWidget {
  final String? instituteId;
  final String? instituteName;

  const _ScrollingWelcomeMessage({
    this.instituteId,
    this.instituteName,
  });

  @override
  State<_ScrollingWelcomeMessage> createState() => _ScrollingWelcomeMessageState();
}

class _ScrollingWelcomeMessageState extends State<_ScrollingWelcomeMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  final ScrollController _scrollController = ScrollController();
  String? _instituteName;
  bool _nameLoaded = false;
  double _halfScrollExtent = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    );

    _animationController.addListener(_updateScroll);
    _animationController.repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScroll();
    });

    // Fetch institute name if not provided
    if (widget.instituteName != null) {
      _instituteName = widget.instituteName;
      _nameLoaded = true;
    } else if (widget.instituteId != null && !_nameLoaded) {
      _fetchInstituteName();
    }
  }

  void _initializeScroll() {
    if (!_scrollController.hasClients) return;
    _halfScrollExtent = _scrollController.position.maxScrollExtent / 2;
    _updateScroll();
  }

  void _updateScroll() {
    if (!_scrollController.hasClients || _halfScrollExtent <= 0) return;
    final normalizedValue = _animationController.value;
    final scrollPos = normalizedValue * _halfScrollExtent;
    _scrollController.jumpTo(scrollPos);
  }

  Future<void> _fetchInstituteName() async {
    if (widget.instituteId == null) return;
    if (kDebugMode) {
      debugPrint('🔍 Widget fetching institute name for: ${widget.instituteId}');
    }
    try {
      final result = await appDb
          .from('institutes')
          .select('*')
          .eq('id', widget.instituteId!)
          .maybeSingle();

      if (kDebugMode) {
        debugPrint('📋 Full result: $result');
      }

      if (mounted && result != null) {
        final name = result['name'] ?? '—';
        setState(() {
          _instituteName = name;
          _nameLoaded = true;
        });
        if (kDebugMode) {
          debugPrint('✅ Fetched institute name: $_instituteName');
        }
      } else if (mounted) {
        setState(() {
          _instituteName = '—';
          _nameLoaded = true;
        });
        if (kDebugMode) {
          debugPrint('⚠️ No result for institute: ${widget.instituteId}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching institute name: $e');
      if (mounted) {
        setState(() {
          _instituteName = '—';
          _nameLoaded = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.removeListener(_updateScroll);
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instId = widget.instituteId ?? '—';
    final finalName = widget.instituteName?.isNotEmpty == true
        ? widget.instituteName
        : (_instituteName?.isNotEmpty == true ? _instituteName : null);

    final nameDisplay = finalName != null && finalName.isNotEmpty ? ' ($finalName)' : '';
    final segment = '   👋 Welcome Students - Mark your attendance here  •  Institute: $instId$nameDisplay  •  ';
    // Repeat 4x to ensure seamless loop (first half scrolls, second half mirrors for seamless wrap)
    final message = segment + segment + segment + segment;

    return SizedBox(
      height: 20.h,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          message,
          style: TextStyle(
            color: Colors.white,
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }
}

/// Lightweight value object returned by server-side paginated student queries.
class _StudentPage {
  final List<Map<String, dynamic>> rows;
  final int total;
  final bool hasMore;

  const _StudentPage({
    required this.rows,
    required this.total,
    required this.hasMore,
  });
}
