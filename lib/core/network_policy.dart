import 'package:flutter/foundation.dart' show kDebugMode, kReleaseMode;

/// Enforces trusted URLs for production builds (HTTPS, no accidental HTTP to cloud).
class NetworkPolicy {
  NetworkPolicy._();

  static bool _isDevLoopback(Uri u) {
    final h = u.host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '10.0.2.2' ||
        h.endsWith('.local');
  }

  /// Throws if [raw] is not a usable https URL for production APIs.
  /// In debug, allows http only to loopback (local backend).
  static Uri parseTrustedApiUrl(String raw, {String name = 'API'}) {
    final t = raw.trim();
    if (t.isEmpty) {
      throw ArgumentError('$name URL is empty');
    }
    late final Uri u;
    try {
      u = Uri.parse(t);
    } catch (e) {
      throw ArgumentError('$name URL is invalid: $raw');
    }
    if (!u.hasScheme || u.host.isEmpty) {
      throw ArgumentError('$name URL must include scheme and host: $raw');
    }
    final scheme = u.scheme.toLowerCase();
    if (scheme == 'https') return u;
    if (scheme == 'http' && kDebugMode && _isDevLoopback(u)) return u;
    if (scheme == 'http' && kReleaseMode) {
      throw StateError(
        '$name must use HTTPS in release builds (got $raw). '
        'MITM attackers can read or change traffic on plain HTTP.',
      );
    }
    throw StateError('$name must use https:// (or http:// to localhost in debug only). Got: $raw');
  }

  /// Same as [parseTrustedApiUrl] but returns null on failure (for optional backends).
  static Uri? tryParseTrustedApiUrl(String? raw, {String name = 'API'}) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return parseTrustedApiUrl(raw, name: name);
    } catch (_) {
      return null;
    }
  }
}
