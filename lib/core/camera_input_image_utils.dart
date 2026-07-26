import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show DeviceOrientation;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    show Face, InputImage, InputImageFormat, InputImageMetadata, InputImageRotation, InputImageRotationValue;

/// Shared camera stream → ML Kit [InputImage] (iOS + Android).
///
/// **Android (CameraX):** YUV_420_888 stream → NV21 bytes + rotation metadata.
/// **iOS:** BGRA8888 single plane + sensor rotation.
class CameraInputImageUtils {
  CameraInputImageUtils._();

  static const Map<DeviceOrientation, int> _orientationDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// ML Kit rotation for live camera stream.
  static InputImageRotation rotationForController(CameraController controller) {
    final camera = controller.description;
    final sensor = camera.sensorOrientation;

    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensor) ??
          InputImageRotation.rotation0deg;
    }

    var compensation =
        _orientationDegrees[controller.value.deviceOrientation] ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      compensation = (sensor + compensation) % 360;
    } else {
      compensation = (sensor - compensation + 360) % 360;
    }
    return InputImageRotationValue.fromRawValue(compensation) ??
        InputImageRotation.rotation0deg;
  }

  /// Upright analysis width/height for face bounds (matches ML Kit output space).
  static ({double width, double height}) displaySizeForImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      return (width: image.height.toDouble(), height: image.width.toDouble());
    }
    return (width: image.width.toDouble(), height: image.height.toDouble());
  }

  static bool _boxFits(Rect box, double w, double h) {
    return box.left >= -6 &&
        box.top >= -6 &&
        box.right <= w + 6 &&
        box.bottom <= h + 6;
  }

  /// Map ML Kit box → upright portrait analysis space for overlay + distance.
  static Rect resolveUprightFaceBox({
    required Rect raw,
    required int imageWidth,
    required int imageHeight,
    required InputImageRotation rotation,
    required double uprightWidth,
    required double uprightHeight,
  }) {
    if (_boxFits(raw, uprightWidth, uprightHeight)) {
      return raw;
    }
    if (_boxFits(raw, imageWidth.toDouble(), imageHeight.toDouble())) {
      return _bufferBoxToUpright(
        raw,
        imageWidth,
        imageHeight,
        rotation,
      );
    }
    if (Platform.isAndroid) {
      return _bufferBoxToUpright(
        raw,
        imageWidth,
        imageHeight,
        rotation,
      );
    }
    return raw;
  }

  static Rect _bufferBoxToUpright(
    Rect box,
    int imageWidth,
    int imageHeight,
    InputImageRotation rotation,
  ) {
    final w = imageWidth.toDouble();
    final h = imageHeight.toDouble();
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Rect.fromLTRB(
          box.top,
          w - box.right,
          box.bottom,
          w - box.left,
        );
      case InputImageRotation.rotation270deg:
        return Rect.fromLTRB(
          h - box.bottom,
          box.left,
          h - box.top,
          box.right,
        );
      case InputImageRotation.rotation180deg:
        return Rect.fromLTRB(
          w - box.right,
          h - box.bottom,
          w - box.left,
          h - box.top,
        );
      default:
        return box;
    }
  }

  static Rect analysisBoxToBufferRect({
    required Rect analysisBox,
    required int imageWidth,
    required int imageHeight,
    required InputImageRotation rotation,
    required Rect rawFallback,
  }) {
    if (_boxFits(rawFallback, imageWidth.toDouble(), imageHeight.toDouble())) {
      return rawFallback;
    }
    final w = imageWidth.toDouble();
    final h = imageHeight.toDouble();
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Rect.fromLTRB(
          w - analysisBox.bottom,
          analysisBox.left,
          w - analysisBox.top,
          analysisBox.right,
        );
      case InputImageRotation.rotation270deg:
        return Rect.fromLTRB(
          analysisBox.top,
          h - analysisBox.right,
          analysisBox.bottom,
          h - analysisBox.left,
        );
      case InputImageRotation.rotation180deg:
        return Rect.fromLTRB(
          w - analysisBox.right,
          h - analysisBox.bottom,
          w - analysisBox.left,
          h - analysisBox.top,
        );
      default:
        return analysisBox;
    }
  }

  /// Face size vs frame in upright ML Kit analysis space (both OS).
  static double distanceRatioForStream({
    required Face face,
    required CameraImage image,
    required InputImageRotation rotation,
    required Rect analysisBox,
    required double analysisWidth,
    required double analysisHeight,
  }) {
    return faceToFrameRatio(analysisBox, analysisWidth, analysisHeight);
  }

  /// @deprecated Use [resolveUprightFaceBox] via [StreamFaceFrame].
  static Rect faceBoxInAnalysisSpace({
    required Face face,
    required CameraImage image,
    required InputImageRotation rotation,
  }) {
    final display = displaySizeForImage(image, rotation);
    return resolveUprightFaceBox(
      raw: face.boundingBox,
      imageWidth: image.width,
      imageHeight: image.height,
      rotation: rotation,
      uprightWidth: display.width,
      uprightHeight: display.height,
    );
  }

  static double faceToFrameRatio(Rect box, double frameWidth, double frameHeight) {
    if (frameWidth <= 0 || frameHeight <= 0) return 0.0;
    final faceSpan = math.max(box.width, box.height);
    final frameSpan = math.max(frameWidth, frameHeight);
    return faceSpan / frameSpan;
  }

  static InputImage? cameraImageToInputImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    try {
      if (Platform.isAndroid) {
        final nv21 = _androidCameraImageToNv21(image);
        if (nv21 == null) return null;
        return InputImage.fromBytes(
          bytes: nv21,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.nv21,
            bytesPerRow: image.width,
          ),
        );
      }

      if (image.planes.isEmpty) return null;
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// CameraX on Android always streams [ImageFormatGroup.yuv420] (YUV_420_888).
  static Uint8List? _androidCameraImageToNv21(CameraImage image) {
    if (image.planes.isEmpty) return null;
    if (image.planes.length == 1) {
      return Uint8List.fromList(image.planes[0].bytes);
    }
    if (image.planes.length == 2) {
      return _yuv420TwoPlaneToNv21(image);
    }
    return _yuv420ThreePlaneToNv21(image);
  }

  static Uint8List _yuv420TwoPlaneToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uvPlane = image.planes[1];
    final nv21 = Uint8List((width * height * 1.5).round());

    final yPixelStride = yPlane.bytesPerPixel ?? 1;
    var outY = 0;
    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      for (var col = 0; col < width; col++) {
        nv21[outY++] = yPlane.bytes[rowStart + col * yPixelStride];
      }
    }

    final uvStart = width * height;
    final uvNeeded = nv21.length - uvStart;
    final uvCopy = math.min(uvNeeded, uvPlane.bytes.length);
    nv21.setRange(uvStart, uvStart + uvCopy, uvPlane.bytes);
    return nv21;
  }

  static Uint8List _yuv420ThreePlaneToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBuffer = yPlane.bytes;
    final uBuffer = uPlane.bytes;
    final vBuffer = vPlane.bytes;

    final nv21 = Uint8List((width * height * 1.5).round());
    var idY = 0;
    var idUV = width * height;

    final uvWidth = width ~/ 2;
    final uvHeight = height ~/ 2;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    final yRowStride = yPlane.bytesPerRow;
    final yPixelStride = yPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < height; y++) {
      final uvOffset = (y ~/ 2) * uvRowStride;
      final yOffset = y * yRowStride;
      for (var x = 0; x < width; x++) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];
        if (y < uvHeight && x < uvWidth) {
          final bufferIndex = uvOffset + (x * uvPixelStride);
          if (bufferIndex < vBuffer.length && bufferIndex < uBuffer.length) {
            nv21[idUV++] = vBuffer[bufferIndex];
            nv21[idUV++] = uBuffer[bufferIndex];
          }
        }
      }
    }
    return nv21;
  }
}
