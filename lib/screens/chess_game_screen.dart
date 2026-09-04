import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_clock.dart';
import '../chess/chess960.dart';
import '../chess/board_annotations.dart';
import '../chess/board_theme.dart';
import '../chess/notation.dart';
import '../chess/chess_game.dart';
import '../chess/game_state.dart';
import '../chess/game_tree.dart';
import '../chess/move_analyzer.dart';
import '../engines/chess_engine.dart';
import '../engines/dart_engine.dart';
import '../engines/engine_factory.dart';
import '../services/engine_service.dart';
import '../services/multi_engine_service.dart';
import '../services/onboarding_service.dart';
import '../services/preferences_service.dart';
import '../services/sound_service.dart';
import '../services/sound_service_factory.dart';
import '../widgets/captured_pieces.dart';
import '../widgets/chess_board.dart';
import '../widgets/eval_chart.dart';
import '../widgets/horizontal_evaluation_bar.dart';
import '../chess/openings.dart';
import '../chess/puzzle.dart';
import '../chess/xp_system.dart' show XpAwards, levelFromXp, PlayerLevel;
import '../main.dart' show themeNotifier, localeNotifier;
import 'about_screen.dart';
import 'coordinate_trainer_screen.dart';
import 'game_history_screen.dart';
import 'game_summary_screen.dart';
import 'opening_explorer_screen.dart';
import 'mistakes_screen.dart';
import 'stats_screen.dart';
import '../l10n/generated/app_localizations.dart';

import 'ai_coach_sheet.dart';
import 'drill_screen.dart';
import 'engine_match_screen.dart';
import 'pgn_database_screen.dart';
import 'position_editor_screen.dart';
import 'puzzle_screen.dart';
import 'settings_screen.dart';

/// A single PV (principal variation) line from the engine.
class PvLine {
  final double eval;
  final int depth;
  final String pv; // space-separated UCI moves
  final int pvIndex; // 1-based

  const PvLine({
    required this.eval,
    required this.depth,
    required this.pv,
    required this.pvIndex,
  });

  String get bestMove => pv.split(' ').first;
}

class ChessGameScreen extends StatefulWidget {
  const ChessGameScreen({super.key});

