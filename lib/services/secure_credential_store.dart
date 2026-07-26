import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores small secrets (e.g. biometric XOR key) in Keychain / EncryptedSharedPreferences.
/// Web falls back to SharedPreferences (weaker); use biometrics primarily on mobile.
class SecureCredentialStore {
  SecureCredentialStore._();

  static final FlutterSecureStorage _mobile = FlutterSecureStorage(
    aOptions: const AndroidOptions(),
    iOptions: const IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<String?> read(String key) async {
    if (kIsWeb) {
      final p = await SharedPreferences.getInstance();
      return p.getString('sec_$key');
    }
    return _mobile.read(key: key);
  }

  static Future<void> write(String key, String value) async {
    if (kIsWeb) {
      final p = await SharedPreferences.getInstance();
      await p.setString('sec_$key', value);
      return;
    }
    await _mobile.write(key: key, value: value);
  }

  static Future<void> delete(String key) async {
    if (kIsWeb) {
      final p = await SharedPreferences.getInstance();
      await p.remove('sec_$key');
      return;
    }
    await _mobile.delete(key: key);
  }
}
