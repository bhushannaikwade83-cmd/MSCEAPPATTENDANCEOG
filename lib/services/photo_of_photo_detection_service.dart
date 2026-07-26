import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// 🔒 Photo-of-Photo Detection Service
///
/// Detects when user shows a printed/screen photo instead of real face
/// Uses multiple detection methods:
/// 1. Image Blur Detection (Laplacian variance)
/// 2. Texture Analysis (detect print paper texture)
/// 3. Color Histogram Analysis (flat vs natural)
/// 4. Edge Detection (2D vs 3D characteristics)
class PhotoOfPhotoDetectionService {

  /// Analyze if image is "photo of photo" (fake)
  /// Returns: {
  ///   'isFake': bool,
  ///   'confidence': 0.0-1.0,
  ///   'reason': String,
  ///   'details': {...}
  /// }
  static Future<Map<String, dynamic>> analyzePhoto(
    File photoFile, {
    bool strictMode = false,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'ANTI_SPOOF_GATE: PHOTO_OF_PHOTO_CHECK_STARTED strictMode=$strictMode path=${photoFile.path}',
        );
      }
      if (kDebugMode) debugPrint('📸 Starting photo-of-photo analysis...');

      final imageBytes = await photoFile.readAsBytes();
      if (kDebugMode) debugPrint('📸 Image bytes read: ${imageBytes.length} bytes');

      final image = img.decodeImage(imageBytes);

      if (image == null) {
        if (kDebugMode) debugPrint('❌ Could not decode image');
        return {
          'isFake': true,
          'confidence': 1.0,
          'reason': 'Invalid image file',
          'details': {'error': 'Could not decode image'}
        };
      }

      if (kDebugMode) debugPrint('📸 Image decoded successfully: ${image.width}x${image.height}');

      // Run all detection methods
      final results = <String, double>{};

      // Method 1: Blur Detection
      if (kDebugMode) debugPrint('📸 Running blur detection...');
      final blurScore = _detectBlur(image);
      results['blur'] = blurScore;
      if (kDebugMode) debugPrint('📸 Blur score: ${blurScore.toStringAsFixed(2)}');

      // Method 2: Texture Analysis
      if (kDebugMode) debugPrint('📸 Running texture analysis...');
      final textureScore = _analyzeTexture(image);
      results['texture'] = textureScore;
      if (kDebugMode) debugPrint('📸 Texture score: ${textureScore.toStringAsFixed(2)}');

      // Method 3: Color Histogram
      if (kDebugMode) debugPrint('📸 Running histogram analysis...');
      final histogramScore = _analyzeHistogram(image);
      results['histogram'] = histogramScore;
      if (kDebugMode) debugPrint('📸 Histogram score: ${histogramScore.toStringAsFixed(2)}');

      // Method 4: Edge Detection
      if (kDebugMode) debugPrint('📸 Running edge detection...');
      final edgeScore = _analyzeEdges(image);
      results['edges'] = edgeScore;
      if (kDebugMode) debugPrint('📸 Edge score: ${edgeScore.toStringAsFixed(2)}');

      // Calculate overall confidence
      final overallConfidence = _calculateConfidence(results);
      final isFake = _isLikelyFakePhoto(results, overallConfidence, strictMode);

      if (kDebugMode) {
        debugPrint('📸 ✅ Photo Analysis Complete:');
        debugPrint('   Overall Confidence: ${overallConfidence.toStringAsFixed(2)}');
        debugPrint('   Is Fake: $isFake');
        debugPrint(
          'ANTI_SPOOF_GATE: PHOTO_OF_PHOTO_CHECK_RESULT isFake=$isFake confidence=${overallConfidence.toStringAsFixed(2)}',
        );
      }

