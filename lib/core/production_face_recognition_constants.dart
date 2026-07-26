/// Production real-time attendance face pipeline thresholds.
class ProductionFaceRecognitionConstants {
  ProductionFaceRecognitionConstants._();

  /// ArcFace buffalo_l / InsightFace API path (512-dim).
  static const int arcFaceEmbeddingDimensions = 512;

  /// On-device MobileFaceNet fallback (192-dim).
  static const int mobileFaceNetEmbeddingDimensions = 192;

  static const String modelArcFaceBuffaloL = 'arcface_buffalo_l';
  static const String modelMobileFaceNet = 'mobilefacenet_tflite_v1';

  /// ArcFace / server path (not used in on-device-only builds).
  static const double recognitionConfidenceThreshold = 0.85;

  /// MobileFaceNet on-device auto attendance (no backend).
  /// MobileFaceNet same-person scores: 0.65–0.80. Different-person: 0.35–0.55.
  static const double onDeviceRecognitionConfidenceThreshold = 0.60;

  /// Best match must beat second-best by this margin.
  /// 0.06 = good balance: prevents ambiguous matches without blocking
  /// real recognitions when two students happen to look somewhat alike.
  static const double recognitionMarginThreshold = 0.06;

  /// Auto scan marks on first successful match (one photo capture).
  static const int stableIdentificationFramesRequired = 1;

  /// Minimum time between full recognition attempts on stream (ms).
  static const int minRecognitionIntervalMs = 400;

  /// Cooldown after marking same student again (seconds).
  static const int postMarkCooldownSeconds = 30;

  /// MiniFAS / anti-spoof: minimum live confidence when model loaded.
  static const double livenessMinConfidence = 0.55;

  /// Enrollment: front + left + right in one session (MobileFaceNet).
  static const int enrollmentRequiredSamples = 3;

  static const int enrollmentTargetSamples = 3;
  static const int enrollmentMinSamples = 3;
  static const int enrollmentMaxSamples = 3;

  static const List<MapEntry<String, String>> enrollmentPoseSteps = [
    MapEntry('front', 'Look straight — blink 2 times (auto capture)'),
    MapEntry('left', 'Turn your head slightly to your left'),
    MapEntry('right', 'Turn your head slightly to your right'),
  ];
}
