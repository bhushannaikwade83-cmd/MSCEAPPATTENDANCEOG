import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode, debugPrint;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../core/camera_input_image_utils.dart';
import '../core/stream_face_frame.dart';

import '../core/live_face_box_state.dart';
import '../core/streaming_blink_detector.dart';
import 'anti_spoof_service.dart';
import 'device_performance_service.dart';
import 'distance_check_service.dart'
    show DistanceProfile, DistanceStatus, DistanceCheckService;
import 'depth_analysis_service.dart';
import 'screen_spoof_detection_service.dart';
import 'video_replay_guard_service.dart';

/// Random left/right turn — blocks pre-recorded clips that blink + turn the wrong way.
enum ScanHeadTurnChallenge { turnLeft, turnRight }

/// Live-stream gate: block screen/video **before** blinks and [takePicture].
class PreCaptureLivenessTracker {
  PreCaptureLivenessTracker({
    this.screenSpoofFramesRequired = 2,
    this.minCleanLiveFramesBeforeCapture = 4,
    this.minMicroMotionEvents = 0,
    this.minPadLiveStreak = 3,
    this.requireBlink = true,
    this.requiredBlinks = 1,
    this.enableStreamPad = false,
    this.enableStreamScreenSpoof = false,
    this.softAutoScanScreenSpoof = false,
    this.requireLiveFaceBeforeLiveness = false,
    this.require3DPoseEvidence = false,
    this.minHeadYawRangeDegrees = 2.5,
    this.minHeadPitchRangeDegrees = 2.0,
    this.randomHeadTurnChallenge,
    this.directedTurnYawDegrees = 18.0,
    this.enableDepthReplayGuard = false,
    this.blockVideoReplay = false,
    this.requireCenterReturnAfterTurn = false,
    this.videoReplayFramesRequired = 6,
    this.strictAutoScanPad = false,
    this.inlinePadOnly = false,
    this.distanceProfile = DistanceProfile.attendance,
  });

  final int screenSpoofFramesRequired;
  final int minCleanLiveFramesBeforeCapture;
  final int minMicroMotionEvents;
  final int minPadLiveStreak;
  final bool requireBlink;
  final int requiredBlinks;
  final bool enableStreamPad;
  final bool enableStreamScreenSpoof;
  /// Higher thresholds so live faces are not blocked (auto scan only).
  final bool softAutoScanScreenSpoof;
  final bool requireLiveFaceBeforeLiveness;
  /// Reject flat 2D photo/screen using head-pose range + nose/ear landmarks.
  final bool require3DPoseEvidence;
  final double minHeadYawRangeDegrees;
  final double minHeadPitchRangeDegrees;
  final ScanHeadTurnChallenge? randomHeadTurnChallenge;
  final double directedTurnYawDegrees;
  /// Extra 2D/screen proxy while scanning (ML Kit pose + tracking).
  final bool enableDepthReplayGuard;
  /// LCD flicker + smooth video motion heuristics (auto scan).
  final bool blockVideoReplay;
  /// After random L/R turn, face must return to center (blocks one-shot clips).
  final bool requireCenterReturnAfterTurn;
  /// Consecutive video signals before block (avoids live-face false positives).
  final int videoReplayFramesRequired;
  /// Fast red on photo/video; green + capture only after stable live PAD.
  final bool strictAutoScanPad;
  /// PAD run from screen via await (no async duplicate in tracker).
  final bool inlinePadOnly;
  final DistanceProfile distanceProfile;

  static const double _gridScreenThreshold = 0.045;
  static const double _gridScreenWithScoreThreshold = 0.028;
  static const double _gridScreenMinCombinedScore = 0.20;
  static const double _sustainedReplayPeakScore = 0.24;
  static const double _sustainedReplayAverageScore = 0.18;
  static const double _temporalReplayThreshold = 0.40;

  static const double _softGridScreenThreshold = 0.058;
  static const double _softGridScreenWithScoreThreshold = 0.038;
  static const double _softGridScreenMinCombinedScore = 0.28;
  static const double _softSustainedReplayPeakScore = 0.34;
  static const double _softSustainedReplayAverageScore = 0.26;
  static const double _softTemporalReplayThreshold = 0.48;

  StreamingBlinkDetector get blinkDetector => _blinkDetector;
  late final StreamingBlinkDetector _blinkDetector = StreamingBlinkDetector(
    closedFramesRequired:
        DevicePerformanceService.relaxedStreamBlinkDetection ? 1 : 2,
    openFramesRequired:
        DevicePerformanceService.relaxedStreamBlinkDetection ? 1 : 2,
    minOpenClosedSwing:
        DevicePerformanceService.relaxedStreamBlinkDetection ? 0.14 : 0.20,
  );

  int screenSpoofStreak = 0;
  int _videoReplayAnalysisTick = 0;
  int cleanLiveFrameStreak = 0;
  int heuristicLiveStreak = 0;
  int padLiveStreak = 0;
  int padSpoofStreak = 0;
  int perfectDistanceStreak = 0;
  int microMotionEvents = 0;
  int blinksDetected = 0;
  double screenSpoofScore = 0.0;
  bool screenReplayDetected = false;
  bool padMarkedFake = false;

