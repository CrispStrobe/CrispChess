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

Future<Uint8List> fetchModelBytes(String url, String cacheFileName) async =>
    File(await fetchModelFile(url, cacheFileName)).readAsBytes();

/// Downloads [url] once into the model cache and returns the file's path,
/// for native libraries that load a model from disk themselves.
///
/// The download goes to a temporary file that is renamed only when complete,
/// so an interrupted download is not mistaken for the model next time.
Future<String> fetchModelFile(String url, String cacheFileName,
    {void Function(int received, int? total)? onProgress}) async {
  final modelDir = await _modelDir();
  if (!modelDir.existsSync()) modelDir.createSync(recursive: true);
  final file = File('${modelDir.path}/${_cacheName(url, cacheFileName)}');
  if (file.existsSync()) return file.path;

  final part = File('${file.path}.part');
  final client = HttpClient();
  try {
    var request = await client.getUrl(Uri.parse(url));
    var response = await request.close();
    // HuggingFace's resolve/ URLs redirect to the actual CDN object.
    while (response.statusCode == 301 || response.statusCode == 302) {
      final redirect = response.headers.value('location');
      if (redirect == null) break;
      await response.drain<void>();
      request = await client.getUrl(Uri.parse(url).resolve(redirect));
      response = await request.close();
    }
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final total = response.contentLength >= 0 ? response.contentLength : null;
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    if (total != null && received != total) {
      throw HttpException('download truncated ($received of $total bytes)', uri: Uri.parse(url));
    }
    await part.rename(file.path);
  } finally {
    client.close();
    if (part.existsSync()) part.deleteSync();
  }
  return file.path;
}
