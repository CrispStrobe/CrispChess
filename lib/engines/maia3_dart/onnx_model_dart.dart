/// Unified Maia3 ONNX model — one implementation for every platform.
///
/// Runs inference via a from-scratch Dart interpreter of the ONNX graph
/// (`onnx/`) instead of Microsoft's onnxruntime plugin. Model weights are
/// still downloaded at runtime and never bundled — only how they're
/// *executed* changed. See THIRD_PARTY_LICENSES.md for why: the weights'
/// authoritative license is AGPL-3.0, and this way no AGPL/GPL code (the
/// original CSSLab/maia3 model-execution code, nor a third party's
/// conversion of it) ever runs — only original Dart code implementing the
/// public ONNX operator specification, operating on downloaded data.
library;

import 'dart:typed_data';

import 'onnx/model_fetch.dart';
import 'onnx/onnx.pb.dart';
import 'onnx/onnx_graph.dart';
import 'onnx/tensor.dart';
import 'onnx_model.dart';
import 'variants.dart';

class Maia3DartOnnxModel extends Maia3OnnxModel {
  final Maia3Variant variant;
  OnnxGraphExecutor? _executor;

  Maia3DartOnnxModel({required this.variant});

  @override
  Future<void> load() async {
    final bytes = await fetchModelBytes(variant.url, variant.onnxFile);
    final model = ModelProto.fromBuffer(bytes);
    _executor = OnnxGraphExecutor(model);
  }

  @override
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo) async {
    final executor = _executor;
    if (executor == null) throw StateError('Model not loaded');

    final out = executor.run({
      'tokens': Tensor.float(tokens, [1, 64, 96]),
      'self_elo': Tensor.int64(Int64List.fromList([selfElo]), [1]),
      'oppo_elo': Tensor.int64(Int64List.fromList([oppoElo]), [1]),
    }, ['logits_move', 'logits_value']);

    return InferenceResult(
      logitsMove: out['logits_move']!.f!,
      logitsValue: out['logits_value']!.f!,
    );
  }

  @override
  Future<void> close() async {
    _executor = null;
  }
}
