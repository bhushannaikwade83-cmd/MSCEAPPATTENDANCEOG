import 'package:tflite_flutter/tflite_flutter.dart' as tflite;

class Interpreter {
  final tflite.Interpreter _delegate;
  tflite.IsolateInterpreter? _isolateDelegate;

  Interpreter._(this._delegate);

  static Future<Interpreter> fromAsset(String assetName) async {
    final interpreter = await tflite.Interpreter.fromAsset(assetName);
    return Interpreter._(interpreter);
  }

  void run(Object input, Object output) {
    _delegate.run(input, output);
  }

  /// Runs inference in a background isolate to prevent UI thread blockage.
  Future<void> runInIsolate(Object input, Object output) async {
    _isolateDelegate ??= await tflite.IsolateInterpreter.create(address: _delegate.address);
    await _isolateDelegate!.run(input, output);
  }

  void close() {
    _isolateDelegate?.close();
    _delegate.close();
  }
}
