import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'game_state.dart' show ChessVariant;
import 'chess960_castling.dart';
import 'game_tree.dart';
import 'move_analyzer.dart';
import 'pgn.dart';
import 'variants.dart';

enum PieceType { pawn, knight, bishop, rook, queen, king }
enum PieceColor { white, black }

class ChessPiece {
  final PieceType type;
  final PieceColor color;

  ChessPiece(this.type, this.color);

  String get symbol {
    final symbols = {
      PieceType.pawn: 'p',
      PieceType.knight: 'n',
      PieceType.bishop: 'b',
      PieceType.rook: 'r',
      PieceType.queen: 'q',
      PieceType.king: 'k',
    };
    final s = symbols[type]!;
    return color == PieceColor.white ? s.toUpperCase() : s;
  }
}

class ChessGame with ChangeNotifier {
  final chess.Chess _game = chess.Chess();
  late final MoveAnalyzer _analyzer;
  final List<MoveAnnotation> _annotations = [];

  List<String>? _cachedLegalMoves;
  List<List<ChessPiece?>>? _cachedBoard;

  /// Game-over state for the current position.
  ///
  /// Cached because `package:chess`'s `game_over` reaches
  /// `in_threefold_repetition`, which undoes the entire game and regenerates a
  /// FEN for every ply (the package documents it as "costly"). The game screen
  /// asks for it from `build()`, and the screen rebuilds on every clock tick —
  /// so an uncached call replayed the whole game ten times a second, costing
  /// more with every move played.
  bool? _cachedGameOver;
  String? _cachedGameOverReason;

  /// FEN of the current position. `chess.Chess.fen` rebuilds it from the board
  /// on every read, and the screen asks for it several times per rebuild
  /// (opening lookup, board, bookmarks).
  String? _cachedFen;

  void _invalidatePositionCaches() {
    _cachedLegalMoves = null;
    _cachedBoard = null;
    _cachedGameOver = null;
    _cachedGameOverReason = null;
    _cachedFen = null;
  }

  double? _lastEvaluation;
  int? _lastDepth;

  /// Game tree for tracking variations.
  late GameTree _tree;

  /// The game tree (read-only access for UI).
  GameTree get tree => _tree;

  /// Current node in the game tree.
  GameTreeNode get currentNode => _tree.current;

  ChessGame() {
    _analyzer = MoveAnalyzer(_game);
    _tree = GameTree(startFen: _game.fen);
  }

  bool get inCheck => _game.in_check;
  String get currentFEN => _cachedFen ??= _game.fen;
  bool get whiteToMove => _game.turn == chess.Color.WHITE;

  String squareToAlgebraic(int row, int col) {
    return '${String.fromCharCode(97 + col)}${8 - row}';
  }

  /// Get the 8x8 board parsed from the current FEN. Cached and invalidated on move/undo/reset.
  List<List<ChessPiece?>> get board {
    if (_cachedBoard != null) return _cachedBoard!;
    _cachedBoard = _parseBoardFromFen(_game.fen);
    return _cachedBoard!;
  }

  List<List<ChessPiece?>> _parseBoardFromFen(String fen) {
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final parts = fen.split(' ');
    final rows = parts[0].split('/');

    for (int r = 0; r < 8; r++) {
      int c = 0;
      for (var char in rows[r].split('')) {
        int? emptySquares = int.tryParse(char);
        if (emptySquares != null) {
          c += emptySquares;
        } else {
          final color = char == char.toUpperCase() ? PieceColor.white : PieceColor.black;
          final type = _charToType(char.toLowerCase());
          result[r][c] = ChessPiece(type, color);
          c++;
        }
      }
    }
    return result;
  }

  static PieceType _charToType(String char) {
    switch (char) {
      case 'p': return PieceType.pawn;
      case 'n': return PieceType.knight;
      case 'b': return PieceType.bishop;
      case 'r': return PieceType.rook;
      case 'q': return PieceType.queen;
      case 'k': return PieceType.king;
      default: return PieceType.pawn;
    }
  }
  
