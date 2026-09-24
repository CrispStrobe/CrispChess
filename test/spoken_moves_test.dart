import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/voice/spoken_moves.dart';

void main() {
  const en = VoiceLanguage.english, de = VoiceLanguage.german;

  test('piece moves, captures, pawns, castling, promotion', () {
    expect(phrasesForSan('Nf3', en), containsAll(['knight f3', 'knight to f3']));
    expect(phrasesForSan('Nxe5+', en), containsAll(['knight takes e5', 'knight captures e5']));
    expect(phrasesForSan('e4', en), containsAll(['e4', 'pawn e4', 'pawn to e4']));
    expect(phrasesForSan('exd5', en), containsAll(['e takes d5', 'pawn e takes d5']));
    expect(phrasesForSan('O-O', en), contains('castles'));
    expect(phrasesForSan('O-O-O', de), contains('lange rochade'));
    expect(phrasesForSan('e8=Q', en), containsAll(['e8 queen', 'e8 promotes to queen']));
    expect(phrasesForSan('Nbd7', en), contains('knight b d7'));
    expect(phrasesForSan('Lf4', de), isNotEmpty);
    expect(phrasesForSan('Bf4', de), containsAll(['läufer f4', 'läufer nach f4']));
    expect(phrasesForSan('Qxd8#', de), contains('dame schlägt d8'));
  });

  test('matching a transcript to the legal move', () {
    final b = chess.Chess()..move('e4')..move('e5');
    final moves = spokenMoves(b, en);
    expect(matchUtterance('Knight to F3.', moves), 'g1f3');
    expect(matchUtterance('knight f 3', moves), 'g1f3');
    expect(matchUtterance('okay, knight f3', moves), 'g1f3');
    expect(matchUtterance('Bishop c4', moves), 'f1c4');
    expect(matchUtterance('pawn d4', moves), 'd2d4');
    expect(matchUtterance('knight e5', moves), isNull, reason: 'not legal');
    // German
    final dm = spokenMoves(b, de);
    expect(matchUtterance('Springer nach f3', dm), 'g1f3');
    expect(matchUtterance('Läufer c4', dm), 'f1c4');
  });

  test('ambiguous knights must name their file', () {
    final b = chess.Chess.fromFEN('4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1');
    final moves = spokenMoves(b, en);
    expect(matchUtterance('knight b d2', moves), 'b1d2');
    expect(matchUtterance('knight f d2', moves), 'f1d2');
    expect(matchUtterance('knight d2', moves), isNull);
  });

  test('castling by voice', () {
    final b = chess.Chess.fromFEN('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
    expect(matchUtterance('castles', spokenMoves(b, en)), 'e1g1');
    expect(matchUtterance('long castle', spokenMoves(b, en)), 'e1c1');
    expect(matchUtterance('kurze Rochade', spokenMoves(b, de)), 'e1g1');
  });

  test('the grammar lists exactly the legal phrases', () {
    final g = grammarFor(spokenMoves(chess.Chess(), en));
    expect(g, startsWith('root ::= " " move'));
    expect(g, contains('"knight f3"'));
    expect(g, contains('"e4"'));
    expect(g, isNot(contains('"knight e5"')));
  });
}
