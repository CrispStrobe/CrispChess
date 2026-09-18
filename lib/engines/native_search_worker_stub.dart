import 'package:crisp_chess_engine/crisp_chess_engine.dart';

class NativeSearchWorker {
  Stream<SearchResult> search(
          String fen, List<String> moves, int depth, int budgetMs) =>
      throw UnsupportedError('Native worker is unavailable on web');
  void cancel() {}
  void dispose() {}
}
