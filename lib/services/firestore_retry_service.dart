import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Retries DB / network operations with exponential backoff (legacy name kept).
class FirestoreRetryService {
  static const int maxRetries = 3;
  static const Duration initialDelay = Duration(seconds: 1);
  static const double backoffMultiplier = 2.0;

  static Future<T> executeWithRetry<T>({
    required Future<T> Function() operation,
    String? operationName,
    int maxRetries = maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;
    Object? lastError;

    while (attempt < maxRetries) {
      try {
        return await operation();
      } on SocketException catch (e) {
        lastError = e;
        attempt++;
        if (attempt >= maxRetries) rethrow;
        if (kDebugMode) {
          debugPrint('⚠️ Socket error (attempt $attempt/$maxRetries): $operationName');
        }
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).round(),
        );
        await Future.delayed(Duration(milliseconds: Random().nextInt(500)));
      } on TimeoutException catch (e) {
        lastError = e;
        attempt++;
        if (attempt >= maxRetries) rethrow;
        if (kDebugMode) {
          debugPrint('⚠️ Timeout (attempt $attempt/$maxRetries): $operationName');
        }
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).round(),
        );
        await Future.delayed(Duration(milliseconds: Random().nextInt(500)));
      } on PostgrestException catch (e) {
        lastError = e;
        final code = e.code;
        if (!_isRetryableHttp(code)) {
          if (kDebugMode) {
            debugPrint('❌ Non-retryable PostgREST error: $code');
          }
          rethrow;
        }
        attempt++;
        if (kDebugMode) {
          debugPrint('⚠️ PostgREST (attempt $attempt/$maxRetries): $code ${e.message}');
        }
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).round(),
        );
        await Future.delayed(Duration(milliseconds: Random().nextInt(500)));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Non-retryable error: $e');
        }
        rethrow;
      }
    }

    throw lastError ?? Exception('Unknown error after $maxRetries attempts');
  }

  static bool _isRetryableHttp(String? code) {
    if (code == null) return false;
    return code == '503' ||
        code == '502' ||
        code == '504' ||
        code == '500' ||
        code == '408' ||
        code == '429';
  }

  static String getUserFriendlyMessage(Object e) {
    if (e is PostgrestException) {
      final c = e.code ?? '';
      if (c == '42501' || c == 'PGRST301') {
        return 'You do not have permission to perform this action.';
      }
      return e.message;
    }
    return e.toString();
  }

  static bool isNetworkError(Object e) {
    return e is SocketException ||
        e is TimeoutException ||
        (e is PostgrestException && _isRetryableHttp(e.code));
  }
}
