import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_db.dart';
import '../../core/credential_strength.dart';
import '../../core/institute_id_display.dart';
import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/validation_service.dart';
import '../widgets/credential_strength_indicator.dart';
import 'login_screen.dart';

class InstituteAdminRegistrationScreen extends StatefulWidget {
  static const routeName = '/admin-registration';

  const InstituteAdminRegistrationScreen({super.key});

  @override
  State<InstituteAdminRegistrationScreen> createState() =>
      _InstituteAdminRegistrationScreenState();
}

class _InstituteAdminRegistrationScreenState
    extends State<InstituteAdminRegistrationScreen> {
  final AuthService _authService = AuthService();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  List<Map<String, dynamic>> _adminInvites = [];
  Map<String, dynamic>? _selectedInvite;
  bool _isLoadingInvites = true;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isSettingPassword = false;
  bool _showPassword = false;
  bool _otpSent = false;
  int _currentStep = 0; // 0 select, 1 review, 2 otp, 3 password

  @override
  void initState() {
    super.initState();
    _loadAdminInvites();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminInvites() async {
    try {
      setState(() => _isLoadingInvites = true);

      final invites = await appDb
          .from('admin_invites')
          .select('id, institute_id, full_name, phone, email, claimed')
          .eq('claimed', false)
          .order('created_at', ascending: false);

      final rows = <Map<String, dynamic>>[];
      for (final raw in invites as List) {
        final invite = Map<String, dynamic>.from(raw as Map);
        final instituteId = invite['institute_id']?.toString();
        if (instituteId != null && instituteId.isNotEmpty) {
          final institute = await appDb
              .from('institutes')
              .select('id, name, address, city, mobile_no, institute_code')
              .eq('id', instituteId)
              .maybeSingle();
          if (institute != null) {
            invite['institute'] = Map<String, dynamic>.from(institute);
          }
        }
        rows.add(invite);
      }

      if (!mounted) return;
      setState(() {
        _adminInvites = rows;
        _isLoadingInvites = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading admin setup records: $e');
      if (!mounted) return;
      setState(() => _isLoadingInvites = false);
      _showSnack('Could not load institute setup records.', isError: true);
    }
  }

  void _selectInstitute(Map<String, dynamic> invite) {
    setState(() {
      _selectedInvite = invite;
      _otpSent = false;
      _otpController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _currentStep = 1;
    });
  }

  Future<void> _sendOtp() async {
    final email = _selectedInvite?['email']?.toString().trim() ?? '';
    if (email.isEmpty) {
      _showSnack('Admin email is missing.', isError: true);
      return;
    }

    setState(() => _isSendingOtp = true);
    final result = await _authService.sendInviteSignupEmailOTP(email);
    if (!mounted) return;
    setState(() {
      _isSendingOtp = false;
      _otpSent = result['success'] == true;
      if (_otpSent) _currentStep = 2;
    });

    if (result['success'] == true) {
      if (!mounted) return;
      _showSnack(result['message']?.toString() ?? 'OTP sent to $email.');
    } else {
      _showSnack(result['message']?.toString() ?? 'Could not send OTP.',
          isError: true);
    }
  }

  Future<void> _verifyOtp() async {
    if (_isVerifyingOtp) return;
    final email = _selectedInvite?['email']?.toString().trim() ?? '';
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      _showSnack('Enter the 6-digit OTP.', isError: true);
      return;
    }

    setState(() => _isVerifyingOtp = true);
    final result = await _authService.verifyInviteSignupEmailOTP(email, otp);
    if (!mounted) return;
    setState(() => _isVerifyingOtp = false);

    if (result['success'] == true) {
      setState(() => _currentStep = 3);
      _showSnack('OTP verified. Create your password.');
    } else {
      _showSnack(result['message']?.toString() ?? 'Invalid OTP.',
          isError: true);
    }
  }

  Future<void> _setPassword() async {
    final invite = _selectedInvite;
    if (invite == null) return;

    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    final pwdErr =
        ValidationService.validatePassword(password, isRegistration: true);
    if (pwdErr != null) {
      _showSnack('Please use a stronger password. $pwdErr', isError: true);
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match.', isError: true);
      return;
    }

    setState(() => _isSettingPassword = true);
    final institute = _institute(invite);
    final result = await _authService.claimAdminInvite(
      inviteId: invite['id'].toString(),
      instituteId: invite['institute_id'].toString(),
      email: invite['email'].toString(),
      password: password,
      fullName: invite['full_name']?.toString(),
      phone: invite['phone']?.toString(),
      instituteName: institute['name']?.toString(),
    );

    if (!mounted) return;
    setState(() => _isSettingPassword = false);

    if (result['success'] == true) {
      _showSnack('Password created. Login with Institute ID and password.');

      // ✅ Save institute ID for next login
      final instituteId = invite['institute_id'].toString();
      await _saveInstituteIdForLogin(instituteId);

      Navigator.pushNamedAndRemoveUntil(
        context,
        LoginScreen.routeName,
        (route) => false,
        arguments: {
          'forceFullLogin': true,
          'instituteId': instituteId,
        },
      );
    } else {
      _showSnack(result['message']?.toString() ?? 'Registration failed.',
          isError: true);
    }
  }

  Map<String, dynamic> _institute(Map<String, dynamic> invite) {
    final raw = invite['institute'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
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

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppTheme.primaryBlue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.backgroundGrey,
      appBar: AppBar(
        title: const Text('Admin Setup'),
        backgroundColor: AppTheme.primaryBlue,
        elevation: 0,
      ),
      body: switch (_currentStep) {
        0 => _buildInstituteSelection(isDark),
        1 => _buildReviewStep(isDark),
        2 => _buildOtpStep(isDark),
        _ => _buildPasswordStep(isDark),
      },
    );
  }

  Widget _buildInstituteSelection(bool isDark) {
    if (_isLoadingInvites) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_adminInvites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No institute setup found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask the website admin to add institute and admin details first.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textGray),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loadAdminInvites,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAdminInvites,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Select Your Institute',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These records are created from the website form.',
            style: TextStyle(color: AppTheme.textGray),
          ),
          const SizedBox(height: 16),
          ..._adminInvites.map((invite) => _buildInstituteCard(invite, isDark)),
        ],
      ),
    );
  }

  Widget _buildInstituteCard(Map<String, dynamic> invite, bool isDark) {
    final institute = _institute(invite);
    return Card(
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        onTap: () => _selectInstitute(invite),
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.12),
          child: const Icon(Icons.domain, color: AppTheme.primaryBlue),
        ),
        title: Text(
          institute['name']?.toString().isNotEmpty == true
              ? institute['name'].toString()
              : 'Institute ${invite['institute_id']}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppTheme.textDark,
          ),
        ),
        subtitle: Text(
          'ID: ${invite['institute_id']}\nAdmin: ${invite['full_name'] ?? ''}',
          style: TextStyle(color: AppTheme.textGray),
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  Widget _buildReviewStep(bool isDark) {
    final invite = _selectedInvite!;
    final institute = _institute(invite);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Confirm Details', isDark),
        const SizedBox(height: 12),
        _infoTile('Institute ID', formatInstituteIdForDisplay(invite['institute_id']?.toString() ?? '')),
        _infoTile('Institute name', institute['name']?.toString() ?? ''),
        _infoTile('Address', institute['address']?.toString() ?? ''),
        _infoTile('City', institute['city']?.toString() ?? ''),
        const SizedBox(height: 14),
        _infoTile('Admin full name', invite['full_name']?.toString() ?? ''),
        _infoTile('Mobile number', invite['phone']?.toString() ?? ''),
        _infoTile('Email for OTP', invite['email']?.toString() ?? ''),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _isSendingOtp ? null : _sendOtp,
          icon: _isSendingOtp
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_email_read_outlined),
          label: Text(_otpSent ? 'Send OTP Again' : 'Send OTP'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _currentStep = 0),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildOtpStep(bool isDark) {
    final email = _selectedInvite?['email']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Verify OTP', isDark),
        const SizedBox(height: 8),
        Text(
          'Enter the 6-digit OTP sent to $email.',
          style: TextStyle(color: AppTheme.textGray),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            if (v.length != 6 || _isVerifyingOtp || !RegExp(r'^\d{6}$').hasMatch(v)) {
              return;
            }
            _verifyOtp();
          },
          decoration: InputDecoration(
            labelText: 'OTP Code',
            prefixIcon: const Icon(Icons.security),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isVerifyingOtp ? null : _verifyOtp,
          child: _isVerifyingOtp
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verify OTP'),
        ),
        TextButton(
          onPressed: _isSendingOtp ? null : _sendOtp,
          child: const Text('Resend OTP'),
        ),
        OutlinedButton(
          onPressed: () => setState(() => _currentStep = 1),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Create Password', isDark),
        const SizedBox(height: 8),
        Text(
          'Use at least 8 characters with uppercase, lowercase, a number, and a symbol (!@#\$%^&*).',
          style: TextStyle(color: AppTheme.textGray),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _passwordController,
          obscureText: !_showPassword,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        CredentialStrengthIndicator(
          analysis: CredentialStrengthAnalysis.analyzePassword(_passwordController.text),
          dense: true,
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordController,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _isSettingPassword ? null : _setPassword,
          child: _isSettingPassword
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create Password'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => setState(() => _currentStep = 2),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : AppTheme.textDark,
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    final display = value.trim().isEmpty ? '-' : value.trim();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textGray, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            display,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
