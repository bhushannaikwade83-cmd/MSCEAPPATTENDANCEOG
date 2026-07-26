import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'camera_input_image_utils.dart';
import 'stream_face_frame.dart';

/// Builds ML Kit inputs from a live [CameraImage] (Android + iOS).
class CameraStreamPipeline {
  CameraStreamPipeline._();

  static InputImageRotation rotationFor(CameraController controller) =>
      CameraInputImageUtils.rotationForController(controller);

  static InputImage? inputImageFrom(CameraImage image, InputImageRotation rotation) =>
      CameraInputImageUtils.cameraImageToInputImage(image, rotation);

  /// Rotation + [InputImage] for face detection. Returns null if conversion failed.
  static ({InputImageRotation rotation, InputImage inputImage})? mlKitInput(
    CameraController controller,
    CameraImage image,
  ) {
    final rotation = rotationFor(controller);
    final input = inputImageFrom(image, rotation);
    if (input == null) return null;
    return (rotation: rotation, inputImage: input);
  }

  static StreamFaceFrame faceFrame({
    required Face face,
    required CameraImage image,
    required InputImageRotation rotation,
  }) =>
      StreamFaceFrame.from(face: face, image: image, rotation: rotation);
}
