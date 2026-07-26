import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/camera_input_image_utils.dart';
import '../services/device_performance_service.dart';

/// Registration vs auto-attendance distance bands.
enum DistanceProfile {
  /// Auto scan / staff attendance (~3 ft arm's length).
  attendance,

  /// Face enrollment — same 3 ft rule; UI uses face box, not a guide circle.
  registration,

  /// Fixed-camera kiosk — phone is mounted; student walks up.
  /// Wider distance band; messages say "step closer/back" not "hold phone".
  kiosk,
}

/// 📐 Distance Status Enum (Top-level for use across the app)
enum DistanceStatus {
  noFace,
  tooClosed, // Phone/photo held too close to lens
  tooFar,
  perfect,
}

/// 📐 Distance Check Service
/// Face size in frame ≈ distance from camera (registration + attendance).
///
/// Target: **~3 feet (1 metre)** phone-to-face — same for registration and auto attendance.
class DistanceCheckService {
  /// User-facing copy (registration + mark attendance).
  static const String recommendedDistanceShort =
      'Hold phone at arm\'s length (~3 ft) — face in the box';
  static const String recommendedDistanceDetail =
      'Hold the phone at arm\'s length (~3 ft). Keep your full face inside the on-screen box.';

  /// Shown while face is in the 3 ft band but not held steady yet.
  static const String holdThreeFeetSteady =
      'Hold phone steady at 3 ft from your face…';

  static String holdThreeFeetSteadyFor(DistanceProfile profile) =>
      switch (profile) {
        DistanceProfile.registration => '3 ft OK — keep face in box, hold still…',
        DistanceProfile.kiosk => 'Face detected — blink once',
        _ => holdThreeFeetSteady,
      };

  static String recommendedDistanceShortFor(DistanceProfile profile) =>
      switch (profile) {
        DistanceProfile.registration => 'Arm\'s length (~3 ft) — full face inside the box',
        DistanceProfile.kiosk => 'Stand in front of the camera — face in the box',
        _ => recommendedDistanceShort,
      };

  /// Frames at 3 ft before blink / capture (avoids one-frame jitter).
  static int get minPerfectFramesToProceed =>
      DevicePerformanceService.minPerfectFramesToProceed;

  static bool allowsCapture(DistanceStatus status) =>
      status == DistanceStatus.perfect;

  static ({double min, double max, double maxRatio}) _bandsFor(
    DistanceProfile profile,
  ) {
    if (profile == DistanceProfile.kiosk) {
      // Wider band: student can be anywhere from ~0.5 m to ~2 m from fixed camera.
      return (min: 0.08, max: 0.60, maxRatio: 0.65);
    }
    // Same ~3 ft band for registration and attendance.
    return (min: _perfectMin, max: _perfectMax, maxRatio: _maxRatio);
  }

  static String userMessageFor(
    DistanceStatus status, {
    DistanceProfile profile = DistanceProfile.attendance,
  }) =>
      phoneNotAtThreeFeetMessage(status, profile: profile);

  /// Primary gate message when phone is not at required distance.
  static String phoneNotAtThreeFeetMessage(
    DistanceStatus status, {
    DistanceProfile profile = DistanceProfile.attendance,
  }) {
    if (status == DistanceStatus.perfect) {
      return holdThreeFeetSteadyFor(profile);
    }
    if (profile == DistanceProfile.kiosk) {
      return switch (status) {
        DistanceStatus.noFace    => 'Show your face in the camera',
        DistanceStatus.tooClosed => 'Step back a little',
        DistanceStatus.tooFar    => 'Step closer to the camera',
        DistanceStatus.perfect   => holdThreeFeetSteadyFor(profile),
      };
    }
    return switch (status) {
      DistanceStatus.noFace =>
        'Show your full face in the box',
      DistanceStatus.tooClosed =>
        'Too close — move phone back (~3 ft)',
      DistanceStatus.tooFar =>
        'Too far — move closer (~3 ft), face in box',
      DistanceStatus.perfect => holdThreeFeetSteadyFor(profile),
    };
  }

  static String phoneAtThreeFeetReadyMessage() =>
      'Phone at 3 ft ✓ — blink once, then we capture';

  /// Reject phone/photo pressed against camera (face dominates frame).
  static const double MAX_RATIO = 0.52;

  /// Below this, face is too small (~4+ ft on typical phones).
  static const double MIN_RATIO = 0.12;

  /// ~2–3.5 ft band (varies by camera FOV).
  static const double PERFECT_MIN = 0.20;
  static const double PERFECT_MAX = 0.42;

  static double get _perfectMin =>
      Platform.isAndroid ? 0.14 : PERFECT_MIN;

  static double get _perfectMax =>
      Platform.isAndroid ? 0.48 : PERFECT_MAX;

  static double get _maxRatio =>
      Platform.isAndroid ? 0.54 : MAX_RATIO;

  static double get _minRatio =>
      Platform.isAndroid ? 0.10 : MIN_RATIO;

