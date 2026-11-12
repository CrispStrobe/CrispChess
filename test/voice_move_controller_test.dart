import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/controllers/voice_move_controller.dart';
import 'package:crispchess/voice/voice_input.dart';

class RecordingInput implements VoiceInput {
  int releases = 0;
  bool started = false;
  Completer<void>? microphone;
  @override
  bool get listening => started;
  @override
  Future<void> startListening() async {
    if (microphone != null) await microphone!.future;
    started = true;
  }

  @override
  void dispose() {
    releases++;
    started = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a speech model that finishes loading after navigation is released',
      () async {
    final loading = Completer<VoiceInput>();
    final input = RecordingInput();
    final c = VoiceMoveController(openInput: () => loading.future);
    final task = c.start();
    c.dispose();
    loading.complete(input);
    await task;
    expect(input.releases, 1);
    expect(input.started, isFalse);
  });
  test('microphone activation finishing after disposal is released again',
      () async {
    final microphone = Completer<void>();
    final input = RecordingInput()..microphone = microphone;
    final c = VoiceMoveController(openInput: () async => input);
    final task = c.start();
    await Future<void>.delayed(Duration.zero);
    c.dispose();
    microphone.complete();
    await task;
    expect(input.releases, 2);
    expect(input.started, isFalse);
  });
}
