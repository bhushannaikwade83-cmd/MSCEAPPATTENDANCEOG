import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/error_handler.dart';
import '../../services/validation_service.dart';
import '../../core/credential_strength.dart';
import '../../core/support_contact_instructions.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/credential_strength_indicator.dart';
import '../../core/institute_id_display.dart';
import 'login_screen.dart';

/// After selecting an institute from search: shows details prefilled from [admin_invites]
/// (submitted on website), then email OTP → verify → password (8+ chars) → [claimAdminInvite].
class InstituteRegistrationScreen extends StatefulWidget {
  final String instituteId;
  final String instituteName;
  final String instituteLocation;

  /// From `admin_invites` when the institute admin registered on the website.
  final String? inviteId;
  final String? prefilledFullName;
  final String? prefilledEmail;
  final String? prefilledPhone;

  const InstituteRegistrationScreen({
    super.key,
    required this.instituteId,
    required this.instituteName,
    required this.instituteLocation,
    this.inviteId,
    this.prefilledFullName,
    this.prefilledEmail,
    this.prefilledPhone,
  });

  static const routeName = '/institute-registration';

  @override
  State<InstituteRegistrationScreen> createState() =>
      _InstituteRegistrationScreenState();
}

class _InstituteRegistrationScreenState extends State<InstituteRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final GlobalKey _passwordSectionKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isPasswordVisible = false;
  bool _isLoading = false;

  bool _inviteEmailOtpSent = false;
  bool _inviteEmailOtpVerified = false;

  /// Loaded when there is no unclaimed invite row (anon RLS hides claimed invites).
  bool _checkingPublicSetupStatus = false;
  bool _setupAlreadyComplete = false;
  bool _inviteAlreadyConsumed = false;
  String _registeredAdminDisplayName = 'Registered administrator';

  @override
  void initState() {
    super.initState();
    if (!_hasWebsiteInvite) {
      _checkingPublicSetupStatus = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPublicSetupStatus());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _hasWebsiteInvite {
    final id = widget.inviteId?.trim() ?? '';
    final em = widget.prefilledEmail?.trim() ?? '';
    return id.isNotEmpty && em.isNotEmpty;
  }

  Future<void> _loadPublicSetupStatus() async {
    try {
      final r = await _authService.instituteAdminSetupPublicStatus(widget.instituteId);
      if (!mounted) return;
      setState(() {
        _checkingPublicSetupStatus = false;
        if (r['success'] == true) {
          _setupAlreadyComplete = r['setup_complete'] == true;
          _inviteAlreadyConsumed = r['invite_claimed'] == true;
          final n = r['registered_admin_name']?.toString().trim() ?? '';
          _registeredAdminDisplayName =
              n.isNotEmpty ? n : 'Registered administrator';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingPublicSetupStatus = false);
    }
  }

  Future<void> _goToLoginScreen() async {
    // ✅ Save institute ID for next login
    await _saveInstituteIdForLogin(widget.instituteId);

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      LoginScreen.routeName,
      arguments: {
        'forceFullLogin': true,
        'instituteId': widget.instituteId,
      },
    );
  }

  Future<void> _saveInstituteIdForLogin(String instituteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('msce_last_institute_id', instituteId.trim());
      if (kDebugMode) {
        debugPrint('💾 Saved institute ID for next login: $instituteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to save institute ID: $e');
      }
    }
  }

  Future<void> _sendInviteEmailOtp() async {
    final email = widget.prefilledEmail!.trim();
    setState(() => _isLoading = true);
    try {
      final result = await _authService.sendInviteSignupEmailOTP(email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (result['success'] == true) {
          _inviteEmailOtpSent = true;
        }
      });

      if (result['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']?.toString() ?? 'OTP sent to $email'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
      } else {
        _showError(result['message']?.toString() ?? 'Could not send OTP');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Error sending OTP: $e');
    }
  }

  Future<void> _verifyInviteEmailOtp() async {
    if (_inviteEmailOtpVerified || _isLoading) return;
    final email = widget.prefilledEmail!.trim();
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showError('Enter the 6-digit OTP');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.verifyInviteSignupEmailOTP(email, otp);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        setState(() => _inviteEmailOtpVerified = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP verified. Set a strong password (see strength meter).'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = _passwordSectionKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.08,
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutCubic,
            );
          }
        });
      } else {
        _showError(result['message']?.toString() ?? 'Invalid OTP');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('OTP verification failed: $e');
    }
  }

  Future<void> _completeInviteRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    final password = _passwordController.text;
    setState(() => _isLoading = true);

    try {
      final result = await _authService.claimAdminInvite(
        inviteId: widget.inviteId!,
        instituteId: widget.instituteId,
        email: widget.prefilledEmail!.trim(),
        password: password,
        fullName: widget.prefilledFullName,
        phone: widget.prefilledPhone,
        instituteName: widget.instituteName,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account ready. Sign in with Institute ID and password.'),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
        _goToLoginScreen();
      } else {
        _showError(result['message']?.toString() ?? 'Registration failed');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final err =
          ErrorHandler.formatErrorForUI(e, context: 'instituteRegistration', appType: 'admin');
      _showError(err['message'] ?? e.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildPrefilledTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textGray),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textGray,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? '—' : value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textDark,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebsiteInviteFlow(bool isDark) {
    final phone = widget.prefilledPhone?.trim() ?? '';
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final phoneDisplay =
        digits.length == 10 ? '+91 $digits' : (phone.isEmpty ? '—' : phone);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Details from website',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppTheme.textDark,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'These match what you submitted online. OTP is sent to the email below.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark ? Colors.white70 : AppTheme.textGray,
                height: 1.35,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.amber.shade800),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kInstituteSupportContactInstructions,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white70 : AppTheme.textDark,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPrefilledTile(
                'Institute ID',
                formatInstituteIdForDisplay(widget.instituteId),
                Icons.tag,
              ),
              _buildPrefilledTile(
                'Institute',
                widget.instituteName,
                Icons.school_outlined,
              ),
              _buildPrefilledTile(
                'Admin full name',
                widget.prefilledFullName?.trim() ?? '',
                Icons.person_outline,
              ),
              _buildPrefilledTile(
                'Email (for OTP)',
                widget.prefilledEmail!.trim(),
                Icons.email_outlined,
              ),
              _buildPrefilledTile(
                'Mobile',
                phoneDisplay,
                Icons.phone_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        if (!_inviteEmailOtpSent) ...[
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _sendInviteEmailOtp,
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mark_email_unread_outlined),
            label: const Text('Send OTP to email'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppTheme.primaryGreen, width: 2),
            ),
          ),
        ],

        if (_inviteEmailOtpSent && !_inviteEmailOtpVerified) ...[
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              letterSpacing: 8,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Enter OTP',
              prefixIcon: Icon(
                Icons.verified_user,
                color: isDark ? Colors.white70 : AppTheme.textGray,
              ),
              counterText: '',
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : AppTheme.dividerColor,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryGreen, width: 2),
              ),
              labelStyle: TextStyle(color: isDark ? Colors.white70 : AppTheme.textGray),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Enter OTP';
              if (value.length != 6) return '6 digits required';
              return null;
            },
            onChanged: (v) {
              if (v.length == 6 && !_isLoading) {
                _verifyInviteEmailOtp();
              }
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _verifyInviteEmailOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
              ),
              child: const Text('Verify OTP'),
            ),
          ),
          TextButton(
            onPressed: _isLoading ? null : _sendInviteEmailOtp,
            child: Text(
              'Resend OTP',
              style: TextStyle(
                color: isDark ? Colors.lightGreenAccent.shade100 : AppTheme.primaryGreen,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],

        if (_inviteEmailOtpVerified) ...[
          KeyedSubtree(
            key: _passwordSectionKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          TextFormField(
            controller: _passwordController,
            obscureText: !_isPasswordVisible,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: isDark ? Colors.white : AppTheme.textDark),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(
                Icons.lock_outlined,
                color: isDark ? Colors.white70 : AppTheme.textGray,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                ),
                onPressed: () {
                  setState(() => _isPasswordVisible = !_isPasswordVisible);
                },
              ),
              helperText:
                  'Strong password: 8+ chars with upper & lower case, a number, and a symbol (!@#\$%^&*).',
              helperStyle: TextStyle(color: isDark ? Colors.white54 : AppTheme.textGray),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : AppTheme.dividerColor,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
              labelStyle: TextStyle(color: isDark ? Colors.white70 : AppTheme.textGray),
            ),
            validator: (value) =>
                ValidationService.validatePassword(value, isRegistration: true),
          ),
          CredentialStrengthIndicator(
            analysis: CredentialStrengthAnalysis.analyzePassword(_passwordController.text),
            dense: true,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: !_isPasswordVisible,
            style: TextStyle(color: isDark ? Colors.white : AppTheme.textDark),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(
                Icons.lock_outline,
                color: isDark ? Colors.white70 : AppTheme.textGray,
              ),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? Colors.white24 : AppTheme.dividerColor,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
              ),
              labelStyle: TextStyle(color: isDark ? Colors.white70 : AppTheme.textGray),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: DecoratedBox(
              decoration: AppTheme.primaryGradientDecoration,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _completeInviteRegistration,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        'Complete registration',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAdminAlreadyRegisteredMessage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.verified_rounded, size: 64, color: AppTheme.primaryGreen.withValues(alpha: 0.9)),
          const SizedBox(height: 16),
          Text(
            'Admin registration already done',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Institute admin setup is complete. It is registered under '
            '$_registeredAdminDisplayName. '
            'There is no pending OTP signup for this institute.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _goToLoginScreen,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Sign in with Institute ID'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteConsumedButNoActiveAdminMessage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.info_outline_rounded, size: 56, color: Colors.amber.shade700),
          const SizedBox(height: 16),
          Text(
            'Invite already used',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'The website invite for this institute has already been submitted. '
            'If you finished OTP and password on this app, sign in below. '
            'If something failed or you need help, contact support.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: _goToLoginScreen,
              child: const Text('Go to sign in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoInviteMessage(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No admins found contact administrators',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your institute does not have any admin details registered yet. '
            'Please contact the system administrators or institute management to proceed with setup.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white70 : AppTheme.textGray,
                  height: 1.4,
                ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundOffWhite,
      appBar: AppBar(
        title: const Text('Complete signup'),
        centerTitle: true,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryGreen.withValues(alpha: 0.1),
                        AppTheme.accentMint.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: AppTheme.primaryGreen,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.instituteName,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppTheme.textDark,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: isDark ? Colors.white70 : AppTheme.textGray,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.instituteLocation,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: isDark ? Colors.white70 : AppTheme.textGray,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_hasWebsiteInvite)
                  _buildWebsiteInviteFlow(isDark)
                else if (_checkingPublicSetupStatus)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_setupAlreadyComplete)
                  _buildAdminAlreadyRegisteredMessage(isDark)
                else if (_inviteAlreadyConsumed)
                  _buildInviteConsumedButNoActiveAdminMessage(isDark)
                else
                  _buildNoInviteMessage(isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

