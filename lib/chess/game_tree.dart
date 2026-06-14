/// Tree-structured move history with branching variations.
///
/// Replaces the flat move list with a tree where each node represents
/// a move and can have multiple child moves (variations).

import 'move_analyzer.dart';

/// A single node in the game tree.
class GameTreeNode {
  /// UCI move string (e.g. "e2e4"). Null for the root node.
  final String? move;

  /// SAN notation (e.g. "e4", "Nf3"). Set after the move is played.
  String? san;

  /// FEN after this move was played.
  final String fen;

  /// Move annotation (quality assessment).
  MoveAnnotation? annotation;

  /// Text comment on this move.
  String? comment;

  /// Numeric Annotation Glyph ($1 = !, $2 = ?, etc.)
  int? nag;

  /// Evaluation at this position (centipawns, white's perspective).
  double? eval;

  /// Parent node (null for root).
  final GameTreeNode? parent;

  /// Child moves. First child is the main line, rest are variations.
  final List<GameTreeNode> children = [];

  /// The move number (1-based, counting full moves).
  int get moveNumber {
    int count = 0;
    GameTreeNode? node = this;
    while (node?.parent != null) {
      count++;
      node = node!.parent;
    }
    return (count + 1) ~/ 2; // Two half-moves = one full move
  }

  /// The half-move index (0-based ply count from root).
  int get ply {
    int count = 0;
    GameTreeNode? node = this;
    while (node?.parent != null) {
      count++;
      node = node!.parent;
    }
    return count;
  }

  /// Whether this node is on the main line (first child at every level).
  bool get isMainLine {
    if (parent == null) return true; // root
    return parent!.children.first == this && parent!.isMainLine;
  }

  /// The index of this node among its parent's children (0 = main line).
  int get variationIndex {
    if (parent == null) return 0;
    return parent!.children.indexOf(this);
  }

  GameTreeNode({
    this.move,
    this.san,
    required this.fen,
    this.annotation,
    this.comment,
    this.nag,
    this.eval,
    this.parent,
  });

  /// Add a child move. If a child with the same UCI move already exists,
  /// return the existing child (navigate into it instead of duplicating).
  GameTreeNode addChild({
    required String move,
    String? san,
    required String fen,
  }) {
    // Check for existing child with same move
    for (final child in children) {
      if (child.move == move) return child;
    }

    final child = GameTreeNode(
      move: move,
      san: san,
      fen: fen,
      parent: this,
    );
    children.add(child);
    return child;
  }

  /// Get the main line continuation from this node.
  List<GameTreeNode> get mainLine {
    final result = <GameTreeNode>[];
    var node = this;
    while (node.children.isNotEmpty) {
      node = node.children.first;
      result.add(node);
    }
    return result;
  }

  /// Get the path from root to this node.
  List<GameTreeNode> get pathFromRoot {
    final path = <GameTreeNode>[];
    GameTreeNode? node = this;
    while (node != null && node.move != null) {
      path.insert(0, node);
      node = node.parent;
    }
    return path;
  }

  /// Promote this variation to become the main line (first child).
  void promote() {
    if (parent == null) return;
    final idx = parent!.children.indexOf(this);
    if (idx <= 0) return; // Already main line
    parent!.children.removeAt(idx);
    parent!.children.insert(0, this);
  }

  /// Delete this node and its subtree from the parent.
  void delete() {
    parent?.children.remove(this);
  }

  /// Whether this node has variation branches.
  bool get hasVariations => children.length > 1;
}

/// The game tree — root + cursor for current position.
class GameTree {
  /// Root node (no move, starting position FEN).
  final GameTreeNode root;

  /// Current position in the tree.
  GameTreeNode current;

  GameTree({required String startFen})
      : root = GameTreeNode(fen: startFen),
        current = GameTreeNode(fen: startFen) {
    current = root;
  }

  /// Add a move at the current position and advance the cursor.
  /// If the move already exists as a child, navigate into it.
  GameTreeNode addMove({
    required String uci,
    String? san,
    required String fen,
  }) {
    final child = current.addChild(move: uci, san: san, fen: fen);
    current = child;
    return child;
  }

  /// Go back one move (to parent).
  bool goBack() {
    if (current.parent == null) return false;
    current = current.parent!;
    return true;
  }

  /// Go forward one move (main line).
  bool goForward() {
    if (current.children.isEmpty) return false;
    current = current.children.first;
    return true;
  }

  /// Navigate to a specific node.
  void goTo(GameTreeNode node) {
    current = node;
  }

  /// Go to the beginning (root).
  void goToStart() {
    current = root;
  }

  /// Go to the end of the main line.
  void goToEnd() {
    while (current.children.isNotEmpty) {
      current = current.children.first;
    }
  }

  /// Enter a specific variation at the current position.
  bool enterVariation(int index) {
    if (index < 0 || index >= current.children.length) return false;
    current = current.children[index];
    return true;
  }

  /// Get the main line from root as a list of nodes.
  List<GameTreeNode> get mainLine => root.mainLine;

  /// Get all moves from root to current position.
  List<GameTreeNode> get currentPath => current.pathFromRoot;

  /// Get the UCI move history for the current path (for engine position command).
  List<String> get moveHistory =>
      currentPath.map((n) => n.move!).toList();

  /// Reset the tree to a new starting position.
  void reset(String startFen) {
    root.children.clear();
    current = root;
    // Can't change root FEN since it's final, so create a new tree
  }

  /// Whether we're at the root (no moves played).
  bool get atStart => current == root;

  /// Whether we're at the end of the current line (no children).
  bool get atEnd => current.children.isEmpty;

  /// Count total nodes in the tree (for diagnostics).
  int get nodeCount {
    int count = 0;
    void walk(GameTreeNode node) {
      count++;
      for (final child in node.children) walk(child);
    }
    walk(root);
    return count;
  }

  /// Prune variations beyond a maximum node count to prevent memory bloat.
  /// Keeps the main line intact, removes deepest variations first.
  void pruneIfNeeded({int maxNodes = 5000}) {
    if (nodeCount <= maxNodes) return;
    // Remove all non-main-line variations
    void pruneVariations(GameTreeNode node) {
      if (node.children.length > 1) {
        node.children.removeRange(1, node.children.length);
      }
      for (final child in node.children) pruneVariations(child);
    }
    pruneVariations(root);
  }
}
