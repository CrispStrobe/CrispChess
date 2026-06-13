import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ChessBoard extends StatefulWidget {
  final List<List<ChessPiece?>> board;
  final bool whiteToMove;
  final String Function(int row, int col) squareToAlgebraic;
  final Function(int fromRow, int fromCol, int toRow, int toCol)? onMove;
  final Function(int row, int col)? onSquareTap;
  final int? selectedRow;
  final int? selectedCol;
  final List<String> validMoves;
  final String? hintMove;
  final bool isCheck;
  final bool animateMoves;
  final String pieceTheme;
  final String? lastMoveUci; // e.g. "e2e4" — triggers slide animation

  const ChessBoard({
    Key? key,
    required this.board,
    required this.whiteToMove,
    required this.squareToAlgebraic,
    this.onMove,
    this.onSquareTap,
    this.selectedRow,
    this.selectedCol,
    this.validMoves = const [],
    this.hintMove,
    this.isCheck = false,
    this.animateMoves = true,
    this.pieceTheme = 'chessnut',
    this.lastMoveUci,
  }) : super(key: key);

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  String? _lastProcessedMove;

  // Animation state: piece sliding from one square to another
  int? _animFromRow, _animFromCol, _animToRow, _animToCol;
  ChessPiece? _animPiece;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _animPiece = null;
          _animFromRow = null;
        });
      }
    });
  }

  @override
  void didUpdateWidget(ChessBoard old) {
    super.didUpdateWidget(old);
    // Trigger animation when lastMoveUci changes
    if (widget.lastMoveUci != null &&
        widget.lastMoveUci != _lastProcessedMove &&
        widget.animateMoves) {
      _lastProcessedMove = widget.lastMoveUci;
      _startMoveAnimation(widget.lastMoveUci!);
    }
  }

  void _startMoveAnimation(String uci) {
    if (uci.length < 4) return;
    final fromCol = uci.codeUnitAt(0) - 97; // 'a' = 0
    final fromRow = 8 - int.parse(uci[1]);
    final toCol = uci.codeUnitAt(2) - 97;
    final toRow = 8 - int.parse(uci[3]);

    // The piece is already at the destination in the board state.
    // We grab it and animate it FROM the source TO the destination.
    final piece = widget.board[toRow][toCol];
    if (piece == null) return;

    setState(() {
      _animPiece = piece;
      _animFromRow = fromRow;
      _animFromCol = fromCol;
      _animToRow = toRow;
      _animToCol = toCol;
    });
    _animController.forward(from: 0);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Pre-compute valid target squares as a Set for O(1) lookup
    final validTargets = <String>{};
    for (final move in widget.validMoves) {
      if (move.length >= 4) {
        validTargets.add(move.substring(2, 4));
      }
    }

    // Pre-compute hint squares
    String? hintFrom;
    String? hintTo;
    if (widget.hintMove != null && widget.hintMove!.length >= 4) {
      hintFrom = widget.hintMove!.substring(0, 2);
      hintTo = widget.hintMove!.substring(2, 4);
    }

    final isAnimating = _animPiece != null;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.brown, width: 2),
        ),
        child: RepaintBoundary(
          child: Stack(
            children: [
              Column(
                children: List.generate(8, (row) {
                  return Expanded(
                    child: Row(
                      children: List.generate(8, (col) {
                    // During animation, hide piece at destination
                    final hideForAnim = isAnimating &&
                        row == _animToRow && col == _animToCol;
                    final piece = hideForAnim ? null : widget.board[row][col];

                    final squareName =
                        widget.squareToAlgebraic(row, col);
                    final isLight = (row + col) % 2 == 0;
                    final isSelected = widget.selectedRow == row &&
                        widget.selectedCol == col;
                    final isValidTarget =
                        validTargets.contains(squareName);
                    final isHintFrom = squareName == hintFrom;
                    final isHintTo = squareName == hintTo;

                    bool isKingInDanger = false;
                    if (widget.isCheck &&
                        widget.board[row][col] != null &&
                        widget.board[row][col]!.type == PieceType.king) {
                      if (widget.whiteToMove &&
                          widget.board[row][col]!.color == PieceColor.white) {
                        isKingInDanger = true;
                      }
                      if (!widget.whiteToMove &&
                          widget.board[row][col]!.color == PieceColor.black) {
                        isKingInDanger = true;
                      }
                    }

                    return _ChessSquare(
                      row: row,
                      col: col,
                      piece: piece,
                      squareName: squareName,
                      isLight: isLight,
                      isSelected: isSelected,
                      isValidTarget: isValidTarget,
                      isHintFrom: isHintFrom,
                      isHintTo: isHintTo,
                      isKingInDanger: isKingInDanger,
                      onSquareTap: widget.onSquareTap,
                      onMove: widget.onMove,
                      pieceTheme: widget.pieceTheme,
                    );
                  }),
                ),
              );
            }),
          ),
              // Animated piece overlay
              if (isAnimating && _animFromRow != null)
                AnimatedBuilder(
                  animation: _animController,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(_animController.value);
                    final fromX = _animFromCol! / 8.0;
                    final fromY = _animFromRow! / 8.0;
                    final toX = _animToCol! / 8.0;
                    final toY = _animToRow! / 8.0;
                    final x = fromX + (toX - fromX) * t;
                    final y = fromY + (toY - fromY) * t;
                    return Positioned(
                      left: x * (context.size?.width ?? 300),
                      top: y * (context.size?.height ?? 300),
                      width: (context.size?.width ?? 300) / 8,
                      height: (context.size?.height ?? 300) / 8,
                      child: IgnorePointer(
                        child: _PieceWidget(
                          piece: _animPiece!,
                          theme: widget.pieceTheme,
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChessSquare extends StatelessWidget {
  final int row;
  final int col;
  final ChessPiece? piece;
  final String squareName;
  final bool isLight;
  final bool isSelected;
  final bool isValidTarget;
  final bool isHintFrom;
  final bool isHintTo;
  final bool isKingInDanger;
  final Function(int row, int col)? onSquareTap;
  final Function(int fromRow, int fromCol, int toRow, int toCol)? onMove;
  final String pieceTheme;

  const _ChessSquare({
    required this.row,
    required this.col,
    required this.piece,
    required this.squareName,
    required this.isLight,
    required this.isSelected,
    required this.isValidTarget,
    required this.isHintFrom,
    required this.isHintTo,
    required this.isKingInDanger,
    required this.onSquareTap,
    required this.onMove,
    required this.pieceTheme,
  });

  @override
  Widget build(BuildContext context) {
    final isHintSquare = isHintFrom || isHintTo;

    return Expanded(
      child: GestureDetector(
        onTap: () => onSquareTap?.call(row, col),
        child: DragTarget<Map<String, int>>(
          onWillAcceptWithDetails: (details) => true,
          onAcceptWithDetails: (details) {
            onMove?.call(
                details.data['row']!, details.data['col']!, row, col);
          },
          builder: (context, candidateData, rejectedData) {
            Color? bgColor;
            if (isKingInDanger) {
              bgColor = Colors.red.withValues(alpha: 0.7);
            } else if (isSelected) {
              bgColor = Colors.blue.withValues(alpha: 0.5);
            } else if (isValidTarget) {
              bgColor = isLight
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.4);
            } else if (isHintSquare) {
              bgColor = Colors.yellow.withValues(alpha: 0.5);
            } else {
              bgColor = isLight ? Colors.brown[200] : Colors.brown[400];
            }

            return Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: candidateData.isNotEmpty
                    ? Border.all(color: Colors.green, width: 3)
                    : isSelected
                        ? Border.all(color: Colors.blue, width: 3)
                        : null,
              ),
              child: Stack(
                children: [
                  if (piece == null)
                    Center(
                      child: Text(
                        squareName,
                        style: TextStyle(
                          fontSize: 8,
                          color: isLight
                              ? Colors.brown[400]
                              : Colors.brown[200],
                        ),
                      ),
                    ),
                  if (isValidTarget && piece == null)
                    Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  if (piece != null)
                    Draggable<Map<String, int>>(
                      data: {'row': row, 'col': col},
                      feedback: _PieceWidget(piece: piece!, size: 60, theme: pieceTheme),
                      childWhenDragging: Container(),
                      child: _PieceWidget(piece: piece!, theme: pieceTheme),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PieceWidget extends StatelessWidget {
  final ChessPiece piece;
  final double? size;
  final String theme;

  const _PieceWidget({required this.piece, this.size, this.theme = 'chessnut'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SvgPicture.asset(
        _getPieceAsset(piece),
        width: size ?? 45,
        height: size ?? 45,
      ),
    );
  }

  String _getPieceAsset(ChessPiece piece) {
    final colorPrefix = piece.color == PieceColor.white ? 'w' : 'b';

    String typeSuffix = '';
    switch (piece.type) {
      case PieceType.pawn:
        typeSuffix = 'P';
      case PieceType.knight:
        typeSuffix = 'N';
      case PieceType.bishop:
        typeSuffix = 'B';
      case PieceType.rook:
        typeSuffix = 'R';
      case PieceType.queen:
        typeSuffix = 'Q';
      case PieceType.king:
        typeSuffix = 'K';
    }

    return 'assets/pieces/$theme/$colorPrefix$typeSuffix.svg';
  }
}
