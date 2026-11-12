/// Native (non-web) model fetch: download once to app-support storage,
/// reuse the cached file on subsequent loads.
library;

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import '../../../../services/model_download_registry.dart';

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
final _pending = <String, Future<String>>{};

Future<List<CachedModel>> listCachedModels({bool includeEngines = true}) async {
  final dir = await _modelDir();
  final result = <CachedModel>[];
  if (await dir.exists()) {
    await for (final entry in dir.list(followLinks: false)) {
      if (entry is! File || entry.path.endsWith('.part')) continue;
      final name = entry.uri.pathSegments.last;
      result.add(CachedModel(name, name, await entry.length()));
    }
  }
  if (!includeEngines) return result;
  for (final entry in (await _engineLocations()).entries) {
    final directory = entry.value;
    if (!await directory.exists()) continue;
    var bytes = 0;
    await for (final file
        in directory.list(recursive: true, followLinks: false)) {
      if (file is File && !file.path.endsWith('.part'))
        bytes += await file.length();
    }
    if (bytes > 0)
      result.add(CachedModel('engine:${entry.key}', entry.key, bytes));
  }
  return result;
}

Future<Map<String, Directory>> _engineLocations() async {
  final home = Platform.environment['HOME'] ??
      Platform.environment['APPDATA'] ??
      Directory.systemTemp.path;
  Directory? support;
  try {
    support = await getApplicationSupportDirectory();
  } catch (_) {}
  return {
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows)
      'Lynx': Directory('$home/.crispchess/engines/lynx'),
    if (Platform.isIOS && support != null)
      'Stockfish': Directory('${support.path}/engines'),
  };
}

Future<void> removeCachedModel(String id) async {
  if (id.startsWith('engine:')) {
    final name = id.substring(7);
    if (ModelDownloadRegistry.instance.active
        .any((d) => d.name.startsWith(name))) {
      throw StateError('Download still running');
    }
    final directory = (await _engineLocations())[name];
    if (directory == null) throw ArgumentError('Invalid engine entry');
    if (await directory.exists()) await directory.delete(recursive: true);
    return;
  }
  // Only entries inside our cache may be removed.
  if (id.contains('/') || id.contains('\\') || id == '.' || id == '..') {
    throw ArgumentError('Invalid cache entry');
  }
  final dir = await _modelDir();
  final file = File('${dir.path}/$id');
  if (await file.exists()) await file.delete();
}

Future<String> fetchModelFile(String url, String cacheFileName,
    {void Function(int received, int? total)? onProgress}) async {
  final key = _cacheName(url, cacheFileName);
  final existing = _pending[key];
  if (existing != null) return existing;
  final task = _downloadModel(url, cacheFileName, onProgress);
  _pending[key] = task;
  try {
    return await task;
  } finally {
    _pending.remove(key);
  }
}

Future<String> _downloadModel(String url, String cacheFileName,
    void Function(int received, int? total)? onProgress) async {
  if (cacheFileName.contains('/') || cacheFileName.contains('\\')) {
    throw ArgumentError('Invalid model name');
  }
  final modelDir = await _modelDir();
  await modelDir.create(recursive: true);
  final file = File('${modelDir.path}/${_cacheName(url, cacheFileName)}');
  return downloadAssetFile(url, file,
      name: cacheFileName, onProgress: onProgress);
}

/// The same bounded, cancellable transfer for separately downloaded engines.
final _pendingAssets = <String, ({String url, Future<String> task})>{};

Future<String> downloadAssetFile(String url, File file,
    {required String name,
    void Function(int received, int? total)? onProgress}) async {
  final key = file.absolute.path;
  final existing = _pendingAssets[key];
  if (existing != null) {
    if (existing.url != url) {
      throw StateError('Another download targets the same file');
    }
    return existing.task;
  }
  final task =
      _downloadAssetFile(url, file, name: name, onProgress: onProgress);
  _pendingAssets[key] = (url: url, task: task);
  try {
    return await task;
  } finally {
    _pendingAssets.remove(key);
  }
}

Future<String> _downloadAssetFile(String url, File file,
    {required String name,
    void Function(int received, int? total)? onProgress}) async {
  if (await file.exists()) return file.path;
  await file.parent.create(recursive: true);

  final part = File('${file.path}.part');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  final registry = ModelDownloadRegistry.instance;
  void Function()? cancelTransfer;
  final download = registry.begin(file.uri.pathSegments.last, name, () {
    cancelTransfer?.call();
    client.close(force: true);
  });
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final total = response.contentLength >= 0 ? response.contentLength : null;
    final sink = part.openWrite();
    var received = 0;
    try {
      if (download.cancelled) throw DownloadCancelled();
      final transfer = Completer<void>();
      late StreamSubscription<List<int>> subscription;
      subscription =
          response.timeout(const Duration(seconds: 30)).listen((chunk) {
        try {
          if (download.cancelled) throw DownloadCancelled();
          sink.add(chunk);
          received += chunk.length;
          registry.progress(download, received, total);
          onProgress?.call(received, total);
        } catch (e, stack) {
          if (!transfer.isCompleted) transfer.completeError(e, stack);
        }
      }, onError: (Object e, StackTrace stack) {
        if (!transfer.isCompleted) transfer.completeError(e, stack);
      }, onDone: () {
        if (!transfer.isCompleted) transfer.complete();
      });
      cancelTransfer = () {
        subscription.cancel();
        if (!transfer.isCompleted) transfer.completeError(DownloadCancelled());
      };
      try {
        await transfer.future;
      } finally {
        cancelTransfer = null;
        await subscription.cancel();
      }
    } finally {
      await sink.close();
    }
    if (download.cancelled) throw DownloadCancelled();
    if (total != null && received != total) {
      throw HttpException('download truncated ($received of $total bytes)',
          uri: Uri.parse(url));
    }
    await part.rename(file.path);
    return file.path;
  } catch (_) {
    if (download.cancelled) throw DownloadCancelled();
    rethrow;
  } finally {
    client.close(force: true);
    if (await part.exists()) await part.delete();
    registry.finish(download);
  }
}
