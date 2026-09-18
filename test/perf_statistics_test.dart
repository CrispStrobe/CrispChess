import 'package:flutter_test/flutter_test.dart';
import '../tool/perf/statistics.dart';

void main() {
  test('percentiles use nearest rank without mutating samples', () {
    final samples = <num>[4, 1, 3, 2];
    expect(summarizeSamples(samples), {
      'count': 4,
      'min': 1,
      'p50': 2,
      'p95': 4,
      'max': 4,
    });
    expect(samples, [4, 1, 3, 2]);
    expect(() => summarizeSamples([]), throwsArgumentError);
  });
}
