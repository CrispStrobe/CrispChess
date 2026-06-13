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
}
