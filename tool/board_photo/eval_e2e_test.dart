// End-to-end score of lib/vision/photo/ on labelled photos: locating the
// board, classifying the squares and guessing the orientation, exactly as the
// app runs them (the image decoded by dart:ui, recognised at full size).
//
//   BP_SET=labels.tsv [BP_ROOT=dir] [BP_BACKEND=dart|native] [BP_OUT=out.tsv] \
//   [BP_MODELS=dir] [BP_LIMIT=n] \
//     flutter test tool/board_photo/eval_e2e_test.dart
//
// labels.tsv: file <TAB> grid <TAB> rotation, one photo per line, where grid
// is the 64 cells as seen in the photo (row 0 = top, '.' empty, FEN letters)
// and rotation the true quarter turns to White's view, or -1 when unknown
// (then only the orientation-free grid is scored). tool/board_photo/py/
// make_eval_sets.py writes these for the chesscog, samryan and RF100 sets.
//
// For native ONNX Runtime set LD_LIBRARY_PATH to the directory holding
// libonnxruntime.so.1.15.1 (package:onnxruntime ships one under linux/).
//
// Lives outside test/ on purpose: a measurement that takes minutes, not a
// regression gate.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:ui' as ui;

import 'package:crispchess/vision/photo/board_photo_recognizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final set = env['BP_SET'];
  testWidgets('photo recognition end to end', (tester) async {
    await tester.runAsync(() async {
      final root = env['BP_ROOT'] ?? File(set!).parent.path;
      final modelDir = env['BP_MODELS'] ?? 'tool/board_photo/models';
      final backend = env['BP_BACKEND'] == 'native'
          ? PhotoBackend.native
          : env['BP_BACKEND'] == 'auto'
              ? PhotoBackend.auto
              : PhotoBackend.dart;
      final rec = BoardPhotoRecognizer(
          BoardPhotoModels(
              occupancy: File('$modelDir/board_photo_occupancy.onnx')
                  .readAsBytesSync(),
              pieces:
                  File('$modelDir/board_photo_pieces.onnx').readAsBytesSync()),
          backend: backend);
      final limit = int.tryParse(env['BP_LIMIT'] ?? '') ?? 1 << 30;
      final rows = File(set!)
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty && !l.startsWith('#'))
          .take(limit)
          .toList();
      final out = StringBuffer('file\tlocated\tgrid_ok\trot_true\trot_guess\t'
          'rot_conf\tpred_grid\ttimings\n');
      int n = 0, located = 0, cells = 0, cellsOk = 0, gridExact = 0;
      int le1 = 0, rotKnown = 0, rotOk = 0, fenExact = 0;
      int rawOk = 0, rawExact = 0; // without the chess rules
      final times = <String, List<int>>{};
      for (final line in rows) {
        final f = line.split('\t');
        final file = f[0], want = f[1], rotTrue = int.parse(f[2]);
        n++;
        final codec = await ui
            .instantiateImageCodec(File('$root/$file').readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        BoardPhotoResult r;
        try {
          r = await rec.recognize(
              bytes.buffer.asUint8List(), image.width, image.height);
        } on BoardNotLocatedException catch (e) {
          out.writeln('$file\t0\t0\t$rotTrue\t-\t-\t-\t${e.reason}');
          cells += 64;
          if (rotTrue >= 0) rotKnown++;
          continue;
        }
        located++;
        int ok = 0;
        for (int i = 0; i < 64; i++) {
          if (r.grid[i] == want[i]) ok++;
        }
        cells += 64;
        cellsOk += ok;
        if (ok == 64) gridExact++;
        final raw =
            decodePhotoGrid(r.pOccupied, r.pieceProbs, r.rotation, rules: false)
                .$1;
        int rok = 0;
        for (int i = 0; i < 64; i++) {
          if (raw[i] == want[i]) rok++;
        }
        rawOk += rok;
        if (rok == 64) rawExact++;
        if (ok >= 63) le1++;
        if (rotTrue >= 0) {
          rotKnown++;
          if (r.rotation == rotTrue) {
            rotOk++;
            if (ok == 64) fenExact++;
          }
        }
        for (final e in r.timings.entries) {
          times.putIfAbsent(e.key, () => []).add(e.value);
        }
        out.writeln('$file\t1\t$ok\t$rotTrue\t${r.rotation}\t'
            '${r.orientationConfidence.toStringAsFixed(2)}\t${r.grid.join()}\t'
            '${r.timings}');
      }
      rec.dispose();
      String med(List<int> v) {
        final s = [...v]..sort();
        return s.isEmpty ? '-' : '${s[s.length ~/ 2]}';
      }

      final summary = StringBuffer()
        ..writeln('== $set  backend=${rec.backend}')
        ..writeln('photos $n, located $located')
        ..writeln('squares ${(cellsOk / cells * 100).toStringAsFixed(2)} % '
            '(unlocated boards count as 64 wrong)')
        ..writeln('boards exact (grid) $gridExact/$n, <=1 wrong $le1/$n')
        ..writeln('without rules: squares '
            '${(rawOk / cells * 100).toStringAsFixed(2)} %, exact $rawExact/$n')
        ..writeln(rotKnown > 0
            ? 'orientation $rotOk/$rotKnown, exact FEN $fenExact/$rotKnown'
            : 'orientation unknown for this set')
        ..writeln('median ms: ${{
          for (final e in times.entries) e.key: med(e.value)
        }}');
      print(summary);
      final o = env['BP_OUT'];
      if (o != null) {
        File(o).writeAsStringSync(
            '$out${summary.toString().trim().split('\n').map((l) => '# $l').join('\n')}\n');
      }
    });
  }, skip: set == null, timeout: const Timeout(Duration(hours: 2)));
}
