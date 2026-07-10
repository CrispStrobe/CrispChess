/// Native (non-web) model fetch: download once to app-support storage,
/// reuse the cached file on subsequent loads.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Uint8List> fetchModelBytes(String url, String cacheFileName) async {
  final dir = await getApplicationSupportDirectory();
  final modelDir = Directory('${dir.path}/maia3_models');
  if (!modelDir.existsSync()) modelDir.createSync(recursive: true);
  final file = File('${modelDir.path}/$cacheFileName');

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
