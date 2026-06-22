#!/usr/bin/env dart
/// CrispChess CLI — analyze positions, solve puzzles, run engine matches.
///
/// Usage:
///   dart run bin/crispchess.dart analyze --fen "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1" --depth 15
///   dart run bin/crispchess.dart puzzle --rating 1500
///   dart run bin/crispchess.dart play --engine stockfish --depth 10
///   dart run bin/crispchess.dart match --white frozenight --black stockfish --games 10 --depth 12
///   dart run bin/crispchess.dart perft --depth 5
///   dart run bin/crispchess.dart fen "e2e4 e7e5 g1f3"

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:chess/chess.dart' as chess;

// ANSI colors
const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _dim = '\x1B[2m';
const _red = '\x1B[31m';
const _green = '\x1B[32m';
const _yellow = '\x1B[33m';
const _blue = '\x1B[34m';
const _cyan = '\x1B[36m';
const _white = '\x1B[37m';
const _bgWhite = '\x1B[47m';
const _bgGreen = '\x1B[42m';

void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(0);
  }

  final command = args[0];
  final flags = _parseFlags(args.sublist(1));

  switch (command) {
    case 'analyze':
      await _analyze(flags);
    case 'play':
      await _play(flags);
    case 'match':
      await _match(flags);
    case 'perft':
      _perft(flags);
    case 'fen':
      _fenFromMoves(args.sublist(1));
    case 'puzzle':
      await _puzzle(flags);
    case 'board':
      _showBoard(flags);
    case 'help':
    case '--help':
    case '-h':
      _printUsage();
    case 'version':
      print('CrispChess CLI v2.0.0');
    default:
      print('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      final key = args[i].substring(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        flags[key] = args[i + 1];
        i++;
      } else {
        flags[key] = 'true';
      }
    } else if (!args[i].startsWith('-')) {
      flags['_positional'] = (flags['_positional'] ?? '') +
          (flags['_positional'] != null ? ' ' : '') + args[i];
    }
  }
  return flags;
}

void _printUsage() {
  print('''
${_bold}CrispChess CLI$_reset — chess analysis and engine tools

${_bold}COMMANDS$_reset
  ${_cyan}analyze$_reset     Analyze a position with a UCI engine
  ${_cyan}play$_reset        Play an interactive game against an engine
  ${_cyan}match$_reset       Run an engine vs engine match
  ${_cyan}perft$_reset       Run perft (performance test) on a position
  ${_cyan}fen$_reset         Show FEN after a sequence of UCI moves
  ${_cyan}board$_reset       Display a position as ASCII board
  ${_cyan}puzzle$_reset      Load and display a random puzzle
  ${_cyan}version$_reset     Show version

${_bold}EXAMPLES$_reset
  dart run bin/crispchess.dart analyze --fen "starting" --depth 20 --engine stockfish
  dart run bin/crispchess.dart play --engine stockfish --depth 12
  dart run bin/crispchess.dart match --white stockfish --black frozenight --games 4 --depth 15
  dart run bin/crispchess.dart perft --depth 6
  dart run bin/crispchess.dart fen e2e4 e7e5 g1f3 b8c6
  dart run bin/crispchess.dart board --fen "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
  dart run bin/crispchess.dart puzzle

${_bold}ENGINE OPTIONS$_reset
  --engine <name>    Engine binary name or path (default: stockfish)
  --depth <n>        Search depth (default: 15)
  --fen <fen>        Position FEN ("starting" for initial position)
  --hash <mb>        Hash table size in MB
  --threads <n>      Number of threads
''');
}

// ─── Board Display ───

String _pieceChar(String p) {
  return switch (p) {
    'K' => '♔', 'Q' => '♕', 'R' => '♖', 'B' => '♗', 'N' => '♘', 'P' => '♙',
    'k' => '♚', 'q' => '♛', 'r' => '♜', 'b' => '♝', 'n' => '♞', 'p' => '♟',
    _ => ' ',
  };
}

