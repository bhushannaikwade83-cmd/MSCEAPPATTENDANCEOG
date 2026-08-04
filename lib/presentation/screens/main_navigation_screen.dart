import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';
import '../../core/app_db.dart';
import '../../services/geofence_service.dart';
import '../../services/attendance_hours_persistence_service.dart';
import 'admin_home_screen.dart';
import 'student_management_screen.dart';
import 'attendance_reports_screen.dart';
import 'institute_report_screen.dart';
import 'add_institute_attendance_user_screen.dart';
import 'gps_settings_screen.dart';
import '../widgets/modern_bottom_nav_bar.dart';
import '../widgets/session_monitor.dart';
import '../../core/theme/app_theme.dart';
import 'institute_location_gate_screen.dart';

/// Main Navigation Screen with Bottom Navigation Bar
/// Provides easy access to all features
class MainNavigationScreen extends StatefulWidget {
  static const routeName = '/main-navigation';

  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  String? _instituteId;
  List<Widget> _screens = [];

  @override
  void initState() {
    super.initState();
    _buildScreens(); // Build with null instituteId first
    _loadInstituteId();
    WidgetsBinding.instance.addObserver(this);

    // Incremental credited-hours backfill (one small batch; skips when done).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(AttendanceHoursPersistenceService.maybeBackfillOnLogin());
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfAdminNeedsGps());
  }

  Future<void> _loadInstituteId() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      final adminData = await appDb
          .from('admin_users')
          .select('institute_id')
          .eq('user_id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _instituteId = adminData['institute_id']?.toString();
          print('📚 MainNav loaded instituteId: $_instituteId');
          _buildScreens();
        });
      }
    } catch (e) {
      print('❌ Error loading instituteId: $e');
    }
  }

  void _buildScreens() {
    _screens = [
      const AdminHomeScreen(key: PageStorageKey('main-admin-home')),
      const AddInstituteAttendanceUserScreen(key: PageStorageKey('main-add-user')),
      const StudentManagementScreen(key: PageStorageKey('main-students')),
      const GpsSettingsScreen(key: PageStorageKey('main-gps')),
      AttendanceReportsScreen(
        key: const PageStorageKey('main-student-reports'),
        instituteId: _instituteId,
      ),
      InstituteReportScreen(
        key: const PageStorageKey('main-institute-report'),
        instituteId: _instituteId,
        startDate: DateTime.now().subtract(const Duration(days: 7)),
        endDate: DateTime.now()),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted || SessionMonitor.shouldSkipResumeLockForCamera) return;
        final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
        if (!mounted || !ok) return;
        final gate = await GeofenceService().attendanceLocationGateForCurrentUser();
        if (!mounted || gate['allowed'] == true) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          InstituteLocationGateScreen.routeName,
          (_) => false,
          arguments: {'resumeRoute': MainNavigationScreen.routeName},
        );
      });
    }
  }

  Future<void> _redirectIfAdminNeedsGps() async {
    if (!mounted) return;
    final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
    if (!mounted) return;
    if (!ok) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        GpsSettingsScreen.routeName,
        (route) => false,
        arguments: {'mandatory': true, 'fromLogin': true},
      );
      return;
    }
    final gate = await GeofenceService().attendanceLocationGateForCurrentUser();
    if (!mounted || gate['allowed'] == true) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      InstituteLocationGateScreen.routeName,
      (_) => false,
      arguments: {'resumeRoute': MainNavigationScreen.routeName},
    );
  }

  Future<void> _onNavItemTapped(int index) async {
    // Add user (1), Student Reports (4), and Institute Report (5) require a locked attendance GPS zone for admins.
    if (index == 1 || index == 4 || index == 5) {
      final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lock your attendance zone in GPS Settings before adding users or viewing reports.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        setState(() => _currentIndex = 3);
        _pageController.jumpToPage(3);
        return;
      }
    }
    setState(() => _currentIndex = index);
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final navSubtitles = <String>[
      l10n.mainNavSubtitleAdmin,
      l10n.mainNavSubtitleInstructor,
      l10n.mainNavSubtitleStudent,
      l10n.mainNavSubtitleGps,
      'Student Reports',
      'Institute Report',
    ];
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        // Pop already happened if didPop is true, no action needed
        // If didPop is false, pop was prevented (no previous route), also no action needed
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: AppTheme.backgroundGrey,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GovPortalHeader(
              secondaryLine: navSubtitles[_currentIndex],
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                children: _screens,
              ),
            ),
          ],
        ),
      bottomNavigationBar: ModernBottomNavBar(
        selectedIndex: _currentIndex,
        onTap: (i) => _onNavItemTapped(i),
      ),
      ),
    );
  }
}


/// Search Screen
class _SearchScreen extends StatefulWidget {
  const _SearchScreen();

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        title: const Text(
          'Search',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search students, attendance...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryBlue),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                ),
                filled: true,
                fillColor: AppTheme.backgroundGrey,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          
          // Search Results
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildEmptyState()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Search for students or attendance',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    // Placeholder search results (wire to your data source when needed)
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSearchResultItem('Students', Icons.person, 'Search students by name or roll number'),
        _buildSearchResultItem('Classes', Icons.groups, 'Find subjects and schedules'),
        _buildSearchResultItem('Attendance', Icons.calendar_today, 'Search attendance records'),
        _buildSearchResultItem('Reports', Icons.bar_chart, 'View attendance reports'),
      ],
    );
  }

  Widget _buildSearchResultItem(String title, IconData icon, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primaryBlue, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
