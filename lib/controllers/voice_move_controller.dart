import '../voice/voice_input.dart';

/// Owns the microphone/model across screen rebuilds and releases a load that
/// finishes after the screen has gone away.
class VoiceMoveController {
  final Future<VoiceInput> Function() _openInput;
  VoiceMoveController({Future<VoiceInput> Function()? openInput})
      : _openInput =
            openInput ?? (() => VoiceInput.open(model: VoiceModel.base));
  VoiceInput? _input;
  bool _disposed = false;
  bool get listening => _input?.listening ?? false;

  Future<void> start() async {
    if (_disposed) return;
    if (_input == null) {
      final input = await _openInput();
      if (_disposed) {
        input.dispose();
        return;
      }
      _input = input;
    }
    final input = _input!;
    await input.startListening();
    if (_disposed) input.dispose();
  }

  Future<List<VoiceCandidate>> recognize(
      String fen, VoiceLanguage language) async {
    if (_disposed || _input == null) return [];
    return _input!.stopAndRank(fen, language);
  }

  void dispose() {
    _disposed = true;
    _input?.dispose();
    _input = null;
  }
}
