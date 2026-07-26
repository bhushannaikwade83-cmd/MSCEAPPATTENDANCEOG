import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_input_image_utils.dart';

/// One consistent face frame for distance, overlay, and PAD on a camera stream.
class StreamFaceFrame {
  const StreamFaceFrame({
    required this.rotation,
    required this.analysisBox,
    required this.analysisSize,
    required this.bufferRect,
    required this.distanceRatio,
  });

  final InputImageRotation rotation;
  final Rect analysisBox;
  final Size analysisSize;
  final Rect bufferRect;
  final double distanceRatio;

  factory StreamFaceFrame.from({
    required Face face,
    required CameraImage image,
    required InputImageRotation rotation,
  }) {
    final display = CameraInputImageUtils.displaySizeForImage(image, rotation);
    final analysisSize = Size(display.width, display.height);
    final raw = face.boundingBox;

    final analysisBox = CameraInputImageUtils.resolveUprightFaceBox(
      raw: raw,
      imageWidth: image.width,
      imageHeight: image.height,
      rotation: rotation,
      uprightWidth: display.width,
      uprightHeight: display.height,
    );

    final distanceRatio = CameraInputImageUtils.distanceRatioForStream(
      face: face,
      image: image,
      rotation: rotation,
      analysisBox: analysisBox,
      analysisWidth: display.width,
      analysisHeight: display.height,
    );

    final bufferRect = CameraInputImageUtils.analysisBoxToBufferRect(
      analysisBox: analysisBox,
      imageWidth: image.width,
      imageHeight: image.height,
      rotation: rotation,
      rawFallback: raw,
    );

    return StreamFaceFrame(
      rotation: rotation,
      analysisBox: analysisBox,
      analysisSize: analysisSize,
      bufferRect: bufferRect,
      distanceRatio: distanceRatio,
    );
  }
}
