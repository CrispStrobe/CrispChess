import 'package:chess/chess.dart' as chess;

enum MoveQuality {
  brilliant,    // !!
  good,         // !
  interesting,  // !?
  dubious,      // ?!
  mistake,      // ?
  blunder,      // ??
  neutral,
}

class MoveEvaluation {
  final double scoreBefore;
  final double scoreAfter;
  final String bestMove;
  final double bestMoveScore;
  final int depth;
  final bool whiteToMove;  // track whose turn it was
  
  MoveEvaluation({
    required this.scoreBefore,
    required this.scoreAfter,
    required this.bestMove,
    required this.bestMoveScore,
    required this.depth,
    required this.whiteToMove,
  });
  
  // Centipawn loss from the perspective of the player who moved
  double get centipawnLoss {
    if (whiteToMove) {
      // White moved: if eval decreased, that's a loss for White
      final loss = scoreBefore - scoreAfter;
      return loss > 0 ? loss : 0; // Only count actual losses
    } else {
      // Black moved: if eval increased (more positive), that's a loss for Black
      final loss = scoreAfter - scoreBefore;
      return loss > 0 ? loss : 0; // Only count actual losses
    }
  }
  
  // Get the actual change (can be negative if position improved)
  double get evaluationChange {
    if (whiteToMove) {
      return scoreBefore - scoreAfter;  // Negative = improvement for White
    } else {
      return scoreAfter - scoreBefore;  // Negative = improvement for Black
    }
  }
  
  MoveQuality get quality {
    final change = evaluationChange;
    
    // If move IMPROVED position significantly
    if (change < -1.0) {
      return MoveQuality.brilliant;
    }
    
    // If move improved position slightly or maintained it
    if (change < 0.3) {
      return MoveQuality.good;
    }
    
    // Standard thresholds for mistakes (positive change = loss)
    if (change < 0.5) return MoveQuality.neutral;
    if (change < 1.0) return MoveQuality.interesting;
    if (change < 2.0) return MoveQuality.dubious;
    if (change < 3.0) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }
  
  String get symbol {
    switch (quality) {
      case MoveQuality.brilliant: return '‼️';
      case MoveQuality.good: return '❗';
      case MoveQuality.interesting: return '⁉️';
      case MoveQuality.dubious: return '⁈';
      case MoveQuality.mistake: return '❓';
      case MoveQuality.blunder: return '⁉️⁉️';
      case MoveQuality.neutral: return '';
    }
  }
}

class TacticalPattern {
  final String name;
  final String description;
  final List<String> involvedSquares;
  
  TacticalPattern({
    required this.name,
    required this.description,
    this.involvedSquares = const [],
  });
}

/// Serializable request for isolate-based move analysis.
class AnalysisRequest {
  final String fen;
  final String uciMove;
  final MoveEvaluation evaluation;

  AnalysisRequest({
    required this.fen,
    required this.uciMove,
    required this.evaluation,
  });
}

/// Top-level function suitable for use with `compute()`.
/// Creates a fresh MoveAnalyzer from a FEN string and analyzes the move.
MoveAnnotation analyzeInIsolate(AnalysisRequest request) {
  final game = chess.Chess.fromFEN(request.fen);
  final analyzer = MoveAnalyzer(game);
  return analyzer.analyzeMove(
    uciMove: request.uciMove,
    evaluation: request.evaluation,
  );
}

class MoveAnalyzer {
  chess.Chess game;

  // Reverse lookup: integer index -> algebraic notation
  late final Map<int, String> _indexToSquare;

  MoveAnalyzer(this.game) {
    _indexToSquare = {};
    for (var entry in chess.Chess.SQUARES.entries) {
      _indexToSquare[entry.value] = entry.key;
    }
  }

  /// Convert integer square index to algebraic notation
  String? _squareFromIndex(int index) {
    return _indexToSquare[index];
  }

  /// Analyze a move with evaluation data from Stockfish
  MoveAnnotation analyzeMove({
    required String uciMove,
    required MoveEvaluation evaluation,
  }) {
    final tactics = _detectTactics(uciMove);
    final positional = _analyzePositionalThemes(uciMove);
    final phase = _getGamePhase();
    
    return MoveAnnotation(
      move: uciMove,
      evaluation: evaluation,
      tactics: tactics,
      positionalThemes: positional,
      gamePhase: phase,
    );
  }
  
