/// "Your Ghost": an opponent that plays like you.
///
/// In positions you have reached before it plays your own moves, in
/// proportion to how often you chose them; everywhere else it plays Maia at
/// the rating your moves look like, *sampled* rather than always taking
/// Maia's favourite, so it varies the way a person does. Built from the
/// games in your history; the rating is measured on demand
/// (HumanLensService.estimatePlayerElo) and remembered.
library;

import 'dart:math' as math;

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chess/player_profile.dart';
import 'chess_engine.dart';
import 'maia3_dart_engine.dart';
import 'uci_position.dart';

const String ghostEngineName = 'Your Ghost';

/// Preference keys for the measured rating and the games it came from.
const String ghostEloKey = 'ghostElo';
const String ghostEloGamesKey = 'ghostEloGames';
const String _historyKey = 'gameHistory';

class GhostEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final math.Random _random;

  /// Tests supply the profile and rating instead of reading preferences,
  /// and Maia's move probabilities instead of the model.
  final PlayerProfile? profileOverride;
  final int? eloOverride;
  final Future<Map<String, double>> Function(String positionCommand, int elo)?
      policyOverride;

  PlayerProfile _profile = PlayerProfile.empty;
  int _elo = 1500;
  Maia3DartEngine? _maia;

  GhostEngine(
      {this.profileOverride, this.eloOverride, this.policyOverride, math.Random? random})
      : _random = random ?? math.Random();

  PlayerProfile get profile => _profile;
  int get elo => _elo;

  @override
  String get name => ghostEngineName;
  @override
  String get version => '1.0';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => _elo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;
  @override
  bool get canPonder => false;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      if (profileOverride != null) {
        _profile = profileOverride!;
        _elo = eloOverride ?? 1500;
      } else {
        final prefs = await SharedPreferences.getInstance();
        _profile = PlayerProfile.fromPgns(prefs.getStringList(_historyKey) ?? []);
        _elo = prefs.getInt(ghostEloKey) ?? 1500;
      }
      if (policyOverride == null) {
        _maia = Maia3DartEngine(variantId: '5m', playerElo: _elo);
        await _maia!.initialize();
      }
      _stateNotifier.value =
          policyOverride != null || _maia!.state == EngineState.ready
              ? EngineState.ready
              : EngineState.error;
      debugPrint('[Ghost] ${_profile.games} games, '
          '${_profile.repertoire.length} book positions, plays like $_elo');
    } catch (e) {
      debugPrint('[Ghost] Failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  @override
  Future<String> bestMove(String positionCommand,
      {int? depth, Duration? moveTime, int? skillLevel}) async {
    if (_maia == null && policyOverride == null) {
      throw StateError('Not initialized');
    }
    _stateNotifier.value = EngineState.thinking;
    try {
      final fen = fenFromPositionCommand(positionCommand);
      final legal = {
        for (final m in chess.Chess.fromFEN(fen).generate_moves())
          '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}'
      };
      final book = {
        for (final e in (_profile.bookMoves(fen) ?? const <String, int>{}).entries)
          if (legal.contains(e.key)) e.key: e.value
      };
      if (book.isNotEmpty) return PlayerProfile.sample(book, _random);

      final policy = policyOverride != null
          ? await policyOverride!(positionCommand, _elo)
          : await _maia!.movePolicy(positionCommand, elo: _elo);
      var r = _random.nextDouble();
      for (final e in policy.entries) {
        r -= e.value;
        if (r <= 0) return e.key;
      }
      return policy.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    } finally {
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
          {int? depth, bool infinite = false}) =>
      _maia?.analyze(positionCommand, depth: depth, infinite: infinite) ??
      const Stream.empty();

  @override
  void stop() => _maia?.stop();

  @override
  void setOption(String name, String value) {}

  @override
  void dispose() {
    _maia?.dispose();
    _stateNotifier.value = EngineState.disposed;
  }
}
