import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../chess/pgn_database.dart';
import '../l10n/generated/app_localizations.dart';

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
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l?.noPgnData ?? 'No PGN data in clipboard'), backgroundColor: Colors.orange),
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
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.noGamesFound ?? 'No games found in PGN'), backgroundColor: Colors.orange),
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

  void _showStats() {
    if (_allGames == null || _allGames!.isEmpty) return;
    final games = _allGames!;

    // Result distribution
    int white = 0, black = 0, draw = 0;
    for (final g in games) {
      if (g.result == '1-0') white++;
      else if (g.result == '0-1') black++;
      else if (g.result == '1/2-1/2') draw++;
    }

    // Most common ECO codes
    final ecoCount = <String, int>{};
    for (final g in games) {
      if (g.eco.isNotEmpty) {
        ecoCount[g.eco] = (ecoCount[g.eco] ?? 0) + 1;
      }
    }
    final topEcos = ecoCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Most active players
    final playerCount = <String, int>{};
    for (final g in games) {
      if (g.white != '?') playerCount[g.white] = (playerCount[g.white] ?? 0) + 1;
      if (g.black != '?') playerCount[g.black] = (playerCount[g.black] ?? 0) + 1;
    }
    final topPlayers = playerCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.databaseStatistics ?? 'Database Statistics'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l?.nGames('${games.length}') ?? '${games.length} games', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(l?.results ?? 'Results', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              _statBar(l?.whiteWins ?? 'White wins', white, games.length, Colors.green),
              _statBar(l?.blackWins ?? 'Black wins', black, games.length, Colors.red),
              _statBar(l?.draws ?? 'Draws', draw, games.length, Colors.grey),
              const SizedBox(height: 12),
              if (topEcos.isNotEmpty) ...[
                Text(l?.topOpenings ?? 'Top Openings (ECO)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                for (final eco in topEcos.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 36, child: Text(eco.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        Expanded(child: LinearProgressIndicator(
                          value: eco.value / games.length,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                        )),
                        const SizedBox(width: 4),
                        Text('${eco.value}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (topPlayers.isNotEmpty) ...[
                Text(l?.mostActivePlayers ?? 'Most Active Players', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                for (final p in topPlayers.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('${p.key}: ${p.value} games', style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l?.close ?? 'Close')),
        ],
      ),
    );
  }

  Widget _statBar(String label, int count, int total, Color color) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 12))),
          Expanded(child: LinearProgressIndicator(
            value: pct,
            minHeight: 10,
            color: color,
            borderRadius: BorderRadius.circular(4),
          )),
          const SizedBox(width: 6),
          Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_allGames == null
            ? (l?.pgnDatabase ?? 'PGN Database')
            : '${_filtered.length} / ${_allGames!.length} ${l?.games ?? 'games'}'),
        actions: [
          if (_allGames != null && _allGames!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.analytics),
              tooltip: l?.databaseStatistics ?? 'Database statistics',
              onPressed: _showStats,
            ),
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
                        Text(l?.noDatabaseLoaded ?? 'No database loaded'),
                        const SizedBox(height: 8),
                        Text(
                          l?.noDatabaseSubtitle ?? 'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.',
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
                          decoration: InputDecoration(
                            hintText: l?.searchByPlayer ?? 'Search by player...',
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
