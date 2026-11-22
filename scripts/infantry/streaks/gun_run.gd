class_name GunRun
extends Node3D
## A pair of A-10s down a line drawn on the map, guns firing.
##
## They come in from well out, diving shallow toward the start of the line; at a
## kilometre and a bit the leader opens up and walks his fire from one end of
## the line to the other, the wingman a second and a half behind him and a few
## metres to one side, and both pull up and away over the far end. The rounds
## are seen -- tracer from the nose to where they land -- and land a moment
## after they are fired, which is the thing a gun run sounds like from the
## ground: the strikes first, the gun after.

## A picture of a strike called on another machine: flies and goes off
## here, and hurts nobody. See `Killstreaks.call_picture`.
var picture := false
const SPEED := 190.0
const RUN_IN := 3600.0
## The dive, and the climb out after.
const DIVE := 0.19
const CLIMB := 0.26
## Lowest it comes, over the middle of the line.
const LOW := 110.0
const SLANT := 1150.0
const BURST := 2.2
## What is drawn and what lands, a second: the gun's sixty-five rounds a
## second, thinned to what the eye and the frame can take.
const RATE := 24.0
const SPREAD := 6.0
const SHELL_SPEED := 1000.0
const WING := Vector3(16.0, 0.0, 0.0)
const TRAIL := 1.5
var arena: CqbMatch = null
var from := Vector3.ZERO
var to := Vector3.ZERO
var eta := 0.0
var _dir := Vector3.FORWARD
var _len := 0.0
var _t := 0.0
var _jets: Array = []          # [model, lateral offset, delay]
var _fire0 := 0.0              # when the leader opens up, from the start
var _landing: Array = []       # [time it lands, where]
var _shots: Array = [0, 0]     # rounds fired by each jet
var _gone := 0.0
static var _tracer: Mesh = null

func _init() -> void:
	top_level = true

func _enter_tree() -> void:
	if not _jets.is_empty():
		return
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	_len = clampf(flat.length(), 40.0, 450.0)
	_dir = flat.normalized() if flat.length() > 1.0 else Vector3.FORWARD
	# fire opens when the leader is a slant range short of the line's start
	var s_open: float = -sqrt(maxf(SLANT * SLANT - _height_at(-SLANT * 0.95) * _height_at(-SLANT * 0.95), 1.0))
	_fire0 = (RUN_IN + s_open) / SPEED
	eta = _fire0 + SLANT / SHELL_SPEED
	_gone = (RUN_IN + _len + RUN_IN) / SPEED + TRAIL
	for k in 2:
		var spec: Dictionary = JetSpec.get_spec("a10").duplicate(true)
		var m: Dictionary = JetFactory.build(spec)
		for g in m["gear"]:
			(g as Node3D).visible = false
		for st in m["stores"]:
			(m["stores"][st] as Node3D).visible = true
		var root: Node3D = m["root"]
		root.top_level = true
		add_child(root)
		_jets.append([root, WING * float(k), TRAIL * float(k)])
	_place(0.0)
	for j in _jets:
		(j[0] as Node3D).reset_physics_interpolation()
	Sfx.play_at(get_parent(), "roar", from - _dir * RUN_IN, 10.0, 1.15, 9000.0)
	if GunRun._tracer == null:
		var tm := BoxMesh.new()
		tm.size = Vector3(0.12, 0.12, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.82, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.3)
		mat.emission_energy_multiplier = 5.0
		tm.material = mat
		GunRun._tracer = tm

## Height over the line's own ground at `s` metres along it: down the dive
## to the lowest point over the middle, then up the climb.
func _height_at(s: float) -> float:
	var mid: float = _len * 0.5
	if s < mid:
		return LOW + (mid - s) * DIVE
	return LOW + (s - mid) * CLIMB

## Where a jet is at `t` seconds into the run, `side` off the leader's track.
func _pos(t: float, side: Vector3) -> Vector3:
	var s: float = t * SPEED - RUN_IN
	var across: Vector3 = _dir.cross(Vector3.UP).normalized() * side.x
	var g: Vector3 = from + _dir * s + across
	return Vector3(g.x, from.y + minf(_height_at(s), 2500.0), g.z)

func _place(t: float) -> void:
	for j in _jets:
		var tt: float = t - float(j[2])
		var p: Vector3 = _pos(tt, j[1])
		var ahead: Vector3 = _pos(tt + 0.2, j[1])
		var jn: Node3D = j[0]
		jn.global_position = p
		if ahead.distance_to(p) > 0.1:
			jn.look_at(ahead, Vector3.UP)

func lead_at() -> Vector3:
	return _pos(_t, Vector3.ZERO)

## Seconds until the first rounds land.
func until_fire() -> float:
	return maxf(eta - _t, 0.0)

func _physics_process(delta: float) -> void:
	_t += delta
	_place(_t)
	for k in _jets.size():
		var j: Array = _jets[k]
		var tf: float = _t - float(j[2]) - _fire0
		if tf < 0.0 or tf > BURST:
			continue
		var want: int = int(tf * RATE)
		while int(_shots[k]) < want:
			_shots[k] = int(_shots[k]) + 1
			# walked from one end of the line to the other over the burst
			var f: float = clampf(float(_shots[k]) / (BURST * RATE), 0.0, 1.0)
			var across: Vector3 = _dir.cross(Vector3.UP).normalized() * (j[1] as Vector3).x
			var aim: Vector3 = from + _dir * (_len * f) + across \
				+ Vector3(randf_range(-SPREAD, SPREAD), 0.0, randf_range(-SPREAD, SPREAD))
			aim.y = Sim.height_at(aim.x, aim.z)
			var muzzle: Vector3 = (j[0] as Node3D).global_position
			_streak(muzzle, aim)
			_landing.append([_t + muzzle.distance_to(aim) / SHELL_SPEED, aim])
			if int(_shots[k]) % 6 == 1:
				Sfx.play_at(get_parent(), "autocannon", muzzle, 9.0, 0.55, 6000.0)
	var keep: Array = []
	for l in _landing:
		if _t >= float(l[0]):
			if is_instance_valid(arena):
				arena.streaks.cannon(l[1], picture)
		else:
			keep.append(l)
	_landing = keep
	if _t >= _gone and _landing.is_empty():
		queue_free()

## A tracer from the gun to where it lands, there for a blink.
func _streak(a: Vector3, b: Vector3) -> void:
	var streak_mi := MeshInstance3D.new()
	streak_mi.mesh = GunRun._tracer
	streak_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	streak_mi.top_level = true
	add_child(streak_mi)
	var along_ab: Vector3 = a.lerp(b, randf_range(0.35, 0.8))
	var lenv: float = minf(a.distance_to(b) * 0.25, 60.0)
	streak_mi.global_position = along_ab
	streak_mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.98 else Vector3.FORWARD)
	streak_mi.scale = Vector3(1.0, 1.0, lenv)
	get_tree().create_timer(0.07).timeout.connect(streak_mi.queue_free)
