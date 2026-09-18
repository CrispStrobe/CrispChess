/// Generic UCI engine that loads any engine binary from disk.
///
/// Speaks the UCI protocol over stdin/stdout. Available on desktop
/// and mobile platforms (not web — no process spawning).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'generic_uci_engine_stub.dart';
import 'uci_option.dart';
import 'uci_search_coordinator.dart';

export 'generic_uci_engine_stub.dart' show EngineProfile;

/// Thrown when the engine process exits while it still owed us a move.
///
/// Without this the death was invisible: nothing completed the pending
/// request, the caller waited out its own timeout, and a crashed engine was
/// reported as a slow one. The two need telling apart — a slow engine wants a
/// bigger budget, a dead one wants its stderr read — so the last thing it
/// printed travels with the exception.
class EngineProcessDiedException implements Exception {
  final String engine;
  final int? exitCode;
  final List<String> stderrTail;

  EngineProcessDiedException(this.engine, this.exitCode, this.stderrTail);

  @override
  String toString() {
    final code = exitCode == null ? 'unknown exit code' : 'exit code $exitCode';
    final tail = stderrTail.isEmpty
        ? ' (it printed nothing to stderr)'
        : '\n  stderr: ${stderrTail.join('\n          ')}';
    return 'Engine "$engine" exited while searching ($code)$tail';
  }
}

class GenericUciEngine with UciSearchCoordinator implements ChessEngine {
  final EngineProfile profile;

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  /// Set once the connection is gone, so a request can say so instead of
  /// waiting. Stdout closing is the earliest sign and arrives well before the
  /// exit code — relying on the code alone left a 13ms death being reported as
  /// a 6.8-second timeout.
  bool _exited = false;
  int? _exitCode;

  /// Set while tearing down on purpose, so a kill is not reported as a crash.
  bool _disposing = false;

  /// The last few stderr lines, kept for the exception that reports a death.
  /// A crash usually explains itself there, and the output was being discarded.
  final List<String> _stderrTail = [];
  final _evalController = StreamController<EvalInfo>.broadcast();

  /// Engine identity parsed from the UCI handshake.
  String _engineName = 'Unknown';
  String _engineAuthor = '';

  /// Author, as reported by the engine's `id author` line.
  String get engineAuthor => _engineAuthor;

  /// UCI options advertised by the engine.
  final List<UciOption> options = [];

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');

  GenericUciEngine(this.profile);

  @override
  String get name => _engineName;
  @override
  String get version => '';
  @override
  String get license => 'Unknown';
  @override
  int get estimatedElo => 0;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // A real UCI process searches on its own thread and honours `stop`, so
  // background analysis is safe here.
  @override
  bool get canPonder => true;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final file = File(profile.path);
      if (!await file.exists()) {
        throw FileSystemException('Engine binary not found', profile.path);
      }

      _process = await Process.start(profile.path, []);
      _exited = false;
      _exitCode = null;
      _stderrTail.clear();

