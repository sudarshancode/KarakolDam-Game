extends RefCounted
## Procedural sound effects. Everything is synthesised at startup, so the
## game ships without any audio files.

const RATE := 22050


static func _to_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


static func _noise(rng: RandomNumberGenerator, dur: float, decay: float, gain: float, lp := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		if lp > 0.0:
			prev = prev + (w - prev) * lp
			w = prev * 2.2
		out[i] = w * exp(-t * decay) * gain
	return out


static func _tone(freq: float, dur: float, decay: float, gain: float, sweep := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * maxf(20.0, freq + sweep * t) / RATE
		out[i] = sin(phase) * exp(-t * decay) * gain
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size() + offset)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in a.size():
		out[i] = a[i]
	for i in b.size():
		out[i + offset] += b[i]
	return out


static func _fade_edges(a: PackedFloat32Array, ms := 6.0) -> PackedFloat32Array:
	var f := int(ms * 0.001 * RATE)
	for i in mini(f, a.size()):
		var k := float(i) / f
		a[i] *= k
		a[a.size() - 1 - i] *= k
	return a


static func build_all() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var d := {}

	d["rifle"] = _to_wav(_mix(_noise(rng, 0.32, 14.0, 0.9, 0.55), _tone(85.0, 0.3, 16.0, 0.75, -35.0)))
	d["pistol"] = _to_wav(_mix(_noise(rng, 0.14, 42.0, 0.5, 0.35), _tone(320.0, 0.1, 40.0, 0.14)))
	d["click"] = _to_wav(_noise(rng, 0.05, 90.0, 0.5))
	d["reload"] = _to_wav(_mix(_noise(rng, 0.07, 70.0, 0.55), _noise(rng, 0.09, 60.0, 0.65), int(0.55 * RATE)))
	d["hit"] = _to_wav(_mix(_tone(150.0, 0.12, 28.0, 0.8, -70.0), _noise(rng, 0.1, 40.0, 0.4, 0.4)))
	d["death"] = _to_wav(_mix(_tone(190.0, 0.4, 7.0, 0.5, -140.0), _noise(rng, 0.25, 12.0, 0.25, 0.3)))
	d["hurt"] = _to_wav(_mix(_tone(120.0, 0.25, 9.0, 0.6, -60.0), _noise(rng, 0.15, 25.0, 0.3, 0.4)))
	d["step"] = _to_wav(_noise(rng, 0.09, 38.0, 0.45, 0.25))
	d["beep"] = _to_wav(_fade_edges(_tone(880.0, 0.14, 2.0, 0.35)))
	d["tick"] = _to_wav(_fade_edges(_tone(1500.0, 0.05, 6.0, 0.3), 2.0))
	d["pickup"] = _to_wav(_fade_edges(_mix(_tone(660.0, 0.09, 4.0, 0.3), _tone(990.0, 0.12, 4.0, 0.3), int(0.09 * RATE))))
	d["done"] = _to_wav(_fade_edges(_mix(_mix(_tone(523.0, 0.12, 3.0, 0.3), _tone(659.0, 0.12, 3.0, 0.3), int(0.12 * RATE)), _tone(784.0, 0.25, 3.0, 0.3), int(0.24 * RATE))))
	d["explosion"] = _to_wav(_mix(_noise(rng, 3.0, 1.5, 1.0, 0.07), _tone(48.0, 2.5, 1.3, 0.9, -8.0)))

	# Looping siren (continuous at the loop point because 700 Hz * 2 s is a whole number of cycles).
	var siren := PackedFloat32Array()
	var n := int(2.0 * RATE)
	siren.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * 700.0 * t - 400.0 * cos(TAU * t / 2.0)
		siren[i] = sin(ph) * 0.22
	d["siren"] = _to_wav(siren, true)
	return d
