import 'package:flutter/material.dart';
import 'package:smart_attendance_app/core/theme/app_theme.dart';
import 'package:smart_attendance_app/presentation/widgets/app_button_variants.dart';
import 'package:smart_attendance_app/presentation/widgets/app_card_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_state_widgets.dart';
import 'package:smart_attendance_app/presentation/widgets/app_utility_widgets.dart';

/// EXAMPLE: Refactored Attendance Screen with New UI System
///
/// This shows:
/// - New button variants
/// - New card system
/// - State management (empty, loading, error)
/// - Proper spacing and animations
/// - Accessibility improvements
///
/// Copy this pattern to your own screens!

class ExampleAttendanceScreen extends StatefulWidget {
  static const routeName = '/example-attendance';

  const ExampleAttendanceScreen({super.key});

  @override
  State<ExampleAttendanceScreen> createState() =>
      _ExampleAttendanceScreenState();
}

class _ExampleAttendanceScreenState extends State<ExampleAttendanceScreen> {
  bool _isLoading = false;
  bool _isMarked = false;
  String? _error;
  List<AttendanceRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadAttendanceRecords();
  }

  Future<void> _loadAttendanceRecords() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      // In real app, load from database/API
      setState(() {
        _records = [
          AttendanceRecord(
            date: DateTime.now(),
            status: 'Present',
            time: '09:00 AM',
            verificationMethod: 'Face Detection',
          ),
          AttendanceRecord(
            date: DateTime.now().subtract(const Duration(days: 1)),
            status: 'Present',
            time: '09:15 AM',
            verificationMethod: 'GPS',
          ),
          AttendanceRecord(
            date: DateTime.now().subtract(const Duration(days: 2)),
            status: 'Absent',
            time: '-',
            verificationMethod: '-',
          ),
        ];
      });
    } catch (e) {
      setState(() => _error = 'Failed to load records. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAttendance() async {
    setState(() => _isLoading = true);

    try {
      // Simulate marking attendance
      await Future.delayed(const Duration(seconds: 2));

      setState(() => _isMarked = true);

      // Show success dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: Padding(
              padding: AppSpacing.cardPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SuccessCheckmark(
                    size: 80,
                    onComplete: () => Navigator.pop(context),
                  ),
                  SizedBox(height: AppSpacing.xl),
                  Text(
                    'Attendance Marked',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  SizedBox(height: AppSpacing.md),
                  Text(
                    'Your attendance has been recorded successfully',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textGray,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Failed to mark attendance: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        elevation: 2,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Loading state
    if (_isLoading && _records.isEmpty) {
      return LoadingStateWidget(
        message: 'Loading your attendance...',
        showProgress: true,
      );
    }

    // Error state
    if (_error != null) {
      return ErrorStateWidget(
        title: 'Failed to Load',
        message: _error!,
        retryCallback: _loadAttendanceRecords,
        dismissCallback: () => Navigator.pop(context),
      );
    }

    // Empty state
    if (_records.isEmpty) {
      return EmptyStateWidget(
        icon: Icons.calendar_today_rounded,
        title: 'No Attendance Records',
        description: 'Mark your attendance to get started',
        actionLabel: 'Mark Attendance',
        actionCallback: _markAttendance,
      );
    }

    // Main content
    return RefreshIndicator(
      onRefresh: _loadAttendanceRecords,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              // 1. Mark Attendance Section
              _buildMarkAttendanceSection(),
              SizedBox(height: AppSpacing.xl),

              // 2. Today's Status Section
              _buildTodayStatusSection(),
              SizedBox(height: AppSpacing.xl),

              // 3. Recent Records Section
              _buildRecentRecordsSection(),
              SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  /// SECTION 1: Mark Attendance Card
  Widget _buildMarkAttendanceSection() {
    return ElevatedAppCard(
      showTopAccent: true,
      accentColor: AppTheme.accentSaffron,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppTheme.saffronLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.accentSaffron,
                  size: 24,
                ),
              ),
              SizedBox(width: AppSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Attendance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    'Mark your presence with face detection',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textGray,
                        ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          AppButton(
            text: _isMarked ? 'Marked ✓' : 'Mark Attendance',
            onPressed: _isMarked ? null : _markAttendance,
            isLoading: _isLoading,
            icon: _isMarked ? Icons.check_rounded : Icons.camera_alt_rounded,
          ),
          if (_isMarked) ...[
            SizedBox(height: AppSpacing.md),
            InfoBanner(
              title: 'Attendance Confirmed',
              description: 'Marked at 09:00 AM via Face Detection',
              icon: Icons.check_circle_outline_rounded,
              backgroundColor: AppTheme.greenLight,
              textColor: AppTheme.primaryGreen,
            ),
          ],
        ],
      ),
    );
  }

  /// SECTION 2: Today's Status Overview
  Widget _buildTodayStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overview',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark,
              ),
        ),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: DataCard(
                label: 'Status',
                value: 'Present',
                icon: Icons.check_circle_rounded,
                accentColor: AppTheme.primaryGreen,
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: DataCard(
                label: 'Time',
                value: '09:00',
                icon: Icons.access_time_rounded,
                accentColor: AppTheme.primaryBlue,
              ),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: DataCard(
                label: 'Method',
                value: 'Face',
                icon: Icons.face_rounded,
                accentColor: AppTheme.accentSaffron,
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: DataCard(
                label: 'Verified',
                value: 'Yes',
                icon: Icons.verified_rounded,
                accentColor: AppTheme.primaryGreen,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// SECTION 3: Recent Attendance Records
  Widget _buildRecentRecordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Records',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark,
                  ),
            ),
            TextButton.icon(
              onPressed: _loadAttendanceRecords,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
            ),
          ],
        ),
        SizedBox(height: AppSpacing.md),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _records.length,
          separatorBuilder: (context, index) =>
              SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final record = _records[index];
            return AnimatedListItem(
              index: index,
              staggerDelay: const Duration(milliseconds: 50),
              child: _buildRecordCard(record),
            );
          },
        ),
      ],
    );
  }

  /// Individual Record Card
  Widget _buildRecordCard(AttendanceRecord record) {
    final isPresent = record.status == 'Present';

    return AppCard(
      onTap: () => _showRecordDetails(record),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(record.date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    SizedBox(height: AppSpacing.xs),
                    Text(
                      record.time,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textGray,
                          ),
                    ),
                  ],
                ),
              ),
              StatusIndicator(
                status: isPresent
                    ? StatusIndicator.StatusType.success
                    : StatusIndicator.StatusType.error,
                label: record.status,
                showIcon: true,
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlueLighter,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Verified via ${record.verificationMethod}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Show detailed view of a record
  void _showRecordDetails(AttendanceRecord record) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Details',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            SizedBox(height: AppSpacing.lg),
            _detailRow('Date', _formatDate(record.date)),
            _detailRow('Status', record.status),
            _detailRow('Time', record.time),
            _detailRow('Method', record.verificationMethod),
            SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Close',
                    onPressed: () => Navigator.pop(context),
                    variant: ButtonVariant.secondary,
                  ),
                ),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: AppButton(
                    text: 'Share',
                    onPressed: () {
                      Navigator.pop(context);
                      _shareRecord(record);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppTheme.textGray,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _shareRecord(AttendanceRecord record) {
    // Implement sharing logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sharing attendance record...'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Model class for demonstration
class AttendanceRecord {
  final DateTime date;
  final String status;
  final String time;
  final String verificationMethod;

  AttendanceRecord({
    required this.date,
    required this.status,
    required this.time,
    required this.verificationMethod,
  });
}

/*
KEY PATTERNS USED IN THIS EXAMPLE:

1. ✅ Spacing: All padding/margins use AppSpacing constants
2. ✅ Buttons: Uses new AppButton variants (primary, secondary, danger)
3. ✅ Cards: Uses new card system (ElevatedAppCard, AppCard, DataCard)
4. ✅ States: Shows empty, loading, error states properly
5. ✅ Animations: Lists use AnimatedListItem with stagger
6. ✅ Status: Uses StatusIndicator for visual feedback
7. ✅ Loading: Shows AppLoadingSpinner and progress
8. ✅ Accessibility: Includes tooltips and proper labels
9. ✅ Color: Uses AppTheme constants throughout
10. ✅ Feedback: Shows success animations and error handling

COPY THIS PATTERN TO YOUR SCREENS!
*/
