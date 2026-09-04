/// Maia3 backend on the high-level `OnnxModel` API of onnx_runtime_dart.
///
/// Same pure-Dart interpreter underneath as `onnx_model_dart.dart` (which is
/// kept compiling as the parity oracle — see
/// test/maia3_runtime_parity_test.dart), but through the package's public
/// `OnnxModel` facade, which adds:
///
/// - an isolate GEMM pool on native targets (`parallelize`/`runAsync`),
///   bitwise identical to the synchronous path but faster and off the UI
///   thread's critical path.
///
/// Batching stays a sequential loop on purpose: the maia3 int32 exports are
/// batch-FIXED (hardcoded batch-1 reshapes — native onnxruntime rejects
/// `tokens [N,64,96]` for N > 1, and a single-graph-run batch silently
/// blends positions). test/maia3_runtime_parity_test.dart guards this.
///
/// Model download/caching (`onnx/model_fetch.dart`) and position encoding
/// are untouched — only how the graph is *invoked* changed.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import 'onnx/model_fetch.dart';
import '../onnx_dart_experiments.dart';
import 'onnx_model.dart';
import 'variants.dart';

class Maia3OnnxRuntimeBackend extends Maia3OnnxModel {
  final Maia3Variant variant;

  /// Isolate workers for the GEMM pool (native only; ignored on web where
  /// isolates don't exist). 0 or 1 disables the pool entirely.
  final int isolateWorkers;

  OnnxModel? _model;

  Maia3OnnxRuntimeBackend({required this.variant, this.isolateWorkers = 4});

  @override
  Future<void> load() async {
    final bytes = await fetchModelBytes(variant.url, variant.onnxFile);
    final model = OnnxModel.fromBytes(bytes, experiments: onnxDartExperiments);
    if (!kIsWeb && isolateWorkers > 1) {
      await model.parallelize(workers: isolateWorkers);
    }
    _model = model;
  }

  @override
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo) async {
    final model = _model;
    if (model == null) throw StateError('Model not loaded');

    // runAsync == run when no isolate pool was set up (web / workers <= 1).
    final out = await model.runAsync({
      'tokens': Tensor.float(tokens, [1, 64, 96]),
      'self_elo': Tensor.int64(Int64List.fromList([selfElo]), [1]),
      'oppo_elo': Tensor.int64(Int64List.fromList([oppoElo]), [1]),
    }, [
      'logits_move',
      'logits_value',
    ]);
    return InferenceResult(
      logitsMove: out['logits_move']!.f!,
      logitsValue: out['logits_value']!.f!,
    );
  }

  @override
  Future<List<InferenceResult>> inferBatch(List<Float32List> tokensList,
      List<int> selfElos, List<int> oppoElos) async {
    // Sequential on purpose — see the library comment: the export is
    // batch-fixed, so a single [N,...] graph run is silently wrong.
    return [
      for (int i = 0; i < tokensList.length; i++)
        await infer(tokensList[i], selfElos[i], oppoElos[i]),
    ];
  }

  @override
  Future<void> close() async {
    _model?.dispose();
    _model = null;
  }
}
