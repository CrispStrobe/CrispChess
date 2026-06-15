import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/variants.dart';

void main() {
  group('King of the Hill', () {
    test('detects white king on e4', () {
      expect(checkKothWin('8/8/8/8/4K3/8/8/4k3 w - - 0 1'), isTrue);
    });

    test('detects black king on d5', () {
      expect(checkKothWin('8/8/8/3k4/8/8/8/4K3 w - - 0 1'), isTrue);
    });

    test('detects king on d4', () {
      expect(checkKothWin('8/8/8/8/3K4/8/8/4k3 w - - 0 1'), isTrue);
    });

    test('detects king on e5', () {
      expect(checkKothWin('8/8/8/4k3/8/8/8/4K3 w - - 0 1'), isTrue);
    });

    test('returns false for normal position', () {
      expect(checkKothWin('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'), isFalse);
    });

    test('returns false when king is near but not on center', () {
      expect(checkKothWin('8/8/8/8/8/4K3/8/4k3 w - - 0 1'), isFalse);
    });
  });

  group('kothWinner', () {
    test('returns White when white king on center', () {
      expect(kothWinner('8/8/8/8/4K3/8/8/4k3 w - - 0 1'), 'White');
    });

    test('returns Black when black king on center', () {
      expect(kothWinner('8/8/8/3k4/8/8/8/4K3 w - - 0 1'), 'Black');
    });

    test('returns null when no king on center', () {
      expect(kothWinner('8/8/8/8/8/8/8/4K2k w - - 0 1'), isNull);
    });
  });

  group('Three-Check', () {
    test('returns true at exactly 3 white checks', () {
      expect(checkThreeCheckWin(3, 0), isTrue);
    });

    test('returns true at exactly 3 black checks', () {
      expect(checkThreeCheckWin(0, 3), isTrue);
    });

    test('returns true above 3', () {
      expect(checkThreeCheckWin(5, 2), isTrue);
    });

    test('returns false below 3', () {
      expect(checkThreeCheckWin(2, 2), isFalse);
    });

    test('returns false at 0', () {
      expect(checkThreeCheckWin(0, 0), isFalse);
    });
  });
}
