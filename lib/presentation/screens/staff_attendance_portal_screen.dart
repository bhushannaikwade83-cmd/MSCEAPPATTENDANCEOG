import 'package:flutter/material.dart';

import '../../core/root_navigator.dart';
import '../../services/geofence_service.dart';
import '../../services/pin_midnight_logout_service.dart';
import '../../services/pin_session_manager.dart';
import '../../services/session_manager.dart';
import '../widgets/session_monitor.dart';
import 'login_screen.dart';
import 'student_management_screen.dart';
import 'institute_location_gate_screen.dart';

/// Attendance staff sees the same student experience as admin (student list, search, mark attendance).
/// Uses the same institute GPS fence as admin; resumes re-check institute radius (camera flows skipped).
class StaffAttendancePortalScreen extends StatefulWidget {
  static const routeName = '/staff-attendance-portal';

  const StaffAttendancePortalScreen({super.key});

  /// Full sign-out to main admin login (email/password), not instructor PIN restore.
  static Future<void> signOutToLogin(BuildContext context) async {
    final lastInstituteCode =
        await PinSessionManager.getLastStaffInstituteCode();
    PinMidnightLogoutService.stopMonitoring();
    await SessionManager.signOut();
    await PinSessionManager.clearPinSession();

    final args = <String, dynamic>{'forceFullLogin': true};
    if (lastInstituteCode != null && lastInstituteCode.isNotEmpty) {
      args['instituteId'] = lastInstituteCode;
    }

    final nav = rootNavigatorKey.currentState;
    if (nav != null && nav.mounted) {
      nav.pushNamedAndRemoveUntil(
        LoginScreen.routeName,
        (_) => false,
        arguments: args,
      );
      return;
    }
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        LoginScreen.routeName,
        (_) => false,
        arguments: args,
      );
    }
  }

  @override
  State<StaffAttendancePortalScreen> createState() =>
      _StaffAttendancePortalScreenState();
}

class _StaffAttendancePortalScreenState
    extends State<StaffAttendancePortalScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _enforceInstituteGate(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 550), () async {
        if (!mounted || SessionMonitor.shouldSkipResumeLockForCamera) return;
        await _enforceInstituteGate();
      });
    }
  }

  Future<void> _enforceInstituteGate() async {
    final ok = await GeofenceService().hasValidPersonalGpsForCurrentAdmin();
    if (!mounted || !ok) return;

    final gate = await GeofenceService().attendanceLocationGateForCurrentUser(
      fastFenceSampleForLogin: true,
    );
    if (!mounted || gate['allowed'] == true) return;

    Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
      InstituteLocationGateScreen.routeName,
      (_) => false,
      arguments: {'resumeRoute': StaffAttendancePortalScreen.routeName},
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: StudentManagementScreen(forAttendanceStaffPortal: true),
    );
  }
}
