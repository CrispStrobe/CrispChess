import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chesslm/kv_model.dart';
import 'package:crispchess/engines/chesslm/native_kv_model_stub.dart'
    if (dart.library.ffi) 'package:crispchess/engines/chesslm/native_kv_model.dart';
import 'package:crispchess/engines/chesslm/prompt.dart';
import 'package:crispchess/engines/chesslm/scorer.dart';
import 'package:crispchess/engines/chesslm/tokenizer.dart';

// Real chess_llama_68m against reference log-probabilities computed in
// Python (onnxruntime + tokenizers, every candidate fed whole from an empty
// cache). Point CHESS_LM_DIR at a folder with model_kv_fp16.onnx and
// tokenizer.json from huggingface.co/cstr/chess-lm-zoo-onnx/chess_llama_68m.
void main() {
  final dir = Platform.environment['CHESS_LM_DIR'];
  test('chess_llama_68m matches the Python reference on both runtimes', () async {
    final bytes = File('$dir/model_kv_fp16.onnx').readAsBytesSync();
    final tok = ChessLmTokenizer.fromJson(File('$dir/tokenizer.json').readAsStringSync());
    const ref = {'c2c3': -2.5906, 'b1c3': -2.6913, 'd2d4': -2.9254, 'd2d3': -2.9648, 'f1e1': -2.9666, 'h2h3': -4.2612};
    const sans = {'c2c3': 'c3', 'b1c3': 'Nc3', 'd2d4': 'd4', 'd2d3': 'd3', 'f1e1': 'Re1', 'h2h3': 'h3'};
    final history = 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7'.split(' ');
    for (final (name, KvLanguageModel model) in [
      ('native', NativeKvLanguageModel.create(bytes, layers: 2, kvHeads: 12, headDim: 64, vocab: 32000)),
      ('pure Dart', DartKvLanguageModel(bytes, layers: 2, kvHeads: 12, headDim: 64, vocab: 32000)),
    ]) {
      final scorer = ChessLmScorer(model, tok, ChessLmFormat.spaced, contextLength: 512);
      final sw = Stopwatch()..start();
      final got = await scorer.score(history, [for (final u in ref.keys) sans[u]!]);
      final t1 = sw.elapsedMilliseconds;
      var worst = 0.0;
      var i = 0;
      for (final u in ref.keys) {
        final d = (got[i++] - ref[u]!).abs();
        if (d > worst) worst = d;
      }
      // the next position reuses the cache: one more move each side
      sw.reset();
      await scorer.score([...history, 'Re1', 'b5'], ['Bb3', 'Bc2']);
      print('$name: max |dart - python| = $worst, first ${t1} ms, next position ${sw.elapsedMilliseconds} ms');
      expect(worst, lessThan(0.02));
    }
  }, skip: dir == null ? 'set CHESS_LM_DIR to run' : null,
      timeout: const Timeout(Duration(minutes: 5)));
}
