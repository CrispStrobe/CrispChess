/// Searchless-chess transformer on native ONNX Runtime (not on web).
library;

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ort_fast_io.dart';
import 'model.dart';

class NativeSearchlessModel implements SearchlessModel {
  final OrtSession _session;
  final OrtRunOptions _runOptions;
  NativeSearchlessModel._(this._session, this._runOptions);

  static bool get isSupported => true;

  static NativeSearchlessModel create(Uint8List bytes, {int threads = 2}) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativeSearchlessModel._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions());
    } finally {
      options.release();
    }
  }

  @override
  Future<Float32List> run(Int64List tokens, int rows) async {
    final feeds = OrtInputs()
      ..add('tokens', tokens, [rows, searchlessSequenceLength]);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, feeds.values, ['log_probs']);
      return ortFloats(outputs[0]!, rows * searchlessBuckets);
    } finally {
      feeds.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  @override
  void dispose() {
    _runOptions.release();
    _session.release();
  }
}
