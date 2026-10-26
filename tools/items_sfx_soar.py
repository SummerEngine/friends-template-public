#!/usr/bin/env python3
"""The template's SOAR sound, made procedurally (numpy only, fixed seed): demo/audio/items/soar_hit.ogg, an upbeat riser into a drop with a bright chord and an arpeggio.

    python3 tools/items_sfx_soar.py

Mono Ogg Vorbis, about 1.7 s, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, decay, fm_bell, one_pole, place, t_axis

DROP_AT = 0.55


def soar_hit(rng):
    out = np.zeros(int(1.7 * SR))
    # the riser: noise whose filter opens and a sine that climbs two octaves, louder as it goes
    n = int(DROP_AT * SR)
    t = t_axis(DROP_AT)
    rise = (t / DROP_AT) ** 2.0
    noise = one_pole(rng.standard_normal(n), 500.0 + 9000.0 * rise, "low")
    sweep = np.sin(2 * np.pi * np.cumsum(330.0 * 4.0 ** (t / DROP_AT)) / SR)
    riser = (noise * 0.9 + sweep * 0.5) * (0.15 + 0.85 * rise)
    riser *= np.minimum((DROP_AT - t) / 0.01, 1.0)
    place(out, riser, 0.0)
    # the drop: a sub thump and a bright major stab (C5 E5 G5 D6 C6) that plucks away
    t = t_axis(0.5)
    place(out, np.sin(2 * np.pi * np.cumsum(46.0 + 110.0 * np.exp(-t / 0.05)) / SR) * decay(t, 0.16, 0.002) * 1.3, DROP_AT)
    t = t_axis(0.9)
    stab = np.zeros_like(t)
    for f in (523.25, 659.25, 783.99, 1174.66, 1046.5):
        for detune in (0.994, 1.0, 1.006):
            stab += np.sign(np.sin(2 * np.pi * f * detune * t + rng.uniform(0, 6.28))) * 0.12 * 0.4 + np.sin(2 * np.pi * f * detune * t) * 0.09
    stab = one_pole(stab, 5200.0 * np.exp(-t / 0.5) + 900.0, "low") * decay(t, 0.28, 0.003)
    place(out, stab * 1.1, DROP_AT)
    # the arpeggio on top: bells climbing C6 E6 G6 C7
    for k, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        place(out, fm_bell(f, 0.6, 0.16, 1.2) * 0.4, DROP_AT + 0.1 + k * 0.075)
    return out


def main():
    rng = np.random.default_rng(20261026)
    lib.save("soar_hit", soar_hit(rng))


if __name__ == "__main__":
    sys.exit(main())
