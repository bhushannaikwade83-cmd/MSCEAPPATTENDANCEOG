import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../services/pin_session_manager.dart';
import 'main_navigation_screen.dart';

class PinSetupScreenModern extends StatefulWidget {
  static const routeName = '/pin-setup';
  final bool fromLogin;
  final bool isMandatory;

  const PinSetupScreenModern({
    super.key,
    this.fromLogin = false,
    this.isMandatory = false,
  });

  @override
  State<PinSetupScreenModern> createState() => _PinSetupScreenModernState();
}

class _PinSetupScreenModernState extends State<PinSetupScreenModern> {
  User? get _currentUser => appDb.auth.currentUser;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';
  String _step = 'enter';
  String? _enteredPin;
  bool _showPin = false;
  String? _instituteId;

  @override
  void initState() {
    super.initState();
    _loadUserInstituteId();
    if (kDebugMode) {
      debugPrint('🔐 PIN Setup Screen: fromLogin=${widget.fromLogin}, isMandatory=${widget.isMandatory}');
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInstituteId() async {
    final u = _currentUser;
    if (u == null) {
      setState(() => _instituteId = null);
      return;
    }
    try {
      final row = await appDb
          .from('profiles')
          .select('institute_id')
          .eq('id', u.id)
          .maybeSingle();
      if (!mounted) return;
      if (row != null) {
        setState(() {
          _instituteId = row['institute_id'] as String?;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading institute ID: $e');
    }
  }

  void _onPinInput(String value) {
    if (value.length > 4) {
      if (_step == 'enter') {
        _pinController.text = value.substring(0, 4);
      } else {
        _confirmPinController.text = value.substring(0, 4);
      }
      return;
    }
    setState(() {
      _errorMessage = '';
    });
    if (value.length == 4) {
      if (_step == 'enter') {
        _proceedToConfirm();
      } else {
        _validateAndSavePin();
      }
    }
  }

  void _proceedToConfirm() {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      setState(() => _errorMessage = 'PIN must be 4 digits');
      return;
    }
    setState(() {
      _enteredPin = pin;
      _step = 'confirm';
      _confirmPinController.clear();
      _errorMessage = '';
    });
  }

  Future<void> _validateAndSavePin() async {
    final confirmPin = _confirmPinController.text.trim();
    if (confirmPin.length != 4) {
      setState(() => _errorMessage = 'PIN must be 4 digits');
      return;
    }
    if (_enteredPin != confirmPin) {
      setState(() => _errorMessage = 'PINs do not match. Try again.');
      _confirmPinController.clear();
      return;
    }
    await _savePin(_enteredPin!);
  }

  Future<void> _savePin(String pin) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final cu = _currentUser;
      if (cu == null) throw 'User not authenticated';
      if (_instituteId != null) {
        await appDb.from('admin_pin_settings').upsert({
          'institute_id': _instituteId,
          'admin_id': cu.id,
          'pin_hash': _hashPin(pin),
          'pin_set_at': DateTime.now().toUtc().toIso8601String(),
          'is_active': true,
        });
      }
      final userData = await appDb
          .from('profiles')
          .select()
          .eq('id', cu.id)
          .maybeSingle();
      if (userData != null && _instituteId != null) {
        await PinSessionManager.savePinSession(
          instituteId: _instituteId!,
          userName: cu.email ?? '',
          userData: userData,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text("✅ PIN Set Successfully!"),
            ],
          ),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted && widget.fromLogin && widget.isMandatory) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          MainNavigationScreen.routeName,
          (route) => false,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving PIN: $e');
      if (mounted) {
        setState(() => _errorMessage = 'Failed to save PIN. Try again.');
        setState(() => _isLoading = false);
      }
    }
  }

  String _hashPin(String pin) {
    return 'pin_${pin.hashCode}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentPin = _step == 'enter' ? _pinController.text : _confirmPinController.text;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryBlue,
                AppTheme.primaryBlue.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back button
                  if (_step == 'confirm')
                    Align(
                      alignment: Alignment.topLeft,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _step = 'enter';
                            _pinController.clear();
                            _confirmPinController.clear();
                            _enteredPin = null;
                            _errorMessage = '';
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),

                  // Lock Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  Text(
                    _step == 'enter'
                        ? 'Create Your PIN'
                        : 'Confirm Your PIN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 12),

                  // Subtitle
                  Text(
                    _step == 'enter'
                        ? 'Set a 4-digit PIN for secure access'
                        : 'Re-enter PIN to confirm',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  // PIN Display Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (index) => AnimatedScale(
                        scale: index < currentPin.length ? 1.2 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: index < currentPin.length
                                ? Colors.white
                                : Colors.white.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // PIN Input
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _step == 'enter'
                          ? _pinController
                          : _confirmPinController,
                      obscureText: !_showPin,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                          color: Colors.grey.withOpacity(0.3),
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
                              color: AppTheme.primaryBlue.withOpacity(0.6),
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _showPin = !_showPin),
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
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 48),

                  // Action Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : (currentPin.length == 4
                              ? (_step == 'enter'
                                  ? _proceedToConfirm
                                  : _validateAndSavePin)
                              : null),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 8,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppTheme.primaryBlue,
                                ),
                              ),
                            )
                          : Text(
                              _step == 'enter' ? '→ Next' : '✓ Save PIN',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Security Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.shield, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Security Tips',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '• Avoid patterns: 0000, 1111, 1234\n'
                          '• Don\'t use birthdays or simple sequences\n'
                          '• Keep your PIN confidential',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            height: 1.6,
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
      ),
    );
  }
}
