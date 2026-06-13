import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:crispchess/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and shows CrispChess', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('CrispChess'), findsOneWidget);
  });
}
