import 'chess_engine.dart';
import 'dart_engine.dart';

// Conditional imports: web gets *_web_engine.dart, native gets the stub/FFI version.
// Both files export the same class names.
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

import 'frozenight_engine.dart'
    if (dart.library.js_interop) 'frozenight_web_engine.dart';

import 'maia3_engine.dart'
    if (dart.library.js_interop) 'maia3_web_engine.dart';

/// Create a [ChessEngine] by name.
ChessEngine createEngine(String name, {int? playerElo}) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine();
    case 'Frozenight':
      return FrozenightEngine();
    case 'Maia3':
      return Maia3Engine(playerElo: playerElo ?? 1500);
    default:
      return DartEngine();
  }
}
