import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, kDebugMode, debugPrint;
import 'package:image/image.dart' as img;

/// Tunables shared with the isolate [must be compile-time for worker].
const int _maxKb = 95;

/// CPU-heavy work runs in a [compute] isolate so the UI thread keeps scrolling/animating.
Uint8List _compressPhotoBytesWorker(Uint8List photoBytes) {
  try {
    final image = img.decodeImage(photoBytes);
    if (image == null) {
      return photoBytes;
    }

    // Always bake orientation and re-encode to a standard sequential JPEG.
    // This prevents Android Skia/libjpeg error 122 from camera files that are
    // technically JPEGs but have problematic SOS markers or orientation data.
    final normalized = img.bakeOrientation(image);

    var quality = 90;
    var compressed = img.encodeJpg(normalized, quality: quality);

    while (compressed.length > _maxKb * 1024 && quality > 35) {
      quality -= 5;
      compressed = img.encodeJpg(normalized, quality: quality);
    }

    if (compressed.length > _maxKb * 1024) {
      var scale = 0.7;
      while (compressed.length > _maxKb * 1024 && scale > 0.15) {
        final width = (normalized.width * scale).toInt();
        final height = (normalized.height * scale).toInt();
        var resized = img.copyResize(normalized, width: width, height: height);
        var resizeQuality = 70;
        compressed = img.encodeJpg(resized, quality: resizeQuality);
        while (compressed.length > _maxKb * 1024 && resizeQuality > 35) {
          resizeQuality -= 5;
          compressed = img.encodeJpg(resized, quality: resizeQuality);
        }
        scale -= 0.08;
      }
    }

    return Uint8List.fromList(compressed);
  } catch (_) {
    return photoBytes;
  }
}

/// Isolate worker for generating tiny Base64 thumbnails.
String _createTinyThumbnailWorker(Uint8List photoBytes) {
  try {
    final image = img.decodeImage(photoBytes);
    if (image == null) return '';
    final thumbnail = img.copyResize(image, width: 50);
    final compressed = img.encodeJpg(thumbnail, quality: 35);
    return base64Encode(compressed);
  } catch (e) {
    return '';
  }
}

/// Photo Compression Service
/// Compresses photos to stay safely under 100KB while keeping enough detail
/// for attendance evidence and face-related workflows.
class PhotoCompressionService {
  static const int MIN_KB = 35;
  static const int MAX_KB = 95;
  static const int TARGET_KB = 70;

  /// Compress photo bytes directly to target size (50-100KB)
  static Future<Uint8List> compressPhotoBytes(Uint8List photoBytes) async {
    try {
      if (kDebugMode) {
        debugPrint('🗜️ Starting photo bytes normalization/compression (background isolate)...');
        debugPrint('   Original size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
      }
      final out = await compute(_compressPhotoBytesWorker, photoBytes);
      if (kDebugMode) {
        debugPrint('✅ Normalization/compression complete: ${(out.length / 1024).toStringAsFixed(2)} KB');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Compression failed: $e');
      return photoBytes;
    }
  }

  /// Compress photo to target size (roughly 35-95KB)
  static Future<Uint8List> compressPhoto(String photoPath) async {
    try {
      if (kDebugMode) {
        debugPrint('🗜️ Starting photo compression (background isolate)...');
      }
      final file = File(photoPath);
      final bytes = await file.readAsBytes();
      if (kDebugMode) {
        debugPrint('   Original size: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
      }
      final out = await compute(_compressPhotoBytesWorker, bytes);
      if (kDebugMode) {
        debugPrint('✅ Normalization/compression complete: ${(out.length / 1024).toStringAsFixed(2)} KB');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Compression failed: $e');
      return await File(photoPath).readAsBytes();
    }
  }

  /// Creates a tiny Base64 thumbnail for instant DB loading.
  static Future<String> createTinyThumbnail(Uint8List photoBytes) async {
    return await compute(_createTinyThumbnailWorker, photoBytes);
  }

  /// Compress and validate photo size
  static Future<CompressedPhotoResult> compressAndValidate(
      String photoPath) async {
    try {
      final compressed = await compressPhoto(photoPath);
      final sizeKB = compressed.length / 1024;

      final isValid =
          compressed.length >= MIN_KB * 1024 &&
          compressed.length <= MAX_KB * 1024;

      if (kDebugMode) {
        debugPrint('📊 Compression Result:');
        debugPrint('   Size: ${sizeKB.toStringAsFixed(2)} KB');
        debugPrint('   Valid: $isValid (Target: $MIN_KB-$MAX_KB KB, hard goal under 100KB)');
      }

      return CompressedPhotoResult(
        bytes: compressed,
        sizeKB: sizeKB,
        isValid: isValid,
        reason: isValid
            ? 'Photo compressed successfully ✅'
            : 'Size out of range: ${sizeKB.toStringAsFixed(2)} KB',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Validation failed: $e');
      return CompressedPhotoResult(
        bytes: Uint8List(0),
        sizeKB: 0,
        isValid: false,
        reason: 'Error: $e',
      );
    }
  }
}

/// Compressed photo result
class CompressedPhotoResult {
  final Uint8List bytes;
  final double sizeKB;
  final bool isValid; // true if 50-100KB
  final String reason;

  CompressedPhotoResult({
    required this.bytes,
    required this.sizeKB,
    required this.isValid,
    required this.reason,
  });
}
