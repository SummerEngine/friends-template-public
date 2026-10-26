"""The template's sounds of the SMASH item (docs/items.md), made procedurally (numpy, fixed seed; nothing recorded, nothing downloaded):

    python3 tools/items_sfx_smash.py            # writes demo/audio/items/smash_use.ogg, smash_hit.ogg, smash_back.ogg

  smash_use    the hand coming: a rush of air that builds for 1.3 s under a falling whistle-free wind, a low swell, cut where the slap lands
  smash_hit    the slap: a fat thump (pitch falling 150 -> 45 Hz), a flat-hand crack, a short squashed "splat" of air
  smash_back   the spring back: a rubbery boing, two damped bounces

Mono Ogg Vorbis, 44.1 kHz, under 2 s, each levelled to about -16 LUFS with a true-peak ceiling of -1.5 dBFS. Needs numpy, sox (the Ogg Vorbis encoder) and ffmpeg (the loudness meter).
"""
import os
import subprocess
import tempfile

import numpy

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "demo", "audio", "items")
TARGET_LUFS = -16.0
CEILING_DB = -3.5  # before the encoder: Vorbis rings a little over the peaks of a click, so the file stays under -1.5 dBTP


def t_axis(seconds):
    return numpy.arange(int(seconds * RATE)) / RATE


def lowpass(x, cutoff):
    """One-pole low pass; `cutoff` is a number or an array (Hz) per sample."""
    cutoff = numpy.broadcast_to(numpy.asarray(cutoff, dtype=float), x.shape)
    out = numpy.empty_like(x)
    state = 0.0
    for i in range(len(x)):
        a = 1.0 - numpy.exp(-2.0 * numpy.pi * cutoff[i] / RATE)
        state += a * (x[i] - state)
        out[i] = state
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, centre, q=2.0):
    """State-variable band pass (Chamberlin); `centre` per sample in Hz."""
    centre = numpy.broadcast_to(numpy.asarray(centre, dtype=float), x.shape)
    out = numpy.empty_like(x)
    low = band = 0.0
    for i in range(len(x)):
        f = 2.0 * numpy.sin(numpy.pi * min(centre[i], RATE * 0.2) / RATE)
        low += f * band
        high = x[i] - low - band / q
        band += f * high
        out[i] = band
    return out


def decay(t, seconds, power=1.0):
    return numpy.exp(-t / seconds) ** power


def fade_in(x, seconds):
    n = int(seconds * RATE)
    x[:n] *= numpy.linspace(0.0, 1.0, n)
    return x


def fade_out(x, seconds):
    n = int(seconds * RATE)
    x[-n:] *= numpy.linspace(1.0, 0.0, n)
    return x


def use_sound(rng):
    """Incoming: filtered noise whose band falls from 2.4 kHz to 260 Hz while it swells, plus a low rumble; stops abruptly at 1.3 s."""
    length = 1.3
    t = t_axis(length)
    u = t / length
    noise = rng.standard_normal(len(t))
    sweep = 2400.0 * (260.0 / 2400.0) ** (u ** 0.8)
    rush = bandpass(noise, sweep, q=1.6)
    swell = (u ** 2.2) * (1.0 - 0.12 * numpy.cos(2 * numpy.pi * 9.0 * t))
    air = rush * swell * 2.6
    rumble = lowpass(rng.standard_normal(len(t)), 120.0 * (1.0 + u)) * (u ** 1.6) * 6.0
    body = numpy.sin(2 * numpy.pi * numpy.cumsum(70.0 - 25.0 * u) / RATE) * (u ** 2.0) * 0.5
    x = air + rumble + body
    return fade_out(fade_in(x, 0.02), 0.012)


