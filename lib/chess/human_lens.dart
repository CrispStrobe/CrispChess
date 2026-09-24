/// Human Lens — how a *human* of a given rating sees a position.
///
/// Every analysis board answers "what is the best move?". This answers the
/// questions an engine can't: how likely a player of rating R is to find that
/// move, which wrong moves tempt them, and — over a whole game — what rating
/// the moves actually played look like.
///
/// The probabilities come from Maia (trained to predict human moves at a given
/// rating) and the verdicts from an ordinary engine. Both arrive as injected
/// functions so this file stays pure logic and can be tested without a model.
library;

import 'dart:math' as math;

/// Probability of each legal move (UCI) for a player of [elo], summing to 1.
typedef HumanPolicy = Future<Map<String, double>> Function(
    String positionCommand, int elo);

/// Engine verdict on a position: score in pawns from White's point of view,
/// plus the engine's best move there (null once the game is over).
typedef PositionEvaluator = Future<({double score, String? bestMove})>
    Function(String positionCommand);

/// Ratings the findability curve is sampled at. Maia is trained on roughly
/// this range; outside it the conditioning stops meaning much.
const List<int> defaultEloLadder = [800, 1100, 1400, 1700, 2000, 2300];

/// Expected score for the side to move, from a pawn evaluation — the
/// logistic curve Lichess fits to its own games. Judging moves by this instead
/// of by raw pawns keeps "+9 to +7" from counting as a mistake while
/// "+0.5 to −1.5" does.
double winChance(double pawns) {
  final cp = pawns.clamp(-20.0, 20.0) * 100;
  return 1 / (1 + math.exp(-0.00368208 * cp));
}

/// How hard a move is to find for a given rating.
enum Findability {
  /// Played by most players at this level.
  obvious,

  /// A common choice.
  natural,

  /// A real minority find it.
  findable,

  /// Rarely found.
  hard,

  /// Almost nobody at this level plays it.
  veryHard;

  static Findability fromProbability(double p) {
    if (p >= 0.5) return obvious;
    if (p >= 0.25) return natural;
    if (p >= 0.1) return findable;
    if (p >= 0.03) return hard;
    return veryHard;
  }
}

/// A move humans consider here, with the engine's opinion of it.
class HumanCandidate {
  /// UCI move.
  final String uci;

  /// Share of players at the lens rating who play it.
  final double probability;

  /// Engine score after the move, pawns from the *mover's* point of view.
  final double? evalAfter;

  /// Drop in the mover's expected score compared with the engine's best move.
  /// 0 for the best move itself, null when the move was not evaluated.
  final double? winChanceLoss;

  const HumanCandidate({
    required this.uci,
    required this.probability,
    this.evalAfter,
    this.winChanceLoss,
  });

  /// Loses at least a mistake's worth of expected score (10 points of 100).
  bool get isMistake => (winChanceLoss ?? 0) >= HumanLensReport.mistakeLoss;
}

/// What the Human Lens concluded about one position at one rating.
class HumanLensReport {
  /// Expected-score drop (0..1) from which a move counts as a mistake.
  /// Lichess marks a mistake at 10 points of winning chances, a blunder at 15.
  static const double mistakeLoss = 0.10;

  /// The rating the report is for.
  final int elo;

  /// Engine's best move, UCI. Null when the side to move has no moves.
  final String? bestMove;

  /// Moves humans at [elo] play here, most popular first. Includes the best
  /// move even when almost nobody plays it.
  final List<HumanCandidate> candidates;

  /// P(best move) at each rating of the ladder, ascending by rating.
  final Map<int, double> findabilityByElo;

  const HumanLensReport({
    required this.elo,
    required this.bestMove,
    required this.candidates,
    required this.findabilityByElo,
  });

  HumanCandidate? get best {
    for (final c in candidates) {
      if (c.uci == bestMove) return c;
    }
    return null;
  }

  /// Share of players at [elo] who find the engine's move.
  double get bestMoveProbability => best?.probability ?? 0;

  Findability get findability =>
      Findability.fromProbability(bestMoveProbability);

