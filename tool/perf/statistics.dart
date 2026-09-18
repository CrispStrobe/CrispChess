/// Latency sample summaries shared by the perf harnesses.
///
/// Nearest-rank percentiles on a copy, so callers can keep appending raw
/// samples and summarising at the end without the sort reordering their data.
library;

/// [samples] in microseconds or milliseconds — the unit is the caller's.
///
/// Throws [ArgumentError] on an empty list rather than reporting zeros: a
/// harness that measured nothing must not look like a harness that measured
/// something fast.
Map<String, num> summarizeSamples(List<num> samples) {
  if (samples.isEmpty) {
    throw ArgumentError.value(samples, 'samples', 'must not be empty');
  }
  final sorted = List<num>.of(samples)..sort();
  num atRank(double percentile) {
    final rank = (percentile * sorted.length).ceil();
    final index = rank < 1 ? 0 : rank - 1;
    return sorted[index >= sorted.length ? sorted.length - 1 : index];
  }

  return {
    'count': sorted.length,
    'min': sorted.first,
    'p50': atRank(0.50),
    'p95': atRank(0.95),
    'max': sorted.last,
  };
}
