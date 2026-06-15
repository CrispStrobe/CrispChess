import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../chess/chess_game.dart';
import '../l10n/generated/app_localizations.dart';

/// Board setup / position editor screen.
///
/// Allows placing pieces on the board, setting side to move,
/// castling rights, and en passant. Generates a FEN string.
class PositionEditorScreen extends StatefulWidget {
  /// Initial FEN to load into the editor.
  final String initialFen;

  const PositionEditorScreen({
    super.key,
    this.initialFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  });

  @override
  State<PositionEditorScreen> createState() => _PositionEditorScreenState();
}

class _PositionEditorScreenState extends State<PositionEditorScreen> {
  late List<List<ChessPiece?>> _board;
  bool _whiteToMove = true;
  bool _whiteCastleKing = true;
  bool _whiteCastleQueen = true;
  bool _blackCastleKing = true;
  bool _blackCastleQueen = true;
  String? _enPassant;

  /// Currently selected piece to place (null = eraser mode).
  ChessPiece? _selectedPiece;
  String _pieceTheme = 'chessnut';

  @override
  void initState() {
    super.initState();
    _parseFen(widget.initialFen);
  }

  void _parseFen(String fen) {
    final parts = fen.split(' ');
    final rows = parts[0].split('/');

    _board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    for (int r = 0; r < 8 && r < rows.length; r++) {
      int c = 0;
      for (var char in rows[r].split('')) {
        final empty = int.tryParse(char);
        if (empty != null) {
          c += empty;
        } else {
          final color = char == char.toUpperCase() ? PieceColor.white : PieceColor.black;
          final type = _charToType(char.toLowerCase());
          if (c < 8) _board[r][c] = ChessPiece(type, color);
          c++;
        }
      }
    }

    if (parts.length > 1) _whiteToMove = parts[1] == 'w';
    if (parts.length > 2) {
      _whiteCastleKing = parts[2].contains('K');
      _whiteCastleQueen = parts[2].contains('Q');
      _blackCastleKing = parts[2].contains('k');
      _blackCastleQueen = parts[2].contains('q');
    }
    if (parts.length > 3) _enPassant = parts[3] == '-' ? null : parts[3];
  }

  PieceType _charToType(String c) {
    return switch (c) {
      'p' => PieceType.pawn,
      'n' => PieceType.knight,
      'b' => PieceType.bishop,
      'r' => PieceType.rook,
      'q' => PieceType.queen,
      'k' => PieceType.king,
      _ => PieceType.pawn,
    };
  }

  String _generateFen() {
    final sb = StringBuffer();

    // Piece placement
    for (int r = 0; r < 8; r++) {
      int empty = 0;
      for (int c = 0; c < 8; c++) {
        final piece = _board[r][c];
        if (piece == null) {
          empty++;
        } else {
          if (empty > 0) { sb.write(empty); empty = 0; }
          sb.write(piece.symbol);
        }
      }
      if (empty > 0) sb.write(empty);
      if (r < 7) sb.write('/');
    }

    // Side to move
    sb.write(_whiteToMove ? ' w' : ' b');

    // Castling
    sb.write(' ');
    final castling = StringBuffer();
    if (_whiteCastleKing) castling.write('K');
    if (_whiteCastleQueen) castling.write('Q');
    if (_blackCastleKing) castling.write('k');
    if (_blackCastleQueen) castling.write('q');
    sb.write(castling.isEmpty ? '-' : castling.toString());

    // En passant
    sb.write(' ${_enPassant ?? "-"}');

    // Half-move clock and full move number
    sb.write(' 0 1');

    return sb.toString();
  }

