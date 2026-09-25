/// Voice moves on native platforms: CrispASR's microphone and Whisper.
///
/// The spoken move is not transcribed freely. Every phrase of every legal
/// move is scored against the recording (log P(phrase | audio), Whisper
/// teacher-forced) and the likeliest move wins, so the answer is always a
/// legal move and the recogniser never has to spell out a square it misheard.
/// The Whisper session lives in a worker isolate: loading it and scoring take
/// seconds, which must not block the board.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:chess/chess.dart' as chess;
import 'package:crispasr/crispasr.dart';

import '../engines/maia3_dart/onnx/model_fetch.dart';
import 'spoken_moves.dart';
import 'voice_pick.dart';

/// Whisper models the app can use, smallest first.
enum VoiceModel {
  tiny('ggml-tiny.bin', 75),
  base('ggml-base.bin', 142);

  final String file;
  final int megabytes;
  const VoiceModel(this.file, this.megabytes);

  String get url => 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$file';
}

/// Decoder threads. Scoring runs one tiny decoder step per phrase token, and
/// with more threads ggml's workers stall on each other at every step: on a
/// busy 4-core CPU a step took 345 ms with 4 threads and 18 ms with 2.
const _threads = 2;

/// At most this much speech is kept (Whisper's window is 30 s).
const _maxSamples = 16000 * 30;

class VoiceInput {
  final SendPort _worker;
  final ReceivePort _replies;
  final Isolate _isolate;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  Mic? _mic;
  final _recording = <Float32List>[];
  var _recorded = 0;

  VoiceInput._(this._worker, this._replies, Stream<dynamic> replies, this._isolate) {
    replies.listen((message) {
      if (message is! (int, Object?)) return;
      final (id, result) = message;
      _pending.remove(id)?.complete(result);
    });
  }

  /// Whether this build can take voice moves: the CrispASR library is
  /// present and has the microphone and phrase scoring.
  static bool get available {
    try {
      final lib = DynamicLibrary.open(CrispASR.defaultLibName());
      return lib.providesSymbol('crispasr_session_score_texts') &&
          lib.providesSymbol('crispasr_mic_open');
    } catch (_) {
      return false;
    }
  }

  /// Downloads [model] if needed and loads it.
  static Future<VoiceInput> open({
    VoiceModel model = VoiceModel.base,
    void Function(int received, int? total)? onProgress,
  }) async {
    final path = await fetchModelFile(model.url, model.file, onProgress: onProgress);
    final port = ReceivePort();
    final replies = port.asBroadcastStream();
    final isolate = await Isolate.spawn(_workerMain, (port.sendPort, path),
        onError: port.sendPort, debugName: 'voice');
    // The worker answers with its inbox, or with why it could not load.
    final first = await replies.first;
    if (first is! SendPort) {
      isolate.kill();
      port.close();
      throw StateError(first is List ? '${first.first}' : '$first');
    }
    return VoiceInput._(first, port, replies, isolate);
  }

  bool get listening => _mic != null;

  /// Starts recording from the default microphone.
  void startListening() {
    if (_mic != null) return;
    _recording.clear();
    _recorded = 0;
    final mic = Mic.open(callback: (pcm) {
      if (_recorded >= _maxSamples) return;
      _recording.add(pcm);
      _recorded += pcm.length;
    });
    mic.start();
    _mic = mic;
  }

  /// Stops recording and ranks the legal moves of [fen] by how well they
  /// match what was said, best first. Empty when nothing was recorded.
  Future<List<VoiceCandidate>> stopAndRank(String fen, VoiceLanguage lang) async {
    final mic = _mic;
    _mic = null;
    mic?.close();
    final pcm = Float32List(_recorded.clamp(0, _maxSamples));
    var at = 0;
    for (final chunk in _recording) {
      final n = (pcm.length - at).clamp(0, chunk.length);
      pcm.setRange(at, at + n, chunk);
      at += n;
    }
    _recording.clear();
    return rankPcm(pcm, fen, lang);
  }

  /// Ranks the legal moves of [fen] against [pcm] (16 kHz mono), best first.
  Future<List<VoiceCandidate>> rankPcm(Float32List pcm, String fen, VoiceLanguage lang) async {
    if (pcm.length < 1600) return const []; // under 0.1 s: a stray tap
    final id = _nextId++;
    final done = Completer<Object?>();
    _pending[id] = done;
    _worker.send((id, TransferableTypedData.fromList([pcm]), fen, lang.index));
    final result = await done.future;
    if (result is String) throw StateError(result);
    return [
      for (final (uci, san, phrase, score) in result as List<(String, String, String, double)>)
        VoiceCandidate(uci, san, phrase, score),
    ];
  }

  void dispose() {
    _mic?.close();
    _mic = null;
    _isolate.kill(priority: Isolate.immediate);
    _replies.close();
    for (final p in _pending.values) {
      p.completeError(StateError('voice input closed'));
    }
    _pending.clear();
  }
}

/// Worker isolate: owns the Whisper session and scores phrases.
void _workerMain((SendPort, String) args) {
  final (reply, modelPath) = args;
  final CrispasrSession session;
  try {
    session = CrispasrSession.open(modelPath, backend: 'whisper', nThreads: _threads);
  } catch (e) {
    reply.send('could not load the speech model: $e');
    return;
  }
  final inbox = ReceivePort();
  reply.send(inbox.sendPort);
  inbox.listen((message) {
    final (id, data, fen, langIndex) =
        message as (int, TransferableTypedData, String, int);
    try {
      final pcm = data.materialize().asFloat32List();
      final lang = VoiceLanguage.values[langIndex];
      final moves = spokenMoves(chess.Chess.fromFEN(fen), lang);
      final scores = session.scoreTexts(pcm, phrasesOf(moves),
          language: voiceLanguageCode(lang), prompt: voicePrompt(lang));
      final ranked = rankMoves(moves, scores);
      reply.send((id, [for (final c in ranked) (c.uci, c.san, c.phrase, c.score)]));
    } catch (e) {
      reply.send((id, '$e'));
    }
  });
}