  /// Share of players at [elo] who play a move that is a mistake here.
  /// Only counts the evaluated candidates, so it is a lower bound.
  double get trapRisk => candidates
      .where((c) => c.isMistake)
      .fold(0.0, (sum, c) => sum + c.probability);

  /// The single most tempting mistake, if any.
  HumanCandidate? get trapMove {
    for (final c in candidates) {
      if (c.isMistake) return c;
    }
    return null;
  }

  /// A trap: the most popular move at this rating is a mistake, or mistakes
  /// together draw at least a third of the players.
  bool get isTrap =>
      trapMove != null &&
      (candidates.first.isMistake || trapRisk >= 1 / 3);

  /// Lowest rating on the ladder at which a majority finds the best move.
  /// Null when no rating on the ladder gets there.
  int? get naturalFromElo {
    for (final e in findabilityByElo.entries) {
      if (e.value >= 0.5) return e.key;
    }
    return null;
  }
}

/// A move actually played in a game, seen through the lens.
class HumanMoveReview {
  /// Ply index in the main line, 0-based (0 = White's first move).
  final int ply;
  final String played;
  final String? bestMove;

  /// Share of players at the reviewed rating who play [played].
  final double playedProbability;

  /// Share of players at the reviewed rating who find [bestMove].
  final double bestProbability;

  /// P(played move) at each rating of the ladder, for the rating estimate.
  final Map<int, double> playedByElo;

  /// Expected score the played move gave away against [bestMove] (0..1).
  final double winChanceLoss;

  const HumanMoveReview({
    required this.ply,
    required this.played,
    required this.bestMove,
    required this.playedProbability,
    required this.bestProbability,
    required this.playedByElo,
    this.winChanceLoss = 0,
  });

  bool get playedBest => bestMove != null && played == bestMove;

  /// The move cost at least a mistake's worth of expected score.
  bool get isMistake => winChanceLoss >= HumanLensReport.mistakeLoss;

  /// How hard the move the player missed was to find. Null when they found it.
  Findability? get missedFindability => playedBest || bestMove == null
      ? null
      : Findability.fromProbability(bestProbability);
}

/// Rating whose players' choices best explain [moves], by maximum likelihood
/// over the ladder, refined by fitting a parabola through the best rung and its
/// neighbours. Null when there is nothing to go on.
///
/// Probabilities are floored so a single move the model found unthinkable does
/// not dominate the estimate.
int? estimateElo(List<HumanMoveReview> moves) {
  if (moves.isEmpty) return null;
  final ladder = moves.first.playedByElo.keys.toList()..sort();
  if (ladder.isEmpty) return null;
  final ll = [
    for (final elo in ladder)
      moves.fold(0.0,
          (s, m) => s + math.log(math.max(m.playedByElo[elo] ?? 0, 0.005)))
  ];
  var i = 0;
  for (var k = 1; k < ll.length; k++) {
    if (ll[k] > ll[i]) i = k;
  }
  if (i == 0 || i == ll.length - 1) return ladder[i];
  // Vertex of the parabola through three equally spaced points.
  final a = ll[i - 1], b = ll[i], c = ll[i + 1];
  final denom = a - 2 * b + c;
  if (denom >= 0) return ladder[i];
  final offset = 0.5 * (a - c) / denom; // in rungs, within (-0.5, 0.5)
  final step = ladder[i + 1] - ladder[i];
  return (ladder[i] + offset * step).round();
}

/// Runs the lens: Maia for what humans play, an engine for what it is worth.
class HumanLens {
  final HumanPolicy policy;
  final PositionEvaluator evaluate;
  final List<int> ladder;

  HumanLens({
    required this.policy,
    required this.evaluate,
    this.ladder = defaultEloLadder,
  });

