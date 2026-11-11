class_name Ballistics
## How anything that is fired flies, once it is clear of the muzzle.
##
## Every round used to fall straight down the world's y axis at 9.81 m/s/s in
## a vacuum. The world is a planet: down is towards its centre, which a few
## kilometres out is not the y axis; gravity weakens with height; the air is
## thick at the ground and thin at altitude and slows a round in proportion to
## the square of its speed; and the planet turns underneath, which bends a long
## shot sideways. All of that is here, in one place, so that what flies and
## what aims it are the same sums.
##
## Close in none of it matters -- a rifle round loses a few metres a second and
## drifts by a hair in the first few dozen metres -- and most of what is fired
## in a street fight lands inside that. So the first `NEAR` metres of every
## flight are plain gravity, and the rest of the model only starts once it is
## past it.

const G0 := 9.81
## The planet's turn, radians a second: one sidereal day.
const OMEGA := 7.2921e-5
## Height over which the air thins by a factor of e.
const RHO_SCALE := 8500.0
## Metres of flight on plain gravity before the full model takes over.
const NEAR := 30.0

## The planet's spin as a vector in the world's own frame. The world is the
## tangent frame at the chart's origin -- x east, y up, z south -- and the axis
## is known on the planet, so it is that axis taken into those three.
static func spin() -> Vector3:
	var n: Vector3 = Sim.PLANET_NORTH
	return Vector3(n.dot(Sim.chart_east), n.dot(Sim.chart_origin),
		n.dot(Sim.chart_south)) * OMEGA

## Everything acting on a round at `p` going `v`. `k` is its drag figure: the
## fraction of its speed it loses per metre at sea level (a rifle round about a
## thousandth, a shell a twentieth of that). `w` is `spin()`, passed in so a
## loop asks for it once.
static func accel(p: Vector3, v: Vector3, k: float, w: Vector3) -> Vector3:
	var r: Vector3 = p - Sim.planet_centre
	var rl: float = maxf(r.length(), 1.0)
	var q: float = Sim.PLANET_R / rl
	# towards the centre, an inverse square
	var a: Vector3 = r * (-G0 * q * q / rl)
	# the planet turning under it
	a -= 2.0 * w.cross(v)
	if k > 0.0:
		var h: float = clampf(rl - Sim.PLANET_R, -500.0, 80000.0)
		a -= v * (v.length() * k * exp(-h / RHO_SCALE))
	return a

## The velocity after one tick, for a round that has flown `flown` metres.
static func step(p: Vector3, v: Vector3, k: float, dt: float, flown: float) -> Vector3:
	if flown < NEAR:
		return v + Vector3.DOWN * G0 * dt
	return v + accel(p, v, k, spin()) * dt

## Fly a round from `o` at `v0` until it has come as far as `to` across the
## ground, and say where it is then: [point, seconds], or [] if it comes down
## or runs out of time first. The same model as `step`, taken in big midpoint
## steps -- this is asked a few times per solution, not every tick.
static func fly(o: Vector3, v0: Vector3, k: float, to: Vector3, max_t: float) -> Array:
	var w := spin()
	var goal: float = Vector2(to.x - o.x, to.z - o.z).length()
	var dt: float = clampf(max_t / 400.0, 1.0 / 120.0, 0.25)
	var p := o
	var v := v0
	var t := 0.0
	var flown := 0.0
	var gone := 0.0
	while t < max_t:
		var a1: Vector3 = Vector3.DOWN * G0 if flown < NEAR else accel(p, v, k, w)
		var vm: Vector3 = v + a1 * (dt * 0.5)
		var pm: Vector3 = p + v * (dt * 0.5)
		var a2: Vector3 = Vector3.DOWN * G0 if flown < NEAR else accel(pm, vm, k, w)
		var p2: Vector3 = p + vm * dt
		v += a2 * dt
		flown += vm.length() * dt
		var gone2: float = Vector2(p2.x - o.x, p2.z - o.z).length()
		if gone2 >= goal:
			var f: float = clampf((goal - gone) / maxf(gone2 - gone, 1e-6), 0.0, 1.0)
			return [p.lerp(p2, f), t + dt * f]
		# into the ground well short: it never gets there
		if v.y < 0.0 and p2.y < to.y - 400.0:
			return []
		p = p2
		gone = gone2
		t += dt
	return []

