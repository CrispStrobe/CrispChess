/// Cross-platform HTTP GET helper.
///
/// Uses dart:io HttpClient on native, web fetch API on web.
/// Avoids requiring the `http` package.

import 'http_service_impl.dart'
    if (dart.library.js_interop) 'http_service_impl_web.dart';

/// Perform a cross-platform HTTP GET request.
/// Returns the response body as a string, or null on error.
Future<String?> httpGet(String url) => platformHttpGet(url);
