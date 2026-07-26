/// InsightFace API Service
/// Communicates with professional face recognition backend
/// Uses: InsightFace, FAISS, MiniFASNet

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../core/network_policy.dart';
import '../core/production_face_recognition_constants.dart';

class InsightFaceApiService {
  /// Set `INSIGHTFACE_API_BASE=https://your.host/api/v1` in `app_config.env` (HTTPS required in release).
  static Uri? _baseUri() {
    final raw = dotenv.env['INSIGHTFACE_API_BASE']?.trim();
    if (raw == null || raw.isEmpty) return null;
    return NetworkPolicy.tryParseTrustedApiUrl(raw, name: 'INSIGHTFACE_API_BASE');
  }

  static Uri? _apiUrl(String suffix) {
    final b = _baseUri();
    if (b == null) return null;
    final root = b.toString().replaceAll(RegExp(r'/+$'), '');
    final path = suffix.startsWith('/') ? suffix : '/$suffix';
    return Uri.parse('$root$path');
  }

  static Uri? _healthUri() {
    final b = _baseUri();
    if (b == null) return null;
    return Uri(
      scheme: b.scheme,
      host: b.host,
      port: b.hasPort ? b.port : null,
      path: '/health',
    );
  }
  static const String _extractEmbeddingEndpoint = '/extract-embedding';
  static const String _checkLivenessEndpoint = '/check-liveness';
  static const String _checkDuplicateEndpoint = '/check-duplicate';
  static const String _registerStudentEndpoint = '/register-student';
  static const String _matchFacesEndpoint = '/match-faces';
  static const String _recognizeEndpoint = '/recognize';

