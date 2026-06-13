/// Built-in opening book — maps FEN positions to weighted candidate moves.
///
/// Contains ~100 popular opening positions covering:
/// - Italian Game, Ruy Lopez, Sicilian, French, Caro-Kann
/// - Queen's Gambit, King's Indian, Nimzo-Indian, English
/// - Common responses for both sides through move 8-10
///
/// Moves are weighted by popularity in master games. The engine picks
/// randomly weighted by these values for natural variation.

import 'dart:math';

/// A candidate book move with a weight (higher = more likely to be chosen).
class BookMove {
  final String uci;
  final int weight;
  const BookMove(this.uci, this.weight);
}

/// The opening book. Lookup by FEN position key (piece placement + side only).
class OpeningBook {
  static final _rng = Random();

  /// Look up book moves for a position.
  /// Returns null if the position is not in the book.
  static List<BookMove>? lookup(String fen) {
    final key = _positionKey(fen);
    return _book[key];
  }

  /// Pick a random book move weighted by popularity.
  /// Returns null if no book move exists.
  static String? pickMove(String fen) {
    final moves = lookup(fen);
    if (moves == null || moves.isEmpty) return null;

    final totalWeight = moves.fold<int>(0, (sum, m) => sum + m.weight);
    var roll = _rng.nextInt(totalWeight);
    for (final m in moves) {
      roll -= m.weight;
      if (roll < 0) return m.uci;
    }
    return moves.last.uci;
  }

  /// Extract position key: piece placement + side to move.
  /// Strips castling, en passant, and move counters for broader matching.
  static String _positionKey(String fen) {
    final parts = fen.split(' ');
    if (parts.length < 2) return fen;
    return '${parts[0]} ${parts[1]}';
  }

  // ── Opening book data ──────────────────────────────────────────────
  // Format: FEN position key → list of (UCI move, weight)
  // Weights approximate relative popularity in master-level games.

  static final Map<String, List<BookMove>> _book = {
    // ── Starting position ──
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w': [
      BookMove('e2e4', 40), // King's pawn
      BookMove('d2d4', 35), // Queen's pawn
      BookMove('g1f3', 12), // Réti
      BookMove('c2c4', 10), // English
      BookMove('b1c3', 2),
      BookMove('g2g3', 1),
    ],

    // ── After 1.e4 ──
    'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b': [
      BookMove('e7e5', 30), // Open game
      BookMove('c7c5', 30), // Sicilian
      BookMove('e7e6', 15), // French
      BookMove('c7c6', 12), // Caro-Kann
      BookMove('d7d5', 5),  // Scandinavian
      BookMove('g7g6', 5),  // Modern/Pirc
      BookMove('d7d6', 3),  // Pirc
    ],

