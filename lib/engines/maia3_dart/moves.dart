/// Maia3 move vocabulary — 4352 UCI strings.
///
/// Indices 0–4095: all 64×64 from/to square pairs.
/// Indices 4096–4351: promotion moves (white-side only, board is mirrored).
///
/// Ported from maia3-js/dist/moves.js (MIT).
library;

const int numFromToMoves = 4096;
const int numPromoMoves = 256;
const int numMoves = 4352;

const _files = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
const _promoSuffixes = ['q', 'r', 'b', 'n'];

List<String>? _allMoves;
Map<String, int>? _moveToIndex;

/// Generate the full move vocabulary (lazy singleton).
List<String> getAllMoves() {
  if (_allMoves != null) return _allMoves!;

  final moves = <String>[];

  // 0–4095: from/to pairs (rank-outer, file-inner, a1=0)
  for (int fromRank = 0; fromRank < 8; fromRank++) {
    for (int fromFile = 0; fromFile < 8; fromFile++) {
      for (int toRank = 0; toRank < 8; toRank++) {
        for (int toFile = 0; toFile < 8; toFile++) {
          final from = '${_files[fromFile]}${fromRank + 1}';
          final to = '${_files[toFile]}${toRank + 1}';
          moves.add('$from$to');
        }
      }
    }
  }

  // 4096–4351: promotions (white side: X7→Y8, piece in [q,r,b,n])
  for (int fromFile = 0; fromFile < 8; fromFile++) {
    for (int toFile = 0; toFile < 8; toFile++) {
      for (final piece in _promoSuffixes) {
        final from = '${_files[fromFile]}7';
        final to = '${_files[toFile]}8';
        moves.add('$from$to$piece');
      }
    }
  }

  _allMoves = moves;
  return moves;
}

/// Lookup: UCI string → index.
Map<String, int> getMoveToIndex() {
  if (_moveToIndex != null) return _moveToIndex!;
  final moves = getAllMoves();
  _moveToIndex = {for (int i = 0; i < moves.length; i++) moves[i]: i};
  return _moveToIndex!;
}

/// Convert UCI string to index.
int moveToIndex(String uci) {
  final idx = getMoveToIndex()[uci];
  if (idx == null) throw ArgumentError('Unknown move: $uci');
  return idx;
}

/// Convert index to UCI string.
String indexToMove(int index) {
  final moves = getAllMoves();
  if (index < 0 || index >= moves.length) {
    throw RangeError.range(index, 0, moves.length - 1);
  }
  return moves[index];
}
