#!/usr/bin/env python3
"""The template's BOOST sound, made procedurally (numpy only, fixed seed): demo/audio/items/boost_hit.ogg, a cash-register ka-ching with a few coins settling.

    python3 tools/items_sfx_boost.py

Mono Ogg Vorbis, about 1.3 s, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, bandpass, decay, partials, place, t_axis


def boost_hit(rng):
    out = np.zeros(int(1.35 * SR))
    # "ka": the drawer's mechanical clunk, a dry noise burst and a low knock
    place(out, bandpass(rng.standard_normal(int(0.05 * SR)), 700.0, 3200.0) * decay(t_axis(0.05), 0.012, 0.0005) * 1.1, 0.0)
    t = t_axis(0.08)
    place(out, np.sin(2 * np.pi * np.cumsum(190.0 - 90.0 * np.minimum(t / 0.08, 1.0)) / SR) * decay(t, 0.025, 0.001) * 0.9, 0.0)
    # "ching": the register's bell struck twice, inharmonic partials with their own decay
    ratios = [1.0, 2.32, 3.98, 5.43, 7.81]
    amps = [1.0, 0.55, 0.32, 0.18, 0.08]
    taus = [0.55, 0.38, 0.25, 0.16, 0.1]
    place(out, partials(2790.0, 1.0, taus, amps, ratios) * 0.7, 0.085)
    place(out, partials(2790.0 * 1.335, 1.2, [t * 1.5 for t in taus], amps, ratios) * 0.8, 0.17)
    # coins: small high tings settling after the bell, thinning out
    at = 0.34
    for k in range(11):
        f = rng.uniform(3600.0, 6800.0)
        ting = np.sin(2 * np.pi * f * t_axis(0.12)) * decay(t_axis(0.12), 0.03, 0.0005) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t_axis(0.12)) * decay(t_axis(0.12), 0.015, 0.0005)
        place(out, ting * 0.22 * np.exp(-(at - 0.34) / 0.45), at)
        at += rng.uniform(0.025, 0.05) * (1.0 + k * 0.2)
    return out


def main():
    rng = np.random.default_rng(20261025)
    lib.save("boost_hit", boost_hit(rng))


if __name__ == "__main__":
    sys.exit(main())
