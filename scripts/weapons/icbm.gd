class_name Icbm
extends Node3D
## An intercontinental ballistic missile, and the warheads it turns into.
##
## It is not a `Missile`. Those are steered all the way in over a world that is
## flat enough to aim across, and their arithmetic -- range as v squared over g,
## a target at an `x` and a `z` -- stops meaning anything a tenth of the way
## round a planet. This flies the way the real thing does:
##
## * three stages burn in turn and fall away, steering not at the target but at
##   the *velocity* that would fall onto it (`Orbit.v_required`);
## * the moment it is going at that, the motor is cut. From there to the far
##   side of the world nothing steers it: it is a thrown stone, and where it
##   comes down was settled at burnout. That arc is integrated in the planet's
##   own frame under Newton's gravity, which is the only reason it arrives;
## * above the air it opens, and each warhead is put on its own arc to its own
##   mark -- that is what independently targetable means;
## * each one comes back in at seven kilometres a second, trims the last of
##   its error out in the air, and goes off on the ground.
##
## The round you launch becomes the first of its own warheads when it opens, so
## a camera riding it rides it all the way down.

## Burn time, and thrust acceleration at the start and end of the burn, for
## each stage. A stage gets lighter as it burns, so it pushes harder at the end
## than at the beginning.
const STAGES := [[62.0, 22.0, 46.0], [60.0, 30.0, 62.0], [64.0, 36.0, 92.0]]
## Straight up for this long before it tips over: clear of the launcher.
const RISE := 6.0
## Height at which the warheads start to steer themselves, and how hard.
const TERMINAL_ALT := 70_000.0
const TERMINAL_G := 30.0

var wid := "yars"
var ws: Dictionary = {}
var shooter: Node = null
var team := 0
## Velocity in the world's frame, for whatever is watching it.
var vel := Vector3.ZERO
## Where each warhead is going: a direction from the planet's centre, or the
## unit it was locked on. The first is the round's own.
var marks: Array = []
## A warhead rather than the missile that carried it.
var rv := false
var age := 0.0
var dead := false

var _s := PackedFloat64Array()
var _stage := 0
var _stage_t := 0.0
var _burning := true
var _opened := false
var _coast_t := 0.0
var _body: Node3D
var _segs: Array = []
var _flame: MeshInstance3D
var _glow: OmniLight3D
var _trail: GPUParticles3D
var _ribbon: GeometryInstance3D
var _glow_rv: Effects.Plasma = null
var _said_reentry := false
var _nose := Vector3.UP

## Stand one on a launcher and light it. `from` is where it is in the world;
## `targets` is one mark per warhead, primary first -- a world point or a unit.
static func launch(world: Node, id: String, from: Vector3, by: Node, side: int,
		targets: Array) -> Icbm:
	var m := Icbm.new()
	m.wid = id
	m.ws = WeaponSpec.get_spec(id)
	m.shooter = by
	m.team = side
	for t in targets:
		if t is Vector3:
			m.marks.append(Sim.chart_to_dir((t as Vector3).x, (t as Vector3).z))
		elif t is Node3D and is_instance_valid(t):
			m.marks.append(t)
	var p: Vector3 = Sim.world_to_space(from)
	m._s = Orbit.make(p, p.normalized() * 4.0)
	world.add_child(m)
	m.global_position = from
	return m

func _ready() -> void:
	top_level = true
	add_to_group("icbm")
	if ws.is_empty():
		ws = WeaponSpec.get_spec(wid)
	_body = Node3D.new()
	add_child(_body)
	if rv:
		_build_rv()
	else:
		_build_stack()
	_place()
	reset_physics_interpolation()

