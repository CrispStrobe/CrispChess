import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/uci_position.dart';

void main() {
  group('fenFromPositionCommand', () {
    test('startpos with no moves returns the start FEN', () {
      expect(
        fenFromPositionCommand('position startpos'),
        startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w'),
      );
    });

    test('startpos replays moves to the current position', () {
      // After 1.d4 the side to move must be black and a d4 pawn present.
      final fen = fenFromPositionCommand('position startpos moves d2d4');
      expect(fen.split(' ')[1], 'b', reason: 'black to move after white d4');
      expect(fen, startsWith('rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR'));
    });

    test('replays a longer line', () {
      final fen =
          fenFromPositionCommand('position startpos moves e2e4 e7e5 g1f3');
      // Knight on f3, white pawn e4, black pawn e5, black to move.
      expect(fen.split(' ')[1], 'b');
      expect(fen, contains('5N2'));
    });

    test('handles promotion suffix', () {
      final fen = fenFromPositionCommand(
          'position fen 8/P7/8/8/8/8/8/k6K w - - 0 1 moves a7a8q');
      expect(fen, startsWith('Q7/8/8/8/8/8/8/k6K'));
    });

    test('position fen without moves returns that FEN', () {
      const f = 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2';
      expect(fenFromPositionCommand('position fen $f'), f);
    });
  });

  group('fenHistoryFromPositionCommand', () {
    // Maia3 conditions on the real game history. It used to be accumulated
    // engine-side across bestMove calls, which only fire on the engine's own
    // turns — so the model was handed every *other* ply as though the plies
    // were consecutive, i.e. a game that never happened.
    test('returns every ply in order, current position last', () {
      final history = fenHistoryFromPositionCommand(
          'position startpos moves e2e4 e7e5 g1f3');

      // start + 3 plies
      expect(history.length, 4);
      expect(history.first, startsWith('rnbqkbnr/pppppppp'));
      expect(history[1], contains(' b ')); // after e2e4, Black to move
      expect(history[2], contains(' w ')); // after e7e5, White to move
      expect(history.last, fenFromPositionCommand(
          'position startpos moves e2e4 e7e5 g1f3'));
    });

    test('consecutive entries alternate side to move', () {
      final history = fenHistoryFromPositionCommand(
          'position startpos moves e2e4 e7e5 g1f3 b8c6 f1b5');
      final turns = history.map((f) => f.split(' ')[1]).toList();
      // Regression: skipping plies would repeat a side (w, w, w...).
      expect(turns, ['w', 'b', 'w', 'b', 'w', 'b']);
    });

    test('keeps only the most recent `limit` positions', () {
      final history = fenHistoryFromPositionCommand(
        'position startpos moves e2e4 e7e5 g1f3 b8c6 f1b5 g8f6 e1g1 f8e7',
        limit: 3,
      );
      expect(history.length, 3);
      // Still ends at the current position.
      expect(history.last, fenFromPositionCommand(
          'position startpos moves e2e4 e7e5 g1f3 b8c6 f1b5 g8f6 e1g1 f8e7'));
    });

    test('works from an explicit fen base', () {
      const f = 'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2';
      final history = fenHistoryFromPositionCommand('position fen $f moves g1f3');
      expect(history.length, 2);
      expect(history.first, f);
      expect(history.last, contains(' b '));
    });

    test('startpos with no moves yields just the current position', () {
      expect(fenHistoryFromPositionCommand('position startpos').length, 1);
    });
  });
}
