import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chess/board_annotations.dart';
import '../chess/chess_game.dart';
import '../l10n/generated/app_localizations.dart';
import '../engines/maia3_dart/onnx/model_fetch.dart';
import '../vision/board_recognizer.dart';
import '../vision/photo/board_photo_recognizer.dart';
import '../widgets/chess_board.dart';

/// Recognition off the UI isolate. The model is 277 KB, so loading it per job
/// costs nothing next to the 64-square pass it is loaded for.
Future<BoardRecognition> _recognizeJob(
    ({Uint8List model, Uint8List rgba, int w, int h, BoardRect? crop})
        job) async {
  final recognizer = BoardRecognizer(job.model);
  try {
    return await recognizer.recognize(job.rgba, job.w, job.h, crop: job.crop);
  } finally {
    recognizer.dispose();
  }
}

/// Photo recognition off the UI isolate: locate the board, read the squares.
Future<BoardPhotoResult> _recognizePhotoJob(
    ({Uint8List occ, Uint8List pieces, Uint8List rgba, int w, int h}) j) async {
  final r = BoardPhotoRecognizer(BoardPhotoModels(occupancy: j.occ, pieces: j.pieces));
  try {
    return await r.recognize(j.rgba, j.w, j.h);
  } finally {
    r.dispose();
  }
}

/// Castling rights a scanned position can plausibly have: king and rook still
/// on their starting squares. The editor lets the user take them away.
String inferCastling(List<String> squares) {
  bool at(String sq, String piece) {
    final i = (8 - int.parse(sq[1])) * 8 + sq.codeUnitAt(0) - 97;
    return squares[i] == piece;
  }

  final rights = [
    if (at('e1', 'K') && at('h1', 'R')) 'K',
    if (at('e1', 'K') && at('a1', 'R')) 'Q',
    if (at('e8', 'k') && at('h8', 'r')) 'k',
    if (at('e8', 'k') && at('a8', 'r')) 'q',
  ].join();
  return rights.isEmpty ? '-' : rights;
}

/// Picks an image of a chess diagram — a screenshot, a scanned book page — and
/// turns it into a position, entirely on the device. Pops with a FEN.
class ScanBoardScreen extends StatefulWidget {
  const ScanBoardScreen({super.key});

  @override
  State<ScanBoardScreen> createState() => _ScanBoardScreenState();
}

class _ScanBoardScreenState extends State<ScanBoardScreen> {
  /// Longest side images are decoded at. Diagrams need nowhere near a phone
  /// camera's resolution, and the grid search is linear in pixels.
  static const _maxSide = 1600;

  Uint8List? _model;
  Uint8List? _photoOcc, _photoPieces;

