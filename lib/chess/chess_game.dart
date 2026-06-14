import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';
import 'game_state.dart' show ChessVariant;
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
  String get currentFEN => _game.fen;
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
  
  List<String> get moveHistory => _game.history
      .map((m) => '${m.move.fromAlgebraic}${m.move.toAlgebraic}${m.move.promotion?.name ?? ""}')
      .toList();
  
  List<MoveAnnotation> get annotations => _annotations;
  MoveAnnotation? get lastAnnotation => _annotations.isEmpty ? null : _annotations.last;
  
  String get positionCommand {
    final cmd = moveHistory.isEmpty 
        ? 'position startpos' 
        : 'position startpos moves ${moveHistory.join(' ')}';
    return cmd;
  }
  
  List<String> getLegalMoves() {
    _cachedLegalMoves ??= _game.generate_moves()
        .map((m) => '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ""}')
        .toList();
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
  
  // Make the move in the main game
  bool success = _game.move({
    'from': from, 
    'to': to, 
    'promotion': promotion
  });
  
  if (success) {
    _cachedLegalMoves = null;
    _cachedBoard = null;

    // Track three-check counts
    if (variant == ChessVariant.threeCheck && _game.in_check) {
      // The side that just moved gave check
      if (whiteToMove) whiteChecks++;
      else blackChecks++;
    }

    // Get SAN from the last move in the chess history
    final sanList = moveHistorySan;
    final san = sanList.isNotEmpty ? sanList.last : uciMove;

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

  bool get isGameOver {
    if (_game.game_over || _resigned || _drawAgreed) return true;
    // Variant win conditions
    if (variant == ChessVariant.kingOfTheHill && checkKothWin(_game.fen)) return true;
    if (variant == ChessVariant.threeCheck && checkThreeCheckWin(whiteChecks, blackChecks)) return true;
    return false;
  }

  String get gameOverReason {
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
    notifyListeners();
  }

  /// Agree to a draw.
  void agreeToDraw() {
    _drawAgreed = true;
    notifyListeners();
  }

  /// Get move history in SAN notation (e.g., "e4", "Nf3", "O-O").
  List<String> get moveHistorySan {
    final pgn = _game.pgn();
    if (pgn.isEmpty) return [];
    // PGN format: "1. e4 e5 2. Nf3 Nc6 *"
    final results = {'1-0', '0-1', '1/2-1/2', '*'};
    return pgn
        .replaceAll(RegExp(r'\d+\.+\s*'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty && !results.contains(s))
        .toList();
  }
  
  void undoMove() {
    if (_tree.atStart) return;
    _tree.goBack();
    _game.load(_tree.current.fen);
    _cachedLegalMoves = null;
    _cachedBoard = null;
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
    _cachedLegalMoves = null;
    _cachedBoard = null;
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
    _cachedLegalMoves = null;
    _cachedBoard = null;
    notifyListeners();
  }

  /// Go forward one move in the main line.
  bool goForward() {
    if (_tree.atEnd) return false;
    _tree.goForward();
    _game.load(_tree.current.fen);
    _cachedLegalMoves = null;
    _cachedBoard = null;
    notifyListeners();
    return true;
  }

  /// Enter a specific variation at the current position.
  bool enterVariation(int index) {
    if (!_tree.enterVariation(index)) return false;
    _game.load(_tree.current.fen);
    _cachedLegalMoves = null;
    _cachedBoard = null;
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

    // Use RAV export if tree has any variations
    final hasVariations = _tree.root.mainLine.any((n) => n.parent?.hasVariations ?? false);
    if (hasVariations) {
      return exportPgnWithVariations(tree: _tree, headers: headers);
    }

    return exportPgn(game: _game, headers: headers);
  }

  /// Load a game from PGN. Returns true on success.
  bool loadPgn(String pgnText) {
    final loaded = importPgn(pgnText);
    if (loaded == null) return false;

    _cachedLegalMoves = null;
    _cachedBoard = null;
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

    _cachedBoard = null;
    _cachedLegalMoves = null;
    notifyListeners();
    return true;
  }

  /// Load a position from a FEN string. Returns true on success.
  bool loadFen(String fen) {
    final ok = _game.load(fen);
    if (!ok) return false;

    _cachedLegalMoves = null;
    _cachedBoard = null;
    _annotations.clear();
    _lastEvaluation = null;
    _lastDepth = null;
    _resigned = false;
    _drawAgreed = false;
    _tree = GameTree(startFen: fen);
    notifyListeners();
    return true;
  }

  void reset() {
    _cachedLegalMoves = null;
    _cachedBoard = null;
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