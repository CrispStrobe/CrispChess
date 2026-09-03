import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/preferences_service.dart';

/// Game History — browse and filter past games stored as PGN.
class GameHistoryScreen extends StatefulWidget {
  const GameHistoryScreen({super.key});

  @override
  State<GameHistoryScreen> createState() => _GameHistoryScreenState();
}

class _GameHistoryScreenState extends State<GameHistoryScreen> {
  final _prefs = PreferencesService();
  List<String> _games = [];
  String _resultFilter = 'all'; // 'all', '1-0', '0-1', '1/2-1/2'
  bool _favoritesOnly = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _prefs.init();
    if (mounted) {
      setState(() {
        _games = _prefs.gameHistory;
        _loaded = true;
      });
    }
  }

  List<String> get _filteredGames {
    var list = _games;
    if (_favoritesOnly) {
      list = list.where((pgn) => _prefs.isFavorite(pgn)).toList();
    }
    if (_resultFilter != 'all') {
      list = list.where((pgn) => pgn.contains('[Result "$_resultFilter"]')).toList();
    }
    return list;
  }

  String _extractHeader(String pgn, String header) {
    final regex = RegExp('\\[$header "([^"]*)"\\]');
    final match = regex.firstMatch(pgn);
    return match?.group(1) ?? '';
  }

  String _gameLabel(String pgn) {
    final white = _extractHeader(pgn, 'White');
    final black = _extractHeader(pgn, 'Black');
    final result = _extractHeader(pgn, 'Result');
    if (white.isEmpty && black.isEmpty) {
      return result.isEmpty ? 'Game' : result;
    }
    return '$white vs $black${result.isNotEmpty ? '  $result' : ''}';
  }

  String _gameSubtitle(String pgn) {
    final date = _extractHeader(pgn, 'Date');
    final event = _extractHeader(pgn, 'Event');
    final eco = _extractHeader(pgn, 'ECO');
    final parts = <String>[];
    if (date.isNotEmpty && date != '?') parts.add(date);
    if (event.isNotEmpty && event != '?') parts.add(event);
    if (eco.isNotEmpty && eco != '?') parts.add(eco);
    return parts.join(' · ');
  }

  IconData _resultIcon(String pgn) {
    final result = _extractHeader(pgn, 'Result');
    return switch (result) {
      '1-0' => Icons.arrow_upward,
      '0-1' => Icons.arrow_downward,
      '1/2-1/2' => Icons.drag_handle,
      _ => Icons.circle_outlined,
    };
  }

  Color _resultColor(String pgn) {
    final result = _extractHeader(pgn, 'Result');
    return switch (result) {
      '1-0' => Colors.green,
      '0-1' => Colors.red,
      '1/2-1/2' => Colors.orange,
      _ => Colors.grey,
    };
  }

  void _exportAllPgn() {
    final filtered = _filteredGames;
    if (filtered.isEmpty) return;
    final allPgn = filtered.join('\n\n');
    Clipboard.setData(ClipboardData(text: allPgn));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${filtered.length} games copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredGames;

    return Scaffold(
      appBar: AppBar(
        title: Text('Game History (${_games.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, size: 20),
            tooltip: 'Export all as PGN',
            onPressed: filtered.isNotEmpty ? _exportAllPgn : null,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('Favorites', style: TextStyle(fontSize: 11)),
                        selected: _favoritesOnly,
                        onSelected: (v) => setState(() => _favoritesOnly = v),
                        avatar: Icon(_favoritesOnly ? Icons.star : Icons.star_border, size: 16),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      ...['all', '1-0', '0-1', '1/2-1/2'].map((r) {
                        final label = r == 'all' ? 'All' : r;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(label, style: const TextStyle(fontSize: 11)),
                            selected: _resultFilter == r,
                            visualDensity: VisualDensity.compact,
                            onSelected: (sel) {
                              if (sel) setState(() => _resultFilter = r);
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // Game list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(
                                _games.isEmpty ? 'No games yet' : 'No matching games',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final pgn = filtered[index];
                            final isFav = _prefs.isFavorite(pgn);
                            return ListTile(
                              leading: Icon(_resultIcon(pgn), color: _resultColor(pgn), size: 20),
                              title: Text(_gameLabel(pgn), style: const TextStyle(fontSize: 13)),
                              subtitle: Text(_gameSubtitle(pgn), style: const TextStyle(fontSize: 11)),
                              trailing: IconButton(
                                icon: Icon(isFav ? Icons.star : Icons.star_border,
                                    color: isFav ? Colors.amber : Colors.grey, size: 20),
                                onPressed: () => setState(() => _prefs.toggleFavorite(pgn)),
                              ),
                              dense: true,
                              onTap: () {
                                // Return PGN to game screen for loading
                                Navigator.pop(context, pgn);
                              },
                              onLongPress: () {
                                Clipboard.setData(ClipboardData(text: pgn));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('PGN copied')),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
