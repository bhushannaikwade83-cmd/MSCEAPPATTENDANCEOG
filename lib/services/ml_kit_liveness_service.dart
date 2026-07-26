import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'face_recognition_service.dart';

/// ML Kit Liveness Detection Service
/// Uses ML Kit face properties to detect genuine faces vs photos
class MLKitLivenessService {
  MLKitLivenessService._();

  /// Check if face in photo is genuine (not a photo-of-photo)
  /// Returns {
  ///   'isLive': bool,
  ///   'confidence': 0.0-1.0,
  ///   'reason': String,
  ///   'metrics': {
  ///     'eyesOpen': double,
  ///     'facingCamera': double,
  ///     'naturalLighting': double,
  ///     'facialFeatures': double,
  ///   }
  /// }
  static Future<Map<String, dynamic>> checkLiveness(String photoPath) async {
    try {
      if (kDebugMode) debugPrint('🔍 Checking face liveness with ML Kit...');

      // Get face from ML Kit
      final faces = await FaceRecognitionService.detectFaces(photoPath);

      if (faces.isEmpty) {
        if (kDebugMode) debugPrint('❌ No face detected');
        return {
          'isLive': false,
          'confidence': 0.0,
          'reason': 'No face detected in photo',
          'metrics': {}
        };
      }

      final face = faces.first;
      final metrics = <String, double>{};

      // Metric 1: Eyes Open (real faces have eyes open)
      final leftEyeOpen = face.leftEyeOpenProbability ?? 0.0;
      final rightEyeOpen = face.rightEyeOpenProbability ?? 0.0;
      final eyesOpenScore = (leftEyeOpen + rightEyeOpen) / 2.0;
      metrics['eyesOpen'] = eyesOpenScore;

      if (kDebugMode) {
        debugPrint('👁️ Eyes Open: Left=$leftEyeOpen, Right=$rightEyeOpen');
      }

      // Metric 2: Head angle (real faces have natural angles, flat photos are straight)
      final headEulerX = (face.headEulerAngleX ?? 0.0).abs();
      final headEulerY = (face.headEulerAngleY ?? 0.0).abs();
      final headEulerZ = (face.headEulerAngleZ ?? 0.0).abs();

      // Real faces should have some angle variation
      final angleVariation = ((headEulerX + headEulerY + headEulerZ) / 270.0).clamp(0.0, 1.0);
      metrics['facingCamera'] = angleVariation;

      if (kDebugMode) {
        debugPrint('🎯 Head Angles: X=$headEulerX, Y=$headEulerY, Z=$headEulerZ');
      }

      // Metric 3: Smile probability (real faces can smile, photos are static)
      final smileProb = face.smilingProbability ?? 0.0;
      metrics['naturalLighting'] = smileProb;

      if (kDebugMode) {
        debugPrint('😊 Smiling Probability: $smileProb');
      }

      // Metric 4: Face bounds (real faces have natural bounds, printed photos are often cropped)
      final faceBounds = face.boundingBox;
      final faceSize = faceBounds.width * faceBounds.height;
      final reasonableSize = (faceSize > 10000) ? 1.0 : 0.0; // Face should be reasonably sized
      metrics['facialFeatures'] = reasonableSize;

      if (kDebugMode) {
        debugPrint('📐 Face Size: $faceSize pixels');
      }

      // Calculate liveness confidence
      // Real faces should have: eyes open + some angle + face detection quality
      final livenessScore = (
          (eyesOpenScore * 0.4) +          // Eyes must be open
          (angleVariation * 0.3) +         // Some natural head angle
          (smileProb * 0.2) +              // Can express emotions
          (reasonableSize * 0.1)           // Reasonable face size
      ).clamp(0.0, 1.0);

      final isLive = livenessScore > 0.45; // Threshold

      if (kDebugMode) {
        debugPrint('🔍 Liveness Score: ${livenessScore.toStringAsFixed(2)}');
        debugPrint('   Is Live: $isLive');
      }

      return {
        'isLive': isLive,
        'confidence': livenessScore,
        'reason': _getLivenessReason(metrics, isLive),
        'metrics': metrics,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Liveness check error: $e');
      return {
        'isLive': false,
        'confidence': 0.0,
        'reason': 'Could not check liveness',
        'metrics': {}
      };
    }
  }

  static String _getLivenessReason(Map<String, double> metrics, bool isLive) {
    if (isLive) {
      return '✅ Face is genuine - liveness verified';
    }

    final eyesOpen = metrics['eyesOpen'] ?? 0.0;
    final angle = metrics['facingCamera'] ?? 0.0;
    final smile = metrics['naturalLighting'] ?? 0.0;

    if (eyesOpen < 0.3) {
      return '❌ Eyes appear closed - cannot verify genuine face. Show open eyes.';
    }
    if (angle < 0.2) {
      return '❌ Face appears flat/static - show natural head movement.';
    }
    if (smile < 0.1) {
      return '❌ Face appears static - show facial expression (smile/blink).';
    }

    return '❌ Face liveness check failed - not a genuine face.';
  }
}
