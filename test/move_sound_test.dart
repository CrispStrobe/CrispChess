import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/services/move_sound.dart';
import 'package:crispchess/services/sound_service.dart';
import 'package:flutter_test/flutter_test.dart';

ChessSound playAndSelect(ChessGame game, String uci) {
  expect(game.makeMove(uci), isTrue, reason: 'legal test move: $uci');
  return soundForMove(
    uci: uci,
    san: game.moveHistorySan.last,
    inCheck: game.inCheck,
  );
}

void main() {
  test('ordinary moves and captures for both player and engine sides', () {
    final game = ChessGame();
    addTearDown(game.dispose);
    expect(playAndSelect(game, 'e2e4'), ChessSound.move);
    expect(playAndSelect(game, 'd7d5'), ChessSound.move);
    expect(playAndSelect(game, 'e4d5'), ChessSound.capture);
    expect(game.moveHistorySan.last, 'exd5');
    expect(playAndSelect(game, 'd8d5'), ChessSound.capture);
    expect(game.moveHistorySan.last, 'Qxd5');
    // The last SAN is used, rather than a capture earlier in the history.
    expect(playAndSelect(game, 'b1c3'), ChessSound.move);
  });

  for (final (side, moves, capture) in [
    ('white', ['e2e4', 'a7a6', 'e4e5', 'd7d5'], 'e5d6'),
    ('black', ['a2a3', 'e7e5', 'a3a4', 'e5e4', 'd2d4'], 'e4d3'),
  ]) {
    test('$side en passant uses capture sound despite an empty destination',
        () {
      final game = ChessGame();
      addTearDown(game.dispose);
      for (final move in moves) {
        expect(game.makeMove(move), isTrue);
      }
      final row = 8 - int.parse(capture[3]);
      final col = capture.codeUnitAt(2) - 'a'.codeUnitAt(0);
      expect(game.board[row][col], isNull);
      expect(playAndSelect(game, capture), ChessSound.capture);
      expect(game.moveHistorySan.last, contains('x'));
    });
  }

  test('castling for either side keeps castle sound', () {
    final game = ChessGame();
    addTearDown(game.dispose);
    expect(game.loadFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'), isTrue);
    expect(playAndSelect(game, 'e1g1'), ChessSound.castle);
    expect(playAndSelect(game, 'e8c8'), ChessSound.castle);
  });

  for (final (label, fen, uci, expected) in [
    (
      'capture promotion',
      'r7/1P5k/8/8/8/8/8/7K w - - 0 1',
      'b7a8q',
      ChessSound.promote
    ),
    (
      'checking promotion',
      '7k/P7/8/8/8/8/8/7K w - - 0 1',
      'a7a8q',
      ChessSound.check
    ),
    (
      'checking capture',
      '4k3/3r4/8/8/6B1/8/8/4K3 w - - 0 1',
      'g4d7',
      ChessSound.check
    ),
  ]) {
    test('$label preserves higher-priority feedback', () {
      final game = ChessGame();
      addTearDown(game.dispose);
      expect(game.loadFen(fen), isTrue);
      expect(playAndSelect(game, uci), expected);
    });
  }

  test('checking castle takes priority, and SAN distinguishes a rook move', () {
    expect(soundForMove(uci: 'e1g1', san: 'O-O+', inCheck: true),
        ChessSound.check);
    expect(
        soundForMove(uci: 'e1g1', san: 'Rg1', inCheck: false), ChessSound.move);
    expect(
        soundForMove(uci: 'e2e4', san: null, inCheck: false), ChessSound.move);
    expect(soundForMove(uci: 'e1g1', san: null, inCheck: false),
        ChessSound.castle);
  });
}
