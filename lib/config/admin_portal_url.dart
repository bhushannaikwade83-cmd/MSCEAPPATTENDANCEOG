import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

/// Web admin portal (React app in sibling repo `msce-website/admin-portal-react`). Same Supabase project.
/// Set in `app_config.env`: `ADMIN_PORTAL_URL=https://your-domain.com` (or `http://localhost:5173` for dev).
class AdminPortalUrl {
  AdminPortalUrl._();

  static String? get raw => dotenv.env['ADMIN_PORTAL_URL']?.trim();

  static Uri? get uri {
    final r = raw;
    if (r == null || r.isEmpty) return null;
    return Uri.tryParse(r);
  }

  static bool get isConfigured => uri != null;

  /// Opens the admin portal in the browser / external app.
  static Future<bool> launch() async {
    final u = uri;
    if (u == null) return false;
    return launchUrl(u, mode: LaunchMode.externalApplication);
  }
}
