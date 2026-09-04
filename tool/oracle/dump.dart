/// Dump what this app's Lc0 pipeline computes, for comparison against lc0.
///
/// Reads `positions.txt` (move sequences from the initial position), and for
/// each one writes the network input planes, the policy over the legal moves
/// and the value. The planes come out in lc0's own representation — a 64-bit
/// mask plus the value its set bits carry — so they can be diffed against
/// lc0's `InputPlane` without a translation step in between.
///
///   dart run tool/oracle/dump.dart --model maia-1900.onnx \
///       --positions tool/oracle/positions.txt --out build/oracle/dart.json
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:crispchess/engines/lc0_dart/policy_map.dart' as policy;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

String _arg(List<String> args, String name, {String? fallback}) {
  final i = args.indexOf('--$name');
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  if (fallback != null) return fallback;
  stderr.writeln('missing --$name');
  exit(2);
}

/// A plane as lc0 stores it: which squares are set, and what value they hold.
///
/// Every plane this encoder produces is constant over its set squares, so the
/// pair is lossless — asserted rather than assumed.
Map<String, Object> _planeToMask(Float32List planes, int plane) {
  var mask = BigInt.zero;
  double? value;
  for (var i = 0; i < 64; i++) {
    final v = planes[plane * 64 + i];
    if (v == 0.0) continue;
    value ??= v;
    if ((v - value).abs() > 1e-9) {
      throw StateError('plane $plane is not constant over its set squares: '
          'saw $value and $v — the mask/value form cannot represent it');
    }
    mask |= BigInt.one << i;
  }
  return {
    'mask': mask.toRadixString(16),
    'value': value ?? 0.0,
  };
}

List<String> _legalMoves(chess.Chess board) => [
      for (final m in board.generate_moves())
        '${m.fromAlgebraic}${m.toAlgebraic}'
            '${m.promotion?.name.toLowerCase() ?? ''}'
    ];

void main(List<String> args) async {
  final modelPath = _arg(args, 'model');
  final positionsPath =
      _arg(args, 'positions', fallback: 'tool/oracle/positions.txt');
  final outPath = _arg(args, 'out', fallback: 'build/oracle/dart.json');
  final planesOnly = args.contains('--planes-only');

  OnnxModel? model;
  if (!planesOnly) {
    final bytes = File(modelPath).readAsBytesSync();
    model = OnnxModel.fromBytes(bytes);
    stderr.writeln('loaded ${modelPath.split('/').last} '
        '(${(bytes.length / 1048576).toStringAsFixed(1)} MB)');
  }

  final cases = <Map<String, Object?>>[];
  final lines = File(positionsPath).readAsLinesSync();
  for (final line in lines) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final tab = line.indexOf('\t');
    final name = tab < 0 ? line : line.substring(0, tab);
    final moves = tab < 0
        ? <String>[]
        : line.substring(tab + 1).split(' ').where((m) => m.isNotEmpty).toList();

    // Replay, keeping every position before the current one: that is the
    // history the encoder feeds to the network.
    final board = chess.Chess();
    final history = <String>[];
    for (final uci in moves) {
      history.add(board.fen);
      final ok = board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4),
      });
      if (ok == false) {
        stderr.writeln('$name: illegal move $uci — skipping this case');
        history.clear();
        break;
      }
    }
    if (moves.isNotEmpty && history.isEmpty) continue;

    final fen = board.fen;
    final legal = _legalMoves(board);
    final planes = encodePosition(fen, historyFens: history);

    final entry = <String, Object?>{
      'name': name,
      'fen': fen,
      'moves': moves,
      'legal': legal,
      'planes': [for (var p = 0; p < 112; p++) _planeToMask(planes, p)],
    };

    if (model != null && legal.isNotEmpty) {
      final out = model.run(
        {'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
        ['/output/policy', '/output/wdl'],
      );
      final logits = out['/output/policy']!.f!;
      final wdl = out['/output/wdl']!.f!;
      final isBlack = board.turn == chess.Color.BLACK;
      final moveToIndex = policy.getMoveToIndex();

      final raw = <String, double>{};
      for (final move in legal) {
        final lookup = isBlack ? policy.mirrorMove(move) : move;
        final idx = moveToIndex[lookup];
        raw[move] = idx != null ? logits[idx].toDouble() : -100.0;
      }
      final maxLogit = raw.values.reduce(max);
      var sum = 0.0;
      final weights = {
        for (final e in raw.entries) e.key: exp(e.value - maxLogit)
      };
      for (final w in weights.values) {
        sum += w;
      }
      entry['policy'] = {
        for (final e in weights.entries) e.key: e.value / sum
      };
      entry['logits'] = raw;
      entry['wdl'] = wdl.toList();
      entry['value'] = wdl[0] - wdl[2];
      entry['unmapped'] = [
        for (final move in legal)
          if (!moveToIndex.containsKey(isBlack ? policy.mirrorMove(move) : move))
            move
      ];
    }
    cases.add(entry);
    stderr.write('.');
  }
  stderr.writeln(' ${cases.length} positions');

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(const JsonEncoder().convert({'cases': cases}));
  stderr.writeln('wrote $outPath');
  model?.dispose();
}
