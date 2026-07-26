import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ML Kit–based blink detection over a live camera stream.
///
/// A **blink** is eyes clearly closed for a few frames, then clearly open again.
/// Single-frame "both eyes below X" is unreliable (fast blinks, noisy scores).
class StreamingBlinkDetector {
  StreamingBlinkDetector({
    this.closedFramesRequired = 2,      // ✅ INCREASED from 1: Better debounce of noise
    this.openFramesRequired = 2,        // Keep at 2: Reasonable
    this.minOpenClosedSwing = 0.20,     // ✅ DECREASED from 0.28: Works in poor lighting
  });

  /// Consecutive frames needed to count as "closed" (debounces noise).
  final int closedFramesRequired;

  /// Consecutive frames needed to count as "open again" after closed phase.
  final int openFramesRequired;

  /// Required eye-probability movement from closed → open. This rejects still
  /// photos where ML Kit jitters slightly and pretends a blink happened.
  final double minOpenClosedSwing;

  bool _inClosedPhase = false;
  bool _sawClearOpenBeforeClose = false;
  int _closedRun = 0;
  int _openRun = 0;
  double? _closedPhaseMinAvg;
  int _postBlinkGraceFrames = 0;

  /// True while eyes are closing, closed, or reopening.
  bool get inBlinkPhase => _inClosedPhase || _closedRun > 0;

  /// Brief cooldown after a completed blink (eye-region banding/HF still settling).
  bool get inPostBlinkGrace => _postBlinkGraceFrames > 0;

  /// Only skip **banding / HF** screen heuristics — grid + temporal checks stay on.
  bool get shouldSuppressBandingSpoof => inBlinkPhase || inPostBlinkGrace;

  @Deprecated('Use shouldSuppressBandingSpoof')
  bool get shouldSuppressScreenSpoof => shouldSuppressBandingSpoof;

  void reset() {
    _inClosedPhase = false;
    _sawClearOpenBeforeClose = false;
    _closedRun = 0;
    _openRun = 0;
    _closedPhaseMinAvg = null;
    _postBlinkGraceFrames = 0;
  }

  void _tickGraceFrames() {
    if (_postBlinkGraceFrames > 0) {
      _postBlinkGraceFrames--;
    }
  }

  static ({double left, double right, double avg, double min, double max})? _eyeStats(Face face) {
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    if (l == null || r == null) return null;
    final avg = (l + r) / 2;
    return (left: l, right: r, avg: avg, min: math.min(l, r), max: math.max(l, r));
  }

  /// Useful for legacy single-frame checks (prefer [processFrame] on a stream).
  static bool eyesClosedFrame(Face face) {
    final stats = _eyeStats(face);
    if (stats == null) return false;
    return stats.min < 0.25 && stats.avg < 0.35;
  }

  /// Complement of closed: clearly open again.
  static bool eyesOpenFrame(Face face) {
    final stats = _eyeStats(face);
    if (stats == null) return false;
    return stats.min > 0.55 && stats.avg > 0.62;
  }

  /// Eyes shutting: use min + average so quick / asymmetric blinks still register.
  static bool _eyesClosedNow(Face face) => eyesClosedFrame(face);

  /// Eyes open again after a blink (avoid "dead zone" between 0.40–0.45 only).
  static bool _eyesOpenNow(Face face) => eyesOpenFrame(face);

  /// Call once per processed face frame. Returns `true` when one full blink just finished.
  bool processFrame(Face face) {
    _tickGraceFrames();

    final stats = _eyeStats(face);
    if (stats == null) {
      reset();
      return false;
    }

    final closed = _eyesClosedNow(face);
    final open = _eyesOpenNow(face);

    if (!_inClosedPhase) {
      if (open) {
        _sawClearOpenBeforeClose = true;
      }

      if (closed && _sawClearOpenBeforeClose) {
        _closedRun++;
        _closedPhaseMinAvg = math.min(_closedPhaseMinAvg ?? stats.avg, stats.avg);
        if (_closedRun >= closedFramesRequired) {
          _inClosedPhase = true;
          _closedRun = 0;
          _openRun = 0;
        }
      } else {
        _closedRun = 0;
      }
      return false;
    }

    if (open) {
      _openRun++;
      if (_openRun >= openFramesRequired) {
        final closedAvg = _closedPhaseMinAvg;
        final hasRealEyeMovement =
            closedAvg != null && stats.avg - closedAvg >= minOpenClosedSwing;
        _inClosedPhase = false;
        _openRun = 0;
        _closedRun = 0;
        _closedPhaseMinAvg = null;
        _sawClearOpenBeforeClose = true;
        if (hasRealEyeMovement) {
          // Suppress screen-spoof for a few frames — blinks spike HF in the face ROI.
          _postBlinkGraceFrames = 4;
        }
        return hasRealEyeMovement;
      }
    } else {
      if (closed) {
        _openRun = 0;
        _closedPhaseMinAvg = math.min(_closedPhaseMinAvg ?? stats.avg, stats.avg);
      } else if (_openRun > 0) {
        _openRun--;
      }
    }
    return false;
  }
}
