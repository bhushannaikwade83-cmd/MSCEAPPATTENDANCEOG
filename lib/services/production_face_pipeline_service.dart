import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/app_db.dart';
import '../core/production_face_recognition_constants.dart';
import 'anti_spoof_service.dart';
import 'face_recognition_service.dart';
import 'insightface_api_service.dart';
import 'student_face_match_index.dart';

/// Production attendance pipeline:
/// Camera frame → (RetinaFace+ArcFace via API **or** ML Kit+MobileFaceNet on-device)
/// → MiniFAS liveness → embedding match (≥0.85, margin ≥0.05).
class ProductionFacePipelineService {
  ProductionFacePipelineService._();

  /// Use InsightFace API when INSIGHTFACE_API_BASE is set in app_config.env.
  static Future<bool> _useInsightFaceApi() async =>
      await InsightFaceApiService.healthCheck();

  /// Process one still frame (JPEG bytes or file path) for auto attendance.
  ///
  /// [fastAttendancePath] runs lenient auto-scan liveness (still blocks photo/screen).
  static Future<ProductionFacePipelineResult> processFrame({
    required String photoPath,
    required String instituteId,
    Uint8List? photoBytes,
    bool fastAttendancePath = false,
  }) async {
    final started = DateTime.now();
    final bytes = photoBytes ?? await _readBytes(photoPath);
    if (bytes == null || bytes.isEmpty) {
      return ProductionFacePipelineResult.fail(
        'Could not read camera photo',
        started: started,
      );
    }

    if (await _useInsightFaceApi()) {
      return _processViaApi(
        photoPath: photoPath,
        photoBytes: bytes,
        instituteId: instituteId,
        started: started,
      );
    }
    return _processOnDevice(
      photoPath: photoPath,
      instituteId: instituteId,
      started: started,
      fastAttendancePath: fastAttendancePath,
    );
  }

  static Future<ProductionFacePipelineResult> _processViaApi({
    required String photoPath,
    required Uint8List photoBytes,
    required String instituteId,
    required DateTime started,
  }) async {
    final api = await InsightFaceApiService.recognizeFaceMultipart(
      photoBytes: photoBytes,
      fileName: 'frame.jpg',
      instituteId: instituteId,
      threshold: ProductionFaceRecognitionConstants.recognitionConfidenceThreshold,
    );

    if (api == null) {
      return ProductionFacePipelineResult.fail(
        'Recognition service unavailable',
        started: started,
        pipeline: ProductionPipelineMode.insightFaceApi,
      );
    }

    if (api['liveness_passed'] == false) {
      return ProductionFacePipelineResult.fail(
        'Liveness check failed — use a live face, not a photo or screen',
        started: started,
        pipeline: ProductionPipelineMode.insightFaceApi,
        livenessPassed: false,
        livenessConfidence: (api['liveness_confidence'] as num?)?.toDouble(),
      );
    }

    if (api['success'] != true || api['match'] == null) {
      return ProductionFacePipelineResult.fail(
        '❌ Face doesn\'t match any registered student — Make sure your photo quality is good and face is clearly visible',
        started: started,
        pipeline: ProductionPipelineMode.insightFaceApi,
        livenessPassed: api['liveness_passed'] as bool? ?? true,
        livenessConfidence: (api['liveness_confidence'] as num?)?.toDouble(),
      );
    }

    final match = Map<String, dynamic>.from(api['match'] as Map);
    final similarity = (api['similarity'] as num?)?.toDouble() ?? 0.0;
    final margin = (api['margin'] as num?)?.toDouble() ?? 0.0;

    if (similarity <
        ProductionFaceRecognitionConstants.recognitionConfidenceThreshold) {
      return ProductionFacePipelineResult.fail(
        '⚠️ Face similar but score is low (${(similarity * 100).toStringAsFixed(1)}%) — Try better lighting or angle, ensure full face is visible',
        started: started,
        pipeline: ProductionPipelineMode.insightFaceApi,
        similarity: similarity,
        margin: margin,
      );
    }
    if (margin < ProductionFaceRecognitionConstants.recognitionMarginThreshold) {
      return ProductionFacePipelineResult.fail(
        'Ambiguous match — stand closer and face the camera',
        started: started,
        pipeline: ProductionPipelineMode.insightFaceApi,
        similarity: similarity,
        margin: margin,
      );
    }

    final studentId = match['student_id']?.toString() ?? '';
    final full = await _fetchStudentRow(instituteId, studentId: studentId);
    final student = full ??
        {
          'id': studentId,
          'name': match['name']?.toString() ?? 'Student',
          'sr_no': match['roll_number']?.toString() ?? '',
        };

    return ProductionFacePipelineResult.success(
      student: student,
      photoPath: photoPath,
      similarity: similarity,
      margin: margin,
      livenessPassed: true,
      livenessConfidence:
          (api['liveness_confidence'] as num?)?.toDouble() ?? 1.0,
      pipeline: ProductionPipelineMode.insightFaceApi,
      detectionBackend: 'RetinaFace',
      recognitionBackend: ProductionFaceRecognitionConstants.modelArcFaceBuffaloL,
      embeddingDimensions:
          ProductionFaceRecognitionConstants.arcFaceEmbeddingDimensions,
      started: started,
    );
  }

