// Stub file for platforms where Stockfish is not available.
// The actual implementation would import 'package:stockfish/stockfish.dart'
// and wrap it in the ChessEngine interface.
//
// To enable Stockfish:
// 1. Add stockfish: ^1.8.1 to pubspec.yaml
// 2. Replace this stub with the real implementation
// 3. Mark iOS builds to exclude this file
//
// Stockfish is GPL-3.0 — bundling it makes the entire binary GPL.
// Only use on non-iOS platforms where GPL compliance is acceptable.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

/// Stub Stockfish engine — returns unavailable on all platforms.
///
/// Replace with real implementation when stockfish package is added
/// as a dependency. See PLAN.md Phase 4.
class StockfishEngine implements ChessEngine {
  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.error);

  @override
  String get name => 'Stockfish';
  @override
  String get version => '18';
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => 3600;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  /// Check if Stockfish is available (requires stockfish package).
  static bool get isAvailable => false;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.error;
    throw UnsupportedError(
      'Stockfish not available. Add stockfish package to pubspec.yaml '
      'and replace this stub with the real implementation.',
    );
  }

  @override
  Future<String> bestMove(String positionCommand,
      {int? depth, Duration? moveTime, int? skillLevel}) {
    throw UnsupportedError('Stockfish not available');
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth}) {
    return const Stream.empty();
  }

  @override
  void stop() {}

  @override
  void dispose() {
    _stateNotifier.value = EngineState.disposed;
  }
}