  String? _validatePosition(AppLocalizations? l) {
    int whiteKings = 0, blackKings = 0;
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final p = _board[r][c];
        if (p != null && p.type == PieceType.king) {
          if (p.color == PieceColor.white) whiteKings++;
          else blackKings++;
        }
        // Pawns on rank 1 or 8
        if (p != null && p.type == PieceType.pawn && (r == 0 || r == 7)) {
          return l?.pawnsOnEdgeRank ?? 'Pawns cannot be on the first or last rank';
        }
      }
    }
    if (whiteKings != 1) return l?.needOneWhiteKing ?? 'White must have exactly one king';
    if (blackKings != 1) return l?.needOneBlackKing ?? 'Black must have exactly one king';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final fen = _generateFen();
    final error = _validatePosition(l);

    return Scaffold(
      appBar: AppBar(
        title: Text(l?.positionEditor ?? 'Position Editor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: l?.startingPosition ?? 'Starting position',
            onPressed: () {
              setState(() {
                _parseFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
                _selectedPiece = null;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: l?.clearBoard ?? 'Clear board',
            onPressed: () {
              setState(() {
                _board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
                _selectedPiece = null;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Board
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.brown, width: 2),
                  ),
                  child: Column(
                    children: List.generate(8, (row) {
                      return Expanded(
                        child: Row(
                          children: List.generate(8, (col) {
                            final piece = _board[row][col];
                            final isLight = (row + col) % 2 == 0;
                            return Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedPiece == null) {
                                      // Eraser mode — remove piece
                                      _board[row][col] = null;
                                    } else {
                                      _board[row][col] = ChessPiece(
                                        _selectedPiece!.type,
                                        _selectedPiece!.color,
                                      );
                                    }
                                  });
                                },
                                child: Container(
                                  color: isLight ? Colors.brown[200] : Colors.brown[400],
                                  child: piece != null
                                      ? Center(
                                          child: SvgPicture.asset(
                                            _pieceAsset(piece),
                                            width: 32,
                                            height: 32,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),

          // Piece palette
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                // White pieces
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final type in PieceType.values)
                      _buildPalettePiece(ChessPiece(type, PieceColor.white)),
                  ],
                ),
                const SizedBox(height: 4),
                // Black pieces
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final type in PieceType.values)
                      _buildPalettePiece(ChessPiece(type, PieceColor.black)),
                  ],
                ),
                const SizedBox(height: 4),
                // Eraser
                GestureDetector(
                  onTap: () => setState(() => _selectedPiece = null),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _selectedPiece == null ? Colors.blue : Colors.grey,
                        width: _selectedPiece == null ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.backspace, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // Options
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                // Side to move
                Row(
                  children: [
                    Text(l?.sideToMove ?? 'Side to move:', style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text(l?.playAsWhite ?? 'White')),
                        ButtonSegment(value: false, label: Text(l?.playAsBlack ?? 'Black')),
                      ],
                      selected: {_whiteToMove},
                      onSelectionChanged: (s) => setState(() => _whiteToMove = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Castling
                Row(
                  children: [
                    Text(l?.castling ?? 'Castling:', style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    _castlingChip('K', _whiteCastleKing, (v) => setState(() => _whiteCastleKing = v)),
                    _castlingChip('Q', _whiteCastleQueen, (v) => setState(() => _whiteCastleQueen = v)),
                    _castlingChip('k', _blackCastleKing, (v) => setState(() => _blackCastleKing = v)),
                    _castlingChip('q', _blackCastleQueen, (v) => setState(() => _blackCastleQueen = v)),
                  ],
                ),
              ],
            ),
          ),

          // FEN display
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    fen,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: l?.copyFen ?? 'Copy FEN',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: fen));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l?.fenCopied ?? 'FEN copied')),
                    );
                  },
                ),
              ],
            ),
          ),

          // Error or Load button
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
        ],
      ),
      floatingActionButton: error == null
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, fen),
              icon: const Icon(Icons.check),
              label: Text(l?.loadPosition ?? 'Load Position'),
            )
          : null,
    );
  }

  Widget _buildPalettePiece(ChessPiece piece) {
    final isSelected = _selectedPiece != null &&
        _selectedPiece!.type == piece.type &&
        _selectedPiece!.color == piece.color;
    return GestureDetector(
      onTap: () => setState(() => _selectedPiece = piece),
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
          color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
        ),
        child: Center(
          child: SvgPicture.asset(
            _pieceAsset(piece),
            width: 28,
            height: 28,
          ),
        ),
      ),
    );
  }

  Widget _castlingChip(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: value,
        onSelected: onChanged,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
      ),
    );
  }

  String _pieceAsset(ChessPiece piece) {
    final color = piece.color == PieceColor.white ? 'w' : 'b';
    final type = switch (piece.type) {
      PieceType.pawn => 'P',
      PieceType.knight => 'N',
      PieceType.bishop => 'B',
      PieceType.rook => 'R',
      PieceType.queen => 'Q',
      PieceType.king => 'K',
    };
    return 'assets/pieces/$_pieceTheme/$color$type.svg';
  }
}
