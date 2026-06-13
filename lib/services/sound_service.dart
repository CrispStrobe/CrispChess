/// Sound effects for chess moves, captures, and game events.
///
/// On web: uses Web Audio API via sound_bridge.js (tone synthesis).
/// On native: stub for now. Add audioplayers package for native sounds.

import 'package:flutter/foundation.dart';

/// Sound events in the game.
enum ChessSound {
  move,
  capture,
  check,
  castle,
  promote,
  gameStart,
  gameEnd,
  illegal,
}

/// Service managing sound effects.
class SoundService {
  bool _enabled = true;
  double _volume = 0.7;

  bool get enabled => _enabled;
  double get volume => _volume;

  set enabled(bool value) => _enabled = value;
  set volume(double value) => _volume = value.clamp(0.0, 1.0);

  /// Play a sound effect.
  void play(ChessSound sound) {
    if (!_enabled) return;
    debugPrint('[Sound] ${sound.name}');
    // On web, the JS bridge is called from the platform-specific import.
    // This base class is used on native where we don't play sounds yet.
  }

  void dispose() {}
}
