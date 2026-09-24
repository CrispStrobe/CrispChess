/// Scores legal moves under a language model.
///
/// The game text is kept as a KV cache: a new position feeds only the tokens
/// that changed (falling back to the longest common token prefix when the
/// tokenizer merges across the join). Each legal move is then written after
/// the game in the model's format; the moves' token sequences form a trie,
/// and each depth of the trie is one batched call, extending a copy of the
/// cache by one token per row. A move's score is the sum of its tokens'
/// log-probabilities — the constrained decoding the Chess LLM Arena uses,
/// computed exactly instead of sampled.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'kv_model.dart';
import 'prompt.dart';
import 'tokenizer.dart';

class ChessLmScorer {
  final KvLanguageModel model;
  final ChessLmTokenizer tokenizer;
  final ChessLmFormat format;

  /// Positions the model was trained on; older moves are dropped to fit.
  final int contextLength;

  List<int> _ids = const [];
  KvCache? _cache;
  Float32List? _lastLogits;

  ChessLmScorer(this.model, this.tokenizer, this.format,
      {required this.contextLength});

  /// Log-probability of each of [moves] (in the notation [format] uses:
  /// SAN, or UCI for [ChessLmFormat.uci]) after the game [history].
  Future<List<double>> score(List<String> history, List<String> moves) async {
    final (prompt, ids) = _fit(history, moves);
    await _sync(ids);

    // Candidate token sequences and where each departs from the prompt.
    final seqs = <(List<int>, int)>[];
    for (final m in moves) {
      final full = tokenizer.encode(prompt + moveText(format, prompt, m));
      var s = 0;
      while (s < ids.length && s < full.length && full[s] == ids[s]) {
        s++;
      }
      seqs.add((full, s));
    }

    final scores = List<double>.filled(moves.length, double.negativeInfinity);
    final byBase = <int, List<int>>{};
    for (var i = 0; i < seqs.length; i++) {
      byBase.putIfAbsent(seqs[i].$2, () => []).add(i);
    }
    for (final entry in byBase.entries) {
      final base = await _baseAt(entry.key, ids);
      await _scoreTrie(base, [for (final i in entry.value) seqs[i].$1.sublist(entry.key)],
          (k, v) => scores[entry.value[k]] = v);
    }
    return scores;
  }

  /// The prompt, trimmed from the front a whole move pair at a time until it
  /// and the longest candidate fit the context.
  (String, List<int>) _fit(List<String> history, List<String> moves) {
    final longest = moves.fold(0, (a, m) => math.max(a, m.length)) + 4;
    var first = 0;
    while (true) {
      final prompt = renderGame(format, history.sublist(first), firstPly: first);
      final ids = tokenizer.encode(prompt);
      if (ids.length + longest <= contextLength || first + 2 > history.length) {
        return (prompt, ids);
      }
      first += 2;
    }
  }

  /// Brings the cache to exactly [ids], reusing the shared prefix.
  Future<void> _sync(List<int> ids) async {
    var k = 0;
    while (k < _ids.length && k < ids.length && _ids[k] == ids[k]) {
      k++;
    }
    if (k == ids.length && k == _ids.length && _lastLogits != null) return;
    // At least one token must be fed to get the logits after the prompt.
    k = math.min(k, ids.length - 1);
    final past = (_cache == null || k == 0)
        ? KvCache.empty(model.layers, model.kvHeads, model.headDim)
        : _cache!.truncate(k);
    final step = await model.run(Int64List.fromList(ids.sublist(k)), ids.length - k, past);
    _ids = List.of(ids);
    _cache = step.cache;
    _lastLogits = step.logits;
  }

  /// Logits after the first [s] prompt tokens, and the cache holding them.
  Future<(Float32List, KvCache)> _baseAt(int s, List<int> ids) async {
    if (s == ids.length) return (_lastLogits!, _cache!);
    final k = math.max(0, s - 1);
    final past = k == 0
        ? KvCache.empty(model.layers, model.kvHeads, model.headDim)
        : _cache!.truncate(k);
    final step = await model.run(Int64List.fromList(ids.sublist(k, s)), s - k, past);
    return (step.logits, step.cache);
  }

  Future<void> _scoreTrie((Float32List, KvCache) base, List<List<int>> suffixes,
      void Function(int, double) report) async {
    final v = model.vocab;
    // Level by level: `rows` are the trie nodes whose logits are known (row r
    // of `logits`); each suffix walks down, accumulating log-probabilities.
    var logits = base.$1;
    var cache = base.$2;
    var rowOf = List<int>.filled(suffixes.length, 0);
    final total = List<double>.filled(suffixes.length, 0);
    final logZ = <int, double>{};
    double logSoftmax(int row, int token) {
      final z = logZ.putIfAbsent(row, () {
        var mx = double.negativeInfinity;
        for (var i = 0; i < v; i++) {
          mx = math.max(mx, logits[row * v + i]);
        }
        var sum = 0.0;
        for (var i = 0; i < v; i++) {
          sum += math.exp(logits[row * v + i] - mx);
        }
        return mx + math.log(sum);
      });
      return logits[row * v + token] - z;
    }

    for (var depth = 0;; depth++) {
      final next = <String, int>{}; // path key -> new row
      final parents = <int>[], tokens = <int>[];
      for (var i = 0; i < suffixes.length; i++) {
        final s = suffixes[i];
        if (depth >= s.length) continue;
        total[i] += logSoftmax(rowOf[i], s[depth]);
        if (depth + 1 < s.length) {
          final key = '${rowOf[i]}:${s[depth]}';
          rowOf[i] = next.putIfAbsent(key, () {
            parents.add(rowOf[i]);
            tokens.add(s[depth]);
            return parents.length - 1;
          });
        }
      }
      if (parents.isEmpty) break;
      final step = await model.run(
          Int64List.fromList(tokens), 1, cache.gather(parents));
      logits = step.logits;
      cache = step.cache;
      logZ.clear();
    }
    for (var i = 0; i < suffixes.length; i++) {
      report(i, suffixes[i].isEmpty ? double.negativeInfinity : total[i]);
    }
  }
}
