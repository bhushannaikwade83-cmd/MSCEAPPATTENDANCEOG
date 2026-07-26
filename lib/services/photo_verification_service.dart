import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:exif/exif.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

/// Service for photo verification and anti-fraud checks
/// Verifies EXIF data, detects screenshots, checks timestamps, adds watermarks
class PhotoVerificationService {
  static FaceDetector? _faceDetectorInstance;

  static FaceDetector get _faceDetector {
    _faceDetectorInstance ??= FaceDetector(
      options: FaceDetectorOptions(
        enableContours: false,
        enableClassification: false,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    return _faceDetectorInstance!;
  }

  /// Verify photo metadata and detect fraud
  static Future<Map<String, dynamic>> verifyPhoto({
    required String photoPath,
    required DateTime markingTime,
    required String? expectedLocation,
  }) async {
    final verification = <String, dynamic>{
      'isValid': true,
      'warnings': <String>[],
      'errors': <String>[],
      'metadata': <String, dynamic>{},
    };

    try {
      // 1. Check if file exists
      final file = File(photoPath);
      if (!await file.exists()) {
        verification['isValid'] = false;
        verification['errors'].add('Photo file not found');
        return verification;
      }

      // 2. Extract EXIF data
      final exifData = await _extractExifData(photoPath);
      verification['metadata'] = exifData;

      // 3. Verify timestamp
      final timestampCheck = _verifyTimestamp(exifData, markingTime);
      if (!timestampCheck['isValid']) {
        verification['warnings'].addAll(timestampCheck['warnings']);
        if (timestampCheck['isCritical'] == true) {
          verification['isValid'] = false;
          verification['errors'].addAll(timestampCheck['warnings']);
        }
      }

      // 4. Detect screenshot
      final isScreenshot = _detectScreenshot(exifData);
      if (isScreenshot) {
        verification['isValid'] = false;
        verification['errors'].add('Screenshot detected - must use live camera');
      }

      // 5. Verify location (if provided)
      if (expectedLocation != null) {
        final locationCheck = _verifyLocation(exifData, expectedLocation);
        if (!locationCheck['isValid']) {
          verification['warnings'].add('Location mismatch detected');
        }
      }

      // 6. Check file write time vs reference time (both should be immediate after capture)
      final fileTime = await file.lastModified();
      final ageDifference = markingTime.difference(fileTime).abs();
      if (ageDifference.inMinutes > 15) {
        verification['warnings'].add(
          'Photo file time differs from capture clock by ${ageDifference.inMinutes} min — verify device time is correct',
        );
      }

      if (kDebugMode) {
        debugPrint('📸 Photo Verification:');
        debugPrint('   Valid: ${verification['isValid']}');
        debugPrint('   Warnings: ${verification['warnings'].length}');
        debugPrint('   Errors: ${verification['errors'].length}');
      }

      return verification;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error verifying photo: $e');
      verification['isValid'] = false;
      verification['errors'].add('Verification error: $e');
      return verification;
    }
  }

  /// Extract EXIF metadata from photo
  static Future<Map<String, dynamic>> _extractExifData(String photoPath) async {
    try {
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      final exifData = await readExifFromBytes(bytes);

      final Map<String, dynamic> metadata = {};

      // Extract common EXIF fields
      if (exifData.isNotEmpty) {
        metadata['hasExif'] = true;
        metadata['make'] = exifData['Image Make']?.toString();
        metadata['model'] = exifData['Image Model']?.toString();
        metadata['dateTime'] = exifData['Image DateTime']?.toString();
        metadata['dateTimeOriginal'] = exifData['EXIF DateTimeOriginal']?.toString();
        metadata['dateTimeDigitized'] = exifData['EXIF DateTimeDigitized']?.toString();
        
        // GPS data
        if (exifData.containsKey('GPS GPSLatitude') && 
            exifData.containsKey('GPS GPSLongitude')) {
          metadata['latitude'] = exifData['GPS GPSLatitude'];
          metadata['longitude'] = exifData['GPS GPSLongitude'];
        }

        // Camera settings
        metadata['orientation'] = exifData['Image Orientation']?.toString();
        metadata['software'] = exifData['Image Software']?.toString();
      } else {
        metadata['hasExif'] = false;
        metadata['warning'] = 'No EXIF data found - possible screenshot or edited image';
      }

      return metadata;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting EXIF: $e');
      return {'hasExif': false, 'error': e.toString()};
    }
  }

  /// Verify photo timestamp matches marking time
  static Map<String, dynamic> _verifyTimestamp(
    Map<String, dynamic> exifData,
    DateTime markingTime,
  ) {
    final result = <String, dynamic>{
      'isValid': true,
      'isCritical': false,
      'warnings': <String>[],
    };

    if (!exifData['hasExif']) {
      result['warnings'].add('No EXIF timestamp available');
      return result;
    }

    DateTime? photoTime;
    final dateTimeStr = exifData['dateTimeOriginal'] ?? exifData['dateTime'];
    
    if (dateTimeStr != null) {
      try {
        // Parse EXIF datetime format: "YYYY:MM:DD HH:MM:SS"
        final parts = dateTimeStr.toString().split(' ');
        if (parts.length == 2) {
          final dateParts = parts[0].split(':');
          final timeParts = parts[1].split(':');
          if (dateParts.length == 3 && timeParts.length == 3) {
            photoTime = DateTime(
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
              int.parse(dateParts[2]),
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
              int.parse(timeParts[2]),
            );
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('❌ Error parsing EXIF timestamp: $e');
      }
    }

    if (photoTime != null) {
      // EXIF DateTime is wall-clock with no timezone; [markingTime] must be taken right after capture
      // (device `DateTime.now()`). Allow slack for camera processing / compression on slow devices.
      final timeDifference = markingTime.difference(photoTime).abs();
      const criticalAfter = Duration(minutes: 12);
      const warnAfter = Duration(minutes: 3);

      if (timeDifference > criticalAfter) {
        result['isValid'] = false;
        result['isCritical'] = true;
        result['warnings'].add(
          'Photo timestamp (${DateFormat('HH:mm:ss').format(photoTime)}) '
          'does not match capture time (${DateFormat('HH:mm:ss').format(markingTime)}) '
          '— difference: ${timeDifference.inMinutes} min (check device date & time is set automatically)',
        );
      } else if (timeDifference > warnAfter) {
        result['warnings'].add(
          'Photo timestamp differs from capture time by ${timeDifference.inMinutes} min',
        );
      }
    } else {
      result['warnings'].add('Could not extract photo timestamp from EXIF');
    }

    return result;
  }

  /// Detect if photo is a screenshot
  static bool _detectScreenshot(Map<String, dynamic> exifData) {
    // Screenshots typically have:
    // 1. No EXIF data or minimal EXIF
    // 2. No camera make/model
    // 3. Software field contains "screenshot" or similar
    // 4. No GPS data
    
    if (!exifData['hasExif']) {
      return true; // High probability of screenshot
    }

    final software = exifData['software']?.toString().toLowerCase() ?? '';
    if (software.contains('screenshot') || 
        software.contains('screen') ||
        software.contains('capture')) {
      return true;
    }

    // No camera make/model suggests screenshot
    if (exifData['make'] == null && exifData['model'] == null) {
      return true;
    }

    return false;
  }

  /// Verify location from EXIF GPS data
  static Map<String, dynamic> _verifyLocation(
    Map<String, dynamic> exifData,
    String expectedLocation,
  ) {
    // This is a simplified check - you'd need to parse expectedLocation
    // and compare with GPS coordinates from EXIF
    return {
      'isValid': true,
      'warnings': <String>[],
    };
  }

  /// Add timestamp watermark to photo
  /// Note: Watermarking is simplified - full text overlay requires additional packages
  /// For now, metadata is stored in Firestore which serves the same purpose
  static Future<Uint8List> addTimestampWatermark({
    required Uint8List imageBytes,
    required DateTime timestamp,
    required String rollNumber,
    required String subject,
  }) async {
    try {
      // For now, return original image
      // Watermark data is stored in Firestore metadata which is more reliable
      // To add visual watermark, consider using packages like:
      // - image_editor or flutter_image_editor for text overlay
      // - Or use server-side watermarking
      
      if (kDebugMode) {
        final dateStr = DateFormat('yyyy-MM-dd').format(timestamp);
        final timeStr = DateFormat('HH:mm:ss').format(timestamp);
        debugPrint('✅ Watermark metadata: $dateStr $timeStr | Roll: $rollNumber | $subject');
        debugPrint('   (Visual watermark can be added with image_editor package)');
      }

      // Return original - metadata is stored in Firestore
      return imageBytes;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error in watermark function: $e');
      return imageBytes;
    }
  }

  /// Detect multiple faces in photo (group photo detection)
  static Future<Map<String, dynamic>> detectMultipleFaces(String photoPath) async {
    try {
      if (kIsWeb) {
        return {'faceCount': 0, 'isGroupPhoto': false};
      }

      final inputImage = InputImage.fromFilePath(photoPath);
      final faces = await _faceDetector.processImage(inputImage);

      final result = {
        'faceCount': faces.length,
        'isGroupPhoto': faces.length > 1,
        'faces': faces.map((face) => {
          'boundingBox': {
            'left': face.boundingBox.left,
            'top': face.boundingBox.top,
            'width': face.boundingBox.width,
            'height': face.boundingBox.height,
          },
        }).toList(),
      };

      if (kDebugMode) {
        debugPrint('👥 Face Detection: ${faces.length} face(s) detected');
        if (faces.length > 1) {
          debugPrint('⚠️ Group photo detected - may indicate misuse');
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error detecting faces: $e');
      return {'faceCount': 0, 'isGroupPhoto': false, 'error': e.toString()};
    }
  }

  /// Detect blur in photo using Laplacian variance
  /// Returns true if photo is blurry, false if sharp
  static Future<bool> detectBlur(Uint8List imageBytes) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return true; // Consider unreadable as blurry

      // Sample a portion of the image for better performance
      // Check center region and edges for better accuracy
      final sampleStep = math.max(2, (image.width / 200).round()); // Sample every Nth pixel
      double variance = 0;
      int count = 0;

      // Sample center region (most important for face photos)
      final centerX = image.width ~/ 2;
      final centerY = image.height ~/ 2;
      final sampleSize = math.min(200, image.width ~/ 2);
      
      final startX = math.max(1, centerX - sampleSize ~/ 2);
      final endX = math.min(image.width - 1, centerX + sampleSize ~/ 2);
      final startY = math.max(1, centerY - sampleSize ~/ 2);
      final endY = math.min(image.height - 1, centerY + sampleSize ~/ 2);

      for (var y = startY; y < endY; y += sampleStep) {
        for (var x = startX; x < endX; x += sampleStep) {
          final center = img.getLuminance(image.getPixel(x, y)).toDouble();
          final right = img.getLuminance(image.getPixel(x + 1, y)).toDouble();
          final bottom = img.getLuminance(image.getPixel(x, y + 1)).toDouble();
          
          // Calculate Laplacian (second derivative approximation)
          final diff = (center - right).abs() + (center - bottom).abs();
          variance += diff * diff;
          count++;
        }
      }

      if (count == 0) return false; // Can't determine, assume not blurry
      
      variance /= count;
      
      // Adjusted threshold: variance < 15 is considered blurry
      // Lowered from 30 to 15 to reduce false positives for selfies
      // Clear photos typically have variance > 15
      // Selfies may have slightly lower variance due to front camera quality
      final isBlurry = variance < 15;
      
      if (kDebugMode) {
        debugPrint('📸 Blur Detection: variance=${variance.toStringAsFixed(2)}, isBlurry=$isBlurry, imageSize=${image.width}x${image.height}');
      }

      return isBlurry;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error detecting blur: $e');
      return false; // Assume not blurry on error (less strict)
    }
  }

  /// Detect if photo is a photo-of-photo (someone taking a photo of a student's photo)
  /// This prevents cheating by taking photos of photos instead of live photos
  static Future<bool> detectPhotoOfPhoto(String photoPath) async {
    try {
      if (kIsWeb) return false; // Skip on web

      // Load image
      final file = File(photoPath);
      if (!await file.exists()) return false;

      final imageBytes = await file.readAsBytes();
      final image = img.decodeImage(imageBytes);
      if (image == null) return false;

      // Method 1: Check for rectangular edges/frames (photo frames)
      // Photos of photos often have visible rectangular borders or frames
      // NOTE: Don't return immediately - collect all indicators first
      final edgeDetection = _detectRectangularEdges(image);

      // Method 2: Check for uniform lighting (photos of photos often have uniform lighting)
      final lightingCheck = _checkLightingUniformity(image);

      // Method 3: Check for compression artifacts (double compression)
      // Photos of photos often have double compression artifacts
      final compressionCheck = _checkDoubleCompression(imageBytes);

      // Method 4: Check for reflections/glare (screen reflections)
      final reflectionCheck = _checkReflections(image);

      // Method 5: Check image sharpness vs expected sharpness
      // Photos of photos are often less sharp than direct camera photos
      final sharpnessCheck = _checkSharpness(image);

      // Method 6: Additional check - if multiple methods suggest photo-of-photo, be more strict
      // Count how many indicators we found
      int suspiciousIndicators = 0;
      if (edgeDetection['hasRectangularFrame']) suspiciousIndicators++;
      if (lightingCheck['isTooUniform']) suspiciousIndicators++;
      if (compressionCheck['hasDoubleCompression']) suspiciousIndicators++;
      if (reflectionCheck['hasReflections']) suspiciousIndicators++;
      if (sharpnessCheck['isTooBlurry']) suspiciousIndicators++;

      // ⚠️ STRICT MODE: Even ONE strong signal from rectangular frame or lighting uniformity should block
      // These are strong indicators of passport photos or printed photos
      if (edgeDetection['hasRectangularFrame'] == true) {
        if (kDebugMode) {
          debugPrint('⚠️ Photo-of-photo BLOCKED: Rectangular frame detected (passport/printed photo)');
        }
        return true;
      }

      // Two or more other indicators is enough to block
      if (suspiciousIndicators >= 2) {
        if (kDebugMode) {
          debugPrint('⚠️ Photo-of-photo detected: indicators=$suspiciousIndicators');
        }
        return true;
      }

      if (kDebugMode && suspiciousIndicators > 0) {
        debugPrint('ℹ️ Photo-of-photo check: $suspiciousIndicators indicator(s), need 2+ to block');
      }

      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error detecting photo-of-photo: $e');
      // On error, assume it's a normal photo (less strict to avoid false positives)
      return false; // Allow on error to avoid blocking legitimate photos
    }
  }

  /// Detect rectangular edges/frames that might indicate a photo frame
  static Map<String, dynamic> _detectRectangularEdges(img.Image image) {
    // Check for strong horizontal and vertical edges near image borders
    // Photos of photos often have visible rectangular borders
    // Increased sensitivity for laptop/phone screens
    final borderWidth = (image.width * 0.08).round(); // Check 8% border (increased from 5%)
    int horizontalEdges = 0;
    int verticalEdges = 0;

    // Check top and bottom borders for horizontal edges
    for (var y = 0; y < borderWidth && y < image.height; y++) {
      for (var x = borderWidth; x < image.width - borderWidth; x++) {
        final pixel = image.getPixel(x, y);
        final nextPixel = image.getPixel(x, y + 1);
        final diff = (img.getLuminance(pixel).toDouble() - img.getLuminance(nextPixel).toDouble()).abs();
        if (diff > 30) horizontalEdges++; // Lower threshold (30 instead of 50) for better detection
      }
    }

    for (var y = image.height - borderWidth; y < image.height; y++) {
      for (var x = borderWidth; x < image.width - borderWidth; x++) {
        final pixel = image.getPixel(x, y);
        final prevPixel = image.getPixel(x, y - 1);
        final diff = (img.getLuminance(pixel).toDouble() - img.getLuminance(prevPixel).toDouble()).abs();
        if (diff > 30) horizontalEdges++; // Lower threshold for better detection
      }
    }

    // Check left and right borders for vertical edges
    for (var x = 0; x < borderWidth && x < image.width; x++) {
      for (var y = borderWidth; y < image.height - borderWidth; y++) {
        final pixel = image.getPixel(x, y);
        final nextPixel = image.getPixel(x + 1, y);
        final diff = (img.getLuminance(pixel).toDouble() - img.getLuminance(nextPixel).toDouble()).abs();
        if (diff > 30) verticalEdges++; // Lower threshold for better detection
      }
    }

    for (var x = image.width - borderWidth; x < image.width; x++) {
      for (var y = borderWidth; y < image.height - borderWidth; y++) {
        final pixel = image.getPixel(x, y);
        final prevPixel = image.getPixel(x - 1, y);
        final diff = (img.getLuminance(pixel).toDouble() - img.getLuminance(prevPixel).toDouble()).abs();
        if (diff > 30) verticalEdges++; // Lower threshold for better detection
      }
    }

    // If we have many edges near borders, it might be a photo frame
    final totalBorderPixels = (borderWidth * image.width * 2) + (borderWidth * image.height * 2);
    final edgeRatio = (horizontalEdges + verticalEdges) / totalBorderPixels;

    // STRICTER detection for passport photos and printed images
    // Passport photos have strong rectangular frames with clear borders
    // Lowered threshold from 0.30 to 0.15 for better detection of printed/passport photos
    return {
      'hasRectangularFrame': edgeRatio > 0.15,
    };
  }

  /// Check if lighting is too uniform (indicates photo of photo)
  static Map<String, dynamic> _checkLightingUniformity(img.Image image) {
    // Sample multiple regions and check variance
    final sampleSize = 50;
    final samples = <double>[];
    
    for (var i = 0; i < 20; i++) {
      final x = (i * image.width / 20).round();
      final y = (i * image.height / 20).round();
      if (x < image.width && y < image.height) {
        final pixel = image.getPixel(x, y);
        samples.add(img.getLuminance(pixel).toDouble());
      }
    }

    if (samples.isEmpty) return {'isTooUniform': false};

    // Calculate variance
    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance = samples.map((s) => (s - mean) * (s - mean)).reduce((a, b) => a + b) / samples.length;

    // Very low variance indicates uniform lighting (photo of photo)
    // Less strict - normal photos can have somewhat uniform lighting
    return {
      'isTooUniform': variance < 80, // Decreased threshold (80 instead of 150) to reduce false positives
    };
  }

  /// Check for double compression artifacts
  static Map<String, dynamic> _checkDoubleCompression(Uint8List imageBytes) {
    // Photos of photos often have double JPEG compression artifacts
    // This is a simplified check - full analysis would require DCT analysis
    
    // Check file size vs expected size
    // Double-compressed images often have unusual compression ratios
    final size = imageBytes.length;
    
    // Very small file size for a photo might indicate double compression
    // (though this is not definitive)
    return {
      'hasDoubleCompression': false, // Simplified - can be enhanced
    };
  }

  /// Check for screen reflections/glare
  static Map<String, dynamic> _checkReflections(img.Image image) {
    // Check for bright spots that might indicate screen glare
    final brightSpots = <int>[];
    
    // Sample center region for bright spots
    final centerX = image.width ~/ 2;
    final centerY = image.height ~/ 2;
    final regionSize = (image.width * 0.3).round();
    
    for (var y = centerY - regionSize; y < centerY + regionSize && y < image.height; y++) {
      if (y < 0) continue;
      for (var x = centerX - regionSize; x < centerX + regionSize && x < image.width; x++) {
        if (x < 0) continue;
        final pixel = image.getPixel(x, y);
        final luminance = img.getLuminance(pixel).toDouble();
        if (luminance > 240) { // Very bright pixel
          brightSpots.add(1);
        }
      }
    }

    final brightRatio = brightSpots.length / (regionSize * regionSize * 4);
    
    // Less strict - normal photos can have some bright spots
    return {
      'hasReflections': brightRatio > 0.25, // Increased threshold (25% instead of 10%) to reduce false positives
    };
  }

  /// Check image sharpness
  static Map<String, dynamic> _checkSharpness(img.Image image) {
    // Calculate Laplacian variance (same as blur detection)
      double variance = 0;
      int count = 0;

      for (var y = 1; y < image.height - 1; y++) {
        for (var x = 1; x < image.width - 1; x++) {
        final center = img.getLuminance(image.getPixel(x, y)).toDouble();
        final right = img.getLuminance(image.getPixel(x + 1, y)).toDouble();
        final bottom = img.getLuminance(image.getPixel(x, y + 1)).toDouble();
          
          final diff = (center - right).abs() + (center - bottom).abs();
          variance += diff * diff;
          count++;
        }
      }

      variance /= count;
      
    // Photos of photos are often less sharp
    // Less strict - normal selfies can have some blur
    return {
      'isTooBlurry': variance < 40, // Decreased threshold (40 instead of 80) to reduce false positives
    };
  }
}
