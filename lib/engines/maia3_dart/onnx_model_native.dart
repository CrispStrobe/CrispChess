/// Native ONNX model for Maia3 — uses onnxruntime Flutter package.
///
/// Downloads model from HuggingFace and caches locally.
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:onnxruntime/onnxruntime.dart';

import 'onnx_model.dart';
import 'variants.dart';

/// Native implementation of Maia3 ONNX model.
class Maia3NativeOnnxModel extends Maia3OnnxModel {
  final Maia3Variant variant;
  OrtSession? _session;

  Maia3NativeOnnxModel({required this.variant});

  @override
  Future<void> load() async {
    debugPrint('[Maia3Dart/Native] Loading model: ${variant.onnxFile}');

    // Ensure model file exists locally
    final modelPath = await _ensureModel();

    // Initialize ONNX Runtime
    OrtEnv.instance.init();

    // Create session
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromFile(File(modelPath), sessionOptions);
    sessionOptions.release();

    debugPrint('[Maia3Dart/Native] Session ready');
  }

  Future<String> _ensureModel() async {
    final dir = await getApplicationSupportDirectory();
    final modelDir = Directory('${dir.path}/maia3_models');
    if (!modelDir.existsSync()) modelDir.createSync(recursive: true);

    final modelFile = File('${modelDir.path}/${variant.onnxFile}');

    if (modelFile.existsSync()) {
      debugPrint('[Maia3Dart/Native] Model cached at ${modelFile.path}');
      return modelFile.path;
    }

    // Download from HuggingFace
    debugPrint('[Maia3Dart/Native] Downloading ${variant.url}...');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(variant.url));
      final response = await request.close();

      if (response.statusCode == 302 || response.statusCode == 301) {
        // Follow redirect
        final redirect = response.headers.value('location');
        if (redirect != null) {
          final redirectRequest = await client.getUrl(Uri.parse(redirect));
          final redirectResponse = await redirectRequest.close();
          await _writeResponseToFile(redirectResponse, modelFile);
        }
      } else {
        await _writeResponseToFile(response, modelFile);
      }

      debugPrint('[Maia3Dart/Native] Downloaded to ${modelFile.path}');
      return modelFile.path;
    } finally {
      client.close();
    }
  }

  Future<void> _writeResponseToFile(
      HttpClientResponse response, File file) async {
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.close();
  }

  @override
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo) async {
    if (_session == null) throw StateError('Model not loaded');

    // Create input tensors
    // tokens: [1, 64, 96]
    final tokensTensor = OrtValueTensor.createTensorWithDataList(
      tokens,
      [1, 64, 96],
    );

    // self_elo: [1] int64
    final selfEloTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList([selfElo]),
      [1],
    );

    // oppo_elo: [1] int64
    final oppoEloTensor = OrtValueTensor.createTensorWithDataList(
      Int64List.fromList([oppoElo]),
      [1],
    );

    // Run inference
    final inputs = {
      'tokens': tokensTensor,
      'self_elo': selfEloTensor,
      'oppo_elo': oppoEloTensor,
    };

    final results = await (_session!.runAsync(
      OrtRunOptions(),
      inputs,
    ) ?? Future.value(<OrtValue?>[]));

    // Extract outputs
    final moveLogitsRaw = results[0]?.value as List;
    final valueLogitsRaw = results[1]?.value as List;

    // Flatten from [[...]] to [...]
    final moveLogits = Float32List.fromList(
      (moveLogitsRaw[0] as List).cast<double>().map((d) => d.toDouble()).toList(),
    );
    final valueLogits = Float32List.fromList(
      (valueLogitsRaw[0] as List).cast<double>().map((d) => d.toDouble()).toList(),
    );

    // Release tensors
    tokensTensor.release();
    selfEloTensor.release();
    oppoEloTensor.release();
    for (final r in results) {
      r?.release();
    }

    return InferenceResult(logitsMove: moveLogits, logitsValue: valueLogits);
  }

  @override
  Future<void> close() async {
    _session?.release();
    _session = null;
  }
}
