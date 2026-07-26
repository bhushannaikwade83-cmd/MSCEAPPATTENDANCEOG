import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/production_face_recognition_constants.dart';
import '../core/student_face_embedding_utils.dart';
import 'face_recognition_service.dart';

/// In-memory 1:N matcher with multi-embedding support and margin gating.
class StudentFaceMatchIndex {
  StudentFaceMatchIndex._();

  static String? _cachedInstituteId;
  static List<Map<String, dynamic>>? _cachedRows;
  static DateTime? _cacheLoadedAt;
  static const Duration _cacheTtl = Duration(minutes: 10);

  static void invalidateCache() {
    _cachedInstituteId = null;
    _cachedRows = null;
    _cacheLoadedAt = null;
  }

  /// Preload enrolled embeddings when auto-scan opens.
  static Future<void> warmCache(String instituteId) =>
      _rowsForInstitute(instituteId);

  static Future<List<Map<String, dynamic>>> _rowsForInstitute(
    String instituteId,
  ) async {
    final instId = instituteId.trim();
    final now = DateTime.now();
    if (_cachedInstituteId == instId &&
        _cachedRows != null &&
        _cacheLoadedAt != null &&
        now.difference(_cacheLoadedAt!) < _cacheTtl) {
      return _cachedRows!;
    }

    final rows =
        await FaceRecognitionService.fetchEnrolledStudentsForMatching(instId);
    _cachedInstituteId = instId;
    _cachedRows = rows;
    _cacheLoadedAt = now;
    if (kDebugMode) {
      debugPrint(
        '🔍 Face match cache: ${rows.length} enrolled student(s) for institute=$instId',
      );
    }
    return rows;
  }

  static void _logMatchRejection({
    required double bestSim,
    required double minConfidence,
    required int enrolledCount,
    required int probeDims,
    required int dimMismatchCount,
    required int emptyTemplateCount,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '🔍 Match rejected: best=${bestSim.toStringAsFixed(3)} '
      '(need >= ${minConfidence.toStringAsFixed(2)}), '
      'enrolled=$enrolledCount, probe=${probeDims}d',
    );
    if (enrolledCount == 0) {
      debugPrint(
        '   ⚠️ No enrolled face templates in this institute — register students (3 photos) first.',
      );
    } else if (dimMismatchCount > 0 && bestSim <= 0) {
      debugPrint(
        '   ⚠️ $dimMismatchCount student(s) have embeddings that do not match probe '
        '(${probeDims}d). Re-register faces with the in-app 3-photo flow.',
      );
    } else if (emptyTemplateCount > 0) {
      debugPrint(
        '   ⚠️ $emptyTemplateCount enrolled row(s) had empty/unparseable templates.',
      );
    }
  }

  static Future<StudentFaceMatchResult?> matchProbe({
    required List<double> probeEmbedding,
    required String instituteId,
    double minConfidence =
        ProductionFaceRecognitionConstants.recognitionConfidenceThreshold,
    double minMargin =
        ProductionFaceRecognitionConstants.recognitionMarginThreshold,
  }) async {
    if (probeEmbedding.isEmpty) return null;

    final rows = await _rowsForInstitute(instituteId);
    final probeDims = probeEmbedding.length;

    String? bestStudentId;
    String? bestName;
    String? bestSrNo;
    String? bestUserId;
    double bestSim = 0.0;
    double secondBestSim = 0.0;
    var dimMismatchCount = 0;
    var emptyTemplateCount = 0;

    for (final row in rows) {
      final templates = parseAllEmbeddingsFromField(row['face_embedding']);
      if (templates.isEmpty) {
        emptyTemplateCount++;
        continue;
      }

      final hasMatchingDim =
          templates.any((t) => t.length == probeDims);
      if (!hasMatchingDim) {
        dimMismatchCount++;
        continue;
      }

      final studentBest =
          FaceRecognitionService.probeBestSimilarity(probeEmbedding, row);
      if (studentBest <= 0) continue;

      if (studentBest > bestSim) {
        secondBestSim = bestSim;
        bestSim = studentBest;
        bestStudentId = row['id']?.toString();
        bestName = row['name']?.toString();
        bestSrNo = row['sr_no']?.toString();
        bestUserId = row['user_id']?.toString();
      } else if (studentBest > secondBestSim) {
        secondBestSim = studentBest;
      }
    }

    // When only one student enrolled there is no second candidate for margin
    // comparison — use a stricter confidence floor to prevent a stranger match.
    const singleStudentMinConfidence = 0.62;
    final effectiveMinConfidence = secondBestSim == 0
        ? singleStudentMinConfidence
        : minConfidence;

    if (bestStudentId == null || bestSim < effectiveMinConfidence) {
      _logMatchRejection(
        bestSim: bestSim,
        minConfidence: effectiveMinConfidence,
        enrolledCount: rows.length,
        probeDims: probeDims,
        dimMismatchCount: dimMismatchCount,
        emptyTemplateCount: emptyTemplateCount,
      );
      return null;
    }

    final margin = bestSim - secondBestSim;
    // Only apply margin gate when there is a real second candidate.
    if (secondBestSim > 0 && margin < minMargin) {
      if (kDebugMode) {
        debugPrint(
          '🔍 Match rejected: margin=${margin.toStringAsFixed(3)} '
          '(need >= ${minMargin.toStringAsFixed(2)}, '
          'best=${bestSim.toStringAsFixed(3)}, second=${secondBestSim.toStringAsFixed(3)})',
        );
      }
      return null;
    }

    if (kDebugMode) {
      debugPrint(
        '✅ Match: ${bestName ?? bestSrNo ?? bestStudentId} '
        'sim=${bestSim.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)}',
      );
    }

    return StudentFaceMatchResult(
      studentId: bestStudentId!,
      name: bestName ?? 'Student',
      srNo: bestSrNo ?? '',
      userId: bestUserId,
      similarity: bestSim,
      secondBestSimilarity: secondBestSim,
      margin: margin,
      embeddingDimensions: probeDims,
    );
  }
}

class StudentFaceMatchResult {
  const StudentFaceMatchResult({
    required this.studentId,
    required this.name,
    required this.srNo,
    required this.userId,
    required this.similarity,
    required this.secondBestSimilarity,
    required this.margin,
    required this.embeddingDimensions,
  });

  final String studentId;
  final String name;
  final String srNo;
  final String? userId;
  final double similarity;
  final double secondBestSimilarity;
  final double margin;
  final int embeddingDimensions;

  Map<String, dynamic> toStudentMap() => {
        'id': studentId,
        'name': name,
        'sr_no': srNo,
        'user_id': userId,
        'identified': true,
        'similarity': similarity,
        'similarity_percent': similarity * 100,
        'margin': margin,
        'second_best_similarity': secondBestSimilarity,
      };
}
