// Perf harness: how per-move search cost evolves as a game progresses.
//
// Run: dart run tool/perf/bench_search.dart
import 'dart:io';
import 'package:crisp_chess_engine/bitboard.dart' as bb;

// Kasparov–Topalov, Wijk aan Zee 1999 (first 44 plies) in UCI.
const _gameUci = 'e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 c1e3 f8g7 d1d2 c7c6 f2f3 b7b5 '
    'g1e2 b8d7 e3h6 g7h6 d2h6 c8b7 a2a3 e7e5 e1c1 d8e7 c1b1 a7a6 e2c1 e8c8 '
    'c1b3 e5d4 d1d4 c6c5 d4d1 d7b6 g2g3 c8b8 b3a5 b7a8 f1h3 d6d5 h6f4 b8a7 '
    'h1e1 d5d4 c3d5 b6d5';

void main(List<String> args) {
  final moves = _gameUci.split(' ').where((m) => m.isNotEmpty).toList();
  final depths = [4, 6, 8];

  stdout.writeln('=== Bitboard search: fixed DEPTH vs fixed MOVETIME over a game ===');
  stdout.writeln('ply | pieces | ' +
      depths.map((d) => 'd$d ms'.padLeft(8)).join(' | ') +
      ' | depth reached in 1000ms');

  for (var ply = 0; ply <= moves.length; ply += 4) {
    final pos = bb.Position.startpos();
    final hist = <int>[pos.hash()];
    for (final u in moves.take(ply)) {
      final m = pos.moveFromUci(u);
      if (m < 0) break;
      pos.makeMove(m);
      hist.add(pos.hash());
    }
    final fen = pos.toFen();
    final pieces =
        fen.split(' ').first.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;

    final times = <int>[];
    for (final d in depths) {
      final p2 = bb.Position.fromFen(fen);
      final sw = Stopwatch()..start();
      bb.BitboardSearch(p2, repetitionHistory: List.of(hist)).search(d);
      times.add(sw.elapsedMilliseconds);
    }
    final p3 = bb.Position.fromFen(fen);
    final r = bb.BitboardSearch(p3, repetitionHistory: List.of(hist))
        .search(64, timeBudget: const Duration(milliseconds: 1000));

    stdout.writeln('${ply.toString().padLeft(3)} | ${pieces.toString().padLeft(6)} | ' +
        times.map((t) => t.toString().padLeft(8)).join(' | ') +
        ' | ${r?.depth}');
  }
}
