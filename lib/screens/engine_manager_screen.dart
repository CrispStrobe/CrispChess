import 'dart:io';
import 'package:flutter/material.dart';
import '../engines/generic_uci_engine.dart';
import '../engines/uci_option.dart';
import '../services/engine_profile_store.dart';

/// Screen for managing user-added UCI engine profiles.
///
/// Allows adding engines by path, configuring UCI options,
/// and removing engines. Only available on desktop/mobile (not web).
class EngineManagerScreen extends StatefulWidget {
  const EngineManagerScreen({super.key});

  @override
  State<EngineManagerScreen> createState() => _EngineManagerScreenState();
}

class _EngineManagerScreenState extends State<EngineManagerScreen> {
  final _store = EngineProfileStore();
  List<EngineProfile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    await _store.init();
    setState(() {
      _profiles = _store.profiles;
      _loading = false;
    });
  }

  Future<void> _addEngine() async {
    final controller = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<EngineProfile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add UCI Engine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Engine binary path',
                hintText: '/usr/local/bin/stockfish',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
                hintText: 'Leave blank to auto-detect',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isEmpty) return;
              Navigator.pop(ctx, EngineProfile(
                name: nameController.text.trim(),
                path: path,
              ));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null) return;

    // Verify the binary exists
    if (!await File(result.path).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File not found: ${result.path}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Probe the engine to detect its name and options
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Probing engine...')),
      );
    }

    final engine = GenericUciEngine(result);
    try {
      await engine.initialize();
      // Use detected name if user didn't provide one
      if (result.name.isEmpty) {
        result.name = engine.name;
      }
      engine.dispose();

      await _store.add(result);
      await _loadProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added: ${result.name}')),
        );
      }
    } catch (e) {
      engine.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Engine failed to initialize: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _configureEngine(int index) async {
    final profile = _profiles[index];
    final engine = GenericUciEngine(profile);

    // Show loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading engine options...'), duration: Duration(seconds: 1)),
      );
    }

    try {
      await engine.initialize();
      if (!mounted) { engine.dispose(); return; }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _UciOptionsScreen(
            engine: engine,
            profile: profile,
            onSave: (overrides) async {
              profile.optionOverrides.clear();
              profile.optionOverrides.addAll(overrides);
              await _store.update(index, profile);
              await _loadProfiles();
            },
          ),
        ),
      );

      engine.dispose();
    } catch (e) {
      engine.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load engine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeEngine(int index) async {
    final profile = _profiles[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Engine?'),
        content: Text('Remove "${profile.name}" from your engine list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );

    if (confirmed == true) {
      await _store.remove(index);
      await _loadProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Engine Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.memory, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('No custom engines added'),
                      const SizedBox(height: 8),
                      Text(
                        'Add any UCI-compatible chess engine\nby providing the path to its binary.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _profiles.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.memory),
                        title: Text(profile.name),
                        subtitle: Text(
                          profile.path,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.settings, size: 20),
                              tooltip: 'Configure',
                              onPressed: () => _configureEngine(index),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, size: 20, color: Colors.red.shade300),
                              tooltip: 'Remove',
                              onPressed: () => _removeEngine(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEngine,
        icon: const Icon(Icons.add),
        label: const Text('Add Engine'),
      ),
    );
  }
}

/// Screen that displays auto-generated UCI option controls for an engine.
class _UciOptionsScreen extends StatefulWidget {
  final GenericUciEngine engine;
  final EngineProfile profile;
  final Future<void> Function(Map<String, String> overrides) onSave;

  const _UciOptionsScreen({
    required this.engine,
    required this.profile,
    required this.onSave,
  });

  @override
  State<_UciOptionsScreen> createState() => _UciOptionsScreenState();
}

class _UciOptionsScreenState extends State<_UciOptionsScreen> {
  late Map<String, String> _overrides;

  @override
  void initState() {
    super.initState();
    _overrides = Map.of(widget.profile.optionOverrides);
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.engine.options;
    // Filter out internal/debug options that most users don't need
    final userOptions = options.where((o) =>
      o.name != 'UCI_Chess960' &&
      o.name != 'UCI_ShowWDL' &&
      o.name != 'Debug Log File'
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.engine.name),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _overrides.clear());
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: userOptions.isEmpty
          ? const Center(child: Text('No configurable options'))
          : ListView.builder(
              itemCount: userOptions.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final opt = userOptions[index];
                return _buildOptionWidget(opt);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await widget.onSave(_overrides);
          if (mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.save),
        label: const Text('Save'),
      ),
    );
  }

  Widget _buildOptionWidget(UciOption opt) {
    final currentValue = _overrides[opt.name] ?? opt.value ?? opt.defaultValue ?? '';

    switch (opt.type) {
      case UciOptionType.check:
        return SwitchListTile(
          title: Text(opt.name),
          value: currentValue.toLowerCase() == 'true',
          onChanged: (val) {
            setState(() => _overrides[opt.name] = val.toString());
          },
        );

      case UciOptionType.spin:
        final intVal = int.tryParse(currentValue) ?? opt.min ?? 0;
        final min = opt.min ?? 0;
        final max = opt.max ?? 100;
        // Use slider for reasonable ranges, text field for large ranges
        if (max - min <= 100) {
          return ListTile(
            title: Text('${opt.name}: $intVal'),
            subtitle: Slider(
              value: intVal.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min > 0 ? max - min : 1,
              label: intVal.toString(),
              onChanged: (val) {
                setState(() => _overrides[opt.name] = val.round().toString());
              },
            ),
          );
        }
        // Large range — show text field
        return ListTile(
          title: Text(opt.name),
          subtitle: Text('Range: $min – $max', style: const TextStyle(fontSize: 11)),
          trailing: SizedBox(
            width: 80,
            child: TextField(
              controller: TextEditingController(text: intVal.toString()),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                final parsed = int.tryParse(val);
                if (parsed != null) {
                  setState(() => _overrides[opt.name] = parsed.clamp(min, max).toString());
                }
              },
            ),
          ),
        );

      case UciOptionType.combo:
        return ListTile(
          title: Text(opt.name),
          trailing: DropdownButton<String>(
            value: currentValue.isEmpty ? null : currentValue,
            underline: const SizedBox.shrink(),
            onChanged: (val) {
              if (val != null) setState(() => _overrides[opt.name] = val);
            },
            items: (opt.comboValues ?? []).map((v) {
              return DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13)));
            }).toList(),
          ),
        );

      case UciOptionType.string:
        return ListTile(
          title: Text(opt.name),
          trailing: SizedBox(
            width: 200,
            child: TextField(
              controller: TextEditingController(text: currentValue),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                setState(() => _overrides[opt.name] = val);
              },
            ),
          ),
        );

      case UciOptionType.button:
        return ListTile(
          title: Text(opt.name),
          trailing: OutlinedButton(
            onPressed: () => widget.engine.pressButton(opt.name),
            child: const Text('Run'),
          ),
        );
    }
  }
}
