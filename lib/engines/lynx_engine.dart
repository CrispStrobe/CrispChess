/// Lynx chess engine — MIT-licensed, ~3350 ELO, classical HCE.
///
/// Downloaded at runtime from GitHub Releases as a self-contained
/// native binary. No .NET runtime required.
///
/// Source: https://github.com/lynx-chess/Lynx
/// License: MIT
/// Supports: UCI protocol, Chess960, multithreading, pondering

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';

/// GitHub release download URLs for Lynx v1.11.0 (self-contained binaries).
const _lynxVersion = '1.11.0';
const _lynxBaseUrl =
    'https://github.com/lynx-chess/Lynx/releases/download/v$_lynxVersion';

/// Platform → download URL + binary name mapping.
({String url, String binary}) _platformAsset() {
  if (Platform.isMacOS) {
    // Universal: use ARM64 for Apple Silicon, x64 for Intel
    final arch = Platform.version.contains('arm64') ||
            Platform.operatingSystemVersion.contains('arm64')
        ? 'osx-arm64'
        : 'osx-x64';
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-$arch.zip',
      binary: 'Lynx',
    );
  }
  if (Platform.isLinux) {
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-linux-x64.zip',
      binary: 'Lynx',
    );
  }
  if (Platform.isWindows) {
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-win-x64.zip',
      binary: 'Lynx.exe',
    );
  }
  throw UnsupportedError('Lynx not available on this platform');
}

/// Lynx chess engine — downloads and runs as a native UCI process.
class LynxEngine implements ChessEngine {
  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  StreamSubscription? _stdoutSub;
  final _evalController = StreamController<EvalInfo>.broadcast();

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r'multipv (\d+)');

  @override
  String get name => 'Lynx';
  @override
  String get version => _lynxVersion;
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 3350;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  static bool get isAvailable =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final binaryPath = await _ensureDownloaded();
      debugPrint('[Lynx] Starting: $binaryPath');
      _process = await Process.start(binaryPath, []);

      final ready = Completer<void>();
      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line);
        if (line.trim() == 'uciok' && !ready.isCompleted) ready.complete();
      });

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => debugPrint('[Lynx stderr] $line'));

      _process!.stdin.writeln('uci');
      await ready.future.timeout(const Duration(seconds: 15),
          onTimeout: () => debugPrint('[Lynx] UCI handshake timeout'));

      _process!.stdin.writeln('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[Lynx] Ready (v$_lynxVersion, ~${estimatedElo} ELO)');
    } catch (e) {
      debugPrint('[Lynx] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  void _handleLine(String line) {
    final t = line.trim();

    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final mate = _mateRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pvMatch = _pvRegex.firstMatch(t);
      final mpv = _multipvRegex.firstMatch(t);

      if (d != null && (cp != null || mate != null)) {
        final double score;
        if (mate != null) {
          final mateIn = int.parse(mate.group(1)!);
          score = mateIn > 0 ? 100.0 : -100.0; // Large score for mate
        } else {
          score = int.parse(cp!.group(1)!) / 100.0;
        }
        final pv = pvMatch?.group(1);
        _evalController.add(EvalInfo(
          score: score,
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

    _process!.stdin.writeln(positionCommand);
    _moveCompleter = Completer<String>();

    // Lynx doesn't have Skill Level — use depth to control strength
    final searchDepth = depth ?? (skillLevel != null ? 5 + skillLevel ~/ 2 : 15);
    _process!.stdin.writeln('go depth $searchDepth');

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

  // --- Download management ---

  static Future<Directory> _engineDir() async {
    final home = Platform.environment['HOME'] ??
        Platform.environment['APPDATA'] ?? '/tmp';
    return Directory('$home/.crispchess/engines/lynx');
  }

  /// Check if Lynx binary exists locally.
  static Future<bool> isDownloaded() async {
    try {
      final dir = await _engineDir();
      final asset = _platformAsset();
      return File('${dir.path}/${asset.binary}').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Download and extract the platform-appropriate Lynx binary.
  Future<String> _ensureDownloaded() async {
    final dir = await _engineDir();
    final asset = _platformAsset();
    final binaryFile = File('${dir.path}/${asset.binary}');

    if (binaryFile.existsSync()) {
      return binaryFile.path;
    }

    debugPrint('[Lynx] Downloading from ${asset.url}...');
    await dir.create(recursive: true);

    // Download zip
    final zipFile = File('${dir.path}/lynx.zip');
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      final response = await request.close();

      // Follow redirects (GitHub releases redirect)
      if (response.statusCode == 302 || response.statusCode == 301) {
        final redirect = response.headers.value('location');
        if (redirect != null) {
          final r2 = await client.getUrl(Uri.parse(redirect));
          final resp2 = await r2.close();
          await resp2.pipe(zipFile.openWrite());
        }
      } else {
        await response.pipe(zipFile.openWrite());
      }
    } finally {
      client.close();
    }

    // Extract zip
    debugPrint('[Lynx] Extracting...');
    if (Platform.isWindows) {
      await Process.run('powershell', [
        '-command',
        'Expand-Archive', '-Path', zipFile.path, '-DestinationPath', dir.path, '-Force',
      ]);
    } else {
      await Process.run('unzip', ['-o', zipFile.path, '-d', dir.path]);
    }

    // Make executable on Unix
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', binaryFile.path]);
    }

    // Clean up zip
    if (zipFile.existsSync()) zipFile.deleteSync();

    debugPrint('[Lynx] Ready at ${binaryFile.path}');
    return binaryFile.path;
  }

  /// Delete downloaded engine files.
  static Future<void> deleteDownload() async {
    final dir = await _engineDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
