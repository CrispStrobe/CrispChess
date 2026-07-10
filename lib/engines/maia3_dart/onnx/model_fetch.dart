/// Fetches (and, where possible, caches) ONNX model bytes.
///
/// The only part of the interpreter that's genuinely platform-specific —
/// `dart:io` doesn't exist on web, so downloading/caching a file needs two
/// implementations. Everything else (graph parsing, execution) is 100%
/// shared Dart, no conditional imports needed.
library;

export 'model_fetch_native.dart' if (dart.library.js_interop) 'model_fetch_web.dart';
