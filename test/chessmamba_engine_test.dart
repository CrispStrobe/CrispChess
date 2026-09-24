import 'dart:io';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/chessmamba/search.dart';
import 'package:crispchess/engines/chessmamba/step_model.dart';
import 'package:crispchess/engines/chessmamba_engine.dart';

/// A stand-in network: a fixed logit per from/to pair, value 0, and a state
/// that only counts steps. Records every call.
class FakeMamba implements MambaStepModel {
  final Map<String, double> logits;
  int steps = 0;
  int calls = 0;
  FakeMamba(this.logits);

  @override
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs) async {
    steps += inputs.length;
    calls++;
    final policy = Float32List(4096);
    logits.forEach((uci, v) {
      policy[mambaSquare(uci.substring(0, 2)) * 64 +
          mambaSquare(uci.substring(2, 4))] = v;
    });
    return [
      for (final _ in inputs) MambaOutput(policy, Float32List(5), 0, Float32List(4))
    ];
  }

  @override
  void dispose() {}
}

Future<ChessMambaEngine> _engine(FakeMamba fake) async {
  final e = ChessMambaEngine(modelFactory: () async => fake);
  await e.initialize();
  expect(e.state, EngineState.ready);
  return e;
}

void main() {
  test('square numbering matches python-chess', () {
    expect(mambaSquare('a1'), 0);
    expect(mambaSquare('h1'), 7);
    expect(mambaSquare('e4'), 28);
    expect(mambaSquare('h8'), 63);
  });

  test('value maps to pawns through the logistic curve', () {
    expect(mambaValueToPawns(0, whiteToMove: true), closeTo(0, 1e-9));
    expect(mambaValueToPawns(0.5, whiteToMove: true), greaterThan(2));
    expect(mambaValueToPawns(0.5, whiteToMove: false), lessThan(-2));
  });

  test('policy-only plays the network\'s favourite legal move', () async {
    final e = await _engine(FakeMamba({'g1f3': 3, 'e2e4': 2, 'e7e5': 9}));
    expect(await e.bestMove('position startpos', skillLevel: 0), 'g1f3');
  });

  test('search finds a mate the policy does not like best', () async {
    // 1.f3 e5 2.g4: Qh4# is on the board. The fake policy prefers Nc6.
    final e = await _engine(FakeMamba({'b8c6': 5, 'd8h4': 1}));
    final move = await e.bestMove('position startpos moves f2f3 e7e5 g2g4',
        moveTime: const Duration(seconds: 5), depth: 1);
    expect(move, 'd8h4');
  });

  test('extending the game costs one step, taking back costs none', () async {
    final fake = FakeMamba({'e2e4': 1});
    final e = await _engine(fake);
    await e.bestMove('position startpos moves e2e4 e7e5', skillLevel: 0);
    final before = fake.steps;
    await e.bestMove('position startpos moves e2e4 e7e5 g1f3', skillLevel: 0);
    expect(fake.steps - before, 1);
    final mid = fake.steps;
    await e.bestMove('position startpos moves e2e4', skillLevel: 0);
    expect(fake.steps - mid, 0);
  });

  test('a game from a FEN goes to the built-in engine', () async {
    final e = await _engine(FakeMamba({}));
    const fen = '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1';
    final move = await e.bestMove('position fen $fen',
        moveTime: const Duration(milliseconds: 500));
    final legal = chess.Chess.fromFEN(fen).generate_moves().map(
        (m) => '${m.fromAlgebraic}${m.toAlgebraic}');
    expect(legal, contains(move));
    e.dispose();
  });

  // The real exported network, when its ONNX is on disk (it is downloaded in
  // the app). Reference values are PyTorch's, from the Kaggle export report.
  final onnx = Platform.environment['CHESSMAMBA_ONNX'];
  test('real network: 1.e4 from the start, Bh4 after 30 plies', () async {
    final e = ChessMambaEngine(
        modelFactory: () async =>
            DartMambaStepModel(File(onnx!).readAsBytesSync()));
    await e.initialize();
    expect(await e.bestMove('position startpos', skillLevel: 0), 'e2e4');
    const ruy = 'e2e4 e7e5 g1f3 b8c6 f1b5 a7a6 b5a4 g8f6 e1g1 f8e7 f1e1 b7b5 '
        'a4b3 d7d6 c2c3 e8g8 h2h3 c6b8 d2d4 b8d7 c3c4 c7c6 c4b5 a6b5 b1c3 '
        'c8b7 c1g5 b5b4 c3b1 h7h6';
    expect(await e.bestMove('position startpos moves $ruy', skillLevel: 0),
        'g5h4');
    e.dispose();
  }, skip: onnx == null ? 'set CHESSMAMBA_ONNX to run' : null,
      timeout: const Timeout(Duration(minutes: 3)));
}
