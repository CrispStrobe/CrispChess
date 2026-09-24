/// Stand-in for web_model.dart off the web.
library;

import 'dart:typed_data';

import 'model.dart';

class WebSearchlessModel implements SearchlessModel {
  static bool get isSupported => false;
  static Future<WebSearchlessModel> load(String key, String url) =>
      throw UnsupportedError('ONNX Runtime Web is only available on web');
  @override
  Future<Float32List> run(Int64List tokens, int rows) =>
      throw UnsupportedError('ONNX Runtime Web is only available on web');
  @override
  void dispose() {}
}
