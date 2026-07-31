import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class AttendancePhotoService {
  static const String B2_BUCKET = 'attendance-photos';
  static const int MAX_SIZE_KB = 100;
  static const String B2_URL_BASE =
      'https://f004.backblazeb2.com/file/attendance-photos';

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

      // 3. Upload to Supabase storage (which uses B2 backend)
      final fileName = _generateFileName(srNo, instituteId, recordType);
      final filePath = 'attendance/$instituteId/$srNo/$fileName';

      print('   📤 Uploading to B2: $filePath');

      final supabase = Supabase.instance.client;
      await supabase.storage.from(B2_BUCKET).uploadBinary(
        filePath,
        compressedBytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          cacheControl: '3600',
        ),
      );

      // 4. Generate public URL
      final publicUrl = supabase.storage.from(B2_BUCKET).getPublicUrl(filePath);
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
    return '$B2_URL_BASE/attendance/$instituteId/$srNo/$fileName';
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

      if (pathSegments.length < 3) return;

      // Remove first segment (bucket name is in domain)
      final filePath = pathSegments.skip(1).join('/');

      final supabase = Supabase.instance.client;
      await supabase.storage.from(B2_BUCKET).remove([filePath]);

      print('🗑️ Deleted old photo: $filePath');
    } catch (e) {
      print('⚠️ Could not delete photo: $e');
    }
  }
}
