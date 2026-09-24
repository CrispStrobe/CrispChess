import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/l10n/generated/app_localizations.dart';
import 'package:crispchess/screens/scan_board_screen.dart';

List<String> _squares(String placement) {
  final out = <String>[];
  for (final c in placement.split('')) {
    if (c == '/') continue;
    final n = int.tryParse(c);
    out.addAll(n == null ? [c] : List.filled(n, '.'));
  }
  return out;
}

void main() {
  group('inferCastling', () {
    test('grants every right in the starting position', () {
      expect(
          inferCastling(_squares('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR')),
          'KQkq');
    });

    test('drops a right once king or rook has left home', () {
      // White king on f1, black a8 rook gone.
      expect(inferCastling(_squares('4k2r/8/8/8/8/8/8/R4K1R')), 'k');
    });

    test('says "-" when nothing is left', () {
      expect(inferCastling(_squares('8/8/4k3/8/8/4K3/8/8')), '-');
    });
  });

  testWidgets('shows the picker before any image is chosen', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScanBoardScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Choose image'), findsOneWidget);
    expect(find.text('Use position'), findsNothing);
  });
}
