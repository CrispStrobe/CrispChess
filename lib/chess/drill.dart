/// Structured chess drill system.
///
/// A drill is a series of positions with correct moves and
/// coaching messages. Supports branching for common mistakes.

/// A single step in a drill lesson.
class DrillStep {
  /// FEN of the position.
  final String fen;

  /// The correct move (UCI).
  final String correctMove;

  /// Coach message shown before the player moves.
  final String? hint;

  /// Coach message shown after the correct move.
  final String? explanation;

  /// Messages for common incorrect moves (UCI → message).
  final Map<String, String> wrongMoveMessages;

  const DrillStep({
    required this.fen,
    required this.correctMove,
    this.hint,
    this.explanation,
    this.wrongMoveMessages = const {},
  });
}

/// A complete drill lesson.
class Drill {
  final String id;
  final String title;
  final String description;
  final String category; // opening, middlegame, endgame, tactics
  final List<DrillStep> steps;

  const Drill({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.steps,
  });
}

/// Built-in drills covering key chess concepts.
final builtInDrills = <Drill>[
  Drill(
    id: 'back_rank_mate',
    title: 'Back Rank Mate',
    description: 'Learn to deliver checkmate on the back rank.',
    category: 'tactics',
    steps: [
      DrillStep(
        fen: '6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1',
        correctMove: 'e1e8',
        hint: 'The black king is trapped behind its own pawns. Can you deliver checkmate?',
        explanation: 'Re8# is checkmate! The king cannot escape because its own pawns block the retreat.',
      ),
      DrillStep(
        fen: '3r2k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
        correctMove: 'a1a8',
        hint: 'Another back rank pattern. The rook can deliver mate in one.',
        explanation: 'Ra8# — same pattern, different file. Always look for back rank weakness!',
      ),
    ],
  ),
  Drill(
    id: 'pin_tactics',
    title: 'Pin Tactics',
    description: 'Use pins to win material.',
    category: 'tactics',
    steps: [
      DrillStep(
        fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 2 3',
        correctMove: 'f3g5',
        hint: 'Attack the weak f7 pawn. Which piece should move?',
        explanation: 'Ng5 threatens Nxf7 (forking queen and rook) and also eyes the pin on f7.',
        wrongMoveMessages: {
          'd2d4': 'd4 is a reasonable move but misses the tactical opportunity on f7.',
        },
      ),
    ],
  ),
  Drill(
    id: 'king_pawn_endgame',
    title: 'King and Pawn Endgames',
    description: 'Master the opposition and pawn promotion.',
    category: 'endgame',
    steps: [
      DrillStep(
        fen: '8/8/8/8/4k3/8/4P3/4K3 w - - 0 1',
        correctMove: 'e1d2',
        hint: 'You need to advance your pawn, but first gain the opposition.',
        explanation: 'Kd2 starts the king march to support the pawn. Direct e3 or e4 allows Black to gain opposition.',
        wrongMoveMessages: {
          'e2e4': 'e4+? After Ke5, Black has the opposition and can blockade the pawn.',
          'e2e3': 'e3? allows Black to take the opposition with Ke5.',
        },
      ),
    ],
  ),
  Drill(
    id: 'italian_opening',
    title: 'Italian Game Basics',
    description: 'Learn the key moves of the Italian Opening.',
    category: 'opening',
    steps: [
      DrillStep(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        correctMove: 'e2e4',
        hint: 'Start with the most popular opening move — control the center!',
        explanation: '1. e4 controls the center and opens lines for the bishop and queen.',
      ),
      DrillStep(
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        correctMove: 'e7e5',
        hint: 'Black responds symmetrically.',
        explanation: '1...e5 — the Open Game. Both sides contest the center.',
      ),
      DrillStep(
        fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
        correctMove: 'g1f3',
        hint: 'Develop a knight toward the center. Which square is best?',
        explanation: '2. Nf3 develops with tempo — attacking the e5 pawn.',
      ),
      DrillStep(
        fen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2',
        correctMove: 'b8c6',
        hint: 'Defend the e5 pawn with a developing move.',
        explanation: '2...Nc6 defends e5 and develops toward the center.',
      ),
      DrillStep(
        fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
        correctMove: 'f1c4',
        hint: 'Develop the bishop to its most active diagonal.',
        explanation: '3. Bc4 — the Italian Game! The bishop targets the weak f7 square.',
      ),
    ],
  ),
  // --- Endgame drills ---
  Drill(
    id: 'kq_vs_k',
    title: 'King + Queen vs King',
    description: 'Drive the lone king to the edge and deliver checkmate.',
    category: 'endgame',
    steps: [
      DrillStep(
        fen: '8/8/8/4k3/8/8/8/4KQ2 w - - 0 1',
        correctMove: 'f1f5',
        hint: 'Restrict the enemy king. Cut off escape squares with the queen.',
        explanation: 'Qf5+ pushes the king toward the edge. In Q vs K, use the queen to restrict, then bring your king close.',
      ),
      DrillStep(
        fen: '8/8/8/4kQ2/8/8/8/4K3 b - - 1 1',
        correctMove: 'e5d4',
        hint: 'Black must move. The king tries to stay central.',
        explanation: 'Kd4 — the king tries to stay in the center, but the queen controls too many squares.',
      ),
      DrillStep(
        fen: '8/8/8/5Q2/3k4/8/8/4K3 w - - 2 2',
        correctMove: 'e1d2',
        hint: 'Bring your king closer to help deliver mate. The queen alone cannot force mate.',
        explanation: 'Kd2 — the key principle: the king must help! Walk your king toward the opponent\'s king.',
      ),
    ],
  ),
  Drill(
    id: 'kr_vs_k',
    title: 'King + Rook vs King',
    description: 'Use the rook to cut off ranks and files, then deliver checkmate.',
    category: 'endgame',
    steps: [
      DrillStep(
        fen: '8/8/8/4k3/8/8/8/R3K3 w - - 0 1',
        correctMove: 'a1a5',
        hint: 'Cut off the king! Place the rook on the 5th rank to restrict the king.',
        explanation: 'Ra5 cuts the king off from ranks 1-4. Now bring your king up to help.',
      ),
      DrillStep(
        fen: '8/8/8/R3k3/8/8/8/4K3 b - - 1 1',
        correctMove: 'e5e6',
        hint: 'Black\'s king retreats.',
        explanation: 'Ke6 — the king moves up, but it\'s confined to ranks 5-8.',
      ),
      DrillStep(
        fen: '8/8/4k3/R7/8/8/8/4K3 w - - 2 2',
        correctMove: 'e1d2',
        hint: 'March your king forward. The rook holds the barrier.',
        explanation: 'Kd2 — step by step, bring the king to the 6th rank to assist the rook.',
      ),
    ],
  ),
  Drill(
    id: 'kp_vs_k_basic',
    title: 'King + Pawn vs King (Basic)',
    description: 'Learn the key squares and opposition to promote your pawn.',
    category: 'endgame',
    steps: [
      DrillStep(
        fen: '8/8/8/3k4/8/4K3/4P3/8 w - - 0 1',
        correctMove: 'e3d3',
        hint: 'Take the opposition! Place your king directly facing the enemy king.',
        explanation: 'Kd3 takes the opposition — kings face each other with one square between. This is the key to K+P endings.',
        wrongMoveMessages: {
          'e2e4': 'e4? allows Ke5 and Black gets the opposition, drawing.',
          'e3f4': 'Kf4? sidesteps — Black plays Ke6 and draws.',
        },
      ),
      DrillStep(
        fen: '8/8/8/3k4/8/3K4/4P3/8 b - - 1 1',
        correctMove: 'd5e5',
        hint: 'Black tries to block the pawn.',
        explanation: 'Ke5 opposes the white king, but White has the move.',
      ),
      DrillStep(
        fen: '8/8/8/4k3/8/3K4/4P3/8 w - - 2 2',
        correctMove: 'e2e4',
        hint: 'Now advance the pawn! Black has stepped aside.',
        explanation: 'e4! Now the pawn advances with the king\'s support. The key: advance the pawn only when you have the opposition.',
      ),
    ],
  ),
  Drill(
    id: 'two_bishops_mate',
    title: 'Two Bishops Checkmate',
    description: 'Coordinate two bishops to force the king to the corner.',
    category: 'endgame',
    steps: [
      DrillStep(
        fen: '8/8/8/4k3/8/8/8/2B1KB2 w - - 0 1',
        correctMove: 'c1d2',
        hint: 'Step 1: Centralize your king. The bishops need the king\'s help.',
        explanation: 'Kd2 begins the king march. Two bishops control diagonals — you need the king to push the enemy to the corner.',
      ),
      DrillStep(
        fen: '8/8/8/4k3/8/8/3K4/2B2B2 b - - 1 1',
        correctMove: 'e5d5',
        hint: 'Black tries to stay central.',
        explanation: 'Kd5 — reasonable. But the two bishops will gradually restrict the king.',
      ),
      DrillStep(
        fen: '8/8/8/3k4/8/8/3K4/2B2B2 w - - 2 2',
        correctMove: 'd2e3',
        hint: 'Keep advancing the king. Build a wall with the bishops behind.',
        explanation: 'Ke3 — the king is now centralized. Next: position the bishops on long diagonals to create a shrinking box.',
      ),
    ],
  ),
];