def hit_sound(rng):
    """The slap: thump + crack + splat, 0.75 s."""
    length = 0.75
    t = t_axis(length)
    f = 45.0 + 105.0 * numpy.exp(-t / 0.045)
    thump = numpy.sin(2 * numpy.pi * numpy.cumsum(f) / RATE) * decay(t, 0.26) * 1.5
    body = lowpass(rng.standard_normal(len(t)), 700.0) * decay(t, 0.05) * 1.2
    crack = highpass(rng.standard_normal(len(t)), 1800.0) * decay(t, 0.010) * 0.9
    click = numpy.sin(2 * numpy.pi * 2600.0 * t) * decay(t, 0.003) * 0.3
    splat = bandpass(rng.standard_normal(len(t)), 900.0 - 700.0 * numpy.clip(t / 0.22, 0.0, 1.0), q=3.0) * decay(t, 0.07) * 0.9
    tail = lowpass(rng.standard_normal(len(t)), 260.0) * decay(t, 0.3) * 0.7
    x = thump + body + crack + click + splat + tail
    return fade_out(fade_in(x, 0.0005), 0.03)


def back_sound(rng):
    """The spring back: a rubbery boing: a pitch that wobbles up and settles, two damped bounces, 0.55 s."""
    length = 0.55
    t = t_axis(length)
    wobble = numpy.exp(-t / 0.2) * numpy.sin(2 * numpy.pi * 6.0 * t)
    f = 190.0 + 120.0 * numpy.exp(-t / 0.15) + 70.0 * wobble
    phase = 2 * numpy.pi * numpy.cumsum(f) / RATE
    tone = (numpy.sin(phase) + 0.35 * numpy.sin(2 * phase) + 0.12 * numpy.sin(3 * phase)) * decay(t, 0.17)
    thud = numpy.sin(2 * numpy.pi * numpy.cumsum(95.0 - 40.0 * numpy.clip(t / 0.06, 0, 1)) / RATE) * decay(t, 0.03) * 0.8
    air = highpass(rng.standard_normal(len(t)), 2500.0) * decay(t, 0.008) * 0.25
    x = tone * 0.9 + thud + air
    return fade_out(fade_in(x, 0.002), 0.06)


def measure(path):
    """Integrated loudness (LUFS) and true peak (dBTP) of a file by ffmpeg's ebur128."""
    report = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"], capture_output=True, text=True).stderr
    lufs = peak = None
    for line in report.splitlines():
        line = line.strip()
        if line.startswith("I:"):
            lufs = float(line.split()[1])
        if line.startswith("Peak:"):
            peak = float(line.split()[1])
    return lufs, peak


def write_wav(path, samples):
    import wave
    data = (numpy.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(data.tobytes())


def write_ogg(name, samples):
    """Levels the sound to TARGET_LUFS: gain, then a soft clip at the ceiling (peaks of a slap are tamed rather than the whole sound being turned down)."""
    os.makedirs(OUT, exist_ok=True)
    samples = samples - numpy.mean(samples)
    ceiling = 10.0 ** (CEILING_DB / 20.0)
    with tempfile.TemporaryDirectory() as folder:
        wav = os.path.join(folder, name + ".wav")
        gain = 0.3
        cap = ceiling * 2.6 / numpy.max(numpy.abs(samples))  # beyond this the soft clip would squash the slap instead of levelling it
        for _ in range(10):
            gain = min(gain, cap)
            write_wav(wav, ceiling * numpy.tanh(samples * gain / ceiling))
            lufs, _ = measure(wav)
            if lufs is None or abs(lufs - TARGET_LUFS) < 0.3 or (gain >= cap and lufs < TARGET_LUFS):
                break
            gain *= 10.0 ** ((TARGET_LUFS - lufs) / 20.0)
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run(["sox", wav, "-C", "3", out], check=True)  # libvorbis through sox: mono Ogg Vorbis
    lufs, peak = measure(out)
    print(f"{name}.ogg  {os.path.getsize(out) / 1024:.0f} KB  {len(samples) / RATE:.2f} s  {lufs} LUFS  {peak} dBTP")


def main():
    rng = numpy.random.default_rng(24102026)
    write_ogg("smash_use", use_sound(rng))
    write_ogg("smash_hit", hit_sound(rng))
    write_ogg("smash_back", back_sound(rng))


main()