  /// Everything the lens says about the position of [positionCommand] for a
  /// player rated [elo].
  ///
  /// Costs one model pass per ladder rung (plus [elo] if off the ladder) and
  /// one engine evaluation per candidate: moves at least [minProbability]
  /// likely, at most [maxCandidates] of them, plus the engine's best move.
  Future<HumanLensReport> analyzePosition(
    String positionCommand, {
    required int elo,
    int maxCandidates = 4,
    double minProbability = 0.05,
  }) async {
    final root = await evaluate(positionCommand);
    final bestMove = root.bestMove;
    final whiteToMove = _whiteToMove(positionCommand);

    final byElo = <int, Map<String, double>>{};
    for (final e in {...ladder, elo}.toList()..sort()) {
      byElo[e] = await policy(positionCommand, e);
    }
    final probs = byElo[elo]!;

    final ranked = probs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final picked = <String>[
      for (final e in ranked.take(maxCandidates))
        if (e.value >= minProbability || e == ranked.first) e.key,
    ];
    if (bestMove != null && !picked.contains(bestMove)) picked.add(bestMove);

    // Every candidate — the best move too — is scored the same way, one ply
    // down, so the comparison is not skewed by search-depth parity.
    final evals = <String, double>{};
    for (final uci in picked) {
      final after = await evaluate(_withMove(positionCommand, uci));
      final white = after.score;
      evals[uci] = whiteToMove ? white : -white;
    }
    final bestEval = bestMove != null ? evals[bestMove] : null;

    final candidates = [
      for (final uci in picked)
        HumanCandidate(
          uci: uci,
          probability: probs[uci] ?? 0,
          evalAfter: evals[uci],
          winChanceLoss: bestEval == null || evals[uci] == null
              ? null
              : math.max(0.0, winChance(bestEval) - winChance(evals[uci]!)),
        ),
    ]..sort((a, b) => b.probability.compareTo(a.probability));

    return HumanLensReport(
      elo: elo,
      bestMove: bestMove,
      candidates: candidates,
      findabilityByElo: {
        for (final e in ladder) e: byElo[e]![bestMove] ?? 0,
      },
    );
  }

  /// Reviews moves of a game against the rating [elo].
  ///
  /// [positionCommands] are the positions *before* each of [played]. For each
  /// one the engine names the best move and scores it against the move played,
  /// and Maia says how many players at each rating would have played either.
  Future<List<HumanMoveReview>> reviewMoves({
    required List<int> plies,
    required List<String> positionCommands,
    required List<String> played,
    required int elo,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final rungs = {...ladder, elo}.toList()..sort();
    final out = <HumanMoveReview>[];
    for (var i = 0; i < played.length; i++) {
      if (cancelled?.call() ?? false) break;
      final cmd = positionCommands[i];
      final bestMove = (await evaluate(cmd)).bestMove;

      var loss = 0.0;
      if (bestMove != null && bestMove != played[i]) {
        final mover = _whiteToMove(cmd) ? 1.0 : -1.0;
        final afterBest = (await evaluate(_withMove(cmd, bestMove))).score;
        final afterPlayed = (await evaluate(_withMove(cmd, played[i]))).score;
        loss = math.max(0.0,
            winChance(mover * afterBest) - winChance(mover * afterPlayed));
      }

      final byElo = <int, Map<String, double>>{};
      for (final e in rungs) {
        byElo[e] = await policy(cmd, e);
      }
      final atElo = byElo[elo]!;
      out.add(HumanMoveReview(
        ply: plies[i],
        played: played[i],
        bestMove: bestMove,
        playedProbability: atElo[played[i]] ?? 0,
        bestProbability: bestMove == null ? 0 : atElo[bestMove] ?? 0,
        playedByElo: {for (final e in ladder) e: byElo[e]![played[i]] ?? 0},
        winChanceLoss: loss,
      ));
      onProgress?.call(i + 1, played.length);
    }
    return out;
  }

  static bool _whiteToMove(String positionCommand) {
    final parts = positionCommand.trim().split(RegExp(r'\s+'));
    final movesIdx = parts.indexOf('moves');
    final plies = movesIdx < 0 ? 0 : parts.length - movesIdx - 1;
    var whiteStarts = true;
    if (parts.length > 3 && parts[1] == 'fen') whiteStarts = parts[3] != 'b';
    return plies.isEven == whiteStarts;
  }

  static String _withMove(String positionCommand, String uci) =>
      positionCommand.contains(' moves ')
          ? '$positionCommand $uci'
          : '${positionCommand.trim()} moves $uci';
}
