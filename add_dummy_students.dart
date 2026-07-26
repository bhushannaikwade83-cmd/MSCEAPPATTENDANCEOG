import 'package:supabase_flutter/supabase_flutter.dart';

/// Script to add 3 dummy students (7, 8, 9) to institute 99099
void main() async {
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://snxcrqgodamoxwgkkqez.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNueGNycWdvZGFtb3h3Z2trenFxeiIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzExODcyMDAwLCJleHAiOjE4Njk2MzIwMDB9.3vhWvqb8cKdYrYHVLvGwW7C7pEfJpnx8Q7K8J8QQ8Ys',
  );

  final client = Supabase.instance.client;
  final instituteId = '99099';

  // Create 3 dummy students
  final students = [
    {
      'first_name': 'Dummy',
      'middle_name': '',
      'last_name': '7',
      'sr_no': 7,
      'institute_id': instituteId,
      'year': 'Year 2026',
      'face_embedding': null,
      'face_photo_url': null,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'first_name': 'Dummy',
      'middle_name': '',
      'last_name': '8',
      'sr_no': 8,
      'institute_id': instituteId,
      'year': 'Year 2026',
      'face_embedding': null,
      'face_photo_url': null,
      'created_at': DateTime.now().toIso8601String(),
    },
    {
      'first_name': 'Dummy',
      'middle_name': '',
      'last_name': '9',
      'sr_no': 9,
      'institute_id': instituteId,
      'year': 'Year 2026',
      'face_embedding': null,
      'face_photo_url': null,
      'created_at': DateTime.now().toIso8601String(),
    },
  ];

  try {
    for (final student in students) {
      final response = await client
          .from('students')
          .insert(student)
          .select();

      print('✅ Added student: ${student['first_name']} ${student['last_name']} (Roll ${student['sr_no']})');
      print('   Response: $response\n');
    }

    print('✅ All 3 dummy students added successfully to institute 99099!');
  } catch (e) {
    print('❌ Error adding students: $e');
  }
}
