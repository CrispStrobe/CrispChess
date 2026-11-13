import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crispchess/services/sound_service.dart';
import 'package:crispchess/services/sound_service_factory.dart';
import 'package:crispchess/services/sound_service_native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlayer implements AudioPlayer {
  final sources = <Source>[];
  final volumes = <double>[];
  final contexts = <AudioContext>[];
  int resumes = 0;
  int stops = 0;
  int disposals = 0;
  Completer<void>? loading;
  Object? contextError;
  Object? sourceError;
  Object? resumeError;
  Object? disposeError;

  @override
  Future<void> setAudioContext(AudioContext context) async {
    if (contextError case final error?) throw error;
    contexts.add(context);
  }

  @override
  Future<void> setSource(Source source) async {
    sources.add(source);
    if (sourceError case final error?) throw error;
    await loading?.future;
  }

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> resume() async {
    if (resumeError case final error?) throw error;
    resumes++;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async {
    disposals++;
    if (disposeError case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlayer player;
  late SoundServiceNative service;
  late List<MethodCall> feedback;
  late int creations;

  setUp(() {
    player = FakePlayer();
    feedback = [];
    creations = 0;
    service = SoundServiceNative(playerFactory: () {
      creations++;
      return player;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      feedback.add(call);
      return null;
    });
  });

  tearDown(() async {
    service.dispose();
    await service.pendingOperations;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('native factory uses sample service without allocating a player', () {
    final instance = createSoundService();
    expect(instance, isA<SoundServiceNative>());
    instance.dispose();
    expect(creations, 0);
  });

  test('disabled effects create no player and send no haptics; re-enable works',
      () async {
    service.enabled = false;
    for (final sound in ChessSound.values) {
      service.play(sound);
    }
    await service.pendingOperations;
    expect(creations, 0);
    expect(feedback, isEmpty);
    service.enabled = true;
    service.play(ChessSound.move);
    await service.pendingOperations;
    expect(creations, 1);
    expect(player.resumes, 1);
  });

  test('each event loads its distinct bundled PCM sample and current volume',
      () async {
    const expectedPaths = [
      'sounds/move.wav',
      'sounds/capture.wav',
      'sounds/check.wav',
      'sounds/castle.wav',
      'sounds/promote.wav',
      'sounds/game-start.wav',
      'sounds/game-end.wav',
      'sounds/illegal.wav',
    ];
    final payloads = <String>{};
    for (final (index, sound) in ChessSound.values.indexed) {
      service.volume = index / 10;
      service.play(sound);
      await service.pendingOperations;
      final source = player.sources.last as AssetSource;
      expect(source.path, expectedPaths[index]);
      expect(player.volumes.last, index / 10);
      final bytes = await rootBundle.load('assets/${source.path}');
      expect(String.fromCharCodes(bytes.buffer.asUint8List(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.buffer.asUint8List(8, 4)), 'WAVE');
      expect(bytes.getUint16(20, Endian.little), 1); // PCM
      expect(bytes.getUint16(22, Endian.little), 1); // mono
      expect(bytes.getUint32(24, Endian.little), 44100);
      expect(bytes.getUint16(34, Endian.little), 16);
      expect(bytes.lengthInBytes, inInclusiveRange(44 + 4410, 44 + 52920));
      payloads.add(String.fromCharCodes(bytes.buffer.asUint8List()));
    }
    expect(payloads.length, ChessSound.values.length);
    expect(player.resumes, 8);
    expect(creations, 1);
    expect(feedback.map((call) => call.method),
        everyElement('HapticFeedback.vibrate'));
    expect(feedback.map((call) => call.arguments), [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
    expect(player.contexts.last.android.audioFocus, AndroidAudioFocus.none);
    expect(player.contexts.last.iOS.category, AVAudioSessionCategory.ambient);
  });

  test('disable stops current playback and invalidates queued effects',
      () async {
    service.play(ChessSound.move);
    await service.pendingOperations;
    final stops = player.stops;
    service.play(ChessSound.promote);
    service.enabled = false;
    await service.pendingOperations;
    expect(player.stops, stops + 1);
    expect(player.resumes, 1);
    expect(player.sources, hasLength(1));
  });

  test('mute during loading prevents delayed playback even after re-enable',
      () async {
    player.loading = Completer<void>();
    service.play(ChessSound.move);
    await Future<void>.delayed(Duration.zero);
    expect(player.sources, hasLength(1));
    service.enabled = false;
    service.enabled = true;
    player.loading!.complete();
    await service.pendingOperations;
    expect(player.resumes, 0);
    service.play(ChessSound.capture);
    await service.pendingOperations;
    expect(player.resumes, 1);
  });

  test('rapid pending events use the newest effect', () async {
    service.play(ChessSound.move);
    service.play(ChessSound.gameEnd);
    await service.pendingOperations;
    expect((player.sources.single as AssetSource).path, 'sounds/game-end.wav');
    expect(player.resumes, 1);
  });

  test('source failure is contained, keeps haptics, and next playback can work',
      () async {
    player.sourceError = PlatformException(code: 'decode-failed');
    service.play(ChessSound.check);
    await service.pendingOperations;
    expect(player.resumes, 0);
    expect(feedback.single.arguments, 'HapticFeedbackType.mediumImpact');
    player.sourceError = null;
    service.play(ChessSound.move);
    await service.pendingOperations;
    expect(player.resumes, 1);
  });

  test('missing plugin failure is contained and preserves haptics', () async {
    player.contextError = MissingPluginException('backend unavailable');
    service.play(ChessSound.capture);
    await service.pendingOperations;
    expect(player.sources, isEmpty);
    expect(player.resumes, 0);
    expect(feedback.single.arguments, 'HapticFeedbackType.mediumImpact');
  });

  test('asynchronous playback failure does not poison later operations',
      () async {
    player.resumeError = StateError('device unavailable');
    service.play(ChessSound.move);
    await service.pendingOperations;
    player.resumeError = null;
    service.play(ChessSound.move);
    await service.pendingOperations;
    expect(player.resumes, 1);
  });

  test('synchronous player creation failure is contained and can retry',
      () async {
    var fail = true;
    final instance = SoundServiceNative(playerFactory: () {
      if (fail) throw StateError('unavailable');
      return player;
    });
    instance.play(ChessSound.illegal);
    await instance.pendingOperations;
    expect(feedback.single.arguments, 'HapticFeedbackType.heavyImpact');
    fail = false;
    instance.play(ChessSound.move);
    await instance.pendingOperations;
    expect(player.resumes, 1);
    instance.dispose();
    await instance.pendingOperations;
  });

  test('haptic failure does not prevent audio playback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async {
      throw PlatformException(code: 'no-haptics');
    });
    service.play(ChessSound.illegal);
    await service.pendingOperations;
    expect(player.resumes, 1);
  });

  test('dispose during load cancels playback and releases player once',
      () async {
    player.loading = Completer<void>();
    service.play(ChessSound.move);
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    service.dispose();
    player.loading!.complete();
    await service.pendingOperations;
    service.play(ChessSound.check);
    await service.pendingOperations;
    expect(player.resumes, 0);
    expect(player.disposals, 1);
    expect(feedback, isEmpty);
  });

  test('disposal failure is contained and calls after dispose are ignored',
      () async {
    service.play(ChessSound.move);
    await service.pendingOperations;
    player.disposeError = PlatformException(code: 'already-gone');
    service.dispose();
    await service.pendingOperations;
    service.enabled = false;
    service.play(ChessSound.illegal);
    await service.pendingOperations;
    expect(player.resumes, 1);
    expect(player.disposals, 1);
    expect(feedback, isEmpty);
  });
}
