#!/usr/bin/env python3
"""Compose et synthétise la bande originale de Legenders RPG (assets/music/*.ogg).

Tout est généré ici (aucun échantillon externe) : batterie, basse, guitares
saturées, cordes, cuivres, chœurs, flûte, piano, cloches… Chaque morceau boucle
sans coupure (les queues de notes et la réverbération reviennent au début).

Usage : python3 tools/compose_music.py            (nécessite numpy, scipy, ffmpeg)
        python3 tools/compose_music.py taverne    (un seul morceau)
"""
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 32000
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "music")

# ---------------------------------------------------------------------------
# Outils de base
# ---------------------------------------------------------------------------

NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
        "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
SCALES = {
    "major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "harmonic": [0, 2, 3, 5, 7, 8, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10], "phrygian": [0, 1, 3, 5, 7, 8, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11], "penta": [0, 3, 5, 7, 10],
}
CHORDS = {"": [0, 4, 7], "m": [0, 3, 7], "5": [0, 7, 12], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10],
          "maj7": [0, 4, 7, 11], "sus2": [0, 2, 7], "sus4": [0, 5, 7], "dim": [0, 3, 6]}


def midi(name, octave):
    return 12 * (octave + 1) + NOTE[name]


def freq(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def chord(symbol, octave=3):
    """« Am », « F », « E5 », « Cmaj7 » -> (racine midi, intervalles)."""
    name = symbol[:2] if len(symbol) > 1 and symbol[1] in "#b" else symbol[:1]
    return midi(name, octave), CHORDS[symbol[len(name):]]


def t(n):
    return np.arange(n) / SR


def lowpass(x, fc, order=2):
    fc = min(fc, SR * 0.45)
    b, a = signal.butter(order, fc / (SR / 2))
    return signal.lfilter(b, a, x)


def highpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), btype="high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], btype="band")
    return signal.lfilter(b, a, x)


def env(n, a=0.005, d=0.1, s=0.7, r=0.1):
    """Enveloppe ADSR (s = niveau de maintien), la note dure n échantillons + relâchement."""
    a_n, d_n, r_n = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    hold = max(0, n - a_n - d_n)
    e = np.concatenate([np.linspace(0, 1, a_n), np.linspace(1, s, d_n), np.full(hold, s), np.linspace(s, 0, r_n)])
    return e


def saw(f, n, detune=0.0, rng=None):
    ph = rng.random() if rng is not None else 0.0
    return 2 * ((f * (1 + detune) * t(n) + ph) % 1.0) - 1


def additive(f, n, amps, decays=None, inharm=0.0):
    tt = t(n)
    out = np.zeros(n)
    for k, amp in enumerate(amps, start=1):
        fk = f * k * np.sqrt(1 + inharm * k * k)
        if fk > SR * 0.45:
            break
        part = amp * np.sin(2 * np.pi * fk * tt)
        if decays is not None:
            part *= np.exp(-tt * decays * (1 + 0.6 * (k - 1)))
        out += part
    return out


def vibrato_sine(f, n, depth=0.004, rate=5.2, delay=0.25, harmonics=(1.0,)):
    tt = t(n)
    ramp = np.clip((tt - delay) / 0.3, 0, 1)
    inst = f * (1 + depth * ramp * np.sin(2 * np.pi * rate * tt))
    ph = 2 * np.pi * np.cumsum(inst) / SR
    return sum(a * np.sin((k + 1) * ph) for k, a in enumerate(harmonics))


# ---------------------------------------------------------------------------
# Instruments (renvoient un signal mono)
# ---------------------------------------------------------------------------

