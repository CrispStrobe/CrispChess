/// How long a Maia forward pass takes, and where the time goes.
///
/// The network is 76 MFLOP — about the work of one small image filter. If a
/// pass costs 300ms that is 0.25 GFLOP/s, which is one to two orders of
/// magnitude below what a CPU core does on a `Float32List`, and it means the
/// engine gets a single evaluation inside a 300ms move budget: no search, just
/// the network's first opinion.
///
///   dart run tool/oracle/bench.dart --model maia-1900.onnx [--iterations 20]
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/lc0_dart/encoding.dart';
import 'package:onnx_runtime_dart/onnx_runtime_dart.dart';

/// 76.3 MFLOP, counted from the graph: 2 * Cout * Cin * kh * kw * 8 * 8 per
/// convolution, 2 * m * n per matmul.
const double _mflops = 76.3;

Future<double> _time(OnnxModel model, Float32List planes, int iterations,
    {ExecutionProfile? profile, bool useAsync = false}) async {
  // One untimed pass so lazily built buffers are not charged to the first
  // measurement.
  if (useAsync) {
    await model.runAsync(
        {'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
        ['/output/policy', '/output/wdl']);
  } else {
    model.run({'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
        ['/output/policy', '/output/wdl']);
  }

  final watch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    if (useAsync) {
      await model.runAsync(
          {'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
          ['/output/policy', '/output/wdl'],
          profile: profile);
    } else {
      model.run({'/input/planes': Tensor.float(planes, [1, 112, 8, 8])},
          ['/output/policy', '/output/wdl'],
          profile: profile);
    }
  }
  watch.stop();
  return watch.elapsedMicroseconds / 1000.0 / iterations;
}

void _report(String label, double ms) {
  final gflops = _mflops / 1000.0 / (ms / 1000.0);
  final perBudget = (300.0 / ms).floor();
  stdout.writeln('  ${label.padRight(34)}${ms.toStringAsFixed(1).padLeft(8)} ms'
      '${gflops.toStringAsFixed(2).padLeft(8)} GFLOP/s'
      '${perBudget.toString().padLeft(5)} evals per 300ms');
}

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final path = arg('model', '');
  if (path.isEmpty) {
    stderr.writeln('usage: bench.dart --model <weights.onnx>');
    exit(2);
  }
  final iterations = int.parse(arg('iterations', '20'));
  final bytes = File(path).readAsBytesSync();
  final planes = encodePosition(chess.Chess().fen);

  stdout.writeln('${path.split('/').last}, '
      '${(bytes.length / 1048576).toStringAsFixed(1)} MB, '
      '${_mflops.toStringAsFixed(1)} MFLOP per pass, '
      '$iterations iterations, ${Platform.numberOfProcessors} cores\n');

  // Single-threaded, which is what the graph does with no pool attached.
  final plain = OnnxModel.fromBytes(bytes);
  final profile = ExecutionProfile();
  final baseline = await _time(plain, planes, iterations, profile: profile);
  _report('single isolate', baseline);
  plain.dispose();

  // What the app asks for today: a pool that takes matmuls only. This model's
  // matmuls are 0.7% of its arithmetic, so the workers have almost nothing to
  // do and the convolutions stay on one core.
  for (final workers in [2, 4]) {
    final model = OnnxModel.fromBytes(bytes);
    await model.parallelize(workers: workers);
    _report('$workers workers, matmul only (today)',
        await _time(model, planes, iterations, useAsync: true));
    model.dispose();
  }

  // Convolutions in the pool as well — 99% of the arithmetic. The package
  // warns that the activation copying can outweigh the parallel compute, so
  // this is measured rather than assumed.
  for (final workers in [2, 4]) {
    final model = OnnxModel.fromBytes(bytes);
    await model.parallelize(workers: workers, poolConv: true);
    _report('$workers workers, convolutions too',
        await _time(model, planes, iterations, useAsync: true));
    model.dispose();
  }

  stdout.writeln('\nwhere a single-isolate pass goes:\n');
  stdout.writeln(profile.report());
  final maxCore = max(1.0, _mflops / 1000.0 / (baseline / 1000.0));
  stdout.writeln('one evaluation at ${baseline.toStringAsFixed(0)}ms leaves '
      '${(300 / baseline).floor()} per 300ms move budget '
      '(${maxCore.toStringAsFixed(2)} GFLOP/s on one core)');
}
