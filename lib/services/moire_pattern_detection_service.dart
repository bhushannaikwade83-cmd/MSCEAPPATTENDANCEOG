import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// 🌀 Moiré Pattern Detection Service
///
/// Detects moiré patterns that appear when photographing:
/// - Laptop displays
/// - Mobile phone screens
/// - Printed halftone images
///
/// Moiré patterns have characteristic:
/// - Regular repeating frequencies
/// - Wave-like patterns
/// - Frequency signatures (60Hz, 50Hz screen refresh)
///
/// Uses simplified frequency domain analysis to detect these patterns
class MoirePatternDetectionService {
  MoirePatternDetectionService._();

  /// Detect moiré patterns in image
  /// Returns {
  ///   'hasMorePattern': bool,
  ///   'confidence': 0.0-1.0,
  ///   'reason': String,
  ///   'metrics': {
  ///     'frequencyPeakStrength': double,
  ///     'patternRegularity': double,
  ///     'waveDetection': double,
  ///   }
  /// }
  static Future<Map<String, dynamic>> detectMorePattern(File photoFile) async {
    try {
      if (kDebugMode) debugPrint('🌀 Starting moiré pattern detection...');

      final imageBytes = await photoFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        if (kDebugMode) debugPrint('❌ Could not decode image');
        return {
          'hasMorePattern': false,
          'confidence': 0.0,
          'reason': 'Could not analyze image',
          'metrics': {}
        };
      }

      if (kDebugMode) debugPrint('🌀 Image decoded: ${image.width}x${image.height}');

      // Convert to grayscale for frequency analysis
      final grayscale = img.grayscale(image);

      final metrics = <String, double>{};

      // Metric 1: Detect regular frequency peaks (screen grid patterns)
      if (kDebugMode) debugPrint('🌀 Analyzing frequency peaks...');
      final frequencyPeakStrength = _analyzeFrequencyPeaks(grayscale);
      metrics['frequencyPeakStrength'] = frequencyPeakStrength;
      if (kDebugMode) {
        debugPrint('🌀 Frequency peak strength: ${frequencyPeakStrength.toStringAsFixed(2)}');
      }

      // Metric 2: Detect pattern regularity (repeating patterns)
      if (kDebugMode) debugPrint('🌀 Detecting pattern regularity...');
      final patternRegularity = _detectPatternRegularity(grayscale);
      metrics['patternRegularity'] = patternRegularity;
      if (kDebugMode) {
        debugPrint('🌀 Pattern regularity: ${patternRegularity.toStringAsFixed(2)}');
      }

      // Metric 3: Detect wave patterns (moiré waves)
      if (kDebugMode) debugPrint('🌀 Detecting wave patterns...');
      final waveDetection = _detectWavePatterns(grayscale);
      metrics['waveDetection'] = waveDetection;
      if (kDebugMode) debugPrint('🌀 Wave detection: ${waveDetection.toStringAsFixed(2)}');

      // Calculate overall moiré confidence
      final moireConfidence = _calculateMoreConfidence(metrics);
      final hasMorePattern = moireConfidence > 0.50; // Threshold

      if (kDebugMode) {
        debugPrint('🌀 Moiré confidence: ${moireConfidence.toStringAsFixed(2)} (threshold: 0.50)');
        debugPrint('   Has moiré pattern: $hasMorePattern');
      }

      return {
        'hasMorePattern': hasMorePattern,
        'confidence': moireConfidence,
        'reason': _getMoreReason(metrics, hasMorePattern),
        'metrics': metrics,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error in moiré detection: $e');
      return {
        'hasMorePattern': false,
        'confidence': 0.0,
        'reason': 'Could not analyze moiré patterns',
        'metrics': {}
      };
    }
  }

  /// Analyze frequency peaks (simplified frequency domain analysis)
  /// Screens have characteristic frequency signatures at 50/60Hz
  static double _analyzeFrequencyPeaks(img.Image grayscale) {
    try {
      final width = grayscale.width;
      final height = grayscale.height;

      // Sample horizontal and vertical line profiles
      // Screen patterns repeat at regular intervals (pixel grid)

      // Horizontal profile (middle row)
      final midY = height ~/ 2;
      final horizontalProfile = <int>[];

      for (int x = 0; x < width; x++) {
        try {
          final pixel = grayscale.getPixelSafe(x, midY);
          if (pixel != null) {
            final lum = img.getLuminance(pixel);
            horizontalProfile.add(lum.toInt());
          }
        } catch (e) {
          continue;
        }
      }

      if (horizontalProfile.isEmpty) return 0.2;

      // Detect periodicity in the profile
      // Screens have repeating patterns at pixel grid frequency
      // Calculate autocorrelation for common periods (pixels per cycle)

      double maxCorrelation = 0.0;
      const testPeriods = [2, 3, 4, 5, 6, 8, 10, 12]; // Common pixel grid sizes

      for (final period in testPeriods) {
        double correlation = 0.0;
        int count = 0;

        for (int i = 0; i < horizontalProfile.length - period; i++) {
          final diff = (horizontalProfile[i] - horizontalProfile[i + period]).abs();
          correlation += (255 - diff) / 255.0; // Higher correlation = less difference
          count++;
        }

        if (count > 0) {
          correlation /= count;
          if (correlation > maxCorrelation) {
            maxCorrelation = correlation;
          }
        }
      }

      // Real faces: low correlation (random texture)
      // Screens: high correlation (repeating pixels/patterns)
      return (maxCorrelation * 0.5).clamp(0.0, 1.0);
    } catch (e) {
      return 0.2;
    }
  }

