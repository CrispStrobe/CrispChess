// Real model output for the App Store screenshots.
//
// The screenshot test (test/store_screenshots_generator_test.dart) renders the
// real widgets but cannot download models, so the numbers it shows are
// produced here, once, by the same services the app uses, and saved under
// test/fixtures/store/. Nothing in those files is typed in by hand.
//
//   flutter test tool/store/store_fixtures_test.dart            # ghost + lens
//   STORE_VOICE=1 LD_LIBRARY_PATH=<libcrispasr lib dir> \
//     flutter test tool/store/store_fixtures_test.dart          # + voice
//
// Parts: ghost (Maia rates 30 real games of one Lichess player, from the CC0
// database, test/fixtures/store/ghost_games.json), lens (Human Lens on
// positions of those games; the most telling report is kept) and voice (the
// app's recogniser ranking TTS recordings of spoken moves). STORE_PARTS picks
// some of them, e.g. STORE_PARTS=lens. Lives under tool/ so the regular suite
// does not run it.
// ignore_for_file: avoid_print
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/human_lens.dart';
import 'package:crispchess/chess/player_profile.dart';
import 'package:crispchess/services/human_lens_service.dart';
import 'package:crispchess/voice/voice_input.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/store';
final _env = Platform.environment;
bool _part(String name) =>
    (_env['STORE_PARTS'] ?? 'ghost,lens,voice').split(',').contains(name);

void _write(String name, Object json) {
  File('$_dir/$name')
      .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(json)}\n');
  print('wrote $_dir/$name');
}

List<String> _pgns() => [
      for (final g in jsonDecode(File('$_dir/ghost_games.json').readAsStringSync())
          as List)
        g['pgn'] as String
    ];

Map<String, Object?> reportJson(String positionCommand, HumanLensReport r) => {
      'positionCommand': positionCommand,
      'elo': r.elo,
      'bestMove': r.bestMove,
      'candidates': [
        for (final c in r.candidates)
          {
            'uci': c.uci,
            'probability': c.probability,
            'evalAfter': c.evalAfter,
            'winChanceLoss': c.winChanceLoss,
          }
      ],
      'findabilityByElo': {
        for (final e in r.findabilityByElo.entries) '${e.key}': e.value
      },
    };

