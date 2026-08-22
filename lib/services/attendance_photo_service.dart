import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

class AttendancePhotoService {
  // ✅ Upload to YOUR SERVER (not B2!)
  static const String SERVER_URL = "https://api.digitrixmedia.com";
  static const int MAX_SIZE_KB = 50; // Compress aggressively

  /// Upload attendance photo to PHP API
  static Future<String?> uploadAttendancePhoto({
    required File photoFile,
    required String srNo,
    required String studentName,
    required String instituteId,
    required String recordType, // 'entry' or 'exit'
  }) async {
    try {
      print('📸 [PHOTO] Starting upload for $srNo ($recordType)...');

      // 1. Read and compress
      final bytes = await photoFile.readAsBytes();
      print('   Original: ${(bytes.length / 1024).toStringAsFixed(1)} KB');

      final compressedBytes = await _compressImage(bytes);
      print('   Compressed: ${(compressedBytes.length / 1024).toStringAsFixed(1)} KB');

      // 2. Upload to PHP API
      print('   📤 Uploading to PHP API...');
      final photoUploadStart = DateTime.now();

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://digitrixmedia.com/msceattendanceapp/api/upload.php'),
      );

      // Add metadata
      request.fields['sr_no'] = srNo;
      request.fields['institute_id'] = instituteId;
      request.fields['record_type'] = recordType;
      request.fields['date'] = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Add compressed photo
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          compressedBytes,
          filename: '${srNo}_${recordType}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

      // Send request
      var response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Upload timeout after 30s'),
      );

      final uploadMs = DateTime.now().difference(photoUploadStart).inMilliseconds;

      if (response.statusCode != 200) {
        var errorBody = await response.stream.bytesToString();
        print('   ❌ Server error: ${response.statusCode}');
        print('   $errorBody');
        return null;
      }

      // Parse response
      var responseData = await response.stream.toBytes();
      var result = json.decode(utf8.decode(responseData));

      if (result['success'] == true) {
        final photoUrl = result['photo_url'] as String?;
        print('   ✅ Uploaded in ${uploadMs}ms');
        print('   📷 URL: $photoUrl');
        return photoUrl;
      } else {
        print('   ❌ Upload failed: ${result['error']}');
        return null;
      }
    } catch (e) {
      print('   ❌ Exception: $e');
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

  /// Delete old attendance photos (server-based, no deletion needed)
  static Future<void> deletePhotoIfExists({
    required String objectPath,
  }) async {
    // Photos stored on server - no need to delete
    print('ℹ️ Photos stored on server - no deletion needed');
  }
}
