import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'screens/chess_game_screen.dart';

void main() {
  // Logger.root.level = Level.ALL;
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrispChess',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ChessGameScreen(),
    );
  }
}