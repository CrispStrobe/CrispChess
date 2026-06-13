class GameState {
  final int strengthLevel;
  final int hintDepth;
  final bool showValidMoves;
  final bool animateMoves;
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

  const GameState({
    this.strengthLevel = 10,
    this.hintDepth = 15,
    this.showValidMoves = true,
    this.animateMoves = true,
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
  });

  static const _sentinel = Object();

  GameState copyWith({
    int? strengthLevel,
    int? hintDepth,
    bool? showValidMoves,
    bool? animateMoves,
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
  }) =>
      GameState(
        strengthLevel: strengthLevel ?? this.strengthLevel,
        hintDepth: hintDepth ?? this.hintDepth,
        showValidMoves: showValidMoves ?? this.showValidMoves,
        animateMoves: animateMoves ?? this.animateMoves,
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
      );
}
