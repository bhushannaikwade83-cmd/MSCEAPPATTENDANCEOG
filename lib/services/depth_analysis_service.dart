import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Heuristic 3D vs 2D / screen replay proxy using ML Kit head pose (no IR depth).
class DepthAnalysisService {
  DepthAnalysisService._();

  static Map<String, dynamic> analyzeDepth(
    Face face, {
    double? frameFaceRatio,
  }) {
    try {
      final headEulerAngleX = face.headEulerAngleX ?? 0.0;
      final headEulerAngleY = face.headEulerAngleY ?? 0.0;
      final headEulerAngleZ = face.headEulerAngleZ ?? 0.0;

      final angleVariation =
          ((headEulerAngleX.abs() + headEulerAngleY.abs() + headEulerAngleZ.abs()) /
                  90.0)
              .clamp(0.0, 1.0);

      final trackingId = face.trackingId ?? -1;
      final hasTracking = trackingId >= 0;

      final maxEuler = [
        headEulerAngleX.abs(),
        headEulerAngleY.abs(),
        headEulerAngleZ.abs(),
      ].reduce((a, b) => a > b ? a : b);

      // Video/photo on a screen: very stable pose, often no ML Kit tracking id.
      final staticFlatPose = maxEuler < 10.0 && !hasTracking && angleVariation < 0.14;

      final faceBounds = face.boundingBox;
      final boxRatio = frameFaceRatio ??
          (faceBounds.width > 0 ? (faceBounds.height / faceBounds.width).clamp(0.5, 2.0) : 1.0);

      final depthScore = (
          (angleVariation.clamp(0.0, 0.5) * 2 * 0.45) +
          (hasTracking ? 0.35 : 0.0) +
          (maxEuler >= 12 ? 0.2 : 0.0)
      ).clamp(0.0, 1.0);

      final isFake = staticFlatPose || depthScore < 0.32;

      return {
        'isFake': isFake,
        'confidence': depthScore,
        'reason': _getDepthReason(
          angleVariation: angleVariation,
          staticFlatPose: staticFlatPose,
          hasTracking: hasTracking,
        ),
      };
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error in depth analysis: $e');
      return {
        'isFake': false,
        'confidence': 0.0,
        'reason': 'Could not analyze depth',
      };
    }
  }

  static String _getDepthReason({
    required double angleVariation,
    required bool staticFlatPose,
    required bool hasTracking,
  }) {
    if (staticFlatPose) {
      return 'Live face required (screen/video not allowed)';
    }
    if (angleVariation < 0.08 && !hasTracking) {
      return 'Move your head slightly — flat image detected';
    }
    return 'Face verified - 3D depth detected ✓';
  }
}