void _printBoard(chess.Chess game) {
  final fen = game.fen;
  final ranks = fen.split(' ')[0].split('/');
  print('');
  print('  ${_dim}a b c d e f g h$_reset');
  for (int r = 0; r < 8; r++) {
    final rank = ranks[r];
    final buf = StringBuffer('${_dim}${8 - r}$_reset ');
    int col = 0;
    for (final ch in rank.split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        for (int i = 0; i < n; i++) {
          final isLight = (r + col) % 2 == 0;
          buf.write(isLight ? '${_dim}·$_reset ' : '${_dim}·$_reset ');
          col++;
        }
      } else {
        final isWhite = ch == ch.toUpperCase();
        final color = isWhite ? _white : _red;
        buf.write('$color${_pieceChar(ch)}$_reset ');
        col++;
      }
    }
    buf.write('${_dim}${8 - r}$_reset');
    print(buf.toString());
  }
  print('  ${_dim}a b c d e f g h$_reset');
  final turn = game.turn == chess.Color.WHITE ? 'White' : 'Black';
  print('${_dim}$turn to move$_reset');
  print('');
}

void _showBoard(Map<String, String> flags) {
  final fen = flags['fen'] ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final game = chess.Chess();
  if (fen != 'starting') game.load(fen);
  _printBoard(game);
}

// ─── FEN from moves ───

void _fenFromMoves(List<String> args) {
  final game = chess.Chess();
  final moves = args.where((a) => !a.startsWith('-')).toList();
  for (final m in moves) {
    if (m.length >= 4) {
      final from = m.substring(0, 2);
      final to = m.substring(2, 4);
      final promo = m.length > 4 ? m[4] : null;
      final move = <String, String>{'from': from, 'to': to};
      if (promo != null) move['promotion'] = promo;
      if (!game.move(move)) {
        print('${_red}Illegal move: $m$_reset');
        _printBoard(game);
        return;
      }
    }
  }
  _printBoard(game);
  print('FEN: ${game.fen}');
}

// ─── Perft ───

void _perft(Map<String, String> flags) {
  final depth = int.tryParse(flags['depth'] ?? '5') ?? 5;
  final fen = flags['fen'];
  final game = chess.Chess();
  if (fen != null && fen != 'starting') game.load(fen);

  print('${_bold}Perft$_reset depth=$depth');
  print('FEN: ${game.fen}');
  print('');

  final sw = Stopwatch()..start();
  final nodes = _perftCount(game, depth);
  sw.stop();

  print('Nodes: ${_green}$nodes$_reset');
  print('Time:  ${sw.elapsedMilliseconds}ms');
  if (sw.elapsedMilliseconds > 0) {
    final nps = (nodes * 1000 / sw.elapsedMilliseconds).round();
    print('NPS:   $nps');
  }
}

int _perftCount(chess.Chess game, int depth) {
  if (depth == 0) return 1;
  final moves = game.generate_moves();
  if (depth == 1) return moves.length;
  int nodes = 0;
  for (final move in moves) {
    game.make_move(move);
    nodes += _perftCount(game, depth - 1);
    game.undo_move();
  }
  return nodes;
}

// ─── UCI Engine Helper ───

class _UciEngine {
  final Process process;
  final StreamController<String> _lines = StreamController.broadcast();
  late final StreamSubscription _sub;

  _UciEngine(this.process) {
    _sub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _lines.add(line));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => stderr.writeln('[engine stderr] $line'));
  }

  void send(String cmd) => process.stdin.writeln(cmd);

  Future<void> waitFor(String prefix, {Duration timeout = const Duration(seconds: 15)}) async {
    await _lines.stream
        .firstWhere((l) => l.trim().startsWith(prefix))
        .timeout(timeout, onTimeout: () => '');
  }

  Stream<String> get lines => _lines.stream;

  Future<void> init({int? hash, int? threads}) async {
    send('uci');
    await waitFor('uciok');
    if (hash != null) send('setoption name Hash value $hash');
    if (threads != null) send('setoption name Threads value $threads');
    send('isready');
    await waitFor('readyok');
  }

  Future<({String bestMove, double eval, int depth, String? pv})> go(
      String position, {int depth = 15}) async {
    send(position);
    send('go depth $depth');

    double lastEval = 0;
    int lastDepth = 0;
    String? lastPv;

    await for (final line in _lines.stream) {
      final t = line.trim();
      if (t.startsWith('info') && t.contains('depth')) {
        final cp = RegExp(r'score cp (-?\d+)').firstMatch(t);
        final mate = RegExp(r'score mate (-?\d+)').firstMatch(t);
        final d = RegExp(r'depth (\d+)').firstMatch(t);
        final pv = RegExp(r' pv (.+)').firstMatch(t);
        if (d != null) lastDepth = int.parse(d.group(1)!);
        if (cp != null) lastEval = int.parse(cp.group(1)!) / 100.0;
        if (mate != null) {
          final m = int.parse(mate.group(1)!);
          lastEval = m > 0 ? 100.0 : -100.0;
        }
        if (pv != null) lastPv = pv.group(1);
      }
      if (t.startsWith('bestmove')) {
        final parts = t.split(' ');
        return (bestMove: parts[1], eval: lastEval, depth: lastDepth, pv: lastPv);
      }
    }
    throw StateError('Engine stream ended without bestmove');
  }

  void dispose() {
    send('quit');
    _sub.cancel();
    process.kill();
  }
}

