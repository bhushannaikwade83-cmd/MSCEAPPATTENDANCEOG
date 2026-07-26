import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import '../core/gps_attendance_constants.dart';

/// Result of comparing the device position to a locked fence point.
class GpsFenceSampleResult {
  const GpsFenceSampleResult({
    required this.isWithinFence,
    required this.bestDistanceMeters,
    required this.accuracyUsedForMessage,
    this.mockedDetected = false,
    this.errorMessage,
    this.samplesCollected = 0,
    this.samplesUsed = 0,
  });

  final bool isWithinFence;
  /// Smallest distance to the fence center across successful samples (meters).
  final double bestDistanceMeters;
  /// Reported accuracy (meters) for the sample that produced [bestDistanceMeters], when known.
  final double accuracyUsedForMessage;
  final bool mockedDetected;
  final String? errorMessage;
  /// Number of GPS samples collected.
  final int samplesCollected;
  /// Number of GPS samples used after filtering.
  final int samplesUsed;
}

/// Takes several GPS readings and rejects weak fixes.
/// Strict mode for attendance:
/// - live GPS samples only
/// - hard-block mocked positions
/// - ignore weak/low-confidence fixes
/// - apply only a small accuracy buffer
Future<GpsFenceSampleResult> samplePositionAgainstFence({
  required double fenceLat,
  required double fenceLng,
  double radiusMeters = kAttendanceFenceRadiusMeters,
  int maxSamples = 7,
  Duration delayBetweenSamples = const Duration(milliseconds: 1200),
  int firstSampleTimeoutSeconds = 16,
  int laterSampleTimeoutSeconds = 12,
  /// Extra wait before samples after the first so the chip can refine a fix (indoor).
  /// Use a shorter value only for "fast" attendance flows where total time matters.
  Duration preSampleStabilizationDelay = const Duration(milliseconds: 2500),
  bool tryRecentLastKnownFirst = false,
  Duration lastKnownMaxAge = const Duration(minutes: 3),
}) async {
  // Pre-checks: fail fast with clear actionable messages.
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage: 'Location services are OFF. Please enable GPS and try again.',
    );
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever ||
      permission == LocationPermission.denied) {
    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage:
          'Location permission is required. Allow location access, then try again.',
    );
  }

  if (tryRecentLastKnownFirst) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last?.isMocked == true) {
        return const GpsFenceSampleResult(
          isWithinFence: false,
          bestDistanceMeters: 0,
          accuracyUsedForMessage: 0,
          mockedDetected: true,
        );
      }
      if (last != null && !last.isMocked) {
        final age = DateTime.now().difference(last.timestamp);
        if (!age.isNegative && age <= lastKnownMaxAge) {
          final d = Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            fenceLat,
            fenceLng,
          );
          final rawAcc = last.accuracy > 0 ? last.accuracy : 35.0;
          final effectiveRadius = attendanceEffectiveFenceRadiusMeters(
            rawAcc,
            nominalRadiusMeters: radiusMeters,
          );
          if (d <= effectiveRadius) {
            return GpsFenceSampleResult(
              isWithinFence: true,
              bestDistanceMeters: d,
              accuracyUsedForMessage:
                  last.accuracy > 0 ? last.accuracy : rawAcc,
              samplesCollected: 1,
              samplesUsed: 1,
            );
          }
        }
      }
    } catch (_) {}
  }

  List<double> distances = [];
  List<double> accuracies = [];
  double bestDistance = double.infinity;
  double? bestAccuracy;

  // **BEST PRACTICE**: Rolling buffer of last 3 good locations for averaging
  final List<({double lat, double lng, double accuracy})> lastGoodReadings = [];
  const int maxGoodReadingsBuffer = 3;
  const double goodAccuracyThreshold = kAttendanceGpsGoodAccuracyThresholdMeters;

  for (var i = 0; i < maxSamples; i++) {
    try {
      // **BEST PRACTICE**: Let GPS stabilize between reads (especially indoors).
      if (i > 0 && preSampleStabilizationDelay > Duration.zero) {
        await Future<void>.delayed(preSampleStabilizationDelay);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(
            seconds: i == 0 ? firstSampleTimeoutSeconds : laterSampleTimeoutSeconds,
          ),
        ),
      );

      if (position.isMocked) {
        return GpsFenceSampleResult(
          isWithinFence: false,
          bestDistanceMeters: 0,
          accuracyUsedForMessage: 0,
          mockedDetected: true,
          samplesCollected: i + 1,
          samplesUsed: 0,
        );
      }

      final accuracy = position.accuracy > 0 ? position.accuracy : 35.0;

      // **BEST PRACTICE**: Only accept readings with good accuracy
      if (accuracy <= goodAccuracyThreshold) {
        // Add to rolling buffer
        lastGoodReadings.add((
          lat: position.latitude,
          lng: position.longitude,
          accuracy: accuracy,
        ));

        // Keep only last 3
        if (lastGoodReadings.length > maxGoodReadingsBuffer) {
          lastGoodReadings.removeAt(0);
        }
      }

      // **BEST PRACTICE**: Average last 3 good locations for smoothing
      double useLat = position.latitude;
      double useLng = position.longitude;

      if (lastGoodReadings.isNotEmpty) {
        // Use average of all good readings in buffer
        final avgLat =
            lastGoodReadings.map((r) => r.lat).reduce((a, b) => a + b) /
                lastGoodReadings.length;
        final avgLng =
            lastGoodReadings.map((r) => r.lng).reduce((a, b) => a + b) /
                lastGoodReadings.length;
        useLat = avgLat;
        useLng = avgLng;
      }

      final d = Geolocator.distanceBetween(
        useLat,
        useLng,
        fenceLat,
        fenceLng,
      );

      distances.add(d);
      accuracies.add(accuracy);

      if (d < bestDistance) {
        bestDistance = d;
        bestAccuracy = accuracy;
      }
    } catch (_) {
      // Try another sample after a short wait.
    }

    if (i < maxSamples - 1) {
      await Future<void>.delayed(delayBetweenSamples);
    }
  }

  // Process collected samples with smart filtering
  if (distances.isNotEmpty) {
    final sortedDistances = List<double>.from(distances)..sort();
    final minDistance = sortedDistances.first;

    // Find samples close to minimum (likely true location with possible drift)
    // Accept samples within minDistance + strict drift tolerance
    final driftTolerance = kAttendanceGpsDriftToleranceMeters;
    final filteredDistances = distances
        .where((d) => d <= minDistance + driftTolerance)
        .toList();

    int samplesUsed = filteredDistances.isNotEmpty ? filteredDistances.length : distances.length;

    // Use average of filtered samples, or minimum if none filter
    final effectiveDistance = filteredDistances.isNotEmpty
        ? filteredDistances.reduce((a, b) => a + b) / filteredDistances.length
        : minDistance;

    // Calculate average accuracy
    final avgAccuracy = accuracies.isNotEmpty
        ? accuracies.reduce((a, b) => a + b) / accuracies.length
        : bestAccuracy ?? 35.0;

    // Small accuracy buffer only; weak readings are already rejected above.
    final rawAcc = avgAccuracy > 0 ? avgAccuracy : 35.0;
    final effectiveRadius = attendanceEffectiveFenceRadiusMeters(
      rawAcc,
      nominalRadiusMeters: radiusMeters,
    );

    if (effectiveDistance <= effectiveRadius) {
      return GpsFenceSampleResult(
        isWithinFence: true,
        bestDistanceMeters: effectiveDistance,
        accuracyUsedForMessage: avgAccuracy,
        samplesCollected: distances.length,
        samplesUsed: samplesUsed,
      );
    }

    return GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: effectiveDistance,
      accuracyUsedForMessage: avgAccuracy,
      samplesCollected: distances.length,
      samplesUsed: samplesUsed,
    );
  }

  if (bestDistance == double.infinity) {
    if (kAttendanceGpsAllowLastKnownFallback) {
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last?.isMocked == true) {
          return const GpsFenceSampleResult(
            isWithinFence: false,
            bestDistanceMeters: 0,
            accuracyUsedForMessage: 0,
            mockedDetected: true,
          );
        }
        if (last != null) {
          final d = Geolocator.distanceBetween(
            last.latitude,
            last.longitude,
            fenceLat,
            fenceLng,
          );
          final rawAcc = last.accuracy > 0 ? last.accuracy : 45.0;
          final effectiveRadius = attendanceEffectiveFenceRadiusMeters(
            rawAcc,
            nominalRadiusMeters: radiusMeters,
          );
          if (d <= effectiveRadius) {
            return GpsFenceSampleResult(
              isWithinFence: true,
              bestDistanceMeters: d,
              accuracyUsedForMessage:
                  last.accuracy > 0 ? last.accuracy : rawAcc,
              samplesCollected: 0,
              samplesUsed: 0,
            );
          }
          return GpsFenceSampleResult(
            isWithinFence: false,
            bestDistanceMeters: d,
            accuracyUsedForMessage:
                last.accuracy > 0 ? last.accuracy : rawAcc,
            samplesCollected: 0,
            samplesUsed: 0,
          );
        }
      } catch (_) {
        // fall through to user-facing message
      }
    }

    return const GpsFenceSampleResult(
      isWithinFence: false,
      bestDistanceMeters: 0,
      accuracyUsedForMessage: 0,
      errorMessage:
          'Could not get a stable GPS reading inside classroom. Move near a window/open area for 10-15 seconds, then try again.',
      samplesCollected: 0,
      samplesUsed: 0,
    );
  }

  return GpsFenceSampleResult(
    isWithinFence: false,
    bestDistanceMeters: bestDistance,
    accuracyUsedForMessage: bestAccuracy ?? 0,
    samplesCollected: distances.length,
    samplesUsed: distances.length,
  );
}