  final List<double> _recentScreenScores = [];
  final List<double> _faceLumaHistory = [];
  double _temporalReplayScore = 0.0;
  int _eligibleFrameCount = 0;
  bool _padCheckRunning = false;
  bool _hasPadResult = false;
  bool? _lastPadIsLive;
  double _lastPadConfidence = 0.0;
  int _padNullStreak = 0;
  bool _streamPadDegraded = false;

  /// Fired after async MiniFAS result (refresh UI).
  VoidCallback? onPadUpdated;

  double get lastPadConfidence => _lastPadConfidence;

  double? _lastYaw;
  double? _lastPitch;
  double? _lastCenterX;
  double? _lastCenterY;

  bool _poseRangeInitialized = false;
  double _yawMin = 0;
  double _yawMax = 0;
  double _pitchMin = 0;
  double _pitchMax = 0;
  int _poseSampleCount = 0;
  int _landmarkAsymmetryHits = 0;
  int _landmarkProfileHits = 0;
  int _earProfileHits = 0;
  bool _directedTurnCompleted = false;
  bool _centerReturnCompleted = false;
  int _centerReturnStreak = 0;
  bool _depthReplayBlocked = false;
  bool _videoReplayBlocked = false;
  int _videoReplayStreak = 0;
  String _videoReplayReason = '';
  final List<double> _yawHistory = [];
  static const int _maxYawHistory = 18;

  /// Show spoof UI once, then clear after this (avoids 3–4 repeats per frame).
  static const Duration spoofMessageHoldDuration = Duration(seconds: 5);

  DateTime? _spoofUiHoldUntil;
  String? _spoofUiHoldMessage;

  /// True while the spoof warning should stay on screen (fixed text, red box).
  bool get isSpoofUiHoldActive {
    if (_spoofUiHoldUntil == null) return false;
    if (DateTime.now().isBefore(_spoofUiHoldUntil!)) return true;
    return false;
  }

  String? get activeSpoofUiMessage =>
      isSpoofUiHoldActive ? _spoofUiHoldMessage : null;

  void _expireSpoofUiHoldIfNeeded() {
    if (_spoofUiHoldUntil == null) return;
    if (DateTime.now().isBefore(_spoofUiHoldUntil!)) return;
    _spoofUiHoldUntil = null;
    _spoofUiHoldMessage = null;
    _softResetScreenSpoofState();
    _resetSpoofAndLiveness();
  }

  void _lockSpoofUiMessage(String message) {
    if (isSpoofUiHoldActive) return;
    _spoofUiHoldMessage = message;
    _spoofUiHoldUntil = DateTime.now().add(spoofMessageHoldDuration);
    screenReplayDetected = true;
    padMarkedFake = true;
  }

  /// Call when capture-time PAD / screen check fails (same 5s hold).
  void lockSpoofMessageForHold(String message) {
    _lockSpoofUiMessage(message);
  }

  double get _gridThreshold =>
      softAutoScanScreenSpoof ? _softGridScreenThreshold : _gridScreenThreshold;

  double get _gridWithScoreThreshold => softAutoScanScreenSpoof
      ? _softGridScreenWithScoreThreshold
      : _gridScreenWithScoreThreshold;

  double get _gridMinCombined =>
      softAutoScanScreenSpoof ? _softGridScreenMinCombinedScore : _gridScreenMinCombinedScore;

  double get _sustainedPeak =>
      softAutoScanScreenSpoof ? _softSustainedReplayPeakScore : _sustainedReplayPeakScore;

  double get _sustainedAvg => softAutoScanScreenSpoof
      ? _softSustainedReplayAverageScore
      : _sustainedReplayAverageScore;

  double get _temporalThreshold => softAutoScanScreenSpoof
      ? _softTemporalReplayThreshold
      : _temporalReplayThreshold;

  bool get isDistanceLocked =>
      perfectDistanceStreak >= DistanceCheckService.minPerfectFramesToProceed;

  bool get directedTurnOk =>
      randomHeadTurnChallenge == null || _directedTurnCompleted;

  bool get centerReturnOk =>
      !requireCenterReturnAfterTurn ||
      randomHeadTurnChallenge == null ||
      !_directedTurnCompleted ||
      _centerReturnCompleted;

  /// True when head moved in 3D (yaw/pitch range) or nose/ear geometry looks 3D.
  bool get has3DPoseEvidence {
    if (!require3DPoseEvidence) return true;
    if (_poseSampleCount < 3) return false;
    if (_yawMax - _yawMin >= minHeadYawRangeDegrees) return true;
    if (_pitchMax - _pitchMin >= minHeadPitchRangeDegrees) return true;
    if (_landmarkAsymmetryHits >= 2) return true;
    if (_landmarkProfileHits >= 2) return true;
    if (_earProfileHits >= 1) return true;
    return false;
  }

  /// Confirmed live face — required before blinks count or capture.
  bool get liveFaceGateOpen {
    if (screenReplayDetected || padMarkedFake) return false;
    if (!requireLiveFaceBeforeLiveness) return true;
    if (enableStreamPad && AntiSpoofService.captureTimePadOnly) {
      return heuristicLiveStreak >= 1;
    }
    if (enableStreamPad && AntiSpoofService.supportsStreamPad) {
      return padLiveStreak >= 1;
    }
    // No stream PAD (registration): open gate on first heuristic live frame.
    return heuristicLiveStreak >= 1;
  }

