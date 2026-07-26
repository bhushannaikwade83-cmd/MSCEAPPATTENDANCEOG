import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';

import '../../core/app_db.dart';
import '../../core/root_navigator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../../core/utils/responsive_page.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/geofence_service.dart';
import '../../services/session_manager.dart';
import 'gps_settings_screen.dart';
import 'institute_location_gate_screen.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';
import 'staff_attendance_portal_screen.dart';

/// PIN/Biometric lock screen for both scenarios:
/// 1. App resume lock — requires authentication via biometric or PIN
/// 2. Returning user login — authenticate with saved email and PIN/biometric
class BiometricLockScreen extends StatefulWidget {
  static const routeName = '/biometric-lock';
  const BiometricLockScreen({super.key});

  @override
  State<BiometricLockScreen> createState() => _BiometricLockScreenState();
}

class _BiometricLockScreenState extends State<BiometricLockScreen>
    with WidgetsBindingObserver {
  static const String _kPrefLastEmail = 'msce_last_login_email';
  static const String _kPrefLastAdminEmail = 'msce_last_admin_email';
  static const String _kPrefLastInstituteId = 'msce_last_institute_id';
  static const String _kPrefLastUserHasPin = 'msce_last_user_has_pin';
  static const String _kPrefForgotPinEmail = 'msce_forgot_pin_email';

  final TextEditingController _pinController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;
  bool _biometricSupported = false;

  /// True when this screen's [email] is in the per-device biometric list.
  bool _canUseBiometric = false;
  String? _userEmail;
  String? _userId;
  String _errorMessage = '';
  bool _isForgotPinBusy = false;
  bool _isLogoutBusy = false;

  // Track if screen is in login mode (returning user) or app-resume mode
  bool _isLoginMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Route [arguments] and [ModalRoute.of] are only reliable after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pinController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshBiometricFlags();
    }
  }

  /// Re-read prefs and device so unlock button and labels update after settings change.
  Future<void> _refreshBiometricFlags() async {
    await _syncBiometricUi();
  }

  /// Biometric CTA and auto-prompt are per-email (same admin, multiple devices: each has its list).
  Future<void> _syncBiometricUi() async {
    try {
      final isSupported = await BiometricService.isDeviceSupported();
      final email = _userEmail?.trim();
      var can = false;
      if (isSupported && email != null && email.isNotEmpty) {
        can = await BiometricService.isBiometricEnabledForAdmin(email);
      }
      if (mounted) {
        setState(() {
          _biometricSupported = isSupported;
          _canUseBiometric = can;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _biometricSupported = false;
          _canUseBiometric = false;
        });
      }
    }
  }

  Future<void> _initialize() async {
    try {
      final args = ModalRoute.of(context)?.settings.arguments;
      final loginEmail = args is Map ? args['loginEmail'] as String? : null;

      if (loginEmail != null && loginEmail.isNotEmpty) {
        _isLoginMode = true;
        _userEmail = loginEmail.trim();
        await _applyEmailFallback();
        await _syncBiometricUi();
        if (mounted) {
          if (_canUseBiometric) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) _tryBiometricUnlockLogin();
                });
              }
            });
          }
        }
        return;
      }

      var user = appDb.auth.currentUser;
      if (user == null) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        user = appDb.auth.currentUser;
      }
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, LoginScreen.routeName);
        }
        return;
      }

      _userId = user.id;
      _userEmail = user.email;
      await _applyEmailFallback();
      await _syncBiometricUi();
      if (mounted) {
        if (_canUseBiometric) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (mounted) _tryBiometricUnlock();
              });
            }
          });
        }
      }
    } catch (e) {
      // PIN field always visible; errors in init only affect biometric flags.
      if (mounted) setState(() {});
    }
  }

  /// Supabase can omit [user.email] on some devices; [LoginScreen] still saves last used email.
  Future<void> _applyEmailFallback() async {
    if (_userEmail != null && _userEmail!.trim().isNotEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      final e = p.getString(_kPrefLastEmail)?.trim();
      if (e != null && e.isNotEmpty) {
        _userEmail = e;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _tryBiometricUnlock() async {
    if (!_canUseBiometric || !_biometricSupported || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authenticated = await BiometricService.authenticate(
        reason: 'Unlock app with biometric',
        useErrorDialogs: true,
      );

      if (!mounted) return;

      if (authenticated) {
        await _unlockApp();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Biometric authentication failed. Please use PIN.';
        });
      }
    }
  }

  /// For login mode: local_auth then [AuthService.signInWithBiometric] (cached password).
  Future<void> _tryBiometricUnlockLogin() async {
    if (_userEmail == null || _userEmail!.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Account email not loaded. Use full login below.';
        });
      }
      return;
    }
    if (!_canUseBiometric || !_biometricSupported || !mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authenticated = await BiometricService.authenticate(
        reason: 'Login with biometric',
        useErrorDialogs: true,
      );

      if (!mounted) return;

      if (!authenticated) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      var result = await _authService.signInWithBiometric(email: _userEmail!);
      if (!mounted) return;

      if (result['success'] != true) {
        final msg = result['message']?.toString() ?? '';
        final needsCache = msg.toLowerCase().contains('not ready');
        if (needsCache) {
          final pin = _pinController.text.trim();
          if (AuthService.isValidLoginPinLength(pin)) {
            final filled = await _authService.ensureBiometricCacheUsingPin(
              email: _userEmail!,
              pin: pin,
            );
            if (filled && mounted) {
              result = await _authService.signInWithBiometric(
                email: _userEmail!,
              );
            }
          }
        }
      }

      if (!mounted) return;

      if (result['success'] == true) {
        await _unlockAppLogin();
      } else {
        final msg = result['message']?.toString() ?? '';
        setState(() {
          _isLoading = false;
          _errorMessage = msg.toLowerCase().contains('not ready')
              ? 'Use UNLOCK with your PIN once on this device. After that, Login with Biometric will work without entering PIN. Or use Logout and sign in with password once.'
              : (msg.isNotEmpty
                    ? msg
                    : 'Biometric sign-in failed. Please use UNLOCK with your PIN.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Biometric authentication failed. Please use PIN.';
        });
      }
    }
  }

  void _onPinDigitsChanged(String value) {
    final pin = value.trim();
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin) || _isLoading) {
      return;
    }
    _unlockWithPin();
  }

  Future<void> _unlockWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _errorMessage = 'Please enter PIN');
      return;
    }
    if (!AuthService.isValidLoginPinLength(pin)) {
      setState(() => _errorMessage = AuthService.loginPinLengthMessage);
      return;
    }

    if (_isLoginMode && (_userEmail == null || _userEmail!.trim().isEmpty)) {
      setState(
        () => _errorMessage =
            'Account email not loaded. Tap Logout and use full login.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Check if in login mode or app-resume mode
      if (_isLoginMode) {
        // ✅ LOGIN MODE: Use signInWithPIN
        final result = await _authService.signInWithPIN(
          email: _userEmail!,
          pin: pin,
        );

        if (!mounted) return;

        if (result['success'] == true) {
          if (_userEmail != null &&
              await BiometricService.isBiometricEnabledForAdmin(_userEmail!)) {
            await _authService.cacheBiometricSecretUsingCurrentPin(
              email: _userEmail!,
              pin: pin,
            );
          }
          // Successful login
          await _unlockAppLogin();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage =
                result['message'] ?? 'Incorrect PIN. Please try again.';
            _pinController.clear();
          });
          HapticFeedback.vibrate();
        }
      } else {
        // ✅ APP RESUME MODE: Use verifyPIN (user already authenticated)
        final isValid = await _authService.verifyPIN(_userId!, pin);

        if (!mounted) return;

        if (isValid) {
          if (_userEmail != null &&
              await BiometricService.isBiometricEnabledForAdmin(_userEmail!)) {
            await _authService.cacheBiometricSecretUsingCurrentPin(
              email: _userEmail!,
              pin: pin,
            );
          }
          await _unlockApp();
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Incorrect PIN. Please try again.';
            _pinController.clear();
          });
          HapticFeedback.vibrate();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'PIN verification failed. Please try again.';
          _pinController.clear();
        });
      }
    }
  }

  /// Login mode unlock: Check GPS configuration, offer biometric setup, then navigate
  Future<void> _navigateHomeByRole() async {
    if (!mounted) return;
    final uid = appDb.auth.currentUser?.id;
    if (uid == null) {
      Navigator.pushReplacementNamed(context, LoginScreen.routeName);
      return;
    }
    try {
      final row = await appDb
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      final role = row?['role'] as String?;
      if (role == 'attendance_user') {
        if (mounted) {
          final nav = rootNavigatorKey.currentState;
          if (nav != null && nav.mounted) {
            nav.pushReplacementNamed(StaffAttendancePortalScreen.routeName);
          } else {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pushReplacementNamed(StaffAttendancePortalScreen.routeName);
          }
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      Navigator.pushReplacementNamed(context, MainNavigationScreen.routeName);
    }
  }

  Future<void> _unlockAppLogin() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    SessionManager.updateActivity();

    if (_isLoginMode && _biometricSupported && _userEmail != null) {
      final forUser = await BiometricService.isBiometricEnabledForAdmin(
        _userEmail!,
      );
      if (!forUser) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showBiometricSetupDialog(_userEmail!);
        }
        return;
      }
    }

    // Attendance instructors use the same locked institute GPS row as configured by institute admin (no separate zone).
    final user = appDb.auth.currentUser;
    String? roleGate;
    Map<String, dynamic>? profileForFence;
    if (user != null) {
      profileForFence = await appDb
          .from('profiles')
          .select('institute_id, role')
          .eq('id', user.id)
          .maybeSingle();
      roleGate = profileForFence?['role'] as String?;
      // ⚡ Timeout GPS check after 5 seconds to prevent hanging
      final gpsOk = await Future.any<bool>([
        GeofenceService().hasValidPersonalGpsForCurrentAdmin(
          preloadedProfile: profileForFence,
        ),
        Future.delayed(
          const Duration(seconds: 5),
          () => true,
        ), // ✅ Fallback after 5s
      ]).catchError((_) => true);
      if (!gpsOk && mounted) {
        if (roleGate == 'attendance_user') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your institute has not locked a GPS attendance point yet. Ask your admin to complete GPS Settings, then try again.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          await SessionManager.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, LoginScreen.routeName);
          }
          return;
        }
        Navigator.pushReplacementNamed(
          context,
          GpsSettingsScreen.routeName,
          arguments: {'mandatory': true, 'fromLogin': true},
        );
        return;
      }
    }

    if (user != null && mounted) {
      final isAttendanceInstructor = roleGate == 'attendance_user';
      final gateResult = isAttendanceInstructor
          // Instructors must be strictly inside institute radius: fail closed.
          ? await GeofenceService()
                .attendanceLocationGateForCurrentUser(
                  preloadedProfile: profileForFence,
                  fastFenceSampleForLogin: true,
                )
                .catchError(
                  (_) => <String, dynamic>{
                    'allowed': false,
                    'message':
                        'Location check failed. Please retry from institute premises.',
                  },
                )
          // Admin unlock keeps timeout fallback to avoid lock-screen hangs.
          : await Future.any<Map<String, dynamic>>([
              GeofenceService().attendanceLocationGateForCurrentUser(
                preloadedProfile: profileForFence,
                fastFenceSampleForLogin: true,
              ),
              Future.delayed(
                const Duration(seconds: 8),
                () => {'allowed': true},
              ),
            ]).catchError((_) => {'allowed': true});
      if (!mounted) return;
      if (gateResult['allowed'] != true) {
        final resumeRoute = roleGate == 'attendance_user'
            ? StaffAttendancePortalScreen.routeName
            : MainNavigationScreen.routeName;
        Navigator.pushNamedAndRemoveUntil(
          context,
          InstituteLocationGateScreen.routeName,
          (_) => false,
          arguments: {'resumeRoute': resumeRoute},
        );
        return;
      }
    }

    if (mounted) {
      await _navigateHomeByRole();
    }
  }

  /// App-resume mode unlock: already authenticated, just unlock
  Future<void> _unlockApp() async {
    if (!mounted) return;

    SessionManager.updateActivity();
    if (!mounted) return;

    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      await _navigateHomeByRole();
    }
  }

  Future<void> _showForgotPinDialog() async {
    if (_userEmail == null || _userEmail!.trim().isEmpty) {
      setState(() {
        _errorMessage =
            'Account email not found. Use Change user on the login screen.';
      });
      return;
    }

    final email = _userEmail!.trim();
    var dialogBusy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Forgot PIN',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            _isLoginMode
                ? 'You will go to the login screen, sign in with Institute ID, password and CAPTCHA, and then set a new PIN.'
                : 'You will be signed out and taken to the login screen. Sign in with Institute ID, password and CAPTCHA, then set a new PIN.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: dialogBusy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: dialogBusy
                  ? null
                  : () async {
                      setDialogState(() {
                        dialogBusy = true;
                      });

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(
                        _kPrefForgotPinEmail,
                        email.toLowerCase(),
                      );
                      await prefs.remove(_kPrefLastEmail);
                      await prefs.remove(_kPrefLastAdminEmail);
                      await prefs.remove(_kPrefLastInstituteId);
                      await prefs.remove(_kPrefLastUserHasPin);

                      await SessionManager.signOut();

                      if (!mounted || !dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      await Navigator.pushReplacementNamed(
                        context,
                        LoginScreen.routeName,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: Text(dialogBusy ? 'Please wait...' : 'Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    var dialogBusy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Sign out',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'You will be signed out and returned to the login screen.',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: dialogBusy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: dialogBusy
                  ? null
                  : () async {
                      setDialogState(() {
                        dialogBusy = true;
                      });

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.remove(_kPrefLastEmail);
                      await prefs.remove(_kPrefLastAdminEmail);
                      await prefs.remove(_kPrefLastUserHasPin);

                      await SessionManager.signOut();

                      if (!mounted || !dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!mounted) return;
                      await Navigator.pushReplacementNamed(
                        context,
                        LoginScreen.routeName,
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentSaffron,
                foregroundColor: Colors.white,
              ),
              child: Text(dialogBusy ? 'Please wait…' : 'Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForgotPinInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryBlue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textGray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewportH = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoH = viewportH * 0.14;
        final logoW = (logoH * AppUI.appLogoAspectRatio).clamp(
          0.0,
          constraints.maxWidth * 0.88,
        );
        return Column(
          children: [
            Center(
              child: Container(
                width: logoW,
                height: logoH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 7),
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.r),
                  child: Padding(
                    padding: EdgeInsets.all(logoH * 0.06),
                    child: Image.asset(AppUI.appLogoAsset, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              l10n.loginAppTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 22.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              l10n.loginSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textGray,
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Matches [LoginScreen] `_buildGovPINField` styling.
  /// Shows PIN entry with status message about biometric availability.
  Widget _buildGovPinField() {
    // Determine label text based on biometric availability
    String labelText = 'Enter PIN  |  पिन टाका';
    if (!_biometricSupported) {
      labelText = 'No biometric - Enter PIN  |  बायोमेट्रिक नहीं - पिन टाका';
    } else if (_canUseBiometric) {
      labelText = 'PIN (Biometric enabled)  |  पिन (बायोमेट्रिक सक्षम)';
    }

    return TextFormField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 4,
      obscureText: true,
      textAlign: TextAlign.center,
      autofocus: !_canUseBiometric,
      style: TextStyle(
        color: AppTheme.primaryBlue,
        fontSize: 22.sp,
        letterSpacing: 10,
        fontWeight: FontWeight.bold,
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: '4 digits  |  ४ अंक',
        hintStyle: TextStyle(
          color: AppTheme.textLightGray,
          fontSize: 18.sp,
          letterSpacing: 8,
        ),
        prefixIcon: Icon(
          _biometricSupported ? Icons.fingerprint_rounded : Icons.pin_rounded,
          color: AppTheme.textGray,
          size: 19.sp,
        ),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppTheme.dividerColor,
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppTheme.dividerColor,
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
        ),
        counterText: '',
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
      ),
      onChanged: _onPinDigitsChanged,
      onFieldSubmitted: (_) => _unlockWithPin(),
    );
  }

  Widget _buildUnlockButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _unlockWithPin,
      child: Container(
        width: double.infinity,
        height: 52.h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _isLoading
                ? [AppTheme.primaryBlueDark, AppTheme.primaryBlue]
                : [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
              spreadRadius: 1,
            ),
          ],
        ),
        child: _isLoading
            ? Center(
                child: SizedBox(
                  width: 24.w,
                  height: 24.w,
                  child: const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
              )
            : Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.lock_open_rounded,
                      color: Colors.white,
                      size: 20.sp,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          'UNLOCK  |  अनलॉक',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// Show dialog to enable biometric after successful PIN login
  void _showBiometricSetupDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.fingerprint_rounded,
                color: AppTheme.primaryBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Enable Biometric Login',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              'Speed up your next login using your fingerprint or face recognition.',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textGray,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_open_rounded,
                    color: AppTheme.primaryGreen,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Login instantly next time',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryGreen,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Skip biometric setup, go to home
              await _proceedAfterLoginFlow();
            },
            child: const Text(
              'Not Now',
              style: TextStyle(color: AppTheme.textGray),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Enable biometric
              await _enableBiometric(email);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Enable Now'),
          ),
        ],
      ),
    );
  }

  /// Enable biometric authentication for the user
  Future<void> _enableBiometric(String email) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      // Step 1: Authenticate with biometric to confirm setup
      final authenticated = await BiometricService.authenticate(
        reason: 'Enable biometric login',
        useErrorDialogs: true,
        requirePreferenceEnabled: false,
      );

      if (!mounted) return;

      if (authenticated) {
        // Step 2: Cache biometric credentials
        final user = appDb.auth.currentUser;
        if (user != null) {
          // Mark biometric as enabled for this device/email
          await BiometricService.enableBiometric(email);
          await _authService.cacheBiometricSecretUsingCurrentPin(
            email: email,
            pin: _pinController.text.trim(),
          );
          await _refreshBiometricFlags();

          if (mounted) {
            setState(() => _isLoading = false);
            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Biometric enabled! Next login will be faster.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: AppTheme.primaryGreen,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
            // Proceed to next step (GPS or home)
            await Future.delayed(const Duration(seconds: 2));
            if (mounted) {
              await _proceedAfterLoginFlow();
            }
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          // User cancelled biometric setup
          await _proceedAfterLoginFlow();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Could not enable biometric. Proceeding without it.',
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.accentOrange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        // Proceed anyway
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          await _proceedAfterLoginFlow();
        }
      }
    }
  }

  /// Continue with post-login flow (check GPS, navigate to home)
  Future<void> _proceedAfterLoginFlow() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    final user = appDb.auth.currentUser;
    if (user != null) {
      final prof = await appDb
          .from('profiles')
          .select('institute_id, role')
          .eq('id', user.id)
          .maybeSingle();
      final role = prof?['role'] as String?;
      final gpsOk = await GeofenceService().hasValidPersonalGpsForCurrentAdmin(
        preloadedProfile: prof,
      );
      if (!gpsOk && mounted) {
        if (role == 'attendance_user') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your institute has not locked a GPS attendance point yet. Ask your admin to complete GPS Settings, then try again.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          await SessionManager.signOut();
          if (mounted) {
            Navigator.pushReplacementNamed(context, LoginScreen.routeName);
          }
          return;
        }
        Navigator.pushReplacementNamed(
          context,
          GpsSettingsScreen.routeName,
          arguments: {'mandatory': true, 'fromLogin': true},
        );
        return;
      }
    }

    if (mounted) {
      await _navigateHomeByRole();
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _userEmail ?? '';
    final initials = email.isEmpty
        ? 'U'
        : (email.split('@').first.isEmpty
              ? 'U'
              : email.split('@').first.substring(0, 1).toUpperCase());

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GovPortalHeader(
              primaryLine: 'Secure session  |  सुरक्षित सत्र',
              secondaryLine: _canUseBiometric && _biometricSupported
                  ? 'PIN or biometric — same as government login'
                  : 'Enter your PIN to continue',
            ),
            Expanded(
              child: ResponsiveScrollBody(
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.padding(context).horizontal,
                  vertical: 20.h,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildLogoSection(context),
                    SizedBox(height: 20.h),
                    GovElevatedCard(
                      padding: EdgeInsets.zero,
                      child: Padding(
                        padding: EdgeInsets.all(20.w),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 4.w,
                                  height: 22.h,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        AppTheme.primaryBlueLight,
                                        AppTheme.primaryBlueDark,
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    'Unlock app  |  अ‍ॅप अनलॉक करा',
                                    style: TextStyle(
                                      color: AppTheme.primaryBlue,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 6.h),
                            const Divider(
                              color: AppTheme.dividerColor,
                              thickness: 1,
                            ),
                            SizedBox(height: 20.h),
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    width: 64.w,
                                    height: 64.h,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          AppTheme.primaryBlueLight,
                                          AppTheme.primaryBlueDark,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primaryBlue
                                              .withValues(alpha: 0.3),
                                          blurRadius: 14,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        initials,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 26.sp,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 10.h),
                                  if (email.isNotEmpty)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 14.w,
                                        vertical: 8.h,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.backgroundGrey,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: AppTheme.dividerColor,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.account_circle_outlined,
                                            color: AppTheme.textGray,
                                            size: 16,
                                          ),
                                          SizedBox(width: 6.w),
                                          Flexible(
                                            child: Text(
                                              email,
                                              style: TextStyle(
                                                color: AppTheme.textDark,
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  SizedBox(height: 4.h),
                                  Text(
                                    'Administrator session',
                                    style: TextStyle(
                                      color: AppTheme.textLightGray,
                                      fontSize: 10.5.sp,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 24.h),
                            _buildGovPinField(),
                            if (_errorMessage.isNotEmpty) ...[
                              SizedBox(height: 10.h),
                              Text(
                                _errorMessage,
                                style: TextStyle(
                                  color: AppTheme.accentRed,
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            SizedBox(height: 20.h),
                            _buildUnlockButton(),
                            if (_canUseBiometric && _biometricSupported) ...[
                              SizedBox(height: 14.h),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : (_isLoginMode
                                            ? _tryBiometricUnlockLogin
                                            : _tryBiometricUnlock),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryBlue,
                                    side: const BorderSide(
                                      color: AppTheme.primaryBlue,
                                      width: 1.5,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      vertical: 14.h,
                                      horizontal: 10.w,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: FutureBuilder<List<String>>(
                                    future:
                                        BiometricService.getAvailableBiometricNames(),
                                    builder: (context, snapshot) {
                                      final action = _isLoginMode
                                          ? 'Login'
                                          : 'Unlock';
                                      final label =
                                          snapshot.hasData &&
                                              snapshot.data!.isNotEmpty
                                          ? '$action with ${snapshot.data!.first}'
                                          : '$action with Biometric';
                                      return Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.fingerprint,
                                            size: 22,
                                          ),
                                          SizedBox(width: 8.w),
                                          Flexible(
                                            child: Text(
                                              label,
                                              textAlign: TextAlign.center,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.sp,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.primaryBlue,
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
                            SizedBox(height: 16.h),
                            if (_userEmail != null &&
                                _userEmail!.trim().isNotEmpty)
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 4.w,
                                runSpacing: 8.h,
                                children: [
                                  TextButton.icon(
                                    onPressed:
                                        (_isLoading ||
                                            _isForgotPinBusy ||
                                            _isLogoutBusy)
                                        ? null
                                        : () async {
                                            setState(
                                              () => _isForgotPinBusy = true,
                                            );
                                            try {
                                              await _showForgotPinDialog();
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () =>
                                                      _isForgotPinBusy = false,
                                                );
                                              }
                                            }
                                          },
                                    icon: const Icon(
                                      Icons.lock_reset_rounded,
                                      size: 18,
                                      color: AppTheme.textGray,
                                    ),
                                    label: Text(
                                      'Forgot PIN?  |  पिन विसरलात?',
                                      style: TextStyle(
                                        color: AppTheme.textGray,
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed:
                                        (_isLoading ||
                                            _isForgotPinBusy ||
                                            _isLogoutBusy)
                                        ? null
                                        : () async {
                                            setState(
                                              () => _isLogoutBusy = true,
                                            );
                                            try {
                                              await _showLogoutDialog();
                                            } finally {
                                              if (mounted) {
                                                setState(
                                                  () => _isLogoutBusy = false,
                                                );
                                              }
                                            }
                                          },
                                    icon: Icon(
                                      Icons.logout_rounded,
                                      size: 18,
                                      color: AppTheme.accentSaffron.withValues(
                                        alpha: 0.9,
                                      ),
                                    ),
                                    label: Text(
                                      'Logout  |  लॉगआउट',
                                      style: TextStyle(
                                        color: AppTheme.accentSaffron,
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
