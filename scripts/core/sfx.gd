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
		# ------------------------------------------------------ small arms
		# One shot was doing for every weapon a man can carry, pitched up or
		# down. A report has three parts and each weapon weights them its own
		# way: the crack of the gas leaving the muzzle, the thump of the
		# action and the chest, and the tail the street hands back.
		"carbine":
			return _wav(_shot(0.34, 0.80, 0.30, 0.95, 150.0, 0.55, 0.20, 211), false)
		"smg":
			return _wav(_shot(0.22, 0.62, 0.36, 0.80, 210.0, 0.40, 0.10, 223), false)
		"shotgun":
			return _wav(_shot(0.60, 0.50, 0.14, 1.50, 78.0, 1.10, 0.36, 227), false)
		"dmr":
			return _wav(_shot(0.55, 0.88, 0.22, 1.20, 105.0, 0.85, 0.34, 229), false)
		"pistol":
			return _wav(_shot(0.24, 0.70, 0.40, 0.70, 240.0, 0.45, 0.10, 233), false)
		"suppressed":
			# A can takes the crack off and leaves the gas and the action: a
			# cough, and the bolt going home after it.
			var n := int(RATE * 0.20)
			var b := _noise(n, 0.11, 401)
			var hiss := _noise(n, 0.55, 409, 0.25)
			var clack := _clicks([[0.035, 0.9, 1700.0, 0.012]], 0.20, 419)
			for i in n:
				var secs := float(i) / RATE
				b[i] = b[i] * exp(-secs * 48.0) * 1.3 + hiss[i] * exp(-secs * 30.0) * 0.28 \
					+ sin(TAU * 120.0 * secs) * exp(-secs * 40.0) * 0.5 + clack[i] * 0.5
			return _wav(_norm(b, 0.8), false)
		"shot_far":
			# What a rifle is from three streets away: the crack has gone and
			# what arrives is the thump and what the walls made of it.
			var n := int(RATE * 0.9)
			var b := _noise(n, 0.07, 239)
			var slap := _noise(n, 0.16, 241)
			var gap := int(RATE * 0.11)
			for i in n:
				var t := float(i) / float(n)
				var v: float = b[i] * pow(1.0 - t, 7.0)
				if i >= gap:
					var t2 := float(i - gap) / float(n - gap)
					v += slap[i] * pow(1.0 - t2, 5.0) * 0.55
				b[i] = v
			return _wav(_norm(b, 0.9), false)
		"dry":
			return _wav(_clicks([[0.0, 0.9, 3200.0, 0.012]], 0.09, 251), false)
		"mag_out":
			return _wav(_clicks([[0.0, 0.7, 1500.0, 0.020], [0.07, 0.5, 620.0, 0.05]],
				0.24, 257), false)
		"mag_in":
			return _wav(_clicks([[0.0, 0.5, 900.0, 0.03], [0.09, 1.0, 1900.0, 0.022]],
				0.26, 263), false)
		"bolt":
			return _wav(_clicks([[0.0, 0.8, 1300.0, 0.03], [0.11, 1.0, 2400.0, 0.018]],
				0.30, 269), false)
		"pump":
			return _wav(_clicks([[0.0, 0.9, 700.0, 0.05], [0.17, 1.0, 950.0, 0.045]],
				0.42, 271), false)
		"shell":
			return _wav(_clicks([[0.0, 0.7, 1100.0, 0.03], [0.05, 0.6, 500.0, 0.04]],
				0.20, 277), false)
		"cloth":
			# webbing and a sling: what bringing a weapon up sounds like
			var n := int(RATE * 0.28)
			var b := _noise(n, 0.5, 281, 0.2)
			for i in n:
				var t := float(i) / float(n)
				b[i] *= sin(t * PI) * (0.6 + 0.4 * sin(t * 40.0))
			return _wav(_norm(b, 0.45), false)
		"step_a", "step_b", "step_c":
			# a boot on a hard road: a heel, then the scuff of the sole
			var which: int = ["step_a", "step_b", "step_c"].find(id)
			var n := int(RATE * 0.16)
			var b := _noise(n, 0.10 + 0.03 * which, 283 + which * 7)
			var grit := _noise(n, 0.6, 293 + which * 5, 0.3)
			for i in n:
				var t := float(i) / float(n)
				b[i] = b[i] * pow(1.0 - t, 9.0) + grit[i] * pow(1.0 - t, 4.0) \
					* clampf(t / 0.12, 0.0, 1.0) * 0.20
			return _wav(_norm(b, 0.8), false)
		"land":
			var n := int(RATE * 0.3)
			var b := _noise(n, 0.07, 307)
			var grit := _noise(n, 0.5, 311, 0.3)
			for i in n:
				var t := float(i) / float(n)
				b[i] = b[i] * pow(1.0 - t, 6.0) + grit[i] * pow(1.0 - t, 5.0) * 0.3
			return _wav(_norm(b, 0.9), false)
		"impact_hard":
			# into masonry: a tick and a spray of grit
			var n := int(RATE * 0.16)
			var b := _noise(n, 0.85, 313, 0.35)
			for i in n:
				var t := float(i) / float(n)
				b[i] *= pow(1.0 - t, 12.0) + pow(1.0 - t, 3.0) * 0.12
			return _wav(_norm(b, 0.85), false)
		"impact_soft":
			var n := int(RATE * 0.14)
			var b := _noise(n, 0.16, 317)
			for i in n:
				var t := float(i) / float(n)
				b[i] *= pow(1.0 - t, 8.0)
			return _wav(_norm(b, 0.8), false)
		"ricochet":
			# the whine of something tumbling off a wall, falling in pitch
			var n := int(RATE * 0.55)
			var b := PackedFloat32Array()
			b.resize(n)
			var tick := _noise(n, 0.85, 331, 0.35)
			var ph := 0.0
			for i in n:
				var t := float(i) / float(n)
				var f: float = lerpf(3400.0, 1300.0, pow(t, 0.6))
				ph += TAU * f / RATE
				b[i] = (sin(ph) + sin(ph * 1.51) * 0.4) * pow(1.0 - t, 2.4) * 0.5 \
					* clampf(t / 0.03, 0.0, 1.0) + tick[i] * pow(1.0 - t, 30.0)
			return _wav(_norm(b, 0.7), false)
		"snap":
			# a supersonic round passing close: its own small crack, no report
			var n := int(RATE * 0.07)
			var b := _noise(n, 0.95, 337, 0.4)
			for i in n:
				var t := float(i) / float(n)
				b[i] *= pow(1.0 - t, 14.0)
			return _wav(_norm(b, 0.95), false)
		"whiz":
			var n := int(RATE * 0.3)
			var b := _noise(n, 0.5, 347, 0.12)
			var ph := 0.0
			for i in n:
				var t := float(i) / float(n)
				var f: float = lerpf(1900.0, 700.0, t)
				ph += TAU * f / RATE
				b[i] = (b[i] * 0.5 + sin(ph) * 0.35) * sin(t * PI) * sin(t * PI)
			return _wav(_norm(b, 0.6), false)
		"hit_body":
			var n := int(RATE * 0.12)
			var b := _noise(n, 0.09, 349)
			var wet := _noise(n, 0.4, 353)
			for i in n:
				var t := float(i) / float(n)
				b[i] = b[i] * pow(1.0 - t, 7.0) + wet[i] * pow(1.0 - t, 12.0) * 0.4
			return _wav(_norm(b, 0.85), false)
		"hitmark":
			# the tick that tells you a round landed
			var n := int(RATE * 0.05)
			var b := PackedFloat32Array()
			b.resize(n)
			for i in n:
				var t := float(i) / float(n)
				b[i] = (sin(TAU * 2300.0 * float(i) / RATE)
					+ sin(TAU * 3450.0 * float(i) / RATE) * 0.5) * pow(1.0 - t, 5.0)
			return _wav(_norm(b, 0.5), false)
		"killmark":
			var n := int(RATE * 0.16)
			var b := PackedFloat32Array()
			b.resize(n)
			for i in n:
				var t := float(i) / float(n)
				var f: float = 1250.0 if t < 0.4 else 1870.0
				b[i] = sin(TAU * f * float(i) / RATE) * pow(1.0 - t, 2.5)
			return _wav(_norm(b, 0.5), false)
		"hurt":
			# taking a round: a dull knock right in the ears
			var n := int(RATE * 0.22)
			var b := _noise(n, 0.05, 359)
			for i in n:
				var t := float(i) / float(n)
				b[i] = (b[i] + sin(TAU * 90.0 * float(i) / RATE) * 0.6) * pow(1.0 - t, 5.0)
			return _wav(_norm(b, 0.9), false)
		"pin":
			return _wav(_clicks([[0.0, 0.8, 3800.0, 0.012], [0.06, 0.6, 2600.0, 0.03]],
				0.2, 367), false)
		"clink":
			# a grenade body meeting the road
			var n := int(RATE * 0.2)
			var b := PackedFloat32Array()
			b.resize(n)
			var k := _noise(n, 0.4, 373)
			for i in n:
				var t := float(i) / float(n)
				b[i] = (sin(TAU * 1700.0 * float(i) / RATE) * 0.5
					+ sin(TAU * 2750.0 * float(i) / RATE) * 0.3) * pow(1.0 - t, 7.0) \
					+ k[i] * pow(1.0 - t, 20.0)
			return _wav(_norm(b, 0.7), false)
		"frag":
			# sharper and shorter than a bomb: all crack, with debris after it
			var n := int(RATE * 1.3)
			var b := _noise(n, 0.09, 379)
			var crack := _noise(n, 0.8, 383)
			var debris := _noise(n, 0.55, 389, 0.3)
			for i in n:
				var t := float(i) / float(n)
				b[i] = b[i] * pow(1.0 - t, 3.2) + crack[i] * pow(1.0 - t, 18.0) * 0.9 \
					+ debris[i] * pow(1.0 - t, 3.0) * clampf((t - 0.08) / 0.1, 0.0, 1.0) \
					* 0.10 * (0.5 + 0.5 * sin(t * 90.0))
			return _wav(_norm(b, 1.0), false)
		_:
			return _wav(PackedFloat32Array([0.0]), false)

