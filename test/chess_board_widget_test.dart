import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/widgets/chess_board.dart';

void main() {
  testWidgets('ChessBoard renders 64 squares', (tester) async {
    final game = ChessGame();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChessBoard(
          board: game.board,
          whiteToMove: game.whiteToMove,
          squareToAlgebraic: game.squareToAlgebraic,
        ),
      ),
    ));
    // There should be 64 GestureDetector widgets (one per square)
    expect(find.byType(GestureDetector), findsNWidgets(64));
  });
}
