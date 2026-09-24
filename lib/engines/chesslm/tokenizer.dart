/// Tokenizers for the chess language models, from a HuggingFace
/// `tokenizer.json`.
///
/// Three families cover every model the app ships:
/// - byte-level BPE (GPT-2, Pythia, SmolLM2), with GPT-2's own
///   pre-tokenization regex — the interpreter's BpeTokenizer uses the newer
///   Qwen/Llama-3 split, which keeps a space apart from a following number
///   (" 2." becomes " " + "2", where GPT-2 has " 2") — and SmolLM2's
///   individual-digit split first;
/// - SentencePiece-style BPE (Llama/Mistral: `▁` for spaces, merges over the
///   whole string, byte fallback, a BOS token from the template);
/// - word level (chessformer: one token per UCI move).
///
/// Encodings are checked token for token against the `tokenizers` library in
/// test/chess_lm_tokenizer_test.dart. Chess notation is ASCII, so the NFC
/// normalizer some of them declare has nothing to do.
library;

import 'dart:convert';

abstract class ChessLmTokenizer {
  /// Ids for [text], with the tokens the model's template adds (a BOS) when
  /// [addSpecial] — what `tokenizer(text)` gives in Python.
  List<int> encode(String text, {bool addSpecial = true});

  factory ChessLmTokenizer.fromJson(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final model = j['model'] as Map<String, dynamic>;
    switch (model['type']) {
      case 'WordLevel':
        return _WordLevelTokenizer(j);
      case 'BPE':
        final pre = j['pre_tokenizer'] as Map<String, dynamic>?;
        if (_mentions(pre, 'ByteLevel')) {
          return _ByteLevelTokenizer(j,
              splitDigits: _mentions(pre, 'Digits'),
              prefix: _templatePrefix(j));
        }
        return _SentencePieceBpe(j);
    }
    throw UnsupportedError('Tokenizer model ${model['type']}');
  }
}

bool _mentions(Object? node, String type) {
  if (node is Map) {
    if (node['type'] == type) return true;
    return node.values.any((v) => _mentions(v, type));
  }
  if (node is List) return node.any((v) => _mentions(v, type));
  return false;
}

/// Special-token ids a `TemplateProcessing` post-processor puts before the
/// sequence (a BOS); none for the byte-level post-processors.
List<int> _templatePrefix(Map<String, dynamic> j) {
  final post = j['post_processor'] as Map<String, dynamic>?;
  if (post == null || post['type'] != 'TemplateProcessing') return const [];
  final specials = (post['special_tokens'] as Map<String, dynamic>?) ?? {};
  final out = <int>[];
  for (final part in post['single'] as List) {
    final special = (part as Map)['SpecialToken'];
    if (special == null) break; // only what precedes the sequence
    final entry = specials[special['id']] as Map<String, dynamic>?;
    final ids = (entry?['ids'] as List?)?.cast<int>();
    if (ids != null) out.addAll(ids);
  }
  return out;
}

Map<String, int> _mergeRanks(Map<String, dynamic> j) {
  final merges = (j['model'] as Map)['merges'] as List;
  return {
    for (var i = 0; i < merges.length; i++)
      (merges[i] is String ? merges[i] as String : '${merges[i][0]} ${merges[i][1]}'): i
  };
}

/// Repeatedly merges the adjacent pair with the lowest rank.
List<String> _bpe(List<String> symbols, Map<String, int> ranks) {
  while (symbols.length > 1) {
    var best = -1, bestRank = 1 << 62;
    for (var i = 0; i < symbols.length - 1; i++) {
      final r = ranks['${symbols[i]} ${symbols[i + 1]}'];
      if (r != null && r < bestRank) {
        bestRank = r;
        best = i;
      }
    }
    if (best < 0) break;
    symbols = [
      ...symbols.sublist(0, best),
      symbols[best] + symbols[best + 1],
      ...symbols.sublist(best + 2),
    ];
  }
  return symbols;
}

class _ByteLevelTokenizer implements ChessLmTokenizer {
  final Map<String, int> vocab;
  final Map<String, int> ranks;
  final bool splitDigits;
  final List<int> prefix;
  final Map<String, List<int>> _cache = {};

  /// GPT-2's pre-tokenization pattern.
  static final _gpt2 = RegExp(
      "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+",
      unicode: true);
  static final _digit = RegExp(r'\d');

