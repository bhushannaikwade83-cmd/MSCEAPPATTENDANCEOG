/// Model Training Service
/// Learns from testing data to improve embedding accuracy
/// Uses accumulated embeddings to improve thresholds and model

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelTrainingService {
  static const String _trainDataKey = 'embedding_training_data';
  static const String _metricsKey = 'model_metrics';
  static const String _thresholdKey = 'adaptive_threshold';

  /// Training data structure
  static const int minSamplesForTraining = 10;
  static const int maxStoredSamples = 1000;

  /// Store embedding from registration for training
  static Future<void> recordRegistrationEmbedding(
    String studentId,
    List<double> embedding,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing training data
      final dataJson = prefs.getString(_trainDataKey) ?? '[]';
      final data = List<Map<String, dynamic>>.from(
        jsonDecode(dataJson).map((x) => Map<String, dynamic>.from(x)),
      );

      // Add new embedding
      data.add({
        'student_id': studentId,
        'embedding': embedding,
        'type': 'registration',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'accuracy': 1.0, // Perfect match for registration
      });

      // Keep only recent samples
      if (data.length > maxStoredSamples) {
        data.removeRange(0, data.length - maxStoredSamples);
      }

      // Save
      await prefs.setString(_trainDataKey, jsonEncode(data));

      if (kDebugMode) {
        debugPrint('📊 Recorded registration: ${data.length} total samples');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Training data error: $e');
    }
  }

  /// Record attendance matching result for training
  static Future<void> recordAttendanceMatch(
    String studentId,
    List<double> registrationEmbedding,
    List<double> attendanceEmbedding,
    bool isMatch,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing training data
      final dataJson = prefs.getString(_trainDataKey) ?? '[]';
      final data = List<Map<String, dynamic>>.from(
        jsonDecode(dataJson).map((x) => Map<String, dynamic>.from(x)),
      );

      // Calculate similarity
      final similarity = _cosineSimilarity(registrationEmbedding, attendanceEmbedding);

      // Add training sample
      data.add({
        'student_id': studentId,
        'registration_embedding': registrationEmbedding,
        'attendance_embedding': attendanceEmbedding,
        'type': 'attendance',
        'is_match': isMatch,
        'similarity': similarity,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Keep only recent samples
      if (data.length > maxStoredSamples) {
        data.removeRange(0, data.length - maxStoredSamples);
      }

      // Save
      await prefs.setString(_trainDataKey, jsonEncode(data));

      if (kDebugMode) {
        debugPrint(
          '📊 Attendance recorded: $studentId - ${isMatch ? 'MATCH' : 'NO MATCH'} (${similarity.toStringAsFixed(3)})',
        );
      }

      // Check if we should retrain
      if (data.length >= minSamplesForTraining) {
        await _retrainModel(data);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Attendance recording error: $e');
    }
  }

  /// Retrain model based on accumulated data
  static Future<void> _retrainModel(
    List<Map<String, dynamic>> trainingData,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('🧠 Retraining model with ${trainingData.length} samples...');
      }

      // Analyze attendance data
      final attendanceData =
          trainingData.where((d) => d['type'] == 'attendance').toList();

      if (attendanceData.isEmpty) return;

      // Calculate statistics
      final matches = attendanceData.where((d) => d['is_match'] == true).toList();
      final noMatches = attendanceData.where((d) => d['is_match'] == false).toList();

      // Get similarity scores for matches
      final matchSimilarities =
          matches.map((d) => d['similarity'] as double).toList();
      final noMatchSimilarities =
          noMatches.map((d) => d['similarity'] as double).toList();

      if (matchSimilarities.isEmpty || noMatchSimilarities.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ Insufficient data for retraining');
        }
        return;
      }

      // Calculate optimal threshold
      final avgMatchSimilarity = _average(matchSimilarities);
      final avgNoMatchSimilarity = _average(noMatchSimilarities);
      final optimalThreshold = (avgMatchSimilarity + avgNoMatchSimilarity) / 2;

      if (kDebugMode) {
        debugPrint(
          '📊 Training Analysis:\n'
          '   Matches avg: ${avgMatchSimilarity.toStringAsFixed(3)}\n'
          '   No-matches avg: ${avgNoMatchSimilarity.toStringAsFixed(3)}\n'
          '   Optimal threshold: ${optimalThreshold.toStringAsFixed(3)}',
        );
      }

      // Calculate accuracy with this threshold
      int correct = 0;
      for (final sample in attendanceData) {
        final similarity = sample['similarity'] as double;
        final isMatch = sample['is_match'] as bool;
        final predicted = similarity >= optimalThreshold;

        if (predicted == isMatch) {
          correct++;
        }
      }

      final accuracy = (correct / attendanceData.length) * 100;

      // Save metrics
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_thresholdKey, optimalThreshold);
      await prefs.setString(
        _metricsKey,
        jsonEncode({
          'accuracy': accuracy,
          'samples': attendanceData.length,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'match_avg': avgMatchSimilarity,
          'nomatch_avg': avgNoMatchSimilarity,
        }),
      );

      if (kDebugMode) {
        debugPrint('✅ Model retrained - Accuracy: ${accuracy.toStringAsFixed(1)}%');
        debugPrint('   New optimal threshold: ${optimalThreshold.toStringAsFixed(3)}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Retraining error: $e');
    }
  }

  /// Get adaptive threshold (learns from data)
  static Future<double> getAdaptiveThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final threshold = prefs.getDouble(_thresholdKey);

      if (threshold != null) {
        if (kDebugMode) {
          debugPrint('📊 Using adaptive threshold: ${threshold.toStringAsFixed(3)}');
        }
        return threshold;
      }

      // Default if no training data
      if (kDebugMode) {
        debugPrint('📊 Using default threshold: 0.50');
      }
      return 0.50;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Threshold retrieval error: $e');
      return 0.50;
    }
  }

  /// Get current model metrics
  static Future<Map<String, dynamic>?> getModelMetrics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metricsJson = prefs.getString(_metricsKey);

      if (metricsJson == null) return null;

      return Map<String, dynamic>.from(jsonDecode(metricsJson));
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Metrics retrieval error: $e');
      return null;
    }
  }

  /// Get training progress
  static Future<Map<String, dynamic>> getTrainingProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dataJson = prefs.getString(_trainDataKey) ?? '[]';
      final data = List<Map<String, dynamic>>.from(
        jsonDecode(dataJson).map((x) => Map<String, dynamic>.from(x)),
      );

      final registrations = data.where((d) => d['type'] == 'registration').length;
      final attendances = data.where((d) => d['type'] == 'attendance').length;
      final metrics = await getModelMetrics();

      return {
        'total_samples': data.length,
        'registrations': registrations,
        'attendances': attendances,
        'ready_for_training': data.length >= minSamplesForTraining,
        'current_accuracy': metrics?['accuracy'] ?? 0.0,
        'current_threshold': await getAdaptiveThreshold(),
        'last_updated': metrics?['timestamp'],
      };
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Progress retrieval error: $e');
      return {
        'total_samples': 0,
        'registrations': 0,
        'attendances': 0,
        'ready_for_training': false,
        'current_accuracy': 0.0,
      };
    }
  }

  /// Clear all training data
  static Future<void> clearTrainingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trainDataKey);
      await prefs.remove(_metricsKey);
      await prefs.remove(_thresholdKey);

      if (kDebugMode) {
        debugPrint('✅ Training data cleared');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Clear error: $e');
    }
  }

  // ============================================================================
  // Helper methods
  // ============================================================================

  /// Calculate cosine similarity between two embeddings
  static double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = (normA.isnan || normB.isnan)
        ? 0.0
        : (normA.sqrt() * normB.sqrt());

    return denominator == 0.0 ? 0.0 : (dotProduct / denominator);
  }

  /// Calculate average of list
  static double _average(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }
}
