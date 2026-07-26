/// Face matching thresholds for registration and attendance
/// Cosine similarity ranges from 0.0 to 1.0
/// Higher = more similar faces

class FaceMatchingThresholds {
  /// ✅ TWO-TIER DUPLICATE DETECTION SYSTEM
  /// Soft warning at 60% (admin reviews, can approve)
  /// Hard block at 88% (confirmed duplicate/fraud)
  /// Allow below 60% (genuine different students)

  /// HARD BLOCK: Same person attempting duplicate registration (confirmed duplicate/fraud)
  /// >= 88% similarity = Almost identical face = Same person definitely
  static const double DUPLICATE_HARD_BLOCK_THRESHOLD = 0.88;

  /// SOFT WARNING: Suspicious similarity but let admin decide
  /// Raised to 0.88 to match hard block — family members / lookalikes
  /// can easily score 70-85% and are genuine different students.
  static const double DUPLICATE_REVIEW_THRESHOLD = 0.88;

  /// LEGACY: Kept for backward compatibility
  /// Now replaced by two-tier system above
  static const double DUPLICATE_DETECTION_THRESHOLD = DUPLICATE_HARD_BLOCK_THRESHOLD;

  /// Threshold for **attendance / entry / exit** face verification (probe vs enrolled embedding).
  /// Entry and exit both use [FaceRecognitionService.verifyStudent] only — no separate
  /// "exit photo vs today's entry photo" step.
  ///
  /// - Below 0.45 (45%) → ❌ HARD REJECT vs enrollment (almost certainly wrong person — no manual)
  /// - Between 0.45–0.55 (45–55%) → ⚠️ MANUAL CONFIRM (ambiguous band — staff compares to roster)
  /// - ≥ 0.55 (55%) → ✅ AUTO-ACCEPT (strong match vs enrolled embedding)
  ///
  /// Probe vs **other** students uses only rows in `students` for the same `institute_id`
  /// (no cross-institute pool).
  ///
  /// Camera factors affecting similarity:
  /// • Phone camera quality varies (0.05-0.10 drop)
  /// • Lighting conditions (0.10-0.15 drop)
  /// • Face angle/distance (0.05-0.20 drop)
  /// • Time of day differences (0.05-0.10 drop)
  static const double ATTENDANCE_VERIFICATION_THRESHOLD = 0.55;

  /// Below this vs enrollment → hard reject **when an embedding exists** (no manual in that band).
  static const double ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY = 0.45;

  /// Block attendance when another student in the **same institute** matches this face
  /// at or above this score and beats the selected student card.
  /// Raised slightly so look-alikes in the same class trigger manual confirm, not hard block.
  static const double CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD = 0.82;

  /// Another student's score must exceed the selected student's by at least this margin
  /// to treat the face as belonging to the other enrolled student.
  /// Increased from 0.06 to 0.15 to reduce false positives for genuine students
  /// with appearance changes while still blocking obvious fraud (same-person at 88%+).
  static const double CROSS_STUDENT_DOMINANCE_MARGIN = 0.15;

  /// Near-duplicate / same-person fraud block (always reject; no manual override).
  static const double CROSS_STUDENT_MANUAL_CEILING_OTHER = 0.88;

  /// Minimum confidence for face detection itself
  /// 0.5 = 50% confidence the detected face is a real face (vs noise)
  static const double MINIMUM_FACE_CONFIDENCE = 0.5;

  /// Print thresholds for debugging
  static void printThresholds() {
    print('''
╔════════════════════════════════════════════════════════════════╗
║    FACE MATCHING THRESHOLDS - TWO-TIER DUPLICATE DETECTION     ║
╠════════════════════════════════════════════════════════════════╣
║ HARD BLOCK (confirmed duplicate):  >= ${(DUPLICATE_HARD_BLOCK_THRESHOLD * 100).toStringAsFixed(0)}% similar
║ SOFT WARNING (admin review):       60-85% similar
║ ALLOW (genuine students):          < 60% similar
║
║ ATTENDANCE AUTO-ACCEPT:            >= ${(ATTENDANCE_VERIFICATION_THRESHOLD * 100).toStringAsFixed(0)}% vs enrollment (same institute roster only)
║ APPEARANCE-MANUAL BAND:            ${(ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY * 100).toStringAsFixed(0)}-${(ATTENDANCE_VERIFICATION_THRESHOLD * 100).toStringAsFixed(0)}% vs enrollment (staff confirm)
║ CROSS-STUDENT BLOCK (other wins):  >= ${(CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD * 100).toStringAsFixed(0)}% and beats selected card
║ CROSS-STUDENT FRAUD BLOCK:        >= ${(CROSS_STUDENT_MANUAL_CEILING_OTHER * 100).toStringAsFixed(0)}% (near-duplicate, likely same person)
║ FACE CONFIDENCE:                   >= 50%
╚════════════════════════════════════════════════════════════════╝

TWO-TIER SYSTEM BEHAVIOR:
├─ >= 88% (confirmed duplicate)  → ❌ HARD BLOCK "This is same person"
├─ 60-88% (suspicious)           → ⚠️ SOFT WARNING (allow but log for admin)
└─ < 60% (genuine different)     → ✅ ALLOW registration

HOW TO TUNE:
✅ Genuine students stuck below staff-confirm band (<45%) too often?
   → Lower ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY slightly.

✅ Too many fraudsters passing (same person registering twice)?
   → Raise DUPLICATE_HARD_BLOCK_THRESHOLD from 0.88 to 0.92
   → Stricter on confirmed duplicates during registration
    ''');
  }

  /// Calculate similarity percentage for user display
  static String similarityPercentage(double similarity) {
    return '${(similarity * 100).toStringAsFixed(1)}%';
  }

  /// Check if two faces are too similar (duplicate)
  static bool isDuplicate(double similarity) {
    return similarity >= DUPLICATE_DETECTION_THRESHOLD;
  }

  /// Check if face matches for attendance
  static bool isMatch(double similarity) {
    return similarity >= ATTENDANCE_VERIFICATION_THRESHOLD;
  }
}
