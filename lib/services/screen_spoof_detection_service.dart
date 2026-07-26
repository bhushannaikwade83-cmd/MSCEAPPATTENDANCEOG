import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// Live-stream heuristic for phone/laptop/tablet display replay.
class ScreenSpoofDetectionService {
  /// Full-frame banding threshold (normalized).
  static const double lineEnergyThreshold = 0.28;

  /// Used only with [lineEnergyThreshold] / sustained replay logic in tracker.
  static const double suspiciousScoreThreshold = 0.28;

  static const double _minContrast = 12.0;

  static ScreenSpoofResult analyzeCameraImage(
    CameraImage image, {
    Rect? faceRect,
    bool useFaceRoiBanding = false,
  }) {
    try {
      if (image.width <= 0 || image.height <= 0 || image.planes.isEmpty) {
        return const ScreenSpoofResult(score: 0.0, isLikelyScreenReplay: false);
      }

      final fullBand = _analyzeRegion(image, 0, 0, image.width, image.height);

      double hfScore = 0.0;
      double gridScore = 0.0;
      double roiBand = 0.0;

      if (faceRect != null && faceRect.width >= 32 && faceRect.height >= 32) {
        final roi = _clampRect(faceRect, image.width, image.height, padding: 0.08);
        roiBand = _analyzeRegion(
          image,
          roi.left.toInt(),
          roi.top.toInt(),
          roi.width.toInt(),
          roi.height.toInt(),
        );
        hfScore = _highFrequencyEnergy(image, roi);
        gridScore = _rgbGridScore(image, roi);
      }

      // iOS BGRA streams often saturate banding to 1.0 on live faces (buffer artifact).
      final bandFull = _sanitizeBandingScore(fullBand);
      final bandRoi = _sanitizeBandingScore(roiBand);

      // Face-ROI "banding" is mostly skin/beard texture on live cameras, not LCD rows.
      final roiBandForScore = useFaceRoiBanding ? bandRoi : 0.0;

      final score = _combineScores(
        bandFull: bandFull,
        bandRoi: roiBandForScore,
        hfScore: hfScore,
        gridScore: gridScore,
      );

      final isLikely = score >= lineEnergyThreshold;

      if (kDebugMode && score >= 0.06) {
        debugPrint(
          '📺 ScreenSpoof score=${score.toStringAsFixed(3)} '
          '(bandFull=$fullBand→$bandFull roiBand=$roiBand→$roiBandForScore '
          'hf=${hfScore.toStringAsFixed(3)} grid=${gridScore.toStringAsFixed(3)} likely=$isLikely)',
        );
      }

      final bandSignal = math.max(bandFull, roiBandForScore);

      return ScreenSpoofResult(
        score: score,
        isLikelyScreenReplay: isLikely,
        bandingScore: bandSignal,
        faceRoiBandingScore: bandRoi,
        highFrequencyScore: hfScore,
        gridScore: gridScore,
        moireScore: 0.0,
      );
    } catch (_) {
      return const ScreenSpoofResult(score: 0.0, isLikelyScreenReplay: false);
    }
  }

  /// LCD / moiré on a **saved JPEG** (reliable on iOS; stream YUV often scores 0).
  static ScreenSpoofResult analyzeStillImage(img.Image image, {Rect? faceRect}) {
    try {
      if (image.width < 32 || image.height < 32) {
        return const ScreenSpoofResult(score: 0.0, isLikelyScreenReplay: false);
      }

      Rect roi = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      if (faceRect != null && faceRect.width >= 24 && faceRect.height >= 24) {
        roi = _clampRect(faceRect, image.width, image.height, padding: 0.12);
      } else {
        final cx = image.width / 2.0;
        final cy = image.height / 2.0;
        final w = image.width * 0.55;
        final h = image.height * 0.65;
        roi = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
      }

      final bandFull = _bandingOnImage(image, 0, 0, image.width, image.height);
      final bandRoi = _bandingOnImage(
        image,
        roi.left.toInt(),
        roi.top.toInt(),
        roi.width.toInt(),
        roi.height.toInt(),
      );
      final moire = _moireOnImage(
        image,
        roi.left.toInt(),
        roi.top.toInt(),
        roi.width.toInt(),
        roi.height.toInt(),
      );
      final grid = _rgbGridOnImage(
        image,
        roi.left.toInt(),
        roi.top.toInt(),
        roi.width.toInt(),
        roi.height.toInt(),
      );
      final score = math.max(
        math.max(bandFull, bandRoi) * 0.55 + moire * 0.95,
        grid * 0.85,
      ).clamp(0.0, 1.0);

      const stillThreshold = 0.16;
      final isLikely = score >= stillThreshold ||
          moire >= 0.38 ||
          (grid >= 0.12 && bandRoi >= 0.14);

      if (kDebugMode && score >= 0.08) {
        debugPrint(
          '📺 Still LCD: score=${score.toStringAsFixed(3)} moire=$moire '
          'grid=$grid band=$bandRoi likely=$isLikely',
        );
      }

      return ScreenSpoofResult(
        score: score,
        isLikelyScreenReplay: isLikely,
        bandingScore: math.max(bandFull, bandRoi),
        faceRoiBandingScore: bandRoi,
        moireScore: moire,
        gridScore: grid,
      );
    } catch (_) {
      return const ScreenSpoofResult(score: 0.0, isLikelyScreenReplay: false);
    }
  }