# ------------------------------------------------------------------ the model
func _build_stack() -> void:
	var L: float = float(ws["length"])
	var r: float = float(ws["dia"]) * 0.5
	var body: Color = ws.get("colour", Color(0.3, 0.32, 0.3))
	var band: Color = ws.get("band", Color(0.6, 0.5, 0.15))
	# nose at -Z, like everything else that flies; three stages from the tail
	var cuts: Array = STACK_CUTS
	for i in 3:
		var st := MeshKit.begin()
		var z0: float = L * float(cuts[i + 1])
		var z1: float = L * float(cuts[i])
		var rr: float = r * (1.0 - 0.10 * float(i))
		MeshKit.cone(st, rr, rr, z0, z1, Vector3.ZERO, 14)
		# an interstage ring, which is where it comes apart
		MeshKit.cone(st, rr * 1.03, rr * 1.03, z0, z0 + L * 0.012, Vector3.ZERO, 14)
		# and the nozzle it will be flying on once the one below has gone
		MeshKit.cone(st, rr * 0.34, rr * 0.62, z1, z1 + L * 0.03, Vector3.ZERO, 10)
		var seg := MeshKit.mi(MeshKit.finish(st,
			MeshKit.mat(body.lerp(band, 0.12 * float(i)), 0.5, 0.3)), "Stage%d" % (i + 1))
		_body.add_child(seg)
		_segs.append(seg)
	var nst := MeshKit.begin()
	MeshKit.cone(nst, 0.03, r * 0.72, -L * 0.5, -L * 0.34, Vector3.ZERO, 14)
	_body.add_child(MeshKit.mi(MeshKit.finish(nst, MeshKit.mat(band, 0.4, 0.35)), "Shroud"))
	var fst := MeshKit.begin()
	MeshKit.cone(fst, r * 0.7, 0.05, 0.0, 9.0 + r * 9.0, Vector3.ZERO, 10, false)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	fm.albedo_color = Color(1.0, 0.86, 0.6, 0.8)
	fm.render_priority = 6
	_flame = MeshKit.mi(MeshKit.finish(fst, fm), "Flame")
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0, 0, L * 0.5)
	_body.add_child(_flame)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.74, 0.44)
	_glow.light_energy = 9.0
	_glow.omni_range = 420.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0, 0, L * 0.5 + 2.0)
	_body.add_child(_glow)
	_trail = Effects.trail_particles(Color(0.95, 0.93, 0.9), 6.0, 150)
	_trail.position = Vector3(0, 0, L * 0.5)
	_body.add_child(_trail)
	# No ribbon behind the stack. It is a flat band three metres wide laid
	# along the flight, and a camera riding the round sits beside that band:
	# from there it is a white wedge across a third of the screen. The puffs
	# are the smoke; they are round from every side.

func _build_rv() -> void:
	var st := MeshKit.begin()
	MeshKit.cone(st, 0.02, 0.28, -0.95, 0.85, Vector3.ZERO, 12)
	_body.add_child(MeshKit.mi(MeshKit.finish(st,
		MeshKit.mat(Color(0.10, 0.10, 0.11), 0.35, 0.5)), "Warhead"))

## The round has opened: what is left of it is one warhead.
func _become_rv() -> void:
	rv = true
	for c in _body.get_children():
		c.queue_free()
	_segs.clear()
	_flame = null
	_glow = null
	_trail = null
	_ribbon = null
	_build_rv()

# --------------------------------------------------------------------- flight
func alt() -> float:
	return Orbit.radius(_s) - Sim.PLANET_R

## Where this warhead's mark is now, as a point in the planet's frame.
func _mark_point() -> Vector3:
	if marks.is_empty():
		return Vector3.ZERO
	var mk: Variant = marks[0]
	if mk is Vector3:
		var d: Vector3 = mk
		var q: Vector2 = Sim.dir_to_chart(d)
		var h: float = maxf(Sim.height_at(q.x, q.y) + Sim.planet_drop(q.x, q.y), 0.0)
		return d * (Sim.PLANET_R + h)
	if mk is Node3D and is_instance_valid(mk):
		return Sim.world_to_space((mk as Node3D).global_position)
	return Vector3.ZERO

