import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../core/app_db.dart';

/// Service to add test/dummy data for development and testing
class TestDataService {
  static Future<void> addDummyStudents(String instituteId) async {
    if (!kDebugMode) {
      debugPrint('❌ Test data service only works in debug mode');
      return;
    }

    try {
      debugPrint('🧪 Adding dummy students to institute: $instituteId');

      final dummyStudents = [
        {
          'first_name': 'Dummy',
          'last_name': '7',
          'sr_no': 7,
          'institute_id': instituteId,
          'year': 'Year 2026',
          'face_embedding': null,
          'face_photo_url': null,
        },
        {
          'first_name': 'Dummy',
          'last_name': '8',
          'sr_no': 8,
          'institute_id': instituteId,
          'year': 'Year 2026',
          'face_embedding': null,
          'face_photo_url': null,
        },
        {
          'first_name': 'Dummy',
          'last_name': '9',
          'sr_no': 9,
          'institute_id': instituteId,
          'year': 'Year 2026',
          'face_embedding': null,
          'face_photo_url': null,
        },
      ];

      for (final student in dummyStudents) {
        final response = await appDb
            .from('students')
            .insert(student)
            .select();

        debugPrint('✅ Added: ${student['first_name']} ${student['last_name']} (Roll ${student['sr_no']})');
        debugPrint('   ID: ${response.isNotEmpty ? response.first['id'] : 'unknown'}');
      }

      debugPrint('✅ All 3 dummy students added successfully!');
    } catch (e) {
      debugPrint('❌ Error adding dummy students: $e');
      rethrow;
    }
  }
}
