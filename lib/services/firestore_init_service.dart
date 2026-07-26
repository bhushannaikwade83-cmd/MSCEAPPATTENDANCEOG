import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Schema is managed by Supabase SQL migrations — no client-side collection init.
class FirestoreInitService {
  static Future<void> initializeAll() async {
    if (kDebugMode) {
      debugPrint('✅ DB: using Supabase migrations (no Firestore init)');
    }
  }

  static Future<void> initializeInstituteCollections(String instituteId) async {
    if (instituteId.isEmpty) return;
    if (kDebugMode) {
      debugPrint('✅ Institute data uses Postgres tables for: $instituteId');
    }
  }

  static Future<void> initializeHierarchicalStructure(String instituteCode) async {
    if (instituteCode.isEmpty) return;
    if (kDebugMode) {
      debugPrint('✅ Attendance uses attendance_in_out for: $instituteCode');
    }
  }

  static String? getIndexCreationLink(String errorMessage) {
    final regex = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
    final match = regex.firstMatch(errorMessage);
    return match?.group(0);
  }

  static bool isIndexError(dynamic error) {
    if (error == null) return false;
    final errorString = error.toString().toLowerCase();
    return errorString.contains('index') &&
        (errorString.contains('failed-precondition') || errorString.contains('postgres'));
  }
}
