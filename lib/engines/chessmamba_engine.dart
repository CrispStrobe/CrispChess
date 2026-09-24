/// ChessMamba — a selective state-space network (Mamba/S6) that reads a game
/// as a sequence of moves, plus its own policy-guided search. By TobiasLogic,
/// MIT (huggingface.co/TobiasLogic/chessmamba); weights exported to ONNX by
/// tool/kaggle/chess-lm-onnx/export_chess_lms.py.
///
/// It never sees the board, only the moves, so it can only play games that
/// began from the standard starting position. For anything else — a FEN, a
/// puzzle, Chess960 — it hands the position to the built-in engine rather
/// than guess.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_engine.dart';
import 'chessmamba/native_step_model_stub.dart'
    if (dart.library.ffi) 'chessmamba/native_step_model.dart';
import 'chessmamba/search.dart';
import 'chessmamba/step_model.dart';
import 'dart_engine.dart';
import 'maia3_dart/onnx/model_fetch.dart';
import 'uci_position.dart';

const String chessMambaModelUrl =
    'https://huggingface.co/cstr/chessmamba-onnx/resolve/main/chessmamba_step_batch.onnx';
const String _modelFile = 'chessmamba_step_batch.onnx';
const String _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Pawns (White's view) for a value in -1..1 (side to move), through the
/// same logistic curve the Human Lens uses to turn pawns into expectations.
double mambaValueToPawns(double value, {required bool whiteToMove}) {
  final e = ((value.clamp(-0.999, 0.999)) + 1) / 2;
  final pawns = math.log(e / (1 - e)) / 0.368208;
  return whiteToMove ? pawns : -pawns;
}

class ChessMambaEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);

  /// Try native ONNX Runtime first where it exists.
  static bool preferNative = true;

  /// Lets tests supply the step model (and so skip the download).
  final Future<MambaStepModel> Function()? modelFactory;

  MambaStepModel? _model;
  bool _native = false;
  MambaSearcher? _searcher;
  DartEngine? _fallback;
  bool _stopRequested = false;

  /// Nodes along the line last searched: [_nodes][i] is the model's output
  /// after [_line] up to i moves (i = 0 is the start step).
  List<String> _line = [];
  final List<MambaNode> _nodes = [];

  /// First move index the nodes cover when the game outgrew the model's
  /// 96-ply window (native only; see [_rootFor]).
  int _windowStart = 0;

  ChessMambaEngine({this.modelFactory});

  @override
  String get name => 'ChessMamba';
  @override
  String get version => '1.0';
  @override
  String get license => 'MIT';
  // Measured: about even with the built-in engine at level 4 (12 games at
  // 1 s a move), with or without its search.
  @override
  int get estimatedElo => 1100;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // Search steps run on the calling isolate on the pure-Dart backend.
  @override
  bool get canPonder => false;

  /// Which runtime the model runs on, for diagnostics.
  String get backendName => _native ? 'native ONNX Runtime' : 'pure Dart';

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      _model = modelFactory != null ? await modelFactory!() : await _load();
      _searcher = MambaSearcher(_model!);
      await _startNode();
      _stateNotifier.value = EngineState.ready;
      debugPrint('[ChessMamba] Ready ($backendName)');
    } catch (e) {
      debugPrint('[ChessMamba] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  Future<MambaStepModel> _load() async {
    final bytes = await fetchModelBytes(chessMambaModelUrl, _modelFile);
    if (preferNative && NativeMambaStepModel.isSupported) {
      try {
        final native = NativeMambaStepModel.create(bytes);
        _native = true;
        return native;
      } catch (e) {
        debugPrint('[ChessMamba] Native runtime unavailable, using Dart: $e');
      }
    }
    return DartMambaStepModel(bytes);
  }

  Future<MambaNode> _startNode() async {
    final out = await _model!.step(
        from: 0, to: 0, promo: 0, ply: 0, start: true, state: mambaZeroState());
    return MambaNode(out, 0);
  }

  /// The board and the model's node for the position of [command], or null
  /// when the game did not start from the standard position.
  ///
  /// Up to 96 plies the model's state simply advances one step per move and
  /// is reused from the previous call. Past that, upstream re-reads only the
  /// last 96 moves each time; that costs 96 steps a move, fine on native
  /// ONNX Runtime but seconds on the pure-Dart interpreter, which instead keeps
  /// stepping (the model clamps the position embedding, so this is supported,
  /// only not what it was tuned on).
  Future<(chess.Chess, MambaNode)?> _rootFor(String command) async {
    final parsed = parsePositionCommand(command);
    if (parsed.baseFen != _startFen) return null;
    final moves = parsed.moves;
    final windowStart = _native && moves.length > mambaMaxPlies
        ? moves.length - mambaMaxPlies
        : 0;

    // Reuse the longest shared prefix of the cached line.
    var shared = 0;
    if (windowStart == _windowStart && _nodes.isNotEmpty) {
      final limit = math.min(_line.length, moves.length);
      while (shared < limit && _line[shared] == moves[shared]) {
        shared++;
      }
      if (shared < windowStart) shared = windowStart;
    } else {
      shared = windowStart;
      _nodes.clear();
    }
    if (_nodes.isEmpty) {
      _nodes.add(await _startNode());
    } else {
      _nodes.removeRange(shared - windowStart + 1, _nodes.length);
    }
    _windowStart = windowStart;

    final board = chess.Chess();
    for (var i = 0; i < moves.length; i++) {
      final uci = moves[i];
      final m = board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4, 5),
      });
      if (!m) {
        // Keep the cache consistent: drop it rather than leave states that no
        // longer match the remembered line.
        _nodes.clear();
        _line = [];
        return null;
      }
      if (i < shared) continue;
      final prev = _nodes.last;
      final out = await _model!.step(
        from: mambaSquare(uci.substring(0, 2)),
        to: mambaSquare(uci.substring(2, 4)),
        promo: mambaPromoIndex[uci.length > 4 ? uci[4] : null] ?? 0,
        ply: math.min(prev.ply + 1, mambaMaxPlies),
        start: false,
        state: prev.output.state,
      );
      _nodes.add(MambaNode(out, prev.ply + 1));
    }
    _line = List.of(moves);
    return (board, _nodes.last);
  }

  Future<DartEngine> _fallbackEngine() async {
    final e = _fallback ??= DartEngine();
    if (e.state == EngineState.idle) await e.initialize();
    return e;
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_model == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;
    _stopRequested = false;
    try {
      final root = await _rootFor(positionCommand);
      if (root == null) {
        debugPrint('[ChessMamba] Not a game from the start position; '
            'using the built-in engine');
        final fb = await _fallbackEngine();
        return await fb.bestMove(positionCommand,
            depth: depth, moveTime: moveTime, skillLevel: skillLevel);
      }
      final (board, node) = root;
      final level = skillLevel ?? 20;
      final result = await _searcher!.search(
        board,
        node,
        budget: moveTime ?? thinkTimeForLevel(level),
        // The weakest levels play the network's first instinct.
        policyOnly: level <= 3,
        depthLimit: depth,
        shouldStop: () => _stopRequested,
      );
      if (result.bestMove == null) throw StateError('No legal moves');
      return result.bestMove!;
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) async* {
    if (_model == null) return;
    _stateNotifier.value = EngineState.thinking;
    _stopRequested = false;
    try {
      final root = await _rootFor(positionCommand);
      if (root == null) {
        yield* (await _fallbackEngine())
            .analyze(positionCommand, depth: depth, infinite: infinite);
        return;
      }
      final (board, node) = root;
      final white = board.turn == chess.Color.WHITE;
      yield EvalInfo(
        score: mambaValueToPawns(node.output.value, whiteToMove: white),
        depth: 0,
        bestMove: MambaSearcher.priors(board, node).firstOrNull?.$1 == null
            ? null
            : _uciOf(MambaSearcher.priors(board, node).first.$1),
      );
      final updates = StreamController<EvalInfo>();
      final done = _searcher!
          .search(
            board,
            node,
            budget: infinite ? const Duration(minutes: 10) : kFixedDepthTimeCap,
            depthLimit: depth,
            onDepth: (r) => updates.add(EvalInfo(
              score: mambaValueToPawns(r.score, whiteToMove: white),
              depth: r.depth,
              bestMove: r.bestMove,
              pv: r.bestMove,
            )),
            shouldStop: () => _stopRequested,
          )
          .whenComplete(updates.close);
      yield* updates.stream;
      await done;
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }

  static String _uciOf(chess.Move m) =>
      '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';

  @override
  void stop() {
    _stopRequested = true;
    _fallback?.stop();
  }

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _stopRequested = true;
    _model?.dispose();
    _model = null;
    _fallback?.dispose();
    _stateNotifier.value = EngineState.disposed;
  }
}
