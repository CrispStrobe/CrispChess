import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/board_theme.dart';

void main() {
  group('BoardColorTheme', () {
    test('has exactly 8 themes', () {
      expect(boardColorThemes.length, 8);
    });

    test('each theme has unique id', () {
      final ids = boardColorThemes.map((t) => t.id).toSet();
      expect(ids.length, boardColorThemes.length);
    });

    test('each theme has different light and dark square colors', () {
      for (final theme in boardColorThemes) {
        expect(theme.lightSquare, isNot(theme.darkSquare),
            reason: '${theme.name} light and dark squares should differ');
      }
    });

    test('getBoardTheme returns correct theme by id', () {
      final green = getBoardTheme('green');
      expect(green.id, 'green');
      expect(green.name, 'Classic Green');
    });

    test('getBoardTheme returns default for unknown id', () {
      final fallback = getBoardTheme('nonexistent');
      expect(fallback.id, 'brown'); // first theme
    });

    test('all themes have names', () {
      for (final theme in boardColorThemes) {
        expect(theme.name, isNotEmpty);
      }
    });

    test('known theme ids exist', () {
      final ids = boardColorThemes.map((t) => t.id).toSet();
      expect(ids, containsAll(['brown', 'green', 'blue', 'gray', 'tournament', 'walnut', 'ice', 'midnight']));
    });
  });
}
