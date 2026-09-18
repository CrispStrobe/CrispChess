/// How long a Maia forward pass takes, on each backend and at each batch size.
///
///   flutter test tool/perf/inference_bench.dart --timeout none
///
/// The Lc0 engine's strength tracks how many positions it can evaluate inside
/// a move budget almost linearly — measured at roughly +160 Elo per four-fold
/// increase — so this is the number that decides how well it plays.
///
/// Runs under `flutter test` rather than `dart run` because the native runtime
/// is a Flutter plugin: a plain Dart VM cannot load it, which is also why the
/// first version of this benchmark could only ever see the Dart path. Both
/// backends are driven through the same interface the engine uses, so the
/// figures describe what ships. Where the native runtime is missing this says
/// so and carries on — that is the answer for users on that platform, not a
/// reason to stop.
///
/// Environment:
///   BENCH_MODEL       path to a .onnx file (required)
///   BENCH_ITERATIONS  timed runs per batch size (default 25)
///   BENCH_BATCHES     comma-separated batch sizes (default 1,2,4,8,16)
///   BENCH_WORKERS     isolate workers / intra-op threads (default 4)
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:crispchess/engines/lc0_dart/inference_backend.dart';
import 'package:crispchess/engines/lc0_dart/native_inference_backend.dart';
import 'package:flutter_test/flutter_test.dart';

/// 76.3 MFLOP, counted from the graph: 2 * Cout * Cin * kh * kw * 8 * 8 per
/// convolution, 2 * m * n per matmul.
const double _mflopsPerPosition = 76.3;

/// The move budget the strength tournament uses, so "positions per budget"
/// means the same thing in both places.
const int _budgetMs = 300;

String _env(String name, String fallback) =>
    Platform.environment[name]?.trim().isNotEmpty == true
        ? Platform.environment[name]!.trim()
        : fallback;

/// Planes for [batchSize] copies of the opening position.
///
/// The content does not affect timing — the graph has no data-dependent
/// branches — but the layout does: a batch has to be one contiguous block,
/// the way the engine assembles it from the leaves it wants evaluated.
Float32List _batchedPlanes(int batchSize) {
  final one = encodePosition(chess.Chess().fen);
  final all = Float32List(one.length * batchSize);
  for (var i = 0; i < batchSize; i++) {
    all.setRange(i * one.length, (i + 1) * one.length, one);
  }
  return all;
}

Future<double> _msPerPosition(
    Lc0InferenceBackend backend, int batchSize, int iterations) async {
  final planes = _batchedPlanes(batchSize);
  await backend.run(planes, batchSize); // warm the lazily built buffers

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    await backend.run(planes, batchSize);
  }
  watch.stop();
  return watch.elapsedMicroseconds / 1000.0 / iterations / batchSize;
}

Future<void> _measure(String label, Uint8List bytes, List<int> batches,
    int iterations, Future<Lc0InferenceBackend> Function() create) async {
  Lc0InferenceBackend backend;
  try {
    backend = await create();
  } catch (e) {
    stdout.writeln('  $label: unavailable here — $e\n');
    return;
  }

  stdout.writeln('  $label');
  stdout.writeln('    ${'batch'.padLeft(6)}${'ms/position'.padLeft(14)}'
      '${'GFLOP/s'.padLeft(10)}${'per ${_budgetMs}ms'.padLeft(14)}'
      '${'vs batch 1'.padLeft(12)}');
  double? single;
  for (final batch in batches) {
    final ms = await _msPerPosition(backend, batch, iterations);
    single ??= ms;
    stdout.writeln('    ${batch.toString().padLeft(6)}'
        '${ms.toStringAsFixed(2).padLeft(14)}'
        '${(_mflopsPerPosition / ms).toStringAsFixed(2).padLeft(10)}'
        '${(_budgetMs / ms).floor().toString().padLeft(14)}'
        '${'${(single / ms).toStringAsFixed(2)}x'.padLeft(12)}');
  }
  stdout.writeln();
  backend.dispose();
}

void main() {
  test('inference', () async {
    final path = _env('BENCH_MODEL', '');
    if (path.isEmpty || !File(path).existsSync()) {
      stdout.writeln('BENCH_MODEL is not set to a readable .onnx file — '
          'nothing to measure');
      return;
    }
    final iterations = int.parse(_env('BENCH_ITERATIONS', '25'));
    final batches =
        _env('BENCH_BATCHES', '1,2,4,8,16').split(',').map(int.parse).toList();
    final workers = int.parse(_env('BENCH_WORKERS', '4'));
    final bytes = File(path).readAsBytesSync();

    stdout.writeln('${path.split('/').last}, '
        '${(bytes.length / 1048576).toStringAsFixed(1)} MB, '
        '${_mflopsPerPosition.toStringAsFixed(1)} MFLOP per position, '
        '$iterations iterations, ${Platform.numberOfProcessors} cores, '
        '$workers workers\n');

    await _measure('native ONNX Runtime', bytes, batches, iterations,
        () async => NativeLc0InferenceBackend.create(bytes, workers));
    await _measure('pure Dart', bytes, batches, iterations,
        () => DartLc0InferenceBackend.create(bytes, workers));
  }, timeout: const Timeout(Duration(minutes: 30)));
}
