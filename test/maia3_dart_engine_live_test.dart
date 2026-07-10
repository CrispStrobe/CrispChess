// Live end-to-end test: exercises the real Maia3DartEngine (download,
// init, bestMove) exactly as the app invokes it — not just the ONNX
// interpreter in isolation. Requires network access to Hugging Face.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/maia3_dart_engine.dart';

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

  test('Maia3DartEngine initializes and suggests a legal-looking opening move',
      () async {
    final engine = Maia3DartEngine(variantId: '5m', playerElo: 1500);
    await engine.initialize();
    expect(engine.state, EngineState.ready,
        reason: 'engine failed to initialize');

    final move = await engine.bestMove(
      'position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    );
    // eg "e2e4" — 4-5 chars, algebraic squares
    expect(move, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    print('Maia3 Dart suggested: $move');

    engine.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
