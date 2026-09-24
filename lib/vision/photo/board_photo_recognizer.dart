/// Photo of a physical chessboard -> FEN piece placement, fully offline.
///
/// The pipeline is chesscog's (Wölflein & Arandjelović, "Determining Chess
/// Game State from an Image", J. Imaging 2021; MIT), ported to Dart:
///
///  1. [locateBoard] finds the four board corners (board_locator.dart);
///  2. the board is warped flat and every square cut out twice, as chesscog
///     cuts them (square_crops.dart): a 100 x 100 crop for the occupancy
///     classifier, and for occupied squares a 100 x 200 crop reaching up over
///     the squares a standing piece covers in the photo;
///  3. two small CNNs (MobileNetV3-small, trained by tool/board_photo/ on
///     chesscog's synthetic renders plus permissively licensed real photos)
///     classify them — on native ONNX Runtime where dart:ffi exists, on the
///     pure-Dart interpreter elsewhere (and as a fallback);
///  4. unlike chesscog, which asks who took the photo, the orientation is
///     guessed: the light/dark square pattern fixes it up to a half turn
///     (h1 is light), the side the white pieces stand on settles the rest.
///
/// Input is raw RGBA, as for the diagram scanner (board_recognizer.dart):
/// decoding belongs to the caller. No widgets or dart:ui here, so it runs in
/// a background isolate (`compute`) and under `flutter test`. (The locator,
/// crops and geometry files import nothing but dart:math/typed_data and run
/// in plain Dart; this file reaches Flutter only through package:onnxruntime
/// on the native path.)
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

import '../board_recognizer.dart' show BoardRect, BoardRecognition;
import 'board_locator.dart';
import 'geometry.dart';
import 'image_ops.dart';
import 'photo_ort_stub.dart' if (dart.library.ffi) 'photo_ort_native.dart';
import 'square_crops.dart';

export 'board_locator.dart' show BoardNotLocatedException, LocatorConfig;
export 'geometry.dart' show Pt;

/// Occupancy classifier output order (chesscog's, alphabetical).
const List<String> photoOccupancyClasses = ['empty', 'occupied'];

/// Piece classifier output order (chesscog's class folders, alphabetical:
/// black_bishop, black_king, ... white_rook) as FEN letters.
const List<String> photoPieceClasses = [
  'b', 'k', 'n', 'p', 'q', 'r', 'B', 'K', 'N', 'P', 'Q', 'R', //
];

/// Asset paths the app is expected to ship the two models under.
/// Where the two classifiers are downloaded from on first use (12 MB
/// together, then cached; MIT, see the model card and NOTICE.md).
const String photoModelsBase =
    'https://huggingface.co/cstr/chess-board-photo-onnx/resolve/main';
const String photoOccupancyUrl = '$photoModelsBase/board_photo_occupancy.onnx';
const String photoPiecesUrl = '$photoModelsBase/board_photo_pieces.onnx';

/// The two classifier models, as ONNX bytes.
class BoardPhotoModels {
  final Uint8List occupancy;
  final Uint8List pieces;
  const BoardPhotoModels({required this.occupancy, required this.pieces});
}

/// Where the classifiers run.
enum PhotoBackend {
  /// Native ONNX Runtime when available, else the pure-Dart interpreter.
  auto,

  /// Always the pure-Dart interpreter (every platform, web included).
  dart,

  /// Native ONNX Runtime only; throws where it is unavailable.
  native,
}

/// The result of recognising one photo.
class BoardPhotoResult {
  /// Board corners in the input image's pixels, in image order: top left,
  /// top right, bottom right, bottom left.
  final List<Pt> corners;

  /// Probability that each grid cell (row 0 = top of the photo, col 0 =
  /// left) holds a piece.
  final List<double> pOccupied;

  /// Piece probabilities per grid cell, 64 x 12 in [photoPieceClasses]
  /// order; zeros for cells judged empty (the piece net never saw them).
  final Float64List pieceProbs;

  /// Quarter turns clockwise that bring the photo's grid to White's view
  /// (White at the bottom): 0 = photographed from White's side, 2 = from
  /// Black's, 1 / 3 = from the side (1: White sat on the photo's right,
  /// 3: on its left).
  final int rotation;

  /// How sure the orientation guess is, 0..1 (the colour-pattern contrast
  /// and the white/black side separation, whichever is weaker).
  final double orientationConfidence;

  /// Apply the rules every game position obeys when reading the classes
  /// off (see [decodePhotoGrid]).
  final bool rules;

  /// Milliseconds per stage: locate, crop, occupancy, pieces, total.
  final Map<String, int> timings;