  void reset() {
    _spoofUiHoldUntil = null;
    _spoofUiHoldMessage = null;
    screenSpoofStreak = 0;
    cleanLiveFrameStreak = 0;
    heuristicLiveStreak = 0;
    padLiveStreak = 0;
    padSpoofStreak = 0;
    perfectDistanceStreak = 0;
    microMotionEvents = 0;
    blinksDetected = 0;
    screenSpoofScore = 0.0;
    screenReplayDetected = false;
    padMarkedFake = false;
    _recentScreenScores.clear();
    _faceLumaHistory.clear();
    _temporalReplayScore = 0.0;
    _eligibleFrameCount = 0;
    _padCheckRunning = false;
    _hasPadResult = false;
    _lastPadIsLive = null;
    _lastPadConfidence = 0.0;
    _padNullStreak = 0;
    _streamPadDegraded = false;
    _reset3DPoseEvidence();
    blinkDetector.reset();
  }

  LiveFaceBoxState faceBoxState(DistanceStatus status, bool eligible) {
    if (isSpoofUiHoldActive) return LiveFaceBoxState.spoof;
    if (status == DistanceStatus.noFace) return LiveFaceBoxState.none;
    if (!eligible) return LiveFaceBoxState.distance;

    if (enableStreamPad) {
      if (AntiSpoofService.allModelsFailed) {
        return LiveFaceBoxState.live;
      }
      if (!AntiSpoofService.isModelLoaded) {
        return AntiSpoofService.allModelsFailed
            ? LiveFaceBoxState.distance
            : LiveFaceBoxState.checking;
      }
      if (AntiSpoofService.captureTimePadOnly ||
          (!strictAutoScanPad &&
              (AntiSpoofService.useCaptureTimePadOnly || _streamPadDegraded))) {
        if (padMarkedFake) return LiveFaceBoxState.spoof;
        return LiveFaceBoxState.live;
      }
      if (padMarkedFake ||
          padSpoofStreak >= 1 ||
          (_hasPadResult && _lastPadIsLive == false)) {
        return LiveFaceBoxState.spoof;
      }
      // Box turns green on first live PAD result.
      if (_hasPadResult && _lastPadIsLive == true) {
        return LiveFaceBoxState.live;
      }
      return LiveFaceBoxState.checking;
    }

    if (screenReplayDetected || padMarkedFake || _videoReplayBlocked) {
      return LiveFaceBoxState.spoof;
    }
    // Stream PAD off (registration) — show green as soon as any heuristic
    // live frame is seen at correct distance; capture gate handles the rest.
    if (heuristicLiveStreak >= 1) {
      return LiveFaceBoxState.live;
    }
    return LiveFaceBoxState.checking;
  }

