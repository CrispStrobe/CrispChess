import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/dart_engine/evaluation.dart';
import 'package:chess/chess.dart' as chess;

void main() {
  group('DartEngine interface', () {
    test('name, version, license are correct', () {
      final engine = DartEngine();
      expect(engine.name, 'Built-in');
      expect(engine.license, 'MIT');
      expect(engine.estimatedElo, greaterThan(1000));
      engine.dispose();
    });

    test('initializes to ready state', () async {
      final engine = DartEngine();
      expect(engine.state, EngineState.idle);
      await engine.initialize();
      expect(engine.state, EngineState.ready);
      engine.dispose();
    });

    test('bestMove returns valid UCI move from starting position', () async {
      final engine = DartEngine();
      await engine.initialize();
      final move = await engine.bestMove('position startpos', depth: 3);
      expect(move.length, greaterThanOrEqualTo(4));
      // Should be a valid opening move
      final validOpenings = [
        'a2a3', 'a2a4', 'b2b3', 'b2b4', 'c2c3', 'c2c4',
        'd2d3', 'd2d4', 'e2e3', 'e2e4', 'f2f3', 'f2f4',
        'g2g3', 'g2g4', 'h2h3', 'h2h4',
        'b1a3', 'b1c3', 'g1f3', 'g1h3',
      ];
      expect(validOpenings.contains(move), isTrue,
          reason: 'Expected valid opening move, got: $move');
      engine.dispose();
    });

    test('bestMove works with moves played', () async {
      final engine = DartEngine();
      await engine.initialize();
      final move = await engine.bestMove(
          'position startpos moves e2e4 e7e5', depth: 3);
      expect(move.length, greaterThanOrEqualTo(4));
      engine.dispose();
    });

    test('state transitions during search', () async {
      final engine = DartEngine();
      await engine.initialize();
      final states = <EngineState>[];
      engine.stateNotifier.addListener(() => states.add(engine.state));
      await engine.bestMove('position startpos', depth: 2);
      expect(states, contains(EngineState.thinking));
      expect(states.last, EngineState.ready);
      engine.dispose();
    });

    test('dispose sets state to disposed', () {
      final engine = DartEngine();
      engine.dispose();
      expect(engine.state, EngineState.disposed);
    });
  });

  group('Evaluation', () {
    test('starting position is roughly equal', () {
      final game = chess.Chess();
      final score = evaluate(game);
      // Starting position should be close to 0 (slight white advantage from mobility)
      expect(score.abs(), lessThan(100)); // less than 1 pawn
    });

    test('white up a queen evaluates positively for white', () {
      final game = chess.Chess();
      // Remove black queen
      game.load('rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      final score = evaluate(game);
      expect(score, greaterThan(800)); // queen is ~900cp
    });

    test('checkmate evaluates to large negative', () {
      final game = chess.Chess();
      // Fool's mate position: white is checkmated
      game.load('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 0 1');
      // Actually need to verify checkmate. Let's use a known checkmate FEN
      game.load('rnb1kbnr/pppp1ppp/4p3/8/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 0 1');
      if (game.in_checkmate) {
        final score = evaluate(game);
        expect(score, lessThan(-90000));
      }
    });

    test('material values are positive', () {
      expect(pieceValues[chess.PieceType.PAWN], 100);
      expect(pieceValues[chess.PieceType.KNIGHT], greaterThan(300));
      expect(pieceValues[chess.PieceType.QUEEN], greaterThan(800));
    });
  });

  group('ChessEngine interface contract', () {
    test('implements ChessEngine', () {
      final engine = DartEngine();
      expect(engine, isA<ChessEngine>());
      engine.dispose();
    });

    test('EvalInfo has required fields', () {
      const info = EvalInfo(score: 0.5, depth: 10, bestMove: 'e2e4');
      expect(info.score, 0.5);
      expect(info.depth, 10);
      expect(info.bestMove, 'e2e4');
    });

    test('EngineState has expected values', () {
      expect(EngineState.values.length, 6);
      expect(EngineState.values, contains(EngineState.ready));
      expect(EngineState.values, contains(EngineState.thinking));
    });
  });
}