## A gunshot. `crack` and `body` are filter cutoffs for the two noise layers,
## `weight` how much chest there is to it, `thump_hz` the low knock of the
## action, `tail` how much of the street comes back and `slap` how long after.
static func _shot(dur: float, crack: float, body: float, weight: float,
		thump_hz: float, tail: float, slap: float, seed_v: int) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var hi := _noise(n, crack, seed_v, 0.18)
	var lo := _noise(n, body * 0.5, seed_v + 2)
	var echo := _noise(n, 0.14, seed_v + 4)
	var out := PackedFloat32Array()
	out.resize(n)
	var gap := int(RATE * slap * 0.35)
	for i in n:
		var t := float(i) / float(n)
		var secs := float(i) / RATE
		var v: float = hi[i] * exp(-secs * 95.0) * 1.0
		v += lo[i] * exp(-secs * 34.0) * weight
		v += sin(TAU * thump_hz * secs) * exp(-secs * 26.0) * weight * 0.55
		# the report coming back off the far side of the street
		if i >= gap:
			var t2 := float(i - gap) / float(maxi(n - gap, 1))
			v += echo[i] * pow(1.0 - t2, 3.5) * tail * 0.28
		out[i] = v * (1.0 - pow(t, 6.0))
	return _norm(out, 0.97)

