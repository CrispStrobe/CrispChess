# CrispChess synthesized sound effects

These eight original effects and their generator are licensed under the MIT
license in LICENSE (Copyright (c) 2024-2026 CrispStrobe). They contain no imported
recordings or third-party samples. Regenerate with:

    python3 tool/generate_sound_samples.py

Format: mono, signed 16-bit PCM WAV, 44,100 Hz. Each effect lasts 85–520 ms.
Move is a high tap; capture a lower impact; check a repeated high tone;
castle a double tap; promote an ascending sparkle; game-start an ascending
triad; game-end a descending triad; illegal a low descending double tone.
Smooth attack/release envelopes and conservative peaks avoid clicks/clipping.
