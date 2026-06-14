/// PGN (Portable Game Notation) export and import.
///
/// Uses the chess package's built-in PGN support for move parsing,
/// with custom header management for game metadata.
/// Supports RAV (Recursive Annotation Variation) for branching game trees.

import 'package:chess/chess.dart' as chess;
import 'game_tree.dart';

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

/// Export a game tree to PGN with RAV (Recursive Annotation Variation).
///
/// Variations are encoded in parentheses per the PGN spec:
/// `1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 Nc6`
String exportPgnWithVariations({
  required GameTree tree,
  PgnHeaders headers = const PgnHeaders(),
}) {
  final sb = StringBuffer();

  // Headers
  sb.writeln('[Event "${_escape(headers.event)}"]');
  sb.writeln('[Site "${_escape(headers.site)}"]');
  sb.writeln('[Date "${headers.date}"]');
  sb.writeln('[Round "${headers.round}"]');
  sb.writeln('[White "${_escape(headers.white)}"]');
  sb.writeln('[Black "${_escape(headers.black)}"]');
  sb.writeln('[Result "${headers.result}"]');
  for (final entry in headers.extra.entries) {
    sb.writeln('[${entry.key} "${_escape(entry.value)}"]');
  }
  sb.writeln();

  // Move text with variations
  _writeNode(sb, tree.root, true, 1);
  sb.write(' ${headers.result}');
  sb.writeln();

  return sb.toString();
}

void _writeNode(StringBuffer sb, GameTreeNode node, bool isWhite, int moveNum) {
  if (node.children.isEmpty) return;

  final mainChild = node.children.first;

  // Write main line move
  if (isWhite) {
    sb.write('$moveNum. ');
  } else if (node.children.length > 1 || node == node) {
    // Only write black move number after a variation
  }
  sb.write(mainChild.san ?? mainChild.move ?? '?');

  // Write comment if present
  if (mainChild.comment != null && mainChild.comment!.isNotEmpty) {
    sb.write(' {${mainChild.comment}}');
  }

  // Write NAG
  if (mainChild.nag != null) {
    sb.write(' \$${mainChild.nag}');
  }

  sb.write(' ');

  // Write variations (children 1+)
  for (int i = 1; i < node.children.length; i++) {
    final variation = node.children[i];
    sb.write('(');
    if (isWhite) {
      sb.write('$moveNum. ');
    } else {
      sb.write('$moveNum... ');
    }
    sb.write(variation.san ?? variation.move ?? '?');
    if (variation.comment != null) sb.write(' {${variation.comment}}');
    sb.write(' ');
    // Recurse into variation
    _writeNode(sb, variation, !isWhite,
        isWhite ? moveNum : moveNum + 1);
    sb.write(') ');
  }

  // Recurse into main line
  _writeNode(sb, mainChild, !isWhite,
      isWhite ? moveNum : moveNum + 1);
}

/// Import PGN with RAV variations into a game tree.
///
/// Parses parenthesized variations and builds a full game tree.
/// Returns null if parsing fails.
GameTree? importPgnWithVariations(String pgn) {
  try {
    // Extract move text
    final lines = pgn.split('\n');
    final moveLines = <String>[];
    bool pastHeaders = false;
    String? startFen;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[')) {
        // Check for FEN header
        final fenMatch = RegExp(r'\[FEN\s+"(.+)"\]').firstMatch(trimmed);
        if (fenMatch != null) startFen = fenMatch.group(1);
        continue;
      }
      if (trimmed.isEmpty && !pastHeaders) { pastHeaders = true; continue; }
      if (pastHeaders || !trimmed.startsWith('[')) {
        pastHeaders = true;
        moveLines.add(trimmed);
      }
    }

    final moveText = moveLines.join(' ').trim();
    if (moveText.isEmpty) return null;

    // Tokenize: split into move numbers, moves, comments, variations
    final tokens = _tokenize(moveText);
    if (tokens.isEmpty) return null;

    final fen = startFen ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    final tree = GameTree(startFen: fen);
    final game = chess.Chess();
    game.load(fen);

    _parseTokens(tokens, 0, tree.root, game);

    return tree;
  } catch (e) {
    return null;
  }
}