  /// UCI moves from the start of the game to the current position.
  ///
  /// Read from the game tree, not `chess.Chess.history`: undoing a move
  /// reloads the board from a FEN, and `load()` clears that history. Sourcing
  /// the move list from it meant that after an undo the app told the engine
  /// `position startpos` — the *initial* position — while the board showed
  /// something else entirely. The engine then answered with a move that was
  /// illegal on the real board, `makeMove` rejected it, and the UI sat on
  /// "thinking" forever.
  List<String> get moveHistory => _tree.moveHistory;

  /// Number of half-moves played to reach the current position.
  ///
  /// Cheaper than `moveHistory.length`, which builds the whole list of UCI
  /// strings. Callers on hot paths — the eval-update handler fires several
  /// times a second while the engine searches — only want the count.
  int get plyCount => _tree.current.ply;

  /// Whether any move has been played from the starting position.
  bool get hasMoves => plyCount > 0;

  List<MoveAnnotation> get annotations => _annotations;
  MoveAnnotation? get lastAnnotation => _annotations.isEmpty ? null : _annotations.last;

  /// The UCI `position` command for the current position.
  ///
  /// Anchored to the tree's starting FEN, so games that did not start from the
  /// initial position — Chess960, a position loaded from FEN, a puzzle — are
  /// described correctly instead of being passed off as `startpos`.
  String get positionCommand {
    final moves = moveHistory;
    final start = _tree.root.fen;
    final base = start == _standardStartFen
        ? 'position startpos'
        : 'position fen $start';
    return moves.isEmpty ? base : '$base moves ${moves.join(' ')}';
  }

  static const String _standardStartFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  
  List<String> getLegalMoves() {
    _cachedLegalMoves ??= [
      ..._game.generate_moves().map(
          (m) => '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ""}'),
      // package:chess hardcodes castling to a king on e1/e8, so in a shuffled
      // position it offers none — the player just cannot castle. Added here
      // rather than by forking the library.
      if (variant == ChessVariant.chess960)
        ...chess960Castles(_game).map((c) => c.uci),
    ];
    return _cachedLegalMoves!;
  }
  
