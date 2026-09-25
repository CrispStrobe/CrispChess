import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/voice/spoken_moves.dart';
import 'package:crispchess/voice/voice_pick.dart';

void main() {
  final moves = spokenMoves(chess.Chess()..move('e4')..move('e5'), VoiceLanguage.english);
  final phrases = phrasesOf(moves);

  /// Scores that make [said] the likeliest phrase per token, while every short
  /// phrase has the better summed log-probability.
  List<({double logprob, int tokens})> scoresFavouring(String said) => [
        for (final p in phrases)
          p == said
              ? (logprob: -3.0, tokens: 6) // -0.5 per token
              : (logprob: -2.0 * p.split(' ').length, tokens: p.split(' ').length + 1),
      ];

  test('a move is ranked by its best phrase, per token', () {
    final ranked = rankMoves(moves, scoresFavouring('knight to f3'));
    expect(ranked.first.uci, 'g1f3');
    expect(ranked.first.phrase, 'knight to f3');
    expect(ranked.first.score, closeTo(-0.5, 1e-9));
    expect(ranked.map((c) => c.uci).toSet().length, moves.length, reason: 'one entry per move');
    for (var i = 1; i < ranked.length; i++) {
      expect(ranked[i - 1].score, greaterThanOrEqualTo(ranked[i].score));
    }
  });

  test('a clear lead is confident, a near tie is not', () {
    final ranked = rankMoves(moves, scoresFavouring('knight to f3'));
    expect(isConfident(ranked), isTrue);
    final tie = [
      const VoiceCandidate('g1f3', 'Nf3', 'knight f3', -0.50),
      const VoiceCandidate('g1e2', 'Ne2', 'knight e2', -0.55),
    ];
    expect(isConfident(tie), isFalse);
    expect(isConfident(const []), isFalse);
    expect(isConfident(const [VoiceCandidate('e1g1', 'O-O', 'castles', -1.0)]), isTrue);
  });

  test('scores must line up with the phrases', () {
    expect(() => rankMoves(moves, scoresFavouring('e4').sublist(1)), throwsArgumentError);
  });
}
