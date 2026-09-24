// Live: Searchless 9M downloads from huggingface.co/cstr/searchless-chess-onnx
// and plays a legal opening. Requires network access.
import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/searchless_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final tempDir = Directory.systemTemp.createTempSync('searchless_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );

  test('Searchless 9M downloads and plays', () async {
    final engine = SearchlessEngine(SearchlessSize.m9);
    await engine.initialize();
    expect(engine.state, EngineState.ready);
    addTearDown(engine.dispose);
    print('backend: ${engine.backendName}');
    final game = chess.Chess();
    final played = <String>[];
    for (var ply = 0; ply < 12; ply++) {
      final cmd = played.isEmpty ? 'position startpos' : 'position startpos moves ${played.join(' ')}';
      final m = await engine.bestMove(cmd);
      expect(game.move({'from': m.substring(0, 2), 'to': m.substring(2, 4),
          if (m.length > 4) 'promotion': m.substring(4, 5)}), isTrue, reason: m);
      played.add(m);
    }
    print('Searchless 9M self-play: ${game.pgn()}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
