/// Web stand-in for native_step_model.dart: no dart:ffi in the browser, so
/// ChessMamba always runs on the pure-Dart interpreter there.
library;

import 'dart:typed_data';

import 'step_model.dart';

class NativeMambaStepModel implements MambaStepModel {
  static bool get isSupported => false;

  static NativeMambaStepModel create(Uint8List bytes, {int threads = 2}) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  void dispose() {}
}
