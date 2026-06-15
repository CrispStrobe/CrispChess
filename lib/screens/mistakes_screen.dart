import 'dart:convert';
import '../l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import '../services/preferences_service.dart';

/// Screen showing tracked mistakes from past games.
class MistakesScreen extends StatefulWidget {
  const MistakesScreen({super.key});

  @override
  State<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends State<MistakesScreen> {
  final _prefs = PreferencesService();
  List<Map<String, dynamic>> _mistakes = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _prefs.init().then((_) {
      final raw = _prefs.mistakes;
      _mistakes = raw
          .map((s) {
            try {
              return jsonDecode(s) as Map<String, dynamic>;
            } catch (_) {
              return <String, dynamic>{};
            }
          })
          .where((m) => m.isNotEmpty)
          .toList();
      setState(() => _loaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Mistakes (${_mistakes.length})'),
        actions: [
          if (_mistakes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear all',
              onPressed: () {
                _prefs.clearMistakes();
                setState(() => _mistakes.clear());
              },
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _mistakes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 48, color: Colors.green),
                      SizedBox(height: 8),
                      Text('No mistakes tracked yet!'),
                      SizedBox(height: 4),
                      Text('Play games with analysis enabled to track blunders.',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _mistakes.length,
                  itemBuilder: (context, index) {
                    final m = _mistakes[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: Icon(Icons.warning,
                            color: Colors.orange.shade700),
                        title: Text(
                          m['move'] as String? ?? 'Unknown move',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m['better'] != null)
                              Text('Better: ${m['better']}',
                                  style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontSize: 12)),
                            if (m['loss'] != null)
                              Text('Loss: ${m['loss']}',
                                  style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                        trailing: Text(
                          m['date'] as String? ?? '',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
