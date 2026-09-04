/// This app's Lc0 pipeline, exposed over UCI so lc0 can play against it.
///
/// The encoder, the policy mapping and the MCTS are the ones the app ships —
/// imported, not reimplemented — so a result here is a result about the app.
/// What is left out is the Flutter wrapper around them (`Lc0Engine`), which is
/// state notifiers and a download, neither of which affects a move.
///
/// Two things make the comparison against lc0 fair:
///   * `go nodes N` runs exactly N MCTS playouts with no clock, so neither
///     side is being measured on how fast its ONNX runtime is.
///   * the position history is kept for the whole game, so the network gets
///     the same history planes lc0 would build.
///
///   dart run tool/oracle/uci_engine.dart --model maia-1900.onnx
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:crispchess/engines/lc0_dart/mcts.dart';
import 'package:crispchess/engines/lc0_dart/policy_map.dart' as policy;
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

late OnnxModel _model;
final _history = <String>[];
var _fen = chess.Chess.DEFAULT_POSITION;

List<String> _legalMoves(chess.Chess board) => [
      for (final m in board.generate_moves())
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
    ];

Future<NnEval> _evaluate(
    String fen, List<String> legalMoves, List<String> history) async {
  final planes = encodePosition(fen, historyFens: history);
  final out = _model.run(
    {'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
    ['/output/policy', '/output/wdl'],
  );
  final logits = out['/output/policy']!.f!;
  final wdl = out['/output/wdl']!.f!;
  final isBlack = fen.split(' ')[1] == 'b';
  final moveToIndex = policy.getMoveToIndex();

  final raw = <String, double>{};
  for (final move in legalMoves) {
    final lookup = isBlack ? policy.mirrorMove(move) : move;
    final idx = moveToIndex[lookup];
    raw[move] = idx != null ? logits[idx].toDouble() : -100.0;
  }
  final maxLogit = raw.values.reduce(max);
  final weights = {for (final e in raw.entries) e.key: exp(e.value - maxLogit)};
  final sum = weights.values.reduce((a, b) => a + b);
  return NnEval(
    policy: {for (final e in weights.entries) e.key: e.value / sum},
    value: wdl[0] - wdl[2],
  );
}

MctsPosition _positionAt(
    String rootFen, List<String> rootHistory, List<String> moves) {
  final board = chess.Chess.fromFEN(rootFen);
  final history = <String>[...rootHistory, rootFen];
  for (final uci in moves) {
    board.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
      if (uci.length > 4) 'promotion': uci.substring(4, 5),
    });
    history.add(board.fen);
  }
  history.removeLast();
  final legal = _legalMoves(board);
  if (legal.isEmpty) {
    return MctsPosition(
      fen: board.fen,
      legalMoves: const [],
      historyFens: history,
      terminalValue: board.in_check ? -1.0 : 0.0,
    );
  }
  if (board.in_draw || board.in_threefold_repetition) {
    return MctsPosition(
        fen: board.fen,
        legalMoves: legal,
        historyFens: history,
        terminalValue: 0.0);
  }
  return MctsPosition(
      fen: board.fen, legalMoves: legal, historyFens: history);
}

void _setPosition(List<String> tokens) {
  _history.clear();
  final board = chess.Chess();
  var i = 1;
  if (i < tokens.length && tokens[i] == 'startpos') {
    i++;
  } else if (i < tokens.length && tokens[i] == 'fen') {
    final fen = tokens.sublist(i + 1, min(i + 7, tokens.length)).join(' ');
    board.load(fen);
    i += 7;
  }
  if (i < tokens.length && tokens[i] == 'moves') {
    for (final uci in tokens.sublist(i + 1)) {
      _history.add(board.fen);
      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4, 5),
      });
    }
  }
  _fen = board.fen;
}

Future<void> _go(List<String> tokens) async {
  final board = chess.Chess.fromFEN(_fen);
  final legal = _legalMoves(board);
  if (legal.isEmpty) {
    stdout.writeln('bestmove 0000');
    return;
  }
  if (legal.length == 1) {
    stdout.writeln('bestmove ${legal.first}');
    return;
  }

  var nodes = 200; // the app's default when no skill level is set
  var moveTime = const Duration(hours: 1);
  for (var i = 0; i < tokens.length - 1; i++) {
    final value = int.tryParse(tokens[i + 1]);
    if (value == null) continue;
    if (tokens[i] == 'nodes') nodes = value;
    if (tokens[i] == 'movetime') moveTime = Duration(milliseconds: value);
  }

  final best = await mctsSearch(
    fen: _fen,
    legalMoves: legal,
    evaluate: _evaluate,
    historyFens: _history,
    positionAt: (moves) => _positionAt(_fen, _history, moves),
    config: MctsConfig(maxNodes: nodes, maxTime: moveTime, cpuct: 2.5),
  );
  stdout.writeln('bestmove $best');
}

Future<void> main(List<String> args) async {
  final modelIndex = args.indexOf('--model');
  if (modelIndex < 0 || modelIndex + 1 >= args.length) {
    stderr.writeln('usage: uci_engine.dart --model <weights.onnx>');
    exit(2);
  }
  _model = OnnxModel.fromBytes(File(args[modelIndex + 1]).readAsBytesSync());

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    final tokens = line.trim().split(RegExp(r'\s+'));
    switch (tokens.first) {
      case 'uci':
        stdout.writeln('id name CrispChess Lc0');
        stdout.writeln('id author CrispChess');
        stdout.writeln('uciok');
      case 'isready':
        stdout.writeln('readyok');
      case 'ucinewgame':
        _history.clear();
        _fen = chess.Chess.DEFAULT_POSITION;
      case 'position':
        _setPosition(tokens);
      case 'go':
        await _go(tokens);
      case 'quit':
        _model.dispose();
        return;
    }
  }
}
