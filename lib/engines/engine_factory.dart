import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'dart_engine.dart';
import 'maia3_engine.dart';

// Conditional imports for platform-specific engines
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

// Maia3: web uses JS interop, native uses stub
import 'maia3_engine.dart'
    if (dart.library.js_interop) 'maia3_web_engine.dart'
    as maia3_impl;

/// Create a [ChessEngine] by name. Handles platform differences.
ChessEngine createEngine(String name, {int? playerElo}) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine();
    case 'Maia3':
      if (kIsWeb) {
        return maia3_impl.Maia3WebEngine(playerElo: playerElo ?? 1500);
      }
      return Maia3Engine(playerElo: playerElo ?? 1500);
    default:
      return DartEngine();
  }
}