  /// Update evaluation from Stockfish
  void updateEvaluation(double evaluation, String bestMove, int depth) {
    _lastEvaluation = evaluation;
    _lastDepth = depth;
    
    // If we have a pending annotation without complete evaluation, update it
    if (_annotations.isNotEmpty) {
      final last = _annotations.last;
      // Check if this is an incomplete annotation (has scoreBefore but scoreAfter is 0)
      if (last.evaluation.scoreBefore != 0.0 && 
          last.evaluation.scoreAfter == 0.0 && 
          last.evaluation.bestMove.isEmpty) {
        _completeLastAnnotation(evaluation, bestMove, depth);
      }
    }
  }
  
  
  /// Make a move and create initial annotation
  bool makeMove(String uciMove) {
  if (uciMove.length < 4) return false;
  
  final from = uciMove.substring(0, 2);
  final to = uciMove.substring(2, 4);
  final promotion = uciMove.length > 4 ? uciMove.substring(4, 5) : null;
  
  // Store evaluation BEFORE making the move AND whose turn it is
  final evalBefore = _lastEvaluation ?? 0.0;
  final whiteToMove = _game.turn == chess.Color.WHITE;  // ADD THIS
  
  // Chess960 castling, which package:chess cannot play: apply it by loading the
  // resulting position. Handled before the normal path because the library
  // would reject the move outright.
  if (variant == ChessVariant.chess960) {
    final castled = applyChess960Castle(_game, uciMove);
    if (castled != null) {
      final wasWhite = _game.turn == chess.Color.WHITE;
      if (!_game.load(castled)) return false;
      _invalidatePositionCaches();
      final node = _tree.addMove(
        uci: uciMove,
        // O-O / O-O-O by destination file, as the PGN spec has it.
        san: uciMove[2] == 'g' ? 'O-O' : 'O-O-O',
        fen: _game.fen,
      );
      node.eval = _lastEvaluation;
      _annotations.add(_analyzer.analyzeMove(
        uciMove: uciMove,
        evaluation: MoveEvaluation(
          scoreBefore: evalBefore,
          scoreAfter: 0.0,
          bestMove: '',
          bestMoveScore: 0.0,
          depth: _lastDepth ?? 10,
          whiteToMove: wasWhite,
        ),
      ));
      if (_annotations.length > 500) _annotations.removeAt(0);
      notifyListeners();
      return true;
    }
  }

  // SAN has to be produced from the position *before* the move (that is what
  // disambiguates it), so take it here rather than re-deriving the whole game's
  // notation afterwards.
  final san = _sanForUci(from, to, promotion) ?? uciMove;

  // Make the move in the main game
  bool success = _game.move({
    'from': from, 
    'to': to, 
    'promotion': promotion
  });
  
  if (success) {
    _invalidatePositionCaches();

    // Track three-check counts
    if (variant == ChessVariant.threeCheck && _game.in_check) {
      // The side that just moved gave check
      if (whiteToMove) whiteChecks++;
      else blackChecks++;
    }

    // Update game tree — adds as child or navigates into existing
    final node = _tree.addMove(uci: uciMove, san: san, fen: _game.fen);
    node.eval = _lastEvaluation;

    // Create INCOMPLETE annotation with temporary evaluation
    final tempEval = MoveEvaluation(
      scoreBefore: evalBefore,
      scoreAfter: 0.0,
      bestMove: '',
      bestMoveScore: 0.0,
      depth: _lastDepth ?? 10,
      whiteToMove: whiteToMove,
    );

    final annotation = _analyzer.analyzeMove(
      uciMove: uciMove,
      evaluation: tempEval,
    );

    node.annotation = annotation;
    _annotations.add(annotation);
    // Cap annotations to prevent unbounded memory growth
    if (_annotations.length > 500) _annotations.removeAt(0);
    notifyListeners();
  }

  return success;
}

void _completeLastAnnotation(double evalAfter, String bestMove, int depth) {
  if (_annotations.isEmpty) return;
  
  final incomplete = _annotations.last;
  final evalBefore = incomplete.evaluation.scoreBefore;
  final whiteToMove = incomplete.evaluation.whiteToMove;  // GET THIS
  
  // Create complete MoveEvaluation
  final completeEval = MoveEvaluation(
    scoreBefore: evalBefore,
    scoreAfter: evalAfter,
    bestMove: bestMove,
    bestMoveScore: evalAfter,
    depth: depth,
    whiteToMove: whiteToMove,  // ADD THIS
  );
  
  // Re-analyze with complete evaluation
  final completeAnnotation = _analyzer.analyzeMove(
    uciMove: incomplete.move,
    evaluation: completeEval,
  );
  
  _annotations[_annotations.length - 1] = completeAnnotation;
}
  
  bool _resigned = false;
  bool _drawAgreed = false;

  /// Active variant mode.
  ChessVariant variant = ChessVariant.standard;

  /// Three-check: count of checks given by each side.
  int whiteChecks = 0;
  int blackChecks = 0;

  bool get isGameOver => _cachedGameOver ??= _computeGameOver();

  bool _computeGameOver() {
    if (_resigned || _drawAgreed) return true;
    if (_game.game_over) return true;
    // Variant win conditions
    if (variant == ChessVariant.kingOfTheHill && checkKothWin(_game.fen)) return true;
    if (variant == ChessVariant.threeCheck && checkThreeCheckWin(whiteChecks, blackChecks)) return true;
    return false;
  }

