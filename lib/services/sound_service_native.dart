/// Native sound service — uses Flutter SystemSound for basic feedback.
///
/// For full audio sample playback, add `audioplayers` (BSD) or
/// `just_audio` (MIT) and replace SystemSound calls with asset playback.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'sound_service.dart';

/// Native sound service using system sounds as a lightweight fallback.
class SoundServiceNative extends SoundService {
  @override
  void play(ChessSound sound) {
    if (!enabled) return;
    try {
      // Use system click sound for move feedback
      switch (sound) {
        case ChessSound.move:
        case ChessSound.castle:
          SystemSound.play(SystemSoundType.click);
        case ChessSound.capture:
        case ChessSound.check:
          HapticFeedback.mediumImpact();
          SystemSound.play(SystemSoundType.click);
        case ChessSound.illegal:
          HapticFeedback.heavyImpact();
        case ChessSound.gameStart:
        case ChessSound.gameEnd:
        case ChessSound.promote:
          SystemSound.play(SystemSoundType.click);
      }
    } catch (e) {
      debugPrint('[Sound] Native audio error: $e');
    }
  }
}
