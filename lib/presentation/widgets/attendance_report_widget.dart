import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'package:smart_attendance_app/presentation/widgets/app_button_variants.dart';
import 'package:smart_attendance_app/presentation/widgets/app_card_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_state_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_utility_widgets.dart';
import '../../services/attendance_report_service.dart';

/// Widget that displays student attendance report with present/absent statistics
class AttendanceReportWidget extends StatefulWidget {
  final String instituteCode;
  final DateTime startDate;
  final DateTime endDate;

  const AttendanceReportWidget({
    super.key,
    required this.instituteCode,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<AttendanceReportWidget> createState() => _AttendanceReportWidgetState();
}

class _AttendanceReportWidgetState extends State<AttendanceReportWidget> {
  bool _isLoading = false;
  List<StudentAttendanceStats> _allStats = [];
  List<StudentAttendanceStats> _filteredStats = [];
  Map<String, dynamic> _overallStats = {};
  String _searchQuery = '';
  String _statusFilter = 'all'; // all | good | average | poor

  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    setState(() => _isLoading = true);

    try {
      final stats = await AttendanceReportService.calculateStudentStats(
        instituteCode: widget.instituteCode,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );

      setState(() {
        _allStats = stats;
        _filteredStats = stats;
        _overallStats = AttendanceReportService.calculateOverallStats(studentStats: stats);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading report: $e'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    var filtered = _allStats;

    // Apply status filter
    if (_statusFilter != 'all') {
      filtered = AttendanceReportService.filterByStatus(
        stats: filtered,
        status: _statusFilter,
      );
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = AttendanceReportService.searchStudents(
        stats: filtered,
        query: _searchQuery,
      );
    }

    setState(() => _filteredStats = filtered);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingStateWidget(
        message: 'Generating attendance report...',
        showProgress: true,
      );
    }

    if (_allStats.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.assignment_rounded,
        title: 'No Data Available',
        description: 'No attendance records found for the selected date range',
        actionLabel: 'Retry',
        actionCallback: _loadAttendanceData,
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Overall Statistics Cards
          _buildOverallStatsSection(),
          const SizedBox(height: 24),

          // Filters Section
          _buildFiltersSection(),
          const SizedBox(height: 24),

          // Student List
          _buildStudentListSection(),
        ],
      ),
    );
  }

  /// Build overall statistics cards
  Widget _buildOverallStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overall Statistics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _buildStatCard(
              label: 'Total Students',
              value: '${_overallStats['totalStudents'] ?? 0}',
              icon: Icons.group_rounded,
              color: AppTheme.primaryBlue,
            ),
            _buildStatCard(
              label: 'Average Attendance',
              value: '${(_overallStats['averageAttendance'] ?? 0).toStringAsFixed(1)}%',
              icon: Icons.trending_up_rounded,
              color: AppTheme.accentGreen,
            ),
            _buildStatCard(
              label: 'Total Present Days',
              value: '${_overallStats['totalPresentDays'] ?? 0}',
              icon: Icons.check_circle_rounded,
              color: AppTheme.primaryGreen,
            ),
            _buildStatCard(
              label: 'Total Absent Days',
              value: '${_overallStats['totalAbsentDays'] ?? 0}',
              icon: Icons.cancel_rounded,
              color: AppTheme.accentRed,
            ),
          ],
        ),
      ],
    );
  }

  /// Build individual stat card
  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return DataCard(
      label: label,
      value: value,
      icon: icon,
      accentColor: color,
    );
  }

  /// Build filters section
  Widget _buildFiltersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filters',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),

        // Search box
        TextField(
          decoration: InputDecoration(
            labelText: 'Search by name or roll number',
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (value) {
            _searchQuery = value;
            _applyFilters();
          },
        ),
        const SizedBox(height: 12),

        // Status filter chips
        Wrap(
          spacing: 8,
          children: [
            _buildFilterChip('All', 'all'),
            _buildFilterChip('Good (75%+)', 'good'),
            _buildFilterChip('Average (50-75%)', 'average'),
            _buildFilterChip('Poor (<50%)', 'poor'),
          ],
        ),
      ],
    );
  }

  /// Build filter chip
  Widget _buildFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _statusFilter = selected ? value : 'all');
        _applyFilters();
      },
      selectedColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
      backgroundColor: AppTheme.dividerColor,
      side: BorderSide(
        color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
        width: 2,
      ),
    );
  }

  /// Build student list section
  Widget _buildStudentListSection() {
    if (_filteredStats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.filter_list_off_rounded,
                size: 48,
                color: AppTheme.textGray,
              ),
              const SizedBox(height: 16),
              Text(
                'No students match the filter',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textGray,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Student Details (${_filteredStats.length})',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredStats.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final stat = _filteredStats[index];
            return _buildStudentCard(stat);
          },
        ),
      ],
    );
  }

  /// Build individual student card
  Widget _buildStudentCard(StudentAttendanceStats stat) {
    final statusColor = stat.getStatusColor();
    final statusBgColor = statusColor == 'green'
        ? AppTheme.greenLight
        : statusColor == 'orange'
            ? AppTheme.orangeLight
            : AppTheme.redLight;
    final statusTextColor = statusColor == 'green'
        ? AppTheme.primaryGreen
        : statusColor == 'orange'
            ? AppTheme.accentOrange
            : AppTheme.accentRed;

    return AccentCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name and Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stat.studentName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Roll: ${stat.rollNumber}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textGray,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stat.getStatus(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: statusTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Stats row: Present | Absent | Percentage
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  label: 'Present',
                  value: '${stat.presentDays}',
                  color: AppTheme.primaryGreen,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  label: 'Absent',
                  value: '${stat.absentDays}',
                  color: AppTheme.accentRed,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  label: 'Percentage',
                  value: '${stat.attendancePercentage.toStringAsFixed(1)}%',
                  color: AppTheme.primaryBlue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stat.attendancePercentage / 100,
              minHeight: 6,
              backgroundColor: AppTheme.dividerColor,
              valueColor: AlwaysStoppedAnimation<Color>(statusTextColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Build stat item
  Widget _buildStatItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTheme.textGray,
              ),
        ),
      ],
    );
  }
}
