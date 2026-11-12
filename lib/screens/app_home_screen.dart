import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/model_download_registry.dart';
import 'chess_game_screen.dart';
import 'model_manager_screen.dart';
import 'review_hub_screen.dart';
import 'training_hub_screen.dart';

/// Keeps the board alive while exposing review and training directly.
class AppHomeScreen extends StatefulWidget {
  const AppHomeScreen({super.key});
  @override
  State<AppHomeScreen> createState() => _AppHomeScreenState();
}

class _AppHomeScreenState extends State<AppHomeScreen> {
  int _tab = 0;
  int _visit = 0;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(children: [
        Expanded(
            child: IndexedStack(index: _tab, children: [
          ExcludeFocus(excluding: _tab != 0, child: const ChessGameScreen()),
          if (_tab == 1)
            ReviewHubScreen(key: ValueKey(_visit))
          else
            const SizedBox.shrink(),
          if (_tab == 2)
            TrainingHubScreen(key: ValueKey(_visit))
          else
            const SizedBox.shrink(),
        ])),
        ListenableBuilder(
            listenable: ModelDownloadRegistry.instance,
            builder: (context, _) {
              final active = ModelDownloadRegistry.instance.active;
              if (active.isEmpty) return const SizedBox.shrink();
              final item = active.first;
              return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.download),
                      title: Text(item.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: LinearProgressIndicator(
                          value: item.total == null || item.total == 0
                              ? null
                              : (item.received / item.total!).clamp(0, 1)),
                      trailing: IconButton(
                          tooltip: l.cancelAction,
                          icon: const Icon(Icons.close),
                          onPressed: item.cancel),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ModelManagerScreen()))));
            }),
      ]),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (tab) => setState(() {
                _tab = tab;
                _visit++;
              }),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.sports_esports_outlined),
                label: l.playTab),
            NavigationDestination(
                icon: const Icon(Icons.analytics_outlined), label: l.reviewTab),
            NavigationDestination(
                icon: const Icon(Icons.school_outlined), label: l.trainTab),
          ]),
    );
  }
}
