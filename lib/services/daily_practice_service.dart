import 'package:shared_preferences/shared_preferences.dart';

class DailyPracticeService {
  final SharedPreferences prefs;
  DailyPracticeService(this.prefs);

  // Several screens can record at once. Serialize read-modify-write operations
  // across service instances so counts and deduplicated IDs stay consistent.
  static Future<void> _pending = Future.value();
  String get _day => DateTime.now().toIso8601String().substring(0, 10);
  int count(String activity) => prefs.getInt('practice_${_day}_$activity') ?? 0;

  Future<void> record(String activity, {String? itemId}) {
    final day = _day;
    final write = _pending.then((_) async {
      if (itemId != null) {
        final key = 'practice_${day}_${activity}_ids';
        final ids = prefs.getStringList(key) ?? [];
        if (ids.contains(itemId)) return;
        await prefs.setStringList(key, [...ids, itemId]);
      }
      final key = 'practice_${day}_$activity';
      await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
    });
    // A failed write must not prevent future practice from being recorded.
    _pending = write.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return write;
  }
}
