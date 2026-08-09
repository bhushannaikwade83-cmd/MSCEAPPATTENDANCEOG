import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'core/root_navigator.dart' show rootNavigatorKey, rootScaffoldMessengerKey;
import 'core/theme/app_theme.dart';
import 'config/apply_network_overrides_stub.dart'
    if (dart.library.io) 'config/apply_network_overrides_io.dart';
import 'config/supabase_env.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'l10n/app_localizations.dart';
import 'services/locale_service.dart';
import 'core/utils/responsive.dart';

// Import your screens...
import 'services/session_manager.dart';
import 'services/theme_service.dart';
import 'presentation/widgets/session_monitor.dart';
import 'presentation/screens/splash_screen.dart';
import 'presentation/screens/app_permissions_screen.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/forgot_password_screen.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/admin_home_screen.dart';
import 'presentation/screens/add_student_screen.dart';
import 'presentation/screens/student_management_screen.dart';
import 'presentation/screens/gps_settings_screen.dart';
import 'presentation/screens/attendance_reports_screen.dart';
import 'presentation/screens/institute_report_screen.dart';
import 'presentation/screens/institute_search_screen.dart';
import 'presentation/screens/coder_login_screen.dart';
import 'presentation/screens/coder_dashboard_screen.dart';
import 'presentation/screens/super_admin_institute_screen.dart';
import 'presentation/screens/institute_admin_registration_screen.dart';
import 'presentation/screens/institute_location_gate_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/main_navigation_screen.dart';
import 'presentation/screens/staff_attendance_portal_screen.dart';
import 'presentation/screens/auto_face_scan_screen.dart';
import 'presentation/screens/attendance_staff_login_screen.dart';
import 'presentation/screens/help_desk_screen.dart';
import 'presentation/screens/biometric_lock_screen.dart';
import 'presentation/screens/pin_setup_screen.dart';
import 'presentation/screens/security_dashboard_screen.dart';
import 'services/anti_spoof_service.dart';
import 'services/face_recognition_service.dart';
import 'services/institute_notification_service.dart';
import 'services/device_performance_service.dart';
import 'services/device_security_service.dart';
import 'services/anti_spoof_api_service.dart';
import 'services/backend_monitor_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Wi‑Fi: prefer IPv4 + skip auto-proxy before any cloud calls (REST, auth, Realtime WS).
  applySupabaseNetworkOverrides();

  // Load environment variables (bundled as a Flutter asset — see pubspec.yaml)
  try {
    await dotenv.load(fileName: 'app_config.env');
    debugPrint('✅ Loaded app_config.env');
  } catch (e) {
    debugPrint('⚠️ app_config.env not found: $e - continuing with defaults');
    // Continue anyway - B2BStorageConfig has hardcoded fallbacks
  }

  await DevicePerformanceService.initialize();
  _configureGlobalImageCache();

  await SupabaseEnv.initializeRequired();

  SessionManager.initialize();

  // Show UI first — on 4GB Android 10 phones, loading TFLite + Workmanager before runApp()
  // often causes instant close (OOM). Models load in background after splash is visible.
  runApp(const SmartAttendanceApp());
  unawaited(_warmUpHeavyServicesAfterFirstFrame());
}

Future<void> _warmUpHeavyServicesAfterFirstFrame() async {
  await Future<void>.delayed(DevicePerformanceService.deferredModelLoadDelay);

  if (!DevicePerformanceService.skipHeavyWarmup) {
    try {
      await AntiSpoofService.ensureLoaded();
    } catch (e, st) {
      debugPrint('⚠️ Anti-spoof model failed to load: $e');
      debugPrint('$st');
    }
    try {
      await FaceRecognitionService.initialize();
    } catch (e, st) {
      debugPrint('⚠️ Face model (MobileFaceNet) failed to load: $e');
      debugPrint('$st');
    }
  } else {
    debugPrint(
      '📱 ${DevicePerformanceService.isLowRamDevice ? "Low-RAM" : "Constrained"} device: '
      'deferring startup face-model warm-up',
    );
  }

  try {
    await InstituteNotificationService.initialize();
  } catch (e, st) {
    debugPrint('⚠️ Local notifications failed to initialize: $e');
    debugPrint('$st');
  }

  // 🚀 Pre-warm backend (optional, models load on first registration anyway)
  // Disabled for now - prewarm is not critical
  // try {
  //   unawaited(AntiSpoofApiService.prewarmModels());
  // } catch (e, st) {
  //   debugPrint('⚠️ Backend pre-warm failed (not critical): $e');
  // }

  // 🔍 Backend connection monitor disabled (network detection works on actual requests)
  // try {
  //   unawaited(BackendMonitorService.startMonitoring());
  // } catch (e, st) {
  //   debugPrint('⚠️ Backend monitor failed (not critical): $e');
  // }
}

void _configureGlobalImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = DevicePerformanceService.imageCacheItems;
  cache.maximumSizeBytes = DevicePerformanceService.imageCacheBytes;
  debugPrint(
    '🖼️ Image cache tuned: items=${cache.maximumSize}, bytes=${cache.maximumSizeBytes}',
  );
}

