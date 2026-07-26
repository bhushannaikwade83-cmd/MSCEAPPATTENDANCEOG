class Interpreter {
  Interpreter._();

  static Future<Interpreter> fromAsset(String assetName) async {
    throw UnsupportedError(
      'TFLite interpreter is not available on this platform.',
    );
  }

  void run(Object input, Object output) {
    throw UnsupportedError(
      'TFLite interpreter is not available on this platform.',
    );
  }

  Future<void> runInIsolate(Object input, Object output) async {
    throw UnsupportedError(
      'TFLite interpreter is not available on this platform.',
    );
  }

  void close() {}
}
