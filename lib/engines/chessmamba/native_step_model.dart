/// ChessMamba step on Microsoft's native ONNX Runtime — ~8x the pure-Dart
/// speed, which is what gives the search room to look ahead. Not on web; see
/// native_step_model_stub.dart.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// The raw-buffer accessor below needs the generated binding types.
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

import 'step_model.dart';

class NativeMambaStepModel implements MambaStepModel {
  final OrtSession _session;
  final OrtRunOptions _runOptions;

  NativeMambaStepModel._(this._session, this._runOptions);

  static bool get isSupported => true;

  static NativeMambaStepModel create(Uint8List bytes, {int threads = 2}) {
    OrtEnv.instance.init();
    final options = OrtSessionOptions()
      ..setIntraOpNumThreads(threads.clamp(1, 4))
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    try {
      return NativeMambaStepModel._(
          OrtSession.fromBuffer(bytes, options), OrtRunOptions());
    } finally {
      options.release();
    }
  }

  @override
  Future<List<MambaOutput>> stepBatch(List<MambaStepInput> inputs) async {
    final b = inputs.length;
    final owned = <ffi.Pointer<ffi.Void>>[];
    OrtValue ids(int Function(MambaStepInput) f) => _tensor(
        Int64List.fromList([for (final x in inputs) f(x)]), [b], owned);
    final feeds = {
      'from_sq': ids((x) => x.from),
      'to_sq': ids((x) => x.to),
      'promo': ids((x) => x.promo),
      'ply': ids((x) => x.ply),
      'is_start': _tensor(
          Float32List.fromList([for (final x in inputs) x.start ? 1 : 0]),
          [b, 1],
          owned),
      'state': _tensor(packStates(inputs),
          [mambaDepth, b, mambaInner, mambaStateDim], owned),
    };
    List<OrtValue?> outputs = const [];
    try {
      outputs = _session.run(_runOptions, feeds,
          ['policy', 'promo_logits', 'value', 'new_state']);
      return unpackOutputs(
          b,
          _floats(outputs[0]!, b * 4096),
          _floats(outputs[1]!, b * 5),
          _floats(outputs[2]!, b),
          _floats(outputs[3]!, mambaDepth * b * mambaInner * mambaStateDim));
    } finally {
      for (final v in feeds.values) {
        v.release();
      }
      for (final o in outputs) {
        o?.release();
      }
      for (final p in owned) {
        calloc.free(p);
      }
    }
  }

  /// A tensor over a native copy of [data], made with one typed copy.
  /// `createTensorWithDataList` flattens its input element by element, which
  /// for a batch's state costs more than the network. The buffer is freed by
  /// the caller (collected in [owned]) after the value is released.
  static OrtValue _tensor(
      TypedData data, List<int> shape, List<ffi.Pointer<ffi.Void>> owned) {
    final int type, bytes;
    final ffi.Pointer<ffi.Void> buf;
    if (data is Float32List) {
      final p = calloc<ffi.Float>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      buf = p.cast();
      bytes = data.length * 4;
      type = 1; // ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT
    } else if (data is Int64List) {
      final p = calloc<ffi.Int64>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      buf = p.cast();
      bytes = data.length * 8;
      type = 7; // ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64
    } else {
      throw ArgumentError('Unsupported tensor type ${data.runtimeType}');
    }
    owned.add(buf);
    final shapePtr = calloc<ffi.Int64>(shape.length);
    shapePtr.asTypedList(shape.length).setAll(0, shape);
    final infoOut = calloc<ffi.Pointer<bg.OrtMemoryInfo>>();
    final valueOut = calloc<ffi.Pointer<bg.OrtValue>>();
    try {
      final api = OrtEnv.instance.ortApiPtr.ref;
      OrtStatus.checkOrtStatus(api.AllocatorGetInfo.asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtAllocator>,
                  ffi.Pointer<ffi.Pointer<bg.OrtMemoryInfo>>)>()(
          OrtAllocator.instance.ptr, infoOut));
      OrtStatus.checkOrtStatus(api.CreateTensorWithDataAsOrtValue.asFunction<
              bg.OrtStatusPtr Function(
                  ffi.Pointer<bg.OrtMemoryInfo>,
                  ffi.Pointer<ffi.Void>,
                  int,
                  ffi.Pointer<ffi.Int64>,
                  int,
                  int,
                  ffi.Pointer<ffi.Pointer<bg.OrtValue>>)>()(
          infoOut.value, buf, bytes, shapePtr, shape.length, type, valueOut));
      return OrtValueTensor(valueOut.value);
    } finally {
      calloc.free(shapePtr);
      calloc.free(infoOut);
      calloc.free(valueOut);
    }
  }

  /// Copies a float tensor's buffer out in one go. `OrtValue.value` boxes
  /// every element into nested Dart lists, which for a batch's 1.2M-float
  /// state cost more than running the network.
  static Float32List _floats(OrtValue value, int count) {
    final out = calloc<ffi.Pointer<ffi.Void>>();
    try {
      final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
          .asFunction<
              bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                  ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(value.ptr, out);
      OrtStatus.checkOrtStatus(status);
      return Float32List.fromList(
          out.value.cast<ffi.Float>().asTypedList(count));
    } finally {
      calloc.free(out);
    }
  }

  @override
  void dispose() {
    _runOptions.release();
    _session.release();
  }
}
