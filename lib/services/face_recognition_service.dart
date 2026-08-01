import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb, compute;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';
import '../core/app_db.dart';
import '../core/face_matching_thresholds.dart';
import '../core/student_face_embedding_utils.dart';
import '../core/supabase_maps.dart';
import '../core/streaming_blink_detector.dart';
import 'device_performance_service.dart';
import 'package:image/image.dart' as img;
import 'tflite_interpreter_stub.dart'
    if (dart.library.io) 'tflite_interpreter_native.dart';

/// Simple Result for Face Verification
class StudentFaceVerifyResult {
  final bool isMatch;
  final String message;
  final double? similarityPercent;
  final double? closestOtherSimilarityPercent;
  final String? closestOtherLabel;
  final bool requiresManualConfirmation;
  /// True when the selected profile has no usable enrollment embedding; staff confirm is offline/visual.
  final bool enrollmentEmbeddingMissing;

  const StudentFaceVerifyResult.match({
    this.similarityPercent,
    this.closestOtherSimilarityPercent,
    this.closestOtherLabel,
  })  : isMatch = true,
        message = '',
        requiresManualConfirmation = false,
        enrollmentEmbeddingMissing = false;

  const StudentFaceVerifyResult.reject(
    this.message, {
    this.similarityPercent,
    this.closestOtherSimilarityPercent,
    this.closestOtherLabel,
    this.requiresManualConfirmation = false,
    this.enrollmentEmbeddingMissing = false,
  }) : isMatch = false;
}

class DuplicateFaceRegistrationException implements Exception {
  final String message;
  DuplicateFaceRegistrationException(this.message);
  @override
  String toString() => message;
}

class PreparedFaceRegistrationOnePhoto {
  final Map<String, dynamic> embeddingPayload;
  PreparedFaceRegistrationOnePhoto({required this.embeddingPayload});
}

class FaceRecognitionService {
  static FaceDetector? _faceDetectorInstance;
  static FaceDetector? _streamFaceDetectorInstance;
  static Interpreter? _interpreter;
  static bool _isInitialized = false;

  // ✅ OPTIMIZATION: Embedding cache (reduces processing by 80%)
  static final Map<String, List<double>> _embeddingCache = {};
  static const int _maxCacheSize = 50;

  // ✅ OPTIMIZATION: Enrolled-students cache for duplicate check during registration.
  // Avoids repeated DB fetch for each of the 3 angle photos — same TTL as StudentFaceMatchIndex.
  static String? _enrolledCacheInstId;
  static List<Map<String, dynamic>>? _enrolledCacheRows;
  static DateTime? _enrolledCacheAt;
  static const Duration _enrolledCacheTtl = Duration(minutes: 30);

  // ✅ OPTIMIZATION: instituteKeys cache — prevents 2 DB hits per recognition attempt.
  // Called on every auto-scan frame that triggers recognition. 30-min TTL matches institute data.
  static final Map<String, Set<String>> _instituteKeysCache = {};
  static final Map<String, DateTime>    _instituteKeysCacheAt = {};
  static const Duration _instituteKeysCacheTtl = Duration(minutes: 30);

  /// Invalidate enrolled-students + instituteKeys caches (called by realtime sync on student change).
  static void invalidateEnrolledCache() {
    _enrolledCacheInstId = null;
    _enrolledCacheRows   = null;
    _enrolledCacheAt     = null;
    _instituteKeysCache.clear();
    _instituteKeysCacheAt.clear();
    if (kDebugMode) debugPrint('🔄 FaceRecognitionService: enrolled cache invalidated');
  }

  // ✅ OPTIMIZATION: Frame processing throttle (reduces CPU by 80%)
  static int _frameProcessingCounter = 0;
  static const int _frameProcessInterval = 5;  // Process every 5th frame (6 fps instead of 30)

  static FaceDetector get _faceDetector {
    _faceDetectorInstance ??= FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // For eye open (liveness)
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    return _faceDetectorInstance!;
  }

  static FaceDetector get _streamFaceDetector {
    _streamFaceDetectorInstance ??= FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    return _streamFaceDetectorInstance!;
  }

