import 'package:flutter/foundation.dart';

import '../core/gps_attendance_constants.dart';
import 'geofence_service.dart';
import 'gps_fence_sample.dart';

/// On-demand location verification for PIN-session flows (critical moments before
/// face registration, student-management attendance trigger, etc.).
///
/// Uses the **same locked fence and sampling logic** as inline attendance marking
/// (`samplePositionAgainstFence`), not a separate strict 15m check against prefs.
class LocationVerificationService {
  /// Same fence + tolerance as `_checkGPSRadius` in attendance flows.
  static Future<({bool isWithinRadius, double? distance, String? error})>
      verifyLocationNow({
    required String instituteId,
  }) async {
    try {
      final fence =
          await GeofenceService().lockedFenceLatLngForInstitute(instituteId.trim());
      if (fence == null) {
        return (
          isWithinRadius: false,
          distance: null,
          error:
              'Institute GPS is not locked yet. Ask an admin to open GPS Settings, set the campus point, and lock it.',
        );
      }

      final sample = await samplePositionAgainstFence(
        fenceLat: fence.latitude,
        fenceLng: fence.longitude,
        radiusMeters: kAttendanceFenceRadiusMeters,
        maxSamples: kAttendanceGpsFastMaxSamples,
        delayBetweenSamples:
            Duration(milliseconds: kAttendanceGpsFastDelayBetweenMs),
        firstSampleTimeoutSeconds: kAttendanceGpsFastFirstTimeoutSec,
        laterSampleTimeoutSeconds: kAttendanceGpsFastLaterTimeoutSec,
        preSampleStabilizationDelay:
            Duration(milliseconds: kAttendanceGpsFastStabilizationMs),
        tryRecentLastKnownFirst: kAttendanceGpsTryLastKnownFirst,
        lastKnownMaxAge:
            Duration(minutes: kAttendanceGpsLastKnownMaxAgeMinutes),
      );

      if (sample.mockedDetected) {
        return (
          isWithinRadius: false,
          distance: sample.bestDistanceMeters,
          error: 'Fake GPS detected. Turn off Mock Location apps and try again.',
        );
      }

      if (sample.errorMessage != null) {
        return (
          isWithinRadius: false,
          distance: null,
          error: sample.errorMessage,
        );
      }

      if (!sample.isWithinFence) {
        return (
          isWithinRadius: false,
          distance: sample.bestDistanceMeters,
          error:
              'Out of radius: closest ~${sample.bestDistanceMeters.toStringAsFixed(0)}m. '
              'Try near a window or open area, wait a few seconds for GPS to settle, then retry.',
        );
      }

      if (kDebugMode) {
        debugPrint(
          '📍 LocationVerificationService: PASSED (~${sample.bestDistanceMeters.toStringAsFixed(1)}m, '
          'accuracy context ±${sample.accuracyUsedForMessage.toStringAsFixed(1)}m)',
        );
      }

      return (
        isWithinRadius: true,
        distance: sample.bestDistanceMeters,
        error: null,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('📍 Location verification error: $e');
      return (
        isWithinRadius: false,
        distance: null,
        error: 'Location verification failed: ${e.toString()}',
      );
    }
  }
}
