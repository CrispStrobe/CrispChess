/// Native sample playback. Web keeps its independent Web Audio implementation.
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sound_service.dart';

/// Short local PCM samples supported by all audioplayers native backends.
/// Paths are relative to AudioCache's default `assets/` prefix.
const nativeSoundAssets = <ChessSound, String>{
  ChessSound.move: 'sounds/move.wav',
  ChessSound.capture: 'sounds/capture.wav',
  ChessSound.check: 'sounds/check.wav',
  ChessSound.castle: 'sounds/castle.wav',
  ChessSound.promote: 'sounds/promote.wav',
  ChessSound.gameStart: 'sounds/game-start.wav',
  ChessSound.gameEnd: 'sounds/game-end.wav',
  ChessSound.illegal: 'sounds/illegal.wav',
};

/// Owns one lazy player; newer events replace pending effects to avoid a backlog.
/// Audio and haptic failures are isolated from each other and from game play.
class SoundServiceNative extends SoundService {
  SoundServiceNative({AudioPlayer Function()? playerFactory})
      : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  AudioPlayer? _player;
  bool _disposed = false;
  int _request = 0;
  Future<void> _pending = Future<void>.value();

  @visibleForTesting
  Future<void> get pendingOperations => _pending;

  void _enqueue(Future<void> Function() operation) {
    _pending = _pending.then((_) async {
      try {
        await operation();
      } catch (error) {
        debugPrint('[Sound] Native audio error: $error');
      }
    });
  }

  @override
  set enabled(bool value) {
    if (_disposed || value == enabled) return;
    super.enabled = value;
    ++_request;
    if (!value) {
      _enqueue(() async => _player?.stop());
    }
  }

  @override
  void play(ChessSound sound) {
    if (_disposed || !enabled) return;
    unawaited(_haptic(sound));
    final request = ++_request;
    bool isCurrent() => !_disposed && enabled && request == _request;
    _enqueue(() async {
      if (!isCurrent()) return;
      final player = _player ??= _playerFactory();
      // Mix with spoken accessibility feedback and other apps. On iOS ambient
      // also respects the silent switch. No microphone permission is needed.
      await player.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ));
      if (!isCurrent()) return;
      await player.stop();
      await player.setSource(AssetSource(nativeSoundAssets[sound]!));
      // Loading assets is asynchronous: never resume an obsolete/muted effect.
      if (!isCurrent()) return;
      await player.setVolume(volume);
      if (!isCurrent()) return;
      await player.resume();
    });
  }

  Future<void> _haptic(ChessSound sound) async {
    try {
      switch (sound) {
        case ChessSound.capture:
        case ChessSound.check:
          await HapticFeedback.mediumImpact();
        case ChessSound.illegal:
          await HapticFeedback.heavyImpact();
        default:
          break;
      }
    } catch (error) {
      debugPrint('[Sound] Native haptic error: $error');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_request;
    _enqueue(() async {
      final player = _player;
      _player = null;
      await player?.dispose();
    });
  }
}
