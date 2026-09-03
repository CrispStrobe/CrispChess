/// Web stub for GenericUciEngine — not available on web platform.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'generic_uci_engine_stub.dart';
import 'uci_option.dart';

export 'generic_uci_engine_stub.dart' show EngineProfile;

class GenericUciEngine implements ChessEngine {
  final EngineProfile profile;
  final List<UciOption> options = [];

  GenericUciEngine(this.profile);

  @override String get name => profile.name;
  @override String get version => '';
  @override String get license => 'Unknown';
  @override int get estimatedElo => 0;
  @override EngineState get state => EngineState.error;
  @override ValueNotifier<EngineState> get stateNotifier => ValueNotifier(EngineState.error);
  @override Future<void> initialize() async =>
      throw UnsupportedError('Custom UCI engines not available on web');
  @override Future<String> bestMove(String p, {int? depth, Duration? moveTime, int? skillLevel}) async =>
      throw UnsupportedError('Custom UCI engines not available on web');
  @override Stream<EvalInfo> analyze(String p, {int? depth, bool infinite = false}) =>
      const Stream.empty();
  @override bool get canPonder => false;
  @override void stop() {}
  @override void setOption(String name, String value) {}
  @override void dispose() {}
  void pressButton(String name) {}
}
