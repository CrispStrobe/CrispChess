/// Monte Carlo Tree Search (MCTS) for lc0-style neural network chess.
///
/// Uses PUCT (Predictor + Upper Confidence bound for Trees) to balance
/// exploration and exploitation, guided by the neural network's policy
/// and value outputs.
library;

import 'dart:collection';
import 'dart:math';

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

  /// Set when the game ends here, from the side-to-move's point of view:
  /// -1 for being mated, 0 for a draw. Negated into [backpropagate].
  double? terminalValue;

  MctsNode({this.move, this.parent, this.prior = 0.0});

  /// Mean value Q = W / N (from this node's perspective).
  double get q => visits > 0 ? totalValue / visits : 0.0;

  /// PUCT score for selection: Q + c_puct * P * sqrt(parent_N) / (1 + N)
  ///
  /// The parent's visit count is floored at one. The root has not been visited
  /// when the first simulation picks a move from it, and `sqrt(0)` cancels the
  /// exploration term for *every* child at once — so they all score zero, the
  /// first one generated wins the comparison, and the network's policy is
  /// ignored precisely on the smallest budgets, where it is the only thing
  /// there is to go on. Against lc0 at one node this agreed on 4 positions
  /// out of 40, answering a2a3 from the start position; at ten nodes, where
  /// the flaw has washed out, it agreed on 37.
  double puctScore(double cpuct) {
    final parentVisits = max(1, parent?.visits ?? 1);
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
  ///
  /// Ties break on the network's prior. Without that, children that were never
  /// visited all look equal and the *first* one generated wins — which is a
  /// move ordered by the move generator, not by chess.
  MctsNode? bestChild() {
    if (children.isEmpty) return null;
    MctsNode? best;
    for (final child in children) {
      if (best == null ||
          child.visits > best.visits ||
          (child.visits == best.visits && child.prior > best.prior)) {
        best = child;
      }
    }
    return best;
  }

  /// Backpropagate a value up the tree.
  ///
  /// [value] is from the perspective of the player who *made the move into this
  /// node* — the opposite of the side to move here. That matches what
  /// [puctScore] reads: a parent compares its children by their `q`, and it
  /// wants "how good is this move for me". A network value, or a terminal
  /// score, comes from the side to move at the node, so it enters negated.
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
///
/// [historyFens] is the game that led to [fen], oldest first and excluding
/// [fen] itself. Lc0-style networks read the previous plies as input planes,
/// so a leaf evaluated with the root's history is being asked about a
/// different game from the one it is in.
typedef NnEvaluator = Future<NnEval> Function(
    String fen, List<String> legalMoves, List<String> historyFens);

/// A bounded least-recently-used cache for network evaluations.
///
/// MCTS trees are deliberately rebuilt for each move, but the opponent often
/// chooses a reply that the previous search already evaluated. Keeping the
/// network result lets the next search spend that forward pass on a new leaf.
/// The complete history is part of the key because repetition and the seven
/// historical board slots are network inputs, not merely search metadata.
class NnEvalCache {
  final int capacity;
  final LinkedHashMap<String, Future<NnEval>> _entries = LinkedHashMap();

  NnEvalCache({this.capacity = 512}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  int get length => _entries.length;

  Future<NnEval> evaluate(
    String fen,
    List<String> legalMoves,
    List<String> historyFens,
    NnEvaluator evaluator,
  ) {
    final key = _key(fen, legalMoves, historyFens);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached; // Touch: newest entries are evicted last.
      return cached;
    }

    late final Future<NnEval> result;
    result = Future.sync(() => evaluator(fen, legalMoves, historyFens)).then(
      (value) => value,
      onError: (Object error, StackTrace stackTrace) {
        // A transient inference failure must not poison future searches.
        if (identical(_entries[key], result)) _entries.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _entries[key] = result;
    if (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return result;
  }

  void clear() => _entries.clear();

  String _key(String fen, List<String> legalMoves, List<String> historyFens) {
    final buffer = StringBuffer();
    for (final historyFen in historyFens) {
      buffer
        ..write(historyFen)
        ..write('\n');
    }
    buffer
      ..write(fen)
      ..write('\n')
      ..writeAll(legalMoves, ',');
    return buffer.toString();
  }
}

/// A position reached by playing [moves] from the root.
class MctsPosition {
  final String fen;
  final List<String> legalMoves;

  /// The positions before this one, oldest first: the root's own history plus
  /// every position along the line that reached it. Only a resolver can
  /// produce these, because only it replays the moves.
  final List<String> historyFens;

  /// Set when the game ends here, from the side-to-move's point of view:
  /// -1 for checkmate (they are mated), 0 for a draw.
  final double? terminalValue;

  const MctsPosition({
    required this.fen,
    required this.legalMoves,
    this.historyFens = const [],
    this.terminalValue,
  });
}

/// Resolves the position a line of play reaches, so the search can evaluate
/// nodes other than the root.
///
/// Without one, [mctsSearch] can only ever score the root — see the note on
/// [mctsSearch] itself.
typedef MctsPositionResolver = MctsPosition Function(List<String> moves);

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

/// Run MCTS and return the best move (UCI string).
///
/// [fen] — current position FEN
/// [legalMoves] — its legal UCI moves
/// [evaluate] — the neural network
/// [positionAt] — resolves the position a line reaches, so leaves can be
///   evaluated. Without it this returns the network's top policy move, which
///   is the honest answer when there is no way to look further.
/// [config] — search parameters
///
/// This used to expand only the root and then run up to [MctsConfig.maxNodes]
/// iterations that scored every leaf with the *root's* value, scaled by depth.
/// That is not a search: the visit counts it produced carried no information
/// the policy did not already have, and the iterations were pure cost. With a
/// resolver each simulation now evaluates the position it actually reached.
///
/// One evaluation per simulation is the budget that matters — Lc0's is about
/// 70ms — so [MctsConfig.maxTime] usually binds long before
/// [MctsConfig.maxNodes]. Note also that Maia weights are trained to imitate
/// human choices, so searching on top of them makes play stronger but less
/// human, which is the opposite of why one picks Maia.
Future<String> mctsSearch({
  required String fen,
  required List<String> legalMoves,
  required NnEvaluator evaluate,
  List<String> historyFens = const [],
  MctsPositionResolver? positionAt,
  MctsConfig config = const MctsConfig(),
}) async {
  if (legalMoves.isEmpty) throw StateError('No legal moves');
  if (legalMoves.length == 1) return legalMoves.first;

  final root = MctsNode();
  final stopwatch = Stopwatch()..start();

  // Initial expansion of root
  final rootEval = await evaluate(fen, legalMoves, historyFens);
  for (final move in legalMoves) {
    final prior = rootEval.policy[move] ?? (1.0 / legalMoves.length);
    root.children.add(MctsNode(move: move, parent: root, prior: prior));
  }
  root.expanded = true;

  // MCTS iterations
  // Without a resolver there is no position to evaluate below the root, so
  // there is no tree to build: return the network's own preference rather than
  // spending the budget looking busy.
  if (positionAt == null) return root.bestChild()?.move ?? legalMoves.first;

  for (int i = 0; i < config.maxNodes; i++) {
    // Each simulation costs a network evaluation, so the clock is checked
    // before starting one rather than after.
    if (stopwatch.elapsed > config.maxTime) break;

    // Select: follow PUCT to a leaf.
    var node = root;
    while (node.expanded && node.children.isNotEmpty) {
      node = node.selectChild(config.cpuct)!;
    }

    if (node.terminalValue != null) {
      node.backpropagate(-node.terminalValue!);
      continue;
    }

    // Expand: resolve the leaf's position and evaluate it.
    final position = positionAt(node.movePath());
    if (position.terminalValue != null) {
      node.terminalValue = position.terminalValue;
      node.expanded = true;
      node.backpropagate(-position.terminalValue!);
      continue;
    }

    final leafEval =
        await evaluate(position.fen, position.legalMoves, position.historyFens);
    for (final move in position.legalMoves) {
      final prior = leafEval.policy[move] ?? (1.0 / position.legalMoves.length);
      node.children.add(MctsNode(move: move, parent: node, prior: prior));
    }
    node.expanded = true;

    // The value is from the leaf's side to move, and backpropagate flips at
    // every step, so it enters negated.
    node.backpropagate(-leafEval.value);
  }

  // Pick best move (most visited, prior as the tie-break).
  //
  // The root evaluation above is the expensive part — one network forward pass
  // — so on a tight budget, or the first (cold) call of a session, the loop can
  // run no simulations at all. Every child then has zero visits, and before the
  // tie-break was added this returned `children.first`: the first move out of
  // the move generator, a2a3 from the starting position, no matter what the
  // network thought. Falling back to the highest prior returns the network's
  // own choice, which is the best answer available without simulations.
  final best = root.bestChild();
  return best?.move ?? legalMoves.first;
}
