// What analysis actually sends, and what it does when the engine is gone.
//
// Every test written for these engines covers `bestMove`. `analyze` had none,
// and it turned out to have the bugs `bestMove` had already been fixed for:
// a fixed depth with no clock behind it, and a dead process treated as a quiet
// one. These watch the wire.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _dir;
late File _log;

/// An engine that records every command it is given, so a test can assert on
/// what was sent rather than on what the code appears to send.
EngineProfile _recorder({String onGo = 'echo "bestmove e2e4"'}) {
  _log = File('${_dir.path}/commands.log');
  final file = File('${_dir.path}/recorder.sh');
  file.writeAsStringSync('''
#!/bin/bash
while IFS= read -r line; do
  echo "\$line" >> "${_log.path}"
  case "\$line" in
    uci) echo "id name Recorder"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*) $onGo ;;
    quit) exit 0 ;;
  esac
done
''');
  Process.runSync('chmod', ['+x', file.path]);
  return EngineProfile(name: 'Recorder', path: file.path);
}

Future<List<String>> _commands() async {
  for (var i = 0; i < 40 && !_log.existsSync(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return _log.existsSync() ? _log.readAsLinesSync() : const [];
}

Future<String?> _goCommand() async {
  for (var i = 0; i < 40; i++) {
    final go = (await _commands()).where((l) => l.startsWith('go')).toList();
    if (go.isNotEmpty) return go.first;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return null;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('analysis'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('a depth search carries a clock as well', () async {
    final engine = GenericUciEngine(_recorder(onGo: 'true'));
    await engine.initialize();

    engine.analyze('position startpos', depth: 12).listen((_) {});
    final go = await _goCommand();

    expect(go, isNotNull, reason: 'analysis should have started a search');
    expect(go, contains('depth 12'));
    expect(go, contains('movetime'),
        reason: 'a fixed depth costs whatever that depth costs in the '
            'position, and nothing else here ever stops it');
    engine.dispose();
  });

  test('infinite analysis is left unbounded', () async {
    final engine = GenericUciEngine(_recorder(onGo: 'true'));
    await engine.initialize();

    engine.analyze('position startpos', infinite: true).listen((_) {});
    final go = await _goCommand();

    expect(go, 'go infinite',
        reason: 'infinite is unbounded on purpose and ends at stop');
    engine.dispose();
  });

  test('analysis is not started on a process that has died', () async {
    final engine = GenericUciEngine(_recorder(onGo: 'exit 4'));
    await engine.initialize();

    // Kill it the way it dies in the wild: ask for a move it answers by
    // exiting.
    await expectLater(
      engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 200)),
      throwsA(isA<EngineProcessDiedException>()),
    );

    final before = (await _commands()).length;
    final events = await engine
        .analyze('position startpos', depth: 12)
        .toList()
        .timeout(const Duration(seconds: 3));

    expect(events, isEmpty);
    expect((await _commands()).length, before,
        reason: 'nothing should be written to a dead engine');
    engine.dispose();
  });
}
