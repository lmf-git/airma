class_name MortarRound
extends Node3D
## One mortar round in the air. Fired from a battery off behind the man who
## called it, it climbs and comes down on its mark when the plan said it would,
## and goes off as the match's own bombs do, credited to him. It was a timer
## with a bang at the end of it: nothing in the sky and nothing on the map
## between the call and the round landing.

const G := 9.81
var arena: CqbMatch = null
var from := Vector3.ZERO
var to := Vector3.ZERO
## Time of flight, and how long after the call it is fired.
var flight := 12.0
var delay := 0.0
var vel := Vector3.ZERO
var _t := 0.0
var _v0 := Vector3.ZERO
var _fired := false
var _whiz := false
var _trail: GeometryInstance3D = null
## Who fired it from a tube of his own (see `Walker._mortar`); null for a
## barrage called in.
var shooter: Node3D = null
## A picture of a round fired on another machine: lands and goes off here,
## hurts nothing. See `NetLaunches.share_round`.
var picture := false
static var _mesh: Mesh = null
## How hard it knocks a building about, in direct hits of a 60 mm bomb, and
## how far from a wall that still counts: see `Obstacles.batter`.
var blow := 1.0
var blow_r := 6.0

## Where a round coming down on (x, z) goes off: on the roof of whatever stands
## there, not on the ground under it. Laid on the ground, a bomb on a block went
## off inside the ground floor, under the roof it had come down through.
static func lands_at(x: float, z: float) -> Vector3:
	return Vector3(x, maxf(Sim.height_at(x, z), Obstacles.top_at(x, z)), z)

## Wear down whatever it went off on or beside.
func _batter() -> void:
	if Scenery.current != null and is_instance_valid(Scenery.current):
		Scenery.current.batter(to, blow_r, blow)

func _init() -> void:
	top_level = true

func _ready() -> void:
	if MortarRound._mesh == null:
		var st := MeshKit.begin()
		MeshKit.cone(st, 0.06, 0.06, -0.22, 0.12, Vector3.ZERO, 8)
		MeshKit.cone(st, 0.0, 0.06, -0.34, -0.22, Vector3.ZERO, 8)
		MeshKit.box(st, Vector3(0.16, 0.01, 0.1), Vector3(0, 0, 0.18))
		MeshKit.box(st, Vector3(0.01, 0.16, 0.1), Vector3(0, 0, 0.18))
		MortarRound._mesh = MeshKit.finish(st, MeshKit.mat(Color(0.25, 0.28, 0.22), 0.6, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = MortarRound._mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A 120 mm bomb, not a pencil: at a third of a metre and dark green it
	# could not be picked out against the sky at any range, so a barrage
	# was ten bangs out of nowhere.
	mi.scale = Vector3.ONE * 1.9
	add_child(mi)
	# and the streak it leaves coming down: a faint grey line is what you
	# actually see of a mortar round in the air
	var rb := Effects.ribbon(Color(0.82, 0.80, 0.76, 0.55), 0.35, 0.9, 3.0, false, 1)
	if rb != null:
		rb.top_level = true
		add_child(rb)
		_trail = rb
	# Up and over: the vertical speed that carries it from the tube to the
	# mark in exactly the time of flight, which is a mortar's arc -- a few
	# hundred metres up -- for a battery a kilometre or so off.
	_v0 = Vector3((to.x - from.x) / flight,
		(to.y - from.y + 0.5 * G * flight * flight) / flight, (to.z - from.z) / flight)
	vel = _v0
	visible = false
	global_position = from
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if not _fired:
		delay -= delta
		if delay > 0.0:
			return
		_fired = true
		visible = true
		Sfx.play_at(get_parent(), "thump", from, 4.0, 0.85, 3000.0)
		reset_physics_interpolation()
		if is_instance_valid(_trail):
			_trail.global_position = global_position
			_trail.call(&"clear")
	_t += delta
	vel = _v0 - Vector3(0.0, G * _t, 0.0)
	if not _whiz and flight - _t < 1.5:
		_whiz = true
		Sfx.play_at(get_parent(), "whiz", to + Vector3(0.0, 25.0, 0.0), 2.0, 0.65, 700.0)
	if _t >= flight:
		if picture:
			var was_mp: bool = Effects.mute_blast
			Effects.mute_blast = true
			Effects.explosion(get_parent(), to + Vector3(0, 0.6, 0), 9.0, false, false)
			Effects.he_impact(get_parent(), to + Vector3(0, 0.4, 0), 2.6)
			Effects.mute_blast = was_mp
			Effects.dust(get_parent(), to, 3.0)
			# what is drawn coming down has to come down here too
			_batter()
			queue_free()
			return
		_batter()
		if is_instance_valid(shooter):
			# one man's 60 mm: the blast, credited to him, hurting whoever
			# is in it on the other side
			var was_c: Node = Effects.credit
			var was_s: int = Effects.spare_team
			var was_k: String = KillFeed.cause
			Effects.credit = shooter
			Effects.spare_team = int(shooter.get("side")) if "side" in shooter else -1
			KillFeed.cause = "mortar"
			Effects.explosion(get_parent(), to + Vector3(0, 0.6, 0), 9.0, false, false)
			Effects.he_impact(get_parent(), to + Vector3(0, 0.4, 0), 2.6)
			Effects.credit = was_c
			Effects.spare_team = was_s
			KillFeed.cause = was_k
			Effects.dust(get_parent(), to, 3.0)
		elif is_instance_valid(arena):
			arena.streaks.bomb(to, 0.8, false, "mortar")
			Effects.dust(get_parent(), to, 4.0)
		queue_free()
		return
	global_position = from + _v0 * _t + Vector3(0.0, -0.5 * G * _t * _t, 0.0)
	if is_instance_valid(_trail):
		_trail.global_position = global_position
	if vel.length_squared() > 1.0:
		look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)

## Seconds until it lands.
func eta() -> float:
	return maxf(delay, 0.0) + flight - _t

func in_air() -> bool:
	return _fired
