import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import './b2b_storage_service.dart';

class AttendancePhotoService {
  // Backblaze B2 bucket structure: DEC-2026/GCC/ATTENDANCE/{institute_id}/{student_name}/
  static const int MAX_SIZE_KB = 100;

  /// Compress and upload attendance photo to B2 (using working B2B service)
  static Future<String?> uploadAttendancePhoto({
    required File photoFile,
    required String srNo,
    required String studentName,
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

      // 3. Upload to B2 using working B2BStorageService
      // Path: DEC-2026/GCC/ATTENDANCE/{institute_id}/{student_name}/{entry/exit}_{sr_no}_{timestamp}.jpg
      final fileName = _generateFileName(srNo, recordType);
      final filePath = 'DEC-2026/GCC/ATTENDANCE/$instituteId/$studentName/$fileName';

      print('   📤 Uploading to B2: $filePath');

      final publicUrl = await B2BStorageService.uploadFile(
        filePath,
        compressedBytes,
        contentType: 'image/jpeg',
      );

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

  /// Generate standardized filename: {entry/exit}_{sr_no}_{timestamp}.jpg
  static String _generateFileName(String srNo, String recordType) {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    return '${recordType}_${srNo}_$timestamp.jpg';
  }

  /// Delete old attendance photos (use B2BStorageService.deleteAttendancePhoto instead)
  static Future<void> deletePhotoIfExists({
    required String objectPath,
  }) async {
    try {
      if (objectPath.isEmpty) return;
      await B2BStorageService.deleteAttendancePhoto(objectPath);
      print('🗑️ Deleted old photo: $objectPath');
    } catch (e) {
      print('⚠️ Could not delete photo: $e');
    }
  }
}
