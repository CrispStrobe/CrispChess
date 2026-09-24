import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ort_fast_io.dart';
import 'inference_backend.dart';

/// Microsoft's optimized native runtime. Input and output values are released
/// after every call; the compiled graph and its allocator stay in the session.
class NativeLc0InferenceBackend implements Lc0InferenceBackend {
  final OrtSession _session;
  final OrtRunOptions _runOptions;

  NativeLc0InferenceBackend._(this._session, this._runOptions);

  static NativeLc0InferenceBackend create(Uint8List bytes, int workers) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(workers.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativeLc0InferenceBackend._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions());
    } finally {
      options.release();
    }
  }

  @override
  Future<Map<String, Float32List>> run(
      Float32List planes, int batchSize) async {
    final feeds = OrtInputs()
      ..add('/input/planes', planes, [batchSize, 112, 8, 8]);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(
        _runOptions,
        feeds.values,
        ['/output/policy', '/output/wdl'],
      );
      return {
        '/output/policy': ortAllFloats(outputs[0]!),
        '/output/wdl': ortAllFloats(outputs[1]!),
      };
    } finally {
      feeds.release();
      for (final output in outputs) {
        output?.release();
      }
    }
  }

  @override
  void dispose() {
    _runOptions.release();
    _session.release();
  }
}
