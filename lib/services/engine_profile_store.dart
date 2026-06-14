/// Persists user-added UCI engine profiles to shared_preferences.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../engines/generic_uci_engine.dart';

class EngineProfileStore {
  static const _key = 'uci_engine_profiles';
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  List<EngineProfile> get profiles {
    final json = _prefs?.getString(_key);
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => EngineProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<EngineProfile> profiles) async {
    await init();
    final json = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _prefs!.setString(_key, json);
  }

  Future<void> add(EngineProfile profile) async {
    final list = profiles;
    list.add(profile);
    await save(list);
  }

  Future<void> remove(int index) async {
    final list = profiles;
    if (index >= 0 && index < list.length) {
      list.removeAt(index);
      await save(list);
    }
  }

  Future<void> update(int index, EngineProfile profile) async {
    final list = profiles;
    if (index >= 0 && index < list.length) {
      list[index] = profile;
      await save(list);
    }
  }
}
