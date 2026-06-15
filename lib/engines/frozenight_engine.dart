import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

// Native function types
typedef _InitC = Int32 Function(Uint32 hashMb);
typedef _InitDart = int Function(int hashMb);

typedef _SetPositionC = Int32 Function(Pointer<Utf8> fen, Pointer<Utf8> moves);
typedef _SetPositionDart = int Function(Pointer<Utf8> fen, Pointer<Utf8> moves);

typedef _SearchC = Int32 Function(Int32 depth);
typedef _SearchDart = int Function(int depth);

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
  _GetBestMoveDart? _getBestMove;
  _GetScoreDart? _getScore;
  _GetDepthDart? _getDepth;
  _DisposeDart? _disposeNative;

  bool _disposed = false;
  bool _available = false;

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

    _applyPosition(positionCommand);
    final d = depth ?? (2 + (skillLevel ?? 10) * 12 ~/ 20).clamp(2, 14);
    final result = _search!(d);

    _stateNotifier.value = EngineState.ready;

    if (result != 0) throw StateError('Search failed');
    final ptr = _getBestMove!();
    if (ptr.address == 0) throw StateError('No move found');
    return ptr.toDartString();
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (_disposed || !_available) return;
    _stateNotifier.value = EngineState.thinking;
    _applyPosition(positionCommand);

    for (int d = 1; d <= (depth ?? 20); d++) {
      if (_disposed) break;
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
  void stop() {}

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
    _setPosition!(fenPtr, movesPtr);
    malloc.free(fenPtr);
    if (moves.isNotEmpty) malloc.free(movesPtr);
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
