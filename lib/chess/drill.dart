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
];
