/// ChessMamba step on Microsoft's native ONNX Runtime — several times the
/// pure-Dart speed, which is what gives the search room to look ahead. Not on
/// web; see native_step_model_stub.dart.
library;

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ort_fast_io.dart';
import 'step_model.dart';

class NativeMambaStepModel implements MambaStepModel {
  final OrtSession _session;
  final OrtRunOptions _runOptions;

  NativeMambaStepModel._(this._session, this._runOptions);

  static bool get isSupported => true;

  static NativeMambaStepModel create(Uint8List bytes, {int threads = 2}) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativeMambaStepModel._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions());
    } finally {
      options.release();
    }
  }

  @override
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs) async {
    final b = inputs.length;
    Int64List ids(int Function(MambaStepInput) f) =>
        Int64List.fromList([for (final x in inputs) f(x)]);
    final feeds = OrtInputs()
      ..add('from_sq', ids((x) => x.from), [b])
      ..add('to_sq', ids((x) => x.to), [b])
      ..add('promo', ids((x) => x.promo), [b])
      ..add('ply', ids((x) => x.ply), [b])
      ..add(
          'is_start',
          Float32List.fromList([for (final x in inputs) x.start ? 1 : 0]),
          [b, 1])
      ..add('state', packStates(inputs),
          [mambaDepth, b, mambaInner, mambaStateDim]);
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, feeds.values,
          ['policy', 'promo_logits', 'value', 'new_state']);
      return unpackOutputs(
          b,
          ortFloats(outputs[0]!, b * 4096),
          ortFloats(outputs[1]!, b * 5),
          ortFloats(outputs[2]!, b),
          ortFloats(outputs[3]!, mambaDepth * b * mambaInner * mambaStateDim));
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
