import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Biometric Authentication Service (IRCTC Style)
///
/// Provides fingerprint and face unlock functionality (per-admin per-device)
/// Each admin on this device has SEPARATE biometric login
class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();
  // CHANGED: Store list of biometric-enabled admins, not just one
  static const String _biometricAdminsKey = 'biometric_enabled_admins_json';
  /// Cleared on uninstall; when true we already showed "enable biometric?" this install.
  static const String _biometricSetupPromptShownKey = 'biometric_setup_prompt_shown';

  static Future<bool> wasBiometricSetupPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_biometricSetupPromptShownKey) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error reading biometric prompt flag: $e');
      return false;
    }
  }

  static Future<void> markBiometricSetupPromptShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricSetupPromptShownKey, true);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error saving biometric prompt flag: $e');
    }
  }

  /// True when the device can use biometric auth (hardware + at least one enrolled biometric).
  static Future<bool> isDeviceSupported() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      final enrolled = await _localAuth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking biometric support: $e');
      return false;
    }
  }

  /// Get available biometric types (fingerprint, face, etc.)
  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting available biometrics: $e');
      return [];
    }
  }

  /// Get list of admins with biometric enabled on THIS device
  static Future<List<String>> getBiometricEnabledAdmins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_biometricAdminsKey);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final List<dynamic> decoded = jsonDecode(jsonStr);
      return List<String>.from(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting biometric admins: $e');
      return [];
    }
  }

  /// Check if biometric authentication is enabled for THIS admin (email)
  static Future<bool> isBiometricEnabledForAdmin(String email) async {
    try {
      final admins = await getBiometricEnabledAdmins();
      return admins.contains(email.toLowerCase());
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking biometric for admin: $e');
      return false;
    }
  }

  /// Check if ANY admin has biometric enabled on this device
  /// (For backward compatibility with old code that didn't need email)
  static Future<bool> isBiometricEnabled() async {
    try {
      final admins = await getBiometricEnabledAdmins();
      return admins.isNotEmpty;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking if biometric is enabled: $e');
      return false;
    }
  }

  /// Enable biometric for THIS admin (add to list, don't overwrite others)
  static Future<bool> enableBiometric(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final admins = await getBiometricEnabledAdmins();
      final normalizedEmail = email.toLowerCase();

      if (!admins.contains(normalizedEmail)) {
        admins.add(normalizedEmail);
        await prefs.setString(_biometricAdminsKey, jsonEncode(admins));
        if (kDebugMode) {
          debugPrint('✅ Biometric enabled for admin: $email (total: ${admins.length})');
        }
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error enabling biometric: $e');
      return false;
    }
  }

  /// Disable biometric for THIS admin only (remove from list)
  static Future<bool> disableBiometric(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final admins = await getBiometricEnabledAdmins();
      final normalizedEmail = email.toLowerCase();

      admins.removeWhere((e) => e == normalizedEmail);

      if (admins.isEmpty) {
        // No admins left with biometric - remove the key
        await prefs.remove(_biometricAdminsKey);
        if (kDebugMode) debugPrint('✅ Biometric disabled for admin: $email (all removed)');
      } else {
        // Other admins still have biometric - keep the list
        await prefs.setString(_biometricAdminsKey, jsonEncode(admins));
        if (kDebugMode) {
          debugPrint('✅ Biometric disabled for admin: $email (${admins.length} remaining)');
        }
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error disabling biometric: $e');
      return false;
    }
  }

  /// Get the first admin with biometric enabled (for UI showing last logged in)
  /// NOTE: Better approach is to show list of biometric-enabled admins for user to choose
  @Deprecated('Use getBiometricEnabledAdmins() to show admin list instead')
  static Future<String?> getBiometricEmail() async {
    try {
      final admins = await getBiometricEnabledAdmins();
      return admins.isNotEmpty ? admins.first : null;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting biometric email: $e');
      return null;
    }
  }

  /// Authenticate using the device biometric (Face ID, fingerprint, etc.).
  ///
  /// [requirePreferenceEnabled]: when false, used for first-time setup so the OS
  /// can show Face ID / fingerprint permission and the user can confirm before
  /// we save [enableBiometric].
  ///
  /// [useErrorDialogs] is kept for call-site compatibility; local_auth 3.x does
  /// not expose this flag (the plugin uses fixed dialog behavior).
  static Future<bool> authenticate({
    String reason = 'Authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
    bool requirePreferenceEnabled = true,
  }) async {
    try {
      final isSupported = await isDeviceSupported();
      if (!isSupported) {
        if (kDebugMode) debugPrint('⚠️ No enrolled biometrics on this device');
        return false;
      }

      if (requirePreferenceEnabled) {
        // Check if ANY admin has biometric enabled on this device
        final adminsWithBiometric = await getBiometricEnabledAdmins();
        if (adminsWithBiometric.isEmpty) {
          if (kDebugMode) debugPrint('⚠️ No admin has biometric login enabled on this device');
          return false;
        }
      }

      // local_auth 3.x: options are top-level parameters (no AuthenticationOptions here).
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        sensitiveTransaction: false,
        persistAcrossBackgrounding: stickyAuth,
      );

      if (didAuthenticate) {
        if (kDebugMode) debugPrint('✅ Biometric authentication successful');
      } else {
        if (kDebugMode) debugPrint('❌ Biometric authentication failed or cancelled');
      }

      return didAuthenticate;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Biometric authentication error: ${e.code} - ${e.message}');
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error during biometric authentication: $e');
      return false;
    }
  }

  /// Stop authentication (if in progress)
  static Future<void> stopAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error stopping authentication: $e');
    }
  }

  /// Get biometric type name for display
  static String getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.strong:
        return 'Strong Biometric';
      case BiometricType.weak:
        return 'Biometric';
      case BiometricType.iris:
        return 'Iris';
      default:
        return 'Biometric';
    }
  }

  /// Get all available biometric types as string list
  static Future<List<String>> getAvailableBiometricNames() async {
    final types = await getAvailableBiometrics();
    return types.map((type) => getBiometricTypeName(type)).toList();
  }
}