  PreCaptureFrameResult evaluate({
    required CameraImage image,
    required Face face,
    required double displayWidth,
    required double displayHeight,
    InputImageRotation? imageRotation,
    StreamFaceFrame? streamFrame,
  }) {
    _expireSpoofUiHoldIfNeeded();

    final frame = streamFrame ??
        (imageRotation != null
            ? StreamFaceFrame.from(
                face: face,
                image: image,
                rotation: imageRotation,
              )
            : null);

    final distanceCheck = DistanceCheckService.checkFaceDistance(
      face,
      displayWidth,
      displayHeight,
      image: image,
      rotation: imageRotation,
      distanceRatioOverride: frame?.distanceRatio,
      profile: distanceProfile,
    );

    final status = distanceCheck['status'] as DistanceStatus;
    final isSafe = distanceCheck['isSafe'] as bool;
    final ratio = (distanceCheck['ratio'] as num?)?.toDouble() ?? 0.0;
    final confidence = (distanceCheck['confidence'] as num?)?.toDouble() ?? 0.0;

    final atThreeFeet = DistanceCheckService.allowsCapture(status);
    if (atThreeFeet) {
      perfectDistanceStreak++;
    } else {
      perfectDistanceStreak = 0;
    }

    final distanceLocked =
        atThreeFeet &&
        perfectDistanceStreak >= DistanceCheckService.minPerfectFramesToProceed;

    final eligible = isSafe && distanceLocked;

    if (isSpoofUiHoldActive) {
      return PreCaptureFrameResult(
        distanceStatus: status,
        faceRatio: ratio,
        distanceConfidence: confidence,
        canCapture: false,
        spoofBlocked: true,
        livenessMessage: _spoofUiHoldMessage!,
        boxState: LiveFaceBoxState.spoof,
        padConfidence: _lastPadConfidence,
      );
    }

    if (!eligible) {
      _resetSpoofAndLiveness();
      final msg = !atThreeFeet
          ? DistanceCheckService.phoneNotAtThreeFeetMessage(
              status,
              profile: distanceProfile,
            )
          : DistanceCheckService.holdThreeFeetSteadyFor(distanceProfile);
      return PreCaptureFrameResult(
        distanceStatus: status,
        faceRatio: ratio,
        distanceConfidence: confidence,
        canCapture: false,
        spoofBlocked: false,
        livenessMessage: msg,
        boxState: faceBoxState(status, false),
        padConfidence: _lastPadConfidence,
      );
    }

    _eligibleFrameCount++;

    final analysisFace = frame?.analysisBox ??
        (imageRotation != null
            ? CameraInputImageUtils.faceBoxInAnalysisSpace(
                face: face,
                image: image,
                rotation: imageRotation,
              )
            : face.boundingBox);
    final faceRect = frame?.bufferRect ??
        mapFaceRectToCameraBuffer(
          image: image,
          face: face,
          displayWidth: displayWidth,
          displayHeight: displayHeight,
          analysisBox: analysisFace,
        );

    final suppressBanding = blinkDetector.shouldSuppressBandingSpoof;

    double peakScore = 0.0;
    double avgScore = 0.0;

    if (enableStreamScreenSpoof || blockVideoReplay) {
      _faceLumaHistory.add(
        ScreenSpoofDetectionService.meanFaceLuma(image, faceRect),
      );
      if (_faceLumaHistory.length > 14) {
        _faceLumaHistory.removeAt(0);
      }
      _temporalReplayScore =
          ScreenSpoofDetectionService.temporalReplayScore(_faceLumaHistory);
    }

    if (!enableStreamScreenSpoof && blockVideoReplay) {
      // Throttle: run heavy pixel analysis every 5th frame only (saves CPU/heat).
      _videoReplayAnalysisTick = (_videoReplayAnalysisTick + 1) % 5;
      if (_videoReplayAnalysisTick == 0) {
        final probe = ScreenSpoofDetectionService.analyzeCameraImage(
          image,
          faceRect: faceRect,
          useFaceRoiBanding: false,
        );
        screenSpoofScore = probe.score;
      }
    }

    if (enableStreamScreenSpoof) {
      final screenSpoof = ScreenSpoofDetectionService.analyzeCameraImage(
        image,
        faceRect: faceRect,
        useFaceRoiBanding: false,
      );
      screenSpoofScore = math.max(screenSpoof.score, _temporalReplayScore);

      _recentScreenScores.add(screenSpoofScore);
      if (_recentScreenScores.length > 10) {
        _recentScreenScores.removeAt(0);
      }
      peakScore = _recentScreenScores.reduce(math.max);
      avgScore =
          _recentScreenScores.reduce((a, b) => a + b) / _recentScreenScores.length;

      final strongScreenFrame = _isLikelyScreenReplayFrame(
        screenSpoof,
        temporalScore: _temporalReplayScore,
        suppressBandingHeuristics: suppressBanding,
      );
      // Never treat camera flicker (temporal-only) as screen replay on live faces.
      final sustainedReplay = _recentScreenScores.length >= 6 &&
          peakScore >= _sustainedPeak &&
          avgScore >= _sustainedAvg &&
          screenSpoof.gridScore >= _gridWithScoreThreshold;

      if (strongScreenFrame || sustainedReplay) {
        screenSpoofStreak++;
        heuristicLiveStreak = 0;
      } else {
        screenSpoofStreak = 0;
        heuristicLiveStreak++;
      }
      screenReplayDetected = screenSpoofStreak >= screenSpoofFramesRequired;
    } else {
      screenSpoofStreak = 0;
      screenReplayDetected = false;
      screenSpoofScore = 0.0;
      _temporalReplayScore = 0.0;
      heuristicLiveStreak++;
    }

    if (enableStreamPad &&
        AntiSpoofService.supportsStreamPad &&
        !_streamPadDegraded &&
        !inlinePadOnly &&
        !_padCheckRunning) {
      _schedulePadCheck(image, analysisFace, imageRotation);
    }

    if (blockVideoReplay && eligible) {
      _updateVideoReplayGuard(face);
      if (_videoReplayBlocked) {
        final msg = _videoReplayReason.isNotEmpty
            ? _videoReplayReason
            : 'Video not allowed — show your live face';
        _lockSpoofUiMessage(msg);
        return PreCaptureFrameResult(
          distanceStatus: DistanceStatus.perfect,
          faceRatio: ratio,
          distanceConfidence: confidence,
          canCapture: false,
          spoofBlocked: true,
          livenessMessage: _spoofUiHoldMessage ?? msg,
          boxState: LiveFaceBoxState.spoof,
          padConfidence: _lastPadConfidence,
        );
      }
    }

    final padStreamSpoof = enableStreamPad &&
        AntiSpoofService.supportsStreamPad &&
        _hasPadResult &&
        padSpoofStreak >= 1 &&
        _lastPadIsLive == false;
    final spoofBlocked =
        screenReplayDetected || padMarkedFake || padStreamSpoof;

    if (spoofBlocked) {
      final blockedScreen = screenReplayDetected;
      final blockedPad = padMarkedFake;
      final msg = padStreamSpoof || padMarkedFake
          ? 'Photo or screen spoof detected — use your live face only'
          : 'Screen spoof detected — use your live face only';
      _lockSpoofUiMessage(msg);
      if (kDebugMode) {
        debugPrint(
          '🚫 Pre-capture BLOCK: screen=$blockedScreen pad=$blockedPad '
          '(hold ${spoofMessageHoldDuration.inSeconds}s)',
        );
      }
      return PreCaptureFrameResult(
        distanceStatus: DistanceStatus.perfect,
        faceRatio: ratio,
        distanceConfidence: confidence,
        canCapture: false,
        spoofBlocked: true,
        livenessMessage: _spoofUiHoldMessage ?? msg,
        boxState: LiveFaceBoxState.spoof,
        padConfidence: _lastPadConfidence,
      );
    }

    // Blinks only count after live-face gate is open (blocks video-with-blink attacks).
    final blinkCompleted = blinkDetector.processFrame(face);
    if (requireBlink &&
        liveFaceGateOpen &&
        blinksDetected < requiredBlinks &&
        blinkCompleted) {
      blinksDetected++;
    }

    if (!liveFaceGateOpen) {
      cleanLiveFrameStreak = 0;
      return PreCaptureFrameResult(
        distanceStatus: DistanceStatus.perfect,
        faceRatio: ratio,
        distanceConfidence: confidence,
        canCapture: false,
        spoofBlocked: false,
        livenessMessage: DistanceCheckService.phoneAtThreeFeetReadyMessage(),
        boxState: faceBoxState(DistanceStatus.perfect, true),
        padConfidence: _lastPadConfidence,
      );
    }

    _updateMicroMotion(face);
    _update3DPoseEvidence(face);
    _updateDirectedHeadTurn(face);
    _updateCenterReturn(face);
    if (enableDepthReplayGuard) {
      _updateDepthReplayGuard(face, frameFaceRatio: ratio);
    }
    cleanLiveFrameStreak++;

    final motionOk = microMotionEvents >= minMicroMotionEvents;
    final blinkOk = !requireBlink || blinksDetected >= requiredBlinks;
    final poseOk = has3DPoseEvidence;
    final turnOk = directedTurnOk;
    final centerOk = centerReturnOk;
    final cleanOk = cleanLiveFrameStreak >= minCleanLiveFramesBeforeCapture;
    final canCapture = motionOk &&
        blinkOk &&
        turnOk &&
        centerOk &&
        poseOk &&
        cleanOk &&
        !_depthReplayBlocked &&
        !_videoReplayBlocked;

    final box = faceBoxState(DistanceStatus.perfect, true);
    return PreCaptureFrameResult(
      distanceStatus: DistanceStatus.perfect,
      faceRatio: ratio,
      distanceConfidence: confidence,
      canCapture: canCapture && box == LiveFaceBoxState.live,
      spoofBlocked: false,
      livenessMessage: _livenessMessage(
        blinkOk: blinkOk,
        motionOk: motionOk,
        poseOk: poseOk,
        turnOk: turnOk,
        centerOk: centerOk,
        boxState: box,
      ),
      boxState: box,
      padConfidence: _lastPadConfidence,
    );
  }

