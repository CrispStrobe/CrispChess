// Sound bridge for CrispChess — generates short tones via Web Audio API.
// No external audio files needed.

let audioCtx = null;

function ensureAudioCtx() {
  if (!audioCtx) {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  }
  // Resume if suspended (browsers require user gesture)
  if (audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
  return audioCtx;
}

function playTone(frequency, duration, type, volume) {
  try {
    const ctx = ensureAudioCtx();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();

    osc.type = type || 'sine';
    osc.frequency.value = frequency;
    gain.gain.value = volume || 0.3;

    // Quick fade out to avoid click
    gain.gain.setTargetAtTime(0, ctx.currentTime + duration - 0.02, 0.01);

    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + duration);
  } catch(e) {
    // Silently fail — audio is not critical
  }
}

function chessSoundPlay(soundName, volume) {
  const v = (volume || 0.7) * 0.4; // Scale down
  switch (soundName) {
    case 'move':
      playTone(440, 0.08, 'sine', v);
      break;
    case 'capture':
      playTone(220, 0.12, 'sawtooth', v * 0.8);
      break;
    case 'check':
      playTone(880, 0.15, 'square', v * 0.6);
      setTimeout(() => playTone(880, 0.1, 'square', v * 0.4), 100);
      break;
    case 'castle':
      playTone(330, 0.06, 'sine', v);
      setTimeout(() => playTone(440, 0.06, 'sine', v), 80);
      break;
    case 'promote':
      playTone(523, 0.08, 'sine', v);
      setTimeout(() => playTone(659, 0.08, 'sine', v), 80);
      setTimeout(() => playTone(784, 0.12, 'sine', v), 160);
      break;
    case 'gameStart':
      playTone(262, 0.1, 'sine', v);
      setTimeout(() => playTone(330, 0.1, 'sine', v), 100);
      setTimeout(() => playTone(392, 0.15, 'sine', v), 200);
      break;
    case 'gameEnd':
      playTone(392, 0.15, 'sine', v);
      setTimeout(() => playTone(330, 0.15, 'sine', v), 150);
      setTimeout(() => playTone(262, 0.2, 'sine', v), 300);
      break;
    case 'illegal':
      playTone(150, 0.15, 'sawtooth', v * 0.5);
      break;
  }
}

globalThis.chessSoundPlay = chessSoundPlay;
