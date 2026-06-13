// Native Stockfish engine — runs stockfish binary as a separate process.
// This file is used on non-web platforms (via conditional import in engine_factory.dart).
// On web, stockfish_web_engine.dart is used instead.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

/// Stockfish engine running as a separate process via UCI protocol.
///
/// Runs the `stockfish` binary (must be installed on the system).
/// Since Stockfish runs as a separate process, the app binary itself
/// is NOT a derivative work under GPL — the GPL applies only to the
/// Stockfish binary, not to this wrapper code.
class StockfishEngine implements ChessEngine {
  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  StreamSubscription? _stdoutSub;

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r'pv (\S+)');

  @override
  String get name => 'Stockfish';
  @override
  String get version => '16';
  @override
  String get license => 'GPL-3.0 (separate process)';
  @override
  int get estimatedElo => 3600;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final path = await _findBinary();
      _process = await Process.start(path, []);

      final ready = Completer<void>();
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line);
        if (line.trim() == 'uciok' && !ready.isCompleted) ready.complete();
      });

      _process!.stdin.writeln('uci');
      await ready.future.timeout(const Duration(seconds: 5),
          onTimeout: () => debugPrint('[Stockfish] UCI timeout'));

      _process!.stdin.writeln('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Stockfish] Ready: $path');
    } catch (e) {
      debugPrint('[Stockfish] Not available: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  void _handleLine(String line) {
    final t = line.trim();
    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pv = _pvRegex.firstMatch(t);
      if (cp != null && d != null) {
        // eval updates available via analyze() stream
      }
    }
    if (t.startsWith('bestmove')) {
      final parts = t.split(' ');
      if (parts.length >= 2 && parts[1] != '(none)') {
        _moveCompleter?.complete(parts[1]);
        _moveCompleter = null;
        _stateNotifier.value = EngineState.ready;
      }
    }
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async {
    if (_process == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;
    if (skillLevel != null) {
      _process!.stdin.writeln('setoption name Skill Level value $skillLevel');
    }
    _process!.stdin.writeln(positionCommand);
    _moveCompleter = Completer<String>();
    _process!.stdin.writeln('go depth ${depth ?? 15}');
    return _moveCompleter!.future.timeout(const Duration(seconds: 30),
        onTimeout: () { _process!.stdin.writeln('stop'); throw TimeoutException('timeout'); });
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) {
    // For full analysis, create a stream controller
    final controller = StreamController<EvalInfo>();
    if (_process == null) return controller.stream..drain();

    _stateNotifier.value = EngineState.thinking;
    _process!.stdin.writeln(positionCommand);
    _process!.stdin.writeln('go depth ${depth ?? 20}');

    // Piggyback on stdout listener
    late StreamSubscription sub;
    sub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final t = line.trim();
      if (t.startsWith('info') && t.contains('depth')) {
        final cp = _cpRegex.firstMatch(t);
        final d = _depthRegex.firstMatch(t);
        final pv = _pvRegex.firstMatch(t);
        if (cp != null && d != null) {
          controller.add(EvalInfo(
            score: int.parse(cp.group(1)!) / 100.0,
            depth: int.parse(d.group(1)!),
            bestMove: pv?.group(1),
          ));
        }
      }
      if (t.startsWith('bestmove')) {
        _stateNotifier.value = EngineState.ready;
        sub.cancel();
        controller.close();
      }
    });

    return controller.stream;
  }

  @override
  void stop() {
    _process?.stdin.writeln('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _process?.stdin.writeln('quit');
    _stdoutSub?.cancel();
    _process?.kill();
    _process = null;
    _stateNotifier.value = EngineState.disposed;
  }

  static Future<String> _findBinary() async {
    // Search common locations
    for (final name in ['stockfish', 'stockfish.exe']) {
      try {
        final result = await Process.run(
            Platform.isWindows ? 'where' : 'which', [name]);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim();
        }
      } catch (_) {}
    }
    throw FileSystemException(
        'Stockfish not found. Install via package manager '
        'or download from stockfishchess.org');
  }
}
