import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_attendance_app/l10n/app_localizations.dart';
import '../../services/locale_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
import '../../services/biometric_service.dart';
import '../../services/geofence_service.dart';
import '../../services/security_ops_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/credential_strength.dart';
import '../../core/utils/responsive.dart';
import '../widgets/credential_strength_indicator.dart';
import 'main_navigation_screen.dart';
import 'institute_search_screen.dart';
import 'attendance_staff_login_screen.dart';
import 'staff_attendance_portal_screen.dart';
import 'gps_settings_screen.dart';
import 'institute_location_gate_screen.dart';
import 'biometric_lock_screen.dart';
import 'forgot_password_screen.dart';
import '../widgets/support_email_footer.dart';
import '../../core/app_db.dart';
import '../../config/admin_portal_url.dart';
import '../../services/pin_session_manager.dart';
import '../../services/pin_midnight_logout_service.dart';

// ─── CAPTCHA PAINTER ──────────────────────────────────────────────────────────

class _CaptchaPainter extends CustomPainter {
  final String text;
  final List<Color> charColors;
  final List<double> charRotations;

  const _CaptchaPainter({
    required this.text,
    required this.charColors,
    required this.charRotations,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFFEEF4FF),
          const Color(0xFFE8F0FE),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(8)),
      bgPaint,
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppTheme.primaryBlue.withValues(alpha: 0.25)
        ..strokeWidth = 1.5,
    );

    // Noise lines
    final noisePaint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rand = math.Random(text.hashCode);
    for (int i = 0; i < 6; i++) {
      noisePaint.color = [
        AppTheme.primaryBlue,
        AppTheme.accentSaffron,
        AppTheme.primaryGreen,
      ][i % 3]
          .withValues(alpha: 0.15 + rand.nextDouble() * 0.15);
      canvas.drawLine(
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        noisePaint,
      );
    }
    // Noise dots
    final dotPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 20; i++) {
      dotPaint.color =
          AppTheme.primaryBlue.withValues(alpha: 0.08 + rand.nextDouble() * 0.1);
      canvas.drawCircle(
        Offset(rand.nextDouble() * size.width,
            rand.nextDouble() * size.height),
        1.2 + rand.nextDouble() * 1.5,
        dotPaint,
      );
    }

    // Draw each character
    final charW = size.width / (text.length + 1);
    for (int i = 0; i < text.length; i++) {
      final x = charW * (i + 0.6) + charW * 0.2;
      final y = size.height / 2 + (rand.nextDouble() - 0.5) * 8;
      final fontSize = 20.0 + rand.nextDouble() * 6;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(charRotations[i]);

      final tp = TextPainter(
        text: TextSpan(
          text: text[i],
          style: TextStyle(
            color: charColors[i],
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CaptchaPainter oldDelegate) =>
      oldDelegate.text != text;
}

// ─── LOGIN SCREEN ─────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  static const routeName = '/login';
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool get _allowDebugAttestationBypass {
    if (!kDebugMode) return false;
    final raw = (dotenv.env['ALLOW_ATTESTATION_BYPASS'] ?? '').trim().toLowerCase();
    return raw == '1' || raw == 'true' || raw == 'yes' || raw == 'on';
  }

  // ── Form controllers ─────────────────────────────────────────────────────────
  /// NEW FLOW: Institute ID (numeric only) + Password login
  final _emailController = TextEditingController();
  final _instituteIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  final _captchaController = TextEditingController();
  // ── Services ─────────────────────────────────────────────────────────────────
  final AuthService _authService = AuthService();
  final GeofenceService _geofenceService = GeofenceService();
  final SecurityOpsService _securityOps = SecurityOpsService();

  // ── State ────────────────────────────────────────────────────────────────────
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _biometricSupported = false;
  bool _showBiometricOnPinCard = false;
  String? _currentUserId;

  // ── Returning-user flow state ────────────────────────────────────────────────
  bool _isReturningUser = false;
  String? _savedEmail;
  /// Matches [AttendanceStaffLoginScreen]: editable until a code exists in prefs
  /// (`msce_last_institute_id` or `msce_last_staff_institute_code`).
  bool _instituteIdFieldDisabled = false;

  /// After a successful forgot-password reset, button disabled until this time.
  DateTime? _forgotPasswordCooldownUntil;

  static const String _prefLastEmail = 'msce_last_admin_email';
  static const String _prefLastInstituteId = 'msce_last_institute_id';
  static const String _prefLastUserHasPin = 'msce_last_user_has_pin';
  static const String _prefForgotPinEmail = 'msce_forgot_pin_email';

  // ── CAPTCHA state ─────────────────────────────────────────────────────────────
  String _captchaText = '';
  List<Color> _captchaColors = [];
  List<double> _captchaRotations = [];
  bool _captchaVerified = false;
  static const String _captchaChars =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  // ── Animation Controllers ─────────────────────────────────────────────────────
  late AnimationController _masterController;
  late AnimationController _buttonPulseController;

  late Animation<double> _logoFlip;
  late Animation<double> _screenFade;
  late Animation<double> _cardTiltX;
  late Animation<double> _cardSlideY;
  late Animation<double> _cardFade;
  late Animation<double> _buttonPulse;

  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    _generateCaptcha();
    _setupAnimations();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      String? routeInstituteId;
      if (args is Map && args['instituteId'] != null) {
        routeInstituteId = args['instituteId'].toString().trim();
        if (routeInstituteId.isNotEmpty) {
          _instituteIdController.text = routeInstituteId;
        }
      }
      // forceFullLogin: show email/password/CAPTCHA (same as "Change user"), clear saved email.
      if (args is Map && args['forceFullLogin'] == true) {
        await _switchToChangeUser();
        if (args['instituteId'] != null) {
          final id = args['instituteId'].toString().trim();
          if (id.isNotEmpty) {
            routeInstituteId = id;
            _instituteIdController.text = id;
          }
        }
      } else {
        final pinRestored = await _checkAndRestorePinSessionIfActive();
        if (pinRestored) return;
        // Check if returning user with PIN - if so, _loadSavedUser() navigates away
        final navigatedAway = await _loadSavedUser();
        if (navigatedAway) return;
      }
      if (!mounted) return;
      // Mirror instructor logout/staff handoff: persist route institute to admin pref.
      if (routeInstituteId != null && routeInstituteId.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefLastInstituteId, routeInstituteId);
      }
      if (!mounted) return;
      await _hydrateInstituteDisplayIfNeeded();
      if (!mounted) return;
      await _applyInstituteIdFieldLockFromStorage();
      if (!mounted) return;
      await _loadForgotPasswordCooldown();
      if (!mounted) return;
      _checkBiometricStatus();
    });
  }

  Future<void> _loadForgotPasswordCooldown() async {
    final until = await AuthService.forgotPasswordAvailableAt();
    if (!mounted) return;
    setState(() => _forgotPasswordCooldownUntil = until);
  }

  Future<void> _openForgotPassword() async {
    if (await AuthService.isForgotPasswordCooldownActive()) {
      final until = _forgotPasswordCooldownUntil ??
          await AuthService.forgotPasswordAvailableAt();
      final label = until != null
          ? 'Forgot password is disabled until ${_formatCooldownTime(until)}.'
          : 'Forgot password is disabled for 24 hours after your last reset.';
      _showModernSnackbar(label, isSuccess: false);
      return;
    }

    var instituteId = _instituteIdController.text.trim();
    if (instituteId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        instituteId = prefs.getString(_prefLastInstituteId)?.trim() ?? '';
        if (instituteId.isNotEmpty && mounted) {
          _instituteIdController.text = instituteId;
        }
      } catch (_) {}
    }

    if (instituteId.isEmpty) {
      _showModernSnackbar('Enter or save Institute ID first.', isSuccess: false);
      return;
    }

    setState(() => _isLoading = true);
    final email = await _authService.getAdminResetEmailForInstitute(instituteId);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (email == null || email.isEmpty) {
      _showModernSnackbar(
        'No admin invite email found for this institute. Complete setup or contact support.',
        isSuccess: false,
      );
      return;
    }

    final resetOk = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: ForgotPasswordScreen.routeName),
        builder: (_) => ForgotPasswordScreen(
          initialInstituteId: instituteId,
          initialEmail: email,
        ),
      ),
    );

    if (resetOk == true) {
      _passwordController.clear();
      _generateCaptcha();
      await _loadForgotPasswordCooldown();
      if (!mounted) return;
      _showModernSnackbar(
        'Password updated. Sign in with your new password.',
        isSuccess: true,
      );
    }
  }

  String _formatCooldownTime(DateTime until) {
    final local = until.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month}/${local.year} $h:$m';
  }

  // ─── CAPTCHA ──────────────────────────────────────────────────────────────────

  void _generateCaptcha() {
    final rand = math.Random();
    final sb = StringBuffer();
    for (int i = 0; i < 6; i++) {
      sb.write(_captchaChars[rand.nextInt(_captchaChars.length)]);
    }
    final colors = [
      AppTheme.primaryBlue,
      AppTheme.accentRed,
      AppTheme.primaryGreen,
      const Color(0xFF6B21A8), // purple
      AppTheme.accentSaffron,
      AppTheme.primaryBlueDark,
    ]..shuffle(rand);
    setState(() {
      _captchaText = sb.toString();
      _captchaColors = List.generate(6, (i) => colors[i % colors.length]);
      _captchaRotations = List.generate(
          6, (_) => (rand.nextDouble() - 0.5) * 0.45);
      _captchaVerified = false;
      _captchaController.clear();
    });
  }

  bool _verifyCaptcha() {
    return _captchaController.text.trim().toUpperCase() == _captchaText;
  }

  // ─── SAVED USER ───────────────────────────────────────────────────────────────

  /// Restore active PIN session (admin → main nav, instructor → staff portal).
  /// Returns true if navigation replaced this screen.
  Future<bool> _checkAndRestorePinSessionIfActive() async {
    try {
      if (!await PinSessionManager.hasActivePinSession() || !mounted) {
        return false;
      }

      final sessionData = await PinSessionManager.restorePinSession();
      final instituteId = sessionData?['instituteId']?.toString().trim() ?? '';
      if (instituteId.isEmpty) return false;

      final userData = sessionData?['userData'] as Map<String, dynamic>?;
      final isStaff = PinSessionManager.isAttendanceStaffSessionData(userData);
      final route = isStaff
          ? StaffAttendancePortalScreen.routeName
          : MainNavigationScreen.routeName;

      if (kDebugMode) {
        debugPrint(
          '✅ PIN session restored → ${isStaff ? "staff portal" : "admin home"}',
        );
      }

      Navigator.of(context, rootNavigator: true).pushReplacementNamed(route);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking PIN session: $e');
      return false;
    }
  }

  /// Load saved user and check if they have PIN.
  /// Returns true if navigated to BiometricLockScreen, false otherwise.
  Future<bool> _loadSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_prefLastEmail);
      final instituteId = prefs.getString(_prefLastInstituteId);
      if (mounted &&
          instituteId != null &&
          instituteId.isNotEmpty &&
          _instituteIdController.text.trim().isEmpty) {
        _instituteIdController.text = instituteId;
      }
      if (email != null && email.isNotEmpty) {
        final localHadPin = prefs.getBool(_prefLastUserHasPin) ?? false;
        bool serverHasPin = false;
        try {
          serverHasPin = await _authService.hasPINForEmail(email);
        } catch (_) {}
        final hasPIN = serverHasPin || localHadPin;
        if (mounted) {
          if (hasPIN) {
            // ✅ Check if PIN session is still active (before midnight)
            // If session is valid, restore directly WITHOUT BiometricLockScreen
            final hasActiveSession = await PinSessionManager.hasActivePinSession();
            if (hasActiveSession) {
              if (kDebugMode) {
                debugPrint('✅ Session still active - restoring without PIN prompt');
              }
              // Session valid - navigate directly to home
              _scheduleLocationLockFeedback();
              await _navigateBasedOnGpsStatus();
              return true; // Navigated away
            }

            // ✅ Session expired or no active session - show BiometricLockScreen
            // User must re-authenticate with PIN
            Navigator.pushReplacementNamed(
              context,
              BiometricLockScreen.routeName,
              arguments: {'loginEmail': email},
            );
            return true; // Navigated away
          }

          // No PIN: show full login form
          setState(() {
            _savedEmail = email;
            _isReturningUser = false;
            _emailController.text = email;
            if (instituteId != null) {
              _instituteIdController.text = instituteId;
            }
            _instituteIdFieldDisabled =
                instituteId != null && instituteId.trim().isNotEmpty;
          });
        }
      }
    } catch (_) {}
    return false; // Didn't navigate away
  }

  /// Lock the institute field when either admin or instructor prefs carry a saved code.
  Future<void> _applyInstituteIdFieldLockFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final admin = prefs.getString(_prefLastInstituteId)?.trim() ?? '';
      final staff =
          (await PinSessionManager.getLastStaffInstituteCode())?.trim() ?? '';
      final shouldLock = admin.isNotEmpty || staff.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _instituteIdFieldDisabled = shouldLock;
      });
    } catch (_) {}
  }

  /// Instructor flow saves `msce_last_staff_institute_code`; password login reads
  /// `msce_last_institute_id`. Hydrate Institute ID field from either source.
  Future<void> _hydrateInstituteDisplayIfNeeded() async {
    if (_instituteIdController.text.trim().isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromAdminPrefs = prefs.getString(_prefLastInstituteId)?.trim() ?? '';
      final fromStaffPrefs =
          (await PinSessionManager.getLastStaffInstituteCode())?.trim() ?? '';
      final code = fromAdminPrefs.isNotEmpty ? fromAdminPrefs : fromStaffPrefs;
      if (code.isEmpty || !mounted) return;
      _instituteIdController.text = code;
      await prefs.setString(_prefLastInstituteId, code);
      setState(() {});
    } catch (_) {}
  }

  Future<void> _saveLastUser(String email, {String? instituteId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastEmail, email);
      final key = instituteId?.trim();
      if (key != null && key.isNotEmpty) {
        await prefs.setString(_prefLastInstituteId, key);
      }
    } catch (_) {}
  }

  Future<void> _persistLastUserHasPin(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value) {
        await prefs.setBool(_prefLastUserHasPin, true);
      } else {
        await prefs.remove(_prefLastUserHasPin);
      }
    } catch (_) {}
  }

  Future<String?> _consumeForgotPinEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_prefForgotPinEmail)?.trim();
      await prefs.remove(_prefForgotPinEmail);
      if (email == null || email.isEmpty) return null;
      return email.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  Future<void> _switchToChangeUser() async {
    String? savedInstituteId;
    try {
      final prefs = await SharedPreferences.getInstance();
      savedInstituteId = prefs.getString(_prefLastInstituteId);
      await prefs.remove(_prefLastEmail);
      await prefs.remove(_prefLastUserHasPin);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isReturningUser = false;
      _emailController.clear();
      _instituteIdController.text = savedInstituteId?.trim() ?? '';
      _passwordController.clear();
      _pinController.clear();
      final sid = savedInstituteId?.trim() ?? '';
      _instituteIdFieldDisabled = sid.isNotEmpty;
    });
    _generateCaptcha();
  }

  void _setupAnimations() {
    _masterController = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this);
    _buttonPulseController = AnimationController(
        duration: const Duration(milliseconds: 1600), vsync: this)
      ..repeat(reverse: true);

    _screenFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.0, 0.15, curve: Curves.easeIn)),
    );
    _logoFlip = Tween<double>(begin: -math.pi / 2, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.05, 0.35, curve: Curves.elasticOut)),
    );
    _cardFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.55, curve: Curves.easeIn)),
    );
    _cardTiltX = Tween<double>(begin: -0.18, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _cardSlideY = Tween<double>(begin: 45.0, end: 0.0).animate(
      CurvedAnimation(parent: _masterController,
          curve: const Interval(0.35, 0.65, curve: Curves.easeOutCubic)),
    );
    _buttonPulse = Tween<double>(begin: 1.0, end: 1.028).animate(
      CurvedAnimation(parent: _buttonPulseController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _masterController.forward();
    });
  }

  // ─── BIOMETRIC ────────────────────────────────────────────────────────────────

  Future<void> _checkBiometricStatus() async {
    final isSupported = await BiometricService.isDeviceSupported();
    final anyAdminBio = await BiometricService.isBiometricEnabled();
    final saved = _savedEmail?.trim() ?? '';
    var forSaved = false;
    if (isSupported && saved.isNotEmpty) {
      forSaved = await BiometricService.isBiometricEnabledForAdmin(saved);
    }
    if (mounted) {
      setState(() {
        _biometricSupported = isSupported;
        _showBiometricOnPinCard = isSupported && (forSaved || anyAdminBio);
      });
      if (_isReturningUser && isSupported && (forSaved || anyAdminBio)) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) _tryBiometricLogin();
        });
      }
    }
  }

  Future<void> _tryBiometricLogin() async {
    if (!_biometricSupported || !mounted) return;

    final anyAdminBio = await BiometricService.isBiometricEnabled();
    if (!anyAdminBio) {
      if (mounted) {
        _showModernSnackbar(
          'Biometric login is not set up on this phone. Log in with password once, then enable biometric.',
          isSuccess: false,
        );
      }
      return;
    }

    String? selectedEmail;
    final saved = _savedEmail?.trim();
    if (saved != null && saved.isNotEmpty) {
      if (await BiometricService.isBiometricEnabledForAdmin(saved)) {
        selectedEmail = saved;
      }
    }

    if (selectedEmail == null) {
      final biometricAdmins = await BiometricService.getBiometricEnabledAdmins();
      if (biometricAdmins.isEmpty) return;

      if (biometricAdmins.length > 1) {
        selectedEmail =
            await _showBiometricAdminSelectionDialog(biometricAdmins);
        if (selectedEmail == null || !mounted) return;
      } else {
        selectedEmail = biometricAdmins.first;
      }
    }

    _emailController.text = selectedEmail;

    // Verify biometric
    final authenticated = await BiometricService.authenticate(
      reason: 'Use biometric to login as $selectedEmail',
      useErrorDialogs: true,
    );
    if (!mounted) return;
    if (!authenticated) return;

    setState(() => _isLoading = true);
    var result = await _authService.signInWithBiometric(email: selectedEmail);
    if (!mounted) return;

    if (result['success'] != true) {
      final msg = result['message']?.toString() ?? '';
      if (msg.toLowerCase().contains('not ready')) {
        final pin = _pinController.text.trim();
        if (AuthService.isValidLoginPinLength(pin)) {
          final filled = await _authService.ensureBiometricCacheUsingPin(
            email: selectedEmail,
            pin: pin,
          );
          if (filled && mounted) {
            result = await _authService.signInWithBiometric(email: selectedEmail);
          }
        }
      }
    }
    if (!mounted) return;

    if (result['success'] == true) {
      _currentUserId = result['userId'];
      final String role = result['role'];
      if (role != 'admin') {
        setState(() => _isLoading = false);
        _showModernSnackbar('Access denied. Admin only.', isSuccess: false);
        return;
      }

      await _saveLastUser(selectedEmail);
      await _persistLastUserHasPin(true);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _savedEmail = selectedEmail;
        _isReturningUser = true;
      });
      _scheduleLocationLockFeedback();
      if (mounted) await _navigateBasedOnGpsStatus();
    } else {
      setState(() => _isLoading = false);
      _showLoginFailure(result);
    }
  }

  /// Show dialog to select which admin to login as when multiple have biometric enabled
  Future<String?> _showBiometricAdminSelectionDialog(List<String> admins) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Select Admin Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Multiple admin accounts have biometric enabled on this device.\nSelect which admin to login as:'),
              const SizedBox(height: 16),
              ...admins.map((email) => ListTile(
                title: Text(email),
                onTap: () => Navigator.pop(dialogContext, email),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _instituteIdController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _captchaController.dispose();
    _masterController.dispose();
    _buttonPulseController.dispose();
    super.dispose();
  }

  // ─── AUTH LOGIC ───────────────────────────────────────────────────────────────

  /// Called when user taps LOGIN in the PIN screen.
  void _handlePINLogin() async {
    final email = _savedEmail ?? _emailController.text.trim();
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      _showModernSnackbar('PIN is required', isSuccess: false);
      return;
    }
    if (!AuthService.isValidLoginPinLength(pin)) {
      _showModernSnackbar(AuthService.loginPinLengthMessage, isSuccess: false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ Check location permission first (admin PIN login GPS verification)
      final hasPermission = await PinSessionManager.hasLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          _showModernSnackbar(
            'Location permission required for PIN login. Please enable location in app settings.',
            isSuccess: false,
          );
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ✅ Check if location services are enabled
      final isEnabled = await PinSessionManager.ensureLocationEnabled();
      if (!isEnabled) {
        if (mounted) {
          _showModernSnackbar(
            'Location services are disabled. Please enable them to continue.',
            isSuccess: false,
          );
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Get institute ID for GPS verification
      final instituteId = _instituteIdController.text.trim();
      if (instituteId.isEmpty) {
        if (mounted) {
          _showModernSnackbar('Institute ID required', isSuccess: false);
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ✅ Try to get cached GPS coordinates from previous login
      final cachedGps = await PinSessionManager.getCachedGpsCoordinates();

      // ✅ Verify user is within PIN-login geofence (25m nominal + accuracy slack)
      final locationResult = await PinSessionManager.verifyLocationRadius(
        instituteId: instituteId,
        cachedLatitude: cachedGps.latitude,
        cachedLongitude: cachedGps.longitude,
      );

      if (!locationResult.isWithinRadius) {
        // Check if GPS is not configured (vs being out of radius)
        if (locationResult.error?.contains('GPS is not locked') == true) {
          if (kDebugMode) {
            debugPrint('🛰️ GPS NOT CONFIGURED - navigating to GPS Settings');
            debugPrint('   Error message: ${locationResult.error}');
            debugPrint('   Institute ID: $instituteId');
          }
          if (mounted) setState(() => _isLoading = false);
          Navigator.pushNamedAndRemoveUntil(
            context,
            GpsSettingsScreen.routeName,
            (route) => false,
            arguments: {
              'mandatory': true,
              'fromLogin': true,
              'instituteId': instituteId,
            },
          );
          return;
        }

        if (mounted) {
          final distanceStr = locationResult.distanceMeters != null
              ? ' (${PinSessionManager.formatDistance(locationResult.distanceMeters!)})'
              : '';
          _showModernSnackbar(
            '❌ Out of Radius - Try Again$distanceStr',
            isSuccess: false,
          );
        }
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (kDebugMode) {
        debugPrint('📍 PIN login: User within allowed GPS zone - allowing login');
      }

      final result =
          await _authService.signInWithPIN(email: email, pin: pin);
      if (!mounted) return;

      if (result['success']) {
        _currentUserId = result['userId'];
        final String role = result['role'];
        // ✅ Allow both admin AND staff PIN login (with GPS verification)
        if (role != 'admin' && role != 'staff') {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showModernSnackbar('Access denied. Only admin and staff can use PIN login.', isSuccess: false);
          return;
        }
        await _persistLastUserHasPin(true);
        if (!mounted) return;

        // 💾 Save PIN session for persistence until midnight
        final instituteCode = _instituteIdController.text.trim();
        final adminEmail = email;
        final now = DateTime.now();

        await PinSessionManager.savePinSession(
          instituteId: instituteCode,
          userName: adminEmail,
          userData: {
            'loginTime': now.toIso8601String(),
            'adminEmail': adminEmail,
          },
        );

        // ⏰ Start midnight auto-logout monitor
        PinMidnightLogoutService.startMidnightMonitor();

        if (kDebugMode) {
          debugPrint('✅ PIN session saved and midnight monitor started');
        }

        setState(() => _isLoading = false);
        _scheduleLocationLockFeedback();
        if (mounted) await _navigateBasedOnGpsStatus();
      } else {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showLoginFailure(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
    }
  }

  /// Institute ID + password login. Email is resolved internally so Supabase
  /// still creates the authenticated session required by existing RLS.
  Future<void> _handleFullFormLogin() async {
    final instituteKey = _instituteIdController.text.trim();
    final password = _passwordController.text;
    if (instituteKey.isEmpty) {
      _showModernSnackbar('Institute ID is required', isSuccess: false);
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(instituteKey)) {
      _showModernSnackbar('Institute ID must be numeric only', isSuccess: false);
      return;
    }
    if (password.isEmpty) {
      _showModernSnackbar('Password is required', isSuccess: false);
      return;
    }

    if (!_verifyCaptcha()) {
      _showModernSnackbar(
          'Verification code is incorrect. Please try again.',
          isSuccess: false);
      _generateCaptcha();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Resolve admin email in parallel with device risk work to cut wall-clock time.
      final riskFuture = _securityOps.collectDeviceRiskSignals();
      final emailFuture = _authService.getAdminEmailForInstituteLogin(instituteKey);

      final risk = await riskFuture;
      final riskFlags =
          (risk['riskFlags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      if (riskFlags.contains('unknown_platform') ||
          riskFlags.contains('risk_collection_error')) {
        await emailFuture;
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showModernSnackbar(
          'Security check failed on this device. Please retry or contact support.',
          isSuccess: false,
        );
        return;
      }

      final platform = (risk['platform'] ?? 'unknown').toString();
      final deviceTrustFuture = _securityOps.verifyDeviceTrust(
        platform: platform,
        // Free mode: use deterministic device fingerprint token for baseline trust scoring.
        token: (risk['fingerprint'] ?? '').toString(),
      );
      final trustAndEmail = await Future.wait<dynamic>([
        deviceTrustFuture,
        emailFuture,
      ]);
      final deviceTrust = trustAndEmail[0] as Map<String, dynamic>;
      final email = trustAndEmail[1] as String?;

      if ((deviceTrust['verified'] ?? false) != true) {
        final reason = (deviceTrust['reason'] ?? 'unknown').toString();
        if (_allowDebugAttestationBypass) {
          // Keep development/testing unblocked when attestation plumbing is incomplete,
          // but surface a clear warning so this is never missed before release.
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showModernSnackbar(
            'Debug bypass enabled: device trust check skipped ($reason). Disable ALLOW_ATTESTATION_BYPASS before release.',
            isSuccess: false,
          );
        } else {
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showModernSnackbar(
            'Device security check failed. Login blocked for security.',
            isSuccess: false,
          );
          return;
        }
      }

      if (email == null || email.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showModernSnackbar(
          'No active admin found for this Institute ID. Complete admin setup first.',
          isSuccess: false,
        );
        _generateCaptcha();
        return;
      }

      _emailController.text = email;
      await _saveLastUser(email, instituteId: instituteKey);

      await _handleFullLogin(
        email: email,
        password: password,
        instituteId: instituteKey,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
      _generateCaptcha();
    }
  }

  Future<void> _handleFullLogin({
    required String email,
    required String password,
    String? instituteId,
    bool isBiometric = false,
  }) async {
    try {
      // ✅ Authenticate FIRST (before GPS check)
      final result = await _authService.signInWithEmail(
          email: email, password: password);

      if (!mounted) return;

      if (result['success']) {
        _currentUserId = result['userId'];
        final String role = result['role'];
        if (role != 'admin') {
          setState(() => _isLoading = false);
          _showModernSnackbar('Access denied. Admin only.', isSuccess: false);
          return;
        }

        // ✅ NOW check GPS AFTER authentication succeeds
        final instId = instituteId ?? _instituteIdController.text.trim();
        if (instId.isNotEmpty) {
          final locationResult = await PinSessionManager.verifyLocationRadius(
            instituteId: instId,
            cachedLatitude: null,
            cachedLongitude: null,
          );

          if (!locationResult.isWithinRadius) {
            if (locationResult.error?.contains('GPS is not locked') == true) {
              if (kDebugMode) debugPrint('🛰️ GPS not configured - navigating to GPS Settings');
              if (mounted) setState(() => _isLoading = false);
              Navigator.pushNamedAndRemoveUntil(
                context,
                GpsSettingsScreen.routeName,
                (route) => false,
                arguments: {
                  'mandatory': true,
                  'fromLogin': true,
                  'instituteId': instId,
                },
              );
              return;
            }

            // Out of radius error
            if (mounted) {
              final distanceStr = locationResult.distanceMeters != null
                  ? ' (${PinSessionManager.formatDistance(locationResult.distanceMeters!)})'
                  : '';
              _showModernSnackbar(
                '❌ Out of Radius - Try Again$distanceStr',
                isSuccess: false,
              );
            }
            if (mounted) setState(() => _isLoading = false);
            return;
          }
        }

        // Save email for future PIN-only logins
        await Future.wait<void>([
          _saveLastUser(
            email,
            instituteId: instituteId ?? _instituteIdController.text.trim(),
          ),
          _authService.cacheBiometricLogin(
            email: email,
            password: password,
          ),
        ]);

        final userData =
            (result['userData'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        var hasPin = userData['hasPIN'] == true;
        final forgotPinFuture = _consumeForgotPinEmail();
        final pinChecks = await Future.wait<Object?>([
          forgotPinFuture,
          hasPin ? Future<bool>.value(true) : _authService.hasPIN(_currentUserId!),
        ]);
        final forgotPinEmail = pinChecks[0] as String?;
        hasPin = pinChecks[1] as bool;
        final normalizedLoginEmail = AuthService.normalizeLoginEmail(email);
        if (forgotPinEmail == normalizedLoginEmail) {
          final clearPinResult = await _authService.clearPinForUser(
            userId: _currentUserId!,
            email: email,
          );
          if (clearPinResult['success'] != true) {
            setState(() => _isLoading = false);
            _showModernSnackbar(
              clearPinResult['message']?.toString() ?? 'Could not clear old PIN.',
              isSuccess: false,
            );
            return;
          }
          hasPin = false;
        }

        await _persistLastUserHasPin(hasPin);

        if (hasPin) {
          await _authService.syncLocalPinCacheAfterPasswordLogin(
            email: email,
            userData: userData,
          );
        }

        setState(() => _isLoading = false);

        if (!hasPin) {
          _showPinSetupDialog(email);
          return;
        }

        if (mounted) {
          await _maybeOfferBiometricAfterPin(email);
        }
      } else {
        setState(() => _isLoading = false);
        _showLoginFailure(result);
        if (!isBiometric) _generateCaptcha();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      final err = ErrorHandler.formatErrorForUI(e,
          context: 'login', appType: 'admin');
      _showModernSnackbar(err['message'], isSuccess: false);
      if (!isBiometric) _generateCaptcha();
    }
  }

  Future<void> _maybeOfferBiometricAfterPin(String email) async {
    if (!mounted) return;
    // ✅ SKIP biometric setup dialog during login - it interrupts the flow
    // Biometric setup will be offered from Settings screen instead
    // Mark that we've offered it so no dialogs appear
    await BiometricService.markBiometricSetupPromptShown();
    await _finishAdminLoginToHomeOrGps();
  }

  /// Run after PIN / biometric prompts: GPS route decision is not blocked by location sampling snackbar.
  Future<void> _finishAdminLoginToHomeOrGps() async {
    if (!mounted) return;
    _scheduleLocationLockFeedback();
    await _navigateBasedOnGpsStatus();
  }




  void _showPinSetupDialog(String email) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SetLoginPinAlert(
        email: email,
        authService: _authService,
        userId: _currentUserId!,
        accountPassword: _passwordController.text,
        onDone: (success, message) async {
          if (!mounted) return;
          if (success) {
            await _persistLastUserHasPin(true);
            setState(() {
              _savedEmail = email;
              _isReturningUser = true;
              _emailController.text = email;
              _pinController.clear();
            });
            _showModernSnackbar(
              'PIN set! Use PIN for next login.',
              isSuccess: true,
            );
            await _maybeOfferBiometricAfterPin(email);
          } else if (message != null && message.isNotEmpty) {
            _showModernSnackbar(message, isSuccess: false);
          }
        },
      ),
    );
  }

  void _showBiometricSetupDialog(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Icon(Icons.fingerprint, color: AppTheme.primaryBlue, size: 26),
          SizedBox(width: 10),
          Expanded(
              child: Text('Enable Biometric Login',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Enable fingerprint / face ID for one-tap login on future visits.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 14),
            FutureBuilder<List<String>>(
              future: BiometricService.getAvailableBiometricNames(),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available on this device:',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 12)),
                      const SizedBox(height: 6),
                      ...snapshot.data!.map((type) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(children: [
                              const Icon(Icons.check_circle,
                                  color: AppTheme.primaryGreen, size: 14),
                              const SizedBox(width: 6),
                              Text(type,
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                          )),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await BiometricService.markBiometricSetupPromptShown();
              if (!mounted) return;
              await _finishAdminLoginToHomeOrGps();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final names =
                  await BiometricService.getAvailableBiometricNames();
              final label =
                  names.isNotEmpty ? names.join(' / ') : 'biometric';
              final verified = await BiometricService.authenticate(
                reason: 'Use $label to enable quick login.',
                useErrorDialogs: true,
                stickyAuth: true,
                requirePreferenceEnabled: false,
              );
              if (!mounted) return;
              await BiometricService.markBiometricSetupPromptShown();
              if (!mounted) return;
              if (!verified) {
                _showModernSnackbar(
                    'Biometric setup cancelled. Enable later in settings.',
                    isSuccess: false);
                await _finishAdminLoginToHomeOrGps();
                return;
              }
              final enabled =
                  await BiometricService.enableBiometric(email);
              if (!mounted) return;
              if (enabled) {
                await _authService.cacheBiometricLogin(
                  email: email,
                  password: _passwordController.text,
                );
                if (!mounted) return;
                setState(() {
                  _showBiometricOnPinCard = _biometricSupported;
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Row(children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Biometric login enabled'),
                  ]),
                  backgroundColor: AppTheme.primaryGreen,
                ));
              }
              await _finishAdminLoginToHomeOrGps();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  void _navigateToHome() async {
    if (!mounted) return;

    // ── Stop all repeating animations BEFORE navigation ───────────────────────
    // The 600ms page-transition keeps this widget alive; without stopping,
    // the 3D-transform AnimatedBuilders keep firing and hit a RenderBox
    // "!_debugNeedsLayout" assertion (dart:ui line ~6268).
    _buttonPulseController.stop();
    _masterController.stop();

    Navigator.pushNamedAndRemoveUntil(
      context,
      MainNavigationScreen.routeName,
      (route) => false,
    );
  }

  /// Navigate to GPS settings if not configured, otherwise to home
  Future<void> _navigateBasedOnGpsStatus() async {
    if (!mounted || _currentUserId == null) return;

    try {
      final profile =
          await _geofenceService.fetchProfileForLocationGate(_currentUserId!);
      if (!mounted) return;

      final isGpsConfigured = await _geofenceService
          .hasValidPersonalGpsForCurrentAdmin(preloadedProfile: profile);
      if (!mounted) return;

      if (!isGpsConfigured) {
        // GPS not configured - redirect to GPS settings (mandatory)
        if (kDebugMode) debugPrint('🛰️ Redirecting admin to GPS configuration (mandatory)');

        _buttonPulseController.stop();
        _masterController.stop();

        Navigator.pushNamedAndRemoveUntil(
          context,
          GpsSettingsScreen.routeName,
          (route) => false,
          arguments: {'mandatory': true, 'fromLogin': true},
        );
      } else {
        final gateResult = await _geofenceService.attendanceLocationGateForCurrentUser(
          preloadedProfile: profile,
          fastFenceSampleForLogin: true,
        );
        if (!mounted) return;
        if (gateResult['allowed'] != true) {
          _buttonPulseController.stop();
          _masterController.stop();

          // Check if GPS is not configured (vs being out of radius)
          final message = gateResult['message']?.toString() ?? '';
          if (kDebugMode) {
            debugPrint('🛰️ LOGIN GPS CHECK - Message: "$message"');
            debugPrint('🛰️ Contains "GPS is not locked": ${message.contains('GPS is not locked')}');
          }

          if (message.contains('GPS is not locked')) {
            // GPS not configured - show GPS settings screen
            if (kDebugMode) debugPrint('🛰️ Navigating to GPS Settings screen');
            Navigator.pushNamedAndRemoveUntil(
              context,
              GpsSettingsScreen.routeName,
              (route) => false,
              arguments: {'mandatory': true, 'fromLogin': true},
            );
          } else {
            // Out of radius - show location gate screen
            if (kDebugMode) debugPrint('🛰️ Navigating to Location Gate screen (out of radius)');
            Navigator.pushNamedAndRemoveUntil(
              context,
              InstituteLocationGateScreen.routeName,
              (_) => false,
              arguments: {'resumeRoute': MainNavigationScreen.routeName},
            );
          }
          return;
        }
        _navigateToHome();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking GPS status: $e');
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        GpsSettingsScreen.routeName,
        (route) => false,
        arguments: {'mandatory': true, 'fromLogin': true},
      );
    }
  }

  /// Same GPS feedback as before, but does not block navigation (Geolocator can be slow).
  void _scheduleLocationLockFeedback() {
    if (!mounted || _currentUserId == null) return;
    unawaited(_checkLocationLockStatus());
  }

  Future<void> _checkLocationLockStatus() async {
    if (_currentUserId == null) return;
    try {
      final profile = await appDb
          .from('profiles')
          .select('institute_id')
          .eq('id', _currentUserId!)
          .maybeSingle();
      if (profile == null) return;
      final instituteId = profile['institute_id'] as String?;
      if (instituteId == null || instituteId.isEmpty) return;
      final locationStatus =
          await _geofenceService.checkAdminLocationStatus(
        instituteId: instituteId,
        adminId: _currentUserId!,
      );
      if (locationStatus['isLocked'] == true) {
        final isWithinRadius = locationStatus['isWithinRadius'] as bool?;
        final distance = locationStatus['distance'] as double?;
        if (isWithinRadius == false && distance != null && mounted) {
          _showModernSnackbar(
              '⚠️ Location locked – ${distance.toStringAsFixed(0)}m away.',
              isSuccess: false);
        } else if (isWithinRadius == true && mounted) {
          _showModernSnackbar('✅ Within verified location area.',
              isSuccess: true);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking location lock: $e');
    }
  }

  void _showLoginFailure(Map<String, dynamic> result) {
    final message = result['message'] as String? ?? 'Login failed';
    final openPortal = result['openAdminPortal'] == true;
    final isLocked = result['isLocked'] == true;
    final attemptsRemaining = result['attemptsRemaining'] as int?;
    final displayMessage = attemptsRemaining != null && attemptsRemaining > 0
        ? '$message\n🔐 $attemptsRemaining attempt${attemptsRemaining == 1 ? '' : 's'} remaining'
        : message;
    final portalReady = AdminPortalUrl.isConfigured;
    if (isLocked) {
      final email = _emailController.text.trim();
      if (email.isNotEmpty) {
        _securityOps.reportIncident(
          instituteId: (result['instituteId'] ?? '').toString(),
          category: 'auth_lockout',
          severity: 'high',
          title: 'Admin login lockout triggered',
          description: 'Account temporarily locked after repeated failed attempts.',
          metadata: {
            'email': email,
            'flow': _isReturningUser ? 'pin' : 'password',
          },
        );
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
          displayMessage,
          style: const TextStyle(fontSize: 13),
        )),
      ]),
      action: openPortal && portalReady
          ? SnackBarAction(
              label: 'Open Portal',
              textColor: Colors.white,
              onPressed: () async {
                final ok = await AdminPortalUrl.launch();
                if (!ok && mounted) {
                  _showModernSnackbar('Could not open admin portal',
                      isSuccess: false);
                }
              })
          : null,
      backgroundColor: AppTheme.accentRed,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      duration: Duration(seconds: openPortal ? 8 : 4),
    ));
  }

  void _showModernSnackbar(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isSuccess
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: Colors.white,
            size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
      backgroundColor:
          isSuccess ? AppTheme.primaryGreen : AppTheme.accentRed,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _showForgotPinDialog() async {
    // 🔧 Clear old PIN immediately - no dialog, no confirmation
    print('🔑 Forgot PIN clicked - clearing old PIN from database...');

    // Clear from local storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('msce_pin_session_institute_id');
    await prefs.remove('msce_pin_session_user_name');
    await prefs.remove('msce_pin_session_user_data');
    await prefs.remove('msce_pin_session_timestamp');
    await prefs.remove('msce_pin_session_gps_latitude');
    await prefs.remove('msce_pin_session_gps_longitude');
    await _persistLastUserHasPin(false);

    print('✅ Old PIN cleared from local storage');

    // Clear from database (Supabase)
    try {
      await _authService.clearPinHashFromDatabase();
      print('✅ Old PIN cleared from database');
    } catch (e) {
      print('⚠️ Error clearing PIN from database: $e');
    }

    if (mounted) {
      _showModernSnackbar(
        'PIN cleared. Sign in with password to set a new PIN.',
        isSuccess: true,
      );
    }
  }

  void _showForgotPinDialogOld() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Reset PIN?',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Your old PIN will be cleared. Sign in with Institute ID, password and CAPTCHA. Then set a new PIN.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0E27) : const Color(0xFFF0F4FF),
      body: Stack(
        children: [
          // ─── ANIMATED GRADIENT BACKGROUND ───
          _buildAnimatedGradientBackground(isDark),

          // ─── MAIN CONTENT ───
          AnimatedBuilder(
            animation: _masterController,
            builder: (context, _) {
              return Opacity(
                opacity: _screenFade.value.clamp(0.0, 1.0),
                child: Column(
                  children: [
                    // ─── HEADER (Edge-to-Edge) ───
                    _buildModernHeader(isDark),
                    // ─── CONTENT (Safe Area) ───
                    Expanded(
                      child: SafeArea(
                        top: false,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxWidth = context.contentMaxWidth(
                              mobile: 560,
                              tablet: 760,
                            );
                            return SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: EdgeInsets.fromLTRB(
                                Responsive.padding(context).horizontal,
                                16.h,
                                Responsive.padding(context).horizontal,
                                MediaQuery.viewInsetsOf(context).bottom + 16.h,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight - 16.h,
                                    maxWidth: maxWidth,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _buildModernLogoSection(context, isDark),
                                      SizedBox(height: 28.h),
                                      KeyedSubtree(
                                        key: ValueKey(
                                          _isReturningUser
                                              ? 'pin-login-card'
                                              : 'full-login-card',
                                        ),
                                        child: _isReturningUser
                                            ? _buildModernPinCard(isDark)
                                            : _buildModernFullLoginCard(isDark),
                                      ),
                                      SizedBox(height: 28.h),
                                      _buildFooter(context),
                                      SizedBox(height: 16.h),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedGradientBackground(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  const Color(0xFF0A0E27),
                  const Color(0xFF1A1F3A),
                  const Color(0xFF0F1629),
                ]
              : [
                  const Color(0xFFF0F4FF),
                  const Color(0xFFE3F2FD),
                  const Color(0xFFF3E5F5),
                ],
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.3, -0.5),
            radius: 1.2,
            colors: isDark
                ? [
                    AppTheme.primaryBlue.withOpacity(0.1),
                    Colors.transparent,
                  ]
                : [
                    AppTheme.primaryBlue.withOpacity(0.08),
                    Colors.transparent,
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernHeader(bool isDark) {
    return const GovPortalHeader();
  }

  Widget _buildModernLogoSection(BuildContext context, bool isDark) {
    final l10n = AppLocalizations.of(context);
    final viewportH = MediaQuery.sizeOf(context).height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final logoH = viewportH * 0.16;
        final logoW = (logoH * AppUI.appLogoAspectRatio)
            .clamp(0.0, constraints.maxWidth * 0.85);

        return Column(
          children: [
            // ─── ANIMATED LOGO ───
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateY(_logoFlip.value),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                  CurvedAnimation(parent: _masterController, curve: Curves.elasticOut),
                ),
                child: Center(
                  child: Container(
                    width: logoW,
                    height: logoH,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.r),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withOpacity(0.9),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.25),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                          spreadRadius: 3,
                        ),
                        BoxShadow(
                          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.1 : 0.08),
                          blurRadius: 64,
                          offset: const Offset(0, 24),
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20.r),
                      child: Padding(
                        padding: EdgeInsets.all(logoH * 0.08),
                        child: AppUI.dualBrandLogos(mainHeight: logoH * 0.68),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 18.h),
            // ─── TITLE ───
            Opacity(
              opacity: _cardFade.value.clamp(0.0, 1.0),
              child: Text(
                l10n.loginAppTitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.primaryBlue,
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            SizedBox(height: 6.h),
            // ─── SUBTITLE ───
            Opacity(
              opacity: _cardFade.value.clamp(0.0, 1.0),
              child: Text(
                l10n.loginSubtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildModernPinCard(bool isDark) {
    final initials = (_savedEmail ?? 'U')
        .split('@')
        .first
        .substring(0, 1)
        .toUpperCase();

    return _buildModernCardWrapper(
      isDark: isDark,
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── HEADER ───
              Row(
                children: [
                  Container(
                    width: 4.w,
                    height: 24.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryBlue, AppTheme.primaryGreen],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'Quick Access',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _switchToChangeUser,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        'Change',
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              // ─── AVATAR & EMAIL ───
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72.w,
                      height: 72.w,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.primaryBlue, AppTheme.primaryBlueDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withOpacity(0.4),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32.sp,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(isDark ? 0.1 : 0.05),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.25 : 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        _savedEmail ?? '',
                        style: TextStyle(
                          color: isDark ? Colors.white : AppTheme.textDark,
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
              SizedBox(height: 28.h),
              _buildGovPINField(),
              SizedBox(height: 28.h),
              _buildModernLoginButton(
                label: 'LOGIN WITH PIN',
                onTap: _handlePINLogin,
                isDark: isDark,
              ),
              SizedBox(height: 14.h),
              if (_showBiometricOnPinCard) ...[
                // Biometric button
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernFullLoginCard(bool isDark) {
    return _buildModernCardWrapper(
      isDark: isDark,
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── HEADER ───
              Row(
                children: [
                  Container(
                    width: 4.w,
                    height: 24.h,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppTheme.primaryBlue, AppTheme.accentSaffron],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'Secure Login',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.primaryBlue,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              Divider(
                color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.15),
                thickness: 1,
              ),
              SizedBox(height: 16.h),

              // ─── INFO BOX ───
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(isDark ? 0.1 : 0.06),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withOpacity(isDark ? 0.25 : 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                      color: AppTheme.primaryBlue,
                      size: 16.sp,
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        'Enter Institute ID, password and CAPTCHA',
                        style: TextStyle(
                          color: isDark ? Colors.white70 : AppTheme.primaryBlue,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 18.h),

              // ─── INSTITUTE ID FIELD ───
              if (_instituteIdFieldDisabled && _instituteIdController.text.isNotEmpty)
                _buildLockedInstituteIdDisplay()
              else
                _buildGovTextField(
                  controller: _instituteIdController,
                  icon: Icons.domain_outlined,
                  label: 'Institute ID',
                  hint: 'e.g. 00000',
                  keyboardType: TextInputType.number,
                  enabled: !_instituteIdFieldDisabled,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Institute ID is required';
                    if (!RegExp(r'^\d+$').hasMatch(value)) return 'Use numeric ID only';
                    return null;
                  },
                ),
              SizedBox(height: 14.h),

              // ─── PASSWORD FIELD ───
              _buildGovTextField(
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                label: 'Password',
                hint: '••••••••',
                isPassword: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Password is required';
                  return null;
                },
              ),
              SizedBox(height: 8.h),

              // ─── FORGOT PASSWORD ───
              Align(
                alignment: Alignment.centerRight,
                child: _buildForgotPasswordButton(),
              ),
              SizedBox(height: 18.h),

              // ─── CAPTCHA ───
              _buildCaptchaSection(),
              SizedBox(height: 24.h),

              // ─── LOGIN & SIGNUP BUTTONS ───
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final signupBtn = SizedBox(
                        height: 52.h,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const InstituteSearchScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            side: BorderSide(
                              color: AppTheme.primaryBlue,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text(
                            'SIGN UP',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      );

                      if (c.maxWidth < 400) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildModernLoginButton(
                              label: 'LOGIN',
                              onTap: _handleFullFormLogin,
                              isDark: isDark,
                            ),
                            SizedBox(height: 12.h),
                            signupBtn,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: _buildModernLoginButton(
                              label: 'LOGIN',
                              onTap: _handleFullFormLogin,
                              isDark: isDark,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(child: signupBtn),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 10.h),
                  TextButton(
                    onPressed: () {
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          settings: const RouteSettings(
                            name: AttendanceStaffLoginScreen.routeName,
                          ),
                          builder: (_) => const AttendanceStaffLoginScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Institute instructor login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedInstituteIdDisplay() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue.withOpacity(0.08),
            AppTheme.primaryBlue.withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(0.25),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(Icons.domain_outlined,
              color: AppTheme.primaryBlue,
              size: 20.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Institute ID',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  _instituteIdController.text,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryBlue,
                    letterSpacing: 1.8,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Locked after setup',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: AppTheme.textGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(999.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: Colors.white, size: 13.sp),
                SizedBox(width: 5.w),
                Text(
                  'LOCKED',
                  style: TextStyle(
                    fontSize: 10.sp,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernCardWrapper({
    required Widget child,
    required bool isDark,
  }) {
    return Opacity(
      opacity: _cardFade.value.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_cardTiltX.value),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.white.withOpacity(0.95),
                isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.white.withOpacity(0.85),
              ],
            ),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color: Colors.white.withOpacity(isDark ? 0.15 : 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.15),
                blurRadius: 40,
                offset: const Offset(0, 16),
                spreadRadius: 4,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                blurRadius: 60,
                offset: const Offset(0, 32),
                spreadRadius: 8,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20.r),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: isDark ? 15 : 10, sigmaY: isDark ? 15 : 10),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernLoginButton({
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue,
            AppTheme.primaryBlue.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(_isLoading ? 0 : 0.35),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: _isLoading
                  ? SizedBox(
                      height: 22.h,
                      width: 22.h,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── LOGO SECTION ─────────────────────────────────────────────────────────────

  Widget _buildLogoSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final viewportH = MediaQuery.sizeOf(context).height;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drive by height (18% of viewport) so the landscape logo is never squat/compressed.
        final logoH = viewportH * 0.18;
        final logoW = (logoH * AppUI.appLogoAspectRatio)
            .clamp(0.0, constraints.maxWidth * 0.88);
        return Column(
          children: [
            SizedBox(height: 8.h),
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)..rotateY(_logoFlip.value),
              child: Center(
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
                      child: AppUI.dualBrandLogos(mainHeight: logoH * 0.72),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              l10n.loginAppTitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontSize: 25.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              l10n.loginSubtitle,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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

  // ─── CARD WRAPPER ─────────────────────────────────────────────────────────────

  Widget _wrapCard(Widget child) {
    return Opacity(
      opacity: _cardFade.value.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.topCenter,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateX(_cardTiltX.value)
          // ignore: deprecated_member_use
          ..translate(0.0, _cardSlideY.value),
        child: GovElevatedCard(
          padding: EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ──  PIN SCREEN (returning user)  ─────────────────────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildIRCTCPinCard() {
    final initials = (_savedEmail ?? 'U')
        .split('@')
        .first
        .substring(0, 1)
        .toUpperCase();

    return _wrapCard(
      Padding(
        padding: EdgeInsets.all(20.w),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card header
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
                      'Quick Login  |  द्रुत लॉगिन',
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
              const Divider(color: AppTheme.dividerColor, thickness: 1),
              SizedBox(height: 20.h),

              // ── User Avatar + Email ──────────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    // Avatar circle with initial
                    Container(
                      width: 64.w, height: 64.h,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                            blurRadius: 14, offset: const Offset(0, 5))],
                      ),
                      child: Center(
                        child: Text(initials, style: TextStyle(
                            color: Colors.white, fontSize: 26.sp,
                            fontWeight: FontWeight.w800)),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    // Email display
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundGrey,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.dividerColor, width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle_outlined,
                              color: AppTheme.textGray, size: 16),
                          SizedBox(width: 6.w),
                          Expanded(
                            child: Text(
                              _savedEmail ?? '',
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
                    Text('Logged in as Admin',
                        style: TextStyle(color: AppTheme.textLightGray,
                            fontSize: 10.5.sp, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),

              SizedBox(height: 24.h),

              // ── PIN Field ────────────────────────────────────────────────────
              _buildGovPINField(),

              SizedBox(height: 24.h),

              // ── PIN Login Button ─────────────────────────────────────────────
              _build3DLoginButton(
                label: 'LOGIN WITH PIN  |  लॉगिन करा',
                onTap: _handlePINLogin,
              ),

              SizedBox(height: 14.h),

              // ── Biometric Button ─────────────────────────────────────────────
              if (_showBiometricOnPinCard) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _tryBiometricLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryBlue,
                      side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                      padding: EdgeInsets.symmetric(vertical: 14.h, horizontal: 10.w),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: FutureBuilder<List<String>>(
                      future: BiometricService.getAvailableBiometricNames(),
                      builder: (context, snapshot) {
                        final label = snapshot.hasData && snapshot.data!.isNotEmpty
                            ? 'Login with ${snapshot.data!.first}'
                            : 'Login with Biometric';
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.fingerprint, size: 22),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(
                                  label,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryBlue,
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
                SizedBox(height: 14.h),
              ],

              // ── Bottom links: Forgot PIN | Change User ───────────────────────
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  TextButton.icon(
                    onPressed: _showForgotPinDialog,
                    icon: const Icon(Icons.lock_reset_rounded,
                        size: 15, color: AppTheme.textGray),
                    label: Text('Forgot PIN?',
                        style: TextStyle(
                            color: AppTheme.textGray, fontSize: 12.sp,
                            fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ),
                  GestureDetector(
                    onTap: _switchToChangeUser,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSaffron.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.accentSaffron.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz_rounded, size: 15.sp,
                              color: AppTheme.accentSaffron),
                          SizedBox(width: 5.w),
                          Text('Change User',
                              style: TextStyle(color: AppTheme.accentSaffron,
                                  fontSize: 12.sp, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                'Change User: full login with Institute ID, password and CAPTCHA.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.sp,
                  color: AppTheme.textLightGray,
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(height: 10.h),
              _buildSecurityInfoRow(context),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════════
  // ──  FULL LOGIN FORM  (first-time / change user)  ────────────────────────────
  // ══════════════════════════════════════════════════════════════════════════════

  Widget _buildFullLoginCard() {
    return _wrapCard(
      Padding(
        padding: EdgeInsets.all(20.w),
        child: Form(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card header
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
                      'Secure Login  |  सुरक्षित लॉगिन',
                      style: TextStyle(
                        color: AppTheme.primaryBlue,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              const Divider(color: AppTheme.dividerColor, thickness: 1),

              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, color: AppTheme.primaryBlue, size: 16),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Enter Institute ID, password and CAPTCHA. Use Forgot password for OTP reset to your invite email. | पासवर्ड विसरलात? ओटीपीने रीसेट करा.',
                      style: TextStyle(color: AppTheme.primaryBlue,
                          fontSize: 11.sp, fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
              SizedBox(height: 18.h),
              if (_instituteIdFieldDisabled && _instituteIdController.text.isNotEmpty)
                // Read-only institute ID for returning users
                Container(
                  padding: EdgeInsets.all(14.w),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryBlue.withValues(alpha: 0.08),
                        AppTheme.primaryBlue.withValues(alpha: 0.03),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.domain_outlined, color: AppTheme.primaryBlue, size: 20),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Institute ID  |  संस्था आयडी',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              _instituteIdController.text,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryBlue,
                                letterSpacing: 1.8,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              'Locked after first setup. This admin signs in only for this institute.',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: AppTheme.textGray,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock, color: Colors.white, size: 13),
                            SizedBox(width: 5.w),
                            Text(
                              'LOCKED',
                              style: TextStyle(
                                fontSize: 10.sp,
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildGovTextField(
                  controller: _instituteIdController,
                  icon: Icons.domain_outlined,
                  label: 'Institute ID  |  संस्था आयडी',
                  hint: 'e.g. 00000  |  उदा. ०००००',
                  keyboardType: TextInputType.number,
                  enabled: !_instituteIdFieldDisabled,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Institute ID is required';
                    if (!RegExp(r'^\d+$').hasMatch(value)) return 'Use numeric Institute ID only';
                    return null;
                  },
                ),
              SizedBox(height: 14.h),
              _buildGovTextField(
                controller: _passwordController,
                icon: Icons.lock_outline_rounded,
                label: 'Password  |  पासवर्ड',
                hint: '••••••••',
                isPassword: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Password is required';
                  return null;
                },
              ),
              SizedBox(height: 8.h),
              Align(
                alignment: Alignment.centerRight,
                child: _buildForgotPasswordButton(),
              ),
              SizedBox(height: 18.h),
              _buildCaptchaSection(),
              SizedBox(height: 24.h),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, c) {
                      final signupBtn = SizedBox(
                        height: 52.h,
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const InstituteSearchScreen(),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primaryBlue,
                            side: const BorderSide(
                              color: AppTheme.primaryBlue,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(
                                horizontal: 6.w, vertical: 8.h),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              'SIGN UP',
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      );

                      if (c.maxWidth < 400) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _build3DLoginButton(
                              label: 'LOGIN  |  लॉगिन',
                              onTap: _handleFullFormLogin,
                            ),
                            SizedBox(height: 12.h),
                            signupBtn,
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: _build3DLoginButton(
                              label: 'LOGIN  |  लॉगिन',
                              onTap: _handleFullFormLogin,
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(child: signupBtn),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 10.h),
                  TextButton(
                    onPressed: () {
                      // Use explicit route so this always works even if named routes
                      // were not hot-restarted after main.dart changes.
                      Navigator.push<void>(
                        context,
                        MaterialPageRoute<void>(
                          settings: RouteSettings(
                            name: AttendanceStaffLoginScreen.routeName,
                          ),
                          builder: (_) => const AttendanceStaffLoginScreen(),
                        ),
                      );
                    },
                    child: Text(
                      'Institute instructor login  |  संस्था प्रशिक्षक लॉगिन',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),

              SizedBox(height: 14.h),
              _buildSecurityInfoRow(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForgotPasswordButton() {
    final until = _forgotPasswordCooldownUntil;
    final onCooldown = until != null && DateTime.now().isBefore(until);
    final label = onCooldown
        ? 'Forgot password (24h lock)'
        : 'Forgot password?  |  पासवर्ड विसरलात?';

    return TextButton(
      onPressed: (_isLoading || onCooldown) ? null : _openForgotPassword,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: onCooldown ? AppTheme.textLightGray : AppTheme.primaryBlue,
          decoration: onCooldown ? null : TextDecoration.underline,
        ),
      ),
    );
  }

  // ─── CAPTCHA WIDGET ───────────────────────────────────────────────────────────

  Widget _buildCaptchaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label: title on its own row so "Verified" never steals width (avoids tiny overflows)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.verified_user_outlined,
                    size: 14, color: AppTheme.primaryBlue),
                SizedBox(width: 6.w),
                Expanded(
                  child: Text(
                    'Verification Code  |  सत्यापन कोड',
                    style: TextStyle(
                      color: AppTheme.textGray,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_captchaVerified) ...[
              SizedBox(height: 4.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.primaryGreen, size: 14),
                  SizedBox(width: 4.w),
                  Text(
                    'Verified',
                    style: TextStyle(
                      color: AppTheme.primaryGreen,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        SizedBox(height: 8.h),

        // CAPTCHA image + refresh
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 52.h,
              child: CustomPaint(
                painter: _CaptchaPainter(
                  text: _captchaText,
                  charColors: _captchaColors,
                  charRotations: _captchaRotations,
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // Refresh button
          InkWell(
            onTap: _generateCaptcha,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.refresh_rounded,
                  color: AppTheme.primaryBlue, size: 22.sp),
            ),
          ),
        ]),
        SizedBox(height: 10.h),

        // Captcha input
        TextFormField(
          controller: _captchaController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          onChanged: (val) {
            if (val.toUpperCase() == _captchaText && !_captchaVerified) {
              setState(() => _captchaVerified = true);
            } else if (val.toUpperCase() != _captchaText && _captchaVerified) {
              setState(() => _captchaVerified = false);
            }
          },
          style: TextStyle(color: AppTheme.textDark, fontSize: 14.sp,
              fontWeight: FontWeight.w600, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: 'Type the code shown above',
            hintText: 'e.g. A7K9MX',
            hintStyle: TextStyle(fontSize: 13.sp, color: AppTheme.textLightGray,
                letterSpacing: 1),
            prefixIcon: Icon(Icons.keyboard_outlined, size: 19.sp, color: AppTheme.textGray),
            suffixIcon: _captchaVerified
                ? const Icon(Icons.check_circle, color: AppTheme.primaryGreen)
                : null,
            counterText: '',
            filled: true, fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
            contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Please enter the verification code';
            if (value.toUpperCase() != _captchaText) return 'Incorrect code — please try again';
            return null;
          },
        ),
      ],
    );
  }

  // ─── SHARED UI WIDGETS ────────────────────────────────────────────────────────

  Widget _build3DLoginButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _buttonPulseController,
      builder: (_, child) {
        return GestureDetector(
          onTapDown: (_) => setState(() => _buttonPressed = true),
          onTapUp: (_) {
            setState(() => _buttonPressed = false);
            // ✅ Set _isLoading IMMEDIATELY to prevent double-tap queueing
            if (!_isLoading) {
              setState(() => _isLoading = true);
              onTap();
            }
          },
          onTapCancel: () => setState(() => _buttonPressed = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: double.infinity,
            height: 52.h,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              // ignore: deprecated_member_use
              ..translate(0.0, _buttonPressed ? 3.0 : 0.0)
              // ignore: deprecated_member_use
              ..scale(_buttonPressed ? 0.97 : (_isLoading ? 1.0 : _buttonPulse.value)),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _buttonPressed || _isLoading
                  ? const LinearGradient(
                      colors: [AppTheme.primaryBlueDark, AppTheme.primaryBlue],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(
                      colors: [AppTheme.primaryBlueLight, AppTheme.primaryBlueDark],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(10),
              boxShadow: _buttonPressed
                  ? [BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                      blurRadius: 4, offset: const Offset(0, 1))]
                  : [
                      BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.45),
                          blurRadius: 16, offset: const Offset(0, 6), spreadRadius: 1),
                      BoxShadow(color: AppTheme.primaryBlueDark.withValues(alpha: 0.3),
                          blurRadius: 4, offset: const Offset(0, 2)),
                    ],
            ),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10.w),
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
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login_rounded, color: Colors.white, size: 20.sp),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        label,
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
    );
  }

  Widget _buildGovTextField({
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool isPassword = false,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      enabled: enabled,
      textCapitalization: keyboardType == TextInputType.emailAddress
          ? TextCapitalization.none : TextCapitalization.sentences,
      obscureText: isPassword && !_isPasswordVisible,
      style: TextStyle(color: AppTheme.textDark, fontSize: 14.sp, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19.sp, color: AppTheme.textGray),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: AppTheme.textGray, size: 19.sp),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible))
            : null,
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 2)),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        hintStyle: TextStyle(fontSize: 13.sp, color: AppTheme.textLightGray),
      ),
      validator: validator,
    );
  }

  Widget _buildGovPINField() {
    return TextFormField(
      controller: _pinController,
      keyboardType: TextInputType.number,
      maxLength: 4,
      obscureText: true,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppTheme.primaryBlue, fontSize: 22.sp,
          letterSpacing: 10, fontWeight: FontWeight.bold),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: 'Enter PIN  |  पिन टाका',
        hintText: '4 digits  |  ४ अंक',
        hintStyle: TextStyle(color: AppTheme.textLightGray, fontSize: 18.sp, letterSpacing: 8),
        prefixIcon: Icon(Icons.pin_rounded, color: AppTheme.textGray, size: 19.sp),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.dividerColor, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.accentRed, width: 2)),
        counterText: '',
        labelStyle: TextStyle(fontSize: 12.5.sp, color: AppTheme.textGray),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'PIN is required';
        if (!AuthService.isValidLoginPinLength(value)) {
          return AuthService.loginPinLengthMessage;
        }
        return null;
      },
    );
  }

  Widget _buildSecurityInfoRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10.w,
      runSpacing: 8.h,
      children: [
        _buildSecurityChip(Icons.lock_rounded, l10n.chipEncrypted, AppTheme.primaryGreen),
        _buildSecurityChip(Icons.shield_rounded, l10n.chipGovtPortal, AppTheme.primaryBlue),
        _buildSecurityChip(Icons.verified_user_rounded, l10n.chipSecure, AppTheme.accentSaffron),
      ],
    );
  }

  Widget _buildSecurityChip(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12.sp, color: color),
      SizedBox(width: 3.w),
      Text(label, style: TextStyle(fontSize: 10.5.sp, color: AppTheme.textGray,
          fontWeight: FontWeight.w500)),
    ]);
  }

  // ─── FOOTER ───────────────────────────────────────────────────────────────────

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeSvc = context.watch<LocaleService>();
    return Column(
      children: [
        Row(children: [
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(l10n.footerOfficialUse,
                style: TextStyle(fontSize: 10.sp, color: AppTheme.textLightGray,
                    fontWeight: FontWeight.w600, letterSpacing: 1.2)),
          ),
          const Expanded(child: Divider(color: AppTheme.dividerColor)),
        ]),
        SizedBox(height: 10.h),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4.w,
          runSpacing: 4.h,
          children: [
            Text(
              l10n.languageToggleHint,
              style: TextStyle(fontSize: 10.sp, color: AppTheme.textGray, fontWeight: FontWeight.w600),
            ),
            TextButton(
              onPressed: () => localeSvc.setLocale(const Locale('en')),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.languageEnglish,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: localeSvc.locale.languageCode == 'en' ? AppTheme.primaryBlue : AppTheme.textGray,
                  decoration: localeSvc.locale.languageCode == 'en' ? TextDecoration.underline : null,
                ),
              ),
            ),
            Text('|', style: TextStyle(fontSize: 11.sp, color: AppTheme.textLightGray)),
            TextButton(
              onPressed: () => localeSvc.setLocale(const Locale('mr')),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.languageMarathi,
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w800,
                  color: localeSvc.locale.languageCode == 'mr' ? AppTheme.primaryBlue : AppTheme.textGray,
                  decoration: localeSvc.locale.languageCode == 'mr' ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        Text(
          'Maharashtra State Council of Examination | महाराष्ट्र राज्य परीक्षा परिषद',
          style: TextStyle(
            fontSize: 10.5.sp,
            color: AppTheme.textGray,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4.h),
        Text(l10n.loginCopyright('${DateTime.now().year}'),
            style: TextStyle(fontSize: 10.sp, color: AppTheme.textLightGray,
                fontWeight: FontWeight.w400),
            textAlign: TextAlign.center),
        SizedBox(height: 8.h),
        Center(child: SupportEmailFooter()),
        SizedBox(height: 10.h),
        Row(children: [
          Expanded(child: Container(height: 3, decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFFFF6600), Color(0xFFFF9933)])))),
          Expanded(child: Container(height: 3, color: Colors.white70)),
          Expanded(child: Container(height: 3, decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF006600), Color(0xFF138808)])))),
        ]),
      ],
    );
  }
}

/// PIN setup after password login — shows strength and blocks very weak PINs.
class _SetLoginPinAlert extends StatefulWidget {
  const _SetLoginPinAlert({
    required this.email,
    required this.authService,
    required this.userId,
    required this.accountPassword,
    required this.onDone,
  });

  final String email;
  final AuthService authService;
  final String userId;
  final String accountPassword;
  final Future<void> Function(bool success, String? message) onDone;

  @override
  State<_SetLoginPinAlert> createState() => _SetLoginPinAlertState();
}

class _SetLoginPinAlertState extends State<_SetLoginPinAlert> {
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pinCtrl.addListener(() => setState(() {}));
    _confirmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinCtrl.text;
    final confirmPin = _confirmCtrl.text;
    if (!AuthService.isValidLoginPinLength(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AuthService.loginPinLengthMessage)),
      );
      return;
    }
    final pa = CredentialStrengthAnalysis.analyzePinFour(pin);
    if (pa.level == CredentialStrengthLevel.weak) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pa.hint ?? 'Choose a stronger PIN (avoid 1234, repeating digits, etc.)',
          ),
        ),
      );
      return;
    }
    if (pin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PINs do not match')),
      );
      return;
    }

    setState(() => _submitting = true);
    final result = await widget.authService.setPINWithPassword(
      userId: widget.userId,
      pin: pin,
      password: widget.accountPassword,
      email: widget.email,
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    final ok = result['success'] == true;
    final msg = result['message']?.toString();
    Navigator.of(context).pop();
    await widget.onDone(ok, msg);
  }

  @override
  Widget build(BuildContext context) {
    final pinAnalysis = CredentialStrengthAnalysis.analyzePinFour(_pinCtrl.text);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_rounded, color: AppTheme.primaryBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Set Login PIN',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Required: exactly 4 digits. Avoid simple patterns (1234, 1111, etc.).',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppTheme.textGray),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          TextField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Enter PIN (4 digits)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
            ),
          ),
          CredentialStrengthIndicator(analysis: pinAnalysis, dense: true, forPin: true),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Confirm PIN',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: _submitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Set PIN'),
        ),
      ],
    );
  }
}
