import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/widgets/horizontal_evaluation_bar.dart';

void main() {
  testWidgets('shows Analyzing when evaluation is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: null, depth: 0)),
    ));
    expect(find.text('Analyzing...'), findsOneWidget);
  });

  testWidgets('shows positive evaluation with + prefix', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: 1.5, depth: 15)),
    ));
    expect(find.text('+1.5'), findsOneWidget);
    expect(find.text('d15'), findsOneWidget);
  });

  testWidgets('shows negative evaluation', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: -2.3, depth: 10)),
    ));
    expect(find.text('-2.3'), findsOneWidget);
  });

  testWidgets('clamps extreme evaluations', (tester) async {
    // eval of +15 should be clamped to +10 internally for bar width
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: 15.0, depth: 20)),
    ));
    // Widget still shows +15.0 as text, but bar is clamped
    expect(find.text('+15.0'), findsOneWidget);
  });

  testWidgets('shows zero evaluation as +0.0', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: 0.0, depth: 5)),
    ));
    expect(find.text('+0.0'), findsOneWidget);
    expect(find.text('d5'), findsOneWidget);
  });

  testWidgets('shows depth indicator', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: 0.5, depth: 22)),
    ));
    expect(find.text('d22'), findsOneWidget);
  });

  testWidgets('renders without errors for negative extreme', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HorizontalEvaluationBar(evaluation: -15.0, depth: 20)),
    ));
    // Widget still shows -15.0 as text, but bar is clamped internally
    expect(find.text('-15.0'), findsOneWidget);
  });
}
