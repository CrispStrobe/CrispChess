/// Web stand-in for native_kv_model.dart: no dart:ffi in the browser, so the
/// language-model bots run on the pure-Dart interpreter there.
library;

import 'dart:typed_data';

import 'kv_model.dart';

class NativeKvLanguageModel implements KvLanguageModel {
  static bool get isSupported => false;

  static NativeKvLanguageModel create(Uint8List bytes,
          {required int layers,
          required int kvHeads,
          required int headDim,
          required int vocab,
          int threads = 2}) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  int get layers => 0;
  @override
  int get kvHeads => 0;
  @override
  int get headDim => 0;
  @override
  int get vocab => 0;

  @override
  Future<KvStep> run(Int64List tokens, int t, KvCache past) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  @override
  void dispose() {}
}