  /// Final synchronous check on the frame that triggers [takePicture].
  Future<bool> verifyFrameIsLive(CameraImage image, Rect faceRect) async {
    // Stream detection runs continuously on every frame before box goes green.
    // Single-frame verification at capture causes false positives — skip it.
    // Only block if stream already flagged a spoof earlier in the session.
    if (screenReplayDetected || padMarkedFake || _videoReplayBlocked) {
      return false;
    }
    return true;

    if (blockVideoReplay) {
      final verdict = VideoReplayGuardService.evaluate(
        lumaHistory: _faceLumaHistory,
        yawHistory: _yawHistory,
        temporalReplayScore: _temporalReplayScore,
        screenSpoofScore: screenSpoofScore,
        padMarkedSpoof: padMarkedFake,
      );
      if (verdict.isLikelyVideo) return false;
    }

    if (enableStreamScreenSpoof) {
      final screenSpoof = ScreenSpoofDetectionService.analyzeCameraImage(
        image,
        faceRect: faceRect,
        useFaceRoiBanding: false,
      );
      if (_isLikelyScreenReplayFrame(
        screenSpoof,
        temporalScore: _temporalReplayScore,
        suppressBandingHeuristics: blinkDetector.shouldSuppressBandingSpoof,
      )) {
        return false;
      }
    }

    if (enableStreamPad && AntiSpoofService.captureTimePadOnly) {
      return liveFaceGateOpen && !padMarkedFake;
    }

    if (enableStreamPad && AntiSpoofService.supportsStreamPad) {
      final pad = await AntiSpoofService.checkSpoofFromCameraFrame(
        image,
        faceRect,
      );
      if (pad == null) return !strictAutoScanPad;
      if (strictAutoScanPad) {
        return AntiSpoofService.passesStrictAutoScan(pad) &&
            !AntiSpoofService.isImmediateSpoof(pad);
      }
      return AntiSpoofService.passesAttendanceCheck(pad);
    }

    if (enableStreamScreenSpoof) {
      return liveFaceGateOpen && !screenReplayDetected;
    }

    return liveFaceGateOpen;
  }

