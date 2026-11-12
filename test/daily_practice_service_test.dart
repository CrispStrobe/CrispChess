import 'package:crispchess/services/daily_practice_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('concurrent records preserve unique exercises and counts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = DailyPracticeService(prefs);
    final second = DailyPracticeService(prefs);
    await Future.wait([
      first.record('review', itemId: 'one'),
      second.record('review', itemId: 'one'),
      first.record('review', itemId: 'two'),
      second.record('puzzle'),
      first.record('puzzle'),
    ]);
    expect(first.count('review'), 2);
    expect(second.count('puzzle'), 2);
  });
}
