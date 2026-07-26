import 'dart:io';

import 'package:http/io_client.dart';
import 'package:http/http.dart' as http;

/// HTTP client for Supabase REST. Uses platform TLS validation (no cleartext in release — see [applySupabaseNetworkOverrides]).
http.Client createSupabaseHttpClient() {
  final httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 35)
    ..idleTimeout = const Duration(seconds: 90)
    ..badCertificateCallback = (cert, host, port) {
      // Never pin or bypass validation here. Invalid certs must fail.
      return false;
    };
  return IOClient(httpClient);
}
