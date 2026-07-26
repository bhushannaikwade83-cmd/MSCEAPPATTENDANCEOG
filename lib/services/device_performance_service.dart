import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/services.dart';

import '../core/production_face_recognition_constants.dart';
import 'anti_spoof_service.dart';

/// RAM / CPU tuning for institute phones (2–16 GB). Camera ML is throttled on
/// all Android to limit heat; 2–4 GB get the strictest limits.
class DevicePerformanceService {
  static const MethodChannel _channel = MethodChannel('msce/device_performance');

  static bool _initialized = false;

  /// ≤3 GB RAM or Android low-RAM flag.
  static bool isLowRamDevice = false;

  /// ≤4 GB RAM.
  static bool isConstrainedDevice = false;

  static int? memoryClassMb;
  static int? largeMemoryClassMb;
  static int? totalRamMb;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('getDeviceProfile');
      memoryClassMb = (raw?['memoryClassMb'] as num?)?.toInt();
      largeMemoryClassMb = (raw?['largeMemoryClassMb'] as num?)?.toInt();
      totalRamMb = (raw?['totalRamMb'] as num?)?.toInt();

      final flaggedLowRam = raw?['isLowRamDevice'] == true;
      final totalRamLooksLow = totalRamMb != null && totalRamMb! <= 3072;
      final totalRamConstrained = totalRamMb != null && totalRamMb! <= 4096;
      final heapLooksLow = memoryClassMb != null && memoryClassMb! <= 192;

      isLowRamDevice = flaggedLowRam || totalRamLooksLow || heapLooksLow;
      isConstrainedDevice = isLowRamDevice || totalRamConstrained || heapLooksLow;

      if (kDebugMode) {
        debugPrint(
          '📱 Device profile: lowRam=$isLowRamDevice, constrained=$isConstrainedDevice, '
          'memoryClassMb=$memoryClassMb, totalRamMb=$totalRamMb, '
          'streamGap=${streamFrameMinGap.inMilliseconds}ms, streamPad=$enableStreamPadOnLivePreview',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Device performance probe unavailable: $e');
      }
      isConstrainedDevice = true;
    }
  }

  static int get imageCacheItems =>
      isLowRamDevice ? 24 : (isConstrainedDevice ? 40 : 120);

  static int get imageCacheBytes => isLowRamDevice
      ? 12 * 1024 * 1024
      : (isConstrainedDevice ? 20 * 1024 * 1024 : 60 * 1024 * 1024);

  static bool get skipHeavyWarmup => isLowRamDevice || isConstrainedDevice;

  static bool get useLowCameraPreset => isLowRamDevice && !Platform.isAndroid;

  /// Android: always low — ML Kit face detection doesn't need medium/high.
  /// Low resolution = biggest single win for heat + battery.
  static ResolutionPreset get streamCameraResolution {
    if (Platform.isAndroid) return ResolutionPreset.low;
    return useLowCameraPreset ? ResolutionPreset.low : ResolutionPreset.medium;
  }

  /// MiniFAS 80×80 is fast enough for stream PAD — enable for live REAL/FAKE% box.
  static bool get enableStreamPadOnLivePreview => AntiSpoofService.supportsStreamPad;

  static bool get enableStreamPadOnRegistration => false;

  /// Min gap between ML Kit face passes (lower FPS = less heat + battery).
  /// Android bumped up significantly — face detection at ~1.5 fps is plenty.
  static Duration get streamFrameMinGap {
    if (isLowRamDevice) return const Duration(milliseconds: 1000);
    if (isConstrainedDevice) return const Duration(milliseconds: 800);
    if (Platform.isAndroid) return const Duration(milliseconds: 650);
    return const Duration(milliseconds: 280);
  }

  static int get minRecognitionIntervalMs {
    if (isLowRamDevice) return 1200;
    if (isConstrainedDevice) return 950;
    if (Platform.isAndroid) return 750;
    return ProductionFaceRecognitionConstants.minRecognitionIntervalMs;
  }

  static int get padFrameModulo {
    // MiniFAS 80×80 is fast — run every 4th frame for responsive REAL/FAKE%.
    if (Platform.isAndroid) {
      if (isLowRamDevice) return 8;
      if (isConstrainedDevice) return 6;
      return 4;
    }
    return isLowRamDevice ? 6 : 3;
  }

  static int get uiUpdateMinGapMs {
    if (Platform.isAndroid) {
      if (isLowRamDevice) return 320;
      if (isConstrainedDevice) return 260;
      return 200;
    }
    if (isLowRamDevice) return 240;
    return 120;
  }

  static int get minCleanLiveFramesBeforeCapture {
    if (isLowRamDevice) return 2;
    if (isConstrainedDevice) return 2;
    return 3;
  }

  static int get minPerfectFramesToProceed {
    if (isLowRamDevice) return 2;
    if (isConstrainedDevice) return 2;
    return Platform.isAndroid ? 2 : 5;
  }

  static Duration get backgroundStatsPollInterval {
    if (isLowRamDevice) return const Duration(seconds: 60);
    if (isConstrainedDevice) return const Duration(seconds: 45);
    return const Duration(seconds: 20);
  }

  static bool get enableLandmarksOnStream => !isLowRamDevice && !isConstrainedDevice;

  static bool get enableFaceTrackingOnStream => !isLowRamDevice;

  /// Classification adds extra CPU per frame — skip on constrained Android devices.
  static bool get enableClassificationOnStream =>
      !Platform.isAndroid || (!isLowRamDevice && !isConstrainedDevice);

  /// Slower ML Kit passes on Android miss fast blinks unless thresholds relax.
  static bool get relaxedStreamBlinkDetection =>
      Platform.isAndroid || isConstrainedDevice;

  static Duration get deferredWarmCacheDelay {
    if (isLowRamDevice) return const Duration(seconds: 8);
    if (isConstrainedDevice) return const Duration(seconds: 5);
    return Duration.zero;
  }

  static Duration get deferredModelLoadDelay {
    if (isLowRamDevice) return const Duration(seconds: 2);
    if (isConstrainedDevice) return const Duration(seconds: 1);
    return const Duration(milliseconds: 400);
  }
}
