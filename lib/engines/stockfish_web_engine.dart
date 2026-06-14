import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'chess_engine.dart';

@JS('cachedFetch')
external JSPromise<JSObject> _cachedFetch(JSString url, JSString cacheName);

/// Available Stockfish versions for web (all GPL-3.0, downloaded at runtime).
enum StockfishVersion {
  sf10('Stockfish 10', 'https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js', 2800, '~1MB'),
  sf18asm('Stockfish 18 (NNUE)', 'https://huggingface.co/cstr/stockfish-js-wasm/resolve/main/stockfish-18-asm.js', 3400, '~10MB');

  final String label;
  final String url;
  final int elo;
  final String size;

  const StockfishVersion(this.label, this.url, this.elo, this.size);
}

/// Stockfish engine running as a Web Worker via stockfish.js (WASM/JS).
///
/// Uses nmrugg/stockfish.js compiled Stockfish which communicates
/// via postMessage (UCI protocol over Web Worker messages).
/// GPL-3.0 licensed — downloaded at runtime, never bundled in app binary.
class StockfishEngine implements ChessEngine {
  final StockfishVersion sfVersion;
  web.Worker? _worker;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  final _evalController = StreamController<EvalInfo>.broadcast();

  // Pre-compiled regex for parsing UCI output
  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r'multipv (\d+)');

  StockfishEngine({StockfishVersion? sfVersion, String? variantId})
      : sfVersion = sfVersion ?? _versionFromId(variantId);

  static StockfishVersion _versionFromId(String? id) {
    return switch (id) {
      'sf10' => StockfishVersion.sf10,
      'sf18asm' || 'sf18lite' => StockfishVersion.sf18asm,
      _ => StockfishVersion.sf10,
    };
  }

  @override
  String get name => 'Stockfish';
  @override
  String get version => sfVersion.label;
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => sfVersion.elo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable => kIsWeb;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;

    try {
      debugPrint('[StockfishWeb] Loading ${sfVersion.label} from CDN...');

      // Fetch JS source (cached), create blob URL for same-origin Worker loading
      final jsResponse = await _cachedFetch(sfVersion.url.toJS, 'crispchess-engines'.toJS).toDart;
      final jsBlob = await (jsResponse as web.Response).blob().toDart;
      final blobUrl = web.URL.createObjectURL(jsBlob);
      _worker = web.Worker(blobUrl.toJS);
      debugPrint('[StockfishWeb] Worker created from blob');

      final readyCompleter = Completer<void>();

      _worker!.onmessage = ((web.MessageEvent event) {
        final data = event.data;
        if (data == null) return;
        final line = data.toString();
        debugPrint('[StockfishWeb] << $line');
        _handleOutput(line);
        if (line.contains('uciok') && !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }).toJS;

      _send('uci');

      bool timedOut = false;
      await readyCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[StockfishWeb] UCI handshake timeout (15s)');
          timedOut = true;
        },
      );

      if (timedOut) {
        _worker?.terminate();
        _worker = null;
        debugPrint('[StockfishWeb] Engine timed out — terminating worker');
        _stateNotifier.value = EngineState.error;
        return;
      }

      _send('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[StockfishWeb] ${sfVersion.label} ready');
    } catch (e) {
      debugPrint('[StockfishWeb] Init failed: $e');
      _worker?.terminate();
      _worker = null;
      _stateNotifier.value = EngineState.error;
    }
  }

  void _send(String command) {
    debugPrint('[StockfishWeb] >> $command');
    _worker?.postMessage(command.toJS);
  }

  void _handleOutput(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    // Parse evaluation info
    if (trimmed.startsWith('info') && trimmed.contains('depth')) {
      final cpMatch = _cpRegex.firstMatch(trimmed);
      final depthMatch = _depthRegex.firstMatch(trimmed);
      final pvMatch = _pvRegex.firstMatch(trimmed);
      final mpvMatch = _multipvRegex.firstMatch(trimmed);

      if (cpMatch != null && depthMatch != null) {
        final pv = pvMatch?.group(1);
        _evalController.add(EvalInfo(
          score: int.parse(cpMatch.group(1)!) / 100.0,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: pv?.split(' ').first,
          pv: pv,
          pvIndex: mpvMatch != null ? int.parse(mpvMatch.group(1)!) : 1,
        ));
      }
    }

    // Parse bestmove
    if (trimmed.startsWith('bestmove')) {
      final parts = trimmed.split(' ');
      if (parts.length >= 2 && parts[1] != '(none)') {
        _moveCompleter?.complete(parts[1]);
        _moveCompleter = null;
        _stateNotifier.value = EngineState.ready;
      }
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_worker == null) throw StateError('Engine not initialized');
    _stateNotifier.value = EngineState.thinking;

    // Apply skill level
    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    // Cap depth for responsive WASM play
    final searchDepth = depth ?? (skillLevel != null ? 5 + skillLevel ~/ 4 : 12);
    _send(positionCommand);
    _moveCompleter = Completer<String>();
    _send('go depth $searchDepth');

    final move = await _moveCompleter!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _send('stop');
        throw TimeoutException('Search timed out');
      },
    );

    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false, int multiPv = 1}) {
    if (_worker == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;

    _send('setoption name Skill Level value 20');
    _send('setoption name MultiPV value $multiPv');
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
  void dispose() {
    _worker?.terminate();
    _worker = null;
    _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }
}
