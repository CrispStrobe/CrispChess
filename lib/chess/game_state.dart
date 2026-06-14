import 'chess_clock.dart';

/// Supported chess variant modes.
enum ChessVariant { standard, chess960, kingOfTheHill, threeCheck }

class GameState {
  final int strengthLevel;
  final int hintDepth;
  final bool showValidMoves;
  final bool allowUndo;
  final bool twoPlayerMode;
  final int animationSpeed; // 0=instant, 1=fast, 2=normal, 3=slow
  final String hintEngine; // 'same' = use game engine, or engine name
  final TimeControl timeControl;
  final int? selectedRow;
  final int? selectedCol;
  final List<String> validMoves;
  final String statusMessage;
  final bool isThinking;
  final String? hintMove;
  final String lastMove;
  final bool waitingForHint;
  final bool analysisExpanded;
  final String? currentBestMove;
  final bool playAsBlack;
  final String pieceTheme;
  final bool boardFlipped;
  final String? lastMoveUci;
  final bool isLastMoveCapture;

  const GameState({
    this.strengthLevel = 10,
    this.hintDepth = 15,
    this.showValidMoves = true,
    this.allowUndo = true,
    this.twoPlayerMode = false,
    this.animationSpeed = 2,
    this.hintEngine = 'same',
    this.timeControl = TimeControl.unlimited,
    this.selectedRow,
    this.selectedCol,
    this.validMoves = const [],
    this.statusMessage = 'Your turn (White)',
    this.isThinking = false,
    this.hintMove,
    this.lastMove = '',
    this.waitingForHint = false,
    this.analysisExpanded = false,
    this.currentBestMove,
    this.playAsBlack = false,
    this.pieceTheme = 'chessnut',
    this.boardFlipped = false,
    this.lastMoveUci,
    this.isLastMoveCapture = false,
  });

  /// Whether animation is enabled (speed > 0).
  bool get animateMoves => animationSpeed > 0;

  /// Animation duration in milliseconds based on speed setting.
  int get animationDurationMs {
    switch (animationSpeed) {
      case 0: return 0;
      case 1: return 200;
      case 2: return 450;
      case 3: return 800;
      default: return 450;
    }
  }

  static const _sentinel = Object();

  GameState copyWith({
    int? strengthLevel,
    int? hintDepth,
    bool? showValidMoves,
    bool? allowUndo,
    bool? twoPlayerMode,
    int? animationSpeed,
    String? hintEngine,
    TimeControl? timeControl,
    Object? selectedRow = _sentinel,
    Object? selectedCol = _sentinel,
    List<String>? validMoves,
    String? statusMessage,
    bool? isThinking,
    Object? hintMove = _sentinel,
    String? lastMove,
    bool? waitingForHint,
    bool? analysisExpanded,
    Object? currentBestMove = _sentinel,
    bool? playAsBlack,
    String? pieceTheme,
    bool? boardFlipped,
    Object? lastMoveUci = _sentinel,
    bool? isLastMoveCapture,
  }) =>
      GameState(
        strengthLevel: strengthLevel ?? this.strengthLevel,
        hintDepth: hintDepth ?? this.hintDepth,
        showValidMoves: showValidMoves ?? this.showValidMoves,
        allowUndo: allowUndo ?? this.allowUndo,
        twoPlayerMode: twoPlayerMode ?? this.twoPlayerMode,
        animationSpeed: animationSpeed ?? this.animationSpeed,
        hintEngine: hintEngine ?? this.hintEngine,
        timeControl: timeControl ?? this.timeControl,
        selectedRow: identical(selectedRow, _sentinel)
            ? this.selectedRow
            : selectedRow as int?,
        selectedCol: identical(selectedCol, _sentinel)
            ? this.selectedCol
            : selectedCol as int?,
        validMoves: validMoves ?? this.validMoves,
        statusMessage: statusMessage ?? this.statusMessage,
        isThinking: isThinking ?? this.isThinking,
        hintMove: identical(hintMove, _sentinel)
            ? this.hintMove
            : hintMove as String?,
        lastMove: lastMove ?? this.lastMove,
        waitingForHint: waitingForHint ?? this.waitingForHint,
        analysisExpanded: analysisExpanded ?? this.analysisExpanded,
        currentBestMove: identical(currentBestMove, _sentinel)
            ? this.currentBestMove
            : currentBestMove as String?,
        playAsBlack: playAsBlack ?? this.playAsBlack,
        pieceTheme: pieceTheme ?? this.pieceTheme,
        boardFlipped: boardFlipped ?? this.boardFlipped,
        lastMoveUci: identical(lastMoveUci, _sentinel)
            ? this.lastMoveUci
            : lastMoveUci as String?,
        isLastMoveCapture: isLastMoveCapture ?? this.isLastMoveCapture,
      );
}