      _stderrSub = _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        _stderrTail.add(line);
        if (_stderrTail.length > 10) _stderrTail.removeAt(0);
      });

      // A process that dies owes us an answer it will never send. Watching the
      // exit turns an indefinite wait into an error that names the cause.
      unawaited(_process!.exitCode.then(_onProcessExit));

      final ready = Completer<void>();

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line, handshake: !ready.isCompleted);
        if (line.trim() == 'uciok' && !ready.isCompleted) {
          ready.complete();
        }
      }, onDone: () {
        // stdout closing is the first sign of death, usually ahead of the
        // exit code; don't leave a caller waiting for the difference.
        if (!ready.isCompleted) ready.complete();
        _releasePendingSearch();
      }, onError: (Object e) {
        debugPrint('[UCI] ${profile.path} stdout error: $e');
        _releasePendingSearch();
      });

      // Start UCI handshake
      _send('uci');

      await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('[UCI] Handshake timeout for ${profile.path}');
      });

      // Apply saved option overrides
      for (final entry in profile.optionOverrides.entries) {
        _send('setoption name ${entry.key} value ${entry.value}');
        // Also update the in-memory option
        for (final opt in options) {
          if (opt.name == entry.key) opt.value = entry.value;
        }
      }

      // Use the profile name if set, otherwise use engine-reported name
      if (profile.name.isNotEmpty) {
        _engineName = profile.name;
      }

      _send('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[UCI] $_engineName ready (${options.length} options)');
    } catch (e) {
      debugPrint('[UCI] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  @override
  void sendUci(String command) {
    if (_exited) return;
    try {
      _process?.stdin.writeln(command);
    } on SocketException catch (e) {
      // Writing to a pipe whose far end is gone. The exit watcher reports it.
      debugPrint('[UCI] ${profile.path} write failed: $e');
    }
  }

  void _onProcessExit(int code) {
    _exitCode = code;
    if (!_disposing) {
      debugPrint('[UCI] ${profile.path} exited with code $code');
    }
    _releasePendingSearch();
  }

  /// Note that the far end is gone and complete whatever request is
  /// outstanding, so its caller stops waiting.
  ///
  /// Called from both the exit code and stdout closing, because they do not
  /// arrive together and the request should end on whichever comes first. The
  /// move is null, which `bestMove` turns into [EngineProcessDiedException].
  void _releasePendingSearch() {
    _exited = true;
    if (!_disposing) _stateNotifier.value = EngineState.error;
    if (isSearching) finishSearch(null);
  }

  /// The death report, with the exit code if it can be had.
  ///
  /// Stdout closes a moment before the exit code lands, and the code is the
  /// most useful part of the report, so this waits briefly rather than saying
  /// "unknown" — which also gives any last stderr line time to be delivered.
  Future<EngineProcessDiedException> _deathReport() async {
    if (_exitCode == null && _process != null) {
      try {
        _exitCode =
            await _process!.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Gone but not reaped; report it without a code.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return EngineProcessDiedException(
        _engineName, _exitCode, List.of(_stderrTail));
  }

  void _send(String command) => sendUci(command);

  void _handleLine(String line, {bool handshake = false}) {
    final t = line.trim();

    // During handshake, parse engine identity and options
    if (handshake) {
      if (t.startsWith('id name ')) {
        _engineName = t.substring(8);
      } else if (t.startsWith('id author ')) {
        _engineAuthor = t.substring(10);
      } else if (t.startsWith('option name ')) {
        final opt = UciOption.parse(t);
        if (opt != null) options.add(opt);
      }
      return;
    }

    // Parse evaluation info lines
    if (t.startsWith('info') && t.contains('depth')) {
      final depthMatch = _depthRegex.firstMatch(t);
      if (depthMatch == null) return;

      double? score;
      final cpMatch = _cpRegex.firstMatch(t);
      final mateMatch = _mateRegex.firstMatch(t);
      if (cpMatch != null) {
        score = int.parse(cpMatch.group(1)!) / 100.0;
      } else if (mateMatch != null) {
        final mateIn = int.parse(mateMatch.group(1)!);
        score = mateIn > 0 ? 999.0 : -999.0;
      }

      if (score != null) {
        final pvMatch = _pvRegex.firstMatch(t);
        final pv = pvMatch?.group(1);
        final bestMove = pv?.split(' ').first;
        _evalController.add(EvalInfo(
          score: score,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: bestMove,
          pv: pv,
        ));
      }
    }

    // Parse bestmove. Every `bestmove` ends exactly one search, including
    // `(none)` and the one the engine emits in response to `stop` — routing all
    // of them through the coordinator is what keeps an aborted search's answer
    // from being handed to the next request.
    if (t.startsWith('bestmove')) {
      final parts = t.split(' ');
      final move = parts.length >= 2 && parts[1] != '(none)' ? parts[1] : null;
      finishSearch(move);
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_process == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    // Drive play by time rather than a fixed depth: the cost of a given depth
    // grows by an order of magnitude once the position opens up, which is what
    // made moves take seconds by the middlegame.
    final go = uciGoCommand(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    final cap = uciSearchTimeout(depth: depth, moveTime: moveTime, skillLevel: skillLevel);

    if (_exited) throw await _deathReport();

    final move = await startSearch(positionCommand, go, awaitMove: true)
        .timeout(cap, onTimeout: () {
      abandonSearch();
      return null;
    });
    if (move == null) {
      // A null answer means one of two very different things, and reporting
      // both as a timeout is what let a crashed engine pass for a slow one.
      if (_exited) throw await _deathReport();
      throw TimeoutException(
          'No bestmove within ${cap.inMilliseconds}ms', cap);
    }
    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (_process == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
    startSearch(positionCommand,
        infinite ? 'go infinite' : 'go depth ${depth ?? 20}',
        awaitMove: false);
    return _evalController.stream;
  }

  /// Set a UCI option at runtime.
  @override
  void setOption(String name, String value) {
    _send('setoption name $name value $value');
    for (final opt in options) {
      if (opt.name == name) opt.value = value;
    }
  }

  /// Trigger a button-type UCI option.
  void pressButton(String name) {
    _send('setoption name $name');
  }

  @override
  void stop() {
    // Ask the engine to stop, but leave the search registered: its `bestmove`
    // is still coming and must be consumed here, not by the next request.
    if (isSearching) _send('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _disposing = true;
    finishSearch(null);
    _send('quit');
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _evalController.close();
    _process?.kill();
    _process = null;
    _stateNotifier.value = EngineState.disposed;
  }
}
