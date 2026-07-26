import 'dart:io' show Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Per-OS camera + ML Kit settings (Android CameraX vs iOS AVFoundation).
class CameraPlatformConfig {
  CameraPlatformConfig._();

  /// Stream format for [CameraController.imageFormatGroup].
  ///
  /// - **Android:** [ImageFormatGroup.yuv420] (CameraX YUV_420_888 → converted to NV21 for ML Kit)
  /// - **iOS:** [ImageFormatGroup.bgra8888] (ML Kit native format)
  static ImageFormatGroup get streamImageFormatGroup {
    if (Platform.isAndroid) {
      return ImageFormatGroup.yuv420;
    }
    return ImageFormatGroup.bgra8888;
  }

  /// Whether the live face box should be mirrored on [CameraPreview].
  ///
  /// - **iOS front:** ML Kit coords already match mirrored selfie preview.
  /// - **Android front:** preview is mirrored; ML Kit upright coords need horizontal flip.
  /// - **Back camera:** never mirror.
  static bool mirrorFaceBoxOnPreview(CameraDescription camera) {
    if (camera.lensDirection != CameraLensDirection.front) {
      return false;
    }
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return false;
    }
    return Platform.isAndroid;
  }

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// Shared [CameraController] setup for face registration + auto scan streams.
  static Future<CameraController> createStreamController({
    required CameraDescription camera,
    required ResolutionPreset resolution,
  }) async {
    final controller = CameraController(
      camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: streamImageFormatGroup,
    );
    await controller.initialize();
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    return controller;
  }
}
