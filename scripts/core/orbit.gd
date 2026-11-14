class_name Orbit
## Free fall round a planet, as Newton has it.
##
## A state is six numbers in the planet's own frame -- where the thing is, in
## metres from the planet's centre, and how fast it is going -- held in a
## `PackedFloat64Array`, not in two `Vector3`s. A `Vector3` is single
## precision: six and a half thousand kilometres from the centre it cannot say
## where something is to better than half a metre, and a lap of the planet is
## a third of a million steps of adding a hundred metres to that. In doubles
## an orbit closes; in singles it wanders.
##
## The frame does not turn. The planet's spin bends a shell's flight by a
## hair and `Ballistics` accounts for it there; out here it would mean the
## ground running away under an orbit at four hundred metres a second, and a
## launch site that is somewhere else by the time you come round. A planet
## that holds still is the one that can be flown round by hand.

## The planet's radius and gravitational parameter: `Sim.PLANET_R` and
## `Sim.GM`, written out because a script cannot take a constant off an
## autoload. 9.81 at the surface.
const R := 6_371_000.0
const GM := 9.81 * R * R

## The moon, by the clock. It moves a kilometre a second, and on time warp one
## tick of the game is minutes of flight, so "where the moon is this tick" is
## not good enough for anything going there: the clock is carried here and
## moved on with every step, and the moon is worked out afresh for each.
const MOON_GM := 4.9028e12
const MOON_R := 1_737_400.0
const MOON_DIST := 384_400_000.0
const MOON_PERIOD := 27.32 * 86400.0
const MOON_RATE := TAU / MOON_PERIOD
static var now := 0.0
static var _mu := Vector3.RIGHT
static var _mw := Vector3.BACK
static var _m_ready := false
static var mx := 0.0
static var my := 0.0
static var mz := 0.0
## For anything that only wants to look: the same, as a vector.
static var moon := Vector3.ZERO

## Start a tick: the clock everything in space shares.
static func sync() -> void:
	now = Sim.space_time
	_moon_at(now)

static func _moon_at(t: float) -> void:
	if not _m_ready:
		_m_ready = true
		var ax: Vector3 = Sim.MOON_AXIS.normalized()
		_mu = ax.cross(Vector3.RIGHT).normalized()
		_mw = ax.cross(_mu)
	var a: float = 0.9 + t * MOON_RATE
	var c: float = cos(a) * MOON_DIST
	var s: float = sin(a) * MOON_DIST
	mx = _mu.x * c + _mw.x * s
	my = _mu.y * c + _mw.y * s
	mz = _mu.z * c + _mw.z * s
	moon = Vector3(mx, my, mz)

## Where the moon is and how it is moving at a time, as a state like any other.
static func moon_state(t: float) -> PackedFloat64Array:
	if not _m_ready:
		_moon_at(t)
	var a: float = 0.9 + t * MOON_RATE
	var c: float = cos(a)
	var s: float = sin(a)
	var k: float = MOON_DIST * MOON_RATE
	return PackedFloat64Array([
		(_mu.x * c + _mw.x * s) * MOON_DIST, (_mu.y * c + _mw.y * s) * MOON_DIST,
		(_mu.z * c + _mw.z * s) * MOON_DIST,
		(-_mu.x * s + _mw.x * c) * k, (-_mu.y * s + _mw.y * c) * k,
		(-_mu.z * s + _mw.z * c) * k])

## A state as the moon sees it: where the thing is from the moon's centre and
## how fast it is going past.
static func about_moon(s: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var m: PackedFloat64Array = moon_state(t)
	return PackedFloat64Array([s[0] - m[0], s[1] - m[1], s[2] - m[2],
		s[3] - m[3], s[4] - m[4], s[5] - m[5]])

static func make(p: Vector3, v: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([p.x, p.y, p.z, v.x, v.y, v.z])

static func pos_of(s: PackedFloat64Array) -> Vector3:
	return Vector3(s[0], s[1], s[2])

static func vel_of(s: PackedFloat64Array) -> Vector3:
	return Vector3(s[3], s[4], s[5])

static func radius(s: PackedFloat64Array) -> float:
	return sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2])

static func speed(s: PackedFloat64Array) -> float:
	return sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])

