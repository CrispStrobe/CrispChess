#!/usr/bin/env dart
/// CrispChess Server — REST API for chess analysis, puzzles, and opening data.
///
/// Usage:
///   dart run bin/server.dart [--port 8080] [--engine stockfish] [--depth 15]
///
/// Endpoints:
///   GET /api/analyze?fen=...&depth=15     Analyze a position
///   GET /api/puzzle?rating=1500           Get a random puzzle
///   GET /api/puzzle/daily                 Get today's daily puzzle
///   GET /api/perft?depth=5&fen=...        Run perft
///   GET /api/board?fen=...                Get ASCII board
///   GET /api/fen?moves=e2e4,e7e5          Get FEN after moves
///   GET /api/health                       Health check

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:chess/chess.dart' as chess;

late String _defaultEngine;
late int _defaultDepth;
List<Map<String, dynamic>>? _puzzles;

void main(List<String> args) async {
  final flags = _parseFlags(args);
  final port = int.tryParse(flags['port'] ?? '8080') ?? 8080;
  _defaultEngine = flags['engine'] ?? 'stockfish';
  _defaultDepth = int.tryParse(flags['depth'] ?? '15') ?? 15;

  // Pre-load puzzles
  await _loadPuzzles();

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('CrispChess API server running on http://localhost:$port');
  print('Engine: $_defaultEngine, Default depth: $_defaultDepth');
  print('');
  print('Endpoints:');
  print('  GET /api/analyze?fen=...&depth=15');
  print('  GET /api/puzzle?rating=1500');
  print('  GET /api/puzzle/daily');
  print('  GET /api/perft?depth=5&fen=...');
  print('  GET /api/board?fen=...');
  print('  GET /api/fen?moves=e2e4,e7e5');
  print('  GET /api/health');
  print('');

  await for (final request in server) {
    _handleRequest(request);
  }
}

Map<String, String> _parseFlags(List<String> args) {
  final flags = <String, String>{};
  for (int i = 0; i < args.length; i++) {
    if (args[i].startsWith('--') && i + 1 < args.length) {
      flags[args[i].substring(2)] = args[i + 1];
      i++;
    }
  }
  return flags;
}

Future<void> _loadPuzzles() async {
  try {
    final file = File('assets/puzzles.json');
    if (file.existsSync()) {
      final json = jsonDecode(file.readAsStringSync()) as List;
      _puzzles = json.cast<Map<String, dynamic>>();
      print('Loaded ${_puzzles!.length} puzzles');
    }
  } catch (e) {
    print('Warning: Could not load puzzles: $e');
  }
}

Future<void> _handleRequest(HttpRequest request) async {
  // CORS headers
  request.response.headers
    ..add('Access-Control-Allow-Origin', '*')
    ..add('Access-Control-Allow-Methods', 'GET, OPTIONS')
    ..add('Access-Control-Allow-Headers', 'Content-Type')
    ..add('Content-Type', 'application/json');

  if (request.method == 'OPTIONS') {
    request.response.statusCode = 200;
    await request.response.close();
    return;
  }

  final path = request.uri.path;
  final params = request.uri.queryParameters;

  try {
    switch (path) {
      case '/api/health':
        _json(request, {'status': 'ok', 'engine': _defaultEngine, 'version': '2.0.0'});
      case '/api/analyze':
        await _handleAnalyze(request, params);
      case '/api/puzzle':
        _handlePuzzle(request, params);
      case '/api/puzzle/daily':
        _handleDailyPuzzle(request);
      case '/api/perft':
        _handlePerft(request, params);
      case '/api/board':
        _handleBoard(request, params);
      case '/api/fen':
        _handleFen(request, params);
      default:
        _error(request, 404, 'Not found: $path');
    }
  } catch (e) {
    _error(request, 500, 'Internal error: $e');
  }
}

void _json(HttpRequest request, Object data) {
  request.response
    ..statusCode = 200
    ..write(jsonEncode(data));
  request.response.close();
  _log(request, 200);
}

