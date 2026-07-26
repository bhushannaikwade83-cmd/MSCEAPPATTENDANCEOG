/// Prevents overlapping camera frame work (avoids UI jank / hangs on 2–4 GB phones).
class CameraStreamFrameGate {
  bool _busy = false;
  DateTime? _lastAccepted;

  bool shouldSkip({
    required Duration minGap,
    bool pipelineBusy = false,
  }) {
    if (_busy || pipelineBusy) return true;
    final last = _lastAccepted;
    if (last != null && DateTime.now().difference(last) < minGap) {
      return true;
    }
    return false;
  }

  void markStarted() {
    _busy = true;
    _lastAccepted = DateTime.now();
  }

  void markFinished() {
    _busy = false;
  }

  void reset() {
    _busy = false;
    _lastAccepted = null;
  }
}
