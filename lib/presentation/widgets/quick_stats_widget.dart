import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import '../../core/app_db.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/shared_stats_service.dart';

/// Ultra-Modern Quick Stats Widget - Shows today's attendance statistics
class QuickStatsWidget extends StatefulWidget {
  final String instituteId;

  const QuickStatsWidget({
    super.key,
    required this.instituteId,
  });

  @override
  State<QuickStatsWidget> createState() => _QuickStatsWidgetState();
}

class _QuickStatsWidgetState extends State<QuickStatsWidget>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  int _presentCount = 0;
  int _totalStudents = 0;
  bool _loading = true;

  late AnimationController _statsAnimController;
  late Animation<double> _statsScale;

  @override
  void initState() {
    super.initState();
    _statsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _statsScale = CurvedAnimation(
      parent: _statsAnimController,
      curve: Curves.elasticOut,
    );
    _load();
    // Refresh stats on a sane interval — 500ms hammered Supabase + CPU + radio.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statsAnimController.dispose();
    super.dispose();
  }

  /// ✅ Load stats using shared service (unified logic)
  Future<void> _load() async {
    try {
      // ✅ Use SharedStatsService for consistent calculation across all screens
      final stats = await SharedStatsService.getTodayStats(widget.instituteId);

      if (mounted) {
        setState(() {
          _presentCount = stats['present'] ?? 0;
          _totalStudents = stats['total'] ?? 0;
          _loading = false;
        });
        // Trigger animation when data loads
        _statsAnimController.forward(from: 0);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      final h = Responsive.pctHeight(context, 0.14).clamp(96.0, 160.0);
      return SizedBox(
        height: h,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final presentCount = _presentCount;
    final totalStudents = _totalStudents;
    final absentCount = totalStudents > presentCount ? totalStudents - presentCount : 0;
    final attendanceRate = totalStudents > 0 ? (presentCount / totalStudents * 100) : 0.0;

    return ScaleTransition(
      scale: _statsScale,
      child: Container(
        padding: EdgeInsets.all(Responsive.pctWidth(context, 0.05).clamp(16.0, 28.0)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryBlue.withOpacity(isDark ? 0.12 : 0.06),
              AppTheme.primaryBlue.withOpacity(isDark ? 0.06 : 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
              blurRadius: 16.r,
              offset: Offset(0, 6.h),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📊 Header with Icon
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
                  child: Icon(
                    Icons.today_rounded,
                    color: AppTheme.primaryBlue,
                    size: 24.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    '📊 Today\'s Stats',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppTheme.textDark,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  'Present',
                  presentCount,
                  AppTheme.primaryGreen,
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Absent',
                  absentCount,
                  AppTheme.accentRed,
                  Icons.cancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  context,
                  'Total',
                  totalStudents,
                  AppTheme.primaryBlue,
                  Icons.people,
                ),
              ),
            ],
          ),
          if (totalStudents > 0) ...[
            SizedBox(height: 16.h),
            // Divider
            Container(
              height: 1.h,
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
            SizedBox(height: 16.h),
            // Attendance Rate Display
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Rate',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white.withOpacity(0.7)
                            : AppTheme.textGray,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryBlue.withOpacity(0.2),
                            AppTheme.primaryBlue.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '${attendanceRate.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryBlue,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Progress',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white.withOpacity(0.7)
                              : AppTheme.textGray,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.r),
                        child: LinearProgressIndicator(
                          value: attendanceRate / 100,
                          minHeight: 8.h,
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.08)
                              : AppTheme.primaryBlue.withOpacity(0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            LinearGradient(
                              colors: [
                                AppTheme.primaryBlue,
                                AppTheme.primaryGreen,
                              ],
                            ).colors[0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    int value,
    Color color,
    IconData icon,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: Tween<double>(begin: 0.9, end: 1).animate(
        CurvedAnimation(parent: _statsAnimController, curve: Curves.elasticOut),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withOpacity(isDark ? 0.15 : 0.08),
              color.withOpacity(isDark ? 0.08 : 0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: color.withOpacity(isDark ? 0.4 : 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(isDark ? 0.2 : 0.1),
              blurRadius: 12.r,
              offset: Offset(0, 4.h),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 🎯 Icon with circular background
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    color.withOpacity(0.3),
                    color.withOpacity(0.15),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: 26.sp),
            ),
            SizedBox(height: 10.h),
            // 📊 Value Display
            Text(
              '$value',
              style: TextStyle(
                fontSize: 28.sp,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppTheme.textDark,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 6.h),
            // 📝 Label
            Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : AppTheme.textGray,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
