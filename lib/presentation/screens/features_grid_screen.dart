import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/enhanced_animations.dart';
import '../../core/app_db.dart';
import 'student_management_screen.dart';
import 'help_desk_screen.dart';
import 'attendance_reports_screen.dart';
import 'add_institute_attendance_user_screen.dart';
import 'gps_settings_screen.dart';
import 'attendance_calendar_screen.dart';
import 'attendance_trend_screen.dart';

/// Features Grid Screen - Displays all features in a grid layout
/// Similar to the reference design with square buttons
class FeaturesGridScreen extends StatefulWidget {
  final String? instituteId;
  
  const FeaturesGridScreen({
    super.key,
    this.instituteId,
  });

  @override
  State<FeaturesGridScreen> createState() => _FeaturesGridScreenState();
}

class _FeaturesGridScreenState extends State<FeaturesGridScreen> {
  Map<String, dynamic>? instituteData;
  bool isLoadingInstitute = true;

  @override
  void initState() {
    super.initState();
    _loadInstituteData();
  }

  Future<void> _loadInstituteData() async {
    try {
      if (widget.instituteId != null) {
        final instituteId = widget.instituteId!;
        final data = await appDb
            .from('institutes')
            .select()
            .eq('id', instituteId)
            .single();
        setState(() {
          instituteData = data;
          isLoadingInstitute = false;
        });
      } else {
        setState(() => isLoadingInstitute = false);
      }
    } catch (e) {
      print('⚠️ Error loading institute data: $e');
      setState(() => isLoadingInstitute = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white, size: 24.sp),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Features',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: Responsive.fontSize(context, 20).sp,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      body: ResponsiveScrollBody(
            padding: Responsive.padding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🏢 Institute Information Card
                if (!isLoadingInstitute && instituteData != null)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.r),
                    margin: EdgeInsets.only(bottom: 20.h),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryBlue,
                          AppTheme.primaryBlue.withOpacity(0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8.r,
                          offset: Offset(0, 2.h),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.school, color: Colors.white, size: 24.sp),
                            SizedBox(width: 12.w),
                            Expanded(
                              child: Text(
                                instituteData?['name'] ?? 'Unknown Institute',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.white70, size: 16.sp),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                instituteData?['address'] ?? 'Address not set',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.sp,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        Row(
                          children: [
                            Icon(Icons.badge, color: Colors.white70, size: 16.sp),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                'ID: ${instituteData?['id'] ?? 'N/A'}',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.sp,
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // Grid of Features with Staggered Animations
                GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.gridColumns(context),
                    mainAxisSpacing: Responsive.pctWidth(context, 0.04).clamp(10.0, 20.0),
                    crossAxisSpacing: Responsive.pctWidth(context, 0.04).clamp(10.0, 20.0),
                    childAspectRatio: 1.0,
                  ),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 7,
              itemBuilder: (context, index) {
                final features = [
                  {'title': 'Help Desk', 'icon': Icons.support_agent, 'color': AppTheme.primaryBlue, 'screen': const HelpDeskScreen()},
                  {'title': 'Students', 'icon': Icons.school, 'color': AppTheme.primaryGreen, 'screen': const StudentManagementScreen()},
                  {'title': 'Reports', 'icon': Icons.bar_chart, 'color': AppTheme.accentOrange, 'screen': const AttendanceReportsScreen()},
                  {'title': 'Calendar', 'icon': Icons.calendar_today, 'color': AppTheme.primaryBlue, 'screen': widget.instituteId != null ? AttendanceCalendarScreen(instituteId: widget.instituteId!) : null},
                  {'title': 'Institute instructor', 'icon': Icons.person_add_alt_1, 'color': AppTheme.primaryGreen, 'screen': const AddInstituteAttendanceUserScreen()},
                  {'title': 'Settings', 'icon': Icons.settings, 'color': AppTheme.accentOrange, 'screen': const GpsSettingsScreen()},
                  {'title': 'Trends', 'icon': Icons.show_chart, 'color': AppTheme.primaryBlue, 'screen': widget.instituteId != null ? AttendanceTrendScreen(instituteId: widget.instituteId!) : null},
                ];
                
                final feature = features[index];
                return _buildFeatureCard(
                  title: feature['title'] as String,
                  icon: feature['icon'] as IconData,
                  color: feature['color'] as Color,
                  onTap: () {
                    final screen = feature['screen'];
                    if (screen != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => screen as Widget),
                      );
                    }
                  },
                  isDark: isDark,
                ).stagger(index: index);
              },
            ),
              ],
            ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12.r,
                  offset: Offset(0, 4.h),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(Responsive.pctShortestSide(context, 0.04).clamp(12.0, 24.0)),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: Responsive.pctShortestSide(context, 0.09).clamp(28.0, 44.0),
                  ),
                ),
                SizedBox(height: Responsive.pctHeight(context, 0.012).clamp(8.0, 20.0)),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: Responsive.pctWidth(context, 0.02)),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 14).sp,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
