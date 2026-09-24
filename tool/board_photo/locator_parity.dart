// Corner parity of lib/vision/photo/board_locator.dart against chesscog's
// Python localiser.
//
//   python3 tool/board_photo/py/chesscog_ref.py --out REF img...   # PPM + JSON
//   dart run tool/board_photo/locator_parity.dart REF [seeds]
//
// For every <stem>.ppm/<stem>.json pair in REF it runs the Dart locator with
// [seeds] RANSAC seeds (default 3) and prints the largest corner distance to
// Python's seed-0 answer, and to the nearest of Python's seeds (the RANSAC is
// random on both sides, so Python disagrees with itself too — its own spread
// is printed alongside). Plain Dart: no Flutter needed.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crispchess/vision/photo/board_locator.dart';
import 'package:crispchess/vision/photo/geometry.dart';
import 'package:crispchess/vision/photo/image_ops.dart';

RgbImage readPpm(String path) {
  final b = File(path).readAsBytesSync();
  int pos = 0;
  String token() {
    while (
        b[pos] == 0x20 || b[pos] == 0x0a || b[pos] == 0x0d || b[pos] == 0x09) {
      pos++;
    }
    if (b[pos] == 0x23) {
      while (b[pos] != 0x0a) {
        pos++;
      }
      return token();
    }
    final s = pos;
    while (b[pos] > 0x20) {
      pos++;
    }
    return String.fromCharCodes(b.sublist(s, pos));
  }

  if (token() != 'P6') throw FormatException('not a binary PPM: $path');
  final w = int.parse(token()), h = int.parse(token());
  token(); // maxval
  pos++;
  return RgbImage(w, h, Uint8List.fromList(b.sublist(pos, pos + w * h * 3)));
}

double cornerDist(List<Pt> a, List a2) {
  double m = 0;
  for (int i = 0; i < 4; i++) {
    final dx = a[i].x - (a2[i][0] as num), dy = a[i].y - (a2[i][1] as num);
    m = math.max(m, math.sqrt(dx * dx + dy * dy));
  }
  return m;
}

void main(List<String> args) {
  final dir = args[0];
  final seeds = args.length > 1 ? int.parse(args[1]) : 3;
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .map((f) => f.path)
      .toList()
    ..sort();
  final d0s = <double>[], dbest = <double>[];
  int both = 0, onlyPy = 0, onlyDart = 0, none = 0;
  int totalMs = 0, runs = 0;
  print(
      'image\tdart_vs_py0_px\tdart_vs_nearest_py_px\tpy_spread_px\tms\tstats');
  for (final jf in files) {
    final stem = jf.substring(0, jf.length - 5);
    if (!File('$stem.ppm').existsSync()) continue;
    final ref = jsonDecode(File(jf).readAsStringSync()) as Map;
    final pyRuns = [
      for (final r in ref['runs'] as List)
        if (r['corners'] != null) r['corners'] as List
    ];
    final img = readPpm('$stem.ppm');
    final gray = img.toGray();
    for (int s = 0; s < seeds; s++) {
      final sw = Stopwatch()..start();
      BoardCorners? r;
      String err = '';
      try {
        r = locateBoardGray(gray, seed: s);
      } on BoardNotLocatedException catch (e) {
        err = e.reason;
      }
      final ms = sw.elapsedMilliseconds;
      totalMs += ms;
      runs++;
      final name = stem.split('/').last;
      if (r == null && pyRuns.isEmpty) {
        none++;
        print('$name#$s\t-\t-\t-\t$ms\tboth failed ($err)');
        continue;
      }
      if (r == null) {
        onlyPy++;
        print('$name#$s\tDART FAIL\t-\t${ref['seed_spread_px']}\t$ms\t$err');
        continue;
      }
      if (pyRuns.isEmpty) {
        onlyDart++;
        print('$name#$s\tPY FAIL\t-\t-\t$ms\t${r.stats}');
        continue;
      }
      both++;
      final d0 = ref['corners'] == null
          ? double.nan
          : cornerDist(r.corners, ref['corners'] as List);
      final dn = pyRuns.map((p) => cornerDist(r!.corners, p)).reduce(math.min);
      d0s.add(d0);
      dbest.add(dn);
      print('$name#$s\t${d0.toStringAsFixed(2)}\t${dn.toStringAsFixed(2)}\t'
          '${(ref['seed_spread_px'] as num?)?.toStringAsFixed(2)}\t$ms\t${r.stats}');
    }
  }
  String q(List<double> v) {
    final s = [...v.where((e) => !e.isNaN)]..sort();
    if (s.isEmpty) return '-';
    double at(double p) => s[((s.length - 1) * p).round()];
    int within(double t) => s.where((e) => e <= t).length;
    return 'median ${at(0.5).toStringAsFixed(2)} p90 ${at(0.9).toStringAsFixed(2)} '
        'max ${s.last.toStringAsFixed(2)}; <=3px ${within(3)}/${s.length}, '
        '<=5px ${within(5)}/${s.length}, <=10px ${within(10)}/${s.length}';
  }

  print('== runs $runs: both found $both, Dart-only fail $onlyPy, '
      'Python-only fail $onlyDart, both fail $none; '
      'mean ${(totalMs / math.max(1, runs)).toStringAsFixed(0)} ms/run');
  print('== vs Python seed 0:        ${q(d0s)}');
  print('== vs nearest Python seed:  ${q(dbest)}');
}
