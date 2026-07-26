import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Image Quality Service
/// Checks brightness, sharpness, face size, and contrast
class ImageQualityService {
  static final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(enableContours: true),
  );

  /// Check overall image quality
  static Future<ImageQualityResult> checkQuality(String photoPath) async {
    try {
      if (kDebugMode) debugPrint('🔍 Checking image quality...');

      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);

      if (image == null) {
        return ImageQualityResult(
          isGood: false,
          brightness: 0,
          sharpness: 0,
          contrast: 0,
          faceSize: 0,
          reason: 'Failed to decode image',
        );
      }

      // Check individual quality metrics
      final brightness = _calculateBrightness(image);
      final sharpness = _calculateSharpness(image);
      final contrast = _calculateContrast(image);
      final faceSize = await _calculateFaceSize(photoPath);

      // Determine if quality is good
      bool isGood = true;
      List<String> issues = [];

      if (brightness < 50 || brightness > 200) {
        isGood = false;
        issues.add(brightness < 50 ? '🌑 Too dark' : '🌞 Too bright');
      }

      if (sharpness < 50) {
        isGood = false;
        issues.add('🎲 Too blurry');
      }

      if (contrast < 30) {
        isGood = false;
        issues.add('⚪ Low contrast');
      }

      if (faceSize < 50) {
        isGood = false;
        issues.add('📏 Face too small');
      }

      final reason = isGood
          ? 'Image quality is good ✅'
          : 'Issues: ${issues.join(", ")}';

      if (kDebugMode) {
        debugPrint('📊 Image Quality Results:');
        debugPrint('   Brightness: $brightness (ideal: 80-180)');
        debugPrint('   Sharpness: $sharpness (ideal: >50)');
        debugPrint('   Contrast: $contrast (ideal: >30)');
        debugPrint('   Face Size: $faceSize% (ideal: >50%)');
        debugPrint('   Is Good: $isGood');
        debugPrint('   Reason: $reason');
      }

      return ImageQualityResult(
        isGood: isGood,
        brightness: brightness,
        sharpness: sharpness,
        contrast: contrast,
        faceSize: faceSize,
        reason: reason,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Quality check failed: $e');
      return ImageQualityResult(
        isGood: false,
        brightness: 0,
        sharpness: 0,
        contrast: 0,
        faceSize: 0,
        reason: 'Error: $e',
      );
    }
  }

  /// Calculate brightness (0-255)
  static int _calculateBrightness(img.Image image) {
    int totalBrightness = 0;
    int pixelCount = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixelSafe(x, y);
        final r = _channelToInt(pixel.r);
        final g = _channelToInt(pixel.g);
        final b = _channelToInt(pixel.b);

        // Calculate luminance (standard formula)
        final brightness = (0.299 * r + 0.587 * g + 0.114 * b).toInt();
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    return pixelCount > 0 ? (totalBrightness / pixelCount).toInt() : 0;
  }

  /// Calculate sharpness using Laplacian variance
  static int _calculateSharpness(img.Image image) {
    // Simplified sharpness: check pixel gradient
    int totalGradient = 0;
    int count = 0;

    for (int y = 1; y < image.height - 1; y += 5) {
      for (int x = 1; x < image.width - 1; x += 5) {
        final top = image.getPixelSafe(x, y - 1);
        final bottom = image.getPixelSafe(x, y + 1);
        final left = image.getPixelSafe(x - 1, y);
        final right = image.getPixelSafe(x + 1, y);

        // Calculate gradient magnitude
        final topLum = _getLuminance(top);
        final bottomLum = _getLuminance(bottom);
        final leftLum = _getLuminance(left);
        final rightLum = _getLuminance(right);

        final gradient =
            ((topLum - bottomLum).abs() + (leftLum - rightLum).abs()) ~/ 2;
        totalGradient += gradient;
        count++;
      }
    }

    return count > 0 ? (totalGradient / count).toInt() : 0;
  }

  /// Calculate contrast (standard deviation of pixel values)
  static int _calculateContrast(img.Image image) {
    // Calculate average brightness first
    int totalBrightness = 0;
    int pixelCount = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixelSafe(x, y);
        final brightness = _getLuminance(pixel);
        totalBrightness += brightness;
        pixelCount++;
      }
    }

    final avgBrightness = pixelCount > 0 ? totalBrightness / pixelCount : 128;

    // Calculate variance
    int totalVariance = 0;
    pixelCount = 0;

    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixelSafe(x, y);
        final brightness = _getLuminance(pixel);
        final variance = ((brightness - avgBrightness) * (brightness - avgBrightness))
            .toInt();
        totalVariance += variance;
        pixelCount++;
      }
    }

    final stdDev = pixelCount > 0
        ? (totalVariance / pixelCount).toStringAsFixed(1)
        : '0';
    return int.parse(stdDev.split('.')[0]);
  }

  /// Calculate face size percentage
  static Future<int> _calculateFaceSize(String photoPath) async {
    try {
      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) return 0;

      final face = faces.first;
      final imageWidth = 1.0; // Normalized to 1.0
      final imageHeight = 1.0;

      // Get face bounding box
      final left = face.boundingBox.left / 100; // Convert to percentage
      final right = face.boundingBox.right / 100;
      final top = face.boundingBox.top / 100;
      final bottom = face.boundingBox.bottom / 100;

      final faceWidth = right - left;
      final faceHeight = bottom - top;

      final faceArea = faceWidth * faceHeight;
      final imageArea = imageWidth * imageHeight;

      final facePercentage = (faceArea / imageArea * 100).toInt();

      if (kDebugMode) {
        debugPrint('📏 Face Size: $facePercentage%');
      }

      return facePercentage;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Face size calculation failed: $e');
      return 0;
    }
  }

  /// Get luminance (grayscale value) of a pixel
  static int _getLuminance(dynamic pixel) {
    final r = _channelToInt(pixel.r);
    final g = _channelToInt(pixel.g);
    final b = _channelToInt(pixel.b);
    return (0.299 * r + 0.587 * g + 0.114 * b).toInt();
  }

  static int _channelToInt(num value) {
    if (value.isNaN) return 0;
    return value.round().clamp(0, 255);
  }

  static void dispose() {
    _faceDetector.close();
  }
}

/// Image quality result
class ImageQualityResult {
  final bool isGood;
  final int brightness; // 0-255
  final int sharpness; // 0-100
  final int contrast; // 0-100
  final int faceSize; // 0-100 (percentage)
  final String reason;

  ImageQualityResult({
    required this.isGood,
    required this.brightness,
    required this.sharpness,
    required this.contrast,
    required this.faceSize,
    required this.reason,
  });
}
