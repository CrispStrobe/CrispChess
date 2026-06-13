/// Web sound service — calls sound_bridge.js for tone generation.

import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'sound_service.dart';

@JS('chessSoundPlay')
external void _jsPlaySound(JSString soundName, JSNumber volume);

/// Web-specific sound service using Web Audio API tones.
class SoundServiceWeb extends SoundService {
  @override
  void play(ChessSound sound) {
    if (!enabled) return;
    try {
      _jsPlaySound(sound.name.toJS, volume.toJS);
    } catch (e) {
      debugPrint('[Sound] Web audio error: $e');
    }
  }
}
