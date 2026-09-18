import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'search_pacing.dart';

// Native function types
typedef _InitC = Int32 Function(Uint32 hashMb);
typedef _InitDart = int Function(int hashMb);

typedef _SetPositionC = Int32 Function(Pointer<Utf8> fen, Pointer<Utf8> moves);
typedef _SetPositionDart = int Function(Pointer<Utf8> fen, Pointer<Utf8> moves);

typedef _SearchC = Int32 Function(Int32 depth);
typedef _SearchDart = int Function(int depth);

typedef _SearchBoundedC = Int32 Function(Int32 depth, Uint64 maxNodes);
typedef _SearchBoundedDart = int Function(int depth, int maxNodes);

typedef _GetNodesC = Int64 Function();
typedef _GetNodesDart = int Function();

typedef _GetBestMoveC = Pointer<Utf8> Function();
typedef _GetBestMoveDart = Pointer<Utf8> Function();

typedef _GetScoreC = Int32 Function();
typedef _GetScoreDart = int Function();

typedef _GetDepthC = Int32 Function();
typedef _GetDepthDart = int Function();

typedef _DisposeC = Void Function();
typedef _DisposeDart = void Function();

/// Chess engine using Frozenight (Rust, MIT/Apache-2.0, ~2960 ELO).
///
/// Requires the native `frozenight_ffi` shared library to be available
/// at runtime. See `native/frozenight/` for the Rust FFI wrapper.
class FrozenightEngine implements ChessEngine {
  _InitDart? _init;
  _SetPositionDart? _setPosition;
  _SearchDart? _search;
  _SearchBoundedDart? _searchBounded;
  _GetNodesDart? _getNodes;

  /// Nodes per millisecond, measured as play goes on. Only the initial value
  /// is a guess, and it is deliberately low: guessing high on the first search
  /// of a session is the one case that cannot be corrected afterwards.
  double _nodesPerMs = 200;
  _GetBestMoveDart? _getBestMove;
  _GetScoreDart? _getScore;
  _GetDepthDart? _getDepth;
  _DisposeDart? _disposeNative;

  bool _disposed = false;
  bool _available = false;
  bool _stopped = false;

  /// Deep enough that the time budget is always what ends the search, without
  /// being unbounded: a depth this engine cannot reach inside any budget the
  /// app hands it, so the iterative deepening loop still terminates on its own
  /// in a position where the search returns instantly.
  static const int _fullStrengthDepth = 64;

