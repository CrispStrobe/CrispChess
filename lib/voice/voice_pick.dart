/// From speech-recogniser scores to a ranked list of legal moves.
///
/// Recognition scores every spoken phrase of every legal move (see
/// [spokenMoves]); a move is as likely as its likeliest phrase. Pure Dart, so
/// it is shared by every platform and testable without the native library.
library;

import 'dart:math' as math;

import 'spoken_moves.dart';

/// One legal move and how well the audio matches it.
class VoiceCandidate {
  final String uci;
  final String san;

  /// The phrase of this move that matched best.
  final String phrase;

  /// Log-probability per token of [phrase] (higher is better, at most 0).
  final double score;

  const VoiceCandidate(this.uci, this.san, this.phrase, this.score);

  @override
  String toString() => '$san "$phrase" ${score.toStringAsFixed(2)}';
}

/// The phrases of [moves], in the order [rankMoves] expects their scores.
List<String> phrasesOf(List<SpokenMove> moves) => [
      for (final m in moves) ...m.phrases,
    ];

/// Legal moves best first, each scored by its best phrase.
///
/// [scores] holds, for every phrase of [phrasesOf] in order, the summed
/// log-probability and the number of tokens it covers. Scores are compared
/// per token: a plain sum favours short phrases, and the pawn move "b4" would
/// beat "knight to f3" whatever was said.
List<VoiceCandidate> rankMoves(
    List<SpokenMove> moves, List<({double logprob, int tokens})> scores) {
  final n = moves.fold(0, (a, m) => a + m.phrases.length);
  if (scores.length != n) {
    throw ArgumentError('${scores.length} scores for $n phrases');
  }
  final ranked = <VoiceCandidate>[];
  var k = 0;
  for (final m in moves) {
    VoiceCandidate? best;
    for (final p in m.phrases) {
      final s = scores[k++];
      final perToken = s.logprob / math.max(1, s.tokens);
      if (best == null || perToken > best.score) {
        best = VoiceCandidate(m.uci, m.san, p, perToken);
      }
    }
    if (best != null) ranked.add(best);
  }
  ranked.sort((a, b) => b.score.compareTo(a.score));
  return ranked;
}

/// Whether the best move is clear enough to play without asking.
///
/// [margin] is the lead, in log-probability per token, the best move needs
/// over the runner-up.
bool isConfident(List<VoiceCandidate> ranked, {double margin = voiceConfidentMargin}) =>
    ranked.isNotEmpty &&
    ranked.first.score.isFinite &&
    (ranked.length == 1 || ranked.first.score - ranked[1].score >= margin);

/// Default lead for [isConfident].
const voiceConfidentMargin = 0.3;

/// Text that primes the recogniser for chess moves in [lang]: a few example
/// phrases in the style of [spokenMoves].
String voicePrompt(VoiceLanguage lang) => switch (lang) {
      VoiceLanguage.english => 'Chess moves: knight f3, bishop c4, e4, castles kingside.',
      VoiceLanguage.german => 'Schachzüge: Springer f3, Läufer c4, e4, kurze Rochade.',
    };

/// The Whisper language code for [lang].
String voiceLanguageCode(VoiceLanguage lang) => switch (lang) {
      VoiceLanguage.english => 'en',
      VoiceLanguage.german => 'de',
    };
