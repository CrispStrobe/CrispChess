@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/maia3_dart/onnx/model_fetch_web.dart';
import 'package:crispchess/services/model_download_registry.dart';

@JS('Function')
external JSFunction _jsFunction(JSString body);
@JS('globalThis.fetch')
external JSFunction get _fetch;
@JS('globalThis.fetch')
external set _fetch(JSFunction function);
@JS('globalThis.testModelRequests')
external JSNumber get _requests;

void main() {
  late JSFunction originalFetch;
  setUp(() {
    originalFetch = _fetch;
  });
  tearDown(() {
    _fetch = originalFetch;
  });

  test('browser download persists actual bytes and can be removed', () async {
    final url =
        '${Uri.base.origin}/fixture-${DateTime.now().microsecondsSinceEpoch}.onnx';
    _jsFunction('''
      globalThis.testModelRequests = 0;
      globalThis.fetch = async () => {
        globalThis.testModelRequests++;
        return new Response(new Uint8Array([1, 2, 3, 4]), {status: 200});
      };
    '''
            .toJS)
        .callAsFunction();
    expect(await fetchModelBytes(url, 'fixture.onnx'), [1, 2, 3, 4]);
    expect(await fetchModelBytes(url, 'fixture.onnx'), [1, 2, 3, 4]);
    expect(_requests.toDartInt, 1);
    final entry =
        (await listCachedModels()).singleWhere((m) => m.id.endsWith(url));
    expect(entry.bytes, 4);
    await removeCachedModel(entry.id);
    expect((await listCachedModels()).where((m) => m.id == entry.id), isEmpty);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
  });

  test('browser cancellation aborts fetch without retrying or caching',
      () async {
    final url =
        '${Uri.base.origin}/cancel-${DateTime.now().microsecondsSinceEpoch}.onnx';
    _jsFunction('''
      globalThis.testModelRequests = 0;
      globalThis.fetch = (url, options) => {
        globalThis.testModelRequests++;
        return new Promise((resolve, reject) => {
          options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
        });
      };
    '''
            .toJS)
        .callAsFunction();
    final started = Completer<void>();
    void onChange() {
      if (ModelDownloadRegistry.instance.active.any((d) => d.id == url) &&
          !started.isCompleted) {
        started.complete();
      }
    }

    ModelDownloadRegistry.instance.addListener(onChange);
    final task = fetchModelBytes(url, 'cancel.onnx');
    final assertion = expectLater(task, throwsA(isA<DownloadCancelled>()));
    await started.future;
    // begin() runs before fetch registers its abort handler.
    await Future<void>.delayed(Duration.zero);
    ModelDownloadRegistry.instance.active
        .singleWhere((d) => d.id == url)
        .cancel();
    await assertion;
    ModelDownloadRegistry.instance.removeListener(onChange);
    expect(_requests.toDartInt, 1);
    expect(
        (await listCachedModels()).where((m) => m.id.endsWith(url)), isEmpty);
    expect(ModelDownloadRegistry.instance.active, isEmpty);
  });

  test('browser HTTP failure is surfaced without a cache fallback request',
      () async {
    final url =
        '${Uri.base.origin}/error-${DateTime.now().microsecondsSinceEpoch}.onnx';
    _jsFunction('''
      globalThis.testModelRequests = 0;
      globalThis.fetch = async () => {
        globalThis.testModelRequests++;
        return new Response('unavailable', {status: 503});
      };
    '''
            .toJS)
        .callAsFunction();
    await expectLater(fetchModelBytes(url, 'error.onnx'), throwsStateError);
    expect(_requests.toDartInt, 1);
    expect(
        (await listCachedModels()).where((m) => m.id.endsWith(url)), isEmpty);
  });
}
