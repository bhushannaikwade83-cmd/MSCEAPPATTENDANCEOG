import 'dart:math' as math;

/// Detects phone/tablet **video replay** during live camera scan.
///
/// Never blocks on temporal flicker alone — live cameras under LED/fluorescent
/// lights can flicker too. Requires corroboration (screen moiré, PAD, or smooth
/// video-like motion combined with display signals).
class VideoReplayGuardService {
  VideoReplayGuardService._();

  static const int minLumaSamples = 12;
  static const int minYawSamples = 14;

  /// Strong screen + refresh together (primary video-on-phone signal).
  static const double screenScoreMin = 0.20;
  static const double temporalWithScreenMin = 0.26;

  /// Very high refresh flicker only when screen score also present.
  static const double temporalStrongMin = 0.44;
  static const double temporalStrongScreenMin = 0.10;

  static const double maxLumaStdForScreen = 1.4;
  static const double lumaTemporalMin = 0.30;

  static const double minYawRangeForSmoothCheck = 8.0;
  static const double maxYawDeltaStd = 0.38;
  static const double maxYawDeltaStep = 2.4;
  static const double smoothMotionScreenMin = 0.14;

  static VideoReplayVerdict evaluate({
    required List<double> lumaHistory,
    required List<double> yawHistory,
    double temporalReplayScore = 0.0,
    double screenSpoofScore = 0.0,
    bool padMarkedSpoof = false,
  }) {
    if (padMarkedSpoof) {
      return const VideoReplayVerdict(
        isLikelyVideo: true,
        reason: 'Video or screen detected — use your live face',
      );
    }

    if (screenSpoofScore >= screenScoreMin &&
        temporalReplayScore >= temporalWithScreenMin) {
      return const VideoReplayVerdict(
        isLikelyVideo: true,
        reason: 'Screen video detected — not allowed',
      );
    }

    if (temporalReplayScore >= temporalStrongMin &&
        screenSpoofScore >= temporalStrongScreenMin) {
      return const VideoReplayVerdict(
        isLikelyVideo: true,
        reason: 'Video on screen detected — use your live face',
      );
    }

    if (lumaHistory.length >= minLumaSamples) {
      final lumaStd = _stdDev(lumaHistory);
      if (lumaStd < maxLumaStdForScreen &&
          temporalReplayScore >= lumaTemporalMin &&
          screenSpoofScore >= 0.16) {
        return const VideoReplayVerdict(
          isLikelyVideo: true,
          reason: 'Video replay detected — show live face only',
        );
      }
    }

    if (yawHistory.length >= minYawSamples &&
        screenSpoofScore >= smoothMotionScreenMin) {
      final range = _range(yawHistory);
      final deltaStd = _deltaStdDev(yawHistory);
      if (range >= minYawRangeForSmoothCheck &&
          deltaStd < maxYawDeltaStd &&
          _maxAbsDelta(yawHistory) < maxYawDeltaStep) {
        return const VideoReplayVerdict(
          isLikelyVideo: true,
          reason: 'Recorded video detected — use live camera',
        );
      }
    }

    return const VideoReplayVerdict(isLikelyVideo: false, reason: '');
  }

  static double _stdDev(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    var sumSq = 0.0;
    for (final v in values) {
      sumSq += (v - mean) * (v - mean);
    }
    return math.sqrt(sumSq / values.length);
  }

  static double _range(List<double> values) {
    if (values.isEmpty) return 0.0;
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    return maxV - minV;
  }

  static double _deltaStdDev(List<double> values) {
    if (values.length < 3) return 999.0;
    final deltas = <double>[];
    for (var i = 1; i < values.length; i++) {
      deltas.add((values[i] - values[i - 1]).abs());
    }
    return _stdDev(deltas);
  }

  static double _maxAbsDelta(List<double> values) {
    if (values.length < 2) return 999.0;
    var maxD = 0.0;
    for (var i = 1; i < values.length; i++) {
      final d = (values[i] - values[i - 1]).abs();
      if (d > maxD) maxD = d;
    }
    return maxD;
  }
}

class VideoReplayVerdict {
  const VideoReplayVerdict({
    required this.isLikelyVideo,
    required this.reason,
  });

  final bool isLikelyVideo;
  final String reason;
}
