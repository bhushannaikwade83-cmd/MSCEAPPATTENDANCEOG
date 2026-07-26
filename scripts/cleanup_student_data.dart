import 'package:supabase_flutter/supabase_flutter.dart';

/// Cleanup script: Remove face embeddings and entry/exit photos for students 3 and 4
/// Run with: dart run scripts/cleanup_student_data.dart
Future<void> main() async {
  // Initialize Supabase with your credentials
  // NOTE: Update these with your actual Supabase URL and anon key
  const supabaseUrl = 'YOUR_SUPABASE_URL';
  const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  final db = Supabase.instance.client;

  // Target only institute 12345
  const instituteId = '12345';
  print('📍 Targeting institute: $instituteId');

  // Student sr_nos to clean
  const studentSrNos = [3, 4];

  for (final srNo in studentSrNos) {
    print('\n🧹 Cleaning student sr_no=$srNo...');

    try {
      // Fetch the student record
      final studentData = await db
          .from('students')
          .select()
          .eq('institute_id', instituteId)
          .eq('sr_no', srNo)
          .maybeSingle();

      if (studentData == null) {
        print('   ⚠️  Student sr_no=$srNo not found');
        continue;
      }

      print('   ✓ Found student: ${studentData['name']}');

      // Prepare the update payload
      // Clear:
      // - Face embedding/registration data
      // - Entry photos (entryPhoto, entryPhotoPath, entryPhotoFileId)
      // - Exit photos (exitPhoto, exitPhotoPath, exitPhotoFileId)

      final updatePayload = <String, dynamic>{
        // Clear face registration/embedding
        'face_embedding': null,
        'face_template': null,
        'embedding_hash': null,
        'photo_hash': null,

        // Clear entry photos
        'entryPhoto': null,
        'entryPhotoPath': null,
        'entryPhotoFileId': null,

        // Clear exit photos
        'exitPhoto': null,
        'exitPhotoPath': null,
        'exitPhotoFileId': null,

        // Also clear legacy photo fields
        'photoUrl': null,
        'storagePath': null,
      };

      // Update the student record
      await db.from('students').update(updatePayload).eq('id', studentData['id']);

      print('   ✅ Cleared face embedding and photos for sr_no=$srNo');
    } catch (e) {
      print('   ❌ Error cleaning student sr_no=$srNo: $e');
    }
  }

  print('\n✨ Cleanup complete!');
  print('📋 Students 3 and 4 have been refreshed:');
  print('   • Face embeddings cleared ✓');
  print('   • Entry photos removed ✓');
  print('   • Exit photos removed ✓');
  print('   • Ready for fresh face registration ✓');
}
