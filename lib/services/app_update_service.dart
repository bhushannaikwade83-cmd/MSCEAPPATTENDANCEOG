import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 📲 App Update Service - Notify users about new version on Google Play
class AppUpdateService {
  static const String GOOGLE_PLAY_URL =
      'https://play.google.com/store/apps/details?id=com.msce.msceappattendance';

  // Minimum version that requires update
  static const String LATEST_VERSION = '2.1.0';

  /// 🔍 Check if update is available
  static Future<bool> isUpdateAvailable() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "2.0.0"

      print('🔄 [UPDATE] Current version: $currentVersion');
      print('🔄 [UPDATE] Latest version: $LATEST_VERSION');

      // Simple version comparison
      final isOlder = _isVersionOlder(currentVersion, LATEST_VERSION);

      if (isOlder) {
        print('⚠️ [UPDATE] New version available: $LATEST_VERSION');
        return true;
      }

      print('✅ [UPDATE] App is up to date');
      return false;
    } catch (e) {
      print('❌ [UPDATE] Error checking version: $e');
      return false;
    }
  }

  /// 📱 Show update dialog
  static void showUpdateDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force user to update
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 New Version Available!'),
        content: const Text(
          '📲 MSCE Attendance v2.1.0\n\n'
          '✨ NEW FEATURES:\n'
          '• Geofencing (25m radius)\n'
          '• GPS-verified login\n'
          '• Location tracking\n'
          '• Instructor management\n\n'
          '🔒 SECURITY:\n'
          '• Fake GPS detection\n'
          '• Enhanced privacy\n\n'
          'Please update to enjoy new features!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _openGooglePlay();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  /// 🛒 Open Google Play Store to update
  static Future<void> _openGooglePlay() async {
    try {
      if (await canLaunchUrl(Uri.parse(GOOGLE_PLAY_URL))) {
        await launchUrl(
          Uri.parse(GOOGLE_PLAY_URL),
          mode: LaunchMode.externalApplication,
        );
      } else {
        print('❌ [UPDATE] Could not open Google Play');
      }
    } catch (e) {
      print('❌ [UPDATE] Error opening Google Play: $e');
    }
  }

  /// 🔢 Compare version strings (e.g., "2.0.0" vs "2.1.0")
  static bool _isVersionOlder(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final currPart = i < currentParts.length ? currentParts[i] : 0;
        final latestPart = i < latestParts.length ? latestParts[i] : 0;

        if (currPart < latestPart) return true;
        if (currPart > latestPart) return false;
      }

      return false; // Same version
    } catch (e) {
      print('❌ [UPDATE] Error comparing versions: $e');
      return false;
    }
  }
}
