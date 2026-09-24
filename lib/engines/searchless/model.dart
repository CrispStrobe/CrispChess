/// The searchless-chess action-value transformer as an ONNX graph:
/// tokens int64 [b, 79] -> log_probs float32 [b, 128] (return buckets).
library;

import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../onnx_dart_experiments.dart';

const int searchlessSequenceLength = 79;
const int searchlessBuckets = 128;

abstract class SearchlessModel {
  /// Log-probabilities of the return buckets for each of [rows] sequences.
  Future<Float32List> run(Int64List tokens, int rows);
  void dispose();
}

class DartSearchlessModel implements SearchlessModel {
  final OnnxModel _model;
  DartSearchlessModel(Uint8List bytes)
      : _model = OnnxModel.fromBytes(bytes, experiments: onnxDartExperiments);

  @override
  Future<Float32List> run(Int64List tokens, int rows) async {
    final out = await _model.runAsync(
        {'tokens': Tensor.int64(tokens, [rows, searchlessSequenceLength])},
        ['log_probs']);
    return out['log_probs']!.f!;
  }

  @override
  void dispose() => _model.dispose();
}
