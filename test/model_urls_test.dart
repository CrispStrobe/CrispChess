/// Tests that all model download URLs are reachable.
///
/// These tests make real HTTP HEAD requests. Skip with:
///   flutter test --exclude-tags=network
@Tags(['network'])
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/lc0_dart/variants.dart';
import 'package:crispchess/engines/maia3_dart/variants.dart' as maia3;

void main() {
  final client = HttpClient();

  Future<int> headRequest(String url) async {
    final uri = Uri.parse(url);
    final request = await client.headUrl(uri);
    request.followRedirects = true;
    final response = await request.close();
    await response.drain();
    return response.statusCode;
  }

  group('Lc0 model URLs are reachable', () {
    for (final variant in lc0Variants) {
      test('${variant.displayName} (${variant.id})', () async {
        final status = await headRequest(variant.url);
        expect(status, inInclusiveRange(200, 302),
            reason: '${variant.url} returned $status');
      }, timeout: const Timeout(Duration(seconds: 15)));
    }
  });

  group('Maia3 model URLs are reachable', () {
    for (final entry in maia3.variants.entries) {
      test('Maia3 ${entry.key}', () async {
        final status = await headRequest(entry.value.url);
        expect(status, inInclusiveRange(200, 302),
            reason: '${entry.value.url} returned $status');
      }, timeout: const Timeout(Duration(seconds: 15)));
    }
  });

  group('Stockfish CDN URLs are reachable', () {
    test('Stockfish 10 (niklasf)', () async {
      final status = await headRequest(
          'https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js');
      expect(status, inInclusiveRange(200, 302));
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('Stockfish 18 Lite (nmrugg)', () async {
      final status = await headRequest(
          'https://github.com/nmrugg/stockfish.js/releases/download/v18.0.0/stockfish-18-lite-single.js');
      expect(status, inInclusiveRange(200, 302));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });

  group('ONNX Runtime WASM URL is reachable', () {
    test('ort WASM binary', () async {
      final status = await headRequest(
          'https://cdn.jsdelivr.net/npm/onnxruntime-web@1.21.0/dist/ort-wasm-simd-threaded.wasm');
      expect(status, inInclusiveRange(200, 302));
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
