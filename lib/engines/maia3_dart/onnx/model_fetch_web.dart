library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import '../../../../services/model_download_registry.dart';

const _cacheNames = ['crispchess-models-v1', 'lc0-models', 'searchless-models'];
final _pending = <String, Future<Uint8List>>{};

Future<Uint8List> fetchModelBytes(String url, String cacheFileName) async {
  final existing = _pending[url];
  if (existing != null) return existing;
  final task = _download(url, cacheFileName);
  _pending[url] = task;
  try {
    return await task;
  } finally {
    _pending.remove(url);
  }
}

Future<Uint8List> _download(String url, String name) async {
  web.Cache? cache;
  // Cache Storage can be unavailable in private browsing. Its failure must
  // not cause a second network request or swallow an HTTP/cancellation error.
  try {
    for (final cacheName in _cacheNames) {
      final c = await web.window.caches.open(cacheName).toDart;
      final hit = await c.match(url.toJS).toDart;
      if (hit != null)
        return (await hit.arrayBuffer().toDart).toDart.asUint8List();
    }
    cache = await web.window.caches.open(_cacheNames.first).toDart;
  } catch (_) {
    cache = null;
  }
  final abort = web.AbortController();
  final registry = ModelDownloadRegistry.instance;
  final download = registry.begin(url, name, () => abort.abort());
  try {
    final response = await web.window.fetch(url.toJS, web.RequestInit(signal: abort.signal))
        .toDart;
    if (!response.ok) throw StateError('HTTP ${response.status}');
    final total = int.tryParse(response.headers.get('content-length') ?? '');
    final data = BytesBuilder(copy: false);
    final stream = response.body;
    if (stream == null) throw StateError('Empty download');
    final reader = web.ReadableStreamDefaultReader(stream);
    try {
      while (true) {
        final chunk = await reader.read().toDart;
        if (download.cancelled) throw DownloadCancelled();
        if (chunk.done) break;
        data.add((chunk.value as JSUint8Array).toDart);
        registry.progress(download, data.length, total);
      }
    } finally {
      reader.releaseLock();
    }
    final bytes = data.takeBytes();
    if (cache != null) {
      try {
        await cache
            .put(
                url.toJS,
                web.Response(
                    bytes.toJS,
                    web.ResponseInit(
                        headers: web.Headers({
                      'content-length': '${bytes.length}'
                    }.jsify() as JSObject))))
            .toDart;
      } catch (_) {/* Quota errors leave the downloaded model usable. */}
    }
    return bytes;
  } catch (_) {
    if (download.cancelled) throw DownloadCancelled();
    rethrow;
  } finally {
    registry.finish(download);
  }
}

Future<List<CachedModel>> listCachedModels({bool includeEngines = true}) async {
  final result = <CachedModel>[];
  for (final cacheName in _cacheNames) {
    final cache = await web.window.caches.open(cacheName).toDart;
  final requests = (await cache.keys().toDart).toDart;
    for (final request in requests) {
      final response = await cache.match(request).toDart;
      final size = response == null ? 0 : (await response.blob().toDart).size;
      result.add(CachedModel('$cacheName|${request.url}',
          Uri.parse(request.url).pathSegments.last, size));
}
  }
  return result;
}

Future<void> removeCachedModel(String id) async {
  final separator = id.indexOf('|');
  if (separator < 0 || !_cacheNames.contains(id.substring(0, separator))) {
    throw ArgumentError('Invalid cache entry');
  }
  final cache = await web.window.caches.open(id.substring(0, separator)).toDart;
  await cache.delete(id.substring(separator + 1).toJS).toDart;
}

Future<String> fetchModelFile(String url, String cacheFileName,
        {void Function(int received, int? total)? onProgress}) =>
    throw UnsupportedError('fetchModelFile is not available on the web');
