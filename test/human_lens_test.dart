import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/human_lens.dart';

/// A stand-in for Maia: a fixed distribution per rating.
HumanPolicy _policy(Map<String, double> Function(int elo) at) =>
    (cmd, elo) async => at(elo);

/// A stand-in engine: scores (White's view) keyed by the last move played;
/// any other position is the root, where it answers [best].
PositionEvaluator _engine(Map<String, double> afterMove,
        {String best = 'e2e4', double root = 0.3}) =>
    (cmd) async {
      final score = afterMove[cmd.split(' ').last];
      if (score == null) return (score: root, bestMove: best);
      return (score: score, bestMove: null);
    };

void main() {
  group('winChance', () {
    test('is even at 0 and saturates', () {
      expect(winChance(0), closeTo(0.5, 1e-9));
      expect(winChance(5), greaterThan(0.85));
      expect(winChance(-5), lessThan(0.15));
      expect(winChance(1000), winChance(20));
    });
  });

  group('analyzePosition', () {
    test('flags a trap when the popular move loses', () async {
      final lens = HumanLens(
        policy: _policy((_) => {'e2e4': 0.10, 'd2d4': 0.20, 'g2g4': 0.70}),
        evaluate: _engine({'e2e4': 0.4, 'd2d4': 0.3, 'g2g4': -2.5}),
        ladder: const [1100, 1500],
      );
      final r = await lens.analyzePosition('position startpos', elo: 1500);

      expect(r.bestMove, 'e2e4');
      expect(r.candidates.first.uci, 'g2g4');
      expect(r.trapMove?.uci, 'g2g4');
      expect(r.isTrap, isTrue);
      expect(r.trapRisk, closeTo(0.70, 1e-9));
      expect(r.bestMoveProbability, closeTo(0.10, 1e-9));
      expect(r.findability, Findability.findable);
    });

    test('scores from the mover\'s side when Black is to move', () async {
      // After 1.e4 Black moves; a White-positive score is bad for Black.
      final lens = HumanLens(
        policy: _policy((_) => {'e7e5': 0.8, 'f7f6': 0.2}),
        evaluate: _engine({'e7e5': 0.3, 'f7f6': 2.0}, best: 'e7e5'),
        ladder: const [1500],
      );
      final r = await lens.analyzePosition('position startpos moves e2e4',
          elo: 1500);
      final f6 = r.candidates.firstWhere((c) => c.uci == 'f7f6');
      expect(f6.evalAfter, -2.0);
      expect(f6.isMistake, isTrue);
      expect(r.isTrap, isFalse, reason: 'most players find e5');
    });

    test('includes the best move even when nobody plays it', () async {
      final lens = HumanLens(
        policy: _policy((_) => {'a2a3': 0.98, 'e2e4': 0.001, 'h2h3': 0.019}),
        evaluate: _engine({'a2a3': 0.1, 'e2e4': 0.3}),
        ladder: const [1500],
      );
      final r = await lens.analyzePosition('position startpos', elo: 1500);
      expect(r.candidates.map((c) => c.uci), containsAll(['a2a3', 'e2e4']));
      expect(r.candidates.map((c) => c.uci), isNot(contains('h2h3')));
      expect(r.findability, Findability.veryHard);
    });

    test('finds the rating where the best move becomes natural', () async {
      final lens = HumanLens(
        policy: _policy((elo) {
          final p = (elo - 800) / 2000; // 0 at 800, 0.75 at 2300
          return {'e2e4': p, 'a2a3': 1 - p};
        }),
        evaluate: _engine({'e2e4': 0.3, 'a2a3': 0.0}),
      );
      final r = await lens.analyzePosition('position startpos', elo: 1400);
      expect(r.naturalFromElo, 2000);
      expect(r.findabilityByElo.keys, defaultEloLadder);
    });

    test('a move lost in a won position is not a mistake', () async {
      final lens = HumanLens(
        policy: _policy((_) => {'e2e4': 0.5, 'd2d4': 0.5}),
        evaluate: _engine({'e2e4': 12.0, 'd2d4': 9.0}),
        ladder: const [1500],
      );
      final r = await lens.analyzePosition('position startpos', elo: 1500);
      expect(r.trapMove, isNull);
    });
  });

  group('estimateElo', () {
    List<HumanMoveReview> moves(Map<int, double> p, int n) => [
          for (var i = 0; i < n; i++)
            HumanMoveReview(
              ply: i * 2,
              played: 'x',
              bestMove: 'x',
              playedProbability: 0,
              bestProbability: 0,
              playedByElo: p,
            )
        ];

    test('picks the rating that explains the moves best', () {
      final e = estimateElo(moves({800: .1, 1100: .2, 1400: .4, 1700: .2}, 10));
      expect(e, closeTo(1400, 1));
    });

    test('interpolates between rungs', () {
      final e =
          estimateElo(moves({800: .1, 1100: .3, 1400: .4, 1700: .38}, 10))!;
      expect(e, greaterThan(1400));
      expect(e, lessThan(1550));
    });

    test('is null with nothing to go on', () {
      expect(estimateElo(const []), isNull);
    });
  });

  test('reviewMoves reports how hard the missed move was', () async {
    // Root: best is e2e4. After e2e4 White is +0.5, after a2a3 -1.5.
    final lens = HumanLens(
      policy: _policy((elo) =>
          {'a2a3': 0.9, 'e2e4': elo >= 2000 ? 0.5 : 0.05, 'd2d4': 0.05}),
      evaluate: _engine({'e2e4': 0.5, 'a2a3': -1.5, 'd2d4': 0.45}),
      ladder: const [1400, 2000],
    );
    final r = await lens.reviewMoves(
      plies: const [0, 0, 0],
      positionCommands: List.filled(3, 'position startpos'),
      played: const ['a2a3', 'e2e4', 'd2d4'],
      elo: 1400,
    );
    expect(r[0].bestMove, 'e2e4');
    expect(r[0].isMistake, isTrue);
    expect(r[0].missedFindability, Findability.hard);
    expect(r[0].playedByElo, {1400: 0.9, 2000: 0.9});
    expect(r[1].playedBest, isTrue);
    expect(r[1].missedFindability, isNull);
    expect(r[2].isMistake, isFalse, reason: 'd4 is as good as e4');
  });

  test('reviewMoves stops when cancelled', () async {
    var calls = 0;
    final lens = HumanLens(
      policy: _policy((_) => {'e2e4': 1.0}),
      evaluate: _engine(const {}),
      ladder: const [1500],
    );
    final r = await lens.reviewMoves(
      plies: const [0, 2, 4],
      positionCommands: List.filled(3, 'position startpos'),
      played: const ['e2e4', 'e2e4', 'e2e4'],
      elo: 1500,
      onProgress: (_, __) => calls++,
      cancelled: () => calls >= 1,
    );
    expect(r, hasLength(1));
  });
}
