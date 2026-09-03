/// Lc0 neural network weight variants.
///
/// ONNX exports of the Maia weights, produced with lc0's own converter
/// (`lc0 leela2onnx`, v0.32.1) and hosted on Hugging Face.
///
/// Input:  `/input/planes`  [1, 112, 8, 8] float32 (lc0 board encoding)
/// Policy: `/output/policy` [1, 1858] float32 (already in move-vocabulary
///         order — no policy map needed)
/// Value:  `/output/wdl`    [1, 3] float32 (win, draw, loss; sums to 1)
///
/// These replace an earlier `-opset15` set that was mis-converted: it returned
/// a saturated WDL and policy logits in the hundreds of thousands, and did so
/// even for an all-zeros input, so its highest-scoring outputs were moves that
/// were not legal in the position. The engine was fine; the weights were not.
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
    url: '$_releaseBase/maia-1100.onnx',
    estimatedElo: 1100,
    sizeBytes: 3490000,
    description: 'Beginner-level human play',
  ),
  Lc0Variant(
    id: '1200',
    displayName: 'Maia 1200',
    url: '$_releaseBase/maia-1200.onnx',
    estimatedElo: 1200,
    sizeBytes: 3490000,
    description: 'Beginner human play',
  ),
  Lc0Variant(
    id: '1300',
    displayName: 'Maia 1300',
    url: '$_releaseBase/maia-1300.onnx',
    estimatedElo: 1300,
    sizeBytes: 3490000,
    description: 'Casual human play',
  ),
  Lc0Variant(
    id: '1500',
    displayName: 'Maia 1500',
    url: '$_releaseBase/maia-1500.onnx',
    estimatedElo: 1500,
    sizeBytes: 3497000,
    description: 'Intermediate human play',
  ),
  Lc0Variant(
    id: '1600',
    displayName: 'Maia 1600',
    url: '$_releaseBase/maia-1600.onnx',
    estimatedElo: 1600,
    sizeBytes: 3490000,
    description: 'Intermediate-advanced human play',
  ),
  Lc0Variant(
    id: '1700',
    displayName: 'Maia 1700',
    url: '$_releaseBase/maia-1700.onnx',
    estimatedElo: 1700,
    sizeBytes: 3490000,
    description: 'Advanced human play',
  ),
  Lc0Variant(
    id: '1800',
    displayName: 'Maia 1800',
    url: '$_releaseBase/maia-1800.onnx',
    estimatedElo: 1800,
    sizeBytes: 3490000,
    description: 'Strong club player',
  ),
  Lc0Variant(
    id: '1900',
    displayName: 'Maia 1900',
    url: '$_releaseBase/maia-1900.onnx',
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
