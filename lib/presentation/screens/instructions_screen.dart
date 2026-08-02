import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';
import '../../services/distance_check_service.dart';

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text('Photo Instructions'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📸 General Instructions
              _buildSection(
                icon: '📸',
                title: 'Photo Requirements',
                isDark: isDark,
              ),
              SizedBox(height: 12.h),
              _buildInstructionRow(
                icon: '✓',
                title: '3 ft from phone',
                description: DistanceCheckService.recommendedDistanceDetail,
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'Good closeup',
                description: 'Face clear in the circle — not the whole screen',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'Clear Light',
                description: 'Ensure good lighting without harsh shadows',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'No Mask',
                description: 'Face must be fully visible without mask',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'Face in Focus',
                description: 'Entire face should be clear and in focus',
                isDark: isDark,
              ),
              SizedBox(height: 20.h),

              // 👤 Registration
              _buildSection(
                icon: '👤',
                title: 'Student Face Registration',
                isDark: isDark,
              ),
              SizedBox(height: 12.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'Liveness — two blinks',
                description:
                    'Close your eyes, then open them after about 1 second. Repeat that full close-and-open cycle two times (two times total).',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '🔄',
                title: 'Change photo (once)',
                description:
                    'After face is registered, tap 🔄 next to the check mark to replace the photo one time. The app shows the latest photo; the old one stays on the MSCE website.',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: 'ℹ',
                title: 'Clear background',
                description:
                    'For accurate attendance later, the registration capture should show a clear background with no other people or distracting objects in the frame.',
                isDark: isDark,
              ),
              SizedBox(height: 20.h),

              // ✔️ Attendance
              _buildSection(
                icon: '✔️',
                title: 'Mark Attendance',
                isDark: isDark,
              ),
              SizedBox(height: 12.h),
              _buildInstructionRow(
                icon: '✓',
                title: 'Auto Face Attendance',
                description:
                    'Use the green "Auto Face Attendance" button. '
                    '${DistanceCheckService.recommendedDistanceShort} — same as registration. '
                    'No per-student tap; one scan marks whoever matches.',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: '📷',
                title: 'Entry & Exit photos',
                description:
                    'After auto scan marks attendance, entry and exit photos on each student card update automatically.',
                isDark: isDark,
              ),
              SizedBox(height: 10.h),
              _buildInstructionRow(
                icon: 'ℹ',
                title: 'Clear background',
                description:
                    'For accurate attendance, the capture should have a clear background with no other people in the frame.',
                isDark: isDark,
              ),
              SizedBox(height: 20.h),

              // 💡 Tip
              _buildTipBox(isDark),
              SizedBox(height: 20.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String icon,
    required String title,
    required bool isDark,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(icon, style: TextStyle(fontSize: 18.sp)),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionRow({
    required String icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 16.sp)),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : AppTheme.textGray,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipBox(bool isDark) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('💡', style: TextStyle(fontSize: 18.sp)),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pro Tip',
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber.shade900,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Position yourself with light from the front. Make sure your face fills most of the frame.',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: isDark ? Colors.white70 : Colors.amber.shade900,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