  /// Which runtime classified the squares: `native` or `dart`.
  final String backend;

  /// Per grid cell, the FEN letter or `.` — as seen in the photo, before
  /// orientation.
  late final List<String> grid;

  /// Probability of [grid]'s choice per cell.
  late final List<double> gridConfidence;

  BoardPhotoResult({
    required this.corners,
    required this.pOccupied,
    required this.pieceProbs,
    required this.rotation,
    required this.orientationConfidence,
    required this.timings,
    required this.backend,
    this.rules = true,
  }) {
    final (g, c) =
        decodePhotoGrid(pOccupied, pieceProbs, rotation, rules: rules);
    grid = g;
    gridConfidence = c;
  }

  /// A result with certain classes, from a 64-letter grid — for tests and
  /// for re-rendering an edited position.
  factory BoardPhotoResult.fromGrid(List<String> grid,
      {int rotation = 0,
      List<Pt> corners = const [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1)]}) {
    final probs = Float64List(64 * photoPieceClasses.length);
    for (int i = 0; i < 64; i++) {
      final k = photoPieceClasses.indexOf(grid[i]);
      if (k >= 0) probs[i * photoPieceClasses.length + k] = 1;
    }
    return BoardPhotoResult(
        corners: corners,
        pOccupied: [for (final p in grid) p == '.' ? 0.0 : 1.0],
        pieceProbs: probs,
        rotation: rotation,
        orientationConfidence: 1,
        timings: const {},
        backend: 'none');
  }

  /// 64 FEN letters (`.` = empty) in a8..h8, a7..h7, ..., a1..h1 order.
  List<String> get squares =>
      [for (int i = 0; i < 64; i++) grid[gridIndexFor(i, rotation)]];

  /// Confidence per square, same order as [squares].
  List<double> get confidence =>
      [for (int i = 0; i < 64; i++) gridConfidence[gridIndexFor(i, rotation)]];

  /// The FEN piece-placement field.
  String get placement => placementOf(squares);

  /// The same recognition with the orientation turned by [quarterTurns]
  /// (clockwise) — for a UI "rotate" button when the guess was wrong.
  BoardPhotoResult rotated([int quarterTurns = 1]) => BoardPhotoResult(
        corners: corners,
        pOccupied: pOccupied,
        pieceProbs: pieceProbs,
        rotation: (rotation + quarterTurns) % 4,
        orientationConfidence: orientationConfidence,
        timings: timings,
        backend: backend,
        rules: rules,
      );

  /// As the diagram scanner's result type, so the scan screen's preview,
  /// warnings and editor work unchanged. [BoardRecognition.rect] is the
  /// corners' bounding box; `flipped` means photographed from Black's side.
  BoardRecognition toBoardRecognition() {
    double l = double.infinity, t = double.infinity;
    double r = -double.infinity, b = -double.infinity;
    for (final p in corners) {
      l = math.min(l, p.x);
      t = math.min(t, p.y);
      r = math.max(r, p.x);
      b = math.max(b, p.y);
    }
    return BoardRecognition(
      rect: BoardRect(l, t, r - l, b - t),
      squares: squares,
      confidence: confidence,
      flipped: rotation == 2,
    );
  }

  /// Grid cell (row * 8 + col) that chess square [i] (0 = a8 .. 63 = h1)
  /// comes from under [rotation].
  static int gridIndexFor(int i, int rotation) {
    final r = i ~/ 8, c = i % 8; // chess-view row / col, White at bottom
    switch (rotation % 4) {
      case 0:
        return r * 8 + c;
      case 2:
        return (7 - r) * 8 + (7 - c);
      case 1:
        // chess (r, c) <- grid rotated clockwise: grid (7 - c, r)
        return (7 - c) * 8 + r;
      default:
        return c * 8 + (7 - r);
    }
  }

  static String placementOf(List<String> squares) {
    final rows = <String>[];
    for (int r = 0; r < 8; r++) {
      final sb = StringBuffer();
      int run = 0;
      for (int c = 0; c < 8; c++) {
        final p = squares[r * 8 + c];
        if (p == '.') {
          run++;
        } else {
          if (run > 0) sb.write(run);
          run = 0;
          sb.write(p);
        }
      }
      if (run > 0) sb.write(run);
      rows.add(sb.toString());
    }
    return rows.join('/');
  }
}

abstract class _Classifier {
  String get name;
  Future<Float32List> run(Float32List input, List<int> shape);
  void dispose();
}

