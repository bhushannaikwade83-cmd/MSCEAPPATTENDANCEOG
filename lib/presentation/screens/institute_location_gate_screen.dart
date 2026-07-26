import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_ui.dart';
import '../../core/utils/responsive_page.dart';
import '../../services/geofence_service.dart';
import '../../services/session_manager.dart';
import 'login_screen.dart';
import 'main_navigation_screen.dart';

/// Blocks all features until the device GPS is inside the institute's locked attendance zone.
/// Used for institute admin and institute instructors (same fence as admin’s GPS Settings).
class InstituteLocationGateScreen extends StatefulWidget {
  static const routeName = '/institute-location-gate';

  final String resumeRoute;

  const InstituteLocationGateScreen({
    super.key,
    required this.resumeRoute,
  });

  static InstituteLocationGateScreen fromArgs(dynamic args) {
    final map = <String, dynamic>{};
    if (args is Map) {
      args.forEach((k, v) => map[k.toString()] = v);
    }
    return InstituteLocationGateScreen(
      resumeRoute: map['resumeRoute']?.toString().trim().isNotEmpty == true
          ? map['resumeRoute'].toString()
          : MainNavigationScreen.routeName,
    );
  }

  @override
  State<InstituteLocationGateScreen> createState() => _InstituteLocationGateScreenState();
}

class _InstituteLocationGateScreenState extends State<InstituteLocationGateScreen> {
  final _svc = GeofenceService();
  bool _checking = true;
  String _message =
      'Checking your location for institute attendance radius… '
      '\n\nसंस्था उपस्थिती क्षेत्र तपासत आहे…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  Future<void> _runGate() async {
    if (!mounted) return;
    setState(() => _checking = true);
    final result = await _svc.attendanceLocationGateForCurrentUser(
      fastFenceSampleForLogin: true,
    );
    if (!mounted) return;
    if (result['allowed'] == true) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        widget.resumeRoute,
        (_) => false,
      );
      return;
    }

    final msg = result['message']?.toString() ?? 'Outside institute attendance radius.';
    final d = result['distance'];
    final extra = d is num ? ' (~${d.toDouble().toStringAsFixed(0)} m)' : '';

    setState(() {
      _checking = false;
      _message = '$msg$extra';
    });
  }

  Future<void> _signOut() async {
    await SessionManager.signOut();
    if (!mounted) return;
    // Full institute ID + password + CAPTCHA — do not resume PIN / biometric shortcut.
    Navigator.pushNamedAndRemoveUntil(
      context,
      LoginScreen.routeName,
      (_) => false,
      arguments: const {'forceFullLogin': true},
    );
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.location_disabled_rounded,
                          size: 64, color: AppTheme.accentRed.withValues(alpha: 0.85)),
                      const SizedBox(height: 20),
                      Text(
                        _checking ? 'Verifying location' : 'Out of institute radius — no access',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        _message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          height: 1.45,
                          fontSize: 14,
                          color: AppTheme.textGray,
                        ),
                      ),
                      if (!_checking) ...[
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: () => _runGate(),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.my_location_rounded),
                          label: const Text('Check location again'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _signOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_checking)
                        const Center(child: CircularProgressIndicator()),
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
