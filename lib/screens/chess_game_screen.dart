import 'dart:async';
import 'package:flutter/material.dart';
import '../chess/chess_game.dart';
import '../chess/game_state.dart';
import '../engines/chess_engine.dart';
import '../engines/dart_engine.dart';
import '../services/engine_service.dart';
import '../widgets/chess_board.dart';
import '../widgets/horizontal_evaluation_bar.dart';
import '../engines/frozenight_engine.dart';
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
        } else if (_state.isThinking) {
          _makeEngineMove(move);
        }
      case StateChangeEvent(:final state):
        debugPrint('[CrispChess] Engine state: $state');
        if (state == EngineState.ready) {
          setState(() {
            _state = _state.copyWith(statusMessage: 'Your turn (White)');
          });
        } else if (state == EngineState.error) {
          setState(() {
            _state = _state.copyWith(
              statusMessage: 'Engine error',
              isThinking: false,
            );
          });
        }
      case EngineErrorEvent(:final message):
        debugPrint('[CrispChess] Engine error: $message');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
          setState(() {
            _state = _state.copyWith(isThinking: false);
          });
        }
    }
  }

  List<String> _getValidMovesForSquare(int row, int col) {
    final square = _game.squareToAlgebraic(row, col);
    final piece = _game.board[row][col];
    if (piece == null || piece.color != PieceColor.white) return [];
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
      setState(() {
        _state = _state.copyWith(
          lastMove: '${_engineService.engineName}: $uciMove',
          statusMessage:
              _game.isGameOver ? 'Game Over!' : 'Your turn (White)',
          isThinking: false,
        );
      });
      if (_game.isGameOver) _showGameOverDialog();
    }
  }

  void _onSquareTap(int row, int col) {
    if (!_game.whiteToMove || _state.isThinking) return;

    final piece = _game.board[row][col];

    if (_state.selectedRow != null && _state.selectedCol != null) {
      _onMove(_state.selectedRow!, _state.selectedCol!, row, col);
      setState(() {
        _state = _state.copyWith(
          selectedRow: null,
          selectedCol: null,
          validMoves: const [],
        );
      });
    } else if (piece != null && piece.color == PieceColor.white) {
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
    if (!_game.whiteToMove || _state.isThinking) return;

    if (_engineService.state != EngineState.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Engine not ready. Please wait.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final uciMove = _game.squareToAlgebraic(fromRow, fromCol) +
        _game.squareToAlgebraic(toRow, toCol);

    if (_game.makeMove(uciMove)) {
      setState(() {
        _state = _state.copyWith(lastMove: 'You: $uciMove', hintMove: null);

        if (_game.isGameOver) {
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
    debugPrint('[CrispChess] Requesting engine move: depth=${3 + _state.strengthLevel} skill=${_state.strengthLevel}');
    _engineService.requestMove(
      _game.positionCommand,
      depth: 3 + _state.strengthLevel, // depth 3-23
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
    if (!_game.whiteToMove || _state.isThinking) return;

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
        statusMessage: 'Your turn (White)',
        hintMove: null,
        isThinking: false,
      );
    });
  }

  void _newGame() {
    _evalNotifier.value = null;
    _depthNotifier.value = 0;
    setState(() {
      _game.reset();
      _state = _state.copyWith(
        statusMessage: 'Your turn (White)',
        isThinking: false,
        hintMove: null,
        lastMove: '',
        currentBestMove: null,
      );
    });
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

  Future<void> _openSettings() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          strengthLevel: _state.strengthLevel,
          hintDepth: _state.hintDepth,
          currentEngine: _engineService.engineName,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _state = _state.copyWith(
          strengthLevel: result['strengthLevel']! as int,
          hintDepth: result['hintDepth']! as int,
          showValidMoves: result['showValidMoves']! as bool,
          animateMoves: result['animateMoves']! as bool,
        );
      });

      // Switch engine if changed
      final selectedEngine = result['engine'] as String?;
      if (selectedEngine != null &&
          selectedEngine != _engineService.engineName) {
        debugPrint('[CrispChess] Switching engine to $selectedEngine');
        ChessEngine newEngine;
        switch (selectedEngine) {
          case 'Frozenight':
            newEngine = FrozenightEngine();
          default:
            newEngine = DartEngine();
        }
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
    _game.dispose();
    _engineService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CrispChess'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCompactHeader(),
          _buildAnalysisPanel(),
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
                          animateMoves: _state.animateMoves,
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: _game,
            builder: (context, _) => _buildMoveHistory(),
          ),
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _state.isThinking
            ? Colors.orange.shade100
            : Colors.blue.shade100,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Icon(
            _state.isThinking ? Icons.hourglass_empty : Icons.check_circle,
            size: 20,
            color: _state.isThinking ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_state.statusMessage,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                if (_state.lastMove.isNotEmpty)
                  Text(_state.lastMove,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _engineStatusColor(),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _engineStatusText(),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
          if (_state.isThinking)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalysisPanel() {
    if (_evalNotifier.value == null && _game.annotations.isEmpty) {
      return const SizedBox.shrink();
    }
    final annotations = _game.annotations;
    final playerAnn =
        annotations.length >= 2 ? annotations[annotations.length - 2] : null;
    final engineAnn = annotations.isNotEmpty ? annotations.last : null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _state = _state.copyWith(
                analysisExpanded: !_state.analysisExpanded)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  if (!_state.analysisExpanded)
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
                                    : Colors.orange.shade700),
                          ),
                        );
                      },
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    _state.analysisExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_state.analysisExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ValueListenableBuilder<double?>(
                valueListenable: _evalNotifier,
                builder: (context, eval, _) {
                  return ValueListenableBuilder<int>(
                    valueListenable: _depthNotifier,
                    builder: (context, depth, _) {
                      return HorizontalEvaluationBar(
                          evaluation: eval, depth: depth);
                    },
                  );
                },
              ),
            ),
            if (playerAnn != null || engineAnn != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (playerAnn != null)
                      Expanded(
                        child: _annotationCard(
                            'You', playerAnn, Colors.blue, Icons.person),
                      ),
                    const SizedBox(width: 8),
                    if (engineAnn != null)
                      Expanded(
                        child: _annotationCard('Engine', engineAnn,
                            Colors.grey, Icons.computer),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _annotationCard(String label, dynamic ann, MaterialColor color,
      IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: color.shade700),
            const SizedBox(width: 4),
            Expanded(
              child: Text('$label: ${ann.move}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: color.shade700)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(ann.getFullDescription(),
              style: const TextStyle(fontSize: 10)),
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

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _btn(Icons.refresh, 'New', _newGame),
          _btn(Icons.undo, 'Undo', _state.isThinking ? null : _undoMove),
          _btn(Icons.lightbulb_outline, 'Hint',
              (!_game.whiteToMove || _state.isThinking) ? null : _getHint),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback? onPressed) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}
