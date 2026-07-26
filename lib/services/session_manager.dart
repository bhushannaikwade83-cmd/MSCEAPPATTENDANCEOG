import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_db.dart';

/// Manages user sessions and session timeout (Supabase Auth).
class SessionManager {
  static DateTime? _lastActivity;
  static DateTime? _backgroundTime;
  static const Duration _sessionTimeout = Duration(minutes: 25);
  static const Duration _backgroundTimeout = Duration(minutes: 1);
  static const Duration _tokenRefreshInterval = Duration(minutes: 20);

  static void initialize() {
    appDb.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _lastActivity = DateTime.now();
        if (kDebugMode) debugPrint('✅ Session initialized for user: ${user.id}');
      } else {
        _lastActivity = null;
        if (kDebugMode) debugPrint('🔓 Session cleared');
      }
    });

    _startTokenRefreshTimer();
  }

  static void _startTokenRefreshTimer() {
    Future.delayed(_tokenRefreshInterval, () async {
      await refreshTokenIfNeeded();
      _startTokenRefreshTimer();
    });
  }

  static Future<void> refreshTokenIfNeeded() async {
    try {
      final session = appDb.auth.currentSession;
      if (session != null) {
        await appDb.auth.refreshSession();
        _lastActivity = DateTime.now();
        if (kDebugMode) debugPrint('🔄 Session refreshed');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Session refresh failed: $e');
    }
  }

  static void updateActivity() {
    _lastActivity = DateTime.now();
  }

  static void extendSession() {
    _lastActivity = DateTime.now();
  }

  static Duration? getRemainingTime() {
    if (_lastActivity == null) return null;
    final now = DateTime.now();
    final difference = now.difference(_lastActivity!);
    final remaining = _sessionTimeout - difference;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static void setBackgroundTime() {
    _backgroundTime = DateTime.now();
  }

  static void clearBackgroundTime() {
    _backgroundTime = null;
  }

  static DateTime? getBackgroundStartTime() {
    return _backgroundTime;
  }

  static bool isSessionValid() {
    if (_lastActivity == null) return false;

    final now = DateTime.now();

    if (_backgroundTime != null) {
      final backgroundDifference = now.difference(_backgroundTime!);
      if (backgroundDifference > _backgroundTimeout) {
        return false;
      }
    }

    final difference = now.difference(_lastActivity!);
    if (difference > _sessionTimeout) {
      return false;
    }

    return true;
  }

  static Future<void> checkAndRefreshSession() async {
    if (!isSessionValid()) {
      await appDb.auth.signOut();
      return;
    }
    await refreshTokenIfNeeded();
  }

  static Future<void> signOut() async {
    _lastActivity = null;
    await appDb.auth.signOut();
  }

  static User? getCurrentUser() {
    return appDb.auth.currentUser;
  }

  static bool isAuthenticated() {
    final user = appDb.auth.currentUser;
    if (user == null) return false;
    // Auth listener may lag one frame after sign-in; avoid false "logged out" during
    // navigation to the dashboard (SessionMonitor / timers use this).
    _lastActivity ??= DateTime.now();
    return isSessionValid();
  }
}
