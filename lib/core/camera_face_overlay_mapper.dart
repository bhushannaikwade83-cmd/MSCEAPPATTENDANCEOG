import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'camera_platform_config.dart';

/// Maps ML Kit face bounds to on-screen [CameraPreview] (AspectRatio letterbox + mirror).
class CameraFaceOverlayMapper {
  CameraFaceOverlayMapper._();

  /// Portrait UI: width÷height of the [CameraPreview] child (matches `camera` package).
  static double portraitPreviewWidthOverHeight(double cameraAspectRatio) {
    if (cameraAspectRatio <= 0) return 3 / 4;
    return 1.0 / cameraAspectRatio;
  }

  /// Where [CameraPreview] draws inside a full-screen stack (contain / letterbox).
  static Rect previewLetterboxRect({
    required Size widgetSize,
    required double previewWidthOverHeight,
  }) {
    if (widgetSize.width <= 0 ||
        widgetSize.height <= 0 ||
        previewWidthOverHeight <= 0) {
      return Rect.zero;
    }

    final widgetAspect = widgetSize.width / widgetSize.height;
    final previewAspect = previewWidthOverHeight;

    double w;
    double h;
    if (widgetAspect > previewAspect) {
      h = widgetSize.height;
      w = h * previewAspect;
    } else {
      w = widgetSize.width;
      h = w / previewAspect;
    }

    return Rect.fromLTWH(
      (widgetSize.width - w) / 2,
      (widgetSize.height - h) / 2,
      w,
      h,
    );
  }

  /// Preview aspect for a live [CameraController] (portrait app).
  static double previewWidthOverHeightFromController(CameraController controller) {
    final ar = controller.value.aspectRatio;
    if (ar > 0) return portraitPreviewWidthOverHeight(ar);

    final ps = controller.value.previewSize;
    if (ps != null && ps.height > 0) {
      return ps.height / ps.width;
    }
    return 3 / 4;
  }

  /// Whether to flip face-box X when drawing on [CameraPreview].
  static bool shouldMirrorFaceBoxOnPreview(CameraDescription description) =>
      CameraPlatformConfig.mirrorFaceBoxOnPreview(description);

  /// Android [CameraPreview] applies [RotatedBox]; stream coords are already upright.
  static bool previewHasExtraQuarterTurnOnAndroid(CameraController controller) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return !controller.value.isRecordingVideo;
  }

  /// ML Kit boxes sit on cheeks/eyes — pad out to hairline, ears, and chin.
  static Rect expandFaceRectForDisplay(
    Rect box,
    Size analysisSize, {
    double sidePaddingFraction = 0.28,
    double topPaddingFraction = 0.55,
    double bottomPaddingFraction = 0.40,
  }) {
    if (analysisSize.width <= 0 || analysisSize.height <= 0) return box;
    if (box.width <= 0 || box.height <= 0) return box;

    var left = box.left - box.width * sidePaddingFraction;
    var right = box.right + box.width * sidePaddingFraction;
    var top = box.top - box.height * topPaddingFraction;
    var bottom = box.bottom + box.height * bottomPaddingFraction;

    left = left.clamp(0.0, analysisSize.width);
    top = top.clamp(0.0, analysisSize.height);
    right = right.clamp(left + 8, analysisSize.width);
    bottom = bottom.clamp(top + 8, analysisSize.height);

    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// [analysisRect] / [analysisSize] = ML Kit space (rotated upright, same as distance check).
  static Rect mapToWidget({
    required Rect analysisRect,
    required Size analysisSize,
    required Size widgetSize,
    required double previewWidthOverHeight,
    bool mirrorHorizontally = false,
    double sidePaddingFraction = 0.28,
    double topPaddingFraction = 0.55,
    double bottomPaddingFraction = 0.40,
  }) {
    if (analysisSize.width <= 0 ||
        analysisSize.height <= 0 ||
        widgetSize.width <= 0 ||
        widgetSize.height <= 0) {
      return analysisRect;
    }

    final faceRect = expandFaceRectForDisplay(
      analysisRect,
      analysisSize,
      sidePaddingFraction: sidePaddingFraction,
      topPaddingFraction: topPaddingFraction,
      bottomPaddingFraction: bottomPaddingFraction,
    );

    final preview = previewLetterboxRect(
      widgetSize: widgetSize,
      previewWidthOverHeight: previewWidthOverHeight,
    );
    if (preview.width <= 0 || preview.height <= 0) return faceRect;

    final scale = math.min(
      preview.width / analysisSize.width,
      preview.height / analysisSize.height,
    );
    final scaledW = analysisSize.width * scale;
    final scaledH = analysisSize.height * scale;
    final dx = preview.left + (preview.width - scaledW) / 2;
    final dy = preview.top + (preview.height - scaledH) / 2;

    var left = faceRect.left * scale + dx;
    var top = faceRect.top * scale + dy;
    var right = faceRect.right * scale + dx;
    var bottom = faceRect.bottom * scale + dy;

    if (mirrorHorizontally) {
      final relLeft = left - preview.left;
      final relRight = right - preview.left;
      left = preview.left + preview.width - relRight;
      right = preview.left + preview.width - relLeft;
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }
}
