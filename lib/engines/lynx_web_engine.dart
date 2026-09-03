// Lynx WASM engine for web.
// MIT licensed. ~3350 ELO (CCRL) HCE engine.
// Compiled from C#/.NET to WebAssembly via .NET wasm-tools.
// Communicates via [JSExport] methods on the .NET WASM module.

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'lynx_build.dart';

@JS('lynxLoad')
external JSPromise<JSAny?> _lynxLoad(JSString bundleDir);

@JS('lynxLoadedBundle')
external JSString _lynxLoadedBundle();

@JS('lynxSendUci')
external JSPromise<JSString> _lynxSendUci(JSString command);

@JS('lynxSearch')
external JSPromise<JSString> _lynxSearch(JSString goCommand);

@JS('lynxDispose')
external void _lynxDispose();

// Pre-compiled regex for parsing UCI output
final _cpRegex = RegExp(r'score cp (-?\d+)');
final _mateRegex = RegExp(r'score mate (-?\d+)');
final _depthRegex = RegExp(r'depth (\d+)');
final _pvRegex = RegExp(r' pv (.+)');
final _multipvRegex = RegExp(r'multipv (\d+)');

/// Lynx HCE engine running as WASM in the browser.
///
/// ~3350 ELO (CCRL). MIT licensed.
/// Uses .NET compiled to WebAssembly (Mono runtime).
/// Async search — yields back to event loop during search.
class LynxEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);

  /// Which WASM build to load. The .NET runtime can only be created once per
  /// page, so a change takes effect on the next reload rather than immediately.
  final LynxBuild build;
  final _evalController = StreamController<EvalInfo>.broadcast();
  bool _loaded = false;
  bool _stopping = false;
  String _version = 'WASM';

  /// One search at a time. The .NET/Mono search runs to completion on the UI
  /// thread; overlapping calls interleave `position` and `go` commands on the
  /// same engine and hand back a move for the wrong position.
  Future<void> _searchLock = Future<void>.value();

  @override
  String get name => 'Lynx';
  @override
  String get version => '$_version · ${build.label}';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 3350;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  LynxEngine({String? variantId}) : build = LynxBuild.fromId(variantId);

  static bool get isAvailable => kIsWeb;

  // The Mono interpreter runs the search synchronously on the UI thread and
  // `stop` cannot cut it short, so a background ponder search would freeze the
  // app for as long as it takes — and it takes longer every move.
  @override
  bool get canPonder => false;

  /// Run [body] once any previous search has finished.
  Future<T> _serialized<T>(Future<T> Function() body) {
    final result = _searchLock.then((_) => body());
    _searchLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      debugPrint('[LynxWASM] Loading ${build.label} build (${build.directory})...');
      await _lynxLoad(build.directory.toJS).toDart;
      final loaded = _lynxLoadedBundle().toDart;
      if (loaded != build.directory) {
        // The runtime is a per-page singleton, so whichever build loaded first
        // is the one running. Say so rather than reporting the wrong engine.
        debugPrint('[LynxWASM] Note: $loaded is already loaded on this page; '
            'reload to switch to ${build.directory}.');
      }

      // Verify UCI handshake and parse version
      final uciResponse = (await _lynxSendUci('uci'.toJS).toDart).toDart;
      if (!uciResponse.contains('uciok')) {
        throw StateError('UCI handshake failed: $uciResponse');
      }
      // Parse "id name Lynx 1.11.0-dev-2e4b458f" → "1.11.0-2e4b458f (WASM)"
      final idMatch = RegExp(r'id name Lynx\s+(.+)').firstMatch(uciResponse);
      if (idMatch != null) {
        _version = '${idMatch.group(1)!.replaceAll('-dev', '')} (WASM)';
      }

      // Force single-threaded mode
      await _lynxSendUci('setoption name Threads value 1'.toJS).toDart;
      // Disable online tablebases
      await _lynxSendUci(
          'setoption name OnlineTablebaseInRootPositions value false'.toJS)
          .toDart;
      await _lynxSendUci(
          'setoption name OnlineTablebaseInSearch value false'.toJS)
          .toDart;

      await _lynxSendUci('isready'.toJS).toDart;

      // Warm the runtime up before handing the engine to the player. Mono
      // tiers up as it runs, and the difference is not marginal: measured on
      // this build, the first search of a session reaches depth 1 (57 nodes)
      // in a second, while the same search after one throwaway search on a
      // *different* position reaches depth 8 (10,574 nodes). Paying that here
      // costs nothing the player notices — the UI is already showing
      // "Loading" — instead of making their first move the slow, weak one.
      await _lynxSendUci('position startpos'.toJS).toDart;
      await _lynxSearch('go movetime 600'.toJS).toDart;

      _loaded = true;
      _stateNotifier.value = EngineState.ready;
      debugPrint('[LynxWASM] Ready (~3350 ELO)');
    } catch (e) {
      debugPrint('[LynxWASM] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (!_loaded) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;
    _stopping = false;

    // Lynx has no Skill Level option, so strength used to be dialled with a
    // fixed depth. Under the Mono interpreter a fixed depth costs whatever that
    // depth costs in the current position: quick in the opening, many seconds
    // once the position opens up, and worse every move — the "it gets slower
    // each turn" report. Search by time instead; Lynx honours `go movetime`.
    final budget = moveTime ?? thinkTimeForLevel(skillLevel ?? 10);
    final goCmd = depth != null
        ? 'go depth $depth'
        : 'go movetime ${budget.inMilliseconds}';

    return _serialized(() async {
      try {
        // Yield to let the UI update before the blocking search
        await Future.delayed(const Duration(milliseconds: 50));

        await _lynxSendUci(positionCommand.toJS).toDart;
        final result = (await _lynxSearch(goCmd.toJS).toDart).toDart;

        final bestMove = _parseBestMove(result);
        _stateNotifier.value = EngineState.ready;

        if (bestMove == null) throw StateError('No bestmove in output');
        debugPrint('[LynxWASM] bestmove=$bestMove ($goCmd)');
        return bestMove;
      } catch (e) {
        _stateNotifier.value = EngineState.ready;
        rethrow;
      }
    });
  }

  @override
  Stream<EvalInfo> analyze(
    String positionCommand, {
    int? depth,
    bool infinite = false,
  }) {
    if (!_loaded) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
    _stopping = false;

    // Run search async and emit eval info as it arrives
    _runAnalysis(positionCommand, depth: depth, infinite: infinite);

    return _evalController.stream;
  }

  Future<void> _runAnalysis(
    String positionCommand, {
    int? depth,
    bool infinite = false,
  }) async {
    // Analysis is time-bounded, not depth-bounded. The Mono search blocks the
    // UI thread and only reads `stop` once it has finished, so neither `go
    // infinite` nor a deep `go depth` can be cut short — whatever is asked for
    // is what the app freezes for. [depth] is therefore advisory here; the
    // reported depth comes back on the `info` lines.
    final goCmd = 'go movetime ${kFixedDepthTimeCap.inMilliseconds}';
    await _serialized(() async {
      try {
        await _lynxSendUci(positionCommand.toJS).toDart;
        final result = (await _lynxSearch(goCmd.toJS).toDart).toDart;

        // Parse all info lines from the result
        for (final line in result.split('\n')) {
          if (_stopping) break;
          _parseInfoLine(line.trim());
        }
      } catch (e) {
        debugPrint('[LynxWASM] Analysis error: $e');
      } finally {
        if (!_stopping) {
          _stateNotifier.value = EngineState.ready;
        }
      }
    });
  }

  void _parseInfoLine(String line) {
    if (!line.startsWith('info') || !line.contains('depth')) return;

    final depthMatch = _depthRegex.firstMatch(line);
    if (depthMatch == null) return;

    double? score;
    final cpMatch = _cpRegex.firstMatch(line);
    final mateMatch = _mateRegex.firstMatch(line);
    if (cpMatch != null) {
      score = int.parse(cpMatch.group(1)!) / 100.0;
    } else if (mateMatch != null) {
      final mateIn = int.parse(mateMatch.group(1)!);
      score = mateIn > 0 ? 100.0 : -100.0;
    }
    if (score == null) return;

    final pvMatch = _pvRegex.firstMatch(line);
    final mpvMatch = _multipvRegex.firstMatch(line);
    final pv = pvMatch?.group(1);

    _evalController.add(EvalInfo(
      score: score,
      depth: int.parse(depthMatch.group(1)!),
      bestMove: pv?.split(' ').first,
      pv: pv,
      pvIndex: mpvMatch != null ? int.parse(mpvMatch.group(1)!) : 1,
    ));
  }

  String? _parseBestMove(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('bestmove')) {
        final parts = trimmed.split(' ');
        if (parts.length >= 2 && parts[1] != '(none)') {
          return parts[1];
        }
      }
    }
    return null;
  }

  @override
  void stop() {
    _stopping = true;
    if (_loaded) {
      // Send stop command (fire-and-forget)
      _lynxSendUci('stop'.toJS).toDart.ignore();
    }
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {
    if (!_loaded) return;
    _lynxSendUci('setoption name $name value $value'.toJS).toDart.ignore();
  }

  @override
  void dispose() {
    _stopping = true;
    if (_loaded) _lynxDispose();
    _loaded = false;
    _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }
}
