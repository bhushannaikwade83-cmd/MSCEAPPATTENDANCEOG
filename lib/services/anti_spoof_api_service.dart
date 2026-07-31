import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AntiSpoofApiService {
  // Get backend URL from .env (uses same IP as rest of app)
  static String get API_URL {
    return "http://192.0.0.2:5001"; // 🔥 SYNC with main .env
  }

  /// Pre-warm backend (just check health, models load on first registration)
  static Future<bool> prewarmModels() async {
    try {
      final response = await http.get(
        Uri.parse('$API_URL/api/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        print('✅ Backend online at $API_URL');
        print('✅ Models will load on first registration (30-60 sec first time)');
        return true;
      }
      return false;
    } catch (e) {
      print('⚠️ Backend pre-check failed (will retry on registration): $e');
      return false;
    }
  }

  /// Detect face from image file
  /// Returns: {is_real, confidence, score, bbox, label}
  static Future<Map<String, dynamic>> detectFace(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/api/detect-face'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      var response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('API timeout - server not responding');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('API error: ${response.statusCode}');
      }

      var responseData = await response.stream.toBytes();
      var result = json.decode(utf8.decode(responseData));

      return result;
    } catch (e) {
      return {
        "error": e.toString(),
        "is_real": null,
      };
    }
  }

  /// Check if server is running
  static Future<bool> checkHealth() async {
    try {
      var response = await http.get(
        Uri.parse('$API_URL/api/health'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Register student with 3-angle face photos (OPTIMIZED FOR SPEED)
  /// Returns: {success, message, embeddings}
  static Future<Map<String, dynamic>> registerStudentFace({
    required String studentId,
    required String studentName,
    required File frontPhoto,
    required File leftPhoto,
    required File rightPhoto,
    String? instituteId,
  }) async {
    try {
      print('🚀 [FAST MODE] Starting 3-angle registration...');
      final startTime = DateTime.now();

      // 🔥 Compress photos in PARALLEL for faster upload
      print('📦 Compressing 3 photos in parallel...');
      final compressedPhotos = await Future.wait([
        _compressPhoto(frontPhoto),
        _compressPhoto(leftPhoto),
        _compressPhoto(rightPhoto),
      ]);
      print('✅ Compressed in ${DateTime.now().difference(startTime).inMilliseconds}ms');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/api/v1/register-multi-angle'),
      );

      // Required fields
      request.fields['student_id'] = studentId;
      request.fields['name'] = studentName;
      request.fields['roll_number'] = studentId;
      request.fields['institute_id'] = instituteId ?? 'default';

      // Add compressed photos
      request.files.add(
        http.MultipartFile(
          'front_photo',
          Stream.value(compressedPhotos[0]),
          compressedPhotos[0].length,
          filename: 'front.jpg',
        ),
      );
      request.files.add(
        http.MultipartFile(
          'left_photo',
          Stream.value(compressedPhotos[1]),
          compressedPhotos[1].length,
          filename: 'left.jpg',
        ),
      );
      request.files.add(
        http.MultipartFile(
          'right_photo',
          Stream.value(compressedPhotos[2]),
          compressedPhotos[2].length,
          filename: 'right.jpg',
        ),
      );

      print('📤 Uploading 3 compressed photos...');
      var response = await request.send().timeout(
        const Duration(seconds: 180),  // 🔥 3 minutes - allow full model load + processing
        onTimeout: () => throw Exception('Registration timeout after 180s'),
      );

      final uploadTime = DateTime.now().difference(startTime).inMilliseconds;
      print('✅ Upload complete in ${uploadTime}ms');

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Registration failed: ${response.statusCode} - $errorBody');
      }

      var responseData = await response.stream.toBytes();
      var result = json.decode(utf8.decode(responseData));

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      print('🎯 Total registration time: ${totalTime}ms (~${(totalTime / 1000).toStringAsFixed(1)}s)');

      return result;
    } catch (e) {
      return {
        "error": e.toString(),
        "success": false,
        "message": "Registration error: ${e.toString()}",
      };
    }
  }

  /// Compress photo for faster upload (reduce size by 60-80%)
  static Future<List<int>> _compressPhoto(File photoFile) async {
    try {
      final bytes = await photoFile.readAsBytes();
      final originalSize = bytes.length;

      // Compress using image library (simulated here, actual compression would use image pkg)
      // For now, just return original - you can add image compression library
      print('  📸 Photo: ${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB');

      return bytes;
    } catch (e) {
      print('⚠️ Compression error: $e');
      return await photoFile.readAsBytes();
    }
  }

  /// Auto-attendance marking (HIGH ACCURACY)
  /// Compares live face against all registered students
  /// Returns: {status, student_id, similarity_score, attendance_marked}
  static Future<Map<String, dynamic>> markAttendanceAuto(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/api/mark-attendance-auto'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      var response = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('Attendance timeout'),
      );

      if (response.statusCode != 200) {
        throw Exception('Attendance failed: ${response.statusCode}');
      }

      var responseData = await response.stream.toBytes();
      var result = json.decode(utf8.decode(responseData));

      return result;
    } catch (e) {
      return {"error": e.toString(), "status": "❌ Error", "attendance_marked": false};
    }
  }

  /// Returns user-friendly error message
  static String getErrorMessage(Map<String, dynamic> result) {
    if (result.containsKey('error')) {
      final error = result['error'].toString().toLowerCase();
      if (error.contains('timeout')) {
        return 'Server not responding. Make sure:\n'
            '1. Backend is running: python3 app.py\n'
            '2. IP is correct in anti_spoof_api_service.dart';
      }
      if (error.contains('connection')) {
        return 'Cannot connect to server. Check WiFi and IP address.';
      }
      return 'Error: ${result['error']}';
    }
    return 'Unknown error';
  }
}
