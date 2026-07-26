import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/theme/app_theme.dart';
import 'onboarding_screen.dart';

class InstructionsWindow extends StatefulWidget {
  static const routeName = '/instructions-window';

  const InstructionsWindow({super.key});

  @override
  State<InstructionsWindow> createState() => _InstructionsWindowState();
}

class _InstructionsWindowState extends State<InstructionsWindow>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late List<Animation<double>> _stepAnimations;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _stepAnimations = List.generate(4, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _slideController,
          curve: Interval(
            index * 0.15,
            0.6 + (index * 0.15),
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('instructions_shown', true);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const OnboardingScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeController,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue.withOpacity(0.1),
                AppTheme.primaryGreen.withOpacity(0.05),
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 12.h),
                    // Header
                    FadeTransition(
                      opacity: _stepAnimations[0],
                      child: Column(
                        children: [
                          Container(
                            padding: EdgeInsets.all(16.w),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.info_outline,
                              color: AppTheme.primaryBlue,
                              size: 40.w,
                            ),
                          ),
                          SizedBox(height: 16.h),
                          Text(
                            'Welcome to EDUSETU',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            'Attendance App',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 32.h),

                    // Description
                    FadeTransition(
                      opacity: _stepAnimations[0],
                      child: Text(
                        'Follow these steps to get started and unlock full app features',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: 32.h),

                    // Step 1: Signup/Login
                    _buildStep(
                      stepNumber: 1,
                      emoji: '🔐',
                      title: 'SIGNUP / LOGIN',
                      description:
                          'Create a new account with your email or login with your existing credentials. Set a strong password for security.',
                      details: [
                        'Email verification required',
                        'Password strength meter',
                        'CAPTCHA verification',
                      ],
                      animation: _stepAnimations[0],
                    ),
                    SizedBox(height: 16.h),

                    // Step 2: PIN Setup
                    _buildStep(
                      stepNumber: 2,
                      emoji: '🔑',
                      title: 'SET 4-DIGIT PIN',
                      description:
                          'Create a quick-access PIN for faster login. This is optional but highly recommended for daily use.',
                      details: [
                        '4-digit security PIN',
                        'Quick login (30 seconds)',
                        '5 wrong attempts = 10 min lockout',
                      ],
                      animation: _stepAnimations[1],
                    ),
                    SizedBox(height: 16.h),

                    // Step 3: GPS Lock
                    _buildStep(
                      stepNumber: 3,
                      emoji: '📍',
                      title: 'GPS LOCATION LOCK',
                      description:
                          'Configure your institute location and GPS radius. Attendance can only be marked from within this area.',
                      details: [
                        'Set institute GPS coordinates',
                        'Configure radius (50-500 meters)',
                        'Prevents fake attendance from home',
                      ],
                      animation: _stepAnimations[2],
                    ),
                    SizedBox(height: 16.h),

                    // Step 4: Dashboard
                    _buildStep(
                      stepNumber: 4,
                      emoji: '📊',
                      title: 'DASHBOARD ACCESS',
                      description:
                          'Access the main dashboard to mark attendance, view reports, manage students, and configure settings.',
                      details: [
                        'Mark Entry/Exit for attendance',
                        'View daily & monthly reports',
                        'Manage students & subjects',
                      ],
                      animation: _stepAnimations[3],
                    ),
                    SizedBox(height: 32.h),

                    // Important Notes
                    FadeTransition(
                      opacity: _stepAnimations[0],
                      child: Container(
                        padding: EdgeInsets.all(14.w),
                        decoration: BoxDecoration(
                          color: AppTheme.accentSaffron.withOpacity(0.1),
                          border: Border.all(
                            color: AppTheme.accentSaffron.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.lightbulb_outline,
                                  color: AppTheme.accentSaffron,
                                  size: 20.w,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'Important Notes',
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accentSaffron,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8.h),
                            _buildNote(
                              '📸 Camera permission is required for face photo capture',
                            ),
                            _buildNote(
                              '📍 Location permission is required for GPS tracking',
                            ),
                            _buildNote(
                              '⏱️ Complete setup takes ~5-15 minutes',
                            ),
                            _buildNote(
                              '🔒 All data is encrypted and secure',
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 32.h),

                    // Continue Button
                    FadeTransition(
                      opacity: _stepAnimations[3],
                      child: SizedBox(
                        width: double.infinity,
                        height: 54.h,
                        child: ElevatedButton(
                          onPressed: _handleContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            elevation: 4,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20.w,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required int stepNumber,
    required String emoji,
    required String title,
    required String description,
    required List<String> details,
    required Animation<double> animation,
  }) {
    return SlideTransition(
      position: animation.drive(
        Tween<Offset>(
          begin: const Offset(0.3, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: FadeTransition(
        opacity: animation,
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: Colors.grey[300]!,
            ),
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: TextStyle(fontSize: 22.sp),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                          child: Text(
                            'Step $stepNumber',
                            style: TextStyle(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13.sp,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              SizedBox(height: 10.h),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: details
                    .map((detail) => Padding(
                          padding: EdgeInsets.only(bottom: 6.h),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: AppTheme.primaryGreen,
                                size: 16.w,
                              ),
                              SizedBox(width: 8.w),
                              Expanded(
                                child: Text(
                                  detail,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNote(String note) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