class Inst:
    def __init__(self, rng):
        self.rng = rng

    def noise(self, n):
        return self.rng.uniform(-1, 1, n)

    # --- Percussions ---
    def kick(self, hard=1.0):
        n = int(0.45 * SR)
        tt = t(n)
        f = 48 + 90 * np.exp(-tt * 28)
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7.5)
        click = self.noise(n) * np.exp(-tt * 400) * 0.4
        return np.tanh((body + click) * (1.2 + hard))

    def snare(self, tight=1.0):
        n = int(0.35 * SR)
        tt = t(n)
        nz = bandpass(self.noise(n), 1200, 9000) * np.exp(-tt * 16 * tight)
        tone = np.sin(2 * np.pi * 185 * tt) * np.exp(-tt * 28) * 0.6
        return (nz * 1.3 + tone) * 0.8

    def clap(self):
        n = int(0.3 * SR)
        tt = t(n)
        e = np.exp(-tt * 22) + 0.6 * np.exp(-np.maximum(tt - 0.012, 0) * 30) * (tt > 0.012)
        return bandpass(self.noise(n), 900, 5000) * e * 0.9

    def hat(self, open_=False):
        n = int((0.35 if open_ else 0.08) * SR)
        tt = t(n)
        return highpass(self.noise(n), 7000) * np.exp(-tt * (10 if open_ else 55)) * 0.3

    def crash(self):
        n = int(2.2 * SR)
        tt = t(n)
        return highpass(self.noise(n), 4500) * np.exp(-tt * 2.2) * 0.5

    def tom(self, f0=110):
        n = int(0.5 * SR)
        tt = t(n)
        f = f0 * (1 + 0.6 * np.exp(-tt * 20))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 7) * 0.9

    def taiko(self):
        n = int(1.0 * SR)
        tt = t(n)
        f = 62 * (1 + 0.8 * np.exp(-tt * 15))
        body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 4.5)
        skin = lowpass(self.noise(n), 900) * np.exp(-tt * 30) * 0.8
        return np.tanh((body + skin) * 1.6)

    def shaker(self):
        n = int(0.12 * SR)
        tt = t(n)
        return bandpass(self.noise(n), 4000, 11000) * np.sin(np.pi * tt / 0.12) * 0.1

    def frame_drum(self):
        n = int(0.4 * SR)
        tt = t(n)
        f = 95 * (1 + 0.3 * np.exp(-tt * 25))
        return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9) + lowpass(self.noise(n), 1500) * np.exp(-tt * 40) * 0.5) * 0.9

    # --- Basses ---
    def rock_bass(self, m, dur):
        n = int(dur * SR)
        f = freq(m)
        x = saw(f, n) * 0.6 + np.sin(2 * np.pi * f * t(n))
        x = lowpass(np.tanh(x * 1.8), 900)
        return x * env(n, 0.004, 0.15, 0.75, 0.05)[:n]

    def soft_bass(self, m, dur):
        n = int(dur * SR)
        f = freq(m)
        x = np.sin(2 * np.pi * f * t(n)) + 0.25 * np.sin(4 * np.pi * f * t(n))
        return x * env(n, 0.01, 0.3, 0.6, 0.12)[:n]

    def sub(self, m, dur):
        n = int(dur * SR)
        return np.sin(2 * np.pi * freq(m) * t(n)) * env(n, 0.3, 0.5, 0.9, 0.5)[:n]

    # --- Guitares ---
    def power_chord(self, m, dur, mute=False, voicing=(0, 7, 12)):
        n = int(dur * SR)
        x = np.zeros(n)
        for iv in voicing:
            for dt in (-0.0025, 0.0025):
                x += saw(freq(m + iv), n, dt, self.rng)
        x = highpass(x, 90)
        x = np.tanh(x * (7 if not mute else 5))
        x = lowpass(x, 1700 if mute else 3800)
        e = env(n, 0.003, 0.12 if mute else 0.4, 0.15 if mute else 0.8, 0.04)[:n]
        return x * e * 0.5

    def lead_guitar(self, m, dur):
        n = int(dur * SR)
        tt = t(n)
        f = freq(m) * (1 + 0.006 * np.clip((tt - 0.18) / 0.2, 0, 1) * np.sin(2 * np.pi * 5.5 * tt))
        ph = np.cumsum(f) / SR
        x = 2 * (ph % 1) - 1 + 0.5 * (2 * ((ph * 2.003) % 1) - 1)
        x = lowpass(np.tanh(highpass(x, 150) * 6), 3200)
        return x * env(n, 0.006, 0.2, 0.85, 0.08)[:n] * 0.45

    def clean_guitar(self, m, dur):
        n = int(dur * SR)
        x = additive(freq(m), n, [1, 0.6, 0.35, 0.25, 0.15, 0.1, 0.06], decays=2.2)
        return x * env(n, 0.002, 0.05, 1.0, 0.08)[:n] * 0.4

    # --- Claviers et cordes ---
    def piano(self, m, dur):
        n = int(max(dur, 1.6) * SR)
        x = additive(freq(m), n, [1, 0.5, 0.3, 0.18, 0.1, 0.06, 0.03], decays=1.4, inharm=0.0004)
        hammer = lowpass(self.noise(n), 3000) * np.exp(-t(n) * 120) * 0.08
        return (x + hammer) * env(n, 0.002, 0.05, 1.0, 0.15)[:n] * 0.35

    def epiano(self, m, dur):
        n = int(max(dur, 1.2) * SR)
        tt = t(n)
        f = freq(m)
        mod = np.sin(2 * np.pi * f * tt) * 1.2 * np.exp(-tt * 3)
        x = np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt * 1.3)
        return x * env(n, 0.002, 0.05, 1.0, 0.2)[:n] * 0.35

    def organ(self, m, dur):
        n = int(dur * SR)
        x = additive(freq(m), n, [1, 0.8, 0.5, 0.0, 0.3, 0.0, 0.0, 0.2])
        return x * env(n, 0.02, 0.05, 1.0, 0.1)[:n] * 0.22

    def pad(self, m, dur, bright=1200.0):
        n = int(dur * SR)
        x = sum(saw(freq(m), n, d, self.rng) for d in (-0.006, -0.002, 0.003, 0.007))
        x = lowpass(x, bright)
        return x * env(n, 0.45, 0.6, 0.85, 0.9)[:n] * 0.12

    def strings(self, m, dur, bright=2600.0):
        n = int(dur * SR)
        tt = t(n)
        x = np.zeros(n)
        for d in (-0.004, 0.0, 0.005):
            fv = freq(m) * (1 + d) * (1 + 0.003 * np.sin(2 * np.pi * (5 + d * 100) * tt))
            ph = np.cumsum(fv) / SR + self.rng.random()
            x += 2 * (ph % 1) - 1
        x = lowpass(x, bright)
        return x * env(n, 0.18, 0.4, 0.9, 0.5)[:n] * 0.14

    def staccato(self, m, dur):
        n = int(min(dur, 0.25) * SR)
        x = sum(saw(freq(m), n, d, self.rng) for d in (-0.004, 0.004))
        return lowpass(x, 3000) * env(n, 0.005, 0.12, 0.1, 0.05)[:n] * 0.25

    def brass(self, m, dur):
        n = int(dur * SR)
        tt = t(n)
        x = sum(saw(freq(m), n, d, self.rng) for d in (-0.003, 0.003))
        cutoff = 900 + 2200 * (1 - np.exp(-tt * 12))
        # Filtre qui s'ouvre : on mélange deux versions filtrées.
        lo, hi = lowpass(x, 900), lowpass(x, 3100)
        mix = np.clip((cutoff - 900) / 2200, 0, 1)
        y = lo * (1 - mix) + hi * mix
        return np.tanh(y * 1.5) * env(n, 0.04, 0.2, 0.8, 0.15)[:n] * 0.3

    def choir(self, m, dur, vowel="a"):
        n = int(dur * SR)
        src = sum(saw(freq(m), n, d, self.rng) for d in (-0.005, 0.0, 0.006))
        formants = {"a": [(800, 1.0), (1150, 0.5), (2900, 0.25)], "o": [(450, 1.0), (800, 0.45), (2830, 0.15)]}[vowel]
        y = sum(g * bandpass(src, f * 0.88, f * 1.12) for f, g in formants)
        return y * env(n, 0.5, 0.6, 0.9, 1.0)[:n] * 0.5

    # --- Mélodiques ---
    def pluck(self, m, dur):
        n = int(max(dur, 1.0) * SR)
        x = additive(freq(m), n, [1, 0.7, 0.45, 0.3, 0.2, 0.12, 0.08, 0.05], decays=3.2)
        return x * env(n, 0.001, 0.05, 1.0, 0.1)[:n] * 0.35

    def harp(self, m, dur):
        n = int(max(dur, 1.8) * SR)
        x = additive(freq(m), n, [1, 0.4, 0.2, 0.1, 0.05], decays=1.6)
        return x * env(n, 0.002, 0.05, 1.0, 0.2)[:n] * 0.35

    def flute(self, m, dur):
        n = int(dur * SR)
        x = vibrato_sine(freq(m), n, harmonics=(1.0, 0.18, 0.06))
        breath = bandpass(self.noise(n), 1500, 6000) * 0.04
        return (x + breath) * env(n, 0.07, 0.1, 0.85, 0.12)[:n] * 0.35

    def bell(self, m, dur):
        n = int(max(dur, 2.5) * SR)
        tt = t(n)
        f = freq(m)
        x = sum(a * np.sin(2 * np.pi * f * r * tt) * np.exp(-tt * d) for r, a, d in
                [(1, 1, 1.2), (2.0, 0.5, 1.8), (2.76, 0.35, 2.4), (5.4, 0.2, 4), (8.93, 0.1, 6)])
        return x * env(n, 0.001, 0.05, 1.0, 0.3)[:n] * 0.22

    def synth_lead(self, m, dur):
        n = int(dur * SR)
        x = sum(np.sign(np.sin(2 * np.pi * freq(m) * (1 + d) * t(n))) for d in (-0.004, 0.004))
        return lowpass(x, 2600) * env(n, 0.01, 0.1, 0.7, 0.08)[:n] * 0.14

    def arp_synth(self, m, dur):
        n = int(min(dur, 0.3) * SR)
        x = saw(freq(m), n) + saw(freq(m), n, 0.005)
        return lowpass(x, 2400) * env(n, 0.002, 0.12, 0.2, 0.05)[:n] * 0.2


