// End-to-end score of lib/vision/board_recognizer.dart on bench.py boards:
// detection, classification and orientation, exactly as the app runs them.
//
//   python3 tool/board_vision/bench.py --out /tmp/bv_bench
//   BV_BENCH=/tmp/bv_bench [BV_OUT=per_board.tsv] \
//     flutter test tool/board_vision/bench_e2e_test.dart
//
// Lives outside test/ on purpose: it takes minutes and is a measurement, not
// a regression gate.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crispchess/vision/board_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dir = Platform.environment['BV_BENCH'];
  // Optional per-board results: file, found rect, squares right.
  final outPath = Platform.environment['BV_OUT'];

  testWidgets('bench end to end', (tester) async {
    await tester.runAsync(() async {
      final recognizer = BoardRecognizer(
          File('assets/models/board_squares.onnx').readAsBytesSync());
      final rows = File('$dir/labels.tsv').readAsLinesSync().skip(1);
      final perStyle = <String, List<int>>{}; // boards, exact, squares, found
      final watch = Stopwatch()..start();
      final out = StringBuffer('file\tleft\ttop\twidth\theight\tok\n');
      for (final line in rows) {
        final f = line.split('\t');
        final codec = await ui
            .instantiateImageCodec(File('$dir/${f[0]}').readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final st = perStyle.putIfAbsent(f[2], () => [0, 0, 0, 0]);
        st[0]++;
        try {
          final r = await recognizer.recognize(
              bytes.buffer.asUint8List(), image.width, image.height);
          st[3]++;
          final want = _squares(f[1]);
          int ok = 0;
          for (int i = 0; i < 64; i++) {
            if (r.squares[i] == want[i]) ok++;
          }
          st[2] += ok;
          if (ok == 64) st[1]++;
          out.writeln('${f[0]}\t${r.rect.left.toStringAsFixed(1)}\t'
              '${r.rect.top.toStringAsFixed(1)}\t'
              '${r.rect.width.toStringAsFixed(1)}\t'
              '${r.rect.height.toStringAsFixed(1)}\t$ok');
        } on BoardNotFoundException {
          // counted as found = 0, squares = 0
          out.writeln('${f[0]}\t\t\t\t\t-1');
        }
      }
      final total = [0, 0, 0, 0];
      for (final e in perStyle.entries) {
        final s = e.value;
        for (int i = 0; i < 4; i++) {
          total[i] += s[i];
        }
        // ignore: avoid_print
        print(
            '${e.key.padRight(20)} found ${s[3]}/${s[0]}  exact ${s[1]}/${s[0]}'
            '  squares ${(100 * s[2] / (64 * s[0])).toStringAsFixed(2)}%');
      }
      // ignore: avoid_print
      print('${'all'.padRight(20)} found ${total[3]}/${total[0]}  exact '
          '${total[1]}/${total[0]}  squares '
          '${(100 * total[2] / (64 * total[0])).toStringAsFixed(2)}%  '
          '${watch.elapsedMilliseconds ~/ total[0]} ms/board');
      if (outPath != null) File(outPath).writeAsStringSync(out.toString());
      recognizer.dispose();
    });
  },
      skip: dir == null, // set BV_BENCH to a bench.py output directory
      timeout: const Timeout(Duration(minutes: 30)));
}

List<String> _squares(String placement) => [
      for (final ch in placement.replaceAll('/', '').split(''))
        ...(int.tryParse(ch) != null ? List.filled(int.parse(ch), '.') : [ch]),
    ];
