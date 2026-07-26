import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_env.dart';
import '../../core/theme/app_theme.dart';
import '../../services/app_permissions_service.dart';
import 'biometric_lock_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';

/// Shown once at first launch (before onboarding / login / biometric) to request
/// camera, location, and notification permissions in a consistent order on all devices.
class AppPermissionsScreen extends StatefulWidget {
  static const routeName = '/app-permissions';

  const AppPermissionsScreen({super.key});

  @override
  State<AppPermissionsScreen> createState() => _AppPermissionsScreenState();
}

class _AppPermissionsScreenState extends State<AppPermissionsScreen> {
  bool _busy = false;
  String? _busyLabel;
  Map<Permission, PermissionStatus> _statuses = {};
  bool _askedOnce = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _refreshStatuses();
    if (!mounted) return;
    // Already allowed on a previous install / system settings — skip this screen.
    if (await AppPermissionsService.areCorePermissionsGranted()) {
      await _finishAndNavigate();
    }
  }

  Future<void> _refreshStatuses() async {
    final s = await AppPermissionsService.currentCoreStatuses();
    if (mounted) setState(() => _statuses = s);
  }

  Future<void> _finishAndNavigate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppPermissionsService.prefKeySetupDone, true);
    if (!mounted) return;

    final user = SupabaseEnv.isReady
        ? Supabase.instance.client.auth.currentUser
        : null;
    if (user != null) {
      Navigator.pushReplacementNamed(context, BiometricLockScreen.routeName);
    } else {
      final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
      if (onboardingCompleted) {
        Navigator.pushReplacementNamed(context, LoginScreen.routeName);
      } else {
        Navigator.pushReplacementNamed(context, OnboardingScreen.routeName);
      }
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _busy = true;
      _busyLabel = 'Checking GPS…';
    });

    try {
      final locOn = await AppPermissionsService.isLocationServiceEnabled();
      if (!locOn && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Turn on location (GPS)'),
            content: const Text(
              'Location must be ON for attendance GPS checks. Enable it in system settings, then tap Allow access again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  AppPermissionsService.openLocationSettings();
                },
                child: const Text('Open location settings'),
              ),
            ],
          ),
        );
      }

      if (!mounted) return;
      setState(() => _busyLabel = 'Requesting permissions…');

      final statuses = await AppPermissionsService.requestCorePermissions(
        onEachComplete: (permission, status) {
          if (!mounted) return;
          setState(() {
            _statuses = Map<Permission, PermissionStatus>.from(_statuses)
              ..[permission] = status;
            _busyLabel = _labelForPermission(permission);
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _statuses = statuses;
        _askedOnce = true;
        _busy = false;
        _busyLabel = null;
      });

      // Camera + location OK → optional prompts in background, then login (no second tap).
      if (!AppPermissionsService.criticalDenied(statuses)) {
        unawaited(AppPermissionsService.requestOptionalPermissions());
        await _finishAndNavigate();
        return;
      }

      if (AppPermissionsService.hasPermanentDenial(statuses) && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permissions blocked'),
            content: const Text(
              'Camera or location was denied with "Don\'t ask again". '
              'Open App settings and allow Camera and Location for MSCE Attendance App.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  AppPermissionsService.openDeviceAppSettings();
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
      } else if (AppPermissionsService.criticalDenied(statuses) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera and location are required. Tap Allow access again or use Open app settings.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not request permissions: $e')),
        );
      }
    }
  }

  String _labelForPermission(Permission p) {
    if (p == Permission.camera) return 'Requesting camera…';
    if (p == Permission.locationWhenInUse) return 'Requesting location…';
    if (p == Permission.notification) return 'Requesting notifications…';
    if (p == Permission.storage || p == Permission.photos) return 'Requesting storage…';
    return 'Requesting…';
  }

  PermissionStatus? _status(Permission p) => _statuses[p];

  @override
  Widget build(BuildContext context) {
    final permanentlyDenied =
        _statuses.isNotEmpty && AppPermissionsService.hasPermanentDenial(_statuses);

    return Scaffold(
      backgroundColor: AppTheme.backgroundOffWhite,
      appBar: AppBar(
        title: const Text('Permissions'),
        centerTitle: true,
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Allow access for MSCE Attendance App',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Tap Continue — allow Camera and Location when asked. '
                'Notifications and storage are optional; you will go to login right after.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.textGray,
                      height: 1.4,
                    ),
              ),
              if (_busy && _busyLabel != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _busyLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              _tile(
                icon: Icons.camera_alt_rounded,
                title: 'Camera',
                subtitle: 'Take photos for attendance and student enrollment.',
                status: _status(Permission.camera),
              ),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.location_on_outlined,
                title: 'Location',
                subtitle: 'Confirm you are within the institute area when marking attendance.',
                status: _status(Permission.locationWhenInUse),
              ),
              const SizedBox(height: 8),
              Text(
                'Notifications and file access may be asked after you sign in (optional).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const Spacer(),
              if (permanentlyDenied)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => AppPermissionsService.openDeviceAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('Open app settings'),
                ),
              if (permanentlyDenied) const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (!AppPermissionsService.criticalDenied(_statuses)) {
                          await _finishAndNavigate();
                          return;
                        }
                        await _requestPermissions();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Continue'),
              ),
              if (_askedOnce &&
                  AppPermissionsService.criticalDenied(_statuses)) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _requestPermissions,
                  child: const Text('Try permissions again'),
                ),
                TextButton(
                  onPressed: _busy ? null : _finishAndNavigate,
                  child: const Text('Skip to login (limited features)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    PermissionStatus? status,
  }) {
    Color chipColor = Colors.grey.shade600;
    IconData chipIcon = Icons.help_outline;
    String chipText = 'Waiting';

    if (status != null) {
      if (status.isGranted || status.isLimited) {
        chipColor = Colors.green.shade700;
        chipIcon = Icons.check_circle;
        chipText = 'Allowed';
      } else if (status.isPermanentlyDenied) {
        chipColor = Colors.red.shade700;
        chipIcon = Icons.block;
        chipText = 'Blocked';
      } else if (status.isDenied) {
        chipColor = Colors.orange.shade800;
        chipIcon = Icons.warning_amber;
        chipText = 'Denied';
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.primaryBlue, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(chipIcon, size: 16, color: chipColor),
                  const SizedBox(width: 4),
                  Text(
                    chipText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: chipColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
