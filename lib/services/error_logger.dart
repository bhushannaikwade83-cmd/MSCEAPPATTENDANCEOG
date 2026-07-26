import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';

/// Logs errors to Supabase `error_logs` for coder dashboard.
class ErrorLogger {
  static Future<void> logError({
    required dynamic error,
    required String context,
    String? userId,
    String? userEmail,
    String? instituteId,
    String? appType,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      String errorType = error.runtimeType.toString();
      String errorMessage = error.toString();
      String? errorCode;
      String? stackTrace;

      if (error is Exception) {
        errorCode = error.runtimeType.toString();
        errorMessage = error.toString();
      }
      if (error is AuthException) {
        errorCode = 'auth';
        errorMessage = error.message;
      }
      if (error is PostgrestException) {
        errorCode = error.code;
        errorMessage = error.message;
      }

      try {
        stackTrace = StackTrace.current.toString();
      } catch (_) {
        stackTrace = 'Stack trace not available';
      }

      String? loggedUserId = userId;
      String? loggedUserEmail = userEmail;
      try {
        final u = appDb.auth.currentUser;
        if (u != null) {
          loggedUserId = userId ?? u.id;
          loggedUserEmail = userEmail ?? u.email;
        }
      } catch (_) {}

      final errorData = {
        'error_type': errorType,
        'error_code': errorCode,
        'error_message': errorMessage,
        'stack_trace': stackTrace,
        'context': context,
        'user_id': loggedUserId,
        'user_email': loggedUserEmail,
        'institute_id': instituteId,
        'app_type': appType ?? 'admin',
        'device_info': {
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.toString(),
        },
        'additional_data': additionalData ?? {},
        'resolved': false,
        'resolved_at': null,
        'resolved_by': null,
      };

      try {
        await appDb.from('error_logs').insert(errorData);
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Failed to log error to Supabase: $e');
      }

      if (kDebugMode) {
        debugPrint('🔴 ERROR LOGGED: $context — $errorMessage');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Failed to log error: $e');
    }
  }

  static Future<void> markErrorResolved(String errorId, String resolvedBy) async {
    try {
      await appDb.from('error_logs').update({
        'resolved': true,
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'resolved_by': resolvedBy,
      }).eq('id', errorId);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to mark error as resolved: $e');
    }
  }

  static Future<void> deleteError(String errorId) async {
    try {
      await appDb.from('error_logs').delete().eq('id', errorId);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to delete error: $e');
    }
  }
}
