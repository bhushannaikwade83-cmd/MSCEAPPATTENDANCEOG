import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:ui';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/institute_id_display.dart';
import '../../core/supabase_maps.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';
import '../../core/utils/professional_messaging.dart';
import '../../services/auth_service.dart';
import '../../services/offline_service.dart';
import '../../services/error_handler.dart';
import '../../services/theme_service.dart';
import '../../services/session_manager.dart';
import '../../services/device_performance_service.dart';
import '../../core/theme/app_theme.dart';
import '../screens/login_screen.dart';
import 'add_institute_attendance_user_screen.dart';
import 'student_management_screen.dart';
import 'attendance_reports_screen.dart';
import 'institute_report_screen.dart';
import 'attendance_calendar_screen.dart';
import 'attendance_trend_screen.dart';
import 'auto_face_scan_screen.dart';
import 'help_desk_screen.dart';
import 'security_dashboard_screen.dart';
import '../widgets/quick_stats_widget.dart';
import '../widgets/support_email_footer.dart';
import '../../services/institute_lecture_timing_service.dart';
import '../../services/b2b_storage_service.dart';
import '../../services/institute_realtime_sync_service.dart';
import '../../services/stale_attendance_reconciliation_service.dart';
import '../../services/geofence_service.dart';

class AdminHomeScreen extends StatefulWidget {
  static const routeName = '/admin-home';
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final InstituteLectureTimingService _lectureTimingService = InstituteLectureTimingService();
  String? _instituteId;
  bool _isLoadingInstitute = true;
  Map<String, dynamic>? _instituteTiming;
  Map<String, dynamic>? _instituteData;

  // Institute open/close/holiday removed: attendance is always available every day.
  StreamSubscription<InstituteSyncEvent>? _syncSubscription;
  Timer? _syncDebounce;
  Timer? _statsRefreshTimer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  
  String get _todayDateId => DateTime.now().toString().split(' ')[0];

