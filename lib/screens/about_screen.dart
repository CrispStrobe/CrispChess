import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About CrispChess')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.castle, size: 28,
                        color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CrispChess',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 4),
                        Text('Version 1.1.0',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text('Cross-platform chess with pluggable AI engines',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          _section(Icons.business, 'Service Provider', const Text(
            'Christian Stroebele\n'
            'Nikolausstr. 5\n'
            '70190 Stuttgart\n'
            'Germany',
          )),

          _section(Icons.copyright, 'License', const Text(
            'CrispChess is licensed under the MIT License.\n\n'
            'You are free to use, modify, and distribute this software '
            'for any purpose, including commercial use.',
          )),

          _section(Icons.memory, 'Chess Engines', Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _EngineInfo('CrispEngine', '~1800 ELO', 'MIT',
                  'Built-in pure Dart engine. Alpha-beta with transposition table. '
                  'Works on all platforms including web (WASM).'),
              SizedBox(height: 12),
              _EngineInfo('Frozenight', '~2960 ELO', 'MIT / Apache-2.0',
                  'NNUE-based Rust engine by MinusKelvin. '
                  'Available on native platforms via FFI.'),
              SizedBox(height: 12),
              _EngineInfo('Maia3', 'ELO-adaptive', 'MIT',
                  'Neural network that predicts human-like chess moves. '
                  'Trained on millions of real human games. '
                  'Set your ELO and it plays like a human at that level. '
                  '~21MB model downloaded on first use.'),
              SizedBox(height: 12),
              _EngineInfo('Stockfish', '~3600 ELO', 'GPL-3.0',
                  'Optional download — never compiled into this app. '
                  'Runs via Web Worker (web), JavaScriptCore (iOS), '
                  'or separate process (desktop). App stays MIT.'),
            ],
          )),

          _section(Icons.shield_outlined, 'Privacy Policy', const Text(
            'Short version: CrispChess collects nothing.\n\n'
            'This app does not collect, store, or transmit any personal data. '
            'All chess computation runs locally on your device. '
            'No analytics, no tracking, no advertising, no network requests, '
            'no account system, no cookies.\n\n'
            'Game state (board position, move history) exists only in memory '
            'and is lost when you close the app. Nothing is saved to disk.\n\n'
            'The web version (crispchess.vercel.app) is a static site. '
            'Vercel may log standard HTTP access logs (IP, user agent). '
            'CrispChess itself sends no data to any server.\n\n'
            'If we ever add features that involve data storage or network '
            'access, this policy will be updated and any new data collection '
            'will be opt-in.',
          )),

          _section(Icons.gavel, 'Disclaimer', const Text(
            'This software is provided "as is", without warranty of any kind. '
            'The authors are not liable for any damages arising from the use '
            'of this software.',
          )),

          _section(Icons.code, 'Source Code', const Text(
            'github.com/CrispStrobe/CrispChess\n\n'
            'Contributions welcome. Open an issue first for major changes.',
          )),

          _section(Icons.coffee, 'Support', const Text(
            'CrispChess is free and open source. If you enjoy it, '
            'consider buying the developer a coffee:\n\n'
            'buymeacoffee.com/crispstrobe',
          )),

          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Open Source Licenses'),
            onPressed: () {
              showLicensePage(
                context: context,
                applicationName: 'CrispChess',
                applicationVersion: '1.1.0',
                applicationLegalese: 'MIT License — CrispStrobe',
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  static Widget _section(IconData icon, String title, Widget child) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14)),
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EngineInfo extends StatelessWidget {
  final String name, elo, license, description;
  const _EngineInfo(this.name, this.elo, this.license, this.description);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(name, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Chip(
            label: Text(elo, style: const TextStyle(fontSize: 10)),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text(license, style: TextStyle(
              fontSize: 10, color: Colors.grey.shade600)),
        ]),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(fontSize: 12, height: 1.4)),
      ],
    );
  }
}
