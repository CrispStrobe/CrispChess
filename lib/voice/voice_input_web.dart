/// Voice moves are native-only: the recogniser is a native library.
library;

import 'dart:typed_data';

import 'spoken_moves.dart';
import 'voice_pick.dart';

enum VoiceModel {
  tiny('ggml-tiny.bin', 75),
  base('ggml-base.bin', 142);

  final String file;
  final int megabytes;
  const VoiceModel(this.file, this.megabytes);
}

class VoiceInput {
  VoiceInput._();

  static bool get available => false;

  static Future<VoiceInput> open({
    VoiceModel model = VoiceModel.base,
    void Function(int received, int? total)? onProgress,
  }) =>
      throw UnsupportedError('voice moves are not available on the web');

  bool get listening => false;
  void startListening() {}
  Future<List<VoiceCandidate>> stopAndRank(String fen, VoiceLanguage lang) async => const [];
  Future<List<VoiceCandidate>> rankPcm(Float32List pcm, String fen, VoiceLanguage lang) async => const [];
  void dispose() {}
}
