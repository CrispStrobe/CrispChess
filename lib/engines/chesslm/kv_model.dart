/// A causal language model exported with its KV cache (see
/// tool/kaggle/chess-lm-kv/export_chess_lm_kv.py):
///
///   (input_ids [b, t], past_key_i / past_value_i [b, h, p, d])
///     -> (logits of the last position [b, vocab], present_* [b, h, p + t, d])
library;

import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../onnx_dart_experiments.dart';

/// The cache for a batch: one [b, h, len, d] tensor per layer and k/v,
/// flattened, in `past_key_0, past_value_0, past_key_1, ...` order.
class KvCache {
  final int batch, heads, length, headDim;
  final List<Float32List> tensors;

  const KvCache(this.batch, this.heads, this.length, this.headDim, this.tensors);

  factory KvCache.empty(int layers, int heads, int headDim, {int batch = 1}) =>
      KvCache(batch, heads, 0, headDim,
          List.generate(2 * layers, (_) => Float32List(0)));

  /// The first [len] positions (batch 1 only).
  KvCache truncate(int len) {
    if (len >= length) return this;
    assert(batch == 1);
    return KvCache(batch, heads, len, headDim, [
      for (final t in tensors)
        () {
          final out = Float32List(heads * len * headDim);
          for (var h = 0; h < heads; h++) {
            out.setRange(h * len * headDim, (h + 1) * len * headDim, t,
                h * length * headDim);
          }
          return out;
        }()
    ]);
  }

  /// Rows [rows] of this cache, as a new batch (a row may repeat).
  KvCache gather(List<int> rows) {
    final per = heads * length * headDim;
    return KvCache(rows.length, heads, length, headDim, [
      for (final t in tensors)
        () {
          final out = Float32List(rows.length * per);
          for (var i = 0; i < rows.length; i++) {
            out.setRange(i * per, (i + 1) * per, t, rows[i] * per);
          }
          return out;
        }()
    ]);
  }
}

class KvStep {
  /// [b * vocab] logits for each row's last position.
  final Float32List logits;
  final KvCache cache;
  const KvStep(this.logits, this.cache);
}

abstract class KvLanguageModel {
  int get layers;
  int get kvHeads;
  int get headDim;
  int get vocab;

  /// Feeds [tokens] ([past.batch] rows of [t] tokens each, row-major) after
  /// [past].
  Future<KvStep> run(Int64List tokens, int t, KvCache past);

  void dispose();
}

/// Pure-Dart interpreter backend: every platform, web included.
class DartKvLanguageModel implements KvLanguageModel {
  final OnnxModel _model;
  @override
  final int layers, kvHeads, headDim, vocab;

  DartKvLanguageModel(Uint8List bytes,
      {required this.layers,
      required this.kvHeads,
      required this.headDim,
      required this.vocab})
      : _model = OnnxModel.fromBytes(bytes, experiments: onnxDartExperiments);

  @override
  Future<KvStep> run(Int64List tokens, int t, KvCache past) async {
    final b = past.batch;
    final feeds = <String, Tensor>{
      'input_ids': Tensor.int64(tokens, [b, t]),
    };
    for (var i = 0; i < layers; i++) {
      for (final (j, kv) in [(0, 'key'), (1, 'value')]) {
        feeds['past_${kv}_$i'] = Tensor.float(
            past.tensors[2 * i + j], [b, kvHeads, past.length, headDim]);
      }
    }
    final names = [
      'logits',
      for (var i = 0; i < layers; i++) ...['present_key_$i', 'present_value_$i']
    ];
    final out = await _model.runAsync(feeds, names);
    return KvStep(
        out['logits']!.f!,
        KvCache(b, kvHeads, past.length + t, headDim,
            [for (final n in names.skip(1)) out[n]!.f!]));
  }

  @override
  void dispose() => _model.dispose();
}
