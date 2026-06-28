// iOS smoke test for the WebKit-hosted Stockfish engine.
//
// Verifies the full Option-B path on a real iOS runtime: download stockfish.js
// (CDN) -> load into WKWebView via StockfishJSBridge.swift -> UCI handshake ->
// compute a move from the start position. Needs network. Skipped off iOS.
//
// Run on a booted simulator:
//   flutter test integration_test/stockfish_ios_test.dart -d <simulator-id>

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/stockfish_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final isIOS = !kIsWeb && Platform.isIOS;

  testWidgets('Stockfish (WebKit) computes a legal opening move on iOS',
      (tester) async {
    final ChessEngine engine = StockfishEngine();

    expect(StockfishEngine.isAvailable, isTrue,
        reason: 'Stockfish should be available on iOS via WebKit');

    // Downloads stockfish.js + UCI handshake inside WebKit. Generous timeout:
    // first run fetches ~1.5 MB and the Web Worker compiles the engine.
    await engine.initialize();
    await tester.pump();

    expect(engine.state, isNot(EngineState.error),
        reason: 'engine should initialize, not error');

    // startpos -> any first move. Shallow depth keeps the interpreter fast.
    final move = await engine.bestMove(
      'position startpos',
      depth: 8,
    );

    // UCI long-algebraic move, e.g. e2e4 / g1f3.
    expect(RegExp(r'^[a-h][1-8][a-h][1-8][nbrq]?$').hasMatch(move), isTrue,
        reason: 'expected a UCI move, got "$move"');

    engine.dispose();
  }, skip: !isIOS, timeout: const Timeout(Duration(minutes: 2)));
}