## Metal on metal: a list of [when, how loud, ring Hz, how long] struck in turn.
static func _clicks(hits: Array, dur: float, seed_v: int) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var grit := _noise(n, 0.8, seed_v, 0.3)
	var out := PackedFloat32Array()
	out.resize(n)
	for h in hits:
		var at := int(float(h[0]) * RATE)
		var amp: float = h[1]
		var hz: float = h[2]
		var span: float = h[3]
		for i in range(at, n):
			var secs := float(i - at) / RATE
			if secs > span * 6.0:
				break
			var env: float = exp(-secs / span)
			out[i] += (grit[i] * 0.7 + sin(TAU * hz * secs) * 0.5
				+ sin(TAU * hz * 2.37 * secs) * 0.25) * env * amp
	return _norm(out, 0.6)

## Bake a set of clips ahead of time. Each is synthesised the first time it is
## asked for, which for a gunshot is the moment the trigger is pulled -- and a
## frame spent building a waveform is a frame the first shot of a fight hitches.
static func warm(ids: Array) -> void:
	for id in ids:
		get_clip(String(id))

## Straight into the ears, with no position: the tick of a hit, a dry trigger,
## your own magazine going home.
static func play_ui(world: Node, id: String, db := 0.0, pitch := 1.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = get_clip(id)
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = &"Interface"
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.play()

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
	p.bus = &"Effects"
	p.finished.connect(p.queue_free)
	world.add_child(p)
	p.global_position = pos
	# A looping clip never emits `finished`, so a one-shot built on one is
	# immortal: it plays for the rest of the session and every repeat adds
	# another. The aeroplane's cannon did exactly that — twelve a second of a
	# half-second buzzsaw loop, none of which ever stopped. Anything handed a
	# looping stream here is given a life instead.
	if p.stream is AudioStreamWAV \
			and (p.stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var w := p.stream as AudioStreamWAV
		# 16-bit samples, so two bytes each
		var secs: float = (float(w.data.size()) * 0.5) / maxf(float(w.mix_rate), 1.0)
		var t := world.get_tree().create_timer(maxf(secs / maxf(pitch, 0.05), 0.05))
		t.timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free())
	p.play()
