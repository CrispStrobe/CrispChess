/// Maia3 utility functions — softmax, sampling, WDL.
///
/// Ported from maia3-js/dist/utils.js (MIT).
library;

import 'dart:math';
import 'dart:typed_data';

/// Mirror a UCI square string vertically (e.g. "e2" → "e7").
String mirrorSquare(String sq) {
  final file = sq[0];
  final rank = 9 - int.parse(sq[1]);
  return '$file$rank';
}

/// Mirror a UCI move string (e.g. "e2e4" → "e7e5").
String mirrorMove(String uci) {
  final from = mirrorSquare(uci.substring(0, 2));
  final to = mirrorSquare(uci.substring(2, 4));
  final promo = uci.length > 4 ? uci.substring(4) : '';
  return '$from$to$promo';
}

/// Numerically stable softmax with optional mask.
/// Masked entries (mask[i] == 0) get probability 0.
Float32List softmax(Float32List logits, {Uint8List? mask}) {
  final n = logits.length;
  final result = Float32List(n);

  // Find max (only unmasked entries)
  double maxVal = double.negativeInfinity;
  for (int i = 0; i < n; i++) {
    if (mask != null && mask[i] == 0) continue;
    if (logits[i] > maxVal) maxVal = logits[i];
  }
  if (maxVal == double.negativeInfinity) return result; // all masked

  // Compute exp and sum
  double sum = 0;
  for (int i = 0; i < n; i++) {
    if (mask != null && mask[i] == 0) continue;
    final e = exp(logits[i] - maxVal);
    result[i] = e;
    sum += e;
  }

  // Normalize
  if (sum > 0) {
    for (int i = 0; i < n; i++) {
      result[i] /= sum;
    }
  }

  return result;
}

/// Fast softmax for exactly 3 logits (value head).
List<double> softmax3(List<double> logits) {
  final maxVal = logits.reduce(max);
  final exps = logits.map((l) => exp(l - maxVal)).toList();
  final sum = exps.reduce((a, b) => a + b);
  return exps.map((e) => e / sum).toList();
}

/// Win/draw/loss probabilities from value head logits.
/// Value head outputs [loss, draw, win] order.
({double win, double draw, double loss}) wdlFromValueLogits(
    List<double> logits) {
  final probs = softmax3(logits);
  return (win: probs[2], draw: probs[1], loss: probs[0]);
}

/// Scalar win probability from WDL.
double winProbabilityFromWdl(
    ({double win, double draw, double loss}) wdl) {
  return wdl.win + 0.5 * wdl.draw;
}

/// Nucleus (top-p) sampling.
int sampleIndex(Float32List probs, {double topP = 1.0, Random? rng}) {
  rng ??= Random();

  // Build (index, prob) pairs, sort descending
  final indexed = <(int, double)>[];
  for (int i = 0; i < probs.length; i++) {
    if (probs[i] > 0) indexed.add((i, probs[i]));
  }
  indexed.sort((a, b) => b.$2.compareTo(a.$2));

  if (indexed.isEmpty) return 0;

  // Accumulate until cumulative >= topP (always keep at least top-1)
  double cumulative = 0;
  final nucleus = <(int, double)>[];
  for (final entry in indexed) {
    nucleus.add(entry);
    cumulative += entry.$2;
    if (cumulative >= topP && nucleus.length > 1) break;
  }

  // Renormalize
  final nucleusSum = nucleus.fold<double>(0, (s, e) => s + e.$2);
  final r = rng.nextDouble() * nucleusSum;

  double acc = 0;
  for (final entry in nucleus) {
    acc += entry.$2;
    if (acc >= r) return entry.$1;
  }
  return nucleus.last.$1;
}

/// Index of maximum value.
int argmax(Float32List arr) {
  int best = 0;
  double bestVal = arr[0];
  for (int i = 1; i < arr.length; i++) {
    if (arr[i] > bestVal) {
      bestVal = arr[i];
      best = i;
    }
  }
  return best;
}

/// Clamp value to [lo, hi].
double clamp(double x, double lo, double hi) => x < lo ? lo : (x > hi ? hi : x);
