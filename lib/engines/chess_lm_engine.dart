/// Language-model bots: small chess language models from the Hugging Face
/// Hub, each playing by writing the game as text and choosing among the legal
/// moves by how likely it finds each one's text.
///
/// Only permissively licensed models (MIT / Apache-2.0) are listed; each is
/// exported to ONNX with its KV cache (tool/kaggle/chess-lm-kv), tokenized in
/// Dart exactly as upstream (checked token for token), downloaded on first
/// use, and credited in NOTICE.md.
///
/// They are weak — the Chess LLM Arena rates the pool near 1100 on its own
/// scale, where an untrained Pythia scores 1058 — and that is the point: a
/// zoo of odd little opponents, not an engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import 'chess_engine.dart';
import 'chesslm/kv_model.dart';
import 'chesslm/native_kv_model_stub.dart'
    if (dart.library.ffi) 'chesslm/native_kv_model.dart';
import 'chesslm/prompt.dart';
import 'chesslm/scorer.dart';
import 'chesslm/tokenizer.dart';
import 'dart_engine.dart';
import 'maia3_dart/onnx/model_fetch.dart';
import 'uci_position.dart';

const String _zooBase = 'https://huggingface.co/cstr/chess-lm-zoo-onnx/resolve/main';
const String _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

class ChessLmSpec {
  /// Engine name shown in the app.
  final String name;

  /// Upstream model repository, author and licence, for the credits.
  final String repo, author, license;

  /// Folder in the zoo repository.
  final String folder;
  final String onnxFile;
  final ChessLmFormat format;
  final int layers, kvHeads, headDim, vocab, contextLength;
  final int downloadMb;

  /// Too large to download or run comfortably on a phone.
  final bool desktopOnly;
  final String description;

  const ChessLmSpec({
    required this.name,
    required this.repo,
    required this.author,
    required this.license,
    required this.folder,
    required this.onnxFile,
    required this.format,
    required this.layers,
    required this.kvHeads,
    required this.headDim,
    required this.vocab,
    required this.contextLength,
    required this.downloadMb,
    required this.description,
    this.desktopOnly = false,
  });

  String get onnxUrl => '$_zooBase/$folder/$onnxFile';
  String get tokenizerUrl => '$_zooBase/$folder/tokenizer.json';
}

class ChessLmEngine implements ChessEngine {
  final ChessLmSpec spec;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final math.Random _random;

  /// Try native ONNX Runtime first where it exists.
  static bool preferNative = true;

  /// Lets tests supply the model and tokenizer (and skip the download).
  final Future<(KvLanguageModel, ChessLmTokenizer)> Function()? loader;

  ChessLmScorer? _scorer;
  KvLanguageModel? _model;
  DartEngine? _fallback;
  bool _native = false;

  ChessLmEngine(this.spec, {this.loader, math.Random? random})
      : _random = random ?? math.Random();

  @override
  String get name => spec.name;
  @override
  String get version => '1.0';
  @override
  String get license => spec.license;
  @override
  int get estimatedElo => 800;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;
  @override
  bool get canPonder => false;

