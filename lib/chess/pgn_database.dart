/// PGN database — parse and browse files with multiple games.

import 'pgn.dart';

/// A single game entry in a PGN database.
class PgnGameEntry {
  final Map<String, String> headers;
  final String moveText;
  final int startOffset; // byte offset in file (for lazy loading)

  PgnGameEntry({
    required this.headers,
    required this.moveText,
    this.startOffset = 0,
  });

  String get white => headers['White'] ?? '?';
  String get black => headers['Black'] ?? '?';
  String get result => headers['Result'] ?? '*';
  String get date => headers['Date'] ?? '?';
  String get event => headers['Event'] ?? '?';
  String get eco => headers['ECO'] ?? '';
  String get site => headers['Site'] ?? '';

  /// Full PGN text for this game.
  String get pgn {
    final sb = StringBuffer();
    for (final entry in headers.entries) {
      sb.writeln('[${entry.key} "${entry.value}"]');
    }
    sb.writeln();
    sb.writeln(moveText);
    return sb.toString();
  }
}

/// Parse a PGN file containing multiple games into a list of entries.
///
/// Handles the standard multi-game PGN format where games are
/// separated by blank lines between the move text and next game's headers.
List<PgnGameEntry> parsePgnDatabase(String content) {
  final games = <PgnGameEntry>[];
  final lines = content.split('\n');

  Map<String, String> currentHeaders = {};
  final moveLines = <String>[];
  bool inMoveText = false;
  int gameStart = 0;

  for (int i = 0; i <= lines.length; i++) {
    final line = i < lines.length ? lines[i].trim() : '';
    final isEnd = i == lines.length;

    if (line.startsWith('[') && line.endsWith(']')) {
      // Header line
      if (inMoveText && moveLines.isNotEmpty) {
        // Save previous game
        games.add(PgnGameEntry(
          headers: Map.of(currentHeaders),
          moveText: moveLines.join(' ').trim(),
          startOffset: gameStart,
        ));
        currentHeaders = {};
        moveLines.clear();
        inMoveText = false;
        gameStart = i;
      }

      if (currentHeaders.isEmpty) gameStart = i;

      final match = RegExp(r'\[(\w+)\s+"(.*)"\]').firstMatch(line);
      if (match != null) {
        currentHeaders[match.group(1)!] = match.group(2)!;
      }
    } else if (line.isNotEmpty) {
      inMoveText = true;
      moveLines.add(line);
    } else if (isEnd || (inMoveText && line.isEmpty)) {
      // Blank line after moves or end of file — save game
      if (currentHeaders.isNotEmpty || moveLines.isNotEmpty) {
        games.add(PgnGameEntry(
          headers: Map.of(currentHeaders),
          moveText: moveLines.join(' ').trim(),
          startOffset: gameStart,
        ));
        currentHeaders = {};
        moveLines.clear();
        inMoveText = false;
      }
    }
  }

  return games;
}

/// Filter games by search criteria.
List<PgnGameEntry> filterGames(
  List<PgnGameEntry> games, {
  String? player,
  String? result,
  String? eco,
  String? event,
}) {
  return games.where((g) {
    if (player != null && player.isNotEmpty) {
      final p = player.toLowerCase();
      if (!g.white.toLowerCase().contains(p) &&
          !g.black.toLowerCase().contains(p)) return false;
    }
    if (result != null && result.isNotEmpty && g.result != result) return false;
    if (eco != null && eco.isNotEmpty && !g.eco.startsWith(eco)) return false;
    if (event != null && event.isNotEmpty &&
        !g.event.toLowerCase().contains(event.toLowerCase())) return false;
    return true;
  }).toList();
}