  /// GPT-2's reversible byte -> printable-character table.
  static final List<String> _byteChars = () {
    final bs = <int>[
      for (var b = 33; b <= 126; b++) b,
      for (var b = 161; b <= 172; b++) b,
      for (var b = 174; b <= 255; b++) b,
    ];
    final cs = List<int>.of(bs);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n++);
      }
    }
    final out = List<String>.filled(256, '');
    for (var i = 0; i < bs.length; i++) {
      out[bs[i]] = String.fromCharCode(cs[i]);
    }
    return out;
  }();

  _ByteLevelTokenizer(Map<String, dynamic> j,
      {required this.splitDigits, required this.prefix})
      : vocab = ((j['model'] as Map)['vocab'] as Map).cast<String, int>(),
        ranks = _mergeRanks(j);

  List<int> _word(String piece) => _cache.putIfAbsent(
      piece,
      () => [
            for (final s in _bpe(
                [for (final b in utf8.encode(piece)) _byteChars[b]], ranks))
              if (vocab[s] case final id?) id
          ]);

  void _encodeInto(String text, List<int> ids) {
    for (final m in _gpt2.allMatches(text)) {
      ids.addAll(_word(m.group(0)!));
    }
  }

  @override
  List<int> encode(String text, {bool addSpecial = true}) {
    final ids = <int>[if (addSpecial) ...prefix];
    if (!splitDigits) {
      _encodeInto(text, ids);
      return ids;
    }
    // `Digits(individual_digits)` isolates every digit before the byte-level
    // split; pre-token boundaries are merge boundaries, so encoding the
    // pieces separately is exact.
    var start = 0;
    for (final m in _digit.allMatches(text)) {
      if (m.start > start) _encodeInto(text.substring(start, m.start), ids);
      _encodeInto(m.group(0)!, ids);
      start = m.end;
    }
    if (start < text.length) _encodeInto(text.substring(start), ids);
    return ids;
  }
}

/// Llama/Mistral-style BPE: normalize spaces to `▁` (with one prepended),
/// merge by rank across the whole string, unknown characters as `<0xNN>`.
class _SentencePieceBpe implements ChessLmTokenizer {
  final Map<String, int> vocab;
  final Map<String, int> ranks;
  final bool byteFallback;
  final int? unkId;
  final List<int> prefix;

  _SentencePieceBpe(Map<String, dynamic> j)
      : vocab = ((j['model'] as Map)['vocab'] as Map).cast<String, int>(),
        ranks = _mergeRanks(j),
        byteFallback = (j['model'] as Map)['byte_fallback'] == true,
        unkId = (((j['model'] as Map)['vocab'] as Map)
            [(j['model'] as Map)['unk_token']]) as int?,
        prefix = _templatePrefix(j);

  @override
  List<int> encode(String text, {bool addSpecial = true}) {
    final normalized = '▁${text.replaceAll(' ', '▁')}';
    final symbols = _bpe(
        [for (final r in normalized.runes) String.fromCharCode(r)], ranks);
    final ids = <int>[if (addSpecial) ...prefix];
    for (final s in symbols) {
      final id = vocab[s];
      if (id != null) {
        ids.add(id);
      } else if (byteFallback) {
        for (final b in utf8.encode(s)) {
          final hex = b.toRadixString(16).toUpperCase().padLeft(2, '0');
          final bid = vocab['<0x$hex>'];
          if (bid != null) ids.add(bid);
        }
      } else if (unkId != null) {
        ids.add(unkId!);
      }
    }
    return ids;
  }
}

/// One token per word (`Whitespace` pre-tokenizer splits `\w+|[^\w\s]+`).
class _WordLevelTokenizer implements ChessLmTokenizer {
  final Map<String, int> vocab;
  final int? unkId;
  static final _split = RegExp(r'\w+|[^\w\s]+');

  _WordLevelTokenizer(Map<String, dynamic> j)
      : vocab = ((j['model'] as Map)['vocab'] as Map).cast<String, int>(),
        unkId = (((j['model'] as Map)['vocab'] as Map)
            [(j['model'] as Map)['unk_token']]) as int?;

  @override
  List<int> encode(String text, {bool addSpecial = true}) => [
        for (final m in _split.allMatches(text))
          if (vocab[m.group(0)] case final id?) id else if (unkId != null) unkId!
      ];
}
