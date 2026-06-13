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
  }) : super(key: key);

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard>
    with SingleTickerProviderStateMixin {
  AnimationController? _animationController;
  Animation<Offset>? _animation;
  String? _animatingMove;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  void _animateMove(int fromRow, int fromCol, int toRow, int toCol) {
    if (!widget.animateMoves) return;

    final dx = (toCol - fromCol).toDouble();
    final dy = (toRow - fromRow).toDouble();

    _animation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(dx, dy),
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeInOut,
    ));

    _animatingMove = '${fromRow}_$fromCol';
    _animationController!.forward(from: 0).then((_) {
      if (mounted) {
        setState(() {
          _animatingMove = null;
        });
      }
    });
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

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.brown, width: 2),
        ),
        child: RepaintBoundary(
          child: Column(
            children: List.generate(8, (row) {
              return Expanded(
                child: Row(
                  children: List.generate(8, (col) {
                    final piece = widget.board[row][col];
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
                        piece != null &&
                        piece.type == PieceType.king) {
                      if (widget.whiteToMove &&
                          piece.color == PieceColor.white) {
                        isKingInDanger = true;
                      }
                      if (!widget.whiteToMove &&
                          piece.color == PieceColor.black) {
                        isKingInDanger = true;
                      }
                    }

                    final isAnimating =
                        _animatingMove == '${row}_$col';

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
                      isAnimating: isAnimating,
                      animation: _animation,
                      onSquareTap: widget.onSquareTap,
                      onMove: widget.onMove,
                      animateMove: _animateMove,
                    );
                  }),
                ),
              );
            }),
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
  final bool isAnimating;
  final Animation<Offset>? animation;
  final Function(int row, int col)? onSquareTap;
  final Function(int fromRow, int fromCol, int toRow, int toCol)? onMove;
  final void Function(int fromRow, int fromCol, int toRow, int toCol)
      animateMove;

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
    required this.isAnimating,
    required this.animation,
    required this.onSquareTap,
    required this.onMove,
    required this.animateMove,
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
            if (onMove != null) {
              animateMove(
                  details.data['row']!, details.data['col']!, row, col);
              onMove!(
                  details.data['row']!, details.data['col']!, row, col);
            }
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
                    isAnimating && animation != null
                        ? AnimatedBuilder(
                            animation: animation!,
                            builder: (context, child) {
                              return Transform.translate(
                                offset: Offset(
                                  animation!.value.dx *
                                      MediaQuery.of(context).size.width /
                                      8,
                                  animation!.value.dy *
                                      MediaQuery.of(context).size.height /
                                      8,
                                ),
                                child: child,
                              );
                            },
                            child: _PieceWidget(piece: piece!),
                          )
                        : Draggable<Map<String, int>>(
                            data: {'row': row, 'col': col},
                            feedback:
                                _PieceWidget(piece: piece!, size: 60),
                            childWhenDragging: Container(),
                            child: _PieceWidget(piece: piece!),
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

  const _PieceWidget({required this.piece, this.size});

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

    return 'assets/pieces/$colorPrefix$typeSuffix.svg';
  }
}
