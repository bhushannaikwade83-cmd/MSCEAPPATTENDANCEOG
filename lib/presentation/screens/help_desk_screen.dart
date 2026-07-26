import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';

class HelpDeskScreen extends StatelessWidget {
  static const routeName = '/help-desk';
  
  const HelpDeskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text('Help & Instructions'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ResponsiveScrollBody(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(Responsive.vw(context, 4).clamp(12.0, 24.0)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
            _buildSection(
              context,
              'Getting Started',
              Icons.play_circle_outline,
              [
                _buildInstruction(
                  '1. Institute hours',
                  'Set open and close times for your institute (admin dashboard). These define the daily schedule used for attendance flow.',
                  isDark,
                ),
                _buildInstruction(
                  '2. Add Students',
                  'Open Student Management and add each student with subjects and a clear, recent photo — it is used to confirm identity when marking attendance.',
                  isDark,
                ),
                _buildInstruction(
                  '3. Set GPS Location',
                  'Go to GPS Settings and set your institute location. Students must be within 15 meters of this location to mark attendance.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 24.h),
            _buildSection(
              context,
              'Marking Attendance',
              Icons.check_circle_outline,
              [
                _buildInstruction(
                  'Entry Photo',
                  'Students can mark entry from lecture start time up to 20 minutes after. When they take an entry photo, all lectures for that day are automatically marked as present.',
                  isDark,
                ),
                _buildInstruction(
                  'Exit Photo',
                  'Students can mark exit from 5 minutes before the last lecture ends up to 25 minutes after. Taking an exit photo confirms attendance for all lectures between entry and exit.',
                  isDark,
                ),
                _buildInstruction(
                  'Automatic Absent Marking',
                  'If a student takes an entry photo but doesn\'t take an exit photo within the exit window, they will be automatically marked as absent for all lectures.',
                  isDark,
                ),
                _buildInstruction(
                  'Photo at attendance',
                  'Students should use the in-app camera at entry and exit. The photo should match the person present; use good lighting and a steady shot.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 24.h),
            _buildSection(
              context,
              'Photo Requirements',
              Icons.camera_alt_outlined,
              [
                _buildInstruction(
                  'Clear Photo',
                  'Ensure good lighting and a clear view of the face. The photo should not be blurry. Keep the camera steady while taking the photo.',
                  isDark,
                ),
                _buildInstruction(
                  'Use the live camera',
                  'Take the picture directly in the app. Do not use a photo of another screen, a printout, or a gallery image when prompted for attendance.',
                  isDark,
                ),
                _buildInstruction(
                  'Face Visibility',
                  'The student\'s face should be clearly visible with eyes open. Remove any masks, sunglasses, or obstructions.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 24.h),
            _buildSection(
              context,
              'Viewing Reports',
              Icons.assessment_outlined,
              [
                _buildInstruction(
                  'Individual Reports',
                  'Go to Reports and select a student to view their detailed attendance report. Reports show entry time, exit time, and status for each lecture.',
                  isDark,
                ),
                _buildInstruction(
                  'Export PDF',
                  'You can export individual student reports or all students\' reports as PDF files for record keeping.',
                  isDark,
                ),
                _buildInstruction(
                  'Attendance Trends',
                  'View attendance trends and statistics to analyze patterns and identify students with low attendance.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 24.h),
            _buildSection(
              context,
              'Common Issues & Solutions',
              Icons.help_outline,
              [
                _buildInstruction(
                  'Photo Too Large',
                  'If you see "photo too large" error, the app will automatically compress the photo. Try taking the photo again.',
                  isDark,
                ),
                _buildInstruction(
                  'Blurry Photo Error',
                  'Ensure good lighting and keep the camera steady. Make sure the face is in focus before capturing.',
                  isDark,
                ),
                _buildInstruction(
                  'Photo not accepted',
                  'Make sure the student\'s registration photo still looks like them, use bright, even lighting, and face the camera directly. Try again after adjusting position or light.',
                  isDark,
                ),
                _buildInstruction(
                  'GPS Error',
                  'Make sure location permissions are enabled and GPS is turned on. Students must be within 15 meters of the institute location.',
                  isDark,
                ),
                _buildInstruction(
                  'No Internet Connection',
                  'When you are offline, your work is kept on the device and will update when you are back online. Reconnect when you can and open the app again to refresh.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 24.h),
            _buildSection(
              context,
              'Tips for Best Results',
              Icons.lightbulb_outline,
              [
                _buildInstruction(
                  'Good Lighting',
                  'Always ensure adequate lighting when taking photos. Natural light works best.',
                  isDark,
                ),
                _buildInstruction(
                  'Stable Camera',
                  'Keep the phone or device steady while taking photos to avoid blur.',
                  isDark,
                ),
                _buildInstruction(
                  'Clear Background',
                  'A plain background behind the student makes photos easier to capture and review.',
                  isDark,
                ),
                _buildInstruction(
                  'Regular Updates',
                  'Install app updates from your app store for the latest improvements and fixes.',
                  isDark,
                ),
              ],
              isDark,
            ),
            SizedBox(height: 32.h),
                ],
              ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> instructions,
    bool isDark,
  ) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? Colors.white.withValues(alpha: 0.1) 
              : AppTheme.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: AppTheme.primaryBlue,
                size: 28.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          ...instructions,
        ],
      ),
    );
  }

  Widget _buildInstruction(String title, String description, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withValues(alpha: 0.9) : AppTheme.primaryBlue,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          SizedBox(height: 8.h),
          Text(
            description,
            style: TextStyle(
              fontSize: 14.sp,
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.7) 
                  : AppTheme.textGray,
              height: 1.5,
            ),
            softWrap: true,
          ),
        ],
      ),
    );
  }
}
