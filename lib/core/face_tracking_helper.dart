import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ML Kit face tracking — lock to one person in frame (same as auto attendance).
class FaceTrackingHelper {
  int? _lockedTrackingId;

  void reset() => _lockedTrackingId = null;

  /// Prefer locked [trackingId]; otherwise largest face and lock its id.
  Face? selectPrimaryFace(List<Face> faces) {
    if (faces.isEmpty) return null;

    if (_lockedTrackingId != null) {
      for (final face in faces) {
        if (face.trackingId == _lockedTrackingId) return face;
      }
    }

    Face? largest;
    double maxArea = 0;
    for (final face in faces) {
      final area = face.boundingBox.width * face.boundingBox.height;
      if (area > maxArea) {
        maxArea = area;
        largest = face;
      }
    }

    final pick = largest ?? faces.first;
    final id = pick.trackingId;
    if (id != null) _lockedTrackingId = id;
    return pick;
  }
}
