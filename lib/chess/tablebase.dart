/// Syzygy endgame tablebase lookup via Lichess API.
///
/// For positions with ≤7 pieces, returns the exact result (win/draw/loss)
/// and the best move. No local files needed — queries lichess.org API.
///
/// API: https://tablebase.lichess.ovh/standard?fen=...
/// License: Lichess API is free to use.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class TablebaseResult {
  final String category; // "win", "draw", "loss", "unknown"
  final int? dtm; // distance to mate (null if draw)
  final int? dtz; // distance to zeroing move
  final List<TablebaseMove> moves;

  TablebaseResult({
    required this.category,
    this.dtm,
    this.dtz,
    required this.moves,
  });

  bool get isTablebasePosition => category != 'unknown';
  bool get isWin => category == 'win';
  bool get isDraw => category == 'draw' || category == 'cursed-win' || category == 'blessed-loss';
  bool get isLoss => category == 'loss';
}

class TablebaseMove {
  final String uci;
  final String san;
  final String category; // "win", "draw", "loss"
  final int? dtm;

  TablebaseMove({
    required this.uci,
    required this.san,
    required this.category,
    this.dtm,
  });
}

/// Query the Lichess tablebase API.
/// Returns null on error or if position has too many pieces.
Future<TablebaseResult?> queryTablebase(String fen) async {
  // Count pieces
  final placement = fen.split(' ')[0];
  final pieceCount = placement.replaceAll(RegExp(r'[0-9/]'), '').length;
  if (pieceCount > 7) return null; // Too many pieces

  try {
    final encodedFen = Uri.encodeComponent(fen);
    final url = 'https://tablebase.lichess.ovh/standard?fen=$encodedFen';

    if (kIsWeb) {
      // On web, can't use dart:io HttpClient. Return null for now.
      // Could use package:http or dart:html fetch.
      return null;
    }

    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();

    if (response.statusCode != 200) return null;

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final moves = <TablebaseMove>[];
    if (json['moves'] is List) {
      for (final m in json['moves'] as List) {
        moves.add(TablebaseMove(
          uci: m['uci'] as String? ?? '',
          san: m['san'] as String? ?? '',
          category: m['category'] as String? ?? 'unknown',
          dtm: m['dtm'] as int?,
        ));
      }
    }

    return TablebaseResult(
      category: json['category'] as String? ?? 'unknown',
      dtm: json['dtm'] as int?,
      dtz: json['dtz'] as int?,
      moves: moves,
    );
  } catch (e) {
    debugPrint('[Tablebase] Query failed: $e');
    return null;
  }
}
