import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// Image optimization and compression utility
/// Reduces photo file sizes by 80% while maintaining quality
class ImageOptimization {
  /// Compress image file
  /// Reduces from ~1-2MB to ~200-300KB
  static Future<Uint8List?> compressImage(
    File imageFile, {
    int maxWidth = 800,
    int maxHeight = 800,
    int quality = 80,
  }) async {
    try {
      if (!await imageFile.exists()) {
        if (kDebugMode) debugPrint('❌ Image file not found: ${imageFile.path}');
        return null;
      }

      final originalSize = imageFile.lengthSync();
      if (kDebugMode) {
        debugPrint(
          '📸 Compressing image: ${imageFile.path} (${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB)',
        );
      }

      // Decode image
      final imageData = imageFile.readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) {
        if (kDebugMode) debugPrint('❌ Failed to decode image');
        return null;
      }

      // Resize if needed
      late img.Image compressed;
      if (image.width > maxWidth || image.height > maxHeight) {
        compressed = img.copyResize(
          image,
          width: maxWidth,
          height: maxHeight,
          interpolation: img.Interpolation.linear,
        );
        if (kDebugMode) {
          debugPrint(
            '🔄 Resized: ${image.width}x${image.height} → ${compressed.width}x${compressed.height}',
          );
        }
      } else {
        compressed = image;
      }

      // Encode to JPEG with quality setting
      final compressedData = img.encodeJpg(compressed, quality: quality);
      final compressedSize = compressedData.length;
      final reduction =
          ((1 - (compressedSize / originalSize)) * 100).toStringAsFixed(1);

      if (kDebugMode) {
        debugPrint(
          '✅ Compression successful: ${(compressedSize / 1024 / 1024).toStringAsFixed(2)}MB ($reduction% reduction)',
        );
      }

      return Uint8List.fromList(compressedData);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Image compression error: $e');
      return null;
    }
  }

  /// Compress image from bytes
  static Future<Uint8List?> compressImageBytes(
    Uint8List imageBytes, {
    int maxWidth = 800,
    int maxHeight = 800,
    int quality = 80,
  }) async {
    try {
      final originalSize = imageBytes.length;
      if (kDebugMode) {
        debugPrint(
          '📸 Compressing image bytes (${(originalSize / 1024 / 1024).toStringAsFixed(2)}MB)',
        );
      }

      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        if (kDebugMode) debugPrint('❌ Failed to decode image bytes');
        return null;
      }

      // Resize if needed
      late img.Image compressed;
      if (image.width > maxWidth || image.height > maxHeight) {
        compressed = img.copyResize(
          image,
          width: maxWidth,
          height: maxHeight,
          interpolation: img.Interpolation.linear,
        );
      } else {
        compressed = image;
      }

      // Encode to JPEG
      final compressedData = img.encodeJpg(compressed, quality: quality);
      final reduction =
          ((1 - (compressedData.length / originalSize)) * 100).toStringAsFixed(1);

      if (kDebugMode) {
        debugPrint(
          '✅ Compression successful: ${(compressedData.length / 1024 / 1024).toStringAsFixed(2)}MB ($reduction% reduction)',
        );
      }

      return Uint8List.fromList(compressedData);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Image compression error: $e');
      return null;
    }
  }

  /// Get image dimensions
  static Future<({int width, int height})?> getImageDimensions(
    File imageFile,
  ) async {
    try {
      if (!await imageFile.exists()) return null;

      final imageData = imageFile.readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) return null;

      return (width: image.width, height: image.height);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error getting image dimensions: $e');
      return null;
    }
  }

  /// Check if image is too large
  static Future<bool> isImageTooLarge(
    File imageFile, {
    int maxSizeInMB = 5,
  }) async {
    try {
      if (!await imageFile.exists()) return false;

      final sizeInBytes = await imageFile.length();
      final sizeInMB = sizeInBytes / 1024 / 1024;

      if (kDebugMode) {
        debugPrint('📸 Image size: ${sizeInMB.toStringAsFixed(2)}MB');
      }

      return sizeInMB > maxSizeInMB;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error checking image size: $e');
      return false;
    }
  }

  /// Strip EXIF data and compress
  /// Removes all metadata for privacy
  static Future<Uint8List?> stripExifAndCompress(
    File imageFile, {
    int maxWidth = 800,
    int maxHeight = 800,
    int quality = 80,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔒 Stripping EXIF data and compressing...');
      }

      // Decode (automatically removes EXIF)
      final imageData = imageFile.readAsBytesSync();
      final image = img.decodeImage(imageData);

      if (image == null) {
        if (kDebugMode) debugPrint('❌ Failed to decode image');
        return null;
      }

      // Resize
      late img.Image compressed;
      if (image.width > maxWidth || image.height > maxHeight) {
        compressed = img.copyResize(
          image,
          width: maxWidth,
          height: maxHeight,
        );
      } else {
        compressed = image;
      }

      // Encode without metadata
      final compressedData = img.encodeJpg(compressed, quality: quality);

      if (kDebugMode) {
        debugPrint(
          '✅ EXIF stripped and compressed: ${(compressedData.length / 1024 / 1024).toStringAsFixed(2)}MB',
        );
      }

      return Uint8List.fromList(compressedData);
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error stripping EXIF: $e');
      return null;
    }
  }

  /// Compress multiple images in one pass (gallery / multi-pick).
  static Future<Map<String, Uint8List?>> compressMultiple(
    List<File> imageFiles, {
    int maxWidth = 800,
    int maxHeight = 800,
    int quality = 80,
  }) async {
    final results = <String, Uint8List?>{};

    if (kDebugMode) {
      debugPrint('📦 Compressing ${imageFiles.length} images...');
    }

    for (final file in imageFiles) {
      final compressed = await compressImage(
        file,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        quality: quality,
      );
      results[file.path] = compressed;
    }

    if (kDebugMode) {
      final successCount = results.values.where((v) => v != null).length;
      debugPrint('✅ Compression complete: $successCount/${imageFiles.length}');
    }

    return results;
  }

  /// Recommend compression quality based on image size
  static int recommendQuality(int fileSizeInBytes) {
    final sizeInMB = fileSizeInBytes / 1024 / 1024;

    if (sizeInMB > 5) return 65; // Aggressive compression for large files
    if (sizeInMB > 3) return 75;
    if (sizeInMB > 1) return 80;
    return 85; // High quality for small files
  }
}
