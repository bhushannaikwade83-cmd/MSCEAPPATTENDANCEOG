import 'dart:async';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'pin_session_manager.dart';

/// 🌙 Automatic midnight logout service for PIN sessions
///
/// Monitors PIN sessions and automatically logs them out at midnight (12:00 AM).
/// Session is valid from login time until 11:59:59 PM same day.
/// At midnight, session is automatically cleared and user must re-login next day.
class PinMidnightLogoutService {
  static Timer? _midnightLogoutTimer;

  /// Start monitoring for midnight and auto-logout PIN session
  /// Call this AFTER successful PIN login
  static void startMidnightMonitor() {
    _stopTimer();

    final now = DateTime.now();

    // Calculate midnight of tomorrow (start of next day)
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));

    // Duration from now until midnight
    final durationUntilMidnight = tomorrow.difference(now);

    if (kDebugMode) {
      final hours = durationUntilMidnight.inHours;
      final minutes = durationUntilMidnight.inMinutes % 60;
      debugPrint(
        '🌙 PIN Midnight Logout Monitor Started: '
        'Will auto-logout in ${hours}h ${minutes}m at ${tomorrow.toString()}',
      );
    }

    // Set timer to trigger at midnight
    _midnightLogoutTimer = Timer(durationUntilMidnight, _onMidnightReached);
  }

  /// Called when midnight is reached - auto-logout
  static Future<void> _onMidnightReached() async {
    if (kDebugMode) {
      debugPrint('🌙 MIDNIGHT REACHED: Auto-logging out PIN session...');
    }

    try {
      // Clear PIN session
      await PinSessionManager.clearPinSession();

      if (kDebugMode) {
        debugPrint('✅ PIN Session cleared at midnight');
      }

      // Restart timer for next midnight (if new session is created)
      // startMidnightMonitor() will be called again when user logs in tomorrow
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error during midnight logout: $e');
      }
    }
  }

  /// Stop the midnight logout timer (internal use)
  static void _stopTimer() {
    _midnightLogoutTimer?.cancel();
    _midnightLogoutTimer = null;
  }

  /// Stop monitoring - call when user manually logs out or app exits
  static void stopMonitoring() {
    _stopTimer();
    if (kDebugMode) {
      debugPrint('🛑 PIN Midnight Logout Monitor Stopped');
    }
  }

  /// Get time remaining until midnight
  static Duration getTimeUntilMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
    return tomorrow.difference(now);
  }

  /// Get formatted time string until midnight
  /// Returns "2h 15m" format
  static String getTimeUntilMidnightFormatted() {
    final duration = getTimeUntilMidnight();
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// Restart monitor (use if app resumes and session is still valid)
  static void restartMidnightMonitor() {
    if (kDebugMode) {
      debugPrint('🔄 Restarting PIN Midnight Logout Monitor...');
    }
    startMidnightMonitor();
  }

  /// Check if monitoring is active
  static bool get isMonitoring => _midnightLogoutTimer != null;
}
