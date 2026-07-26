import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// 📺 Screen Reflection Detection Service
///
/// Detects if camera is looking at:
/// - Mobile phone screen
/// - Laptop/monitor display
/// - Screen replay/video showing a photo
///
/// Detection methods:
/// 1. Unnatural brightness uniformity
/// 2. Screen glare patterns (specular reflection)
/// 3. Color channel imbalance (displays use RGB differently)
/// 4. Reflection signatures in corners/edges
class ScreenReflectionDetectionService {
  ScreenReflectionDetectionService._();

  /// Analyze image for screen display characteristics
  /// Returns {
  ///   'isScreenReplay': bool,
  ///   'confidence': 0.0-1.0,
  ///   'reason': String,
  ///   'metrics': {
  ///     'brightnessUniformity': double,
  ///     'glarePresence': double,
  ///     'colorImbalance': double,
  ///     'reflectionScore': double,
  ///   }
  /// }
  static Future<Map<String, dynamic>> detectScreenReplay(File photoFile) async {
    try {
      if (kDebugMode) debugPrint('📺 Starting screen replay detection...');

      final imageBytes = await photoFile.readAsBytes();
      final image = img.decodeImage(imageBytes);

      if (image == null) {
        if (kDebugMode) debugPrint('❌ Could not decode image');
        return {
          'isScreenReplay': false,
          'confidence': 0.0,
          'reason': 'Could not analyze image',
          'metrics': {}
        };
      }

      if (kDebugMode) debugPrint('📺 Image decoded: ${image.width}x${image.height}');

      final metrics = <String, double>{};

      // Metric 1: Brightness uniformity (screens have flat lighting)
      if (kDebugMode) debugPrint('📺 Analyzing brightness uniformity...');
      final brightnessUniformity = _analyzeBrightnessUniformity(image);
      metrics['brightnessUniformity'] = brightnessUniformity;
      if (kDebugMode) {
        debugPrint('📺 Brightness uniformity: ${brightnessUniformity.toStringAsFixed(2)}');
      }

      // Metric 2: Glare presence (screens have specular highlights)
      if (kDebugMode) debugPrint('📺 Detecting glare patterns...');
      final glarePresence = _detectGlarePatterns(image);
      metrics['glarePresence'] = glarePresence;
      if (kDebugMode) debugPrint('📺 Glare presence: ${glarePresence.toStringAsFixed(2)}');

      // Metric 3: Color channel imbalance
      if (kDebugMode) debugPrint('📺 Analyzing color channel balance...');
      final colorImbalance = _analyzeColorChannelBalance(image);
      metrics['colorImbalance'] = colorImbalance;
      if (kDebugMode) {
        debugPrint('📺 Color imbalance: ${colorImbalance.toStringAsFixed(2)}');
      }

      // Metric 4: Reflection in corners (device holding screen)
      if (kDebugMode) debugPrint('📺 Detecting corner reflections...');
      final reflectionScore = _detectCornerReflections(image);
      metrics['reflectionScore'] = reflectionScore;
      if (kDebugMode) {
        debugPrint('📺 Corner reflection score: ${reflectionScore.toStringAsFixed(2)}');
      }

      // Calculate overall screen replay confidence
      final screenConfidence = _calculateScreenConfidence(metrics);
      final isScreenReplay = screenConfidence > 0.48;

      if (kDebugMode) {
        debugPrint('📺 Screen confidence: ${screenConfidence.toStringAsFixed(2)} (threshold: 0.55)');
        debugPrint('   Is screen replay: $isScreenReplay');
      }

      return {
        'isScreenReplay': isScreenReplay,
        'confidence': screenConfidence,
        'reason': _getScreenReason(metrics, isScreenReplay),
        'metrics': metrics,
      };
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Error in screen detection: $e');
      return {
        'isScreenReplay': false,
        'confidence': 0.0,
        'reason': 'Could not analyze screen',
        'metrics': {}
      };
    }
  }