func _physics_process(delta: float) -> void:
	if dead:
		return
	age += delta
	Orbit.sync()
	var h: float = alt()
	if not rv and _burning:
		_boost(delta)
	else:
		# Only what is coasting above the air is hurried, and only if somebody
		# has asked for it.
		var span: float = delta * Sim.warp_at(h, false)
		_coast_t += span
		if rv and h < TERMINAL_ALT:
			_steer(span)
		# a warhead is a dense thing: it keeps most of its speed to the ground
		Orbit.advance(_s, span, 1.0 if h < 150000.0 else 4.0, Vector3.ZERO,
			0.00005 if rv else 0.0006)
		if not rv and not _opened and _coast_t > 4.0:
			_open()
	_place()
	if rv:
		_reentry(h)
		_fuse()
	elif not _burning and h < 60000.0 and Orbit.vel_of(_s).dot(Orbit.pos_of(_s)) < 0.0:
		# a bus that never opened -- no marks -- comes apart on the way down
		_end(false)

## One tick under power.
func _boost(delta: float) -> void:
	var st: Array = STAGES[_stage]
	_stage_t += delta
	var f: float = clampf(_stage_t / float(st[0]), 0.0, 1.0)
	var a_t: float = lerpf(float(st[1]), float(st[2]), f)
	var p: Vector3 = Orbit.pos_of(_s)
	var v: Vector3 = Orbit.vel_of(_s)
	var up: Vector3 = p.normalized()
	var dir: Vector3 = up
	var done := false
	var tgt: Vector3 = _mark_point()
	if age > RISE and tgt != Vector3.ZERO:
		var need: Vector3 = Orbit.v_required(p, tgt, tgt.length() - Sim.PLANET_R)
		if need != Vector3.ZERO:
			var gain: Vector3 = need - v
			var left: float = gain.length()
			# Going at it, near enough that one more tick would overshoot:
			# that is burnout, and from here it is a thrown stone.
			if left < a_t * delta * 1.2 and age > RISE + 4.0:
				for i in 3:
					_s[3 + i] = need[i]
				done = true
			else:
				# Thrust so that what is left after gravity points along the
				# velocity still to be gained.
				var g: Vector3 = up * (-Orbit.GM / p.length_squared())
				dir = (gain / maxf(left, 0.001) * a_t - g).normalized()
		# It has to get out of the air first. The speed it is after is mostly
		# sideways, and a missile that goes sideways off the pad goes into the
		# hill; the nose is held up, and let down as it climbs.
		var floor_el: float = lerpf(deg_to_rad(88.0), deg_to_rad(8.0),
			smoothstep(RISE, 95.0, age))
		if p.length() - Sim.PLANET_R < 130000.0:
			var el: float = asin(clampf(dir.dot(up), -1.0, 1.0))
			if el < floor_el:
				var flat: Vector3 = dir - up * dir.dot(up)
				if flat.length() < 1e-4:
					flat = (tgt.normalized() - up * up.dot(tgt.normalized()))
				dir = (flat.normalized() * cos(floor_el) + up * sin(floor_el)).normalized()
	_nose = dir
	if done:
		_cut()
		return
	Orbit.advance(_s, delta, 0.02, dir * a_t)
	if _flame:
		_flame.scale = Vector3.ONE * (0.9 + 0.2 * sin(age * 51.0))
	if _stage_t >= float(st[0]):
		_drop_stage()

func _drop_stage() -> void:
	if _stage < _segs.size() and is_instance_valid(_segs[_stage]):
		var seg: MeshInstance3D = _segs[_stage]
		var d := Effects.Debris.new()
		d.life = 40.0
		var xf: Transform3D = seg.global_transform
		seg.get_parent().remove_child(seg)
		d.add_child(seg)
		seg.transform = Transform3D.IDENTITY
		get_tree().current_scene.add_child(d)
		d.global_transform = xf
		d.vel = vel - _nose * 12.0
		d.spin = Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.6, 0.6))
	_stage += 1
	_stage_t = 0.0
	if _stage >= STAGES.size():
		_cut()
		return
	# the flame moves up to the stage that is now the bottom one
	var L: float = float(ws["length"])
	var at: float = L * float([0.5, 0.18, -0.12][_stage])
	for n in [_flame, _glow, _trail, _ribbon]:
		if n != null and is_instance_valid(n):
			(n as Node3D).position.z = at
	if is_instance_valid(shooter) and team == 0:
		Sim.report("%s: stage %d away, %d alight — %.0f km up" % [
			String(ws["short"]), _stage, _stage + 1, alt() * 0.001], Sim.Ev.INFO)

