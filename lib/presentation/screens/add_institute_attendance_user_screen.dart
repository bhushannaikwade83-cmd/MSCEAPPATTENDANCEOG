import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      backgroundColor: AppTheme.backgroundGrey,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GovTricolorStrip(),
          Expanded(
            child: ResponsiveScrollBody(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Institute instructor',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Up to $_kMaxInstructors instructor accounts per institute. Each signs in with Institute ID and their own PIN.',
                          style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                        ),
                        if (atLimit) ...[
                          SizedBox(height: 10.h),
                          Text(
                            'Maximum reached ($_kMaxInstructors/$_kMaxInstructors). Remove an instructor in Dashboard → Auth before adding another.',
                            style: TextStyle(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accentRed.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                        if (_instituteId != null) ...[
                          SizedBox(height: 8.h),
                          Text(
                            'Institute ID: ${formatInstituteIdForDisplay(_instituteId!)}',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ],
                        SizedBox(height: 20.h),
                        Text(
                          'Add user',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : AppTheme.textDark,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        TextFormField(
                          controller: _firstCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'First name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                        SizedBox(height: 14.h),
                        TextFormField(
                          controller: _middleCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Middle name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                        SizedBox(height: 14.h),
                        TextFormField(
                          controller: _lastCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Last name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                        SizedBox(height: 14.h),
                        TextFormField(
                          controller: _mobileCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Mobile number',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
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
                        TextFormField(
                          controller: _pinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 4,
                          decoration: const InputDecoration(
                            labelText: 'PIN (4 digits)',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
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
                        CredentialStrengthIndicator(
                          analysis: CredentialStrengthAnalysis.analyzePinFour(_pinCtrl.text.trim()),
                          dense: true,
                          forPin: true,
                        ),
                        SizedBox(height: 14.h),
                        TextFormField(
                          controller: _confirmPinCtrl,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 4,
                          decoration: const InputDecoration(
                            labelText: 'Confirm PIN',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (v) {
                            if (v != _pinCtrl.text) return 'PINs do not match';
                            return null;
                          },
                        ),
                        SizedBox(height: 24.h),
                        FilledButton(
                          onPressed: (_busy || atLimit) ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Create user'),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 28.h),
                  Row(
                    children: [
                      Icon(Icons.people_outline, size: 22.sp, color: AppTheme.primaryBlue),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          _staffRows.isEmpty
                              ? 'Institute instructors'
                              : 'Institute instructors (${_staffRows.length}/$_kMaxInstructors)',
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : AppTheme.textDark,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_instituteId != null)
                        IconButton(
                          tooltip: 'Refresh list',
                          onPressed: _loadingStaff ? null : () => _loadStaffUsers(_instituteId!),
                          icon: const Icon(Icons.refresh),
                        ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    'Only instructor accounts for your institute are shown (not admins or students).',
                    style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
                  ),
                  SizedBox(height: 12.h),
                  if (_loadingStaff)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_staffRows.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 16.w),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'No institute instructor yet. Add one using the form above.\n\n'
                        'If add fails with "already exists" but this list is empty, a leftover login '
                        'is in Supabase Auth only — ask your coder to delete users ending with '
                        '@staff.msce-attendance.app for your institute, then try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.sp,
                          color: AppTheme.textGray,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _staffRows.length,
                      separatorBuilder: (context, _) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final r = _staffRows[index];
                        final name = (r['name'] as String?)?.trim() ?? '—';
                        final email = (r['email'] as String?)?.trim() ?? '';
                        final mob = (r['phone_number'] as String?)?.trim() ?? '';
                        return Material(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
                            onTap: () => _showInstructorDetails(r, isDark),
                            trailing: Icon(
                              Icons.info_outline,
                              size: 22.sp,
                              color: AppTheme.primaryBlue.withValues(alpha: 0.85),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                              child: Text(
                                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                                style: TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15.sp,
                                color: isDark ? Colors.white : AppTheme.textDark,
                              ),
                            ),
                            subtitle: Padding(
                              padding: EdgeInsets.only(top: 4.h),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Login: Institute ${formatInstituteIdForDisplay(_instituteId)} + PIN',
                                    style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                                  ),
                                  if (mob.isNotEmpty)
                                    Text(
                                      'Mobile: $mob',
                                      style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                                    ),
                                  if (email.isNotEmpty)
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: AppTheme.textGray.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  Text(
                                    'Added: ${_formatDateTime(r['created_at'])} (local)',
                                    style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
                                  ),
                                  Text(
                                    'Last sign-in: ${_formatDateTime(r['last_login'])} (local)',
                                    style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  SizedBox(height: 24.h),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
