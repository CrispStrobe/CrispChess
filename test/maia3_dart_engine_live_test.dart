// Live end-to-end test: exercises the real Maia3DartEngine (download,
// init, bestMove) exactly as the app invokes it — not just the ONNX
// interpreter in isolation. Requires network access to Hugging Face.
import 'dart:io';
import 'package:chess/chess.dart' as chess;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/maia3_dart_engine.dart';

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
}
