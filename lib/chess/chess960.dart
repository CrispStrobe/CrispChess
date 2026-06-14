/// Chess960 (Fischer Random) starting position generator.
///
/// Generates random starting positions following Chess960 rules:
/// 1. The king is between the two rooks
/// 2. Bishops are on opposite colors
/// 3. Both sides mirror each other
import 'dart:math';

/// Generate a random Chess960 starting position FEN.
String generateChess960Fen({Random? rng}) {
  rng ??= Random();
  final pieces = List<String>.filled(8, '');

  // Place bishops on opposite colors
  final lightSquare = rng.nextInt(4) * 2; // 0, 2, 4, 6
  final darkSquare = rng.nextInt(4) * 2 + 1; // 1, 3, 5, 7
  pieces[lightSquare] = 'B';
  pieces[darkSquare] = 'B';

  // Place queen on random empty square
  final emptyForQueen = <int>[];
  for (int i = 0; i < 8; i++) {
    if (pieces[i].isEmpty) emptyForQueen.add(i);
  }
  pieces[emptyForQueen[rng.nextInt(emptyForQueen.length)]] = 'Q';

  // Place knights on random empty squares
  final emptyForKnights = <int>[];
  for (int i = 0; i < 8; i++) {
    if (pieces[i].isEmpty) emptyForKnights.add(i);
  }
  final k1 = rng.nextInt(emptyForKnights.length);
  pieces[emptyForKnights[k1]] = 'N';
  emptyForKnights.removeAt(k1);
  final k2 = rng.nextInt(emptyForKnights.length);
  pieces[emptyForKnights[k2]] = 'N';

  // Place rook-king-rook on remaining squares (king between rooks)
  final remaining = <int>[];
  for (int i = 0; i < 8; i++) {
    if (pieces[i].isEmpty) remaining.add(i);
  }
  // remaining has exactly 3 squares; place R-K-R in order
  pieces[remaining[0]] = 'R';
  pieces[remaining[1]] = 'K';
  pieces[remaining[2]] = 'R';

  // Build FEN
  final backRank = pieces.join();
  final whitePawns = 'PPPPPPPP';
  final blackBack = backRank.toLowerCase();
  final blackPawns = 'pppppppp';

  return '$blackBack/$blackPawns/8/8/8/8/$whitePawns/$backRank w KQkq - 0 1';
}
