/// Transposition table entry types.
enum TTFlag { exact, lowerBound, upperBound }

/// A single transposition table entry.
class TTEntry {
  final int hash;
  final int depth;
  final int score;
  final TTFlag flag;
  final String? bestMove;

  TTEntry({
    required this.hash,
    required this.depth,
    required this.score,
    required this.flag,
    this.bestMove,
  });
}

/// Hash-based transposition table for caching search results.
///
/// Uses Zobrist-style hashing via the FEN string hashCode (simplified).
/// Stores search results to avoid re-searching positions already explored
/// at equal or greater depth.
class TranspositionTable {
  final Map<int, TTEntry> _table = {};
  final int maxSize;

  TranspositionTable({this.maxSize = 100000});

  /// Look up a position in the table.
  TTEntry? probe(int hash) => _table[hash];

  /// Store a search result.
  void store({
    required int hash,
    required int depth,
    required int score,
    required TTFlag flag,
    String? bestMove,
  }) {
    // Replace if new entry is deeper or table entry doesn't exist
    final existing = _table[hash];
    if (existing == null || depth >= existing.depth) {
      // Evict oldest entries if table is full
      if (_table.length >= maxSize && !_table.containsKey(hash)) {
        _table.remove(_table.keys.first);
      }
      _table[hash] = TTEntry(
        hash: hash,
        depth: depth,
        score: score,
        flag: flag,
        bestMove: bestMove,
      );
    }
  }

  /// Clear the table (e.g. for a new game).
  void clear() => _table.clear();

  int get size => _table.length;
}
