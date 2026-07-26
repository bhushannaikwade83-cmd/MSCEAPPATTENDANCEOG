import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/app_db.dart';
import '../../core/theme/app_theme.dart';
import '../../services/pin_session_manager.dart';
import 'main_navigation_screen.dart';

class PinSetupScreen extends StatefulWidget {
  static const routeName = '/pin-setup';
  final bool fromLogin;
  final bool isMandatory;

  const PinSetupScreen({
    super.key,
    this.fromLogin = false,
    this.isMandatory = false,
  });

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  User? get _currentUser => appDb.auth.currentUser;

  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';
  String _step = 'enter'; // 'enter' or 'confirm'
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
    // Only allow digits and max 4 characters
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

    // Auto-proceed when 4 digits entered
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

      // Save PIN to database
      if (_instituteId != null) {
        await appDb.from('admin_pin_settings').upsert({
          'institute_id': _instituteId,
          'admin_id': cu.id,
          'pin_hash': _hashPin(pin), // Store hashed PIN for security
          'pin_set_at': DateTime.now().toUtc().toIso8601String(),
          'is_active': true,
        });
      }

      // Save PIN to local session for biometric integration
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

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text("4-Digit PIN Set Successfully!"),
            ],
          ),
          backgroundColor: AppTheme.accentGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // Delay slightly to show success message
      await Future.delayed(const Duration(milliseconds: 600));

      if (mounted && widget.fromLogin && widget.isMandatory) {
        if (kDebugMode) debugPrint('✅ PIN setup complete. Navigating to home...');
        Navigator.pushNamedAndRemoveUntil(
          context,
          MainNavigationScreen.routeName,
          (route) => false,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error saving PIN: $e');
      if (!mounted) return;

      setState(() => _errorMessage = 'Failed to save PIN: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: AppTheme.accentRed,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _hashPin(String pin) {
    // Simple hash for demo - in production use bcrypt or similar
    // This is just to avoid storing PIN in plaintext
    return 'pin_${pin.hashCode}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back navigation during PIN setup
      child: Scaffold(
        backgroundColor: AppTheme.backgroundGrey,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // Title
                Text(
                  _step == 'enter'
                      ? 'Create Your 4-Digit PIN'
                      : 'Confirm Your PIN',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  _step == 'enter'
                      ? 'You\'ll use this PIN with biometric for every login'
                      : 'Re-enter your PIN to confirm',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.textGray,
                      ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 40),

                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _step == 'enter'
                              ? 'Choose any 4 digits (e.g., 1234). Keep it secure but easy to remember.'
                              : 'Make sure both PINs match exactly.',
                          style: TextStyle(
                            color: Colors.blue.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // PIN Input Field
                TextField(
                  controller: _step == 'enter' ? _pinController : _confirmPinController,
                  obscureText: !_showPin,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: _onPinInput,
                  decoration: InputDecoration(
                    labelText: _step == 'enter' ? 'Enter PIN' : 'Confirm PIN',
                    prefixIcon: const Icon(Icons.lock, color: AppTheme.primaryBlue),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPin ? Icons.visibility : Icons.visibility_off,
                        color: AppTheme.primaryBlue,
                      ),
                      onPressed: () => setState(() => _showPin = !_showPin),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    counterText: '',
                    helperText: 'Digits only (4 required)',
                    helperStyle: const TextStyle(color: AppTheme.textGray),
                  ),
                  style: const TextStyle(fontSize: 32, letterSpacing: 8),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 12),

                // Error Message
                if (_errorMessage.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRed.withOpacity(0.1),
                      border: Border.all(color: AppTheme.accentRed),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: AppTheme.accentRed,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 40),

                // Action Buttons
                if (_step == 'enter')
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed:
                              _pinController.text.length == 4 ? _proceedToConfirm : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Next',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : (_confirmPinController.text.length == 4
                                  ? _validateAndSavePin
                                  : null),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Save PIN',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _step = 'enter';
                            _pinController.clear();
                            _confirmPinController.clear();
                            _enteredPin = null;
                            _errorMessage = '';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primaryBlue),
                          foregroundColor: AppTheme.primaryBlue,
                        ),
                        child: const Text('Change PIN'),
                      ),
                    ],
                  ),

                const SizedBox(height: 24),

                // Security Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.lock_outline, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Security Tips',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• Avoid obvious numbers like 0000, 1111, 1234\n'
                        '• Don\'t use your birth year or phone digits\n'
                        '• Use this PIN for biometric login only',
                        style: TextStyle(
                          color: Colors.amber.withOpacity(0.8),
                          fontSize: 12,
                          height: 1.5,
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
  }
}
