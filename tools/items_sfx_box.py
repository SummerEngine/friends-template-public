#!/usr/bin/env python3
"""The template's item-box sounds, made procedurally (numpy only, fixed seed): demo/audio/items/box_get.ogg, box_pop.ogg, box_tick.ogg.
Also the small helpers items_sfx_boost.py and items_sfx_soar.py use (synthesis, loudness through ffmpeg, Ogg Vorbis encoding through sox).

    python3 tools/items_sfx_box.py

Mono Ogg Vorbis, 44.1 kHz, each under 2 s and 100 KB, levelled to about -16 LUFS (what ffmpeg's ebur128 reads of the sound, a short one padded to one 400 ms block),
true peak under -1 dBFS. Nothing is sampled: every sound is sines, noise and envelopes.
"""
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "demo" / "audio" / "items"


def t_axis(seconds):
    return np.arange(int(seconds * SR)) / SR


def decay(t, tau, attack=0.002):
    """Exponential decay with a short linear attack (no click at the start)."""
    return np.minimum(t / max(attack, 1e-5), 1.0) * np.exp(-t / tau)


def place(out, sound, at):
    """Add `sound` into `out` at `at` seconds (the end is cut off if it does not fit)."""
    start = int(at * SR)
    if start >= len(out):
        return
    end = min(len(out), start + len(sound))
    out[start:end] += sound[: end - start]


def one_pole(x, cutoff, kind="low"):
    """One-pole filter; `cutoff` is a number or an array of Hz per sample."""
    cut = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1.0 - np.exp(-2.0 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y if kind == "low" else x - y


def bandpass(x, low, high):
    return one_pole(one_pole(x, high, "low"), low, "high")


def fm_bell(freq, seconds, tau, index=2.0, ratio=1.4, decay_index=0.35):
    """A struck bell: FM with an index that dies faster than the level."""
    t = t_axis(seconds)
    idx = index * np.exp(-t / (tau * decay_index))
    return np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * ratio * t)) * decay(t, tau)


def partials(freq, seconds, taus, amps, ratios):
    """Inharmonic partials, each with its own decay: a metal bell."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for ratio, amp, tau in zip(ratios, amps, taus):
        out += amp * np.sin(2 * np.pi * freq * ratio * t) * decay(t, tau, 0.001)
    return out


def loudness(samples):
    """ffmpeg's ebur128 integrated loudness (LUFS) and true peak (dBFS) of `samples`, padded to 0.4 s."""
    x = np.concatenate([samples, np.zeros(max(0, int(0.45 * SR) - len(samples)))])
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "m.wav"
        write_wav(path, x)
        run = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True)
    text = run.stderr.split("Summary:")[-1]
    integrated = float(re.search(r"I:\s+(-?[\d.]+) LUFS", text).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", text).group(1))
    return integrated, peak


def write_wav(path, samples):
    data = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def level(samples, target=-16.0, ceiling=-1.5):
    """Scale to `target` LUFS, then soft-limit anything over the ceiling (true peak under -1 dBFS)."""
    x = samples / (np.max(np.abs(samples)) + 1e-9) * 0.5
    measured, _ = loudness(x)
    x = x * 10 ** ((target - measured) / 20.0)
    top = 10 ** (ceiling / 20.0)
    for _ in range(3):
        over = np.abs(x) > top * 0.85
        if not over.any():
            break
        x = np.where(over, np.sign(x) * (top * 0.85 + (top - top * 0.85) * np.tanh((np.abs(x) - top * 0.85) / (top - top * 0.85))), x)
        measured, peak = loudness(x)
        if peak <= -1.0:
            break
        x = x * 10 ** ((-1.2 - peak) / 20.0)
    return x


def fade_out(x, seconds=0.04):
    n = int(seconds * SR)
    x = x.copy()
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


def save(name, samples, target=-16.0):
    OUT.mkdir(parents=True, exist_ok=True)
    x = level(fade_out(samples), target)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "x.wav"
        write_wav(wav, x)
        path = OUT / f"{name}.ogg"
        subprocess.run(["sox", str(wav), "-C", "4", "-c", "1", str(path)], check=True)
    measured, peak = loudness(x)
    print(f"{path.name}: {len(x) / SR:.2f} s, {path.stat().st_size / 1024:.1f} KB, {measured:.1f} LUFS, peak {peak:.1f} dBFS")


# ------------------------------------------------------------------ the box

def box_get(rng):
    """The pickup and the roll landing: two quick rising bell notes and a long soft one on top, a little sparkle."""
    out = np.zeros(int(0.8 * SR))
    place(out, fm_bell(659.3, 0.5, 0.16, 1.6) * 0.8, 0.0)       # E5
    place(out, fm_bell(987.8, 0.6, 0.2, 1.6) * 0.8, 0.075)      # B5
    place(out, fm_bell(1318.5, 0.75, 0.3, 1.2) * 0.7, 0.15)     # E6, rings out
    place(out, fm_bell(1975.5, 0.5, 0.18, 0.8) * 0.25, 0.15)    # B6, a shimmer on the last note
    for k in range(5):
        place(out, np.sin(2 * np.pi * rng.uniform(3000, 5200) * t_axis(0.09)) * decay(t_axis(0.09), 0.025) * 0.12, 0.17 + k * 0.045 + rng.uniform(0, 0.015))
    return out


def box_pop(rng):
    """The cube bursting: a plastic pop, a thump under it and the shards ticking away."""
    out = np.zeros(int(0.5 * SR))
    t = t_axis(0.2)
    sweep = np.sin(2 * np.pi * np.cumsum(70.0 + 190.0 * np.exp(-t / 0.035)) / SR) * decay(t, 0.05, 0.001)
    place(out, sweep * 1.0, 0.0)
    noise = rng.standard_normal(int(0.12 * SR))
    place(out, bandpass(noise, 1200.0, 7000.0) * decay(t_axis(0.12), 0.03, 0.0008) * 1.6, 0.0)
    place(out, np.sin(2 * np.pi * 2350.0 * t_axis(0.2)) * decay(t_axis(0.2), 0.05, 0.001) * 0.22, 0.004) # the cube's walls ringing
    for k in range(9):
        at = 0.04 + k * 0.035 + rng.uniform(0, 0.02)
        n = int(0.012 * SR)
        click = bandpass(rng.standard_normal(n), 2500.0, 9000.0) * decay(t_axis(0.012), 0.004, 0.0005)
        place(out, click * (0.6 * np.exp(-at / 0.18)), at)
    return out


def box_tick(rng):
    """One icon flip of the roulette: a short dry click with a tiny wooden note."""
    out = np.zeros(int(0.06 * SR))
    t = t_axis(0.06)
    place(out, np.sin(2 * np.pi * 1650.0 * t) * decay(t, 0.012, 0.0006), 0.0)
    place(out, bandpass(rng.standard_normal(int(0.012 * SR)), 2000.0, 8000.0) * decay(t_axis(0.012), 0.003, 0.0003) * 0.7, 0.0)
    return out


def main():
    rng = np.random.default_rng(20261024)
    save("box_get", box_get(rng))
    save("box_pop", box_pop(rng), -17.0)
    save("box_tick", box_tick(rng), -22.0) # played about ten times in a second: quieter than the rest


if __name__ == "__main__":
    sys.exit(main())
