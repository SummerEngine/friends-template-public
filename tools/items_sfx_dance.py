#!/usr/bin/env python3
"""The template's DANCE sounds, made procedurally (numpy only, fixed seed): demo/audio/items/dance_use.ogg (the throw), dance_hit.ogg (a shutter and a cheesy filter jingle on the victim)
and dance_pop.ogg (the phone bursting in confetti where it misses).

    python3 tools/items_sfx_dance.py

Mono Ogg Vorbis, each under 2 s and 100 KB, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled.
"""
import sys

import numpy as np

from items_sfx_box import SR, bandpass, decay, fm_bell, one_pole, place, save, t_axis


def sweep(f0, f1, seconds, shape=1.0):
    """A sine gliding from f0 to f1 Hz."""
    t = t_axis(seconds)
    f = f0 + (f1 - f0) * np.minimum(t / seconds, 1.0) ** shape
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def squash(x, drive=2.0):
    """A soft clip: the clicks and the pop lose their sharpest peaks, so the sound can be levelled louder under the same ceiling."""
    return np.tanh(x * drive) / np.tanh(drive)


def dance_use(rng):
    """The throw: a quick chirp up as the phone leaves the hand, an airy whoosh that rises and falls away, and a few ticks as it tumbles."""
    out = np.zeros(int(0.62 * SR))
    place(out, sweep(420.0, 1250.0, 0.11, 0.7) * decay(t_axis(0.11), 0.08, 0.002) * 0.55, 0.0)
    n = int(0.5 * SR)
    t = t_axis(0.5)
    centre = 500.0 + 2600.0 * np.sin(np.pi * np.minimum(t / 0.5, 1.0) ** 0.8)
    air = one_pole(rng.standard_normal(n), centre, "low")
    air = one_pole(air, 250.0, "high")
    place(out, air * np.sin(np.pi * np.minimum(t / 0.5, 1.0)) ** 1.6 * 1.3, 0.02)
    for k in range(5):
        at = 0.14 + k * 0.075
        place(out, np.sin(2 * np.pi * (1800.0 - k * 90.0) * t_axis(0.02)) * decay(t_axis(0.02), 0.006, 0.0005) * 0.2, at)
    return out


def dance_hit(rng):
    """On the victim: two shutter clicks, then four quick rising notes (a bright synth with a wobble, the filter switching on) and a bell on top."""
    out = np.zeros(int(1.25 * SR))
    for at, tone in ((0.0, 1.0), (0.055, 0.7)):
        click = bandpass(rng.standard_normal(int(0.03 * SR)), 900.0, 6500.0) * decay(t_axis(0.03), 0.007, 0.0004)
        place(out, click * 1.4 * tone, at)
        place(out, np.sin(2 * np.pi * 220.0 * t_axis(0.05)) * decay(t_axis(0.05), 0.012, 0.0008) * 0.7 * tone, at)
    notes = [523.3, 659.3, 784.0, 1046.5]  # C5 E5 G5 C6
    for k, freq in enumerate(notes):
        t = t_axis(0.2)
        vibrato = 1.0 + 0.012 * np.sin(2 * np.pi * 6.5 * t)
        wave = np.sign(np.sin(2 * np.pi * freq * vibrato * t)) * 0.5 + np.sin(2 * np.pi * freq * 2 * t) * 0.25
        wave = one_pole(wave, 3200.0, "low")
        place(out, wave * decay(t, 0.09, 0.003) * 0.55, 0.16 + k * 0.085)
    place(out, fm_bell(2093.0, 0.9, 0.3, 1.3) * 0.5, 0.5)
    place(out, fm_bell(1568.0, 0.8, 0.28, 1.0) * 0.3, 0.5)
    for k in range(6):
        place(out, np.sin(2 * np.pi * rng.uniform(3200, 6200) * t_axis(0.08)) * decay(t_axis(0.08), 0.02) * 0.1, 0.52 + k * 0.05 + rng.uniform(0, 0.02))
    return squash(out / np.max(np.abs(out)), 2.2)


def dance_pop(rng):
    """A party popper: a sharp pop, a puff of paper and the confetti ticking down."""
    out = np.zeros(int(0.7 * SR))
    t = t_axis(0.12)
    place(out, np.sin(2 * np.pi * np.cumsum(90.0 + 380.0 * np.exp(-t / 0.02)) / SR) * decay(t, 0.03, 0.0008) * 1.0, 0.0)
    place(out, bandpass(rng.standard_normal(int(0.1 * SR)), 1500.0, 9000.0) * decay(t_axis(0.1), 0.02, 0.0006) * 1.7, 0.0)
    rustle = bandpass(rng.standard_normal(int(0.5 * SR)), 2200.0, 8500.0) * decay(t_axis(0.5), 0.12, 0.004)
    place(out, rustle * (0.35 + 0.65 * (rng.random(len(rustle)) > 0.82)) * 0.5, 0.03)
    for k in range(10):
        at = 0.08 + k * 0.045 + rng.uniform(0, 0.03)
        place(out, np.sin(2 * np.pi * rng.uniform(2500, 5200) * t_axis(0.02)) * decay(t_axis(0.02), 0.005, 0.0004) * 0.18 * np.exp(-at / 0.25), at)
    return squash(out / np.max(np.abs(out)), 4.0)


def main():
    rng = np.random.default_rng(20261024)
    save("dance_use", dance_use(rng))
    save("dance_hit", dance_hit(rng))
    save("dance_pop", dance_pop(rng), -16.0)


if __name__ == "__main__":
    sys.exit(main())