## Air density at a height, kilograms a cubic metre.
static func rho(alt: float) -> float:
	if alt > 160000.0:
		return 0.0
	return 1.225 * exp(-maxf(alt, -500.0) / 8500.0)

## Everything pulling on a body at `p` going `v`, into `o`: the planet, an
## inverse square; the moon, as the difference between its pull here and its
## pull on the planet's centre, which is what is left in a frame that falls
## with the planet; and the air, by `kd` -- drag area over mass, m2/kg.
static func _acc(px: float, py: float, pz: float, vx: float, vy: float, vz: float,
		kd: float, o: PackedFloat64Array) -> void:
	var r2: float = px * px + py * py + pz * pz
	var r: float = sqrt(r2)
	var k: float = -GM / (r2 * r)
	var ax: float = px * k
	var ay: float = py * k
	var az: float = pz * k
	var m2: float = mx * mx + my * my + mz * mz
	if m2 > 1.0:
		var dx: float = mx - px
		var dy: float = my - py
		var dz: float = mz - pz
		var d2: float = maxf(dx * dx + dy * dy + dz * dz, 1.0e10)
		var kd3: float = MOON_GM / (d2 * sqrt(d2))
		var km3: float = MOON_GM / (m2 * sqrt(m2))
		ax += dx * kd3 - mx * km3
		ay += dy * kd3 - my * km3
		az += dz * kd3 - mz * km3
	if kd > 0.0:
		var alt: float = r - R
		if alt < 160000.0:
			var q: float = 0.5 * rho(alt) * kd * sqrt(vx * vx + vy * vy + vz * vz)
			ax -= vx * q
			ay -= vy * q
			az -= vz * q
	o[0] = ax
	o[1] = ay
	o[2] = az

static var _k1 := PackedFloat64Array([0.0, 0.0, 0.0])
static var _k2 := PackedFloat64Array([0.0, 0.0, 0.0])
static var _k3 := PackedFloat64Array([0.0, 0.0, 0.0])
static var _k4 := PackedFloat64Array([0.0, 0.0, 0.0])

## One step of `dt` seconds, fourth order. `thrust` is an acceleration in the
## planet's frame, held for the step; `kd` is drag area over mass.
static func step(s: PackedFloat64Array, dt: float, thrust := Vector3.ZERO,
		kd := 0.0) -> void:
	var tx: float = thrust.x
	var ty: float = thrust.y
	var tz: float = thrust.z
	var h: float = dt * 0.5
	# the moon where it is half way through the step
	_moon_at(now + h)
	now += dt
	_acc(s[0], s[1], s[2], s[3], s[4], s[5], kd, _k1)
	var v2x: float = s[3] + (_k1[0] + tx) * h
	var v2y: float = s[4] + (_k1[1] + ty) * h
	var v2z: float = s[5] + (_k1[2] + tz) * h
	_acc(s[0] + s[3] * h, s[1] + s[4] * h, s[2] + s[5] * h, v2x, v2y, v2z, kd, _k2)
	var v3x: float = s[3] + (_k2[0] + tx) * h
	var v3y: float = s[4] + (_k2[1] + ty) * h
	var v3z: float = s[5] + (_k2[2] + tz) * h
	_acc(s[0] + v2x * h, s[1] + v2y * h, s[2] + v2z * h, v3x, v3y, v3z, kd, _k3)
	var v4x: float = s[3] + (_k3[0] + tx) * dt
	var v4y: float = s[4] + (_k3[1] + ty) * dt
	var v4z: float = s[5] + (_k3[2] + tz) * dt
	_acc(s[0] + v3x * dt, s[1] + v3y * dt, s[2] + v3z * dt, v4x, v4y, v4z, kd, _k4)
	var sixth: float = dt / 6.0
	s[0] += (s[3] + 2.0 * v2x + 2.0 * v3x + v4x) * sixth
	s[1] += (s[4] + 2.0 * v2y + 2.0 * v3y + v4y) * sixth
	s[2] += (s[5] + 2.0 * v2z + 2.0 * v3z + v4z) * sixth
	s[3] += (_k1[0] + 2.0 * _k2[0] + 2.0 * _k3[0] + _k4[0] + 6.0 * tx) * sixth
	s[4] += (_k1[1] + 2.0 * _k2[1] + 2.0 * _k3[1] + _k4[1] + 6.0 * ty) * sixth
	s[5] += (_k1[2] + 2.0 * _k2[2] + 2.0 * _k3[2] + _k4[2] + 6.0 * tz) * sixth

