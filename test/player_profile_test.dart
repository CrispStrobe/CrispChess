import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/player_profile.dart';

String pgn(String white, String black, String moves, {String? fen}) => [
      '[Event "Casual"]',
      '[White "$white"]',
      '[Black "$black"]',
      if (fen != null) ...['[SetUp "1"]', '[FEN "$fen"]'],
      '[Result "*"]',
      '',
      '$moves *',
    ].join('\n');

const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

void main() {
  test('collects only the player\'s own moves, by colour', () {
    final p = PlayerProfile.fromPgns([
      pgn('Human', 'Lynx', '1. e4 e5 2. Nf3 Nc6'),
      pgn('Human', 'Maia', '1. e4 c5 2. Nf3 d6'),
      pgn('Lynx', 'Human', '1. d4 d5 2. c4 e6'),
    ]);
    expect(p.games, 3);
    expect(p.bookMoves(start), {'e2e4': 2});
    // As Black after 1.d4 the player chose d5.
    final afterD4 = 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1';
    expect(p.bookMoves(afterD4), {'d7d5': 1});
    // The engine's replies are not in the book.
    final afterE4 = 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1';
    expect(p.bookMoves(afterE4), isNull);
    // 2 + 2 + 2 of the player's moves, newest game first.
    expect(p.moves, hasLength(6));
    expect(p.moves.first.positionCommand, 'position startpos moves d2d4');
    expect(p.moves.first.move, 'd7d5');
  });

  test('two-player games count both sides; FEN starts and others\' games do not',
      () {
    final p = PlayerProfile.fromPgns([
      pgn('Human', 'Human', '1. e4 e5'),
      pgn('Lynx', 'Stockfish', '1. e4 e5'),
      pgn('Human', 'Lynx', '1. Qh5 Kf7',
          fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1x'),
    ]);
    expect(p.games, 1);
    expect(p.moves, hasLength(2));
  });

  test('transpositions share a book entry', () {
    final p = PlayerProfile.fromPgns([
      pgn('Human', 'X', '1. Nf3 Nf6 2. c4'),
      pgn('Human', 'X', '1. c4 Nf6 2. Nf3'),
    ]);
    // After 1.Nf3 Nf6 2.c4 and 1.c4 Nf6 2.Nf3 the position is the same; the
    // player's next moves (none here) share the key. Both first moves are in.
    expect(p.bookMoves(start), {'g1f3': 1, 'c2c4': 1});
    expect(positionKey('x y z w 5 17'), 'x y z');
  });

  test('sampling follows the counts', () {
    final r = math.Random(3);
    final seen = <String, int>{};
    for (var i = 0; i < 4000; i++) {
      final m = PlayerProfile.sample({'e2e4': 3, 'd2d4': 1}, r);
      seen[m] = (seen[m] ?? 0) + 1;
    }
    expect(seen['e2e4']! / 4000, closeTo(0.75, 0.03));
  });

  test('an empty history gives an empty profile', () {
    final p = PlayerProfile.fromPgns(const []);
    expect(p.games, 0);
    expect(p.favouriteFirstMoves(), isEmpty);
  });
}