  void _resetSpoofAndLiveness() {
    screenSpoofStreak = 0;
    cleanLiveFrameStreak = 0;
    heuristicLiveStreak = 0;
    padLiveStreak = 0;
    microMotionEvents = 0;
    blinksDetected = 0;
    screenReplayDetected = false;
    padMarkedFake = false;
    padSpoofStreak = 0;
    screenSpoofScore = 0.0;
    _recentScreenScores.clear();
    _faceLumaHistory.clear();
    _temporalReplayScore = 0.0;
    blinkDetector.reset();
    _reset3DPoseEvidence();
  }

  void _reset3DPoseEvidence() {
    _lastYaw = null;
    _lastPitch = null;
    _lastCenterX = null;
    _lastCenterY = null;
    _poseRangeInitialized = false;
    _yawMin = 0;
    _yawMax = 0;
    _pitchMin = 0;
    _pitchMax = 0;
    _poseSampleCount = 0;
    _landmarkAsymmetryHits = 0;
    _landmarkProfileHits = 0;
    _earProfileHits = 0;
    _directedTurnCompleted = false;
    _centerReturnCompleted = false;
    _centerReturnStreak = 0;
    _depthReplayBlocked = false;
    _videoReplayBlocked = false;
    _videoReplayStreak = 0;
    _videoReplayReason = '';
    _yawHistory.clear();
  }

  void _softResetAfterVideoHint() {
    _videoReplayBlocked = false;
    _videoReplayStreak = 0;
    _faceLumaHistory.clear();
    _temporalReplayScore = 0.0;
    _yawHistory.clear();
    screenSpoofScore = 0.0;
  }

  void _softResetScreenSpoofState() {
    screenSpoofStreak = 0;
    screenReplayDetected = false;
    screenSpoofScore = 0.0;
    _recentScreenScores.clear();
    _faceLumaHistory.clear();
    _temporalReplayScore = 0.0;
  }

  void _updateVideoReplayGuard(Face face) {
    final yaw = -(face.headEulerAngleY ?? 0.0);
    _yawHistory.add(yaw);
    if (_yawHistory.length > _maxYawHistory) {
      _yawHistory.removeAt(0);
    }

    final verdict = VideoReplayGuardService.evaluate(
      lumaHistory: _faceLumaHistory,
      yawHistory: _yawHistory,
      temporalReplayScore: _temporalReplayScore,
      screenSpoofScore: screenSpoofScore,
      padMarkedSpoof: padMarkedFake,
    );
    if (verdict.isLikelyVideo) {
      _videoReplayStreak++;
      _videoReplayReason = verdict.reason;
      if (_videoReplayStreak >= videoReplayFramesRequired) {
        _videoReplayBlocked = true;
        if (kDebugMode) {
          debugPrint(
            '🚫 Video replay (${_videoReplayStreak} frames): ${verdict.reason} '
            'temporal=${_temporalReplayScore.toStringAsFixed(3)} '
            'screen=${screenSpoofScore.toStringAsFixed(3)}',
          );
        }
      }
    } else {
      _videoReplayStreak = 0;
      _videoReplayReason = '';
    }
  }

  void _updateCenterReturn(Face face) {
    if (!requireCenterReturnAfterTurn ||
        randomHeadTurnChallenge == null ||
        !_directedTurnCompleted ||
        _centerReturnCompleted) {
      return;
    }
    final angleY = -(face.headEulerAngleY ?? 0.0);
    if (angleY.abs() <= 10.0) {
      _centerReturnStreak++;
      if (_centerReturnStreak >= 4) _centerReturnCompleted = true;
    } else {
      _centerReturnStreak = 0;
    }
  }

  /// Apply MiniFAS stream result (also used from [AutoFaceScanScreen] inline await).
  void applyStreamPadResult(AntiSpoofResult? result) {
    if (result == null) {
      _padNullStreak++;
      if (!strictAutoScanPad &&
          _padNullStreak >= 4 &&
          AntiSpoofService.isModelLoaded) {
        _streamPadDegraded = true;
        if (kDebugMode) {
          debugPrint(
            '⚠️ Stream PAD unavailable — using capture-time anti-spoof only',
          );
        }
      }
      onPadUpdated?.call();
      return;
    }

    _padNullStreak = 0;
    _hasPadResult = true;
    _lastPadConfidence = result.confidence;

    final spoofNow = AntiSpoofService.isImmediateSpoof(result);
    final liveNow = strictAutoScanPad
        ? AntiSpoofService.passesStrictAutoScan(result)
        : AntiSpoofService.passesAttendanceCheck(result);

    if (spoofNow || !liveNow) {
      padLiveStreak = 0;
      padSpoofStreak++;
      _lastPadIsLive = false;
      if (kDebugMode) {
        debugPrint(
          '🚫 PAD NOT LIVE spoof=${(result.confidence * 100).toStringAsFixed(0)}% '
          '— ${result.reason}',
        );
      }
      if (strictAutoScanPad ? padSpoofStreak >= 1 : padSpoofStreak >= 2) {
        padMarkedFake = true;
        blinksDetected = 0;
        blinkDetector.reset();
      }
    } else {
      _lastPadIsLive = true;
      padLiveStreak++;
      padSpoofStreak = 0;
      padMarkedFake = false;
      if (kDebugMode && padLiveStreak == minPadLiveStreak) {
        debugPrint(
          '✅ PAD LIVE stable (${(result.confidence * 100).toStringAsFixed(0)}%)',
        );
      }
    }
    onPadUpdated?.call();
  }