      return {
        'isFake': isFake,
        'confidence': overallConfidence,
        'reason': _getReasonMessage(results, isFake),
        'details': results,
      };

    } catch (e) {
      debugPrint('❌ CRITICAL Error in photo analysis: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');
      // Strict mode blocks when detector cannot complete.
      if (kDebugMode) {
        debugPrint(
          strictMode
              ? '📸 Photo analysis failed in strict mode, blocking photo'
              : '📸 Photo analysis failed, allowing photo to proceed',
        );
        debugPrint(
          'ANTI_SPOOF_GATE: PHOTO_OF_PHOTO_CHECK_ERROR strictMode=$strictMode error=$e',
        );
      }
      return {
        'isFake': strictMode,
        'confidence': 0.0,
        'reason': strictMode
            ? 'Could not verify a live face. Please retake in better lighting.'
            : 'Could not analyze photo (service error)',
        'details': {'error': e.toString(), 'type': e.runtimeType.toString()}
      };
    }
  }

  /// Method 1: Detect image blur (Laplacian variance)
  /// High blur = likely a photo of photo (less sharp)
  /// Returns score 0.0-1.0 (higher = more likely fake)
  static double _detectBlur(img.Image image) {
    try {
      // Convert to grayscale
      final gray = img.grayscale(image);

      // Apply Laplacian filter to detect edges
      final width = gray.width;
      final height = gray.height;

      double laplacianVariance = 0.0;
      int edgeCount = 0;

      // Sample every 2nd pixel for performance
      for (int y = 2; y < height - 2; y += 2) {
        for (int x = 2; x < width - 2; x += 2) {
          try {
            // Laplacian kernel - safely access pixels
            final center = _getPixelLuminance(gray, x, y);
            final n = _getPixelLuminance(gray, x, y - 1);
            final s = _getPixelLuminance(gray, x, y + 1);
            final e = _getPixelLuminance(gray, x + 1, y);
            final w = _getPixelLuminance(gray, x - 1, y);

            final laplacian = 4 * center - n - s - e - w;
            laplacianVariance += laplacian * laplacian;
            edgeCount++;
          } catch (e) {
            // Skip problematic pixels
            continue;
          }
        }
      }

      // Normalize: low variance = blurry = fake
      final avgVariance = edgeCount > 0 ? laplacianVariance / edgeCount : 0;

      // Convert to 0-1 score (inverted: high blur = high score)
      // Sharp images have variance > 500
      // Blurry images have variance < 200
      final blurScore = avgVariance < 400 ?
        ((400 - avgVariance) / 400).clamp(0.0, 1.0) : 0.0;

      if (kDebugMode) {
        debugPrint('📸 Blur: avgVariance=${avgVariance.toStringAsFixed(2)}, score=${blurScore.toStringAsFixed(2)}');
      }

      return blurScore;
    } catch (e) {
      debugPrint('⚠️ Error in blur detection: $e');
      return 0.3; // Default medium score
    }
  }

  /// Method 2: Texture Analysis
  /// Printed photos have repetitive patterns
  /// Real faces have organic texture variation
  static double _analyzeTexture(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      // Analyze texture variation in the image
      // Printed photos have low variation (repetitive), real faces have high variation
      double varianceSum = 0.0;
      int blockCount = 0;

      // Divide image into 8x8 blocks and measure variance within each
      for (int by = 0; by < height; by += 8) {
        for (int bx = 0; bx < width; bx += 8) {
          try {
            // Calculate mean brightness in block
            double blockMean = 0.0;
            int blockPixels = 0;

            for (int dy = 0; dy < 8 && by + dy < height; dy++) {
              for (int dx = 0; dx < 8 && bx + dx < width; dx++) {
                final lum = _getPixelLuminance(image, bx + dx, by + dy);
                blockMean += lum;
                blockPixels++;
              }
            }

            if (blockPixels > 0) {
              blockMean /= blockPixels;

              // Calculate variance in block
              double blockVariance = 0.0;
              for (int dy = 0; dy < 8 && by + dy < height; dy++) {
                for (int dx = 0; dx < 8 && bx + dx < width; dx++) {
                  final lum = _getPixelLuminance(image, bx + dx, by + dy);
                  blockVariance += (lum - blockMean) * (lum - blockMean);
                }
              }

              varianceSum += blockVariance / blockPixels;
              blockCount++;
            }
          } catch (e) {
            continue;
          }
        }
      }

      // Average variance across blocks
      final avgVariance = blockCount > 0 ? varianceSum / blockCount : 0.0;

      // Low variance = repetitive = fake (printed photos have variance 50-200)
      // High variance = natural texture = real (real faces have variance 400+)
      final textureScore = avgVariance < 300 ?
        ((300 - avgVariance) / 300).clamp(0.0, 1.0) : 0.0;

      if (kDebugMode) {
        debugPrint('📸 Texture: avgVariance=${avgVariance.toStringAsFixed(2)}, score=${textureScore.toStringAsFixed(2)}');
      }

      return textureScore;
    } catch (e) {
      debugPrint('⚠️ Error in texture analysis: $e');
      return 0.2;
    }
  }

  /// Method 3: Analyze color histogram
  /// Printed photos have flatter, more uniform color distribution
  /// Real faces have richer color variation
  static double _analyzeHistogram(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      // Simplified histogram analysis using pixel sampling
      // Count distinct brightness levels in the image
      final Set<int> brightnessBuckets = {};
      int sampledPixels = 0;

      // Sample every 4th pixel for performance
      for (int y = 0; y < height; y += 4) {
        for (int x = 0; x < width; x += 4) {
          try {
            final lum = _getPixelLuminance(image, x, y);
            final bucket = (lum / 10).round(); // Group into buckets of 10
            brightnessBuckets.add(bucket);
            sampledPixels++;
          } catch (e) {
            continue;
          }
        }
      }

      // Fewer buckets = flatter histogram = printed photo
      // Real faces have variance (many different brightness levels)
      // Printed photos have limited brightness levels
      final bucketCount = brightnessBuckets.length;

      // Real faces typically have 15-25 buckets, printed ~5-12
      final flatnessScore = bucketCount < 12 ?
        ((12 - bucketCount) / 12).clamp(0.0, 1.0) : 0.0;

      if (kDebugMode) {
        debugPrint('📸 Histogram: $bucketCount buckets, flatness=${flatnessScore.toStringAsFixed(2)}');
      }

      return flatnessScore;
    } catch (e) {
      debugPrint('⚠️ Error in histogram analysis: $e');
      return 0.2;
    }
  }

  /// Method 4: Edge Detection Analysis
  /// Real 3D faces have depth-related edge variations
  /// 2D printed photos have different edge characteristics
  static double _analyzeEdges(img.Image image) {
    try {
      final width = image.width;
      final height = image.height;

      // Simplified Sobel edge detection using pixel luminance
      double edgeCount = 0.0;
      int processedPixels = 0;

      // Sample every other pixel for performance
      for (int y = 2; y < height - 2; y += 2) {
        for (int x = 2; x < width - 2; x += 2) {
          try {
            final center = _getPixelLuminance(image, x, y);
            final right = _getPixelLuminance(image, x + 1, y);
            final down = _getPixelLuminance(image, x, y + 1);

            // Calculate gradient magnitude
            final gradX = (right - center).abs();
            final gradY = (down - center).abs();
            final magnitude = (gradX + gradY).toDouble();

            if (magnitude > 30) {
              edgeCount++;
            }
            processedPixels++;
          } catch (e) {
            continue;
          }
        }
      }

      // Edge density analysis
      // Real faces have moderate edge density
      // 2D printed photos have different patterns
      final edgeDensity = processedPixels > 0 ?
        (edgeCount / processedPixels).clamp(0.0, 1.0) : 0.0;

      // Score: high edge density (>0.3) suggests strong boundaries typical of 2D images
      final edgeAnomalyScore = edgeDensity > 0.3 ? edgeDensity - 0.3 : 0.0;

      if (kDebugMode) {
        debugPrint('📸 Edges: density=${edgeDensity.toStringAsFixed(2)}, anomaly=${edgeAnomalyScore.toStringAsFixed(2)}');
      }

      return edgeAnomalyScore.clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('⚠️ Error in edge analysis: $e');
      return 0.2;
    }
  }

  /// Calculate overall confidence
  static double _calculateConfidence(Map<String, double> results) {
    // STRICTER weights - boost histogram/edges to catch printed photos
    final weights = {
      'blur': 0.25,      // 25% weight
      'texture': 0.30,   // 30% weight
      'histogram': 0.25, // 25% weight (important for flat photos!)
      'edges': 0.20,     // 20% weight (2D vs 3D detection)
    };

    double confidence = 0.0;
    weights.forEach((key, weight) {
      confidence += (results[key] ?? 0.0) * weight;
    });

    return confidence.clamp(0.0, 1.0);
  }

  /// Decision rule tuned to reduce false positives on genuine users.
  /// Strict mode still blocks clear spoof attempts, but requires stronger evidence.
  static bool _isLikelyFakePhoto(
    Map<String, double> results,
    double overallConfidence,
    bool strictMode,
  ) {
    final blur = results['blur'] ?? 0.0;
    final texture = results['texture'] ?? 0.0;
    final histogram = results['histogram'] ?? 0.0;
    final edges = results['edges'] ?? 0.0;

    final strongSignals = [
      texture >= 0.80,  // Increased from 0.70
      histogram >= 0.80,  // Increased from 0.70
      edges >= 0.55,  // Increased from 0.45
      blur >= 0.85,  // Increased from 0.75
    ].where((v) => v).length;

    final mediumSignals = [
      texture >= 0.65,  // Increased from 0.50
      histogram >= 0.65,  // Increased from 0.50
      edges >= 0.40,  // Increased from 0.30
      blur >= 0.70,  // Increased from 0.60
    ].where((v) => v).length;

    // ⚠️ CRITICAL: Printed/passport photos have VERY LOW histogram + edges
    // Real faces MUST have some color variation and edge detail
    final suspiciouslyFlat = (histogram < 0.10 && edges < 0.10);  // Reduced from 0.15

    if (strictMode) {
      // STRICTER - catches printed photos, passport photos, screen replays
      return strongSignals >= 2 ||
          (strongSignals >= 1 && overallConfidence >= 0.65) ||
          (mediumSignals >= 3 && overallConfidence >= 0.60) ||
          (suspiciouslyFlat && texture >= 0.50);  // Increased from 0.40
    }

    // Non-strict mode - reduced sensitivity to minimize false positives on real photos
    return strongSignals >= 3 ||  // Increased from 2 - needs 3 strong signals
        overallConfidence >= 0.70 ||  // Increased from 0.50
        (suspiciouslyFlat && texture >= 0.50);  // Increased from 0.35
  }

  /// Get user-friendly error message
  static String _getReasonMessage(Map<String, double> results, bool isFake) {
    if (!isFake) {
      return 'Photo accepted - Real face detected';
    }

    // Determine which method detected the fake
    final blur = results['blur'] ?? 0.0;
    final texture = results['texture'] ?? 0.0;
    final histogram = results['histogram'] ?? 0.0;
    final edges = results['edges'] ?? 0.0;

    if (texture > 0.4) {
      return 'Photo of photo is detected. Printed photo/screen replay is not allowed. Please show your real face.';
    }
    if (histogram > 0.5) {
      return 'Photo of photo is detected. Screenshot/display replay is not allowed. Please take a live photo.';
    }
    if (blur > 0.6) {
      return 'Photo of photo is detected or image is too unclear. Please retake with a live face clearly visible.';
    }
    if (edges > 0.3) {
      return 'Photo of photo is detected. 2D image replay is not allowed. Please show your real face.';
    }

    return 'Photo of photo is detected. Please use a live face and try again.';
  }

  /// Helper: Safely get pixel luminance using image package API
  static double _getPixelLuminance(img.Image image, int x, int y) {
    try {
      final pixel = image.getPixelSafe(x, y);
      if (pixel == null) return 128.0; // Default middle gray
      return img.getLuminance(pixel).toDouble();
    } catch (e) {
      return 128.0; // Default middle gray on error
    }
  }
}
