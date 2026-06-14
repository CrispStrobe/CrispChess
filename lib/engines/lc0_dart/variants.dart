/// Lc0 neural network weight variants.
///
/// These are pre-converted ONNX models of Maia chess weights from HuggingFace.
/// Each variant plays at a specific human ELO level.
///
/// Input:  [1, 112, 8, 8] float32 (lc0 board encoding)
/// Policy: [1, 1858] float32 logits
/// Value:  [1, 3] float32 (WDL: win, draw, loss)
library;

/// A neural network weight variant for Lc0.
class Lc0Variant {
  /// Short identifier (e.g. '1100', '1500').
  final String id;

  /// Human-readable display name.
  final String displayName;

  /// URL to download the ONNX model.
  final String url;

  /// Estimated ELO rating.
  final int estimatedElo;

  /// Approximate model size in bytes.
  final int sizeBytes;

  /// Description of the variant.
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

/// Default variant ID.
const String defaultLc0Variant = '1500';

/// All available Maia ONNX weight variants.
const List<Lc0Variant> lc0Variants = [
  Lc0Variant(
    id: '1100',
    displayName: 'Maia 1100',
    url: 'https://huggingface.co/shermansiu/maia-1100/resolve/main/model.onnx',
    estimatedElo: 1100,
    sizeBytes: 3500000,
    description: 'Beginner-level human play',
  ),
  Lc0Variant(
    id: '1200',
    displayName: 'Maia 1200',
    url: 'https://huggingface.co/shermansiu/maia-1200/resolve/main/model.onnx',
    estimatedElo: 1200,
    sizeBytes: 3500000,
    description: 'Beginner human play',
  ),
  Lc0Variant(
    id: '1300',
    displayName: 'Maia 1300',
    url: 'https://huggingface.co/shermansiu/maia-1300/resolve/main/model.onnx',
    estimatedElo: 1300,
    sizeBytes: 3500000,
    description: 'Casual human play',
  ),
  Lc0Variant(
    id: '1400',
    displayName: 'Maia 1400',
    url: 'https://huggingface.co/shermansiu/maia-1400/resolve/main/model.onnx',
    estimatedElo: 1400,
    sizeBytes: 3500000,
    description: 'Casual-intermediate human play',
  ),
  Lc0Variant(
    id: '1500',
    displayName: 'Maia 1500',
    url: 'https://huggingface.co/shermansiu/maia-1500/resolve/main/model.onnx',
    estimatedElo: 1500,
    sizeBytes: 3500000,
    description: 'Intermediate human play',
  ),
  Lc0Variant(
    id: '1600',
    displayName: 'Maia 1600',
    url: 'https://huggingface.co/shermansiu/maia-1600/resolve/main/model.onnx',
    estimatedElo: 1600,
    sizeBytes: 3500000,
    description: 'Intermediate-advanced human play',
  ),
  Lc0Variant(
    id: '1700',
    displayName: 'Maia 1700',
    url: 'https://huggingface.co/shermansiu/maia-1700/resolve/main/model.onnx',
    estimatedElo: 1700,
    sizeBytes: 3500000,
    description: 'Advanced human play',
  ),
  Lc0Variant(
    id: '1800',
    displayName: 'Maia 1800',
    url: 'https://huggingface.co/shermansiu/maia-1800/resolve/main/model.onnx',
    estimatedElo: 1800,
    sizeBytes: 3500000,
    description: 'Strong club player',
  ),
  Lc0Variant(
    id: '1900',
    displayName: 'Maia 1900',
    url: 'https://huggingface.co/shermansiu/maia-1900/resolve/main/model.onnx',
    estimatedElo: 1900,
    sizeBytes: 3500000,
    description: 'Strong human play',
  ),
];

/// Look up a variant by ID. Returns the default if not found.
Lc0Variant getLc0Variant(String id) {
  return lc0Variants.firstWhere(
    (v) => v.id == id,
    orElse: () => lc0Variants.firstWhere((v) => v.id == defaultLc0Variant),
  );
}

/// Map a Maia3 variant ID to the closest Lc0/Maia ELO variant.
/// Maia3 uses '5m', '23m', '79m'; we map to closest ELO.
Lc0Variant lc0VariantFromMaia3(String maia3Variant) {
  switch (maia3Variant) {
    case '5m':
      return getLc0Variant('1500'); // ~1800 ELO maps to 1500 Maia
    case '23m':
      return getLc0Variant('1700'); // ~2200 ELO maps to 1700 Maia
    case '79m':
      return getLc0Variant('1900'); // ~2500 ELO maps to 1900 Maia
    default:
      return getLc0Variant(defaultLc0Variant);
  }
}
