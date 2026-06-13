import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/game_state.dart';

void main() {
  group('GameState', () {
    test('default values are correct', () {
      const state = GameState();
      expect(state.strengthLevel, 10);
      expect(state.hintDepth, 15);
      expect(state.showValidMoves, true);
      expect(state.animateMoves, true);
      expect(state.selectedRow, isNull);
      expect(state.selectedCol, isNull);
      expect(state.validMoves, isEmpty);
      expect(state.statusMessage, 'Your turn (White)');
      expect(state.isThinking, false);
      expect(state.hintMove, isNull);
      expect(state.lastMove, '');
      expect(state.waitingForHint, false);
      expect(state.analysisExpanded, false);
      expect(state.currentBestMove, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      final state = const GameState(
        strengthLevel: 5,
        hintDepth: 20,
        showValidMoves: false,
        selectedRow: 3,
        selectedCol: 4,
        statusMessage: 'Test',
        isThinking: true,
        hintMove: 'e2e4',
        lastMove: 'You: e2e4',
        currentBestMove: 'd7d5',
      );

      final updated = state.copyWith(strengthLevel: 8);

      expect(updated.strengthLevel, 8);
      expect(updated.hintDepth, 20);
      expect(updated.showValidMoves, false);
      expect(updated.selectedRow, 3);
      expect(updated.selectedCol, 4);
      expect(updated.statusMessage, 'Test');
      expect(updated.isThinking, true);
      expect(updated.hintMove, 'e2e4');
      expect(updated.lastMove, 'You: e2e4');
      expect(updated.currentBestMove, 'd7d5');
    });

    test('copyWith updates specified fields', () {
      const state = GameState();

      final updated = state.copyWith(
        strengthLevel: 15,
        hintDepth: 25,
        showValidMoves: false,
        animateMoves: false,
        selectedRow: 2,
        selectedCol: 3,
        validMoves: ['e2e4', 'd2d4'],
        statusMessage: 'Thinking...',
        isThinking: true,
        hintMove: 'e2e4',
        lastMove: 'You: e2e4',
        waitingForHint: true,
        analysisExpanded: true,
        currentBestMove: 'd7d5',
      );

      expect(updated.strengthLevel, 15);
      expect(updated.hintDepth, 25);
      expect(updated.showValidMoves, false);
      expect(updated.animateMoves, false);
      expect(updated.selectedRow, 2);
      expect(updated.selectedCol, 3);
      expect(updated.validMoves, ['e2e4', 'd2d4']);
      expect(updated.statusMessage, 'Thinking...');
      expect(updated.isThinking, true);
      expect(updated.hintMove, 'e2e4');
      expect(updated.lastMove, 'You: e2e4');
      expect(updated.waitingForHint, true);
      expect(updated.analysisExpanded, true);
      expect(updated.currentBestMove, 'd7d5');
    });

    test('copyWith can set nullable fields to null', () {
      final state = const GameState(
        selectedRow: 3,
        selectedCol: 4,
        hintMove: 'e2e4',
        currentBestMove: 'd7d5',
      );

      final updated = state.copyWith(
        selectedRow: null,
        selectedCol: null,
        hintMove: null,
        currentBestMove: null,
      );

      expect(updated.selectedRow, isNull);
      expect(updated.selectedCol, isNull);
      expect(updated.hintMove, isNull);
      expect(updated.currentBestMove, isNull);
    });

    test('copyWith with no arguments returns equivalent state', () {
      final state = const GameState(
        strengthLevel: 5,
        hintDepth: 20,
        showValidMoves: false,
        animateMoves: false,
        selectedRow: 3,
        selectedCol: 4,
        validMoves: ['e2e4'],
        statusMessage: 'Test',
        isThinking: true,
        hintMove: 'e2e4',
        lastMove: 'You: e2e4',
        waitingForHint: true,
        analysisExpanded: true,
        currentBestMove: 'd7d5',
      );

      final copy = state.copyWith();

      expect(copy.strengthLevel, state.strengthLevel);
      expect(copy.hintDepth, state.hintDepth);
      expect(copy.showValidMoves, state.showValidMoves);
      expect(copy.animateMoves, state.animateMoves);
      expect(copy.selectedRow, state.selectedRow);
      expect(copy.selectedCol, state.selectedCol);
      expect(copy.validMoves, state.validMoves);
      expect(copy.statusMessage, state.statusMessage);
      expect(copy.isThinking, state.isThinking);
      expect(copy.hintMove, state.hintMove);
      expect(copy.lastMove, state.lastMove);
      expect(copy.waitingForHint, state.waitingForHint);
      expect(copy.analysisExpanded, state.analysisExpanded);
      expect(copy.currentBestMove, state.currentBestMove);
    });

    test('multiple copyWith chains work correctly', () {
      const state = GameState();

      final result = state
          .copyWith(strengthLevel: 5)
          .copyWith(hintDepth: 25)
          .copyWith(isThinking: true)
          .copyWith(statusMessage: 'Chained');

      expect(result.strengthLevel, 5);
      expect(result.hintDepth, 25);
      expect(result.isThinking, true);
      expect(result.statusMessage, 'Chained');
      // Defaults should be preserved
      expect(result.showValidMoves, true);
      expect(result.animateMoves, true);
      expect(result.lastMove, '');
    });

    test('GameState equality by field comparison', () {
      const state1 = GameState(strengthLevel: 5, hintDepth: 20);
      const state2 = GameState(strengthLevel: 5, hintDepth: 20);
      const state3 = GameState(strengthLevel: 10, hintDepth: 20);

      // Same field values
      expect(state1.strengthLevel, state2.strengthLevel);
      expect(state1.hintDepth, state2.hintDepth);

      // Different field values
      expect(state1.strengthLevel, isNot(state3.strengthLevel));
    });
  });
}
