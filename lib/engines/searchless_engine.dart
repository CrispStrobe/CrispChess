/// DeepMind's searchless-chess transformers ("Grandmaster-Level Chess Without
/// Search", google-deepmind/searchless_chess: code Apache-2.0, weights
/// CC BY 4.0).
///
/// No search at all: the network looks at the position once per legal move
/// and predicts that move's win probability (a distribution over 128
/// buckets); the engine plays the best. All legal moves go through in one
/// batched call. The 270M model plays at a Lichess blitz rating of about
/// 2895; the 9M one runs anywhere.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_engine.dart';
import 'maia3_dart/onnx/model_fetch.dart';
import 'searchless/model.dart';
import 'searchless/native_model_stub.dart'
    if (dart.library.ffi) 'searchless/native_model.dart';
import 'searchless/tokenizer.dart';
import 'searchless/web_model_stub.dart'
    if (dart.library.js_interop) 'searchless/web_model.dart';
import 'uci_position.dart';

const String _base = 'https://huggingface.co/cstr/searchless-chess-onnx/resolve/main';

enum SearchlessSize {
  m9('9M', '9M/model.onnx', 36, false),
  m136('136M', '136M/model_fp16.onnx', 272, true),
  m270('270M', '270M/model_fp16.onnx', 540, true);

  final String label, file;
  final int downloadMb;

  /// Too large for phones and the browser.
  final bool desktopOnly;
  const SearchlessSize(this.label, this.file, this.downloadMb, this.desktopOnly);

  String get engineName => 'Searchless $label';
}

class SearchlessEngine implements ChessEngine {
  final SearchlessSize size;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final math.Random _random;
  static bool preferNative = true;

  /// Tests supply the model and tables instead of downloading them.
  final Future<(SearchlessModel, List<String>, List<double>)> Function()? loader;

  SearchlessModel? _model;
  Map<String, int> _actionOf = const {};
  List<double> _buckets = const [];

  SearchlessEngine(this.size, {this.loader, math.Random? random})
      : _random = random ?? math.Random();

  @override
  String get name => size.engineName;
  @override
  String get version => '1.0';
  @override
  String get license => 'Apache-2.0 / CC BY 4.0';
  @override
  // Only the 270M figure is published in the repository (Lichess blitz
  // against humans); the smaller ones are placeholders until measured.
  int get estimatedElo => switch (size) {
        SearchlessSize.m9 => 2000,
        SearchlessSize.m136 => 2400,
        SearchlessSize.m270 => 2895,
      };
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;
  @override
  bool get canPonder => false;

