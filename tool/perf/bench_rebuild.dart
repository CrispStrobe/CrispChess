// Measures what one game-screen rebuild pays to read the move list and the
// game-over state, before and after the caching work.
//
// Run: flutter test tool/perf/bench_rebuild.dart
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/chess_game.dart';
import 'package:flutter_test/flutter_test.dart';

const _gameUci = 'e2e4 d7d6 d2d4 g8f6 b1c3 g7g6 c1e3 f8g7 d1d2 c7c6 f2f3 b7b5 '
    'g1e2 b8d7 e3h6 g7h6 d2h6 c8b7 a2a3 e7e5 e1c1 d8e7 c1b1 a7a6 e2c1 e8c8 '
    'c1b3 e5d4 d1d4 c6c5 d4d1 d7b6 g2g3 c8b8 b3a5 b7a8 f1h3 d6d5 h6f4 b8a7 '
    'h1e1 d5d4 c3d5 b6d5 e4d5 e7d6';

final _results = {'1-0', '0-1', '1/2-1/2', '*'};

/// What `moveHistorySan` used to do: re-derive the whole game's notation from
/// `package:chess`'s PGN export (which undoes and replays every move).
List<String> _sanViaPgn(chess.Chess game) => game
    .pgn()
    .replaceAll(RegExp(r'\d+\.+\s*'), '')
    .trim()
    .split(RegExp(r'\s+'))
    .where((s) => s.isNotEmpty && !_results.contains(s))
    .toList();

int _timeUs(int reps, void Function() body) {
  for (var i = 0; i < 20; i++) {
    body();
  }
  final sw = Stopwatch()..start();
  for (var i = 0; i < reps; i++) {
    body();
  }
  return sw.elapsedMicroseconds ~/ reps;
}

void main() {
  test('per-rebuild cost, old path vs new', () {
    final moves = _gameUci.split(' ').where((m) => m.isNotEmpty).toList();

    print('plies |  old us | new us | speedup');
    for (final plies in [4, 12, 24, 36, moves.length]) {
      final game = ChessGame();
      final raw = chess.Chess();
      for (final u in moves.take(plies)) {
        game.makeMove(u);
        raw.move({
          'from': u.substring(0, 2),
          'to': u.substring(2, 4),
          if (u.length > 4) 'promotion': u.substring(4, 5),
        });
      }

      final oldCost = _timeUs(200, () {
        _sanViaPgn(raw);
        raw.game_over;
      });
      final newCost = _timeUs(200, () {
        game.moveHistorySan;
        game.isGameOver;
      });

      print('${plies.toString().padLeft(5)} | '
          '${oldCost.toString().padLeft(7)} | '
          '${newCost.toString().padLeft(6)} | '
          '${(oldCost / (newCost == 0 ? 1 : newCost)).toStringAsFixed(0)}x');
    }
  });
}
