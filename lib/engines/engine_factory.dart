import 'chess_engine.dart';
import 'dart_engine.dart';
import 'lc0_engine.dart';

// Conditional import: web → stockfish_web_engine, native → stockfish_engine
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

/// Create a [ChessEngine] by name. Handles platform differences.
ChessEngine createEngine(String name) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine();
    case 'Lc0':
      return Lc0Engine();
    default:
      return DartEngine();
  }
}
