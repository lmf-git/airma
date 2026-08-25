class_name Sfx
## Procedurally baked audio. Nothing is loaded from disk: every clip is
## synthesised into a 16-bit PCM buffer once, then cached and shared.

const RATE := 22050

static var _cache := {}

static func get_clip(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var s: AudioStreamWAV = _bake(id)
	_cache[id] = s
	return s

# ---------------------------------------------------------------- synthesis
static func _wav(buf: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		if v < 0:
			v += 65536
		bytes[i * 2] = v & 0xFF
		bytes[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = buf.size()
	return w

## White noise run through a one-pole low pass, with the tail cross-faded into
## the head so it loops without a click.
static func _noise(n: int, cutoff: float, seed_v: int, hp := 0.0) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * cutoff
		var v := lp
		if hp > 0.0:
			lp2 += (v - lp2) * hp
			v -= lp2
		out[i] = v
	var fade := int(n * 0.06)
	for i in fade:
		var t := float(i) / float(fade)
		out[i] = lerpf(out[n - fade + i], out[i], t)
	return out

static func _norm(buf: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in buf.size():
		buf[i] *= k
	return buf

## Sum of harmonics with an exact whole number of cycles, so the loop is seamless.
static func _harmonics(n: int, cycles: Array, amps: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for h in cycles.size():
		var c: float = cycles[h]
		var a: float = amps[h]
		var ph := randf() * TAU
		for i in n:
			out[i] += sin(TAU * c * float(i) / float(n) + ph) * a
	return out

static func _bake(id: String) -> AudioStreamWAV:
	match id:
		"engine":
			# turbine core: low rumble plus compressor whine
			var n := RATE * 2
			var b := _harmonics(n, [96.0, 192.0, 288.0, 480.0, 1400.0, 2100.0],
				[0.55, 0.30, 0.16, 0.09, 0.10, 0.06])
			var hiss := _noise(n, 0.35, 11)
			for i in n:
				b[i] += hiss[i] * 0.22
			return _wav(_norm(b, 0.85), true)
		"rotor":
			# blade slap: a thump train at the blade passing frequency over the
			# turbine whine, which is what a helicopter actually sounds like
			var n := RATE * 2
			var b := PackedFloat32Array()
			b.resize(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = 151
			var period := int(RATE / 21.0)          # four blades, ~5 rev/s
			var lp := 0.0
			for i in n:
				var ph := i % period
				var env: float = exp(-float(ph) / (float(period) * 0.34))
				lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.13
				b[i] = lp * env * 1.4
			var whine := _harmonics(n, [640.0, 1280.0, 2560.0], [0.16, 0.09, 0.05])
			var wash := _noise(n, 0.28, 157)
			for i in n:
				b[i] += whine[i] * 0.5 + wash[i] * 0.18
			return _wav(_norm(b, 0.9), true)
		"roar":
			# afterburner: broadband, weighted low
			var n := RATE * 2
			var b := _noise(n, 0.10, 23)
			var mid := _noise(n, 0.55, 29)
			for i in n:
				b[i] = b[i] * 1.0 + mid[i] * 0.35
			return _wav(_norm(b, 0.9), true)
		"wind":
			var n := RATE * 2
			var b := _noise(n, 0.22, 37, 0.02)
			return _wav(_norm(b, 0.8), true)
		"tyres":
			var n := RATE
			var b := _noise(n, 0.06, 41)
			var rumble := _harmonics(n, [30.0, 61.0], [0.4, 0.2])
			for i in n:
				b[i] = b[i] * 0.8 + rumble[i] * 0.5
			return _wav(_norm(b, 0.75), true)
		"gun":
			# M61 buzzsaw: a repeating impulse train at ~100 rounds/sec
			var n := int(RATE / 2.0)
			var b := PackedFloat32Array()
			b.resize(n)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var period := int(RATE / 100.0)
			for i in n:
				var ph := i % period
				var env: float = exp(-float(ph) / (float(period) * 0.30))
				b[i] = rng.randf_range(-1.0, 1.0) * env
			var lp := 0.0
			for i in n:
				lp += (b[i] - lp) * 0.5
				b[i] = lp
			return _wav(_norm(b, 0.85), true)
		"rifle":
			# short crack with a tight tail; anything longer turns into an echo
			var n := int(RATE * 0.22)
			var b := _noise(n, 0.72, 131)
			var body := _noise(n, 0.22, 137)
			for i in n:
				var t := float(i) / float(n)
				var env: float = pow(1.0 - t, 9.0)
				var thud: float = pow(1.0 - t, 26.0)
				b[i] = b[i] * env * 0.8 + body[i] * thud * 1.1
			return _wav(_norm(b, 0.95), false)
		"launch":
			var n := int(RATE * 1.4)
			var b := _noise(n, 0.30, 53)
			for i in n:
				var t := float(i) / float(n)
				var env: float = clampf(t / 0.05, 0.0, 1.0) * pow(1.0 - t, 1.6)
				b[i] *= env
			return _wav(_norm(b, 0.95), false)
		"boom":
			var n := int(RATE * 2.2)
			var b := _noise(n, 0.05, 61)
			var crack := _noise(n, 0.6, 67)
			for i in n:
				var t := float(i) / float(n)
				b[i] = b[i] * pow(1.0 - t, 1.4) + crack[i] * pow(1.0 - t, 7.0) * 0.7
			return _wav(_norm(b, 1.0), false)
		"servo":
			var n := int(RATE * 1.1)
			var b := _noise(n, 0.7, 71, 0.25)
			var whine := _harmonics(n, [520.0, 1040.0], [0.5, 0.2])
			for i in n:
				var t := float(i) / float(n)
				var env: float = clampf(t / 0.06, 0.0, 1.0) * clampf((1.0 - t) / 0.15, 0.0, 1.0)
				b[i] = (b[i] * 0.55 + whine[i] * 0.45) * env
			return _wav(_norm(b, 0.5), false)
		"thump":
			var n := int(RATE * 0.8)
			var b := PackedFloat32Array()
			b.resize(n)
			var noise := _noise(n, 0.35, 83)
			for i in n:
				var t := float(i) / float(n)
				var env: float = pow(1.0 - t, 4.0)
				b[i] = (sin(TAU * 62.0 * float(i) / RATE) * 0.8 + noise[i] * 0.5) * env
			return _wav(_norm(b, 0.9), false)
		"beep":
			var n := int(RATE * 0.5)
			var b := PackedFloat32Array()
			b.resize(n)
			for i in n:
				var t := float(i) / float(n)
				var gate := 1.0 if fmod(t, 0.5) < 0.26 else 0.0
				b[i] = sin(TAU * 880.0 * float(i) / RATE) * 0.6 * gate
			return _wav(b, true)
		"buffet":
			var n := RATE
			var b := _noise(n, 0.12, 97)
			var shake := PackedFloat32Array()
			shake.resize(n)
			for i in n:
				shake[i] = b[i] * (0.6 + 0.4 * sin(TAU * 11.0 * float(i) / RATE))
			return _wav(_norm(shake, 0.8), true)
		_:
			return _wav(PackedFloat32Array([0.0]), false)

## One-shot at a world position. Falls back to a 2D player when no scene is set.
static func play_at(world: Node, id: String, pos: Vector3, db := 0.0, pitch := 1.0, dist := 900.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = get_clip(id)
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = dist
	p.unit_size = 26.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.global_position = pos
	p.play()
