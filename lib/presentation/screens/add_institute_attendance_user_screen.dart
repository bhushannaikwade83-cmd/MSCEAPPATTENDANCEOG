import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:ui' as ui;

import '../../core/app_db.dart';
import '../../core/credential_strength.dart';
import '../../core/institute_id_display.dart';
import '../../core/supabase_maps.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_page.dart';
import '../../services/auth_service.dart';
import '../widgets/credential_strength_indicator.dart';

/// Institute admin: create institute instructor (full name + mobile + PIN). Login = Institute ID + PIN.
/// Also lists existing instructors for this institute only.
class AddInstituteAttendanceUserScreen extends StatefulWidget {
  static const routeName = '/add-institute-attendance-user';

  const AddInstituteAttendanceUserScreen({super.key});

  @override
  State<AddInstituteAttendanceUserScreen> createState() =>
      _AddInstituteAttendanceUserScreenState();
}

class _AddInstituteAttendanceUserScreenState extends State<AddInstituteAttendanceUserScreen> {
  static const int _kMaxInstructors = 4;

  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _middleCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  String? _instituteId;
  bool _loadingStaff = false;
  List<Map<String, dynamic>> _staffRows = [];

  @override
  void initState() {
    super.initState();
    _loadInstitute();
  }

  Future<void> _loadInstitute() async {
    final uid = appDb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await appDb.from('profiles').select('institute_id').eq('id', uid).maybeSingle();
      final rawIid = row?['institute_id'] as String?;
      final canonical = rawIid == null ? null : await resolveCanonicalInstituteId(rawIid);
      if (!mounted) return;
      setState(() => _instituteId = canonical ?? rawIid);
      final loadKey = canonical ?? rawIid;
      if (loadKey != null && loadKey.isNotEmpty) {
        await _loadStaffUsers(loadKey);
      }
    } catch (_) {}
  }

  Future<void> _loadStaffUsers(String instituteId) async {
    setState(() => _loadingStaff = true);
    try {
      final canonicalId = await resolveCanonicalInstituteId(instituteId) ?? instituteId;
      final code = await instituteCodeForId(canonicalId);
      final instituteKeys = <String>{canonicalId, code, instituteId.trim()}
        ..removeWhere((s) => s.isEmpty);
      final orFilter = instituteKeys.map((k) => 'institute_id.eq.$k').join(',');

      // Only instructors with a saved PIN (same rule as server count).
      final rows = await appDb
          .from('profiles')
          .select('id,name,email,phone_number,status,created_at,last_login,role,pin_hash')
          .eq('role', 'attendance_user')
          .or(orFilter)
          .not('pin_hash', 'is', null)
          .order('created_at', ascending: false);
      if (!mounted) return;
      final list = (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() => _staffRows = list);
    } catch (_) {
      if (mounted) setState(() => _staffRows = []);
    } finally {
      if (mounted) setState(() => _loadingStaff = false);
    }
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _middleCtrl.dispose();
    _lastCtrl.dispose();
    _mobileCtrl.dispose();
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  String _mergedFullName() {
    final parts = [
      _firstCtrl.text.trim(),
      _middleCtrl.text.trim(),
      _lastCtrl.text.trim(),
    ].where((s) => s.isNotEmpty).toList();
    return parts.join(' ');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_staffRows.length >= _kMaxInstructors) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximum of $_kMaxInstructors institute instructors reached. Remove one before adding another.',
          ),
          backgroundColor: AppTheme.accentRed,
        ),
      );
      return;
    }

    final iid = _instituteId?.trim();
    if (iid == null || iid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load your institute. Open GPS / admin home first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final fullName = _mergedFullName();

    setState(() => _busy = true);
    try {
      final res = await _auth.createInstituteAttendanceUser(
        instituteKey: iid,
        fullName: fullName,
        firstName: _firstCtrl.text.trim(),
        middleName: _middleCtrl.text.trim(),
        lastName: _lastCtrl.text.trim(),
        mobile: _mobileCtrl.text.trim().replaceAll(RegExp(r'\D'), ''),
        pin: _pinCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'User created. They sign in with Institute ID + PIN from Institute instructor login.',
            ),
            backgroundColor: AppTheme.primaryGreen,
          ),
        );
        _firstCtrl.clear();
        _middleCtrl.clear();
        _lastCtrl.clear();
        _mobileCtrl.clear();
        _pinCtrl.clear();
        _confirmPinCtrl.clear();
        await _loadStaffUsers(iid);
      } else {
        final msg = res['message']?.toString() ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.accentRed,
            duration: msg.toLowerCase().contains('already') ||
                    msg.toLowerCase().contains('leftover')
                ? const Duration(seconds: 12)
                : const Duration(seconds: 5),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppTheme.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDateTime(dynamic v) {
    if (v == null) return 'Never';
    final s = v.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    final local = dt.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd  $hh:$min';
  }

  void _showInstructorDetails(Map<String, dynamic> r, bool isDark) {
    final ctx = context;
    final nameRaw = (r['name'] as String?)?.trim() ?? '';
    final name = nameRaw.isEmpty ? '—' : nameRaw;
    final emailRaw = (r['email'] as String?)?.trim() ?? '';
    final email = emailRaw.isEmpty ? '—' : emailRaw;
    final mobRaw = (r['phone_number'] as String?)?.trim() ?? '';
    final mob = mobRaw.isEmpty ? '—' : mobRaw;
    final statusRaw = (r['status'] as String?)?.trim() ?? '';
    final status = statusRaw.isEmpty ? '—' : statusRaw;
    final iidRaw = (_instituteId ?? '').trim();
    final iidDisplay = iidRaw.isEmpty ? '—' : formatInstituteIdForDisplay(iidRaw);

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Container(
        margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h + MediaQuery.paddingOf(sheetCtx).bottom),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(18.w, 16.h, 18.w, 20.h),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Instructor details',
                        style: TextStyle(
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Divider(height: 20.h),
                _detailLine('Full name', name, isDark),
                SizedBox(height: 10.h),
                _detailLine('Mobile', mob, isDark),
                SizedBox(height: 10.h),
                _detailLine('Status', status, isDark),
                SizedBox(height: 10.h),
                _detailLine('Account email', email, isDark),
                SizedBox(height: 10.h),
                _detailLine('Institute ID', iidDisplay, isDark),
                SizedBox(height: 10.h),
                _detailLine('Added (local)', _formatDateTime(r['created_at']), isDark),
                SizedBox(height: 10.h),
                _detailLine('Last sign-in (local)', _formatDateTime(r['last_login']), isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: AppTheme.textGray,
          ),
        ),
        SizedBox(height: 2.h),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 14.sp,
            height: 1.25,
            color: isDark ? Colors.white.withValues(alpha: 0.95) : AppTheme.textDark,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final atLimit = _staffRows.length >= _kMaxInstructors;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GovTricolorStrip(),
          Expanded(
            child: ResponsiveScrollBody(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderCard(isDark, atLimit),
                  SizedBox(height: 20.h),
                  Form(
                    key: _formKey,
                    child: _buildFormCard(isDark, atLimit),
                  ),
                  SizedBox(height: 28.h),
                  _buildInstructorsHeader(isDark),
                  SizedBox(height: 12.h),
                  if (_loadingStaff)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_staffRows.isEmpty)
                    _buildEmptyState(isDark)
                  else
                    _buildInstructorsList(isDark),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(bool isDark, bool atLimit) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryBlue.withOpacity(0.3),
                      AppTheme.primaryBlue.withOpacity(0.15),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryBlue.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.person_add_rounded, color: AppTheme.primaryBlue, size: 24.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Institute Instructor',
                      style: TextStyle(
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppTheme.textDark,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Add up to $_kMaxInstructors instructors',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: isDark ? Colors.white70 : AppTheme.textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_instituteId != null) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_rounded, size: 16.sp, color: AppTheme.primaryBlue),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Institute ID: ${formatInstituteIdForDisplay(_instituteId!)}',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (atLimit) ...[
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_rounded, size: 16.sp, color: AppTheme.accentRed),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Maximum reached ($_kMaxInstructors/$_kMaxInstructors)',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentRed.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormCard(bool isDark, bool atLimit) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accentSaffron.withOpacity(isDark ? 0.12 : 0.06),
            AppTheme.accentSaffron.withOpacity(isDark ? 0.06 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: AppTheme.accentSaffron.withOpacity(isDark ? 0.3 : 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentSaffron.withOpacity(isDark ? 0.1 : 0.06),
            blurRadius: 16.r,
            offset: Offset(0, 4.h),
          ),
        ],
      ),
      padding: EdgeInsets.all(18.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add New Instructor',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.textDark,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: 16.h),
          _buildModernTextField(
            controller: _firstCtrl,
            label: 'First name',
            icon: Icons.person_outline,
            isDark: isDark,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
          ),
          SizedBox(height: 14.h),
          _buildModernTextField(
            controller: _middleCtrl,
            label: 'Middle name',
            icon: Icons.person_outline,
            isDark: isDark,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
          ),
          SizedBox(height: 14.h),
          _buildModernTextField(
            controller: _lastCtrl,
            label: 'Last name',
            icon: Icons.person_outline,
            isDark: isDark,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
          ),
          SizedBox(height: 14.h),
          _buildModernTextField(
            controller: _mobileCtrl,
            label: 'Mobile number',
            icon: Icons.phone_outlined,
            isDark: isDark,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 15,
            validator: (v) {
              final d = (v ?? '').trim().replaceAll(RegExp(r'\D'), '');
              if (d.isEmpty) return 'Required';
              if (d.length < 10 || d.length > 15) {
                return 'Use 10–15 digits';
              }
              return null;
            },
          ),
          SizedBox(height: 14.h),
          _buildModernTextField(
            controller: _pinCtrl,
            label: 'PIN (4 digits)',
            icon: Icons.lock_outline,
            isDark: isDark,
            obscureText: true,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            validator: (v) {
              final p = v?.trim() ?? '';
              if (!AuthService.isValidLoginPinLength(p)) {
                return AuthService.loginPinLengthMessage;
              }
              final pa = CredentialStrengthAnalysis.analyzePinFour(p);
              if (pa.level == CredentialStrengthLevel.weak) {
                return pa.hint ?? 'Choose a stronger PIN';
              }
              return null;
            },
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: CredentialStrengthIndicator(
              analysis: CredentialStrengthAnalysis.analyzePinFour(_pinCtrl.text.trim()),
              dense: true,
              forPin: true,
            ),
          ),
          SizedBox(height: 14.h),
          _buildModernTextField(
            controller: _confirmPinCtrl,
            label: 'Confirm PIN',
            icon: Icons.lock_outline,
            isDark: isDark,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            validator: (v) {
              if (v != _pinCtrl.text) return 'PINs do not match';
              return null;
            },
          ),
          SizedBox(height: 24.h),
          _buildModernButton(isDark, atLimit),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    bool obscureText = false,
    Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      obscureText: obscureText,
      onChanged: onChanged,
      textCapitalization: !obscureText ? TextCapitalization.words : TextCapitalization.none,
      validator: validator,
      style: TextStyle(
        fontSize: 14.sp,
        color: isDark ? Colors.white : AppTheme.textDark,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryBlue, size: 20.sp),
        counterText: '',
        filled: true,
        fillColor: isDark
            ? Colors.white.withOpacity(0.05)
            : AppTheme.primaryBlue.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.3 : 0.15),
            width: 1.5,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(
            color: AppTheme.primaryBlue.withOpacity(isDark ? 0.25 : 0.1),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(
            color: AppTheme.primaryBlue,
            width: 2,
          ),
        ),
        labelStyle: TextStyle(
          fontSize: 13.sp,
          color: isDark ? Colors.white70 : AppTheme.textGray,
        ),
      ),
    );
  }

  Widget _buildModernButton(bool isDark, bool atLimit) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue,
            AppTheme.primaryBlue.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(12.r),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withOpacity(_busy ? 0 : 0.3),
            blurRadius: 12,
            offset: Offset(0, 4.h),
            spreadRadius: 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_busy || atLimit) ? null : _submit,
          borderRadius: BorderRadius.circular(12.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h),
            child: Center(
              child: _busy
                  ? SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Create Instructor',
                      style: TextStyle(
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInstructorsHeader(bool isDark) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryGreen.withOpacity(0.2),
                AppTheme.primaryGreen.withOpacity(0.08),
              ],
            ),
          ),
          child: Icon(Icons.people_rounded, size: 20.sp, color: AppTheme.primaryGreen),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            _staffRows.isEmpty
                ? 'Institute Instructors'
                : 'Instructors (${_staffRows.length}/$_kMaxInstructors)',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppTheme.textDark,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (_instituteId != null)
          IconButton(
            tooltip: 'Refresh list',
            onPressed: _loadingStaff ? null : () => _loadStaffUsers(_instituteId!),
            icon: Icon(
              Icons.refresh_rounded,
              color: AppTheme.primaryGreen,
              size: 20.sp,
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 32.h, horizontal: 16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(isDark ? 0.08 : 0.04),
            AppTheme.primaryBlue.withOpacity(isDark ? 0.04 : 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppTheme.primaryBlue.withOpacity(isDark ? 0.2 : 0.1),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Text(
            '👥',
            style: TextStyle(fontSize: 48.sp),
          ),
          SizedBox(height: 12.h),
          Text(
            'No Instructors Yet',
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : AppTheme.textDark,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Add your first instructor using the form above',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.sp,
              color: isDark ? Colors.white70 : AppTheme.textGray,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructorsList(bool isDark) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _staffRows.length,
      separatorBuilder: (context, _) => SizedBox(height: 10.h),
      itemBuilder: (context, index) {
        final r = _staffRows[index];
        final name = (r['name'] as String?)?.trim() ?? '—';
        return _buildInstructorCard(r, name, isDark);
      },
    );
  }

  Widget _buildInstructorCard(Map<String, dynamic> r, String name, bool isDark) {
    final email = (r['email'] as String?)?.trim() ?? '';
    final mob = (r['phone_number'] as String?)?.trim() ?? '';

    return GestureDetector(
      onTap: () => _showInstructorDetails(r, isDark),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primaryGreen.withOpacity(isDark ? 0.1 : 0.05),
              AppTheme.primaryGreen.withOpacity(isDark ? 0.05 : 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: AppTheme.primaryGreen.withOpacity(isDark ? 0.3 : 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryGreen.withOpacity(isDark ? 0.08 : 0.04),
              blurRadius: 12.r,
              offset: Offset(0, 3.h),
            ),
          ],
        ),
        padding: EdgeInsets.all(14.w),
        child: Row(
          children: [
            Container(
              width: 44.r,
              height: 44.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryGreen.withOpacity(0.25),
                    AppTheme.primaryGreen.withOpacity(0.12),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryGreen.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                  style: TextStyle(
                    color: AppTheme.primaryGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 18.sp,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
                      color: isDark ? Colors.white : AppTheme.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  if (mob.isNotEmpty)
                    Text(
                      mob,
                      style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (mob.isNotEmpty && email.isNotEmpty) SizedBox(height: 2.h),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: AppTheme.textGray.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            // 🗑️ Delete button
            GestureDetector(
              onTap: () => _showDeleteConfirmation(r),
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(
                  Icons.delete_rounded,
                  color: Colors.red.withOpacity(0.7),
                  size: 20.sp,
                ),
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.primaryGreen.withOpacity(0.6),
              size: 24.sp,
            ),
          ],
        ),
      ),
    );
  }

  /// 🗑️ Show delete confirmation dialog
  void _showDeleteConfirmation(Map<String, dynamic> instructor) {
    final name = (instructor['name'] as String?)?.trim() ?? '—';
    final id = instructor['id'] as String?;

    if (id == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🗑️ Delete Instructor'),
        content: Text('Delete "$name" from instructors?\n\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteInstructor(id, name);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// 🗑️ Delete instructor from database
  Future<void> _deleteInstructor(String instructorId, String instructorName) async {
    try {
      print('🗑️ [DELETE] Attempting to delete instructor: $instructorName (ID: $instructorId)');

      // Use Supabase REST API with explicit auth header
      print('🔍 [DELETE] Calling via Supabase client...');

      final response = await appDb.from('profiles').delete().eq('id', instructorId).select();

      print('✅ [DELETE] Response: $response');

      // Double-check: verify instructor was actually deleted
      print('🔍 [DELETE] Verifying deletion...');
      final checkAfterDelete = await appDb
          .from('profiles')
          .select('id')
          .eq('id', instructorId)
          .maybeSingle();

      if (checkAfterDelete != null) {
        print('⚠️ [DELETE] Instructor still exists in database! RLS policy issue?');
        throw Exception('Delete failed: Instructor still exists (RLS policy issue?)');
      }

      print('✅ [DELETE] Verified: Instructor deleted from database');

      // Refresh the list
      if (_instituteId != null) {
        print('🔄 [DELETE] Refreshing instructor list...');
        await _loadStaffUsers(_instituteId!);
      }

      if (!mounted) return;

      print('✅ [DELETE] Showing success message');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Instructor "$instructorName" deleted'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ [DELETE] Error deleting instructor: $e');
      print('❌ [DELETE] Stack trace: ${StackTrace.current}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Delete failed (RLS policy issue): $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
