// Engine-vs-engine round robin: play strength and move latency.
//
//   flutter test tool/perf/tournament.dart --timeout none
//
// Every engine that can actually run on this machine plays every other one,
// both colours, from a small opening book so the games differ. Each engine gets
// the same per-move time budget, which makes the score a strength comparison
// and the latency numbers a check that the budget is honoured — the point of
// the move to time-based search was that a fixed depth costs an order of
// magnitude more in the middlegame than in the opening.
//
// Web-only engines (Lynx WASM, web Stockfish, Frozenight WASM, Lc0 web) cannot
// take part: they need a browser. Engines whose weights or binaries are not
// present are skipped and reported as such.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/frozenight_engine.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:crispchess/engines/lc0_engine.dart';
import 'package:crispchess/engines/lynx_engine.dart';
import 'package:crispchess/engines/maia3_dart_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- parameters

/// Per-move budget handed to every engine. Small enough to finish a round robin
/// in minutes, large enough that a real search happens.
const Duration kMoveTime = Duration(milliseconds: 300);

/// A move that takes longer than this counts as a hang; the game is abandoned
/// and the engine is reported as broken rather than silently skewing results.
const Duration kHangCutoff = Duration(seconds: 40);

/// Games per ordered pair (A as white vs B, then B as white vs A, repeated).
const int kGamesPerPairing = 1;

/// Plies before a game is called a draw.
const int kPlyCap = 160;

/// Opening lines, so repeated pairings are not the same game.
const List<List<String>> kOpenings = [
  [],
  ['e2e4', 'e7e5'],
  ['d2d4', 'd7d5', 'c2c4', 'e7e6'],
  ['e2e4', 'c7c5', 'g1f3', 'd7d6'],
  ['g1f3', 'g8f6', 'c2c4', 'g7g6'],
  ['d2d4', 'g8f6', 'c2c4', 'e7e6', 'g2g3', 'd7d5'],
];

// ------------------------------------------------------------------- results

class MoveSample {
  final int ply;
  final int micros;
  const MoveSample(this.ply, this.micros);
}

class EngineStats {
  final String name;
  final List<MoveSample> samples = [];
  double points = 0; // 1 win, 0.5 draw
  int games = 0;
  int wins = 0, draws = 0, losses = 0;
  String? brokenReason;

  EngineStats(this.name);

  List<int> _sorted([bool Function(MoveSample)? where]) {
    final xs = [
      for (final s in samples)
        if (where == null || where(s)) s.micros
    ]..sort();
    return xs;
  }

  int _pct(List<int> sorted, double p) =>
      sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];

  int get medianUs => _pct(_sorted(), 0.5);
  int get p95Us => _pct(_sorted(), 0.95);
  int get maxUs => _sorted().isEmpty ? 0 : _sorted().last;
  int get openingMedianUs => _pct(_sorted((s) => s.ply < 20), 0.5);
  int get lateMedianUs => _pct(_sorted((s) => s.ply >= 40), 0.5);

  /// How much slower a late-game move is than an opening one. A fixed-depth
  /// engine climbs here; a time-budgeted one stays near 1.
  double get lateVsOpening {
    final early = openingMedianUs, late = lateMedianUs;
    if (early == 0 || late == 0) return double.nan;
    return late / early;
  }
}

// ------------------------------------------------------------------- engines

class Candidate {
  final String name;
  final Future<ChessEngine?> Function() build;
  const Candidate(this.name, this.build);
}

Future<ChessEngine?> _tryBuild(String label, ChessEngine Function() make) async {
  try {
    final engine = make();
    await engine.initialize().timeout(const Duration(seconds: 90));
    if (engine.state != EngineState.ready) {
      stdout.writeln('  skip $label: initialize left it in ${engine.state}');
      engine.dispose();
      return null;
    }
    return engine;
  } catch (e) {
    stdout.writeln('  skip $label: $e');
    return null;
  }
}

