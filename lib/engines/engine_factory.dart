import 'chess_engine.dart';
import 'dart_engine.dart';

// Conditional import: on web, use stockfish_web_engine (Web Worker).
// On native, use stockfish_engine (stub / native FFI).
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

/// Create a [ChessEngine] by name. Handles platform differences.
ChessEngine createEngine(String name) {
  switch (name) {
    case 'Stockfish':
      return StockfishEngine();
    default:
      return DartEngine();
  }
}
