import 'package:camera/camera.dart';

/// Prefer the **back** (world-facing) camera for face registration flows.
/// Falls back to index `0` if no back camera is listed (unusual devices).
int preferredBackCameraIndex(List<CameraDescription> cameras) {
  final i = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
  if (i >= 0) return i;
  return 0;
}

/// Prefer the **front** (user-facing/selfie) camera for marking attendance.
/// Falls back to index `0` if no front camera is listed (unusual devices).
int preferredFrontCameraIndex(List<CameraDescription> cameras) {
  final i = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
  if (i >= 0) return i;
  return 0;
}

/// Flip between **front** and **back** when the user taps the switch control.
/// If only one facing exists, cycles to the next physical camera.
int toggleFacingCameraIndex(List<CameraDescription> cameras, int currentIndex) {
  if (cameras.isEmpty) return 0;
  final safe = currentIndex.clamp(0, cameras.length - 1);
  final cur = cameras[safe].lensDirection;
  final target =
      cur == CameraLensDirection.front ? CameraLensDirection.back : CameraLensDirection.front;
  final j = cameras.indexWhere((c) => c.lensDirection == target);
  if (j >= 0) return j;
  return (safe + 1) % cameras.length;
}