class _DartClassifier implements _Classifier {
  final OnnxModel _model;
  _DartClassifier(Uint8List bytes) : _model = OnnxModel.fromBytes(bytes);
  @override
  String get name => 'dart';
  @override
  Future<Float32List> run(Float32List input, List<int> shape) async {
    final out = await _model
        .runAsync({'input': Tensor.float(input, shape)}, ['logits']);
    return Float32List.fromList(out['logits']!.asFloatList());
  }

  @override
  void dispose() => _model.dispose();
}

class _NativeClassifier implements _Classifier {
  final NativePhotoModel _model;
  _NativeClassifier(Uint8List bytes, int threads)
      : _model = NativePhotoModel.load(bytes, threads: threads);
  @override
  String get name => 'native';
  @override
  Future<Float32List> run(Float32List input, List<int> shape) async =>
      _model.run(input, shape);
  @override
  void dispose() => _model.dispose();
}

/// Recognises physical boards in photos. Create once, reuse, [dispose].
class BoardPhotoRecognizer {
  final _Classifier _occupancy;
  final _Classifier _pieces;
  final LocatorConfig locatorConfig;

  BoardPhotoRecognizer._(this._occupancy, this._pieces, this.locatorConfig);

  /// Loads both models on [backend]. With [PhotoBackend.auto] a failure to
  /// load native ONNX Runtime (no library, web) falls back to pure Dart.
  factory BoardPhotoRecognizer(BoardPhotoModels models,
      {PhotoBackend backend = PhotoBackend.auto,
      int threads = 2,
      LocatorConfig locatorConfig = const LocatorConfig()}) {
    if (backend != PhotoBackend.dart && NativePhotoModel.isSupported) {
      try {
        return BoardPhotoRecognizer._(
            _NativeClassifier(models.occupancy, threads),
            _NativeClassifier(models.pieces, threads),
            locatorConfig);
      } catch (e) {
        if (backend == PhotoBackend.native) rethrow;
      }
    } else if (backend == PhotoBackend.native) {
      throw UnsupportedError('Native ONNX Runtime is not available here');
    }
    return BoardPhotoRecognizer._(_DartClassifier(models.occupancy),
        _DartClassifier(models.pieces), locatorConfig);
  }

  /// `native` or `dart`.
  String get backend => _occupancy.name;

  /// Recognises the board in [rgba] ([width] x [height]).
  ///
  /// [corners] (image order TL, TR, BR, BL, in [rgba]'s pixels) skips the
  /// locator — for a UI that lets the user drag the corners. [rotation]
  /// overrides the orientation guess. Throws [BoardNotLocatedException] when
  /// no board is found and no corners were given.
  Future<BoardPhotoResult> recognize(Uint8List rgba, int width, int height,
      {List<Pt>? corners,
      int? rotation,
      int seed = 0,
      bool rules = true}) async {
    final total = Stopwatch()..start();
    final sw = Stopwatch()..start();
    final timings = <String, int>{};
    final full = RgbImage.fromRgba(rgba, width, height);
    // chesscog locates and crops on the image resized to 1200 px wide.
    final (img, scale) =
        resizeForLocator(full, width: locatorConfig.resizeWidth);
    List<Pt> c;
    if (corners != null) {
      c = [for (final p in corners) Pt(p.x * scale, p.y * scale)];
    } else {
      c = locateBoardGray(img.toGray(), cfg: locatorConfig, seed: seed).corners;
    }
    timings['locate'] = sw.elapsedMilliseconds;
    sw.reset();

    final occWarp = warpForOccupancy(img, c);
    const on = 3 * occupancyCropSize * occupancyCropSize;
    final occIn = Float32List(64 * on);
    for (int i = 0; i < 64; i++) {
      cropToTensor(occupancyCrop(occWarp, i ~/ 8, i % 8), occupancyCropSize,
          occupancyCropSize, occIn, i * on);
    }
    timings['crop'] = sw.elapsedMilliseconds;
    sw.reset();
    final occLogits = await _occupancy
        .run(occIn, [64, 3, occupancyCropSize, occupancyCropSize]);
    final pOcc = List<double>.filled(64, 0);
    for (int i = 0; i < 64; i++) {
      pOcc[i] = _softmax(occLogits, i * 2, 2)[1];
    }
    timings['occupancy'] = sw.elapsedMilliseconds;
    sw.reset();

    final occupied = [
      for (int i = 0; i < 64; i++)
        if (pOcc[i] > 0.5) i
    ];
    const k = 12;
    final pieceProbs = Float64List(64 * k);
    if (occupied.isNotEmpty) {
      final pieceWarp = warpForPieces(img, c);
      const pn = 3 * pieceCropWidth * pieceCropHeight;
      final pIn = Float32List(occupied.length * pn);
      for (int j = 0; j < occupied.length; j++) {
        final i = occupied[j];
        cropToTensor(pieceCrop(pieceWarp, i ~/ 8, i % 8), pieceCropWidth,
            pieceCropHeight, pIn, j * pn);
      }
      final logits = await _pieces
          .run(pIn, [occupied.length, 3, pieceCropHeight, pieceCropWidth]);
      for (int j = 0; j < occupied.length; j++) {
        final p = _softmax(logits, j * k, k);
        pieceProbs.setAll(occupied[j] * k, p);
      }
    }
    timings['pieces'] = sw.elapsedMilliseconds;

    // Orientation from the plain argmax reading; the rules (which need to
    // know where the back ranks are) are applied for the chosen turn.
    final raw = decodePhotoGrid(pOcc, pieceProbs, 0, rules: false).$1;
    final (rot, rotConf) = rotation != null
        ? (rotation % 4, 1.0)
        : guessRotation(raw, squareTones(occWarp), pOcc);
    timings['total'] = total.elapsedMilliseconds;
    return BoardPhotoResult(
      corners: [for (final p in c) Pt(p.x / scale, p.y / scale)],
      pOccupied: pOcc,
      pieceProbs: pieceProbs,
      rotation: rot,
      orientationConfidence: rotConf,
      timings: timings,
      backend: backend,
      rules: rules,
    );
  }

