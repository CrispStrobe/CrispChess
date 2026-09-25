// Headless check of the voice-move path the app uses (model download, worker
// isolate, phrase scoring, ranking) on recorded WAVs instead of the mic.
// Lives under tool/ so the regular suite does not run it.
//
//   VOICE_FEN='<fen>' VOICE_LANG=en VOICE_WANT=g1f3 VOICE_WAVS='a.wav b.wav' \
//   LD_LIBRARY_PATH=<dir with libcrispasr.so> \
//     flutter test tool/voice/voice_smoke_test.dart
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/voice/voice_input.dart';

void main() {
  final env = Platform.environment;
  test('voice moves rank the spoken move first', () async {
    final fen = env['VOICE_FEN']!;
    final lang = env['VOICE_LANG'] == 'de' ? VoiceLanguage.german : VoiceLanguage.english;
    final want = env['VOICE_WANT']!;
    final wavs = env['VOICE_WAVS']!.split(' ').where((w) => w.isNotEmpty).toList();
    expect(VoiceInput.available, isTrue, reason: 'libcrispasr with phrase scoring');
    final voice = await VoiceInput.open(model: VoiceModel.tiny);
    var ok = 0;
    for (final path in wavs) {
      final sw = Stopwatch()..start();
      final ranked = await voice.rankPcm(_wav16k(path), fen, lang);
      final hit = ranked.isNotEmpty && ranked.first.uci == want;
      if (hit) ok++;
      print('${hit ? 'OK  ' : 'MISS'} $path  ${sw.elapsedMilliseconds} ms  '
          'confident=${isConfident(ranked)}  ${ranked.take(3).join(', ')}');
    }
    voice.dispose();
    expect(ok, wavs.length);
  }, timeout: const Timeout(Duration(minutes: 20)), skip: env['VOICE_FEN'] == null);
}

/// 16-bit mono 16 kHz PCM WAV → floats in [-1, 1].
Float32List _wav16k(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var at = 12;
  while (at + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(at, at + 4));
    final size = d.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      return Float32List.fromList(
          [for (var i = 0; i < n; i++) d.getInt16(at + 8 + 2 * i, Endian.little) / 32768]);
    }
    at += 8 + size + (size & 1);
  }
  throw FormatException('no data chunk in $path');
}
