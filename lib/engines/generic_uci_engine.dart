/// Generic UCI engine that loads any engine binary from disk.
///
/// Speaks the UCI protocol over stdin/stdout. Available on desktop
/// and mobile platforms (not web — no process spawning).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'uci_option.dart';

/// Persisted engine profile — name, binary path, and option overrides.
class EngineProfile {
  String name;
  String path;
  final Map<String, String> optionOverrides;

  EngineProfile({
    required this.name,
    required this.path,
    Map<String, String>? optionOverrides,
  }) : optionOverrides = optionOverrides ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'options': optionOverrides,
  };

  factory EngineProfile.fromJson(Map<String, dynamic> json) => EngineProfile(
    name: json['name'] as String,
    path: json['path'] as String,
    optionOverrides: (json['options'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
  );
}

class GenericUciEngine implements ChessEngine {
  final EngineProfile profile;

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  Completer<String>? _moveCompleter;
  StreamSubscription? _stdoutSub;
  final _evalController = StreamController<EvalInfo>.broadcast();

  /// Engine identity parsed from the UCI handshake.
  String _engineName = 'Unknown';
  String _engineAuthor = '';

  /// UCI options advertised by the engine.
  final List<UciOption> options = [];

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');

  GenericUciEngine(this.profile);

  @override
  String get name => _engineName;
  @override
  String get version => '';
  @override
  String get license => 'Unknown';
  @override
  int get estimatedElo => 0;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  @override
  Future<void> initialize() async {
    _stateNotifier.value = EngineState.initializing;
    try {
      final file = File(profile.path);
      if (!await file.exists()) {
        throw FileSystemException('Engine binary not found', profile.path);
      }

      _process = await Process.start(profile.path, []);

      final ready = Completer<void>();

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line, handshake: !ready.isCompleted);
        if (line.trim() == 'uciok' && !ready.isCompleted) {
          ready.complete();
        }
      });

      // Start UCI handshake
      _send('uci');

      await ready.future.timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('[UCI] Handshake timeout for ${profile.path}');
      });

      // Apply saved option overrides
      for (final entry in profile.optionOverrides.entries) {
        _send('setoption name ${entry.key} value ${entry.value}');
        // Also update the in-memory option
        for (final opt in options) {
          if (opt.name == entry.key) opt.value = entry.value;
        }
      }

      // Use the profile name if set, otherwise use engine-reported name
      if (profile.name.isNotEmpty) {
        _engineName = profile.name;
      }

      _send('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[UCI] $_engineName ready (${options.length} options)');
    } catch (e) {
      debugPrint('[UCI] Init failed: $e');
      _stateNotifier.value = EngineState.error;
    }
  }

  void _send(String command) {
    _process?.stdin.writeln(command);
  }

  void _handleLine(String line, {bool handshake = false}) {
    final t = line.trim();

    // During handshake, parse engine identity and options
    if (handshake) {
      if (t.startsWith('id name ')) {
        _engineName = t.substring(8);
      } else if (t.startsWith('id author ')) {
        _engineAuthor = t.substring(10);
      } else if (t.startsWith('option name ')) {
        final opt = UciOption.parse(t);
        if (opt != null) options.add(opt);
      }
      return;
    }

    // Parse evaluation info lines
    if (t.startsWith('info') && t.contains('depth')) {
      final depthMatch = _depthRegex.firstMatch(t);
      if (depthMatch == null) return;

      double? score;
      final cpMatch = _cpRegex.firstMatch(t);
      final mateMatch = _mateRegex.firstMatch(t);
      if (cpMatch != null) {
        score = int.parse(cpMatch.group(1)!) / 100.0;
      } else if (mateMatch != null) {
        final mateIn = int.parse(mateMatch.group(1)!);
        score = mateIn > 0 ? 999.0 : -999.0;
      }

      if (score != null) {
        final pvMatch = _pvRegex.firstMatch(t);
        final pv = pvMatch?.group(1);
        final bestMove = pv?.split(' ').first;
        _evalController.add(EvalInfo(
          score: score,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: bestMove,
          pv: pv,
        ));
      }
    }

    // Parse bestmove
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
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_process == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    _send(positionCommand);
    _moveCompleter = Completer<String>();

    if (moveTime != null) {
      _send('go movetime ${moveTime.inMilliseconds}');
    } else {
      _send('go depth ${depth ?? 15}');
    }

    return _moveCompleter!.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _send('stop');
        throw TimeoutException('Search timed out');
      },
    );
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (_process == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
    _send(positionCommand);
    _send(infinite ? 'go infinite' : 'go depth ${depth ?? 20}');
    return _evalController.stream;
  }

  /// Set a UCI option at runtime.
  void setOption(String name, String value) {
    _send('setoption name $name value $value');
    for (final opt in options) {
      if (opt.name == name) opt.value = value;
    }
  }

  /// Trigger a button-type UCI option.
  void pressButton(String name) {
    _send('setoption name $name');
  }

  @override
  void stop() {
    _send('stop');
    _stateNotifier.value = EngineState.ready;
  }

  @override
  void dispose() {
    _send('quit');
    _stdoutSub?.cancel();
    _evalController.close();
    _process?.kill();
    _process = null;
    _stateNotifier.value = EngineState.disposed;
  }
}