  /// Detect tactical patterns
  List<TacticalPattern> _detectTactics(String uciMove) {
    final patterns = <TacticalPattern>[];
    final from = uciMove.substring(0, 2);
    final to = uciMove.substring(2, 4);
    
    // Check for captures
    final isCapture = _isCapture(from, to);
    if (isCapture) {
      // Check if it's a trade or winning material
      final materialDiff = _getMaterialDifference(from, to);
      if (materialDiff > 0) {
        patterns.add(TacticalPattern(
          name: 'Material Gain',
          description: 'Winning material worth ${materialDiff.toStringAsFixed(0)} points',
          involvedSquares: [from, to],
        ));
      }
    }
    
    // Check for checks
    if (game.in_check) {
      patterns.add(TacticalPattern(
        name: 'Check',
        description: 'Forcing move that puts the king in danger',
        involvedSquares: [to],
      ));
    }
    
    // Detect pins
    final pin = _detectPin(to);
    if (pin != null) patterns.add(pin);
    
    // Detect forks
    final fork = _detectFork(to);
    if (fork != null) patterns.add(fork);
    
    // Castling
    if (_isCastling(from, to)) {
      patterns.add(TacticalPattern(
        name: 'Castling',
        description: 'King safety and rook development',
      ));
    }
    
    return patterns;
  }
  
  /// Analyze positional themes
  List<String> _analyzePositionalThemes(String uciMove) {
    final themes = <String>[];
    final to = uciMove.substring(2, 4);
    
    // Center control
    if (_isCentralSquare(to)) {
      themes.add('Center Control: Occupying key central squares');
    }
    
    // Piece development
    if (_isDevelopmentMove(uciMove)) {
      themes.add('Development: Activating pieces from starting squares');
    }
    
    // Pawn structure
    final pawnStructure = _analyzePawnStructure();
    if (pawnStructure.isNotEmpty) {
      themes.add(pawnStructure);
    }
    
    // King safety
    final kingSafety = _analyzeKingSafety();
    if (kingSafety.isNotEmpty) {
      themes.add(kingSafety);
    }
    
    return themes;
  }
  
  bool _isCapture(String from, String to) {
    final toSquare = chess.Chess.SQUARES[to];
    if (toSquare == null) return false;
    return game.get(to) != null;
  }
  
  double _getMaterialDifference(String from, String to) {
    final pieceValues = {
      chess.PieceType.PAWN: 1.0,
      chess.PieceType.KNIGHT: 3.0,
      chess.PieceType.BISHOP: 3.0,
      chess.PieceType.ROOK: 5.0,
      chess.PieceType.QUEEN: 9.0,
      chess.PieceType.KING: 0.0,
    };
    
    final attacker = game.get(from);
    final defender = game.get(to);
    
    if (attacker == null || defender == null) return 0.0;
    
    return (pieceValues[defender.type] ?? 0.0) - (pieceValues[attacker.type] ?? 0.0);
  }
  
  TacticalPattern? _detectPin(String square) {
    final squareIndex = chess.Chess.SQUARES[square];
    if (squareIndex == null) return null;
    
    final moves = game.generate_moves({'square': squareIndex});
    final piece = game.get(square);
    
    if (piece == null) return null;
    
    // Check if this piece attacks multiple valuable pieces
    if (moves.length >= 2) {
      final targets = moves.where((m) {
        final toSquare = _squareFromIndex(m.to);
        if (toSquare == null) return false;
        final targetPiece = game.get(toSquare);
        return targetPiece != null;
      }).toList();
      
      if (targets.length >= 2) {
        return TacticalPattern(
          name: 'Pin',
          description: 'Piece cannot move without exposing a more valuable piece',
          involvedSquares: [square],
        );
      }
    }
    
    return null;
  }
  
  TacticalPattern? _detectFork(String square) {
    final squareIndex = chess.Chess.SQUARES[square];
    if (squareIndex == null) return null;
    
    final moves = game.generate_moves({'square': squareIndex});
    final piece = game.get(square);
    
    if (piece == null) return null;
    
    // Count valuable pieces attacked
    int valuableTargets = 0;
    for (var move in moves) {
      final toSquare = _squareFromIndex(move.to);
      if (toSquare == null) continue;
      
      final target = game.get(toSquare);
      if (target != null && target.color != piece.color) {
        if (target.type == chess.PieceType.KING || 
            target.type == chess.PieceType.QUEEN ||
            target.type == chess.PieceType.ROOK) {
          valuableTargets++;
        }
      }
    }
    
    if (valuableTargets >= 2) {
      return TacticalPattern(
        name: 'Fork',
        description: 'Attacking multiple pieces simultaneously',
        involvedSquares: [square],
      );
    }
    
    return null;
  }
  
