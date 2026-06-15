import 'package:flutter/material.dart';

/// A board color scheme for the chess board.
class BoardColorTheme {
  final String id;
  final String name;
  final Color lightSquare;
  final Color darkSquare;
  final Color lightLastMove;
  final Color darkLastMove;
  final Color lightCoordinate;
  final Color darkCoordinate;

  const BoardColorTheme({
    required this.id,
    required this.name,
    required this.lightSquare,
    required this.darkSquare,
    required this.lightLastMove,
    required this.darkLastMove,
    required this.lightCoordinate,
    required this.darkCoordinate,
  });
}

/// All available board color themes.
const boardColorThemes = <BoardColorTheme>[
  BoardColorTheme(
    id: 'brown',
    name: 'Classic Brown',
    lightSquare: Color(0xFFF0D9B5),
    darkSquare: Color(0xFFB58863),
    lightLastMove: Color(0xFFE8D0A0),
    darkLastMove: Color(0xFFA87B50),
    lightCoordinate: Color(0xFFB58863),
    darkCoordinate: Color(0xFFF0D9B5),
  ),
  BoardColorTheme(
    id: 'green',
    name: 'Classic Green',
    lightSquare: Color(0xFFEEEED2),
    darkSquare: Color(0xFF769656),
    lightLastMove: Color(0xFFF6F669),
    darkLastMove: Color(0xFFBBCA2B),
    lightCoordinate: Color(0xFF769656),
    darkCoordinate: Color(0xFFEEEED2),
  ),
  BoardColorTheme(
    id: 'blue',
    name: 'Blue',
    lightSquare: Color(0xFFDEE3E6),
    darkSquare: Color(0xFF8CA2AD),
    lightLastMove: Color(0xFFC8D8E0),
    darkLastMove: Color(0xFF7B97A3),
    lightCoordinate: Color(0xFF8CA2AD),
    darkCoordinate: Color(0xFFDEE3E6),
  ),
  BoardColorTheme(
    id: 'gray',
    name: 'Gray',
    lightSquare: Color(0xFFD9D9D9),
    darkSquare: Color(0xFF8B8B8B),
    lightLastMove: Color(0xFFC8C8C8),
    darkLastMove: Color(0xFF7A7A7A),
    lightCoordinate: Color(0xFF8B8B8B),
    darkCoordinate: Color(0xFFD9D9D9),
  ),
  BoardColorTheme(
    id: 'tournament',
    name: 'Tournament',
    lightSquare: Color(0xFFC8E6C9),
    darkSquare: Color(0xFF388E3C),
    lightLastMove: Color(0xFFB5DEB7),
    darkLastMove: Color(0xFF2E7D32),
    lightCoordinate: Color(0xFF388E3C),
    darkCoordinate: Color(0xFFC8E6C9),
  ),
  BoardColorTheme(
    id: 'walnut',
    name: 'Walnut',
    lightSquare: Color(0xFFE0C8A8),
    darkSquare: Color(0xFF8B6B47),
    lightLastMove: Color(0xFFD5BD98),
    darkLastMove: Color(0xFF7E6040),
    lightCoordinate: Color(0xFF8B6B47),
    darkCoordinate: Color(0xFFE0C8A8),
  ),
  BoardColorTheme(
    id: 'ice',
    name: 'Ice',
    lightSquare: Color(0xFFF0F4F8),
    darkSquare: Color(0xFF9BB8D3),
    lightLastMove: Color(0xFFE0ECF4),
    darkLastMove: Color(0xFF8AACC8),
    lightCoordinate: Color(0xFF9BB8D3),
    darkCoordinate: Color(0xFFF0F4F8),
  ),
  BoardColorTheme(
    id: 'midnight',
    name: 'Midnight',
    lightSquare: Color(0xFFC4CCD8),
    darkSquare: Color(0xFF4B6584),
    lightLastMove: Color(0xFFB3BCC9),
    darkLastMove: Color(0xFF3D5775),
    lightCoordinate: Color(0xFF4B6584),
    darkCoordinate: Color(0xFFC4CCD8),
  ),
];

/// Look up a board color theme by ID. Defaults to 'brown'.
BoardColorTheme getBoardTheme(String id) {
  return boardColorThemes.firstWhere(
    (t) => t.id == id,
    orElse: () => boardColorThemes.first,
  );
}