  /// Mean luma in face ROI (for temporal PWM / refresh detection).
  static double meanFaceLuma(CameraImage image, Rect faceRect) {
    final roi = _clampRect(faceRect, image.width, image.height, padding: 0.05);
    final left = roi.left.toInt();
    final top = roi.top.toInt();
    final right = roi.right.toInt();
    final bottom = roi.bottom.toInt();
    if (right - left < 12 || bottom - top < 12) return 0.0;

    const step = 4;
    double sum = 0.0;
    int count = 0;
    for (int y = top; y < bottom; y += step) {
      for (int x = left; x < right; x += step) {
        sum += _lumaAt(image, x, y);
        count++;
      }
    }
    return count > 0 ? sum / count : 0.0;
  }

  /// Elevated when face region flickers like an LCD (PWM / video refresh).
  static double temporalReplayScore(List<double> lumaHistory) {
    if (lumaHistory.length < 8) return 0.0;

    final deltas = <double>[];
    for (var i = 1; i < lumaHistory.length; i++) {
      deltas.add((lumaHistory[i] - lumaHistory[i - 1]).abs());
    }
    final meanDelta = deltas.reduce((a, b) => a + b) / deltas.length;

    final mean = lumaHistory.reduce((a, b) => a + b) / lumaHistory.length;
    var crossings = 0;
    for (var i = 1; i < lumaHistory.length; i++) {
      if ((lumaHistory[i] - mean) * (lumaHistory[i - 1] - mean) < 0) {
        crossings++;
      }
    }
    final oscRate = crossings / (lumaHistory.length - 1);

    final deltaScore = (meanDelta / 6.5).clamp(0.0, 1.0);
    final oscScore = ((oscRate - 0.35) / 0.35).clamp(0.0, 1.0);
    return (deltaScore * 0.55 + oscScore * 0.45).clamp(0.0, 1.0);
  }

