// Score lib/vision/board_recognizer.dart on a folder of real diagrams whose
// file names are their piece placement: ranks joined by '-', digits or runs
// of '1' for empty squares, e.g. `rnbqkbnr-pppppppp-8-8-8-8-PPPPPPPP-RNBQKBNR.png`
// (a trailing '+' before the extension is ignored). The layout of
// github.com/tsoj/Chess_diagram_to_FEN's test images.
//
//   BV_REAL=/path/to/img [BV_MODEL=model.onnx] [BV_OUT=out.tsv] \
//     flutter test tool/board_vision/real_eval_test.dart
//
// A board counts as correct when it matches as read or turned 180 degrees
// (the file names do not say which side is at the bottom). Measurement only,
// not a regression gate — the images are third-party and not in the repo.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crispchess/vision/board_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['BV_REAL'];
  final modelPath =
      Platform.environment['BV_MODEL'] ?? 'assets/models/board_squares.onnx';
  final outPath = Platform.environment['BV_OUT'];

  testWidgets('real diagrams', (tester) async {
    await tester.runAsync(() async {
      final recognizer = BoardRecognizer(File(modelPath).readAsBytesSync());
      final files = Directory(dir!)
          .listSync()
          .whereType<File>()
          .where((f) =>
              RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(f.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      final out = StringBuffer('file\tfound\tleft\ttop\tsize\tok\tread\n');
      int found = 0, exact = 0, squares = 0;
      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final want = _fromName(name);
        final codec = await ui.instantiateImageCodec(f.readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        try {
          final r = await recognizer.recognize(
              bytes.buffer.asUint8List(), image.width, image.height);
          found++;
          int a = 0, b = 0;
          for (int i = 0; i < 64; i++) {
            if (r.squares[i] == want[i]) a++;
            if (r.squares[63 - i] == want[i]) b++;
          }
          final ok = a > b ? a : b;
          squares += ok;
          if (ok == 64) exact++;
          out.writeln('$name\t1\t${r.rect.left.toStringAsFixed(0)}\t'
              '${r.rect.top.toStringAsFixed(0)}\t'
              '${r.rect.width.toStringAsFixed(0)}\t$ok\t${r.placement}');
        } on BoardNotFoundException {
          out.writeln('$name\t0\t\t\t\t0\t');
        }
      }
      if (outPath != null) File(outPath).writeAsStringSync(out.toString());
      // ignore: avoid_print
      print('found $found/${files.length}  exact $exact/${files.length}  '
          'squares of found ${(100 * squares / (64 * found)).toStringAsFixed(1)}%'
          '  squares of all '
          '${(100 * squares / (64 * files.length)).toStringAsFixed(1)}%');
      recognizer.dispose();
    });
  }, skip: dir == null, timeout: const Timeout(Duration(minutes: 30)));
}

List<String> _fromName(String name) {
  var stem = name.substring(0, name.lastIndexOf('.'));
  if (stem.endsWith('+')) stem = stem.substring(0, stem.length - 1);
  final out = <String>[];
  for (final rank in stem.split('-')) {
    for (final ch in rank.split('')) {
      final n = int.tryParse(ch);
      out.addAll(n != null ? List.filled(n, '.') : [ch]);
    }
  }
  if (out.length != 64) throw FormatException('not a placement: $name');
  return out;
}
