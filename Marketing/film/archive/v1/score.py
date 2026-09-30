#!/usr/bin/env python3
"""Scores the film: 20 seconds at 96 BPM, eight bars, with each sound on a cue from film.js.

    python3 Marketing/film/score.py

Writes build/film/score.wav: 48 kHz, 24-bit stereo, -16 LUFS, true peak under -1 dBTP. Every sound is
synthesized here, so the film carries no licensed audio. The cue times copy film.js; change them together.
"""
import os

import numpy as np
import soundfile
from scipy import ndimage, signal

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "build", "film", "score.wav")

SR = 48000
BEAT = 60 / 96
LENGTH = 20.0
N = int(LENGTH * SR)
SPAN = N + 3 * SR  # room for tails; the mix is cut at LENGTH

# Cues from film.js, in seconds.
PRESS = [BEAT, 1.5 * BEAT, 2 * BEAT, 3 * BEAT]
MOVES = [5 * BEAT, 6 * BEAT, 7 * BEAT]
RETURN = 7.5 * BEAT
WORDS = [8.5 * BEAT, 9 * BEAT, 10 * BEAT, 11 * BEAT]
ALL_AT_ONCE = 13 * BEAT
SWITCHES = [b * BEAT for b in (14, 15, 16, 17, 17.5, 18, 18.5, 19, 19.25, 19.5, 19.75, 20)]
WALL, THEMES_CAPTION, ICON, END = 12.5, 21 * BEAT, 16.3, 17.5

# The chord under each part of the film, as (start, end, MIDI notes). The key is F major.
PAD = [
    (0.0, 2.5, [41, 53, 57, 64, 67]),         # Fmaj9: the keys
    (2.5, 5.0, [38, 53, 57, 60, 64]),         # Dm9: the switcher
    (5.0, 7.5, [46, 53, 57, 60, 62]),         # Bbmaj9: the desktop changes one part at a time
    (7.5, 8.75, [48, 55, 60, 65, 67]),        # Csus4: "All at once."
    (8.75, 10.0, [48, 55, 60, 64, 67]),       # C: the switches start
    (10.0, 12.5, [50, 53, 57, 60, 64]),       # Dm9: the switches speed up
    (12.5, 15.0, [46, 53, 57, 60, 62, 69]),   # Bbmaj9: the wall of themes
    (15.0, 16.25, [43, 53, 58, 62, 69]),      # Gm9: the wall recedes
    (16.25, 17.5, [48, 53, 55, 58, 65]),      # C7sus4: the icon forms
    (17.5, 19.0, [41, 53, 57, 60, 64, 67]),   # Fmaj9: the end card
]

# Each track's loudness relative to the pad (LU), its reverb send, and whether it echoes.
MIX = {
    "pad": (0, 0.30, False),
    "bass": (-4, 0.0, False),
    "kick": (-3, 0.03, False),
    "mallet": (-4, 0.45, True),
    "chime": (-8, 0.55, True),
    "click": (-14, 0.15, False),
    "hat": (-16, 0.10, False),
    "air": (-10, 0.30, False),
    "crash": (-14, 0.30, False),
    "impact": (-4, 0.05, False),
    "swell": (-9, 0.0, False),
}

rng = np.random.default_rng(7)


def hz(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def time(duration):
    return np.arange(int(duration * SR)) / SR


def butter(kind, cutoff, order=2):
    return signal.butter(order, cutoff, kind, fs=SR, output="sos")


def high_shelf(frequency, gain_db, slope=0.8):
    """An RBJ high shelf as one second-order section."""
    a = 10 ** (gain_db / 40)
    w = 2 * np.pi * frequency / SR
    c, s = np.cos(w), np.sqrt(a) * np.sin(w) * np.sqrt((a + 1 / a) * (1 / slope - 1) + 2)
    b = [a * ((a + 1) + (a - 1) * c + s), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - s)]
    d = [(a + 1) - (a - 1) * c + s, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - s]
    return np.array([b + d]) / d[0]


def envelope(points, n=SPAN):
    """A line through (seconds, value) points, one value per sample."""
    return np.interp(np.arange(n) / SR, [p[0] for p in points], [p[1] for p in points])


def pan(sound, position):
    """Places a mono sound from left (-1) to right (+1) at constant power."""
    angle = (np.asarray(position) + 1) * np.pi / 4
    return np.stack([sound * np.cos(angle), sound * np.sin(angle)]) * np.sqrt(2)