# ---------------------------------------------------------------------------
# Séquenceur
# ---------------------------------------------------------------------------

class Song:
    def __init__(self, bpm, bars, beats=4, seed=1, swing=0.0):
        self.bpm, self.bars, self.beats = bpm, bars, beats
        self.spb = 60.0 / bpm
        self.n = int(round(bars * beats * self.spb * SR))
        self.mix = np.zeros((self.n, 2))
        self.verb = np.zeros((self.n, 2))
        self.rng = np.random.default_rng(seed)
        self.inst = Inst(self.rng)
        self.swing = swing

    def at(self, bar, beat):
        b = bar * self.beats + beat
        frac = b - np.floor(b)
        if self.swing and abs(frac - 0.5) < 1e-6:
            b += self.swing * 0.5
        return int(round(b * self.spb * SR))

    def beats_to_sec(self, beats):
        return beats * self.spb

    def place(self, x, start, gain=1.0, pan=0.0, verb=0.2, human=True):
        if human:
            start += int(self.rng.normal(0, 0.004) * SR)
            gain *= 1 + self.rng.normal(0, 0.05)
        l, r = gain * np.cos((pan + 1) * np.pi / 4), gain * np.sin((pan + 1) * np.pi / 4)
        stereo = np.stack([x * l, x * r], axis=1)
        # Les queues de notes qui dépassent la fin reviennent au début : boucle parfaite.
        pos = start % self.n
        k = 0
        while k < len(stereo):
            chunk = stereo[k:k + self.n - pos]
            self.mix[pos:pos + len(chunk)] += chunk
            if verb > 0:
                self.verb[pos:pos + len(chunk)] += chunk * verb
            k += len(chunk)
            pos = 0

    def note(self, fn, m, bar, beat, beats, gain=1.0, pan=0.0, verb=0.2):
        self.place(fn(m, self.beats_to_sec(beats)), self.at(bar, beat), gain, pan, verb)

    def drums(self, pattern, bars, kit, gain=1.0, verb=0.08):
        """pattern : {instrument: « x...x...x...x... »} (16 pas par mesure en 4/4,
        12 pas en 6/8). Majuscule = accent."""
        for bar in bars:
            for name, steps in pattern.items():
                step_beats = self.beats / len(steps)
                for i, c in enumerate(steps):
                    if c in ".-":
                        continue
                    sample = kit[name]()
                    g = gain * (1.0 if c.isupper() or c == "x" else 0.6)
                    pan = {"hat": 0.25, "ohat": 0.25, "shaker": -0.3, "tom": -0.2, "crash": 0.15}.get(name, 0.0)
                    self.place(sample, self.at(bar, i * step_beats), g, pan, verb)

    def render(self, wet=0.25, decay=2.2, width=1.0):
        ir_n = int(decay * SR)
        tt = t(ir_n)
        out = self.mix.copy()
        for ch in range(2):
            ir = self.rng.normal(0, 1, ir_n) * np.exp(-tt * 6.9 / decay)
            ir = lowpass(ir, 5000)
            ir[: int(0.012 * SR)] = 0
            ir /= np.sqrt(np.sum(ir ** 2))
            wetc = signal.fftconvolve(self.verb[:, ch], ir)
            full = np.zeros(self.n)
            for k in range(0, len(wetc), self.n):  # réverbération circulaire (boucle sans coupure)
                seg = wetc[k:k + self.n]
                full[: len(seg)] += seg
            out[:, ch] += full * wet * 3
        mid, side = (out[:, 0] + out[:, 1]) / 2, (out[:, 0] - out[:, 1]) / 2 * width
        out = np.stack([mid + side, mid - side], axis=1)
        out = highpass(out.T, 30).T
        peak = np.max(np.abs(out)) + 1e-9
        out = np.tanh(out / peak * 1.25) / np.tanh(1.25) * 0.93
        return out


