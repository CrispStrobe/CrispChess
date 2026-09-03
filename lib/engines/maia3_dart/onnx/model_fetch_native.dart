/// Native (non-web) model fetch: download once to app-support storage,
/// reuse the cached file on subsequent loads.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where downloaded models live.
///
/// Prefers the platform's app-support directory. That needs a Flutter binding
/// and a platform implementation, neither of which exists when the engine is
/// driven headlessly — from a CLI tool, a test, or the tournament harness —
/// where it fails with "Binding has not yet been initialized" and the engine
/// simply never loads. Fall back to the same `~/.crispchess` location the
/// downloadable engines already use, so the engine works in every context.
Future<Directory> _modelDir() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return Directory('${dir.path}/maia3_models');
  } catch (_) {
    final home = Platform.environment['HOME'] ??
        Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return Directory('$home/.crispchess/models/maia3');
  }
}

/// A cache file name that changes when [url] does.
///
/// The name alone is not enough: callers derive it from the variant id, so
/// re-pointing a variant at a corrected model kept serving the old bytes from
/// disk forever. Tagging the name with a hash of the URL makes a changed URL a
/// cache miss.
String _cacheName(String url, String cacheFileName) {
  var hash = 0;
  for (final unit in url.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final tag = hash.toRadixString(16).padLeft(8, '0');
  final dot = cacheFileName.lastIndexOf('.');
  return dot > 0
      ? '${cacheFileName.substring(0, dot)}-$tag${cacheFileName.substring(dot)}'
      : '$cacheFileName-$tag';
}

Future<Uint8List> fetchModelBytes(String url, String cacheFileName) async {
  final modelDir = await _modelDir();
  if (!modelDir.existsSync()) modelDir.createSync(recursive: true);
  final file = File('${modelDir.path}/${_cacheName(url, cacheFileName)}');

  if (file.existsSync()) {
    return file.readAsBytes();
  }

  final client = HttpClient();
  try {
    var request = await client.getUrl(Uri.parse(url));
    var response = await request.close();
    // HuggingFace's resolve/ URLs redirect to the actual CDN object.
    while (response.statusCode == 301 || response.statusCode == 302) {
      final redirect = response.headers.value('location');
      if (redirect == null) break;
      request = await client.getUrl(Uri.parse(redirect));
      response = await request.close();
    }
    final sink = file.openWrite();
    await response.pipe(sink);
    await sink.close();
  } finally {
    client.close();
  }
  return file.readAsBytes();
}
