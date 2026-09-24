/// What a player may say for each legal move, in English and German, and
/// the grammar that restricts speech recognition to exactly those phrases.
///
/// Recognition is constrained per position: the grammar lists only the legal
/// moves' spoken forms, so a small offline Whisper model can only ever hear
/// a legal move (GBNF grammar sampling in CrispASR/whisper.cpp). The same
/// table maps the transcript back to the move.
library;

import 'package:chess/chess.dart' as chess;

enum VoiceLanguage { english, german }

const _pieceWords = {
  VoiceLanguage.english: {
    'N': ['knight'], 'B': ['bishop'], 'R': ['rook'], 'Q': ['queen'], 'K': ['king'],
  },
  VoiceLanguage.german: {
    'N': ['springer'], 'B': ['läufer', 'laeufer'], 'R': ['turm'], 'Q': ['dame'], 'K': ['könig', 'koenig'],
  },
};

const _pawnWord = {VoiceLanguage.english: 'pawn', VoiceLanguage.german: 'bauer'};
const _captureWords = {
  VoiceLanguage.english: ['takes', 'captures', 'x'],
  VoiceLanguage.german: ['schlägt', 'nimmt', 'x'],
};
const _toWords = {VoiceLanguage.english: ['to'], VoiceLanguage.german: ['nach', 'auf']};
const _castleShort = {
  VoiceLanguage.english: ['castles', 'castle', 'short castle', 'castle short', 'castles kingside', 'o o'],
  VoiceLanguage.german: ['kurze rochade', 'rochade kurz', 'rochade', 'o o'],
};
const _castleLong = {
  VoiceLanguage.english: ['long castle', 'castle long', 'castles queenside', 'o o o'],
  VoiceLanguage.german: ['lange rochade', 'rochade lang', 'o o o'],
};
const _promoteWords = {
  VoiceLanguage.english: ['promotes to', 'promote to', 'equals', ''],
  VoiceLanguage.german: ['wird', 'umwandlung in', 'umwandlung', ''],
};

/// A legal move and every phrase that means it.
class SpokenMove {
  final String uci;
  final String san;
  final List<String> phrases;
  const SpokenMove(this.uci, this.san, this.phrases);
}

String _uci(chess.Move m) =>
    '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}';

/// Phrases for [san] (check marks ignored). Squares are spoken as written
/// ("e4"); a piece move may name the piece and, for disambiguation, the
/// origin file or rank, as SAN does.
List<String> phrasesForSan(String san, VoiceLanguage lang) {
  final s = san.replaceAll(RegExp(r'[+#]'), '');
  if (s == 'O-O') return List.of(_castleShort[lang]!);
  if (s == 'O-O-O') return List.of(_castleLong[lang]!);
  final m = RegExp(r'^([NBRQK])?([a-h])?([1-8])?(x)?([a-h][1-8])(=([NBRQ]))?$')
      .firstMatch(s);
  if (m == null) return [s.toLowerCase()];
  final piece = m.group(1), fromFile = m.group(2), fromRank = m.group(3);
  final capture = m.group(4) != null;
  final to = m.group(5)!, promo = m.group(7);

  final heads = <String>[];
  final origin = '${fromFile ?? ''}${fromRank ?? ''}';
  if (piece != null) {
    for (final w in _pieceWords[lang]![piece]!) {
      heads.add(origin.isEmpty ? w : '$w $origin');
    }
  } else {
    // A pawn: the file it comes from on a capture ("e takes d5"), optionally
    // the word "pawn", or nothing at all on a push ("e4").
    heads.add(capture ? origin : '');
    heads.add(capture ? '${_pawnWord[lang]} $origin' : _pawnWord[lang]!);
  }
  final links = capture
      ? _captureWords[lang]!
      : ['', ..._toWords[lang]!];
  final out = <String>{};
  for (final h in heads) {
    for (final l in links) {
      final core = [h, l, to].where((x) => x.isNotEmpty).join(' ');
      if (promo == null) {
        out.add(core);
      } else {
        for (final p in _promoteWords[lang]!) {
          for (final w in _pieceWords[lang]![promo]!) {
            out.add([core, p, w].where((x) => x.isNotEmpty).join(' '));
          }
        }
      }
    }
  }
  return out.toList();
}

/// Every legal move in [board] with its phrases in [lang].
List<SpokenMove> spokenMoves(chess.Chess board, VoiceLanguage lang) => [
      for (final m in board.generate_moves())
        () {
          final san = board.move_to_san(m);
          return SpokenMove(_uci(m), san, phrasesForSan(san, lang));
        }()
    ];

/// Lower-case, umlauts kept, punctuation dropped, whitespace collapsed; digits
/// and letters split so "e 4", "E4" and "e4" compare equal.
String normalizeUtterance(String text) {
  var t = text.toLowerCase();
  t = t.replaceAll(RegExp(r'[.,!?;:"“”„()]'), ' ');
  t = t.replaceAll('-', ' ');
  t = t.replaceAllMapped(RegExp(r'([a-h])\s+([1-8])'), (m) => '${m[1]}${m[2]}');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The move [transcript] names, or null. Exact phrase match first; failing
/// that, the unique move whose phrase the transcript ends with (speech
/// recognisers add filler in front: "okay knight f3").
String? matchUtterance(String transcript, List<SpokenMove> moves) {
  final t = normalizeUtterance(transcript);
  if (t.isEmpty) return null;
  for (final m in moves) {
    if (m.phrases.any((p) => normalizeUtterance(p) == t)) return m.uci;
  }
  // The longest phrase the transcript ends with wins: "okay knight f3" ends
  // with both "knight f3" and the pawn move "f3", and means the knight.
  var best = 0;
  final hits = <String>{};
  for (final m in moves) {
    for (final p in m.phrases) {
      final n = normalizeUtterance(p);
      if (n.isEmpty || !t.endsWith(' $n')) continue;
      if (n.length > best) {
        best = n.length;
        hits
          ..clear()
          ..add(m.uci);
      } else if (n.length == best) {
        hits.add(m.uci);
      }
    }
  }
  return hits.length == 1 ? hits.single : null;
}

/// A GBNF grammar accepting exactly the phrases of [moves] (with the leading
/// space Whisper emits before the first word).
String grammarFor(List<SpokenMove> moves) {
  final phrases = <String>{
    for (final m in moves)
      for (final p in m.phrases) normalizeUtterance(p)
  }.where((p) => p.isNotEmpty).toList()
    ..sort();
  String lit(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  return 'root ::= " " move "."?\n'
      'move ::= ${phrases.map(lit).join(' | ')}\n';
}
