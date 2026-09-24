/// What the app knows about how *you* play, from your saved games: the moves
/// you choose in the openings, and — measured separately by
/// HumanLensService.estimatePlayerElo — the rating your moves look like.
/// "Your Ghost" plays from this.
library;

import 'dart:math' as math;

import 'pgn.dart';

const String _startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// A position without its move counters or en-passant square, so
/// transpositions share an entry. The chess library records an en-passant
/// square after every double pawn push, capture possible or not, which would
/// otherwise split 1.d4 d5 2.c4 from 1.c4 d5 2.d4.
String positionKey(String fen) => fen.split(' ').take(3).join(' ');

/// One of the player's own moves: the position before it (as a UCI
/// `position` command) and the move played.
typedef PlayerMove = ({String positionCommand, String move});

class PlayerProfile {
  /// Games the profile was built from.
  final int games;

  /// Position key -> the player's moves there (UCI) -> how often.
  final Map<String, Map<String, int>> repertoire;

  /// The player's own moves, most recent games first, for rating estimates.
  final List<PlayerMove> moves;

  const PlayerProfile(this.games, this.repertoire, this.moves);

  static const empty = PlayerProfile(0, {}, []);

  /// Builds a profile from saved games (the app's history, newest last).
  /// [playerName] is the PGN name of the player's side ("Human" in games
  /// against an engine; both sides in two-player games). Only games from the
  /// standard start count; the repertoire covers the first [bookPlies] plies.
  factory PlayerProfile.fromPgns(List<String> pgns,
      {String playerName = 'Human', int bookPlies = 24}) {
    final repertoire = <String, Map<String, int>>{};
    final moves = <PlayerMove>[];
    var games = 0;
    for (final pgn in pgns.reversed) {
      final headers = parseHeaders(pgn);
      final white = headers['White'] == playerName;
      final black = headers['Black'] == playerName;
      if (!white && !black) continue;
      final tree = importPgnWithVariations(pgn);
      if (tree == null || tree.root.fen != _startFen) continue;
      final line = tree.root.mainLine;
      if (line.isEmpty) continue;
      games++;
      var fen = tree.root.fen;
      final played = <String>[];
      for (var ply = 0; ply < line.length; ply++) {
        final uci = line[ply].move!;
        final mine = ply.isEven ? white : black;
        if (mine) {
          moves.add((
            positionCommand: played.isEmpty
                ? 'position startpos'
                : 'position startpos moves ${played.join(' ')}',
            move: uci,
          ));
          if (ply < bookPlies) {
            final book = repertoire.putIfAbsent(positionKey(fen), () => {});
            book[uci] = (book[uci] ?? 0) + 1;
          }
        }
        played.add(uci);
        fen = line[ply].fen;
      }
    }
    return PlayerProfile(games, repertoire, moves);
  }

  /// The player's moves in [fen] with their counts, or null if never faced.
  Map<String, int>? bookMoves(String fen) => repertoire[positionKey(fen)];

  /// A move from the book, drawn in proportion to how often it was played.
  static String sample(Map<String, int> counts, math.Random random) {
    final total = counts.values.fold(0, (a, b) => a + b);
    var r = random.nextInt(total);
    for (final e in counts.entries) {
      r -= e.value;
      if (r < 0) return e.key;
    }
    return counts.keys.last;
  }

  /// The player's most frequent first moves as White, as a short summary.
  List<MapEntry<String, int>> favouriteFirstMoves() {
    final first = repertoire[positionKey(_startFen)] ?? const {};
    return first.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}