  String _backend = 'pure Dart';
  String get backendName => _backend;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final (model, actions, buckets) =
          loader != null ? await loader!() : await _load();
      _model = model;
      _actionOf = {for (var i = 0; i < actions.length; i++) actions[i]: i};
      _buckets = buckets;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Searchless] ${size.label} ready ($backendName)');
    } catch (e) {
      debugPrint('[Searchless] ${size.label} failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  Future<(SearchlessModel, List<String>, List<double>)> _load() async {
    List<T> json<T>(Uint8List b) => (jsonDecode(utf8.decode(b)) as List).cast<T>();
    final actions = json<String>(
        await fetchModelBytes('$_base/actions.json', 'searchless_actions.json'));
    final buckets = [
      for (final v in json<num>(await fetchModelBytes(
          '$_base/bucket_values.json', 'searchless_bucket_values.json')))
        v.toDouble()
    ];
    if (WebSearchlessModel.isSupported) {
      // The browser: ONNX Runtime Web downloads and caches the model itself.
      try {
        final m = await WebSearchlessModel.load(size.label, '$_base/${size.file}');
        _backend = 'ONNX Runtime Web';
        return (m as SearchlessModel, actions, buckets);
      } catch (e) {
        debugPrint('[Searchless] ONNX Runtime Web unavailable, using Dart: $e');
      }
    }
    final bytes = await fetchModelBytes('$_base/${size.file}',
        'searchless_${size.label}_${size.file.split('/').last}');
    if (preferNative && NativeSearchlessModel.isSupported) {
      try {
        final m = NativeSearchlessModel.create(bytes);
        _backend = 'native ONNX Runtime';
        return (m as SearchlessModel, actions, buckets);
      } catch (e) {
        debugPrint('[Searchless] Native runtime unavailable, using Dart: $e');
      }
    }
    return (DartSearchlessModel(bytes) as SearchlessModel, actions, buckets);
  }

  /// Win probability (0..1, for the side to move) of every legal move,
  /// keyed by UCI, as the paper's ActionValueEngine computes it — including
  /// its rule that a move allowing a draw by repetition is worth 0.5.
  Future<Map<String, double>> winProbabilities(String positionCommand) async {
    final board = _boardFor(positionCommand);
    final legal = board.generate_moves();
    if (legal.isEmpty) return const {};
    final fenTokens = tokenizeFen(pythonChessFen(board));
    final ucis = [
      for (final m in legal)
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
    ];
    final tokens = Int64List(ucis.length * searchlessSequenceLength);
    for (var i = 0; i < ucis.length; i++) {
      tokens.setAll(i * searchlessSequenceLength, fenTokens);
      tokens[i * searchlessSequenceLength + fenTokenCount] = _actionOf[ucis[i]]!;
    }
    final logProbs = await _model!.run(tokens, ucis.length);
    final out = <String, double>{};
    for (var i = 0; i < ucis.length; i++) {
      var p = 0.0;
      for (var k = 0; k < searchlessBuckets; k++) {
        p += math.exp(logProbs[i * searchlessBuckets + k]) * _buckets[k];
      }
      board.make_move(legal[i]);
      if (board.in_threefold_repetition) p = 0.5;
      board.undo_move();
      out[ucis[i]] = p;
    }
    return out;
  }

  chess.Chess _boardFor(String positionCommand) {
    final parsed = parsePositionCommand(positionCommand);
    final board = chess.Chess.fromFEN(parsed.baseFen);
    for (final uci in parsed.moves) {
      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        if (uci.length > 4) 'promotion': uci.substring(4, 5),
      });
    }
    return board;
  }

  /// Softmax temperature over win probabilities for a strength level, as the
  /// paper's engines take one: none (always the best move) at the top, more
  /// variety below.
  static double? temperatureFor(int level) =>
      level >= 20 ? null : 0.005 + (20 - level.clamp(0, 20)) * 0.01;

  @override
  Future<String> bestMove(String positionCommand,
      {int? depth, Duration? moveTime, int? skillLevel}) async {
    if (_model == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;
    try {
      final wins = await winProbabilities(positionCommand);
      if (wins.isEmpty) throw StateError('No legal moves');
      final t = temperatureFor(skillLevel ?? 20);
      if (t == null) {
        return wins.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
      final top = wins.values.reduce(math.max);
      final w = {for (final e in wins.entries) e.key: math.exp((e.value - top) / t)};
      final sum = w.values.fold(0.0, (a, b) => a + b);
      var r = _random.nextDouble() * sum;
      for (final e in w.entries) {
        r -= e.value;
        if (r <= 0) return e.key;
      }
      return w.keys.last;
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }

  /// One "depth": the best move and its win probability as an evaluation.
  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) async* {
    if (_model == null) return;
    final wins = await winProbabilities(positionCommand);
    if (wins.isEmpty) return;
    final best = wins.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final whiteToMove = _boardFor(positionCommand).turn == chess.Color.WHITE;
    final e = best.value.clamp(0.001, 0.999);
    final pawns = math.log(e / (1 - e)) / 0.368208;
    yield EvalInfo(
        score: whiteToMove ? pawns : -pawns,
        depth: 1,
        bestMove: best.key,
        pv: best.key);
  }

  @override
  void stop() {}
  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _model?.dispose();
    _model = null;
    _stateNotifier.value = EngineState.disposed;
  }
}

/// Searchless sizes offered on this platform.
List<SearchlessSize> get availableSearchlessSizes => [
      for (final s in SearchlessSize.values)
        if (!s.desktopOnly ||
            (!kIsWeb &&
                const {TargetPlatform.linux, TargetPlatform.macOS, TargetPlatform.windows}
                    .contains(defaultTargetPlatform)))
          s
    ];

SearchlessSize? searchlessSizeNamed(String name) {
  for (final s in SearchlessSize.values) {
    if (s.engineName == name) return s;
  }
  return null;
}
