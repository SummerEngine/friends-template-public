#!/usr/bin/env python3
"""The template's GLITCH sounds, made procedurally (numpy only, fixed seed): demo/audio/items/glitch_use.ogg and glitch_hit.ogg, corrupted digital audio.

    python3 tools/items_sfx_glitch.py

Mono Ogg Vorbis, under 2 s and 100 KB, levelled to about -16 LUFS (helpers and limits: items_sfx_box.py). Nothing is sampled: sines, noise, bit crushing and a stuttering buffer
(one short grain of the sound repeated and pitch-dropped) make the sound of a model that lost its place.
"""
import sys

import numpy as np

import items_sfx_box as lib
from items_sfx_box import SR, decay, one_pole, place, t_axis


def crush(x, bits, hold):
    """Bit crusher: quantise to `bits` and hold every `hold`-th sample."""
    held = np.repeat(x[::hold], hold)[: len(x)]
    steps = 2.0 ** (bits - 1)
    return np.round(held * steps) / steps


def blip(freq, seconds, square=True):
    t = t_axis(seconds)
    wave = np.sign(np.sin(2 * np.pi * freq * t)) if square else np.sin(2 * np.pi * freq * t)
    return wave * decay(t, seconds * 0.45, 0.001)


def stutter(x, start, grain, repeats, drop):
    """The buffer stuck: `grain` s of `x` from `start` repeated `repeats` times, each repeat a bit quieter and `drop` lower in pitch."""
    a = int(start * SR)
    g = x[a: a + int(grain * SR)]
    out = []
    for k in range(repeats):
        rate = (1.0 - drop) ** k
        idx = np.arange(0, len(g) - 1, rate)
        out.append(np.interp(idx, np.arange(len(g)), g) * (0.85 ** k))
    return np.concatenate(out)


def glitch_use(rng):
    """The user's own: a burst of corrupted packets going out, four blips that stumble up the scale and fall into static. About 0.5 s."""
    out = np.zeros(int(0.55 * SR))
    for k, f in enumerate([880.0, 1320.0, 1108.7, 1760.0]):
        place(out, crush(blip(f, 0.06) * 0.7, 5, 2), k * 0.055)
    t = t_axis(0.22)
    zap = np.sin(2 * np.pi * np.cumsum(2200.0 * np.exp(-t / 0.07) + 140.0) / SR) * decay(t, 0.09, 0.001)
    place(out, crush(zap * 0.8, 4, 3), 0.22)
    noise = one_pole(rng.standard_normal(int(0.12 * SR)), 3000.0, "high") * decay(t_axis(0.12), 0.04, 0.001)
    place(out, crush(noise * 0.6, 3, 4), 0.2)
    return out


def glitch_hit(rng):
    """The victim's: a dial-up chirp train that cannot hold a note, a chord dragged down and crushed, the stuck buffer stuttering and a hard cut. About 1.3 s."""
    out = np.zeros(int(1.35 * SR))
    # the chirps: a tone that hops every 30 ms to a new random pitch
    hops = rng.uniform(900.0, 2600.0, 14)
    for k, f in enumerate(hops):
        t = t_axis(0.032)
        place(out, np.sin(2 * np.pi * f * t) * np.minimum(t / 0.002, 1.0) * np.minimum((0.032 - t) / 0.002, 1.0) * 0.3, k * 0.032)
    # the dragged chord: three detuned saws sliding down, bit crushed harder as it goes
    t = t_axis(0.9)
    slide = np.exp(-t / 0.5)
    chord = np.zeros_like(t)
    for ratio in (1.0, 1.26, 1.5):
        phase = np.cumsum(520.0 * ratio * (0.25 + 0.75 * slide)) / SR
        chord += (2.0 * (phase % 1.0) - 1.0)
    chord = one_pole(chord / 3.0, 2400.0, "low") * decay(t, 0.55, 0.004)
    first = crush(chord[: len(t) // 3], 6, 2)
    mid = crush(chord[len(t) // 3: 2 * len(t) // 3], 4, 4)
    last = crush(chord[2 * len(t) // 3:], 3, 7)
    place(out, np.concatenate([first, mid, last]) * 0.7, 0.14)
    # the stuck buffer: the start of the chord looped, dropping in pitch each time
    source = np.concatenate([np.zeros(int(0.14 * SR)), chord])
    loop = stutter(source, 0.15, 0.055, 7, 0.16)
    place(out, crush(loop, 4, 3) * 0.65, 0.78)
    return out


def main():
    rng = np.random.default_rng(20261027)
    lib.save("glitch_use", glitch_use(rng))
    lib.save("glitch_hit", glitch_hit(rng))


if __name__ == "__main__":
    sys.exit(main())
