import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import '../core/app_db.dart';
import '../core/face_matching_thresholds.dart';
import 'face_recognition_service.dart';

/// Debug service to check face similarity scores for troubleshooting
/// Use this to identify which students have poor registration photos
class FaceDebugService {
  /// Check similarity score between a test photo and a student's registered photo
  /// Returns the similarity percentage (0-100%)
  static Future<({double similarity, String message})> checkStudentFaceSimilarity({
    required String testPhotoPath,
    required String instituteId,
    required String studentSrNo,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 FACE DEBUG: Checking similarity for student $studentSrNo');
      }

      // Extract features from test photo
      final testFeatures = await FaceRecognitionService.extractFaceFeatures(testPhotoPath);
      if (testFeatures == null) {
        return (
          similarity: 0.0,
          message: '❌ Could not extract face from test photo. Ensure good lighting and clear face.',
        );
      }

      // Extract embedding from test photo
      final testEmbedding = await FaceRecognitionService.extractNeuralEmbedding(
        testPhotoPath,
        testFeatures,
      );
      if (testEmbedding == null) {
        return (
          similarity: 0.0,
          message: '❌ Could not extract face embedding from test photo.',
        );
      }

      // Fetch student's registered photo from database (3-angle embeddings)
      final studentData = await appDb
          .from('students')
          .select('id, fname, lname, sr_no, face_embedding_front, face_embedding_left, face_embedding_right')
          .eq('institute_id', instituteId)
          .eq('sr_no', studentSrNo)
          .maybeSingle();

      if (studentData == null) {
        return (
          similarity: 0.0,
          message: '❌ Student with SR NO $studentSrNo not found.',
        );
      }

      final faceEmbed = studentData['face_embedding_front'] ?? studentData['face_embedding_left'] ?? studentData['face_embedding_right'];
      if (faceEmbed == null) {
        return (
          similarity: 0.0,
          message: '❌ Student has NO registered face. Must register first.',
        );
      }

      // Extract embedding from database
      Map<String, dynamic>? embedMap;
      if (faceEmbed is Map) {
        embedMap = Map<String, dynamic>.from(faceEmbed);
      }

      if (embedMap == null) {
        return (
          similarity: 0.0,
          message: '❌ Could not read face embedding from database.',
        );
      }

      final registeredEmbedding = (embedMap['embedding'] as List<dynamic>?)?.cast<double>().toList();
      if (registeredEmbedding == null) {
        return (
          similarity: 0.0,
          message: '❌ Registered face embedding is corrupted in database.',
        );
      }

      // Calculate similarity
      final similarity = FaceRecognitionService.calculateCosineSimilarity(
        testEmbedding,
        registeredEmbedding,
      );

      final similarityPercent = similarity * 100.0;
      final threshold = FaceMatchingThresholds.ATTENDANCE_VERIFICATION_THRESHOLD * 100.0;

      if (kDebugMode) {
        debugPrint('');
        debugPrint('╔════════════════════════════════════════════════════════╗');
        debugPrint('║            📊 FACE DEBUG SIMILARITY CHECK               ║');
        debugPrint('╠════════════════════════════════════════════════════════╣');
        debugPrint('║ Student: $studentSrNo');
        debugPrint('║ Name: ${studentData['name']}');
        debugPrint('║');
        debugPrint('║ Similarity: ${similarityPercent.toStringAsFixed(1)}%');
        debugPrint('║ Threshold: ${threshold.toStringAsFixed(0)}%');
        if (similarityPercent >= threshold) {
          debugPrint('║ Status: ✅ PASS (will match in attendance)');
        } else {
          debugPrint('║ Status: ❌ FAIL (needs re-registration)');
          debugPrint('║ Shortfall: ${(threshold - similarityPercent).toStringAsFixed(1)}% below threshold');
        }
        debugPrint('╚════════════════════════════════════════════════════════╝');
        debugPrint('');
      }

      final status = similarityPercent >= threshold ? '✅ PASS' : '❌ FAIL';
      return (
        similarity: similarity,
        message: '$status: Student $studentSrNo = ${similarityPercent.toStringAsFixed(1)}% '
            '(need ${threshold.toStringAsFixed(0)}%)',
      );
    } catch (e) {
      return (
        similarity: 0.0,
        message: '❌ Error: ${e.toString()}',
      );
    }
  }

  /// Batch check all students in an institute to find which ones have low scores
  /// Returns list of students sorted by similarity (lowest first)
  static Future<List<Map<String, dynamic>>> diagnoseAllStudents({
    required String instituteId,
    required String testPhotoPath,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 BATCH DIAGNOSIS: Analyzing all students...');
      }

      // Extract test embedding
      final testFeatures = await FaceRecognitionService.extractFaceFeatures(testPhotoPath);
      if (testFeatures == null) {
        if (kDebugMode) debugPrint('❌ Could not extract face from test photo');
        return [];
      }

      final testEmbedding = await FaceRecognitionService.extractNeuralEmbedding(
        testPhotoPath,
        testFeatures,
      );
      if (testEmbedding == null) {
        if (kDebugMode) debugPrint('❌ Could not extract embedding');
        return [];
      }

      // Fetch all students (3-angle embeddings)
      final students = await appDb
          .from('students')
          .select('id, sr_no, fname, lname, face_embedding_front, face_embedding_left, face_embedding_right')
          .eq('institute_id', instituteId);

      final results = <Map<String, dynamic>>[];

      for (final student in students) {
        try {
          final faceEmbed = student['face_embedding_front'] ?? student['face_embedding_left'] ?? student['face_embedding_right'];
          if (faceEmbed == null) continue;

          Map<String, dynamic>? embedMap;
          if (faceEmbed is Map) {
            embedMap = Map<String, dynamic>.from(faceEmbed);
          }

          if (embedMap == null) continue;

          final registeredEmbedding = (embedMap['embedding'] as List<dynamic>?)?.cast<double>().toList();
          if (registeredEmbedding == null) continue;

          final similarity = FaceRecognitionService.calculateCosineSimilarity(
            testEmbedding,
            registeredEmbedding,
          );

          results.add({
            'srNo': student['sr_no'],
            'name': student['name'],
            'similarity': similarity,
            'percentage': (similarity * 100.0),
            'status': similarity >= 0.35 ? '✅' : '❌',
          });
        } catch (e) {
          // Skip this student on error
        }
      }

      // Sort by similarity (lowest first - these need re-registration)
      results.sort((a, b) => (a['similarity'] as double).compareTo(b['similarity'] as double));

      if (kDebugMode) {
        debugPrint('');
        debugPrint('╔════════════════════════════════════════════════════════╗');
        debugPrint('║         📊 BATCH DIAGNOSIS RESULTS (${results.length} students)        ║');
        debugPrint('╠════════════════════════════════════════════════════════╣');
        debugPrint('║ Students needing re-registration (❌):                  ║');
        int count = 0;
        for (final r in results) {
          if (r['status'] == '❌') {
            count++;
            final srNo = (r['srNo'] ?? '?').toString().padRight(8);
            final name = (r['name'] ?? '?').toString().padRight(20);
            final pct = (r['percentage'] as double).toStringAsFixed(1).padLeft(5);
            debugPrint('║ $srNo | $name | $pct%');
            if (count >= 10) {
              debugPrint('║ ... and ${results.where((r) => r['status'] == '❌').length - 10} more');
              break;
            }
          }
        }
        if (count == 0) {
          debugPrint('║ None! All students are good.                          ║');
        }
        debugPrint('╚════════════════════════════════════════════════════════╝');
        debugPrint('');
      }

      return results;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Batch diagnosis error: $e');
      return [];
    }
  }
}
