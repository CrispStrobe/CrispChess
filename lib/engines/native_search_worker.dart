import 'dart:async';
import 'dart:isolate';
import 'package:crisp_chess_engine/crisp_chess_engine.dart';
import 'native_search_bitboard.dart';

/// Reuses an idle isolate; synchronous active searches are killed on cancel.
class NativeSearchWorker {
  Isolate? _isolate;
  ReceivePort? _port;
  SendPort? _commands;
  StreamController<SearchResult>? _active;
  Timer? _deadline;
  int _generation = 0;
  bool _disposed = false;

  Stream<SearchResult> search(
      String fen, List<String> moves, int depth, int budgetMs) {
    if (_disposed) throw StateError('Worker disposed');
    cancel();
    final generation = ++_generation;
    late final StreamController<SearchResult> controller;
    controller = StreamController<SearchResult>(onCancel: () {
      if (identical(_active, controller)) _cancel(reportError: false);
    });
    _active = controller;
    final request = [generation, fen, List<String>.of(moves), depth, budgetMs];
    _deadline = Timer(
        Duration(milliseconds: (budgetMs > 0 ? budgetMs : 3000) + 5000), () {
      if (identical(_active, controller)) {
        _cancel(error: TimeoutException('Search worker did not respond'));
      }
    });
    if (_commands != null) {
      _commands!.send(request);
    } else {
      final port = ReceivePort();
      _port = port;
      port.listen((dynamic event) {
        if (!identical(_port, port)) return;
        if (event is SendPort) {
          _commands = event;
          event.send(request);
        } else if (event is List &&
            event.length == 3 &&
            event[0] == _generation) {
          if (event[1] == 'depth') {
            _active?.add(event[2] as SearchResult);
          } else if (event[1] == 'done') {
            final active = _active;
            _active = null;
            _deadline?.cancel();
            active?.close();
          } else if (event[1] == 'error') {
            _cancel(error: StateError(event[2] as String));
          }
        } else if (event == null || (event is List && event.length == 2)) {
          _cancel(error: StateError('Search isolate exited unexpectedly'));
        }
      });
      Isolate.spawn(_workerMain, port.sendPort,
              onError: port.sendPort, onExit: port.sendPort)
          .then((isolate) {
        if (!identical(_port, port)) {
          isolate.kill(priority: Isolate.immediate);
        } else {
          _isolate = isolate;
        }
      }, onError: (Object error, StackTrace stack) {
        if (identical(_port, port)) _cancel(error: error);
      });
    }
    return controller.stream;
  }

  void cancel() {
    if (_active != null) _cancel();
  }

  void _cancel({bool reportError = true, Object? error}) {
    ++_generation;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _port?.close();
    _port = null;
    _deadline?.cancel();
    final active = _active;
    _active = null;
    if (reportError) active?.addError(error ?? StateError('Search cancelled'));
    active?.close();
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }
}

void _workerMain(SendPort replies) {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  commands.listen((dynamic message) {
    final request = message as List;
    final id = request[0] as int;
    try {
      final fen = request[1] as String;
      final moves = (request[2] as List).cast<String>();
      final result = searchPositionNative(
          fen, moves, request[3] as int, request[4] as int,
          onDepthComplete: (result) => replies.send([id, 'depth', result]));
      if (result == null) {
        final fallback = searchPositionNative(fen, moves, 1, 0);
        if (fallback != null) replies.send([id, 'depth', fallback]);
      }
      replies.send([id, 'done', null]);
    } catch (error) {
      replies.send([id, 'error', error.toString()]);
    }
  });
}