  Future<bool> _ensureLockedGpsForRestrictedActions() async {
    final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
    if (!mounted) return false;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open GPS Settings (bottom bar) and lock your attendance zone before using this feature.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }
    return ok;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _fadeController.forward();
    _loadInstituteId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload timing when screen becomes visible again
    if (_instituteId != null && _instituteTiming == null) {
      _loadInstituteTiming(_instituteId!);
    }
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _statsRefreshTimer?.cancel();
    _syncSubscription?.cancel();
    final iid = _instituteId;
    if (iid != null && iid.isNotEmpty) {
      InstituteRealtimeSyncService.instance.release(iid);
    }
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = appDb.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() => _isLoadingInstitute = false);
        }
        if (mounted) await _loadDashboardStats();
        return;
      }

      final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      final instituteId = row?['institute_id'] as String?;
      if (instituteId != null && instituteId.isNotEmpty) {
        if (mounted) {
          setState(() {
            _instituteId = instituteId;
          });
        }
        if (!mounted) return;
        await InstituteRealtimeSyncService.instance.retain(instituteId);
        if (!mounted) return;
        _syncSubscription?.cancel();
        _syncSubscription = InstituteRealtimeSyncService.instance
            .watch(instituteId)
            .listen((event) {
          if (!mounted) return;
          _syncDebounce?.cancel();
          _syncDebounce = Timer(const Duration(milliseconds: 700), () async {
            if (!mounted || _instituteId == null) return;
            if (event.type == 'institute' || event.type == 'gps') {
              await _loadInstituteTiming(_instituteId!);
            }
            if (event.type == 'students' ||
                event.type == 'attendance' ||
                event.type == 'institute') {
              if (!mounted) return;
              await _loadDashboardStats();
            }
          });
        });
        _loadInstituteTiming(instituteId);
      }
      if (mounted) {
        setState(() => _isLoadingInstitute = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingInstitute = false);
        if (kDebugMode) {
          final errorResult = ErrorHandler.formatErrorForUI(
            e,
            context: 'loadInstituteId',
            appType: 'admin',
          );
          debugPrint('Error loading institute: ${errorResult['error']}');
        }
      }
    }
    if (mounted) await _loadDashboardStats();

    // Refresh dashboard stats periodically (was 500ms — very heavy on battery/network).
    _statsRefreshTimer = Timer.periodic(
      DevicePerformanceService.backgroundStatsPollInterval,
      (_) {
      if (mounted) _loadDashboardStats();
    },
    );
  }

  Future<void> _loadInstituteTiming(String instituteId) async {
    try {
      final timing = await _lectureTimingService.getInstituteTiming(instituteId);
      if (mounted) {
        setState(() {
          _instituteTiming = timing;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading institute timing: $e');
      }
    }
    // Also load institute info
    _loadInstituteInfo(instituteId);
  }

  Future<void> _loadInstituteInfo(String instituteId) async {
    try {
      final data = await appDb
          .from('institutes')
          .select('id, name, address')
          .eq('id', instituteId)
          .single();
      if (mounted) {
        setState(() {
          _instituteData = data;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading institute info: $e');
      }
    }
  }

  // Institute status (open/close/holiday) removed.

  Future<void> _confirmOneWayDecision({
    required String actionLabel,
    required String warningText,
    required Future<void> Function() onConfirm,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppTheme.accentRed),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                '$actionLabel Confirmation',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          '$warningText\n\nThis is a one-way process for today and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await onConfirm();
    }
  }

  /// Resolves a full display name when `profiles.name` is empty or only first name in DB.
  String _composeAdminFullName(Map<String, dynamic>? profileRow, User user) {
    String p(String? s) => (s ?? '').trim();

    final fromProfile = p(profileRow?['name'] as String?);
    if (fromProfile.isNotEmpty) return fromProfile;

    final meta = user.userMetadata;
    if (meta != null && meta.isNotEmpty) {
      final full = p(meta['full_name']?.toString());
      if (full.isNotEmpty) return full;
      final nm = p(meta['name']?.toString());
      if (nm.isNotEmpty) return nm;
      final fn = p(meta['first_name']?.toString() ?? meta['given_name']?.toString());
      final ln = p(meta['last_name']?.toString() ?? meta['family_name']?.toString());
      if (fn.isNotEmpty || ln.isNotEmpty) return '$fn $ln'.trim();
    }

    final email = p(profileRow?['email'] as String?).isNotEmpty
        ? p(profileRow?['email'] as String?)
        : p(user.email);
    if (email.contains('@')) {
      final local = email.split('@').first;
      final pretty = local.replaceAll(RegExp(r'[._+\-]+'), ' ').trim();
      if (pretty.isNotEmpty) return pretty;
    }
    return 'Admin';
  }

  // Dashboard counters – loaded once on init, refreshed only when user pulls-to-refresh.
  String? _profileName;
  int _studentCount = 0;
  int _todayAttendanceCount = 0;
  bool _statsLoading = true;

  Future<void> _loadDashboardStats() async {
    if (!mounted) return;
    if (mounted) setState(() => _statsLoading = true);
    try {
      final u = appDb.auth.currentUser;
      if (u == null) {
        if (mounted) {
          setState(() {
            _profileName = null;
            _studentCount = 0;
            _todayAttendanceCount = 0;
            _statsLoading = false;
          });
        }
        return;
      }

      final profileRow = await appDb
          .from('profiles')
          .select('name, email')
          .eq('id', u.id)
          .maybeSingle();
      final name = _composeAdminFullName(profileRow, u);

      int sc = 0;
      int att = 0;
      final iid = _instituteId;
      if (iid != null && iid.isNotEmpty) {
        final studentRes = await appDb
            .from('students')
            .select('id')
            .eq('institute_id', iid)
            .count(CountOption.exact);
        sc = studentRes.count;

        final code = await instituteCodeForId(iid);
        final attRows = await appDb
            .from('attendance_in_out')
            .select('student_id,sr_no,type,additional')
            .eq('institute_code', code)
            .eq('attendance_date', _todayDateId);
        final uniqueToday = <String>{};
        for (final r in attRows) {
          final m = r as Map<String, dynamic>;
          final type = (m['type']?.toString() ?? '').toLowerCase();
          final add = m['additional'];
          final status = (add is Map ? add['status'] : null)?.toString().toLowerCase();
          final isPresent = status == 'present' || (status == null && type == 'exit');
          if (!isPresent) continue;
          final sid = (m['student_id'] as String?)?.trim() ?? '';
          final sr = (m['sr_no'] as String?)?.trim() ?? '';
          final key = sid.isNotEmpty ? sid : sr;
          if (key.isNotEmpty) uniqueToday.add(key);
        }
        att = uniqueToday.length;
      }

      if (!mounted) return;
      setState(() {
        _profileName = name;
        _studentCount = sc;
        _todayAttendanceCount = att;
        _statsLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Dashboard stats error: $e');
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Prevent back button from exiting app - admin home is main screen
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
        body: SafeArea(
          top: false,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                Expanded(
                  child: ResponsiveScrollBody(
                        padding: EdgeInsets.all(16.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileGovCard(isDark),
                            SizedBox(height: 16.h),

                            // ── Institute Information Card (Name, Address, ID) ──
                            if (_instituteId != null && _instituteData != null)
                              _buildInstituteInfoCard(isDark),
                            if (_instituteId != null && _instituteData != null)
                              SizedBox(height: 16.h),

                            // Institute Open/Close/Holiday removed (attendance always open)

                            // Date and Clock Times
                            _buildDateAndClockTimes(isDark),
                            SizedBox(height: 20.h),

                            // Institute Timing Card
                            if (_instituteTiming != null)
                              _buildInstituteTimingCard(isDark),
                            if (_instituteTiming != null)
                              SizedBox(height: 20.h),

                            // Enhanced Quick Stats Widget (Today's Stats)
                            if (_instituteId != null)
                              QuickStatsWidget(
                                instituteId: _instituteId!,
                              ),
                            SizedBox(height: 20.h),

                            // Quick Actions
                            _buildQuickActions(isDark),
                            SizedBox(height: 20.h),

                            const Center(child: SupportEmailFooter()),
                            SizedBox(height: 16.h),

                            SizedBox(height: 24.h),
                          ],
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernAppBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(Icons.dashboard_rounded, color: Colors.white, size: 24.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  'Attendance Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: Responsive.fontSize(context, 20).sp,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              FutureBuilder<int>(
                future: OfflineService.getPendingCount(),
                builder: (context, snapshot) {
                  final pendingCount = snapshot.data ?? 0;
                  if (pendingCount > 0) {
                    return Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.cloud_off, color: Colors.white, size: 24.sp),
                          onPressed: () async {
                            if (_instituteId != null) {
                              await OfflineService.syncPendingAttendance(_instituteId!);
                              if (mounted) setState(() {});
                            }
                          },
                          tooltip: '$pendingCount pending sync',
                        ),
                        Positioned(
                          right: 8.w,
                          top: 8.h,
                          child: Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentRed,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.h),
                            child: Text(
                              '$pendingCount',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
              IconButton(
                icon: Icon(Icons.help_outline, color: Colors.white, size: 24.sp),
                onPressed: () {
                  Navigator.pushNamed(context, HelpDeskScreen.routeName);
                },
                tooltip: 'Help & Instructions',
              ),
              IconButton(
                icon: Icon(Icons.security, color: Colors.white, size: 24.sp),
                onPressed: () {
                  Navigator.pushNamed(context, SecurityDashboardScreen.routeName);
                },
                tooltip: 'Security Dashboard',
              ),
              Consumer<ThemeService>(
                builder: (context, themeService, _) {
                  return IconButton(
                    icon: Icon(
                      themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                      color: Colors.white,
                      size: 24.sp,
                    ),
                    onPressed: () => themeService.toggleTheme(),
                    tooltip: themeService.isDarkMode ? 'Light Mode' : 'Dark Mode',
                  );
                },
              ),
              IconButton(
                icon: Icon(Icons.logout, color: Colors.white, size: 24.sp),
                onPressed: () async {
                  await SessionManager.signOut();
                  if (!mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil(
                    LoginScreen.routeName,
                    (route) => false,
                  );
                },
                tooltip: 'Logout',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24.r),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5.w),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20.r,
                spreadRadius: 5.r,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Row(
                children: [
                  Container(
                    width: 60.w,
                    height: 60.h,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(15.r),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 30.sp),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: Responsive.fontSize(context, 24).sp,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Manage attendance & students',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14.sp,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildCalendarButton() {
    return Container(
      height: 60.h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_instituteId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceCalendarScreen(
                    instituteId: _instituteId!,
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                Icon(Icons.calendar_today, color: Colors.white, size: 22.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'View Attendance Calendar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendButton() {
    return Container(
      height: 60.h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_instituteId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceTrendScreen(
                    instituteId: _instituteId!,
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Row(
              children: [
                Icon(Icons.show_chart, color: Colors.white, size: 22.sp),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'View Attendance Trend',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildManagementCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> items,
  }) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items,
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.7), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: child,
        ),
      ),
    );
  }

  Widget _buildProfileGovCard(bool isDark) {
    final avatar = Responsive.pctShortestSide(context, 0.12).clamp(48.0, 64.0);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentSaffron.withOpacity(isDark ? 0.15 : 0.08),
            AppTheme.accentSaffron.withOpacity(isDark ? 0.08 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: AppTheme.accentSaffron.withOpacity(isDark ? 0.4 : 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentSaffron.withOpacity(isDark ? 0.2 : 0.1),
            blurRadius: 16.r,
            offset: Offset(0, 6.h),
            spreadRadius: 1,
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          // 👤 Avatar with gradient
          Container(
            width: avatar,
            height: avatar,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accentSaffron.withOpacity(0.3),
                  AppTheme.accentSaffron.withOpacity(0.15),
                ],
              ),
              border: Border.all(
                color: AppTheme.accentSaffron.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentSaffron.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.person_rounded,
                color: AppTheme.primaryBlue, size: avatar * 0.5),
          ),
          SizedBox(width: 14.w),
          // 👋 Welcome Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (_profileName == null || _profileName == 'Admin')
                      ? '👋 Welcome'
                      : '👋 Welcome, Mr $_profileName',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textDark,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  'Best wishes for your day! 🌟',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.75)
                        : AppTheme.textGray,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          FutureBuilder<int>(
            future: OfflineService.getPendingCount(),
            builder: (context, snapshot) {
              final pendingCount = snapshot.data ?? 0;
              if (pendingCount <= 0) return const SizedBox.shrink();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(Icons.cloud_off, color: AppTheme.primaryBlue, size: 22.sp),
                    onPressed: () async {
                      if (_instituteId != null) {
                        await OfflineService.syncPendingAttendance(_instituteId!);
                        if (mounted) setState(() {});
                      }
                    },
                    tooltip: '$pendingCount pending sync',
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: EdgeInsets.all(4.w),
                      decoration: const BoxDecoration(
                        color: AppTheme.accentRed,
                        shape: BoxShape.circle,
                      ),
                      constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.h),
                      child: Text(
                        '$pendingCount',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.help_outline, color: AppTheme.primaryBlue, size: 22.sp),
            onPressed: () {
              Navigator.pushNamed(context, HelpDeskScreen.routeName);
            },
            tooltip: 'Help & Instructions',
          ),
          IconButton(
            icon: Icon(Icons.security, color: AppTheme.primaryBlue, size: 22.sp),
            onPressed: () {
              Navigator.pushNamed(context, SecurityDashboardScreen.routeName);
            },
            tooltip: 'Security Dashboard',
          ),
          Consumer<ThemeService>(
            builder: (context, themeService, _) {
              return IconButton(
                icon: Icon(
                  themeService.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  color: AppTheme.primaryBlue,
                  size: 22.sp,
                ),
                onPressed: () => themeService.toggleTheme(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: AppTheme.primaryBlue, size: 22.sp),
            onPressed: () async {
              await SessionManager.signOut();
              if (!mounted) return;
              Navigator.of(context).pushNamedAndRemoveUntil(
                LoginScreen.routeName,
                (route) => false,
              );
            },
            tooltip: 'Logout',
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndClockTimes(bool isDark) {
    final now = DateTime.now();
    final currentDate = DateFormat('EEEE, d MMMM yyyy').format(now);
    final currentTime = DateFormat('hh:mm a').format(now);

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
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
            blurRadius: 12.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          // 📅 Calendar Icon
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryBlue.withOpacity(0.25),
                  AppTheme.primaryBlue.withOpacity(0.12),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.calendar_today_rounded,
                color: AppTheme.primaryBlue, size: 22.sp),
          ),
          SizedBox(width: 14.w),
          // 📅 Date and Time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  currentDate,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.textDark,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                SizedBox(height: 4.h),
                Text(
                  currentTime,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryBlue.withOpacity(0.8),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          // 👥 Students Count Badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryBlue,
                  AppTheme.primaryBlue.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_rounded, color: Colors.white, size: 18.sp),
                SizedBox(height: 3.h),
                Text(
                  '$_studentCount',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Students',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 9.sp,
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

  Widget _buildInfoCard(
    String title,
    IconData icon,
    Color color,
    bool isDark,
    Widget Function() contentBuilder,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: contentBuilder(),
    );
  }


  Widget _buildInstituteTimingCard(bool isDark) {
    if (_instituteTiming == null) return const SizedBox.shrink();
    
    final openTime = _instituteTiming!['openTime'] as TimeOfDay;
    final closeTime = _instituteTiming!['closeTime'] as TimeOfDay;
    final duration = _instituteTiming!['durationMinutes'] as int? ?? 60;
    
    final openTimeStr = '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}';
    final closeTimeStr = '${closeTime.hour.toString().padLeft(2, '0')}:${closeTime.minute.toString().padLeft(2, '0')}';
    
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withValues(alpha: 0.1),
            AppTheme.primaryBlueDark.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: AppTheme.primaryBlue,
              size: 28.sp,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Institute hours',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppTheme.textDark.withValues(alpha: 0.7),
                  ),
                ),
                SizedBox(height: 4.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: Icon(
                        Icons.access_time,
                        size: 16.sp,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8.w,
                        runSpacing: 6.h,
                        children: [
                          Text(
                            '$openTimeStr - $closeTimeStr',
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.textDark,
                            ),
                          ),
                          if (duration == 120)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: AppTheme.accentOrange.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                'Late Admission',
                                style: TextStyle(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentOrange,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  duration == 120
                      ? '120 minutes per slot (2 hours)'
                      : '60 minutes per slot (1 hour)',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white60 : AppTheme.textDark.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstituteInfoCard(bool isDark) {
    final instituteName = _instituteData?['name'] as String? ?? 'Unknown Institute';
    final instituteAddress = _instituteData?['address'] as String? ?? 'Address not set';
    final instituteId = _instituteData?['id'] as String? ?? 'N/A';

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
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
            blurRadius: 16.r,
            offset: Offset(0, 6.h),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Icon
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
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
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.school_rounded,
                    color: AppTheme.primaryBlue, size: 26.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  instituteName,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textDark,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          // Divider
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppTheme.primaryBlue.withOpacity(0.2),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          SizedBox(height: 14.h),
          // Location
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_rounded,
                  color: AppTheme.primaryBlue, size: 18.sp),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  instituteAddress,
                  style: TextStyle(
                    color: isDark ? Colors.white.withOpacity(0.8) : AppTheme.textGray,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // ID Badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(
                color: AppTheme.primaryBlue.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.badge_rounded,
                    color: AppTheme.primaryBlue, size: 14.sp),
                SizedBox(width: 6.w),
                Text(
                  'ID: ${formatInstituteIdForDisplay(instituteId)}',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textDark,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /*
  // Institute open/close/holiday UI removed.
  Widget _buildInstituteStatusCard(bool isDark) {
    final status = _todayStatus?['status'] as String? ?? 'unknown';
    final isDayFinalized = _todayStatus?['dayFinalized'] == true;
    final isDecisionLocked = _isOpenHolidayDecisionLocked();
    final canCloseNow = _canCloseInstituteNow();
    final today = DateFormat('EEE, d MMM yyyy').format(DateTime.now());

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (status) {
      case 'open':
        statusColor = AppTheme.accentGreen;
        statusIcon = Icons.domain_verification_rounded;
        statusLabel = 'Open';
        break;
      case 'holiday':
        statusColor = AppTheme.accentOrange;
        statusIcon = Icons.beach_access_rounded;
        statusLabel = 'Holiday';
        break;
      case 'closed':
        statusColor = AppTheme.accentRed;
        statusIcon = Icons.domain_disabled_rounded;
        statusLabel = 'Closed';
        break;
      default:
        statusColor = isDark ? Colors.white54 : Colors.grey.shade500;
        statusIcon = Icons.help_outline_rounded;
        statusLabel = 'Not Set';
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.15),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 24.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Institute Status — Today',
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: isDark ? Colors.white60 : Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        today,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isDark ? Colors.white38 : Colors.grey.shade400,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Current status badge
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            // Description
            Text(
              status == 'open'
                  ? 'Attendance is being tracked. Students marking entry will be counted for today.'
                  : status == 'holiday'
                  ? 'Today is a holiday. Attendance will not be counted — students are marked accordingly.'
                  : status == 'closed'
                  ? 'Institute is closed. Attendance will not be counted for today.'
                  : 'Set today\'s status to control attendance tracking and auto-absence.',
              style: TextStyle(
                fontSize: 13.sp,
                color: isDark ? Colors.white70 : AppTheme.textDark.withValues(alpha: 0.7),
              ),
            ),
            if (status == 'closed' && isDayFinalized) ...[
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppTheme.accentRed.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999.r),
                  border: Border.all(
                    color: AppTheme.accentRed.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_rounded,
                      size: 14.sp,
                      color: AppTheme.accentRed,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'Day Finalized - Reopen disabled for today',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.accentRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (isDecisionLocked) ...[
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999.r),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 14.sp,
                      color: AppTheme.primaryBlue,
                    ),
                    SizedBox(width: 6.w),
                    Text(
                      'Today\'s Open/Holiday choice is locked.',
                      style: TextStyle(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 16.h),
            // Action buttons
            if (_isChangingStatus)
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.h),
                  child: SizedBox(
                    width: 24.w,
                    height: 24.w,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: statusColor),
                  ),
                ),
              )
            else
              Row(
                children: [
                  // Open button
                  Expanded(
                    child: _buildStatusButton(
                      label: isDayFinalized && status == 'closed'
                          ? '🟢  Open (Locked)'
                          : '🟢  Open',
                      color: AppTheme.accentGreen,
                      isActive: status == 'open',
                      isDark: isDark,
                      onTap: (isDayFinalized && status == 'closed') || isDecisionLocked
                          ? null
                          : () => _confirmOneWayDecision(
                                actionLabel: 'Open Institute',
                                warningText:
                                    'If you choose Open now, Holiday option will be disabled for today.',
                                onConfirm: () => _changeInstituteStatus('open'),
                              ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // Holiday button
                  Expanded(
                    child: _buildStatusButton(
                      label: '🏖️  Holiday',
                      color: AppTheme.accentOrange,
                      isActive: status == 'holiday',
                      isDark: isDark,
                      onTap: isDecisionLocked || (isDayFinalized && status == 'closed')
                          ? null
                          : () => _confirmOneWayDecision(
                                actionLabel: 'Mark Holiday',
                                warningText:
                                    'If you choose Holiday now, Open option will be disabled for today.',
                                onConfirm: _showHolidayReasonDialog,
                              ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // Close button
                  Expanded(
                    child: _buildStatusButton(
                      label: _isAutoMarkingAbsent
                          ? '⏳ Marking...'
                          : (canCloseNow ? '🔴  Close' : '🔒 Close'),
                      color: AppTheme.accentRed,
                      isActive: status == 'closed',
                      isDark: isDark,
                      onTap: (_isChangingStatus ||
                              _isAutoMarkingAbsent ||
                              !canCloseNow)
                          ? null
                          : () => _confirmCloseInstitute(),
                    ),
                  ),
                ],
              ),
            if (!canCloseNow && status != 'closed') ...[
              SizedBox(height: 8.h),
              Text(
                _closeButtonHelperText(),
                style: TextStyle(
                  fontSize: 12.sp,
                  color: isDark
                      ? Colors.white70
                      : AppTheme.textDark.withValues(alpha: 0.65),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusButton({
    required String label,
    required Color color,
    required bool isActive,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: isActive ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: isActive ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: color.withValues(alpha: isActive ? 0 : 0.4)),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : color,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Future<void> _showHolidayReasonDialog() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.beach_access_rounded, color: AppTheme.accentOrange, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mark as Holiday',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        children: [
          _buildHolidayReasonOption(ctx, 'Holiday'),
          _buildHolidayReasonOption(ctx, 'Government Holiday'),
          _buildHolidayReasonOption(ctx, 'Festival'),
          _buildHolidayReasonOption(ctx, 'Emergency Closure'),
          _buildHolidayReasonOption(ctx, 'Other Holiday'),
          const Divider(height: 8),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || reason == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    await _changeInstituteStatus('holiday', holidayReason: reason);
  }

  Widget _buildHolidayReasonOption(BuildContext ctx, String reason) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(ctx).pop(reason),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 18, color: AppTheme.accentOrange),
          const SizedBox(width: 10),
          Expanded(child: Text(reason)),
        ],
      ),
    );
  }
  */

  Widget _buildQuickActions(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🎯 Modern Section Header
            Container(
              margin: EdgeInsets.only(bottom: 16.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryBlue.withOpacity(0.2),
                          AppTheme.primaryBlue.withOpacity(0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: AppTheme.primaryBlue.withOpacity(0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.flash_on_rounded,
                            color: AppTheme.primaryBlue, size: 16.sp),
                        SizedBox(width: 6.w),
                        Text(
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 18).sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppTheme.textDark,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Spacer(),
                  Container(
                    width: 4.w,
                    height: 24.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppTheme.primaryBlue,
                          AppTheme.primaryGreen,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Calendar',
                    Icons.calendar_today,
                    AppTheme.primaryGreen,
                    () {
                      if (_instituteId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceCalendarScreen(
                              instituteId: _instituteId!,
                            ),
                          ),
                        );
                      }
                    },
                    isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildActionCard(
                    'Institute instructor',
                    Icons.person_add_alt_1,
                    AppTheme.primaryBlue,
                    () async {
                      if (!await _ensureLockedGpsForRestrictedActions()) return;
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddInstituteAttendanceUserScreen(),
                        ),
                      );
                    },
                    isDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Trends',
                    Icons.show_chart,
                    AppTheme.accentOrange,
                    () {
                      if (_instituteId != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceTrendScreen(
                              instituteId: _instituteId!,
                            ),
                          ),
                        );
                      }
                    },
                    isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildActionCard(
                    'Student Reports',
                    Icons.bar_chart,
                    AppTheme.accentGreen,
                    () async {
                      if (!await _ensureLockedGpsForRestrictedActions()) return;
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AttendanceReportsScreen()),
                      );
                    },
                    isDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: _buildActionCard(
                    'Institute Report',
                    Icons.assessment,
                    AppTheme.primaryBlue,
                    () async {
                      if (!await _ensureLockedGpsForRestrictedActions()) return;
                      if (!mounted) return;
                      Navigator.pushNamed(
                        context,
                        InstituteReportScreen.routeName,
                        arguments: {
                          'instituteId': _instituteId,
                          'startDate': DateTime.now().subtract(const Duration(days: 7)),
                          'endDate': DateTime.now(),
                        },
                      );
                    },
                    isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _buildActionCard(
                    'Help',
                    Icons.help_center_rounded,
                    AppTheme.accentOrange,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HelpDeskScreen()),
                    ),
                    isDark,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            _buildActionCard(
              'Student Attendance',
              Icons.how_to_reg_rounded,
              AppTheme.primaryGreen,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const StudentManagementScreen(),
                ),
              ),
              isDark,
            ),
            SizedBox(height: 12.h),

            // Logout Button - Full Width
            _buildLogoutButton(isDark),
          ],
        );
      },
    );
  }

  Widget _buildLogoutButton(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.accentRed,
                AppTheme.accentRed.withValues(alpha: 0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentRed.withValues(alpha: 0.3),
                blurRadius: 12.r,
                offset: Offset(0, 4.h),
              ),
            ],
          ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            // Show confirmation dialog
            final shouldLogout = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20.r),
                ),
                title: Row(
                  children: [
                    Icon(Icons.logout, color: AppTheme.accentRed, size: 28.sp),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'Confirm Logout',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 20).sp,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                content: Text(
                  'Are you sure you want to logout?',
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: AppTheme.textDark,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    ),
                    child: Text('Logout', style: TextStyle(fontSize: 14.sp)),
                  ),
                ],
              ),
            );

            if (shouldLogout == true && mounted) {
              await SessionManager.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                  (route) => false,
                );
              }
            }
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: Colors.white, size: 24.sp),
                SizedBox(width: 12.w),
                Flexible(
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: Responsive.fontSize(context, 18).sp,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      );
      },
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, VoidCallback onTap, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 600 + title.length * 30),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value,
                    child: child,
                  ),
                );
              },
              child: Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  // 🌈 Modern gradient based on color
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(isDark ? 0.15 : 0.08),
                      color.withOpacity(isDark ? 0.08 : 0.03),
                    ],
                  ),
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: color.withOpacity(isDark ? 0.4 : 0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    // Primary shadow
                    BoxShadow(
                      color: color.withOpacity(isDark ? 0.25 : 0.15),
                      blurRadius: 16.r,
                      offset: Offset(0, 6.h),
                      spreadRadius: 1,
                    ),
                    // Glow effect
                    BoxShadow(
                      color: color.withOpacity(0.1),
                      blurRadius: 24.r,
                      offset: Offset(0, 12.h),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // 🎯 Icon Container with Glow
                    Container(
                      width: 48.r,
                      height: 48.r,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withOpacity(0.25),
                            color.withOpacity(0.12),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 24.sp),
                    ),
                    SizedBox(width: 12.w),
                    // 📱 Text Section
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppTheme.textDark,
                              letterSpacing: 0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.left,
                          ),
                          SizedBox(height: 2.h),
                          Container(
                            height: 2.h,
                            width: 24.w,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withOpacity(0.3)],
                              ),
                              borderRadius: BorderRadius.circular(1.r),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ➜ Arrow indicator
                    Icon(
                      Icons.arrow_forward_rounded,
                      color: color.withOpacity(0.6),
                      size: 18.sp,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturesGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'All Features',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                // FeaturesGridScreen is not implemented yet
                // Navigator.push(
                //   context,
                //   MaterialPageRoute(
                //     builder: (_) => FeaturesGridScreen(instituteId: _instituteId),
                //   ),
                // );
              },
              child: const Text(
                'View All',
                style: TextStyle(color: AppTheme.primaryBlue),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: [
            _buildFeatureGridCard(
              title: 'Institute instructor',
              icon: Icons.person_add_alt_1,
              color: AppTheme.primaryBlue,
              onTap: () async {
                if (!await _ensureLockedGpsForRestrictedActions()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddInstituteAttendanceUserScreen()),
                );
              },
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Auto Face Scan',
              icon: Icons.face_retouching_natural,
              color: AppTheme.primaryBlue,
              onTap: () async {
                if (!await _ensureLockedGpsForRestrictedActions()) return;
                if (!mounted) return;
                Navigator.pushNamed(
                  context,
                  AutoFaceScanScreen.routeName,
                  arguments: {'instituteId': _instituteId},
                );
              },
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Students',
              icon: Icons.school,
              color: AppTheme.primaryGreen,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StudentManagementScreen()),
              ),
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Students Report',
              icon: Icons.bar_chart,
              color: AppTheme.accentOrange,
              onTap: () async {
                if (!await _ensureLockedGpsForRestrictedActions()) return;
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AttendanceReportsScreen()),
                );
              },
              isDark: isDark,
            ),
            _buildFeatureGridCard(
              title: 'Institute Report',
              icon: Icons.assessment,
              color: AppTheme.primaryBlue,
              onTap: () async {
                if (!await _ensureLockedGpsForRestrictedActions()) return;
                if (!mounted) return;
                Navigator.pushNamed(
                  context,
                  InstituteReportScreen.routeName,
                  arguments: {
                    'instituteId': _instituteId,
                    'startDate': DateTime.now().subtract(const Duration(days: 7)),
                    'endDate': DateTime.now(),
                  },
                );
              },
              isDark: isDark,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureGridCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: color,
                size: 32,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
