/// Lynx engine stub for web — Lynx has no WASM build.
///
/// This stub exists so conditional imports compile on web.
/// It always reports as unavailable.

import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

class LynxEngine implements ChessEngine {
  @override String get name => 'Lynx';
  @override String get version => 'N/A';
  @override String get license => 'MIT';
  @override int get estimatedElo => 3350;
  @override EngineState get state => _stateNotifier.value;
  @override ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);

  static bool get isAvailable => false;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.error;
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async => throw UnsupportedError('Lynx not available on web');

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) =>
      const Stream.empty();

  @override void stop() {}
  @override void setOption(String name, String value) {}
  @override void dispose() {}
}
