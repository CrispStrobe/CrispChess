import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/move_analyzer.dart';

void main() {
  group('MoveAnalyzer', () {
    test('analyzeInIsolate returns annotation for opening move', () {
      final request = AnalysisRequest(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        uciMove: 'e2e4',
        evaluation: MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.3,
          bestMove: 'e2e4',
          bestMoveScore: 0.3,
          depth: 10,
          whiteToMove: true,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.move, 'e2e4');
      expect(annotation.gamePhase, GamePhase.opening);
    });

    test('MoveEvaluation quality thresholds', () {
      // Good move (slight improvement)
      final good = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 0.2,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      expect(good.quality, MoveQuality.good);

      // Blunder (big loss)
      final blunder = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -4.0,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      expect(blunder.quality, MoveQuality.blunder);
    });

    test('MoveQuality.brilliant for significant improvement', () {
      // White moves, eval goes from 0.0 to +2.0 (big improvement for White)
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 2.0,
        bestMove: 'e2e4',
        bestMoveScore: 2.0,
        depth: 15,
        whiteToMove: true,
      );
      // evaluationChange = 0.0 - 2.0 = -2.0 => brilliant (< -1.0)
      expect(eval.quality, MoveQuality.brilliant);
    });

    test('MoveQuality.neutral for small change', () {
      // White moves, eval goes from 0.5 to 0.2 => change = 0.3
      final eval = MoveEvaluation(
        scoreBefore: 0.5,
        scoreAfter: 0.2,
        bestMove: 'd2d4',
        bestMoveScore: 0.5,
        depth: 10,
        whiteToMove: true,
      );
      // evaluationChange = 0.5 - 0.2 = 0.3, which is < 0.5 => neutral
      expect(eval.quality, MoveQuality.neutral);
    });

    test('MoveQuality.mistake for moderate loss', () {
      // White moves, eval drops from 0.0 to -2.5 => change = 0.0 - (-2.5) = 2.5
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -2.5,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 15,
        whiteToMove: true,
      );
      // evaluationChange = 0.0 - (-2.5) = 2.5 => mistake (2.0 <= change < 3.0)
      expect(eval.quality, MoveQuality.mistake);
    });

    test('MoveEvaluation.centipawnLoss for white move', () {
      // White moves, eval drops from 1.0 to 0.5
      final eval = MoveEvaluation(
        scoreBefore: 1.0,
        scoreAfter: 0.5,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // centipawnLoss for white = scoreBefore - scoreAfter = 0.5
      expect(eval.centipawnLoss, closeTo(0.5, 0.001));
    });

    test('MoveEvaluation.centipawnLoss for black move', () {
      // Black moves, eval goes from -1.0 to 0.0 (bad for black)
      final eval = MoveEvaluation(
        scoreBefore: -1.0,
        scoreAfter: 0.0,
        bestMove: 'e7e5',
        bestMoveScore: -1.0,
        depth: 10,
        whiteToMove: false,
      );
      // centipawnLoss for black = scoreAfter - scoreBefore = 0.0 - (-1.0) = 1.0
      expect(eval.centipawnLoss, closeTo(1.0, 0.001));
    });

    test('MoveEvaluation.centipawnLoss is zero when position improves', () {
      // White moves, eval improves from 0.0 to 1.0
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 1.0,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // centipawnLoss = 0.0 - 1.0 = -1.0, clamped to 0
      expect(eval.centipawnLoss, 0.0);
    });

    test('MoveEvaluation.evaluationChange sign convention', () {
      // White move: positive change = worsening
      final whiteEval = MoveEvaluation(
        scoreBefore: 1.0,
        scoreAfter: 0.5,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // For white: scoreBefore - scoreAfter = 0.5 (positive = loss)
      expect(whiteEval.evaluationChange, closeTo(0.5, 0.001));

      // Black move: positive change = worsening
      final blackEval = MoveEvaluation(
        scoreBefore: -1.0,
        scoreAfter: -0.5,
        bestMove: 'e7e5',
        bestMoveScore: -1.0,
        depth: 10,
        whiteToMove: false,
      );
      // For black: scoreAfter - scoreBefore = -0.5 - (-1.0) = 0.5 (positive = loss)
      expect(blackEval.evaluationChange, closeTo(0.5, 0.001));
    });
  });

  group('MoveAnnotation', () {
    test('getFullDescription includes quality', () {
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -4.0,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      final annotation = MoveAnnotation(
        move: 'f2f3',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.opening,
      );
      final desc = annotation.getFullDescription();
      // Should contain the quality description (blunder in this case)
      expect(desc.contains('Blunder'), isTrue);
      // Should contain phase advice
      expect(desc.contains('Opening'), isTrue);
    });

    test('getPhaseAdvice varies by phase', () {
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 0.0,
        bestMove: '',
        bestMoveScore: 0.0,
        depth: 10,
        whiteToMove: true,
      );

      final opening = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.opening,
      );
      expect(opening.getPhaseAdvice(), contains('Opening'));
      expect(opening.getPhaseAdvice(), contains('development'));

      final middlegame = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.middlegame,
      );
      expect(middlegame.getPhaseAdvice(), contains('Middlegame'));
      expect(middlegame.getPhaseAdvice(), contains('tactical'));

      final endgame = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.endgame,
      );
      expect(endgame.getPhaseAdvice(), contains('Endgame'));
      expect(endgame.getPhaseAdvice(), contains('king'));
    });
  });

  group('GamePhase detection', () {
    test('GamePhase detection based on move count and pieces', () {
      // Opening: fewer than 15 moves
      final request = AnalysisRequest(
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        uciMove: 'e7e5',
        evaluation: MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.0,
          bestMove: '',
          bestMoveScore: 0.0,
          depth: 10,
          whiteToMove: false,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.gamePhase, GamePhase.opening);
    });
  });

  group('analyzeInIsolate', () {
    test('analyzeInIsolate handles castling move', () {
      // Position where white has already castled kingside
      // After 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5, white can castle
      final fen = 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
      final request = AnalysisRequest(
        fen: fen,
        uciMove: 'e1g1', // kingside castling
        evaluation: MoveEvaluation(
          scoreBefore: 0.5,
          scoreAfter: 0.6,
          bestMove: 'e1g1',
          bestMoveScore: 0.6,
          depth: 15,
          whiteToMove: true,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.move, 'e1g1');
      // Should detect castling as a tactical pattern
      expect(
        annotation.tactics.any((t) => t.name == 'Castling'),
        isTrue,
      );
    });
  });
}
