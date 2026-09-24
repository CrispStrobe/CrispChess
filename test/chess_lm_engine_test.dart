import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chesslm/kv_model.dart';
import 'package:crispchess/engines/chesslm/prompt.dart';
import 'package:crispchess/engines/chesslm/scorer.dart';
import 'package:crispchess/engines/chesslm/tokenizer.dart';
import 'package:crispchess/engines/chess_lm_engine.dart';

const _v = 16;

/// Next-token logits that depend on the whole prefix, so a wrong cache or a
/// wrong trie row gives a different answer.
Float32List _logitsAfter(List<int> prefix) {
  var h = 17;
  for (final t in prefix) {
    h = (h * 31 + t + 1) % 1000003;
  }
  return Float32List.fromList([for (var j = 0; j < _v; j++) ((h * (j + 3)) % 97) / 10.0]);
}

/// A model whose "cache" is simply the token history of each row.
class FakeLm implements KvLanguageModel {
  int calls = 0;
  @override
  int get layers => 1;
  @override
  int get kvHeads => 1;
  @override
  int get headDim => 1;
  @override
  int get vocab => _v;

  @override
  Future<KvStep> run(Int64List tokens, int t, KvCache past) async {
    calls++;
    final b = past.batch;
    final logits = Float32List(b * _v);
    final rows = <Float32List>[];
    for (var r = 0; r < b; r++) {
      final hist = [
        if (past.length > 0)
          for (var i = 0; i < past.length; i++) past.tensors[0][r * past.length + i].toInt(),
        for (var i = 0; i < t; i++) tokens[r * t + i],
      ];
      logits.setAll(r * _v, _logitsAfter(hist));
      rows.add(Float32List.fromList([for (final x in hist) x.toDouble()]));
    }
    final len = past.length + t;
    final flat = Float32List(b * len);
    for (var r = 0; r < b; r++) {
      flat.setAll(r * len, rows[r]);
    }
    return KvStep(logits, KvCache(b, 1, len, 1, [flat, Float32List.fromList(flat)]));
  }

  @override
  void dispose() {}
}

/// One token per character, so moves share prefixes ("Nf3"/"Nc3") in the trie.
class CharTokenizer implements ChessLmTokenizer {
  @override
  List<int> encode(String text, {bool addSpecial = true}) =>
      [if (addSpecial) 1, for (final c in text.codeUnits) c % (_v - 2) + 2];
}

double _bruteForce(String prompt, String move, ChessLmFormat f) {
  final tok = CharTokenizer();
  final p = tok.encode(prompt), full = tok.encode(prompt + moveText(f, prompt, move));
  var lp = 0.0;
  for (var j = p.length; j < full.length; j++) {
    final x = _logitsAfter(full.sublist(0, j));
    final mx = x.reduce(math.max);
    final z = mx + math.log(x.fold(0.0, (a, b) => a + math.exp(b - mx)));
    lp += x[full[j]] - z;
  }
  return lp;
}

void main() {
  group('renderGame', () {
    const moves = ['e4', 'e5', 'Nf3', 'Nc6'];
    test('arena, spaced, plain and UCI', () {
      expect(renderGame(ChessLmFormat.arena, moves), '1.e4 e5 2.Nf3 Nc6 3.');
      expect(renderGame(ChessLmFormat.spaced, moves), '1. e4 e5 2. Nf3 Nc6 3.');
      expect(renderGame(ChessLmFormat.plain, moves), 'e4 e5 Nf3 Nc6');
      expect(renderGame(ChessLmFormat.uci, ['e2e4', 'e7e5']), 'e2e4 e7e5');
    });
    test('black to move and check marks', () {
      expect(renderGame(ChessLmFormat.spaced, ['e4', 'e5', 'Qh5']), '1. e4 e5 2. Qh5');
      expect(renderGame(ChessLmFormat.arena, ['f3', 'e5', 'g4', 'Qh4#']), '1.f3 e5 2.g4 Qh4 3.');
    });
    test('move text joins the prompt the way the format writes it', () {
      expect(moveText(ChessLmFormat.arena, '1.e4 e5 2.', 'Nf3+'), 'Nf3');
      expect(moveText(ChessLmFormat.spaced, '1. e4 e5 2.', 'Nf3'), ' Nf3');
      expect(moveText(ChessLmFormat.plain, 'e4 e5', 'Nf3'), ' Nf3');
    });
    test('a trimmed game keeps its move numbers', () {
      expect(renderGame(ChessLmFormat.spaced, ['Bb5', 'a6'], firstPly: 4), '3. Bb5 a6 4.');
    });
  });

  test('the cached trie scorer equals scoring every move from scratch', () async {
    final model = FakeLm();
    final scorer = ChessLmScorer(model, CharTokenizer(), ChessLmFormat.spaced,
        contextLength: 4096);
    const history = ['e4', 'e5'];
    const moves = ['Nf3', 'Nc3', 'Bc4', 'Bb5', 'd4', 'O-O'];
    final got = await scorer.score(history, moves);
    final prompt = renderGame(ChessLmFormat.spaced, history);
    for (var i = 0; i < moves.length; i++) {
      expect(got[i], closeTo(_bruteForce(prompt, moves[i], ChessLmFormat.spaced), 1e-4),
          reason: moves[i]);
    }
    // The next position reuses the cache and is still exact.
    final next = await scorer.score([...history, 'Nf3', 'Nc6'], ['Bb5', 'Bc4']);
    final p2 = renderGame(ChessLmFormat.spaced, [...history, 'Nf3', 'Nc6']);
    expect(next[0], closeTo(_bruteForce(p2, 'Bb5', ChessLmFormat.spaced), 1e-4));
    expect(next[1], closeTo(_bruteForce(p2, 'Bc4', ChessLmFormat.spaced), 1e-4));
  });

  test('a long game is trimmed to the context from the front', () async {
    final scorer = ChessLmScorer(FakeLm(), CharTokenizer(), ChessLmFormat.spaced,
        contextLength: 40);
    final history = List.generate(30, (i) => i.isEven ? 'Nf3' : 'Nf6');
    final got = await scorer.score(history, ['Ng1']);
    expect(got.single.isFinite, isTrue);
  });

  test('zoo entries are well formed', () {
    final names = chessLmZoo.map((s) => s.name).toSet();
    expect(names.length, chessLmZoo.length);
    for (final s in chessLmZoo) {
      expect(s.name, startsWith('LM: '));
      expect(['MIT', 'Apache-2.0'], contains(s.license));
      expect(s.onnxUrl, startsWith('https://huggingface.co/cstr/chess-lm-zoo-onnx/'));
      expect(chessLmSpecNamed(s.name), same(s));
    }
    // Phones get only the small ones.
    expect(chessLmZoo.where((s) => !s.desktopOnly).every((s) => s.downloadMb < 300), isTrue);
  });
}
