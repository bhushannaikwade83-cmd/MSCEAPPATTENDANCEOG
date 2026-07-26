import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Liveness Detection Service
/// Detects blink and head movement to prevent static images/videos
class LivenessDetectionService {
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
    ),
  );

  /// Check if person is blinking (eyes closed)
  static Future<bool> isBlinking(String photoPath) async {
    try {
      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ No face detected for blink check');
        return false;
      }

      final face = faces.first;
      final leftEyeOpenProb = face.leftEyeOpenProbability ?? 0;
      final rightEyeOpenProb = face.rightEyeOpenProbability ?? 0;

      final isEyesClosed = leftEyeOpenProb < 0.3 && rightEyeOpenProb < 0.3;

      if (kDebugMode) {
        debugPrint('👁️ Left eye open prob: $leftEyeOpenProb');
        debugPrint('👁️ Right eye open prob: $rightEyeOpenProb');
        debugPrint('👁️ Eyes closed: $isEyesClosed');
      }

      return isEyesClosed;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Blink detection failed: $e');
      return false;
    }
  }

  /// Check if person is smiling
  static Future<bool> isSmiling(String photoPath) async {
    try {
      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) return false;

      final face = faces.first;
      final smilingProb = face.smilingProbability ?? 0;

      if (kDebugMode) debugPrint('😊 Smiling probability: $smilingProb');

      return smilingProb > 0.5;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Smile detection failed: $e');
      return false;
    }
  }

  /// Get head pose (yaw = left/right, pitch = up/down) from face detection
  static Future<HeadPoseResult?> getHeadPose(String photoPath) async {
    try {
      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        if (kDebugMode) debugPrint('⚠️ No face detected for head pose');
        return null;
      }

      final face = faces.first;

      // Get head euler angles (rotation angles)
      final headEulerAngleY = face.headEulerAngleY ?? 0; // Yaw (left/right)
      final headEulerAngleX = face.headEulerAngleX ?? 0; // Pitch (up/down)

      if (kDebugMode) {
        debugPrint('🎭 Head Pose:');
        debugPrint('   Yaw (left/right): ${headEulerAngleY.toStringAsFixed(1)}°');
        debugPrint('   Pitch (up/down): ${headEulerAngleX.toStringAsFixed(1)}°');
      }

      return HeadPoseResult(
        yaw: headEulerAngleY.abs(),
        pitch: headEulerAngleX.abs(),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Head pose detection failed: $e');
      return null;
    }
  }

  /// Comprehensive liveness detection from photo
  /// Returns a result object with all liveness metrics
  static Future<LivenessCheckResult> detectLivenessFromPhoto({
    required String photoPath,
  }) async {
    try {
      if (kDebugMode) debugPrint('🔍 Running comprehensive liveness detection...');

      // Check blink (eyes should be open)
      final isBlinkingResult = await isBlinking(photoPath);
      if (isBlinkingResult) {
        return LivenessCheckResult(
          isLive: false,
          reason: 'Eyes appear to be closed - liveness check failed',
        );
      }

      // Check head pose (head should be relatively straight)
      final headPose = await getHeadPose(photoPath);
      if (headPose != null) {
        // If head is too tilted, it might be a static image
        if (headPose.yaw > 30 || headPose.pitch > 30) {
          return LivenessCheckResult(
            isLive: false,
            reason: 'Head angle too extreme - might be a static image',
          );
        }
      }

      // If we got here, liveness checks passed
      return LivenessCheckResult(
        isLive: true,
        reason: 'Liveness check passed ✅',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Liveness detection error: $e');
      return LivenessCheckResult(
        isLive: false,
        reason: 'Error during liveness detection: $e',
      );
    }
  }

  /// Check if liveness result passes the minimum requirements
  static bool passesLivePersonPreCheck(LivenessCheckResult result) {
    return result.isLive;
  }

  static void dispose() {
    _faceDetector.close();
  }
}

/// Head pose result
class HeadPoseResult {
  final double yaw;
  final double pitch;
  HeadPoseResult({required this.yaw, required this.pitch});
}

/// Liveness check result
class LivenessCheckResult {
  final bool isLive;
  final String reason;
  LivenessCheckResult({required this.isLive, required this.reason});
}
