/// One recurrent step of ChessMamba (MIT, TobiasLogic/chessmamba): feed a
/// move, get the next-move policy, a value and the updated state.
///
/// The network reads a game as a sequence of moves — never the board — and
/// carries a fixed-size state from move to move, so a step costs the same at
/// move 5 as at move 50. The ONNX graph is exported by
/// tool/kaggle/chess-lm-onnx/export_chess_lms.py.
library;

import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../onnx_dart_experiments.dart';

/// Layers x inner width x state width of the published checkpoint.
const int mambaDepth = 10;
const int mambaInner = 768;
const int mambaStateDim = 16;
const int mambaStateSize = mambaDepth * mambaInner * mambaStateDim;

/// Plies the position embedding covers; later plies reuse the last one.
const int mambaMaxPlies = 96;

/// Promotion ids as the model numbers them.
const Map<String?, int> mambaPromoIndex = {null: 0, 'q': 1, 'r': 2, 'b': 3, 'n': 4};

class MambaOutput {
  /// 4096 logits, index from * 64 + to, squares a1 = 0 .. h8 = 63.
  final Float32List policy;

  /// 5 logits: none, queen, rook, bishop, knight.
  final Float32List promo;

  /// Expected result for the side to move, -1..1.
  final double value;

  /// State after this step, to feed to the next one.
  final Float32List state;

  const MambaOutput(this.policy, this.promo, this.value, this.state);
}

/// One step to take: a move (or the start token) from a state.
class MambaStepInput {
  final int from, to, promo, ply;
  final bool start;
  final Float32List state;
  const MambaStepInput({
    required this.from,
    required this.to,
    required this.promo,
    required this.ply,
    required this.start,
    required this.state,
  });
}

abstract class MambaStepModel {
  /// Several steps in one call — each from its own state. The search expands
  /// all of a node's candidate moves at once: the weights are read once for
  /// the whole batch, so ten children cost about 1.4 single steps natively.
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs);

  void dispose();
}

extension MambaSingleStep on MambaStepModel {
  Future<MambaOutput> step({
    required int from,
    required int to,
    required int promo,
    required int ply,
    required bool start,
    required Float32List state,
  }) async =>
      (await stepBatch([
        MambaStepInput(
            from: from, to: to, promo: promo, ply: ply, start: start, state: state)
      ]))
          .single;
}

/// The graph wants states as [layers, batch, inner, stateDim]; each input
/// holds its own [layers, 1, inner, stateDim]. Interleave per layer.
Float32List packStates(List<MambaStepInput> inputs) {
  const block = mambaInner * mambaStateDim;
  final b = inputs.length;
  final out = Float32List(mambaDepth * b * block);
  for (var l = 0; l < mambaDepth; l++) {
    for (var i = 0; i < b; i++) {
      out.setRange((l * b + i) * block, (l * b + i + 1) * block,
          inputs[i].state, l * block);
    }
  }
  return out;
}

/// Splits the batched outputs back into one [MambaOutput] per input.
List<MambaOutput> unpackOutputs(int b, Float32List policy, Float32List promo,
    Float32List value, Float32List state) {
  const block = mambaInner * mambaStateDim;
  return [
    for (var i = 0; i < b; i++)
      MambaOutput(
        Float32List.sublistView(policy, i * 4096, (i + 1) * 4096),
        Float32List.sublistView(promo, i * 5, (i + 1) * 5),
        value[i],
        () {
          final s = Float32List(mambaDepth * block);
          for (var l = 0; l < mambaDepth; l++) {
            s.setRange(l * block, (l + 1) * block, state, (l * b + i) * block);
          }
          return s;
        }(),
      ),
  ];
}

/// Pure-Dart interpreter backend: every platform, web included.
class DartMambaStepModel implements MambaStepModel {
  final OnnxModel _model;

  DartMambaStepModel(Uint8List bytes)
      : _model = OnnxModel.fromBytes(bytes, experiments: onnxDartExperiments);

  @override
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs) async {
    final b = inputs.length;
    Tensor ids(int Function(MambaStepInput) f) =>
        Tensor.int64(Int64List.fromList([for (final x in inputs) f(x)]), [b]);
    final out = await _model.runAsync({
      'from_sq': ids((x) => x.from),
      'to_sq': ids((x) => x.to),
      'promo': ids((x) => x.promo),
      'ply': ids((x) => x.ply),
      'is_start': Tensor.float(
          Float32List.fromList([for (final x in inputs) x.start ? 1 : 0]),
          [b, 1]),
      'state': Tensor.float(
          packStates(inputs), [mambaDepth, b, mambaInner, mambaStateDim]),
    }, ['policy', 'promo_logits', 'value', 'new_state']);
    return unpackOutputs(b, out['policy']!.f!, out['promo_logits']!.f!,
        out['value']!.f!, out['new_state']!.f!);
  }

  @override
  void dispose() => _model.dispose();
}
