@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/maia3_dart/onnx/model_fetch_native.dart';
import 'package:crispchess/services/model_download_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late HttpServer server;
  setUp(() async {
    HttpOverrides.global = null;
    dir = await Directory.systemTemp.createTemp('crispchess_download_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });
  String url() => 'http://127.0.0.1:${server.port}/model';

  test(
      'concurrent consumers share one atomic download and removal causes a new request',
      () async {
    var requests = 0;
    server.listen((request) async {
      requests++;
      request.response.contentLength = 4;
      request.response.add([1, 2, 3, 4]);
      await request.response.close();
    });
    final paths = await Future.wait([
      fetchModelFile(url(), 'fixture.onnx'),
      fetchModelFile(url(), 'fixture.onnx')
    ]);
    expect(paths[0], paths[1]);
    expect(requests, 1);
    expect(await File(paths.first).readAsBytes(), [1, 2, 3, 4]);
    final entries = await listCachedModels(includeEngines: false);
    expect(entries, hasLength(1));
    expect(entries.single.bytes, 4);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
    await removeCachedModel(entries.single.id);
    expect(await listCachedModels(includeEngines: false), isEmpty);
    await fetchModelFile(url(), 'fixture.onnx');
    expect(requests, 2);
  });

  test('engine downloads share their destination and reject conflicting URLs',
      () async {
    var requests = 0;
    final started = Completer<void>();
    final finish = Completer<void>();
    server.listen((request) async {
      requests++;
      started.complete();
      await finish.future;
      request.response.add([5, 6, 7]);
      await request.response.close();
    });
    final file = File('${dir.path}/engine.zip');
    final first = downloadAssetFile(url(), file, name: 'Engine');
    final second = downloadAssetFile(url(), file, name: 'Engine');
    await started.future;
    await expectLater(downloadAssetFile('${url()}-other', file, name: 'Engine'),
        throwsStateError);
    finish.complete();
    expect(await Future.wait([first, second]), [file.path, file.path]);
    expect(requests, 1);
    expect(await file.readAsBytes(), [5, 6, 7]);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
  });

  test('HTTP errors never become cached models', () async {
    server.listen((request) async {
      request.response.statusCode = 503;
      await request.response.close();
    });
    await expectLater(
        fetchModelFile(url(), 'bad.onnx'), throwsA(isA<HttpException>()));
    expect(await listCachedModels(includeEngines: false), isEmpty);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
    expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue);
  });

  test('cancellation closes the request and removes partial files', () async {
    final received = Completer<void>();
    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.contentLength = 1024 * 1024;
      request.response.add(List.filled(8192, 42));
      await request.response.flush();
      if (!received.isCompleted) received.complete();
      // The client aborts rather than the server ending the response.
    });
    final download = fetchModelFile(url(), 'cancel.onnx');
    final assertion = expectLater(download, throwsA(isA<DownloadCancelled>()));
    await received.future;
    ModelDownloadRegistry.instance.active.single.cancel();
    await assertion;
    expect(await listCachedModels(includeEngines: false), isEmpty);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
    expect(
        await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue);
  });

  test('cache removal rejects directory traversal', () async {
    await expectLater(removeCachedModel('../outside'), throwsArgumentError);
    await expectLater(fetchModelFile(url(), '../outside'), throwsArgumentError);
  });
}
