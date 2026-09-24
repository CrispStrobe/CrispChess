import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/player_profile.dart';
import 'package:crispchess/engines/ghost_engine.dart';

String pgn(String moves) =>
    '[White "Human"]\n[Black "Engine"]\n[Result "*"]\n\n$moves *';

void main() {
  final profile = PlayerProfile.fromPgns([
    pgn('1. e4 e5 2. Nf3 Nc6'),
    pgn('1. e4 c5 2. Nf3 d6'),
    pgn('1. e4 e5 2. Bc4 Nf6'),
  ]);

  test('plays the player\'s own book moves, in proportion', () async {
    final asked = <int>[];
    final g = GhostEngine(
      profileOverride: profile,
      eloOverride: 1234,
      policyOverride: (cmd, elo) async {
        asked.add(elo);
        return {'d2d4': 1.0};
      },
      random: math.Random(7),
    );
    await g.initialize();
    // Always 1.e4 from the start: it is the only first move in the book.
    for (var i = 0; i < 10; i++) {
      expect(await g.bestMove('position startpos'), 'e2e4');
    }
    // After 1.e4 e5 the player chose Nf3 once and Bc4 once.
    final seen = <String>{};
    for (var i = 0; i < 40; i++) {
      seen.add(await g.bestMove('position startpos moves e2e4 e7e5'));
    }
    expect(seen, {'g1f3', 'f1c4'});
    expect(asked, isEmpty, reason: 'book moves need no model');
  });

  test('off the book it samples Maia at the player\'s rating', () async {
    final asked = <int>[];
    final g = GhostEngine(
      profileOverride: profile,
      eloOverride: 1234,
      policyOverride: (cmd, elo) async {
        asked.add(elo);
        return {'b1c3': 0.5, 'g1f3': 0.5};
      },
      random: math.Random(1),
    );
    await g.initialize();
    final seen = <String>{};
    for (var i = 0; i < 30; i++) {
      seen.add(await g.bestMove('position startpos moves d2d4 d7d5'));
    }
    expect(seen, {'b1c3', 'g1f3'});
    expect(asked.toSet(), {1234});
  });

  test('a book move that is not legal here is never played', () async {
    // A profile whose only entry at the start is an impossible "move".
    final bad = PlayerProfile(1, {positionKey('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'): {'e2e5': 3}}, const []);
    final g = GhostEngine(
      profileOverride: bad,
      policyOverride: (cmd, elo) async => {'e2e4': 1.0},
    );
    await g.initialize();
    expect(await g.bestMove('position startpos'), 'e2e4');
  });
}