class Track:
    def __init__(self):
        self.x = np.zeros((2, SPAN))

    def add(self, sound, at, position=0.0, gain=1.0):
        if sound.ndim == 1:
            sound = pan(sound, position)
        i = int(round(at * SR))
        n = min(sound.shape[1], SPAN - i)
        self.x[:, i:i + n] += gain * sound[:, :n]


# MARK: Instruments

def mallet(note, decay=0.55, bright=1.0):
    """A soft marimba-like note."""
    f, t = hz(note), time(decay * 6)
    y = (np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
         + 0.25 * np.sin(2 * np.pi * 2 * f * t + 0.4) * np.exp(-t / (decay * 0.45))
         + 0.18 * bright * np.sin(2 * np.pi * 3.99 * f * t + 1.1) * np.exp(-t / 0.09)
         + 0.08 * bright * np.sin(2 * np.pi * 9.9 * f * t + 0.3) * np.exp(-t / 0.025))
    strike = signal.sosfilt(butter("bandpass", [2500, 9000]), rng.standard_normal(t.size)) * np.exp(-t / 0.004)
    return (y + 0.12 * bright * strike) * np.minimum(1, t / 0.0025)


def chime(note, decay=1.8):
    """A glassy bell: a gentle FM tone with one inharmonic partial."""
    f, t = hz(note), time(decay * 5)
    index = 1.1 * np.exp(-t / 0.25)
    y = np.sin(2 * np.pi * f * t + index * np.sin(2 * np.pi * 2 * f * t)) * np.exp(-t / decay)
    y += 0.2 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t / (decay * 0.25))
    return y * np.minimum(1, t / 0.003)


def click(body=190.0):
    """A keycap: a short bright tick over a small thump."""
    t = time(0.3)
    tick = signal.sosfilt(butter("bandpass", [1800, 6500]), rng.standard_normal(t.size)) * np.exp(-t / 0.0035)
    thump = np.sin(2 * np.pi * body * t) * np.exp(-t / 0.035) * np.minimum(1, t / 0.001)
    return 0.7 * tick + thump


def kick():
    t = time(0.8)
    f = 45 + 95 * np.exp(-t / 0.032)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.3)
    y += 0.2 * signal.sosfilt(butter("highpass", 3000), rng.standard_normal(t.size)) * np.exp(-t / 0.003)
    return np.tanh(1.5 * y) / np.tanh(1.5)


def hat(decay=0.028):
    t = time(0.3)
    return signal.sosfilt(butter("highpass", 7500, 4), rng.standard_normal(t.size)) * np.exp(-t / decay)


def crash(decay=1.1):
    t = time(decay * 4)
    y = signal.sosfilt(butter("bandpass", [3000, 12000]), rng.standard_normal((2, t.size)), axis=1)
    return y * np.exp(-t / decay) * np.minimum(1, t / 0.002)


def impact(note, decay=0.9):
    """A sub drop that falls into pitch, saturated so that small speakers show it."""
    f0, t = hz(note), time(decay * 4)
    f = f0 * (1 + 0.7 * np.exp(-t / 0.05))
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    return np.tanh(2.2 * y) / np.tanh(2.2) * np.minimum(1, t / 0.002)


def bass(note, duration, release=0.25):
    f, t = hz(note), time(duration + release * 5)
    phase = 2 * np.pi * f * t
    y = np.sin(phase) + 0.3 * np.sin(2 * phase) + 0.1 * np.sin(3 * phase)
    gate = np.where(t < duration, 1.0, np.exp(-(t - duration) / release))
    return np.tanh(1.4 * y) / np.tanh(1.4) * gate * np.minimum(1, t / 0.008)


def air(duration, centers, gains, width=0.8, positions=None):
    """Stereo noise whose band follows the centers (Hz). Points are (fraction of the duration, value)."""
    n = int(duration * SR)
    f, frames, spectrum = signal.stft(rng.standard_normal((2, n)), SR, nperseg=2048, noverlap=1536)
    fraction = frames / duration
    center = np.exp(np.interp(fraction, [p[0] for p in centers], np.log([p[1] for p in centers])))
    gain = np.interp(fraction, [p[0] for p in gains], [p[1] for p in gains])
    octaves = np.log2(np.maximum(f, 20))[:, None] - np.log2(center)[None, :]
    _, y = signal.istft(spectrum * (np.exp(-0.5 * (octaves / width) ** 2) * gain)[None], SR, nperseg=2048, noverlap=1536)
    y = y[:, :n]
    if positions:
        angle = (np.interp(np.arange(n) / n, [p[0] for p in positions], [p[1] for p in positions]) + 1) * np.pi / 4
        y = y * np.stack([np.cos(angle), np.sin(angle)]) * np.sqrt(2)
    return y


