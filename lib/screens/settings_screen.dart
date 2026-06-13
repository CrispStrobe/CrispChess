import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final int strengthLevel;
  final int hintDepth;
  final String currentEngine;

  const SettingsScreen({
    Key? key,
    required this.strengthLevel,
    required this.hintDepth,
    this.currentEngine = 'CrispEngine',
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _strengthLevel;
  late int _hintDepth;
  late String _selectedEngine;
  bool _showValidMoves = true;
  bool _animateMoves = true;

  @override
  void initState() {
    super.initState();
    _strengthLevel = widget.strengthLevel;
    _hintDepth = widget.hintDepth;
    _selectedEngine = widget.currentEngine;
  }

  List<_EngineOption> get _availableEngines {
    final engines = <_EngineOption>[
      _EngineOption(
        name: 'CrispEngine',
        description: 'Built-in Dart engine',
        elo: '~1800',
        license: 'MIT',
        available: true,
      ),
    ];

    // Frozenight only on native platforms (can't import dart:ffi on web)
    if (!kIsWeb) {
      engines.add(_EngineOption(
        name: 'Frozenight',
        description: 'NNUE engine (Rust)',
        elo: '~2960',
        license: 'MIT/Apache-2.0',
        available: false, // Will be true when native lib is installed
      ));
    }

    return engines;
  }

  String _getStrengthDescription(int level) {
    if (level <= 3) return 'Beginner';
    if (level <= 6) return 'Novice';
    if (level <= 10) return 'Intermediate';
    if (level <= 14) return 'Advanced';
    if (level <= 17) return 'Expert';
    return 'Master+';
  }

  int _getEstimatedElo(int level) => 800 + (level * 80);
  int _getSearchDepth(int level) => 3 + level;

  Color _getColorForStrength(int level) {
    if (level <= 6) return Colors.green;
    if (level <= 10) return Colors.blue;
    if (level <= 14) return Colors.orange;
    if (level <= 17) return Colors.red;
    return Colors.purple;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Engine selector
          Text('Chess Engine', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _availableEngines.map((engine) {
                final selected = _selectedEngine == engine.name;
                return RadioListTile<String>(
                  value: engine.name,
                  groupValue: _selectedEngine,
                  onChanged: engine.available
                      ? (value) => setState(() => _selectedEngine = value!)
                      : null,
                  title: Row(
                    children: [
                      Text(engine.name,
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.normal)),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(engine.elo,
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  subtitle: Text(
                    '${engine.description} (${engine.license})'
                    '${engine.available ? '' : ' — not installed'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // Strength slider
          Text('Opponent Strength',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level $_strengthLevel',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Chip(
                        label: Text(_getStrengthDescription(_strengthLevel),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        backgroundColor: _getColorForStrength(_strengthLevel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _strengthLevel.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: _strengthLevel.toString(),
                    onChanged: (value) =>
                        setState(() => _strengthLevel = value.round()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'ELO ~${_getEstimatedElo(_strengthLevel)}  ·  Depth ${_getSearchDepth(_strengthLevel)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Hint depth
          Text('Hint Depth', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Analysis Depth: $_hintDepth',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _hintDepth.toDouble(),
                    min: 8,
                    max: 22,
                    divisions: 14,
                    label: _hintDepth.toString(),
                    onChanged: (value) =>
                        setState(() => _hintDepth = value.round()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Visual settings
          Text('Display', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Show Valid Moves'),
                  subtitle:
                      const Text('Highlight legal moves when selecting a piece'),
                  value: _showValidMoves,
                  onChanged: (value) =>
                      setState(() => _showValidMoves = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Animate Moves'),
                  subtitle: const Text('Smooth piece movement animation'),
                  value: _animateMoves,
                  onChanged: (value) =>
                      setState(() => _animateMoves = value),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About
          Card(
            color: Colors.grey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      const Text('About CrispChess',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MIT licensed chess app with pluggable engines.\n'
                    'CrispEngine: Pure Dart, works everywhere including web.\n'
                    'Frozenight: Rust NNUE engine for native platforms.',
                    style: TextStyle(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context, {
            'strengthLevel': _strengthLevel,
            'hintDepth': _hintDepth,
            'showValidMoves': _showValidMoves,
            'animateMoves': _animateMoves,
            'engine': _selectedEngine,
          });
        },
        icon: const Icon(Icons.check),
        label: const Text('Save'),
      ),
    );
  }
}

class _EngineOption {
  final String name;
  final String description;
  final String elo;
  final String license;
  final bool available;

  _EngineOption({
    required this.name,
    required this.description,
    required this.elo,
    required this.license,
    required this.available,
  });
}