def chord_tones(sym, octave=3):
    root, iv = chord(sym, octave)
    return [root + i for i in iv]


def scale_notes(key, mode, lo, hi):
    base = NOTE[key]
    return [m for m in range(lo, hi + 1) if (m - base) % 12 in SCALES[mode]]


def melody(rng, prog, key, mode, lo, hi, rhythms, bars_per_phrase=4):
    """Mélodie : motif de 2 mesures répété avec variations, notes fortes sur les accords."""
    sc = scale_notes(key, mode, lo, hi)
    out = []
    motif = None
    prev = sc[len(sc) // 2]
    for i, sym in enumerate(prog):
        tones = {m % 12 for m in chord_tones(sym)}
        if i % 2 == 0 or motif is None:
            rhythm = rhythms[rng.integers(len(rhythms))]
            bar_notes = []
            for j, (beat, length) in enumerate(rhythm):
                strong = beat == int(beat) and int(beat) % 2 == 0
                cands = [m for m in sc if abs(m - prev) <= (7 if strong else 4)]
                if strong:
                    cands = [m for m in cands if m % 12 in tones] or cands
                weights = np.array([1.0 / (1 + abs(m - prev)) for m in cands])
                prev = int(rng.choice(cands, p=weights / weights.sum()))
                bar_notes.append((beat, length, prev))
            motif = bar_notes
        else:
            # Variation : même rythme, transposé vers les notes de l'accord, fin modifiée.
            bar_notes = []
            for beat, length, m in motif:
                cands = [x for x in sc if abs(x - m) <= 2]
                target = [x for x in cands if x % 12 in tones]
                prev = int(rng.choice(target or cands))
                bar_notes.append((beat, length, prev))
        out.append(bar_notes)
    return out


def play_melody(song, mel, fn, gain, pan=0.0, verb=0.3, bar_offset=0):
    for i, notes in enumerate(mel):
        for beat, length, m in notes:
            song.note(fn, m, bar_offset + i, beat, length, gain, pan, verb)


def kit(song):
    I = song.inst
    return {"kick": I.kick, "snare": I.snare, "hat": I.hat, "ohat": lambda: I.hat(True), "crash": I.crash,
            "clap": I.clap, "tom": I.tom, "taiko": I.taiko, "shaker": I.shaker, "frame": I.frame_drum,
            "ltom": lambda: I.tom(80)}


R_ROCK = [[(0, 1), (1, 0.5), (1.5, 0.5), (2, 1.5), (3.5, 0.5)], [(0, 0.5), (0.5, 0.5), (1, 1), (2, 1), (3, 1)],
          [(0, 1.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 1)], [(0, 2), (2, 1), (3, 0.5), (3.5, 0.5)]]
R_CALM = [[(0, 2), (2, 2)], [(0, 1.5), (1.5, 0.5), (2, 2)], [(0, 1), (1, 1), (2, 2)], [(0, 3), (3, 1)]]
R_68 = [[(0, 1.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5)], [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 1.5)],
        [(0, 1), (1, 0.5), (1.5, 1), (2.5, 0.5)]]

