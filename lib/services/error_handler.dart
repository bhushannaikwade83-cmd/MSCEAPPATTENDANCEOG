import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, defaultTargetPlatform, kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_logger.dart';

/// Centralized error handling for sign-in and app data — messages are end-user safe (no stack traces).
class ErrorHandler {
  static String handleAuthException(AuthException e, {String? context, String? instituteId, String? appType}) {
    ErrorLogger.logError(
      error: e,
      context: context ?? 'auth',
      instituteId: instituteId,
      appType: appType,
    );

    if (kDebugMode) {
      debugPrint('🔴 AUTH ERROR${context != null ? " ($context)" : ""}: ${e.message}');
    }

    final msg = e.message.toLowerCase();
    if (msg.contains('invalid') && (msg.contains('credential') || msg.contains('password') || msg.contains('login'))) {
      return 'Invalid email or password. Please check your credentials and try again.';
    }
    if (msg.contains('email') && msg.contains('confirm')) {
      return 'Please confirm your email address before signing in.';
    }
    if (msg.contains('already registered') || msg.contains('user already')) {
      return 'This email is already registered. Please use a different email or try logging in.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    return 'Authentication failed. Please try again. If the problem persists, contact support.';
  }

  static String handlePostgrestError(PostgrestException e, {String? context, String? instituteId, String? appType}) {
    ErrorLogger.logError(
      error: e,
      context: context ?? 'database',
      instituteId: instituteId,
      appType: appType,
    );

    if (kDebugMode) {
      debugPrint('🔴 DATABASE ERROR${context != null ? " ($context)" : ""}: ${e.message}');
    }

    final c = e.code ?? '';
    if (c == '42501' || c == 'PGRST301') {
      return 'Permission denied. Please contact your administrator.';
    }
    if (c == 'PGRST116') {
      return 'The requested data was not found.';
    }
    return 'An error occurred while accessing data. Please try again.';
  }

  static String handleError(dynamic error, {String? context, String? instituteId, String? appType}) {
    ErrorLogger.logError(
      error: error,
      context: context ?? 'general',
      instituteId: instituteId,
      appType: appType,
    );

    if (kDebugMode) {
      debugPrint('🔴 ERROR${context != null ? " ($context)" : ""}: $error');
    }

    if (error is AuthException) {
      return handleAuthException(error, context: context, instituteId: instituteId, appType: appType);
    }
    if (error is PostgrestException) {
      return handlePostgrestError(error, context: context, instituteId: instituteId, appType: appType);
    }
    if (error is Exception) {
      return 'Something went wrong. Please try again. If it keeps happening, contact your institute administrator.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  static Map<String, dynamic> formatErrorForUI(dynamic error, {String? context, String? instituteId, String? appType}) {
    final message = handleError(error, context: context, instituteId: instituteId, appType: appType);
    return {
      'success': false,
      'message': message,
      'error': error.toString(),
    };
  }
}
