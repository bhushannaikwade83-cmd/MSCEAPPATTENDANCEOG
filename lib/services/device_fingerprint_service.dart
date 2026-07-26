import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Service for device fingerprinting and tracking
/// Helps detect suspicious device changes and prevent misuse
class DeviceFingerprintService {
  static const String _deviceFingerprintKey = 'device_fingerprint';
  static const String _deviceHistoryKey = 'device_history';

  /// Get current device fingerprint
  static Future<Map<String, dynamic>> getDeviceFingerprint() async {
    try {
      if (kIsWeb) {
        const webId = 'web_browser';
        return {
          'platform': 'web',
          'userAgent': webId,
          'fingerprint': _generateFingerprint(
            platform: 'web',
            stableId: webId,
            model: webId,
          ),
        };
      }

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      Map<String, dynamic> deviceData = {};

      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        deviceData = {
          'platform': 'android',
          'deviceId': androidInfo.id, // Android ID
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'brand': androidInfo.brand,
          'device': androidInfo.device,
          'product': androidInfo.product,
          'hardware': androidInfo.hardware,
          'androidId': androidInfo.id,
          'fingerprint': _generateFingerprint(
            platform: 'android',
            stableId: androidInfo.id,
            model: androidInfo.model,
            manufacturer: androidInfo.manufacturer,
            brand: androidInfo.brand,
          ),
        };
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        deviceData = {
          'platform': 'ios',
          'deviceId': iosInfo.identifierForVendor ?? 'unknown',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemName': iosInfo.systemName,
          'systemVersion': iosInfo.systemVersion,
          'fingerprint': _generateFingerprint(
            platform: 'ios',
            stableId: iosInfo.identifierForVendor ?? 'unknown',
            model: iosInfo.model,
            manufacturer: iosInfo.name,
          ),
        };
      }

      // Store fingerprint
      await _storeFingerprint(deviceData);

      if (kDebugMode) {
        debugPrint('📱 Device Fingerprint: ${deviceData['fingerprint']}');
        debugPrint('   Platform: ${deviceData['platform']}');
        debugPrint('   Model: ${deviceData['model']}');
      }

      return deviceData;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting device fingerprint: $e');
      return {
        'platform': 'unknown',
        'fingerprint': 'unknown',
        'error': e.toString(),
      };
    }
  }

  /// Generate a unique fingerprint hash
  static String _generateFingerprint({
    required String platform,
    required String stableId,
    required String model,
    String? manufacturer,
    String? brand,
  }) {
    // Keep this deterministic for a given device installation profile.
    // Do not include time-based values, otherwise every call appears as a new device.
    final seed = [
      platform.trim().toLowerCase(),
      stableId.trim(),
      model.trim().toLowerCase(),
      (manufacturer ?? '').trim().toLowerCase(),
      (brand ?? '').trim().toLowerCase(),
    ].join('|');
    final bytes = utf8.encode(seed);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // Short hash
  }

  /// Store device fingerprint
  static Future<void> _storeFingerprint(Map<String, dynamic> fingerprint) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_deviceFingerprintKey, jsonEncode(fingerprint));

      // Store in history
      final historyJson = prefs.getString(_deviceHistoryKey) ?? '[]';
      final List<dynamic> history = jsonDecode(historyJson);
      
      // Add if not already exists
      final exists = history.any((h) => 
        h['fingerprint'] == fingerprint['fingerprint']
      );
      
      if (!exists) {
        history.add({
          ...fingerprint,
          'firstSeen': DateTime.now().toIso8601String(),
        });
        await prefs.setString(_deviceHistoryKey, jsonEncode(history));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error storing fingerprint: $e');
    }
  }

  /// Check if device has changed (suspicious activity)
  static Future<bool> hasDeviceChanged() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedJson = prefs.getString(_deviceFingerprintKey);
      
      if (storedJson == null) {
        // First time, store current device
        await getDeviceFingerprint();
        return false;
      }

      final stored = jsonDecode(storedJson) as Map<String, dynamic>;
      final current = await getDeviceFingerprint();

      // Compare fingerprints
      final hasChanged = stored['fingerprint'] != current['fingerprint'];
      
      if (hasChanged && kDebugMode) {
        debugPrint('⚠️ Device change detected!');
        debugPrint('   Old: ${stored['fingerprint']}');
        debugPrint('   New: ${current['fingerprint']}');
      }

      return hasChanged;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking device change: $e');
      return false;
    }
  }

  /// Get device history
  static Future<List<Map<String, dynamic>>> getDeviceHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_deviceHistoryKey) ?? '[]';
      final List<dynamic> history = jsonDecode(historyJson);
      return history.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting device history: $e');
      return [];
    }
  }

  /// Get device info for logging
  static Future<Map<String, dynamic>> getDeviceInfoForLogging() async {
    final fingerprint = await getDeviceFingerprint();
    return {
      'deviceId': fingerprint['deviceId'] ?? fingerprint['androidId'] ?? 'unknown',
      'model': fingerprint['model'] ?? 'unknown',
      'manufacturer': fingerprint['manufacturer'] ?? fingerprint['name'] ?? 'unknown',
      'platform': fingerprint['platform'] ?? 'unknown',
      'fingerprint': fingerprint['fingerprint'] ?? 'unknown',
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
