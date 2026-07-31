import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import '../../core/app_db.dart';

class AttendanceMarkingService {
  /// Match face embedding against registered students
  /// Returns: {success, student_id, institute_id, sr_no, student_name, similarity_score}
  static Future<Map<String, dynamic>> matchFaceAndGetStudent({
    required List<double> embedding,
    required String instituteId,
  }) async {
    try {
      debugPrint('🔍 Matching face embedding against registered students...');

      // Fetch all registered students for this institute
      final students = await appDb
          .from('students')
          .select('id, sr_no, fname, lname, mname, institute_id, face_embedding_average')
          .eq('institute_id', instituteId)
          .eq('face_registration_status', 'registered')
          .not('face_embedding_average', 'is', null);

      if (students.isEmpty) {
        return {
          'success': false,
          'message': 'No registered students found in this institute',
        };
      }

      debugPrint('📊 Checking ${students.length} registered students...');

      double bestScore = 0;
      Map<String, dynamic>? bestMatch;

      // Compare with each registered student
      for (final student in students) {
        try {
          final storedEmbedding = student['face_embedding_average'] as String?;
          if (storedEmbedding == null || storedEmbedding.isEmpty) continue;

          // Parse stored embedding
          final storedList = List<double>.from(
            jsonDecode(storedEmbedding).map((x) => (x as num).toDouble()),
          );

          // Calculate cosine similarity (0 to 1, higher = more similar)
          final similarity = _cosineSimilarity(embedding, storedList);

          debugPrint('  📌 ${student['sr_no']}: ${(similarity * 100).toStringAsFixed(1)}%');

          // Keep track of best match
          if (similarity > bestScore) {
            bestScore = similarity;
            bestMatch = student;
          }
        } catch (e) {
          debugPrint('  ⚠️ Error comparing ${student['sr_no']}: $e');
          continue;
        }
      }

      // Check if match quality is good enough (>70% similarity)
      const double MATCH_THRESHOLD = 0.70;
      if (bestScore < MATCH_THRESHOLD) {
        return {
          'success': false,
          'message': 'Face not recognized (similarity: ${(bestScore * 100).toStringAsFixed(1)}%)',
          'similarity': bestScore,
        };
      }

      // Construct student name
      final fname = bestMatch!['fname'] ?? '';
      final lname = bestMatch['lname'] ?? '';
      final mname = bestMatch['mname'] ?? '';
      final studentName =
          '$fname ${mname.isNotEmpty ? '$mname ' : ''}$lname'.trim();

      debugPrint('✅ MATCHED: ${bestMatch['sr_no']} ($studentName) - ${(bestScore * 100).toStringAsFixed(1)}%');

      return {
        'success': true,
        'student_id': bestMatch['id'],
        'institute_id': bestMatch['institute_id'],
        'sr_no': bestMatch['sr_no'],
        'student_name': studentName,
        'similarity_score': bestScore,
      };
    } catch (e) {
      debugPrint('❌ Face matching error: $e');
      return {
        'success': false,
        'message': 'Face matching failed: $e',
      };
    }
  }

  /// Calculate cosine similarity between two embeddings (0 to 1)
  static double _cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) return 0;

    double dotProduct = 0;
    double norm1 = 0;
    double norm2 = 0;

    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      norm1 += vec1[i] * vec1[i];
      norm2 += vec2[i] * vec2[i];
    }

    final denominator = (norm1 * norm2).sqrt();
    if (denominator == 0) return 0;

    return dotProduct / denominator;
  }

  /// Save attendance record to database (SEPARATE entry/exit records)
  /// recordType: 'entry' or 'exit'
  /// Returns: {success, message, attendance_id}
  static Future<Map<String, dynamic>> markAttendance({
    required String studentId,
    required String instituteId,
    required String srNo,
    required String studentName,
    required String photoUrl,
    required List<double> embedding,
    required double similarityScore,
    required DateTime timestamp,
    required String recordType, // 'entry' or 'exit'
  }) async {
    try {
      debugPrint('💾 Saving $recordType record for $studentName...');

      final attendanceDate = timestamp.toIso8601String().split('T')[0]; // YYYY-MM-DD

      final result = await appDb.from('attendance').upsert({
        'student_id': studentId,
        'institute_id': instituteId,
        'sr_no': srNo,
        'student_name': studentName,
        'attendance_date': attendanceDate,
        'record_type': recordType,  // 'entry' or 'exit'
        'marked_time': timestamp.toIso8601String(),
        'photo_url': photoUrl,
        'embedding': jsonEncode(embedding),
        'similarity_score': similarityScore,
        'status': 'present',
      }).select();

      if (result.isEmpty) {
        throw Exception('Failed to create attendance record');
      }

      final emoji = recordType == 'entry' ? '🚪➡️' : '🚪⬅️';
      debugPrint('✅ $emoji $recordType marked for ${result[0]['sr_no']} at ${timestamp.hour}:${timestamp.minute}');

      return {
        'success': true,
        'message': '$recordType marked: $studentName',
        'attendance_id': result[0]['id'],
        'record_type': recordType,
      };
    } catch (e) {
      debugPrint('❌ Attendance save error: $e');
      return {
        'success': false,
        'message': 'Failed to save attendance: $e',
      };
    }
  }
}
