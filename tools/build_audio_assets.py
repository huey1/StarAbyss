"""Rebuild original Star Abyss PCM sound cues using only Python's standard library.

No downloaded samples, external synthesizer, or runtime synthesis is required.
Run with the installed Python: python tools/build_audio_assets.py
"""
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot' / 'assets' / 'audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 44100
SEED = 271022


def envelope(t, duration, attack=0.008, release=0.04):
    return min(1.0, t / attack) * min(1.0, (duration - t) / release)


def synth(name, duration, kind, pitch=440.0, end_pitch=None, notes=None):
    rng = random.Random(SEED + sum(ord(c) for c in name))
    values = []
    low_noise = 0.0
    phase = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        x = t / duration
        noise = rng.uniform(-1.0, 1.0)
        low_noise += .12 * (noise - low_noise)
        freq = pitch + ((end_pitch if end_pitch is not None else pitch) - pitch) * x
        phase += math.tau * freq / RATE
        if kind == 'swing':
            value = (noise - low_noise) * math.sin(math.pi * x) ** 1.5 * .70
            value += math.sin(phase) * .18 * math.sin(math.pi * x)
        elif kind == 'impact':
            decay = math.exp(-9.0 * x)
            value = (math.sin(phase) * .60 + low_noise * 1.7) * decay
            value += math.sin(phase * 2.31) * .20 * math.exp(-17.0 * x)
        elif kind == 'crystal':
            value = sum(math.sin(phase * ratio) * gain for ratio, gain in [(1, .5), (2.03, .22), (3.97, .09)])
            value *= math.exp(-4.8 * x)
            value += low_noise * .13 * math.exp(-16 * x)
        elif kind == 'warning':
            # A short pitched pulse precedes the action; the ground warning is
            # still authoritative and is not obscured by a looping siren.
            pulse = .65 + .35 * math.sin(math.tau * 18.0 * t)
            value = (math.sin(phase) * .65 + math.sin(phase * 2) * .12) * pulse * math.exp(-2.3 * x)
        elif kind == 'chord':
            value = 0.0
            for offset, note, gain in notes:
                nt = t - offset
                if nt >= 0:
                    value += math.sin(math.tau * note * nt) * gain * math.exp(-3.8 * nt)
                    value += math.sin(math.tau * note * 2.01 * nt) * gain * .16 * math.exp(-6 * nt)
        else:
            raise ValueError(kind)
        values.append(value * envelope(t, duration))
    peak = max(abs(v) for v in values)
    scale = .58 / peak
    pcm = [round(v * scale * 32767) for v in values]
    assert max(abs(v) for v in pcm) < 20000
    assert pcm[0] == 0 and abs(pcm[-1]) < 300
    with wave.open(str(OUT / (name + '.wav')), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack('<{}h'.format(len(pcm)), *pcm))
    return {'duration_seconds': len(pcm) / RATE,
            'peak_linear': max(abs(v) for v in pcm) / 32768.0,
            'rms_linear': math.sqrt(sum((v / 32768.0) ** 2 for v in pcm) / len(pcm)),
            'sample_rate': RATE, 'channels': 1, 'bits_per_sample': 16}


manifest = {'origin': 'Original deterministic synthesis authored for Star Abyss',
            'license': 'Project-owned original sound waveforms; no third-party samples',
            'seed': SEED, 'cues': {}}
definitions = [
    ('swing_01', .20, 'swing', 820, 410, None),
    ('swing_02', .24, 'swing', 680, 280, None),
    ('swing_03', .31, 'swing', 490, 130, None),
    ('skill', .49, 'crystal', 659, 988, None),
    ('dodge', .24, 'swing', 1100, 180, None),
    ('impact', .18, 'impact', 330, 78, None),
    ('hurt', .24, 'impact', 180, 60, None),
    ('sentinel_warning', .18, 'warning', 330, 390, None),
    ('guardian_sweep_warning', .26, 'warning', 174, 230, None),
    ('guardian_shock_warning', .34, 'warning', 246, 370, None),
    ('guardian_slam', .48, 'impact', 110, 39, None),
    ('shatter', .33, 'crystal', 880, 360, None),
    ('room_clear', .51, 'chord', 0, None, [(0, 440, .35), (.08, 554.37, .28), (.16, 659.25, .25)]),
    ('blessing', .61, 'chord', 0, None, [(0, 659.25, .4), (.08, 880, .3), (.17, 1318.5, .2)]),
    ('victory', 1.25, 'chord', 0, None, [(0, 392, .35), (.12, 523.25, .3), (.26, 659.25, .25), (.43, 783.99, .25)]),
    ('defeat', 1.05, 'chord', 0, None, [(0, 293.66, .38), (.17, 246.94, .3), (.36, 196, .28)]),
]
for name, duration, kind, pitch, end, notes in definitions:
    manifest['cues'][name] = synth(name, duration, kind, pitch, end, notes)
(OUT / 'audio_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
print('AUDIO_ASSETS: {} PCM cues, peak <= 0.58, deterministic seed {}'.format(len(definitions), SEED))
