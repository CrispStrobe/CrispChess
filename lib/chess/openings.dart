/// ECO opening name lookup — maps FEN positions to opening names.
///
/// Contains ~50 common openings. The lookup uses the piece placement
/// + side to move (ignoring castling/EP/move counters) for matching.

const Map<String, String> _openings = {
  // Starting position
  'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w': 'Starting Position',

  // King's Pawn
  'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b': "King's Pawn (e4)",
  'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w': 'Open Game (1.e4 e5)',

  // Italian / Ruy Lopez
  'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': "King's Knight Opening",
  'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b': 'Ruy Lopez',
  'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b': 'Italian Game',
  'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w': 'Giuoco Piano',
  'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w': 'Two Knights Defense',

  // Scotch / Petrov
  'r1bqkbnr/pppp1ppp/2n5/4p3/3PP3/5N2/PPP2PPP/RNBQKB1R b': 'Scotch Game',
  'rnbqkb1r/pppp1ppp/5n2/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w': "Petrov's Defense",

  // Sicilian
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w': 'Sicilian Defense',
  'rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKB1R b': 'Open Sicilian',
  'rnbqkbnr/pp2pppp/3p4/2p5/3PP3/5N2/PPP2PPP/RNBQKB1R b': 'Sicilian (2...d6)',
  'rnbqkbnr/pp2pppp/3p4/8/3NP3/8/PPP2PPP/RNBQKB1R b': 'Sicilian Open',
  'rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w': 'Sicilian Najdorf',

  // French
  'rnbqkbnr/pppp1ppp/4p3/8/4P3/8/PPPP1PPP/RNBQKBNR w': 'French Defense',
  'rnbqkbnr/ppp2ppp/4p3/3p4/3PP3/8/PPP2PPP/RNBQKBNR w': 'French (2...d5)',

  // Caro-Kann
  'rnbqkbnr/pp1ppppp/2p5/8/4P3/8/PPPP1PPP/RNBQKBNR w': 'Caro-Kann Defense',

  // Scandinavian
  'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w': 'Scandinavian Defense',

  // Queen's Pawn
  'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b': "Queen's Pawn (d4)",
  'rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w': "Queen's Pawn Game",
  'rnbqkbnr/ppp1pppp/8/3p4/2PP4/8/PP2PPPP/RNBQKBNR b': "Queen's Gambit",
  'rnbqkbnr/ppp2ppp/4p3/3p4/2PP4/8/PP2PPPP/RNBQKBNR w': "Queen's Gambit Declined",
  'rnbqkbnr/pp2pppp/2p5/3p4/2PP4/8/PP2PPPP/RNBQKBNR w': 'Slav Defense',

  // Indian
  'rnbqkb1r/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w': 'Indian Defense',
  'rnbqkb1r/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b': 'Indian (2.c4)',
  'rnbqk2r/ppppppbp/5np1/8/2PP4/2N5/PP2PPPP/R1BQKBNR w': "King's Indian Defense",
  'rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w': 'Nimzo-Indian Defense',
  'rnbqkb1r/pppp1ppp/4pn2/8/2PP4/8/PP2PPPP/RNBQKBNR w': "Queen's Indian / Nimzo",

  // English / Réti
  'rnbqkbnr/pppppppp/8/8/2P5/8/PP1PPPPP/RNBQKBNR b': 'English Opening',
  'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b': 'Réti Opening',

  // London
  'rnbqkbnr/ppp1pppp/8/3p4/3P1B2/8/PPP1PPPP/RN1QKBNR b': 'London System',

  // King's Gambit
  'rnbqkbnr/pppp1ppp/8/4p3/4PP2/8/PPPP2PP/RNBQKBNR b': "King's Gambit",

  // Pirc / Modern
  'rnbqkbnr/ppp1pppp/3p4/8/4P3/8/PPPP1PPP/RNBQKBNR w': 'Pirc/Modern Defense',
  'rnbqkbnr/pppppp1p/6p1/8/4P3/8/PPPP1PPP/RNBQKBNR w': 'Modern Defense',
};

/// Look up the opening name for a FEN position.
/// Returns null if the position is not a known opening.
String? lookupOpening(String fen) {
  final parts = fen.split(' ');
  if (parts.length < 2) return null;
  final key = '${parts[0]} ${parts[1]}';
  return _openings[key];
}