## How to send a round at `speed` so that it comes down on `to`, as a
## direction, starting from the vacuum answer `guess` and correcting it against
## the full model: elevation by the secant on the height it arrives at, and
## bearing by how far to one side it arrives. Returns {"dir", "tof"}, or an
## empty dictionary if it cannot be got there.
static func solve(o: Vector3, to: Vector3, speed: float, k: float, guess: Vector3) -> Dictionary:
	var flat := Vector2(to.x - o.x, to.z - o.z)
	var rng: float = flat.length()
	if rng < 1.0 or guess == Vector3.ZERO:
		return {}
	var el: float = asin(clampf(guess.y, -1.0, 1.0))
	var yaw: float = atan2(guess.x, -guess.z)
	var t_max: float = maxf(rng / maxf(speed * 0.25, 1.0), 4.0) + 10.0
	var prev_el := INF
	var prev_err := 0.0
	var tof := 0.0
	for it in 6:
		var dir := Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
		var got: Array = fly(o, dir * speed, k, to, t_max)
		if got.is_empty():
			# short of it: more elevation, if there is any left to give
			el = minf(el + 0.05, deg_to_rad(44.0))
			prev_el = INF
			continue
		var at: Vector3 = got[0]
		tof = got[1]
		var err: float = at.y - to.y
		# to one side: signed, across the line to the target
		var side := Vector2(flat.y, -flat.x).normalized()
		var lat: float = Vector2(at.x - o.x, at.z - o.z).dot(side)
		if absf(err) < 0.05 and absf(lat) < 0.05:
			return {"dir": dir, "tof": tof}
		var next_el: float
		if prev_el == INF or absf(err - prev_err) < 1e-6:
			next_el = el - err / maxf(rng, 1.0)
		else:
			next_el = el - err * (el - prev_el) / (err - prev_err)
		prev_el = el
		prev_err = err
		el = clampf(next_el, deg_to_rad(-80.0), deg_to_rad(80.0))
		yaw += lat / maxf(rng, 1.0)
	return {"dir": Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el)), "tof": tof}

## The same at a fixed elevation, finding the charge instead: how a howitzer
## at its quadrant elevation reaches a range. {"speed", "yaw", "tof"}, or {}.
static func solve_charge(o: Vector3, to: Vector3, el: float, v_guess: float, v_max: float,
		k: float) -> Dictionary:
	var flat := Vector2(to.x - o.x, to.z - o.z)
	var rng: float = flat.length()
	if rng < 1.0:
		return {}
	var yaw: float = atan2(flat.x, -flat.y)
	var v: float = clampf(v_guess, 20.0, v_max)
	var prev_v := INF
	var prev_err := 0.0
	var tof := 0.0
	var t_max: float = maxf(rng / maxf(v_max * cos(el) * 0.3, 1.0), 4.0) + 20.0
	for it in 7:
		var dir := Vector3(sin(yaw) * cos(el), sin(el), -cos(yaw) * cos(el))
		var got: Array = fly(o, dir * v, k, to, t_max)
		if got.is_empty():
			if v >= v_max - 0.01:
				return {}
			v = minf(v * 1.15, v_max)
			prev_v = INF
			continue
		var at: Vector3 = got[0]
		tof = got[1]
		# high when it gets there means it would have carried on: too much
		var err: float = at.y - to.y
		var side := Vector2(flat.y, -flat.x).normalized()
		yaw += Vector2(at.x - o.x, at.z - o.z).dot(side) / maxf(rng, 1.0)
		if absf(err) < 0.1:
			break
		var next_v: float
		if prev_v == INF or absf(err - prev_err) < 1e-6:
			next_v = v * (1.0 - clampf(err / maxf(rng, 1.0), -0.3, 0.3))
		else:
			next_v = v - err * (v - prev_v) / (err - prev_err)
		prev_v = v
		prev_err = err
		v = clampf(next_v, 20.0, v_max)
	return {"speed": v, "yaw": yaw, "tof": tof}