void _error(HttpRequest request, int code, String message) {
  request.response
    ..statusCode = code
    ..write(jsonEncode({'error': message}));
  request.response.close();
  _log(request, code);
}

void _log(HttpRequest request, int status) {
  final ts = DateTime.now().toIso8601String().substring(11, 19);
  print('$ts ${request.method} ${request.uri.path} → $status');
}

// ─── Analyze ───

Future<void> _handleAnalyze(HttpRequest request, Map<String, String> params) async {
  final fen = params['fen'] ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final depth = int.tryParse(params['depth'] ?? '$_defaultDepth') ?? _defaultDepth;
  final engineName = params['engine'] ?? _defaultEngine;

  // Validate FEN
  final game = chess.Chess();
  if (!game.load(fen)) {
    _error(request, 400, 'Invalid FEN: $fen');
    return;
  }

  // Start engine
  Process process;
  try {
    final path = await _findEngine(engineName);
    process = await Process.start(path, []);
  } catch (e) {
    _error(request, 500, 'Engine not found: $engineName ($e)');
    return;
  }

  final completer = Completer<Map<String, dynamic>>();
  double lastEval = 0;
  int lastDepth = 0;
  String? lastPv;
  String? bestMove;

  final sub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    final t = line.trim();
    if (t.startsWith('info') && t.contains('depth') && t.contains('score')) {
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
    if (t.startsWith('bestmove') && !completer.isCompleted) {
      bestMove = t.split(' ')[1];
      completer.complete({
        'fen': fen,
        'bestMove': bestMove,
        'eval': lastEval,
        'depth': lastDepth,
        'pv': lastPv?.split(' '),
        'engine': engineName,
      });
    }
  });

  // UCI init
  process.stdin.writeln('uci');
  await Future.delayed(const Duration(seconds: 2));
  process.stdin.writeln('isready');
  await Future.delayed(const Duration(milliseconds: 500));
  process.stdin.writeln('position fen $fen');
  process.stdin.writeln('go depth $depth');

  try {
    final result = await completer.future.timeout(const Duration(seconds: 30));
    _json(request, result);
  } catch (e) {
    _error(request, 504, 'Engine timeout');
  } finally {
    process.stdin.writeln('quit');
    sub.cancel();
    process.kill();
  }
}

Future<String> _findEngine(String name) async {
  if (name.contains('/') || name.contains('\\')) return name;
  final cmd = Platform.isWindows ? 'where' : 'which';
  final result = await Process.run(cmd, [name]);
  if (result.exitCode != 0) {
    throw FileSystemException('Engine "$name" not found in PATH');
  }
  return (result.stdout as String).trim().split('\n').first;
}

// ─── Puzzle ───

void _handlePuzzle(HttpRequest request, Map<String, String> params) {
  if (_puzzles == null || _puzzles!.isEmpty) {
    _error(request, 503, 'Puzzles not loaded');
    return;
  }

  final ratingMin = int.tryParse(params['rating_min'] ?? '');
  final ratingMax = int.tryParse(params['rating_max'] ?? '');
  final rating = int.tryParse(params['rating'] ?? '');
  final theme = params['theme'];

  var pool = _puzzles!;
  if (rating != null) {
    pool = pool.where((p) => (((p['rating'] as int?) ?? 1500) - rating).abs() < 300).toList();
  }
  if (ratingMin != null) {
    pool = pool.where((p) => ((p['rating'] as int?) ?? 1500) >= ratingMin).toList();
  }
  if (ratingMax != null) {
    pool = pool.where((p) => ((p['rating'] as int?) ?? 1500) <= ratingMax).toList();
  }
  if (theme != null) {
    pool = pool.where((p) {
      final themes = p['themes'];
      if (themes is List) return themes.contains(theme);
      if (themes is String) return themes.contains(theme);
      return false;
    }).toList();
  }

  if (pool.isEmpty) {
    _error(request, 404, 'No puzzles match criteria');
    return;
  }

  final puzzle = pool[Random().nextInt(pool.length)];
  final moves = (puzzle['moves'] as String).split(' ');
  _json(request, {
    'fen': puzzle['fen'],
    'rating': puzzle['rating'],
    'themes': puzzle['themes'],
    'setupMove': moves.isNotEmpty ? moves[0] : null,
    'solution': moves.length > 1 ? moves.sublist(1) : [],
  });
}

