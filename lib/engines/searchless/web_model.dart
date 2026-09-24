/// Searchless-chess transformer on ONNX Runtime Web (web only), through
/// web/searchless_onnx_bridge.js — several times faster in the browser than
/// the pure-Dart interpreter for this graph.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'model.dart';

@JS('searchlessOnnxLoad')
external JSPromise<JSAny?> _load(JSString key, JSString url);

@JS('searchlessOnnxInfer')
external JSPromise<JSFloat32Array> _infer(JSString key, JSInt32Array tokens, JSNumber rows);

@JS('searchlessOnnxClose')
external JSPromise<JSAny?> _close(JSString key);

class WebSearchlessModel implements SearchlessModel {
  final String key;
  WebSearchlessModel._(this.key);

  static bool get isSupported => true;

  static Future<WebSearchlessModel> load(String key, String url) async {
    await _load(key.toJS, url.toJS).toDart;
    return WebSearchlessModel._(key);
  }

  @override
  Future<Float32List> run(Int64List tokens, int rows) async {
    final ints = Int32List.fromList(tokens);
    final out = await _infer(key.toJS, ints.toJS, rows.toJS).toDart;
    return out.toDart;
  }

  @override
  void dispose() => _close(key.toJS);
}
