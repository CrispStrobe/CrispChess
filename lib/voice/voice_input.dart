/// Speak a move instead of dragging it: microphone capture and recognition
/// against the legal moves of the position. Native platforms only;
/// [VoiceInput.available] says whether this build has it.
library;

export 'voice_input_native.dart' if (dart.library.js_interop) 'voice_input_web.dart';
export 'voice_pick.dart';
export 'spoken_moves.dart' show VoiceLanguage;