Future<_UciEngine> _startEngine(String name, {int? hash, int? threads}) async {
  // Find engine binary
  String path;
  if (name.contains('/') || name.contains('\\')) {
    path = name; // Absolute or relative path
  } else {
    // Search PATH
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = await Process.run(cmd, [name]);
    if (result.exitCode != 0) {
      throw FileSystemException('Engine "$name" not found in PATH. '
          'Install it or provide a full path with --engine /path/to/$name');
    }
    path = (result.stdout as String).trim().split('\n').first;
  }

  final process = await Process.start(path, []);
  final engine = _UciEngine(process);
  await engine.init(hash: hash, threads: threads);
  return engine;
}

// ─── Analyze ───

Future<void> _analyze(Map<String, String> flags) async {
  final fenInput = flags['fen'] ?? 'starting';
  final depth = int.tryParse(flags['depth'] ?? '15') ?? 15;
  final engineName = flags['engine'] ?? 'stockfish';
  final hash = int.tryParse(flags['hash'] ?? '');
  final threads = int.tryParse(flags['threads'] ?? '');

  final game = chess.Chess();
  if (fenInput != 'starting') game.load(fenInput);

  _printBoard(game);
  print('${_bold}Analyzing$_reset with ${_cyan}$engineName$_reset depth=$depth');
  print('');

  final engine = await _startEngine(engineName, hash: hash, threads: threads);
  try {
    final position = 'position fen ${game.fen}';

    // Stream info lines during search
    final infoPrinter = engine.lines.listen((line) {
      final t = line.trim();
      if (t.startsWith('info') && t.contains('depth') && t.contains('score')) {
        final d = RegExp(r'depth (\d+)').firstMatch(t);
        final cp = RegExp(r'score cp (-?\d+)').firstMatch(t);
        final mate = RegExp(r'score mate (-?\d+)').firstMatch(t);
        final pv = RegExp(r' pv (.+)').firstMatch(t);
        if (d != null) {
          final depthStr = d.group(1)!.padLeft(2);
          String evalStr;
          if (mate != null) {
            evalStr = '#${mate.group(1)}';
          } else if (cp != null) {
            final e = int.parse(cp.group(1)!) / 100.0;
            evalStr = e >= 0 ? '+${e.toStringAsFixed(2)}' : e.toStringAsFixed(2);
          } else {
            evalStr = '?';
          }
          final pvStr = pv?.group(1)?.split(' ').take(8).join(' ') ?? '';
          stdout.write('\r  ${_dim}d=$depthStr$_reset  ${_bold}$evalStr$_reset  $pvStr          ');
        }
      }
    });

    final result = await engine.go(position, depth: depth);
    await infoPrinter.cancel();

    print('');
    print('');
    final evalStr = result.eval >= 0
        ? '${_green}+${result.eval.toStringAsFixed(2)}$_reset'
        : '${_red}${result.eval.toStringAsFixed(2)}$_reset';
    print('${_bold}Best move:$_reset ${_cyan}${result.bestMove}$_reset');
    print('${_bold}Eval:$_reset     $evalStr');
    print('${_bold}Depth:$_reset    ${result.depth}');
    if (result.pv != null) {
      print('${_bold}PV:$_reset       ${result.pv!.split(' ').take(10).join(' ')}');
    }
  } finally {
    engine.dispose();
  }
}

// ─── Play ───