  /// Detect pattern regularity (how regular/repetitive the patterns are)
  static double _detectPatternRegularity(img.Image grayscale) {
    try {
      final width = grayscale.width;
      final height = grayscale.height;

      // Divide into blocks and check if blocks are similar (indicates repetition)
      const blockSize = 16;
      final blockSimilarities = <double>[];

      for (int by = 0; by < height - blockSize * 2; by += blockSize) {
        for (int bx = 0; bx < width - blockSize * 2; bx += blockSize) {
          try {
            // Get average luminance of current block and next block
            double block1Sum = 0.0, block2Sum = 0.0;
            int block1Count = 0, block2Count = 0;

            // Block 1
            for (int y = by; y < by + blockSize && y < height; y++) {
              for (int x = bx; x < bx + blockSize && x < width; x++) {
                final pixel = grayscale.getPixelSafe(x, y);
                if (pixel != null) {
                  block1Sum += img.getLuminance(pixel);
                  block1Count++;
                }
              }
            }

            // Block 2 (next to block 1)
            for (int y = by; y < by + blockSize && y < height; y++) {
              for (int x = bx + blockSize; x < bx + blockSize * 2 && x < width; x++) {
                final pixel = grayscale.getPixelSafe(x, y);
                if (pixel != null) {
                  block2Sum += img.getLuminance(pixel);
                  block2Count++;
                }
              }
            }

            if (block1Count > 0 && block2Count > 0) {
              final avg1 = block1Sum / block1Count;
              final avg2 = block2Sum / block2Count;
              final similarity = 1.0 - ((avg1 - avg2).abs() / 255.0);
              blockSimilarities.add(similarity);
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (blockSimilarities.isEmpty) return 0.2;

      // Calculate variance of similarities
      final meanSimilarity = blockSimilarities.reduce((a, b) => a + b) / blockSimilarities.length;
      final variance = blockSimilarities
          .map((s) => (s - meanSimilarity) * (s - meanSimilarity))
          .reduce((a, b) => a + b) /
          blockSimilarities.length;

      // Low variance = regular patterns = screen
      // High variance = natural variation = real face
      final regularity = 1.0 / (1.0 + (variance * 10));

      // Real faces: 0.3-0.5 regularity (natural variation)
      // Screens: 0.7-0.95 regularity (very regular patterns)
      return (regularity * 0.6).clamp(0.0, 1.0);
    } catch (e) {
      return 0.2;
    }
  }

  /// Detect wave patterns (moiré waves)
  static double _detectWavePatterns(img.Image grayscale) {
    try {
      final width = grayscale.width;
      final height = grayscale.height;

      // Analyze horizontal gradients (changes in luminance across rows)
      // Moiré patterns create wave-like gradient changes

      double totalGradientWave = 0.0;
      int gradientCount = 0;

      // Sample gradient changes across horizontal lines
      for (int y = 10; y < height - 10; y += 10) {
        final gradients = <int>[];

        for (int x = 1; x < width - 1; x++) {
          try {
            final left = grayscale.getPixelSafe(x - 1, y);
            final center = grayscale.getPixelSafe(x, y);
            final right = grayscale.getPixelSafe(x + 1, y);

            if (left != null && center != null && right != null) {
              final leftLum = img.getLuminance(left);
              final rightLum = img.getLuminance(right);
              final grad = (rightLum - leftLum).abs();
              gradients.add(grad.toInt());
            }
          } catch (e) {
            continue;
          }
        }

        if (gradients.length > 2) {
          // Calculate variance of gradients
          // Moiré: high variance (wave-like changes)
          // Real face: low variance (smooth gradient)
          final mean = gradients.reduce((a, b) => a + b) / gradients.length;
          final variance = gradients
              .map((g) => (g - mean.toInt()) * (g - mean.toInt()))
              .reduce((a, b) => a + b) /
              gradients.length;

          totalGradientWave += variance.toDouble();
          gradientCount++;
        }
      }

      if (gradientCount == 0) return 0.2;

      final avgGradientWave = totalGradientWave / gradientCount;

      // Real faces: low gradient variance (smooth transitions)
      // Screens with moiré: high gradient variance (wave patterns)
      final waveScore = math.min(avgGradientWave / 10000, 1.0);

      return waveScore.clamp(0.0, 1.0);
    } catch (e) {
      return 0.2;
    }
  }

  /// Calculate overall moiré confidence
  static double _calculateMoreConfidence(Map<String, double> metrics) {
    final frequencyPeaks = metrics['frequencyPeakStrength'] ?? 0.0;
    final patternRegularity = metrics['patternRegularity'] ?? 0.0;
    final waveDetection = metrics['waveDetection'] ?? 0.0;

    // Weighted combination
    // All three metrics should indicate moiré to be confident
    final score = (
        (frequencyPeaks * 0.35) +
        (patternRegularity * 0.35) +
        (waveDetection * 0.30)
    ).clamp(0.0, 1.0);

    return score;
  }

  /// Get user-friendly reason
  static String _getMoreReason(Map<String, double> metrics, bool hasMore) {
    if (!hasMore) {
      return 'Face verified - no moiré patterns detected ✓';
    }

    final frequency = metrics['frequencyPeakStrength'] ?? 0.0;
    final regularity = metrics['patternRegularity'] ?? 0.0;
    final wave = metrics['waveDetection'] ?? 0.0;

    if (frequency > 0.6 && regularity > 0.6) {
      return '❌ Screen grid pattern detected - show your real face, not display.';
    }
    if (wave > 0.6) {
      return '❌ Moiré wave pattern detected - take photo of real face.';
    }

    return '❌ Display pattern detected - show your real face.';
  }
}
