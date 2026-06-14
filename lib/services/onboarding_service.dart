import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a brief onboarding dialog on first launch.
class OnboardingService {
  static const _key = 'onboarding_shown';

  static Future<void> showIfFirstLaunch(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key) == true) return;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.castle, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Welcome to CrispChess'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Play chess against AI engines or a friend.'),
            SizedBox(height: 12),
            _TipRow(Icons.touch_app, 'Tap a piece, then tap its destination'),
            _TipRow(Icons.swap_vert, 'Drag pieces to move them'),
            _TipRow(Icons.lightbulb_outline, 'Tap the lightbulb for a hint'),
            _TipRow(Icons.analytics, 'Toggle analysis with the chart icon'),
            _TipRow(Icons.settings, 'Change engine & settings in the menu'),
            _TipRow(Icons.extension, 'Try puzzles to improve your tactics'),
            SizedBox(height: 8),
            Text('Keyboard: Z=undo, H=hint, N=new, F=flip, A=analysis',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Let\'s play!'),
          ),
        ],
      ),
    );

    await prefs.setBool(_key, true);
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
