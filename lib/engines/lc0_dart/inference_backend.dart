import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../onnx_dart_experiments.dart';

abstract interface class Lc0InferenceBackend {
  Future<Map<String, Float32List>> run(Float32List planes, int batchSize);
  void dispose();
}

class DartLc0InferenceBackend implements Lc0InferenceBackend {
  final OnnxModel model;

  DartLc0InferenceBackend(this.model);

  static Future<DartLc0InferenceBackend> create(
      Uint8List bytes, int workers) async {
    final model = OnnxModel.fromBytes(bytes, experiments: onnxDartExperiments);
    if (workers > 1) await model.parallelize(workers: workers);
    return DartLc0InferenceBackend(model);
  }

  @override
  Future<Map<String, Float32List>> run(
      Float32List planes, int batchSize) async {
    final out = await model.runAsync(
      {
        '/input/planes': Tensor.float(planes, [batchSize, 112, 8, 8])
      },
      ['/output/policy', '/output/wdl'],
    );
    return {
      '/output/policy': out['/output/policy']!.f!,
      '/output/wdl': out['/output/wdl']!.f!,
    };
  }

  @override
  void dispose() => model.dispose();
}
