/// Nominal attendance geofence (meters) from the locked GPS point — all directions.
const double kAttendanceFenceRadiusMeters = 15.0;

/// Hard cap on how far from the locked point attendance may pass (includes GPS slack).
/// Indoor phones often report 30–80 m accuracy; 25 m was too tight vs PIN login.
const double kAttendanceMaxEffectiveFenceMeters = 50.0;

/// Radius used for **PIN login** distance check (nominal center, before accuracy buffer).
/// Kept equal to [kAttendanceFenceRadiusMeters]; buffer is added separately (see below).
const double kPinLoginNominalFenceRadiusMeters = kAttendanceFenceRadiusMeters;

/// One-shot GPS fixes (PIN login) use [Position.accuracy] — indoors/phones often report
/// 30–100m. We add a **capped** slack so staff at the locked point are not denied when
/// the true position matches but the reported fix is offset.
double pinLoginEffectiveFenceRadiusMeters(double positionAccuracyMeters) {
  final raw = positionAccuracyMeters > 0 ? positionAccuracyMeters : 35.0;
  final clampedAcc = raw.clamp(18.0, 100.0);
  return kPinLoginNominalFenceRadiusMeters + clampedAcc;
}

// --- Fast path while marking attendance (admin mark + Student Management) ---

/// Indoor-friendly: try a fresh last-known fix before waking GPS for live samples.
const bool kAttendanceGpsTryLastKnownFirst = true;

/// Indoor-friendly: allow last-known fallback after live sampling fails.
const bool kAttendanceGpsAllowLastKnownFallback = true;

/// Max age for that last-known shortcut ([samplePositionAgainstFence]).
const int kAttendanceGpsLastKnownMaxAgeMinutes = 3;

/// Fewer samples + shorter waits than the full “verify location” flow.
const int kAttendanceGpsFastMaxSamples = 5;

const int kAttendanceGpsFastFirstTimeoutSec = 12;
const int kAttendanceGpsFastLaterTimeoutSec = 7;
const int kAttendanceGpsFastDelayBetweenMs = 250;
const int kAttendanceGpsFastStabilizationMs = 400;

/// Prefer stronger fixes for smoothing, but do not reject honest indoor users.
const double kAttendanceGpsGoodAccuracyThresholdMeters = 18.0;

/// Effective fence radius for attendance sampling (nominal + accuracy slack).
///
/// Uses the same idea as [pinLoginEffectiveFenceRadiusMeters] but caps lower so
/// marking stays tighter than PIN login (which can reach ~115 m).
double attendanceEffectiveFenceRadiusMeters(
  double positionAccuracyMeters, {
  double nominalRadiusMeters = kAttendanceFenceRadiusMeters,
}) {
  final raw = positionAccuracyMeters > 0 ? positionAccuracyMeters : 35.0;
  final clampedAcc = raw.clamp(18.0, 45.0);
  final uncapped = nominalRadiusMeters + clampedAcc;
  return uncapped > kAttendanceMaxEffectiveFenceMeters
      ? kAttendanceMaxEffectiveFenceMeters
      : uncapped;
}

/// Keep samples reasonably close to the best live reading.
const double kAttendanceGpsDriftToleranceMeters = 15.0;
