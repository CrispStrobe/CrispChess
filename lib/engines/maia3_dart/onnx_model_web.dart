/// Web ONNX model for Maia3 — uses a thin JS bridge for raw inference.
///
/// The bridge (maia3_onnx_bridge.js) handles ONNX Runtime Web session
/// management. This Dart code handles tokenization and sampling.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'onnx_model.dart';
import 'variants.dart';

// JS bridge functions (defined in web/maia3_onnx_bridge.js)
@JS('maia3OnnxLoad')
external JSPromise<JSAny?> _jsOnnxLoad(JSString modelUrl);

// Returns Float32Array of 4355 elements: [moveLogits(4352), valueLogits(3)]
@JS('maia3OnnxInfer')
external JSPromise<JSFloat32Array> _jsOnnxInfer(
    JSFloat32Array tokens, JSNumber selfElo, JSNumber oppoElo);

@JS('maia3OnnxClose')
external JSPromise<JSAny?> _jsOnnxClose();

/// Web implementation of Maia3 ONNX model.
class Maia3WebOnnxModel extends Maia3OnnxModel {
  final Maia3Variant variant;

  Maia3WebOnnxModel({required this.variant});

  @override
  Future<void> load() async {
    debugPrint('[Maia3Dart/Web] Loading model: ${variant.url}');
    try {
      await _jsOnnxLoad(variant.url.toJS).toDart;
      debugPrint('[Maia3Dart/Web] Model loaded');
    } catch (e) {
      debugPrint('[Maia3Dart/Web] Failed: $e');
      rethrow;
    }
  }

  @override
  Future<InferenceResult> infer(
      Float32List tokens, int selfElo, int oppoElo) async {
    try {
      // Bridge returns a single Float32Array: [moveLogits(4352), valueLogits(3)]
      final combined = (await _jsOnnxInfer(
        tokens.toJS,
        selfElo.toJS,
        oppoElo.toJS,
      ).toDart).toDart;

      // Split into move and value logits
      final moveLogits = Float32List.sublistView(combined, 0, 4352);
      final valueLogits = Float32List.sublistView(combined, 4352, 4355);

      return InferenceResult(
        logitsMove: moveLogits,
        logitsValue: valueLogits,
      );
    } catch (e) {
      debugPrint('[Maia3Dart/Web] Inference error: $e');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _jsOnnxClose().toDart;
    } catch (_) {}
  }
}
