import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/services/rating_fit.dart';

RatedGame g(String w, String b, double s) => (white: w, black: b, score: s);

void main() {
  test('3 of 4 wins is a 191-point gap without the prior', () {
    final r = fitRatings([
      g('A', 'B', 1), g('B', 'A', 0), g('A', 'B', 1), g('B', 'A', 1),
    ], prior: 0);
    final a = r.firstWhere((p) => p.name == 'A');
    final b = r.firstWhere((p) => p.name == 'B');
    expect(a.rating - b.rating, closeTo(400 * math.log(3) / math.ln10, 0.01));
    expect((a.rating + b.rating) / 2, closeTo(1500, 1e-6));
    expect(a.wins, 3);
    expect(b.losses, 3);
  });

  test('the prior keeps an unbeaten player finite', () {
    final r = fitRatings([g('A', 'B', 1), g('B', 'A', 0)]);
    expect(r.first.name, 'A');
    expect(r.first.rating.isFinite, isTrue);
    expect(r.first.stdErr.isFinite, isTrue);
  });

  test('evenly matched players rate the same', () {
    final r = fitRatings([g('A', 'B', 0.5), g('B', 'A', 0.5), g('A', 'B', 1), g('B', 'A', 1)]);
    expect(r[0].rating, closeTo(r[1].rating, 1e-6));
  });

  test('a round robin orders the players and anchors on one of them', () {
    final games = [
      for (var k = 0; k < 4; k++) ...[
        g('Strong', 'Mid', k < 3 ? 1 : 0.5),
        g('Mid', 'Weak', k < 3 ? 1 : 0),
        g('Strong', 'Weak', 1),
      ]
    ];
    final r = fitRatings(games, anchorPlayer: 'Mid', anchor: 1440);
    expect(r.map((p) => p.name), ['Strong', 'Mid', 'Weak']);
    expect(r[1].rating, closeTo(1440, 1e-6));
    // More games against the pool shrink the error bars.
    final r2 = fitRatings([...games, ...games, ...games], anchorPlayer: 'Mid', anchor: 1440);
    expect(r2.first.stdErr, lessThan(r.first.stdErr));
  });

  test('expected score is the Elo curve', () {
    expect(expectedScore(1500, 1500), 0.5);
    expect(expectedScore(1700, 1500), closeTo(0.76, 0.01));
  });

  test('no games, no ratings', () => expect(fitRatings(const []), isEmpty));
}