func _cut() -> void:
	_burning = false
	if _flame:
		_flame.visible = false
	if _glow:
		_glow.light_energy = 0.0
	if _trail:
		_trail.emitting = false
	if _ribbon != null:
		_ribbon.set(&"emitting", false)
	var ap: Dictionary = Orbit.apsides(_s)
	if is_instance_valid(shooter) and team == 0:
		var tgt: Vector3 = _mark_point()
		var arc: float = 0.0
		if tgt != Vector3.ZERO:
			arc = acos(clampf(Orbit.pos_of(_s).normalized().dot(tgt.normalized()), -1.0, 1.0)) \
				* Sim.PLANET_R
		Sim.report("%s: burnout at %.0f km, %.1f km/s — %.0f km to run, over the top at %.0f km" % [
			String(ws["short"]), alt() * 0.001, Orbit.speed(_s) * 0.001, arc * 0.001,
			float(ap["ap"]) * 0.001], Sim.Ev.INFO)

## Open, above the air: every warhead onto its own arc.
func _open() -> void:
	_opened = true
	var count: int = maxi(int(ws.get("mirv", 1)), 1)
	var p: Vector3 = Orbit.pos_of(_s)
	var own: Array = marks.duplicate()
	if own.is_empty():
		return
	# Fewer marks than warheads: the rest are laid in a ring round the first,
	# so one aiming point still gets the whole load across it.
	var first: Vector3 = _mark_point()
	var spread: float = float(ws.get("mirv_spread", 3000.0))
	var k := 0
	while own.size() < count:
		var d: Vector3 = first.normalized()
		var side: Vector3 = d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
		var fwd: Vector3 = d.cross(side)
		var a: float = TAU * float(k) / float(maxi(count - marks.size(), 1))
		own.append((d + (side * cos(a) + fwd * sin(a)) * (spread / Sim.PLANET_R)).normalized())
		k += 1
	var world := get_tree().current_scene
	for i in range(1, count):
		var w := Icbm.new()
		w.wid = wid
		w.ws = ws
		w.shooter = shooter
		w.team = team
		w.rv = true
		w._burning = false
		w._opened = true
		w.marks = [own[i]]
		w._s = _s.duplicate()
		world.add_child(w)
		w._aim_arc()
	marks = [own[0]]
	_become_rv()
	_aim_arc()
	if is_instance_valid(shooter) and team == 0:
		Sim.report("%s: %d warheads released at %.0f km" % [String(ws["short"]),
			count, (p.length() - Sim.PLANET_R) * 0.001], Sim.Ev.BAD)

## Put this warhead on the arc that comes down on its own mark.
func _aim_arc() -> void:
	var tgt: Vector3 = _mark_point()
	if tgt == Vector3.ZERO:
		return
	var need: Vector3 = Orbit.v_required(Orbit.pos_of(_s), tgt, tgt.length() - Sim.PLANET_R)
	# The bus has only so much to give each one. A mark it cannot reach from
	# here keeps the arc it was released on.
	if need != Vector3.ZERO and (need - Orbit.vel_of(_s)).length() < 900.0:
		for i in 3:
			_s[3 + i] = need[i]

## The last of the error, taken out in the air: turn the velocity towards the
## mark, as hard as the warhead can pull at the speed it is doing.
func _steer(dt: float) -> void:
	var tgt: Vector3 = _mark_point()
	if tgt == Vector3.ZERO:
		return
	var los := Vector3(tgt.x - _s[0], tgt.y - _s[1], tgt.z - _s[2])
	var v: Vector3 = Orbit.vel_of(_s)
	var sp: float = v.length()
	if sp < 50.0 or los.length() < 30.0:
		return
	var axis: Vector3 = v.cross(los)
	if axis.length() < 1e-6:
		return
	var off: float = v.angle_to(los)
	# thin air gives it less to push against
	var bite: float = clampf(Orbit.rho(alt()) / 0.04, 0.12, 1.0)
	var turn: float = minf(off, TERMINAL_G * 9.81 * bite / sp * dt)
	var nv: Vector3 = v.rotated(axis.normalized(), turn)
	for i in 3:
		_s[3 + i] = nv[i]

