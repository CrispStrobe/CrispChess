/// Ratings from a set of games, fitted jointly (Bradley–Terry).
///
/// Ported from `elo.py` of TobiasLogic's Chess Arena
/// (huggingface.co/spaces/TobiasLogic/chess-arena-gpu, MIT): minorisation–
/// maximisation iterations on the Bradley–Terry model, with a small prior of
/// shared draws between every pair so a player who never lost still gets a
/// finite rating, and a standard error per rating from the Fisher
/// information. Unlike running Elo updates, the result does not depend on the
/// order the games were played in.
library;

import 'dart:math' as math;

/// One game: [white] against [black], [score] from White's side
/// (1, 0.5 or 0).
typedef RatedGame = ({String white, String black, double score});

class PlayerRating {
  final String name;
  final double rating;

  /// One standard error of [rating]; infinite with no information.
  final double stdErr;
  final int wins, draws, losses;

  const PlayerRating(this.name, this.rating, this.stdErr, this.wins, this.draws,
      this.losses);

  int get games => wins + draws + losses;

  /// Points scored per game, 0..1.
  double get score => games == 0 ? 0 : (wins + draws / 2) / games;
}

const double _scale = 400 / math.ln10;

/// Fits ratings to [games]. Ratings are centred on [anchor] on average, or,
/// when [anchorPlayer] is given, shifted so that player sits exactly at
/// [anchor]. [prior] is the number of phantom games (as draws) between every
/// pair.
List<PlayerRating> fitRatings(
  List<RatedGame> games, {
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  double tolerance = 1e-11,
  int maxIterations = 10000,
}) {
  final players = {for (final g in games) ...[g.white, g.black]}.toList()..sort();
  if (players.isEmpty) return const [];
  final n = players.length;
  final idx = {for (var i = 0; i < n; i++) players[i]: i};

  final wins = List<double>.filled(n, 0);
  final played = List.generate(n, (_) => List<double>.filled(n, 0));
  final record = List.generate(n, (_) => [0, 0, 0]);
  for (final g in games) {
    final i = idx[g.white]!, j = idx[g.black]!;
    played[i][j] += 1;
    played[j][i] += 1;
    wins[i] += g.score;
    wins[j] += 1 - g.score;
    if (g.score == 1) {
      record[i][0]++;
      record[j][2]++;
    } else if (g.score == 0) {
      record[i][2]++;
      record[j][0]++;
    } else {
      record[i][1]++;
      record[j][1]++;
    }
  }
  if (prior > 0) {
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i != j) played[i][j] += prior;
      }
      wins[i] += prior * (n - 1) / 2;
    }
  }

  var gamma = List<double>.filled(n, 1);
  for (var it = 0; it < maxIterations; it++) {
    final next = List<double>.of(gamma);
    for (var i = 0; i < n; i++) {
      var denom = 0.0;
      for (var j = 0; j < n; j++) {
        if (i != j && played[i][j] > 0) denom += played[i][j] / (gamma[i] + gamma[j]);
      }
      if (denom > 0 && wins[i] > 0) next[i] = wins[i] / denom;
    }
    final geo = math.exp(
        next.fold(0.0, (s, g) => s + math.log(math.max(g, 1e-300))) / n);
    for (var i = 0; i < n; i++) {
      next[i] /= geo;
    }
    var delta = 0.0;
    for (var i = 0; i < n; i++) {
      delta = math.max(delta,
          (math.log(math.max(next[i], 1e-300)) - math.log(math.max(gamma[i], 1e-300))).abs());
    }
    gamma = next;
    if (delta < tolerance) break;
  }

  final raw = [for (final g in gamma) _scale * math.log(g)];
  final shift = anchorPlayer != null && idx.containsKey(anchorPlayer)
      ? anchor - raw[idx[anchorPlayer]!]
      : anchor - raw.fold(0.0, (a, b) => a + b) / n;

  return [
    for (var i = 0; i < n; i++)
      PlayerRating(
        players[i],
        raw[i] + shift,
        () {
          var info = 0.0;
          for (var j = 0; j < n; j++) {
            if (i != j && played[i][j] > 0) {
              final p = gamma[i] / (gamma[i] + gamma[j]);
              info += played[i][j] * p * (1 - p);
            }
          }
          return info > 0 ? _scale / math.sqrt(info) : double.infinity;
        }(),
        record[i][0],
        record[i][1],
        record[i][2],
      ),
  ]..sort((a, b) => b.rating.compareTo(a.rating));
}

/// Expected score of a player rated [a] against one rated [b].
double expectedScore(double a, double b) => 1 / (1 + math.pow(10, (b - a) / 400));
