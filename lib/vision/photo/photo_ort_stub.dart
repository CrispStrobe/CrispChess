/// Web stand-in for photo_ort_native.dart: no dart:ffi in the browser, so
/// the photo classifiers run on the pure-Dart interpreter there.
library;

import 'dart:typed_data';

class NativePhotoModel {
  static bool get isSupported => false;

  static NativePhotoModel load(Uint8List bytes, {int threads = 2}) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  Float32List run(Float32List input, List<int> shape) =>
      throw UnsupportedError('Native ONNX Runtime is not available on web');

  void dispose() {}
}
