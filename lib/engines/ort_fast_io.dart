/// Fast tensor I/O for package:onnxruntime (native only).
///
/// The package's `OrtValueTensor.createTensorWithDataList` flattens its input
/// element by element and `OrtValue.value` boxes every output element into
/// nested Dart lists. For ChessMamba's 1.2M-float state that conversion cost
/// more than the network: a batch of ten took 294 ms instead of 72. These go
/// through the C API directly, with one typed copy each way.
///
/// Import only from files that are themselves native-only (behind a
/// `dart.library.ffi` conditional import) — this pulls in dart:ffi.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:onnxruntime/onnxruntime.dart';
// The raw-buffer calls need the generated binding types.
// ignore: implementation_imports
import 'package:onnxruntime/src/bindings/onnxruntime_bindings_generated.dart'
    as bg;

/// Native buffers backing input tensors, freed together after the run.
class OrtInputs {
  final Map<String, OrtValue> values = {};
  final List<ffi.Pointer<ffi.Void>> _buffers = [];

  /// Adds input [name] over a native copy of [data] (Float32List, Int64List
  /// or Int32List) with [shape].
  void add(String name, TypedData data, List<int> shape) {
    final int type, bytes;
    final ffi.Pointer<ffi.Void> buf;
    if (data is Float32List) {
      final p = calloc<ffi.Float>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      buf = p.cast();
      bytes = data.length * 4;
      type = 1; // FLOAT
    } else if (data is Int64List) {
      final p = calloc<ffi.Int64>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      buf = p.cast();
      bytes = data.length * 8;
      type = 7; // INT64
    } else if (data is Int32List) {
      final p = calloc<ffi.Int32>(data.length);
      p.asTypedList(data.length).setAll(0, data);
      buf = p.cast();
      bytes = data.length * 4;
      type = 6; // INT32
    } else {
      throw ArgumentError('Unsupported tensor type ${data.runtimeType}');
    }
    _buffers.add(buf);
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
      // No data pointer handed over: the buffer is ours to free.
      values[name] = OrtValueTensor(valueOut.value);
    } finally {
      calloc.free(shapePtr);
      calloc.free(infoOut);
      calloc.free(valueOut);
    }
  }

  /// Releases the values, then the buffers under them.
  void release() {
    for (final v in values.values) {
      v.release();
    }
    for (final b in _buffers) {
      calloc.free(b);
    }
    values.clear();
    _buffers.clear();
  }
}

/// The first [count] floats of a float tensor, copied out in one go.
Float32List ortFloats(OrtValue value, int count) {
  final out = calloc<ffi.Pointer<ffi.Void>>();
  try {
    final status = OrtEnv.instance.ortApiPtr.ref.GetTensorMutableData
        .asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                ffi.Pointer<ffi.Pointer<ffi.Void>>)>()(value.ptr, out);
    OrtStatus.checkOrtStatus(status);
    return Float32List.fromList(out.value.cast<ffi.Float>().asTypedList(count));
  } finally {
    calloc.free(out);
  }
}

/// Element count of a tensor output, from its shape.
int ortElementCount(OrtValue value) {
  final info = calloc<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>();
  final count = calloc<ffi.Size>();
  try {
    final api = OrtEnv.instance.ortApiPtr.ref;
    OrtStatus.checkOrtStatus(api.GetTensorTypeAndShape.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtValue>,
                ffi.Pointer<ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>>)>()(
        value.ptr, info));
    OrtStatus.checkOrtStatus(api.GetTensorShapeElementCount.asFunction<
            bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>,
                ffi.Pointer<ffi.Size>)>()(info.value, count));
    api.ReleaseTensorTypeAndShapeInfo.asFunction<
        void Function(ffi.Pointer<bg.OrtTensorTypeAndShapeInfo>)>()(info.value);
    return count.value;
  } finally {
    calloc.free(info);
    calloc.free(count);
  }
}

/// A whole float tensor output.
Float32List ortAllFloats(OrtValue value) =>
    ortFloats(value, ortElementCount(value));
