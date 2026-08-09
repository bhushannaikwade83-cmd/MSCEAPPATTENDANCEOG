import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/attendance_staff_auth.dart';
import '../../core/root_navigator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive_page.dart';
import '../../services/auth_service.dart';
import '../../services/geofence_service.dart';
import '../../services/location_monitor_service.dart';
import '../../services/session_manager.dart';
import '../../services/pin_session_manager.dart';
import '../../services/pin_midnight_logout_service.dart';
import 'login_screen.dart';
import 'staff_attendance_portal_screen.dart';
import 'gps_settings_screen.dart';
import 'institute_location_gate_screen.dart';

/// Login for institute instructors: Institute ID + PIN (access scoped by institute).
class AttendanceStaffLoginScreen extends StatefulWidget {
  static const routeName = '/attendance-staff-login';

  const AttendanceStaffLoginScreen({super.key});

  @override
  State<AttendanceStaffLoginScreen> createState() =>
      _AttendanceStaffLoginScreenState();
}

class _AttendanceStaffLoginScreenState extends State<AttendanceStaffLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _instituteCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  bool _isReturningUser = false;
  /// When a saved institute code exists we lock the field; otherwise it must stay
  /// editable or first-time instructors see an empty, disabled Institute ID box.
  bool _instituteFieldDisabled = false;

  // Preferences key for saved institute code
  static const String _prefLastStaffInstituteCode = 'msce_last_staff_institute_code';

  @override
  void initState() {
    super.initState();
    _loadSavedInstitute();

    // 🔐 Check if PIN session is still active
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAndRestorePinSession();
    });
  }

  @override
  void dispose() {
    _instituteCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  /// Load saved institute code for returning users
  Future<void> _loadSavedInstitute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedInstituteCode = prefs.getString(_prefLastStaffInstituteCode);
      if (mounted) {
        if (savedInstituteCode != null && savedInstituteCode.isNotEmpty) {
          // Returning user: pre-fill and keep disabled
          setState(() {
            _instituteCtrl.text = savedInstituteCode;
            _isReturningUser = true;
            _instituteFieldDisabled = true;  // Locked permanently
          });
        }
      }
    } catch (_) {}
  }

  /// 🔐 Check if PIN session is still active and restore it
  Future<void> _checkAndRestorePinSession() async {
    try {
      final hasActiveSession = await PinSessionManager.hasActivePinSession();

      if (hasActiveSession && mounted) {
        // Session is active - restore it
        final sessionData = await PinSessionManager.restorePinSession();
        final instituteId = sessionData?['instituteId'] ?? '';

        if (instituteId.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('✅ PIN session restored - navigating to Staff Portal');
          }

          // Navigate directly to Staff Portal without showing login screen
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pushReplacementNamed(
              StaffAttendancePortalScreen.routeName,
            );
          }
        } else {
          await _hydrateInstituteWhenAvailable();
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ No active PIN session - showing login screen');
        }
        await _hydrateInstituteWhenAvailable();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error checking PIN session: $e');
      await _hydrateInstituteWhenAvailable();
    }
  }

  /// PIN session inactive but `PinSessionManager` may still retain last institute code.
  Future<void> _hydrateInstituteWhenAvailable() async {
    if (_instituteCtrl.text.trim().isNotEmpty) return;
    try {
      final fallback = await PinSessionManager.getLastStaffInstituteCode();
      final code = fallback?.trim() ?? '';
      if (!mounted || code.isEmpty) return;
      setState(() {
        _instituteCtrl.text = code;
        _isReturningUser = true;
        _instituteFieldDisabled = true;
      });
    } catch (_) {}
  }

  /// Save institute code after successful login
  Future<void> _saveStaffInstituteCode(String instituteCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = instituteCode.trim();
      if (code.isNotEmpty) {
        await prefs.setString(_prefLastStaffInstituteCode, code);
      }
    } catch (_) {}
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      // Check location permission first
      final hasPermission = await PinSessionManager.hasLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission required for PIN login. '
                            'Please enable location in app settings.'),
              backgroundColor: AppTheme.accentRed,
              duration: Duration(seconds: 4),
            ),
          );
        }
        if (mounted) setState(() => _busy = false);
        return;
      }

      // Check if location services are enabled
      final isEnabled = await PinSessionManager.ensureLocationEnabled();
      if (!isEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. '
                            'Please enable them to continue.'),
              backgroundColor: AppTheme.accentRed,
              duration: Duration(seconds: 4),
            ),
          );
        }
        if (mounted) setState(() => _busy = false);
        return;
      }

      final instituteId = _instituteCtrl.text.trim();

      // Same locked fence + sampling as admin GPS Settings / attendance marking.
      if (kDebugMode) {
        debugPrint('🔐 Verifying instructor PIN login against admin locked GPS...');
      }

      final locationResult =
          await LocationVerificationService.verifyLocationNow(
        instituteId: instituteId,
      );

      if (!locationResult.isWithinRadius) {
        // 🔧 Handle GPS not configured case
        if (locationResult.error?.contains('GPS is not locked') == true) {
          if (kDebugMode) {
            debugPrint('🛰️ GPS not configured - navigating to GPS Settings screen');
          }
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              GpsSettingsScreen.routeName,
              (route) => false,
              arguments: {'mandatory': true, 'fromPinLogin': true},
            );
            setState(() => _busy = false);
          }
          return;
        }

        // Regular out-of-radius error
        if (mounted) {
          final errorMsg = locationResult.error ??
              'You are outside the institute attendance zone. '
              'Stand at the same place your admin locked in GPS Settings, then try again.';

          final distanceStr = locationResult.distance != null
              ? '\n\n📍 Distance: ${PinSessionManager.formatDistance(locationResult.distance!)}'
              : '';

          if (kDebugMode) {
            debugPrint('❌ Instructor PIN login denied: outside locked fence');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$errorMsg$distanceStr'),
              backgroundColor: AppTheme.accentRed,
              duration: const Duration(seconds: 6),
            ),
          );
        }
        if (mounted) setState(() => _busy = false);
        return;
      }

      if (kDebugMode) {
        debugPrint('✅ Instructor PIN login: within admin locked GPS fence');
      }

      // Now attempt PIN login
      final res = await _auth.signInAttendanceStaff(
        instituteKey: instituteId,
        pin: _pinCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message']?.toString() ?? 'Login failed'),
            backgroundColor: AppTheme.accentRed,
          ),
        );
        return;
      }

      final email = res['email']?.toString() ?? '';
      final canonId = res['canonicalInstituteId']?.toString() ?? '';
      final pin = _pinCtrl.text.trim();
      final pwd = email.isNotEmpty && canonId.isNotEmpty
          ? AttendanceStaffAuth.authPasswordFor(
              canonicalInstituteId: canonId,
              pin: pin,
            )
          : null;

      // Save institute code and PIN session
      await _saveStaffInstituteCode(_instituteCtrl.text);

      // Get institute GPS coordinates from gps_settings table to cache for future logins
      double? gpsLat;
      double? gpsLng;
      try {
        final fence = await GeofenceService().lockedFenceLatLngForInstitute(instituteId);
        if (fence != null) {
          gpsLat = fence.latitude;
          gpsLng = fence.longitude;
          if (kDebugMode) {
            debugPrint('📍 Cached locked-fence GPS: Lat=$gpsLat, Lng=$gpsLng');
          }
        } else if (kDebugMode) {
          debugPrint('⚠️ No locked gps_settings row to cache for institute $instituteId');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Could not fetch locked fence GPS for caching: $e');
      }

      // Save PIN session for persistent login (with cached GPS coordinates)
      await PinSessionManager.savePinSession(
        instituteId: _instituteCtrl.text.trim(),
        userName: email,
        userData: {
          'canonicalInstituteId': canonId,
          'pin': _pinCtrl.text.trim(),
          'email': email,
          'loginTime': DateTime.now().toIso8601String(),
        },
        gpsLatitude: gpsLat,
        gpsLongitude: gpsLng,
      );

      // 🌙 Start midnight auto-logout monitor for this PIN session
      PinMidnightLogoutService.startMidnightMonitor();

      SessionManager.updateActivity();
      if (!mounted) return;

      final gateFuture = GeofenceService().attendanceLocationGateForCurrentUser(
        fastFenceSampleForLogin: true,
      );
      final cacheFuture = (email.isNotEmpty && canonId.isNotEmpty && pwd != null)
          ? Future.wait<void>([
              _auth.cachePinForAttendanceStaffLogin(
                email: email,
                pin: pin,
                canonicalInstituteId: canonId,
              ),
              _auth.cacheBiometricLogin(
                email: email,
                password: pwd,
              ),
            ])
          : Future<void>.value();

      final done = await Future.wait<dynamic>([cacheFuture, gateFuture]);
      final gate = done[1] as Map<String, dynamic>;
      if (!mounted) return;
      if (gate['allowed'] != true) {
        final nav = rootNavigatorKey.currentState;
        if (nav != null && nav.mounted) {
          nav.pushNamedAndRemoveUntil(
            InstituteLocationGateScreen.routeName,
            (_) => false,
            arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
          );
        } else {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
            InstituteLocationGateScreen.routeName,
            (_) => false,
            arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
          );
        }
        return;
      }

      // PIN session already saved above with correct email/userData — do not call
      // savePinSession again (it would overwrite userName with the PIN fragment).

      // Use root navigator so staff portal replaces splash/lock, not a nested route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final nav = rootNavigatorKey.currentState;
        if (nav != null && nav.mounted) {
          nav.pushNamedAndRemoveUntil(
            StaffAttendancePortalScreen.routeName,
            (_) => false,
          );
        } else {
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
            StaffAttendancePortalScreen.routeName,
            (_) => false,
          );
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GovTricolorStrip(),
          Expanded(
            child: ResponsiveScrollBody(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
              child: Form(
                key: _formKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Institute instructor login',
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'Enter your institute\'s 5-digit Institute ID (e.g. 00000) and the PIN your admin set for your account. '
                        'Each instructor has their own PIN. Access is limited to that institute only.',
                        style: TextStyle(fontSize: 13.sp, color: AppTheme.textGray),
                      ),
                      SizedBox(height: 24.h),
                      if (_isReturningUser && _instituteFieldDisabled)
                        // Read-only institute ID display for returning users
                        Container(
                          padding: EdgeInsets.all(12.h),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primaryBlue.withOpacity(0.3),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lock,
                                    color: AppTheme.primaryBlue,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8.w),
                                  Text(
                                    'Your Registered Institute',
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryBlue,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.h),
                              Text(
                                _instituteCtrl.text,
                                style: TextStyle(
                                  fontSize: 20.sp,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primaryBlue,
                                  letterSpacing: 2,
                                ),
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                'Locked to this institute for security',
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: AppTheme.textGray,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        TextFormField(
                          controller: _instituteCtrl,
                          keyboardType: TextInputType.number,
                          enabled: !_instituteFieldDisabled,
                          decoration: InputDecoration(
                            labelText: 'Institute ID',
                            helperText: _instituteFieldDisabled
                              ? 'Your registered institute (locked)'
                              : '5-digit code (leading zeros), e.g. 00000',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return 'Required';
                            if (!RegExp(r'^\d+$').hasMatch(t)) {
                              return 'Use numeric Institute ID';
                            }
                            return null;
                          },
                        ),
                      SizedBox(height: 16.h),
                      TextFormField(
                        controller: _pinCtrl,
                        obscureText: true,
                        keyboardType: TextInputType.number,
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
                          return null;
                        },
                      ),
                      SizedBox(height: 28.h),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('LOG IN  |  लॉगिन'),
                      ),
                      SizedBox(height: 16.h),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                PinMidnightLogoutService.stopMonitoring();
                                await SessionManager.signOut();
                                await PinSessionManager.clearPinSession();
                                if (!mounted) return;
                                Navigator.of(context, rootNavigator: true)
                                    .pushNamedAndRemoveUntil(
                                  LoginScreen.routeName,
                                  (_) => false,
                                  arguments: const {'forceFullLogin': true},
                                );
                              },
                        child: const Text('Back to admin login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