  static Future<ProductionFacePipelineResult> _processOnDevice({
    required String photoPath,
    required String instituteId,
    required DateTime started,
    bool fastAttendancePath = false,
  }) async {
    debugPrint('🔵 PIPELINE: Starting on-device face processing...');

    // Capture-time PAD: final hard gate against photo/screen spoofs.
    debugPrint('🛡️ PIPELINE: Checking liveness/spoof...');
    if (AntiSpoofService.isModelLoaded) {
      final pad = await AntiSpoofService.checkSpoofForAutoScan(photoPath);
      final liveScore = pad.confidence * 100;
      final spoofScore = AntiSpoofService.spoofConfidence(pad) * 100;

      if (kDebugMode) {
        debugPrint('');
        debugPrint('═══════════════════════════════════════════════');
        debugPrint('🛡️  ANTI-SPOOF DETECTION SCORE');
        debugPrint('═══════════════════════════════════════════════');
        debugPrint('   isReal: ${pad.isReal}');
        debugPrint('   LIVE Score: ${liveScore.toStringAsFixed(1)}%');
        debugPrint('   SPOOF Score: ${spoofScore.toStringAsFixed(1)}%');
        debugPrint('   Reason: ${pad.reason}');
        debugPrint('   Threshold: LIVE > 50% = ACCEPT');
        debugPrint('═══════════════════════════════════════════════');
        debugPrint('');
      }

      if (AntiSpoofService.shouldRejectAutoScanCapture(pad)) {
        return ProductionFacePipelineResult.fail(
          '🛡️ Spoof detection failed — Use a live face, not a photo/video/screen (Confidence: ${(pad.confidence * 100).toStringAsFixed(0)}%)',
          started: started,
          pipeline: ProductionPipelineMode.onDevice,
          livenessPassed: false,
          livenessConfidence: pad.confidence,
        );
      }
    }

    final workPath = await FaceRecognitionService.normalizeImageForPipeline(photoPath);
    final face = await FaceRecognitionService.detectFaceForPipeline(workPath);
    if (face == null) {
      return ProductionFacePipelineResult.fail(
        '📷 Face quality check failed — Center your face in the frame, ensure good lighting, and look at the camera',
        started: started,
        pipeline: ProductionPipelineMode.onDevice,
        livenessPassed: true,
        livenessConfidence: 0.0,
      );
    }

    final embedding =
        await FaceRecognitionService.extractEmbeddingForPipeline(workPath, face);
    if (embedding == null || embedding.isEmpty) {
      return ProductionFacePipelineResult.fail(
        '⚠️ Could not extract face features — Try with clearer photo and better lighting',
        started: started,
        pipeline: ProductionPipelineMode.onDevice,
        livenessPassed: true,
        livenessConfidence: 0.0,
      );
    }

    final match = await StudentFaceMatchIndex.matchProbe(
      probeEmbedding: embedding,
      instituteId: instituteId,
      minConfidence:
          ProductionFaceRecognitionConstants.onDeviceRecognitionConfidenceThreshold,
    );
    if (match == null) {
      final enrolled = await FaceRecognitionService.fetchEnrolledStudentsForMatching(
        instituteId,
      );
      final message = enrolled.isEmpty
          ? '❌ No students with registered faces found — Complete 3-photo face registration first before marking attendance'
          : '⚠️ Face not recognized (Score: ${(0.0 * 100).toStringAsFixed(1)}%) — Use the same person who registered, ensure good light, hold phone at ~3 ft, and center your face';
      return ProductionFacePipelineResult.fail(
        message,
        started: started,
        pipeline: ProductionPipelineMode.onDevice,
        livenessPassed: true,
        livenessConfidence: 0.0,
      );
    }

    final full = await _fetchStudentRow(
      instituteId,
      studentId: match.studentId,
    );
    final student = full ?? match.toStudentMap();

    return ProductionFacePipelineResult.success(
      student: student,
      photoPath: photoPath,
      similarity: match.similarity,
      margin: match.margin,
      livenessPassed: true,
      livenessConfidence: 0.0,
      pipeline: ProductionPipelineMode.onDevice,
      detectionBackend: 'Google ML Kit',
      recognitionBackend: ProductionFaceRecognitionConstants.modelMobileFaceNet,
      embeddingDimensions: embedding.length,
      started: started,
    );
  }