  /// Check if detected face is at correct distance
  /// Returns: {
  ///   'status': DistanceStatus,
  ///   'ratio': double (0-1),
  ///   'message': String,
  ///   'confidence': double (0-1)
  /// }
  static Map<String, dynamic> checkFaceDistance(
    Face face,
    double frameWidth,
    double frameHeight, {
    CameraImage? image,
    InputImageRotation? rotation,
    double? distanceRatioOverride,
    DistanceProfile profile = DistanceProfile.attendance,
  }) {
    try {
      if (kDebugMode) {
        debugPrint('📐 DISTANCE_CHECK: Face detected ($profile)');
      }

      final bands = _bandsFor(profile);

      final ratio = distanceRatioOverride ??
          (() {
            var box = face.boundingBox;
            if (image != null && rotation != null) {
              box = CameraInputImageUtils.faceBoxInAnalysisSpace(
                face: face,
                image: image,
                rotation: rotation,
              );
            }
            return CameraInputImageUtils.faceToFrameRatio(
              box,
              frameWidth,
              frameHeight,
            );
          })();

      if (kDebugMode) {
        final fb = face.boundingBox;
        debugPrint(
          '📐 Face ratio: ${ratio.toStringAsFixed(3)} '
          '(face: ${fb.width.toStringAsFixed(0)}×${fb.height.toStringAsFixed(0)}px, '
          'frame: ${frameWidth.toStringAsFixed(0)}×${frameHeight.toStringAsFixed(0)}px, '
          'android=${Platform.isAndroid})',
        );
      }

      DistanceStatus status;
      String message;
      double confidence;

      if (ratio > bands.maxRatio) {
        status = DistanceStatus.tooClosed;
        message = userMessageFor(status, profile: profile);
        confidence = (ratio - bands.maxRatio).clamp(0.0, 1.0);

        if (kDebugMode) {
          debugPrint('🔴 DISTANCE_CHECK: TOO_CLOSE (ratio: ${ratio.toStringAsFixed(3)})');
        }
      } else if (ratio < _minRatio) {
        status = DistanceStatus.tooFar;
        message = userMessageFor(status, profile: profile);
        confidence = (_minRatio - ratio).clamp(0.0, 1.0);

        if (kDebugMode) {
          debugPrint('🟡 DISTANCE_CHECK: TOO_FAR (ratio: ${ratio.toStringAsFixed(3)})');
        }
      } else if (ratio < bands.min || ratio > bands.max) {
        status = ratio < bands.min ? DistanceStatus.tooFar : DistanceStatus.tooClosed;
        message = userMessageFor(status, profile: profile);
        confidence = 0.55;

        if (kDebugMode) {
          debugPrint(
            '🟡 DISTANCE_CHECK: ADJUST (ratio: ${ratio.toStringAsFixed(3)} '
            'target ${bands.min}-${bands.max})',
          );
        }
      } else {
        status = DistanceStatus.perfect;
        message = userMessageFor(status, profile: profile);

        final perfectCenter = (bands.min + bands.max) / 2;
        final distanceFromCenter = (ratio - perfectCenter).abs();
        confidence = 1.0 -
            (distanceFromCenter / ((bands.max - bands.min) / 2));

        if (kDebugMode) {
          debugPrint(
            '🟢 DISTANCE_CHECK: PERFECT (ratio: ${ratio.toStringAsFixed(3)}, '
            'confidence: ${(confidence * 100).toStringAsFixed(1)}%)',
          );
        }
      }

      return {
        'status': status,
        'ratio': ratio,
        'message': message,
        'confidence': confidence.clamp(0.0, 1.0),
        'isSafe': status == DistanceStatus.perfect,
      };
    } catch (e) {
      debugPrint('❌ Distance check error: $e');
      return {
        'status': DistanceStatus.noFace,
        'ratio': 0.0,
        'message': userMessageFor(DistanceStatus.noFace, profile: profile),
        'confidence': 0.0,
        'isSafe': false,
      };
    }
  }

  static String userMessageForLegacy(DistanceStatus status) =>
      userMessageFor(status);

  /// Get UI feedback for distance status
  static Map<String, dynamic> getUIFeedback(DistanceStatus status, double ratio) {
    return {
      'circleColor': _getCircleColor(status),
      'message': userMessageFor(status),
      'shouldBlock': status != DistanceStatus.perfect,
      'icon': _getIcon(status),
    };
  }

  static String _getCircleColor(DistanceStatus status) {
    switch (status) {
      case DistanceStatus.perfect:
        return 'green';
      case DistanceStatus.tooClosed:
        return 'red';
      case DistanceStatus.tooFar:
        return 'yellow';
      case DistanceStatus.noFace:
        return 'gray';
    }
  }

  static String _getIcon(DistanceStatus status) {
    switch (status) {
      case DistanceStatus.perfect:
        return '✓';
      case DistanceStatus.tooClosed:
        return '!';
      case DistanceStatus.tooFar:
        return '→';
      case DistanceStatus.noFace:
        return '?';
    }
  }
}