## Where the node is, and which way it points.
func _place() -> void:
	var p: Vector3 = Orbit.pos_of(_s)
	var at: Vector3 = Sim.space_to_world(p)
	var v: Vector3 = Sim.planet_to_world_dir(Orbit.vel_of(_s))
	vel = v
	var nose: Vector3 = Sim.planet_to_world_dir(_nose) if (_burning and not rv) else v
	if nose.length_squared() < 0.01:
		nose = Vector3.UP
	nose = nose.normalized()
	var ref: Vector3 = Vector3.UP if absf(nose.y) < 0.98 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(nose, ref), at)

## Coming back into the air, a warhead is the brightest thing in the sky.
func _reentry(h: float) -> void:
	var falling: bool = Orbit.vel_of(_s).dot(Orbit.pos_of(_s)) < 0.0
	if not falling or h > 125000.0:
		if _glow_rv != null:
			_glow_rv.feed(global_position, vel, 0.0)
		return
	var heat: float = Effects.reentry_heat(h, Orbit.speed(_s))
	if _glow_rv == null and heat > 0.01:
		# drawn a good deal bigger than the warhead itself, which is a cone
		# half a metre across: the glow is what you see of it from anywhere
		_glow_rv = Effects.plasma(self, 0.75)
		# a thread of fire, not a band: see the note on the stack's smoke
		_ribbon = Effects.ribbon(Color(1.0, 0.62, 0.32, 0.3), 0.14, 0.7, 30.0, true, 1)
		if _ribbon != null:
			add_child(_ribbon)
			_ribbon.call(&"clear")
	if _glow_rv != null:
		_glow_rv.feed(get_global_transform_interpolated().origin, vel, heat)
		if _ribbon != null:
			_ribbon.set(&"emitting", heat > 0.05)
	if heat < 0.05:
		return
	if not _said_reentry and is_instance_valid(shooter) and team == 0:
		_said_reentry = true
		Sim.report("%s warhead: re-entry, %.1f km/s" % [String(ws["short"]),
			Orbit.speed(_s) * 0.001], Sim.Ev.INFO)

## On the mark, or on the ground short of it.
func _fuse() -> void:
	if age < 2.0:
		return
	var h: float = alt()
	if h > 14000.0:
		return
	var at: Vector3 = global_position
	var ground: float = maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z))
	var tgt: Vector3 = _mark_point()
	var near: bool = tgt != Vector3.ZERO \
		and Vector3(tgt.x - _s[0], tgt.y - _s[1], tgt.z - _s[2]).length() < 90.0
	if at.y <= ground + 2.0 or near:
		global_position = Vector3(at.x, maxf(at.y, ground + 1.0), at.z)
		_end(true)

## How far this warhead is from its mark, along the ground. For the harness.
func miss() -> float:
	var tgt: Vector3 = _mark_point()
	if tgt == Vector3.ZERO:
		return -1.0
	# As a distance between two points, in doubles. The angle between two unit
	# vectors held in single precision cannot be told from nothing until it is
	# three kilometres of ground: a warhead that burst on its mark and one two
	# miles off both came back as "0 m", or as 2200, or as 3111, and nothing
	# between.
	var r: float = Orbit.radius(_s)
	var tl: float = tgt.length()
	var dx: float = _s[0] / r - float(tgt.x) / tl
	var dy: float = _s[1] / r - float(tgt.y) / tl
	var dz: float = _s[2] / r - float(tgt.z) / tl
	return sqrt(dx * dx + dy * dy + dz * dz) * Sim.PLANET_R

