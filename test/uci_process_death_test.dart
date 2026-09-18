// A UCI engine that dies is not a UCI engine that is thinking.
//
// Nothing watched the process, so when one exited mid-search the pending
// request was never completed: the caller waited out its own timeout and
// reported a crash as slowness. In the strength tournament that produced
// "no move within 60s", which sent the investigation after a search-time bug
// for a failure that might not have been one.
//
// These use a shell script as the engine. It speaks just enough UCI to be
// driven, and each variant fails in a different way on purpose.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _dir;

/// Writes an executable script and returns a profile pointing at it.
EngineProfile _engine(String name, String body) {
  final file = File('${_dir.path}/$name.sh');
  file.writeAsStringSync('#!/bin/bash\n$body\n');
  Process.runSync('chmod', ['+x', file.path]);
  return EngineProfile(name: name, path: file.path);
}

/// Answers the handshake, then does whatever [onGo] says.
String _script(String onGo) => '''
while IFS= read -r line; do
  case "\$line" in
    uci) echo "id name Fake"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*) $onGo ;;
    quit) exit 0 ;;
  esac
done
''';

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('uci_death'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('a process that exits mid-search reports the death, not a timeout',
      () async {
    final engine = GenericUciEngine(_engine('dies', _script('exit 3')));
    await engine.initialize();

    final watch = Stopwatch()..start();
    await expectLater(
      engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 300)),
      throwsA(isA<EngineProcessDiedException>()),
    );
    watch.stop();

    // The search cap for a 300ms budget is 6.8s. Waiting for it is the bug.
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)),
        reason: 'the death should be noticed, not waited out');
    engine.dispose();
  });

  test('the exit code and the last stderr travel with it', () async {
    final engine = GenericUciEngine(_engine(
        'complains', _script('echo "assertion failed: bad move" >&2; exit 9')));
    await engine.initialize();

    try {
      await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 300));
      fail('expected the death to be reported');
    } on EngineProcessDiedException catch (e) {
      expect(e.exitCode, 9);
      expect(e.stderrTail.join('\n'), contains('assertion failed'));
      expect(e.toString(), contains('exited while searching'));
    }
    engine.dispose();
  });

  test('an engine that is merely slow still reports a timeout', () async {
    // The distinction being drawn: this one is alive and says nothing.
    final engine = GenericUciEngine(_engine('slow', _script('sleep 30')));
    await engine.initialize();

    await expectLater(
      engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
    engine.dispose();
  });

  test('a request made after the engine is gone fails immediately', () async {
    final engine = GenericUciEngine(_engine('quits', _script('exit 0')));
    await engine.initialize();

    try {
      await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 300));
    } catch (_) {/* the first request is the one that notices */}

    final watch = Stopwatch()..start();
    await expectLater(
      engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 300)),
      throwsA(isA<EngineProcessDiedException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    engine.dispose();
  });
}