# ---------------------------------------------------------------------------
# Morceaux
# ---------------------------------------------------------------------------


def rock_section(song, prog, start, riff="x.x.xxx.x.x.xx.x", mute_steps=None, gtr_gain=0.9, bass_gain=0.9):
    """Guitares rythmiques doublées (gauche/droite) + basse sur un motif de 16 pas."""
    I = song.inst
    for i, sym in enumerate(prog):
        root, iv = chord(sym, 2)
        voicing = (0, 7, 12) if "m" not in sym or sym.endswith("5") else (0, 7, 12)
        for k, c in enumerate(riff):
            if c == ".":
                continue
            length = 0.25
            j = k + 1
            while j < len(riff) and riff[j] == "-":
                length += 0.25
                j += 1
            mute = c == "x"
            for pan in (-0.7, 0.7):
                song.note(lambda m, d: I.power_chord(m, d, mute, voicing), root + 12, start + i, k * 0.25, length, gtr_gain, pan, 0.12)
            song.note(I.rock_bass, root, start + i, k * 0.25, length, bass_gain, 0.0, 0.03)


def track_poing_de_braise():
    s = Song(160, 40, seed=11)
    K = kit(s)
    intro = ["E5", "E5", "C5", "D5"]
    a = ["E5", "C5", "D5", "E5"] * 2
    b = ["G5", "D5", "C5", "D5", "E5", "C5", "D5", "B5"]
    prog = intro + a + b + a + b + ["E5", "C5", "D5", "B5"]
    groove = {"kick": "X.x...x.x.x...x.", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.x."}
    fill = {"kick": "X.x...x.x.......", "snare": "....X.....xxXxXX", "hat": "x.x.x.x.x......."}
    rock_section(s, intro, 0, riff="X-------x.x.x.x.")
    rock_section(s, prog[4:], 4, riff="x.x.xxX-x.x.xxX-")
    s.drums({"kick": "X...............", "crash": "X..............."}, [0, 2], K)
    s.drums({"tom": "........X.X.XXXX"}, [3], K)
    for bar in range(4, 40):
        s.drums(fill if bar % 8 == 7 else groove, [bar], K)
        if bar % 8 == 4:
            s.drums({"crash": "X..............."}, [bar], K)
    mel = melody(s.rng, b * 2, "E", "minor", 64, 81, R_ROCK)
    play_melody(s, mel[:8], s.inst.lead_guitar, 0.75, 0.1, 0.35, bar_offset=12)
    play_melody(s, mel[8:], s.inst.lead_guitar, 0.75, -0.1, 0.35, bar_offset=28)
    return s.render(wet=0.18, decay=1.6)


def track_gardien_du_dragon():
    s = Song(96, 32, seed=21)
    K = kit(s)
    prog = ["C#5", "C#5", "D5", "C#5", "C#5", "C#5", "A5", "B5"] * 4
    rock_section(s, prog, 0, riff="X.xxX.xxX.xxX-x.", gtr_gain=1.0)
    for bar in range(32):
        s.drums({"kick": "xxxxxxxxxxxxxxxx" if bar >= 16 else "X..xX..xX..xX..x", "snare": "........X.......",
                 "hat": "x...x...x...x..."}, [bar], K, 0.85)
        if bar % 4 == 0:
            s.drums({"crash": "X..............."}, [bar], K)
    for bar in range(0, 32, 2):
        sym = prog[bar]
        for m in chord_tones(sym.replace("5", "m"), 4):
            s.note(lambda mm, d: s.inst.choir(mm, d, "o"), m, bar, 0, 8, 0.5, 0.0, 0.6)
    mel = melody(s.rng, prog[16:], "C#", "phrygian", 61, 76, R_CALM)
    play_melody(s, mel, s.inst.lead_guitar, 0.7, 0.0, 0.4, bar_offset=16)
    return s.render(wet=0.3, decay=2.6)


def track_test_de_la_magie():
    s = Song(128, 40, seed=31)
    K = kit(s)
    verse = ["Am", "F", "C", "G"]
    chorus = ["F", "G", "Am", "Am", "F", "G", "C", "E"]
    prog = verse * 2 + verse * 2 + chorus + verse * 2 + chorus
    roots = [p if p.endswith("m") is False else p for p in prog]
    rock_section(s, [p.rstrip("m") + "5" for p in prog[:8]], 0, riff="x.x.x.x.x.x.x.x.", gtr_gain=0.6)
    rock_section(s, [p.rstrip("m") + "5" for p in prog[8:]], 8, riff="X-x.X-x.X-x.X.x.")
    for bar in range(40):
        g = {"kick": "X.....x.X.......", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.x."}
        if bar < 8:
            g = {"kick": "X.......X.......", "hat": "x...x...x...x..."}
        s.drums(g, [bar], K)
        if bar % 8 == 0:
            s.drums({"crash": "X..............."}, [bar], K)
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 4):
            s.note(s.inst.strings, m, i, 0, 4, 0.55, 0.0, 0.4)
    mel = melody(s.rng, chorus * 2, "A", "minor", 64, 81, R_ROCK)
    play_melody(s, mel[:8], s.inst.lead_guitar, 0.7, 0.0, 0.35, bar_offset=16)
    play_melody(s, mel[8:], s.inst.lead_guitar, 0.7, 0.0, 0.35, bar_offset=32)
    return s.render(wet=0.22, decay=2.0)


def track_chevaliers_de_pik():
    s = Song(112, 32, seed=41)
    K = kit(s)
    prog = ["Gm", "Eb", "Bb", "F", "Gm", "Eb", "D", "D", "Cm", "Eb", "Gm", "F", "Cm", "Eb", "D", "D"] * 2
    march = {"snare": "X.xxX.x.X.xxX.xx", "kick": "X.......X.......", "taiko": "X...............".replace(".", ".", 1)}
    for bar in range(32):
        s.drums(march, [bar], K, 0.8)
        if bar % 4 == 0:
            s.drums({"crash": "X..............."}, [bar], K)
    rock_section(s, [p.rstrip("m") + "5" for p in prog], 0, riff="X-x.x.X-x.x.X-X-", gtr_gain=0.7)
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 3):
            s.note(s.inst.brass, m + 12, i, 0, 2, 0.5, -0.3, 0.35)
            s.note(s.inst.brass, m + 12, i, 2.5, 1.5, 0.45, 0.3, 0.35)
    mel = melody(s.rng, prog, "G", "minor", 62, 79, R_ROCK)
    play_melody(s, mel, s.inst.brass, 1.0, 0.0, 0.4)
    return s.render(wet=0.3, decay=2.4)


