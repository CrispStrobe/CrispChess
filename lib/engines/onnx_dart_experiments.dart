import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// Comma-separated opt-in strategies for hardware-specific benchmark builds.
///
/// Example: `--dart-define=ONNX_DART_EXPERIMENTS=inPlaceRelu,cacheAttributes`.
/// Production builds omit the define and retain the proven default kernels.
Set<OnnxExperiment> get onnxDartExperiments {
  const raw = String.fromEnvironment('ONNX_DART_EXPERIMENTS');
  if (raw.isEmpty) return const {};
  return raw
      .split(',')
      .where((name) => name.isNotEmpty)
      .map((name) => OnnxExperiment.values.firstWhere(
            (value) => value.name == name,
            orElse: () => throw ArgumentError.value(
                name, 'ONNX_DART_EXPERIMENTS', 'unknown experiment'),
          ))
      .toSet();
}