/// The repo's Node UCI adapters, which make the browser-only engines usable
/// headless: they run the very same WASM/JS build the web app does, wrapped as
/// an ordinary UCI process. See tool/uci/.
List<Candidate> _nodeAdapters() {
  final list = <Candidate>[];
  if (Process.runSync('which', ['node']).exitCode != 0) return list;

  final repo = Directory.current.path;
  void add(String name, String script, {String? requires}) {
    final path = '$repo/tool/uci/$script';
    if (!File(path).existsSync()) return;
    if (requires != null && !Directory(requires).existsSync()) {
      stdout.writeln('  skip $name: needs $requires');
      return;
    }
    list.add(Candidate(
      name,
      () => _tryBuild(name,
          () => GenericUciEngine(EngineProfile(name: name, path: path))),
    ));
  }

  add('Lynx WASM', 'lynx_wasm_uci.mjs',
      requires: '$repo/web/lynx/_framework');
  // Downloads stockfish.js on first run, exactly as the app does.
  add('Stockfish.js', 'stockfish_js_uci.mjs');
  if (File('$repo/web/frozenight_wasm_bg.wasm').existsSync()) {
    add('Frozenight WASM', 'frozenight_wasm_uci.mjs');
  }
  return list;
}

/// A reference UCI engine on this machine, if the user has one installed.
/// Never downloaded by this harness — it only uses what is already there.
String? _systemUciEngine() {
  for (final name in ['stockfish', 'lc0']) {
    final which = Process.runSync('which', [name]);
    if (which.exitCode == 0) {
      final path = (which.stdout as String).trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
}

List<Candidate> _candidates() {
  final list = <Candidate>[
    Candidate('Built-in', () => _tryBuild('Built-in', DartEngine.new)),
  ];

  if (LynxEngine.isAvailable) {
    list.add(Candidate('Lynx', () => _tryBuild('Lynx', LynxEngine.new)));
  }
  if (FrozenightEngine.isAvailable) {
    list.add(
        Candidate('Frozenight', () => _tryBuild('Frozenight', FrozenightEngine.new)));
  }
  // Pure Dart + ONNX; downloads its weights on first use. It answers from a
  // single forward pass rather than a search, so the move-time budget does not
  // apply to it — its latency column is inference cost, not a search.
  list.add(Candidate(
    'Maia3 Dart',
    () => _tryBuild('Maia3 Dart',
        () => Maia3DartEngine(variantId: '5m', playerElo: 1900)),
  ));

  // Dart MCTS over a Maia network. Like Maia3 it imitates human play rather
  // than searching for the best move, so its score says more about the model
  // than about the engine.
  list.add(Candidate(
    'Lc0 (Maia 1900)',
    () => _tryBuild('Lc0', () => Lc0Engine(variantId: '1900')),
  ));

  list.addAll(_nodeAdapters());

  final system = _systemUciEngine();
  if (system != null) {
    list.add(Candidate(
      'System UCI (${system.split('/').last})',
      () => _tryBuild(
          'system UCI',
          () => GenericUciEngine(
              EngineProfile(name: 'System UCI', path: system))),
    ));
  }
  return list;
}

// ------------------------------------------------------------------ the game

enum GameResult { whiteWins, blackWins, draw, aborted }

class GameOutcome {
  final GameResult result;
  final String? abortReason;
  final int plies;
  const GameOutcome(this.result, this.plies, [this.abortReason]);
}

String _uciOf(chess.Move m) =>
    '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';

Future<GameOutcome> _playGame({
  required ChessEngine white,
  required ChessEngine black,
  required EngineStats whiteStats,
  required EngineStats blackStats,
  required List<String> opening,
}) async {
  final board = chess.Chess();
  final played = <String>[];

  for (final uci in opening) {
    if (!board.move({'from': uci.substring(0, 2), 'to': uci.substring(2, 4)})) {
      break;
    }
    played.add(uci);
  }

  while (!board.game_over && played.length < kPlyCap) {
    final whiteToMove = board.turn == chess.Color.WHITE;
    final engine = whiteToMove ? white : black;
    final stats = whiteToMove ? whiteStats : blackStats;

    final position = played.isEmpty
        ? 'position startpos'
        : 'position startpos moves ${played.join(' ')}';

    final legal = {for (final m in board.generate_moves()) _uciOf(m)};
    if (legal.isEmpty) break;

    final sw = Stopwatch()..start();
    String move;
    try {
      move = await engine
          .bestMove(position, moveTime: kMoveTime, skillLevel: 20)
          .timeout(kHangCutoff);
    } on TimeoutException {
      stats.brokenReason = 'no move within ${kHangCutoff.inSeconds}s '
          'at ply ${played.length}';
      return GameOutcome(GameResult.aborted, played.length, stats.brokenReason);
    } catch (e) {
      stats.brokenReason = 'bestMove threw at ply ${played.length}: $e';
      return GameOutcome(GameResult.aborted, played.length, stats.brokenReason);
    }
    sw.stop();
    stats.samples.add(MoveSample(played.length, sw.elapsedMicroseconds));

    if (!legal.contains(move)) {
      stats.brokenReason =
          'illegal move "$move" at ply ${played.length} (${board.fen})';
      return GameOutcome(GameResult.aborted, played.length, stats.brokenReason);
    }

    board.move({
      'from': move.substring(0, 2),
      'to': move.substring(2, 4),
      if (move.length > 4) 'promotion': move.substring(4, 5),
    });
    played.add(move);
  }

  if (board.in_checkmate) {
    // The side to move is mated, so the other side won.
    return GameOutcome(
        board.turn == chess.Color.WHITE
            ? GameResult.blackWins
            : GameResult.whiteWins,
        played.length);
  }
  return GameOutcome(GameResult.draw, played.length);
}

// -------------------------------------------------------------------- report

String _ms(int micros) => (micros / 1000).toStringAsFixed(0);

/// Elo difference implied by a score rate against the rest of the field.
///
/// The inverse of the Elo expected-score curve: d = -400 * log10(1/p - 1).
/// A clean sweep or a whitewash has no finite answer, so those are reported as
/// bounds.
String _eloDiff(double score, int games) {
  if (games == 0) return '—';
  final p = score / games;
  if (p <= 0.0) return '<-800';
  if (p >= 1.0) return '>+800';
  final elo = -400 * (math.log(1 / p - 1) / math.ln10);
  return '${elo >= 0 ? '+' : ''}${elo.toStringAsFixed(0)}';
}

void main() {
  test('round robin', () async {
    stdout.writeln('Building engines…');
    final candidates = _candidates();
    final engines = <String, ChessEngine>{};
    for (final c in candidates) {
      final e = await c.build();
      if (e != null) engines[c.name] = e;
    }

    stdout.writeln('Playing with ${engines.length} engine(s): '
        '${engines.keys.join(', ')}');
    if (engines.length < 2) {
      stdout.writeln('Need at least two runnable engines for a round robin.');
      for (final e in engines.values) {
        e.dispose();
      }
      return;
    }

    final stats = {
      for (final name in engines.keys) name: EngineStats(name),
    };
    final crossTable = <String, Map<String, String>>{
      for (final a in engines.keys)
        a: {for (final b in engines.keys) b: ''},
    };

    final names = engines.keys.toList();
    var openingIndex = 0;

    for (var i = 0; i < names.length; i++) {
      for (var j = i + 1; j < names.length; j++) {
        final a = names[i], b = names[j];
        var aPoints = 0.0, bPoints = 0.0;

        for (var round = 0; round < kGamesPerPairing; round++) {
          for (final aIsWhite in [true, false]) {
            if (stats[a]!.brokenReason != null ||
                stats[b]!.brokenReason != null) {
              continue;
            }
            final opening = kOpenings[openingIndex++ % kOpenings.length];
            final white = aIsWhite ? a : b;
            final black = aIsWhite ? b : a;

            final outcome = await _playGame(
              white: engines[white]!,
              black: engines[black]!,
              whiteStats: stats[white]!,
              blackStats: stats[black]!,
              opening: opening,
            );

            if (outcome.result == GameResult.aborted) {
              stdout.writeln('  $white vs $black: ABORTED '
                  '(${outcome.abortReason})');
              continue;
            }

            double wScore;
            switch (outcome.result) {
              case GameResult.whiteWins:
                wScore = 1;
              case GameResult.blackWins:
                wScore = 0;
              default:
                wScore = 0.5;
            }
            final aScore = aIsWhite ? wScore : 1 - wScore;
            aPoints += aScore;
            bPoints += 1 - aScore;

            stats[a]!.games++;
            stats[b]!.games++;
            stats[a]!.points += aScore;
            stats[b]!.points += 1 - aScore;
            if (aScore == 1) {
              stats[a]!.wins++;
              stats[b]!.losses++;
            } else if (aScore == 0) {
              stats[a]!.losses++;
              stats[b]!.wins++;
            } else {
              stats[a]!.draws++;
              stats[b]!.draws++;
            }

            stdout.writeln('  $white vs $black (${opening.length} book plies): '
                '${outcome.result.name} in ${outcome.plies} plies');
          }
        }
        crossTable[a]![b] = '$aPoints';
        crossTable[b]![a] = '$bPoints';
      }
    }

    stdout.writeln('\n=== Strength (${kMoveTime.inMilliseconds}ms/move) ===');
    stdout.writeln('engine               | games |  W  D  L | score | vs field');
    final ranked = stats.values.toList()
      ..sort((x, y) => (y.points / (y.games == 0 ? 1 : y.games))
          .compareTo(x.points / (x.games == 0 ? 1 : x.games)));
    for (final s in ranked) {
      stdout.writeln('${s.name.padRight(20)} | '
          '${s.games.toString().padLeft(5)} | '
          '${s.wins.toString().padLeft(2)} '
          '${s.draws.toString().padLeft(2)} '
          '${s.losses.toString().padLeft(2)} | '
          '${s.points.toStringAsFixed(1).padLeft(5)} | '
          '${_eloDiff(s.points, s.games).padLeft(6)}');
    }

    stdout.writeln('\n=== Cross table (points out of '
        '${kGamesPerPairing * 2} per pairing) ===');
    final header = StringBuffer('${''.padRight(20)} |');
    for (final b in names) {
      header.write(' ${b.length > 10 ? b.substring(0, 10) : b}'.padRight(12));
    }
    stdout.writeln(header);
    for (final a in names) {
      final row = StringBuffer('${a.padRight(20)} |');
      for (final b in names) {
        row.write(' ${a == b ? '—' : crossTable[a]![b]!}'.padRight(12));
      }
      stdout.writeln(row);
    }

    stdout.writeln('\n=== Move latency (budget '
        '${kMoveTime.inMilliseconds}ms) ===');
    stdout.writeln('engine               | moves | median | p95  | max   | '
        'opening | late | late/opening');
    for (final s in ranked) {
      stdout.writeln('${s.name.padRight(20)} | '
          '${s.samples.length.toString().padLeft(5)} | '
          '${_ms(s.medianUs).padLeft(6)} | '
          '${_ms(s.p95Us).padLeft(4)} | '
          '${_ms(s.maxUs).padLeft(5)} | '
          '${_ms(s.openingMedianUs).padLeft(7)} | '
          '${_ms(s.lateMedianUs).padLeft(4)} | '
          '${s.lateVsOpening.toStringAsFixed(2).padLeft(12)}');
    }

    final broken = stats.values.where((s) => s.brokenReason != null);
    if (broken.isNotEmpty) {
      stdout.writeln('\n=== Broken ===');
      for (final s in broken) {
        stdout.writeln('${s.name}: ${s.brokenReason}');
      }
    }

    for (final e in engines.values) {
      e.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 60)));
}
