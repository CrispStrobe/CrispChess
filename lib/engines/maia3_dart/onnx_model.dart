/// ONNX model interface for Maia3 inference.
///
/// Platform-specific implementations:
/// - Native: uses onnxruntime package via FFI
/// - Web: uses onnxruntime-web via JS interop
library;

import 'dart:typed_data';

/// Result from a single model inference.
class InferenceResult {
  /// Policy logits — move probabilities (4352 values).
  final Float32List logitsMove;

  /// Value logits — [loss, draw, win] (3 values).
  final Float32List logitsValue;

  InferenceResult({required this.logitsMove, required this.logitsValue});
}

/// Abstract ONNX model for Maia3 inference.
abstract class Maia3OnnxModel {
  /// Load the model from bytes or URL.
  Future<void> load();

  /// Run inference on a single position.
  ///
  /// [tokens]: [64, 96] float32 tensor (6144 values)
  /// [selfElo]: player's ELO rating
  /// [oppoElo]: opponent's ELO rating
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo);

  /// Run inference on multiple positions (sequential, model has batch=1).
  Future<List<InferenceResult>> inferBatch(
      List<Float32List> tokensList,
      List<int> selfElos,
      List<int> oppoElos) async {
    final results = <InferenceResult>[];
    for (int i = 0; i < tokensList.length; i++) {
      results.add(await infer(tokensList[i], selfElos[i], oppoElos[i]));
    }
    return results;
  }

  /// Release model resources.
  Future<void> close();
}
