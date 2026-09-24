/// The photo classifiers on Microsoft's native ONNX Runtime (FFI) — the fast
/// path on Android, iOS and desktop. Web gets photo_ort_stub.dart instead.
library;

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../../engines/ort_fast_io.dart';

class NativePhotoModel {
  final OrtSession _session;
  final OrtRunOptions _runOptions;

  NativePhotoModel._(this._session, this._runOptions);

  static bool get isSupported => true;

  /// Loads [bytes] (an ONNX model with input `input`, output `logits`).
  /// Throws when the ONNX Runtime library cannot be loaded.
  static NativePhotoModel load(Uint8List bytes, {int threads = 2}) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativePhotoModel._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions());
    } finally {
      options.release();
    }
  }

  /// Logits for a batch shaped [shape] (NCHW).
  Float32List run(Float32List input, List<int> shape) {
    final feeds = OrtInputs()..add('input', input, shape);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, feeds.values, ['logits']);
      return ortAllFloats(outputs[0]!);
    } finally {
      feeds.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  void dispose() {
    _runOptions.release();
    _session.release();
  }
}
