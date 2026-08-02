import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';

/// Empty State Widget - Shows when there's no data to display
class EmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String icon;
  final VoidCallback? onRetry;
  final String? actionButtonText;

  const EmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = '📭',
    this.onRetry,
    this.actionButtonText,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                icon,
                style: TextStyle(fontSize: 64.sp),
              ),
              SizedBox(height: 20.h),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: 8.h),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    height: 1.5,
                  ),
                ),
              ],
              if (onRetry != null || actionButtonText != null) ...[
                SizedBox(height: 24.h),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionButtonText ?? 'Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty Students State
class EmptyStudentsState extends StatelessWidget {
  final VoidCallback? onRetry;

  const EmptyStudentsState({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'No Students Yet',
    subtitle: 'No students registered in your institute. Students will appear here once they register.',
    icon: '👥',
    onRetry: onRetry,
    actionButtonText: 'Refresh',
  );
}

/// Empty Search Results State
class EmptySearchState extends StatelessWidget {
  final String query;
  final VoidCallback? onClear;

  const EmptySearchState({
    super.key,
    required this.query,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    title: 'No Results Found',
    subtitle: 'No students match "$query". Try a different search or name.',
    icon: '🔍',
    onRetry: onClear,
    actionButtonText: 'Clear Search',
  );
}

/// Empty Filter Results State
class EmptyFilterState extends StatelessWidget {
  final String filterType; // 'present', 'absent'
  final VoidCallback? onClear;

  const EmptyFilterState({
    super.key,
    required this.filterType,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final title = filterType == 'present' ? 'No Present Students' : 'No Absent Students';
    final subtitle = filterType == 'present'
        ? 'All students have marked their attendance.'
        : 'All students are present today!';
    final icon = filterType == 'present' ? '✅' : '🎉';

    return EmptyState(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onRetry: onClear,
      actionButtonText: 'Clear Filter',
    );
  }
}
