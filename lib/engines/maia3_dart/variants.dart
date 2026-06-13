/// Maia3 model variant registry.
///
/// Ported from maia3-js/dist/variants.js (MIT).
library;

const String hfRepoBase =
    'https://huggingface.co/cemoss17/maia3-onnx/resolve/main';

/// A Maia3 model variant.
class Maia3Variant {
  final String id;
  final String alias;
  final String displayName;
  final String onnxFile;
  final String url;
  final int approxBytes;

  const Maia3Variant({
    required this.id,
    required this.alias,
    required this.displayName,
    required this.onnxFile,
    required this.url,
    required this.approxBytes,
  });

  String get displaySize {
    if (approxBytes >= 100000000) return '${approxBytes ~/ 1000000}MB';
    return '${approxBytes ~/ 1000000}MB';
  }

  /// Estimated ELO range based on model size.
  int get estimatedElo {
    switch (id) {
      case '5m':
        return 1800;
      case '23m':
        return 2200;
      case '79m':
        return 2500;
      default:
        return 1800;
    }
  }
}

const variants = <String, Maia3Variant>{
  '5m': Maia3Variant(
    id: '5m',
    alias: '5m',
    displayName: 'Maia3 5M',
    onnxFile: 'maia3_5m.onnx',
    url: '$hfRepoBase/maia3_5m.onnx',
    approxBytes: 25000000,
  ),
  '23m': Maia3Variant(
    id: '23m',
    alias: '23m',
    displayName: 'Maia3 23M',
    onnxFile: 'maia3_23m.onnx',
    url: '$hfRepoBase/maia3_23m.onnx',
    approxBytes: 92500000,
  ),
  '79m': Maia3Variant(
    id: '79m',
    alias: '79m',
    displayName: 'Maia3 79M',
    onnxFile: 'maia3_79m.onnx',
    url: '$hfRepoBase/maia3_79m.onnx',
    approxBytes: 313000000,
  ),
};

const String defaultVariant = '5m';

Maia3Variant getVariant(String alias) {
  final v = variants[alias];
  if (v == null) throw ArgumentError('Unknown Maia3 variant: $alias');
  return v;
}
