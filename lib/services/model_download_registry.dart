import 'package:flutter/foundation.dart';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

class ModelDownload {
  final String id;
  final String name;
  final VoidCallback _abort;
  int received = 0;
  int? total;
  bool cancelled = false;
  ModelDownload(this.id, this.name, this._abort);
  void cancel() {
    cancelled = true;
    _abort();
  }
}

class CachedModel {
  final String id;
  final String name;
  final int bytes;
  const CachedModel(this.id, this.name, this.bytes);
}

/// One place for engines, scanning and speech to report their downloads.
class ModelDownloadRegistry extends ChangeNotifier {
  static final instance = ModelDownloadRegistry();
  final Map<String, ModelDownload> _active = {};
  List<ModelDownload> get active => List.unmodifiable(_active.values);
  ModelDownload begin(String id, String name, VoidCallback cancel) {
    final item = ModelDownload(id, name, cancel);
    _active[id] = item;
    notifyListeners();
    return item;
  }

  void progress(ModelDownload item, int received, int? total) {
    item.received = received;
    item.total = total;
    // A download chunk can be much smaller than a UI frame.
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds >= 100) {
      _lastUpdate = now;
      notifyListeners();
    }
  }

  DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  void finish(ModelDownload item) {
    if (_active[item.id] == item) _active.remove(item.id);
    notifyListeners();
  }
}

String formatModelBytes(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(0)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
