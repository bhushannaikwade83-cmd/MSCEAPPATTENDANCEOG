import 'package:flutter/material.dart';

/// Real-time face box color from ML Kit + TFLite anti-spoof (MiniFAS / Silent-Face).
enum LiveFaceBoxState {
  /// No face in frame.
  none,

  /// Face found but wrong distance / not centered.
  distance,

  /// Anti-spoof model running or warming up.
  checking,

  /// PAD says live person.
  live,

  /// PAD says photo, screen, or video replay.
  spoof,
}

extension LiveFaceBoxStateStyle on LiveFaceBoxState {
  Color get borderColor => switch (this) {
        LiveFaceBoxState.live => Colors.greenAccent,
        LiveFaceBoxState.spoof => Colors.redAccent,
        LiveFaceBoxState.checking => Colors.amberAccent,
        LiveFaceBoxState.distance => Colors.orangeAccent,
        LiveFaceBoxState.none => Colors.white38,
      };

  String get label => switch (this) {
        LiveFaceBoxState.live => 'REAL',
        LiveFaceBoxState.spoof => 'FAKE',
        LiveFaceBoxState.checking => 'CHECKING…',
        LiveFaceBoxState.distance => 'NOT 3 FT',
        LiveFaceBoxState.none => '',
      };
}
