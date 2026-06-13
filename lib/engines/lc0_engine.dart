// Leela Chess Zero engine wrapper.
//
// Lc0 uses neural networks + MCTS instead of alpha-beta + NNUE.
// Plays more "human-like" especially with Maia weights.
//
// On native (iOS/Android): uses the leela_chess_zero Flutter package
//   which compiles lc0 C++ via NDK/CocoaPods (GPL-3.0 linked binary).
// On web: not available — no upstream WASM build of lc0 exists.
// The only attempt (frpays/lc0-js, 2019) is abandoned and uses
// outdated TF.js APIs. Blocked until lczero.org provides WASM support.
//
// The lc0 package is an OPTIONAL dependency — only add it to pubspec.yaml
// when you want a GPL build flavor. Without it, this file provides a stub.
//
// Neural network weights are downloaded separately (data, not code):
//   - Maia-1100 to Maia-1900: human-like play at specific ELO levels
//   - T80/T82: strongest lc0 nets (~3300+ ELO)
//   - Weights from: lczero.org/play/networks/ or maiachess.com

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

/// Available Lc0 neural network weight files.
class Lc0Weights {
  final String name;
  final String url;
  final int estimatedElo;
  final String description;
  final int sizeBytes;

  const Lc0Weights({
    required this.name,
    required this.url,
    required this.estimatedElo,
    required this.description,
    required this.sizeBytes,
  });

  /// Bundled Maia-1900 weights (human-like, ~1900 ELO)
  static const maia1900 = Lc0Weights(
    name: 'Maia-1900',
    url: 'bundled',
    estimatedElo: 1900,
    description: 'Human-like play at ~1900 ELO (trained on human games)',
    sizeBytes: 1200000,
  );

  /// Available weight options for download
  static const available = [
    Lc0Weights(
      name: 'Maia-1100',
      url: 'https://github.com/CSSLab/maia-chess/raw/main/maia_weights/maia-1100.pb.gz',
      estimatedElo: 1100,
      description: 'Beginner-level human play',
      sizeBytes: 1200000,
    ),
    Lc0Weights(
      name: 'Maia-1500',
      url: 'https://github.com/CSSLab/maia-chess/raw/main/maia_weights/maia-1500.pb.gz',
      estimatedElo: 1500,
      description: 'Intermediate human play',
      sizeBytes: 1200000,
    ),
    maia1900,
    Lc0Weights(
      name: 'Maia-1900',
      url: 'https://github.com/CSSLab/maia-chess/raw/main/maia_weights/maia-1900.pb.gz',
      estimatedElo: 1900,
      description: 'Advanced human play',
      sizeBytes: 1200000,
    ),
  ];
}

/// Stub Lc0 engine — available when leela_chess_zero package is added.
///
/// To enable:
/// 1. Add to pubspec.yaml:
///    leela_chess_zero:
///      git:
///        url: https://github.com/ArjanAswal/LeelaChessZero.git
/// 2. Replace this stub with the real Lc0Engine implementation
/// 3. Note: this makes the binary GPL-3.0 licensed
///
/// On iOS, the same downloadable JS approach as Stockfish could work
/// if an Emscripten/WASM build of lc0 becomes available.
class Lc0Engine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final Lc0Weights weights;

  Lc0Engine({this.weights = Lc0Weights.maia1900});

  @override
  String get name => 'Lc0 (${weights.name})';
  @override
  String get version => '0.31';
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => weights.estimatedElo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable {
    // Available when leela_chess_zero package is in pubspec.yaml
    // For now, returns false (stub)
    return false;
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.error;
    debugPrint('[Lc0] Not available — add leela_chess_zero package to pubspec.yaml');
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async {
    throw UnsupportedError('Lc0 not available');
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
