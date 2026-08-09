import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/app_db.dart';
import '../../core/root_navigator.dart';
import '../../core/theme/app_theme.dart';
import '../../services/session_manager.dart';
import '../../services/biometric_service.dart';
import 'main_navigation_screen.dart';
import 'login_screen.dart';

class BiometricLockScreenModern extends StatefulWidget {
  static const routeName = '/biometric-lock';
  const BiometricLockScreenModern({super.key});

  @override
  State<BiometricLockScreenModern> createState() =>
      _BiometricLockScreenModernState();
}

class _BiometricLockScreenModernState extends State<BiometricLockScreenModern>
    with WidgetsBindingObserver {
  static const String _kPrefLastEmail = 'msce_last_login_email';
  static const String _kPrefLastUserHasPin = 'msce_last_user_has_pin';

  final TextEditingController _pinController = TextEditingController();

  bool _isLoading = false;
  bool _biometricSupported = false;
  bool _canUseBiometric = false;
  String? _userEmail;
  String _errorMessage = '';
  bool _isForgotPinBusy = false;
  bool _showPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_kPrefLastEmail)?.trim();

      if (email != null && email.isNotEmpty) {
        _userEmail = email;
        await _syncBiometricUi();
      } else {
        if (mounted) {
          Navigator.pushReplacementNamed(context, LoginScreen.routeName);
        }
      }
    } catch (e) {
      print('Error initializing: $e');
    }
  }

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

      if (can) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _triggerBiometric();
        }
      }
    } catch (e) {
      print('Error syncing biometric: $e');
    }
  }

  Future<void> _triggerBiometric() async {
    try {
      final authenticated = await BiometricService.authenticate();
      if (authenticated && mounted) {
        _unlockApp();
      }
    } catch (e) {
      print('Biometric error: $e');
    }
  }

  Future<void> _validatePin() async {
    final pin = _pinController.text.trim();

    if (pin.length != 4) {
      setState(() => _errorMessage = 'PIN must be 4 digits');
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPin = prefs.getString('msce_admin_pin');

      // Simple PIN validation (in production, use proper hash comparison)
      final isValid = savedPin == pin;

      if (!mounted) return;

      if (isValid) {
        _unlockApp();
      } else {
        setState(() {
          _errorMessage = '❌ Invalid PIN. Try again.';
          _pinController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _unlockApp() {
    SessionManager.extendSession();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        MainNavigationScreen.routeName,
        (route) => false,
      );
    }
  }

  void _onPinInput(String value) {
    if (value.length > 4) {
      _pinController.text = value.substring(0, 4);
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    if (value.length == 4) {
      _validatePin();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlue.withOpacity(0.7),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),

                        // Welcome Icon
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock_open_outlined,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Welcome Text
                        Text(
                          'Welcome Back',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28.sp,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 8),

                        // User Email
                        Text(
                          _userEmail ?? 'user@example.com',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14.sp,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 48),

                        // Biometric Button
                        if (_biometricSupported && _canUseBiometric)
                          Column(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.3),
                                    width: 2,
                                  ),
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _triggerBiometric,
                                    customBorder: const CircleBorder(),
                                    child: const Icon(
                                      Icons.fingerprint,
                                      color: Colors.white,
                                      size: 50,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tap to unlock with biometric',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12.sp,
                                ),
                              ),
                              const SizedBox(height: 40),
                              Text(
                                'Or enter your PIN',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 12.sp,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          )
                        else
                          Column(
                            children: [
                              const SizedBox(height: 20),
                              Text(
                                'Enter Your PIN',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14.sp,
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),

                        // PIN Display Dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            4,
                            (index) => AnimatedScale(
                              scale: index < _pinController.text.length
                                  ? 1.1
                                  : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                width: 14,
                                height: 14,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                decoration: BoxDecoration(
                                  color: index < _pinController.text.length
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.3),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 36),

                        // PIN Input Field
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _pinController,
                            obscureText: !_showPin,
                            keyboardType: TextInputType.number,
                            maxLength: 4,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            onChanged: _onPinInput,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 16,
                              color: AppTheme.primaryBlue,
                            ),
                            decoration: InputDecoration(
                              hintText: '••••',
                              hintStyle: TextStyle(
                                color: Colors.grey.withOpacity(0.2),
                                fontSize: 36,
                                letterSpacing: 16,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(20),
                              counterText: '',
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: IconButton(
                                  icon: Icon(
                                    _showPin
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: AppTheme.primaryBlue
                                        .withOpacity(0.6),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _showPin = !_showPin),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Error Message
                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.5),
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red.withOpacity(0.8),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _errorMessage,
                                      style: TextStyle(
                                        color: Colors.red.withOpacity(0.8),
                                        fontSize: 12.sp,
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
                ),

                // Logout Button
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 24,
                  ),
                  child: TextButton(
                    onPressed: () {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        LoginScreen.routeName,
                        (route) => false,
                      );
                    },
                    child: const Text(
                      '🚪 Switch Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
