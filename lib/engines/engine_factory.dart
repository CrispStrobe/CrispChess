import 'chess_engine.dart';
import 'dart_engine.dart';
import 'lc0_engine.dart' if (dart.library.js_interop) 'lc0_web_engine.dart';

// Conditional imports: web gets *_web_engine.dart, native gets the stub/FFI version.
// Both files export the same class names.
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

import 'frozenight_engine.dart'
    if (dart.library.js_interop) 'frozenight_web_engine.dart';

import 'maia3_engine.dart'
    if (dart.library.js_interop) 'maia3_web_engine.dart';

import 'maia3_dart_engine.dart'
    if (dart.library.js_interop) 'maia3_dart_web_engine.dart';

/// Create a [ChessEngine] by name.
///
/// All engines are either MIT-licensed or downloaded separately
/// (GPL engines run via JS runtime / separate process, never linked).
ChessEngine createEngine(String name, {
  int? playerElo,
  String? maia3Variant,
}) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine(); // Downloaded, not linked
    case 'Frozenight':
      return FrozenightEngine(); // MIT/Apache-2.0
    case 'Maia3':
      return Maia3Engine(playerElo: playerElo ?? 1500); // MIT (JS bridge)
    case 'Maia3 Dart':
      return Maia3DartEngine(
        variantId: maia3Variant ?? '5m',
        playerElo: playerElo ?? 1500,
      ); // MIT (pure Dart)
    case 'Lc0':
      return Lc0Engine(variantId: maia3Variant); // GPL-3.0, downloaded separately
    default:
      return DartEngine(); // MIT, built-in
  }
}
