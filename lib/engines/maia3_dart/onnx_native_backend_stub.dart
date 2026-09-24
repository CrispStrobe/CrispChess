/// Web stand-in for onnx_native_backend.dart: there is no dart:ffi in the
/// browser, so Maia always runs on the pure-Dart interpreter there.
library;

import 'dart:typed_data';

import 'onnx_model.dart';
import 'variants.dart';

class Maia3NativeBackend extends Maia3OnnxModel {
  Maia3NativeBackend({required Maia3Variant variant, int threads = 4});

  static bool get isSupported => false;

  @override
  Future<void> load() =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  Future<InferenceResult> infer(Float32List tokens, int selfElo, int oppoElo) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  Future<void> close() async {}
}
