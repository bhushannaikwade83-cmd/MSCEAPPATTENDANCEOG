import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/app_db.dart';
import '../../core/institute_dashboard_stats.dart';
import '../../core/supabase_maps.dart';
import '../../core/utils/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/institute_realtime_sync_service.dart';
import '../../services/offline_service.dart';

/// Modern Admin Dashboard - Similar to the reference design
class ModernAdminDashboard extends StatefulWidget {
  static const routeName = '/modern-admin-dashboard';
  const ModernAdminDashboard({super.key});

  @override
  State<ModernAdminDashboard> createState() => _ModernAdminDashboardState();
}

class _ModernAdminDashboardState extends State<ModernAdminDashboard> {
  String? _instituteId;
  StreamSubscription<InstituteSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadInstituteId();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    final iid = _instituteId;
    if (iid != null && iid.isNotEmpty) {
      InstituteRealtimeSyncService.instance.release(iid);
    }
    super.dispose();
  }

  Future<void> _loadInstituteId() async {
    final user = appDb.auth.currentUser;
    if (user == null) return;

    final row = await appDb.from('profiles').select('institute_id').eq('id', user.id).maybeSingle();
    final iid = row?['institute_id'] as String?;
    if (iid != null && iid.isNotEmpty) {
      await InstituteRealtimeSyncService.instance.retain(iid);
      _syncSubscription?.cancel();
      _syncSubscription = InstituteRealtimeSyncService.instance
          .watch(iid)
          .listen((_) {
        if (mounted) setState(() {});
      });
      setState(() => _instituteId = iid);
    }
  }

  static const _dashboardPollInterval = Duration(seconds: 30);

  Future<InstituteDashboardStats> _loadDashboardStats() async {
    final iid = _instituteId;
    if (iid == null || iid.isEmpty) {
      return InstituteDashboardStats.empty(DateFormat('yyyy-MM-dd').format(DateTime.now()));
    }
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    try {
      return await fetchInstituteDashboardStats(iid, dateYyyyMmDd: today);
    } catch (_) {
      return InstituteDashboardStats.empty(today);
    }
  }

  Stream<int> _studentCountStream() async* {
    if (_instituteId == null) {
      yield 0;
      return;
    }
    yield (await _loadDashboardStats()).studentCount;
    await for (final _ in Stream.periodic(_dashboardPollInterval)) {
      yield (await _loadDashboardStats()).studentCount;
    }
  }

  Stream<int> _todayAttendanceCountStream() async* {
    if (_instituteId == null) {
      yield 0;
      return;
    }
    yield (await _loadDashboardStats()).todayInOutRows;
    await for (final _ in Stream.periodic(_dashboardPollInterval)) {
      yield (await _loadDashboardStats()).todayInOutRows;
    }
  }

  Stream<Map<String, int>> _employeeStatsStream() async* {
    if (_instituteId == null) {
      yield {'total': 0, 'present': 0};
      return;
    }
    Future<Map<String, int>> load() async {
      final s = await _loadDashboardStats();
      return {
        'total': s.studentCount,
        'present': s.todayDistinctStudents,
      };
    }

    yield await load();
    await for (final _ in Stream.periodic(_dashboardPollInterval)) {
      yield await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentDate = DateFormat('d MMM, yyyy').format(now);

    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Profile
            Container(
              width: double.infinity,
              color: AppTheme.primaryBlue,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade400,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mr Super Admin',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Best wishes for your day!',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Today's Overview
                    _buildSectionHeader('Today\'s Overview', 'View All'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildOverviewCard(
                            '3 Appointments',
                            Icons.calendar_today,
                            AppTheme.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildOverviewCard(
                            '1 Meetings',
                            Icons.business_center,
                            AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildOverviewCard(
                            '2 New Notices',
                            Icons.description,
                            AppTheme.accentOrange,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Date and Total Students
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentDate,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        // Total Students Count instead of clock
                        StreamBuilder<int>(
                          stream: _studentCountStream(),
                          builder: (context, snapshot) {
                            final studentCount = snapshot.data ?? 0;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people, color: Colors.white, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$studentCount Students',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _buildPendingSyncCard(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTodayAttendanceCard(),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Employee Statistics
                    const Text(
                      'Employee Statistics',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_instituteId != null)
                      _buildEmployeeStats()
                    else
                      const Center(child: CircularProgressIndicator()),

                    const SizedBox(height: 24),

                    // Upcoming Meeting
                    _buildSectionHeader('Upcoming Meeting', 'View All'),
                    const SizedBox(height: 12),
                    _buildMeetingCard('CEO meeting', '13.00.01'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(0), // Home selected
    );
  }

  Widget _buildSectionHeader(String title, String action) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textDark,
          ),
        ),
        TextButton(
          onPressed: () {},
          child: Text(
            action,
            style: const TextStyle(color: AppTheme.primaryBlue),
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewCard(String title, IconData icon, Color color) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingSyncCard() {
    return Container(
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
      child: FutureBuilder<int>(
        future: OfflineService.getPendingCount(),
        builder: (context, snapshot) {
          final pendingCount = snapshot.data ?? 0;
          
          return GestureDetector(
            onTap: pendingCount > 0
                ? () async {
                    if (_instituteId != null) {
                      await OfflineService.syncPendingAttendance(_instituteId!);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 12),
                                Text('Pending records synced successfully!'),
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
                    }
                  }
                : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_off,
                    color: AppTheme.accentOrange,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Sync',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Text(
                        '$pendingCount records',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      if (pendingCount > 0)
                        Text(
                          'Tap to sync',
                          style: TextStyle(
                            fontSize: 10,
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
        },
      ),
    );
  }

  Widget _buildTodayAttendanceCard() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    return Container(
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
      child: StreamBuilder<int>(
        stream: _todayAttendanceCountStream(),
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          
          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: AppTheme.primaryGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Attendance",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '$count marked',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmployeeStats() {
    return StreamBuilder<Map<String, int>>(
      stream: _employeeStatsStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final totalEmployees = snapshot.data!['total'] ?? 0;
        final presentCount = snapshot.data!['present'] ?? 0;
        final lateCount = 0;
        final leaveCount = 0;

        return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.5,
              children: [
                _buildStatItem('Total Employee', '$totalEmployees', Icons.people, AppTheme.primaryBlue),
                _buildStatItem('Total Present', '$presentCount', Icons.person, AppTheme.primaryGreen),
                _buildStatItem('Total Late', '$lateCount', Icons.access_time, AppTheme.accentOrange),
                _buildStatItem('Total Leave', '$leaveCount', Icons.event_busy, AppTheme.accentRed),
              ],
            );
      },
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingCard(String title, String time) {
    return Container(
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
            child: const Icon(Icons.calendar_today, color: AppTheme.primaryBlue, size: 24),
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
                  time,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(int selectedIndex) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(Icons.home, selectedIndex == 0),
              _buildNavItem(Icons.help_outline, selectedIndex == 1),
              _buildNavItem(Icons.search, selectedIndex == 2, isLarge: true),
              _buildNavItem(Icons.notifications_outlined, selectedIndex == 3),
              _buildNavItem(Icons.person_outline, selectedIndex == 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isSelected, {bool isLarge = false}) {
    return Container(
      width: isLarge ? 50 : 40,
      height: isLarge ? 50 : 40,
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryBlue.withOpacity(0.1) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade600,
        size: isLarge ? 28 : 24,
      ),
    );
  }
}
