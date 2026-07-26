import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/camera_face_overlay_mapper.dart';
import '../../core/live_face_box_state.dart';
import '../../services/distance_check_service.dart';

/// Colored rectangle aligned to the face on [CameraPreview].
class FaceTrackingBoxOverlay extends StatelessWidget {
  const FaceTrackingBoxOverlay({
    super.key,
    required this.analysisRect,
    required this.analysisSize,
    required this.boxState,
    this.cameraController,
    this.previewWidthOverHeight,
    this.mirrorHorizontally,
    this.padConfidence = 0.0,
    this.labelOverride,
  });

  /// Face bounds from ML Kit ([Face.boundingBox]).
  final Rect analysisRect;
  final Size analysisSize;
  final LiveFaceBoxState boxState;

  /// When set, letterbox math matches [CameraPreview] (recommended).
  final CameraController? cameraController;
  final double? previewWidthOverHeight;
  /// When null, derived from [cameraController] (iOS front = no mirror).
  final bool? mirrorHorizontally;
  final double padConfidence;
  final String? labelOverride;

  static LiveFaceBoxState stateForRegistration({
    required DistanceStatus distance,
    required bool distanceLocked,
    required bool canCapture,
  }) {
    if (distance == DistanceStatus.noFace) return LiveFaceBoxState.none;
    if (!DistanceCheckService.allowsCapture(distance) || !distanceLocked) {
      return LiveFaceBoxState.distance;
    }
    if (canCapture) return LiveFaceBoxState.live;
    return LiveFaceBoxState.checking;
  }

  static String? labelForDistanceGate({
    required DistanceStatus distance,
    required bool distanceLocked,
    required bool canCapture,
    bool requireBlink = true,
  }) {
    if (distance == DistanceStatus.noFace) return 'SHOW FACE';
    if (!DistanceCheckService.allowsCapture(distance)) {
      return distance == DistanceStatus.tooClosed ? 'TOO CLOSE' : 'TOO FAR';
    }
    if (!distanceLocked) return 'HOLD 3 FT';
    if (canCapture) return '3 FT OK';
    return requireBlink ? 'BLINK' : 'HOLD STILL';
  }

  /// Alias for older call sites.
  static String? labelForRegistration({
    required DistanceStatus distance,
    required bool distanceLocked,
    required bool canCapture,
  }) =>
      labelForDistanceGate(
        distance: distance,
        distanceLocked: distanceLocked,
        canCapture: canCapture,
      );

  bool _effectiveMirror() {
    if (mirrorHorizontally != null) return mirrorHorizontally!;
    if (cameraController != null) {
      return CameraFaceOverlayMapper.shouldMirrorFaceBoxOnPreview(
        cameraController!.description,
      );
    }
    return false;
  }

  double _previewAspect() {
    if (previewWidthOverHeight != null && previewWidthOverHeight! > 0) {
      return previewWidthOverHeight!;
    }
    if (cameraController != null &&
        cameraController!.value.isInitialized) {
      return CameraFaceOverlayMapper.previewWidthOverHeightFromController(
        cameraController!,
      );
    }
    return 3 / 4;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        final screenRect = CameraFaceOverlayMapper.mapToWidget(
          analysisRect: analysisRect,
          analysisSize: analysisSize,
          widgetSize: widgetSize,
          previewWidthOverHeight: _previewAspect(),
          mirrorHorizontally: _effectiveMirror(),
        );

        final color = boxState.borderColor;
        final label = labelOverride ?? boxState.label;

        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: screenRect.left,
              top: screenRect.top,
              width: screenRect.width,
              height: screenRect.height,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 3),
                  borderRadius: BorderRadius.circular(10),
                  color: boxState == LiveFaceBoxState.spoof
                      ? Colors.red.withValues(alpha: 0.12)
                      : boxState == LiveFaceBoxState.live
                          ? Colors.green.withValues(alpha: 0.08)
                          : boxState == LiveFaceBoxState.distance
                              ? Colors.orange.withValues(alpha: 0.06)
                              : null,
                ),
              ),
            ),
            if (label.isNotEmpty)
              Positioned(
                left: screenRect.left,
                top: screenRect.top > 28 ? screenRect.top - 28 : 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    (boxState == LiveFaceBoxState.live ||
                            boxState == LiveFaceBoxState.spoof) &&
                            padConfidence > 0
                        ? '$label ${(padConfidence * 100).toStringAsFixed(0)}%'
                        : label,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: (boxState == LiveFaceBoxState.live ||
                              boxState == LiveFaceBoxState.spoof)
                          ? 13
                          : 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
