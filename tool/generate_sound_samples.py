#!/usr/bin/env python3
"""Generate CrispChess's original MIT-licensed effects (Python standard library).

Run from any directory: python3 tool/generate_sound_samples.py
No recordings, external samples, or synthesis dependencies are used.
"""

import math
from pathlib import Path
import struct
import wave

RATE = 44100
OUTPUT = Path(__file__).resolve().parents[1] / 'assets' / 'sounds'
# Each note: onset seconds, duration seconds, frequency Hz, amplitude.
# A damped fundamental + overtone makes soft, distinct board/game feedback.
SOUNDS = {
    'move': [(0, .085, 660, .40)],
    'capture': [(0, .14, 220, .48), (.015, .09, 880, .18)],
    'check': [(0, .10, 1046.5, .32), (.135, .13, 1046.5, .32)],
    'castle': [(0, .075, 440, .36), (.095, .10, 660, .36)],
    'promote': [(0, .11, 659.25, .30), (.09, .11, 830.61, .30),
                (.18, .20, 1318.51, .32)],
    'game-start': [(0, .12, 523.25, .32), (.12, .12, 659.25, .32),
                   (.24, .17, 783.99, .32)],
    'game-end': [(0, .18, 783.99, .30), (.15, .18, 659.25, .30),
                 (.30, .22, 523.25, .34)],
    'illegal': [(0, .12, 185, .34), (.13, .15, 146.83, .34)],
}


def render(notes):
    duration = max(start + length for start, length, _, _ in notes)
    samples = []
    for index in range(math.ceil(duration * RATE)):
        time = index / RATE
        value = 0.0
        for start, length, frequency, amplitude in notes:
            t = time - start
            if 0 <= t < length:
                # Smooth attack/release prevent clicks; exponential decay.
                envelope = min(t / .004, 1) * min((length - t) / .012, 1)
                envelope *= math.exp(-3 * t / length)
                phase = 2 * math.pi * frequency * t
                value += amplitude * envelope * (
                    .85 * math.sin(phase) + .15 * math.sin(phase * 2)
                )
        assert abs(value) < 1, 'Sample would clip'
        samples.append(round(value * 32767))
    return struct.pack(f'<{len(samples)}h', *samples)


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, notes in SOUNDS.items():
        with wave.open(str(OUTPUT / f'{name}.wav'), 'wb') as output:
            output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
            output.writeframes(render(notes))


if __name__ == '__main__':
    main()