  String get gameOverReason => _cachedGameOverReason ??= _computeGameOverReason();

  String _computeGameOverReason() {
    if (_resigned) return 'Resignation';
    if (_drawAgreed) return 'Draw by agreement';
    if (variant == ChessVariant.kingOfTheHill && checkKothWin(_game.fen)) {
      return 'King of the Hill';
    }
    if (variant == ChessVariant.threeCheck && checkThreeCheckWin(whiteChecks, blackChecks)) {
      return 'Three-check';
    }
    if (_game.in_checkmate) return 'Checkmate';
    if (_game.in_stalemate) return 'Stalemate';
    if (_game.in_threefold_repetition) return 'Draw — threefold repetition';
    if (_game.insufficient_material) return 'Draw — insufficient material';
    if (_game.in_draw) return 'Draw — fifty-move rule';
    return 'Game Over';
  }

  /// Detailed explanation for the game-over reason.
  String get gameOverExplanation {
    if (_game.in_stalemate) {
      return 'The side to move has no legal moves but is not in check. '
             'This is a draw. To win, you need to deliver checkmate — '
             'trapping the king while also putting it in check.';
    }
    if (_game.insufficient_material) {
      return 'Neither side has enough pieces to force checkmate.';
    }
    if (_game.in_threefold_repetition) {
      return 'The same position occurred three times.';
    }
    return '';
  }

  String? get winner {
    if (_drawAgreed || _game.in_stalemate || _game.in_draw) return null;
    if (_resigned) {
      return whiteToMove ? 'Black' : 'White';
    }
    if (variant == ChessVariant.kingOfTheHill) {
      final w = kothWinner(_game.fen);
      if (w != null) return w;
    }
    if (variant == ChessVariant.threeCheck) {
      if (whiteChecks >= 3) return 'White';
      if (blackChecks >= 3) return 'Black';
    }
    if (!_game.in_checkmate) return null;
    return _game.turn == chess.Color.WHITE ? 'Black' : 'White';
  }

  /// Player resigns.
  void resign() {
    _resigned = true;
    _invalidatePositionCaches();
    notifyListeners();
  }

  /// Agree to a draw.
  void agreeToDraw() {
    _drawAgreed = true;
    _invalidatePositionCaches();
    notifyListeners();
  }

  /// Get move history in SAN notation (e.g., "e4", "Nf3", "O-O").
  ///
  /// Read from the tree, where each node's SAN was computed once when the move
  /// was played. It used to re-derive the whole list from `chess.pgn()` on
  /// every call — which undoes and replays the entire game, generating legal
  /// moves several times per ply for disambiguation and check marks. The game
  /// screen calls this from `build()`, so that cost was paid on every rebuild
  /// and grew with every move played. It was also wrong after an undo: `load()`
  /// leaves PGN headers behind, which the regex parsed as "moves".
  List<String> get moveHistorySan => _tree.currentPath
      .map((n) => n.san ?? n.move ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  
  /// SAN for a move about to be played from the current position, or null if
  /// no legal move matches.
  String? _sanForUci(String from, String to, String? promotion) {
    for (final m in _game.generate_moves()) {
      if (m.fromAlgebraic == from &&
          m.toAlgebraic == to &&
          (promotion == null || m.promotion?.name == promotion)) {
        return _game.move_to_san(m);
      }
    }
    return null;
  }

  void undoMove() {
    if (_tree.atStart) return;
    _tree.goBack();
    _game.load(_tree.current.fen);
    _invalidatePositionCaches();
    if (_annotations.isNotEmpty) {
      _annotations.removeLast();
    }
    notifyListeners();
  }

  /// Redo: go forward in the main line (if there are children).
  bool redoMove() {
    if (_tree.atEnd) return false;
    _tree.goForward();
    _game.load(_tree.current.fen);
    _invalidatePositionCaches();
    notifyListeners();
    return true;
  }

  /// Whether redo is available.
  bool get canRedo => !_tree.atEnd;

  /// Whether undo is available.
  bool get canUndo => !_tree.atStart;

  /// Navigate to a specific node in the game tree.
  /// Reloads the chess position from the node's FEN.
  void goToNode(GameTreeNode node) {
    _game.load(node.fen);
    _tree.goTo(node);
    _invalidatePositionCaches();
    notifyListeners();
  }

  /// Go forward one move in the main line.
  bool goForward() {
    if (_tree.atEnd) return false;
    _tree.goForward();
    _game.load(_tree.current.fen);
    _invalidatePositionCaches();
    notifyListeners();
    return true;
  }

  /// Enter a specific variation at the current position.
  bool enterVariation(int index) {
    if (!_tree.enterVariation(index)) return false;
    _game.load(_tree.current.fen);
    _invalidatePositionCaches();
    notifyListeners();
    return true;
  }
  
  /// Export current game as PGN string.
  /// Uses RAV notation if the game tree has variations.
  String toPgn({String engineName = 'Engine', bool playAsBlack = false}) {
    final now = DateTime.now();
    final date = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}';
    final headers = PgnHeaders(
      date: date,
      white: playAsBlack ? engineName : 'Human',
      black: playAsBlack ? 'Human' : engineName,
      result: gameResult(_game),
    );

    // Exported from the tree, not from `chess.Chess`: the latter's history is
    // cleared by every takeback (undo reloads the board from a FEN), so an
    // export after an undo produced headers and no moves at all. The tree also
    // carries the real starting position and any variations.
    return exportPgnFromTree(tree: _tree, headers: headers);
  }