def track_course():
    s = Song(140, 32, seed=51)
    K = kit(s)
    prog = ["Bm", "G", "D", "A"] * 4 + ["Em", "G", "Bm", "F#"] * 4
    for bar in range(32):
        s.drums({"kick": "X...X...X...X...", "clap": "....X.......X...", "hat": "..x...x...x...x.",
                 "shaker": "xxxxxxxxxxxxxxxx"}, [bar], K, 0.85)
    for i, sym in enumerate(prog):
        tones = chord_tones(sym, 4)
        seq = [tones[0], tones[1], tones[2], tones[1] + 12 if len(tones) > 1 else tones[0]] * 4
        for k, m in enumerate(seq):
            s.note(s.inst.arp_synth, m, i, k * 0.25, 0.25, 0.8, 0.35 if k % 2 else -0.35, 0.25)
        root = chord(sym, 2)[0]
        for k in range(8):
            s.note(s.inst.rock_bass, root + (12 if k % 2 else 0), i, k * 0.5, 0.45, 0.8, 0.0, 0.02)
        if i >= 16:
            for m in chord_tones(sym, 3):
                s.note(lambda mm, d: s.inst.power_chord(mm, d, False), m, i, 0, 4, 0.25, -0.6 if m % 2 else 0.6, 0.1)
    mel = melody(s.rng, prog[16:], "B", "minor", 66, 83, R_ROCK)
    play_melody(s, mel, s.inst.synth_lead, 1.0, 0.0, 0.3, bar_offset=16)
    return s.render(wet=0.2, decay=1.8)


def track_kurtzuma():
    s = Song(84, 32, seed=61)
    K = kit(s)
    prog = ["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"] * 4
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 3):
            s.note(s.inst.strings, m, i, 0, 4, 0.7, 0.0, 0.5)
            s.note(s.inst.strings, m + 12, i, 0, 4, 0.45, 0.0, 0.5)
        s.note(s.inst.soft_bass, chord(sym, 2)[0], i, 0, 4, 0.9, 0.0, 0.1)
        if i >= 8:
            for k in range(8):
                s.note(s.inst.staccato, chord_tones(sym, 3)[k % 3] + 12, i, k * 0.5, 0.5, 0.6, -0.4, 0.2)
        if i >= 16:
            for m in chord_tones(sym, 4):
                s.note(lambda mm, d: s.inst.choir(mm, d, "a"), m, i, 0, 4, 0.35, 0.0, 0.7)
    for bar in range(8, 32):
        s.drums({"taiko": "X.....x.X...x...", "ltom": "..........x.x.x."}, [bar], K, 0.75, 0.3)
        if bar % 8 == 0:
            s.drums({"crash": "X..............."}, [bar], K)
    mel = melody(s.rng, prog[8:], "D", "minor", 62, 81, R_CALM)
    play_melody(s, mel, s.inst.brass, 1.0, 0.0, 0.45, bar_offset=8)
    return s.render(wet=0.35, decay=3.0)


def track_victoire():
    s = Song(120, 16, seed=71)
    K = kit(s)
    prog = ["Bb", "F", "Gm", "Eb", "Bb", "F", "Eb", "F"] * 2
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 3):
            s.note(s.inst.brass, m + 12, i, 0, 1.5, 0.5, -0.3, 0.3)
            s.note(s.inst.brass, m + 12, i, 2, 2, 0.5, 0.3, 0.3)
            s.note(s.inst.strings, m, i, 0, 4, 0.5, 0.0, 0.4)
        s.note(s.inst.soft_bass, chord(sym, 2)[0], i, 0, 4, 0.9)
    for bar in range(16):
        s.drums({"snare": "X.xxX...X.xxX.x.", "kick": "X.......X.......", "hat": "x.x.x.x.x.x.x.x."}, [bar], K, 0.7)
        if bar % 4 == 0:
            s.drums({"crash": "X..............."}, [bar], K)
    mel = melody(s.rng, prog, "Bb", "major", 65, 82, R_ROCK)
    play_melody(s, mel, s.inst.brass, 1.1, 0.0, 0.4)
    play_melody(s, [[(b, l, m + 12) for b, l, m in bar] for bar in mel[8:]], s.inst.bell, 0.4, 0.3, 0.5, 8)
    return s.render(wet=0.3, decay=2.2)