  /// One search at a time. The FFI engine holds a single global position, so
  /// two overlapping searches would clobber each other's board between
  /// iterations (the deepening loop yields to the event loop, so another call
  /// really can land in the middle of one).
  Future<void> _searchLock = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() body) {
    final result = _searchLock.then((_) => body());
    _searchLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  String get name => 'Frozenight';
  @override
  String get version => '7.0.0';
  @override
  String get license => 'MIT/Apache-2.0';
  @override
  int get estimatedElo => 2960;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // The FFI search is one blocking call on the calling isolate — the UI
  // isolate here — so a background ponder search would freeze the app.
  @override
  bool get canPonder => false;

  /// Check if the native library is available on this platform.
  static bool get isAvailable {
    if (kIsWeb) return false;
    try {
      _openLib();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final lib = _openLib();
      _init = lib.lookupFunction<_InitC, _InitDart>('frozenight_init');
      _setPosition = lib.lookupFunction<_SetPositionC, _SetPositionDart>(
          'frozenight_set_position');
      _search = lib.lookupFunction<_SearchC, _SearchDart>('frozenight_search');
      // Added later than the rest; a library built before it still loads and
      // simply searches without a node bound.
      try {
        _searchBounded = lib.lookupFunction<_SearchBoundedC, _SearchBoundedDart>(
            'frozenight_search_bounded');
        _getNodes =
            lib.lookupFunction<_GetNodesC, _GetNodesDart>('frozenight_get_nodes');
      } on ArgumentError {
        debugPrint('[Frozenight] library predates the node bound');
      }
      _getBestMove = lib.lookupFunction<_GetBestMoveC, _GetBestMoveDart>(
          'frozenight_get_best_move');
      _getScore =
          lib.lookupFunction<_GetScoreC, _GetScoreDart>('frozenight_get_score');
      _getDepth =
          lib.lookupFunction<_GetDepthC, _GetDepthDart>('frozenight_get_depth');
      _disposeNative =
          lib.lookupFunction<_DisposeC, _DisposeDart>('frozenight_dispose');

      final result = _init!(32);
      if (result != 0) {
        _stateNotifier.value = EngineState.error;
        return;
      }
      _available = true;
      _stateNotifier.value = EngineState.ready;
    } catch (e) {
      debugPrint('Frozenight unavailable: $e');
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
    if (_disposed || !_available) throw StateError('Engine not ready');
    _stateNotifier.value = EngineState.thinking;

    // The depth ceiling is the difficulty knob: a weaker setting is a
    // shallower search. At full strength it should not be a knob at all — the
    // clock should be what stops the search — and 14 was low enough to stop it
    // first. Measured over a round robin at 300ms per move, 830 of 1554
    // Frozenight moves finished depth 14 and returned, several of them in
    // three milliseconds, handing back nearly the whole budget unused.
    final maxDepth = depth ??
        (skillLevel != null && skillLevel >= 20
            ? _fullStrengthDepth
            : (2 + (skillLevel ?? 10) * 12 ~/ 20).clamp(2, 14));
    final budget = moveTime ??
        (depth != null ? kFixedDepthTimeCap : thinkTimeForLevel(skillLevel ?? 10));

    // Deepen one step at a time inside a time budget rather than jumping
    // straight to the target depth. A single `search(14)` is one uninterruptible
    // FFI call whose cost explodes once the position opens up — fine on move 2,
    // tens of seconds of frozen UI by the middlegame. Each iteration is a small
    // fraction of the next, so stopping before starting one keeps the overshoot
    // bounded.
    return _serialized(() async {
      _applyPosition(positionCommand);
      final sw = Stopwatch()..start();
      String? best;
      var reached = 0;
      for (var d = 1; d <= maxDepth; d++) {
        if (_disposed) break;
        final remaining = budget - sw.elapsed;
        if (d > 1) {
          // With a node bound there is no need to predict whether a depth
          // fits: it is cut short if it does not. Without one, fall back to
          // the prediction, which is all the older library can support.
          if (_searchBounded == null) {
            if (!hasTimeForNextDepth(sw.elapsed, budget)) break;
          } else if (!worthStartingDepth(remaining, budget)) {
            break;
          }
          // Yield so the UI can paint between iterations.
          await Future<void>.delayed(Duration.zero);
        }

        final before = sw.elapsed;
        final int status;
        if (_searchBounded != null) {
          status = _searchBounded!(d, nodeAllowance(remaining, _nodesPerMs));
        } else {
          status = _search!(d);
        }
        if (status != 0) break;

        if (_getNodes != null) {
          final nodes = _getNodes!();
          final spent = (sw.elapsed - before).inMilliseconds;
          _nodesPerMs = updatedRate(_nodesPerMs, nodes, spent);
        }

        final ptr = _getBestMove!();
        if (ptr.address != 0) {
          best = ptr.toDartString();
          reached = d;
        }
      }

      _stateNotifier.value = EngineState.ready;

      // Nothing came back because the budget ran out before even depth one
      // finished, which is a timeout and not a broken engine. The type is what
      // the service classifies on: as a StateError this arrived at the player
      // as "Move request failed: Bad state: No move found".
      if (best == null) {
        throw TimeoutException(
            'No move within ${budget.inMilliseconds}ms', budget);
      }
      debugPrint('[Frozenight] $best depth=$reached/$maxDepth '
          '${sw.elapsedMilliseconds}ms (budget ${budget.inMilliseconds}ms)');
      return best;
    });
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (_disposed || !_available) return;
    _stateNotifier.value = EngineState.thinking;
    _stopped = false;
    _applyPosition(positionCommand);

    // Bounded for the same reason as [bestMove]: a deep iteration is one
    // blocking call that `stop` cannot interrupt.
    final budget = infinite ? const Duration(seconds: 10) : kFixedDepthTimeCap;
    final sw = Stopwatch()..start();

    for (int d = 1; d <= (depth ?? 20); d++) {
      if (_disposed || _stopped) break;
      if (d > 1 && !hasTimeForNextDepth(sw.elapsed, budget)) break;
      if (d > 1) await Future<void>.delayed(Duration.zero);
      if (_search!(d) != 0) break;

      final ptr = _getBestMove!();
      yield EvalInfo(
        score: _getScore!() / 100.0,
        depth: _getDepth!(),
        bestMove: ptr.address != 0 ? ptr.toDartString() : null,
      );
    }
    if (!_disposed) _stateNotifier.value = EngineState.ready;
  }

  @override
  void stop() {
    // The FFI search itself can't be signalled; this stops the deepening loop
    // from starting another iteration.
    _stopped = true;
  }

  @override
  void setOption(String name, String value) {
    // Frozenight FFI engine doesn't support runtime option changes
    // Options would need to be implemented in the native library
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeNative?.call();
    _stateNotifier.value = EngineState.disposed;
  }

  void _applyPosition(String positionCommand) {
    final parts = positionCommand.split(' ');
    String fen = 'startpos';
    String moves = '';

    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      fen = mi > 0 ? parts.sublist(2, mi).join(' ') : parts.sublist(2).join(' ');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    } else {
      final mi = parts.indexOf('moves');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    }

    final fenPtr = fen.toNativeUtf8();
    final movesPtr = moves.isEmpty ? nullptr.cast<Utf8>() : moves.toNativeUtf8();
    final rc = _setPosition!(fenPtr, movesPtr);
    malloc.free(fenPtr);
    if (moves.isNotEmpty) malloc.free(movesPtr);
    // Ignoring this return code is how a broken position went unnoticed: the
    // library kept the position it already had and answered with a move for the
    // wrong side, which the board then rejected as illegal.
    if (rc != 0) {
      throw StateError('Frozenight rejected the position (code $rc): $fen'
          '${moves.isEmpty ? '' : ' moves $moves'}');
    }
  }

  static DynamicLibrary _openLib() {
    if (Platform.isAndroid) return DynamicLibrary.open('libfrozenight_ffi.so');
    if (Platform.isIOS) return DynamicLibrary.process();
    if (Platform.isMacOS) return DynamicLibrary.open('libfrozenight_ffi.dylib');
    if (Platform.isLinux) return DynamicLibrary.open('libfrozenight_ffi.so');
    if (Platform.isWindows) return DynamicLibrary.open('frozenight_ffi.dll');
    throw UnsupportedError('Unsupported platform');
  }
}
