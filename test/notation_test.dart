import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/chess/notation.dart';

void main() {
  group('Figurine notation', () {
    test('converts knight moves', () {
      expect(toFigurine('Nf3'), '\u2658f3');
      expect(toFigurine('Nxe5'), '\u2658xe5');
    });

    test('converts bishop moves', () {
      expect(toFigurine('Bc4'), '\u2657c4');
      expect(toFigurine('Bxf7+'), '\u2657xf7+');
    });

    test('converts rook moves', () {
      expect(toFigurine('Rd1'), '\u2656d1');
    });

    test('converts queen moves', () {
      expect(toFigurine('Qh5'), '\u2655h5');
      expect(toFigurine('Qxf7#'), '\u2655xf7#');
    });

    test('converts king moves', () {
      expect(toFigurine('Ke2'), '\u2654e2');
    });

    test('leaves pawn moves unchanged', () {
      expect(toFigurine('e4'), 'e4');
      expect(toFigurine('dxe5'), 'dxe5');
      expect(toFigurine('e8=Q'), 'e8=Q');
    });

    test('leaves castling unchanged', () {
      expect(toFigurine('O-O'), 'O-O');
      expect(toFigurine('O-O-O'), 'O-O-O');
    });

    test('handles empty string', () {
      expect(toFigurine(''), '');
    });
  });

  group('formatNotation', () {
    test('algebraic returns unchanged', () {
      expect(formatNotation('Nf3', NotationStyle.algebraic), 'Nf3');
    });

    test('figurine converts piece letters', () {
      expect(formatNotation('Nf3', NotationStyle.figurine), '\u2658f3');
    });
  });
}
