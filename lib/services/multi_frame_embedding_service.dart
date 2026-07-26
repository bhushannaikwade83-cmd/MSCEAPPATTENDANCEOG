import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'face_recognition_service.dart';

/// Processes multiple video frames to generate a robust face embedding
/// by averaging embeddings from several frames
class MultiFrameEmbeddingService {
  static const int _targetFrameCount = 5; // Number of frames to use

  /// Extract best frames from video frames and generate averaged embedding
  /// frames: List of image bytes from video frames
  /// Returns: Averaged face embedding (192-dim vector)
  static Future<List<double>> generateAveragedEmbedding(
    List<Uint8List> frames,
  ) async {
    if (frames.isEmpty) {
      throw Exception('No frames provided');
    }

    if (kDebugMode) {
      debugPrint('🎬 Processing ${frames.length} frames for embedding...');
    }

    if (kIsWeb) {
      throw Exception('Face embedding not supported on web');
    }

    // Select best frames (evenly distributed across video)
    final selectedFrames = _selectBestFrames(frames, _targetFrameCount);
    if (kDebugMode) {
      debugPrint('✅ Selected ${selectedFrames.length} best frames');
    }

    // Generate embedding for each frame
    final embeddings = <List<double>>[];
    for (int i = 0; i < selectedFrames.length; i++) {
      try {
        final embedding = await _extractEmbeddingFromFrameBytes(selectedFrames[i]);
        if (embedding != null && embedding.isNotEmpty) {
          embeddings.add(embedding);
          if (kDebugMode) {
            debugPrint('   Frame ${i + 1}/${selectedFrames.length}: ✅ Embedding extracted');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('   Frame ${i + 1}/${selectedFrames.length}: ⚠️ Failed - $e');
        }
      }
    }

    if (embeddings.isEmpty) {
      throw Exception('Failed to extract embeddings from any frame');
    }

    // Average all embeddings
    final averaged = _averageEmbeddings(embeddings);
    if (kDebugMode) {
      debugPrint('🧠 Generated averaged embedding from ${embeddings.length} frames');
      debugPrint('   Embedding dimensions: ${averaged.length}');
    }

    return averaged;
  }

  /// Extract embedding from raw image bytes
  /// Saves bytes to temp file, extracts features, then extracts neural embedding
  static Future<List<double>?> _extractEmbeddingFromFrameBytes(Uint8List imageBytes) async {
    try {
      // Save bytes to temp file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/frame_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await tempFile.writeAsBytes(imageBytes);

      try {
        // Extract face features first
        final features = await FaceRecognitionService.extractFaceFeatures(tempFile.path);
        if (features == null) {
          if (kDebugMode) debugPrint('⚠️ Could not extract face features from frame');
          return null;
        }

        // Extract neural embedding
        final embedding = await FaceRecognitionService.extractNeuralEmbedding(
          tempFile.path,
          features,
        );

        return embedding;
      } finally {
        // Clean up temp file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error extracting embedding from frame: $e');
      return null;
    }
  }

  /// Select best frames evenly distributed across video
  /// Picks frames at regular intervals to capture different angles
  static List<Uint8List> _selectBestFrames(
    List<Uint8List> allFrames,
    int targetCount,
  ) {
    if (allFrames.length <= targetCount) {
      return allFrames;
    }

    final selected = <Uint8List>[];
    final interval = allFrames.length ~/ targetCount;

    for (int i = 0; i < targetCount; i++) {
      final index = (i * interval).clamp(0, allFrames.length - 1);
      selected.add(allFrames[index]);
    }

    return selected;
  }

  /// Average multiple embeddings to create a robust combined embedding
  /// All embeddings should be L2-normalized (cosine similarity compatible)
  static List<double> _averageEmbeddings(List<List<double>> embeddings) {
    if (embeddings.isEmpty) {
      return [];
    }

    final embeddingDim = embeddings[0].length;
    final averaged = List<double>.filled(embeddingDim, 0.0);

    // Sum all embeddings
    for (final embedding in embeddings) {
      for (int i = 0; i < embeddingDim; i++) {
        averaged[i] += embedding[i];
      }
    }

    // Average
    for (int i = 0; i < embeddingDim; i++) {
      averaged[i] /= embeddings.length;
    }

    // Re-normalize to unit length (L2 normalization)
    return _normalizeEmbedding(averaged);
  }

  /// L2 normalize embedding to unit vector
  static List<double> _normalizeEmbedding(List<double> embedding) {
    double sumSquares = 0.0;
    for (final val in embedding) {
      sumSquares += val * val;
    }

    if (sumSquares == 0) return embedding;

    final norm = sqrt(sumSquares);
    return embedding.map((val) => val / norm).toList();
  }
}