  @override
  State<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen> {
  late ChessGame _game;
  late EngineService _engineService;
  StreamSubscription<EngineEvent>? _eventSubscription;

  GameState _state = const GameState();
  ChessClock? _clock;
  final SoundService _sound = createSoundService();
  final PreferencesService _prefs = PreferencesService();
  final PuzzleDatabase _puzzleDb = PuzzleDatabase();

  final ValueNotifier<double?> _evalNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<int> _depthNotifier = ValueNotifier<int>(0);
  final List<double> _evalHistory = [];
  bool _awaitingEngineMove = false; // true when we expect a game move, not analysis
  String? _premove; // queued move (UCI) to play after engine responds

  /// Multi-PV lines from engine analysis (index 0 = best line).
  final List<PvLine> _pvLines = [];

  /// When the analysis panel last repainted, so a stream of `info` lines can be
  /// coalesced instead of driving one screen rebuild each.
  DateTime _lastAnalysisRepaint = DateTime.fromMillisecondsSinceEpoch(0);

  /// Key for board screenshot capture.
  final GlobalKey _boardKey = GlobalKey();

  /// User-drawn board annotations (arrows, colored squares).
  final BoardAnnotations _boardAnnotations = BoardAnnotations();
  /// Track secondary (right-click) drag for arrow drawing.
  String? _arrowDragFrom;

  /// Render black pieces as solid black instead of grey gradient.
  bool _solidBlackPieces = false;

  /// Multi-engine analysis service (null when not active).
  MultiEngineService? _multiEngine;
  StreamSubscription<MultiEngineEvent>? _multiEngineSub;

  @override
  void initState() {
    super.initState();
    _game = ChessGame();
    _engineService = EngineService(DartEngine());
    _loadPreferencesAndInit();
  }

  Future<void> _loadPreferencesAndInit() async {
    await _prefs.init();
    _maia3Variant = _prefs.variant;
    _sound.enabled = _prefs.soundEnabled;
    // Load solid black pieces preference
    final sp = await SharedPreferences.getInstance();
    _solidBlackPieces = sp.getBool('solidBlackPieces') ?? false;
    setState(() {
      _state = _state.copyWith(
        strengthLevel: _prefs.strengthLevel,
        hintDepth: _prefs.hintDepth,
        animationSpeed: _prefs.animationSpeed,
        playAsBlack: _prefs.playAsBlack,
        pieceTheme: _prefs.pieceTheme,
        timeControl: _prefs.timeControl,
        showValidMoves: _prefs.showValidMoves,
      );
    });

    // Initialize with saved engine
    final savedEngine = _prefs.engine;
    if (savedEngine != 'Built-in') {
      final elo = 800 + (_prefs.strengthLevel * 60);
      final engine = createEngine(
        savedEngine,
        playerElo: elo,
        maia3Variant: _maia3Variant,
        lc0Backend: _prefs.lc0Backend,
      );
      _engineService = EngineService(engine);
    }
    _initializeEngine();
    _puzzleDb.load();
    // Show onboarding, check daily login, then check saved game
    Future.delayed(const Duration(milliseconds: 500), () async {
      await OnboardingService.showIfFirstLaunch(context);
      // Daily login streak
      final streakXp = _prefs.checkDailyLogin();
      if (streakXp > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Daily login: +$streakXp XP (streak: ${_prefs.dailyStreak})'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _checkSavedGame();
    });
  }

  void _checkSavedGame() {
    if (!mounted) return;
    if (_prefs.hasSavedGame) {
      final moves = _prefs.savedGameMoves;
      if (moves != null && moves.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppLocalizations.of(context)?.resumeGame ?? 'Resume game?'),
            content: Text('You have a saved game (${moves.split(" ").length} moves).'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _prefs.clearSavedGame();
                },
                child: Text(AppLocalizations.of(context)?.discard ?? 'Discard'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resumeSavedGame();
                },
                child: Text(AppLocalizations.of(context)?.resume ?? 'Resume'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _resumeSavedGame() {
    final moves = _prefs.savedGameMoves;
    if (moves == null || moves.isEmpty) return;
    // Replay moves
    final moveList = moves.split(' ');
    _game.reset();
    for (final m in moveList) {
      if (!_game.makeMove(m)) break;
    }
    setState(() {
      _state = _state.copyWith(
        statusMessage: 'Game resumed',
        lastMoveUci: moveList.isNotEmpty ? moveList.last : null,
      );
    });
  }

  void _initializeEngine() {
    debugPrint('[CrispChess] Initializing engine...');
    _eventSubscription?.cancel();
    _eventSubscription = _engineService.events.listen(_onEngineEvent);
    _engineService.initialize().then((_) {
      _applyEngineOptions();
    });
  }

  /// Apply user-configured Hash and Threads to the current engine, plus the
  /// variant flag the engine needs to read the position correctly.
  void _applyEngineOptions() {
    final engine = _engineService.engine;
    engine.setOption('Hash', '${_prefs.engineHashMb}');
    engine.setOption('Threads', '${_prefs.engineThreads}');
    // A Chess960 game is handed to the engine as a FEN with the pieces on
    // shuffled files. Without this flag the engine reads it as ordinary chess
    // and misjudges castling rights. Set explicitly either way, so switching
    // back to a standard game clears it.
    engine.setOption('UCI_Chess960',
        _prefs.chessVariant == ChessVariant.chess960 ? 'true' : 'false');
  }

  void _onEngineEvent(EngineEvent event) {
    if (!mounted) return;
    debugPrint('[CrispChess] Event: ${event.runtimeType}');
    switch (event) {
      case EvalUpdateEvent(:final eval, :final depth, :final bestMove, :final pv, :final pvIndex):
        // Update primary eval display (PV line 1 only)
        if (pvIndex <= 1) {
          _evalNotifier.value = eval;
          _depthNotifier.value = depth;
          // Track eval history for the chart (capped at 500 moves)
          if (_evalHistory.length < _game.plyCount && _evalHistory.length < 500) {
            _evalHistory.add(eval);
          } else if (_evalHistory.isNotEmpty) {
            _evalHistory.last = eval;
          }
        }
        // Update Multi-PV lines (capped at 5 lines)
        if (pv != null && pv.isNotEmpty) {
          final line = PvLine(eval: eval, depth: depth, pv: pv, pvIndex: pvIndex);
          final idx = pvIndex - 1;
          if (idx >= 5) break; // Max 5 PV lines
          while (_pvLines.length <= idx) {
            _pvLines.add(line);
          }
          _pvLines[idx] = line;
          if (pvIndex == 1 && _pvLines.length > 1) {
            _pvLines.removeRange(1, _pvLines.length);
          }
        }
        if (bestMove.isNotEmpty) {
          _game.updateEvaluation(eval, bestMove, depth);
          // A searching engine emits an `info` line several dozen times a
          // second, and each one used to rebuild the whole screen — board,
          // move list and all. The eval and depth readouts have their own
          // notifiers, so a rebuild is only needed when the best move changes;
          // while the analysis panel is open its PV list also has to refresh,
          // but a few times a second is plenty.
          final now = DateTime.now();
          final movedOn = _state.currentBestMove != bestMove;
          final pvDue = _state.analysisExpanded &&
              now.difference(_lastAnalysisRepaint) >
                  const Duration(milliseconds: 200);
          if (movedOn || pvDue) {
            _lastAnalysisRepaint = now;
            setState(() {
              _state = _state.copyWith(currentBestMove: bestMove);
            });
          }
        }
      case BestMoveEvent(:final move):
        debugPrint('[CrispChess] Best move: $move (awaiting=$_awaitingEngineMove, hint=${_state.waitingForHint}, analysis=${_state.analysisExpanded})');
        if (_state.waitingForHint) {
          _handleHintResponse(move);
        } else if (_awaitingEngineMove) {
          _awaitingEngineMove = false;
          _makeEngineMove(move);
        } else {
          // Analysis or stray event — just update display, don't play
          debugPrint('[CrispChess] Treating as analysis result (not a game move)');
          setState(() {
            _state = _state.copyWith(currentBestMove: move);
          });
        }
      case StateChangeEvent(:final state):
        debugPrint('[CrispChess] Engine state: $state');
        if (state == EngineState.ready) {
          // If engine just became ready and it's the engine's turn, make a move
          if (!_isPlayerTurn && !_state.twoPlayerMode && !_awaitingEngineMove && !_game.isGameOver) {
            debugPrint('[CrispChess] Engine ready — requesting first move');
            setState(() {
              _state = _state.copyWith(
                statusMessage: '${_engineService.engineName} is thinking...',
                isThinking: true,
              );
            });
            _requestEngineMove();
          } else {
            setState(() {
              _state = _state.copyWith(
                statusMessage: _state.isThinking
                    ? 'Your turn ($_playerColorName)'
                    : '${_engineService.engineName} ${_engineService.engineVersion} ready',
              );
            });
            // Brief "ready" message, then switch to "Your turn"
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted && _engineService.state == EngineState.ready) {
                setState(() {
                  _state = _state.copyWith(
                      statusMessage: 'Your turn ($_playerColorName)');
                });
              }
            });
          }
        } else if (state == EngineState.initializing) {
          setState(() {
            _state = _state.copyWith(
              statusMessage: 'Loading ${_engineService.engineName}...',
            );
          });
        } else if (state == EngineState.error) {
          setState(() {
            _state = _state.copyWith(
              statusMessage: '${_engineService.engineName} failed to load',
              isThinking: false,
            );
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${_engineService.engineName}: failed to initialize'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Switch to Built-in',
                  textColor: Colors.white,
                  onPressed: () {
                    final fallback = createEngine('Built-in');
                    _engineService.switchEngine(fallback);
                    _prefs.engine = 'Built-in'; // Persist so it doesn't retry on reload
                  },
                ),
              ),
            );
          }
        }
      case EngineErrorEvent(:final message):
        debugPrint('[CrispChess] Engine error: $message');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_engineService.engineName}: $message',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          setState(() {
            _state = _state.copyWith(isThinking: false);
          });
        }
    }
  }

  /// Is it the human player's turn?
  bool get _isPlayerTurn {
    if (_state.twoPlayerMode) return true; // Both sides are human
    if (_state.playAsBlack) return !_game.whiteToMove;
    return _game.whiteToMove;
  }

  /// The player's piece color.
  PieceColor get _playerColor =>
      _state.playAsBlack ? PieceColor.black : PieceColor.white;

  String get _playerColorName => _state.playAsBlack ? 'Black' : 'White';

  List<String> _getValidMovesForSquare(int row, int col) {
    final square = _game.squareToAlgebraic(row, col);
    final piece = _game.board[row][col];
    if (piece == null || piece.color != _playerColor) return [];
    return _game.getLegalMoves().where((m) => m.startsWith(square)).toList();
  }

  void _handleHintResponse(String uciMove) {
    if (!mounted) return;
    setState(() {
      _state = _state.copyWith(
        waitingForHint: false,
        isThinking: false,
        hintMove: uciMove,
        statusMessage: 'Hint: $uciMove',
      );
    });
  }

  void _makeEngineMove(String uciMove) {
    if (!_game.makeMove(uciMove)) {
      // The engine answered with a move that isn't legal here. Don't leave the
      // UI stuck on "thinking" — hand the turn back and say what happened.
      debugPrint('[CrispChess] Engine returned illegal move "$uciMove" for '
          '${_game.currentFEN} — ignoring');
      setState(() {
        _state = _state.copyWith(
          isThinking: false,
          statusMessage: 'Engine returned an illegal move — your turn',
        );
      });
      return;
    }
    _playMoveSound(uciMove);
    _clock?.switchTurn();
    _autoSaveGame();
    final san = _game.moveHistorySan;
    setState(() {
      _state = _state.copyWith(
        lastMoveUci: uciMove,
        lastMove: '${_engineService.engineName}: ${san.isNotEmpty ? san.last : uciMove}',
        statusMessage:
            _game.isGameOver ? 'Game Over!' : 'Your turn ($_playerColorName)',
        isThinking: false,
      );
    });
    if (_game.isGameOver) {
      _clock?.pause();
      _showGameOverDialog();
    } else if (_premove != null) {
      // Execute queued premove
      final premove = _premove!;
      _premove = null;
      // Small delay so the engine's move animation is visible
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted) return;
        if (_game.getLegalMoves().any((m) => m.startsWith(premove))) {
          // Simulate the move via _onMove coordinates
          final fromCol = premove.codeUnitAt(0) - 97;
          final fromRow = 8 - int.parse(premove[1]);
          final toCol = premove.codeUnitAt(2) - 97;
          final toRow = 8 - int.parse(premove[3]);
          _onMove(fromRow, fromCol, toRow, toCol);
        } else {
          // Premove no longer legal
          setState(() {
            _state = _state.copyWith(statusMessage: 'Premove illegal — your turn');
          });
          if (_engineService.engine.canPonder) {
            _engineService.requestAnalysis(
                _game.positionCommand, depth: _state.hintDepth);
          }
        }
      });
    } else if (_engineService.engine.canPonder) {
      // Pondering: light background analysis while waiting for the player.
      // Only for engines that search off the UI thread and honour `stop` —
      // the WASM and FFI engines run the search as one blocking call, so a
      // background `go` froze the app for its whole duration, and that
      // duration grew every move as the position opened up.
      _engineService.requestAnalysis(
        _game.positionCommand,
        depth: (_state.hintDepth ~/ 2).clamp(6, 12),
      );
    }
  }

  void _onSquareTap(int row, int col) {
    if (!_isPlayerTurn || _state.isThinking) return;

    final piece = _game.board[row][col];

    if (_state.selectedRow != null && _state.selectedCol != null) {
      // If tapping same square, deselect
      if (_state.selectedRow == row && _state.selectedCol == col) {
        setState(() {
          _state = _state.copyWith(
            selectedRow: null,
            selectedCol: null,
            validMoves: const [],
          );
        });
        return;
      }

      // If tapping another own piece, reselect it
      if (piece != null && piece.color == _playerColor) {
        setState(() {
          _state = _state.copyWith(
            selectedRow: row,
            selectedCol: col,
            validMoves: _state.showValidMoves
                ? _getValidMovesForSquare(row, col)
                : const [],
          );
        });
        return;
      }

      // Otherwise try to move
      _onMove(_state.selectedRow!, _state.selectedCol!, row, col);
      setState(() {
        _state = _state.copyWith(
          selectedRow: null,
          selectedCol: null,
          validMoves: const [],
        );
      });
    } else if (piece != null && piece.color == _playerColor) {
      setState(() {
        _state = _state.copyWith(
          selectedRow: row,
          selectedCol: col,
          validMoves: _state.showValidMoves
              ? _getValidMovesForSquare(row, col)
              : const [],
        );
      });
    }
  }

  bool _isPromotion(int fromRow, int fromCol, int toRow, int toCol) {
    final piece = _game.board[fromRow][fromCol];
    if (piece == null || piece.type != PieceType.pawn) return false;
    return (piece.color == PieceColor.white && toRow == 0) ||
           (piece.color == PieceColor.black && toRow == 7);
  }

  Future<String?> _showPromotionDialog(PieceColor color) async {
    final isDark = color == PieceColor.black;
    final pieces = [
      ('q', Icons.star, 'Queen'),
      ('r', Icons.domain, 'Rook'),
      ('b', Icons.change_history, 'Bishop'),
      ('n', Icons.pets, 'Knight'),
    ];
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Promote to'),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: pieces.map((p) => InkWell(
            onTap: () => Navigator.pop(ctx, p.$1),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                p.$1 == 'q' ? (isDark ? '\u265B' : '\u2655')
                  : p.$1 == 'r' ? (isDark ? '\u265C' : '\u2656')
                  : p.$1 == 'b' ? (isDark ? '\u265D' : '\u2657')
                  : (isDark ? '\u265E' : '\u2658'),
                style: const TextStyle(fontSize: 40),
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }

  void _onMove(int fromRow, int fromCol, int toRow, int toCol) {
    debugPrint('[CrispChess] _onMove($fromRow,$fromCol -> $toRow,$toCol) whiteToMove=${_game.whiteToMove} isThinking=${_state.isThinking} engineState=${_engineService.state}');

    // Premove: if engine is thinking, queue the move
    if (_state.isThinking && !_state.twoPlayerMode) {
      final uciMove = _game.squareToAlgebraic(fromRow, fromCol) +
          _game.squareToAlgebraic(toRow, toCol);
      setState(() {
        _premove = uciMove;
        _state = _state.copyWith(
          statusMessage: 'Premove: $uciMove',
        );
      });
      return;
    }

    if (!_isPlayerTurn || _state.isThinking) return;

    // Handle pawn promotion
    if (_isPromotion(fromRow, fromCol, toRow, toCol)) {
      final piece = _game.board[fromRow][fromCol]!;
      _showPromotionDialog(piece.color).then((promo) {
        if (promo == null) return; // user cancelled (shouldn't happen with barrierDismissible: false)
        final uciMove = _game.squareToAlgebraic(fromRow, fromCol) +
            _game.squareToAlgebraic(toRow, toCol) + promo;
        _executeMove(uciMove, toRow, toCol);
      });
      return;
    }

    final uciMove = _game.squareToAlgebraic(fromRow, fromCol) +
        _game.squareToAlgebraic(toRow, toCol);
    _executeMove(uciMove, toRow, toCol);
  }

  void _executeMove(String uciMove, int toRow, int toCol) {
    // Detect capture before making the move
    final isCapture = _game.board[toRow][toCol] != null;

    if (_game.makeMove(uciMove)) {
      _boardAnnotations.clear(); // Clear drawn annotations on move
      _playMoveSound(uciMove);
      _clock?.switchTurn();
      _autoSaveGame();
      setState(() {
        final san = _game.moveHistorySan;
        final lastSan = san.isNotEmpty ? san.last : uciMove;
        _state = _state.copyWith(
            lastMove: 'You: $lastSan', hintMove: null,
            lastMoveUci: uciMove, isLastMoveCapture: isCapture);

        if (_game.isGameOver) {
          _clock?.pause();
          _sound.play(ChessSound.gameEnd);
          _state = _state.copyWith(
            isThinking: false,
            statusMessage: 'Game Over: ${_game.gameOverReason}',
          );
          _showGameOverDialog();
        } else {
          if (_state.twoPlayerMode) {
            final turn = _game.whiteToMove ? 'White' : 'Black';
            _state = _state.copyWith(
              statusMessage: '$turn to move',
              isThinking: false,
              boardFlipped: !_game.whiteToMove,
            );
          } else {
            // Stop pondering / any running analysis before requesting a move
            _engineService.stop();
            _state = _state.copyWith(
              statusMessage: '${_engineService.engineName} is thinking...',
              isThinking: true,
            );
            _requestEngineMove();
          }
        }
      });
    } else {
      _sound.play(ChessSound.illegal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)?.illegalMove ?? 'Illegal Move!'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(milliseconds: 700),
        ),
      );
    }
  }

  void _requestEngineMove() {
    debugPrint('[CrispChess] Requesting engine move: skill=${_state.strengthLevel}');
    _awaitingEngineMove = true;
    _engineService.requestMove(
      _game.positionCommand,
      skillLevel: _state.strengthLevel,
      moveTime: _engineMoveTime(),
    );
  }

  /// When a real clock is running, budget the engine's move from *its own*
  /// remaining time; otherwise return null so EngineService falls back to the
  /// flat per-level think time.
  Duration? _engineMoveTime() {
    final clock = _clock;
    if (clock == null || clock.isUnlimited || !clock.isStarted) return null;
    // Player is Black => engine plays White, and vice versa.
    final engineSide = _state.playAsBlack ? clock.white : clock.black;
    return clockAwareThinkTime(
      remaining: engineSide.remaining,
      incrementSeconds: clock.incrementSeconds,
      skillLevel: _state.strengthLevel,
    );
  }

  ChessEngine? _hintEngineInstance;

  void _getHint() {
    if (!_isPlayerTurn || _state.isThinking) return;

    // Use a separate engine for hints if configured
    if (_state.hintEngine != 'same') {
      _getHintFromSeparateEngine();
      return;
    }

    if (_engineService.state != EngineState.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.engineNotReady ?? 'Engine not ready')),
      );
      return;
    }

    // Stop any running pondering/analysis before requesting hint
    _engineService.stop();

    setState(() {
      _state = _state.copyWith(
        waitingForHint: true,
        isThinking: true,
        statusMessage: 'Analyzing position...',
      );
    });

    _engineService.requestMove(
      _game.positionCommand,
      depth: _state.hintDepth,
    );
  }

  void _undoMove() {
    if (_game.plyCount < 2) return;
    if (_state.isThinking) _engineService.stop();

    setState(() {
      _game.undoMove();
      _game.undoMove();
      _state = _state.copyWith(
        statusMessage: 'Your turn ($_playerColorName)',
        hintMove: null,
        isThinking: false,
      );
    });
  }

  void _newGame() {
    _sound.play(ChessSound.gameStart);
    _evalNotifier.value = null;
    _depthNotifier.value = 0;
    _evalHistory.clear();
    _prefs.clearSavedGame();
    _awaitingEngineMove = false;
    _clock?.dispose();
    if (!_state.timeControl.isUnlimited) {
      _clock = ChessClock(
        timeControl: _state.timeControl,
        customBaseTime: _state.timeControl == TimeControl.custom
            ? Duration(minutes: _prefs.customBaseMinutes)
            : null,
        customIncrementSeconds: _state.timeControl == TimeControl.custom
            ? _prefs.customIncrementSeconds
            : null,
      );
      // No screen-wide setState here: the clock ticks 10x a second, and the
      // only thing that changes is the two clock bars — which subscribe to the
      // clock themselves (see _buildClockBar call sites). Rebuilding the whole
      // screen instead meant re-running the board's 64 squares, the captured
      // pieces, the move list and the game-over check ten times a second, all
      // of which get more expensive the longer the game runs.
      _clock!.start();
    } else {
      _clock = null;
    }

    // Set the variant on the game object
    _game.variant = _prefs.chessVariant;
    // The engine has to be told too — the variant can change between games.
    _applyEngineOptions();

    setState(() {
      if (_prefs.chessVariant == ChessVariant.chess960) {
        final fen = generateChess960Fen();
        _game.loadFen(fen);
      } else {
        _game.reset();
      }
      _state = _state.copyWith(
        statusMessage: _state.playAsBlack
            ? '${_engineService.engineName} is thinking...'
            : 'Your turn ($_playerColorName)',
        isThinking: _state.playAsBlack,
        hintMove: null,
        lastMove: '',
        currentBestMove: null,
      );
    });

    // If playing as black, engine makes the first move
    if (_state.playAsBlack) {
      _requestEngineMove();
    }
  }

  void _showLevelUpDialog(PlayerLevel newLevel) {
    final icon = switch (newLevel) {
      PlayerLevel.pawn => Icons.circle,
      PlayerLevel.knight => Icons.hotel,
      PlayerLevel.bishop => Icons.church,
      PlayerLevel.rook => Icons.account_balance,
      PlayerLevel.queen => Icons.auto_awesome,
      PlayerLevel.grandmaster => Icons.stars,
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            Text('Level Up!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: Colors.amber.shade700)),
            const SizedBox(height: 8),
            Text('You reached ${newLevel.title}!',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${_prefs.totalXp} XP',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)?.continueButton ?? 'Continue'),
          ),
        ],
      ),
    );
  }

  void _showGameOverDialog() {
    // Track game stats + award XP
    _prefs.gamesPlayed = _prefs.gamesPlayed + 1;
    final levelBefore = levelFromXp(_prefs.totalXp);
    bool playerWon = false;
    if (_game.winner != null) {
      playerWon = (_state.playAsBlack && _game.winner == 'Black') ||
          (!_state.playAsBlack && _game.winner == 'White');
      if (playerWon) {
        _prefs.gamesWon = _prefs.gamesWon + 1;
        _prefs.addXp(XpAwards.gameWin(_state.strengthLevel));
      } else {
        _prefs.addXp(XpAwards.gameLoss);
      }
    } else {
      _prefs.addXp(XpAwards.gameDraw);
    }

    // Check for level-up
    final levelAfter = levelFromXp(_prefs.totalXp);
    if (levelAfter != levelBefore) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _showLevelUpDialog(levelAfter);
      });
    }

    // Rate app prompt after 3rd win (non-intrusive)
    if (playerWon && _prefs.gamesWon == 3) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Enjoying CrispChess? Consider leaving a review!'),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Dismiss',
                onPressed: () {},
              ),
            ),
          );
        }
      });
    }

    // Save completed game to history
    final pgn = _game.toPgn(
      engineName: _state.twoPlayerMode ? 'Human' : _engineService.engineName,
      playAsBlack: _state.playAsBlack,
    );
    _prefs.addGameToHistory(pgn);
    _prefs.clearSavedGame();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final winner = _game.winner;
        final explanation = _game.gameOverExplanation;
        return AlertDialog(
          title: Text(_game.gameOverReason),
          content: Text(
            winner != null
                ? '$winner wins the game!'
                : explanation.isNotEmpty
                    ? explanation
                    : 'The game ended in a draw.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showGameSummary();
              },
              child: Text(AppLocalizations.of(context)?.review ?? 'Review'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _confirmNewGame();
              },
              child: Text(AppLocalizations.of(context)?.newGame ?? 'New Game'),
            ),
          ],
        );
      },
    );
  }

  void _showGameSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameSummaryScreen(
          movesSan: _game.moveHistorySan,
          evalHistory: List.unmodifiable(_evalHistory),
          annotations: _game.annotations,
          gameResult: _game.gameOverReason,
          winner: _game.winner,
          engineName: _state.twoPlayerMode
              ? 'Human'
              : _engineService.engineName,
          tree: _game.tree,
        ),
      ),
    );
  }

  String _maia3Variant = '5m';

  Future<void> _openGameHistory() async {
    final pgn = await Navigator.push<String>(context,
        MaterialPageRoute(builder: (_) => const GameHistoryScreen()));
    if (pgn != null && pgn.isNotEmpty && mounted) {
      if (_game.loadPgn(pgn)) {
        setState(() {
          _state = _state.copyWith(
            statusMessage: 'Game loaded from history',
            hintMove: null,
            currentBestMove: null,
          );
        });
      }
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          strengthLevel: _state.strengthLevel,
          hintDepth: _state.hintDepth,
          currentEngine: _engineService.engineName,
          playAsBlack: _state.playAsBlack,
          maia3Variant: _maia3Variant,
          animationSpeed: _state.animationSpeed,
          pieceTheme: _state.pieceTheme,
          hintEngine: _state.hintEngine,
          timeControl: _state.timeControl,
          chessVariant: _prefs.chessVariant,
          lc0Backend: _prefs.lc0Backend,
        ),
      ),
    );
    if (result != null) {
      final newPlayAsBlack = result['playAsBlack'] as bool? ?? false;
      final colorChanged = newPlayAsBlack != _state.playAsBlack;
      final newVariant = result['maia3Variant'] as String? ?? '5m';
      final newLc0Backend = result['lc0Backend'] as String? ?? 'auto';
      final lc0BackendChanged = newLc0Backend != _prefs.lc0Backend;
      final newChessVariant = result['chessVariant'] as ChessVariant? ?? ChessVariant.standard;
      final variantModeChanged = newChessVariant != _prefs.chessVariant;
      _prefs.chessVariant = newChessVariant;

      setState(() {
        _state = _state.copyWith(
          strengthLevel: result['strengthLevel']! as int,
          hintDepth: result['hintDepth']! as int,
          showValidMoves: result['showValidMoves']! as bool,
          allowUndo: result['allowUndo'] as bool? ?? true,
          animationSpeed: result['animationSpeed'] as int? ?? 2,
          hintEngine: result['hintEngine'] as String? ?? 'same',
          timeControl: result['timeControl'] as TimeControl? ?? TimeControl.unlimited,
          playAsBlack: newPlayAsBlack,
          pieceTheme: result['pieceTheme'] as String? ?? 'chessnut',
        );
      });

      // If color or game variant changed, start a new game
      if (colorChanged || variantModeChanged) {
        _newGame();
      }

      // Switch engine if changed (or variant changed for Maia)
      final selectedEngine = result['engine'] as String?;
      final variantChanged = newVariant != _maia3Variant;
      _maia3Variant = newVariant;

      if (selectedEngine != null &&
          (selectedEngine != _engineService.engineName ||
              variantChanged ||
              (selectedEngine == 'Lc0' && lc0BackendChanged))) {
        debugPrint('[CrispChess] Switching engine to $selectedEngine (variant: $_maia3Variant)');
        final elo = 800 + (_state.strengthLevel * 60);
        final newEngine = createEngine(
          selectedEngine,
          playerElo: elo,
          maia3Variant: _maia3Variant,
          lc0Backend: newLc0Backend,
        );
        _engineService.switchEngine(newEngine);
        _applyEngineOptions();
      }

      // Apply theme immediately
      final themeMode = result['themeMode'] as String?;
      if (themeMode != null) {
        SharedPreferences.getInstance().then((sp) {
          sp.setString('themeMode', themeMode);
        });
        themeNotifier.value = switch (themeMode) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
      }

      // Apply language change
      final language = result['language'] as String?;
      if (language != null) {
        SharedPreferences.getInstance().then((sp) {
          sp.setString('locale', language);
        });
        localeNotifier.value = language == 'system' ? null : Locale(language);
      }

      // Apply solid black pieces
      final solidBlack = result['solidBlackPieces'] as bool?;
      if (solidBlack != null) {
        _solidBlackPieces = solidBlack;
        SharedPreferences.getInstance().then((sp) {
          sp.setBool('solidBlackPieces', solidBlack);
        });
      }

      // Persist all preferences
      _prefs.engine = selectedEngine ?? _engineService.engineName;
      _prefs.variant = _maia3Variant;
      _prefs.lc0Backend = newLc0Backend;
      _prefs.strengthLevel = _state.strengthLevel;
      _prefs.hintDepth = _state.hintDepth;
      _prefs.animationSpeed = _state.animationSpeed;
      _prefs.playAsBlack = _state.playAsBlack;
      _prefs.pieceTheme = _state.pieceTheme;
      _prefs.timeControl = _state.timeControl;
      _prefs.showValidMoves = _state.showValidMoves;

      // Persist custom time control if set
      final customBase = result['customBaseMinutes'] as int?;
      final customInc = result['customIncrementSeconds'] as int?;
      if (customBase != null) _prefs.customBaseMinutes = customBase;
      if (customInc != null) _prefs.customIncrementSeconds = customInc;

      // Persist board theme, notation, blindfold
      final boardTheme = result['boardTheme'] as String?;
      if (boardTheme != null) _prefs.boardTheme = boardTheme;
      final notation = result['notationStyle'] as String?;
      if (notation != null) _prefs.notationStyle = notation;
      final blindfold = result['blindfold'] as bool?;
      if (blindfold != null) _prefs.blindfold = blindfold;

      // Persist engine resource settings
      final hashMb = result['engineHashMb'] as int?;
      final threads = result['engineThreads'] as int?;
      if (hashMb != null) _prefs.engineHashMb = hashMb;
      if (threads != null) _prefs.engineThreads = threads;
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _multiEngineSub?.cancel();
    _multiEngine?.dispose();
    _evalNotifier.dispose();
    _depthNotifier.dispose();
    _clock?.dispose();
    _sound.dispose();
    _hintEngineInstance?.dispose();
    _game.dispose();
    _engineService.dispose();
    super.dispose();
  }

  void _toggleAnalysis() {
    final expanding = !_state.analysisExpanded;
    setState(() {
      _state = _state.copyWith(analysisExpanded: expanding);
    });
    if (expanding && !_state.isThinking &&
        _engineService.state == EngineState.ready) {
      _engineService.requestAnalysis(
        _game.positionCommand,
        depth: _state.hintDepth,
      );
    } else if (expanding && _engineService.state != EngineState.ready) {
      // Engine not ready — just show the panel, analysis will start when ready
      debugPrint('[CrispChess] Analysis panel opened but engine not ready');
    } else if (!expanding) {
      _engineService.stop();
    }
  }

  Widget _buildAnalysisPanel() {
    final annotations = _game.annotations;
    final lastAnnotation = annotations.isNotEmpty ? annotations.last : null;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
          bottom: BorderSide(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
      ),
      child: Column(
        children: [
          // Header — tap to expand/collapse
          InkWell(
            onTap: _toggleAnalysis,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.analytics, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('Analysis',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: theme.colorScheme.primary)),
                  const Spacer(),
                  // Eval badge (always visible)
                  ValueListenableBuilder<double?>(
                    valueListenable: _evalNotifier,
                    builder: (context, eval, _) {
                      if (eval == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: eval >= 0
                              ? Colors.blue.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          eval >= 0
                              ? '+${eval.toStringAsFixed(1)}'
                              : eval.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: eval >= 0
                                ? Colors.blue
                                : Colors.orange,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.compare_arrows, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Multi-engine analysis',
                    onPressed: _startMultiEngineAnalysis,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.expand_less, size: 20),
                ],
              ),
            ),
          ),

          // Eval bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ValueListenableBuilder<double?>(
              valueListenable: _evalNotifier,
              builder: (context, eval, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: _depthNotifier,
                  builder: (context, depth, _) {
                    return HorizontalEvaluationBar(
                      evaluation: eval,
                      depth: depth,
                    );
                  },
                );
              },
            ),
          ),

          // PV lines display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pvLines.isEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _state.currentBestMove != null
                              ? 'Best: ${_state.currentBestMove}'
                              : _engineService.state == EngineState.ready
                                  ? 'Tap refresh to analyze'
                                  : 'Engine loading...',
                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodyMedium?.color),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildAnalysisRefreshButton(),
                    ],
                  )
                else
                  ...[
                    for (final line in _pvLines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            // Eval badge
                            Container(
                              width: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: line.eval >= 0
                                    ? Colors.blue.withValues(alpha: 0.15)
                                    : Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                line.eval >= 0
                                    ? '+${line.eval.toStringAsFixed(1)}'
                                    : line.eval.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: line.eval >= 0 ? Colors.blue : Colors.orange,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 6),
                            // PV moves (truncated)
                            Expanded(
                              child: Text(
                                line.pv,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: line.pvIndex == 1
                                      ? theme.textTheme.bodyMedium?.color
                                      : theme.textTheme.bodySmall?.color,
                                  fontWeight: line.pvIndex == 1 ? FontWeight.bold : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Depth + refresh on a separate row
                    Row(
                      children: [
                        ValueListenableBuilder<int>(
                          valueListenable: _depthNotifier,
                          builder: (context, depth, _) {
                            if (depth == 0) return const SizedBox.shrink();
                            return Text('Depth: $depth',
                                style: TextStyle(fontSize: 10,
                                    color: theme.textTheme.bodySmall?.color));
                          },
                        ),
                        const Spacer(),
                        _buildAnalysisRefreshButton(),
                      ],
                    ),
                  ],
              ],
            ),
          ),

          // Multi-engine comparison (when active)
          if (_multiEngine != null && _multiEngine!.results.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.compare_arrows, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text('Multi-Engine', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      )),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, size: 16, color: Colors.red.shade300),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Stop multi-engine',
                        onPressed: () {
                          _multiEngineSub?.cancel();
                          _multiEngine?.dispose();
                          setState(() => _multiEngine = null);
                        },
                      ),
                    ],
                  ),
                  for (final result in _multiEngine!.results)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(result.engineName,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            width: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: result.eval >= 0
                                  ? Colors.blue.withValues(alpha: 0.15)
                                  : Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              result.eval >= 0
                                  ? '+${result.eval.toStringAsFixed(1)}'
                                  : result.eval.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold,
                                color: result.eval >= 0 ? Colors.blue : Colors.orange,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('d${result.depth}',
                            style: TextStyle(fontSize: 9, color: theme.textTheme.bodySmall?.color)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(result.pv ?? result.bestMove,
                              style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                                color: theme.textTheme.bodySmall?.color),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 8),
                ],
              ),
            ),

          // Eval chart (shows eval trajectory across the game)
          if (_evalHistory.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: EvalChart(evals: List.unmodifiable(_evalHistory)),
            ),

          // Move annotation (if available)
          if (lastAnnotation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _annotationColor(lastAnnotation.evaluation.quality),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${_annotationSymbol(lastAnnotation.evaluation.quality)} ${lastAnnotation.move}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Text(lastAnnotation.evaluation.quality.name,
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                    if (lastAnnotation.evaluation.bestMove.isNotEmpty &&
                        lastAnnotation.evaluation.quality != MoveQuality.brilliant &&
                        lastAnnotation.evaluation.quality != MoveQuality.good &&
                        lastAnnotation.evaluation.quality != MoveQuality.neutral)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Better: ${lastAnnotation.evaluation.bestMove}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    if (lastAnnotation.getFullDescription().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(lastAnnotation.getFullDescription(),
                            style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Merge user-drawn annotations with analysis PV arrow.
  BoardAnnotations get _mergedAnnotations {
    final merged = BoardAnnotations();
    // Copy user annotations
    for (final a in _boardAnnotations.arrows) merged.arrows.add(a);
    for (final h in _boardAnnotations.highlights) merged.highlights.add(h);
    // Add hint arrow (yellow)
    if (_state.hintMove != null && _state.hintMove!.length >= 4) {
      final hm = _state.hintMove!;
      merged.arrows.add(BoardArrow(
        from: hm.substring(0, 2),
        to: hm.substring(2, 4),
        color: Colors.yellow.shade700,
      ));
    }
    // Add PV arrow from analysis (top line, blue)
    if (_pvLines.isNotEmpty && _state.analysisExpanded) {
      final bestPv = _pvLines.first.pv;
      if (bestPv.length >= 4) {
        final from = bestPv.substring(0, 2);
        final to = bestPv.substring(2, 4);
        merged.arrows.add(BoardArrow(from: from, to: to, color: Colors.blue));
      }
    } else if (_state.currentBestMove != null &&
        _state.currentBestMove!.length >= 4 &&
        _state.analysisExpanded) {
      final bm = _state.currentBestMove!;
      merged.arrows.add(BoardArrow(
        from: bm.substring(0, 2),
        to: bm.substring(2, 4),
        color: Colors.blue,
      ));
    }
    return merged;
  }

  Future<void> _startMultiEngineAnalysis() async {
    // Create a second engine for comparison
    final engines = ['Built-in', 'Frozenight', 'Stockfish', 'Maia3 Dart', 'Lc0'];
    final currentEngine = _engineService.engineName;

    final selected = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        final chosen = <String>{};
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(AppLocalizations.of(context)?.multiEngineAnalysis ?? 'Multi-Engine Analysis'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppLocalizations.of(context)?.selectEnginesToCompare ?? 'Select engines to compare:', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                for (final name in engines)
                  CheckboxListTile(
                    title: Text(name, style: const TextStyle(fontSize: 13)),
                    subtitle: name == currentEngine
                        ? const Text('(current opponent)', style: TextStyle(fontSize: 11))
                        : null,
                    value: chosen.contains(name),
                    dense: true,
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true) chosen.add(name); else chosen.remove(name);
                      });
                    },
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)?.cancel ?? 'Cancel')),
              FilledButton(
                onPressed: chosen.length >= 2 ? () => Navigator.pop(ctx, chosen.toList()) : null,
                child: Text(AppLocalizations.of(context)?.start ?? 'Start'),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || selected.length < 2) return;

    // Dispose previous multi-engine
    _multiEngineSub?.cancel();
    _multiEngine?.dispose();
    _multiEngine = null;

    final multi = MultiEngineService();
    try {
      for (final name in selected) {
        final engine = createEngine(name);
        await multi.addEngine(engine);
      }

      _multiEngine = multi;
      _multiEngineSub = multi.events.listen((event) {
        if (mounted) setState(() {});
      });

      multi.analyzeAll(_game.positionCommand, depth: _state.hintDepth);
      setState(() {});
    } catch (e) {
      multi.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Multi-engine failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildAnalysisRefreshButton() {
    return IconButton(
      icon: const Icon(Icons.refresh, size: 18),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Re-analyze',
      onPressed: (_state.isThinking ||
              _engineService.state != EngineState.ready)
          ? null
          : () {
              _pvLines.clear();
              _engineService.requestAnalysis(
                _game.positionCommand,
                depth: _state.hintDepth,
              );
            },
    );
  }

  Color _annotationColor(MoveQuality q) {
    return switch (q) {
      MoveQuality.brilliant => Colors.cyan.withValues(alpha: 0.15),
      MoveQuality.good => Colors.green.withValues(alpha: 0.15),
      MoveQuality.interesting => Colors.blue.withValues(alpha: 0.15),
      MoveQuality.neutral => Colors.grey.withValues(alpha: 0.15),
      MoveQuality.dubious => Colors.yellow.withValues(alpha: 0.15),
      MoveQuality.mistake => Colors.orange.withValues(alpha: 0.15),
      MoveQuality.blunder => Colors.red.withValues(alpha: 0.15),
    };
  }

  String _annotationSymbol(MoveQuality q) {
    return switch (q) {
      MoveQuality.brilliant => '!!',
      MoveQuality.good => '!',
      MoveQuality.interesting => '!?',
      MoveQuality.neutral => '·',
      MoveQuality.dubious => '?!',
      MoveQuality.mistake => '?',
      MoveQuality.blunder => '??',
    };
  }

  void _confirmResign() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.resignQuestion ?? 'Resign?'),
        content: Text('${_engineService.engineName} wins by resignation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _game.resign();
              _clock?.pause();
              _sound.play(ChessSound.gameEnd);
              setState(() {
                _state = _state.copyWith(
                  isThinking: false,
                  statusMessage: 'You resigned',
                );
              });
              _showGameOverDialog();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)?.resign ?? 'Resign'),
          ),
        ],
      ),
    );
  }

  void _offerDraw() {
    // Eval is from white's perspective: positive = white is better.
    // Determine the engine's advantage from its own perspective.
    final eval = _evalNotifier.value;
    final engineIsWhite = _state.playAsBlack; // if player is black, engine is white
    final engineEval = eval != null
        ? (engineIsWhite ? eval : -eval)
        : 0.0;

    // Engine accepts if:
    // - position is roughly equal (within ±1.5 pawns from engine's view)
    // - engine is losing (eval negative from engine's perspective)
    if (engineEval < 1.5) {
      // Engine accepts draw
      _game.agreeToDraw();
      _clock?.pause();
      _sound.play(ChessSound.gameEnd);
      setState(() {
        _state = _state.copyWith(
          isThinking: false,
          statusMessage: 'Draw agreed',
        );
      });
      _showGameOverDialog();
    } else {
      // Engine declines — it believes it's winning
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.drawDeclined(_engineService.engineName)
                ?? '${_engineService.engineName} declines the draw offer.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _confirmNewGame() {
    if (!_game.hasMoves) {
      _showSidePicker();
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text('${l?.newGame ?? "New Game"}?'),
          content: Text(l?.newGameConfirm ?? 'Current game will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l?.cancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showSidePicker();
              },
              child: Text(l?.newGame ?? 'New Game'),
            ),
          ],
        );
      },
    );
  }

  void _showSidePicker() {
    showDialog(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return SimpleDialog(
        title: Text(l?.playAs ?? 'Play as'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _state = _state.copyWith(
                  playAsBlack: false, twoPlayerMode: false));
              _prefs.playAsBlack = false;
              _newGame();
            },
            child: ListTile(
              leading: const Icon(Icons.circle, color: Colors.white),
              title: Text(l?.playAsWhite ?? 'White'),
              dense: true, contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _state = _state.copyWith(
                  playAsBlack: true, twoPlayerMode: false));
              _prefs.playAsBlack = true;
              _newGame();
            },
            child: ListTile(
              leading: const Icon(Icons.circle, color: Colors.black),
              title: Text(l?.playAsBlack ?? 'Black'),
              dense: true, contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final random = DateTime.now().millisecond % 2 == 0;
              setState(() => _state = _state.copyWith(
                  playAsBlack: random, twoPlayerMode: false));
              _prefs.playAsBlack = random;
              _newGame();
            },
            child: ListTile(
              leading: const Icon(Icons.shuffle),
              title: Text(l?.playAsRandom ?? 'Random'),
              dense: true, contentPadding: EdgeInsets.zero,
            ),
          ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _state = _state.copyWith(
                  twoPlayerMode: true, playAsBlack: false));
              _newGame();
            },
            child: ListTile(
              leading: const Icon(Icons.people),
              title: Text(l?.twoPlayer ?? 'Two Player (local)'),
              subtitle: Text(l?.passAndPlay ?? 'Pass and play'),
              dense: true, contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      );
      },
    );
  }

  Future<void> _getHintFromSeparateEngine() async {
    setState(() {
      _state = _state.copyWith(
        isThinking: true,
        statusMessage: 'Getting hint from ${_state.hintEngine}...',
      );
    });

    try {
      // Create or reuse the hint engine
      _hintEngineInstance ??= createEngine(_state.hintEngine, maia3Variant: _maia3Variant);
      if (_hintEngineInstance!.state == EngineState.idle) {
        await _hintEngineInstance!.initialize();
      }

      final move = await _hintEngineInstance!.bestMove(
        _game.positionCommand,
        depth: _state.hintDepth,
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        _hintEngineInstance?.stop();
        throw TimeoutException('Hint timed out');
      });

      if (mounted) {
        _handleHintResponse(move);
      }
    } catch (e) {
      debugPrint('[CrispChess] Hint engine error: $e');
      if (mounted) {
        setState(() {
          _state = _state.copyWith(
            isThinking: false,
            statusMessage: 'Hint failed — try "Same as opponent"',
          );
        });
      }
    }
  }

  void _autoSaveGame() {
    if (_game.hasMoves && !_game.isGameOver) {
      _prefs.saveGame(_game.currentFEN, _game.moveHistory);
    } else {
      _prefs.clearSavedGame();
    }
  }

  void _playMoveSound(String uci) {
    if (_game.inCheck) {
      _sound.play(ChessSound.check);
    } else if (uci.length > 4) {
      _sound.play(ChessSound.promote);
    } else if (uci == 'e1g1' || uci == 'e1c1' || uci == 'e8g8' || uci == 'e8c8') {
      _sound.play(ChessSound.castle);
    } else {
      // Simplified: we don't track captures here, so just play move sound
      _sound.play(ChessSound.move);
    }
  }

  void _exportPgn() {
    final pgn = _game.toPgn(
      engineName: _engineService.engineName,
      playAsBlack: _state.playAsBlack,
    );
    Clipboard.setData(ClipboardData(text: pgn));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.pgnCopied ?? 'PGN copied to clipboard')),
      );
    }
  }

  Future<void> _importPgn() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No PGN found in clipboard'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (_game.loadPgn(data.text!)) {
      _clock?.pause();
      setState(() {
        _state = _state.copyWith(
          statusMessage: 'Game loaded from PGN',
          isThinking: false,
          hintMove: null,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)?.pgnLoaded ?? 'PGN loaded')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid PGN'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _loadFen() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)?.loadFen ?? 'Load FEN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)?.pasteFenHint ?? 'Paste FEN string...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.paste, size: 16),
                label: Text(AppLocalizations.of(context)?.pasteFromClipboard ?? 'Paste from clipboard'),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    controller.text = data!.text!.trim();
                  }
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final fen = controller.text.trim();
              if (fen.isEmpty) return;
              if (_game.loadFen(fen)) {
                Navigator.pop(ctx);
                _clock?.pause();
                _evalNotifier.value = null;
                _depthNotifier.value = 0;
                _evalHistory.clear();
                _awaitingEngineMove = false;
                setState(() {
                  _state = _state.copyWith(
                    statusMessage: 'Position loaded from FEN',
                    isThinking: false,
                    hintMove: null,
                    lastMove: '',
                    currentBestMove: null,
                  );
                });
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)?.invalidFen ?? 'Invalid FEN string'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Text(AppLocalizations.of(context)?.load ?? 'Load'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareScreenshot() async {
    try {
      final boundary = _boardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)?.couldNotCaptureBoard ?? 'Could not capture board')),
          );
        }
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      // Copy PNG bytes as clipboard data
      await Clipboard.setData(ClipboardData(text: '[Board image captured: ${bytes.length} bytes]'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Board captured (${(bytes.length / 1024).toStringAsFixed(0)} KB)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screenshot failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _openPgnDatabase() async {
    final pgn = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PgnDatabaseScreen()),
    );
    if (pgn != null && mounted) {
      if (_game.loadPgn(pgn)) {
        _clock?.pause();
        _evalNotifier.value = null;
        _depthNotifier.value = 0;
        _evalHistory.clear();
        _pvLines.clear();
        setState(() {
          _state = _state.copyWith(
            statusMessage: 'Game loaded from database',
            isThinking: false,
            hintMove: null,
          );
        });
      }
    }
  }

  Future<void> _openPositionEditor() async {
    final fen = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PositionEditorScreen(initialFen: _game.currentFEN),
      ),
    );
    if (fen != null && mounted) {
      if (_game.loadFen(fen)) {
        _clock?.pause();
        _evalNotifier.value = null;
        _depthNotifier.value = 0;
        _evalHistory.clear();
        _pvLines.clear();
        _awaitingEngineMove = false;
        setState(() {
          _state = _state.copyWith(
            statusMessage: 'Custom position loaded',
            isThinking: false,
            hintMove: null,
            lastMove: '',
            currentBestMove: null,
          );
        });
      }
    }
  }

  Widget _buildClockBar(ClockSide side, {required bool isOpponent}) {
    final isLow = side.remaining.inSeconds < 30;
    final isExpired = side.isExpired;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: isExpired
          ? Colors.red.shade100
          : side.isRunning
              ? Colors.blue.shade50
              : Colors.grey.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            isOpponent ? 'Engine' : 'You',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            side.display,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: isExpired
                  ? Colors.red
                  : isLow
                      ? Colors.orange.shade800
                      : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainMenu(BuildContext context) {
    final l = AppLocalizations.of(context);

    MenuItemButton item(IconData icon, String label, VoidCallback onPressed) {
      return MenuItemButton(
        leadingIcon: Icon(icon, size: 20),
        onPressed: onPressed,
        child: Text(label),
      );
    }

    SubmenuButton submenu(IconData icon, String label, List<Widget> children) {
      return SubmenuButton(
        leadingIcon: Icon(icon, size: 20),
        menuChildren: children,
        child: Text(label),
      );
    }

    return MenuAnchor(
      builder: (ctx, controller, child) => IconButton(
        icon: const Icon(Icons.more_vert, size: 20),
        tooltip: 'Menu',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
      menuChildren: [
        // 1. New Game
        item(Icons.refresh, l?.newGame ?? 'New Game', _confirmNewGame),
        const Divider(height: 1),
        // 2. Game
        submenu(Icons.videogame_asset, l?.game ?? 'Game', [
          item(Icons.swap_vert, l?.flipBoard ?? 'Flip Board', () {
            setState(() => _state = _state.copyWith(boardFlipped: !_state.boardFlipped));
          }),
          item(Icons.handshake, l?.offerDraw ?? 'Offer Draw', _offerDraw),
          item(Icons.flag, l?.resign ?? 'Resign', _confirmResign),
        ]),
        // 3. Import / Export
        submenu(Icons.import_export, l?.importExport ?? 'Import / Export', [
          item(Icons.copy, l?.copyPgn ?? 'Copy PGN', _exportPgn),
          item(Icons.paste, l?.pastePgn ?? 'Paste PGN', _importPgn),
          item(Icons.input, l?.loadFen ?? 'Load FEN', _loadFen),
          item(Icons.grid_on, l?.setupPosition ?? 'Setup Position', _openPositionEditor),
          item(Icons.storage, l?.pgnDatabase ?? 'PGN Database', _openPgnDatabase),
        ]),
        // 4. Board Tools
        submenu(Icons.dashboard_customize, l?.boardToolsMenu ?? 'Board Tools', [
          item(Icons.photo_camera, l?.boardScreenshot ?? 'Board Screenshot', _shareScreenshot),
          item(Icons.layers_clear, l?.clearAnnotations ?? 'Clear Annotations', () {
            setState(() => _boardAnnotations.clear());
          }),
          item(Icons.bookmark_add, l?.bookmarkPosition ?? 'Bookmark Position', () {
            _prefs.addBookmark(_game.currentFEN);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l?.positionBookmarked ?? 'Position bookmarked')),
              );
            }
          }),
        ]),
        // 5. Learn
        submenu(Icons.school, l?.learnMenu ?? 'Learn', [
          item(Icons.extension, l?.puzzles ?? 'Puzzles', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PuzzleScreen(puzzleDb: _puzzleDb)));
          }),
          item(Icons.school, l?.drills ?? 'Drills', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DrillListScreen()));
          }),
          item(Icons.explore, l?.openingExplorer ?? 'Opening Explorer', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OpeningExplorerScreen()));
          }),
          item(Icons.grid_3x3, l?.coordinateTrainer ?? 'Coordinate Trainer', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CoordinateTrainerScreen()));
          }),
          item(Icons.psychology, l?.askCoach ?? 'Ask Coach', () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => AiCoachSheet(
                fen: _game.currentFEN,
                pgn: _game.toPgn(engineName: _engineService.engineName, playAsBlack: _state.playAsBlack),
                lastMove: _game.moveHistorySan.isNotEmpty ? _game.moveHistorySan.last : null,
              ),
            );
          }),
          item(Icons.sports_esports, l?.engineVsEngine ?? 'Engine vs Engine', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const EngineMatchScreen()));
          }),
        ]),
        // 6. Progress
        submenu(Icons.timeline, l?.progressMenu ?? 'Progress', [
          item(Icons.history, l?.gameHistory ?? 'Game History', _openGameHistory),
          item(Icons.warning_amber, l?.mistakes ?? 'My Mistakes', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MistakesScreen()));
          }),
          item(Icons.bar_chart, l?.stats ?? 'Stats', () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
          }),
        ]),
        const Divider(height: 1),
        // 7. Settings
        item(Icons.settings, l?.settings ?? 'Settings', _openSettings),
        // 8. About
        item(Icons.info_outline, l?.about ?? 'About', () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()));
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            // Status indicator
            if (_state.isThinking || _engineService.state == EngineState.initializing)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _engineService.state == EngineState.initializing
                      ? Colors.orange
                      : null,
                ),
              )
            else
              Icon(Icons.circle, size: 10,
                  color: switch (_engineService.state) {
                    EngineState.ready => Colors.green,
                    EngineState.error => Colors.red,
                    _ => Colors.grey,
                  }),
            const SizedBox(width: 8),
            // Status text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _engineService.state == EngineState.initializing
                        ? _state.statusMessage
                        : _state.isThinking
                            ? 'Thinking...'
                            : _engineService.state == EngineState.error
                                ? _state.statusMessage
                                : _state.lastMove.isNotEmpty
                                    ? _state.lastMove
                                    : _state.statusMessage,
                    style: TextStyle(
                      fontSize: 13,
                      color: _engineService.state == EngineState.error
                          ? Colors.red
                          : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _engineService.state == EngineState.initializing
                        ? 'Downloading & initializing...'
                        : () {
                            final info = lookupOpeningInfo(_game.currentFEN);
                            final variantLabel = switch (_game.variant) {
                              ChessVariant.chess960 => ' · 960',
                              ChessVariant.kingOfTheHill => ' · KotH',
                              ChessVariant.threeCheck => ' · 3✓ ${_game.whiteChecks}–${_game.blackChecks}',
                              _ => '',
                            };
                            if (info != null) {
                              return '${info.name}${info.statsText.isNotEmpty ? ' (${info.statsText})' : ''}$variantLabel';
                            }
                            return (_state.twoPlayerMode
                                ? 'Two Player'
                                : '${_engineService.engineName} · Lv ${_state.strengthLevel}') + variantLabel;
                          }(),
                    style: TextStyle(
                      fontSize: 10,
                      color: _engineService.state == EngineState.initializing
                          ? Colors.orange
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            // Eval badge
            ValueListenableBuilder<double?>(
              valueListenable: _evalNotifier,
              builder: (context, eval, _) {
                if (eval == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: eval >= 0 ? Colors.blue.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    eval >= 0 ? '+${eval.toStringAsFixed(1)}' : eval.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: eval >= 0 ? Colors.blue : Colors.orange,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          // Abort button — visible when thinking
          if (_state.isThinking)
            IconButton(
              icon: Icon(Icons.cancel, size: 20, color: Colors.red.shade300),
              tooltip: AppLocalizations.of(context)?.abort ?? 'Abort',
              onPressed: () {
                _engineService.stop();
                setState(() {
                  _state = _state.copyWith(
                    isThinking: false,
                    statusMessage: 'Your turn ($_playerColorName)',
                  );
                });
              },
            ),
          if (_state.allowUndo)
            IconButton(
              icon: const Icon(Icons.undo, size: 20),
              tooltip: AppLocalizations.of(context)?.undo ?? 'Undo',
              onPressed: (_state.isThinking || !_game.canUndo) ? null : _undoMove,
            ),
          if (_state.allowUndo)
            IconButton(
              icon: const Icon(Icons.redo, size: 20),
              tooltip: 'Redo',
              onPressed: (_state.isThinking || !_game.canRedo)
                  ? null
                  : () {
                      _game.redoMove();
                      setState(() {
                        _state = _state.copyWith(
                          statusMessage: 'Position restored',
                          hintMove: null,
                        );
                      });
                    },
            ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline, size: 20),
            tooltip: AppLocalizations.of(context)?.hint ?? 'Hint',
            onPressed: (!_isPlayerTurn || _state.isThinking) ? null : _getHint,
          ),
          IconButton(
            icon: Icon(
              _state.analysisExpanded ? Icons.analytics : Icons.analytics_outlined,
              size: 20,
              color: _state.analysisExpanded ? Colors.blue : null,
            ),
            tooltip: AppLocalizations.of(context)?.analyze ?? 'Analyze',
            onPressed: _toggleAnalysis,
          ),
          _buildMainMenu(context),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator (thinking or loading engine)
          if (_state.isThinking || _engineService.state == EngineState.initializing)
            LinearProgressIndicator(
              minHeight: 3,
              color: _engineService.state == EngineState.initializing
                  ? Colors.orange
                  : null,
            ),
          // Opponent clock (top)
          if (_clock != null)
            ListenableBuilder(
              listenable: _clock!,
              builder: (context, _) => _buildClockBar(
                _state.playAsBlack ? _clock!.white : _clock!.black,
                isOpponent: true,
              ),
            ),
          // Opponent's captured pieces (pieces we captured from them)
          ListenableBuilder(
            listenable: _game,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CapturedPieces(
                board: _game.board,
                color: _state.playAsBlack ? PieceColor.white : PieceColor.black,
              ),
            ),
          ),
          // Board takes all available space
          Expanded(
            child: ListenableBuilder(
              listenable: _game,
              builder: (context, _) {
                return Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.maxHeight < constraints.maxWidth
                          ? constraints.maxHeight
                          : constraints.maxWidth;
                      return SizedBox(
                        width: size,
                        height: size,
                        child: Listener(
                          // Use Listener for right-click (secondary button) detection
                          onPointerDown: (event) {
                            // Only handle secondary (right) button
                            if (event.buttons != 2) return;
                            final squareSize = size / 8;
                            final col = (event.localPosition.dx / squareSize).floor().clamp(0, 7);
                            final row = (event.localPosition.dy / squareSize).floor().clamp(0, 7);
                            final r = _state.boardFlipped ? 7 - row : row;
                            final c = _state.boardFlipped ? 7 - col : col;
                            _arrowDragFrom = _game.squareToAlgebraic(r, c);
                          },
                          onPointerUp: (event) {
                            if (_arrowDragFrom == null) return;
                            final squareSize = size / 8;
                            final col = (event.localPosition.dx / squareSize).floor().clamp(0, 7);
                            final row = (event.localPosition.dy / squareSize).floor().clamp(0, 7);
                            final r = _state.boardFlipped ? 7 - row : row;
                            final c = _state.boardFlipped ? 7 - col : col;
                            final toSq = _game.squareToAlgebraic(r, c);
                            final fromSq = _arrowDragFrom!;
                            _arrowDragFrom = null;

                            setState(() {
                              if (fromSq == toSq) {
                                // Same square — toggle highlight
                                _boardAnnotations.addHighlight(
                                  BoardHighlight(square: fromSq, color: Colors.red),
                                );
                              } else {
                                // Different squares — draw arrow
                                _boardAnnotations.addArrow(
                                  BoardArrow(from: fromSq, to: toSq, color: Colors.green),
                                );
                              }
                            });
                          },
                          child: ChessBoard(
                            board: _game.board,
                            whiteToMove: _game.whiteToMove,
                            squareToAlgebraic: _game.squareToAlgebraic,
                            onMove: _onMove,
                            onSquareTap: _onSquareTap,
                            selectedRow: _state.selectedRow,
                            selectedCol: _state.selectedCol,
                            validMoves: _state.validMoves,
                            hintMove: _state.hintMove,
                            isCheck: _game.inCheck,
                            animationDurationMs: _state.animationDurationMs,
                            flipped: _state.boardFlipped,
                            pieceTheme: _state.pieceTheme,
                            lastMoveUci: _state.lastMoveUci,
                            annotations: _mergedAnnotations,
                            repaintBoundaryKey: _boardKey,
                            isCapture: _state.isLastMoveCapture,
                            isCheckmate: _game.isGameOver && _game.gameOverReason == 'Checkmate',
                            solidBlackPieces: _solidBlackPieces,
                            boardColorTheme: getBoardTheme(_prefs.boardTheme),
                            blindfold: _prefs.blindfold,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Our captured pieces (pieces opponent captured from us)
          ListenableBuilder(
            listenable: _game,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CapturedPieces(
                board: _game.board,
                color: _state.playAsBlack ? PieceColor.black : PieceColor.white,
              ),
            ),
          ),
          // Player clock (bottom)
          if (_clock != null)
            ListenableBuilder(
              listenable: _clock!,
              builder: (context, _) => _buildClockBar(
                _state.playAsBlack ? _clock!.black : _clock!.white,
                isOpponent: false,
              ),
            ),
          // Analysis panel (compact toggle)
          if (_state.analysisExpanded)
            _buildAnalysisPanel(),
          // Move history at bottom
          ListenableBuilder(
            listenable: _game,
            builder: (context, _) => _buildMoveHistory(),
          ),
        ],
      ),
    ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.keyZ ||
        key == LogicalKeyboardKey.arrowLeft) {
      if (_state.allowUndo && !_state.isThinking) _undoMove();
    } else if (key == LogicalKeyboardKey.keyY ||
        key == LogicalKeyboardKey.arrowRight) {
      if (_state.allowUndo && !_state.isThinking && _game.canRedo) {
        _game.redoMove();
        setState(() => _state = _state.copyWith(statusMessage: 'Position restored', hintMove: null));
      }
    } else if (key == LogicalKeyboardKey.keyH ||
        key == LogicalKeyboardKey.space) {
      if (_isPlayerTurn && !_state.isThinking) _getHint();
    } else if (key == LogicalKeyboardKey.keyN) {
      _confirmNewGame();
    } else if (key == LogicalKeyboardKey.keyF) {
      setState(() =>
          _state = _state.copyWith(boardFlipped: !_state.boardFlipped));
    } else if (key == LogicalKeyboardKey.keyA) {
      _toggleAnalysis();
    }
  }

  Widget _buildMoveHistory() {
    final mainLine = _game.tree.mainLine;
    final currentNode = _game.currentNode;

    return GestureDetector(
      onLongPress: _game.hasMoves ? () {
        _exportPgn();
      } : null,
      child: Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: mainLine.isEmpty
          ? Center(
              child: Text(AppLocalizations.of(context)?.noMovesYet ?? 'No moves yet',
                  style: TextStyle(color: Colors.grey, fontSize: 12)))
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: (mainLine.length / 2).ceil(),
              itemBuilder: (context, index) {
                final moveNum = index + 1;
                final whiteIdx = index * 2;
                final blackIdx = index * 2 + 1;
                final whiteNode = mainLine[whiteIdx];
                final blackNode = blackIdx < mainLine.length
                    ? mainLine[blackIdx]
                    : null;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(children: [
                    Text('$moveNum.',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: Colors.grey.shade600)),
                    const SizedBox(width: 4),
                    _buildMoveChip(whiteNode, currentNode),
                    if (blackNode != null) ...[
                      const SizedBox(width: 4),
                      _buildMoveChip(blackNode, currentNode, isBlack: true),
                    ],
                  ]),
                );
              },
            ),
    ),
    );
  }

  NotationStyle get _notationStyle =>
      _prefs.notationStyle == 'figurine' ? NotationStyle.figurine : NotationStyle.algebraic;

  Widget _buildMoveChip(GameTreeNode node, GameTreeNode currentNode, {bool isBlack = false}) {
    final isCurrent = node == currentNode;
    final hasVariations = node.parent?.hasVariations ?? false;
    final rawSan = node.san ?? node.move ?? '?';
    final san = formatNotation(rawSan, _notationStyle);

    return GestureDetector(
      onTap: () {
        _game.goToNode(node);
        setState(() {
          _state = _state.copyWith(
            statusMessage: 'Position at move ${node.moveNumber}',
            hintMove: null,
            currentBestMove: null,
          );
        });
        _pvLines.clear();
        _evalNotifier.value = node.eval;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: isCurrent
            ? BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.blue, width: 1),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              san,
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
                color: isBlack && !isCurrent ? Colors.grey.shade700 : null,
              ),
            ),
            if (hasVariations)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(Icons.call_split, size: 10, color: Colors.grey.shade500),
              ),
          ],
        ),
      ),
    );
  }

}