def track_taverne():
    s = Song(116, 32, beats=3, seed=81)  # 6/8 : 3 temps pointés -> 3 « noires » de 2 croches
    K = kit(s)
    prog = ["G", "C", "G", "D", "G", "C", "D", "G", "Em", "C", "G", "D", "Em", "C", "D", "D"] * 2
    for i, sym in enumerate(prog):
        tones = chord_tones(sym, 3)
        pattern = [tones[0], tones[2], tones[1] + 12, tones[2], tones[1] + 12, tones[2]]
        for k, m in enumerate(pattern):
            s.note(s.inst.pluck, m, i, k * 0.5, 0.5, 0.75, -0.4, 0.25)
        s.note(s.inst.soft_bass, chord(sym, 2)[0], i, 0, 1.5, 0.9)
        s.note(s.inst.soft_bass, chord(sym, 2)[0] + 7, i, 1.5, 1.5, 0.7)
    for bar in range(32):
        s.drums({"frame": "X..x.xX..x..", "shaker": "x.xx.xx.xx.x"}, [bar], K, 0.8, 0.15)
    mel = melody(s.rng, prog, "G", "major", 67, 86, R_68)
    play_melody(s, mel, s.inst.flute, 1.0, 0.25, 0.35)
    play_melody(s, [[(b, l, m - 12) for b, l, m in bar] for bar in mel[16:]], s.inst.clean_guitar, 0.6, -0.2, 0.3, 16)
    return s.render(wet=0.2, decay=1.4)


def track_valombre():
    s = Song(66, 24, seed=91)
    prog = ["Dm", "Dm", "Bb", "A", "Dm", "Gm", "Bb", "A"] * 3
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 3):
            s.note(s.inst.pad, m, i, 0, 4, 0.9, 0.0, 0.6)
        s.note(s.inst.sub, chord(sym, 1)[0] + 12, i, 0, 4, 0.6, 0.0, 0.2)
    mel = melody(s.rng, prog, "D", "harmonic", 62, 77, R_CALM)
    for i, bar in enumerate(mel):
        if i % 4 in (0, 1, 2):
            for b, l, m in bar:
                s.note(s.inst.piano, m, i, b, l, 0.9, 0.2, 0.6)
    for i in range(0, 24, 2):
        s.note(s.inst.bell, chord_tones(prog[i], 5)[s.rng.integers(3)], i, 3, 1, 0.35, -0.5, 0.8)
    return s.render(wet=0.45, decay=3.5, width=1.2)


def track_foret():
    s = Song(96, 32, seed=101)
    K = kit(s)
    prog = ["Em", "D", "C", "D", "Em", "D", "C", "B"] * 2 + ["Am", "Em", "C", "D"] * 4
    for i, sym in enumerate(prog):
        tones = chord_tones(sym, 4)
        arp = [tones[0], tones[1], tones[2], tones[1]] * 2
        for k, m in enumerate(arp):
            s.note(s.inst.harp, m, i, k * 0.5, 0.5, 0.7, 0.35, 0.35)
        for m in chord_tones(sym, 3):
            s.note(s.inst.pad, m, i, 0, 4, 0.6, -0.2, 0.5)
        s.note(s.inst.soft_bass, chord(sym, 2)[0], i, 0, 3, 0.8)
    for bar in range(8, 32):
        s.drums({"frame": "X.....x...x.....", "shaker": "..x...x...x...x."}, [bar], K, 0.6, 0.2)
    mel = melody(s.rng, prog, "E", "dorian", 64, 83, R_CALM)
    play_melody(s, mel[8:], s.inst.flute, 0.95, -0.15, 0.4, 8)
    return s.render(wet=0.3, decay=2.4)


def track_shima():
    s = Song(90, 32, seed=111, swing=0.18)
    K = kit(s)
    prog = ["Fmaj7", "Em7", "Dm7", "Cmaj7"] * 4 + ["Bb", "Am", "Gm", "C"] * 4
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 3):
            s.note(s.inst.epiano, m + 12, i, 0, 1.5, 0.8, -0.2, 0.3)
            s.note(s.inst.epiano, m + 12, i, 2.5, 1.0, 0.6, -0.2, 0.3)
        r = chord(sym, 2)[0]
        for b, l, off in [(0, 0.75, 0), (1, 0.5, 7), (1.5, 0.5, 12), (2.5, 0.5, 10), (3, 1, 7)]:
            s.note(s.inst.rock_bass, r + off, i, b, l, 0.7, 0.0, 0.02)
    for bar in range(32):
        s.drums({"kick": "X......x..X.....", "snare": "....X.......X...", "hat": "x.x.x.x.x.x.x.xx"}, [bar], K, 0.75, 0.1)
    mel = melody(s.rng, prog[16:], "F", "major", 65, 81, R_ROCK)
    play_melody(s, mel, s.inst.clean_guitar, 1.0, 0.3, 0.3, 16)
    return s.render(wet=0.2, decay=1.6)