  void _schedulePadCheck(CameraImage image, Rect analysisBox, InputImageRotation? rotation) {
    _padCheckRunning = true;
    unawaited(
      AntiSpoofService.checkSpoofFromCameraFrame(
        image,
        analysisBox,
        rotation: rotation ?? InputImageRotation.rotation270deg,
      ).then((result) {
        _padCheckRunning = false;
        applyStreamPadResult(result);
      }).catchError((e) {
        _padCheckRunning = false;
        if (kDebugMode) debugPrint('❌ PAD stream error: $e');
        applyStreamPadResult(null);
      }),
    );
  }

  static Rect mapFaceRectToCameraBuffer({
    required CameraImage image,
    required Face face,
    required double displayWidth,
    required double displayHeight,
    Rect? analysisBox,
  }) {
    final box = analysisBox ?? face.boundingBox;
    if (displayWidth <= 0 || displayHeight <= 0) {
      return _clampRect(box, image.width, image.height);
    }
    final sx = image.width / displayWidth;
    final sy = image.height / displayHeight;
    return _clampRect(
      Rect.fromLTRB(
        box.left * sx,
        box.top * sy,
        box.right * sx,
        box.bottom * sy,
      ),
      image.width,
      image.height,
    );
  }

  bool _isLikelyScreenReplayFrame(
    ScreenSpoofResult s, {
    double temporalScore = 0.0,
    bool suppressBandingHeuristics = false,
  }) {
    if (!softAutoScanScreenSpoof && temporalScore >= _temporalThreshold) {
      return true;
    }
    if (s.gridScore >= _gridThreshold) return true;
    if (s.gridScore >= _gridWithScoreThreshold && s.score >= _gridMinCombined) {
      return true;
    }
    if (s.score >= 0.20 && s.gridScore >= 0.02) return true;

    if (suppressBandingHeuristics) return false;

    if (s.faceRoiBandingScore >= 0.32 && s.gridScore >= 0.035) return true;
    if (s.bandingScore >= 0.24 &&
        s.highFrequencyScore < 0.22 &&
        s.score >= 0.34) {
      return true;
    }
    return false;
  }

  static Rect _clampRect(Rect r, int imageW, int imageH) {
    return Rect.fromLTRB(
      r.left.clamp(0.0, imageW.toDouble()),
      r.top.clamp(0.0, imageH.toDouble()),
      r.right.clamp(0.0, imageW.toDouble()),
      r.bottom.clamp(0.0, imageH.toDouble()),
    );
  }

  void _updateDirectedHeadTurn(Face face) {
    if (randomHeadTurnChallenge == null || _directedTurnCompleted) return;
    if (requireBlink && blinksDetected < requiredBlinks) return;

    // ML Kit yaw: negative ≈ user turned to THEIR left, positive ≈ THEIR right
    // (front/selfie camera; previous inverted check captured the wrong direction).
    final yawY = face.headEulerAngleY ?? 0.0;
    switch (randomHeadTurnChallenge!) {
      case ScanHeadTurnChallenge.turnLeft:
        if (yawY <= -directedTurnYawDegrees) {
          _directedTurnCompleted = true;
          if (kDebugMode) {
            debugPrint(
              '✅ Head turn LEFT detected (yaw=${yawY.toStringAsFixed(1)}°)',
            );
          }
        }
      case ScanHeadTurnChallenge.turnRight:
        if (yawY >= directedTurnYawDegrees) {
          _directedTurnCompleted = true;
          if (kDebugMode) {
            debugPrint(
              '✅ Head turn RIGHT detected (yaw=${yawY.toStringAsFixed(1)}°)',
            );
          }
        }
    }
  }

  void _updateDepthReplayGuard(Face face, {required double frameFaceRatio}) {
    final depth = DepthAnalysisService.analyzeDepth(
      face,
      frameFaceRatio: frameFaceRatio,
    );
    if (depth['isFake'] == true && has3DPoseEvidence == false) {
      _depthReplayBlocked = true;
    }
  }

  void _update3DPoseEvidence(Face face) {
    if (!require3DPoseEvidence) return;

    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    if (!_poseRangeInitialized) {
      _yawMin = _yawMax = yaw;
      _pitchMin = _pitchMax = pitch;
      _poseRangeInitialized = true;
    } else {
      if (yaw < _yawMin) _yawMin = yaw;
      if (yaw > _yawMax) _yawMax = yaw;
      if (pitch < _pitchMin) _pitchMin = pitch;
      if (pitch > _pitchMax) _pitchMax = pitch;
    }
    _poseSampleCount++;

    final landmarks = face.landmarks;
    final leftEye = landmarks[FaceLandmarkType.leftEye];
    final rightEye = landmarks[FaceLandmarkType.rightEye];
    final nose = landmarks[FaceLandmarkType.noseBase];
    if (leftEye != null && rightEye != null && nose != null) {
      final eyeMidX = (leftEye.position.x + rightEye.position.x) / 2.0;
      final interEye = (rightEye.position.x - leftEye.position.x).abs();
      if (interEye > 8) {
        final noseShift = (nose.position.x - eyeMidX).abs() / interEye;
        if (noseShift >= 0.12) _landmarkAsymmetryHits++;
        if (noseShift >= 0.06 && yaw.abs() >= 5) _landmarkProfileHits++;
      }
    }

    final leftEar = landmarks[FaceLandmarkType.leftEar];
    final rightEar = landmarks[FaceLandmarkType.rightEar];
    if (yaw.abs() >= 8) {
      if (leftEar != null && rightEar == null) _earProfileHits++;
      if (rightEar != null && leftEar == null) _earProfileHits++;
    }
  }

