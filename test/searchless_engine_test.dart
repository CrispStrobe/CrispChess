// DeepMind's searchless-chess models in Dart: the tokenizer against the
// reference tokens from the original Python (always), and the 9M model's
// win probabilities and chosen moves against the original JAX engine (when
// SEARCHLESS_DIR points at a folder with 9M/model.onnx, actions.json and
// bucket_values.json from huggingface.co/cstr/searchless-chess-onnx).
import 'dart:convert';
import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/searchless/model.dart';
import 'package:crispchess/engines/searchless/native_model_stub.dart'
    if (dart.library.ffi) 'package:crispchess/engines/searchless/native_model.dart';
import 'package:crispchess/engines/searchless/tokenizer.dart';
import 'package:crispchess/engines/searchless_engine.dart';

void main() {
  final refs = (jsonDecode(File('test/fixtures/searchless/reference_9M.json')
          .readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  test('FEN tokens match the original tokenizer', () {
    for (final r in refs) {
      final board = chess.Chess.fromFEN(r['fen']);
      expect(tokenizeFen(pythonChessFen(board)), (r['fen_tokens'] as List).cast<int>(),
          reason: r['fen']);
    }
  });

  test('en passant only when a capture is legal, as python-chess writes it', () {
    final b = chess.Chess()..move('e4');
    expect(b.fen.split(' ')[3], 'e3', reason: 'the Dart library records it');
    expect(pythonChessFen(b).split(' ')[3], '-');
    final c = chess.Chess.fromFEN(
        'rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3');
    expect(pythonChessFen(c).split(' ')[3], 'f6');
  });

  test('temperature: none at full strength, more variety below', () {
    expect(SearchlessEngine.temperatureFor(20), isNull);
    expect(SearchlessEngine.temperatureFor(0)!, greaterThan(SearchlessEngine.temperatureFor(15)!));
  });

  final dir = Platform.environment['SEARCHLESS_DIR'];
  test('9M: win probabilities and moves match the original JAX engine', () async {
    final bytes = File('$dir/9M/model.onnx').readAsBytesSync();
    final actions = (jsonDecode(File('$dir/actions.json').readAsStringSync()) as List).cast<String>();
    final buckets = [
      for (final v in jsonDecode(File('$dir/bucket_values.json').readAsStringSync()) as List)
        (v as num).toDouble()
    ];
    final backends = <String, SearchlessModel Function()>{
      'pure Dart': () => DartSearchlessModel(bytes),
      if (NativeSearchlessModel.isSupported) 'native': () => NativeSearchlessModel.create(bytes),
    };
    for (final entry in backends.entries) {
      SearchlessModel? model;
      try {
        model = entry.value();
      } catch (e) {
        print('${entry.key}: unavailable ($e)');
        continue;
      }
      final m = model;
      final engine = SearchlessEngine(SearchlessSize.m9,
          loader: () async => (m, actions, buckets));
      await engine.initialize();
      var worst = 0.0;
      final sw = Stopwatch()..start();
      for (final r in refs) {
        final got = await engine.winProbabilities('position fen ${r['fen']}');
        final moves = (r['moves'] as List).cast<String>();
        final want = (r['win_probs'] as List).cast<num>();
        for (var i = 0; i < moves.length; i++) {
          final d = (got[moves[i]]! - want[i]).abs();
          if (d > worst) worst = d;
        }
        expect(await engine.bestMove('position fen ${r['fen']}'), r['best'], reason: r['fen']);
      }
      print('${entry.key}: max |win prob - JAX| = $worst, '
          '${sw.elapsedMilliseconds ~/ refs.length} ms a position');
      expect(worst, lessThan(1e-3));
      engine.dispose();
    }
  }, skip: dir == null ? 'set SEARCHLESS_DIR to run' : null,
      timeout: const Timeout(Duration(minutes: 15)));
}
