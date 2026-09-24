// Live end-to-end test: exercises the real Maia3DartEngine (download,
// init, bestMove) exactly as the app invokes it — not just the ONNX
// interpreter in isolation. Requires network access to Hugging Face.
import 'dart:io';
import 'dart:math';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/maia3_dart_engine.dart';
import 'package:crispchess/engines/maia3_dart/encoding.dart';
import 'package:crispchess/engines/maia3_dart/history.dart';
import 'package:crispchess/engines/maia3_dart/onnx_model.dart';
import 'package:crispchess/engines/maia3_dart/onnx_native_backend.dart';
import 'package:crispchess/engines/maia3_dart/onnx_runtime_backend.dart';
import 'package:crispchess/engines/maia3_dart/variants.dart';
import 'package:crispchess/engines/uci_position.dart';

Set<String> _legalMoves(String fen) => chess.Chess.fromFEN(fen)
    .generate_moves()
    .map((m) => '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}')
    .toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // TestWidgetsFlutterBinding fakes all HttpClient responses as 400 by
  // default for test hermeticity — this test deliberately wants the real
  // network (it's downloading a real model file), so restore it.
  HttpOverrides.global = null;

  // path_provider has no real platform implementation under `flutter test`
  // (plain Dart VM, no device) — mock it to a temp dir so the engine's
  // real download+cache path actually runs, same code as on a device.
  final tempDir = Directory.systemTemp.createTempSync('maia3_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );

  const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  test('Maia3DartEngine initializes and suggests a legal opening move',
      () async {
    final engine = Maia3DartEngine(variantId: '5m', playerElo: 1500);
    await engine.initialize();
    expect(engine.state, EngineState.ready,
        reason: 'engine failed to initialize');
    addTearDown(engine.dispose);

    final move = await engine.bestMove('position fen $startFen');
    expect(move, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    // Shape alone proved little — a wrong-side or garbage move matches it too.
    expect(_legalMoves(startFen), contains(move));
    print('Maia3 Dart suggested: $move');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('plays a full opening with real history, every move legal', () async {
    // Exercises the history path: bestMove now rebuilds the game's actual
    // consecutive positions from the position command. It used to accumulate
    // FENs across its own turns only, feeding the model every *other* ply.
    final engine = Maia3DartEngine(variantId: '5m', playerElo: 1500);
    await engine.initialize();
    expect(engine.state, EngineState.ready);
    addTearDown(engine.dispose);

    final game = chess.Chess();
    final played = <String>[];

    // Long enough to exceed the 8-slot history window.
    for (var ply = 0; ply < 12; ply++) {
      final command = played.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${played.join(' ')}';

      final move = await engine.bestMove(command);
      expect(_legalMoves(game.fen), contains(move),
          reason: 'ply ${ply + 1}: $move is not legal in ${game.fen}');

      game.move({
        'from': move.substring(0, 2),
        'to': move.substring(2, 4),
        'promotion': move.length > 4 ? move.substring(4, 5) : null,
      });
      played.add(move);
    }
    print('Maia3 Dart self-play: ${played.join(' ')}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('is deterministic at temperature 0 and stateless across calls',
      () async {
    // Default temperature is 0 (argmax), matching maia3-js's DEFAULT_TEMPERATURE.
    // Repeating the same position must give the same move — it previously
    // could drift because history accumulated in a field and leaked between
    // calls and games.
    final engine = Maia3DartEngine(variantId: '5m', playerElo: 1500);
    await engine.initialize();
    addTearDown(engine.dispose);

    const command = 'position startpos moves e2e4 e7e5 g1f3';
    final first = await engine.bestMove(command);
    // Interleave an unrelated position; must not affect the repeat.
    await engine.bestMove('position startpos moves d2d4');
    final second = await engine.bestMove(command);

    expect(second, first,
        reason: 'same position gave different moves — engine is not stateless');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('movePolicy is a distribution over exactly the legal moves, '
      'and it shifts with rating', () async {
    final engine = Maia3DartEngine(variantId: '5m', playerElo: 1500);
    await engine.initialize();
    addTearDown(engine.dispose);

    // Black to move, so the mirroring path is exercised too.
    const command = 'position startpos moves e2e4 e7e5 g1f3';
    final fen = chess.Chess()
      ..move('e4')
      ..move('e5')
      ..move('Nf3');
    final sw = Stopwatch()..start();
    final low = await engine.movePolicy(command, elo: 800);
    final high = await engine.movePolicy(command, elo: 2300);
    print('Maia3 movePolicy: ${sw.elapsedMilliseconds ~/ 2} ms per pass');

    for (final p in [low, high]) {
      expect(p.keys.toSet(), _legalMoves(fen.fen));
      expect(p.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-3));
    }
    // Same argmax as bestMove at the same rating.
    final engine1500 = await engine.movePolicy(command, elo: 1500);
    final top = engine1500.entries.reduce((a, b) => a.value >= b.value ? a : b);
    expect(await engine.bestMove(command), top.key);
    // Rating conditioning must actually change the distribution.
    final diff = low.keys
        .map((k) => (low[k]! - high[k]!).abs())
        .fold(0.0, (a, b) => a + b);
    expect(diff, greaterThan(0.01));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('native ONNX Runtime and the pure-Dart interpreter agree', () async {
    final variant = getVariant('5m');
    final native = Maia3NativeBackend(variant: variant);
    try {
      await native.load();
    } catch (e) {
      markTestSkipped('native ONNX Runtime not loadable here: $e');
      return;
    }
    final dart = Maia3OnnxRuntimeBackend(variant: variant, isolateWorkers: 1);
    await dart.load();
    addTearDown(() async {
      await native.close();
      await dart.close();
    });

    for (final cmd in [
      'position startpos',
      'position startpos moves e2e4 e7e5 g1f3 b8c6 f1b5',
      'position fen 8/5k2/8/3K4/8/8/5P2/8 w - - 0 1',
    ]) {
      final tokens = buildHistoryTokens(resolveHistory(HistoryInput(
          fen: fenHistoryFromPositionCommand(cmd, limit: 1).last)));
      for (final elo in [900, 1900]) {
        final a = await native.infer(tokens, elo, elo);
        final b = await dart.infer(tokens, elo, elo);
        expect(a.logitsMove.length, b.logitsMove.length);
        var worst = 0.0;
        for (var i = 0; i < a.logitsMove.length; i++) {
          worst = max(worst, (a.logitsMove[i] - b.logitsMove[i]).abs());
        }
        for (var i = 0; i < 3; i++) {
          worst = max(worst, (a.logitsValue[i] - b.logitsValue[i]).abs());
        }
        expect(worst, lessThan(1e-3), reason: '$cmd @ $elo');
      }
    }

    final tokens = buildHistoryTokens(resolveHistory(HistoryInput(
        fen: fenHistoryFromPositionCommand('position startpos', limit: 1).last)));
    Future<int> timeIt(Maia3OnnxModel m) async {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        await m.infer(tokens, 1500, 1500);
      }
      return sw.elapsedMilliseconds ~/ 10;
    }

    print('Maia3 5M per pass: native ${await timeIt(native)} ms, '
        'pure Dart ${await timeIt(dart)} ms');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
