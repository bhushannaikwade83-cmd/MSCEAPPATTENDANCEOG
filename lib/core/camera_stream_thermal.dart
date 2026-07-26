import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/device_performance_service.dart';

/// ML Kit options for live camera streams (blink + distance; minimal CPU heat).
class StreamFaceDetectorOptions {
  StreamFaceDetectorOptions._();

  static FaceDetectorOptions build() => FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: DevicePerformanceService.enableClassificationOnStream,
        enableLandmarks: DevicePerformanceService.enableLandmarksOnStream,
        enableTracking: DevicePerformanceService.enableFaceTrackingOnStream,
        minFaceSize: DevicePerformanceService.isLowRamDevice ? 0.12 : 0.08,
      );
}

/// Stop/start camera stream between ML passes — cuts sustained CPU on Android.
class CameraStreamThermalPulse {
  CameraStreamThermalPulse({
    required this.restAfterFrame,
    required this.pulseEnabled,
  });

  final Duration restAfterFrame;
  final bool pulseEnabled;

  bool _pulseInFlight = false;

  Future<void> restBetweenPasses({
    required bool Function() shouldContinue,
    required bool Function() isStreaming,
    required Future<void> Function() stopStream,
    required void Function() startStream,
  }) async {
    if (!pulseEnabled || _pulseInFlight || !shouldContinue()) return;
    _pulseInFlight = true;
    try {
      if (isStreaming()) {
        await stopStream();
      }
      if (restAfterFrame > Duration.zero) {
        await Future.delayed(restAfterFrame);
      }
      if (shouldContinue()) {
        startStream();
      }
    } finally {
      _pulseInFlight = false;
    }
  }

  void reset() {
    _pulseInFlight = false;
  }
}
