/// Chess clock — manages time for both players.
///
/// Supports standard time controls: bullet, blitz, rapid, classical, unlimited.
/// Each has a base time and optional increment (Fischer).

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Preset time control configurations.
enum TimeControl {
  unlimited('Unlimited', null, 0),
  bullet1('Bullet 1+0', Duration(minutes: 1), 0),
  bullet2('Bullet 2+1', Duration(minutes: 2), 1),
  blitz3('Blitz 3+0', Duration(minutes: 3), 0),
  blitz3inc('Blitz 3+2', Duration(minutes: 3), 2),
  blitz5('Blitz 5+0', Duration(minutes: 5), 0),
  blitz5inc('Blitz 5+3', Duration(minutes: 5), 3),
  rapid10('Rapid 10+0', Duration(minutes: 10), 0),
  rapid10inc('Rapid 10+5', Duration(minutes: 10), 5),
  rapid15('Rapid 15+10', Duration(minutes: 15), 10),
  rapid30('Rapid 30+0', Duration(minutes: 30), 0),
  classical60('Classical 60+30', Duration(minutes: 60), 30),
  custom('Custom', Duration(minutes: 10), 0);

  final String label;
  final Duration? baseTime; // null = unlimited
  final int incrementSeconds;

  const TimeControl(this.label, this.baseTime, this.incrementSeconds);

  bool get isUnlimited => baseTime == null;
}

/// Chess clock state for one player.
class ClockSide {
  Duration remaining;
  bool isRunning;

  ClockSide({required this.remaining, this.isRunning = false});

  bool get isExpired => remaining <= Duration.zero;

  String get display {
    if (remaining <= Duration.zero) return '0:00';
    final totalSeconds = remaining.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours:${mins.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Chess clock managing both players' time.
class ChessClock extends ChangeNotifier {
  final TimeControl timeControl;
  /// Override base time (used for custom time controls).
  final Duration? customBaseTime;
  /// Override increment (used for custom time controls).
  final int? customIncrementSeconds;

  late ClockSide white;
  late ClockSide black;
  Timer? _timer;
  bool _isWhiteTurn = true;
  bool _started = false;

  ChessClock({
    this.timeControl = TimeControl.unlimited,
    this.customBaseTime,
    this.customIncrementSeconds,
  }) {
    final base = customBaseTime ?? timeControl.baseTime ?? const Duration(hours: 99);
    white = ClockSide(remaining: base);
    black = ClockSide(remaining: base);
  }

  int get _incrementSecs => customIncrementSeconds ?? timeControl.incrementSeconds;

  /// Fischer increment (seconds) added to a player after each move.
  int get incrementSeconds => _incrementSecs;

  bool get isUnlimited => timeControl.isUnlimited;
  bool get isStarted => _started;
  bool get isWhiteTurn => _isWhiteTurn;
  bool get isExpired => white.isExpired || black.isExpired;
  String? get winner {
    if (white.isExpired) return 'Black';
    if (black.isExpired) return 'White';
    return null;
  }

  /// Start the clock for the first time (white's turn).
  void start() {
    if (isUnlimited) return;
    _started = true;
    _isWhiteTurn = true;
    white.isRunning = true;
    _startTimer();
  }

  /// Switch the clock after a move. Adds increment to the player who moved.
  void switchTurn() {
    if (isUnlimited || !_started) return;
    _timer?.cancel();

    // Add increment to the player who just moved
    final increment = Duration(seconds: _incrementSecs);
    if (_isWhiteTurn) {
      white.remaining += increment;
      white.isRunning = false;
      black.isRunning = true;
    } else {
      black.remaining += increment;
      black.isRunning = false;
      white.isRunning = true;
    }

    _isWhiteTurn = !_isWhiteTurn;
    _startTimer();
    notifyListeners();
  }

  /// Pause the clock (e.g. when thinking about a hint).
  void pause() {
    _timer?.cancel();
    white.isRunning = false;
    black.isRunning = false;
    notifyListeners();
  }

  /// Resume the clock for the current turn.
  void resume() {
    if (isUnlimited || !_started || isExpired) return;
    if (_isWhiteTurn) {
      white.isRunning = true;
    } else {
      black.isRunning = true;
    }
    _startTimer();
  }

  /// Reset the clock.
  void reset() {
    _timer?.cancel();
    final base = customBaseTime ?? timeControl.baseTime ?? const Duration(hours: 99);
    white = ClockSide(remaining: base);
    black = ClockSide(remaining: base);
    _isWhiteTurn = true;
    _started = false;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    if (isUnlimited) return;

    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final side = _isWhiteTurn ? white : black;
      side.remaining -= const Duration(milliseconds: 100);

      if (side.remaining <= Duration.zero) {
        side.remaining = Duration.zero;
        _timer?.cancel();
        side.isRunning = false;
      }

      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
