import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../core/app_db.dart';
import '../core/attendance_staff_auth.dart';
import '../core/supabase_maps.dart';
import '../config/supabase_env.dart';
import 'error_handler.dart';
import 'validation_service.dart';
import 'database_init_service.dart';
import 'security_ops_service.dart';
import 'secure_credential_store.dart';

class AuthService {
  SupabaseClient get _db => appDb;
  final SecurityOpsService _securityOps = SecurityOpsService();

  String _supabaseHostForLogs() {
    try {
      return Uri.parse(SupabaseEnv.url).host;
    } catch (_) {
      return 'unknown-host';
    }
  }

  final Map<String, String> _otpStorage = {};
  final Map<String, String> _registrationOtpStorage = {};
  final Map<String, String> _verificationIdStorage = {};
  final Map<String, int> _registrationOtpExpiryEpoch = {};
  final Map<String, String> _forgotPinOtpStorage = {};
  final Map<String, int> _forgotPinOtpExpiryEpoch = {};

  /// Phone-first institute signup: stable synthetic Supabase email (unique per mobile).
  static String syntheticEmailFromIndianMobile(String digits10) {
    final d = digits10.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(d)) {
      throw ArgumentError.value(digits10, 'digits10', 'Expected exactly 10 digits');
    }
    return '$d@phone.msce-attendance.app';
  }

  /// Resolves **10-digit Indian mobile** to [syntheticEmailFromIndianMobile]; otherwise lowercases email.
  static String normalizeLoginEmail(String raw) {
    final t = raw.trim();
    if (RegExp(r'^\d{10}$').hasMatch(t)) {
      return syntheticEmailFromIndianMobile(t);
    }
    return t.toLowerCase();
  }

  /// Login / unlock PIN: **4 digits only**.
  static const String loginPinLengthMessage = 'PIN must be exactly 4 digits';

  static bool isValidLoginPinLength(String pin) {
    final n = pin.trim().length;
    return n == 4;
  }

  /// Normalized lookup key for email-OTP flows (registration invite, forgot PIN, etc.).
  String _loginEmailOtpKey(String email) => normalizeLoginEmail(email);

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return phone;
    final visibleTail = digits.substring(digits.length - 4);
    return '******$visibleTail';
  }

  String _maskEmail(String email) {
    final value = email.trim().toLowerCase();
    final at = value.indexOf('@');
    if (at <= 1) return value;
    final prefix = value.substring(0, at);
    final domain = value.substring(at);
    final visible = prefix.length <= 2 ? prefix.substring(0, 1) : prefix.substring(0, 2);
    return '$visible***$domain';
  }

  static String _friendlyBrevoEmailError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('unrecognised ip') ||
        lower.contains('unrecognized ip') ||
        lower.contains('authorised_ips') ||
        lower.contains('authorized_ips')) {
      return 'Email blocked by Brevo IP security. In Brevo go to Settings → Security → '
          'Authorized IPs → Deactivate blocking for API keys (not SMTP only). '
          'Supabase IPs change — do not whitelist one address. Then update BREVO_API_KEY in Supabase.';
    }
    return raw;
  }

  /// Parses `email-otp` Edge Function response (production: Brevo only).
  ({bool ok, String? errorMessage}) _parseEmailOtpInvokeResult(dynamic raw) {
    if (raw == null) {
      return (ok: false, errorMessage: 'Empty email service response');
    }
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw.trim());
      } catch (_) {
        return (ok: false, errorMessage: 'Invalid email service response');
      }
    }
    if (decoded is! Map) {
      return (ok: false, errorMessage: 'Invalid email service response');
    }
    final data = Map<String, dynamic>.from(decoded);
    if (data['demoMode'] == true) {
      return (
        ok: false,
        errorMessage:
            'OTP demo mode is still enabled on `email-otp`. Redeploy the function '
            '(remove DEMO_EMAIL_OTP), then set secrets BREVO_API_KEY and EMAIL_FROM.',
      );
    }
    final success = data['success'] == true;
    if (!success) {
      final msg = data['error']?.toString();
      final p = data['provider'];
      String? detail;
      if (p is Map && p['message'] != null) detail = p['message'].toString();
      final parts = <String>[];
      if (msg != null && msg.isNotEmpty) parts.add(msg);
      if (detail != null && detail.isNotEmpty) parts.add(detail);
      final joined = parts.isNotEmpty ? parts.join(' ') : 'Could not send email';
      return (ok: false, errorMessage: _friendlyBrevoEmailError(joined));
    }
    final vendor = data['emailVendor']?.toString().toLowerCase();
    if (vendor != null && vendor.isNotEmpty && vendor != 'brevo') {
      return (
        ok: false,
        errorMessage:
            'Email was not sent via Brevo (vendor: $vendor). Check Edge Function secrets and redeploy.',
      );
    }
    return (ok: true, errorMessage: null);
  }

  static String _emailOtpInvokeFailure(FunctionException e) {
    final d = e.details;
    if (d is Map) {
      final err = d['error'] ?? d['message'];
      final s = err?.toString().trim();
      if (s != null && s.isNotEmpty) return _friendlyBrevoEmailError(s);
    }
    if (d is String && d.trim().isNotEmpty) {
      return _friendlyBrevoEmailError(d.trim());
    }
    if (e.status == 503) {
      return 'Email unavailable: add BREVO_API_KEY + EMAIL_FROM to Edge Function secrets and deploy '
          '`email-otp`.';
    }
    return 'Could not reach email service (HTTP ${e.status}).'.trim();
  }

  Future<Map<String, dynamic>> getForgotPinContactInfo(String email) async {
    try {
      final key = normalizeLoginEmail(email);
      if (key.isEmpty) {
        return {'success': false, 'message': 'Email is required'};
      }

      final profile = await _findUserProfile(email: key);
      if (profile == null) {
        return {'success': false, 'message': 'Account not found'};
      }

      final userData = profile['userData'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final instituteId = (profile['instituteId'] as String?)?.trim() ?? '';
      var phone = (userData['phoneNumber'] as String?)?.trim() ?? '';

      if (phone.isEmpty && instituteId.isNotEmpty) {
        try {
          final institute = await _db
              .from('institutes')
              .select('mobile_no')
              .eq('id', instituteId)
              .maybeSingle();
          phone = (institute?['mobile_no'] as String?)?.trim() ?? '';
        } catch (_) {}
      }

      return {
        'success': true,
        'email': key,
        'maskedEmail': _maskEmail(key),
        'phone': phone,
        'maskedPhone': phone.isNotEmpty ? _maskPhone(phone) : 'Not available',
      };
    } catch (e) {
      return {'success': false, 'message': 'Could not load account contact details'};
    }
  }

  Future<Map<String, dynamic>> sendForgotPinOtp(String email) async {
    try {
      final key = _loginEmailOtpKey(email);
      if (key.isEmpty) {
        return {'success': false, 'message': 'Email is required'};
      }

      final contact = await getForgotPinContactInfo(key);
      if (contact['success'] != true) {
        return contact;
      }

      final otp = _generateOTP();
      dynamic raw;
      try {
        final fn = await _db.functions.invoke(
          'email-otp',
          body: {
            'mode': 'otp',
            'to': key,
            'otp': otp,
            'purpose': 'Forgot PIN',
          },
        );
        raw = fn.data;
      } on FunctionException catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {
          'success': false,
          'message': _emailOtpInvokeFailure(e),
          'maskedEmail': contact['maskedEmail'],
          'maskedPhone': contact['maskedPhone'],
        };
      } catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {
          'success': false,
          'message': 'Could not reach email service. Check your connection.',
          'maskedEmail': contact['maskedEmail'],
          'maskedPhone': contact['maskedPhone'],
        };
      }

      final parsed = _parseEmailOtpInvokeResult(raw);
      if (!parsed.ok) {
        return {
          'success': false,
          'message': parsed.errorMessage ?? 'Email send failed',
          'maskedEmail': contact['maskedEmail'],
          'maskedPhone': contact['maskedPhone'],
        };
      }

      _forgotPinOtpStorage[key] = otp;
      _forgotPinOtpExpiryEpoch[key] =
          DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

      if (kDebugMode) {
        debugPrint('📧 FORGOT PIN OTP sent via Brevo to $key (valid 10 min)');
      }

      return {
        'success': true,
        'message': 'OTP sent to email',
        'maskedEmail': contact['maskedEmail'],
        'maskedPhone': contact['maskedPhone'],
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  Future<Map<String, dynamic>> verifyForgotPinOtp(String email, String otp) async {
    final key = _loginEmailOtpKey(email);
    final exp = _forgotPinOtpExpiryEpoch[key];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && now > exp) {
      _forgotPinOtpStorage.remove(key);
      _forgotPinOtpExpiryEpoch.remove(key);
      return {'success': false, 'message': 'OTP expired. Tap Send OTP again.'};
    }
    final stored = _forgotPinOtpStorage[key];
    if (stored == null || stored != otp.trim()) {
      return {'success': false, 'message': 'Invalid OTP'};
    }
    return {'success': true, 'message': 'OTP verified'};
  }

  static const String prefForgotPasswordCooldownUntil =
      'msce_admin_forgot_password_cooldown_until';

  static const Duration forgotPasswordCooldown = Duration(days: 1);

  /// True when forgot-password was used successfully within the last 24 hours.
  static Future<bool> isForgotPasswordCooldownActive() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(prefForgotPasswordCooldownUntil);
      if (until == null) return false;
      return DateTime.now().millisecondsSinceEpoch < until;
    } catch (_) {
      return false;
    }
  }

  static Future<DateTime?> forgotPasswordAvailableAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(prefForgotPasswordCooldownUntil);
      if (until == null) return null;
      final dt = DateTime.fromMillisecondsSinceEpoch(until);
      if (!DateTime.now().isBefore(dt)) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  static Future<void> markForgotPasswordCooldown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = DateTime.now().add(forgotPasswordCooldown).millisecondsSinceEpoch;
      await prefs.setInt(prefForgotPasswordCooldownUntil, until);
    } catch (_) {}
  }

  /// Invite email (website) or active admin profile email for forgot-password UI.
  Future<String?> getAdminResetEmailForInstitute(String instituteKey) async {
    try {
      await DatabaseInitService.ensureInitialized();
      final raw = await _db.rpc(
        'get_admin_reset_email_for_institute',
        params: {'p_key': instituteKey.trim()},
      );
      if (raw == null) return null;
      final s = raw.toString().trim();
      return s.isEmpty ? null : s;
    } catch (e) {
      if (kDebugMode) debugPrint('get_admin_reset_email_for_institute: $e');
      return null;
    }
  }

  /// Stage OTP server-side and send to institute admin email (Brevo via email-otp).
  Future<Map<String, dynamic>> sendAdminForgotPasswordOtp({
    required String instituteKey,
    required String email,
  }) async {
    try {
      final key = instituteKey.trim();
      final normalizedEmail = normalizeLoginEmail(email);
      if (key.isEmpty || normalizedEmail.isEmpty) {
        return {'success': false, 'message': 'Institute ID and email are required'};
      }

      final expected = await getAdminResetEmailForInstitute(key);
      if (expected == null || expected.isEmpty) {
        return {
          'success': false,
          'message': 'No admin email on file. Complete institute setup first.',
        };
      }
      if (normalizeLoginEmail(expected) != normalizedEmail) {
        return {
          'success': false,
          'message': 'Email does not match the admin invite for this institute.',
        };
      }

      final otp = _generateOTP();
      final stageRaw = await _db.rpc(
        'stage_admin_password_reset_otp',
        params: {
          'p_institute_key': key,
          'p_email': normalizedEmail,
          'p_otp': otp,
        },
      );
      final stage = stageRaw is Map
          ? Map<String, dynamic>.from(stageRaw)
          : (jsonDecode(stageRaw.toString()) as Map<String, dynamic>);
      if (stage['success'] != true) {
        return {
          'success': false,
          'message': stage['message']?.toString() ?? 'Could not stage OTP',
        };
      }

      dynamic raw;
      try {
        final fn = await _db.functions.invoke(
          'email-otp',
          body: {
            'mode': 'otp',
            'to': normalizedEmail,
            'otp': otp,
            'purpose': 'Forgot password',
          },
        );
        raw = fn.data;
      } on FunctionException catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {'success': false, 'message': _emailOtpInvokeFailure(e)};
      } catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {
          'success': false,
          'message': 'Could not reach email service. Check your connection.',
        };
      }

      final parsed = _parseEmailOtpInvokeResult(raw);
      if (!parsed.ok) {
        return {
          'success': false,
          'message': parsed.errorMessage ?? 'Email send failed',
        };
      }

      if (kDebugMode) {
        debugPrint('📧 Forgot-password OTP sent to $normalizedEmail');
      }

      return {
        'success': true,
        'message': 'OTP sent to ${_maskEmail(normalizedEmail)}',
        'maskedEmail': _maskEmail(normalizedEmail),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('sendAdminForgotPasswordOtp: $e');
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  /// Verify OTP and update Supabase Auth password (admin-reset-password edge function).
  Future<Map<String, dynamic>> resetAdminPasswordAfterOtp({
    required String instituteKey,
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final key = instituteKey.trim();
      final normalizedEmail = normalizeLoginEmail(email);
      final otpTrim = otp.trim();

      if (key.isEmpty || normalizedEmail.isEmpty || otpTrim.length != 6) {
        return {'success': false, 'message': 'Institute ID, email and 6-digit OTP are required'};
      }

      final pwdErr =
          ValidationService.validatePassword(newPassword, isRegistration: true);
      if (pwdErr != null) {
        return {'success': false, 'message': pwdErr};
      }

      dynamic raw;
      try {
        final fn = await _db.functions.invoke(
          'admin-reset-password',
          body: {
            'instituteKey': key,
            'email': normalizedEmail,
            'otp': otpTrim,
            'newPassword': newPassword,
          },
        );
        raw = fn.data;
      } on FunctionException catch (e) {
        if (kDebugMode) debugPrint('admin-reset-password invoke failed: $e');
        return {'success': false, 'message': _emailOtpInvokeFailure(e)};
      } catch (e) {
        if (kDebugMode) debugPrint('admin-reset-password invoke failed: $e');
        return {
          'success': false,
          'message': 'Could not reach password reset service.',
        };
      }

      Map<String, dynamic> data;
      if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else if (raw is String && raw.trim().isNotEmpty) {
        data = Map<String, dynamic>.from(jsonDecode(raw.trim()) as Map);
      } else {
        return {'success': false, 'message': 'Empty response from password reset'};
      }

      if (data['success'] == true) {
        await markForgotPasswordCooldown();
        await _clearCachedCredentialsAfterPasswordReset(normalizedEmail);
        return {
          'success': true,
          'message': data['message']?.toString() ??
              'Password updated in Supabase. Sign in with Institute ID and your new password.',
        };
      }

      return {
        'success': false,
        'message': data['error']?.toString() ??
            data['message']?.toString() ??
            'Password reset failed',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('resetAdminPasswordAfterOtp: $e');
      return {'success': false, 'message': 'Password reset failed: ${e.toString()}'};
    }
  }

  Future<void> _clearCachedCredentialsAfterPasswordReset(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bioEncPassKey(email));
      await prefs.remove(_encPassKey(email));
    } catch (e) {
      if (kDebugMode) debugPrint('clearCachedCredentialsAfterPasswordReset: $e');
    }
  }

  final Map<String, String> _inviteEmailOtpStorage = {};
  final Map<String, int> _inviteEmailOtpExpiryEpoch = {};

  /// OTP for onboarding (website invite) sent to institute email — separate store from login OTP.
  Future<Map<String, dynamic>> sendInviteSignupEmailOTP(String email) async {
    try {
      final key = _loginEmailOtpKey(email);
      if (key.isEmpty) {
        return {'success': false, 'message': 'Email is required'};
      }
      final otp = _generateOTP();
      dynamic raw;
      try {
        final fn = await _db.functions.invoke(
          'email-otp',
          body: {
            'mode': 'otp',
            'to': key,
            'otp': otp,
            'purpose': 'Admin setup',
          },
        );
        raw = fn.data;
      } on FunctionException catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {'success': false, 'message': _emailOtpInvokeFailure(e)};
      } catch (e) {
        if (kDebugMode) debugPrint('email-otp invoke failed: $e');
        return {'success': false, 'message': 'Could not reach email service. Check your connection.'};
      }

      final parsed = _parseEmailOtpInvokeResult(raw);
      if (!parsed.ok) {
        return {'success': false, 'message': parsed.errorMessage ?? 'Email send failed'};
      }

      _inviteEmailOtpStorage[key] = otp;
      _inviteEmailOtpExpiryEpoch[key] =
          DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch ~/ 1000;

      if (kDebugMode) {
        debugPrint('📧 Invite OTP sent via Brevo to $email (valid 10 min)');
      }
      return {
        'success': true,
        'message': 'OTP sent to your email',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  Future<Map<String, dynamic>> verifyInviteSignupEmailOTP(String email, String otp) async {
    final key = _loginEmailOtpKey(email);
    final exp = _inviteEmailOtpExpiryEpoch[key];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && now > exp) {
      _inviteEmailOtpStorage.remove(key);
      _inviteEmailOtpExpiryEpoch.remove(key);
      return {'success': false, 'message': 'OTP expired. Tap Resend OTP.'};
    }
    final stored = _inviteEmailOtpStorage[key];
    if (stored == null || stored != otp.trim()) {
      return {'success': false, 'message': 'Invalid OTP'};
    }
    _inviteEmailOtpStorage.remove(key);
    _inviteEmailOtpExpiryEpoch.remove(key);
    return {'success': true, 'message': 'OTP verified'};
  }

  /// RPC: institute id or institute_code → login email (Supabase still authenticates by email).
  Future<String?> getAdminEmailForInstituteLogin(String instituteKey) async {
    try {
      await DatabaseInitService.ensureInitialized();
      final raw = await _db.rpc(
        'get_admin_email_for_institute_login',
        params: {'p_key': instituteKey.trim()},
      );
      if (raw == null) return null;
      final s = raw.toString().trim();
      return s.isEmpty ? null : s;
    } catch (e) {
      if (kDebugMode) debugPrint('get_admin_email_for_institute_login: $e');
      return null;
    }
  }

  Future<void> _incrementInstituteField(String instituteId, String column) async {
    final row = await _db.from('institutes').select(column).eq('id', instituteId).maybeSingle();
    final n = (row?[column] as int?) ?? 0;
    await _db.from('institutes').update({column: n + 1}).eq('id', instituteId);
  }

  Map<String, dynamic> _profileBundle(Map<String, dynamic> row) {
    return {
      'profileId': row['id'].toString(),
      'userData': profileRowToUserData(row),
      'instituteId': row['institute_id'],
      'instituteName': row['institute_name'],
    };
  }

  Future<Map<String, dynamic>?> _findUserProfile({
    String? uid,
    String? email,
  }) async {
    try {
      if (uid != null && uid.isNotEmpty) {
        final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
        if (row != null) return _profileBundle(row);
      }
      if (email != null && email.isNotEmpty) {
        final normalizedEmail = normalizeLoginEmail(email);

        final exactRow = await _db
            .from('profiles')
            .select()
            .eq('email', normalizedEmail)
            .maybeSingle();
        if (exactRow != null) return _profileBundle(exactRow);

        final caseInsensitiveRow = await _db
            .from('profiles')
            .select()
            .ilike('email', normalizedEmail)
            .maybeSingle();
        if (caseInsensitiveRow != null) return _profileBundle(caseInsensitiveRow);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in _findUserProfile: $e');
    }
    return null;
  }

  Future<bool> _isCurrentUserCoder() async {
    try {
      final u = _db.auth.currentUser;
      if (u == null) return false;
      final row = await _db.from('coders').select('id').eq('id', u.id).maybeSingle();
      return row != null;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ _isCurrentUserCoder: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> registerAdmin({
    required String email,
    required String password,
    required String name,
    required String adminId,
  }) async {
    String? uid;
    try {
      await DatabaseInitService.ensureInitialized();

      final emailError = ValidationService.validateEmail(email);
      if (emailError != null) {
        return {'success': false, 'message': emailError};
      }

      final passwordError = ValidationService.validatePassword(password, isRegistration: true);
      if (passwordError != null) {
        return {'success': false, 'message': passwordError};
      }

      final nameError = ValidationService.validateName(name);
      if (nameError != null) {
        return {'success': false, 'message': nameError};
      }

      email = ValidationService.sanitizeInput(email);
      name = ValidationService.sanitizeInput(name);

      if (ValidationService.containsDangerousContent(email) ||
          ValidationService.containsDangerousContent(name)) {
        return {'success': false, 'message': 'Invalid characters detected in input'};
      }

      final adminIdError = ValidationService.validateRollNumber(adminId);
      if (adminIdError != null) {
        return {'success': false, 'message': adminIdError};
      }

      if (kDebugMode) debugPrint('🔐 Creating Supabase user for: $email');

      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );
      final user = res.user;
      if (user == null) {
        return {'success': false, 'message': 'Could not create account'};
      }
      uid = user.id;

      await _db.from('profiles').upsert(
        {
          'id': uid,
          'email': email,
          'user_id': ValidationService.sanitizeInput(adminId),
          'name': name,
          'role': 'admin',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'last_login': null,
        },
        onConflict: 'id',
      );

      await _db.auth.signOut();
      return {'success': true, 'message': 'Admin created successfully'};
    } on AuthException catch (e) {
      if (uid != null) {
        try {
          await _db.auth.signOut();
        } catch (_) {}
      }
      return {'success': false, 'message': ErrorHandler.handleAuthException(e)};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Unexpected error: $e');
      return {'success': false, 'message': 'Error: ${e.toString()}'};
    }
  }

  /// Server-side max numeric `sr_no` and `user_id` per institute (indexed query, O(1) result size).
  Future<({int srMax, int rollMax})> _peakStudentNumbersFromDb(String instituteId) async {
    try {
      final raw = await _db.rpc('institute_peak_student_numbers', params: {
        'p_institute_id': instituteId,
      });
      if (raw is Map) {
        final m = Map<String, dynamic>.from(raw);
        int read(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v;
          if (v is num) return v.toInt();
          return int.tryParse(v.toString()) ?? 0;
        }
        return (srMax: read(m['sr_max']), rollMax: read(m['roll_max']));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ institute_peak_student_numbers RPC (add migration 032 if missing): $e');
      }
    }
    final rows = await _db.from('students').select('sr_no').eq('institute_id', instituteId);
    var maxSr = 0;
    for (final r in rows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final s = (m['sr_no'] as String?)?.trim() ?? '';
      final n = _parseLooseStudentSerial(s);
      if (n != null && n > maxSr) maxSr = n;
    }
    final rollRows = await _db.from('students').select('user_id').eq('institute_id', instituteId);
    var maxRoll = 0;
    for (final r in rollRows as List) {
      final m = Map<String, dynamic>.from(r as Map);
      final u = (m['user_id'] as String?)?.trim() ?? '';
      if (u.isEmpty) continue;
      final n = _parseLooseStudentSerial(u);
      if (n != null && n > maxRoll) maxRoll = n;
    }
    return (srMax: maxSr, rollMax: maxRoll);
  }

  /// Parses `12`, `012`, `SR_012`, `sr-3` for peak fallback when RPC is unavailable.
  static int? _parseLooseStudentSerial(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    final direct = int.tryParse(s);
    if (direct != null) return direct;
    final stripped = s.replaceFirst(RegExp(r'(?i)^sr[_-]?'), '').trim();
    return int.tryParse(stripped);
  }

  static String _normalizeFullNameParts({
    required String first,
    required String middle,
    required String last,
  }) {
    final f = first.trim().toLowerCase();
    final m = middle.trim().toLowerCase();
    final l = last.trim().toLowerCase();
    return '$f $m $l'.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<Map<String, dynamic>> addStudentManually({
    required String firstName,
    required String middleName,
    required String lastName,
    required String year,
    String? subject,
    String? instituteId,
    List<String>? subjects,
  }) async {
    await DatabaseInitService.ensureInitialized();

    for (final entry in [
      (firstName, 'First name'),
      (middleName, 'Middle name'),
      (lastName, 'Last name'),
    ]) {
      final err = ValidationService.validateRequiredNamePart(entry.$1, entry.$2);
      if (err != null) {
        return {'success': false, 'message': err};
      }
    }

    final fn = ValidationService.sanitizeInput(firstName.trim());
    final mn = ValidationService.sanitizeInput(middleName.trim());
    final ln = ValidationService.sanitizeInput(lastName.trim());
    year = ValidationService.sanitizeInput(year);

    final fullName = '$fn $mn $ln'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final nameCompare = _normalizeFullNameParts(first: fn, middle: mn, last: ln);

    if (ValidationService.containsDangerousContent(fn) ||
        ValidationService.containsDangerousContent(mn) ||
        ValidationService.containsDangerousContent(ln) ||
        ValidationService.containsDangerousContent(year)) {
      return {'success': false, 'message': 'Invalid characters detected in input'};
    }

    try {
      final u = _db.auth.currentUser;
      if (u == null) {
        return {'success': false, 'message': 'Cannot add student: not signed in.'};
      }

      if (kDebugMode) {
        debugPrint('👤 addStudentManually: User ID: ${u.id}');
      }

      final requested = instituteId?.trim();
      final results = await Future.wait([
        _findUserProfile(uid: u.id),
        _isCurrentUserCoder(),
      ]);
      final prof = results[0] as Map<String, dynamic>?;
      final isCoder = results[1] as bool;
      final profileInstituteId = (prof?['instituteId'] as String?)?.trim();

      if (kDebugMode) {
        debugPrint('🏢 Institute ID Resolution:');
        debugPrint('   Supabase host: ${_supabaseHostForLogs()}');
        debugPrint('   Profile institute_id: $profileInstituteId');
        debugPrint('   Requested institute_id: $requested');
        debugPrint('   Is coder: $isCoder');
      }

      final String? currentInstituteId;
      if (isCoder && requested != null && requested.isNotEmpty) {
        currentInstituteId = requested;
        if (kDebugMode) {
          debugPrint('   ✅ Using requested institute_id (coder override)');
        }
      } else {
        if (requested != null &&
            requested.isNotEmpty &&
            profileInstituteId != null &&
            profileInstituteId.isNotEmpty &&
            requested != profileInstituteId) {
          if (kDebugMode) {
            debugPrint(
              '❌ Institute mismatch on this device. requested=$requested profile=$profileInstituteId',
            );
          }
          return {
            'success': false,
            'message':
                'Institute mismatch detected on this device. Please logout and login again before adding a student.',
          };
        }
        currentInstituteId = profileInstituteId;
        if (kDebugMode &&
            requested != null &&
            requested.isNotEmpty &&
            requested != profileInstituteId) {
          debugPrint(
            '⚠️ addStudentManually: ignoring institute_id=$requested; using profile institute $profileInstituteId',
          );
        } else if (kDebugMode) {
          debugPrint('   ✅ Using profile institute_id');
        }
      }

      if (currentInstituteId == null || currentInstituteId.isEmpty) {
        if (kDebugMode) {
          debugPrint('❌ CRITICAL: No institute_id found!');
          debugPrint('   Profile: $prof');
        }
        return {
          'success': false,
          'message':
              'Cannot add student: Institute ID not found. Please ensure you are logged in as an admin of an institute.',
        };
      }

      if (kDebugMode) {
        debugPrint('✅ Creating student with institute_id: $currentInstituteId');
      }

      final nameCandidates = await _db
          .from('students')
          .select('name, first_name, middle_name, last_name')
          .eq('institute_id', currentInstituteId)
          .ilike('first_name', fn.trim())
          .ilike('last_name', ln.trim());
      for (final r in nameCandidates as List) {
        final m = Map<String, dynamic>.from(r as Map);
        final existingName = _normalizeFullNameParts(
          first: (m['first_name'] as String?) ?? '',
          middle: (m['middle_name'] as String?) ?? '',
          last: (m['last_name'] as String?) ?? '',
        ).isNotEmpty
            ? _normalizeFullNameParts(
                first: (m['first_name'] as String?) ?? '',
                middle: (m['middle_name'] as String?) ?? '',
                last: (m['last_name'] as String?) ?? '',
              )
            : ((m['name'] as String?)?.trim().toLowerCase() ?? '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
        if (existingName.isNotEmpty && existingName == nameCompare) {
          return {
            'success': false,
            'message':
                'A student with the same full name is already registered in this institute.',
          };
        }
      }

      final peak = await _peakStudentNumbersFromDb(currentInstituteId);
      final base = peak.srMax > peak.rollMax ? peak.srMax : peak.rollMax;
      final nextSrNo = (base + 1).toString();
      final effectiveUserId = nextSrNo;

      try {
        final existing = await _db
            .from('students')
            .select('id')
            .eq('institute_id', currentInstituteId)
            .eq('user_id', effectiveUserId);
        if (existing.isNotEmpty) {
          return {'success': false, 'message': 'Roll Number already exists in this institute'};
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Duplicate check: $e');
      }

      final docId = 'MANUAL_${DateTime.now().millisecondsSinceEpoch}';

      final studentData = <String, dynamic>{
        'id': docId,
        'institute_id': currentInstituteId,
        'uid': docId,
        'user_id': effectiveUserId,
        'sr_no': nextSrNo,
        'name': fullName,
        'first_name': fn,
        'middle_name': mn,
        'last_name': ln,
        'year': year,
        if (subject?.isNotEmpty ?? false) 'subject': subject,
        if (subjects != null && subjects.isNotEmpty) 'subjects': subjects,
        'role': 'student',
        'status': 'approved',
        'has_device': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      await _db.from('students').insert(studentData);

      final insertedStudent = await _db
          .from('students')
          .select('id, institute_id, user_id, sr_no')
          .eq('id', docId)
          .eq('institute_id', currentInstituteId)
          .maybeSingle();

      if (insertedStudent == null) {
        if (kDebugMode) {
          debugPrint(
            '❌ Post-insert verification failed for student $docId in institute $currentInstituteId',
          );
        }
        return {
          'success': false,
          'message':
              'Student save could not be verified on server. Please refresh and try again.',
        };
      }

      if (kDebugMode) {
        debugPrint('✅ Student inserted to database:');
        debugPrint('   Supabase host: ${_supabaseHostForLogs()}');
        debugPrint('   ID: $docId');
        debugPrint('   Name: $fullName');
        debugPrint('   SR_NO: $nextSrNo');
        debugPrint('   Institute: $currentInstituteId');
        debugPrint('   Verified on server: ${insertedStudent['id']}');
      }

      try {
        await _incrementInstituteField(currentInstituteId, 'student_count');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ student_count: $e');
      }

      return {
        'success': true,
        'message': 'Student added successfully',
        'instituteId': currentInstituteId,
        'studentId': docId,
        'userId': effectiveUserId,
        'srNo': nextSrNo,
      };
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ addStudentManually: $e');
        debugPrint('$stackTrace');
      }
      return {'success': false, 'message': 'Failed to save student: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = normalizeLoginEmail(email);
    final lockAction = 'admin_password_login';
    try {
      final locked = await _securityOps.isLocked(
        identifier: normalizedEmail,
        actionType: lockAction,
      );
      if (locked) {
        return {
          'success': false,
          'message': 'Too many failed login attempts. Please try again later.',
          'isLocked': true,
        };
      }

      await _db.auth.signInWithPassword(email: normalizedEmail, password: password);
      final uid = _db.auth.currentUser!.id;

      if (kDebugMode) debugPrint('Login attempt - Email: $normalizedEmail, UID: $uid');

      final profile = await _findUserProfile(uid: uid, email: normalizedEmail);
      if (profile == null) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          metadata: {'reason': 'profile_not_found'},
        );
        await _db.auth.signOut();
        return {
          'success': false,
          'message':
              'We could not find an account for this sign-in. Confirm Institute ID / email / mobile matches registration. If you recently registered, wait for approval or contact your institute administrator.',
        };
      }

      final userData = profile['userData'] as Map<String, dynamic>;
      var instituteId = profile['instituteId'] as String?;
      final instituteName = profile['instituteName'] as String?;

      // ✅ SYNC PROFILE ON NEW DEVICE: Ensure institute_id is set correctly
      if (kDebugMode) {
        debugPrint('🏢 Institute ID check:');
        debugPrint('   Current value: $instituteId');
      }

      if (instituteId == null || instituteId.isEmpty) {
        // Try to find the correct institute_id from the profile record
        try {
          if (kDebugMode) debugPrint('   ⚠️ Institute ID missing - attempting to sync...');
          final dbProfile = await _db
              .from('profiles')
              .select('institute_id')
              .eq('id', uid)
              .maybeSingle();

          final dbInstituteId = (dbProfile?['institute_id'] as String?)?.trim();
          if (dbInstituteId != null && dbInstituteId.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('   ✅ Found in database: $dbInstituteId');
            }
            instituteId = dbInstituteId;
            profile['instituteId'] = dbInstituteId;
          } else {
            if (kDebugMode) debugPrint('   ❌ No institute_id found in database');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('   ⚠️ Error syncing institute_id: $e');
        }
      } else {
        if (kDebugMode) debugPrint('   ✅ Institute ID synced correctly');
      }

      if (userData.isEmpty) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'empty_user_data'},
        );
        await _db.auth.signOut();
        return {'success': false, 'message': 'User profile data is empty. Please register again.'};
      }

      String role = (userData['role'] ?? '').toString();
      final isAllowedRole = role == 'admin';
      if (!isAllowedRole) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'invalid_role', 'role': role},
        );
        await _db.auth.signOut();
        return {
          'success': false,
          'message':
              'Access denied. Only Admin can login in this app.\n\nYour role: $role',
        };
      }

      final status = (userData['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'approved' && status != 'active') {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'status_not_allowed', 'status': status},
        );
        await _db.auth.signOut();
        final pendingMsg = status == 'pending'
            ? 'Your registration is waiting for approval. An administrator at your institute must approve your account before you can sign in.'
            : 'Your account is not active yet (status: $status). Please contact your institute administrator to complete approval.';
        return {
          'success': false,
          'message': pendingMsg,
          'openAdminPortal': true,
        };
      }

      if (instituteId != null && instituteId.isNotEmpty) {
        if (kDebugMode) debugPrint('✅ User is admin of institute: $instituteId ($instituteName)');
      }

      await _securityOps.recordAttempt(
        identifier: normalizedEmail,
        actionType: lockAction,
        success: true,
        instituteId: instituteId,
      );

      unawaited(
        _db.from('profiles').update({
          'last_login': DateTime.now().toUtc().toIso8601String(),
          'last_login_ip': '192.168.1.1',
        }).eq('id', uid).catchError((e, _) {
          if (kDebugMode) debugPrint('Warning: Could not update lastLogin: $e');
        }),
      );

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': instituteId,
        'instituteName': instituteName,
        'userData': userData,
      };
    } on AuthException catch (e) {
      await _securityOps.recordAttempt(
        identifier: normalizedEmail,
        actionType: lockAction,
        success: false,
        metadata: {'reason': 'auth_exception'},
      );
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      await _securityOps.recordAttempt(
        identifier: normalizedEmail,
        actionType: lockAction,
        success: false,
        metadata: {'reason': 'unexpected_exception'},
      );
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  /// Institute instructors: Institute ID + PIN (4 digits). Up to four per institute; email resolved by PIN hash RPC.
  Future<Map<String, dynamic>> signInAttendanceStaff({
    required String instituteKey,
    required String pin,
  }) async {
    if (!isValidLoginPinLength(pin)) {
      return {'success': false, 'message': loginPinLengthMessage};
    }

    const lockAction = 'attendance_staff_login';
    final lockId = 'att_staff|${instituteKey.trim()}';

    try {
      final lockAndInst = await Future.wait<dynamic>([
        _securityOps.isLocked(
          identifier: lockId,
          actionType: lockAction,
        ),
        _db
            .from('institutes')
            .select('id')
            .or('id.eq.${instituteKey.trim()},institute_code.eq.${instituteKey.trim()}')
            .maybeSingle(),
      ]);
      final locked = lockAndInst[0] as bool;
      final inst = lockAndInst[1] as Map<String, dynamic>?;

      if (locked) {
        return {
          'success': false,
          'message': 'Too many failed attempts. Please try again later.',
          'isLocked': true,
        };
      }

      if (inst == null || inst['id'] == null) {
        await _securityOps.recordAttempt(
          identifier: lockId,
          actionType: lockAction,
          success: false,
          metadata: const {'reason': 'institute_not_found'},
        );
        return {'success': false, 'message': 'Institute not found'};
      }

      final canonicalId = (inst['id'] as String).trim();
      final pinHash = sha256.convert(utf8.encode(pin.trim())).toString();

      dynamic resolvedEmail;
      try {
        resolvedEmail = await _db.rpc(
          'resolve_attendance_staff_email',
          params: <String, dynamic>{
            'p_institute_id': canonicalId,
            'p_pin_hash': pinHash,
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('resolve_attendance_staff_email: $e');
        resolvedEmail = null;
      }
      final email = resolvedEmail?.toString().trim();
      if (email == null || email.isEmpty) {
        await _securityOps.recordAttempt(
          identifier: lockId,
          actionType: lockAction,
          success: false,
          metadata: const {'reason': 'invalid_staff_credentials'},
        );
        return {
          'success': false,
          'message':
              'Invalid Institute ID or PIN. Use the same Institute ID shown on the admin '
              'Instructor screen and the exact 4-digit PIN set when the instructor was added. '
              'If they were just created, pull to refresh the instructor list and try again.',
        };
      }

      final password = AttendanceStaffAuth.authPasswordFor(
        canonicalInstituteId: canonicalId,
        pin: pin,
      );

      await _db.auth.signInWithPassword(email: email, password: password);
      final uid = _db.auth.currentUser!.id;

      final profile =
          await _db.from('profiles').select('role, status, institute_id').eq('id', uid).maybeSingle();
      if (profile == null) {
        await _db.auth.signOut();
        await _securityOps.recordAttempt(
          identifier: lockId,
          actionType: lockAction,
          success: false,
        );
        return {'success': false, 'message': 'Profile not found'};
      }

      final role = (profile['role'] ?? '').toString();
      if (role != 'attendance_user') {
        await _db.auth.signOut();
        await _securityOps.recordAttempt(
          identifier: lockId,
          actionType: lockAction,
          success: false,
          metadata: {'reason': 'wrong_role', 'role': role},
        );
        return {
          'success': false,
          'message': 'This login is not registered as an institute instructor.',
        };
      }

      final st = (profile['status'] ?? '').toString().toLowerCase();
      if (st.isNotEmpty && st != 'approved' && st != 'active') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Account is not active.'};
      }

      await _securityOps.recordAttempt(
        identifier: lockId,
        actionType: lockAction,
        success: true,
        instituteId: canonicalId,
      );

      unawaited(
        _db.from('profiles').update({
          'last_login': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', uid).catchError((e, _) {}),
      );

      return {
        'success': true,
        'userId': uid,
        'email': email,
        'canonicalInstituteId': canonicalId,
        'role': role,
      };
    } on AuthException catch (e) {
      await _securityOps.recordAttempt(
        identifier: lockId,
        actionType: lockAction,
        success: false,
        metadata: const {'reason': 'auth_exception'},
      );
      if (kDebugMode) debugPrint('signInAttendanceStaff AuthException: ${e.message}');
      return {
        'success': false,
        'message':
            'Incorrect PIN for this institute, or the instructor account was not fully created. '
            'Use the Institute ID from the admin Instructor screen and the same 4-digit PIN. '
            'If this keeps failing, ask admin to remove the instructor and add them again.',
      };
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  Future<Map<String, dynamic>> createInstituteAttendanceUser({
    required String instituteKey,
    required String fullName,
    required String pin,
    required String firstName,
    required String middleName,
    required String lastName,
    required String mobile,
  }) async {
    if (!isValidLoginPinLength(pin)) {
      return {'success': false, 'message': loginPinLengthMessage};
    }
    final ft = firstName.trim();
    final mt = middleName.trim();
    final lt = lastName.trim();
    final mobileDigits = mobile.trim().replaceAll(RegExp(r'\D'), '');
    if (ft.isEmpty || mt.isEmpty || lt.isEmpty) {
      return {
        'success': false,
        'message': 'First name, middle name, and last name are all required.',
      };
    }
    if (mobileDigits.length < 10 || mobileDigits.length > 15) {
      return {'success': false, 'message': 'Enter a valid mobile number (10–15 digits).'};
    }

    final trimmedPin = pin.trim();
    final trimmedKey = instituteKey.trim();
    final pinInUseMsg =
        'This PIN is already in use in your institute. Use a different PIN for the institute instructor.';

    try {
      final inst = await _db
          .from('institutes')
          .select('id')
          .or('id.eq.$trimmedKey,institute_code.eq.$trimmedKey')
          .maybeSingle();

      if (inst == null || inst['id'] == null) {
        return {'success': false, 'message': 'Institute not found for that ID'};
      }

      final canonicalId = (inst['id'] as String).trim();
      final instituteCode = (inst['institute_code'] as String?)?.trim() ?? '';

      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        return {'success': false, 'message': 'Sign in again, then add the institute instructor.'};
      }

      final adminProfile = await _db.from('profiles').select('institute_id').eq('id', uid).maybeSingle();
      final adminIid = (adminProfile?['institute_id'] as String?)?.trim() ?? '';
      final adminCanonical = adminIid.isEmpty
          ? null
          : (await _db
                  .from('institutes')
                  .select('id')
                  .or('id.eq.$adminIid,institute_code.eq.$adminIid')
                  .maybeSingle())?['id']
              ?.toString()
              .trim();
      if (adminCanonical == null ||
          adminCanonical.isEmpty ||
          adminCanonical != canonicalId) {
        return {'success': false, 'message': 'You can only add users to your own institute'};
      }

      final pinHash = sha256.convert(utf8.encode(trimmedPin)).toString();
      final instituteKeyForRpc =
          instituteCode.isNotEmpty ? instituteCode : canonicalId;

      final pinTaken = await _db.rpc(
        'institute_instructor_pin_taken',
        params: {
          'p_institute_key': instituteKeyForRpc,
          'p_pin_hash': pinHash,
        },
      );
      if (pinTaken == true) {
        return {'success': false, 'message': pinInUseMsg};
      }

      const maxInstructors = 4;
      final countData = await _db.rpc(
        'count_institute_instructors',
        params: {'p_institute_key': instituteKeyForRpc},
      );
      final instructorCount = countData is int
          ? countData
          : int.tryParse(countData?.toString() ?? '') ?? 0;
      if (instructorCount >= maxInstructors) {
        return {
          'success': false,
          'message':
              'This institute already has $instructorCount instructor(s) (max $maxInstructors). '
              'Refresh the instructor list. If the list shows fewer, run the global instructor fix SQL in Supabase.',
        };
      }

      final fn = await _db.functions.invoke(
        'create-institute-attendance-user',
        body: {
          'instituteKey': trimmedKey,
          'fullName': fullName.trim(),
          'firstName': ft,
          'middleName': mt,
          'lastName': lt,
          'mobile': mobileDigits,
          'pin': trimmedPin,
        },
      );
      final raw = fn.data;
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        if (data['success'] == true) return data;
        return {
          'success': false,
          'message': data['error']?.toString() ??
              data['message']?.toString() ??
              'Could not create user',
        };
      }
      return {'success': false, 'message': 'Unexpected response from server'};
    } on FunctionException catch (e) {
      if (kDebugMode) debugPrint('createInstituteAttendanceUser: $e');
      final d = e.details;
      if (d is Map) {
        final err = d['error'] ?? d['message'];
        if (err != null && err.toString().trim().isNotEmpty) {
          return {'success': false, 'message': err.toString().trim()};
        }
      }
      if (d is String && d.trim().isNotEmpty) {
        return {'success': false, 'message': d.trim()};
      }
      if (e.status == 404) {
        return {
          'success': false,
          'message':
              'Institute instructor service is not available on this project. Deploy the Edge Function '
              '`create-institute-attendance-user` in Supabase Dashboard → Edge Functions.',
        };
      }
      return {
        'success': false,
        'message':
            'Could not create institute instructor (error ${e.status}). ${e.reasonPhrase ?? ''}'.trim(),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('createInstituteAttendanceUser: $e');
      final s = e.toString();
      if (s.contains('SocketException') ||
          s.contains('Failed host lookup') ||
          s.toLowerCase().contains('network')) {
        return {
          'success': false,
          'message': 'Network error. Check your connection and try again.',
        };
      }
      return {
        'success': false,
        'message': 'Could not create institute instructor: $s',
      };
    }
  }

  /// After attendance-staff password login, seed local PIN cache (same format as admin).
  Future<void> cachePinForAttendanceStaffLogin({
    required String email,
    required String pin,
    required String canonicalInstituteId,
  }) async {
    try {
      if (!isValidLoginPinLength(pin)) return;
      final authPassword = AttendanceStaffAuth.authPasswordFor(
        canonicalInstituteId: canonicalInstituteId,
        pin: pin,
      );
      final pinHash = sha256.convert(utf8.encode(pin)).toString();
      final enc = _encryptPassword(authPassword, pin);
      final prefs = await SharedPreferences.getInstance();
      final e = normalizeLoginEmail(email);
      await prefs.setString(_pinHashKey(e), pinHash);
      await prefs.setString(_encPassKey(e), enc);
      await prefs.setBool(_hasPinKey(e), true);
    } catch (e) {
      if (kDebugMode) debugPrint('cachePinForAttendanceStaffLogin: $e');
    }
  }

  Future<Map<String, dynamic>> signInWithId({
    required String userId,
    required String password,
    required String role,
  }) async {
    try {
      // App is admin-only. Ignore/deny any non-admin role-based login attempts.
      if (role != 'admin') {
        return {
          'success': false,
          'message': 'Access denied. Only Admin can login in this app.',
        };
      }

      final rows = await _db.from('profiles').select().eq('user_id', userId).eq('role', role).limit(1);

      if (rows.isEmpty) {
        return {'success': false, 'message': 'User ID not found'};
      }

      final row = rows.first;
      final email = row['email'] as String?;
      if (email == null || email.isEmpty) {
        return {'success': false, 'message': 'User has no email on file'};
      }

      await _db.auth.signInWithPassword(email: email, password: password);

      String userRole = (row['role'] ?? '').toString();
      if (userRole != 'admin') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied. Only Admin can login in this app.'};
      }

      final pid = row['id'].toString();
      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', pid);

      return {
        'success': true,
        'userId': pid,
        'role': row['role'],
        'userData': profileRowToUserData(row),
      };
    } on AuthException catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> setPIN({
    required String userId,
    required String pin,
  }) async {
    try {
      if (!isValidLoginPinLength(pin)) {
        return {'success': false, 'message': loginPinLengthMessage};
      }
      if (!RegExp(r'^\d+$').hasMatch(pin)) {
        return {'success': false, 'message': 'PIN must contain only digits'};
      }

      final pinHash = sha256.convert(utf8.encode(pin)).toString();

      await _db.from('profiles').update({
        'pin_hash': pinHash,
        'pin_set_at': DateTime.now().toUtc().toIso8601String(),
        'has_pin': true,
      }).eq('id', userId);

      return {'success': true, 'message': 'PIN set successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error setting PIN: $e');
      return {'success': false, 'message': 'Failed to set PIN: ${e.toString()}'};
    }
  }

  // ── Local cache keys ──────────────────────────────────────────────────────────
  static String _pinHashKey(String email) =>
      'msce_pin_hash_${normalizeLoginEmail(email)}';
  static String _encPassKey(String email) =>
      'msce_enc_pass_${normalizeLoginEmail(email)}';
  static String _hasPinKey(String email) =>
      'msce_has_pin_${normalizeLoginEmail(email)}';
  static String _bioEncPassKey(String email) =>
      'msce_bio_enc_pass_${normalizeLoginEmail(email)}';
  static const String _bioSecretKey = 'msce_biometric_login_secret';

  Future<String?> _readBiometricSecret(SharedPreferences prefs) async {
    final s = await SecureCredentialStore.read(_bioSecretKey);
    if (s != null && s.isNotEmpty) return s;
    final legacy = prefs.getString(_bioSecretKey);
    if (legacy != null && legacy.isNotEmpty) {
      await SecureCredentialStore.write(_bioSecretKey, legacy);
      await prefs.remove(_bioSecretKey);
      return legacy;
    }
    return null;
  }

  Future<String> _getOrCreateBiometricSecret(SharedPreferences prefs) async {
    final existing = await _readBiometricSecret(prefs);
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final secret = base64Encode(bytes);
    await SecureCredentialStore.write(_bioSecretKey, secret);
    return secret;
  }

  String _xorWithSecret(String value, String secret) {
    final valueBytes = utf8.encode(value);
    final secretBytes = base64Decode(secret);
    final encrypted = <int>[];
    for (int i = 0; i < valueBytes.length; i++) {
      encrypted.add(valueBytes[i] ^ secretBytes[i % secretBytes.length]);
    }
    return base64Encode(encrypted);
  }

  String _unxorWithSecret(String encryptedValue, String secret) {
    final encrypted = base64Decode(encryptedValue);
    final secretBytes = base64Decode(secret);
    final decrypted = <int>[];
    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ secretBytes[i % secretBytes.length]);
    }
    return utf8.decode(decrypted);
  }

  Future<String?> _getCachedPasswordForEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedPassword = prefs.getString(_bioEncPassKey(email));
      final secret = await _readBiometricSecret(prefs);
      if (encryptedPassword == null || encryptedPassword.isEmpty) return null;
      if (secret == null || secret.isEmpty) return null;
      return _unxorWithSecret(encryptedPassword, secret);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not load cached password for PIN reset: $e');
      return null;
    }
  }

  Future<void> cacheBiometricLogin({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final secret = await _getOrCreateBiometricSecret(prefs);
      await prefs.setString(_bioEncPassKey(email), _xorWithSecret(password, secret));
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not cache biometric login: $e');
    }
  }

  /// After PIN unlock, derive the account password and store for [signInWithBiometric].
  /// (Enabling biometrics on the lock screen has no password field — the PIN in the field is used.)
  Future<void> cacheBiometricSecretUsingCurrentPin({
    required String email,
    required String pin,
  }) async {
    if (email.trim().isEmpty || pin.isEmpty) return;
    try {
      final u = _db.auth.currentUser;
      if (u == null) return;
      final profile = await _findUserProfile(uid: u.id);
      if (profile == null) return;
      final userData = profile['userData'] as Map<String, dynamic>?;
      if (userData == null) return;
      final enc = userData['encryptedPassword'] as String?;
      if (enc == null || enc.isEmpty) return;
      final password = _decryptPassword(enc, pin);
      await cacheBiometricLogin(email: email, password: password);
    } catch (e) {
      if (kDebugMode) debugPrint('cacheBiometricSecretUsingCurrentPin: $e');
    }
  }

  /// When biometrics is enabled in prefs but the XOR password was never stored
  /// (e.g. new phone, or flag set without [cacheBiometricLogin]), fill it using the
  /// same PIN+profile sources as [signInWithPIN]. Works when signed out (login mode)
  /// if local PIN cache or an unauthenticated profile read matches the PIN.
  Future<bool> ensureBiometricCacheUsingPin({
    required String email,
    required String pin,
  }) async {
    if (email.trim().isEmpty || !isValidLoginPinLength(pin)) {
      return false;
    }
    if (!RegExp(r'^\d+$').hasMatch(pin)) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final bioSecretLen = (await _readBiometricSecret(prefs)) ?? '';
      if ((prefs.getString(_bioEncPassKey(email)) ?? '').isNotEmpty &&
          bioSecretLen.isNotEmpty) {
        return true;
      }

      final u = _db.auth.currentUser;
      if (u != null) {
        await cacheBiometricSecretUsingCurrentPin(email: email, pin: pin);
        final p2 = await SharedPreferences.getInstance();
        if ((p2.getString(_bioEncPassKey(email)) ?? '').isNotEmpty) {
          return true;
        }
      }

      final providedPinHash = sha256.convert(utf8.encode(pin)).toString();
      final cachedPinHash = prefs.getString(_pinHashKey(email));
      final cachedEncPass = prefs.getString(_encPassKey(email));
      if (cachedPinHash != null &&
          cachedEncPass != null &&
          providedPinHash == cachedPinHash) {
        final password = _decryptPassword(cachedEncPass, pin);
        await cacheBiometricLogin(email: email, password: password);
        return true;
      }

      final profile = await _findUserProfile(email: email);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      if (userData['hasPIN'] != true) return false;
      final storedPinHash = userData['pinHash'] as String?;
      if (storedPinHash == null || providedPinHash != storedPinHash) {
        return false;
      }
      final enc = userData['encryptedPassword'] as String?;
      if (enc == null || enc.isEmpty) return false;
      final password = _decryptPassword(enc, pin);
      await cacheBiometricLogin(email: email, password: password);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('ensureBiometricCacheUsingPin: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> signInWithBiometric({
    required String email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedPassword = prefs.getString(_bioEncPassKey(email));
      final secret = await _readBiometricSecret(prefs);

      if (encryptedPassword == null || secret == null) {
        return {
          'success': false,
          'message': 'Biometric login is not ready yet. Login with password once, then enable biometric again.',
        };
      }

      final password = _unxorWithSecret(encryptedPassword, secret);
      return await signInWithEmail(email: email, password: password);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Biometric login error: $e');
      return {
        'success': false,
        'message': 'Biometric login failed. Please login with PIN or password once.',
      };
    }
  }

  Future<bool> hasPIN(String userId) async {
    try {
      final profile = await _findUserProfile(uid: userId);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      return userData['hasPIN'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Check if a PIN is set for the given email.
  /// First checks the local cache (works offline / without auth),
  /// then falls back to a DB lookup.
  Future<bool> hasPINForEmail(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_hasPinKey(email)) == true) return true;
      // fallback: try DB (may fail if unauthenticated due to RLS)
      final profile = await _findUserProfile(email: email);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      return userData['hasPIN'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyPIN(String userId, String pin) async {
    try {
      final profile = await _findUserProfile(uid: userId);
      if (profile == null) return false;
      final userData = profile['userData'] as Map<String, dynamic>;
      final storedPinHash = userData['pinHash'] as String?;
      if (storedPinHash == null) return false;
      final providedPinHash = sha256.convert(utf8.encode(pin)).toString();
      return providedPinHash == storedPinHash;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> signInWithPIN({
    required String email,
    required String pin,
  }) async {
    final normalizedEmail = normalizeLoginEmail(email);
    final lockAction = 'admin_pin_login';
    try {
      if (kDebugMode) {
        debugPrint('🔐 PIN LOGIN ATTEMPT');
        debugPrint('   Email: $normalizedEmail');
        debugPrint('   PIN length: ${pin.length}');
      }

      if (!isValidLoginPinLength(pin)) {
        return {'success': false, 'message': loginPinLengthMessage};
      }

      // ✅ PRODUCTION: Check account lock status
      final locked = await _securityOps.isLocked(
        identifier: normalizedEmail,
        actionType: lockAction,
      );
      if (locked) {
        if (kDebugMode) debugPrint('   ❌ Account locked - too many failed attempts');
        return {
          'success': false,
          'message': 'PIN login temporarily locked due to repeated failed attempts. Try again in 15 minutes.',
          'isLocked': true,
        };
      }

      // ── Try local cache first (avoids DB query before auth / RLS issues) ──────
      final prefs = await SharedPreferences.getInstance();
      final cachedPinHash    = prefs.getString(_pinHashKey(normalizedEmail));
      final cachedEncPass    = prefs.getString(_encPassKey(normalizedEmail));
      final providedPinHash  = sha256.convert(utf8.encode(pin)).toString();

      if (kDebugMode) {
        debugPrint('   🔍 Checking cached PIN...');
        debugPrint('   Cached hash exists: ${cachedPinHash != null}');
        debugPrint('   Cached password exists: ${cachedEncPass != null}');
      }

      if (cachedPinHash != null && cachedEncPass != null) {
        // ── Local PIN verification path ─────────────────────────────────────────
        if (providedPinHash != cachedPinHash) {
          if (kDebugMode) {
            debugPrint('   ❌ PIN MISMATCH');
            debugPrint('   Expected hash: $cachedPinHash');
            debugPrint('   Provided hash: $providedPinHash');
          }
          await _securityOps.recordAttempt(
            identifier: normalizedEmail,
            actionType: lockAction,
            success: false,
            metadata: {'reason': 'invalid_pin_cached_path'},
          );

          // Check attempt count and return remaining attempts
          final attempts = await _securityOps.getFailedAttemptCount(
            identifier: normalizedEmail,
            actionType: lockAction,
          );
          final remaining = 5 - attempts;
          final message = remaining > 0
              ? 'Invalid PIN. $remaining attempt${remaining == 1 ? '' : 's'} remaining.'
              : 'Too many failed attempts. Account locked for 15 minutes.';

          return {
            'success': false,
            'message': message,
            'attemptsRemaining': remaining,
            'isLocked': remaining <= 0,
          };
        }

        if (kDebugMode) debugPrint('   ✅ PIN VERIFIED - Decrypting password...');

        final password = _decryptPassword(cachedEncPass, pin);
        if (kDebugMode) debugPrint('   ✅ Password decrypted');

        try {
          if (kDebugMode) debugPrint('   🔑 Signing in with Supabase auth...');
          await _db.auth.signInWithPassword(email: normalizedEmail, password: password);
          if (kDebugMode) debugPrint('   ✅ Supabase auth successful');
        } on AuthException catch (e) {
          if (kDebugMode) debugPrint('   ❌ Auth exception: ${e.message}');
          await _securityOps.recordAttempt(
            identifier: normalizedEmail,
            actionType: lockAction,
            success: false,
            metadata: {'reason': 'auth_exception_cached_path'},
          );
          return {'success': false, 'message': ErrorHandler.handleAuthException(e)};
        }

        // Now authenticated — fetch profile
        final uid = _db.auth.currentUser?.id;
        if (kDebugMode) debugPrint('   👤 User ID: $uid');
        if (uid == null) {
          if (kDebugMode) debugPrint('   ❌ User ID is null after auth');
          return {'success': false, 'message': 'Authentication failed'};
        }

        if (kDebugMode) debugPrint('   📋 Fetching user profile...');
        final profile = await _findUserProfile(uid: uid, email: normalizedEmail);
        if (profile == null) {
          if (kDebugMode) debugPrint('   ❌ Profile not found for user');
          await _securityOps.recordAttempt(
            identifier: normalizedEmail,
            actionType: lockAction,
            success: false,
            metadata: {'reason': 'profile_not_found_cached_path'},
          );
          await _db.auth.signOut();
          return {'success': false, 'message': 'User profile not found'};
        }

        if (kDebugMode) debugPrint('   ✅ Profile found');

        // ✅ SYNC PROFILE ON NEW DEVICE: Ensure institute_id is set correctly
        final instituteId = profile['instituteId'] as String?;
        if (kDebugMode) {
          debugPrint('   🏢 Institute ID check:');
          debugPrint('      Current value: $instituteId');
        }

        if (instituteId == null || instituteId.isEmpty) {
          // Try to find the correct institute_id from the admin record
          try {
            if (kDebugMode) debugPrint('      ⚠️ Institute ID missing - attempting to sync...');
            final adminData = await _db
                .from('profiles')
                .select('institute_id')
                .eq('id', uid)
                .maybeSingle();

            final dbInstituteId = (adminData?['institute_id'] as String?)?.trim();
            if (dbInstituteId != null && dbInstituteId.isNotEmpty) {
              if (kDebugMode) {
                debugPrint('      ✅ Found in database: $dbInstituteId');
              }
              profile['instituteId'] = dbInstituteId;
            } else {
              if (kDebugMode) debugPrint('      ❌ No institute_id found in database');
            }
          } catch (e) {
            if (kDebugMode) debugPrint('      ⚠️ Error syncing institute_id: $e');
          }
        } else {
          if (kDebugMode) debugPrint('      ✅ Institute ID synced correctly');
        }

        final userData = profile['userData'] as Map<String, dynamic>;
        final serverHasPin = userData['hasPIN'] == true;
        final serverPinHash = userData['pinHash'] as String?;
        if (!serverHasPin || serverPinHash == null || serverPinHash.isEmpty) {
          await _clearLocalPinCache(normalizedEmail);
          await _db.auth.signOut();
          return {
            'success': false,
            'message': 'PIN was reset for this account. Please login with password and set a new PIN.',
            'requiresPasswordLogin': true,
          };
        }
        final role = (userData['role'] ?? '').toString();
        if (kDebugMode) debugPrint('   👑 Role: $role');
        if (role != 'admin' && role != 'attendance_user') {
          if (kDebugMode) debugPrint('   ❌ Role not allowed');
          await _securityOps.recordAttempt(
            identifier: normalizedEmail,
            actionType: lockAction,
            success: false,
            metadata: {'reason': 'invalid_role_cached_path', 'role': role},
          );
          await _db.auth.signOut();
          return {'success': false, 'message': 'Access denied for this account type.'};
        }

        final status = (userData['status'] ?? '').toString().toLowerCase();
        if (kDebugMode) debugPrint('   📌 Status: $status');
        if (status.isNotEmpty && status != 'approved' && status != 'active') {
          if (kDebugMode) debugPrint('   ❌ Account not approved - status: $status');
          await _securityOps.recordAttempt(
            identifier: normalizedEmail,
            actionType: lockAction,
            success: false,
            metadata: {'reason': 'status_not_allowed_cached_path', 'status': status},
          );
          await _db.auth.signOut();
          return {
            'success': false,
            'message': 'Your account is not approved yet. Current status: $status.',
            'openAdminPortal': true,
          };
        }

        if (kDebugMode) debugPrint('   ⏰ Updating last_login...');
        await _db.from('profiles').update({
          'last_login': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', uid);

        if (kDebugMode) debugPrint('   📊 Recording successful login...');
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: true,
          instituteId: profile['instituteId'] as String?,
        );

        if (kDebugMode) {
          debugPrint('✅✅✅ PIN LOGIN SUCCESSFUL ✅✅✅');
          debugPrint('   User: $normalizedEmail');
          debugPrint('   Role: $role');
        }

        return {
          'success': true,
          'userId': uid,
          'role': userData['role'],
          'userData': userData,
        };
      }

      // ── Fallback: DB path (requires profiles to be readable without auth) ─────
      final profile = await _findUserProfile(email: normalizedEmail);
      if (profile == null) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          metadata: {'reason': 'profile_not_found_db_path'},
        );
        return {'success': false, 'message': 'User not found. Please login with password first to set your PIN.'};
      }

      final userData = profile['userData'] as Map<String, dynamic>;
      final uid = userData['uid'] as String? ?? profile['profileId'] as String;
      final instituteId = profile['instituteId'] as String? ?? userData['instituteId'] as String?;

      if (userData['hasPIN'] != true) {
        return {'success': false, 'message': 'PIN not set. Please login with password first to set PIN.'};
      }

      final storedPinHash = userData['pinHash'] as String?;
      if (storedPinHash == null) {
        return {'success': false, 'message': 'PIN not configured'};
      }

      if (providedPinHash != storedPinHash) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'invalid_pin_db_path'},
        );
        return {'success': false, 'message': 'Invalid PIN'};
      }

      final encryptedPassword = userData['encryptedPassword'] as String?;
      final rolePre = (userData['role'] ?? '').toString();

      late final String password;
      if (rolePre == 'attendance_user' &&
          (encryptedPassword == null || encryptedPassword.isEmpty)) {
        if (instituteId == null || instituteId.isEmpty) {
          return {
            'success': false,
            'message': 'Institute instructor profile is incomplete. Contact your institute admin.',
          };
        }
        password = AttendanceStaffAuth.authPasswordFor(
          canonicalInstituteId: instituteId,
          pin: pin,
        );
      } else {
        if (encryptedPassword == null || encryptedPassword.isEmpty) {
          return {'success': false, 'message': 'Please login with password first to enable PIN login'};
        }
        password = _decryptPassword(encryptedPassword, pin);
      }

      try {
        await _db.auth.signInWithPassword(email: normalizedEmail, password: password);
      } on AuthException catch (e) {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'auth_exception_db_path'},
        );
        return {'success': false, 'message': ErrorHandler.handleAuthException(e)};
      }

      final instituteName = profile['instituteName'] as String? ?? userData['instituteName'] as String?;

      final role = (userData['role'] ?? '').toString();
      if (role != 'admin' && role != 'attendance_user') {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'invalid_role_db_path', 'role': role},
        );
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied for this account type.'};
      }
      final status = (userData['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'approved' && status != 'active') {
        await _securityOps.recordAttempt(
          identifier: normalizedEmail,
          actionType: lockAction,
          success: false,
          instituteId: instituteId,
          metadata: {'reason': 'status_not_allowed_db_path', 'status': status},
        );
        await _db.auth.signOut();
        final pendingMsg = status == 'pending'
            ? 'Your registration is waiting for approval. An administrator at your institute must approve your account before you can sign in.'
            : 'Your account is not active yet (status: $status). Please contact your institute administrator to complete approval.';
        return {
          'success': false,
          'message': pendingMsg,
          'openAdminPortal': true,
        };
      }

      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', uid);

      await _securityOps.recordAttempt(
        identifier: normalizedEmail,
        actionType: lockAction,
        success: true,
        instituteId: instituteId,
      );

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': instituteId,
        'instituteName': instituteName,
        'userData': userData,
      };
    } catch (e) {
      await _securityOps.recordAttempt(
        identifier: normalizedEmail,
        actionType: lockAction,
        success: false,
        metadata: {'reason': 'unexpected_exception'},
      );
      if (kDebugMode) debugPrint('❌ PIN login error: $e');
      return {'success': false, 'message': 'PIN login failed: ${e.toString()}'};
    }
  }

  Future<void> _clearLocalPinCache(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedEmail = normalizeLoginEmail(email);
      await prefs.remove(_pinHashKey(normalizedEmail));
      await prefs.remove(_encPassKey(normalizedEmail));
      await prefs.remove(_hasPinKey(normalizedEmail));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> setPINWithPassword({
    required String userId,
    required String pin,
    required String password,
    String? email,
  }) async {
    try {
      if (!isValidLoginPinLength(pin)) {
        return {'success': false, 'message': loginPinLengthMessage};
      }
      if (!RegExp(r'^\d+$').hasMatch(pin)) {
        return {'success': false, 'message': 'PIN must contain only digits'};
      }

      final pinHash = sha256.convert(utf8.encode(pin)).toString();
      final encryptedPassword = _encryptPassword(password, pin);

      final profile = await _findUserProfile(uid: userId);
      if (profile == null) {
        return {'success': false, 'message': 'User profile not found for PIN setup'};
      }
      final profileId = profile['profileId'] as String;
      await _db.from('profiles').update({
        'pin_hash': pinHash,
        'encrypted_password': encryptedPassword,
        'pin_set_at': DateTime.now().toUtc().toIso8601String(),
        'has_pin': true,
      }).eq('id', profileId);

      // ── Cache PIN data locally so PIN login works without a DB query ──────────
      final rawEmail = email?.trim() ??
          (profile['userData'] as Map<String, dynamic>?)?['email'] as String? ??
          _db.auth.currentUser?.email;
      if (rawEmail != null && rawEmail.isNotEmpty) {
        final emailToCache = normalizeLoginEmail(rawEmail);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_pinHashKey(emailToCache), pinHash);
          await prefs.setString(_encPassKey(emailToCache), encryptedPassword);
          await prefs.setBool(_hasPinKey(emailToCache), true);
        } catch (_) {}
      }

      return {'success': true, 'message': 'PIN set successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to set PIN: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> clearPinForEmail(String email) async {
    try {
      final normalizedEmail = normalizeLoginEmail(email);
      if (normalizedEmail.isEmpty) {
        return {'success': false, 'message': 'Email is required'};
      }

      final profile = await _findUserProfile(email: normalizedEmail);
      if (profile == null) {
        return {'success': false, 'message': 'Account not found'};
      }

      final profileId = profile['profileId'] as String?;
      if (profileId == null || profileId.isEmpty) {
        return {'success': false, 'message': 'Profile not found'};
      }

      await _db.from('profiles').update({
        'pin_hash': null,
        'encrypted_password': null,
        'pin_set_at': null,
        'has_pin': false,
      }).eq('id', profileId);

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pinHashKey(normalizedEmail));
        await prefs.remove(_encPassKey(normalizedEmail));
        await prefs.remove(_hasPinKey(normalizedEmail));
      } catch (_) {}

      return {'success': true, 'message': 'PIN cleared successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to clear PIN: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> clearPinForUser({
    required String userId,
    String? email,
  }) async {
    try {
      if (userId.trim().isEmpty) {
        return {'success': false, 'message': 'User ID is required'};
      }

      final profile = await _findUserProfile(uid: userId.trim());
      if (profile == null) {
        return {'success': false, 'message': 'Account not found'};
      }

      final profileId = profile['profileId'] as String?;
      if (profileId == null || profileId.isEmpty) {
        return {'success': false, 'message': 'Profile not found'};
      }

      await _db.from('profiles').update({
        'pin_hash': null,
        'encrypted_password': null,
        'pin_set_at': null,
        'has_pin': false,
      }).eq('id', profileId);

      final normalizedEmail = email?.trim().toLowerCase();
      if (normalizedEmail != null && normalizedEmail.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(_pinHashKey(normalizedEmail));
          await prefs.remove(_encPassKey(normalizedEmail));
          await prefs.remove(_hasPinKey(normalizedEmail));
        } catch (_) {}
      }

      return {'success': true, 'message': 'PIN cleared successfully'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to clear PIN: ${e.toString()}'};
    }
  }

  /// After password login on a new device, copy server [pin_hash] and [encrypted_password]
  /// into local prefs so the same PIN works here without forcing "set new PIN" again.
  Future<void> syncLocalPinCacheAfterPasswordLogin({
    required String email,
    required Map<String, dynamic> userData,
  }) async {
    try {
      if (userData['hasPIN'] != true) return;
      final ph = userData['pinHash'];
      final ep = userData['encryptedPassword'];
      final pinHash = ph is String ? ph : ph?.toString();
      final encPass = ep is String ? ep : ep?.toString();
      if (pinHash == null || pinHash.isEmpty || encPass == null || encPass.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'syncLocalPinCache: hasPIN on server but missing hash/enc pass — use password login once or set PIN to refresh.',
          );
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final e = email.trim();
      await prefs.setString(_pinHashKey(e), pinHash);
      await prefs.setString(_encPassKey(e), encPass);
      await prefs.setBool(_hasPinKey(e), true);
      if (kDebugMode) {
        debugPrint('✅ Local PIN cache synced for $e (use same PIN on this device).');
      }
    } catch (err) {
      if (kDebugMode) debugPrint('syncLocalPinCacheAfterPasswordLogin: $err');
    }
  }

  Future<Map<String, dynamic>> resetPIN({
    required String email,
    required String password,
    required String newPin,
  }) async {
    try {
      final authResult = await signInWithEmail(email: email, password: password);
      if (authResult['success'] != true) {
        return authResult;
      }

      final userId = authResult['userId'] as String;

      return await setPINWithPassword(
        userId: userId,
        pin: newPin,
        password: password,
      );
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset PIN: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> resetPinWithOtp({
    required String email,
    required String otp,
    required String newPin,
  }) async {
    try {
      final key = _loginEmailOtpKey(email);
      final otpResult = await verifyForgotPinOtp(key, otp);
      if (otpResult['success'] != true) {
        return otpResult;
      }

      final cachedPassword = await _getCachedPasswordForEmail(key);
      if (cachedPassword == null || cachedPassword.isEmpty) {
        return {
          'success': false,
          'message':
              'PIN reset is not ready on this device yet. Complete one full password login on this device first, then Forgot PIN will work here.',
        };
      }

      final authResult = await signInWithEmail(email: key, password: cachedPassword);
      if (authResult['success'] != true) {
        return authResult;
      }

      final userId = authResult['userId'] as String?;
      if (userId == null || userId.isEmpty) {
        return {'success': false, 'message': 'Could not verify this account'};
      }

      final resetResult = await setPINWithPassword(
        userId: userId,
        pin: newPin,
        password: cachedPassword,
        email: key,
      );
      if (resetResult['success'] == true) {
        _forgotPinOtpStorage.remove(key);
        _forgotPinOtpExpiryEpoch.remove(key);
        await cacheBiometricLogin(email: key, password: cachedPassword);
      }
      return resetResult;
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset PIN: ${e.toString()}'};
    }
  }

  String _encryptPassword(String password, String pin) {
    final passwordBytes = utf8.encode(password);
    final pinBytes = utf8.encode(pin);
    final encrypted = <int>[];
    for (int i = 0; i < passwordBytes.length; i++) {
      encrypted.add(passwordBytes[i] ^ pinBytes[i % pinBytes.length]);
    }
    return base64Encode(encrypted);
  }

  String _decryptPassword(String encryptedPassword, String pin) {
    final encrypted = base64Decode(encryptedPassword);
    final pinBytes = utf8.encode(pin);
    final decrypted = <int>[];
    for (int i = 0; i < encrypted.length; i++) {
      decrypted.add(encrypted[i] ^ pinBytes[i % pinBytes.length]);
    }
    return utf8.decode(decrypted);
  }

  Future<Map<String, dynamic>> sendOTP(String userId) async {
    try {
      final key = _loginEmailOtpKey(userId);
      if (key.isEmpty || !key.contains('@')) {
        return {
          'success': false,
          'message': 'A valid email is required to send an OTP.',
        };
      }

      final otp = _generateOTP();

      // TRY 1: Send via Brevo Transactional API (no contact list issues)
      final sentViaTransactional = await _sendOTPViaBrevoTransactional(key, otp);

      if (sentViaTransactional) {
        _otpStorage[key] = otp;
        return {'success': true, 'message': 'OTP sent to your email'};
      }

      if (kDebugMode) debugPrint('⚠️ Brevo transactional failed, trying Edge Function...');

      // FALLBACK: Use Edge Function
      dynamic raw;
      try {
        final fn = await _db.functions.invoke(
          'email-otp',
          body: {
            'mode': 'otp',
            'to': key,
            'otp': otp,
            'purpose': 'Verification',
          },
        );
        raw = fn.data;
      } on FunctionException catch (e) {
        if (kDebugMode) debugPrint('email-otp failed: $e');
        return {'success': false, 'message': _emailOtpInvokeFailure(e)};
      } catch (e) {
        if (kDebugMode) debugPrint('email-otp failed: $e');
        return {'success': false, 'message': 'Could not reach email service.'};
      }

      final parsed = _parseEmailOtpInvokeResult(raw);
      if (!parsed.ok) {
        return {'success': false, 'message': parsed.errorMessage ?? 'Email send failed'};
      }

      _otpStorage[key] = otp;
      return {'success': true, 'message': 'OTP sent to your email'};
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP'};
    }
  }

  /// Send OTP via Brevo Transactional API (bypasses contact list, works with any email)
  Future<bool> _sendOTPViaBrevoTransactional(String email, String otp) async {
    try {
      final brevoKey = String.fromEnvironment('BREVO_API_KEY', defaultValue: '');
      if (brevoKey.isEmpty) {
        if (kDebugMode) debugPrint('❌ BREVO_API_KEY not set in environment');
        return false;
      }

      final response = await http.post(
        Uri.parse('https://api.brevo.com/v3/smtp/email'),
        headers: {
          'accept': 'application/json',
          'api-key': brevoKey,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'sender': {'name': 'MSCE Attendance App', 'email': 'noreply@msce-attendance.com'},
          'to': [{'email': email}],
          'subject': 'Your OTP for MSCE Attendance App',
          'htmlContent': '''
            <h2>Your OTP: <strong>$otp</strong></h2>
            <p>This OTP is valid for 10 minutes.</p>
            <p>Do not share this OTP with anyone.</p>
          '''
        }),
      );

      if (response.statusCode == 201) {
        if (kDebugMode) debugPrint('✅ OTP sent via Brevo transactional API to $email');
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ Brevo transactional API error: ${response.statusCode}');
          debugPrint('   Response: ${response.body}');
        }
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error sending OTP via Brevo: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> verifyOTP({
    required String userId,
    required String otp,
  }) async {
    final key = _loginEmailOtpKey(userId);
    final storedOtp = _otpStorage[key];
    final entered = otp.trim();
    if (storedOtp == null || storedOtp != entered) {
      return {'success': false, 'message': 'Invalid or expired OTP'};
    }
    _otpStorage.remove(key);
    return {'success': true, 'message': 'OTP verified'};
  }

  Future<void> signOut() async {
    try {
      await _db.auth.signOut();
    } catch (e) {
      if (kDebugMode) debugPrint('Error signing out: $e');
    }
  }

  Future<Map<String, dynamic>> sendRegistrationOTP(String mobile) async {
    try {
      if (mobile.isEmpty || mobile.length != 10) {
        return {'success': false, 'message': 'Invalid mobile number. Must be 10 digits'};
      }

      return {
        'success': false,
        'message': 'SMS verification is not enabled for this build.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to send OTP: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> verifyRegistrationOTP({
    required String verificationId,
    required String otp,
    required String mobile,
  }) async {
    final exp = _registrationOtpExpiryEpoch[verificationId];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (exp != null && now > exp) {
      _registrationOtpStorage.remove(verificationId);
      _registrationOtpExpiryEpoch.remove(verificationId);
      _verificationIdStorage.remove(mobile);
      return {'success': false, 'message': 'OTP expired. Request a new code.'};
    }

    final storedOtp = _registrationOtpStorage[verificationId];

    if (storedOtp == null) {
      return {'success': false, 'message': 'Invalid verification ID or OTP expired'};
    }

    if (storedOtp != otp) {
      return {'success': false, 'message': 'Invalid OTP'};
    }

    _registrationOtpStorage.remove(verificationId);
    _registrationOtpExpiryEpoch.remove(verificationId);
    _verificationIdStorage.remove(mobile);

    return {'success': true, 'message': 'OTP verified successfully'};
  }

  Future<Map<String, dynamic>> registerInstituteUser({
    required String instituteId,
    required String instituteName,
    required String name,
    required String email,
    required String password,
    required String mobile,
    String? inviteId,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      // ✅ Check if admin already registered
      try {
        final existingProfiles = await _db
            .from('profiles')
            .select('name, email, institute_id')
            .eq('email', email.trim().toLowerCase())
            .limit(1);

        if (existingProfiles.isNotEmpty) {
          final profile = existingProfiles.first as Map<String, dynamic>;
          final adminName = profile['name']?.toString() ?? 'Admin';
          return {
            'success': false,
            'message': '✅ Admin registration already done!\n\nAdmin: $adminName\nInstitute: $instituteName\n\nPlease login with your credentials.',
            'alreadyRegistered': true,
          };
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Admin check error (non-critical): $e');
      }

      // RLS often blocks pre-signup duplicate checks for anonymous users; Auth enforces unique email.

      final userDataMap = <String, dynamic>{
        'name': name,
        'institute_id': instituteId,
        'institute_name': instituteName,
        'phone_number': mobile,
      };
      if (inviteId != null && inviteId.isNotEmpty) {
        userDataMap['invite_id'] = inviteId;
      }
      userDataMap['website_invite'] = 'true';

      final res = await _db.auth.signUp(
        email: email,
        password: password,
        data: userDataMap,
      );
      final user = res.user;
      if (user == null) {
        return {'success': false, 'message': 'Could not create account'};
      }
      final uid = user.id;

      // profiles + user_credentials + user_count are created by trigger
      // public.handle_institute_admin_signup (migration 012) so this works even when
      // email confirmation is ON and signUp returns no session (RLS would block client inserts).

      if (kDebugMode) {
        debugPrint(
          '📧 Institute admin signup $email / $instituteName — session: ${res.session != null}',
        );
      }

      await _db.auth.signOut();

      // Best-effort: registration credentials (non-invite signups). Invite flow uses Institute ID on app.
      if (inviteId == null || inviteId.isEmpty) {
        try {
          await _db.functions.invoke(
            'email-otp',
            body: {
              'mode': 'credentials',
              'to': email.trim().toLowerCase(),
              'username': email.trim().toLowerCase(),
              'password': password,
              'instituteName': instituteName,
            },
          );
        } on FunctionException catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ credentials email failed: ${_emailOtpInvokeFailure(e)}');
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ credentials email send failed: $e');
        }
      }

      final needsEmailConfirm = res.session == null;
      return {
        'success': true,
        'message': needsEmailConfirm
            ? 'Account created. If your project requires email confirmation, open the verification link, then sign in with your Institute ID and password.'
            : 'Account created. Sign in with your Institute ID (or code) and the password you set.',
        'userId': uid,
        'needsEmailConfirmation': needsEmailConfirm,
        'pendingApproval': false,
      };
    } on AuthException catch (e) {
      final lower = e.toString().toLowerCase();

      if (lower.contains('over_email_send_rate_limit') ||
          lower.contains('email rate limit exceeded') ||
          lower.contains('statuscode: 429')) {
        return {
          'success': false,
          'message':
              'Too many signup email requests were sent. Please wait a few minutes and try again, or use a different test email.',
        };
      }

      if (lower.contains('user_already_exists') || lower.contains('already registered')) {
        return {
          'success': false,
          'message':
              'This email is already in use. Try signing in or use “Forgot password”. If you need a separate admin account, use a different email address.',
        };
      }

      return ErrorHandler.formatErrorForUI(e, context: 'registerInstituteUser', appType: 'admin');
    } catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'registerInstituteUser', appType: 'admin');
    }
  }

  Future<Map<String, dynamic>> initializeDefaultInstitutes() async {
    try {
      await DatabaseInitService.ensureInitialized();

      if (kDebugMode) debugPrint('📚 Initializing default institutes...');
      List<String> created = [];
      List<String> skipped = [];

      Future<void> upsert(String id, Map<String, dynamic> row) async {
        final ex = await _db.from('institutes').select('id').eq('id', id).maybeSingle();
        if (ex != null) {
          skipped.add(id);
          return;
        }
        await _db.from('institutes').insert(row);
        created.add(id);
      }

      await upsert('00000', {
        'id': '00000',
        'institute_code': '00000',
        'name': 'MSCE Pune',
        'location': 'Pune',
        'address': 'Pune',
        'city': 'Pune',
        'district': 'Pune',
        'taluka': 'Haveli',
        'state': 'Maharashtra',
        'country': 'India',
        'mobile_no': '8329012808',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      await upsert('dummy01', {
        'id': 'dummy01',
        'institute_code': '',
        'name': 'Lakshya Institute',
        'location': 'Dombivali West',
        'address': 'Dombivali West',
        'city': 'Mumbai',
        'district': '',
        'taluka': '',
        'state': 'Maharashtra',
        'country': 'India',
        'mobile_no': '',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      return {
        'success': true,
        'message': 'Institutes initialized successfully',
        'created': created,
        'skipped': skipped,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error initializing institutes: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> createInstitute({
    required String instituteId,
    required String name,
    String? instituteCode,
    String? location,
    String? address,
    String? city,
    String? district,
    String? taluka,
    String? state,
    String? country,
    String? mobileNo,
  }) async {
    try {
      await DatabaseInitService.ensureInitialized();

      final existingById = await _db.from('institutes').select('id').eq('id', instituteId).maybeSingle();
      if (existingById != null) {
        return {'success': false, 'message': 'Institute with this ID already exists'};
      }

      if (instituteCode != null && instituteCode.isNotEmpty) {
        final existingByCode = await _db
            .from('institutes')
            .select('id')
            .eq('institute_code', instituteCode)
            .maybeSingle();
        if (existingByCode != null) {
          return {'success': false, 'message': 'Institute with this code already exists'};
        }
      }

      await _db.from('institutes').insert({
        'id': instituteId,
        'institute_code': instituteCode ?? '',
        'name': name,
        'location': location ?? '',
        'address': address ?? '',
        'city': city ?? '',
        'district': district ?? '',
        'taluka': taluka ?? '',
        'state': state ?? '',
        'country': country ?? 'India',
        'mobile_no': mobileNo ?? '',
        'is_active': true,
        'user_count': 0,
        'student_count': 0,
      });

      return {
        'success': true,
        'message': 'Institute created successfully',
        'instituteId': instituteId,
      };
    } catch (e) {
      return {'success': false, 'message': 'Error creating institute: ${e.toString()}'};
    }
  }

  Future<Map<String, dynamic>> signInWithEmailAndInstitute({
    required String email,
    required String password,
    String? instituteId,
  }) async {
    try {
      await _db.auth.signInWithPassword(email: email, password: password);
      final uid = _db.auth.currentUser!.id;

      final row = await _db.from('profiles').select().eq('id', uid).maybeSingle();
      if (row == null) {
        await _db.auth.signOut();
        return {'success': false, 'message': 'User not found'};
      }

      final userData = profileRowToUserData(row);
      final userInstituteId = row['institute_id'] as String?;

      if (instituteId != null && userInstituteId != instituteId) {
        await _db.auth.signOut();
        return {'success': false, 'message': 'User does not belong to this institute'};
      }

      String role = (userData['role'] ?? '').toString();
      if (role != 'admin') {
        await _db.auth.signOut();
        return {'success': false, 'message': 'Access denied. Only Admin can login in this app.'};
      }

      await _db.from('profiles').update({
        'last_login': DateTime.now().toUtc().toIso8601String(),
        'last_login_ip': '192.168.1.1',
      }).eq('id', uid);

      return {
        'success': true,
        'userId': uid,
        'role': userData['role'],
        'instituteId': userInstituteId,
        'instituteName': row['institute_name'],
        'userData': userData,
      };
    } on AuthException catch (e) {
      return ErrorHandler.formatErrorForUI(e, context: 'signInWithEmail', appType: 'admin');
    } catch (e) {
      return {'success': false, 'message': 'Login failed: ${e.toString()}'};
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════════
  // NEW: INSTITUTE-BASED ADMIN AUTHENTICATION (Institute ID + Password)
  // ═══════════════════════════════════════════════════════════════════════════════

  /// Get all pending admin invites (for app registration flow)
  Future<Map<String, dynamic>> getAdminInvites() async {
    try {
      final invites = await _db
          .from('admin_invites')
          .select('id, institute_id, full_name, phone, email')
          .eq('claimed', false);

      if (kDebugMode) {
        debugPrint('📋 Fetched ${(invites as List).length} pending admin invites');
      }

      return {
        'success': true,
        'invites': (invites as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error fetching admin invites: $e');
      return {
        'success': false,
        'message': 'Failed to load invites',
        'error': e.toString(),
      };
    }
  }

  /// Anon-safe: whether institute admin onboarding is done (`profiles`) + display label for UX.
  /// Requires migration `040_institute_admin_setup_public_status.sql` deployed.
  Future<Map<String, dynamic>> instituteAdminSetupPublicStatus(String instituteId) async {
    final key = instituteId.trim();
    if (key.isEmpty) {
      return {
        'success': true,
        'setup_complete': false,
        'registered_admin_name': '',
        'invite_claimed': false,
      };
    }
    try {
      final raw = await _db.rpc(
        'institute_admin_setup_public_status',
        params: {'p_institute_id': key},
      );
      if (raw == null) {
        return {
          'success': true,
          'setup_complete': false,
          'registered_admin_name': '',
          'invite_claimed': false,
        };
      }
      final map = Map<String, dynamic>.from(raw as Map);
      return {
        'success': true,
        'setup_complete': map['setup_complete'] == true,
        'registered_admin_name': map['registered_admin_name']?.toString().trim() ?? '',
        'invite_claimed': map['invite_claimed'] == true,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('institute_admin_setup_public_status: $e');
      return {
        'success': false,
        'setup_complete': false,
        'registered_admin_name': '',
        'invite_claimed': false,
        'error': e.toString(),
      };
    }
  }

  /// Same numbering rule as [addStudentManually] (dense max(sr_no, user_id)+1 per institute).
  Future<String> previewNextStudentSrNo(String instituteId) async {
    final peak = await _peakStudentNumbersFromDb(instituteId.trim());
    final base = peak.srMax > peak.rollMax ? peak.srMax : peak.rollMax;
    return (base + 1).toString();
  }

  /// Admin login with numeric institute_id + password
  /// Uses the new admin_login_by_institute database function
  Future<Map<String, dynamic>> adminLoginByInstitute({
    required String instituteKey, // numeric institute_id or institute_code
    required String password,
  }) async {
    try {
      // Call database function to verify credentials
      final result = await _db.rpc('admin_login_by_institute', params: {
        'p_institute_key': instituteKey.trim(),
        'p_password': password,
      });

      final data = result is Map ? result : (jsonDecode(result.toString()) as Map);

      if (kDebugMode) {
        debugPrint('🔐 adminLoginByInstitute: institute=$instituteKey');
        debugPrint('   Result: ${data['success']}');
      }

      if (data['success'] != true) {
        return {
          'success': false,
          'message': data['message']?.toString() ?? 'Login failed',
        };
      }

      final profileId = data['profile_id']?.toString();
      final instituteId = data['institute_id']?.toString();

      if (profileId == null || instituteId == null) {
        return {
          'success': false,
          'message': 'Login returned incomplete data',
        };
      }

      // Fetch profile data
      final profile = await _db
          .from('profiles')
          .select('*')
          .eq('id', profileId)
          .maybeSingle();

      if (profile == null) {
        return {
          'success': false,
          'message': 'Profile not found',
        };
      }

      if (kDebugMode) {
        debugPrint('✅ Admin login successful');
        debugPrint('   Profile: ${profile['name']}');
        debugPrint('   Institute: $instituteId');
      }

      return {
        'success': true,
        'message': 'Login successful',
        'userId': profileId,
        'role': profile['role'],
        'name': profile['name'],
        'instituteId': instituteId,
        'profile': profile,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ adminLoginByInstitute error: $e');
      return {
        'success': false,
        'message': 'Login failed: ${e.toString()}',
      };
    }
  }

  /// Set password for admin (during registration or password reset)
  Future<Map<String, dynamic>> setAdminPassword({
    required String profileId,
    required String newPassword,
  }) async {
    try {
      if (newPassword.length < 8) {
        return {
          'success': false,
          'message': 'Password must be at least 8 characters',
        };
      }

      // Call database function
      final result = await _db.rpc('set_admin_password', params: {
        'p_profile_id': profileId,
        'p_new_password': newPassword,
      });

      final data = result is Map ? result : (jsonDecode(result.toString()) as Map);

      if (kDebugMode) {
        debugPrint('🔐 setAdminPassword: success=${data['success']}');
      }

      return data as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ setAdminPassword error: $e');
      return {
        'success': false,
        'message': 'Failed to set password: ${e.toString()}',
      };
    }
  }

  /// Claim admin invite and create account
  /// Steps: 1. Create Supabase user 2. Create profile 3. Set password 4. Claim invite
  Future<Map<String, dynamic>> claimAdminInvite({
    required String inviteId,
    required String instituteId,
    required String email,
    required String password,
    String? fullName,
    String? phone,
    String? instituteName,
  }) async {
    Future<void> finalizeExistingOrNewUser(String userId) async {
      try {
        await _db
            .from('admin_invites')
            .update({
              'claimed': true,
              'claimed_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', inviteId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Invite claim update skipped; signup trigger may have claimed it: $e');
        }
      }
      try {
        await _db.from('profiles').update({'status': 'approved'}).eq('id', userId);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Profile auto-approve skipped: $e');
      }
    }

    try {
      if (password.length < 8) {
        return {
          'success': false,
          'message': 'Password must be at least 8 characters',
        };
      }

      // Step 1: Create Supabase auth user
      final authResponse = await _db.auth.signUp(
        email: email,
        password: password,
        data: {
          'institute_id': instituteId,
          if (instituteName != null && instituteName.trim().isNotEmpty)
            'institute_name': instituteName.trim(),
          if (fullName != null && fullName.trim().isNotEmpty)
            'name': fullName.trim(),
          if (phone != null && phone.trim().isNotEmpty)
            'phone_number': phone.trim(),
          'website_invite': 'true',
          'invite_id': inviteId,
        },
      );

      final userId = authResponse.user?.id;
      if (userId == null) {
        return {
          'success': false,
          'message': 'Failed to create user account',
        };
      }

      if (kDebugMode) {
        debugPrint('✅ Admin account created: $userId');
        debugPrint('   Email: $email');
        debugPrint('   Institute: $instituteId');
      }

      await finalizeExistingOrNewUser(userId);

      // Auto-activate the admin account (create if doesn't exist)
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await _db.from('main_admins').upsert(
          {
            'user_id': userId,
            'email': email,
            'institute_id': instituteId,
            'institute_name': instituteName,
            'name': fullName,
            'phone_number': phone,
            'status': 'active',
            'approved_at': now,
            'created_at': now,
            'updated_at': now,
          },
          onConflict: 'email,institute_id',
        );
        if (kDebugMode) debugPrint('✅ Admin auto-activated & created for $email');
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Failed to auto-activate admin: $e');
      }

      return {
        'success': true,
        'message': 'Registration complete!',
        'userId': userId,
        'email': email,
      };
    } on AuthApiException catch (e) {
      final code = (e.code ?? '').toLowerCase();
      final msg = e.message.toLowerCase();
      final alreadyExists =
          code == 'user_already_exists' || msg.contains('already registered');

      if (!alreadyExists) {
        if (kDebugMode) debugPrint('❌ claimAdminInvite auth error: $e');
        return {
          'success': false,
          'message': 'Registration failed: ${e.message}',
        };
      }

      try {
        final signIn = await _db.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final existingUserId = signIn.user?.id;
        if (existingUserId == null) {
          return {
            'success': false,
            'message':
                'This email is already registered. Try logging in with the same password once, or use a new email.',
          };
        }

        await finalizeExistingOrNewUser(existingUserId);

        // Auto-activate the admin account (create if doesn't exist)
        try {
          final now = DateTime.now().toUtc().toIso8601String();
          await _db.from('main_admins').upsert(
            {
              'user_id': existingUserId,
              'email': email,
              'institute_id': instituteId,
              'institute_name': instituteName,
              'name': fullName,
              'phone_number': phone,
              'status': 'active',
              'approved_at': now,
              'created_at': now,
              'updated_at': now,
            },
            onConflict: 'email,institute_id',
          );
          if (kDebugMode) debugPrint('✅ Admin auto-activated & created for $email');
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Failed to auto-activate admin: $e');
        }

        return {
          'success': true,
          'message': 'Registration completed using existing account.',
          'userId': existingUserId,
          'email': email,
        };
      } on AuthException {
        return {
          'success': false,
          'message':
              'This email is already registered. Use the same password that was set earlier, or change the website email and try again.',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ claimAdminInvite error: $e');
      return {
        'success': false,
        'message': 'Registration failed: ${e.toString()}',
      };
    }
  }

  String _generateOTP() {
    return (100000 + Random().nextInt(900000)).toString();
  }
}
