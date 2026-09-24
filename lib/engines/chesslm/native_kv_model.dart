/// KV-cache language model on native ONNX Runtime. Not on web; see
/// native_kv_model_stub.dart.
library;

import 'dart:typed_data';

import 'package:onnxruntime/onnxruntime.dart';

import '../ort_fast_io.dart';
import 'kv_model.dart';

class NativeKvLanguageModel implements KvLanguageModel {
  final OrtSession _session;
  final OrtRunOptions _runOptions;
  @override
  final int layers, kvHeads, headDim, vocab;

  NativeKvLanguageModel._(this._session, this._runOptions,
      {required this.layers,
      required this.kvHeads,
      required this.headDim,
      required this.vocab});

  static bool get isSupported => true;

  static NativeKvLanguageModel create(Uint8List bytes,
      {required int layers,
      required int kvHeads,
      required int headDim,
      required int vocab,
      int threads = 2}) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativeKvLanguageModel._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions(),
          layers: layers, kvHeads: kvHeads, headDim: headDim, vocab: vocab);
    } finally {
      options.release();
    }
  }

  @override
  Future<KvStep> run(Int64List tokens, int t, KvCache past) async {
    final b = past.batch;
    final feeds = OrtInputs()..add('input_ids', tokens, [b, t]);
    for (var i = 0; i < layers; i++) {
      feeds
        ..add('past_key_$i', past.tensors[2 * i],
            [b, kvHeads, past.length, headDim])
        ..add('past_value_$i', past.tensors[2 * i + 1],
            [b, kvHeads, past.length, headDim]);
    }
    final names = [
      'logits',
      for (var i = 0; i < layers; i++) ...['present_key_$i', 'present_value_$i']
    ];
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, feeds.values, names);
      final len = past.length + t;
      final per = b * kvHeads * len * headDim;
      return KvStep(ortFloats(outputs[0]!, b * vocab), KvCache(b, kvHeads, len,
          headDim, [for (final o in outputs.skip(1)) ortFloats(o!, per)]));
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
