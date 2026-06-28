import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_clock.dart';
import '../chess/board_theme.dart';
import '../chess/game_state.dart' show ChessVariant;
import 'engine_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  final int strengthLevel;
  final int hintDepth;
  final String currentEngine;
  final bool playAsBlack;
  final String maia3Variant;
  final int animationSpeed;
  final String pieceTheme;
  final String hintEngine;
  final TimeControl timeControl;
  final ChessVariant chessVariant;

  const SettingsScreen({
    Key? key,
    required this.strengthLevel,
    required this.hintDepth,
    this.currentEngine = 'Built-in',
    this.playAsBlack = false,
    this.maia3Variant = '5m',
    this.animationSpeed = 2,
    this.pieceTheme = 'chessnut',
    this.hintEngine = 'same',
    this.timeControl = TimeControl.unlimited,
    this.chessVariant = ChessVariant.standard,
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
  String _hintEngine = 'same';
  int _animationSpeed = 2;
  late TimeControl _timeControl;
  late ChessVariant _chessVariant;
  int _customBaseMinutes = 10;
  int _customIncrementSeconds = 0;
  int _engineHashMb = 64;
  int _engineThreads = 1;
  String _boardTheme = 'brown';
  String _notationStyle = 'algebraic';
  bool _blindfold = false;
  String _themeMode = 'system';
  String _language = 'system';
  bool _solidBlackPieces = false;
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
    _pieceTheme = widget.pieceTheme;
    _hintEngine = widget.hintEngine;
    _timeControl = widget.timeControl;
    _chessVariant = widget.chessVariant;
    _loadSavedPrefs();
  }

  Future<void> _loadSavedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('locale') ?? 'system';
    final solid = prefs.getBool('solidBlackPieces') ?? false;
    final customBase = prefs.getInt('customBaseMinutes') ?? 10;
    final customInc = prefs.getInt('customIncrementSeconds') ?? 0;
    final hashMb = prefs.getInt('engineHashMb') ?? 64;
    final threads = prefs.getInt('engineThreads') ?? 1;
    if (mounted) setState(() {
      _language = lang;
      _solidBlackPieces = solid;
      _customBaseMinutes = customBase;
      _customIncrementSeconds = customInc;
      _engineHashMb = hashMb;
      _engineThreads = threads;
      _boardTheme = prefs.getString('boardTheme') ?? 'brown';
      _notationStyle = prefs.getString('notationStyle') ?? 'algebraic';
      _blindfold = prefs.getBool('blindfold') ?? false;
    });
  }

  /// Snap hash slider to powers of 2: 16, 32, 64, 128, 256, 512, 1024, 2048.
  static int _snapHashValue(double v) {
    const snaps = [16, 32, 64, 128, 256, 512, 1024, 2048];
    var closest = snaps[0];
    for (final s in snaps) {
      if ((s - v).abs() < (closest - v).abs()) closest = s;
    }
    return closest;
  }

  void _showCustomTimeDialog() {
    var baseMin = _customBaseMinutes;
    var incSec = _customIncrementSeconds;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Custom Time Control'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Base: '),
                    Expanded(
                      child: Slider(
                        value: baseMin.toDouble(),
                        min: 1,
                        max: 180,
                        divisions: 179,
                        label: '$baseMin min',
                        onChanged: (v) => setDialogState(() => baseMin = v.round()),
                      ),
                    ),
                    SizedBox(width: 40, child: Text('$baseMin m', textAlign: TextAlign.right)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Inc: '),
                    Expanded(
                      child: Slider(
                        value: incSec.toDouble(),
                        min: 0,
                        max: 60,
                        divisions: 60,
                        label: '$incSec sec',
                        onChanged: (v) => setDialogState(() => incSec = v.round()),
                      ),
                    ),
                    SizedBox(width: 40, child: Text('${incSec}s', textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$baseMin+$incSec', style: Theme.of(ctx).textTheme.titleMedium),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _customBaseMinutes = baseMin;
                    _customIncrementSeconds = incSec;
                    _timeControl = TimeControl.custom;
                  });
                },
                child: const Text('OK'),
              ),
            ],
          );
        });
      },
    );
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

    // Lynx — MIT, native binary or WASM on web
    engines.add(_EngineOption(
      name: 'Lynx',
      description: kIsWeb ? 'Classical HCE (WASM)' : 'Classical HCE, downloaded from GitHub',
      elo: '~3350',
      license: 'MIT',
      available: true,
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
      // iOS downloads stockfish.js at runtime and runs it inside WebKit
      // (App Store-sanctioned; no GPL code in the app binary). Desktop/Android
      // use a native binary. See NOTICE.md and StockfishJSBridge.swift.
      engines.add(_EngineOption(
        name: 'Stockfish',
        description: isIOS
            ? 'Optional download (runs in WebKit)'
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
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l?.settings ?? 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Engine selector
          Text(l?.chessEngine ?? 'Chess Engine', style: Theme.of(context).textTheme.titleLarge),
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

          // Custom engines (native only)
          if (!kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.memory, size: 18),
                label: Text(l?.engineManagerSubtitle ?? 'Engine Manager — Add Custom UCI Engines'),
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const EngineManagerScreen()));
                },
              ),
            ),

          // Maia3 variant selector (shown when a Maia engine is selected)
          if (_isMaiaEngine) ...[
            const SizedBox(height: 16),
            Text(l?.maia3Model ?? 'Maia3 Model',
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
            Text(l?.stockfishVersion ?? 'Stockfish Version',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ('sf10', 'Stockfish 10', '~1MB', '~2800 ELO'),
                  ('sf18asm', 'Stockfish 18 (NNUE)', '~10MB', '~3400 ELO'),
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
            Text(l?.maiaWeight ?? 'Maia Weight (ELO level)',
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
          Text(l?.opponentStrength ?? 'Opponent Strength',
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

          // Hints & Analysis
          Text(l?.hintsAndAnalysis ?? 'Hints & Analysis', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l?.analysisDepth('$_hintDepth') ?? 'Analysis Depth: $_hintDepth',
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
                  const Divider(),
                  ListTile(
                    title: Text(l?.hintEngine ?? 'Hint Engine'),
                    subtitle: Text(_hintEngine == 'same'
                        ? (l?.sameAsOpponent ?? 'Same as opponent')
                        : _hintEngine,
                        style: const TextStyle(fontSize: 12)),
                    contentPadding: EdgeInsets.zero,
                    trailing: DropdownButton<String>(
                      value: _hintEngine,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) => setState(() => _hintEngine = v!),
                      items: [
                        DropdownMenuItem(value: 'same', child: Text(l?.sameAsOpponent ?? 'Same as opponent', style: const TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Built-in', child: Text('Built-in', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Maia3', child: Text('Maia3', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Maia3 Dart', child: Text('Maia3 Dart', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Lc0', child: Text('Lc0', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Frozenight', child: Text('Frozenight', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Lynx', child: Text('Lynx', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'Stockfish', child: Text('Stockfish', style: TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                  const Divider(),
                  Text('Hash: $_engineHashMb MB',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _engineHashMb.toDouble(),
                    min: 16,
                    max: 2048,
                    divisions: 7,
                    label: '$_engineHashMb MB',
                    onChanged: (v) => setState(() => _engineHashMb = _snapHashValue(v)),
                  ),
                  Text('Threads: $_engineThreads',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _engineThreads.toDouble(),
                    min: 1,
                    max: 16,
                    divisions: 15,
                    label: '$_engineThreads',
                    onChanged: (v) => setState(() => _engineThreads = v.round()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Game settings
          Text(l?.game ?? 'Game', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l?.playAsBlackSetting ?? 'Play as Black'),
                  subtitle: Text(l?.playAsBlackSubtitle ?? 'Engine makes the first move'),
                  value: _playAsBlack,
                  onChanged: (value) =>
                      setState(() => _playAsBlack = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.timeControl ?? 'Time Control'),
                  trailing: DropdownButton<TimeControl>(
                    value: _timeControl,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value == TimeControl.custom) {
                        _showCustomTimeDialog();
                      } else {
                        setState(() => _timeControl = value!);
                      }
                    },
                    items: TimeControl.values.map((tc) {
                      final label = tc == TimeControl.custom
                          ? (_timeControl == TimeControl.custom
                              ? 'Custom ${_customBaseMinutes}+$_customIncrementSeconds'
                              : l?.customTimeControl ?? 'Custom...')
                          : tc.label;
                      return DropdownMenuItem(
                        value: tc,
                        child: Text(label, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.gameMode ?? 'Game Mode'),
                  trailing: DropdownButton<ChessVariant>(
                    value: _chessVariant,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) =>
                        setState(() => _chessVariant = value!),
                    items: ChessVariant.values.map((v) {
                      final label = switch (v) {
                        ChessVariant.standard => l?.standard ?? 'Standard',
                        ChessVariant.chess960 => 'Chess960',
                        ChessVariant.kingOfTheHill => l?.kingOfTheHill ?? 'King of the Hill',
                        ChessVariant.threeCheck => l?.threeCheck ?? 'Three-Check',
                      };
                      return DropdownMenuItem(
                        value: v,
                        child: Text(label, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.showValidMoves ?? 'Show Valid Moves'),
                  subtitle:
                      Text(l?.showValidMovesSubtitle ?? 'Highlight legal moves when selecting a piece'),
                  value: _showValidMoves,
                  onChanged: (value) =>
                      setState(() => _showValidMoves = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.allowUndo ?? 'Allow Undo'),
                  subtitle: Text(l?.allowUndoSubtitle ?? 'Disable for discipline mode'),
                  value: _allowUndo,
                  onChanged: (value) =>
                      setState(() => _allowUndo = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.blindfoldMode ?? 'Blindfold Mode'),
                  subtitle: Text(l?.blindfoldModeSubtitle ?? 'Hide pieces — play by memory'),
                  value: _blindfold,
                  onChanged: (value) =>
                      setState(() => _blindfold = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.solidBlackPieces ?? 'Solid Black Pieces'),
                  subtitle: Text(l?.solidBlackPiecesSubtitle ?? 'Render black pieces as solid black instead of grey gradient'),
                  value: _solidBlackPieces,
                  onChanged: (value) =>
                      setState(() => _solidBlackPieces = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.animationSpeed ?? 'Animation Speed'),
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
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.notationStyleLabel ?? 'Notation'),
                  trailing: DropdownButton<String>(
                    value: _notationStyle,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) => setState(() => _notationStyle = v!),
                    items: const [
                      DropdownMenuItem(value: 'algebraic', child: Text('Nf3 (Algebraic)', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'figurine', child: Text('\u2658f3 (Figurine)', style: TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Board color theme
          Text(l?.boardColorThemeLabel ?? 'Board Color', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: boardColorThemes.map((t) {
                  final isSelected = t.id == _boardTheme;
                  return GestureDetector(
                    onTap: () => setState(() => _boardTheme = t.id),
                    child: Container(
                      width: 64,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: Container(color: t.lightSquare)),
                                  Expanded(child: Container(color: t.darkSquare)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: Container(color: t.darkSquare)),
                                  Expanded(child: Container(color: t.lightSquare)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Piece theme
          Text(l?.pieceStyle ?? 'Piece Style', style: Theme.of(context).textTheme.titleLarge),
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
                      Text(l?.aboutCrispChess ?? 'About CrispChess',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MIT licensed chess app with pluggable engines.\n'
                    'Built-in: Pure Dart alpha-beta engine.\n'
                    'Maia3 Dart: Neural net, human-like play (MIT).\n'
                    'Frozenight: Rust NNUE engine (MIT/Apache-2.0).\n'
                    'Lynx: C# classical HCE engine (MIT).\n'
                    'Stockfish/Lc0: GPL-3.0, downloaded separately.',
                    style: TextStyle(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          // Theme
          Text(l?.theme ?? 'Theme', style: Theme.of(context).textTheme.titleLarge),
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

          // Language
          const SizedBox(height: 24),
          Text(l?.language ?? 'Language', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (value, label) in [
                  ('system', l?.systemDefault ?? 'System Default'),
                  ('en', 'English'),
                  ('de', 'Deutsch'),
                ])
                  RadioListTile<String>(
                    value: value,
                    groupValue: _language,
                    onChanged: (v) => setState(() => _language = v!),
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    dense: true,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: Text(l?.resetToDefaults ?? 'Reset to defaults'),
              onPressed: () {
                setState(() {
                  _strengthLevel = 10;
                  _hintDepth = 15;
                  _selectedEngine = 'Built-in';
                  _maia3Variant = '5m';
                  _animationSpeed = 2;
                  _timeControl = TimeControl.unlimited;
                  _chessVariant = ChessVariant.standard;
                  _engineHashMb = 64;
                  _engineThreads = 1;
                  _boardTheme = 'brown';
                  _notationStyle = 'algebraic';
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
            'hintEngine': _hintEngine,
            'playAsBlack': _playAsBlack,
            'pieceTheme': _pieceTheme,
            'engine': _selectedEngine,
            'maia3Variant': _maia3Variant,
            'timeControl': _timeControl,
            'chessVariant': _chessVariant,
            'customBaseMinutes': _customBaseMinutes,
            'customIncrementSeconds': _customIncrementSeconds,
            'engineHashMb': _engineHashMb,
            'engineThreads': _engineThreads,
            'boardTheme': _boardTheme,
            'notationStyle': _notationStyle,
            'blindfold': _blindfold,
            'themeMode': _themeMode,
            'language': _language,
            'solidBlackPieces': _solidBlackPieces,
          });
        },
        icon: const Icon(Icons.check),
        label: Text(l?.save ?? 'Save'),
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
