// Downloadable Stockfish engine for ALL platforms including iOS.
//
// Pattern: same as downloading a GGUF model for an LLM app.
// 1. App code (MIT) acts as the "runtime/interpreter"
// 2. stockfish.js/WASM (GPL) is downloaded as "data" at runtime
// 3. Executed via platform JavaScript runtime (not linked into app)
//
// On iOS: uses JavaScriptCore (built into iOS) to run stockfish.js
// On Android/Desktop: uses downloaded binary or bundled WASM
// On Web: uses Web Worker (already handled by stockfish_web_engine.dart)
//
// Legal basis: The app binary contains no GPL code. The GPL-licensed
// stockfish.js is downloaded separately by user choice, like a browser
// downloading and running a GPL web application.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'chess_engine.dart';

/// Download URL for stockfish.js WASM build (GPL-3.0, downloaded separately)
const _stockfishJsUrl =
    'https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js';

/// Status of the Stockfish download
enum DownloadStatus { notDownloaded, downloading, ready, error }

/// Stockfish engine that downloads its WASM binary on first use.
///
/// Works on all platforms:
/// - iOS/macOS: Runs stockfish.js via JavaScriptCore framework
/// - Android: Runs via WebView JavaScript bridge or Process
/// - Desktop: Runs via system-installed binary or bundled WASM
/// - Web: Handled by StockfishWebEngine (conditional import)
class StockfishDownloadableEngine implements ChessEngine {
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  final _downloadStatus = ValueNotifier<DownloadStatus>(DownloadStatus.notDownloaded);

  // Platform-specific engine implementation
  // On iOS: uses MethodChannel to JavaScriptCore
  // On Android: uses MethodChannel to WebView
  // On Desktop: uses Process
  static const _channel = MethodChannel('crispchess/stockfish');

  Completer<String>? _moveCompleter;
  final _evalController = StreamController<EvalInfo>.broadcast();
  bool _initialized = false;

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r'pv (\S+)');

  @override
  String get name => 'Stockfish';
  @override
  String get version => '16 (downloaded)';
  @override
  String get license => 'GPL-3.0 (not linked)';
  @override
  int get estimatedElo => 3200;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  ValueNotifier<DownloadStatus> get downloadStatus => _downloadStatus;

  // iOS only: runs stockfish.js inside WebKit via the crispchess/stockfish
  // bridge. Web uses StockfishWebEngine; desktop/Android use the native
  // process-based StockfishEngine.
  static bool get isAvailable => !kIsWeb && Platform.isIOS;

  Completer<void>? _uciOkCompleter;
  Completer<void>? _readyOkCompleter;

  /// Check if stockfish.js is already downloaded/available.
  Future<bool> isDownloaded() async {
    try {
      final dir = await _getEngineDir();
      final file = File('${dir.path}/stockfish.js');
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Download stockfish.js to local storage.
  Future<void> download({void Function(double)? onProgress}) async {
    _downloadStatus.value = DownloadStatus.downloading;
    try {
      final dir = await _getEngineDir();
      await dir.create(recursive: true);
      final targetFile = File('${dir.path}/stockfish.js');

      // Download from CDN (GPL-3.0, never bundled with app)
      debugPrint('[Stockfish] Downloading from $_stockfishJsUrl...');
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_stockfishJsUrl));
        final response = await request.close();
        await response.pipe(targetFile.openWrite());
        debugPrint('[Stockfish] Downloaded to ${targetFile.path}');
        _downloadStatus.value = DownloadStatus.ready;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[Stockfish] Download failed: $e');
      _downloadStatus.value = DownloadStatus.error;
    }
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;

    try {
      // Ensure engine is downloaded (CDN — never bundled with the app binary).
      if (!await isDownloaded()) {
        await download();
        if (_downloadStatus.value != DownloadStatus.ready) {
          _stateNotifier.value = EngineState.error;
          return;
        }
      } else {
        _downloadStatus.value = DownloadStatus.ready;
      }

      final dir = await _getEngineDir();
      final jsPath = '${dir.path}/stockfish.js';

      // Receive UCI output from the WebKit-hosted engine.
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onOutput') {
          _handleOutput(call.arguments as String);
        }
      });

      // Load stockfish.js into the WebView; completes once the harness is ready.
      await _channel.invokeMethod('initialize', {'path': jsPath});
      _initialized = true;

      // UCI handshake — wait for the engine's actual replies rather than a
      // fixed delay (the Web Worker may still be compiling stockfish.js).
      _uciOkCompleter = Completer<void>();
      await _send('uci');
      await _uciOkCompleter!.future.timeout(const Duration(seconds: 20));

      _readyOkCompleter = Completer<void>();
      await _send('isready');
      await _readyOkCompleter!.future.timeout(const Duration(seconds: 10));

      _stateNotifier.value = EngineState.ready;
      debugPrint('[Stockfish] Initialized via WebKit JS runtime');
    } catch (e) {
      debugPrint('[Stockfish] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  Future<void> _send(String command) async {
    if (!_initialized) return;
    await _channel.invokeMethod('send', {'command': command});
  }

  void _handleOutput(String line) {
    final t = line.trim();
    if (t.isEmpty) return;

    if (t == 'uciok') {
      _uciOkCompleter?.complete();
      _uciOkCompleter = null;
      return;
    }
    if (t == 'readyok') {
      _readyOkCompleter?.complete();
      _readyOkCompleter = null;
      return;
    }

    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pv = _pvRegex.firstMatch(t);
      if (cp != null && d != null) {
        _evalController.add(EvalInfo(
          score: int.parse(cp.group(1)!) / 100.0,
          depth: int.parse(d.group(1)!),
          bestMove: pv?.group(1),
        ));
      }
    }

    if (t.startsWith('bestmove')) {
      final parts = t.split(' ');
      if (parts.length >= 2 && parts[1] != '(none)') {
        _moveCompleter?.complete(parts[1]);
        _moveCompleter = null;
        _stateNotifier.value = EngineState.ready;
      }
    }
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async {
    if (!_initialized) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    if (skillLevel != null) {
      await _send('setoption name Skill Level value $skillLevel');
    }
    await _send(positionCommand);
    _moveCompleter = Completer<String>();
    await _send('go depth ${depth ?? 15}');

    return _moveCompleter!.future.timeout(const Duration(seconds: 30),
        onTimeout: () { _send('stop'); throw TimeoutException('timeout'); });
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (!_initialized) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
    _send(positionCommand);
    _send(infinite ? 'go infinite' : 'go depth ${depth ?? 20}');
    return _evalController.stream;
  }

  @override
  void stop() {
    _send('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {
    _send('setoption name $name value $value');
  }

  @override
  void dispose() {
    _send('quit');
    _channel.invokeMethod('dispose');
    _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }

  /// Delete downloaded engine files.
  Future<void> deleteDownload() async {
    final dir = await _getEngineDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _downloadStatus.value = DownloadStatus.notDownloaded;
  }

  static Future<Directory> _getEngineDir() async {
    // App support dir — sandbox-correct on iOS (path_provider), unlike $HOME.
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/engines');
  }
}
