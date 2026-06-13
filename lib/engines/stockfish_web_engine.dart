import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'chess_engine.dart';

/// Stockfish engine running as a Web Worker via stockfish.js (WASM/JS).
///
/// Uses the niklasf/stockfish.js compiled Stockfish which communicates
/// via postMessage (UCI protocol over Web Worker messages).
/// GPL-3.0 licensed.
class StockfishEngine implements ChessEngine {
  web.Worker? _worker;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  final _evalController = StreamController<EvalInfo>.broadcast();

  // Pre-compiled regex for parsing UCI output
  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r'pv (\S+)');

  @override
  String get name => 'Stockfish';
  @override
  String get version => '16 (WASM)';
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => 3200;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable => kIsWeb;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;

    try {
      _worker = web.Worker('assets/stockfish.js'.toJS);

      final readyCompleter = Completer<void>();

      _worker!.onmessage = ((web.MessageEvent event) {
        final line = (event.data as JSString).toDart;
        _handleOutput(line);
        if (line.contains('uciok') && !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }).toJS;

      _send('uci');

      await readyCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[StockfishWeb] UCI handshake timeout');
        },
      );

      _send('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[StockfishWeb] Initialized');
    } catch (e) {
      debugPrint('[StockfishWeb] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  void _send(String command) {
    _worker?.postMessage(command.toJS);
  }

  void _handleOutput(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    // Parse evaluation info
    if (trimmed.startsWith('info') && trimmed.contains('depth')) {
      final cpMatch = _cpRegex.firstMatch(trimmed);
      final depthMatch = _depthRegex.firstMatch(trimmed);
      final pvMatch = _pvRegex.firstMatch(trimmed);

      if (cpMatch != null && depthMatch != null) {
        _evalController.add(EvalInfo(
          score: int.parse(cpMatch.group(1)!) / 100.0,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: pvMatch?.group(1),
        ));
      }
    }

    // Parse bestmove
    if (trimmed.startsWith('bestmove')) {
      final parts = trimmed.split(' ');
      if (parts.length >= 2 && parts[1] != '(none)') {
        _moveCompleter?.complete(parts[1]);
        _moveCompleter = null;
        _stateNotifier.value = EngineState.ready;
      }
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_worker == null) throw StateError('Engine not initialized');
    _stateNotifier.value = EngineState.thinking;

    // Apply skill level
    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    _send(positionCommand);
    _moveCompleter = Completer<String>();
    _send('go depth ${depth ?? 15}');

    final move = await _moveCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _send('stop');
        throw TimeoutException('Search timed out');
      },
    );

    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) {
    if (_worker == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;

    _send('setoption name Skill Level value 20');
    _send(positionCommand);
    _send('go depth ${depth ?? 20}');

    return _evalController.stream;
  }

  @override
  void stop() {
    _send('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _worker?.terminate();
    _worker = null;
    _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }
}
