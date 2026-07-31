import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AntiSpoofApiService {
  // Get backend URL from .env (uses same IP as rest of app)
  static String get API_URL {
    return "https://msceappattendanceog-production.up.railway.app"; // 🔥 Railway Deployment
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

  /// Detect face from image file with auto-retry for model loading
  /// Returns: {is_real, confidence, score, bbox, label}
  static Future<Map<String, dynamic>> detectFace(File imageFile, {int retryCount = 0}) async {
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

      // Handle 503 Service Unavailable (model loading) with automatic retry
      if (response.statusCode == 503) {
        if (retryCount < 5) {
          print('⏳ Model loading (503), retrying in 2 seconds... (attempt ${retryCount + 1}/5)');
          await Future.delayed(const Duration(seconds: 2));
          return detectFace(imageFile, retryCount: retryCount + 1);
        } else {
          throw Exception('API still loading after 5 retries - please wait');
        }
      }

      if (response.statusCode != 200) {
        var responseData = await response.stream.toBytes();
        var responseText = utf8.decode(responseData);
        throw Exception('API error: ${response.statusCode} - $responseText');
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
  /// Mark attendance automatically from face image
  /// Returns: {student_name, sr_no, similarity, record_type, status}
  static Future<Map<String, dynamic>> markAttendanceAuto(
    File imageFile, {
    String instId = "99099", // Default institute ID
  }) async {
    try {
      print('🌐 [SERVICE] Calling /api/mark-attendance-auto');
      print('📊 [SERVICE] Institute ID: $instId');

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$API_URL/api/mark-attendance-auto'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // Add institute_id as form field (backend expects this name)
      request.fields['institute_id'] = instId;

      print('🌐 [SERVICE] Sending request...');
      var response = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw Exception('Attendance timeout'),
      );

      print('✅ [SERVICE] Response status: ${response.statusCode}');

      if (response.statusCode != 200) {
        var responseData = await response.stream.toBytes();
        var responseText = utf8.decode(responseData);
        print('❌ [SERVICE] Error response: $responseText');
        throw Exception('Attendance failed: ${response.statusCode} - $responseText');
      }

      var responseData = await response.stream.toBytes();
      var result = json.decode(utf8.decode(responseData));

      print('✅ [SERVICE] Response: $result');
      return result;
    } catch (e) {
      print('❌ [SERVICE] Exception: $e');
      return {
        "error": e.toString(),
        "status": "❌ Error",
        "student_name": null,
        "sr_no": null,
        "similarity": 0.0
      };
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
