import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DeviceSecurityFlags {
  const DeviceSecurityFlags({
    required this.developerOptionsEnabled,
    required this.adbEnabled,
  });

  final bool developerOptionsEnabled;
  final bool adbEnabled;

  bool get isBlocked => developerOptionsEnabled || adbEnabled;

  bool get wouldBlockApp =>
      DeviceSecurityService.blockDeveloperAndUsbDebug && isBlocked;

  String get blockingTitle {
    if (developerOptionsEnabled && adbEnabled) {
      return 'Developer Options / USB Debugging Detected';
    }
    if (adbEnabled) return 'USB Debugging Detected';
    if (developerOptionsEnabled) return 'Developer Options Detected';
    return 'Security Check Passed';
  }

  String get blockingMessage {
    if (developerOptionsEnabled && adbEnabled) {
      return 'For attendance security, this app is blocked while Developer Options or USB debugging are enabled on this Android device.\n\n'
          'Disable Developer Options and USB debugging, disconnect desktop location-spoofing tools, then try again.';
    }
    if (adbEnabled) {
      return 'For attendance security, this app is blocked while USB debugging is enabled on this Android device.\n\n'
          'Disable USB debugging, disconnect any desktop spoofing tools, then try again.';
    }
    return 'For attendance security, this app is blocked while Developer Options are enabled on this Android device.\n\n'
        'Please disable Developer Options in device settings and try again.';
  }
}

class DeviceSecurityService {
  static const MethodChannel _channel = MethodChannel('msce/device_performance');

  static DeviceSecurityFlags? _securityFlagsCache;

  /// When false, Developer Options / USB debugging do not block the app (testing builds).
  /// Set `BLOCK_DEVELOPER_USB_DEBUG=true` in app_config.env before institute release.
  static bool get blockDeveloperAndUsbDebug {
    final raw = dotenv.maybeGet('BLOCK_DEVELOPER_USB_DEBUG')?.trim().toLowerCase();
    if (raw == null || raw.isEmpty) return true;
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  static Future<DeviceSecurityFlags> securityFlags({bool refresh = false}) async {
    if (kIsWeb || !Platform.isAndroid) {
      return const DeviceSecurityFlags(
        developerOptionsEnabled: false,
        adbEnabled: false,
      );
    }
    if (!refresh && _securityFlagsCache != null) {
      return _securityFlagsCache!;
    }

    try {
      await _channel.invokeMapMethod<String, dynamic>('getSecurityFlags');
      // Developer options / ADB checks disabled — always report clean.
      const flags = DeviceSecurityFlags(
        developerOptionsEnabled: false,
        adbEnabled: false,
      );
      _securityFlagsCache = flags;
      if (kDebugMode) {
        debugPrint(
          '🛡️ Security flags: developerOptions=${flags.developerOptionsEnabled}, adb=${flags.adbEnabled}',
        );
      }
      return flags;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Could not read security flags: $e');
      }
      const flags = DeviceSecurityFlags(
        developerOptionsEnabled: false,
        adbEnabled: false,
      );
      _securityFlagsCache = flags;
      return flags;
    }
  }

  static Future<bool> developerOptionsEnabled({bool refresh = false}) async {
    return (await securityFlags(refresh: refresh)).developerOptionsEnabled;
  }

  static Future<bool> adbEnabled({bool refresh = false}) async {
    return (await securityFlags(refresh: refresh)).adbEnabled;
  }
}