void _handleDailyPuzzle(HttpRequest request) {
  if (_puzzles == null || _puzzles!.isEmpty) {
    _error(request, 503, 'Puzzles not loaded');
    return;
  }
  final day = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
  final puzzle = _puzzles![day % _puzzles!.length];
  final moves = (puzzle['moves'] as String).split(' ');
  _json(request, {
    'fen': puzzle['fen'],
    'rating': puzzle['rating'],
    'themes': puzzle['themes'],
    'setupMove': moves.isNotEmpty ? moves[0] : null,
    'solution': moves.length > 1 ? moves.sublist(1) : [],
    'date': DateTime.now().toIso8601String().substring(0, 10),
  });
}

// ─── Perft ───

void _handlePerft(HttpRequest request, Map<String, String> params) {
  final depth = int.tryParse(params['depth'] ?? '4') ?? 4;
  if (depth > 7) {
    _error(request, 400, 'Max depth is 7 for API perft');
    return;
  }
  final fen = params['fen'] ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final game = chess.Chess();
  if (!game.load(fen)) {
    _error(request, 400, 'Invalid FEN');
    return;
  }

  final sw = Stopwatch()..start();
  final nodes = _perftCount(game, depth);
  sw.stop();

  _json(request, {
    'fen': fen,
    'depth': depth,
    'nodes': nodes,
    'timeMs': sw.elapsedMilliseconds,
    'nps': sw.elapsedMilliseconds > 0
        ? (nodes * 1000 / sw.elapsedMilliseconds).round()
        : 0,
  });
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

// ─── Board ───

void _handleBoard(HttpRequest request, Map<String, String> params) {
  final fen = params['fen'] ?? 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  final game = chess.Chess();
  if (!game.load(fen)) {
    _error(request, 400, 'Invalid FEN');
    return;
  }

  final ranks = fen.split(' ')[0].split('/');
  final lines = <String>[];
  lines.add('  a b c d e f g h');
  for (int r = 0; r < 8; r++) {
    final buf = StringBuffer('${8 - r} ');
    int col = 0;
    for (final ch in ranks[r].split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        for (int i = 0; i < n; i++) { buf.write('. '); col++; }
      } else {
        buf.write('$ch '); col++;
      }
    }
    buf.write('${8 - r}');
    lines.add(buf.toString());
  }
  lines.add('  a b c d e f g h');
  final turn = game.turn == chess.Color.WHITE ? 'White' : 'Black';

  _json(request, {
    'fen': fen,
    'turn': turn,
    'board': lines.join('\n'),
    'legalMoves': game.moves(),
    'isCheck': game.in_check,
    'isCheckmate': game.in_checkmate,
    'isGameOver': game.game_over,
  });
}

// ─── FEN from moves ───

void _handleFen(HttpRequest request, Map<String, String> params) {
  final movesStr = params['moves'] ?? '';
  final startFen = params['fen'];
  final game = chess.Chess();
  if (startFen != null) game.load(startFen);

  final moves = movesStr.split(',').where((m) => m.isNotEmpty).toList();
  final applied = <String>[];

  for (final m in moves) {
    if (m.length >= 4) {
      final from = m.substring(0, 2);
      final to = m.substring(2, 4);
      final promo = m.length > 4 ? m[4] : null;
      final move = <String, String>{'from': from, 'to': to};
      if (promo != null) move['promotion'] = promo;
      if (game.move(move)) {
        applied.add(m);
      } else {
        _error(request, 400, 'Illegal move: $m after ${applied.join(",")}');
        return;
      }
    }
  }

  _json(request, {
    'fen': game.fen,
    'moves': applied,
    'turn': game.turn == chess.Color.WHITE ? 'White' : 'Black',
    'isCheck': game.in_check,
    'isGameOver': game.game_over,
  });
}
