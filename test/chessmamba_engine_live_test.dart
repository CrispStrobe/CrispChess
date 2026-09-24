// Live end-to-end test: the real ChessMambaEngine as the app runs it —
// download from Hugging Face, cache, load, play. Requires network access.
import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/chessmamba_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding fakes every HTTP response; this test wants the real one.
  HttpOverrides.global = null;
  final tempDir = Directory.systemTemp.createTempSync('chessmamba_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );

  test('downloads, loads and plays legal moves with search', () async {
    final engine = ChessMambaEngine();
    await engine.initialize();
    expect(engine.state, EngineState.ready);
    addTearDown(engine.dispose);
    print('ChessMamba backend: ${engine.backendName}');

    final game = chess.Chess();
    final played = <String>[];
    for (var ply = 0; ply < 10; ply++) {
      final cmd = played.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${played.join(' ')}';
      final move = await engine.bestMove(cmd,
          moveTime: const Duration(milliseconds: 400));
      final ok = game.move({
        'from': move.substring(0, 2),
        'to': move.substring(2, 4),
        if (move.length > 4) 'promotion': move.substring(4, 5),
      });
      expect(ok, isTrue, reason: 'ply ${ply + 1}: $move illegal in ${game.fen}');
      played.add(move);
    }
    print('ChessMamba self-play: ${played.join(' ')}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