def track_abime():
    s = Song(56, 20, seed=121)
    prog = ["Cm", "Cm", "Ab", "Ab", "Fm", "Fm", "G", "G"] * 2 + ["Cm", "Ab", "Fm", "G"]
    for i, sym in enumerate(prog):
        for m in chord_tones(sym, 2):
            s.note(lambda mm, d: s.inst.pad(mm, d, 600), m, i, 0, 4.5, 1.0, 0.0, 0.7)
        s.note(lambda mm, d: s.inst.choir(mm, d, "o"), chord_tones(sym, 4)[0], i, 0, 4, 0.4, 0.4, 0.8)
        if i % 2 == 0:
            s.note(s.inst.sub, chord(sym, 1)[0], i, 0, 8, 0.9, 0.0, 0.2)
    for i in range(20):
        s.note(s.inst.bell, chord_tones(prog[i], 5)[s.rng.integers(3)], i, s.rng.choice([0.5, 1.5, 2.5]), 2, 0.25, float(s.rng.uniform(-0.7, 0.7)), 0.9)
    return s.render(wet=0.55, decay=4.5, width=1.3)


def track_desert():
    s = Song(80, 24, seed=131)
    prog = ["Bm", "G", "D", "A", "Bm", "G", "Em", "F#"] * 3
    wind = s.inst.noise(s.n)
    wind = bandpass(wind, 400, 1600) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t(s.n))) * 0.05
    s.place(wind, 0, 1.0, 0.0, 0.3, human=False)
    for i, sym in enumerate(prog):
        tones = chord_tones(sym, 5)
        arp = [tones[0], tones[2], tones[1], tones[2]] * 4
        for k, m in enumerate(arp):
            s.note(s.inst.bell, m, i, k * 0.25, 0.25, 0.35, 0.5 if k % 2 else -0.5, 0.6)
        for m in chord_tones(sym, 3):
            s.note(lambda mm, d: s.inst.pad(mm, d, 2200), m, i, 0, 4, 0.7, 0.0, 0.6)
    mel = melody(s.rng, prog[8:], "B", "minor", 66, 83, R_CALM)
    play_melody(s, mel, s.inst.flute, 0.8, 0.0, 0.6, 8)
    return s.render(wet=0.45, decay=3.5, width=1.2)


def track_campement():
    s = Song(72, 24, seed=141)
    prog = ["C", "Am", "F", "G", "C", "Em", "F", "G"] * 3
    for i, sym in enumerate(prog):
        tones = chord_tones(sym, 3)
        pick = [tones[0], tones[2], tones[1] + 12, tones[2], tones[0] + 12, tones[2], tones[1] + 12, tones[2]]
        for k, m in enumerate(pick):
            s.note(s.inst.clean_guitar, m, i, k * 0.5, 0.5, 0.8, -0.3, 0.3)
        s.note(s.inst.soft_bass, chord(sym, 2)[0], i, 0, 4, 0.6)
        for m in chord_tones(sym, 4):
            s.note(s.inst.pad, m, i, 0, 4, 0.35, 0.3, 0.5)
    mel = melody(s.rng, prog[8:], "C", "major", 64, 81, R_CALM)
    play_melody(s, mel, s.inst.flute, 0.8, 0.25, 0.45, 8)
    return s.render(wet=0.3, decay=2.4)


TRACKS = [
    ("kurtzuma", "Kurtzuma (thème principal)", "Épique", track_kurtzuma),
    ("chevaliers_de_pik", "Les chevaliers mages de Pik", "Épique", track_chevaliers_de_pik),
    ("victoire", "Victoire !", "Épique", track_victoire),
    ("poing_de_braise", "Poing de braise", "Combat (rock)", track_poing_de_braise),
    ("gardien_du_dragon", "Gardien du Dragon", "Combat (rock)", track_gardien_du_dragon),
    ("test_de_la_magie", "Le test de la magie", "Aventure (rock)", track_test_de_la_magie),
    ("course_contre_la_montre", "Course contre la montre", "Tension", track_course),
    ("taverne", "Taverne du Corbeau Rieur", "Taverne", track_taverne),
    ("shima", "Shima, cité des mages", "Ville", track_shima),
    ("foret_monde", "La Forêt-Monde", "Exploration", track_foret),
    ("desert_de_cristal", "Le Désert de Cristal", "Exploration", track_desert),
    ("valombre", "Valombre sous les cendres", "Mystère", track_valombre),
    ("abime_englouti", "L'Abîme englouti", "Mystère", track_abime),
    ("campement", "Repos au campement", "Repos", track_campement),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    manifest = []
    for tid, title, mood, fn in TRACKS:
        path = os.path.join(OUT, tid + ".ogg")
        if not only or tid in only:
            audio = fn()
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                wavfile.write(tmp.name, SR, (audio * 32767).astype(np.int16))
                subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "2", path], check=True)
            os.unlink(tmp.name)
            print(f"{tid:26s} {len(audio) / SR:6.1f} s  {os.path.getsize(path) / 1e6:.2f} Mo")
        manifest.append({"id": tid, "title": title, "mood": mood, "file": "res://assets/music/%s.ogg" % tid})
    with open(os.path.join(ROOT, "data", "music.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