def pad():
    """Detuned saws through a resonant low-pass that opens with the film, over a breath of high noise.

    The saws are sums of sine partials, and each partial is scaled by the filter's response at its frequency."""
    level = envelope([(0, 0), (1.6, 0.55), (2.5, 0.7), (5.0, 0.8), (12.4, 0.9), (12.5, 1.0), (15.0, 0.85),
                      (17.4, 0.75), (17.5, 1.0), (20, 0.9)])
    cutoff = envelope([(0, 1300), (1.9, 1600), (2.5, 2400), (4.7, 2600), (5.0, 3400), (10.0, 3800), (12.4, 5500),
                       (12.5, 8000), (14.9, 6000), (16.3, 2400), (17.4, 2000), (17.5, 6000), (20, 3000)])
    out = np.zeros((2, SPAN))
    p = np.exp(-1 / (0.3 * SR))
    for note in sorted({n for _, _, notes in PAD for n in notes}):
        gate = np.zeros(SPAN)
        for start, end, notes in PAD:
            if note in notes:
                gate[int(start * SR):int(end * SR)] = 1
        env = signal.lfilter([1 - p], [1, -p], gate) * level * (0.75 if note < 50 else 1.0)
        live = np.flatnonzero(env > 1e-4)
        a, b = live[0], live[-1] + 1
        t = np.arange(a, b) / SR
        for cents, position in ((-9, -0.6), (2, 0.0), (10, 0.6)):
            f = hz(note) * 2 ** (cents / 1200) * (1 + 0.0007 * np.sin(2 * np.pi * 0.11 * t + rng.uniform(0, 6.3)))
            phase = 2 * np.pi * np.cumsum(f) / SR + rng.uniform(0, 6.3)
            wave, power = np.zeros(b - a), np.zeros(b - a)
            for k in range(1, 41):
                if hz(note) * k > 12000:
                    break
                r = hz(note) * k / cutoff[a:b]
                amp = 1 / (np.sqrt((1 - r ** 2) ** 2 + (r / 1.2) ** 2) * k)
                wave += amp * np.sin(k * phase + rng.uniform(0, 6.3))
                power += amp ** 2
            out[:, a:b] += pan(env[a:b] * wave / np.sqrt(power), position)
    breath = signal.sosfilt(butter("highpass", 5000, 4), rng.standard_normal((2, SPAN)), axis=1)
    gate = signal.lfilter([1 - p], [1, -p], (np.arange(SPAN) < 19 * SR).astype(float))
    return out + 0.06 * breath * gate * level * np.sqrt((out ** 2).mean() / (breath ** 2).mean())


# MARK: Space

def room(rt60=2.4, predelay=0.024):
    """A stereo reverb impulse: decaying noise that loses its highs first."""
    n = int((predelay + rt60 * 1.2) * SR)
    t = np.arange(n) / SR
    r = np.random.default_rng(11)
    ir = np.zeros((2, n))
    for channel in range(2):
        for sos, rt in ((butter("lowpass", 500, 4), rt60 * 1.1), (butter("bandpass", [500, 4000], 4), rt60),
                        (butter("highpass", 4000, 4), rt60 * 0.55)):
            ir[channel] += signal.sosfilt(sos, r.standard_normal(n)) * 10 ** (-3 * t / rt)
    start = int(predelay * SR)
    ir[:, :start] = 0
    ir[:, start:start + 480] *= np.linspace(0, 1, 480)
    return ir / np.sqrt((ir ** 2).sum(axis=1, keepdims=True))


def reverb(x, ir):
    mono = signal.sosfilt(butter("highpass", 180), x.mean(axis=0))
    return np.stack([signal.fftconvolve(mono, ir[c])[:x.shape[1]] for c in range(2)])


def echo(x, delay=0.75 * BEAT, feedback=0.35, taps=5):
    """Ping-pong echoes, a dotted eighth apart."""
    mono = signal.sosfilt(butter("highpass", 400), x.mean(axis=0))
    out = np.zeros_like(x)
    d = int(delay * SR)
    for k in range(1, taps + 1):
        out[k % 2, k * d:] += feedback ** k * mono[:-k * d]
    return out


