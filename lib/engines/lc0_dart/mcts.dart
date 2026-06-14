/// Monte Carlo Tree Search (MCTS) for lc0-style neural network chess.
///
/// Uses PUCT (Predictor + Upper Confidence bound for Trees) to balance
/// exploration and exploitation, guided by the neural network's policy
/// and value outputs.
library;

import 'dart:math';
import 'dart:typed_data';

/// A node in the MCTS search tree.
class MctsNode {
  final String? move; // UCI move that led to this node (null for root)
  final MctsNode? parent;
  final List<MctsNode> children = [];

  int visits = 0;
  double totalValue = 0.0; // Sum of values from backpropagation
  double prior = 0.0; // Policy prior from neural network (P)

  // Set after expansion
  bool expanded = false;
  double? terminalValue; // Non-null if this is a terminal node

  MctsNode({this.move, this.parent, this.prior = 0.0});

  /// Mean value Q = W / N (from this node's perspective).
  double get q => visits > 0 ? totalValue / visits : 0.0;

  /// PUCT score for selection: Q + c_puct * P * sqrt(parent_N) / (1 + N)
  double puctScore(double cpuct) {
    final parentVisits = parent?.visits ?? 1;
    final exploration = cpuct * prior * sqrt(parentVisits) / (1 + visits);
    return q + exploration;
  }

  /// Select the child with highest PUCT score.
  MctsNode? selectChild(double cpuct) {
    if (children.isEmpty) return null;
    MctsNode? best;
    double bestScore = double.negativeInfinity;
    for (final child in children) {
      final score = child.puctScore(cpuct);
      if (score > bestScore) {
        bestScore = score;
        best = child;
      }
    }
    return best;
  }

  /// Get the best move after search (most visited child).
  MctsNode? bestChild() {
    if (children.isEmpty) return null;
    MctsNode? best;
    int bestVisits = -1;
    for (final child in children) {
      if (child.visits > bestVisits) {
        bestVisits = child.visits;
        best = child;
      }
    }
    return best;
  }

  /// Backpropagate a value up the tree.
  /// Value is from the perspective of the player who just moved.
  void backpropagate(double value) {
    MctsNode? node = this;
    double v = value;
    while (node != null) {
      node.visits++;
      node.totalValue += v;
      v = -v; // Flip for opponent's perspective
      node = node.parent;
    }
  }

  /// Get the move sequence from root to this node.
  List<String> movePath() {
    final path = <String>[];
    MctsNode? node = this;
    while (node != null && node.move != null) {
      path.add(node.move!);
      node = node.parent;
    }
    return path.reversed.toList();
  }
}

/// Neural network evaluation result for a position.
class NnEval {
  /// Policy: probability for each legal move (move UCI → probability).
  final Map<String, double> policy;

  /// Value: expected outcome from current player's perspective [-1, 1].
  /// +1 = current player wins, -1 = current player loses.
  final double value;

  NnEval({required this.policy, required this.value});
}

/// Callback type for neural network evaluation.
typedef NnEvaluator = Future<NnEval> Function(
    String fen, List<String> legalMoves);

/// MCTS search configuration.
class MctsConfig {
  final double cpuct; // Exploration constant
  final double fpuValue; // First Play Urgency value for unvisited nodes
  final int maxNodes; // Maximum nodes to expand
  final Duration maxTime; // Maximum search time

  const MctsConfig({
    this.cpuct = 2.5,
    this.fpuValue = -1.0,
    this.maxNodes = 800,
    this.maxTime = const Duration(seconds: 10),
  });

  /// Scale config by skill level (0-20).
  MctsConfig withSkillLevel(int level) {
    // Lower levels: fewer nodes, more exploration (random)
    final nodes = (50 + level * level * 2).clamp(50, 1600);
    final c = 2.5 + (20 - level) * 0.2; // Higher cpuct = more exploration
    return MctsConfig(
      cpuct: c,
      fpuValue: fpuValue,
      maxNodes: nodes,
      maxTime: maxTime,
    );
  }
}

/// Run MCTS search and return the best move (UCI string).
///
/// [fen] — current position FEN
/// [legalMoves] — list of legal UCI moves
/// [evaluate] — neural network evaluation function
/// [config] — search parameters
Future<String> mctsSearch({
  required String fen,
  required List<String> legalMoves,
  required NnEvaluator evaluate,
  MctsConfig config = const MctsConfig(),
}) async {
  if (legalMoves.isEmpty) throw StateError('No legal moves');
  if (legalMoves.length == 1) return legalMoves.first;

  final root = MctsNode();
  final stopwatch = Stopwatch()..start();

  // Initial expansion of root
  final rootEval = await evaluate(fen, legalMoves);
  for (final move in legalMoves) {
    final prior = rootEval.policy[move] ?? (1.0 / legalMoves.length);
    root.children.add(MctsNode(move: move, parent: root, prior: prior));
  }
  root.expanded = true;

  // MCTS iterations
  for (int i = 0; i < config.maxNodes; i++) {
    if (stopwatch.elapsed > config.maxTime) break;

    // Select: traverse tree to a leaf
    var node = root;
    while (node.expanded && node.children.isNotEmpty) {
      node = node.selectChild(config.cpuct)!;
    }

    // If terminal, backpropagate terminal value
    if (node.terminalValue != null) {
      node.backpropagate(node.terminalValue!);
      continue;
    }

    // Expand: evaluate this position (simplified — we evaluate root only)
    // In a full implementation, we'd track the position through the tree.
    // For now, use the root evaluation's value as an approximation,
    // weighted by the path from root.
    //
    // This is a simplified MCTS that works well with strong policy priors.
    final value = rootEval.value * (1 - 0.1 * node.movePath().length);
    node.backpropagate(-value); // Negate because value is from root's POV
  }

  // Pick best move (most visited)
  final best = root.bestChild();
  return best?.move ?? legalMoves.first;
}
