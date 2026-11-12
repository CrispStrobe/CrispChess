import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/drill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('second back-rank drill solution is legal checkmate', () {
    final drill = builtInDrills.singleWhere((d) => d.id == 'back_rank_mate');
    final step = drill.steps[1];
    final board = chess.Chess.fromFEN(step.fen);
    expect(board.move({'from': step.correctMove.substring(0, 2),
      'to': step.correctMove.substring(2, 4)}), isTrue);
    expect(board.in_checkmate, isTrue);
  });
}
