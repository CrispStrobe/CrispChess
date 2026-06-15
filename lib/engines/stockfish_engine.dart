// Stockfish engine for native platforms.
// Desktop: finds and runs system-installed stockfish binary.
// Android: extracts bundled binary from assets, runs as process.
// iOS: not available (no subprocess support — use Frozenight instead).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'chess_engine.dart';

class StockfishEngine implements ChessEngine {
  // Accept sfVersion/variantId for API compat with web engine (ignored on native)
  StockfishEngine({dynamic sfVersion, String? variantId});

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  StreamSubscription? _stdoutSub;
  final _evalController = StreamController<EvalInfo>.broadcast();

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r'multipv (\d+)');

  @override
  String get name => 'Stockfish';
  @override
  String get version => '16';
  @override
  String get license => 'GPL-3.0 (separate process)';
  @override
  int get estimatedElo => 3600;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable {
    if (kIsWeb) return false;
    // Available on desktop and Android (bundled binary)
    return Platform.isLinux || Platform.isMacOS ||
        Platform.isWindows || Platform.isAndroid;
  }

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final path = await _findOrExtractBinary();
      debugPrint('[Stockfish] Starting: $path');
      _process = await Process.start(path, []);

      final ready = Completer<void>();
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line);
        if (line.trim() == 'uciok' && !ready.isCompleted) ready.complete();
      });

      _process!.stdin.writeln('uci');
      await ready.future.timeout(const Duration(seconds: 10),
          onTimeout: () => debugPrint('[Stockfish] UCI timeout'));

      _process!.stdin.writeln('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Stockfish] Ready');
    } catch (e) {
      debugPrint('[Stockfish] Not available: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  void _handleLine(String line) {
    final t = line.trim();

    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pvMatch = _pvRegex.firstMatch(t);
      final mpv = _multipvRegex.firstMatch(t);
      if (cp != null && d != null) {
        final pv = pvMatch?.group(1);
        _evalController.add(EvalInfo(
          score: int.parse(cp.group(1)!) / 100.0,
          depth: int.parse(d.group(1)!),
          bestMove: pv?.split(' ').first,
          pv: pv,
          pvIndex: mpv != null ? int.parse(mpv.group(1)!) : 1,
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
    if (_process == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    if (skillLevel != null) {
      _process!.stdin.writeln('setoption name Skill Level value $skillLevel');
    }
    _process!.stdin.writeln(positionCommand);
    _moveCompleter = Completer<String>();
    _process!.stdin.writeln('go depth ${depth ?? 15}');

    return _moveCompleter!.future.timeout(const Duration(seconds: 30),
        onTimeout: () {
      _process!.stdin.writeln('stop');
      throw TimeoutException('Search timed out');
    });
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (_process == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
    _process!.stdin.writeln(positionCommand);
    _process!.stdin.writeln(infinite ? 'go infinite' : 'go depth ${depth ?? 20}');
    return _evalController.stream;
  }

  @override
  void stop() {
    _process?.stdin.writeln('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void setOption(String name, String value) {
    _process?.stdin.writeln('setoption name $name value $value');
  }

  @override
  void dispose() {
    _process?.stdin.writeln('quit');
    _stdoutSub?.cancel();
    _evalController.close();
    _process?.kill();
    _process = null;
    _stateNotifier.value = EngineState.disposed;
  }

  /// Find or extract the Stockfish binary.
  static Future<String> _findOrExtractBinary() async {
    if (Platform.isAndroid) {
      return _extractAndroidBinary();
    }
    return _findSystemBinary();
  }

  /// On Android: extract bundled stockfish binary from assets to app data dir.
  static Future<String> _extractAndroidBinary() async {
    // The binary is bundled as a Flutter asset
    final dataDir = Directory('/data/data/${_getPackageName()}/files');
    final binary = File('${dataDir.path}/stockfish');

    if (!await binary.exists()) {
      debugPrint('[Stockfish] Extracting Android binary...');
      try {
        final bytes = await rootBundle.load('assets/bin/stockfish-android');
        await dataDir.create(recursive: true);
        await binary.writeAsBytes(bytes.buffer.asUint8List());
        await Process.run('chmod', ['+x', binary.path]);
        debugPrint('[Stockfish] Extracted to ${binary.path}');
      } catch (e) {
        throw FileSystemException(
            'Failed to extract Stockfish binary: $e');
      }
    }

    return binary.path;
  }

  /// On desktop: find stockfish in system PATH.
  static Future<String> _findSystemBinary() async {
    final cmd = Platform.isWindows ? 'where' : 'which';
    for (final name in ['stockfish', 'stockfish.exe']) {
      try {
        final result = await Process.run(cmd, [name]);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim();
        }
      } catch (_) {}
    }
    throw FileSystemException(
        'Stockfish not found. Install via package manager:\n'
        '  Linux: sudo apt install stockfish\n'
        '  macOS: brew install stockfish\n'
        '  Windows: download from stockfishchess.org');
  }

  static String _getPackageName() {
    // Default package name — can be overridden
    return 'com.crispstrobe.crispchess';
  }
}
