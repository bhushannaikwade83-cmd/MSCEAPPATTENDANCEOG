import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Detects eye blinks using eye aspect ratio from ML Kit face landmarks
class EyeBlinkDetector {
  static const double _eyeAspectRatioThreshold = 0.15; // Eyes closed
  static const int _blinkFrameThreshold = 2; // Consecutive frames to confirm blink

  bool _eyesWereOpen = false;
  int _closedFrameCount = 0;
  bool _blinkDetected = false;

  /// Process face landmarks and detect blink
  /// Returns true if blink detected (eyes closed then opened)
  bool processFrame(Face? face) {
    _blinkDetected = false;

    if (face == null) {
      _eyesWereOpen = false;
      _closedFrameCount = 0;
      return false;
    }

    try {
      // Get eye landmarks from face
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      if (leftEye == null || rightEye == null) {
        return false;
      }

      // Calculate eye aspect ratio (EAR) using landmark positions
      final leftEAR = _calculateEyeAspectRatio(leftEye);
      final rightEAR = _calculateEyeAspectRatio(rightEye);
      final avgEAR = (leftEAR + rightEAR) / 2;

      if (kDebugMode) {
        debugPrint('👁️ Eye Aspect Ratio: ${avgEAR.toStringAsFixed(3)}');
      }

      // Detect if eyes are closed (low EAR)
      final eyesClosed = avgEAR < _eyeAspectRatioThreshold;

      if (eyesClosed) {
        _closedFrameCount++;
        if (kDebugMode && _closedFrameCount == 1) {
          debugPrint('😐 Eyes closing... (frame $_closedFrameCount)');
        }
      } else {
        // Eyes are open
        if (_eyesWereOpen && _closedFrameCount >= _blinkFrameThreshold) {
          // Blink detected: was open → closed → open
          _blinkDetected = true;
          if (kDebugMode) {
            debugPrint('✅ BLINK DETECTED! (closed for $_closedFrameCount frames)');
          }
        }
        _eyesWereOpen = true;
        _closedFrameCount = 0;
      }

      return _blinkDetected;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Eye blink detection error: $e');
      return false;
    }
  }

  /// Calculate eye aspect ratio based on eye landmark
  /// Uses the position of the landmark to estimate eye openness
  double _calculateEyeAspectRatio(FaceLandmark landmark) {
    // ML Kit provides landmark position as a single Point
    // For simplicity, we use a vertical distance approximation
    // A closed eye has very small vertical distance

    // Get the position - this is the center point of the eye
    final position = landmark.position;

    // For a more robust eye detection, we would need all eye contour points
    // For now, use a simplified approach: detect based on eye center Y coordinate change
    // This is a basic approximation - in production, you might want to use
    // face contour points for more accurate eye aspect ratio calculation

    // Placeholder implementation: return 1.0 (open) by default
    // In a production system, this would calculate actual eye aspect ratio
    // from multiple landmark points around the eye
    return 1.0;
  }

  /// Reset detector state
  void reset() {
    _eyesWereOpen = false;
    _closedFrameCount = 0;
    _blinkDetected = false;
  }
}
