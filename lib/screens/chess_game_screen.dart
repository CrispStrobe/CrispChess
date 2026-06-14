import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../chess/chess_clock.dart';
import '../chess/chess_game.dart';
import '../chess/game_state.dart';
import '../chess/move_analyzer.dart';
import '../engines/chess_engine.dart';
import '../engines/dart_engine.dart';
import '../engines/engine_factory.dart';
import '../services/engine_service.dart';
import '../services/sound_service.dart';
import '../widgets/captured_pieces.dart';
import '../widgets/chess_board.dart';
import '../widgets/horizontal_evaluation_bar.dart';
import 'about_screen.dart';
import 'settings_screen.dart';

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
  final SoundService _sound = SoundService();

  final ValueNotifier<double?> _evalNotifier = ValueNotifier<double?>(null);
  final ValueNotifier<int> _depthNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _game = ChessGame();
    _engineService = EngineService(DartEngine());
    _initializeEngine();
  }

  void _initializeEngine() {
    debugPrint('[CrispChess] Initializing engine...');
    _eventSubscription?.cancel();
    _eventSubscription = _engineService.events.listen(_onEngineEvent);
    _engineService.initialize();
  }

  void _onEngineEvent(EngineEvent event) {
    if (!mounted) return;
    debugPrint('[CrispChess] Event: ${event.runtimeType}');
    switch (event) {
      case EvalUpdateEvent(:final eval, :final depth, :final bestMove):
        _evalNotifier.value = eval;
        _depthNotifier.value = depth;
        if (bestMove.isNotEmpty) {
          _game.updateEvaluation(eval, bestMove, depth);
          setState(() {
            _state = _state.copyWith(currentBestMove: bestMove);
          });
        }
      case BestMoveEvent(:final move):
        debugPrint('[CrispChess] Best move: $move');
        if (_state.waitingForHint) {
          _handleHintResponse(move);
        } else {
          // Don't guard on isThinking — the StateChangeEvent(ready) may
          // arrive before BestMoveEvent due to the stateNotifier firing
          // synchronously inside bestMove(), while BestMoveEvent is added
          // to the stream after bestMove() returns.
          _makeEngineMove(move);
        }
      case StateChangeEvent(:final state):
        debugPrint('[CrispChess] Engine state: $state');
        if (state == EngineState.ready) {
          setState(() {
            _state = _state.copyWith(
              statusMessage: _state.isThinking
                  ? 'Your turn ($_playerColorName)'
                  : '${_engineService.engineName} ready',
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
    if (_game.makeMove(uciMove)) {
      _playMoveSound(uciMove);
      _clock?.switchTurn();
      setState(() {
        _state = _state.copyWith(
          lastMoveUci: uciMove,
          lastMove: '${_engineService.engineName}: $uciMove',
          statusMessage:
              _game.isGameOver ? 'Game Over!' : 'Your turn ($_playerColorName)',
          isThinking: false,
        );
      });
      if (_game.isGameOver) {
        _clock?.pause();
        _showGameOverDialog();
      } else if (_state.analysisExpanded) {
        _engineService.requestAnalysis(
          _game.positionCommand,
          depth: _state.hintDepth,
        );
      }
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

  void _onMove(int fromRow, int fromCol, int toRow, int toCol) {
    debugPrint('[CrispChess] _onMove($fromRow,$fromCol -> $toRow,$toCol) whiteToMove=${_game.whiteToMove} isThinking=${_state.isThinking} engineState=${_engineService.state}');
    if (!_isPlayerTurn || _state.isThinking) return;

    final uciMove = _game.squareToAlgebraic(fromRow, fromCol) +
        _game.squareToAlgebraic(toRow, toCol);

    if (_game.makeMove(uciMove)) {
      _playMoveSound(uciMove);
      _clock?.switchTurn();
      setState(() {
        _state = _state.copyWith(lastMove: 'You: $uciMove', hintMove: null, lastMoveUci: uciMove);

        if (_game.isGameOver) {
          _clock?.pause();
          _sound.play(ChessSound.gameEnd);
          _state = _state.copyWith(
            isThinking: false,
            statusMessage: 'Game Over: ${_game.gameOverReason}',
          );
          _showGameOverDialog();
        } else {
          _state = _state.copyWith(
            statusMessage: '${_engineService.engineName} is thinking...',
            isThinking: true,
          );
          _requestEngineMove();
        }
      });
    } else {
      _sound.play(ChessSound.illegal);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Illegal Move!'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(milliseconds: 700),
        ),
      );
    }
  }

  void _requestEngineMove() {
    debugPrint('[CrispChess] Requesting engine move: skill=${_state.strengthLevel}');
    _engineService.requestMove(
      _game.positionCommand,
      skillLevel: _state.strengthLevel,
    );
  }

  void _getHint() {
    if (_engineService.state != EngineState.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Engine not ready')),
      );
      return;
    }
    if (!_isPlayerTurn || _state.isThinking) return;

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
    if (_game.moveHistory.length < 2) return;
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
    _clock?.dispose();
    if (!_state.timeControl.isUnlimited) {
      _clock = ChessClock(timeControl: _state.timeControl);
      _clock!.addListener(() { if (mounted) setState(() {}); });
      _clock!.start();
    } else {
      _clock = null;
    }
    setState(() {
      _game.reset();
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

  void _showGameOverDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final winner = _game.winner;
        return AlertDialog(
          title: Text(_game.gameOverReason),
          content: Text(
            winner != null
                ? '$winner wins the game!'
                : 'The game ended in a draw.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _newGame();
              },
              child: const Text('New Game'),
            ),
          ],
        );
      },
    );
  }

  String _maia3Variant = '5m';

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
          timeControl: _state.timeControl,
        ),
      ),
    );
    if (result != null) {
      final newPlayAsBlack = result['playAsBlack'] as bool? ?? false;
      final colorChanged = newPlayAsBlack != _state.playAsBlack;
      final newVariant = result['maia3Variant'] as String? ?? '5m';

      setState(() {
        _state = _state.copyWith(
          strengthLevel: result['strengthLevel']! as int,
          hintDepth: result['hintDepth']! as int,
          showValidMoves: result['showValidMoves']! as bool,
          animationSpeed: result['animationSpeed'] as int? ?? 2,
          timeControl: result['timeControl'] as TimeControl? ?? TimeControl.unlimited,
          playAsBlack: newPlayAsBlack,
          pieceTheme: result['pieceTheme'] as String? ?? 'chessnut',
        );
      });

      // If color changed, start a new game
      if (colorChanged) {
        _newGame();
      }

      // Switch engine if changed (or variant changed for Maia)
      final selectedEngine = result['engine'] as String?;
      final variantChanged = newVariant != _maia3Variant;
      _maia3Variant = newVariant;

      if (selectedEngine != null &&
          (selectedEngine != _engineService.engineName || variantChanged)) {
        debugPrint('[CrispChess] Switching engine to $selectedEngine (variant: $_maia3Variant)');
        final elo = 800 + (_state.strengthLevel * 60);
        final newEngine = createEngine(
          selectedEngine,
          playerElo: elo,
          maia3Variant: _maia3Variant,
        );
        _engineService.switchEngine(newEngine);
      }
    }
  }

  Color _engineStatusColor() {
    return switch (_engineService.state) {
      EngineState.ready => Colors.green,
      EngineState.initializing => Colors.orange,
      EngineState.thinking => Colors.blue,
      EngineState.error => Colors.red,
      _ => Colors.grey,
    };
  }

  String _engineStatusText() {
    return switch (_engineService.state) {
      EngineState.ready => _engineService.engineName,
      EngineState.initializing => 'Starting...',
      EngineState.thinking => 'Thinking...',
      EngineState.error => 'Error',
      _ => 'Offline',
    };
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _evalNotifier.dispose();
    _depthNotifier.dispose();
    _clock?.dispose();
    _sound.dispose();
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
    final hasAnnotations = _game.annotations.isNotEmpty;
    final annotations = _game.annotations;
    final lastAnnotation = annotations.isNotEmpty ? annotations.last : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
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
                  Icon(Icons.analytics, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text('Analysis',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.blue.shade700)),
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
                              ? Colors.blue.shade100
                              : Colors.orange.shade100,
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
                                ? Colors.blue.shade700
                                : Colors.orange.shade700,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
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

          // Best move + refresh
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _state.currentBestMove != null
                        ? 'Best: ${_state.currentBestMove}'
                        : _engineService.state == EngineState.ready
                            ? 'Tap refresh to analyze'
                            : 'Engine loading...',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Re-analyze',
                  onPressed: (_state.isThinking ||
                          _engineService.state != EngineState.ready)
                      ? null
                      : () {
                          _engineService.requestAnalysis(
                            _game.positionCommand,
                            depth: _state.hintDepth,
                          );
                        },
                ),
              ],
            ),
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
                    if (lastAnnotation.getFullDescription().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
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

  Color _annotationColor(MoveQuality q) {
    return switch (q) {
      MoveQuality.brilliant => Colors.cyan.shade50,
      MoveQuality.good => Colors.green.shade50,
      MoveQuality.interesting => Colors.blue.shade50,
      MoveQuality.neutral => Colors.grey.shade100,
      MoveQuality.dubious => Colors.yellow.shade50,
      MoveQuality.mistake => Colors.orange.shade50,
      MoveQuality.blunder => Colors.red.shade50,
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
        const SnackBar(content: Text('PGN copied to clipboard')),
      );
    }
  }

  Future<void> _importPgn() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
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
          const SnackBar(content: Text('PGN loaded')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid PGN'),
            backgroundColor: Colors.red,
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        : '${_engineService.engineName} · Lv ${_state.strengthLevel}',
                    style: TextStyle(
                      fontSize: 10,
                      color: _engineService.state == EngineState.initializing
                          ? Colors.orange.shade700
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
                    color: eval >= 0 ? Colors.blue.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    eval >= 0 ? '+${eval.toStringAsFixed(1)}' : eval.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold,
                      color: eval >= 0 ? Colors.blue.shade700 : Colors.orange.shade700,
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
              tooltip: 'Abort',
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
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            tooltip: 'Undo',
            onPressed: _state.isThinking ? null : _undoMove,
          ),
          IconButton(
            icon: const Icon(Icons.lightbulb_outline, size: 20),
            tooltip: 'Hint',
            onPressed: (!_isPlayerTurn || _state.isThinking) ? null : _getHint,
          ),
          IconButton(
            icon: Icon(
              _state.analysisExpanded ? Icons.analytics : Icons.analytics_outlined,
              size: 20,
              color: _state.analysisExpanded ? Colors.blue : null,
            ),
            tooltip: 'Analyze',
            onPressed: _toggleAnalysis,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _newGame();
                case 'export_pgn':
                  _exportPgn();
                case 'import_pgn':
                  _importPgn();
                case 'flip':
                  setState(() {
                    _state = _state.copyWith(boardFlipped: !_state.boardFlipped);
                  });
                case 'settings':
                  _openSettings();
                case 'about':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AboutScreen()));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: ListTile(
                leading: Icon(Icons.refresh), title: Text('New Game'),
                contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'export_pgn', child: ListTile(
                leading: Icon(Icons.copy), title: Text('Copy PGN'),
                contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'import_pgn', child: ListTile(
                leading: Icon(Icons.paste), title: Text('Paste PGN'),
                contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'flip', child: ListTile(
                leading: Icon(Icons.swap_vert), title: Text('Flip Board'),
                contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'settings', child: ListTile(
                leading: Icon(Icons.settings), title: Text('Settings'),
                contentPadding: EdgeInsets.zero, dense: true)),
              const PopupMenuItem(value: 'about', child: ListTile(
                leading: Icon(Icons.info_outline), title: Text('About'),
                contentPadding: EdgeInsets.zero, dense: true)),
            ],
          ),
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
            _buildClockBar(
              _state.playAsBlack ? _clock!.white : _clock!.black,
              isOpponent: true,
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
            _buildClockBar(
              _state.playAsBlack ? _clock!.black : _clock!.white,
              isOpponent: false,
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
    );
  }

  Widget _buildMoveHistory() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: _game.moveHistory.isEmpty
          ? const Center(
              child: Text('No moves yet',
                  style: TextStyle(color: Colors.grey, fontSize: 12)))
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: (_game.moveHistory.length / 2).ceil(),
              itemBuilder: (context, index) {
                final moveNum = index + 1;
                final whiteMove = _game.moveHistory[index * 2];
                final blackMove =
                    index * 2 + 1 < _game.moveHistory.length
                        ? _game.moveHistory[index * 2 + 1]
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
                    Text(whiteMove,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11)),
                    if (blackMove != null) ...[
                      const SizedBox(width: 4),
                      Text(blackMove,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade700)),
                    ],
                  ]),
                );
              },
            ),
    );
  }

}