  void dispose() {
    _occupancy.dispose();
    _pieces.dispose();
  }
}

/// One-shot convenience: load, recognise, dispose. For repeated use keep a
/// [BoardPhotoRecognizer].
Future<BoardPhotoResult> recognizePhoto(Uint8List rgba, int width, int height,
    {required BoardPhotoModels models,
    PhotoBackend backend = PhotoBackend.auto,
    List<Pt>? corners,
    int? rotation}) async {
  final r = BoardPhotoRecognizer(models, backend: backend);
  try {
    return await r.recognize(rgba, width, height,
        corners: corners, rotation: rotation);
  } finally {
    r.dispose();
  }
}

List<double> _softmax(Float32List v, int off, int n) {
  double mx = -double.infinity;
  for (int i = 0; i < n; i++) {
    mx = math.max(mx, v[off + i]);
  }
  final e = [for (int i = 0; i < n; i++) math.exp(v[off + i] - mx)];
  final s = e.fold<double>(0, (a, b) => a + b);
  return [for (final x in e) x / s];
}

/// Reads the classes off the network outputs: a cell is occupied when
/// [pOccupied] > 0.5, and then holds its likeliest piece. With [rules], the
/// facts every game position obeys override the networks where they are
/// unsure, with the board seen under [rotation]:
///
/// - no pawn on rank 1 or 8: the best non-pawn class instead;
/// - exactly one king per colour: of several, the likeliest keeps it and
///   the others take their next-best class; a missing king goes to the
///   occupied square likeliest to hold it (a real position always has both);
/// - at most eight pawns per colour: the least likely extras take their
///   next-best class.
///
/// Returns the grid letters and the probability of each choice.
(List<String>, List<double>) decodePhotoGrid(
    List<double> pOccupied, Float64List pieceProbs, int rotation,
    {bool rules = true}) {
  const k = 12;
  final grid = List<String>.filled(64, '.');
  final conf = List<double>.generate(64, (i) => 1 - pOccupied[i]);
  final occupied = [
    for (int i = 0; i < 64; i++)
      if (pOccupied[i] > 0.5) i
  ];
  final banned = {for (final i in occupied) i: <int>{}};
  final choice = <int, int>{};
  int best(int i) {
    int arg = -1;
    for (int j = 0; j < k; j++) {
      if (banned[i]!.contains(j)) continue;
      if (arg < 0 || pieceProbs[i * k + j] > pieceProbs[i * k + arg]) arg = j;
    }
    return arg < 0 ? 0 : arg;
  }

  if (rules) {
    final pawns = {
      photoPieceClasses.indexOf('P'),
      photoPieceClasses.indexOf('p')
    };
    for (int s = 0; s < 64; s++) {
      final rank = 8 - s ~/ 8;
      if (rank != 1 && rank != 8) continue;
      final cell = BoardPhotoResult.gridIndexFor(s, rotation);
      banned[cell]?.addAll(pawns);
    }
  }
  for (final i in occupied) {
    choice[i] = best(i);
  }
  if (rules) {
    void atMost(int cls, int n) {
      final holders = [
        for (final i in occupied)
          if (choice[i] == cls) i
      ]..sort(
          (a, b) => pieceProbs[b * k + cls].compareTo(pieceProbs[a * k + cls]));
      for (final i in holders.skip(n)) {
        banned[i]!.add(cls);
        choice[i] = best(i);
      }
    }

    for (final king in ['K', 'k'].map(photoPieceClasses.indexOf)) {
      atMost(king, 1);
      if (!occupied.any((i) => choice[i] == king)) {
        final kings = {
          photoPieceClasses.indexOf('K'),
          photoPieceClasses.indexOf('k')
        };
        int arg = -1;
        for (final i in occupied) {
          if (kings.contains(choice[i]) || banned[i]!.contains(king)) continue;
          if (arg < 0 ||
              pieceProbs[i * k + king] > pieceProbs[arg * k + king]) {
            arg = i;
          }
        }
        if (arg >= 0 && pieceProbs[arg * k + king] > 0.01) choice[arg] = king;
      }
    }
    for (final pawn in ['P', 'p'].map(photoPieceClasses.indexOf)) {
      atMost(pawn, 8);
    }
  }
  for (final i in occupied) {
    grid[i] = photoPieceClasses[choice[i]!];
    conf[i] = pOccupied[i] * pieceProbs[i * k + choice[i]!];
  }
  return (grid, conf);
}

