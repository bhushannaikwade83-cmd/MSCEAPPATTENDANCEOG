import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// First-launch permission gate so camera, location, and notifications are
/// requested consistently on all supported phones (Android / iOS).
class AppPermissionsService {
  AppPermissionsService._();

  static const String prefKeySetupDone = 'permissions_setup_done';

  static bool get shouldRunPermissionGate => !kIsWeb;

  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    return Geolocator.isLocationServiceEnabled();
  }

  static Future<void> openLocationSettings() => Geolocator.openLocationSettings();

  static Future<bool> openDeviceAppSettings() => openAppSettings();

  /// Read current status without prompting (for UI on permissions screen).
  static Future<Map<Permission, PermissionStatus>> currentCoreStatuses() async {
    if (kIsWeb) return {};
    final keys = await _corePermissionKeys();
    final out = <Permission, PermissionStatus>{};
    for (final p in keys) {
      out[p] = await p.status;
    }
    return out;
  }

  /// Camera + location are required; notifications and storage are optional.
  static Future<bool> areCorePermissionsGranted() async {
    if (kIsWeb) return true;
    final statuses = await currentCoreStatuses();
    return !criticalDenied(statuses);
  }

  /// Request one-by-one with pauses — rapid [request] calls on Android often
  /// skip camera/location dialogs after the first prompt.
  static Future<Map<Permission, PermissionStatus>> requestCorePermissions({
    void Function(Permission permission, PermissionStatus status)? onEachComplete,
  }) async {
    if (kIsWeb) return {};

    final out = <Permission, PermissionStatus>{};
    final keys = await _corePermissionKeys();

    for (final permission in keys) {
      var status = await permission.status;
      if (!status.isGranted && !status.isLimited) {
        status = await permission.request();
        // Android: second chance when user dismissed without choosing.
        if (!status.isGranted &&
            !status.isLimited &&
            !status.isPermanentlyDenied) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          status = await permission.request();
        }
      }
      out[permission] = status;
      onEachComplete?.call(permission, status);
      if (kDebugMode) {
        debugPrint('Permission $permission → $status');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return out;
  }

  /// First-launch gate: only attendance-critical permissions (fewer system dialogs).
  static Future<List<Permission>> _corePermissionKeys() async {
    return [
      Permission.camera,
      Permission.locationWhenInUse,
    ];
  }

  /// Optional permissions — not required to reach login.
  static Future<List<Permission>> optionalPermissionKeys() async {
    final list = <Permission>[];
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      list.add(Permission.notification);
    }
    return list;
  }

  static Future<void> requestOptionalPermissions() async {
    if (kIsWeb) return;
    for (final p in await optionalPermissionKeys()) {
      final s = await p.status;
      if (!s.isGranted && !s.isLimited) {
        await p.request();
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  static bool criticalDenied(Map<Permission, PermissionStatus> statuses) {
    final cam = _statusFor(statuses, Permission.camera);
    final loc = _statusFor(statuses, Permission.locationWhenInUse);
    return !cam.isGranted && !cam.isLimited ||
        !loc.isGranted && !loc.isLimited;
  }

  static PermissionStatus _statusFor(
    Map<Permission, PermissionStatus> statuses,
    Permission key,
  ) {
    return statuses[key] ?? PermissionStatus.denied;
  }

  static bool hasPermanentDenial(Map<Permission, PermissionStatus> statuses) {
    for (final s in statuses.values) {
      if (s.isPermanentlyDenied) return true;
    }
    return false;
  }

  static String labelForStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return 'Allowed';
    if (status.isPermanentlyDenied) return 'Blocked — open Settings';
    if (status.isDenied) return 'Not allowed yet';
    return status.toString();
  }
}
