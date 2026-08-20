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
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('🔍 ATTENDANCE MATCHING: Starting face embedding comparison');
      debugPrint('═══════════════════════════════════════════════════════════');

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
          'message': '❌ No registered students found',
          'reason': 'No students with face registrations in this institute',
          'suggestion': '✓ Complete 3-photo face registration for all students\n✓ Ask students to register faces first\n✓ Check if students are added to this institute',
        };
      }

      final dbQueryEnd = DateTime.now();
      final dbQueryMs = dbQueryEnd.difference(dbQueryStart).inMilliseconds;
      debugPrint('📊 [STEP 1] Database fetch: ${dbQueryMs}ms');
      debugPrint('📊 [STEP 1] Student count: ${students.length} registered students')

      double bestScore = 0;
      Map<String, dynamic>? bestMatch;

      // Compare with each registered student (using MAX of 3 angles)
      final comparisonStart = DateTime.now();
      int successfulComparisons = 0;
      int failedComparisons = 0;

      for (final student in students) {
        try {
          final compareStepStart = DateTime.now();

          final frontEmb = student['face_embedding_front'] as String?;
          final leftEmb = student['face_embedding_left'] as String?;
          final rightEmb = student['face_embedding_right'] as String?;

          // Parse embeddings
          final parseStart = DateTime.now();
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
          final parseMs = DateTime.now().difference(parseStart).inMilliseconds;

          // Calculate similarities with all 3 angles
          final similarityStart = DateTime.now();
          double simFront = frontList != null ? _cosineSimilarity(embedding, frontList) : 0.0;
          double simLeft = leftList != null ? _cosineSimilarity(embedding, leftList) : 0.0;
          double simRight = rightList != null ? _cosineSimilarity(embedding, rightList) : 0.0;
          final similarityMs = DateTime.now().difference(similarityStart).inMilliseconds;

          // Use MAX of 3 angles (best match)
          double similarity = [simFront, simLeft, simRight].reduce((a, b) => a > b ? a : b);

          final compareStepMs = DateTime.now().difference(compareStepStart).inMilliseconds;
          debugPrint('  📌 ${student['sr_no']}: MAX=${(similarity * 100).toStringAsFixed(1)}% (F:${(simFront * 100).toStringAsFixed(0)}% L:${(simLeft * 100).toStringAsFixed(0)}% R:${(simRight * 100).toStringAsFixed(0)}%) | Parse:${parseMs}ms Sim:${similarityMs}ms Total:${compareStepMs}ms');

          // Keep track of best match
          if (similarity > bestScore) {
            bestScore = similarity;
            bestMatch = student;
          }
          successfulComparisons++;
        } catch (e) {
          debugPrint('  ⚠️ Error comparing ${student['sr_no']}: $e');
          failedComparisons++;
          continue;
        }
      }

      final comparisonEnd = DateTime.now();
      final comparisonMs = comparisonEnd.difference(comparisonStart).inMilliseconds;
      debugPrint('📊 [STEP 2] Embedding comparison: ${comparisonMs}ms');
      debugPrint('📊 [STEP 2] Success: $successfulComparisons, Failed: $failedComparisons');

      // Load threshold from app_settings (dynamic) or use default 0.70
      final thresholdStart = DateTime.now();
      double MATCH_THRESHOLD = 0.70;
      try {
        final settings = await appDb
            .from('app_settings')
            .select('value')
            .eq('key', 'similarity_threshold')
            .maybeSingle();

        if (settings != null && settings['value'] != null) {
          MATCH_THRESHOLD = double.tryParse(settings['value'].toString()) ?? 0.70;
        }
      } catch (e) {
        debugPrint('⚠️ Could not load threshold from app_settings, using default 0.70: $e');
      }
      final thresholdMs = DateTime.now().difference(thresholdStart).inMilliseconds;
      debugPrint('📊 [STEP 3] Threshold loaded: $MATCH_THRESHOLD (${thresholdMs}ms)');

      if (bestScore < MATCH_THRESHOLD) {
        // Generate helpful error message based on similarity score
        String userMessage = 'Face not recognized';
        String reason = '';
        String suggestion = '';

        final simPercent = (bestScore * 100).toStringAsFixed(1);
        final threshPercent = (MATCH_THRESHOLD * 100).toStringAsFixed(1);

        if (bestScore < 0.40) {
          // Very low score - likely wrong person or bad photo
          userMessage = '❌ Face doesn\'t match any registered student';
          reason = 'Similarity too low ($simPercent%)';
          suggestion = '✓ Make sure photo quality is good\n✓ Face should be clearly visible\n✓ Check lighting is adequate';
        } else if (bestScore < MATCH_THRESHOLD) {
          // Close but below threshold
          userMessage = '⚠️ Face similar but below threshold';
          reason = 'Score: $simPercent% (need $threshPercent%)';
          suggestion = '✓ Try better lighting or angle\n✓ Ensure full face is visible\n✓ Remove glasses/mask if possible';
        }

        debugPrint('$userMessage | $reason');

        return {
          'success': false,
          'message': userMessage,
          'reason': reason,
          'suggestion': suggestion,
          'similarity': bestScore,
          'threshold': MATCH_THRESHOLD,
        };
      }

      // Construct student name
      final fname = bestMatch!['fname'] ?? '';
      final lname = bestMatch['lname'] ?? '';
      final mname = bestMatch['mname'] ?? '';
      final studentName =
          '$fname ${mname.isNotEmpty ? '$mname ' : ''}$lname'.trim();

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ [RESULT] MATCHED: ${bestMatch['sr_no']} ($studentName)');
      debugPrint('✅ [RESULT] Similarity: ${(bestScore * 100).toStringAsFixed(1)}% (Threshold: ${(MATCH_THRESHOLD * 100).toStringAsFixed(0)}%)');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('⏱️  TOTAL MATCHING TIME: ${totalTime}ms');
      debugPrint('═══════════════════════════════════════════════════════════');

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

      // Generate helpful error message based on error type
      String userMessage = '❌ Could not process face';
      String reason = '';
      String suggestion = '';

      if (e.toString().contains('alignment')) {
        userMessage = '⚠️ Face alignment failed';
        reason = 'Cannot align face from photo';
        suggestion = '✓ Ensure full face is visible\n✓ Try different angle\n✓ Improve lighting';
      } else if (e.toString().contains('embedding')) {
        userMessage = '⚠️ Could not extract face features';
        reason = 'Face recognition module issue';
        suggestion = '✓ Try clearer photo\n✓ Good lighting needed\n✓ Face should fill frame';
      } else if (e.toString().contains('database') || e.toString().contains('students')) {
        userMessage = '❌ No registered students found';
        reason = 'Database connection issue';
        suggestion = '✓ Check internet connection\n✓ Make sure students are registered\n✓ Try again in a moment';
      } else {
        userMessage = '❌ Face matching failed';
        reason = 'System error occurred';
        suggestion = '✓ Try again\n✓ Check device storage\n✓ Restart app if problem continues';
      }

      return {
        'success': false,
        'message': userMessage,
        'reason': reason,
        'suggestion': suggestion,
        'error': e.toString(),
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
    final markStart = DateTime.now();
    try {
      final attendanceDate = timestamp.toIso8601String().split('T')[0]; // YYYY-MM-DD

      // Generate temporary ID for UI (until DB save completes)
      final tempId = '${DateTime.now().millisecondsSinceEpoch}';

      // ⚡ INSTANT RESPONSE: Return success immediately!
      final emoji = recordType == 'entry' ? '🚪➡️' : '🚪⬅️';
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('$emoji [MARKING] $recordType for $srNo at ${timestamp.hour}:${timestamp.minute}');
      debugPrint('═══════════════════════════════════════════════════════════');

      // ⏳ BACKGROUND: Save to database (fire-and-forget, don't wait!)
      final bgSaveStart = DateTime.now();
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
        final bgTime = DateTime.now().difference(bgSaveStart).inMilliseconds;
        debugPrint('✅ [BACKGROUND] $recordType saved to Supabase (${bgTime}ms)');
      }).catchError((e) {
        debugPrint('❌ [BACKGROUND] Attendance save error: $e');
      });

      // Return success IMMEDIATELY (user doesn't wait for DB)
      final immediateTime = DateTime.now().difference(markStart).inMilliseconds;
      debugPrint('⚡ [IMMEDIATE] Returning to user after ${immediateTime}ms (DB save in background)');
      debugPrint('═══════════════════════════════════════════════════════════');
      debugPrint('');

      return {
        'success': true,
        'message': '$recordType marked: $studentName',
        'attendance_id': tempId,  // Temporary ID
        'record_type': recordType,
        'response_time_ms': immediateTime,
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
