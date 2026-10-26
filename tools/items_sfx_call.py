#!/usr/bin/env python3
"""The template's CALL sounds, made procedurally (numpy only, fixed seed): demo/audio/items/call_use.ogg (the shot leaving), call_hit.ogg (a generic phone ring when the call lands) and
call_tap.ogg (one GRAB tap on the Decline button).

    python3 tools/items_sfx_call.py

Mono Ogg Vorbis, under 2 s and 100 KB each, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled: sines, noise and envelopes.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, bandpass, decay, place, t_axis


def tone(freq, seconds, harmonics=(1.0, 0.0, 0.18)):
    t = t_axis(seconds)
    return sum(a * np.sin(2 * np.pi * freq * (k + 1) * t) for k, a in enumerate(harmonics))


def call_use(rng):
    """A send: a quick rising chirp, a bright second blip on top and a soft airy whoosh trailing off."""
    out = np.zeros(int(0.5 * SR))
    t = t_axis(0.2)
    sweep = 520.0 + 1500.0 * (t / 0.2) ** 1.6
    place(out, np.sin(2 * np.pi * np.cumsum(sweep) / SR) * decay(t, 0.08, 0.004) * 0.9, 0.0)
    place(out, tone(1976.0, 0.25) * decay(t_axis(0.25), 0.07, 0.003) * 0.55, 0.13)
    air = bandpass(rng.standard_normal(int(0.42 * SR)), 900.0, 5200.0) * decay(t_axis(0.42), 0.11, 0.02)
    place(out, air * 0.35, 0.02)
    return out


def ring_burst(seconds, carriers=(880.0, 1174.7)):
    """One ring: two carriers, amplitude-modulated at 22 Hz (the old trill), round attack and release."""
    t = t_axis(seconds)
    body = sum(np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t) for f in carriers)
    trill = 0.55 + 0.45 * np.cos(2 * np.pi * 22.0 * t)
    env = np.minimum(t / 0.012, 1.0) * np.minimum((seconds - t) / 0.03, 1.0)
    return body * trill * env


def call_hit(rng):
    """A phone ring that is nobody's ringtone: ring, a beat, ring, and a small ping as it connects."""
    out = np.zeros(int(1.6 * SR))
    place(out, ring_burst(0.42), 0.0)
    place(out, ring_burst(0.42), 0.58)
    place(out, tone(1568.0, 0.4) * decay(t_axis(0.4), 0.12, 0.002) * 0.7, 1.1)
    place(out, tone(2093.0, 0.4) * decay(t_axis(0.4), 0.15, 0.002) * 0.6, 1.2)
    return out


def call_tap(rng):
    """One tap on a button: a dry click and a short, low thock."""
    out = np.zeros(int(0.14 * SR))
    place(out, bandpass(rng.standard_normal(int(0.02 * SR)), 1800.0, 6500.0) * decay(t_axis(0.02), 0.004, 0.0004), 0.0)
    t = t_axis(0.1)
    place(out, np.sin(2 * np.pi * np.cumsum(260.0 - 120.0 * np.minimum(t / 0.1, 1.0)) / SR) * decay(t, 0.03, 0.001) * 0.9, 0.0)
    return out


def main():
    rng = np.random.default_rng(20261026)
    lib.save("call_use", call_use(rng))
    lib.save("call_hit", call_hit(rng))
    lib.save("call_tap", call_tap(rng), -22.0)


if __name__ == "__main__":
    sys.exit(main())
