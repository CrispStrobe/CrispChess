import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../chess/pgn_database.dart';

/// Screen for browsing a PGN database (multiple games in one file).
class PgnDatabaseScreen extends StatefulWidget {
  const PgnDatabaseScreen({super.key});

  @override
  State<PgnDatabaseScreen> createState() => _PgnDatabaseScreenState();
}

class _PgnDatabaseScreenState extends State<PgnDatabaseScreen> {
  List<PgnGameEntry>? _allGames;
  List<PgnGameEntry> _filtered = [];
  final _searchController = TextEditingController();
  String? _resultFilter;
  bool _loading = false;

  Future<void> _loadFromClipboard() async {
    setState(() => _loading = true);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No PGN data in clipboard'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final games = parsePgnDatabase(data.text!);
    setState(() {
      _allGames = games;
      _filtered = games;
      _loading = false;
    });

    if (mounted && games.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No games found in PGN'), backgroundColor: Colors.orange),
      );
    }
  }

  void _applyFilter() {
    if (_allGames == null) return;
    setState(() {
      _filtered = filterGames(
        _allGames!,
        player: _searchController.text,
        result: _resultFilter,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_allGames == null
            ? 'PGN Database'
            : '${_filtered.length} / ${_allGames!.length} games'),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Load PGN from clipboard',
            onPressed: _loadFromClipboard,
          ),
        ],
      ),
      body: _allGames == null
          ? Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storage, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text('No database loaded'),
                        const SizedBox(height: 8),
                        Text(
                          'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
            )
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            hintText: 'Search by player...',
                            prefixIcon: Icon(Icons.search, size: 20),
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => _applyFilter(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String?>(
                        value: _resultFilter,
                        hint: const Text('Result', style: TextStyle(fontSize: 12)),
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('All')),
                          DropdownMenuItem(value: '1-0', child: Text('1-0')),
                          DropdownMenuItem(value: '0-1', child: Text('0-1')),
                          DropdownMenuItem(value: '1/2-1/2', child: Text('Draw')),
                        ],
                        onChanged: (v) {
                          _resultFilter = v;
                          _applyFilter();
                        },
                      ),
                    ],
                  ),
                ),
                // Game list
                Expanded(
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final game = _filtered[index];
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: game.result == '1-0'
                              ? Colors.green
                              : game.result == '0-1'
                                  ? Colors.red
                                  : Colors.grey,
                          child: Text('${index + 1}',
                              style: const TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                        title: Text(
                          '${game.white} vs ${game.black}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${game.result} — ${game.event} ${game.date}${game.eco.isNotEmpty ? ' [${game.eco}]' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => Navigator.pop(context, game.pgn),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
