import 'package:flutter/material.dart';
import 'dart:math' as math;
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
  late Animation<double> _logoScale;
  late Animation<double> _logoTurn;
  late Animation<double> _logoOpacity;
  late Animation<double> _titleOpacity;
  late Animation<double> _titleSlide;
  late Animation<double> _subtitleOpacity;
  late Animation<double> _badgeOpacity;
  late Animation<double> _loaderOpacity;
  late Animation<double> _glowPulse;

  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _logoScale = Tween<double>(begin: 0.12, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.42, curve: Curves.elasticOut),
      ),
    );
    _logoTurn = Tween<double>(begin: -0.12, end: 0.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.0, 0.32, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.26, 0.58, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween<double>(begin: 32.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.26, 0.58, curve: Curves.easeOutCubic),
      ),
    );
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
      ),
    );
    _badgeOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.5, 0.78, curve: Curves.easeOut),
      ),
    );
    _loaderOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.55, 0.88, curve: Curves.easeOut),
      ),
    );
    _glowPulse = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.35, 0.75, curve: Curves.easeInOut),
      ),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _pulse.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _pulse.forward();
        }
      });

    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _pulse.forward();
      }
    });

    _intro.forward();
    _goNext();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    await Future.delayed(const Duration(milliseconds: 3200));
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

    if (SupabaseEnv.isReady) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Every cold start: require PIN (and offer biometric if enabled on device)
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, BiometricLockScreen.routeName);
        return;
      }
    }

    if (!mounted) return;
    final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;

    if (onboardingCompleted) {
      Navigator.pushReplacementNamed(context, LoginScreen.routeName);
    } else {
      Navigator.pushReplacementNamed(context, OnboardingScreen.routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GovTricolorStrip(),
          Expanded(
            child: AnimatedBuilder(
              animation: Listenable.merge([_intro, _pulse]),
              builder: (context, _) {
                final l10n = AppLocalizations.of(context);
                final pulseScale = _intro.isCompleted
                    ? 1.0 + (_pulse.value * 0.028)
                    : 1.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: 0.12 * _logoOpacity.value,
                          child: Container(
                            height: 220.h,
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: Alignment.topCenter,
                                radius: 1.1,
                                colors: [
                                  AppTheme.primaryBlue.withValues(alpha: 0.45),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final padX = constraints.maxWidth * 0.08;
                          // Drive by height so the logo is never a squashed banner.
                          // Logo height = 22% of viewport; width follows the aspect ratio.
                          final logoH = constraints.maxHeight * 0.22;
                          final logoW = (logoH * AppUI.appLogoAspectRatio)
                              .clamp(0.0, constraints.maxWidth - 2 * padX);
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                  maxWidth: Responsive.contentMaxWidth(
                                    context,
                                    mobile: 560,
                                    tablet: 760,
                                  ),
                                ),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: padX),
                                  child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                          Transform.scale(
                            scale: _logoScale.value * pulseScale,
                            child: Transform.rotate(
                              angle: _logoTurn.value * math.pi,
                              child: Opacity(
                                opacity: _logoOpacity.value,
                                child: Container(
                                  width: logoW,
                                  height: logoH,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16.r),
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryBlue.withValues(
                                          alpha: 0.22 * _glowPulse.value,
                                        ),
                                        blurRadius: 28,
                                        spreadRadius: 2,
                                        offset: const Offset(0, 10),
                                      ),
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16.r),
                                    child: Padding(
                                      padding: EdgeInsets.all(logoH * 0.06),
                                      child: AppUI.dualBrandLogos(
                                        mainHeight: logoH * 0.72,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 28.h),
                          Transform.translate(
                            offset: Offset(0, _titleSlide.value),
                            child: Opacity(
                              opacity: _titleOpacity.value,
                              child: Text(
                                l10n.splashTitle,
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26.sp,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Opacity(
                            opacity: _subtitleOpacity.value,
                            child: Text(
                              l10n.splashSubtitle,
                              textAlign: TextAlign.center,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppTheme.textGray,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.sp,
                                height: 1.35,
                              ),
                            ),
                          ),
                          SizedBox(height: 18.h),
                          Opacity(
                            opacity: _badgeOpacity.value,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.w,
                                vertical: 8.h,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(20.r),
                                border: Border.all(
                                  color: AppTheme.primaryBlue.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Text(
                                l10n.splashCredit,
                                style: TextStyle(
                                  color: AppTheme.primaryBlue.withValues(
                                    alpha: 0.85,
                                  ),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.sp,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: 48.h),
                          Opacity(
                            opacity: _loaderOpacity.value,
                            child: Column(
                              children: [
                                SizedBox(
                                  width: 36.w,
                                  height: 36.w,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.primaryBlue,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 14.h),
                                Text(
                                  l10n.splashLoading,
                                  style: TextStyle(
                                    color: AppTheme.textGray,
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                                  ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