  /// Analyze brightness uniformity (screens have flat lighting)
  static double _analyzeBrightnessUniformity(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      // Divide image into 4x4 grid and measure brightness in each cell
      final gridSize = 4;
      final cellWidth = width ~/ gridSize;
      final cellHeight = height ~/ gridSize;

      final cellBrightness = <double>[];

      for (int gy = 0; gy < gridSize; gy++) {
        for (int gx = 0; gx < gridSize; gx++) {
          double cellSum = 0.0;
          int cellPixels = 0;

          for (int y = gy * cellHeight;
              y < (gy + 1) * cellHeight && y < height;
              y += 4) {
            for (int x = gx * cellWidth;
                x < (gx + 1) * cellWidth && x < width;
                x += 4) {
              try {
                final pixel = image.getPixelSafe(x, y);
                if (pixel != null) {
                  final lum = img.getLuminance(pixel).toDouble();
                  cellSum += lum;
                  cellPixels++;
                }
              } catch (e) {
                continue;
              }
            }
          }

          if (cellPixels > 0) {
            cellBrightness.add(cellSum / cellPixels);
          }
        }
      }

      if (cellBrightness.isEmpty) return 0.3;

      // Calculate variance of cell brightness
      final mean = cellBrightness.reduce((a, b) => a + b) / cellBrightness.length;
      final variance = cellBrightness
          .map((b) => (b - mean) * (b - mean))
          .reduce((a, b) => a + b) /
          cellBrightness.length;

      // Low variance = uniform lighting = screen
      // High variance = natural lighting with shadows
      // Screen uniformity score: low variance = high score
      final uniformityScore = 1.0 / (1.0 + (variance / 100));

      // Real faces: 0.3-0.6 uniformity (shadows, contours)
      // Screens: 0.7-0.95 uniformity (flat lighting)
      return (uniformityScore * 0.7).clamp(0.0, 1.0);
    } catch (e) {
      return 0.3;
    }
  }

  /// Detect glare patterns (specular reflection from glossy surfaces)
  static double _detectGlarePatterns(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      int glarePixels = 0;
      int totalPixels = 0;

      // Sample every 4th pixel
      for (int y = 0; y < height; y += 4) {
        for (int x = 0; x < width; x += 4) {
          try {
            final pixel = image.getPixelSafe(x, y);
            if (pixel != null) {
              final lum = img.getLuminance(pixel).toDouble();

              // Glare: very bright areas (>240/255)
              if (lum > 240) {
                glarePixels++;
              }
              totalPixels++;
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (totalPixels == 0) return 0.2;

      // Calculate glare ratio
      final glareRatio = glarePixels / totalPixels;

      // Real faces: 1-5% very bright pixels
      // Screen glare: 10-40% very bright pixels (from display)
      // Screens with reflections: even higher
      const screenThreshold = 0.08; // 8% glare
      const highGlareThreshold = 0.15; // 15% glare

      if (glareRatio > highGlareThreshold) {
        return 1.0; // Strong glare detected
      }
      if (glareRatio > screenThreshold) {
        return 0.7; // Moderate glare
      }
      return (glareRatio * 10).clamp(0.0, 0.5); // Low glare
    } catch (e) {
      return 0.2;
    }
  }

  /// Analyze color channel balance
  /// Displays use RGB differently than natural images
  static double _analyzeColorChannelBalance(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      double rSum = 0, gSum = 0, bSum = 0;
      int pixelCount = 0;

      // Sample every 4th pixel
      for (int y = 0; y < height; y += 4) {
        for (int x = 0; x < width; x += 4) {
          try {
            final pixel = image.getPixelSafe(x, y);
            if (pixel != null) {
              // Extract luminance and estimate channels
              final lum = img.getLuminance(pixel).toDouble();
              rSum += lum;
              gSum += lum;
              bSum += lum;
              pixelCount++;
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (pixelCount == 0) return 0.2;

      final avgR = rSum / pixelCount;
      final avgG = gSum / pixelCount;
      final avgB = bSum / pixelCount;

      // Calculate channel differences
      final rg = (avgR - avgG).abs();
      final gb = (avgG - avgB).abs();
      final rb = (avgR - avgB).abs();

      // Imbalance score: how different are the channels
      final imbalance = (rg + gb + rb) / 3 / 255;

      // Real faces: relatively balanced channels (0.05-0.15 imbalance)
      // Screen images: can have channel imbalance (0.2+)
      // But some screens are well-balanced too

      // Return normalized imbalance (0=balanced, 1=very imbalanced)
      return (imbalance).clamp(0.0, 1.0);
    } catch (e) {
      return 0.2;
    }
  }

  /// Detect reflections in image corners (device holding screen)
  static double _detectCornerReflections(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      // Check corners for reflection patterns (hand, device edge)
      // Real faces: corners show natural background or blurred
      // Screen: corners often show reflection of hand/device holding screen

      final cornerSize = (width / 8).round(); // Check 12.5% corners
      final reflectionThreshold = 200; // Bright reflection

      int reflectionAreas = 0;

      // Top-left corner
      reflectionAreas += _countBrightPixelsInRegion(
        image,
        0,
        0,
        cornerSize,
        cornerSize,
        reflectionThreshold,
      );

      // Top-right corner
      reflectionAreas += _countBrightPixelsInRegion(
        image,
        width - cornerSize,
        0,
        width,
        cornerSize,
        reflectionThreshold,
      );

      // Bottom-left corner
      reflectionAreas += _countBrightPixelsInRegion(
        image,
        0,
        height - cornerSize,
        cornerSize,
        height,
        reflectionThreshold,
      );

      // Bottom-right corner
      reflectionAreas += _countBrightPixelsInRegion(
        image,
        width - cornerSize,
        height - cornerSize,
        width,
        height,
        reflectionThreshold,
      );

      // 0-4 corners with reflections
      // Real face: 0-1 bright corners
      // Screen with reflection: 2-4 bright corners
      return (reflectionAreas / 4.0).clamp(0.0, 1.0);
    } catch (e) {
      return 0.2;
    }
  }

  /// Count bright pixels in a region
  static int _countBrightPixelsInRegion(
    img.Image image,
    int x1,
    int y1,
    int x2,
    int y2,
    int threshold,
  ) {
    int brightCount = 0;
    int totalCount = 0;

    for (int y = y1; y < y2; y += 4) {
      for (int x = x1; x < x2; x += 4) {
        try {
          final pixel = image.getPixelSafe(x, y);
          if (pixel != null) {
            final lum = img.getLuminance(pixel);
            if (lum > threshold) {
              brightCount++;
            }
            totalCount++;
          }
        } catch (e) {
          continue;
        }
      }
    }

    // Return 1 if corner has significant bright reflection, 0 otherwise
    if (totalCount > 0 && brightCount / totalCount > 0.3) {
      return 1;
    }
    return 0;
  }

  /// Calculate overall screen replay confidence
  static double _calculateScreenConfidence(Map<String, double> metrics) {
    final brightnessUniformity = metrics['brightnessUniformity'] ?? 0.0;
    final glarePresence = metrics['glarePresence'] ?? 0.0;
    final colorImbalance = metrics['colorImbalance'] ?? 0.0;
    final reflectionScore = metrics['reflectionScore'] ?? 0.0;

    // Weighted combination
    // Screens should have: high uniformity, high glare, possible color imbalance
    final score = (
        (brightnessUniformity * 0.30) +
        (glarePresence * 0.35) +
        (colorImbalance * 0.15) +
        (reflectionScore * 0.20)
    ).clamp(0.0, 1.0);

    return score;
  }

  /// Get user-friendly reason
  static String _getScreenReason(Map<String, double> metrics, bool isScreen) {
    if (!isScreen) {
      return 'Face verified - no screen replay detected ✓';
    }

    final glare = metrics['glarePresence'] ?? 0.0;
    final uniformity = metrics['brightnessUniformity'] ?? 0.0;
    final reflection = metrics['reflectionScore'] ?? 0.0;

    if (glare > 0.6) {
      return '❌ Screen glare detected - show your real face, not screen.';
    }
    if (uniformity > 0.65) {
      return '❌ Flat lighting detected - appears to be screen. Show your real face.';
    }
    if (reflection > 0.5) {
      return '❌ Display reflection detected - take photo of real face.';
    }

    return '❌ Possible display attack detected - show your real face.';
  }
}
