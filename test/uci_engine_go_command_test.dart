// End-to-end check that a UCI engine is driven by a *time* budget rather than
// a fixed depth.
//
// A fixed `go depth N` costs whatever depth N costs in the position at hand:
// cheap in the opening, an order of magnitude more once the position opens up
// (measured with the built-in search: 0.7s at the start vs 3-5s by the
// middlegame for the same depth). That is the "the engine gets slower every
// turn" report. `go movetime` is flat for the whole game.
//
// Drives the real GenericUciEngine against a tiny UCI-speaking script, so the
// assertion covers the actual command that reaches an engine's stdin.
@TestOn('vm')
library;

import 'dart:io';

import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Writes a shell script that speaks just enough UCI to answer a search, and
/// records every command it receives.
({String enginePath, String logPath}) _writeFakeEngine(Directory dir) {
  final log = '${dir.path}/commands.log';
  final script = File('${dir.path}/fake_uci.sh');
  script.writeAsStringSync('''
#!/bin/sh
while IFS= read -r line; do
  echo "\$line" >> "$log"
  case "\$line" in
    uci) echo "id name FakeEngine"; echo "id author test"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*) echo "info depth 4 score cp 21 pv e2e4 e7e5"; echo "bestmove e2e4" ;;
    quit) exit 0 ;;
  esac
done
''');
  Process.runSync('chmod', ['+x', script.path]);
  return (enginePath: script.path, logPath: log);
}

/// Like [_writeFakeEngine], but models a real engine's pondering behaviour: an
/// open-ended search answers only once it is told to `stop`, and it answers
/// with the move it found for the *previous* position.
({String enginePath, String logPath}) _writePonderingEngine(Directory dir) {
  final log = '${dir.path}/commands.log';
  final script = File('${dir.path}/ponder_uci.sh');
  script.writeAsStringSync('''
#!/bin/sh
searching=0
while IFS= read -r line; do
  echo "\$line" >> "$log"
  case "\$line" in
    uci) echo "id name PonderEngine"; echo "uciok" ;;
    isready) echo "readyok" ;;
    "go infinite") searching=1 ;;
    stop) if [ "\$searching" = 1 ]; then searching=0; echo "bestmove a2a3"; fi ;;
    go*) echo "bestmove e2e4" ;;
    quit) exit 0 ;;
  esac
done
''');
  Process.runSync('chmod', ['+x', script.path]);
  return (enginePath: script.path, logPath: log);
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('crispchess_uci'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<List<String>> runMove({
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    final fake = _writeFakeEngine(dir);
    final engine = GenericUciEngine(
        EngineProfile(name: 'Fake', path: fake.enginePath));
    await engine.initialize();
    addTearDown(engine.dispose);

    final move = await engine.bestMove('position startpos',
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    expect(move, 'e2e4');

    // The script appends as it reads; give it a moment to flush the last line.
    for (var i = 0; i < 50; i++) {
      final lines = File(fake.logPath).existsSync()
          ? File(fake.logPath).readAsLinesSync()
          : <String>[];
      if (lines.any((l) => l.startsWith('go'))) return lines;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('engine never received a `go` command');
  }

  test('normal play asks for a time budget, not a fixed depth', () async {
    final commands = await runMove(skillLevel: 12);
    final go = commands.firstWhere((c) => c.startsWith('go'));
    expect(go, startsWith('go movetime '),
        reason: 'play must be driven by time; a fixed depth costs '
            'increasingly more as the game opens up');
  }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);

  test('an explicit move time is passed through', () async {
    final commands = await runMove(moveTime: const Duration(milliseconds: 750));
    expect(commands, contains('go movetime 750'));
  }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);

  test('an explicit depth (hint / analysis) still wins', () async {
    final commands = await runMove(depth: 10);
    expect(commands, contains('go depth 10'));
  }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);

  test('the position is sent before the search starts', () async {
    final commands = await runMove(skillLevel: 5);
    final posIndex = commands.indexOf('position startpos');
    final goIndex = commands.indexWhere((c) => c.startsWith('go'));
    expect(posIndex, greaterThanOrEqualTo(0));
    expect(goIndex, greaterThan(posIndex));
  }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);

  test('a move request is never answered by the aborted ponder search',
      () async {
    // The engine ponders after its own move; when the player moves, the app
    // stops that search and asks for a new one. The ponder search's `bestmove`
    // arrives first — for the previous position. It used to be handed back as
    // the answer, so the engine "played" a move that was usually illegal on the
    // real board, and the UI stayed on "thinking" for the rest of the game.
    final fake = _writePonderingEngine(dir);
    final engine = GenericUciEngine(
        EngineProfile(name: 'Ponder', path: fake.enginePath));
    await engine.initialize();
    addTearDown(engine.dispose);

    // Ponder the current position.
    engine.analyze('position startpos moves d2d4', infinite: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Player moved: ask for a move in the new position.
    final move = await engine.bestMove('position startpos moves d2d4 d7d5',
        moveTime: const Duration(milliseconds: 100));

    expect(move, 'e2e4',
        reason: 'the answer must come from the new search, not from the '
            'ponder search that was just aborted (which answers a2a3)');

    final commands = File(fake.logPath).readAsLinesSync();
    expect(commands, contains('stop'));
    expect(commands.indexOf('position startpos moves d2d4 d7d5'),
        greaterThan(commands.indexOf('stop')),
        reason: 'the new position must not be sent while the old search runs');
  }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);
}
