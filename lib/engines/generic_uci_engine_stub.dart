/// Platform-independent EngineProfile model.
/// Separated from generic_uci_engine.dart to avoid dart:io on web.

class EngineProfile {
  String name;
  String path;
  final Map<String, String> optionOverrides;

  EngineProfile({
    required this.name,
    required this.path,
    Map<String, String>? optionOverrides,
  }) : optionOverrides = optionOverrides ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'options': optionOverrides,
  };

  factory EngineProfile.fromJson(Map<String, dynamic> json) => EngineProfile(
    name: json['name'] as String,
    path: json['path'] as String,
    optionOverrides: (json['options'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
  );
}
