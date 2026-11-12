import 'package:flutter/material.dart';
import '../engines/maia3_dart/onnx/model_fetch.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/model_download_registry.dart';

class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});
  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final _registry = ModelDownloadRegistry.instance;
  List<CachedModel> _cached = [];
  Object? _error;
  @override
  void initState() {
    super.initState();
    _registry.addListener(_changed);
    _refresh();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_registry.active.isEmpty) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final cached = await listCachedModels();
      if (mounted)
        setState(() {
          _cached = cached;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _registry.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final total = _cached.fold<int>(0, (n, item) => n + item.bytes);
    return Scaffold(
        appBar: AppBar(title: Text(l.modelManager)),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(formatModelBytes(total),
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text(l.cachedModelsNote),
                  const SizedBox(height: 12),
                  if (_error != null) Text('$_error'),
                  for (final item in _registry.active)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(children: [
                              ListTile(
                                  title: Text(item.name),
                                  subtitle: Text(
                                      '${formatModelBytes(item.received)} / '
                                      '${item.total == null ? '—' : formatModelBytes(item.total!)}'),
                                  trailing: IconButton(
                                      tooltip: l.cancelAction,
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        item.cancel();
                                        setState(() {});
                                      })),
                              LinearProgressIndicator(
                                  value: item.total == null || item.total == 0
                                      ? null
                                      : (item.received / item.total!)
                                          .clamp(0, 1)),
                            ]))),
                  if (_cached.isEmpty && _registry.active.isEmpty)
                    Text(l.noModelDownloads),
                  for (final item in _cached)
                    ListTile(
                        title: Text(item.name),
                        subtitle: Text(formatModelBytes(item.bytes)),
                        trailing: IconButton(
                            tooltip: l.removeDownload,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              try {
                                await removeCachedModel(item.id);
                                await _refresh();
                              } catch (e) {
                                if (mounted) setState(() => _error = e);
                              }
                            })),
                ])));
  }
}