/// Mean grey level of each grid cell's middle half (so piece bases and the
/// grid lines stay out), from a [warpForOccupancy] image; row-major.
List<double> squareTones(RgbImage occWarp) {
  final out = List<double>.filled(64, 0);
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      final x0 = photoSquare * (c + 1) + photoSquare ~/ 4;
      final y0 = photoSquare * (r + 1) + photoSquare ~/ 4;
      double s = 0;
      int n = 0;
      for (int y = y0; y < y0 + photoSquare ~/ 2; y++) {
        for (int x = x0; x < x0 + photoSquare ~/ 2; x++) {
          final i = (y * occWarp.width + x) * 3;
          s += 0.299 * occWarp.data[i] +
              0.587 * occWarp.data[i + 1] +
              0.114 * occWarp.data[i + 2];
          n++;
        }
      }
      out[r * 8 + c] = s / n;
    }
  }
  return out;
}

/// Guesses the quarter turns bringing the grid to White's view.
///
/// Square colours first: h1 (and a8) are light, so whether the light squares
/// sit on even or odd `row + col` says photographed from a player's side (0
/// or 2 turns) or from the side (1 or 3). Measured on the squares judged
/// empty, as a median, so pieces do not skew it. Then the side: the turn that
/// puts the white pieces lower on the board than the black ones, or, when
/// they hardly separate, White's side (0, or 1 for a side view). Returns the
/// rotation and a 0..1 confidence — below ~0.3 the UI should ask.
(int, double) guessRotation(
    List<String> grid, List<double> tones, List<double> pOccupied) {
  final even = <double>[], odd = <double>[];
  for (int i = 0; i < 64; i++) {
    if (pOccupied[i] > 0.5) continue;
    ((i ~/ 8 + i % 8).isEven ? even : odd).add(tones[i]);
  }
  double median(List<double> v) {
    if (v.isEmpty) return double.nan;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }

  final me = median(even), mo = median(odd);
  // Light squares on even row+col: the bottom-right cell (7,7) is light ->
  // photographed from a player's side.
  final candidates =
      me.isNaN || mo.isNaN ? [0, 1, 2, 3] : (me > mo ? [0, 2] : [1, 3]);
  final colourConf =
      me.isNaN || mo.isNaN ? 0.0 : math.min(1.0, (me - mo).abs() / 40);

  // White low, black high, in chess ranks.
  double sideScore(int rot) {
    double s = 0;
    int n = 0;
    for (int i = 0; i < 64; i++) {
      final p = grid[BoardPhotoResult.gridIndexFor(i, rot)];
      if (p == '.') continue;
      final rank = 7 - i ~/ 8; // 0 = rank 1
      final white = p.toUpperCase() == p;
      s += white ? (3.5 - rank) : (rank - 3.5);
      n++;
    }
    return n == 0 ? 0 : s / n;
  }

  int best = candidates.first;
  double bestScore = -double.infinity;
  for (final r in candidates) {
    final s = sideScore(r);
    if (s > bestScore) {
      bestScore = s;
      best = r;
    }
  }
  // Composed endgames can have the white king up the board: when the sides
  // barely separate, assume the usual photo, taken from White's side (or
  // with White on the right for a side view).
  if (bestScore < 0.3) best = candidates.first;
  final sideConf = math.min(1.0, bestScore.abs() / 2);
  return (best, math.min(colourConf, sideConf));
}
