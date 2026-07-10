import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _gitHash = String.fromEnvironment('GIT_HASH', defaultValue: 'dev');
  static const _buildDate = String.fromEnvironment('BUILD_DATE', defaultValue: 'local');

  String _version = '…';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
  }

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
                        SelectableText('v$_version ($_gitHash) · $_buildDate',
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
              _EngineInfo('Built-in', '~1800 ELO', 'MIT',
                  'Pure Dart engine. Alpha-beta + TT + quiescence + '
                  'reverse futility pruning + LMR. Works everywhere.'),
              SizedBox(height: 12),
              _EngineInfo('Maia3 / Maia3 Dart', '~1500-2500 ELO', 'AGPL-3.0 (weights)',
                  'Neural network trained on human games. '
                  'ELO-conditioned: plays like a human at your rating. '
                  '3 model sizes (5M/23M/79M). Glue code is MIT; the '
                  'weights\' upstream license is AGPL-3.0 — see '
                  'THIRD_PARTY_LICENSES.md for details.'),
              SizedBox(height: 12),
              _EngineInfo('Lc0', '~1100-1900 ELO', 'GPL-3.0',
                  'MCTS + Maia neural network. AlphaZero-style search. '
                  'Downloaded at runtime, never compiled into app.'),
              SizedBox(height: 12),
              _EngineInfo('Frozenight', '~3226 ELO', 'MIT / Apache-2.0',
                  'NNUE-based Rust engine. Compiled to WASM for web, '
                  'native FFI for desktop/mobile.'),
              SizedBox(height: 12),
              _EngineInfo('Stockfish', '~2800-3400 ELO', 'GPL-3.0',
                  'Downloaded at runtime — never compiled into app. '
                  'Runs as Web Worker or separate process. App stays MIT.'),
            ],
          )),

          _section(Icons.shield_outlined, 'Privacy Policy', const Text(
            'Short version: CrispChess collects nothing about you.\n\n'
            'This app does not collect, store, or transmit any personal data, '
            'and has no analytics, no tracking, no advertising, and no '
            'account system. All chess computation runs locally on your '
            'device.\n\n'
            'The app does make network requests for functional purposes: '
            'downloading engine files (Lc0, Stockfish, Lynx) and neural '
            'network weights on first use of those engines, and querying a '
            'public opening-book/tablebase service from the Opening '
            'Explorer. These requests go to the engines\' hosting servers '
            '(e.g. GitHub Releases) and public chess APIs, and — like any '
            'network request — expose your IP address to those servers as '
            'an unavoidable part of how the internet works. CrispChess '
            'itself does not attach any personal data to these requests, '
            'and downloaded engine files are cached locally so this only '
            'happens once per engine.\n\n'
            'Game state (board position, move history) exists only in '
            'memory and is lost when you close the app. Nothing else is '
            'saved to disk.\n\n'
            'The web version (crispchess.vercel.app) is a static site. '
            'Vercel may log standard HTTP access logs (IP, user agent). '
            'CrispChess itself sends no personal data to any server.\n\n'
            'If we ever add features that involve storing or transmitting '
            'personal data, this policy will be updated and any new data '
            'collection will be opt-in.',
          )),

          _section(Icons.gavel, 'Disclaimer', const Text(
            'This software is provided "as is", without warranty of any kind. '
            'The authors are not liable for any damages arising from the use '
            'of this software.',
          )),

          _section(Icons.code, 'Source Code', Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () {
                  Clipboard.setData(const ClipboardData(
                      text: 'https://github.com/CrispStrobe/CrispChess'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('URL copied to clipboard')),
                  );
                },
                child: Text(
                  'https://github.com/CrispStrobe/CrispChess',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Contributions welcome. Open an issue first for major changes.'),
            ],
          )),

          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined),
            label: const Text('Open Source Licenses'),
            onPressed: () {
              showLicensePage(
                context: context,
                applicationName: 'CrispChess',
                applicationVersion: '$_version ($_gitHash)',
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