void main() {
  test('ghost: rating Maia measures for the games', () async {
    final profile = PlayerProfile.fromPgns(_pgns());
    final sw = Stopwatch()..start();
    final elo = await HumanLensService.instance.estimatePlayerElo(
      profile.moves,
      onProgress: (d, t) {
        if (d % 20 == 0) print('ghost $d/$t');
      },
    );
    print('ghost: ${profile.games} games, ${profile.moves.length} moves, '
        'measured $elo in ${sw.elapsed.inSeconds}s');
    _write('ghost.json', {
      'source': 'HumanLensService.estimatePlayerElo (Maia 5M) over the moves '
          'of ghost_games.json, tool/store/store_fixtures_test.dart',
      'games': profile.games,
      'movesUsed': profile.moves.take(120).length,
      'elo': elo,
    });
  }, timeout: const Timeout(Duration(minutes: 60)), skip: !_part('ghost'));

  test('lens: Human Lens on positions of those games', () async {
    // White-to-move positions from the player's own games as White, in the
    // middlegame, so the screenshot shows a real game from the player's side.
    final profile = PlayerProfile.fromPgns(_pgns());
    final positions = <String>{};
    for (final m in profile.moves) {
      final moves = m.positionCommand.split(' ').skip(3).toList();
      if (moves.length.isOdd || moves.length < 16 || moves.length > 40) continue;
      final game = ChessGame();
      if (!moves.every(game.makeMove)) continue;
      positions.add(game.positionCommand);
    }
    final limit = int.tryParse(_env['STORE_LENS_POSITIONS'] ?? '') ?? 40;
    final picked = positions.toList();
    // Spread the sample across the games rather than taking the first few.
    final step = (picked.length / limit).ceil().clamp(1, 1 << 20);
    final sample = [for (var i = 0; i < picked.length; i += step) picked[i]];
    final reports = <Map<String, Object?>>[];
    for (final cmd in sample) {
      final r = await HumanLensService.instance.analyzePosition(cmd, elo: 1400);
      final best = r.best;
      print('${reports.length} trap=${r.isTrap} best=${r.bestMove} '
          'p=${best?.probability.toStringAsFixed(2)} natural=${r.naturalFromElo} '
          '${r.findabilityByElo.values.map((v) => v.toStringAsFixed(2)).join(' ')}');
      reports.add({
        ...reportJson(cmd, r),
        'isTrap': r.isTrap,
        'findability': r.findability.name,
      });
    }
    // The most telling report: a trap whose engine move gets found more often
    // the higher the rating — the lens's whole point in one picture.
    double interest(Map<String, Object?> j) {
      final f = (j['findabilityByElo'] as Map).values.cast<double>().toList();
      final rise = f.last - f.first;
      return (j['isTrap'] == true ? 1 : 0) + rise;
    }

    final ranked = [...reports]..sort((a, b) => interest(b).compareTo(interest(a)));
    _write('lens.json', {
      'source': 'HumanLensService.analyzePosition(elo: 1400) — Maia 5M for the '
          'players, the built-in engine at depth 8 for the verdicts — on '
          '${reports.length} White-to-move positions of ghost_games.json; '
          '"chosen" is the one with the highest interest score '
          '(trap + rise of the findability curve), tool/store/store_fixtures_test.dart',
      'chosen': ranked.first,
      'all': reports,
    });
  }, timeout: const Timeout(Duration(minutes: 90)), skip: !_part('lens'));

  test('voice: rankings of recorded moves', () async {
    final root = _env['STORE_VOICE_DIR'] ?? '/mnt/volume1/tmp/voice-eval';
    final cases = File('$root/cases.tsv')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.split('\t'))
        .toList();
    // Only positions a real game reaches, so the board behind the sheet is an
    // ordinary game rather than a constructed test position.
    const games = {'start': <String>[], 'e4e5': ['e2e4', 'e7e5'], 'e4d5': ['e2e4', 'd7d5']};
    expect(VoiceInput.available, isTrue, reason: 'libcrispasr with phrase scoring');
    final voice = await VoiceInput.open(model: VoiceModel.base);
    final out = <Map<String, Object?>>[];
    final voices = Directory('$root/audio').listSync().whereType<Directory>()
        .map((d) => d.uri.pathSegments[d.uri.pathSegments.length - 2]).toList()..sort();
    for (final v in voices) {
      final german = v.contains('_d') || v.contains('thorsten') || v.contains('kerstin');
      for (var i = 0; i < cases.length; i++) {
        final moves = games[cases[i][0]];
        final wav = File('$root/audio/$v/${i + 1}.wav');
        if (moves == null || !wav.existsSync()) continue;
        final game = ChessGame();
        for (final m in moves) {
          game.makeMove(m);
        }
        final ranked = await voice.rankPcm(_wav16k(wav.path), game.currentFEN,
            german ? VoiceLanguage.german : VoiceLanguage.english);
        final said = cases[i][german ? 3 : 2];
        print('$v #${i + 1} "$said" confident=${isConfident(ranked)} '
            '${ranked.take(3).join(', ')}');
        out.add({
          'voice': v,
          'lang': german ? 'de' : 'en',
          'case': i + 1,
          'moves': moves,
          'said': said,
          'want': cases[i][1],
          'confident': isConfident(ranked),
          'ranked': [
            for (final c in ranked.take(5))
              {'uci': c.uci, 'san': c.san, 'phrase': c.phrase, 'score': c.score}
          ],
        });
      }
    }
    voice.dispose();
    // The sheet only appears when the recogniser is unsure; show one where the
    // move actually said still comes first, per language.
    Map<String, Object?>? pick(String lang) {
      for (final o in out) {
        final ranked = o['ranked'] as List;
        if (o['lang'] == lang && o['confident'] == false && ranked.length >= 2 &&
            (ranked.first as Map)['uci'] == o['want'] &&
            (o['moves'] as List).isNotEmpty) {
          return o;
        }
      }
      return null;
    }

    _write('voice.json', {
      'source': 'VoiceInput.rankPcm (Whisper base via libcrispasr, the model '
          'the app loads) on the TTS recordings of /mnt/volume1/tmp/voice-eval; '
          '"chosen" is the first unconfident ranking per language whose top '
          'candidate is the move said, tool/store/store_fixtures_test.dart',
      'chosen': {'en': pick('en'), 'de': pick('de')},
      'all': out,
    });
  }, timeout: const Timeout(Duration(minutes: 60)),
      skip: !_part('voice') || _env['STORE_VOICE'] != '1');
}

/// 16-bit mono 16 kHz PCM WAV → floats in [-1, 1].
Float32List _wav16k(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(b);
  var at = 12;
  while (at + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(at, at + 4));
    final size = d.getUint32(at + 4, Endian.little);
    if (id == 'data') {
      final n = size ~/ 2;
      return Float32List.fromList([
        for (var i = 0; i < n; i++) d.getInt16(at + 8 + 2 * i, Endian.little) / 32768
      ]);
    }
    at += 8 + size + (size & 1);
  }
  throw FormatException('no data chunk in $path');
}
