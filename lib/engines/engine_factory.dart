import 'package:flutter/foundation.dart' show kIsWeb;

import 'chess_engine.dart';
import 'dart_engine.dart';
import 'generic_uci_engine.dart'
    if (dart.library.js_interop) 'generic_uci_engine_web.dart';
import 'lc0_engine.dart' if (dart.library.js_interop) 'lc0_web_engine.dart';

// Conditional imports: web gets *_web_engine.dart, native gets the stub/FFI version.
// Both files export the same class names.
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

import 'frozenight_engine.dart'
    if (dart.library.js_interop) 'frozenight_web_engine.dart';

import 'maia3_dart_engine.dart'; // pure Dart, one implementation for every platform

import 'lynx_engine.dart'
    if (dart.library.js_interop) 'lynx_web_engine.dart';

/// Create a [ChessEngine] by name.
///
/// All engines are either MIT-licensed or downloaded separately
/// (GPL engines run via JS runtime / separate process, never linked).
ChessEngine createEngine(String name, {
  int? playerElo,
  String? maia3Variant,
  int? hashMb,
  int? threads,
  String lc0Backend = 'auto',
}) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine(variantId: maia3Variant); // Downloaded from CDN
    case 'Frozenight':
      return FrozenightEngine(); // MIT/Apache-2.0
    // 'Maia3' is the retired JS-bridge engine; kept as an alias so a stale
    // saved preference still gets a working Maia3. See
    // PreferencesService.migrateEngineName.
    case 'Maia3' || 'Maia3 Dart':
      return Maia3DartEngine(
        variantId: maia3Variant ?? '5m',
        playerElo: playerElo ?? 1500,
      ); // MIT (pure Dart)
    case 'Lc0':
      return Lc0Engine(
        variantId: maia3Variant,
        backend: lc0Backend,
      ); // GPL-3.0, downloaded separately
    case 'Lynx':
      // On web the id picks the WASM build (fast/AOT or small/interpreter);
      // on native it is ignored.
      return LynxEngine(variantId: maia3Variant); // MIT
    default:
      return DartEngine(); // MIT, built-in
  }
}

/// Create a [ChessEngine] from a user-added engine profile.
///
/// Only available on native platforms (not web).
ChessEngine createEngineFromProfile(EngineProfile profile) {
  if (kIsWeb) throw UnsupportedError('Custom engines not available on web');
  return GenericUciEngine(profile);
}
