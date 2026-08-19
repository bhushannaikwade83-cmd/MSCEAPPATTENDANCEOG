import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import 'login_screen.dart';
import '../widgets/animated_background.dart';

class OnboardingScreen extends StatefulWidget {
  static const routeName = '/onboarding';
  
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _animationController;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    
    // Create staggered animations for each page element
    _animations = List.generate(4, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.2,
            0.8 + (index * 0.05),
            curve: Curves.easeOutCubic,
          ),
        ),
      );
    });
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
    _animationController.reset();
    _animationController.forward();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            var begin = const Offset(1.0, 0.0);
            var end = Offset.zero;
            var curve = Curves.easeInOutCubic;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = Responsive.padding(context).horizontal;
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: Column(
        children: [
          // ✅ Government UI Header (Tricolor)
          const GovTricolorStrip(),
          // Content Area
          Expanded(
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth.clamp(
                    0.0,
                    context.contentMaxWidth(mobile: 560, tablet: 760),
                  );
                  return Stack(
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentWidth),
                          child: Column(
                            children: [
                              Expanded(
                                child: PageView(
                                  controller: _pageController,
                                  onPageChanged: _onPageChanged,
                                  children: [
                                    _buildOnboardingPage(
                                      title: 'Secure Face Recognition',
                                      description: 'Mark attendance with advanced facial recognition, GPS location verification, and anti-spoofing checks. Real-time updates for accurate records.',
                                      illustrationBuilder: (context, maxHeight) => _buildAttendanceIllustration(maxHeight),
                                    ),
                                    _buildOnboardingPage(
                                      title: 'Comprehensive Dashboard',
                                      description: 'Manage students, view attendance reports, analytics, and attendance trends for all subjects at MSCE institutes in one place.',
                                      illustrationBuilder: (context, maxHeight) => _buildManagementIllustration(maxHeight),
                                    ),
                                    _buildOnboardingPage(
                                      title: 'Smart Features',
                                      description: 'Calendar view, PDF reports, session management until midnight, and location-based verification. Everything for efficient management.',
                                      illustrationBuilder: (context, maxHeight) => _buildSolutionIllustration(maxHeight),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(vertical: 16.h),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20.r),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: List.generate(3, (index) {
                                          return AnimatedContainer(
                                            duration: const Duration(milliseconds: 300),
                                            margin: EdgeInsets.symmetric(horizontal: 4.w),
                                            width: _currentPage == index ? 24.w : 8.w,
                                            height: 8.h,
                                            decoration: BoxDecoration(
                                              color: _currentPage == index
                                                  ? AppTheme.primaryBlue
                                                  : AppTheme.primaryBlue.withOpacity(0.3),
                                              borderRadius: BorderRadius.circular(4.r),
                                              boxShadow: _currentPage == index
                                                  ? [
                                                      BoxShadow(
                                                        color: AppTheme.primaryBlue.withOpacity(0.4),
                                                        blurRadius: 8,
                                                        spreadRadius: 2,
                                                      ),
                                                    ]
                                                  : [],
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  horizontalPadding,
                                  0,
                                  horizontalPadding,
                                  20,
                                ),
                                child: FadeTransition(
                                  opacity: _animations[3],
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.3),
                                      end: Offset.zero,
                                    ).animate(_animations[3]),
                                    child: _buildActionButton(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Skip button (top right)
                      Positioned(
                        top: 16,
                        right: horizontalPadding,
                        child: FadeTransition(
                          opacity: _animations[0],
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10.r),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: TextButton(
                                onPressed: _completeOnboarding,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                  backgroundColor: AppTheme.primaryBlue.withOpacity(0.15),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.r),
                                    side: BorderSide(
                                      color: AppTheme.primaryBlue.withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'Skip',
                                  style: TextStyle(
                                    color: AppTheme.primaryBlue,
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingPage({
    required String title,
    required String description,
    required Widget Function(BuildContext context, double maxHeight)
        illustrationBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pagePadding = Responsive.padding(context).horizontal;
        final illustrationHeight = (constraints.maxHeight * 0.42).clamp(180.0, 300.0);
        final titleSize = constraints.maxWidth < 360 ? 26.0.sp : 32.0.sp;
        final descriptionSize = constraints.maxWidth < 360 ? 14.0.sp : 16.0.sp;

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: pagePadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 12.h),
                FadeTransition(
                  opacity: _animations[1],
                  child: ScaleTransition(
                    scale: _animations[1],
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.r),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                        child: Container(
                          height: illustrationHeight,
                          margin: EdgeInsets.only(bottom: 24.h),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.white.withOpacity(0.05),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20.r),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1.5,
                            ),
                          ),
                          child: illustrationBuilder(context, illustrationHeight),
                        ),
                      ),
                    ),
                  ),
                ),
                FadeTransition(
                  opacity: _animations[2],
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(_animations[2]),
                    child: Text(
                      title,
                      style: TextStyle(
                        color: AppTheme.primaryBlueDark,
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),
                FadeTransition(
                  opacity: _animations[3],
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(_animations[3]),
                    child: Text(
                      description,
                      style: TextStyle(
                        color: AppTheme.textGray,
                        fontSize: descriptionSize,
                        height: 1.6,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendanceIllustration(double maxHeight) {
    final phoneWidth = (maxHeight * 0.75).clamp(140.0, 200.0);
    final phoneHeight = (maxHeight * 0.92).clamp(170.0, 250.0);
    final accentSize = (maxHeight * 0.3).clamp(56.0, 80.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Camera/Phone Frame
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: phoneWidth,
                height: phoneHeight,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    // Camera icon in center
                    Center(
                      child: Container(
                        width: accentSize + 20,
                        height: accentSize + 20,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5),
                            width: 3,
                          ),
                        ),
                        child: Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: accentSize * 0.5,
                        ),
                      ),
                    ),
                    // GPS/Location icon
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: (accentSize * 0.3).clamp(20.0, 24.0),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Checkmark Icon
        Positioned(
          right: 20,
          bottom: 20,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: accentSize,
                  height: accentSize,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: accentSize * 0.5,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildManagementIllustration(double maxHeight) {
    final dashboardSize = (maxHeight * 0.78).clamp(150.0, 200.0);
    final accentSize = (maxHeight * 0.3).clamp(56.0, 80.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Dashboard/Grid
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: dashboardSize,
                height: dashboardSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
                child: GridView.count(
                  crossAxisCount: 2,
                  padding: const EdgeInsets.all(16),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: List.generate(4, (index) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        [Icons.people, Icons.bar_chart, Icons.calendar_today, Icons.settings][index],
                        color: Colors.white,
                        size: (dashboardSize * 0.12).clamp(20.0, 24.0),
                      ),
                    );
                  }),
                ),
              ),
            );
          },
        ),
        // Chart/Graph icon
        Positioned(
          right: 20,
          bottom: 20,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: accentSize,
                  height: accentSize,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.analytics,
                    color: Colors.white,
                    size: accentSize * 0.5,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildSolutionIllustration(double maxHeight) {
    final doorWidth = (maxHeight * 0.68).clamp(130.0, 180.0);
    final doorHeight = (maxHeight * 0.82).clamp(160.0, 220.0);
    final avatarSize = (maxHeight * 0.24).clamp(44.0, 60.0);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Door
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: doorWidth,
                height: doorHeight,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    // Door handle
                    Positioned(
                      right: 20,
                      top: 100,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Checkmark
                    Positioned(
                      top: 20,
                      left: 0,
                      right: 0,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.elasticOut,
                        builder: (context, checkValue, child) {
                          return Transform.scale(
                            scale: checkValue,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // People icons
        ...List.generate(3, (index) {
          return Positioned(
            left: 20 + (index * (avatarSize - 10)),
            bottom: 20,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 600 + (index * 150)),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Transform.translate(
                    offset: Offset(0, 20 * (1 - value)),
                    child: Container(
                      width: avatarSize,
                      height: avatarSize,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        index == 1 ? Icons.person : Icons.person_outline,
                        color: Colors.white,
                        size: avatarSize * 0.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActionButton() {
    final isLastPage = _currentPage == 2;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 56.h,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue.withOpacity(0.15),
                AppTheme.primaryBlue.withOpacity(0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: AppTheme.primaryBlue.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(0.2),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                if (isLastPage) {
                  _completeOnboarding();
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              borderRadius: BorderRadius.circular(16.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLastPage ? 'Get Started' : 'Continue',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Icon(
                      isLastPage ? Icons.arrow_forward_rounded : Icons.arrow_forward_ios_rounded,
                      color: AppTheme.primaryBlue,
                      size: 20.sp,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
