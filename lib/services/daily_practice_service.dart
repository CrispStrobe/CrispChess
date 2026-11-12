import 'package:shared_preferences/shared_preferences.dart';

class DailyPracticeService {
  final SharedPreferences prefs;
  DailyPracticeService(this.prefs);
  String get _day => DateTime.now().toIso8601String().substring(0, 10);
  int count(String activity) => prefs.getInt('practice_${_day}_$activity') ?? 0;
  Future<void> record(String activity, {String? itemId}) async {
    if (itemId != null) {
      final key = 'practice_${_day}_${activity}_ids';
      final ids = prefs.getStringList(key) ?? [];
      if (ids.contains(itemId)) return;
      await prefs.setStringList(key, [...ids, itemId]);
    }
    await prefs.setInt('practice_${_day}_$activity', count(activity) + 1);
  }
}
