// Parity test: the legacy direct-executor wiring (maia3_dart/onnx_model_dart
// .dart, the oracle) vs the new onnx_runtime_dart `OnnxModel` backend
// (maia3_dart/onnx_runtime_backend.dart). Both load the same local .onnx
// file, get identical deterministic tokens/elos, and must agree to cosine
// similarity > 0.999999 on logits_move and logits_value.
//
// Fully offline: it only runs when a maia3*.onnx file already exists on this
// machine (onnx_runtime_dart's model cache, or a previous app run's cache);
// otherwise it skips with a message rather than downloading 22 MB.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/maia3_dart/encoding.dart';
import 'package:crispchess/engines/maia3_dart/history.dart';
import 'package:crispchess/engines/maia3_dart/onnx_model_dart.dart';
import 'package:crispchess/engines/maia3_dart/onnx_runtime_backend.dart';
import 'package:crispchess/engines/maia3_dart/variants.dart';

/// Looks for an already-downloaded Maia3 model — never downloads.
File? _findLocalModel(Maia3Variant variant) {
  final home = Platform.environment['HOME'] ?? '';
  final candidateDirs = [
    '$home/.cache/onnx_runtime_dart_models',
    '$home/.cache',
    '$home/Library/Application Support/com.example.crispchess/maia3_models',
    '$home/Library/Application Support/crispchess/maia3_models',
  ];
  // Exact variant file first, then any maia3*.onnx as a fallback (parity
  // only needs both backends to read the *same* file).
  for (final exactFirst in [true, false]) {
    for (final dirPath in candidateDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        final matches = exactFirst
            ? name == variant.onnxFile
            : name.startsWith('maia3') && name.endsWith('.onnx');
        if (matches) return entry;
      }
    }
  }
  return null;
}

double _cosine(Float32List a, Float32List b) {
  expect(b.length, a.length);
  double dot = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (sqrt(na) * sqrt(nb));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const variantId = '5m';
  final variant = getVariant(variantId);
  final modelFile = _findLocalModel(variant);

  // Point the engines' own cache (path_provider-based) at a temp dir that
  // already contains the model, so both backends run their real load path —
  // fetchModelBytes — and hit the cache instead of the network.
  final tempDir = Directory.systemTemp.createTempSync('maia3_parity_');
  if (modelFile != null) {
    final cacheDir = Directory('${tempDir.path}/maia3_models')
      ..createSync(recursive: true);
    Link('${cacheDir.path}/${variant.onnxFile}')
        .createSync(modelFile.absolute.path);
  }
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );

  test('legacy interpreter wiring and OnnxModel backend agree on logits',
      () async {
    final oracle = Maia3DartOnnxModel(variant: variant);
    final backend = Maia3OnnxRuntimeBackend(variant: variant);
    await oracle.load();
    await backend.load();
    addTearDown(oracle.close);
    addTearDown(backend.close);

    // Deterministic inputs through the real encoding: the start position,
    // and a position with actual history (exercises all 8 token slots'
    // padding logic identically for both backends).
    final cases = <(String, List<String>?, int, int)>[
      ('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', null, 1500,
          1500),
      (
        'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
        [
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        ],
        1100,
        1900,
      ),
    ];

    for (final (fen, priorFens, selfElo, oppoElo) in cases) {
      final boards = resolveHistory(HistoryInput(fen: fen, priorFens: priorFens));
      final tokens = buildHistoryTokens(boards);

      final expected = await oracle.infer(tokens, selfElo, oppoElo);
      final actual = await backend.infer(tokens, selfElo, oppoElo);

      final moveCos = _cosine(expected.logitsMove, actual.logitsMove);
      final valueCos = _cosine(expected.logitsValue, actual.logitsValue);
      print('parity fen="$fen" elo=$selfElo/$oppoElo: '
          'cos(logits_move)=$moveCos cos(logits_value)=$valueCos');

      expect(moveCos, greaterThan(0.999999));
      expect(valueCos, greaterThan(0.999999));
    }

    // inferBatch must equal per-position infer: the maia3 exports are
    // batch-fixed (native onnxruntime rejects tokens [N,64,96] for N > 1),
    // so any future single-graph-run batching would silently blend
    // positions — this pins the sequential semantics.
    final batchBoards = [
      for (final (fen, priorFens, _, _) in cases)
        resolveHistory(HistoryInput(fen: fen, priorFens: priorFens)),
    ];
    final batchTokens = [for (final b in batchBoards) buildHistoryTokens(b)];
    final selfElos = [for (final (_, _, s, _) in cases) s];
    final oppoElos = [for (final (_, _, _, o) in cases) o];
    final batched =
        await backend.inferBatch(batchTokens, selfElos, oppoElos);
    for (int i = 0; i < cases.length; i++) {
      final single =
          await backend.infer(batchTokens[i], selfElos[i], oppoElos[i]);
      expect(_cosine(batched[i].logitsMove, single.logitsMove),
          greaterThan(0.999999),
          reason: 'inferBatch[$i] must match single-position infer');
    }
  },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: modelFile == null
          ? 'No local maia3*.onnx model found (looked in ~/.cache and the '
              'app model caches) — run once with network, or drop '
              '${variant.onnxFile} into ~/.cache/onnx_runtime_dart_models/, '
              'then re-run.'
          : false);
}
