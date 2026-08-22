import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateService {
  // Latest version available on PlayStore
  static const String LATEST_VERSION = '2.2.0';
  static const String PLAYSTORE_URL = 'https://play.google.com/store/apps/details?id=com.gcctbc.attendanceapp';

  /// Check if update available
  static Future<bool> isUpdateAvailable() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g., "2.1.0"

      print('📱 [UPDATE] Current: $currentVersion, Latest: $LATEST_VERSION');

      // Simple version comparison
      return _compareVersions(currentVersion, LATEST_VERSION) < 0;
    } catch (e) {
      print('⚠️ [UPDATE] Error checking version: $e');
      return false;
    }
  }

  /// Show update dialog
  static Future<void> showUpdateDialog(context) async {
    if (await isUpdateAvailable()) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('📲 New Version Available'),
          content: const Text('A new version of MSCE Attendance App is available.\n\n'
              '✨ Faster performance\n'
              '🎯 Better face matching\n'
              '🐛 Bug fixes'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _openPlayStore();
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      );
    }
  }

  /// Open PlayStore
  static Future<void> _openPlayStore() async {
    try {
      if (await canLaunchUrl(Uri.parse(PLAYSTORE_URL))) {
        await launchUrl(
          Uri.parse(PLAYSTORE_URL),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (e) {
      print('❌ [UPDATE] Could not open PlayStore: $e');
    }
  }

  /// Compare semantic versions
  /// Returns: -1 if v1 < v2, 0 if equal, 1 if v1 > v2
  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }
    return 0;
  }
}