  bool _isCastling(String from, String to) {
    return (from == 'e1' && (to == 'g1' || to == 'c1')) ||
           (from == 'e8' && (to == 'g8' || to == 'c8'));
  }
  
  bool _isCentralSquare(String square) {
    return ['e4', 'e5', 'd4', 'd5', 'e3', 'e6', 'd3', 'd6'].contains(square);
  }
  
  bool _isDevelopmentMove(String uciMove) {
    final from = uciMove.substring(0, 2);
    final piece = game.get(from);
    
    if (piece == null) return false;
    
    // Check if piece is moving from back rank (development)
    final rank = from[1];
    return (rank == '1' || rank == '8') && 
           (piece.type == chess.PieceType.KNIGHT || 
            piece.type == chess.PieceType.BISHOP);
  }
  
  String _analyzePawnStructure() {
    // Simplified - could detect doubled, isolated, or passed pawns
    return '';
  }
  
  String _analyzeKingSafety() {
    // Analyze king exposure, pawn shield, etc.
    final king = _findKing(game.turn);
    if (king == null) return '';
    
    // Check if king has castled
    final kingFile = king[0];
    if (kingFile == 'a' || kingFile == 'b' || kingFile == 'g' || kingFile == 'h') {
      return 'King Safety: King castled to a safer position';
    }
    
    return '';
  }
  
  String? _findKing(chess.Color color) {
    for (var entry in chess.Chess.SQUARES.entries) {
      final square = entry.key;
      final piece = game.get(square);
      if (piece?.type == chess.PieceType.KING && piece?.color == color) {
        return square;
      }
    }
    return null;
  }
  
  GamePhase _getGamePhase() {
    final moves = game.history.length;
    final majorPieces = _countMajorPieces();
    
    if (moves < 15) return GamePhase.opening;
    if (majorPieces > 4) return GamePhase.middlegame;
    return GamePhase.endgame;
  }
  
  int _countMajorPieces() {
    int count = 0;
    for (var square in chess.Chess.SQUARES.keys) {
      final piece = game.get(square);
      if (piece != null && 
          (piece.type == chess.PieceType.QUEEN || 
           piece.type == chess.PieceType.ROOK)) {
        count++;
      }
    }
    return count;
  }
}

enum GamePhase {
  opening,
  middlegame,
  endgame,
}

class MoveAnnotation {
  final String move;
  final MoveEvaluation evaluation;
  final List<TacticalPattern> tactics;
  final List<String> positionalThemes;
  final GamePhase gamePhase;
  
  MoveAnnotation({
    required this.move,
    required this.evaluation,
    required this.tactics,
    required this.positionalThemes,
    required this.gamePhase,
  });
  
  String getPhaseAdvice() {
    switch (gamePhase) {
      case GamePhase.opening:
        return 'Opening: Focus on development, center control, and king safety';
      case GamePhase.middlegame:
        return 'Middlegame: Look for tactical opportunities and improve piece positions';
      case GamePhase.endgame:
        return 'Endgame: Activate your king and create passed pawns';
    }
  }
  
  String getFullDescription() {
    final parts = <String>[];
    
    // Add move quality
    if (evaluation.quality != MoveQuality.neutral) {
        parts.add('${evaluation.symbol} ${_qualityDescription(evaluation.quality)}');
    }
    
    // Add evaluation change description
    final change = evaluation.evaluationChange;
    if (change.abs() > 0.3) {
        if (change < 0) {
        // Position improved
        parts.add('Improved position by ${change.abs().toStringAsFixed(1)} pawns');
        } else {
        // Position worsened
        parts.add('Lost ${change.toStringAsFixed(1)} pawns');
        }
    }
    
    // Add tactical themes
    for (var tactic in tactics) {
        parts.add('${tactic.name}: ${tactic.description}');
    }
    
    // Add positional themes (limit to 2 most important)
    if (positionalThemes.isNotEmpty) {
        parts.addAll(positionalThemes.take(2));
    }
    
    // Add phase-specific advice
    parts.add(getPhaseAdvice());
    
    return parts.join('\n');
    }
  
  String _qualityDescription(MoveQuality quality) {
    switch (quality) {
      case MoveQuality.brilliant:
        return 'Brilliant move!';
      case MoveQuality.good:
        return 'Good move';
      case MoveQuality.interesting:
        return 'Interesting idea';
      case MoveQuality.dubious:
        return 'Questionable choice';
      case MoveQuality.mistake:
        return 'Mistake';
      case MoveQuality.blunder:
        return 'Blunder!';
      case MoveQuality.neutral:
        return 'Standard move';
    }
  }
}