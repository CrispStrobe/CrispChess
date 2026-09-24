// Live end-to-end test of a zoo bot as the app runs it: download from
// huggingface.co/cstr/chess-lm-zoo-onnx, load, play legal moves.
import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/chess_lm_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final tempDir = Directory.systemTemp.createTempSync('chess_lm_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );

  test('Chess Llama 68M downloads and plays a legal opening', () async {
    final engine = ChessLmEngine(chessLmSpecNamed('LM: Chess Llama 68M')!);
    await engine.initialize();
    expect(engine.state, EngineState.ready);
    addTearDown(engine.dispose);
    print('backend: ${engine.backendName}');

    final game = chess.Chess();
    final played = <String>[];
    final sw = Stopwatch()..start();
    for (var ply = 0; ply < 16; ply++) {
      final cmd = played.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${played.join(' ')}';
      final move = await engine.bestMove(cmd, skillLevel: 20);
      final ok = game.move({
        'from': move.substring(0, 2),
        'to': move.substring(2, 4),
        if (move.length > 4) 'promotion': move.substring(4, 5),
      });
      expect(ok, isTrue, reason: 'ply ${ply + 1}: $move');
      played.add(move);
    }
    print('Chess Llama self-play: ${game.pgn()}');
    print('${sw.elapsedMilliseconds ~/ 16} ms a move');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