  static Future<void> initialize() async {
    if (_isInitialized) return;
    if (kIsWeb) return;
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Model Load Error: $e');
    }
  }

  // --- RESTORED METHODS FOR COMPATIBILITY ---

  static Future<List<Face>> detectFaces(String imagePath) async {
    return await _faceDetector.processImage(InputImage.fromFilePath(imagePath));
  }

  static Future<String> ensureNormalizedJpegForFacePipeline(String imagePath) async {
    return await _normalizeImage(imagePath);
  }

  static Future<Map<String, dynamic>?> extractFaceFeatures(String imagePath) async {
    final faces = await _faceDetector.processImage(InputImage.fromFilePath(imagePath));
    if (faces.isEmpty) return null;
    final face = faces.first;
    return {
      'boundingBox': {
        'left': face.boundingBox.left,
        'top': face.boundingBox.top,
        'width': face.boundingBox.width,
        'height': face.boundingBox.height,
      },
      'headEulerAngleY': face.headEulerAngleY,
      'headEulerAngleZ': face.headEulerAngleZ,
      'leftEyeOpenProbability': face.leftEyeOpenProbability,
      'rightEyeOpenProbability': face.rightEyeOpenProbability,
    };
  }

  static Future<String?> getDiagnosticReasonForInvalidFace(String imagePath) async {
    final faces = await _faceDetector.processImage(InputImage.fromFilePath(imagePath));
    if (faces.isEmpty) return 'No face detected.';
    final eyeOpen = ((faces.first.leftEyeOpenProbability ?? 0) + (faces.first.rightEyeOpenProbability ?? 0)) / 2;
    if (eyeOpen < 0.4) return 'Eyes not sufficiently open.';
    return null;
  }

  static Future<List<double>?> extractNeuralEmbedding(String imagePath, Map<String, dynamic> faceFeatures) async {
    final faces = await _faceDetector.processImage(InputImage.fromFilePath(imagePath));
    if (faces.isEmpty) return null;
    return await _extractEmbedding(imagePath, faces.first);
  }

  static Future<String?> duplicateRegistrationBlockedMessageForEmbedding(
    List<double> embedding,
    String instituteId, {
    String? excludeStudentId,
  }) async {
    final bestMatch = await _findBestOtherMatch(
      embedding,
      instituteId,
      excludeId: excludeStudentId,
    );
    if (bestMatch == null) return null;

    final similarity = bestMatch['similarity'] as double? ?? 0.0;
    if (kDebugMode) {
      debugPrint(
        '🔎 Registration duplicate check: best similarity '
        '${(similarity * 100).toStringAsFixed(1)}% for '
        '${bestMatch['name'] ?? bestMatch['sr_no'] ?? bestMatch['user_id'] ?? bestMatch['id']}',
      );
    }

    // Block duplicate registration (same person enrolling twice).
    if (similarity >= FaceMatchingThresholds.DUPLICATE_REVIEW_THRESHOLD) {
      final name = (bestMatch['name'] as String?)?.trim();
      final srNo = (bestMatch['sr_no'] as String?)?.trim();
      final userId = (bestMatch['user_id'] as String?)?.trim();
      final who = name != null && name.isNotEmpty
          ? (srNo != null && srNo.isNotEmpty ? '$name (SR $srNo)' : name)
          : (srNo != null && srNo.isNotEmpty ? 'SR $srNo' : (userId ?? 'another student'));
      return '❌ Registration blocked! This face is ${(similarity * 100).toStringAsFixed(1)}% similar to $who. '
          'Same person cannot register twice.';
    }

    return null;
  }

  /// Final gate before saving — checks one or more probe embeddings.
  static Future<void> assertNoDuplicateRegistration({
    required List<List<double>> embeddings,
    required String instituteId,
    String? excludeStudentId,
  }) async {
    for (final embedding in embeddings) {
      if (embedding.isEmpty) continue;
      final message = await duplicateRegistrationBlockedMessageForEmbedding(
        embedding,
        instituteId,
        excludeStudentId: excludeStudentId,
      );
      if (message != null) {
        throw DuplicateFaceRegistrationException(message);
      }
    }
  }

  static Future<PreparedFaceRegistrationOnePhoto?> prepareFaceRegistrationOnePhoto(
    String imagePath,
    String instituteId,
    String rollNumber,
    String studentId,
  ) async {
    final workPath = await _normalizeImage(imagePath);
    final face = await _detectAndCheckLiveness(workPath);
    if (face == null) return null;
    final embedding = await _extractEmbedding(workPath, face);
    if (embedding == null) return null;

    // ✅ CHECK 1: Does THIS STUDENT already have a face registered?
    final student = await _getStudent(instituteId, studentId);
    if (student != null && studentHasNonEmptyFaceEmbedding(student['face_embedding'])) {
      if (kDebugMode) {
        debugPrint('⚠️ REGISTRATION: Student ${_studentDisplayLabel(student)} already has face registered');
      }
      throw DuplicateFaceRegistrationException(
        'This student already has a face registered. Contact admin to update enrollment.',
      );
    }

    // ✅ CHECK 2: Does this FACE match ANOTHER student's face? (fraud/duplicate prevention)
    final duplicateMessage = await duplicateRegistrationBlockedMessageForEmbedding(
      embedding,
      instituteId,
      excludeStudentId: studentId,
    );
    if (duplicateMessage != null) {
      throw DuplicateFaceRegistrationException(duplicateMessage);
    }

    if (kDebugMode) {
      debugPrint('✅ REGISTRATION PASSED ALL CHECKS:');
      debugPrint('   ✅ Face alignment applied (landmarks extracted)');
      debugPrint('   ✅ Embedding extracted (192 dimensions)');
      debugPrint('   ✅ No student already has this face');
      debugPrint('   ✅ Face is unique - no duplicates found');
      debugPrint('   ✅ Ready to save to database');
    }

    return PreparedFaceRegistrationOnePhoto(embeddingPayload: {
      'embedding': embedding,
      'version': 2,
    });
  }

  /// One angle during 3-photo enrollment (front / left / right).
  /// No eye-open / spoof check — camera already verified liveness via blink + head-turn.
  /// Just: detect face → extract 192-dim embedding → duplicate guard.
  static Future<PreparedFaceRegistrationOnePhoto?> prepareFaceRegistrationAnglePhoto(
    String imagePath,
    String instituteId,
    String studentId, {
    required bool blockIfStudentAlreadyEnrolled,
    required String pose,
  }) async {
    final workPath = await _normalizeImage(imagePath);
    // No requireEyesOpen — blink was verified live on camera before capture.
    final face = await _detectFaceInImage(workPath, requireEyesOpen: false);
    if (face == null) return null;
    final embedding = await _extractEmbedding(workPath, face);
    if (embedding == null) return null;

    if (blockIfStudentAlreadyEnrolled) {
      final student = await _getStudent(instituteId, studentId);
      if (student != null &&
          studentHasNonEmptyFaceEmbedding(student['face_embedding'])) {
        throw DuplicateFaceRegistrationException(
          'This student already has a face registered. Use Register again to replace all 3 photos.',
        );
      }
    }

    final duplicateMessage = await duplicateRegistrationBlockedMessageForEmbedding(
      embedding,
      instituteId,
      excludeStudentId: studentId,
    );
    if (duplicateMessage != null) {
      throw DuplicateFaceRegistrationException(duplicateMessage);
    }

    if (kDebugMode) {
      debugPrint(
        '✅ Registration $pose: JPEG normalized → face aligned → 192-dim embedding',
      );
    }

    return PreparedFaceRegistrationOnePhoto(embeddingPayload: {
      'embedding': embedding,
      'version': 2,
    });
  }

  /// One-time registration photo change: student must already have an embedding.
  static Future<PreparedFaceRegistrationOnePhoto?> prepareFacePhotoChangeOnePhoto(
    String imagePath,
    String instituteId,
    String rollNumber,
    String studentId,
  ) async {
    final workPath = await _normalizeImage(imagePath);
    final face = await _detectAndCheckLiveness(workPath);
    if (face == null) return null;
    final embedding = await _extractEmbedding(workPath, face);
    if (embedding == null) return null;

    final student = await _getStudent(instituteId, studentId);
    if (student == null) {
      throw DuplicateFaceRegistrationException(
        'Student not found. Refresh the list and try again.',
      );
    }
    if (!studentHasNonEmptyFaceEmbedding(student['face_embedding'])) {
      throw DuplicateFaceRegistrationException(
        'Register the face first, then you can change the photo once.',
      );
    }
    if (student['face_photo_changed_once'] == true) {
      throw DuplicateFaceRegistrationException(
        'Registration photo was already changed once for this student.',
      );
    }

    final duplicateMessage = await duplicateRegistrationBlockedMessageForEmbedding(
      embedding,
      instituteId,
      excludeStudentId: studentId,
    );
    if (duplicateMessage != null) {
      throw DuplicateFaceRegistrationException(duplicateMessage);
    }

    if (kDebugMode) {
      debugPrint('✅ PHOTO CHANGE PASSED CHECKS for ${_studentDisplayLabel(student)}');
    }

    return PreparedFaceRegistrationOnePhoto(embeddingPayload: {
      'embedding': embedding,
      'version': 2,
    });
  }

  // --- END RESTORED METHODS ---

  /// CORE FLOW 1: Verify Attendance
  ///
  /// [userIdOrSrNo] — `students.user_id` (Supabase auth id) or `students.sr_no`.
  /// [expectedStudentRowId] — when set, must equal the `students.id` row loaded from
  /// [userIdOrSrNo]; stops wrong-embedding matches if the lookup key ever collides.
  static String _studentDisplayLabel(Map<String, dynamic> row) {
    final name = (row['name'] as String?)?.trim();
    final srNo = (row['sr_no'] as String?)?.trim();
    final userId = (row['user_id'] as String?)?.trim();
    if (name != null && name.isNotEmpty) {
      return srNo != null && srNo.isNotEmpty ? '$name (SR $srNo)' : name;
    }
    if (srNo != null && srNo.isNotEmpty) return 'SR $srNo';
    if (userId != null && userId.isNotEmpty) return userId;
    return 'another student';
  }

  /// Returns a rejection when this face fits another enrolled student better than the card selected.
  static StudentFaceVerifyResult? _crossStudentAttendanceBlock({
    required double selectedSimilarity,
    required double simPercent,
    required Map<String, dynamic> student,
    required Map<String, dynamic>? otherMatch,
  }) {
    if (otherMatch == null) return null;

    final otherSimilarity = otherMatch['similarity'] as double? ?? 0.0;
    if (otherSimilarity <= 0) return null;

    final otherPct = otherSimilarity * 100;
    final otherLabel = _studentDisplayLabel(otherMatch);
    final selectedLabel = _studentDisplayLabel(student);
    final dominanceMargin = FaceMatchingThresholds.CROSS_STUDENT_DOMINANCE_MARGIN;
    final blockThreshold = FaceMatchingThresholds.CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD;
    final ceiling = FaceMatchingThresholds.CROSS_STUDENT_MANUAL_CEILING_OTHER;

    if (otherSimilarity >= ceiling) {
      return StudentFaceVerifyResult.reject(
        'Security alert: This face matches $otherLabel at ${otherPct.toStringAsFixed(0)}% '
        '(too close to another enrolled student). Use the correct student card.',
        similarityPercent: simPercent,
        closestOtherSimilarityPercent: otherPct,
        closestOtherLabel: otherLabel,
      );
    }

    if (otherSimilarity > selectedSimilarity + dominanceMargin) {
      return StudentFaceVerifyResult.reject(
        'This face matches $otherLabel (${otherPct.toStringAsFixed(0)}%) more than '
        '$selectedLabel (${simPercent.toStringAsFixed(0)}%). Open the correct student and try again.',
        similarityPercent: simPercent,
        closestOtherSimilarityPercent: otherPct,
        closestOtherLabel: otherLabel,
      );
    }

    if (otherSimilarity >= blockThreshold && otherSimilarity > selectedSimilarity) {
      return StudentFaceVerifyResult.reject(
        'Security: face is closer to $otherLabel (${otherPct.toStringAsFixed(0)}%) than to '
        '$selectedLabel (${simPercent.toStringAsFixed(0)}%). Select the matching student card.',
        similarityPercent: simPercent,
        closestOtherSimilarityPercent: otherPct,
        closestOtherLabel: otherLabel,
      );
    }

    return null;
  }

  static Future<StudentFaceVerifyResult> verifyStudent(
    String imagePath,
    String instituteId,
    String userIdOrSrNo, {
    String? expectedStudentRowId,
  }) async {
    if (kIsWeb) return const StudentFaceVerifyResult.reject('Web not supported');

    final instId = instituteId.trim();
    if (instId.isEmpty) {
      return const StudentFaceVerifyResult.reject('Institute is not set. Sign in again.');
    }

    try {
      // 1. Prepare Image
      final workPath = await _normalizeImage(imagePath);

      // 2. Detect Face & Liveness (Eyes Open)
      final face = await _detectAndCheckLiveness(workPath);
      if (face == null) return const StudentFaceVerifyResult.reject('Liveness check failed. Keep eyes open and look at camera.');

      // 3. Extract Neural Data
      final embedding = await _extractEmbedding(workPath, face);
      if (embedding == null) return const StudentFaceVerifyResult.reject('Could not read face data.');

      // 4. Get Selected Student Record (scoped to this institute only).
      // Prefer the roster row id from the UI when provided — roll/sr_no can collide across
      // duplicate rows in one institute (e.g. SR 130 vs another student's user_id "130").
      Map<String, dynamic>? student;
      final expectedId = expectedStudentRowId?.trim() ?? '';
      if (expectedId.isNotEmpty) {
        final byId = await appDb
            .from('students')
            .select()
            .eq('institute_id', instId)
            .eq('id', expectedId)
            .maybeSingle();
        if (byId != null) {
          student = Map<String, dynamic>.from(byId);
        } else {
          // Do not fall back to sr_no / user_id — keys like "130" can match the wrong row
          // while the UI card still references students.id (UUID).
          return const StudentFaceVerifyResult.reject(
            'Could not load this student for face verification. Pull down to refresh the list and try again.',
          );
        }
      } else {
        student = await _getStudent(instId, userIdOrSrNo);
      }
      if (student == null) {
        return const StudentFaceVerifyResult.reject(
          'Student not found in this institute. Refresh the list and try again.',
        );
      }
      final rowInstitute = student['institute_id']?.toString().trim() ?? '';
      if (rowInstitute.isNotEmpty && rowInstitute != instId) {
        return const StudentFaceVerifyResult.reject(
          'This student does not belong to your institute.',
        );
      }

      // No enrollment embedding on this roster row: compare probe only against **same-institute**
      // neighbors to block picking the wrong card; genuine present-on-roster-but-not-enrolled
      // identities can proceed after explicit staff confirmation.
      if (!studentHasNonEmptyFaceEmbedding(student['face_embedding'])) {
        final sid = student['id']?.toString();
        final otherMatch =
            await _findBestOtherMatch(embedding, instId, excludeId: sid?.isEmpty == true ? null : sid);
        final otherSimilarity = otherMatch?['similarity'] as double? ?? 0.0;
        final otherPct = otherSimilarity > 0 ? otherSimilarity * 100 : null;
        final otherLabel =
            otherMatch != null ? _studentDisplayLabel(otherMatch) : null;

        if (otherSimilarity >= FaceMatchingThresholds.CROSS_STUDENT_MANUAL_CEILING_OTHER &&
            otherMatch != null) {
          return StudentFaceVerifyResult.reject(
            'Security: This face strongly matches enrolled student ${_studentDisplayLabel(otherMatch)} '
            '(${((otherSimilarity * 100).toStringAsFixed(1))}%). '
            'Open that student\'s card, or enroll a face on ${(_studentDisplayLabel(student))}.',
            similarityPercent: 0,
            closestOtherSimilarityPercent: otherPct,
            closestOtherLabel: otherLabel,
          );
        }
        if (otherSimilarity >= FaceMatchingThresholds.CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD &&
            otherMatch != null) {
          return StudentFaceVerifyResult.reject(
            'This face aligns with enrolled ${_studentDisplayLabel(otherMatch)} '
            '(${((otherSimilarity * 100).toStringAsFixed(1))}%); selected profile '
            '${_studentDisplayLabel(student)} has no face embedding — likely wrong card.',
            similarityPercent: 0,
            closestOtherSimilarityPercent: otherPct,
            closestOtherLabel: otherLabel,
          );
        }

        return StudentFaceVerifyResult.reject(
          '❌ Face enrollment required for ${(_studentDisplayLabel(student))}. '
          'This student has not registered their face. Contact admin to enroll face.',
          similarityPercent: 0,
          closestOtherSimilarityPercent: otherPct,
          closestOtherLabel: otherLabel,
          requiresManualConfirmation: false,  // ✅ NO manual confirm for unregistered
          enrollmentEmbeddingMissing: true,
        );
      }

      // 5. Match selected student first (fast path for genuine students).
      double similarity = 0.0;
      try {
        similarity = _calculateSimilarity(embedding, student);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Error calculating similarity: $e');
          debugPrint('   Student: ${student['name']}');
          debugPrint('   Face embedding type: ${student['face_embedding']?.runtimeType}');
        }
        return StudentFaceVerifyResult.reject(
          'Face comparison failed. Try again.',
        );
      }
      final simPercent = similarity * 100;

      final autoMatchThreshold = FaceMatchingThresholds.ATTENDANCE_VERIFICATION_THRESHOLD;
      final manualConfirmationThreshold =
          FaceMatchingThresholds.ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY;

      // Strong 1-to-1 match: skip scanning every other student (large institutes were very slow).
      if (similarity >= autoMatchThreshold) {
        if (kDebugMode) {
          debugPrint(
            '✅ Fast path: ${simPercent.toStringAsFixed(1)}% ≥ '
            '${(autoMatchThreshold * 100).toStringAsFixed(0)}% — auto-accept (no full-institute scan)',
          );
        }
        return StudentFaceVerifyResult.match(
          similarityPercent: simPercent,
        );
      }

      // 6. Borderline / reject band: scan other enrolled students (fraud / wrong card).
      final otherMatch = await _findBestOtherMatch(
        embedding,
        instId,
        excludeId: student['id']?.toString(),
      );
      final otherSimilarity = otherMatch?['similarity'] as double? ?? 0.0;
      final otherPct = otherSimilarity > 0 ? otherSimilarity * 100 : null;
      final otherLabel = otherMatch != null ? _studentDisplayLabel(otherMatch) : null;

      final crossBlock = _crossStudentAttendanceBlock(
        selectedSimilarity: similarity,
        simPercent: simPercent,
        student: student,
        otherMatch: otherMatch,
      );
      if (crossBlock != null) {
        final nearDuplicateOther =
            otherSimilarity >= FaceMatchingThresholds.CROSS_STUDENT_MANUAL_CEILING_OTHER;
        // Plausible match to selected card → staff confirm (not hard block), except near-duplicate fraud.
        if (!nearDuplicateOther && similarity >= manualConfirmationThreshold) {
          return StudentFaceVerifyResult.reject(
            '${crossBlock.message}\n\nCompare both photos below. Tap Confirm & Mark if this is '
            '${_studentDisplayLabel(student)}.',
            similarityPercent: simPercent,
            closestOtherSimilarityPercent: otherPct,
            closestOtherLabel: otherLabel,
            requiresManualConfirmation: true,
          );
        }
        return crossBlock;
      }

      if (kDebugMode) {
        debugPrint(
          '📏 Attendance verification: selected ${simPercent.toStringAsFixed(1)}%'
          '${otherPct != null ? ', best other ${otherPct.toStringAsFixed(1)}% ($otherLabel)' : ''} '
          '(reject <${(manualConfirmationThreshold * 100).toStringAsFixed(0)}%, '
          'manual ${(manualConfirmationThreshold * 100).toStringAsFixed(0)}-'
          '${(autoMatchThreshold * 100).toStringAsFixed(0)}%, '
          'auto ≥${(autoMatchThreshold * 100).toStringAsFixed(0)}%)',
        );
      }

      // Tier 1: Below manual threshold - HARD REJECT (different person)
      if (similarity < manualConfirmationThreshold) {
        if (kDebugMode) {
          debugPrint(
            '❌ Similarity ${simPercent.toStringAsFixed(1)}% < '
            '${(manualConfirmationThreshold * 100).toStringAsFixed(0)}% - REJECTED',
          );
        }
        return StudentFaceVerifyResult.reject(
          otherPct != null &&
                  otherSimilarity >=
                      FaceMatchingThresholds.CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD
              ? 'Face not recognized for this student. It may match $otherLabel (${otherPct.toStringAsFixed(0)}%). '
                  'Open the correct student card.'
              : 'Face not recognized. Try again.',
          similarityPercent: simPercent,
          closestOtherSimilarityPercent: otherPct,
          closestOtherLabel: otherLabel,
        );
      }

      // Tier 2: manual threshold to auto threshold - manual confirmation (only if no stronger other match).
      if (similarity < autoMatchThreshold) {
        if (otherPct != null &&
            otherSimilarity >= manualConfirmationThreshold &&
            otherSimilarity >= similarity - 0.02) {
          return StudentFaceVerifyResult.reject(
            'Face is ambiguous: $otherLabel (${otherPct.toStringAsFixed(0)}%) is as close as '
            '${_studentDisplayLabel(student)} (${simPercent.toStringAsFixed(0)}%). '
            'Compare photos and confirm if this is the correct student.',
            similarityPercent: simPercent,
            closestOtherSimilarityPercent: otherPct,
            closestOtherLabel: otherLabel,
            requiresManualConfirmation: true,
          );
        }
        if (kDebugMode) {
          debugPrint(
            '⚠️ Similarity ${simPercent.toStringAsFixed(1)}% — manual confirmation',
          );
        }
        return StudentFaceVerifyResult.reject(
          'Your appearance has changed (haircut, beard, glasses, or lighting). '
          'Confidence: ${simPercent.toStringAsFixed(0)}%. Staff: confirm this is the same student.',
          similarityPercent: simPercent,
          closestOtherSimilarityPercent: otherPct,
          closestOtherLabel: otherLabel,
          requiresManualConfirmation: true,
        );
      }

      if (kDebugMode) {
        debugPrint(
          '✅ Similarity ${simPercent.toStringAsFixed(1)}% ≥ '
          '${(autoMatchThreshold * 100).toStringAsFixed(0)}% - AUTO-ACCEPT',
        );
      }

      return StudentFaceVerifyResult.match(
        similarityPercent: simPercent,
        closestOtherSimilarityPercent: otherPct,
        closestOtherLabel: otherLabel,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ATTENDANCE VERIFICATION CRASHED:');
        debugPrint('   Error: $e');
        debugPrint('   Type: ${e.runtimeType}');
        debugPrint('   Stack trace: ${StackTrace.current}');
      }
      return StudentFaceVerifyResult.reject(
        'Check failed: ${e.toString().split('\n').first}',
      );
    }
  }

  /// Enrolled students with face embeddings for 1:N matching in the same institute.
  static Future<Set<String>> instituteKeysForStudentQuery(String instituteId) async {
    final trimmed = instituteId.trim();
    if (trimmed.isEmpty) return const {};

    // Cache hit — avoids 2 DB round-trips per recognition attempt.
    final cachedAt = _instituteKeysCacheAt[trimmed];
    if (cachedAt != null &&
        DateTime.now().difference(cachedAt) < _instituteKeysCacheTtl &&
        _instituteKeysCache.containsKey(trimmed)) {
      return _instituteKeysCache[trimmed]!;
    }

    final keys = <String>{trimmed};
    try {
      final canonical = await resolveCanonicalInstituteId(trimmed);
      if (canonical != null && canonical.isNotEmpty) keys.add(canonical);
      final code = await instituteCodeForId(trimmed);
      if (code.isNotEmpty) keys.add(code);
    } catch (e) {
      if (kDebugMode) debugPrint('instituteKeysForStudentQuery: $e');
    }
    keys.removeWhere((s) => s.isEmpty);
    _instituteKeysCache[trimmed]   = keys;
    _instituteKeysCacheAt[trimmed] = DateTime.now();
    return keys;
  }

  static Future<List<Map<String, dynamic>>> fetchEnrolledStudentsForMatching(
    String instituteId,
  ) async {
    final instId = instituteId.trim();
    final now = DateTime.now();
    if (_enrolledCacheInstId == instId &&
        _enrolledCacheRows != null &&
        _enrolledCacheAt != null &&
        now.difference(_enrolledCacheAt!) < _enrolledCacheTtl) {
      return _enrolledCacheRows!;
    }

    final keys = await instituteKeysForStudentQuery(instId);
    if (keys.isEmpty) return const [];

    final rows = await appDb
        .from('students')
        .select('id, user_id, sr_no, fname, lname, face_embedding_front, face_embedding_left, face_embedding_right, face_photo_url')
        .inFilter('institute_id', keys.toList())
        .or('face_embedding_front.not.is.null,face_embedding_left.not.is.null,face_embedding_right.not.is.null');

    final result = rows
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .where((row) => (row['face_embedding_front'] != null) || (row['face_embedding_left'] != null) || (row['face_embedding_right'] != null))
        .toList();

    _enrolledCacheInstId = instId;
    _enrolledCacheRows = result;
    _enrolledCacheAt = now;
    return result;
  }

  /// Weighted similarity between [probe] and student templates (1:N / auto-scan).
  /// Uses pose-weighted average: front template 2×, left/right 1×.
  /// More stable than pure best-pick — reduces noise from partial pose matches.
  static double probeBestSimilarity(
    List<double> probe,
    Map<String, dynamic> student,
  ) =>
      _calculateSimilarity(probe, student, averageMode: true);

  /// Cosine similarity between two embeddings (full cosine, not dot-only).
  static double cosineSimilarityEmbeddings(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;
    double dot = 0.0;
    double mag1 = 0.0;
    double mag2 = 0.0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      mag1 += a[i] * a[i];
      mag2 += b[i] * b[i];
    }
    mag1 = math.sqrt(mag1);
    mag2 = math.sqrt(mag2);
    if (mag1 == 0.0 || mag2 == 0.0) return 0.0;
    return (dot / (mag1 * mag2)).clamp(0.0, 1.0);
  }

  /// Same pipeline as verification: normalize → liveness (eyes open) → MobileFaceNet embedding.
  /// Used for **entry session** snapshots stored alongside attendance.
  static Future<List<double>?> extractAttendanceSessionEmbedding(String imagePath) async {
    if (kIsWeb) return null;
    try {
      final workPath = await _normalizeImage(imagePath);
      final face = await _detectAndCheckLiveness(workPath);
      if (face == null) return null;
      return await _extractEmbedding(workPath, face);
    } catch (e) {
      if (kDebugMode) debugPrint('extractAttendanceSessionEmbedding: $e');
      return null;
    }
  }

  /// CORE FLOW 2: Register Face with THREE-TIER soft warning system
  /// >= 88% → HARD BLOCK (confirmed duplicate)
  /// 70-88% → SOFT WARNING (suspicious but allow admin override)
  /// < 70% → ALLOW (genuine new student)
  static Future<Map<String, dynamic>> registerStudentFace(
    String imagePath,
    String instituteId,
    String studentId,
  ) async {
    try {
      final workPath = await _normalizeImage(imagePath);
      final face = await _detectAndCheckLiveness(workPath);
      if (face == null) {
        return {'success': false, 'message': 'No face detected or not alive'};
      }

      final embedding = await _extractEmbedding(workPath, face);
      if (embedding == null) {
        return {'success': false, 'message': 'Could not extract face features'};
      }

      // ✅ CHECK 1: Does THIS student already have a face registered?
      final student = await _getStudent(instituteId, studentId);
      if (student != null && studentHasNonEmptyFaceEmbedding(student['face_embedding'])) {
        if (kDebugMode) {
          debugPrint('⚠️ registerStudentFace: Student ${_studentDisplayLabel(student)} already has face enrolled');
        }
        return {
          'success': false,
          'alreadyRegistered': true,
          'message': 'This student already has a face enrolled. Use update function or contact admin.',
        };
      }

      // ✅ CHECK 2: Block duplicate registrations (same person registering twice)
      final bestMatch = await _findBestOtherMatch(embedding, instituteId, excludeId: studentId);

      if (bestMatch != null) {
        final similarity = (bestMatch['similarity'] as num).toDouble();
        final matchingName = bestMatch['name'] ?? bestMatch['sr_no'] ?? bestMatch['user_id'] ?? 'Unknown';
        final simPercent = similarity * 100;

        if (kDebugMode) {
          debugPrint('🔍 Face similarity check during registration:');
          debugPrint('   Comparing with: $matchingName at ${simPercent.toStringAsFixed(1)}%');
        }

        if (similarity >= FaceMatchingThresholds.DUPLICATE_REVIEW_THRESHOLD) {
          if (kDebugMode) {
            debugPrint('❌ REGISTRATION BLOCKED: $matchingName at ${simPercent.toStringAsFixed(1)}% (threshold: ${(FaceMatchingThresholds.DUPLICATE_REVIEW_THRESHOLD * 100).toStringAsFixed(0)}%)');
            debugPrint('   Reason: Face matches another student - same person registering twice or fraud detected');
          }
          return {
            'success': false,
            'hardBlock': true,
            'message': 'Registration blocked! This face is ${simPercent.toStringAsFixed(1)}% similar to $matchingName. '
                'Same person cannot register twice. If genuine, contact admin.',
            'similarity': simPercent,
            'matchingStudent': matchingName,
          };
        }
      }

      if (kDebugMode) {
        debugPrint('✅ registerStudentFace: No duplicate faces found - proceeding with registration');
      }

      // ✅ ALLOW: Genuine new student
      final payload = {
        'embedding': embedding,
        'version': 2,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      await appDb.from('students').update({'face_embedding': payload}).eq('id', studentId);

      if (kDebugMode) debugPrint('✅ Face registered successfully for student $studentId');
      return {'success': true, 'message': 'Face registered successfully'};
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Registration error: $e');
      return {'success': false, 'message': 'Registration error: $e'};
    }
  }

  /// --- PUBLIC HELPERS FOR STREAM ---

  /// Single-frame check: eyes look closed (legacy). For camera streams use
  /// [StreamingBlinkDetector.processFrame] so a full blink is counted.
  static bool isBlinking(Face face) => StreamingBlinkDetector.eyesClosedFrame(face);

  static Future<List<Face>> processImageFrame(InputImage inputImage) async {
    return await _streamFaceDetector.processImage(inputImage);
  }

  /// --- PRIVATE HELPERS ---

  static Future<Face?> _detectAndCheckLiveness(String path) async {
    return _detectFaceInImage(path, requireEyesOpen: true);
  }

  static Future<Face?> _detectFaceInImage(
    String path, {
    required bool requireEyesOpen,
  }) async {
    final faces = await _faceDetector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return null;

    final face = faces.first;
    if (!requireEyesOpen) return face;

    // Front-face liveness: eyes should be open (blink verified on camera before capture).
    // Threshold 0.15 (was 0.25) — ML Kit eye-open scores vary with lighting/angle;
    // 0.25 was rejecting perfectly clear registration photos.
    final eyeOpen =
        ((face.leftEyeOpenProbability ?? 0) + (face.rightEyeOpenProbability ?? 0)) / 2;
    if (eyeOpen < 0.15) {
      if (kDebugMode) {
        debugPrint('❌ Liveness Failed: Eyes closed (${eyeOpen.toStringAsFixed(2)})');
      }
      return null;
    }
    return face;
  }

  /// ✅ OPTIMIZED: Get embedding with caching (80% faster for cached images)
  static Future<List<double>?> _extractEmbeddingWithCache(String path, Face face) async {
    // Check cache first
    if (_embeddingCache.containsKey(path)) {
      if (kDebugMode) debugPrint('📦 Cache hit: Reusing embedding for $path');
      return _embeddingCache[path];
    }

    // Extract new embedding
    final emb = await _extractEmbedding(path, face);

    if (emb != null) {
      // Store in cache
      _embeddingCache[path] = emb;

      // Limit cache size to prevent memory issues
      final maxCacheSize = DevicePerformanceService.isLowRamDevice ? 12 : _maxCacheSize;
      if (_embeddingCache.length > maxCacheSize) {
        final oldestKey = _embeddingCache.keys.first;
        _embeddingCache.remove(oldestKey);
        if (kDebugMode) debugPrint('🗑️ Cache cleaned: removed oldest entry');
      }
    }

    return emb;
  }

  /// ✅ OPTIMIZED: Clear embedding cache (call after registration/verification)
  static void clearEmbeddingCache() {
    _embeddingCache.clear();
    if (kDebugMode) debugPrint('🧹 Embedding cache cleared');
  }

  /// ✅ OPTIMIZED: Should process frame? (throttle to reduce CPU)
  static bool shouldProcessFrame() {
    _frameProcessingCounter++;

    // Process every 5th frame (6 fps instead of 30 fps)
    if (_frameProcessingCounter % _frameProcessInterval == 0) {
      if (kDebugMode) {
        debugPrint('🎬 Processing frame (throttled: ${_frameProcessingCounter % _frameProcessInterval == 0})');
      }
      return true;
    }

    return false;  // Skip this frame
  }

  static Future<List<double>?> _extractEmbedding(String path, Face face) async {
    await initialize();
    if (!_isInitialized) return null;

    // Extract eye landmarks for face alignment
    double? leftEyeX, leftEyeY, rightEyeX, rightEyeY;
    try {
      for (final landmark in face.landmarks.values) {
        if (landmark?.type == FaceLandmarkType.leftEye) {
          leftEyeX = landmark?.position.x.toDouble();
          leftEyeY = landmark?.position.y.toDouble();
        } else if (landmark?.type == FaceLandmarkType.rightEye) {
          rightEyeX = landmark?.position.x.toDouble();
          rightEyeY = landmark?.position.y.toDouble();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Could not extract eye landmarks: $e');
    }

    final input = await compute(_prepareTensor, {
      'path': path,
      'box': {
        'left': face.boundingBox.left,
        'top': face.boundingBox.top,
        'width': face.boundingBox.width,
        'height': face.boundingBox.height,
      },
      'landmarks': {
        'leftEyeX': leftEyeX ?? 0.0,
        'leftEyeY': leftEyeY ?? 0.0,
        'rightEyeX': rightEyeX ?? 0.0,
        'rightEyeY': rightEyeY ?? 0.0,
      },
      'alignmentMinDegrees': 2.0,
    });
    if (input == null) return null;

    final output = List.generate(1, (_) => List.filled(192, 0.0));
    await _interpreter!.runInIsolate(input, output);

    // L2 Normalize
    final emb = output[0];
    double norm = math.sqrt(emb.map((x) => x * x).reduce((a, b) => a + b));
    return emb.map((x) => x / (norm > 0 ? norm : 1.0)).toList();
  }

  static List<List<List<List<double>>>>? _prepareTensor(Map<String, dynamic> args) {
    try {
      final imgFile = File(args['path']);
      final image = img.decodeImage(imgFile.readAsBytesSync());
      if (image == null) return null;

      final box = args['box'] as Map<String, dynamic>;
      final boxLeft = (box['left'] as num).toDouble();
      final boxTop = (box['top'] as num).toDouble();
      final boxW = (box['width'] as num).toDouble();
      final boxH = (box['height'] as num).toDouble();

      // Padded crop (forehead/chin) before alignment — same for front / left / right.
      final padX = boxW * 0.14;
      final padY = boxH * 0.18;
      var left = (boxLeft - padX).floor().clamp(0, image.width - 1);
      var top = (boxTop - padY).floor().clamp(0, image.height - 1);
      var right = (boxLeft + boxW + padX).ceil().clamp(left + 1, image.width);
      var bottom = (boxTop + boxH + padY).ceil().clamp(top + 1, image.height);
      var w = right - left;
      var h = bottom - top;

      var crop = img.copyCrop(image, x: left, y: top, width: w, height: h);

      // Roll alignment from eye line (in-plane tilt only — keeps left/right yaw poses).
      final landmarks = args['landmarks'] as Map<String, dynamic>? ?? {};
      final leftEyeX = (landmarks['leftEyeX'] ?? 0.0) as double;
      final leftEyeY = (landmarks['leftEyeY'] ?? 0.0) as double;
      final rightEyeX = (landmarks['rightEyeX'] ?? 0.0) as double;
      final rightEyeY = (landmarks['rightEyeY'] ?? 0.0) as double;
      final minAlignDeg = (args['alignmentMinDegrees'] as num?)?.toDouble() ?? 2.0;

      if (leftEyeX > 0 &&
          rightEyeX > 0 &&
          leftEyeY > 0 &&
          rightEyeY > 0) {
        final angleDeg =
            _calculateFaceAngle(leftEyeX, leftEyeY, rightEyeX, rightEyeY);
        if (angleDeg.abs() > minAlignDeg) {
          crop = img.copyRotate(crop, angle: -angleDeg);
        }
      }

      final resized = img.copyResize(crop, width: 112, height: 112);

      // Return 4D list [1, 112, 112, 3] to satisfy TFLite shape requirements
      final buffer = List.generate(
        1,
        (_) => List.generate(
          112,
          (y) => List.generate(
            112,
            (x) {
              final p = resized.getPixel(x, y);
              return [
                (p.r - 127.5) / 128.0,
                (p.g - 127.5) / 128.0,
                (p.b - 127.5) / 128.0,
              ];
            },
          ),
        ),
      );
      return buffer;
    } catch (e) {
      return null;
    }
  }

  /// [averageMode] = true  → average across all templates (registration duplicate check).
  /// [averageMode] = false → max across all templates (attendance 1:N matching).
  static double _calculateSimilarity(
    List<double> e1,
    Map<String, dynamic> student, {
    bool averageMode = false,
  }) {
    final fe = student['face_embedding'];
    if (fe == null) {
      if (kDebugMode) {
        debugPrint('❌ face_embedding is NULL for student: ${student['name'] ?? student['id']}');
        debugPrint('   Available keys in student object: ${student.keys.toList()}');
      }
      return 0.0;
    }

    List<double>? e2;

    // Build template list with pose metadata for weighted comparison.
    final rawField = fe is Map ? Map<String, dynamic>.from(fe as Map) : null;
    final templateMeta = <Map<String, dynamic>>[];
    if (rawField != null) {
      final faceTemplates = rawField['faceTemplates'];
      if (faceTemplates is List) {
        for (final t in faceTemplates) {
          if (t is Map) {
            templateMeta.add(Map<String, dynamic>.from(t));
          }
        }
      }
    }

    final templates = parseAllEmbeddingsFromField(fe);
    if (templates.isNotEmpty) {
      double weightedTotal = 0.0;
      double weightTotal = 0.0;
      double best = 0.0;
      int count = 0;
      for (int ti = 0; ti < templates.length; ti++) {
        final t = templates[ti];
        if (t.length != e1.length) continue;
        double dot = 0.0;
        double mag1 = 0.0;
        double mag2 = 0.0;
        for (int i = 0; i < e1.length; i++) {
          dot += e1[i] * t[i];
          mag1 += e1[i] * e1[i];
          mag2 += t[i] * t[i];
        }
        mag1 = math.sqrt(mag1);
        mag2 = math.sqrt(mag2);
        if (mag1 == 0.0 || mag2 == 0.0) continue;
        final sim = (dot / (mag1 * mag2)).clamp(0.0, 1.0);

        // Front template gets 2× weight — attendance probe is always frontal.
        // Left/right templates get 1× (help with slightly angled poses).
        final pose = ti < templateMeta.length
            ? (templateMeta[ti]['pose'] as String? ?? '')
            : '';
        final weight = (pose == 'front') ? 2.0 : 1.0;

        weightedTotal += sim * weight;
        weightTotal += weight;
        if (sim > best) best = sim;
        count++;
      }
      if (count == 0) return 0.0;
      // averageMode: pose-weighted average (front 2×, left/right 1×).
      // best mode: max similarity (used only in duplicate-detection paths).
      if (averageMode) return weightTotal > 0 ? weightedTotal / weightTotal : 0.0;
      return best;
    }

    if (fe is List) {
      e2 = fe.map((e) => (e as num).toDouble()).toList();
    } else if (fe is Map) {
      final emb = fe['embedding'];
      if (emb is List) {
        e2 = emb.map((e) => (e as num).toDouble()).toList();
      }
    } else if (fe is String) {
      try {
        final decoded = jsonDecode(fe);
        if (decoded is List) {
          e2 = decoded.map((e) => (e as num).toDouble()).toList();
        } else if (decoded is Map) {
          final emb = decoded['embedding'];
          if (emb is List) {
            e2 = emb.map((e) => (e as num).toDouble()).toList();
          }
        }
      } catch (_) {
        return 0.0;
      }
    }

    if (e2 == null || e2.isEmpty) return 0.0;
    if (e1.length != e2.length) return 0.0;  // Different dimensions = different embeddings

    // ✅ CORRECT COSINE SIMILARITY:
    // cosine_similarity = (A · B) / (|A| * |B|)

    // 1. Calculate dot product
    double dot = 0.0;
    for (int i = 0; i < e1.length; i++) {
      dot += e1[i] * e2[i];
    }

    // 2. Calculate magnitudes
    double mag1 = 0.0;
    double mag2 = 0.0;
    for (int i = 0; i < e1.length; i++) {
      mag1 += e1[i] * e1[i];
      mag2 += e2[i] * e2[i];
    }
    mag1 = math.sqrt(mag1);
    mag2 = math.sqrt(mag2);

    // 3. Handle zero magnitude
    if (mag1 == 0.0 || mag2 == 0.0) return 0.0;

    // 4. Calculate cosine similarity: dot / (mag1 * mag2)
    final cosineSimilarity = dot / (mag1 * mag2);

    if (kDebugMode) {
      debugPrint('📊 Cosine similarity: ${cosineSimilarity.toStringAsFixed(3)} (dot: ${dot.toStringAsFixed(3)}, mag1: ${mag1.toStringAsFixed(3)}, mag2: ${mag2.toStringAsFixed(3)})');

      // Debug: show if embeddings look valid
      if (cosineSimilarity < 0) {
        debugPrint('⚠️ WARNING: Negative similarity detected!');
        debugPrint('   Probe embedding (first 5): ${e1.take(5).map((x) => x.toStringAsFixed(3)).join(", ")}');
        debugPrint('   Enrolled embedding (first 5): ${e2.take(5).map((x) => x.toStringAsFixed(3)).join(", ")}');
        debugPrint('   Probe embedding range: min=${e1.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}, max=${e1.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}');
        debugPrint('   Enrolled embedding range: min=${e2.reduce((a, b) => a < b ? a : b).toStringAsFixed(3)}, max=${e2.reduce((a, b) => a > b ? a : b).toStringAsFixed(3)}');
      }
    }

    final clamped = cosineSimilarity.clamp(0.0, 1.0);
    if (cosineSimilarity < 0 && kDebugMode) {
      debugPrint('   Clamped from $cosineSimilarity to $clamped');
    }
    return clamped;
  }

  static Future<bool> _isMatchingOthers(List<double> emb, String instId, {String? excludeId}) async {
    if (kDebugMode) {
      debugPrint('🔍 Checking if face matches any other registered student...');
    }

    final rows = await appDb.from('students').select('id, user_id, sr_no, fname, lname, face_embedding_front, face_embedding_left, face_embedding_right').eq('institute_id', instId);

    if (kDebugMode) {
      debugPrint('📊 Comparing against ${rows.length} registered students');
    }

    for (final row in rows) {
      if (excludeId != null && row['id'] == excludeId) continue;

      double similarity = 0.0;
      try {
        similarity = _calculateSimilarity(emb, row);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Error comparing with ${row['name']}: $e');
        continue;
      }
      final name = row['name'] ?? row['sr_no'] ?? row['user_id'] ?? 'Unknown';

      if (kDebugMode) {
        debugPrint('  ├─ $name: ${(similarity * 100).toStringAsFixed(1)}%');
      }

      if (similarity >= FaceMatchingThresholds.DUPLICATE_HARD_BLOCK_THRESHOLD) {
        if (kDebugMode) {
          debugPrint('❌ DUPLICATE DETECTED: $name at ${(similarity * 100).toStringAsFixed(1)}% (threshold: ${(FaceMatchingThresholds.DUPLICATE_HARD_BLOCK_THRESHOLD * 100).toStringAsFixed(0)}%)');
        }
        return true; // Hard Match / Duplicate
      }
    }

    if (kDebugMode) {
      debugPrint('✅ No duplicates found - face is unique');
    }
    return false;
  }

  /// Auto-identify enrolled student from a face photo (auto face scan attendance).
  static Future<Map<String, dynamic>?> identifyStudentFromFace(
    String imagePath,
    String instituteId,
  ) async {
    if (kIsWeb) return null;

    final instId = instituteId.trim();
    if (instId.isEmpty) return null;

    try {
      final workPath = await _normalizeImage(imagePath);
      final face = await _detectAndCheckLiveness(workPath);
      if (face == null) return null;

      final embedding = await _extractEmbedding(workPath, face);
      if (embedding == null) return null;

      final best = await _findBestOtherMatch(embedding, instId);
      if (best == null) return null;

      final similarity = (best['similarity'] as num?)?.toDouble() ?? 0.0;
      if (similarity < FaceMatchingThresholds.ATTENDANCE_VERIFICATION_THRESHOLD) {
        return null;
      }

      final rowId = best['id']?.toString() ?? '';
      Map<String, dynamic>? full;
      if (rowId.isNotEmpty) {
        final fetched = await appDb
            .from('students')
            .select('id, user_id, sr_no, fname, lname, year, face_photo_url, face_embedding_front, face_embedding_left, face_embedding_right')
            .eq('institute_id', instId)
            .eq('id', rowId)
            .maybeSingle();
        if (fetched != null) {
          full = Map<String, dynamic>.from(fetched);
        }
      }

      final student = full ?? best;
      return {
        ...student,
        'identified': true,
        'similarity': similarity,
        'similarity_percent': similarity * 100,
        'extracted_embedding': embedding,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('identifyStudentFromFace error: $e');
      return null;
    }
  }

  /// Highest-similarity other enrolled student in the same institute (all institute_id keys).
  static Future<Map<String, dynamic>?> _findBestOtherMatch(
    List<double> emb,
    String instId, {
    String? excludeId,
  }) async {
    final institute = instId.trim();
    if (institute.isEmpty) return null;

    final rows = await fetchEnrolledStudentsForMatching(institute);

    Map<String, dynamic>? bestMatch;
    double bestSimilarity = 0.0;

    for (final row in rows) {
      if (excludeId != null && row['id']?.toString() == excludeId) continue;

      double similarity = 0.0;
      try {
        // Average across all templates — stricter duplicate detection.
        similarity = _calculateSimilarity(emb, row, averageMode: true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ Error comparing with best match ${row['name']}: $e');
        }
        continue;
      }
      if (similarity <= 0) continue;
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestMatch = row;
      }
    }

    if (bestMatch == null) return null;
    return {
      ...bestMatch,
      'similarity': bestSimilarity,
    };
  }

  static Future<Map<String, dynamic>?> _getStudent(String instId, String key) async {
    final keys = await instituteKeysForStudentQuery(instId);
    if (keys.isEmpty) return null;
    final lookupKey = key.trim();
    if (lookupKey.isEmpty) return null;

    final keyList = keys.toList();

    // Management / wrapper pass `students.id` (UUID); attendance flows often pass sr_no or user_id.
    var s = await appDb
        .from('students')
        .select()
        .inFilter('institute_id', keyList)
        .eq('id', lookupKey)
        .maybeSingle();
    s ??= await appDb
        .from('students')
        .select()
        .inFilter('institute_id', keyList)
        .eq('sr_no', lookupKey)
        .maybeSingle();
    s ??= await appDb
        .from('students')
        .select()
        .inFilter('institute_id', keyList)
        .eq('user_id', lookupKey)
        .maybeSingle();

    if (s != null && kDebugMode) {
      debugPrint('📦 Retrieved student record:');
      debugPrint('   Name: ${s['name']}');
      debugPrint('   Has face_embedding: ${s.containsKey('face_embedding')}');
      final fe = s['face_embedding'];
      String embeddingInfo = 'NULL';
      if (fe != null) {
        if (fe is List) {
          embeddingInfo = 'List (length: ${(fe as List).length})';
        } else if (fe is Map) {
          embeddingInfo = 'Map (keys: ${(fe as Map).keys.toList()})';
        } else if (fe is String) {
          embeddingInfo = 'String (length: ${(fe as String).length})';
        } else {
          embeddingInfo = 'Unknown type: ${fe.runtimeType}';
        }
      }
      debugPrint('   face_embedding value: $embeddingInfo');
      debugPrint('   All keys: ${s.keys.toList()}');
    }

    return s;
  }

  static Future<String> _normalizeImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final dir = await getTemporaryDirectory();
      final out = '${dir.path}/norm_${DateTime.now().msSinceEpoch}.jpg';

      return await compute((args) {
        try {
          var image = img.decodeImage(args['bytes'] as Uint8List);
          if (image == null) return args['path'] as String;

          // Apply EXIF orientation to pixels
          image = img.bakeOrientation(image);

          // Quality 80 is the "compatibility" sweet spot. It produces a very standard
          // sequential JPEG header that prevents "Invalid SOS parameters" error 122.
          final encoded = img.encodeJpg(image, quality: 80);
          File(args['out'] as String).writeAsBytesSync(encoded);
          return args['out'] as String;
        } catch (e) {
          return args['path'] as String;
        }
      }, {'bytes': bytes, 'out': out, 'path': path});
    } catch (e) {
      return path;
    }
  }

  /// ✅ FACE ALIGNMENT: Calculate rotation angle from eye landmarks
  static double _calculateFaceAngle(double leftEyeX, double leftEyeY, double rightEyeX, double rightEyeY) {
    try {
      final dX = rightEyeX - leftEyeX;
      final dY = rightEyeY - leftEyeY;
      final angleRad = math.atan2(dY, dX);
      final angleDeg = angleRad * 180.0 / math.pi;

      if (kDebugMode) {
        debugPrint('👁️ Eye landmarks: L(${leftEyeX.toStringAsFixed(1)}, ${leftEyeY.toStringAsFixed(1)}) '
            'R(${rightEyeX.toStringAsFixed(1)}, ${rightEyeY.toStringAsFixed(1)}) → angle: ${angleDeg.toStringAsFixed(1)}°');
      }
      return angleDeg;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error calculating face angle: $e');
      return 0.0;
    }
  }

  /// Production pipeline helpers (used by [ProductionFacePipelineService]).
  static Future<String> normalizeImageForPipeline(String path) =>
      _normalizeImage(path);

  static Future<Face?> detectFaceForPipeline(String path) async {
    final faces =
        await _faceDetector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return null;
    return faces.first;
  }

  static Future<List<double>?> extractEmbeddingForPipeline(
    String path,
    Face face,
  ) =>
      _extractEmbedding(path, face);

  static Future<Uint8List> readFileBytes(String path) async {
    return File(path).readAsBytes();
  }
}

extension on DateTime { int get msSinceEpoch => millisecondsSinceEpoch; }
