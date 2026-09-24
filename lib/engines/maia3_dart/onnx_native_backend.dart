/// Maia3 on Microsoft's native ONNX Runtime (FFI).
///
/// Roughly 15-20x faster than the pure-Dart interpreter on the same model —
/// which is what makes the Human Lens rating ladder (a model pass per rating,
/// per move) feel instant rather than like a progress bar. Not available on
/// web, where dart:ffi does not exist; see onnx_native_backend_stub.dart.
library;

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ort_fast_io.dart';

import 'onnx/model_fetch.dart';
import 'onnx_model.dart';
import 'variants.dart';

/// The ONNX Runtime bundled with package:onnxruntime (1.15) refuses models
/// stamped IR version 10, the stamp the Maia exports carry. Nothing in them
/// needs IR 10 — it adds 4-bit types and function overloads, the graphs are
/// plain opset-18 — so relabel a copy as IR 9 for the native session.
///
/// `ir_version` is protobuf field 1, a varint, serialised first: `08 0A`.
/// Anything else is left alone and ONNX Runtime gives its own verdict.
Uint8List stampIrVersion9(Uint8List model) {
  if (model.length < 2 || model[0] != 0x08 || model[1] != 10) return model;
  return Uint8List.fromList(model)..[1] = 9;
}

class Maia3NativeBackend extends Maia3OnnxModel {
  final Maia3Variant variant;
  final int threads;

  OrtSession? _session;
  OrtRunOptions? _runOptions;

  Maia3NativeBackend({required this.variant, this.threads = 4});

  static bool get isSupported => true;

  @override
  Future<void> load() async {
    final bytes = stampIrVersion9(
        await fetchModelBytes(variant.url, variant.onnxFile));
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      _session = OrtSession.fromBuffer(bytes, options);
      _runOptions = OrtRunOptions();
    } finally {
      options.release();
    }
  }

  @override
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo) async {
    final session = _session;
    if (session == null) throw StateError('Model not loaded');
    // The int32 exports declare the ratings as int32; the pure-Dart
    // interpreter tolerates int64 there, native ONNX Runtime does not.
    final feeds = OrtInputs()
      ..add('tokens', tokens, [1, 64, 96])
      ..add('self_elo', Int32List.fromList([selfElo]), [1])
      ..add('oppo_elo', Int32List.fromList([oppoElo]), [1]);
    List<OrtValue?> outputs = const [];
    try {
      outputs =
          session.run(_runOptions!, feeds.values, ['logits_move', 'logits_value']);
      return InferenceResult(
        logitsMove: ortAllFloats(outputs[0]!),
        logitsValue: ortAllFloats(outputs[1]!),
      );
    } finally {
      feeds.release();
      for (final o in outputs) {
        o?.release();
      }
    }
  }

  @override
  Future<void> close() async {
    _runOptions?.release();
    _session?.release();
    _runOptions = null;
    _session = null;
  }
}