## `span` seconds of it, cut into steps no longer than `most`.
static func advance(s: PackedFloat64Array, span: float, most: float,
		thrust := Vector3.ZERO, kd := 0.0) -> void:
	var n: int = maxi(int(ceil(span / maxf(most, 0.001))), 1)
	var dt: float = span / float(n)
	for i in n:
		step(s, dt, thrust, kd)

## How far a state is from the moon's centre, at the clock as it stands.
static func moon_range(s: PackedFloat64Array) -> float:
	var dx: float = s[0] - mx
	var dy: float = s[1] - my
	var dz: float = s[2] - mz
	return sqrt(dx * dx + dy * dy + dz * dz)

## The longest step that is still honest here: a few thousandths of the time
## it takes to go round whatever is nearest.
static func fair_step(s: PackedFloat64Array) -> float:
	var r: float = radius(s)
	var v: float = maxf(speed(s), 1.0)
	var t: float = r / v
	var dm: float = moon_range(s)
	if dm < 1.2e8:
		t = minf(t, dm / maxf(sqrt(MOON_GM / maxf(dm, 1.0)) * 1.5, 300.0))
	return clampf(t * 0.004, 0.02, 120.0)

## The orbit a state is on: the heights of its highest and lowest points above
## the surface, and how long a lap takes. An open orbit -- one going fast
## enough never to come back -- has no highest point and no period, and says
## so with INF. Round the planet unless told the moon's figures.
static func apsides(s: PackedFloat64Array, gm := GM, body_r := R) -> Dictionary:
	var r: float = radius(s)
	var v2: float = s[3] * s[3] + s[4] * s[4] + s[5] * s[5]
	var energy: float = v2 * 0.5 - gm / r
	var hx: float = s[1] * s[5] - s[2] * s[4]
	var hy: float = s[2] * s[3] - s[0] * s[5]
	var hz: float = s[0] * s[4] - s[1] * s[3]
	var h2: float = hx * hx + hy * hy + hz * hz
	var ecc: float = sqrt(maxf(1.0 + 2.0 * energy * h2 / (gm * gm), 0.0))
	if energy >= -1e-6:
		return {"ap": INF, "pe": h2 / (gm * (1.0 + ecc)) - body_r, "period": INF, "ecc": ecc}
	var a: float = -gm / (2.0 * energy)
	return {"ap": a * (1.0 + ecc) - body_r, "pe": a * (1.0 - ecc) - body_r,
		"period": TAU * sqrt(a * a * a / gm), "ecc": ecc}

## The velocity a body at `p` must have to fall, unpowered, onto the surface
## in the direction `to` -- the free flight range equation, on the arc that
## needs the least speed. ZERO if there is no such arc (the target is
## underfoot, or exactly on the far side).
##
## This is what a ballistic missile is aimed with. It is not steered to the
## target; it is steered until it is going at this, and then let go.
static func v_required(p: Vector3, to: Vector3, to_alt := 0.0) -> Vector3:
	var r0: float = p.length()
	var up: Vector3 = p / maxf(r0, 1.0)
	var t: Vector3 = to.normalized()
	var phi: float = acos(clampf(up.dot(t), -1.0, 1.0))
	if phi < 1e-4 or phi > PI - 0.02:
		return Vector3.ZERO
	var along: Vector3 = (t - up * up.dot(t)).normalized()
	var r1: float = R + to_alt
	# least energy for the range, corrected for starting above the surface: a
	# round released high wants a flatter path than one fired from the ground
	var gam: float = (PI - phi) * 0.25
	gam = maxf(gam - clampf(atan2(r0 - r1, r1 * phi) * 0.5, 0.0, 1.0), 0.04)
	var best := Vector3.ZERO
	for attempt in 8:
		var cg: float = cos(gam)
		var den: float = (r0 / r1) * cg * cg - cos(phi + gam) * cg
		if den > 1e-6:
			var q: float = (1.0 - cos(phi)) / den
			if q > 0.0 and q < 1.98:
				best = (along * cg + up * sin(gam)) * sqrt(q * GM / r0)
				break
		gam += 0.06
	return best