Future<void> _play(Map<String, String> flags) async {
  final engineName = flags['engine'] ?? 'stockfish';
  final depth = int.tryParse(flags['depth'] ?? '10') ?? 10;
  final hash = int.tryParse(flags['hash'] ?? '');
  final threads = int.tryParse(flags['threads'] ?? '');
  final playerColor = (flags['color'] ?? 'white').toLowerCase();

  print('${_bold}CrispChess$_reset — Playing against ${_cyan}$engineName$_reset (depth=$depth)');
  print('Type moves in UCI format (e.g. e2e4). Type "quit" to exit.');
  print('');

  final game = chess.Chess();
  final engine = await _startEngine(engineName, hash: hash, threads: threads);

  try {
    if (playerColor == 'black') {
      // Engine plays first
      _printBoard(game);
      print('${_dim}Engine is thinking...$_reset');
      final result = await engine.go('position fen ${game.fen}', depth: depth);
      _applyUci(game, result.bestMove);
      print('Engine: ${_cyan}${result.bestMove}$_reset (${result.eval >= 0 ? '+' : ''}${result.eval.toStringAsFixed(1)})');
    }

    while (!game.game_over) {
      _printBoard(game);
      final turn = game.turn == chess.Color.WHITE ? 'White' : 'Black';
      stdout.write('$_bold$turn> $_reset');
      final input = stdin.readLineSync()?.trim();
      if (input == null || input == 'quit' || input == 'exit') break;
      if (input == 'fen') { print(game.fen); continue; }
      if (input == 'moves') { print(game.moves().map((m) => m['san']).join(' ')); continue; }
      if (input.isEmpty) continue;

      if (!_applyUci(game, input)) {
        print('${_red}Illegal move: $input$_reset');
        print('Legal moves: ${game.moves().map((m) => m['san']).join(', ')}');
        continue;
      }

      if (game.game_over) break;

      // Engine response
      print('${_dim}Engine is thinking...$_reset');
      final result = await engine.go('position fen ${game.fen}', depth: depth);
      if (!_applyUci(game, result.bestMove)) break;
      print('Engine: ${_cyan}${result.bestMove}$_reset (${result.eval >= 0 ? '+' : ''}${result.eval.toStringAsFixed(1)})');
    }

    _printBoard(game);
    if (game.in_checkmate) {
      final winner = game.turn == chess.Color.WHITE ? 'Black' : 'White';
      print('${_bold}${_green}Checkmate! $winner wins.$_reset');
    } else if (game.in_stalemate) {
      print('${_yellow}Stalemate — draw.$_reset');
    } else if (game.in_draw) {
      print('${_yellow}Draw.$_reset');
    }
  } finally {
    engine.dispose();
  }
}

bool _applyUci(chess.Chess game, String uci) {
  if (uci.length < 4) return false;
  final from = uci.substring(0, 2);
  final to = uci.substring(2, 4);
  final promo = uci.length > 4 ? uci[4] : null;
  final move = <String, String>{'from': from, 'to': to};
  if (promo != null) move['promotion'] = promo;
  return game.move(move);
}

// ─── Engine Match ───

Future<void> _match(Map<String, String> flags) async {
  final whiteName = flags['white'] ?? 'stockfish';
  final blackName = flags['black'] ?? flags['engine'] ?? 'stockfish';
  final games = int.tryParse(flags['games'] ?? '2') ?? 2;
  final depth = int.tryParse(flags['depth'] ?? '12') ?? 12;
  final hash = int.tryParse(flags['hash'] ?? '');
  final threads = int.tryParse(flags['threads'] ?? '');

  print('${_bold}Engine Match$_reset: ${_cyan}$whiteName$_reset vs ${_cyan}$blackName$_reset');
  print('Games: $games, Depth: $depth');
  print('');

  int whiteWins = 0, blackWins = 0, draws = 0;

  for (int g = 1; g <= games; g++) {
    // Alternate colors
    final isSwapped = g % 2 == 0;
    final wName = isSwapped ? blackName : whiteName;
    final bName = isSwapped ? whiteName : blackName;

    stdout.write('Game $g/$games ($wName vs $bName): ');
    final game = chess.Chess();
    final wEngine = await _startEngine(wName, hash: hash, threads: threads);
    final bEngine = await _startEngine(bName, hash: hash, threads: threads);

    try {
      int moveCount = 0;
      while (!game.game_over && moveCount < 300) {
        final engine = game.turn == chess.Color.WHITE ? wEngine : bEngine;
        final result = await engine.go('position fen ${game.fen}', depth: depth);
        if (!_applyUci(game, result.bestMove)) break;
        moveCount++;
        if (moveCount % 20 == 0) stdout.write('.');
      }

      String resultStr;
      if (game.in_checkmate) {
        final winner = game.turn == chess.Color.WHITE ? bName : wName;
        if ((winner == whiteName && !isSwapped) || (winner == blackName && isSwapped)) {
          whiteWins++;
        } else {
          blackWins++;
        }
        resultStr = '${_green}$winner wins$_reset (${moveCount ~/ 2} moves)';
      } else {
        draws++;
        resultStr = '${_yellow}Draw$_reset (${game.in_stalemate ? 'stalemate' : game.in_threefold_repetition ? '3-fold' : game.insufficient_material ? 'material' : '50-move'})';
      }
      print(' $resultStr');
    } finally {
      wEngine.dispose();
      bEngine.dispose();
    }
  }

  print('');
  print('${_bold}Results:$_reset $whiteName ${_green}$whiteWins$_reset - ${_yellow}$draws$_reset - ${_green}$blackWins$_reset $blackName');
  final whiteScore = whiteWins + draws * 0.5;
  final blackScore = blackWins + draws * 0.5;
  print('Score: $whiteScore - $blackScore');
}

