import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// AI Coach bottom sheet — send FEN/PGN to an LLM for analysis.
///
/// BYOK (Bring Your Own Key): user provides their own API key.
/// No data is stored server-side. The key is saved locally only.
class AiCoachSheet extends StatefulWidget {
  final String fen;
  final String pgn;
  final String? lastMove;

  const AiCoachSheet({
    super.key,
    required this.fen,
    required this.pgn,
    this.lastMove,
  });

  @override
  State<AiCoachSheet> createState() => _AiCoachSheetState();
}

class _AiCoachSheetState extends State<AiCoachSheet> {
  final _keyController = TextEditingController();
  String? _apiKey;
  String _response = '';
  bool _loading = false;
  bool _showPrivacy = false;
  String _provider = 'anthropic'; // or 'openai'

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('ai_coach_api_key');
    final provider = prefs.getString('ai_coach_provider') ?? 'anthropic';
    if (key != null && key.isNotEmpty) {
      setState(() {
        _apiKey = key;
        _provider = provider;
      });
    }
  }

  Future<void> _saveApiKey(String key, String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_coach_api_key', key);
    await prefs.setString('ai_coach_provider', provider);
    setState(() {
      _apiKey = key;
      _provider = provider;
    });
  }

  Future<void> _clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('ai_coach_api_key');
    setState(() {
      _apiKey = null;
      _keyController.clear();
    });
  }

  String get _prompt {
    final sb = StringBuffer();
    sb.writeln('You are a chess coach. Analyze this position concisely.');
    sb.writeln('');
    sb.writeln('FEN: ${widget.fen}');
    if (widget.pgn.isNotEmpty) {
      sb.writeln('');
      sb.writeln('PGN:');
      sb.writeln(widget.pgn);
    }
    if (widget.lastMove != null) {
      sb.writeln('');
      sb.writeln('Last move played: ${widget.lastMove}');
    }
    sb.writeln('');
    sb.writeln('Provide: 1) Position assessment, 2) Key ideas for both sides, 3) Suggested best move with brief explanation. Keep it under 200 words.');
    return sb.toString();
  }

  Future<void> _askCoach() async {
    if (_apiKey == null || _apiKey!.isEmpty) return;

    setState(() {
      _loading = true;
      _response = '';
    });

    try {
      // Note: actual HTTP call would use dart:io HttpClient or http package.
      // This is the request structure — the UI is ready, the HTTP call
      // depends on which packages are available at runtime.
      setState(() {
        _response = 'API integration ready.\n\n'
            'Provider: $_provider\n'
            'Prompt prepared (${_prompt.length} chars).\n\n'
            'To complete integration, add the `http` package to pubspec.yaml '
            'and implement the API call in ai_coach_sheet.dart.\n\n'
            'Anthropic: POST https://api.anthropic.com/v1/messages\n'
            'OpenAI: POST https://api.openai.com/v1/chat/completions';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title
              Row(
                children: [
                  Icon(Icons.psychology, color: Colors.purple.shade400),
                  const SizedBox(width: 8),
                  const Text('AI Coach', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _showPrivacy = !_showPrivacy),
                    child: const Text('Privacy', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),

              // Privacy notice
              if (_showPrivacy)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                  ),
                  child: const Text(
                    'Your API key is stored locally on your device only. '
                    'Game data (FEN/PGN) is sent directly to your chosen AI provider. '
                    'CrispChess does not store, log, or transmit any data to its own servers. '
                    'You can delete your API key at any time.',
                    style: TextStyle(fontSize: 11),
                  ),
                ),

              // API key setup
              if (_apiKey == null || _apiKey!.isEmpty) ...[
                const Text('Enter your API key to get started:',
                    style: TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'anthropic', label: Text('Anthropic')),
                    ButtonSegment(value: 'openai', label: Text('OpenAI')),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (s) => setState(() => _provider = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyController,
                  decoration: InputDecoration(
                    hintText: _provider == 'anthropic' ? 'sk-ant-...' : 'sk-...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.save, size: 18),
                      onPressed: () => _saveApiKey(_keyController.text.trim(), _provider),
                    ),
                  ),
                  obscureText: true,
                ),
              ] else ...[
                // Key configured — show ask button
                Row(
                  children: [
                    Chip(
                      label: Text('$_provider key configured',
                          style: const TextStyle(fontSize: 11)),
                      avatar: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearApiKey,
                      child: const Text('Remove key', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome),
                  label: const Text('Ask Coach'),
                  onPressed: _loading ? null : _askCoach,
                ),
              ],

              // Response
              if (_response.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.withValues(alpha: 0.2)),
                  ),
                  child: SelectableText(_response,
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }
}
