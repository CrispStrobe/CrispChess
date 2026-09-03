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

/// The standard initial position, in the FEN form `package:chess` produces.
const String standardStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// Export the game as it currently stands on the board, from the game tree.
///
/// The tree is the app's record of the game: it survives a takeback (which
/// reloads `chess.Chess` from a FEN and so clears *its* history), it knows the
/// real starting position, and it holds the SAN, comments and variations. An
/// export driven by `chess.Chess` instead produced an empty move list after any
/// undo.
///
/// The moves written are the ones that led to the position on the board — the
/// current path — so a takeback removes the move from the export too. Sidelines
/// branching off that path are written as RAV variations.
String exportPgnFromTree({
  required GameTree tree,
  PgnHeaders headers = const PgnHeaders(),
}) {
  final sb = StringBuffer();
  final startFen = tree.root.fen;

  sb.writeln('[Event "${_escape(headers.event)}"]');
  sb.writeln('[Site "${_escape(headers.site)}"]');
  sb.writeln('[Date "${headers.date}"]');
  sb.writeln('[Round "${headers.round}"]');
  sb.writeln('[White "${_escape(headers.white)}"]');
  sb.writeln('[Black "${_escape(headers.black)}"]');
  sb.writeln('[Result "${headers.result}"]');
  // A game that did not start from the initial position is unreadable without
  // these two tags — Chess960, a puzzle, or a position loaded from FEN.
  if (startFen != standardStartFen) {
    sb.writeln('[SetUp "1"]');
    sb.writeln('[FEN "$startFen"]');
  }
  for (final entry in headers.extra.entries) {
    sb.writeln('[${entry.key} "${_escape(entry.value)}"]');
  }
  sb.writeln();

  var (moveNumber, whiteToMove) = _startCounters(startFen);
  var needsNumber = true; // the very first move always carries its number

  for (final node in tree.currentPath) {
    _writeMove(sb, node, moveNumber, whiteToMove, needsNumber);

    // Sidelines at this point: the siblings this move was chosen over.
    final siblings = node.parent?.children ?? const <GameTreeNode>[];
    var wroteVariation = false;
    for (final sibling in siblings) {
      if (identical(sibling, node)) continue;
      sb.write('(');
      var vNumber = moveNumber;
      var vWhite = whiteToMove;
      var vNeedsNumber = true;
      GameTreeNode? v = sibling;
      while (v != null) {
        _writeMove(sb, v, vNumber, vWhite, vNeedsNumber);
        vNeedsNumber = false;
        if (!vWhite) vNumber++;
        vWhite = !vWhite;
        v = v.children.isEmpty ? null : v.children.first;
      }
      sb.write(') ');
      wroteVariation = true;
    }

    // After a variation, black's move needs its "12..." prefix again.
    needsNumber = wroteVariation;
    if (!whiteToMove) moveNumber++;
    whiteToMove = !whiteToMove;
  }

  sb.write(headers.result);
  sb.writeln();
  return sb.toString();
}

void _writeMove(StringBuffer sb, GameTreeNode node, int moveNumber,
    bool whiteToMove, bool needsNumber) {
  if (whiteToMove) {
    sb.write('$moveNumber. ');
  } else if (needsNumber) {
    sb.write('$moveNumber... ');
  }
  sb.write(node.san ?? node.move ?? '?');
  if (node.nag != null) sb.write(' \$${node.nag}');
  if (node.comment != null && node.comment!.isNotEmpty) {
    sb.write(' {${node.comment}}');
  }
  sb.write(' ');
}

/// Move number and side to move at the start of [fen].
(int, bool) _startCounters(String fen) {
  final fields = fen.split(' ');
  final whiteToMove = fields.length < 2 || fields[1] == 'w';
  final moveNumber =
      fields.length >= 6 ? (int.tryParse(fields[5]) ?? 1) : 1;
  return (moveNumber, whiteToMove);
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