class SmartAttendanceApp extends StatelessWidget {
  const SmartAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => LocaleService()),
      ],
      child: Consumer2<ThemeService, LocaleService>(
        builder: (context, themeService, localeService, _) {
          return ScreenUtilInit(
            designSize: const Size(375, 812),
            minTextAdapt: true,
            splitScreenMode: true,
            builder: (_, child) {
              return SessionMonitor(
                child: MaterialApp(
                  navigatorKey: rootNavigatorKey,
                  scaffoldMessengerKey: rootScaffoldMessengerKey,
                  title: 'MSCE ATTENDANCE APP',
                  debugShowCheckedModeBanner: false,
                  builder: (context, child) {
                    final mediaQuery = MediaQuery.of(context);
                    return _DeveloperOptionsGuard(
                      child: MediaQuery(
                        data: mediaQuery.copyWith(
                          textScaler: Responsive.appTextScaler(context),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      ),
                    );
                  },
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: themeService.themeMode,
                  locale: localeService.locale,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  initialRoute: SplashScreen.routeName,
                  routes: {
                    SplashScreen.routeName: (_) => const SplashScreen(),
                    AppPermissionsScreen.routeName: (_) =>
                        const AppPermissionsScreen(),
                    SetupScreen.routeName: (_) => const SetupScreen(),
                    // Government / IRCTC-style login only (captcha, OTP, PIN). No glass "modern" login route.
                    LoginScreen.routeName: (_) => const LoginScreen(),
                    ForgotPasswordScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      final map = args is Map ? args : const {};
                      return ForgotPasswordScreen(
                        initialInstituteId:
                            map['instituteId']?.toString().trim() ?? '',
                        initialEmail: map['email']?.toString(),
                      );
                    },
                    InstituteSearchScreen.routeName: (_) =>
                        const InstituteSearchScreen(),
                    AdminHomeScreen.routeName: (_) => const AdminHomeScreen(),
                    AddStudentScreen.routeName: (_) => const AddStudentScreen(),
                    StudentManagementScreen.routeName: (_) =>
                        const StudentManagementScreen(),
                    GpsSettingsScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      final routeArgs = args is Map ? args : const {};
                      return GpsSettingsScreen(
                        isMandatory: routeArgs['mandatory'] == true,
                        fromLogin: routeArgs['fromLogin'] == true,
                      );
                    },
                    AttendanceReportsScreen.routeName: (_) =>
                        const AttendanceReportsScreen(),
                    InstituteReportScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      final routeArgs = args is Map ? args : const {};
                      return InstituteReportScreen(
                        instituteId: routeArgs['instituteId'] as String?,
                        startDate: routeArgs['startDate'] as DateTime? ?? DateTime.now().subtract(const Duration(days: 7)),
                        endDate: routeArgs['endDate'] as DateTime? ?? DateTime.now(),
                      );
                    },
                    CoderLoginScreen.routeName: (_) => const CoderLoginScreen(),
                    CoderDashboardScreen.routeName: (_) =>
                        const CoderDashboardScreen(),
                    SuperAdminInstituteScreen.routeName: (_) =>
                        const SuperAdminInstituteScreen(),
                    InstituteAdminRegistrationScreen.routeName: (_) =>
                        const InstituteAdminRegistrationScreen(),
                    OnboardingScreen.routeName: (_) => const OnboardingScreen(),
                    InstituteLocationGateScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      return InstituteLocationGateScreen.fromArgs(args);
                    },
                    MainNavigationScreen.routeName: (_) =>
                        const MainNavigationScreen(),
                    StaffAttendancePortalScreen.routeName: (_) =>
                        const StaffAttendancePortalScreen(),
                    AttendanceStaffLoginScreen.routeName: (_) =>
                        const AttendanceStaffLoginScreen(),
                    HelpDeskScreen.routeName: (_) => const HelpDeskScreen(),
                    BiometricLockScreen.routeName: (_) =>
                        const BiometricLockScreen(),
                    PinSetupScreen.routeName: (_) =>
                        const PinSetupScreen(),
                    SecurityDashboardScreen.routeName: (_) =>
                        const SecurityDashboardScreen(),
                    AutoFaceScanScreen.routeName: (context) {
                      final args = ModalRoute.of(context)?.settings.arguments;
                      final map = args is Map ? args : const {};
                      return AutoFaceScanScreen(
                        instituteId: map['instituteId']?.toString(),
                      );
                    },
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DeveloperOptionsGuard extends StatefulWidget {
  const _DeveloperOptionsGuard({required this.child});

  final Widget child;

  @override
  State<_DeveloperOptionsGuard> createState() => _DeveloperOptionsGuardState();
}

class _DeveloperOptionsGuardState extends State<_DeveloperOptionsGuard>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _blocked = false;
  DeviceSecurityFlags _securityFlags = const DeviceSecurityFlags(
    developerOptionsEnabled: false,
    adbEnabled: false,
  );
  Timer? _securityPollTimer;

  @override
  void initState() {
    super.initState();
    if (!DeviceSecurityService.blockDeveloperAndUsbDebug) {
      _checking = false;
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _securityPollTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _securityPollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final flags = await DeviceSecurityService.securityFlags(refresh: true);
    if (!mounted) return;
    setState(() {
      _securityFlags = flags;
      _blocked = flags.wouldBlockApp;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!DeviceSecurityService.blockDeveloperAndUsbDebug) {
      return widget.child;
    }

    if (_checking) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_blocked) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.security,
                    size: 72,
                    color: AppTheme.accentRed,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _securityFlags.blockingTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _securityFlags.blockingMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textGray,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _refresh,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                    ),
                    child: const Text('Check again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
