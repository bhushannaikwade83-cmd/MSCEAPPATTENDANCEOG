/// Limits setState during live camera preview (cuts jank + heat on 2–4 GB phones).
class StreamUiThrottle {
  DateTime? _lastUpdate;

  void reset() => _lastUpdate = null;

  bool shouldUpdate({required bool force, required int minGapMs}) {
    if (force) {
      _lastUpdate = DateTime.now();
      return true;
    }
    final now = DateTime.now();
    if (_lastUpdate == null ||
        now.difference(_lastUpdate!).inMilliseconds >= minGapMs) {
      _lastUpdate = now;
      return true;
    }
    return false;
  }
}