  /// Photo of a physical board (perspective, 3D pieces) instead of a diagram.
  bool _photoMode = false;
  BoardPhotoResult? _photo;
  ui.Image? _image;
  Uint8List? _rgba;
  BoardRecognition? _result;
  BoardRect? _dragRect;
  Offset? _dragStart;
  bool _busy = false;
  bool _notFound = false;
  Object? _error;
  bool _whiteToMove = true;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _photo = null;
      _notFound = false;
      _dragRect = null;
    });
    try {
      if (_photoMode) {
        // Downloaded once (12 MB), then cached like the engines' models.
        _photoOcc ??= await fetchModelBytes(photoOccupancyUrl, 'board_photo_occupancy.onnx');
        _photoPieces ??= await fetchModelBytes(photoPiecesUrl, 'board_photo_pieces.onnx');
      }
      _model ??= (await rootBundle.load('assets/models/board_squares.onnx'))
          .buffer
          .asUint8List();
      final image = await _decode(await file.xFile.readAsBytes());
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      _image?.dispose();
      setState(() {
        _image = image;
        _rgba = data!.buffer.asUint8List();
      });
      if (_photoMode) {
        await _recognizePhoto();
      } else {
        await _recognize(null);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale =
        math.min(1.0, _maxSide / math.max(descriptor.width, descriptor.height));
    final codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round(),
      targetHeight: (descriptor.height * scale).round(),
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<void> _recognize(BoardRect? crop) async {
    final image = _image, rgba = _rgba, model = _model;
    if (image == null || rgba == null || model == null) return;
    setState(() {
      _busy = true;
      _notFound = false;
    });
    try {
      final r = await compute(_recognizeJob,
          (model: model, rgba: rgba, w: image.width, h: image.height, crop: crop));
      if (mounted) setState(() => _result = r);
    } on BoardNotFoundException {
      if (mounted) {
        setState(() {
          _result = null;
          _notFound = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognizePhoto() async {
    final image = _image, rgba = _rgba;
    if (image == null || rgba == null) return;
    setState(() {
      _busy = true;
      _notFound = false;
    });
    try {
      final photo = await compute(_recognizePhotoJob, (
        occ: _photoOcc!,
        pieces: _photoPieces!,
        rgba: rgba,
        w: image.width,
        h: image.height
      ));
      if (mounted) {
        setState(() {
          _photo = photo;
          _result = photo.toBoardRecognition();
        });
      }
    } on BoardNotLocatedException {
      if (mounted) {
        setState(() {
          _result = null;
          _notFound = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _fen {
    final r = _result!;
    return '${r.placement} ${_whiteToMove ? 'w' : 'b'} '
        '${inferCastling(r.squares)} - 0 1';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: Text(l?.scanBoard ?? 'Scan board')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l?.scanBoardHint ??
              'Choose a screenshot or a scanned book diagram.'),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.grid_on),
                  label: Text(l?.scanModeDiagram ?? 'Diagram')),
              ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.photo_camera),
                  label: Text(l?.scanModePhoto ?? 'Photo')),
            ],
            selected: {_photoMode},
            onSelectionChanged: _busy
                ? null
                : (s) => setState(() {
                      _photoMode = s.first;
                      _image = null;
                      _result = null;
                      _photo = null;
                    }),
          ),
          if (_photoMode) ...[
            const SizedBox(height: 6),
            Text(
                l?.scanPhotoHint ??
                    'Photograph the whole board from a player\'s side.',
                style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _pick,
            icon: const Icon(Icons.image_search),
            label: Text(l?.scanPickImage ?? 'Choose image'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 4),
            Text(l?.scanRecognizing ?? 'Recognizing…'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(l?.scanFailed('$_error') ?? 'Could not read the image: $_error',
                style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_image != null) ...[
            const SizedBox(height: 16),
            Text(
              _notFound
                  ? (_photoMode
                      ? l?.scanPhotoNoBoard ??
                          'No board found. Photograph the whole board, with its grid visible.'
                      : l?.scanNoBoard ?? 'No chessboard found. Drag a square.')
                  : (_photoMode
                      ? ''
                      : l?.scanDragHint ?? 'Wrong area? Drag a square around it.'),
              style: _notFound
                  ? TextStyle(color: theme.colorScheme.error)
                  : theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            _imageWithOverlay(theme),
          ],
          if (r != null) ...[
            const SizedBox(height: 16),
            _boardPreview(r),
            const SizedBox(height: 8),
            ..._warnings(l, theme, r),
            if (_photo != null && _photo!.orientationConfidence < 0.3)
              Text(
                  l?.scanOrientationUnsure ??
                      'Check the orientation: rotate until White is at the bottom.',
                  style: TextStyle(color: Colors.orange.shade800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                        value: true,
                        label: Text(l?.whiteToMove ?? 'White to move')),
                    ButtonSegment(
                        value: false,
                        label: Text(l?.blackToMove ?? 'Black to move')),
                  ],
                  selected: {_whiteToMove},
                  onSelectionChanged: (s) =>
                      setState(() => _whiteToMove = s.first),
                ),
                if (_photo != null)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _photo = _photo!.rotated(1);
                      _result = _photo!.toBoardRecognition();
                    }),
                    icon: const Icon(Icons.rotate_90_degrees_cw),
                    label: Text(l?.scanRotate ?? 'Rotate 90°'),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _result = r.rotated()),
                    icon: const Icon(Icons.swap_vert),
                    label: Text(l?.flipBoard ?? 'Flip board'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _fen),
              icon: const Icon(Icons.check),
              label: Text(l?.scanUsePosition ?? 'Use position'),
            ),
          ],
        ],
      ),
    );
  }

  /// The picked image with the board outline on it. Dragging marks the board
  /// by hand — a square, since boards are square.
  Widget _imageWithOverlay(ThemeData theme) {
    final image = _image!;
    return LayoutBuilder(builder: (context, box) {
      final scale = math.min(box.maxWidth / image.width, 400 / image.height);
      final w = image.width * scale, h = image.height * scale;
      Offset toImage(Offset p) => Offset(
          (p.dx / scale).clamp(0, image.width.toDouble()),
          (p.dy / scale).clamp(0, image.height.toDouble()));
      BoardRect squareBetween(Offset a, Offset b) {
        final side = math.max((b.dx - a.dx).abs(), (b.dy - a.dy).abs());
        final left = b.dx >= a.dx ? a.dx : a.dx - side;
        final top = b.dy >= a.dy ? a.dy : a.dy - side;
        return BoardRect(left, top, side, side);
      }

      final shown = _photo != null ? null : _dragRect ?? _result?.rect;
      // A photo is in perspective: outline the four corners the locator
      // found. Drag-to-crop is for flat diagrams only.
      final drag = !_busy && !_photoMode;
      return Center(
        child: GestureDetector(
          onPanStart: !drag
              ? null
              : (d) => setState(() {
                    _dragStart = toImage(d.localPosition);
                    _dragRect = null;
                  }),
          onPanUpdate: !drag || _dragStart == null
              ? null
              : (d) => setState(() => _dragRect =
                  squareBetween(_dragStart!, toImage(d.localPosition))),
          onPanEnd: !drag
              ? null
              : (_) {
                  final crop = _dragRect;
                  _dragStart = null;
                  if (crop != null && crop.width >= 32) _recognize(crop);
                },
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(children: [
              Positioned.fill(child: RawImage(image: image, fit: BoxFit.fill)),
              if (_photo != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _CornersPainter(
                        [for (final c in _photo!.corners) Offset(c.x * scale, c.y * scale)],
                        theme.colorScheme.primary),
                  ),
                ),
              if (shown != null)
                Positioned(
                  left: shown.left * scale,
                  top: shown.top * scale,
                  width: shown.width * scale,
                  height: shown.height * scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: theme.colorScheme.primary, width: 2),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _boardPreview(BoardRecognition r) {
    final board = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    for (var i = 0; i < 64; i++) {
      final c = r.squares[i];
      if (c == '.') continue;
      final color = c == c.toUpperCase() ? PieceColor.white : PieceColor.black;
      final type = switch (c.toLowerCase()) {
        'p' => PieceType.pawn,
        'n' => PieceType.knight,
        'b' => PieceType.bishop,
        'r' => PieceType.rook,
        'q' => PieceType.queen,
        _ => PieceType.king,
      };
      board[i ~/ 8][i % 8] = ChessPiece(type, color);
    }
    final marks = BoardAnnotations();
    for (final i in r.uncertainSquares()) {
      marks.addHighlight(BoardHighlight(
          square: BoardRecognition.squareName(i),
          color: Colors.orange.withValues(alpha: 0.6)));
    }
    return Center(
      child: SizedBox(
        width: 320,
        height: 320,
        child: ChessBoard(
          board: board,
          whiteToMove: _whiteToMove,
          squareToAlgebraic: (row, col) =>
              '${String.fromCharCode(97 + col)}${8 - row}',
          annotations: marks,
          animationDurationMs: 0,
        ),
      ),
    );
  }

  List<Widget> _warnings(
      AppLocalizations? l, ThemeData theme, BoardRecognition r) {
    final uncertain = r.uncertainSquares().length;
    final problems = r.problems.map(_describeProblem).join(', ');
    return [
      if (uncertain > 0)
        Text(
          l?.scanUncertain('$uncertain') ??
              '$uncertain uncertain squares are highlighted. Check them.',
          style: TextStyle(color: Colors.orange.shade800),
        ),
      if (problems.isNotEmpty)
        Text(
          l?.scanProblems(problems) ?? 'Check the position: $problems',
          style: TextStyle(color: theme.colorScheme.error),
        ),
    ];
  }

  /// Problem codes from the recognizer, in piece symbols rather than words so
  /// they read the same in every language.
  String _describeProblem(String code) {
    final parts = code.split(':');
    return switch (parts.first) {
      'whiteKings' => '♔ × ${parts[1]}',
      'blackKings' => '♚ × ${parts[1]}',
      'whitePawns' => '♙ × ${parts[1]}',
      'blackPawns' => '♟ × ${parts[1]}',
      'pawnOnBackRank' => '♙/♟ ${parts[1]}',
      _ => code,
    };
  }
}

/// The board's outline in a photo: the four corners the locator found.
class _CornersPainter extends CustomPainter {
  final List<Offset> corners;
  final Color color;
  _CornersPainter(this.corners, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;
    final path = Path()..addPolygon(corners, true);
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_CornersPainter old) =>
      old.corners != corners || old.color != color;
}
