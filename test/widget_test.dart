import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/main.dart';

void main() {
  testWidgets('App builds without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const CrispChessApp());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // App should render without throwing
    expect(tester.takeException(), isNull);
  });
}
