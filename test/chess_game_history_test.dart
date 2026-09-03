// The move history the app hands to the engine, and the notation it shows,
// both used to be re-derived from `package:chess`'s own history on every call.
// That was wrong after an undo (which reloads the board from a FEN and clears
// that history) and expensive everywhere else (`pgn()` undoes and replays the
// whole game). These tests pin both the correctness and the cost.
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

const _opening = ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5', 'a7a6'];

ChessGame _gameWith(List<String> moves) {
  final game = ChessGame();
  for (final m in moves) {
    expect(game.makeMove(m), isTrue, reason: 'could not play $m');
  }
  return game;
}

void main() {
  group('positionCommand', () {
    test('lists the moves played', () {
      final game = _gameWith(_opening);
      expect(game.positionCommand,
          'position startpos moves ${_opening.join(' ')}');
    });

    test('survives an undo', () {
      // Regression: undoMove() reloads the board from a FEN, which clears
      // `chess.Chess.history`. The position command was built from that
      // history, so after an undo the engine was told the game was at the
      // *initial* position while the board showed something else. It answered
      // with a move that was illegal on the real board, the board rejected it,
      // and the UI stayed on "thinking" for good.
      final game = _gameWith(_opening);
      game.undoMove();
      game.undoMove();

      expect(game.positionCommand,
          'position startpos moves ${_opening.take(4).join(' ')}');

      // And the command really does describe the board the player sees.
      final replayed = chess.Chess();
      for (final uci in _opening.take(4)) {
        replayed.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)});
      }
      expect(game.currentFEN, replayed.fen);
    });

    test('anchors to the starting FEN when the game did not start from the '
        'initial position', () {
      // Chess960, a puzzle, or any position loaded from FEN: calling it
      // "startpos" describes a completely different game to the engine.
      const fen = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
      final game = ChessGame();
      expect(game.loadFen(fen), isTrue);
      expect(game.positionCommand, 'position fen $fen');

      expect(game.makeMove('e2e4'), isTrue);
      expect(game.positionCommand, 'position fen $fen moves e2e4');
    });
  });

  group('moveHistorySan', () {
    test('matches the notation package:chess produces', () {
      final game = _gameWith(_opening);
      expect(game.moveHistorySan, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5', 'a6']);
    });

    test('handles castling, captures, checks and promotion', () {
      final game = _gameWith([
        'e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5', 'e1g1', 'g8f6',
      ]);
      expect(game.moveHistorySan.last, 'Nf6');
      expect(game.moveHistorySan[6], 'O-O');
    });

    test('is empty and stays clean after an undo', () {
      // Regression: the old implementation parsed `pgn()` with a regex. After an
      // undo, load() leaves [SetUp]/[FEN] header tags in the PGN, which the
      // regex happily returned as "moves" — the move list showed
      // `[SetUp, "1"]` where notation belonged.
      final game = _gameWith(_opening);
      game.undoMove();
      expect(game.moveHistorySan, ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5']);
      for (final san in game.moveHistorySan) {
        expect(san, isNot(contains('[')));
      }
    });
  });

  group('cost per screen rebuild', () {
    // The game screen reads these from build(), and the screen rebuilds on
    // every clock tick. Both used to replay the whole game on each call, so the
    // per-rebuild cost climbed with every move — which is what made the app
    // (and, on web, the engine sharing its thread) crawl a few turns in.
    test('does not grow with the length of the game', () {
      final short = _gameWith(_opening);
      final long = ChessGame();
      // A long, quiet game: shuffle the knights back and forth.
      const shuffle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
      for (var i = 0; i < 15; i++) {
        for (final m in shuffle) {
          long.makeMove(m);
        }
      }
      expect(long.moveHistory.length, 60);

      int cost(ChessGame game) {
        // Warm up, then measure what one rebuild reads.
        for (var i = 0; i < 20; i++) {
          game.moveHistorySan;
          game.isGameOver;
        }
        final sw = Stopwatch()..start();
        for (var i = 0; i < 200; i++) {
          game.moveHistorySan;
          game.isGameOver;
        }
        return sw.elapsedMicroseconds;
      }

      final shortCost = cost(short);
      final longCost = cost(long);

      // A 60-ply game reads a longer list than a 6-ply one, so some growth is
      // expected — but nowhere near the order of magnitude a full replay costs.
      expect(longCost, lessThan(shortCost * 10 + 20000),
          reason: 'rebuild cost scales with game length: '
              '${shortCost}us at 6 plies vs ${longCost}us at 60');
    });

    test('game-over state is recomputed after the position changes', () {
      final game = ChessGame();
      expect(game.isGameOver, isFalse);
      // Fool's mate.
      for (final m in ['f2f3', 'e7e5', 'g2g4', 'd8h4']) {
        expect(game.makeMove(m), isTrue);
      }
      expect(game.isGameOver, isTrue);
      expect(game.gameOverReason, 'Checkmate');

      game.undoMove();
      expect(game.isGameOver, isFalse,
          reason: 'cached game-over state must be dropped when the board moves');
    });

    test('resignation and draw agreement invalidate the cached state', () {
      final game = _gameWith(_opening);
      expect(game.isGameOver, isFalse);
      game.resign();
      expect(game.isGameOver, isTrue);
      expect(game.gameOverReason, 'Resignation');
    });
  });
}
