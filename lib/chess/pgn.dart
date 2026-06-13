/// PGN (Portable Game Notation) export and import.
///
/// Uses the chess package's built-in PGN support for move parsing,
/// with custom header management for game metadata.

import 'package:chess/chess.dart' as chess;

/// PGN header tags.
class PgnHeaders {
  final String event;
  final String site;
  final String date;
  final String round;
  final String white;
  final String black;
  final String result;
  final Map<String, String> extra;

  const PgnHeaders({
    this.event = 'CrispChess Game',
    this.site = 'CrispChess App',
    this.date = '????.??.??',
    this.round = '-',
    this.white = 'Human',
    this.black = 'Engine',
    this.result = '*',
    this.extra = const {},
  });
}

/// Export the current game state to PGN format.
String exportPgn({
  required chess.Chess game,
  PgnHeaders headers = const PgnHeaders(),
}) {
  final sb = StringBuffer();

  // Seven Tag Roster (STR) — required by PGN spec
  sb.writeln('[Event "${_escape(headers.event)}"]');
  sb.writeln('[Site "${_escape(headers.site)}"]');
  sb.writeln('[Date "${headers.date}"]');
  sb.writeln('[Round "${headers.round}"]');
  sb.writeln('[White "${_escape(headers.white)}"]');
  sb.writeln('[Black "${_escape(headers.black)}"]');
  sb.writeln('[Result "${headers.result}"]');

  // Extra headers
  for (final entry in headers.extra.entries) {
    sb.writeln('[${entry.key} "${_escape(entry.value)}"]');
  }

  sb.writeln();

  // Move text — use the chess package's pgn() which formats with move numbers
  final pgn = game.pgn({'max_width': 80, 'newline_char': '\n'});
  sb.write(pgn);

  // Append result if not already at end
  if (!pgn.endsWith(headers.result)) {
    sb.write(' ${headers.result}');
  }

  sb.writeln();
  return sb.toString();
}

/// Parse PGN text and return a Chess instance with the game loaded.
/// Returns null if parsing fails.
chess.Chess? importPgn(String pgn) {
  try {
    final game = chess.Chess();

    // Extract move text (everything after headers)
    final lines = pgn.split('\n');
    final moveLines = <String>[];
    bool pastHeaders = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) continue;
      if (trimmed.isEmpty && !pastHeaders) {
        pastHeaders = true;
        continue;
      }
      if (pastHeaders || !trimmed.startsWith('[')) {
        pastHeaders = true;
        moveLines.add(trimmed);
      }
    }

    final moveText = moveLines.join(' ').trim();
    if (moveText.isEmpty) return game; // Empty game is valid

    // Try loading via the chess package
    if (game.load_pgn(moveText)) {
      return game;
    }

    return null;
  } catch (e) {
    return null;
  }
}

/// Extract PGN headers from text.
Map<String, String> parseHeaders(String pgn) {
  final headers = <String, String>{};
  final headerRegex = RegExp(r'\[(\w+)\s+"(.*)"\]');

  for (final line in pgn.split('\n')) {
    final match = headerRegex.firstMatch(line.trim());
    if (match != null) {
      headers[match.group(1)!] = match.group(2)!;
    }
  }

  return headers;
}

/// Get the result string for a game.
String gameResult(chess.Chess game) {
  if (!game.game_over) return '*';
  if (game.in_checkmate) {
    return game.turn == chess.Color.WHITE ? '0-1' : '1-0';
  }
  return '1/2-1/2'; // draw (stalemate, insufficient material, etc.)
}

String _escape(String s) => s.replaceAll('"', '\\"');
