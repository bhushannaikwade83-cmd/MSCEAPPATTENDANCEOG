import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_db.dart';

/// Legacy index check — Supabase uses SQL indexes (see migrations). No client index URLs.
class FirestoreIndexService {
  static const String _indexCheckKey = 'firestore_index_checked';
  static const String _indexCreatedKey = 'firestore_index_created';

  /// Verifies a simple indexed query on `students` succeeds.
  static Future<Map<String, dynamic>> checkIndexesNeeded({
    required String instituteId,
  }) async {
    try {
      await appDb
          .from('students')
          .select('id')
          .eq('institute_id', instituteId)
          .limit(1)
          .maybeSingle();

      if (kDebugMode) {
        debugPrint('✅ Students query OK (indexes assumed from SQL migrations)');
      }

      return {
        'needed': false,
        'indexUrl': null,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error checking DB query: $e');
      }
      return {
        'needed': false,
        'indexUrl': null,
      };
    }
  }

  static Future<bool> hasCheckedIndexes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_indexCheckKey) ?? false;
  }

  static Future<void> markIndexesChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_indexCheckKey, true);
  }

  static Future<bool> hasMarkedIndexesCreated() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_indexCreatedKey) ?? false;
  }

  static Future<void> markIndexesCreated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_indexCreatedKey, true);
  }

  static Future<void> resetIndexCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_indexCheckKey);
    await prefs.remove(_indexCreatedKey);
  }

  static Future<bool> openIndexCreationUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error opening URL: $e');
      }
      return false;
    }
  }

  static String getIndexInstructions() {
    return '''
Database indexes are defined in Supabase SQL migrations (see supabase/migrations).
Apply migrations in the Supabase Dashboard or with supabase db push.
''';
  }
}
