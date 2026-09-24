/// Web stand-in for native_model.dart: the pure-Dart interpreter runs there.
library;

import 'dart:typed_data';

import 'model.dart';

class NativeSearchlessModel implements SearchlessModel {
  static bool get isSupported => false;
  static NativeSearchlessModel create(Uint8List bytes, {int threads = 2}) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');
  @override
  Future<Float32List> run(Int64List tokens, int rows) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');
  @override
  void dispose() {}
}
