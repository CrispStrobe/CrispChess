// End-to-end: the real DartEngine (bitboard isolate + game-history plumbing)
// converts a won K+R vs K ending at a shallow depth. Without the history that
// bestMove now feeds through to the search, the engine shuffles and the ending
// draws by the 50-move rule; with it, it mates.
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/engines/dart_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DartEngine converts K+R vs K at depth 6 (needs history plumbing)',
      () async {
    const startFen = '4k3/8/8/8/8/8/8/R3K3 w - - 0 1';
    final engine = DartEngine();
    await engine.initialize();
    addTearDown(engine.dispose);

    final board = chess.Chess.fromFEN(startFen);
    final moves = <String>[];
    var mated = false;

    for (var ply = 0; ply < 100; ply++) {
      if (board.in_checkmate) {
        mated = true;
        break;
      }
      if (board.in_stalemate || board.in_draw) break; // failed to convert

      final position = 'position fen $startFen moves ${moves.join(' ')}';
      // Fixed depth 6, full strength (no weakening randomness), and an explicit
      // per-move budget. Without one, an explicit depth falls back to
      // kFixedDepthTimeCap — five seconds a move, so a hundred plies can run
      // past any test timeout on a loaded machine, and this went red once for
      // exactly that rather than for anything about the endgame. Depth 6 with
      // three pieces on the board finishes far inside 300ms.
      final uci = await engine.bestMove(position,
          depth: 6, moveTime: const Duration(milliseconds: 300), skillLevel: 20);

      board.move({
        'from': uci.substring(0, 2),
        'to': uci.substring(2, 4),
        'promotion': uci.length > 4 ? uci.substring(4, 5) : null,
      });
      moves.add(uci);
    }

    expect(mated, isTrue,
        reason: 'engine did not mate K+R vs K — it shuffled: ${moves.join(' ')}');
    print('mated in ${moves.length} plies: ${moves.join(' ')}');
    // 100 plies x 300ms is 30s of search; the rest is headroom for a busy
    // machine, not for the engine.
  }, timeout: const Timeout(Duration(minutes: 4)));
}
