import 'sound_service.dart';

/// Select feedback after a successful move, for either side and every platform.
/// SAN records captures even when the destination was empty (en passant).
ChessSound soundForMove({
  required String uci,
  required String? san,
  required bool inCheck,
}) {
  if (inCheck) return ChessSound.check;
  if (uci.length > 4) return ChessSound.promote;
  if (san != null) {
    if (san.startsWith('O-O')) return ChessSound.castle;
    if (san.contains('x')) return ChessSound.capture;
  } else if (const ['e1g1', 'e1c1', 'e8g8', 'e8c8'].contains(uci)) {
    return ChessSound.castle;
  }
  return ChessSound.move;
}