  static Rect _clampRect(Rect r, int imageW, int imageH, {double padding = 0.1}) {
    final padW = r.width * padding;
    final padH = r.height * padding;
    final left = (r.left - padW).clamp(0.0, imageW.toDouble());
    final top = (r.top - padH).clamp(0.0, imageH.toDouble());
    final right = (r.right + padW).clamp(0.0, imageW.toDouble());
    final bottom = (r.bottom + padH).clamp(0.0, imageH.toDouble());
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static double _analyzeRegion(
    CameraImage image,
    int x0,
    int y0,
    int regionW,
    int regionH,
  ) {
    if (regionW < 8 || regionH < 8) return 0.0;

    final x1 = math.min(image.width, x0 + regionW);
    final y1 = math.min(image.height, y0 + regionH);
    final width = x1 - x0;
    final height = y1 - y0;

    final rowCount = math.max(8, math.min(32, height ~/ 8));
    final colCount = math.max(8, math.min(32, width ~/ 8));
    final rowStep = math.max(1, height ~/ rowCount);
    final colStep = math.max(1, width ~/ colCount);

    final rowMeans = <double>[];
    final colMeans = List<double>.filled(colCount, 0.0);
    final colHits = List<int>.filled(colCount, 0);
    double sum = 0.0;
    double sumSq = 0.0;
    int sampleCount = 0;

    for (int y = y0; y < y1; y += rowStep) {
      double rowSum = 0.0;
      int rowHits = 0;
      int colIdx = 0;
      for (int x = x0; x < x1; x += colStep) {
        final lum = _lumaAt(image, x, y).toDouble();
        rowSum += lum;
        rowHits++;
        if (colIdx < colCount) {
          colMeans[colIdx] += lum;
          colHits[colIdx] += 1;
        }
        sum += lum;
        sumSq += lum * lum;
        sampleCount++;
        colIdx++;
      }
      if (rowHits > 0) {
        rowMeans.add(rowSum / rowHits);
      }
    }

    if (sampleCount < 12 || rowMeans.length < 3) return 0.0;

    for (int i = 0; i < colMeans.length; i++) {
      if (colHits[i] > 0) {
        colMeans[i] /= colHits[i];
      }
    }

    final mean = sum / sampleCount;
    final variance = math.max(0.0, (sumSq / sampleCount) - (mean * mean));
    final stdDev = math.sqrt(variance);
    if (stdDev < _minContrast) return 0.0;

    final rowEnergy = _secondDerivativeEnergy(rowMeans);
    final colEnergy = _secondDerivativeEnergy(colMeans);
    final strongest = math.max(rowEnergy, colEnergy);
    return (strongest / stdDev).clamp(0.0, 1.0);
  }

  /// Sharp local transitions (LCD pixel grid / compression on displays).
  static double _highFrequencyEnergy(CameraImage image, Rect roi) {
    final left = roi.left.toInt();
    final top = roi.top.toInt();
    final right = roi.right.toInt();
    final bottom = roi.bottom.toInt();
    if (right - left < 16 || bottom - top < 16) return 0.0;

    const step = 2;
    double gradSum = 0.0;
    int count = 0;

    for (int y = top; y < bottom - step; y += step) {
      for (int x = left; x < right - step; x += step) {
        final c = _lumaAt(image, x, y);
        final r = _lumaAt(image, x + step, y);
        final d = _lumaAt(image, x, y + step);
        gradSum += (c - r).abs() + (c - d).abs();
        count += 2;
      }
    }
    if (count == 0) return 0.0;
    return (gradSum / count / 255.0).clamp(0.0, 1.0);
  }

  /// BGRA: R/B channel imbalance vs G often higher on LCD subpixels.
  static double _rgbGridScore(CameraImage image, Rect roi) {
    final plane = image.planes.first;
    final bpp = plane.bytesPerPixel ?? 1;
    if (bpp < 3) return 0.0;

    final left = roi.left.toInt();
    final top = roi.top.toInt();
    final right = roi.right.toInt();
    final bottom = roi.bottom.toInt();
    const step = 3;
    double imbalanceSum = 0.0;
    int count = 0;

    for (int y = top; y < bottom; y += step) {
      for (int x = left; x < right; x += step) {
        final offset = y * plane.bytesPerRow + x * bpp;
        final bytes = plane.bytes;
        if (offset + 2 >= bytes.length) continue;
        final b = bytes[offset];
        final g = bytes[offset + 1];
        final r = bytes[offset + 2];
        final avg = (r + g + b) / 3.0;
        if (avg < 20) continue;
        imbalanceSum += ((r - g).abs() + (b - g).abs()) / (avg * 2);
        count++;
      }
    }
    if (count < 8) return 0.0;
    return (imbalanceSum / count).clamp(0.0, 1.0);
  }

  /// Raw banding often reads ~1.0 on iPhone live camera — ignore that artifact.
  static double _sanitizeBandingScore(double raw) {
    if (raw >= 0.88) return 0.0;
    return raw;
  }

  static double _combineScores({
    required double bandFull,
    required double bandRoi,
    required double hfScore,
    required double gridScore,
  }) {
    final band = math.max(bandFull, bandRoi);
    final gridComponent = gridScore * 0.90;
    // Live blinks raise HF, not LCD grid — prefer grid when banding is weak.
    if (band < 0.18) {
      return gridComponent.clamp(0.0, 1.0);
    }
    return math.max(band, math.max(hfScore * 0.45, gridComponent));
  }

  static double _secondDerivativeEnergy(List<double> seq) {
    if (seq.length < 3) return 0.0;
    double energy = 0.0;
    for (int i = 1; i < seq.length - 1; i++) {
      final v = seq[i - 1] - (2 * seq[i]) + seq[i + 1];
      energy += v.abs();
    }
    return energy / (seq.length - 2);
  }

  static double _bandingOnImage(
    img.Image image,
    int x0,
    int y0,
    int regionW,
    int regionH,
  ) {
    if (regionW < 8 || regionH < 8) return 0.0;

    final x1 = math.min(image.width, x0 + regionW);
    final y1 = math.min(image.height, y0 + regionH);
    final width = x1 - x0;
    final height = y1 - y0;

    final rowCount = math.max(8, math.min(32, height ~/ 8));
    final colCount = math.max(8, math.min(32, width ~/ 8));
    final rowStep = math.max(1, height ~/ rowCount);
    final colStep = math.max(1, width ~/ colCount);

    final rowMeans = <double>[];
    final colMeans = List<double>.filled(colCount, 0.0);
    final colHits = List<int>.filled(colCount, 0);
    double sum = 0.0;
    double sumSq = 0.0;
    int sampleCount = 0;

    for (int y = y0; y < y1; y += rowStep) {
      double rowSum = 0.0;
      int rowHits = 0;
      var colIdx = 0;
      for (int x = x0; x < x1; x += colStep) {
        final lum = img.getLuminance(image.getPixel(x, y)).toDouble();
        rowSum += lum;
        rowHits++;
        if (colIdx < colCount) {
          colMeans[colIdx] += lum;
          colHits[colIdx]++;
        }
        sum += lum;
        sumSq += lum * lum;
        sampleCount++;
        colIdx++;
      }
      if (rowHits > 0) rowMeans.add(rowSum / rowHits);
    }

    if (sampleCount < 12 || rowMeans.length < 3) return 0.0;

    for (var i = 0; i < colMeans.length; i++) {
      if (colHits[i] > 0) colMeans[i] /= colHits[i];
    }

    final mean = sum / sampleCount;
    final variance = math.max(0.0, (sumSq / sampleCount) - (mean * mean));
    final stdDev = math.sqrt(variance);
    if (stdDev < _minContrast) return 0.0;

    final rowEnergy = _secondDerivativeEnergy(rowMeans);
    final colEnergy = _secondDerivativeEnergy(colMeans);
    return (math.max(rowEnergy, colEnergy) / stdDev).clamp(0.0, 1.0);
  }

  static double _moireOnImage(
    img.Image image,
    int x0,
    int y0,
    int regionW,
    int regionH,
  ) {
    final x1 = math.min(image.width, x0 + regionW);
    final y1 = math.min(image.height, y0 + regionH);
    if (x1 - x0 < 24 || y1 - y0 < 24) return 0.0;

    const step = 2;
    var altEnergy = 0.0;
    var total = 0;

    for (int y = y0; y < y1 - step; y += step) {
      for (int x = x0; x < x1 - step; x += step) {
        final a = img.getLuminance(image.getPixel(x, y));
        final b = img.getLuminance(image.getPixel(x + 1, y));
        final c = img.getLuminance(image.getPixel(x, y + 1));
        final d = img.getLuminance(image.getPixel(x + 1, y + 1));
        altEnergy += (a - b).abs() + (c - d).abs();
        total += 2;
      }
    }
    if (total == 0) return 0.0;
    return (altEnergy / total / 64.0).clamp(0.0, 1.0);
  }

  static double _rgbGridOnImage(
    img.Image image,
    int x0,
    int y0,
    int regionW,
    int regionH,
  ) {
    final x1 = math.min(image.width, x0 + regionW);
    final y1 = math.min(image.height, y0 + regionH);
    const step = 3;
    double imbalanceSum = 0.0;
    var count = 0;

    for (int y = y0; y < y1; y += step) {
      for (int x = x0; x < x1; x += step) {
        final p = image.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final avg = (r + g + b) / 3.0;
        if (avg < 20) continue;
        imbalanceSum += ((r - g).abs() + (b - g).abs()) / (avg * 2);
        count++;
      }
    }
    if (count < 8) return 0.0;
    return (imbalanceSum / count).clamp(0.0, 1.0);
  }

  static int _lumaAt(CameraImage image, int x, int y) {
    final plane = image.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final bytesPerPixel = plane.bytesPerPixel ?? 1;
    final offset = y * rowStride + (x * bytesPerPixel);
    if (offset < 0 || offset >= bytes.length) {
      return 0;
    }

    if (bytesPerPixel == 1) {
      return bytes[offset];
    }

    if (offset + 2 < bytes.length) {
      final b = bytes[offset];
      final g = bytes[offset + 1];
      final r = bytes[offset + 2];
      return ((0.114 * b) + (0.587 * g) + (0.299 * r)).round();
    }
    return bytes[offset];
  }
}

class ScreenSpoofResult {
  final double score;
  final bool isLikelyScreenReplay;
  final double bandingScore;
  final double faceRoiBandingScore;
  final double highFrequencyScore;
  final double gridScore;
  final double moireScore;

  const ScreenSpoofResult({
    required this.score,
    required this.isLikelyScreenReplay,
    this.bandingScore = 0.0,
    this.faceRoiBandingScore = 0.0,
    this.highFrequencyScore = 0.0,
    this.gridScore = 0.0,
    this.moireScore = 0.0,
  });
}
