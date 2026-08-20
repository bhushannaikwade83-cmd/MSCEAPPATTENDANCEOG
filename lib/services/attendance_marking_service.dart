import 'dart:convert';
import 'dart:math' show sqrt;
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
      final startTime = DateTime.now();
      debugPrint('🔍 Matching face embedding against registered students...');

      // Fetch all registered students for this institute (all 3 angles)
      final dbQueryStart = DateTime.now();
      final students = await appDb
          .from('students')
          .select('id, sr_no, fname, lname, mname, institute_id, face_embedding_front, face_embedding_left, face_embedding_right')
          .eq('institute_id', instituteId)
          .eq('face_registration_status', 'registered')
          .or('face_embedding_front.not.is.null,face_embedding_left.not.is.null,face_embedding_right.not.is.null');

      if (students.isEmpty) {
        return {
          'success': false,
          'message': 'No registered students found in this institute',
        };
      }

      final dbQueryEnd = DateTime.now();
      final dbQueryMs = dbQueryEnd.difference(dbQueryStart).inMilliseconds;
      debugPrint('⏱️  DB Query took: ${dbQueryMs}ms');
      debugPrint('📊 Checking ${students.length} registered students (with 3-angle embeddings)...');

      double bestScore = 0;
      Map<String, dynamic>? bestMatch;

      // Compare with each registered student (using MAX of 3 angles)
      final comparisonStart = DateTime.now();
      for (final student in students) {
        try {
          final frontEmb = student['face_embedding_front'] as String?;
          final leftEmb = student['face_embedding_left'] as String?;
          final rightEmb = student['face_embedding_right'] as String?;

          // Parse embeddings
          List<double>? frontList, leftList, rightList;
          if (frontEmb != null && frontEmb.isNotEmpty) {
            frontList = List<double>.from(jsonDecode(frontEmb).map((x) => (x as num).toDouble()));
          }
          if (leftEmb != null && leftEmb.isNotEmpty) {
            leftList = List<double>.from(jsonDecode(leftEmb).map((x) => (x as num).toDouble()));
          }
          if (rightEmb != null && rightEmb.isNotEmpty) {
            rightList = List<double>.from(jsonDecode(rightEmb).map((x) => (x as num).toDouble()));
          }

          // Calculate similarities with all 3 angles
          double simFront = frontList != null ? _cosineSimilarity(embedding, frontList) : 0.0;
          double simLeft = leftList != null ? _cosineSimilarity(embedding, leftList) : 0.0;
          double simRight = rightList != null ? _cosineSimilarity(embedding, rightList) : 0.0;

          // Use MAX of 3 angles (best match)
          double similarity = [simFront, simLeft, simRight].reduce((a, b) => a > b ? a : b);

          debugPrint('  📌 ${student['sr_no']}: MAX=${(similarity * 100).toStringAsFixed(1)}% (F:${(simFront * 100).toStringAsFixed(0)}% L:${(simLeft * 100).toStringAsFixed(0)}% R:${(simRight * 100).toStringAsFixed(0)}%)');

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

      final comparisonEnd = DateTime.now();
      final comparisonMs = comparisonEnd.difference(comparisonStart).inMilliseconds;
      debugPrint('⏱️  Embedding comparison took: ${comparisonMs}ms');

      // Load threshold from app_settings (dynamic) or use default 0.70
      double MATCH_THRESHOLD = 0.70;
      try {
        final settings = await appDb
            .from('app_settings')
            .select('value')
            .eq('key', 'similarity_threshold')
            .maybeSingle();

        if (settings != null && settings['value'] != null) {
          MATCH_THRESHOLD = double.tryParse(settings['value'].toString()) ?? 0.70;
          debugPrint('📊 Loaded threshold from app_settings: $MATCH_THRESHOLD');
        }
      } catch (e) {
        debugPrint('⚠️ Could not load threshold from app_settings, using default 0.70: $e');
      }

      if (bestScore < MATCH_THRESHOLD) {
        return {
          'success': false,
          'message': 'Face not recognized (similarity: ${(bestScore * 100).toStringAsFixed(1)}%, threshold: ${(MATCH_THRESHOLD * 100).toStringAsFixed(1)}%)',
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

    final denominator = sqrt(norm1 * norm2);
    if (denominator == 0) return 0;

    return dotProduct / denominator;
  }

  /// Save attendance record to database (ASYNC - don't wait!)
  /// recordType: 'entry' or 'exit'
  /// Returns: {success, message} IMMEDIATELY (before DB save completes)
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
      final attendanceDate = timestamp.toIso8601String().split('T')[0]; // YYYY-MM-DD

      // Generate temporary ID for UI (until DB save completes)
      final tempId = '${DateTime.now().millisecondsSinceEpoch}';

      // ⚡ INSTANT RESPONSE: Return success immediately!
      final emoji = recordType == 'entry' ? '🚪➡️' : '🚪⬅️';
      debugPrint('$emoji $recordType marked for $srNo at ${timestamp.hour}:${timestamp.minute}');
      debugPrint('⚡ Returning success immediately (DB save in background)...');

      // ⏳ BACKGROUND: Save to database (fire-and-forget, don't wait!)
      appDb.from('attendance').upsert({
        'student_id': studentId,
        'institute_id': instituteId,
        'sr_no': srNo,
        'student_name': studentName,
        'attendance_date': attendanceDate,
        'record_type': recordType,  // 'entry' or 'exit'
        'marked_time': timestamp.toUtc().toIso8601String(),
        'photo_url': photoUrl,
        'embedding': jsonEncode(embedding),
        'similarity_score': similarityScore,
        'status': 'present',
      }).then((_) {
        debugPrint('✅ [BACKGROUND] $recordType attendance saved to Supabase');
      }).catchError((e) {
        debugPrint('❌ [BACKGROUND] Attendance save error: $e');
      });

      // Return success IMMEDIATELY (user doesn't wait for DB)
      return {
        'success': true,
        'message': '$recordType marked: $studentName',
        'attendance_id': tempId,  // Temporary ID
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
