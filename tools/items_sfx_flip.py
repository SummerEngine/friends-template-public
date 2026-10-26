#!/usr/bin/env python3
"""The template's FLIP sounds, made procedurally (numpy only, fixed seed): demo/audio/items/flip_use.ogg and flip_hit.ogg, a record scratch and a tape rewind.

    python3 tools/items_sfx_flip.py

Mono Ogg Vorbis, under 2 s and 100 KB, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled: a sine-and-noise "sample" played back at a hand's
changing speed makes the scratch, noise through a sweeping filter makes the rewind.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, bandpass, decay, one_pole, place, t_axis


def vinyl_source(phase):
    """The 'record': a nasal vowel-ish buzz (a few harmonics with a formant bump) read at `phase` (cycles)."""
    out = np.zeros_like(phase)
    for h in range(1, 14):
        out += np.sin(2 * np.pi * phase * h) / h * (1.0 + 1.8 * np.exp(-((h - 4.0) ** 2) / 3.0))
    return out


def scratch(rng, seconds, speeds, base=210.0, grit=0.12):
    """A hand moving the record: `speeds` is a function of t (1 = playing speed, negative = backwards); it is loudest when the record moves fast and silent when it stops."""
    t = t_axis(seconds)
    v = speeds(t)
    phase = np.cumsum(base * v) / SR
    tone = vinyl_source(phase)
    gain = np.minimum(np.abs(v) / 0.5, 1.0) ** 0.8
    noise = one_pole(rng.standard_normal(len(t)), 5000.0, "high") * grit * np.minimum(np.abs(v), 1.5)
    return (tone * 0.35 + noise) * gain


def rewind(rng, seconds, f0, f1, peak_at=0.6):
    """Tape rewind / reverse swoosh: noise through a bandpass sweeping f0 -> f1, swelling to a peak then stopping short."""
    t = t_axis(seconds)
    f = f0 * (f1 / f0) ** (t / seconds)
    n = rng.standard_normal(len(t))
    y = one_pole(one_pole(n, f * 1.6, "low"), f * 0.5, "high")
    swell = (t / (seconds * peak_at)).clip(0, 1) ** 2 * np.exp(-np.maximum(t - seconds * peak_at, 0) / 0.03)
    return y * swell


def flip_use(rng):
    """The user's own: a quick scratch back and forth, then a short rewind whoosh. About 0.65 s."""
    out = np.zeros(int(0.7 * SR))
    place(out, scratch(rng, 0.34, lambda t: 2.2 * np.sin(2 * np.pi * 3.2 * t) * np.exp(-t / 0.3) + 0.3), 0.0)
    place(out, rewind(rng, 0.3, 500.0, 6500.0, 0.8) * 2.2, 0.28)
    place(out, np.sin(2 * np.pi * 880.0 * t_axis(0.06)) * decay(t_axis(0.06), 0.012, 0.001) * 0.35, 0.6)
    return out


def flip_hit(rng):
    """The victim's: the music stops (a record brought to a halt: the pitch falls through the floor), a rewind swoosh, one scratch back, then a dry thunk. About 1.2 s."""
    out = np.zeros(int(1.25 * SR))
    place(out, scratch(rng, 0.38, lambda t: 1.0 * np.exp(-(t / 0.14) ** 2) * 1.2 + 0.0, base=180.0, grit=0.05) * 0.8, 0.0)
    place(out, rewind(rng, 0.42, 350.0, 5200.0, 0.85) * 2.4, 0.3)
    place(out, scratch(rng, 0.36, lambda t: -2.4 * np.sin(np.pi * np.minimum(t / 0.36, 1.0) * 1.8) * np.exp(-t / 0.5), base=240.0, grit=0.15), 0.72)
    thunk = np.sin(2 * np.pi * np.cumsum(120.0 - 70.0 * np.minimum(t_axis(0.12) / 0.12, 1.0)) / SR) * decay(t_axis(0.12), 0.04, 0.001)
    place(out, thunk * 0.9, 1.1)
    return out


def main():
    rng = np.random.default_rng(20261026)
    lib.save("flip_use", flip_use(rng))
    lib.save("flip_hit", flip_hit(rng))


if __name__ == "__main__":
    sys.exit(main())