  String get backendName => _native ? 'native ONNX Runtime' : 'pure Dart';

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final (model, tokenizer) = loader != null ? await loader!() : await _load();
      _model = model;
      _scorer = ChessLmScorer(model, tokenizer, spec.format,
          contextLength: spec.contextLength);
      _stateNotifier.value = EngineState.ready;
      debugPrint('[ChessLm] ${spec.name} ready ($backendName)');
    } catch (e) {
      debugPrint('[ChessLm] ${spec.name} failed to load: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  Future<(KvLanguageModel, ChessLmTokenizer)> _load() async {
    final tokenizer = ChessLmTokenizer.fromJson(utf8.decode(await fetchModelBytes(
        spec.tokenizerUrl, '${spec.folder}_tokenizer.json')));
    final bytes = await fetchModelBytes(spec.onnxUrl, '${spec.folder}_${spec.onnxFile}');
    if (preferNative && NativeKvLanguageModel.isSupported) {
      try {
        final m = NativeKvLanguageModel.create(bytes,
            layers: spec.layers,
            kvHeads: spec.kvHeads,
            headDim: spec.headDim,
            vocab: spec.vocab);
        _native = true;
        return (m as KvLanguageModel, tokenizer);
      } catch (e) {
        debugPrint('[ChessLm] Native runtime unavailable, using Dart: $e');
      }
    }
    return (
      DartKvLanguageModel(bytes,
          layers: spec.layers,
          kvHeads: spec.kvHeads,
          headDim: spec.headDim,
          vocab: spec.vocab) as KvLanguageModel,
      tokenizer
    );
  }

  /// Probability of each legal move (UCI), or null when the game did not
  /// start from the standard position (the model only knows move text).
  Future<Map<String, double>?> moveProbabilities(String positionCommand) async {
    final parsed = parsePositionCommand(positionCommand);
    if (parsed.baseFen != _startFen) return null;
    final board = chess.Chess();
    final history = <String>[];
    for (final uci in parsed.moves) {
      final move = board.generate_moves().firstWhere(
          (m) => '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}' == uci,
          orElse: () => throw StateError('Illegal move $uci'));
      history.add(spec.format == ChessLmFormat.uci ? uci : board.move_to_san(move));
      board.make_move(move);
    }
    final legal = board.generate_moves();
    if (legal.isEmpty) return const {};
    final ucis = [
      for (final m in legal)
        '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
    ];
    final texts = spec.format == ChessLmFormat.uci
        ? ucis
        : [for (final m in legal) board.move_to_san(m)];
    final scores = await _scorer!.score(history, texts);
    final top = scores.reduce(math.max);
    final exps = [for (final s in scores) math.exp(s - top)];
    final total = exps.fold(0.0, (a, b) => a + b);
    return {for (var i = 0; i < ucis.length; i++) ucis[i]: exps[i] / total};
  }

  /// Sampling temperature for a strength level: the arena's 1.0 at the
  /// bottom, close to always the favourite move at the top.
  static double temperatureFor(int level) =>
      math.max(0.05, 1.0 - level.clamp(0, 20) * 0.045);

  @override
  Future<String> bestMove(String positionCommand,
      {int? depth, Duration? moveTime, int? skillLevel}) async {
    if (_scorer == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;
    try {
      final probs = await moveProbabilities(positionCommand);
      if (probs == null) {
        final fb = _fallback ??= DartEngine();
        if (fb.state == EngineState.idle) await fb.initialize();
        return fb.bestMove(positionCommand,
            depth: depth, moveTime: moveTime, skillLevel: skillLevel);
      }
      if (probs.isEmpty) throw StateError('No legal moves');
      final t = temperatureFor(skillLevel ?? 10);
      final weights = {
        for (final e in probs.entries) e.key: math.pow(e.value, 1 / t).toDouble()
      };
      final sum = weights.values.fold(0.0, (a, b) => a + b);
      var r = _random.nextDouble() * sum;
      for (final e in weights.entries) {
        r -= e.value;
        if (r <= 0) return e.key;
      }
      return weights.keys.last;
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }

  /// No evaluation — a language model has no value head. Analysis reports
  /// the move it would most like to write, with a neutral score.
  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) async* {
    final probs = await moveProbabilities(positionCommand);
    if (probs == null || probs.isEmpty) return;
    final best = probs.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    yield EvalInfo(score: 0, depth: 1, bestMove: best, pv: best);
  }

  @override
  void stop() => _fallback?.stop();

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _model?.dispose();
    _model = null;
    _fallback?.dispose();
    _stateNotifier.value = EngineState.disposed;
  }
}

