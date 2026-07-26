import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/credential_strength.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/validation_service.dart';
import '../widgets/credential_strength_indicator.dart';
import '../widgets/support_email_footer.dart';

/// Admin forgot password: prefilled institute + invite email → OTP → new password.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.initialInstituteId,
    this.initialEmail,
  });

  static const routeName = '/forgot-password';

  final String initialInstituteId;
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _auth = AuthService();
  final _instituteCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _otpSent = false;
  bool _passwordVisible = false;
  bool _confirmVisible = false;
  String? _maskedEmail;

  @override
  void initState() {
    super.initState();
    _instituteCtrl.text = widget.initialInstituteId.trim();
    final seed = widget.initialEmail?.trim() ?? '';
    if (seed.isNotEmpty) {
      _emailCtrl.text = seed;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEmail());
    }
  }

  @override
  void dispose() {
    _instituteCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    final id = _instituteCtrl.text.trim();
    if (id.isEmpty) return;
    setState(() => _loading = true);
    final email = await _auth.getAdminResetEmailForInstitute(id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (email != null && email.isNotEmpty) {
        _emailCtrl.text = email;
      }
    });
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppTheme.accentRed : AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendOtp() async {
    final instituteId = _instituteCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (instituteId.isEmpty) {
      _snack('Institute ID is required', error: true);
      return;
    }
    if (email.isEmpty) {
      _snack('Admin email is required', error: true);
      return;
    }

    setState(() => _loading = true);
    final result = await _auth.sendAdminForgotPasswordOtp(
      instituteKey: instituteId,
      email: email,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _otpSent = result['success'] == true;
      _maskedEmail = result['maskedEmail']?.toString();
    });

    if (result['success'] == true) {
      _snack(result['message']?.toString() ?? 'OTP sent');
    } else {
      _snack(result['message']?.toString() ?? 'Could not send OTP', error: true);
    }
  }

  Future<void> _resetPassword() async {
    final instituteId = _instituteCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final otp = _otpCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (!_otpSent) {
      _snack('Send OTP to your email first', error: true);
      return;
    }
    if (otp.length != 6) {
      _snack('Enter the 6-digit OTP from your email', error: true);
      return;
    }
    final pwdErr =
        ValidationService.validatePassword(password, isRegistration: true);
    if (pwdErr != null) {
      _snack(pwdErr, error: true);
      return;
    }
    if (password != confirm) {
      _snack('Passwords do not match', error: true);
      return;
    }

    setState(() => _loading = true);
    final result = await _auth.resetAdminPasswordAfterOtp(
      instituteKey: instituteId,
      email: email,
      otp: otp,
      newPassword: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      _snack(
        '${result['message'] ?? 'Password updated.'} Forgot password is disabled for 24 hours.',
      );
      Navigator.pop(context, true);
    } else {
      _snack(result['message']?.toString() ?? 'Reset failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final instituteLocked = widget.initialInstituteId.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  'OTP is sent to the same email used when your institute admin was invited. '
                  'After reset, this option stays disabled for 24 hours.',
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              _field(
                controller: _instituteCtrl,
                label: 'Institute ID',
                icon: Icons.domain_outlined,
                readOnly: instituteLocked,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: 14.h),
              _field(
                controller: _emailCtrl,
                label: 'Admin email (from invite)',
                icon: Icons.email_outlined,
                readOnly: true,
              ),
              if (_maskedEmail != null) ...[
                SizedBox(height: 6.h),
                Text(
                  'Sent to: $_maskedEmail',
                  style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
                ),
              ],
              SizedBox(height: 18.h),
              SizedBox(
                height: 48.h,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _sendOtp,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: Text(_otpSent ? 'Resend OTP' : 'Send OTP to email'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryBlue,
                    side: const BorderSide(color: AppTheme.primaryBlue),
                  ),
                ),
              ),
              SizedBox(height: 18.h),
              _field(
                controller: _otpCtrl,
                label: '6-digit OTP',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              SizedBox(height: 14.h),
              _field(
                controller: _passwordCtrl,
                label: 'New password',
                icon: Icons.lock_outline,
                isPassword: true,
                visible: _passwordVisible,
                onToggleVisibility: () =>
                    setState(() => _passwordVisible = !_passwordVisible),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _passwordCtrl,
                builder: (_, value, _) => Padding(
                  padding: EdgeInsets.only(top: 6.h, left: 4.w),
                  child: CredentialStrengthIndicator(
                    analysis: CredentialStrengthAnalysis.analyzePassword(
                      value.text,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 14.h),
              _field(
                controller: _confirmCtrl,
                label: 'Confirm new password',
                icon: Icons.lock_outline,
                isPassword: true,
                visible: _confirmVisible,
                onToggleVisibility: () =>
                    setState(() => _confirmVisible = !_confirmVisible),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                height: 52.h,
                child: ElevatedButton(
                  onPressed: _loading ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Set new password',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 24.h),
              const SupportEmailFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    TextInputType? keyboardType,
    int? maxLength,
    bool isPassword = false,
    bool visible = true,
    VoidCallback? onToggleVisibility,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      maxLength: maxLength,
      obscureText: isPassword && !visible,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryBlue, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  visible ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textGray,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        filled: true,
        fillColor: readOnly ? AppTheme.backgroundGrey : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
        ),
      ),
    );
  }
}
