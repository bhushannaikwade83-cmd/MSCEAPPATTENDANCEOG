import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_permissions_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'biometric_lock_screen.dart';
import '../../config/supabase_env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../services/app_permissions_service.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';

class SplashScreen extends StatefulWidget {
  static const routeName = '/';

  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _intro;
  late AnimationController _featureSlide;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _titleOpacity;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _featureOpacity;
  late Animation<double> _loaderOpacity;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _featureSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Logo animation
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.35, curve: Curves.elasticOut),
      ),
    );

    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    // Title animation
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.2, 0.5, curve: Curves.easeOut),
      ),
    );

    // Subtitle animation
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.35, 0.65, curve: Curves.easeOut),
      ),
    );

    // Feature animation
    _featureOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _featureSlide,
        curve: Curves.easeOut,
      ),
    );

    // Loader animation
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.5, 0.8, curve: Curves.easeOut),
      ),
    );

    _intro.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _featureSlide.forward();
    });
    _goNext();
  }

  @override
  void dispose() {
    _intro.dispose();
    _featureSlide.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    await Future.delayed(const Duration(milliseconds: 3500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    var permissionsDone =
        prefs.getBool(AppPermissionsService.prefKeySetupDone) ?? false;
    if (AppPermissionsService.shouldRunPermissionGate && !permissionsDone) {
      if (await AppPermissionsService.areCorePermissionsGranted()) {
        await prefs.setBool(AppPermissionsService.prefKeySetupDone, true);
        permissionsDone = true;
      } else {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppPermissionsScreen.routeName);
        return;
      }
    }

    if (!mounted) return;

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      Navigator.pushReplacementNamed(context, LoginScreen.routeName);
    } else {
      final hasCompletedOnboarding =
          prefs.getBool('onboarding_completed') ?? false;
      if (!hasCompletedOnboarding) {
        Navigator.pushReplacementNamed(context, OnboardingScreen.routeName);
      } else {
        final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
        if (biometricEnabled) {
          Navigator.pushReplacementNamed(context, BiometricLockScreen.routeName);
        } else {
          Navigator.pushReplacementNamed(context, '/main-navigation');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryBlue.withOpacity(0.95),
              AppTheme.primaryBlueDark.withOpacity(0.98),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated gradient overlay
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _intro,
                builder: (context, _) {
                  return Opacity(
                    opacity: 0.15 * (1 - (_intro.value - 0.5).abs() * 2).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(_intro.value * 0.4 - 0.2, -0.5),
                          radius: 1.5,
                          colors: [
                            AppTheme.primaryBlueLight,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Main content
            SafeArea(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo section
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            width: 120.w,
                            height: 120.w,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Colors.white.withOpacity(0.95),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryBlue.withOpacity(0.4),
                                  blurRadius: 30,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Padding(
                                padding: EdgeInsets.all(12.w),
                                child: Image.asset(
                                  AppUI.appLogoAsset,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 40.h),

                      // Title
                      Opacity(
                        opacity: _titleOpacity.value,
                        child: Column(
                          children: [
                            Text(
                              'MSCE Attendance',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 32.sp,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              'एमएससीई उपस्थिती अॅप',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontWeight: FontWeight.w600,
                                fontSize: 16.sp,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24.h),

                      // Subtitle
                      Opacity(
                        opacity: _subtitleOpacity.value,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24.w),
                          child: Text(
                            'Smart Face Recognition Attendance System',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w500,
                              fontSize: 13.sp,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 48.h),

                      // Feature showcase
                      Opacity(
                        opacity: _featureOpacity.value,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: Column(
                            children: [
                              _buildFeatureRow(
                                icon: Icons.face_rounded,
                                title: 'Face Recognition',
                                subtitle: 'Multi-angle enrollment',
                              ),
                              SizedBox(height: 16.h),
                              _buildFeatureRow(
                                icon: Icons.check_circle_rounded,
                                title: 'Smart Reports',
                                subtitle: 'Real-time attendance tracking',
                              ),
                              SizedBox(height: 16.h),
                              _buildFeatureRow(
                                icon: Icons.location_on_rounded,
                                title: 'GPS Geofence',
                                subtitle: 'Location-based verification',
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // Loading indicator
                      Opacity(
                        opacity: _loaderOpacity.value,
                        child: Column(
                          children: [
                            SizedBox(
                              width: 40.w,
                              height: 40.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 3.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.9),
                                ),
                              ),
                            ),
                            SizedBox(height: 16.h),
                            Text(
                              'Initializing...',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 60.h),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.r),
        color: Colors.white.withOpacity(0.08),
        border: Border.all(
          color: Colors.white.withOpacity(0.15),
          width: 1.5,
        ),
        backdropFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.08),
                ],
              ),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24.sp,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontWeight: FontWeight.w400,
                    fontSize: 11.sp,
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
