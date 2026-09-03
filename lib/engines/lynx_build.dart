/// The two Lynx WASM builds the app ships, and what choosing between them costs.
///
/// Same engine, same source — the difference is whether the .NET assemblies
/// were AOT-compiled into the runtime. Measured on the same position, warmed: a
/// depth-8 search takes ~100 ms on [aot] against ~1.3 s on [lite], and at a
/// 300 ms budget [aot] holds every search under 550 ms where [lite] has
/// multi-second outliers.
///
/// Lives in its own file because the settings UI needs it on every platform,
/// while the engine that uses it is behind a conditional import.
library;

enum LynxBuild {
  aot('aot', 'lynx', 'Fast', '~6MB', 'Full speed — recommended'),
  lite('lite', 'lynx-lite', 'Small', '~2MB',
      '10-15x slower, for slow connections');

  final String id;

  /// Directory under `web/` holding this build's `_framework`.
  final String directory;

  final String label;
  final String downloadSize;
  final String description;

  const LynxBuild(
      this.id, this.directory, this.label, this.downloadSize, this.description);

  /// [aot] for anything unrecognised — the id is shared with the other engines'
  /// variant pickers, so it is routinely something else entirely.
  static LynxBuild fromId(String? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => aot);
}
