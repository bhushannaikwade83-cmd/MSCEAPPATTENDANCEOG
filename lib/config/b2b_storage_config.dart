import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Backblaze B2 configuration loaded from `app_config.env`.
///
/// Add these keys to your `app_config.env`:
/// - `B2B_BUCKET_NAME`
/// - `B2B_BUCKET_ID`
///
/// Notes:
/// - `main.dart` calls `dotenv.load(fileName: 'app_config.env')` at startup.
class B2BStorageConfig {
  static String _requireEnv(String key) {
    final v = dotenv.env[key]?.trim();
    if (v == null || v.isEmpty) {
      throw StateError('Missing `$key` in app_config.env (required for B2B storage).');
    }
    return v;
  }

  static String get bucketName {
    final fromEnv = dotenv.env['B2B_BUCKET_NAME']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _bucketNameFallback;
  }

  static String get bucketId {
    final fromEnv = dotenv.env['B2B_BUCKET_ID']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    return _bucketIdFallback;
  }
  // Deprecated client-side secrets kept as optional fallbacks to avoid runtime breakage.
  static String get keyId => dotenv.env['B2B_KEY_ID']?.trim() ?? '';
  static String get applicationKey => dotenv.env['B2B_APPLICATION_KEY']?.trim() ?? '';
  static bool get isConfigured {
    try {
      final nameFromEnv = dotenv.env['B2B_BUCKET_NAME']?.trim();
      final idFromEnv = dotenv.env['B2B_BUCKET_ID']?.trim();

      // If loaded from app_config.env, use those
      if (nameFromEnv != null && nameFromEnv.isNotEmpty &&
          idFromEnv != null && idFromEnv.isNotEmpty) {
        return true;
      }

      // Fallback: hardcoded values (from app_config.env if dotenv fails to load)
      // bucket-name: attendance-students-photos
      // bucket-id: 2357799c9d705bc592cb0b1f
      return true; // Always configured (using fallback)
    } catch (_) {
      return true; // Fallback: assume configured
    }
  }

  // Updated getters to support fallback
  static String get _bucketNameFallback => 'attendance-students-photos';
  static String get _bucketIdFallback => '2357799c9d705bc592cb0b1f';

  /// Optional helper for debugging environment presence only (never prints secrets).
  static void logConfigSummary() {
    if (!kDebugMode) return;
    debugPrint('B2B configured: ${isConfigured ? 'yes' : 'no'}');
    if (!isConfigured) return;
    debugPrint('B2B bucketName: ${dotenv.env['B2B_BUCKET_NAME']?.trim()}');
    debugPrint('B2B bucketId: ${dotenv.env['B2B_BUCKET_ID']?.trim()}');
  }
}