def swell(notes, length, ir):
    """Chimes played backwards through the room, so they rise into the next downbeat."""
    x = np.zeros((2, int((length + 8) * SR)))
    for i, note in enumerate(notes):
        c = pan(chime(note, 1.4), -0.3 + 0.2 * i)
        x[:, :c.shape[1]] += c
    wet = reverb(x, ir)[:, ::-1]
    tail = wet[:, -int(length * SR):]
    return tail * np.minimum(1, np.arange(tail.shape[1]) / (0.3 * SR))


def duck(times, depth=0.3, recover=0.16):
    """The gain dip that each kick carves into the pad and the bass."""
    g = np.ones(SPAN)
    for at in times:
        i = int(at * SR)
        span = np.arange(SPAN - i) / SR
        g[i:] *= 1 - depth * np.exp(-span / recover) * np.minimum(1, span / 0.004)
    return g


# MARK: Measurement

def loudness(x):
    """Integrated loudness in LUFS (ITU-R BS.1770-4)."""
    y = signal.lfilter([1.53512485958697, -2.69169618940638, 1.19839281085285],
                       [1.0, -1.69065929318241, 0.73248077421585], x, axis=1)
    y = signal.lfilter([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], y, axis=1)
    block, hop = int(0.4 * SR), int(0.1 * SR)
    power = np.array([np.mean(y[:, i:i + block] ** 2, axis=1).sum() for i in range(0, y.shape[1] - block + 1, hop)])
    power = power[-0.691 + 10 * np.log10(power + 1e-20) > -70]
    gate = -0.691 + 10 * np.log10(power.mean()) - 10
    power = power[-0.691 + 10 * np.log10(power) > gate]
    return -0.691 + 10 * np.log10(power.mean())


def true_peak(x):
    return 20 * np.log10(np.abs(signal.resample_poly(x, 4, 1, axis=1)).max())


def limit(x, ceiling_db=-1.0, release=0.08, lookahead=0.005):
    """A look-ahead limiter on 4x oversampled peaks."""
    ceiling = 10 ** (ceiling_db / 20)
    peak = np.abs(signal.resample_poly(x, 4, 1, axis=1)).max(axis=0)[:x.shape[1] * 4].reshape(-1, 4).max(axis=1)
    k = int(lookahead * SR)
    need = ndimage.minimum_filter1d(np.minimum(1.0, ceiling / np.maximum(peak, 1e-9)), 2 * k + 1)
    gain, current, r = np.empty_like(need), 1.0, np.exp(-1 / (release * SR))
    for i, v in enumerate(need):
        current = v if v < current else v + (current - v) * r
        gain[i] = current
    return x * ndimage.uniform_filter1d(gain, k)


# MARK: Arrangement