  static Future<Map<String, dynamic>?> _fetchStudentRow(
    String instituteId, {
    required String studentId,
  }) async {
    if (studentId.isEmpty) return null;
    final row = await appDb
        .from('students')
        .select(
          'id, user_id, sr_no, name, year, subject, subjects, face_photo_url, face_embedding',
        )
        .eq('institute_id', instituteId.trim())
        .eq('id', studentId)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  static Future<Uint8List?> _readBytes(String path) async {
    try {
      return await FaceRecognitionService.readFileBytes(path);
    } catch (_) {
      return null;
    }
  }
}

enum ProductionPipelineMode { insightFaceApi, onDevice }

class ProductionFacePipelineResult {
  const ProductionFacePipelineResult._({
    required this.passed,
    required this.message,
    this.student,
    this.photoPath,
    this.similarity,
    this.margin,
    this.livenessPassed,
    this.livenessConfidence,
    this.pipeline,
    this.detectionBackend,
    this.recognitionBackend,
    this.embeddingDimensions,
    required this.processingMs,
  });

  final bool passed;
  final String message;
  final Map<String, dynamic>? student;
  final String? photoPath;
  final double? similarity;
  final double? margin;
  final bool? livenessPassed;
  final double? livenessConfidence;
  final ProductionPipelineMode? pipeline;
  final String? detectionBackend;
  final String? recognitionBackend;
  final int? embeddingDimensions;
  final int processingMs;

  factory ProductionFacePipelineResult.success({
    required Map<String, dynamic> student,
    required String photoPath,
    required double similarity,
    required double margin,
    required bool livenessPassed,
    required double livenessConfidence,
    required ProductionPipelineMode pipeline,
    required String detectionBackend,
    required String recognitionBackend,
    required int embeddingDimensions,
    required DateTime started,
  }) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    return ProductionFacePipelineResult._(
      passed: true,
      message: 'Recognized ${student['name'] ?? 'student'}',
      student: {
        ...student,
        'identified': true,
        'similarity': similarity,
        'similarity_percent': similarity * 100,
        'margin': margin,
      },
      photoPath: photoPath,
      similarity: similarity,
      margin: margin,
      livenessPassed: livenessPassed,
      livenessConfidence: livenessConfidence,
      pipeline: pipeline,
      detectionBackend: detectionBackend,
      recognitionBackend: recognitionBackend,
      embeddingDimensions: embeddingDimensions,
      processingMs: ms,
    );
  }

  factory ProductionFacePipelineResult.fail(
    String message, {
    required DateTime started,
    ProductionPipelineMode? pipeline,
    bool? livenessPassed,
    double? livenessConfidence,
    double? similarity,
    double? margin,
  }) {
    final ms = DateTime.now().difference(started).inMilliseconds;
    return ProductionFacePipelineResult._(
      passed: false,
      message: message,
      livenessPassed: livenessPassed,
      livenessConfidence: livenessConfidence,
      similarity: similarity,
      margin: margin,
      pipeline: pipeline,
      processingMs: ms,
    );
  }
}
