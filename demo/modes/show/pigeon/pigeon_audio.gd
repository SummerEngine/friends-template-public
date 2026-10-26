extends RefCounted
## GHOST PIGEON (docs/pigeon.md): the two sounds, made in code once (no sound file): a loud three-part COO (two short rising "oo"s and a long falling one with a wobble, a little breath on top) and
## the wet SPLAT of a drop (a thump under a burst of noise that closes down). Mono, 22.05 kHz, 16 bit.
const RATE := 22050

static var _coo: AudioStreamWAV
static var _splat: AudioStreamWAV

static func coo() -> AudioStreamWAV:
	if _coo == null: _coo = _wav(_coo_samples())
	return _coo

static func splat() -> AudioStreamWAV:
	if _splat == null: _splat = _wav(_splat_samples())
	return _splat

static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index in samples.size(): bytes.encode_s16(index * 2, int(clampf(samples[index], -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

## One syllable: `seconds` long, the pitch gliding from `from` to `to` Hz, a wobble of `wobble` Hz depth at 19 Hz, a soft attack and a long tail; added into `out` at `start`.
static func _syllable(out: PackedFloat32Array, start: float, seconds: float, from: float, to: float, wobble: float, gain: float) -> void:
	var count := int(seconds * RATE)
	var offset := int(start * RATE)
	var phase := 0.0
	for index in count:
		var t := float(index) / float(count)
		var hz := lerpf(from, to, t) + sin(float(index) / RATE * TAU * 19.0) * wobble * t
		phase += TAU * hz / RATE
		var tone := sin(phase) + 0.55 * sin(phase * 2.0) + 0.28 * sin(phase * 3.0) + 0.1 * sin(phase * 4.0) # a round, hooting tone: a few harmonics
		var envelope := minf(t / 0.12, 1.0) * pow(1.0 - t, 1.4)
		var at := offset + index
		if at < out.size(): out[at] += tone * envelope * gain

static func _coo_samples() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(1.15 * RATE))
	_syllable(out, 0.0, 0.2, 330.0, 420.0, 0.0, 0.34)
	_syllable(out, 0.22, 0.2, 400.0, 460.0, 0.0, 0.38)
	_syllable(out, 0.46, 0.62, 440.0, 300.0, 9.0, 0.5)
	var seed_state := 12345
	var low := 0.0
	for index in out.size(): # a little breath over the whole of it
		seed_state = (seed_state * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_state) / float(0x7fffffff) * 2.0 - 1.0
		low += (noise - low) * 0.18
		out[index] += low * 0.06 * (1.0 - float(index) / float(out.size()))
	var peak := 0.0
	for value in out: peak = maxf(peak, absf(value))
	for index in out.size(): out[index] = out[index] / maxf(peak, 0.001) * 0.92
	return out

static func _splat_samples() -> PackedFloat32Array:
	var count := int(0.42 * RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_state := 777
	var low := 0.0
	var phase := 0.0
	for index in count:
		var t := float(index) / RATE
		seed_state = (seed_state * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_state) / float(0x7fffffff) * 2.0 - 1.0
		var closing := lerpf(0.55, 0.05, minf(t / 0.3, 1.0)) # the wet burst closes down
		low += (noise - low) * closing
		phase += TAU * lerpf(150.0, 55.0, minf(t / 0.2, 1.0)) / RATE
		out[index] = low * exp(-t / 0.09) * 1.2 + sin(phase) * exp(-t / 0.07) * 0.8 + noise * exp(-t / 0.006) * 0.4
	var peak := 0.0
	for value in out: peak = maxf(peak, absf(value))
	for index in count: out[index] = out[index] / maxf(peak, 0.001) * 0.9
	return out