  void _updateMicroMotion(Face face) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0;
    final box = face.boundingBox;
    final cx = box.left + box.width / 2;
    final cy = box.top + box.height / 2;

    if (_lastYaw != null &&
        _lastPitch != null &&
        _lastCenterX != null &&
        _lastCenterY != null) {
      final dyaw = (yaw - _lastYaw!).abs();
      final dpitch = (pitch - _lastPitch!).abs();
      final dpos = math.sqrt(
        math.pow(cx - _lastCenterX!, 2) + math.pow(cy - _lastCenterY!, 2),
      );
      if (dyaw >= 1.2 || dpitch >= 1.2 || dpos >= 4.0) {
        microMotionEvents++;
      }
    }

    _lastYaw = yaw;
    _lastPitch = pitch;
    _lastCenterX = cx;
    _lastCenterY = cy;
  }

  String _distanceMessage(DistanceStatus status) {
    return DistanceCheckService.phoneNotAtThreeFeetMessage(status);
  }

  String _directedTurnMessage() {
    return switch (randomHeadTurnChallenge) {
      ScanHeadTurnChallenge.turnLeft => requireBlink
          ? 'Blink OK — now turn head LEFT'
          : 'Turn your head slightly LEFT',
      ScanHeadTurnChallenge.turnRight => requireBlink
          ? 'Blink OK — now turn head RIGHT'
          : 'Turn your head slightly RIGHT',
      null => '',
    };
  }

  String _livenessMessage({
    required bool blinkOk,
    required bool motionOk,
    required bool poseOk,
    required bool turnOk,
    required bool centerOk,
    required LiveFaceBoxState boxState,
  }) {
    if (boxState == LiveFaceBoxState.spoof) {
      return 'Photo or video detected — use your live face only';
    }
    if (boxState == LiveFaceBoxState.checking) {
      if (AntiSpoofService.allModelsFailed) {
        return 'Anti-spoof unavailable — rebuild app';
      }
      if (!AntiSpoofService.isModelLoaded) {
        return 'Loading anti-spoof model…';
      }
      if (AntiSpoofService.captureTimePadOnly) {
        return 'Blink once — live check on capture';
      }
      return 'Checking live face (1–2 sec)…';
    }
    if (boxState != LiveFaceBoxState.live) {
      return 'Hold position in the circle';
    }
    if (!turnOk && randomHeadTurnChallenge != null) {
      return _directedTurnMessage();
    }
    if (!blinkOk && requireBlink) {
      return requiredBlinks > 1
          ? 'Blink $requiredBlinks times to verify'
          : 'Blink once to verify';
    }
    if (_videoReplayBlocked) {
      return _videoReplayReason.isNotEmpty
          ? _videoReplayReason
          : 'Video not allowed — show your live face';
    }
    if (_depthReplayBlocked) {
      return 'Flat photo or screen detected — show your live face';
    }
    if (!motionOk) {
      return 'Hold still…';
    }
    return 'Verified — capturing…';
  }

  bool get mayCaptureNow {
    final padOk = !enableStreamPad ||
        AntiSpoofService.allModelsFailed ||
        AntiSpoofService.captureTimePadOnly ||
        (!strictAutoScanPad &&
            (AntiSpoofService.useCaptureTimePadOnly || _streamPadDegraded)) ||
        (padLiveStreak >= minPadLiveStreak && _lastPadIsLive == true);
    return padOk &&
        liveFaceGateOpen &&
        !screenReplayDetected &&
        !padMarkedFake &&
        !_depthReplayBlocked &&
        !_videoReplayBlocked &&
        cleanLiveFrameStreak >= minCleanLiveFramesBeforeCapture &&
        microMotionEvents >= minMicroMotionEvents &&
        (!requireBlink || blinksDetected >= requiredBlinks) &&
        directedTurnOk &&
        centerReturnOk &&
        has3DPoseEvidence;
  }
}

class PreCaptureFrameResult {
  const PreCaptureFrameResult({
    required this.distanceStatus,
    required this.faceRatio,
    required this.distanceConfidence,
    required this.canCapture,
    required this.spoofBlocked,
    required this.livenessMessage,
    required this.boxState,
    this.padConfidence = 0.0,
  });

  final DistanceStatus distanceStatus;
  final double faceRatio;
  final double distanceConfidence;
  final bool canCapture;
  final bool spoofBlocked;
  final String livenessMessage;
  final LiveFaceBoxState boxState;
  final double padConfidence;
}
