#!/usr/bin/env python3
"""The template's HOT EGGPLANT sounds (the experiment, docs/items.md), made procedurally (numpy only, fixed seed): demo/audio/items/eggplant_hit.ogg (it lands on a back, or is passed
to one: the manager plays `hit` on every HIT event) and eggplant_pop.ogg (it pops in confetti). Helpers and loudness handling of tools/items_sfx_box.py.

    python3 tools/items_sfx_eggplant.py

Mono Ogg Vorbis, 44.1 kHz, each under 1 s and 100 KB, levelled to about -16 LUFS. Nothing is sampled: sines, noise and envelopes.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, bandpass, decay, one_pole, place, t_axis


def eggplant_hit(rng):
    """It lands on a back: a heavy soft whump, a wet squelch on top, a slide whistle falling (oh no). About 0.7 s."""
    out = np.zeros(int(0.75 * SR))
    t = t_axis(0.22)
    whump = np.sin(2 * np.pi * np.cumsum(150.0 - 95.0 * np.minimum(t / 0.2, 1.0)) / SR) * decay(t, 0.07, 0.002)
    place(out, whump * 1.2, 0.0)
    place(out, one_pole(rng.standard_normal(int(0.1 * SR)), 900.0) * decay(t_axis(0.1), 0.03, 0.001) * 1.3, 0.0)
    t = t_axis(0.16)
    squelch = np.sin(2 * np.pi * np.cumsum(220.0 + 520.0 * np.sin(np.pi * np.minimum(t / 0.16, 1.0))) / SR) * decay(t, 0.08, 0.004)
    place(out, squelch * 0.35, 0.03)
    t = t_axis(0.42)
    glide = np.sin(2 * np.pi * np.cumsum(1050.0 * np.exp(-t / 0.28) + 260.0) / SR)
    glide += 0.3 * np.sin(2 * np.pi * np.cumsum(2100.0 * np.exp(-t / 0.28) + 520.0) / SR)
    place(out, glide * decay(t, 0.22, 0.01) * 0.3, 0.12)
    return out


def eggplant_pop(rng):
    """It pops: a party-popper bang, a thump under it, the paper rustling down, two bright notes (delivered). About 0.9 s."""
    out = np.zeros(int(0.95 * SR))
    t = t_axis(0.2)
    place(out, np.sin(2 * np.pi * np.cumsum(60.0 + 210.0 * np.exp(-t / 0.03)) / SR) * decay(t, 0.05, 0.001) * 1.1, 0.0)
    place(out, bandpass(rng.standard_normal(int(0.14 * SR)), 1500.0, 8000.0) * decay(t_axis(0.14), 0.03, 0.0008) * 1.7, 0.0)
    rustle = bandpass(rng.standard_normal(int(0.6 * SR)), 3000.0, 9500.0)
    flutter = (0.5 + 0.5 * np.sin(2 * np.pi * 23.0 * t_axis(0.6) + rng.uniform(0, 6.28))) ** 2
    place(out, rustle * flutter * decay(t_axis(0.6), 0.22, 0.01) * 0.55, 0.03)
    place(out, lib.fm_bell(784.0, 0.5, 0.14, 1.2) * 0.45, 0.2)    # G5
    place(out, lib.fm_bell(1046.5, 0.65, 0.2, 1.2) * 0.5, 0.29)   # C6
    return out


def main():
    rng = np.random.default_rng(20261025)
    lib.save("eggplant_hit", eggplant_hit(rng))
    lib.save("eggplant_pop", eggplant_pop(rng), -17.0)


if __name__ == "__main__":
    sys.exit(main())