/// The zoo. "Matched" is the share of real (CC0 Lichess) positions where the
/// model's favourite legal move is the one a human played, in its format —
/// measured by tool/kaggle/chess-lm-onnx; chance is about 3%.
const List<ChessLmSpec> chessLmZoo = [
  ChessLmSpec(
    name: 'LM: Chess Llama 68M',
    repo: 'bharathrajcl/chess_llama_68m',
    author: 'bharathrajcl',
    license: 'Apache-2.0',
    folder: 'chess_llama_68m',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 2, kvHeads: 12, headDim: 64, vocab: 32000, contextLength: 1024,
    downloadMb: 138,
    description: 'Llama-style, 2 layers. Matches human moves 41% of the time',
  ),
  ChessLmSpec(
    name: 'LM: ChessSLM-PM',
    repo: 'FlameF0X/ChessSLM-PM',
    author: 'FlameF0X',
    license: 'Apache-2.0',
    folder: 'ChessSLM-PM',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 6, kvHeads: 6, headDim: 64, vocab: 50257, contextLength: 1024,
    downloadMb: 103,
    description: 'GPT-2, 30M. Matches human moves 34% of the time',
  ),
  ChessLmSpec(
    name: 'LM: AMD Chess',
    repo: 'nlpguy/amdchess-v9',
    author: 'nlpguy',
    license: 'Apache-2.0',
    folder: 'amdchess-v9',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 12, kvHeads: 12, headDim: 64, vocab: 32000, contextLength: 1024,
    downloadMb: 271,
    description: 'AMD-Llama-135M fine-tune. Matches human moves 32% of the time',
  ),
  ChessLmSpec(
    name: 'LM: GrandPythia',
    repo: 'mlabonne/grandpythia-200k-70m',
    author: 'Maxime Labonne',
    license: 'Apache-2.0',
    folder: 'grandpythia-200k-70m',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 6, kvHeads: 8, headDim: 64, vocab: 50304, contextLength: 1024,
    downloadMb: 143,
    description: 'Pythia-70M on 200k games. Matches human moves 28% of the time',
  ),
  ChessLmSpec(
    name: 'LM: DialoChess',
    repo: 'DedeProGames/dialochess',
    author: 'DedeProGames',
    license: 'MIT',
    folder: 'dialochess',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 12, kvHeads: 12, headDim: 64, vocab: 50257, contextLength: 1024,
    downloadMb: 330,
    desktopOnly: true,
    description: 'DialoGPT-small fine-tune. Matches human moves 26% of the time',
  ),
  ChessLmSpec(
    name: 'LM: SmolChess',
    repo: 'nlpguy/smolchess-v2',
    author: 'nlpguy',
    license: 'Apache-2.0',
    folder: 'smolchess-v2',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 30, kvHeads: 3, headDim: 64, vocab: 49152, contextLength: 1024,
    downloadMb: 330,
    desktopOnly: true,
    description: 'SmolLM2-135M fine-tune. Matches human moves 21% of the time',
  ),
  ChessLmSpec(
    name: 'LM: Chesser',
    repo: 'DedeProGames/Chesser-248K-Mini',
    author: 'DedeProGames',
    license: 'Apache-2.0',
    folder: 'Chesser-248K-Mini',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.spaced,
    layers: 12, kvHeads: 8, headDim: 32, vocab: 32005, contextLength: 1024,
    downloadMb: 500,
    desktopOnly: true,
    description: 'TinyMistral-248M fine-tune. Matches human moves 20% of the time',
  ),
  ChessLmSpec(
    name: 'LM: Chessformer',
    repo: 'nsarrazin/chessformer',
    author: 'nsarrazin',
    license: 'MIT',
    folder: 'chessformer',
    onnxFile: 'model_kv_fp16.onnx',
    format: ChessLmFormat.uci,
    layers: 18, kvHeads: 16, headDim: 64, vocab: 4613, contextLength: 512,
    downloadMb: 477,
    desktopOnly: true,
    description: 'GPT-2 232M on 4.4B tokens of decisive Lichess games, one token per move',
  ),
];

ChessLmSpec? chessLmSpecNamed(String name) {
  for (final s in chessLmZoo) {
    if (s.name == name) return s;
  }
  return null;
}

/// Whether [spec] is offered here: desktop-only models are hidden on phones
/// and in the browser.
bool chessLmAvailable(ChessLmSpec spec) {
  if (!spec.desktopOnly) return true;
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => true,
    _ => false,
  };
}

/// Names of the zoo bots offered on this platform.
List<String> get availableChessLmNames =>
    [for (final s in chessLmZoo) if (chessLmAvailable(s)) s.name];
