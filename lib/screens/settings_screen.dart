import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../chess/chess_clock.dart';

class SettingsScreen extends StatefulWidget {
  final int strengthLevel;
  final int hintDepth;
  final String currentEngine;
  final bool playAsBlack;
  final String maia3Variant;
  final int animationSpeed;
  final TimeControl timeControl;

  const SettingsScreen({
    Key? key,
    required this.strengthLevel,
    required this.hintDepth,
    this.currentEngine = 'Built-in',
    this.playAsBlack = false,
    this.maia3Variant = '5m',
    this.animationSpeed = 2,
    this.timeControl = TimeControl.unlimited,
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _strengthLevel;
  late int _hintDepth;
  late String _selectedEngine;
  late String _maia3Variant;
  bool _showValidMoves = true;
  bool _allowUndo = true;
  int _animationSpeed = 2;
  late TimeControl _timeControl;
  String _themeMode = 'system';
  bool _playAsBlack = false;
  String _pieceTheme = 'chessnut';

  static const _pieceThemes = [
    ('chessnut', 'Chessnut', 'MIT'),
    ('rhosgfx', 'Rhosgfx', 'CC0'),
    ('fantasy', 'Fantasy', 'MIT'),
    ('spatial', 'Spatial', 'MIT'),
    ('celtic', 'Celtic', 'MIT'),
    ('kiwen-suwi', 'Kiwen Suwi', 'CC-BY 4.0'),
    ('totoy', 'Totoy', 'CC-BY 4.0'),
    ('papercut', 'Papercut', 'CC-BY 4.0'),
  ];

  static const _maia3Variants = [
    ('5m', 'Maia3 5M', '~25MB', '~1800 ELO'),
    ('23m', 'Maia3 23M', '~92MB', '~2200 ELO'),
    ('79m', 'Maia3 79M', '~313MB', '~2500 ELO'),
  ];

  @override
  void initState() {
    super.initState();
    _strengthLevel = widget.strengthLevel;
    _hintDepth = widget.hintDepth;
    _selectedEngine = widget.currentEngine;
    _playAsBlack = widget.playAsBlack;
    _maia3Variant = widget.maia3Variant;
    _animationSpeed = widget.animationSpeed;
    _timeControl = widget.timeControl;
  }

  bool get _isMaiaEngine =>
      _selectedEngine == 'Maia3' || _selectedEngine == 'Maia3 Dart';
  bool get _isStockfish => _selectedEngine == 'Stockfish';
  bool get _isLc0 => _selectedEngine == 'Lc0';

  List<_EngineOption> get _availableEngines {
    final engines = <_EngineOption>[
      _EngineOption(
        name: 'Built-in',
        description: 'Alpha-beta + TT, pure Dart',
        elo: '~1800',
        license: 'MIT',
        available: true,
      ),
    ];

    // Maia3 JS — bundled maia3-js + ONNX Runtime (web only)
    engines.add(_EngineOption(
      name: 'Maia3',
      description: 'Neural net — human-like play (JS bridge)',
      elo: '~1500',
      license: 'MIT',
      available: kIsWeb,
    ));

    // Maia3 Dart — pure Dart port, works everywhere
    engines.add(_EngineOption(
      name: 'Maia3 Dart',
      description: 'Neural net — human-like play (pure Dart + ONNX)',
      elo: '~1500–2500',
      license: 'MIT',
      available: true,
      hasVariants: true,
    ));

    // Frozenight — MIT, available on all platforms
    engines.add(_EngineOption(
      name: 'Frozenight',
      description: kIsWeb
          ? 'NNUE engine (Rust→WASM)'
          : 'NNUE engine (Rust FFI — needs native lib)',
      elo: '~3226',
      license: 'MIT/Apache-2.0',
      available: true, // Web WASM + native FFI (if lib present)
    ));

    // Stockfish — downloaded at runtime, never linked into app
    if (kIsWeb) {
      engines.add(_EngineOption(
        name: 'Stockfish',
        description: 'Optional download (Web Worker)',
        elo: '~3200',
        license: 'GPL-3.0',
        available: true,
        gplNotice: true,
      ));
    } else {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      engines.add(_EngineOption(
        name: 'Stockfish',
        description: isIOS
            ? 'Optional download (JavaScriptCore)'
            : 'Optional — install stockfish separately',
        elo: isIOS ? '~3200' : '~3600',
        license: 'GPL-3.0',
        available: true,
        gplNotice: true,
      ));
    }

    // Lc0 — downloaded at runtime, GPL-3.0
    engines.add(_EngineOption(
      name: 'Lc0',
      description: kIsWeb
          ? 'MCTS + Maia neural net (ONNX Runtime Web)'
          : 'MCTS + neural net (downloaded separately)',
      elo: '~1100–1900',
      license: 'GPL-3.0',
      available: true, // Web ONNX + native
      gplNotice: true,
    ));

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

  String _getStrengthInfo(int level) {
    switch (_selectedEngine) {
      case 'Built-in':
        return 'ELO ~${800 + level * 80}  ·  Depth ${3 + level}';
      case 'Maia3' || 'Maia3 Dart':
        final elo = 800 + (level * 60);
        return 'Target ELO ~$elo (model adapts to play at this level)';
      case 'Lc0':
        return 'MCTS nodes: ${50 + level * level * 2} (more = stronger)';
      case 'Stockfish':
        return 'Skill Level $level  ·  Depth ${5 + level ~/ 4}';
      case 'Frozenight':
        return 'Depth ${2 + level ~/ 2} (search time ~${level}s)';
      default:
        return 'Level $level';
    }
  }

  static String _animationSpeedLabel(int speed) {
    switch (speed) {
      case 0: return 'Instant';
      case 1: return 'Fast';
      case 2: return 'Normal';
      case 3: return 'Slow';
      default: return 'Normal';
    }
  }

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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${engine.description} (${engine.license})'
                        '${engine.available ? '' : ' — not available'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (engine.gplNotice)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'GPL-3.0 engine — downloaded separately, '
                            'not compiled into this app.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Maia3 variant selector (shown when a Maia engine is selected)
          if (_isMaiaEngine) ...[
            const SizedBox(height: 16),
            Text('Maia3 Model',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _maia3Variants.map((v) {
                  final (id, name, size, elo) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant,
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $elo',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          // Stockfish version selector
          if (_isStockfish && kIsWeb) ...[
            const SizedBox(height: 16),
            Text('Stockfish Version',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ('sf10', 'Stockfish 10', '~1MB', '~2800 ELO'),
                  ('sf18lite', 'Stockfish 18 Lite (NNUE)', '~7MB', '~3400 ELO'),
                ].map((v) {
                  final (id, name, size, elo) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant, // reuse variant field
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $elo',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          // Lc0 Maia weight selector
          if (_isLc0) ...[
            const SizedBox(height: 16),
            Text('Maia Weight (ELO level)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ('1100', 'Maia 1100', '~3.5MB', 'Beginner'),
                  ('1300', 'Maia 1300', '~3.5MB', 'Casual'),
                  ('1500', 'Maia 1500', '~3.5MB', 'Intermediate'),
                  ('1700', 'Maia 1700', '~3.5MB', 'Advanced'),
                  ('1900', 'Maia 1900', '~3.5MB', 'Expert'),
                ].map((v) {
                  final (id, name, size, level) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant, // reuse variant field
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $level',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

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
                    _getStrengthInfo(_strengthLevel),
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

          // Game settings
          Text('Game', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Play as Black'),
                  subtitle: const Text('Engine makes the first move'),
                  value: _playAsBlack,
                  onChanged: (value) =>
                      setState(() => _playAsBlack = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Time Control'),
                  trailing: DropdownButton<TimeControl>(
                    value: _timeControl,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) =>
                        setState(() => _timeControl = value!),
                    items: TimeControl.values.map((tc) {
                      return DropdownMenuItem(
                        value: tc,
                        child: Text(tc.label, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
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
                  title: const Text('Allow Undo'),
                  subtitle: const Text('Disable for discipline mode'),
                  value: _allowUndo,
                  onChanged: (value) =>
                      setState(() => _allowUndo = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Animation Speed'),
                  subtitle: Slider(
                    value: _animationSpeed.toDouble(),
                    min: 0,
                    max: 3,
                    divisions: 3,
                    label: _animationSpeedLabel(_animationSpeed),
                    onChanged: (value) =>
                        setState(() => _animationSpeed = value.round()),
                  ),
                  trailing: Text(
                    _animationSpeedLabel(_animationSpeed),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Piece theme
          Text('Piece Style', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: _pieceThemes.map((t) {
                final (id, name, license) = t;
                return RadioListTile<String>(
                  value: id,
                  groupValue: _pieceTheme,
                  onChanged: (v) => setState(() => _pieceTheme = v!),
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(license, style: const TextStyle(fontSize: 11)),
                  dense: true,
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Theme.of(context).colorScheme.onSurface),
                      const SizedBox(width: 8),
                      const Text('About CrispChess',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MIT licensed chess app with pluggable engines.\n'
                    'Built-in: Pure Dart alpha-beta engine.\n'
                    'Maia3 Dart: Neural net, human-like play (MIT).\n'
                    'Frozenight: Rust NNUE engine (MIT/Apache-2.0).\n'
                    'Stockfish/Lc0: GPL-3.0, downloaded separately.',
                    style: TextStyle(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          // Theme
          Text('Theme', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (value, label, icon) in [
                  ('system', 'System', Icons.brightness_auto),
                  ('light', 'Light', Icons.light_mode),
                  ('dark', 'Dark (AMOLED)', Icons.dark_mode),
                ])
                  RadioListTile<String>(
                    value: value,
                    groupValue: _themeMode,
                    onChanged: (v) => setState(() => _themeMode = v!),
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    secondary: Icon(icon, size: 20),
                    dense: true,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Reset to defaults'),
              onPressed: () {
                setState(() {
                  _strengthLevel = 10;
                  _hintDepth = 15;
                  _selectedEngine = 'Built-in';
                  _maia3Variant = '5m';
                  _animationSpeed = 2;
                  _timeControl = TimeControl.unlimited;
                  _showValidMoves = true;
                  _playAsBlack = false;
                  _pieceTheme = 'chessnut';
                });
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context, {
            'strengthLevel': _strengthLevel,
            'hintDepth': _hintDepth,
            'showValidMoves': _showValidMoves,
            'allowUndo': _allowUndo,
            'animationSpeed': _animationSpeed,
            'playAsBlack': _playAsBlack,
            'pieceTheme': _pieceTheme,
            'engine': _selectedEngine,
            'maia3Variant': _maia3Variant,
            'timeControl': _timeControl,
            'themeMode': _themeMode,
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
  final bool gplNotice;
  final bool hasVariants;

  _EngineOption({
    required this.name,
    required this.description,
    required this.elo,
    required this.license,
    required this.available,
    this.gplNotice = false,
    this.hasVariants = false,
  });
}
