/// Lc0 neural network weight variants.
///
/// Pre-converted ONNX models (opset 15) of Maia chess weights,
/// hosted on GitHub releases for browser compatibility.
///
/// Input:  [1, 112, 8, 8] float32 (lc0 board encoding)
/// Policy: [1, 5120] float32 (convolutional, apply policy map for 1858)
/// Value:  [1, 3] float32 (WDL: win, draw, loss)
library;

const String _releaseBase =
    'https://huggingface.co/cstr/maia-chess-onnx-opset15/resolve/main';

/// A neural network weight variant for Lc0.
class Lc0Variant {
  final String id;
  final String displayName;
  final String url;
  final int estimatedElo;
  final int sizeBytes;
  final String description;

  const Lc0Variant({
    required this.id,
    required this.displayName,
    required this.url,
    required this.estimatedElo,
    required this.sizeBytes,
    required this.description,
  });
}

const String defaultLc0Variant = '1500';

/// All available Maia ONNX weight variants (opset 15).
const List<Lc0Variant> lc0Variants = [
  Lc0Variant(
    id: '1100',
    displayName: 'Maia 1100',
    url: '$_releaseBase/maia-1100-opset15.onnx',
    estimatedElo: 1100,
    sizeBytes: 3490000,
    description: 'Beginner-level human play',
  ),
  Lc0Variant(
    id: '1200',
    displayName: 'Maia 1200',
    url: '$_releaseBase/maia-1200-opset15.onnx',
    estimatedElo: 1200,
    sizeBytes: 3490000,
    description: 'Beginner human play',
  ),
  Lc0Variant(
    id: '1300',
    displayName: 'Maia 1300',
    url: '$_releaseBase/maia-1300-opset15.onnx',
    estimatedElo: 1300,
    sizeBytes: 3490000,
    description: 'Casual human play',
  ),
  Lc0Variant(
    id: '1500',
    displayName: 'Maia 1500',
    url: '$_releaseBase/maia-1500-opset15.onnx',
    estimatedElo: 1500,
    sizeBytes: 3497000,
    description: 'Intermediate human play',
  ),
  Lc0Variant(
    id: '1600',
    displayName: 'Maia 1600',
    url: '$_releaseBase/maia-1600-opset15.onnx',
    estimatedElo: 1600,
    sizeBytes: 3490000,
    description: 'Intermediate-advanced human play',
  ),
  Lc0Variant(
    id: '1700',
    displayName: 'Maia 1700',
    url: '$_releaseBase/maia-1700-opset15.onnx',
    estimatedElo: 1700,
    sizeBytes: 3490000,
    description: 'Advanced human play',
  ),
  Lc0Variant(
    id: '1800',
    displayName: 'Maia 1800',
    url: '$_releaseBase/maia-1800-opset15.onnx',
    estimatedElo: 1800,
    sizeBytes: 3490000,
    description: 'Strong club player',
  ),
  Lc0Variant(
    id: '1900',
    displayName: 'Maia 1900',
    url: '$_releaseBase/maia-1900-opset15.onnx',
    estimatedElo: 1900,
    sizeBytes: 3490000,
    description: 'Strong human play',
  ),
];

Lc0Variant getLc0Variant(String id) {
  return lc0Variants.firstWhere(
    (v) => v.id == id,
    orElse: () => lc0Variants.firstWhere((v) => v.id == defaultLc0Variant),
  );
}

/// Map a Maia3 variant ID to the closest Lc0/Maia ELO variant.
String lc0VariantFromMaia3(String maia3Variant) {
  switch (maia3Variant) {
    case '5m':
      return '1500';
    case '23m':
      return '1700';
    case '79m':
      return '1900';
    default:
      return defaultLc0Variant;
  }
}