def arrange(ir):
    tracks = {name: Track() for name in MIX}
    add = lambda name, sound, at, position=0.0, gain=1.0: tracks[name].add(sound, at, position, gain)

    # The keys: each press rings a note of Fmaj7, and Space sweeps into the switcher.
    for at, note, position in zip(PRESS, (65, 69, 72, 76), (-0.34, -0.21, -0.09, 0.18)):
        add("click", click(150 if note == 76 else 190), at, position)
        add("mallet", mallet(note), at, position, 0.8)
    add("air", air(0.8, [(0, 300), (0.35, 2400), (1, 900)], [(0, 0), (0.3, 1), (1, 0)], positions=[(0, 0.35), (1, 0)]),
        PRESS[3] - 0.05)

    # The switcher: → three times, then ↩ applies the theme and the new wallpaper blooms.
    for at, note in zip(MOVES, (69, 72, 76)):
        add("click", click(), at, 0.1, 0.6)
        add("mallet", mallet(note), at, 0.15)
        add("air", air(0.4, [(0, 700), (0.4, 2000), (1, 1200)], [(0, 0), (0.35, 0.5), (1, 0)],
                       positions=[(0, 0.3), (1, -0.3)]), at)
    add("click", click(160), RETURN, 0.1)
    add("mallet", mallet(77), RETURN, 0, 0.9)
    add("mallet", mallet(84), RETURN, 0, 0.5)
    add("air", air(0.9, [(0, 250), (0.5, 1800), (1, 600)], [(0, 0), (0.4, 1), (1, 0)]), RETURN + 0.02)

    # The desktop changes one part at a time, then all at once.
    for at, note in zip(WORDS, (77, 81, 84, 86)):
        add("chime", chime(note), at)
    for i, note in enumerate((72, 77, 79, 84)):
        add("mallet", mallet(note, 0.4), ALL_AT_ONCE - 0.15 + i * 0.05, -0.3 + 0.2 * i, 0.6)
    add("air", air(0.6, [(0, 800), (1, 5000)], [(0, 0), (0.8, 0.8), (1, 0)]), ALL_AT_ONCE - 0.45)
    add("chime", chime(84), ALL_AT_ONCE, 0, 0.8)

    # Theme switches on the beat, faster and higher up to the wall.
    for at, note in zip(SWITCHES, (67, 72, 74, 77, 69, 74, 76, 81, 74, 77, 81, 86)):
        add("mallet", mallet(note, 0.45), at, rng.uniform(-0.3, 0.3), 0.85)
        add("click", click(240), at, 0, 0.35)

    # Drums from the desktop to the wall: half time, then every beat, with offbeat hats and a roll into the wall.
    kicks = [5.0, 6.25] + [7.5 + i * BEAT for i in range(12)]
    for at in kicks:
        add("kick", kick(), at)
    for i in range(10):
        add("hat", hat(), 9.0625 + i * BEAT, 0.25, 0.8)
    for i in range(8):
        add("hat", hat(0.02), 11.25 + i * BEAT / 4, -0.2, 0.3 + 0.08 * i)
    add("air", air(1.9, [(0, 300), (1, 7000)], [(0, 0), (0.9, 0.7), (0.995, 1.0), (1, 0)], width=0.6), WALL - 1.9)

    add("bass", bass(34, 2.45), 5.0)
    add("bass", bass(36, 2.45), 7.5)
    for i in range(8):
        add("bass", bass(38, 0.2, 0.08), 10.0 + i * BEAT / 2)
        add("bass", bass(34, 0.2, 0.08), WALL + i * BEAT / 2)

    # The wall: the peak, then an arpeggio that thins out while the wall recedes.
    add("impact", impact(34), WALL)
    add("crash", crash(), WALL)
    add("chime", chime(81), THEMES_CAPTION, -0.2, 0.7)
    add("chime", chime(86), THEMES_CAPTION + 0.02, 0.2, 0.7)
    arp = [(12.8125 + i * BEAT / 2, n) for i, n in enumerate((70, 74, 77, 81, 84, 81, 77))]
    arp += [(15.0 + i * BEAT / 2, n) for i, n in enumerate((70, 74, 77, 81, 67, 70, 72, 77))]
    for i, (at, note) in enumerate(arp):
        fade = 1.0 if at < 15 else max(0.0, 1 - (at - 15) / 2.2)
        add("mallet", mallet(note, 0.4, 0.7), at, 0.35 if i % 2 else -0.35, 0.55 * fade)

    # The icon forms: a riser and a reversed chord pull into the end card.
    add("air", air(1.15, [(0, 400), (1, 8000)], [(0, 0), (0.9, 0.8), (0.98, 1.0), (1, 0)], width=0.5), ICON)
    add("swell", swell([65, 69, 72, 76], 1.6, ir), END - 1.6)

    # The end card: a low hit, and a chord that rolls up so its top note lands with the word.
    add("impact", impact(29, 1.2), END)
    add("bass", bass(41, 1.4, 0.4), END)
    for i, note in enumerate((77, 81, 84, 88, 91)):
        add("chime", chime(note, 2.4), END + i * BEAT / 10, -0.4 + 0.2 * i, 0.8)

    out = {name: track.x for name, track in tracks.items()}
    out["pad"] = pad()
    ducking = duck(kicks)
    out["pad"] *= ducking
    out["bass"] *= ducking
    return out


def main():
    ir = room()
    tracks = arrange(ir)
    reference = loudness(tracks["pad"])
    dry, sends = np.zeros((2, SPAN)), np.zeros((2, SPAN))
    for name, (relative, send, echoes) in MIX.items():
        x = tracks[name] * 10 ** ((reference + relative - loudness(tracks[name])) / 20)
        if echoes:
            x = x + 0.3 * echo(x)
        dry += x
        sends += send * x
    master = dry + 0.55 * reverb(sends, ir)
    master = signal.sosfilt(np.vstack([butter("highpass", 25), high_shelf(3000, 3)]), master, axis=1)[:, :N]
    master *= envelope([(0, 1), (19.3, 1), (20.0, 0)], N) ** 2
    for _ in range(3):
        master = limit(master * 10 ** ((-16 - loudness(master)) / 20))
    soundfile.write(OUT, master.T, SR, subtype="PCM_24")
    print(f"{os.path.relpath(OUT)}: {loudness(master):.1f} LUFS, true peak {true_peak(master):.1f} dBTP, {N / SR:.1f} s")


if __name__ == "__main__":
    main()
