import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;

/// Call from [main] before [Supabase.initialize] (and before any HTTP).
///
/// - Skips broken Wi‑Fi / WPAD proxies (`DIRECT`) so Supabase REST/auth can reach the internet.
/// - Uses the platform default TLS stack (no custom [connectionFactory]) — custom
///   SecureSocket wiring often caused 28s timeouts on some Samsung/Android devices.
void applySupabaseNetworkOverrides() {
  HttpOverrides.global = _SupabaseFriendlyHttpOverrides();
}

final class _SupabaseFriendlyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context)
      ..connectionTimeout = const Duration(seconds: 35)
      ..idleTimeout = const Duration(seconds: 90)
      ..findProxy = (Uri uri) => 'DIRECT';

    if (kReleaseMode) {
      client.badCertificateCallback = (_, __, ___) => false;
    }

    return client;
  }
}