  /// Full production recognize: RetinaFace → MiniFAS → ArcFace → FAISS (multipart upload).
  static Future<Map<String, dynamic>?> recognizeFaceMultipart({
    required Uint8List photoBytes,
    required String fileName,
    required String instituteId,
    double threshold =
        ProductionFaceRecognitionConstants.recognitionConfidenceThreshold,
  }) async {
    try {
      final url = _apiUrl(_recognizeEndpoint);
      if (url == null) return null;

      final request = http.MultipartRequest('POST', url)
        ..fields['institute_id'] = instituteId.trim()
        ..fields['threshold'] = threshold.toString()
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            photoBytes,
            filename: fileName,
          ),
        );

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode == 403) {
        return {
          'success': false,
          'liveness_passed': false,
          'error': body,
        };
      }

      if (streamed.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('❌ recognize HTTP ${streamed.statusCode}: $body');
        }
        return {'success': false, 'error': body};
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      return data;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ recognizeFaceMultipart error: $e');
      return null;
    }
  }

  /// Extract face embedding from photo using InsightFace
  /// Returns: 512-dimensional face embedding vector
  static Future<List<double>?> extractEmbedding(Uint8List photoBytes) async {
    try {
      if (kDebugMode) {
        debugPrint('🧠 Calling InsightFace API to extract embedding...');
      }

      // Encode to base64 for transmission
      final base64Photo = base64Encode(photoBytes);

      final url = _apiUrl(_extractEmbeddingEndpoint);
      if (url == null) {
        if (kDebugMode) debugPrint('InsightFace: INSIGHTFACE_API_BASE not set or invalid in app_config.env');
        return null;
      }

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'photo_base64': base64Photo}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final embedding = List<double>.from(data['embedding']);

          if (kDebugMode) {
            debugPrint(
              '✅ Embedding extracted: ${embedding.length} dimensions',
            );
          }

          return embedding;
        } else {
          if (kDebugMode) {
            debugPrint('❌ API Error: ${data['error']}');
          }
          return null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ HTTP Error: ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Embedding extraction error: $e');
      }
      return null;
    }
  }

  /// Check if face is real (liveness detection) using MiniFASNet
  /// Returns: {is_real, liveness_score, confidence}
  static Future<Map<String, dynamic>?> checkLiveness(
    Uint8List photoBytes,
  ) async {
    try {
      final url = _apiUrl(_checkLivenessEndpoint);
      if (url == null) return null;
      if (kDebugMode) {
        debugPrint('👁️ Calling MiniFASNet liveness detection...');
      }

      final base64Photo = base64Encode(photoBytes);

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'photo_base64': base64Photo}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final result = {
            'is_real': data['is_real'] as bool,
            'liveness_score': data['liveness_score'] as double,
            'confidence': data['confidence'] as double,
          };

          if (kDebugMode) {
            debugPrint(
              '👁️ Liveness check: ${(result['is_real'] as bool) ? 'REAL' : 'SPOOF'} (${(result['liveness_score'] as double).toStringAsFixed(3)})',
            );
          }

          return result;
        } else {
          if (kDebugMode) {
            debugPrint('❌ Liveness check failed: ${data['error']}');
          }
          return null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ HTTP Error: ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Liveness check error: $e');
      }
      return null;
    }
  }

  /// Check if embedding is duplicate using FAISS
  /// Returns: {is_duplicate, matched_student, similarity} or null if new
  static Future<Map<String, dynamic>?> checkDuplicate(
    List<double> embedding, {
    String? studentId,
    double threshold = 0.60,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Calling FAISS for duplicate detection...');
      }

      final body = {
        'embedding': embedding,
        'threshold': threshold,
      };

      if (studentId != null) {
        body['student_id'] = studentId;
      }

      final url = _apiUrl(_checkDuplicateEndpoint);
      if (url == null) return null;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final isDuplicate = data['is_duplicate'] as bool;

          if (isDuplicate && data['duplicate_info'] != null) {
            final info = data['duplicate_info'] as Map<String, dynamic>;

            if (kDebugMode) {
              debugPrint(
                '⚠️ DUPLICATE DETECTED: ${info['matched_student']} (similarity: ${(info['similarity'] as double).toStringAsFixed(3)})',
              );
            }

            return {
              'is_duplicate': true,
              'matched_student': info['matched_student'],
              'similarity': info['similarity'],
            };
          } else {
            if (kDebugMode) {
              debugPrint('✅ No duplicate found');
            }
            return {'is_duplicate': false};
          }
        } else {
          if (kDebugMode) {
            debugPrint('❌ Duplicate check failed: ${data['error']}');
          }
          return null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ HTTP Error: ${response.statusCode}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Duplicate check error: $e');
      }
      return null;
    }
  }

  /// Register student embedding in FAISS index
  static Future<bool> registerStudent(
    String studentId,
    List<double> embedding,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('📝 Registering student: $studentId');
      }

      final url = _apiUrl(_registerStudentEndpoint);
      if (url == null) return false;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'student_id': studentId,
          'embedding': embedding,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          if (kDebugMode) {
            debugPrint('✅ Student registered: $studentId');
          }
          return true;
        }
      }

      if (kDebugMode) {
        debugPrint('❌ Registration failed');
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Registration error: $e');
      }
      return false;
    }
  }

  /// Compare two embeddings for attendance matching
  /// Returns: {is_match, similarity, threshold}
  static Future<Map<String, dynamic>?> matchFaces(
    List<double> embedding1,
    List<double> embedding2, {
    double threshold = 0.50,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Matching faces...');
      }

      final url = _apiUrl(_matchFacesEndpoint);
      if (url == null) return null;

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'embedding1': embedding1,
          'embedding2': embedding2,
          'threshold': threshold,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['success'] == true) {
          final result = {
            'is_match': data['is_match'] as bool,
            'similarity': data['similarity'] as double,
            'threshold': threshold,
          };

          if (kDebugMode) {
            debugPrint(
              '🔍 Match result: ${(result['is_match'] as bool) ? 'MATCH' : 'NO MATCH'} (${(result['similarity'] as double).toStringAsFixed(3)})',
            );
          }

          return result;
        }
      }

      if (kDebugMode) {
        debugPrint('❌ Face matching failed');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Face matching error: $e');
      }
      return null;
    }
  }

  /// Check API health
  static Future<bool> healthCheck() async {
    try {
      final url = _healthUri();
      if (url == null) return false;
      final response = await http.get(
        url,
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