/// Tokenize PGN move text into structured tokens.
List<String> _tokenize(String text) {
  final tokens = <String>[];
  int i = 0;

  while (i < text.length) {
    final c = text[i];

    // Skip whitespace
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') { i++; continue; }

    // Comment
    if (c == '{') {
      final end = text.indexOf('}', i);
      if (end < 0) break;
      tokens.add(text.substring(i, end + 1));
      i = end + 1;
      continue;
    }

    // Variation start/end
    if (c == '(' || c == ')') {
      tokens.add(c);
      i++;
      continue;
    }

    // NAG ($1, $2, etc.)
    if (c == '\$') {
      int j = i + 1;
      while (j < text.length && text[j].codeUnitAt(0) >= 48 && text[j].codeUnitAt(0) <= 57) j++;
      tokens.add(text.substring(i, j));
      i = j;
      continue;
    }

    // Result
    if (text.startsWith('1-0', i) || text.startsWith('0-1', i) || text.startsWith('1/2-1/2', i) || c == '*') {
      if (text.startsWith('1/2-1/2', i)) { tokens.add('1/2-1/2'); i += 7; }
      else if (text.startsWith('1-0', i)) { tokens.add('1-0'); i += 3; }
      else if (text.startsWith('0-1', i)) { tokens.add('0-1'); i += 3; }
      else { tokens.add('*'); i++; }
      continue;
    }

    // Move number (skip: "1." or "1...")
    if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
      int j = i;
      while (j < text.length && text[j].codeUnitAt(0) >= 48 && text[j].codeUnitAt(0) <= 57) j++;
      while (j < text.length && text[j] == '.') j++;
      while (j < text.length && text[j] == ' ') j++;
      i = j;
      continue;
    }

    // SAN move (starts with a-h, N, B, R, Q, K, O)
    if ('abcdefghNBRQKO'.contains(c)) {
      int j = i + 1;
      while (j < text.length && !' \n\t(){}*'.contains(text[j])) j++;
      tokens.add(text.substring(i, j));
      i = j;
      continue;
    }

    i++; // skip unknown
  }

  return tokens;
}

/// Recursively parse tokens into the game tree.
int _parseTokens(List<String> tokens, int pos, GameTreeNode parent, chess.Chess game) {
  var current = parent;

  while (pos < tokens.length) {
    final token = tokens[pos];

    if (token == ')') return pos + 1; // End of variation

    if (token == '(') {
      // Start variation — fork from current's parent
      if (current.parent != null) {
        final branchGame = chess.Chess();
        branchGame.load(current.parent!.fen);
        pos = _parseTokens(tokens, pos + 1, current.parent!, branchGame);
      } else {
        pos++;
      }
      continue;
    }

    // Skip results
    if (token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*') {
      pos++;
      continue;
    }

    // Comment
    if (token.startsWith('{') && token.endsWith('}')) {
      current.comment = token.substring(1, token.length - 1).trim();
      pos++;
      continue;
    }

    // NAG
    if (token.startsWith('\$')) {
      current.nag = int.tryParse(token.substring(1));
      pos++;
      continue;
    }

    // SAN move — try to play it
    try {
      final ok = game.move(token);
      if (ok != false) {
        final uci = game.history.last;
        final uciStr = '${uci.move.fromAlgebraic}${uci.move.toAlgebraic}${uci.move.promotion?.name ?? ''}';
        current = current.addChild(
          move: uciStr,
          san: token,
          fen: game.fen,
        );
      }
    } catch (_) {
      // Skip unparseable moves
    }
    pos++;
  }

  return pos;
}