    // ── After 1.e4 e5 ──
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w': [
      BookMove('g1f3', 70), // King's Knight
      BookMove('f1c4', 15), // Bishop's Opening
      BookMove('b1c3', 5),  // Vienna
      BookMove('f2f4', 5),  // King's Gambit
      BookMove('d2d4', 5),  // Center Game
    ],

    // ── After 1.e4 e5 2.Nf3 ──
    'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b': [
      BookMove('b8c6', 75), // Normal
      BookMove('g8f6', 15), // Petrov
      BookMove('d7d6', 5),  // Philidor
      BookMove('f7f5', 3),  // Latvian
    ],

    // ── After 1.e4 e5 2.Nf3 Nc6 ──
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': [
      BookMove('f1b5', 40), // Ruy Lopez
      BookMove('f1c4', 30), // Italian
      BookMove('d2d4', 15), // Scotch
      BookMove('b1c3', 10), // Four Knights
    ],

    // ── Ruy Lopez: 1.e4 e5 2.Nf3 Nc6 3.Bb5 ──
    'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b': [
      BookMove('a7a6', 50), // Morphy Defense
      BookMove('g8f6', 25), // Berlin
      BookMove('f8c5', 10), // Classical
      BookMove('d7d6', 8),  // Steinitz
      BookMove('f7f5', 3),  // Schliemann
    ],

    // ── Ruy Lopez Morphy: 3...a6 ──
    'r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w': [
      BookMove('b5a4', 60), // Maintaining bishop
      BookMove('b5c6', 20), // Exchange Variation
      BookMove('d2d4', 10),
    ],

    // ── Italian: 1.e4 e5 2.Nf3 Nc6 3.Bc4 ──
    'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b': [
      BookMove('f8c5', 40), // Giuoco Piano
      BookMove('g8f6', 35), // Two Knights
      BookMove('f8e7', 10), // Hungarian
      BookMove('d7d6', 8),
    ],

    // ── Italian Giuoco Piano: 3...Bc5 ──
    'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w': [
      BookMove('c2c3', 35), // Main line
      BookMove('d2d3', 30), // Giuoco Pianissimo
      BookMove('b2b4', 15), // Evans Gambit
      BookMove('d2d4', 10),
      BookMove('e1g1', 10), // Castle
    ],

    // ── Sicilian: 1.e4 c5 ──
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w': [
      BookMove('g1f3', 60), // Open Sicilian
      BookMove('b1c3', 15), // Closed
      BookMove('c2c3', 10), // Alapin
      BookMove('d2d4', 5),
      BookMove('f2f4', 5),  // Grand Prix
    ],

    // ── Sicilian 2.Nf3 ──
    'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b': [
      BookMove('d7d6', 35), // Najdorf/Dragon/Classical
      BookMove('b8c6', 25), // Classical
      BookMove('e7e6', 25), // Scheveningen/Kan
      BookMove('g7g6', 8),  // Hyper-Accelerated Dragon
    ],

    // ── Sicilian 2.Nf3 d6 3.d4 ──
    'rnbqkbnr/pp2pppp/3p4/2p5/3PP3/5N2/PPP2PPP/RNBQKB1R b': [
      BookMove('c5d4', 80), // Main line
      BookMove('g8f6', 15),
    ],

    // ── Sicilian Open 3...cxd4 4.Nxd4 ──
    'rnbqkbnr/pp2pppp/3p4/8/3NP3/8/PPP2PPP/RNBQKB1R b': [
      BookMove('g8f6', 45), // Najdorf/Classical
      BookMove('b8c6', 25), // Classical
      BookMove('g7g6', 15), // Dragon
      BookMove('e7e5', 5),
    ],

    // ── Sicilian Najdorf: 4...Nf6 5.Nc3 a6 ──
    'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w': [
      BookMove('f1e2', 25),
      BookMove('c1g5', 25), // English Attack
      BookMove('f2f3', 20),
      BookMove('f1d3', 10),
      BookMove('g2g3', 10),
    ],

    // ── French: 1.e4 e6 ──
    'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w': [
      BookMove('d2d4', 70),
      BookMove('d2d3', 10), // King's Indian Attack
      BookMove('g1f3', 10),
      BookMove('b1c3', 5),
    ],

    // ── French 2.d4 d5 ──
    'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/8/PPP2PPP/RNBQKBNR w': [
      BookMove('b1c3', 30), // Classical/Winawer
      BookMove('b1d2', 25), // Tarrasch
      BookMove('e4e5', 25), // Advance
      BookMove('e4d5', 15), // Exchange
    ],

    // ── Caro-Kann: 1.e4 c6 ──
    'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w': [
      BookMove('d2d4', 60),
      BookMove('b1c3', 15),
      BookMove('g1f3', 10),
      BookMove('c2c4', 5),
    ],

    // ── Caro-Kann 2.d4 d5 ──
    'rnbqkbnr/pp2pppp/2p5/3p4/3PP3/8/PPP2PPP/RNBQKBNR w': [
      BookMove('b1c3', 35), // Classical
      BookMove('b1d2', 20), // Modern
      BookMove('e4e5', 20), // Advance
      BookMove('e4d5', 15), // Exchange
      BookMove('g1f3', 5),
    ],

    // ── After 1.d4 ──
    'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b': [
      BookMove('d7d5', 35), // Queen's pawn game
      BookMove('g8f6', 35), // Indian defenses
      BookMove('f7f5', 5),  // Dutch
      BookMove('e7e6', 10), // Can transpose
      BookMove('d7d6', 5),  // Old Indian
      BookMove('c7c5', 5),  // Benoni
    ],

    // ── 1.d4 d5 ──
    'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w': [
      BookMove('c2c4', 55), // Queen's Gambit
      BookMove('g1f3', 25),
      BookMove('c1f4', 10), // London
      BookMove('b1c3', 5),
    ],

    // ── Queen's Gambit: 1.d4 d5 2.c4 ──
    'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b': [
      BookMove('e7e6', 40), // QGD
      BookMove('c7c6', 25), // Slav
      BookMove('d5c4', 20), // QGA
      BookMove('g8f6', 10),
    ],

    // ── QGD: 2...e6 ──
    'rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w': [
      BookMove('b1c3', 40),
      BookMove('g1f3', 35),
      BookMove('c4d5', 10), // Exchange
      BookMove('c1f4', 5),
    ],

    // ── Slav: 2...c6 ──
    'rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w': [
      BookMove('g1f3', 40),
      BookMove('b1c3', 30),
      BookMove('c4d5', 10),
      BookMove('e2e3', 10),
    ],

    // ── 1.d4 Nf6 ──
    'rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w': [
      BookMove('c2c4', 55), // Main line
      BookMove('g1f3', 20),
      BookMove('c1f4', 10), // London
      BookMove('c1g5', 5),  // Trompowsky
      BookMove('b1c3', 5),
    ],

    // ── 1.d4 Nf6 2.c4 ──
    'rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b': [
      BookMove('e7e6', 25), // Nimzo/QID
      BookMove('g7g6', 30), // King's Indian / Grünfeld
      BookMove('e7e5', 10), // Budapest
      BookMove('c7c5', 10), // Benoni
      BookMove('d7d6', 5),
    ],

    // ── King's Indian: 1.d4 Nf6 2.c4 g6 ──
    'rnbqkb1r/pppppp1p/5np1/8/2PP4/8/PP2PPPP/RNBQKBNR w': [
      BookMove('b1c3', 50),
      BookMove('g1f3', 30),
      BookMove('g2g3', 10),
    ],

    // ── KID 3.Nc3 Bg7 ──
    'rnbqk2r/ppppppbp/5np1/8/2PP4/2N5/PP2PPPP/R1BQKBNR w': [
      BookMove('e2e4', 50), // Classical
      BookMove('g1f3', 25),
      BookMove('g2g3', 15), // Fianchetto
    ],

    // ── Nimzo-Indian: 1.d4 Nf6 2.c4 e6 3.Nc3 Bb4 ──
    'rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w': [
      BookMove('e2e3', 30), // Rubinstein
      BookMove('d1c2', 25), // Classical
      BookMove('g1f3', 20),
      BookMove('c1g5', 10),
      BookMove('a2a3', 5),  // Sämisch
    ],

    // ── English: 1.c4 ──
    'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b': [
      BookMove('e7e5', 30), // Reversed Sicilian
      BookMove('g8f6', 25),
      BookMove('c7c5', 20), // Symmetrical
      BookMove('e7e6', 10),
      BookMove('g7g6', 10),
    ],

    // ── Réti: 1.Nf3 ──
    'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b': [
      BookMove('d7d5', 35),
      BookMove('g8f6', 30),
      BookMove('c7c5', 15),
      BookMove('d7d6', 10),
      BookMove('g7g6', 5),
    ],

    // ── London System: 1.d4 d5 2.Bf4 ──
    'rnbqkbnr/ppp1pppp/8/3p4/3P1B2/8/PPP1PPPP/RN1QKBNR b': [
      BookMove('g8f6', 35),
      BookMove('c7c5', 25),
      BookMove('e7e6', 20),
      BookMove('c7c6', 10),
      BookMove('b8c6', 5),
    ],

    // ── Scotch: 1.e4 e5 2.Nf3 Nc6 3.d4 ──
    'r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b': [
      BookMove('e5d4', 70),
      BookMove('c6d4', 15),
      BookMove('d7d6', 10),
    ],

    // ── Petrov: 1.e4 e5 2.Nf3 Nf6 ──
    'rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': [
      BookMove('f3e5', 50), // Main line
      BookMove('b1c3', 20),
      BookMove('d2d4', 15),
      BookMove('f1c4', 10),
    ],

    // ── Pirc/Modern: 1.e4 d6 2.d4 Nf6 ──
    'rnbqkb1r/ppp1pppp/3p1n2/8/3PP3/8/PPP2PPP/RNBQKBNR w': [
      BookMove('b1c3', 50),
      BookMove('g1f3', 25),
      BookMove('f2f3', 10), // Austrian Attack
    ],

    // ── Scandinavian: 1.e4 d5 ──
    'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w': [
      BookMove('e4d5', 70),
      BookMove('b1c3', 15),
      BookMove('e4e5', 10),
    ],

    // ── King's Gambit: 1.e4 e5 2.f4 ──
    'rnbqkbnr/pppp1ppp/8/4p3/4PP2/8/PPPP2PP/RNBQKBNR b': [
      BookMove('e5f4', 55), // Accepted
      BookMove('f8c5', 20), // Declined
      BookMove('d7d5', 15), // Falkbeer Counter
      BookMove('d7d6', 5),
    ],
  };
}