  /// Load a game from PGN. Returns true on success.
  bool loadPgn(String pgnText) {
    final loaded = importPgn(pgnText);
    if (loaded == null) return false;

    _invalidatePositionCaches();
    // Replace the game state — chess package doesn't support direct assignment
    // so we reset and replay
    _game.reset();
    _annotations.clear();
    _lastEvaluation = null;
    _lastDepth = null;

    // Load the PGN into our game instance
    final moveText = pgnText.split('\n')
        .where((l) => !l.trim().startsWith('[') && l.trim().isNotEmpty)
        .join(' ')
        .trim();
    if (moveText.isNotEmpty) {
      _game.load_pgn(moveText);
    }

    // Rebuild the tree from what was loaded. The tree is the source of truth
    // for the move list, the notation and the engine's position command, so
    // leaving it pointing at the previous game would describe the wrong game
    // to the engine. Replaying through makeMove also fills in SAN and
    // annotations exactly as if the moves had been played.
    final replay = _game.history
        .map((h) =>
            '${h.move.fromAlgebraic}${h.move.toAlgebraic}${h.move.promotion?.name ?? ''}')
        .toList();
    _game.reset();
    _invalidatePositionCaches();
    _tree = GameTree(startFen: _game.fen);
    _annotations.clear();
    for (final uci in replay) {
      makeMove(uci);
    }

    _invalidatePositionCaches();
    notifyListeners();
    return true;
  }

  /// Load a position from a FEN string. Returns true on success.
  bool loadFen(String fen) {
    final ok = _game.load(fen);
    if (!ok) return false;

    _invalidatePositionCaches();
    _annotations.clear();
    _lastEvaluation = null;
    _lastDepth = null;
    _resigned = false;
    _drawAgreed = false;
    whiteChecks = 0;
    blackChecks = 0;
    _tree = GameTree(startFen: fen);
    notifyListeners();
    return true;
  }

  void reset() {
    _invalidatePositionCaches();
    _game.reset();
    _annotations.clear();
    _lastEvaluation = null;
    _lastDepth = null;
    _resigned = false;
    _drawAgreed = false;
    whiteChecks = 0;
    blackChecks = 0;
    _tree = GameTree(startFen: _game.fen);
    notifyListeners();
  }
}