func _end(burst: bool) -> void:
	if dead:
		return
	dead = true
	var world := get_tree().current_scene
	var at: Vector3 = global_position
	if not burst:
		Effects.explosion(world, at, 8.0, false)
		queue_free()
		return
	last_miss = miss()
	var lethal: float = float(ws.get("lethal", 3000.0))
	var hit := 0
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not n.has_method("take_hit"):
			continue
		var d: float = (n as Node3D).global_position.distance_to(at)
		if n.has_method("surface_gap"):
			d = maxf(n.surface_gap(at), 0.0)
		elif n.has_method("hit_radius"):
			d = maxf(d - n.hit_radius(), 0.0)
		if d < lethal:
			n.take_hit(float(ws.get("damage", 90000.0)) * clampf(1.0 - d / lethal, 0.15, 1.0),
				shooter if is_instance_valid(shooter) else null)
			hit += 1
	var flattened := 0
	var scn: Variant = world.get("scenery")
	if scn != null and is_instance_valid(scn) and scn.has_method("damage_area"):
		flattened = scn.damage_area(at, lethal * 0.55)
	Effects.nuke(world, at, lethal)
	if team == 0:
		Sim.report("%s warhead: detonation, %.0f m from the mark — %d units inside it" % [
			String(ws["short"]), last_miss, hit], Sim.Ev.BAD)
	if Sim.debug_weapons:
		var tq: Vector3 = _mark_point()
		print("[icbm]   mark %.0f m above datum, burst %.0f m above datum, speed %.0f, dive %.1f deg, ground under burst %.0f" % [
			tq.length() - Sim.PLANET_R, alt(), Orbit.speed(_s),
			rad_to_deg(asin(clampf(-Orbit.vel_of(_s).normalized().dot(Orbit.pos_of(_s).normalized()), -1.0, 1.0))),
			maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z)) + Sim.planet_drop(at.x, at.z)])
		print("[icbm] %s detonated at %s after %.0f s (%.0f s of coast): %.0f m off, %d units, %d structures" % [
			wid, str(at.round()), age, _coast_t, last_miss, hit, flattened])
	detonated.emit(self)
	queue_free()

signal detonated(who)
var last_miss := -1.0

func get_velocity() -> Vector3:
	return vel

## How far back a camera riding this should stand, as a multiple of what it
## stands off a missile a few metres long: the stack is twenty-two.
func ride_scale() -> float:
	if rv:
		return 1.0
	return maxf(_left_len() / 5.5, 1.5)

## How much of the stack is still there, and where the middle of it is along
## the body: what a camera should be looking at, which stops being the node's
## own origin as soon as the first stage has gone.
const STACK_CUTS := [0.5, 0.18, -0.12, -0.34]

func _left_len() -> float:
	return float(ws.get("length", 20.0)) * (STACK_CUTS[mini(_stage, 3)] + 0.5)

func ride_centre() -> Vector3:
	if rv:
		return Vector3.ZERO
	var L: float = float(ws.get("length", 20.0))
	return Vector3(0.0, 0.0, L * (STACK_CUTS[mini(_stage, 3)] - 0.5) * 0.5)

## Where it is, in the planet's frame.
func space_pos() -> Vector3:
	return Orbit.pos_of(_s)

var _path := PackedVector3Array()
var _path_ms := -100000

## The rest of its flight, flown ahead: points in the planet's frame down to
## where it meets the ground. Worked out afresh a couple of times a second at
## most, because a map draws every frame and the answer barely changes.
func path_ahead() -> PackedVector3Array:
	var ms: int = Time.get_ticks_msec()
	if ms - _path_ms < 1500 and not _path.is_empty():
		return _path
	_path_ms = ms
	var keep: float = Orbit.now
	var s: PackedFloat64Array = _s.duplicate()
	var out := PackedVector3Array()
	out.append(Orbit.pos_of(s))
	for i in 400:
		Orbit.step(s, 12.0)
		out.append(Orbit.pos_of(s))
		if Orbit.radius(s) < Sim.PLANET_R:
			break
	Orbit.now = keep
	Orbit._moon_at(keep)
	_path = out
	return out

func is_alive() -> bool:
	return not dead