// ─── Puzzle ───

Future<void> _puzzle(Map<String, String> flags) async {
  // Load puzzles from assets
  final puzzlePath = flags['file'] ?? 'assets/puzzles.json';
  final file = File(puzzlePath);
  if (!file.existsSync()) {
    print('${_red}Puzzle file not found: $puzzlePath$_reset');
    print('Run from the CrispChess project root, or specify --file path/to/puzzles.json');
    return;
  }

  final json = jsonDecode(file.readAsStringSync()) as List;
  final ratingFilter = int.tryParse(flags['rating'] ?? '');

  var puzzles = json.cast<Map<String, dynamic>>();
  if (ratingFilter != null) {
    puzzles = puzzles.where((p) => ((p['rating'] as int?) ?? 1500) >= ratingFilter - 200 &&
        ((p['rating'] as int?) ?? 1500) <= ratingFilter + 200).toList();
  }

  if (puzzles.isEmpty) {
    print('No puzzles found matching criteria.');
    return;
  }

  // Pick random puzzle
  final idx = DateTime.now().millisecondsSinceEpoch % puzzles.length;
  final p = puzzles[idx];
  final fen = p['fen'] as String;
  final moves = (p['moves'] as String).split(' ');
  final rating = p['rating'] as int? ?? 1500;
  final themes = (p['themes'] as List?)?.cast<String>().join(', ') ??
      (p['themes'] as String?) ?? '';

  final game = chess.Chess.fromFEN(fen);

  // Apply setup move
  if (moves.isNotEmpty) _applyUci(game, moves[0]);

  print('${_bold}Puzzle$_reset (rating: $rating)');
  if (themes.isNotEmpty) print('${_dim}Themes: $themes$_reset');
  _printBoard(game);

  final solutionMoves = moves.length > 1 ? moves.sublist(1) : <String>[];
  print('${_dim}Find the best move for ${game.turn == chess.Color.WHITE ? "White" : "Black"}.$_reset');
  print('Solution: ${_dim}(type "show" to reveal)$_reset');
  print('');

  // Interactive solving
  int step = 0;
  while (step < solutionMoves.length) {
    stdout.write('${_bold}Your move> $_reset');
    final input = stdin.readLineSync()?.trim();
    if (input == null || input == 'quit') return;
    if (input == 'show') {
      print('Solution: ${_yellow}${solutionMoves.join(' ')}$_reset');
      return;
    }
    if (input == 'hint') {
      print('Hint: ${_yellow}${solutionMoves[step].substring(0, 2)}...$_reset');
      continue;
    }

    if (input == solutionMoves[step] ||
        (input.length >= 4 && solutionMoves[step].startsWith(input))) {
      _applyUci(game, solutionMoves[step]);
      print('${_green}Correct!$_reset');
      step++;

      // Apply opponent response if there is one
      if (step < solutionMoves.length) {
        _applyUci(game, solutionMoves[step]);
        step++;
        if (step < solutionMoves.length) {
          _printBoard(game);
          print('${_dim}Continue...$_reset');
        }
      }
    } else {
      print('${_red}Wrong.$_reset Try again (or type "show").');
    }
  }

  if (step >= solutionMoves.length) {
    _printBoard(game);
    print('${_green}${_bold}Puzzle solved!$_reset');
  }
}
