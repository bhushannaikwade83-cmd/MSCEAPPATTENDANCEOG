import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Verifies Supabase connectivity at startup (replaces FirestoreInitService).
///
/// Schema changes belong in `supabase/migrations` — not in the client. The old
/// AutoSchemaInit RPC path added latency on first login by scanning many columns.
class DatabaseInitService {
  static bool _initialized = false;

  /// Runs once per app launch to ensure DB is reachable before writes.
  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    await initializeAll();
    _initialized = true;
  }

  static Future<void> initializeAll() async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await Supabase.instance.client.from('institutes').select('id').limit(1);
        if (kDebugMode) debugPrint('✅ Database (Supabase) reachable');
        return;
      } catch (e) {
        final retry = attempt == 1 && _isRetryable(e);
        if (kDebugMode) {
          debugPrint(
            retry
                ? '⚠️ Database init attempt $attempt failed, retrying: $e'
                : '⚠️ Database init: $e',
          );
        }
        if (!retry) return;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  static bool _isRetryable(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('socketexception');
  }
}
