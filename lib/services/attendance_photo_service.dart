import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class AttendancePhotoService {
  // From B2B config: STORAGE_BUCKET_NAME=attendance-students-photos
  static const String STORAGE_BUCKET = 'attendance-students-photos';
  static const String STORAGE_PATH = 'attendance-photos';
  static const int MAX_SIZE_KB = 100;

  /// Compress and upload attendance photo to B2
  static Future<String?> uploadAttendancePhoto({
    required File photoFile,
    required String srNo,
    required String instituteId,
    required String recordType, // 'entry' or 'exit'
  }) async {
    try {
      print('📸 [PHOTO] Starting compression for $srNo ($recordType)...');

      // 1. Read original file
      final bytes = await photoFile.readAsBytes();
      print('   Original size: ${(bytes.length / 1024).toStringAsFixed(1)} KB');

      // 2. Compress image
      final compressedBytes = await _compressImage(bytes);
      final compressedKB = compressedBytes.length / 1024;
      print('   Compressed size: ${compressedKB.toStringAsFixed(1)} KB');

      if (compressedBytes.length > MAX_SIZE_KB * 1024) {
        print('   ⚠️ Still over ${MAX_SIZE_KB}KB, compressing more...');
        final ultraCompressed = await _compressImage(compressedBytes, quality: 60);
        print('   Final size: ${(ultraCompressed.length / 1024).toStringAsFixed(1)} KB');
      }

      // 3. Upload to Supabase storage
      final fileName = _generateFileName(srNo, instituteId, recordType);
      final filePath = '$STORAGE_PATH/$instituteId/$srNo/$fileName';

      print('   📤 Uploading to bucket: $STORAGE_BUCKET, path: $filePath');

      final supabase = Supabase.instance.client;
      await supabase.storage.from(STORAGE_BUCKET).uploadBinary(
        filePath,
        compressedBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600',
        ),
      );

      // 4. Generate public URL
      final publicUrl = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(filePath);
      print('   ✅ [PHOTO] Upload successful!');
      print('   📷 URL: $publicUrl');

      return publicUrl;
    } catch (e) {
      print('   ❌ [PHOTO] Upload failed: $e');
      return null;
    }
  }

  /// Compress image to target quality
  static Future<Uint8List> _compressImage(
    Uint8List imageBytes, {
    int quality = 75,
    int maxWidth = 800,
    int maxHeight = 800,
  }) async {
    try {
      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Resize if too large
      final resized = img.copyResize(
        image,
        width: maxWidth,
        height: maxHeight,
        interpolation: img.Interpolation.linear,
      );

      // Encode as JPEG with quality
      final compressed = img.encodeJpg(resized, quality: quality);
      return Uint8List.fromList(compressed);
    } catch (e) {
      print('   ⚠️ Compression error: $e, returning original');
      return imageBytes;
    }
  }

  /// Generate standardized filename
  static String _generateFileName(String srNo, String instituteId, String recordType) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${recordType}_${srNo}_$timestamp.jpg';
  }

  /// Get URL for a stored photo
  static String getPhotoUrl(String srNo, String instituteId, String fileName) {
    return '$STORAGE_PATH/$instituteId/$srNo/$fileName';
  }

  /// Delete old attendance photos (cleanup)
  static Future<void> deletePhotoIfExists({
    required String photoUrl,
  }) async {
    try {
      if (photoUrl.isEmpty) return;

      // Extract file path from URL
      final uri = Uri.parse(photoUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.isEmpty) return;

      // Get the file path (everything after domain)
      final filePath = pathSegments.join('/');

      final supabase = Supabase.instance.client;
      await supabase.storage.from(STORAGE_BUCKET).remove([filePath]);

      print('🗑️ Deleted old photo: $filePath');
    } catch (e) {
      print('⚠️ Could not delete photo: $e');
    }
  }
}
