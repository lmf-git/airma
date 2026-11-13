class_name Soldier
extends Node3D
## An AI rifleman. The same body, the same rig and the same weapons as the
## player on foot -- he fires through `Firearm.fire`, his rounds are the same
## projectiles and a wall stops them the same way -- so what he can do to you is
## exactly what you can do to him.
##
## He is not in "hittable". That group is the radar picture and the lock list,
## and a man with a rifle has no business on either; rifle rounds and grenades
## look in "infantry" as well.

signal died(who, killer, head)

enum { ROAM, FIGHT, HUNT, COVER }

const RUN := 5.6
const JOG := 4.4
const WALK := 2.7
const BODY_R := 0.36
const SEE := 150.0

const UNIFORM := {
	0: [Color(0.27, 0.31, 0.22), Color(0.24, 0.27, 0.20), Color(0.15, 0.45, 1.0)],
	1: [Color(0.36, 0.30, 0.22), Color(0.17, 0.16, 0.15), Color(1.0, 0.16, 0.10)],
}

var team := 0
var health := 100.0
var alive := true
var arena: Node = null
var callsign := ""
var kit := "carbine"
## How good he is: quicker to react and tighter on the trigger above 1.
var skill := 1.0
var dmg_scale := 1.0

var body: Pilot
var gun: Dictionary = {}
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var crouching := false
var state := ROAM
var target: Node3D = null

var _path := PackedVector2Array()
var _path_i := 0
var _goal := Vector3.INF
var _repath := 0.0
var _hold := 0.0
var _seen_at := Vector3.ZERO
var _seen_t := 99.0
var _acquired := 0.0
var _think := 0.0
var _alert := 0.0
var _rounds := 0
var _cd := 0.0
var _burst := 0
var _pause := 0.0
var _reload := 0.0
var _reload_span := 1.0
var _strafe := 0.0
var _strafe_t := 0.0
var _stuck := 0.0
var _was := Vector3.ZERO
var _steps_seen := 0
var _hurt_recent := 0.0
var _last_head := false
var _kneel := false
var _last_amount := 0.0
var _last_low := false
## How pinned down he is, 0 to 1. Rounds going close past him put it up --
## a big round more than a small one, a near one more than a wide one -- and
## it drains away when they stop. A man under fire shoots worse and in
## shorter bursts, and past `PINNED` he stops what he was doing and gets
## behind something until it eases: which is what makes firing at somebody
## you cannot quite hit worth doing.
var _pinned := 0.0
var _pin_from := Vector3.ZERO
var _pin_try := 0.0
const PINNED := 0.6

func suppress(amount: float, from: Vector3) -> void:
	if not alive:
		return
	_pinned = minf(_pinned + amount / maxf(skill, 0.5), 1.0)
	_pin_from = from
	_alert = 8.0
	# he knows roughly where it is coming from, whether or not he saw it
	if target == null and _seen_t > 1.0:
		_seen_at = from
		_seen_t = 0.8

## Seconds left of not being able to see: a stun grenade went off in front of
## him. He loses whoever he was shooting at and cannot find anybody else.
var _blind := 0.0

func blind(secs: float) -> void:
	_blind = maxf(_blind, secs)
	target = null
	_acquired = 0.0
	_burst = 0
## Seconds since he last fired, near enough: a shot gives a man away.
var loud := 0.0
## What he carries on his back for the things a rifle does nothing to: "law"
## for armour, "stinger" for aircraft, or nothing.
var launcher := ""
var rounds_heavy := 3
var _heavy_cd := 4.0
var _heavy_aim := 0.0
var _heavy_at: Node3D = null
## The rig is posed every frame near the eye and less often further off: four
## limbs of two-bone IK and a weapon placed in the eye's frame is the most a
## man costs, and at a hundred and fifty metres nobody can see it run at a
## quarter of the frame rate. Staggered, so the squad does not all pose on the
## same frame.
var _anim_acc := 0.0
var _anim_n := 0

func _ready() -> void:
	var u: Array = UNIFORM.get(team, UNIFORM[1])
	body = Pilot.new()
	body.build(u[0], u[1], u[2])
	add_child(body)
	gun = Firearm.spec(kit)
	body.equip(gun)
	_rounds = int(gun["mag"])
	add_to_group("infantry")
	# moved at the frame rate, so there is nothing for the physics to smooth
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_think = randf() * 0.25
	_anim_n = randi() % 4
	_was = global_position
	rotation.y = yaw

func is_alive() -> bool:
	return alive

func hit_radius() -> float:
	return 0.9

func bullet_hit(from: Vector3, to: Vector3) -> Vector2:
	var r: Vector2 = Firearm.body_hit(global_position, crouching, from, to)
	if r.x > 0.0:
		_last_head = r.x > 1.5
		_last_low = r.x < 0.9
	return r

func eye() -> Vector3:
	return global_position + Vector3(0.0, 1.15 if crouching else 1.68, 0.0)

## Where to shoot a man: the middle of what is showing.
static func chest_of(n: Node3D) -> Vector3:
	if (n.get("prone") == true):
		return n.global_position + Vector3(0.0, 0.25, 0.0)
	var low: bool = (n.get("crouching") == true)
	return n.global_position + Vector3(0.0, 0.75 if low else 1.15, 0.0)

func take_hit(amount: float, from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	_last_amount = amount
	if amount >= 120.0:
		_last_head = false
	_hurt_recent = 2.5
	_alert = 8.0
	if from != null and is_instance_valid(from) and from is Node3D:
		# he knows roughly where it came from, whether or not he saw it
		if target == null:
			_seen_at = (from as Node3D).global_position
			_seen_t = minf(_seen_t, 0.5)
	if health <= 0.0:
		_die(from)

func _die(killer: Node) -> void:
	alive = false
	remove_from_group("infantry")
	var u: Array = UNIFORM.get(team, UNIFORM[1])
	var world := get_parent()
	Firearm.drop(world, kit, maxi(_rounds, int(float(gun["mag"]) * 0.5)),
		global_position + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5)))
	var from_dir := Vector3.ZERO
	if is_instance_valid(killer) and killer is Node3D:
		from_dir = (global_position - (killer as Node3D).global_position).normalized()
	Ragdoll.fall(world, global_transform, vel, u[0], u[1], _last_amount, _last_head, _last_low,
		from_dir)
	died.emit(self, killer if is_instance_valid(killer) else null, _last_head)
	queue_free()

## The side has a new plan. Drop whatever street he was wandering to and ask
## where his fire team is going now.
func new_orders() -> void:
	if state == ROAM:
		_goal = Vector3.INF
		_hold = 0.0

## Something loud happened over there.
func hear(at: Vector3) -> void:
	if not alive or target != null:
		return
	_alert = maxf(_alert, 6.0)
	if _seen_t > 1.5:
		_seen_at = at + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		_seen_t = 1.0

func _process(delta: float) -> void:
	if not alive or not is_instance_valid(arena):
		return
	delta = minf(delta, 0.1)
	_seen_t += delta
	_alert = maxf(_alert - delta, 0.0)
	_blind = maxf(_blind - delta, 0.0)
	_pinned = maxf(_pinned - delta * 0.22, 0.0)
	_pin_try = maxf(_pin_try - delta, 0.0)
	_hurt_recent = maxf(_hurt_recent - delta, 0.0)
	loud = maxf(loud - delta, 0.0)
	_think -= delta
	if _think <= 0.0:
		_think = 0.16 + randf() * 0.08
		var _ps := Sim.prof_at()
		_sense()
		_decide()
		Sim.prof_end(&"ai.sense", _ps)
	_acquired = _acquired + delta if is_instance_valid(target) else 0.0
	var before := global_position
	var _ph := Sim.prof_at()
	var shouldered: bool = _heavy(delta)
	Sim.prof_end(&"ai.heavy", _ph)
	if shouldered:
		# the tube is on his shoulder: he stands, turns to it and lets go
		vel = Vector3.ZERO
		_pose(delta, Vector3.ZERO)
		return
	var _pm := Sim.prof_at()
	_move(delta)
	Sim.prof_end(&"ai.move", _pm)
	var _pf := Sim.prof_at()
	_shoot(delta)
	Sim.prof_end(&"ai.shoot", _pf)
	var _pp := Sim.prof_at()
	_pose(delta, (global_position - before) / maxf(delta, 0.001))
	Sim.prof_end(&"ai.pose", _pp)

# ---------------------------------------------------------------- heavy weapons
## Armour and aircraft. A rifleman can do nothing about either and does not
## try; the man with the tube looks for them every time he looks round, and
## when one is in reach and in sight it comes before anything else.
func _heavy(delta: float) -> bool:
	if launcher == "" or rounds_heavy <= 0:
		return false
	_heavy_cd -= delta
	if _heavy_aim > 0.0:
		if not is_instance_valid(_heavy_at) or not _heavy_at.is_alive():
			_heavy_aim = 0.0
			body.equip(gun)
			return false
		var to: Vector3 = _heavy_at.global_position - global_position
		yaw = rotate_toward(yaw, atan2(-to.x, -to.z), delta * 6.0)
		rotation.y = yaw
		var aim0: Vector3 = _heavy_at.global_position + Vector3(0, 1.4, 0) - eye()
		pitch = lerpf(pitch, atan2(aim0.y, Vector2(aim0.x, aim0.z).length()), clampf(delta * 8.0, 0.0, 1.0))
		state = FIGHT
		crouching = launcher == "law"
		_heavy_aim -= delta
		if _heavy_aim <= 0.0:
			var world := get_tree().current_scene
			var from: Vector3 = eye() + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.5
			var dir: Vector3 = (_heavy_at.global_position + Vector3(0, 1.2, 0) - from).normalized()
			if launcher == "law":
				# lead it, and miss by a little: it is a tube, not a gun sight
				var d: float = from.distance_to(_heavy_at.global_position)
				var lead := Vector3.ZERO
				if "linear_velocity" in _heavy_at:
					lead = (_heavy_at.linear_velocity as Vector3) * (d / 150.0)
				dir = (_heavy_at.global_position + lead + Vector3(0, 1.2 + d * 0.012, 0) - from).normalized()
				var b := Basis.looking_at(dir, Vector3.UP)
				dir = (b * Vector3(randfn(0.0, 0.016 / skill), randfn(0.0, 0.012 / skill), -1.0)).normalized()
				Firearm.rocket(world, self, team, Firearm.spec("law"), from, dir)
			else:
				Firearm.sam(world, self, team, from, dir, _heavy_at)
			rounds_heavy -= 1
			_heavy_cd = 9.0 if launcher == "law" else 16.0
			loud = 2.5
			arena.heard(from, team)
			body.equip(gun)
		return true
	if _heavy_cd > 0.0:
		return false
	_heavy_cd = 0.7
	var best: Node3D = null
	var best_d := 1e9
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not n.has_method("is_alive") or not n.is_alive():
			continue
		if not ("team" in n) or n.team == team:
			continue
		var d2: float = eye().distance_to((n as Node3D).global_position)
		if launcher == "law":
			if not (n is Tank) or d2 > 170.0 or d2 < 9.0:
				continue
			if not Firearm.can_see(eye(), (n as Node3D).global_position + Vector3(0, 1.6, 0)):
				continue
		else:
			# A drone is fair game even where the aeroplanes are left alone:
			# it is the other side's eyes, and it is why he carries the tube.
			var drone: bool = n.is_in_group("drones")
			if not (n is Aircraft or drone) or (Sim.no_air_threat and not drone) \
					or d2 > 4000.0 or d2 < 150.0:
				continue
			var up: float = (n as Node3D).global_position.y - Sim.height_at(
				(n as Node3D).global_position.x, (n as Node3D).global_position.z)
			if up < 25.0 or not Firearm.can_see(eye(), (n as Node3D).global_position) \
					or not Sim.line_of_sight(eye(), (n as Node3D).global_position):
				continue
		if d2 < best_d:
			best_d = d2
			best = n
	if best == null:
		return false
	_heavy_at = best
	_heavy_aim = 1.1 / skill
	body.equip(Firearm.spec(launcher))
	return true

# --------------------------------------------------------------------- senses
func _sense() -> void:
	if _blind > 0.0:
		target = null
		return
	var from := eye()
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var best: Node3D = null
	var best_d := SEE
	for n in arena.enemies_of(team):
		if not is_instance_valid(n) or not n.is_alive():
			continue
		var at: Vector3 = chest_of(n)
		var d: float = from.distance_to(at)
		if d > SEE:
			continue
		# Eyes in the front of his head, unless something has his attention:
		# a man who has just been shot at looks round.
		var ahead: float = facing.dot((at - from).normalized())
		if _alert <= 0.0 and ahead < -0.15 and d > 7.0:
			continue
		if not Firearm.can_see(from, at) and ((n.get("prone") == true)
				or not Firearm.can_see(from, n.global_position + Vector3(0, 1.6, 0))):
			continue
		# stay on the one he is already shooting at unless another is much nearer
		var score: float = d * (0.75 if n == target else 1.0)
		if score < best_d:
			best_d = score
			best = n
	if best != target:
		_acquired = 0.0
	target = best
	if best != null:
		_seen_at = best.global_position
		_seen_t = 0.0
		_alert = 8.0
		arena.contact(team, _seen_at)

func _decide() -> void:
	if state == COVER:
		# stay put until the weapon is ready and the worst has passed
		if _at_goal(1.4):
			_kneel = true
			# and not while the rounds are still coming in
			if _reload <= 0.0 and _hold <= 0.0 and _pinned < PINNED * 0.6:
				_kneel = false
				state = HUNT
				_goal = Vector3.INF
		return
	# Pinned: behind something if there is something, and down where he is
	# if there is not.
	if _pinned > PINNED:
		_kneel = true
		if _pin_try <= 0.0:
			_pin_try = 1.5
			var threat: Vector3 = Soldier.chest_of(target) + Vector3(0, 0.4, 0) \
				if is_instance_valid(target) else _pin_from
			var behind: Vector3 = arena.find_cover(global_position, threat)
			if behind != Vector3.INF:
				state = COVER
				_set_goal(behind)
				_hold = randf_range(1.5, 3.0)
				return
	if is_instance_valid(target):
		var d: float = global_position.distance_to(target.global_position)
		var hurt: bool = health < 45.0 and _hurt_recent > 0.0
		var dry: bool = _rounds <= 0 and d < 60.0
		if hurt or dry:
			var spot: Vector3 = arena.find_cover(global_position, Soldier.chest_of(target) + Vector3(0, 0.4, 0))
			if spot != Vector3.INF:
				state = COVER
				_set_goal(spot)
				_hold = randf_range(1.2, 2.6)
				return
		state = FIGHT
		return
	_kneel = false
	if _seen_t < 7.0:
		state = HUNT
		if _goal == Vector3.INF or _goal.distance_to(_seen_at) > 4.0:
			_set_goal(_seen_at)
		return
	state = ROAM
	if _goal == Vector3.INF or (_at_goal(3.0) and _hold <= 0.0):
		_set_goal(arena.objective_for(self))
		_hold = randf_range(2.0, 6.0)

func _at_goal(within: float) -> bool:
	return _goal != Vector3.INF \
		and Vector2(global_position.x - _goal.x, global_position.z - _goal.z).length() < within

func _set_goal(at: Vector3) -> void:
	_goal = at
	var _pp := Sim.prof_at()
	_path = arena.path(global_position, at)
	Sim.prof_end(&"ai.path", _pp)
	_path_i = 0
	_repath = randf_range(2.0, 3.2)

# ------------------------------------------------------------------- movement
func _move(delta: float) -> void:
	_hold = maxf(_hold - delta, 0.0) if (_at_goal(3.0) or state == COVER) else _hold
	_repath -= delta
	var wish := Vector3.ZERO
	var speed := JOG
	var face := yaw
	var fighting: bool = state == FIGHT and is_instance_valid(target)
	if fighting:
		var to: Vector3 = target.global_position - global_position
		var d: float = Vector2(to.x, to.z).length()
		face = atan2(-to.x, -to.z)
		var reach: float = float(gun["reach"])
		speed = WALK
		if d > reach * 1.15:
			# close the distance, along the streets rather than at the wall
			if _repath <= 0.0 or _goal == Vector3.INF:
				_set_goal(target.global_position)
			wish = _along_path()
			speed = JOG
			_kneel = false
		else:
			# Inside his weapon's reach he works the angle: a few steps one
			# way, a pause to shoot, a few steps back.
			_strafe_t -= delta
			if _strafe_t <= 0.0:
				_strafe_t = randf_range(0.6, 1.5)
				var roll := randf()
				_strafe = 0.0 if roll < 0.45 else (1.0 if roll < 0.72 else -1.0)
				_kneel = _strafe == 0.0 and d > 14.0 and randf() < 0.55
			var side := Vector3(-to.z, 0.0, to.x).normalized()
			wish = side * _strafe
			if d < 5.0:
				wish -= Vector3(to.x, 0.0, to.z).normalized() * 0.8
	else:
		if _goal != Vector3.INF and not _at_goal(1.0):
			# The same route to the same place, asked for again every couple of
			# seconds by every man who was walking anywhere: the town has not
			# moved, and from a point on the route the answer is the route. It
			# is only worth asking again when he is no longer on it -- pushed
			# off by the man beside him, or stepped round a corner -- and being
			# properly stuck has its own check below.
			if _repath <= 0.0 and state != COVER:
				_repath = randf_range(2.0, 3.2)
				if _off_route():
					_set_goal(_goal)
			wish = _along_path()
		speed = RUN if state == COVER else (WALK + 0.8 if (state == HUNT and _at_goal(14.0)) else JOG)
		if wish.length() > 0.1:
			face = atan2(-wish.x, -wish.z)
		elif state == HUNT:
			var look: Vector3 = _seen_at - global_position
			face = atan2(-look.x, -look.z)
	crouching = _kneel and wish.length() < 0.1
	if crouching:
		speed = 1.8

	# keep off each other: two men in one doorway is one target
	for o in arena.friends_of(team):
		if o == self or not is_instance_valid(o):
			continue
		var gap: Vector3 = global_position - (o as Node3D).global_position
		gap.y = 0.0
		var gl: float = gap.length()
		if gl < 1.3 and gl > 0.01:
			wish += gap / gl * (1.3 - gl) * 1.6
	if wish.length() > 1.0:
		wish = wish.normalized()

	var flat := Vector3(vel.x, 0.0, vel.z).lerp(wish * speed, clampf(delta * 9.0, 0.0, 1.0))
	vel = flat
	var was := global_position
	var p: Vector3 = was + flat * delta
	p.y = Sim.height_at(p.x, p.z)
	if Obstacles.blocks(p, BODY_R) >= 0:
		var try_x := Vector3(p.x, p.y, was.z)
		var try_z := Vector3(was.x, p.y, p.z)
		if Obstacles.blocks(try_x, BODY_R) < 0:
			p = try_x
		elif Obstacles.blocks(try_z, BODY_R) < 0:
			p = try_z
		else:
			p = Vector3(was.x, p.y, was.z)
	global_position = p

	# Wanting to move and not moving is being stuck on a corner. Ask for the
	# route again from where he actually is, and step sideways off whatever
	# has him while it comes back.
	if wish.length() > 0.5:
		_stuck += delta
		if _stuck > 0.8:
			if _was.distance_to(p) < 0.35:
				if _goal != Vector3.INF:
					_set_goal(_goal)
				_strafe = -_strafe if _strafe != 0.0 else 1.0
				_strafe_t = 0.6
			_stuck = 0.0
			_was = p
	else:
		_stuck = 0.0
		_was = p

	yaw = rotate_toward(yaw, face, delta * (7.5 if fighting else 5.5))
	rotation.y = yaw
	var want_pitch := 0.0
	if fighting:
		var aim: Vector3 = Soldier.chest_of(target) - eye()
		want_pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	pitch = lerpf(pitch, clampf(want_pitch, -1.2, 1.2), clampf(delta * 8.0, 0.0, 1.0))

## Has he strayed from the route he was given? True with no route at all.
func _off_route() -> bool:
	if _path_i >= _path.size():
		return true
	var wp: Vector2 = _path[_path_i]
	return Vector2(wp.x - global_position.x, wp.y - global_position.z).length() > 5.0

## The next stretch of the route, as a direction to walk in.
func _along_path() -> Vector3:
	while _path_i < _path.size():
		var wp: Vector2 = _path[_path_i]
		var to := Vector3(wp.x - global_position.x, 0.0, wp.y - global_position.z)
		if to.length() < 1.1 and _path_i < _path.size() - 1:
			_path_i += 1
			continue
		if to.length() < 0.3:
			return Vector3.ZERO
		return to.normalized()
	return Vector3.ZERO

# -------------------------------------------------------------------- shooting
func _shoot(delta: float) -> void:
	_cd = maxf(_cd - delta, 0.0)
	_pause = maxf(_pause - delta, 0.0)
	var world := get_tree().current_scene
	if _reload > 0.0:
		_reload -= delta
		if _reload <= 0.0:
			_rounds = int(gun["mag"])
			_near_sound("mag_in", -10.0)
		return
	if _rounds <= 0:
		_reload_span = float(gun["reload"]) * (3.2 if gun.get("shells", false) else 1.0)
		_reload = _reload_span
		_near_sound("mag_out", -11.0)
		return
	if state != FIGHT or not is_instance_valid(target) or not target.is_alive():
		_burst = 0
		return
	# It takes a moment to register a man and put the sights on him.
	var react: float = (0.28 if _alert > 0.0 else 0.55) / skill
	if _acquired < react:
		return
	var from: Vector3 = body.muzzle_pos()
	var mark: Vector3 = Soldier.chest_of(target)
	var d: float = from.distance_to(mark)
	if "vel" in target:
		mark += (target.vel as Vector3) * (d / float(gun["muzzle"]))
	var aim: Vector3 = (mark - from).normalized()
	var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if facing.dot(Vector3(aim.x, 0.0, aim.z).normalized()) < 0.96:
		return
	if _burst <= 0:
		if _pause > 0.0:
			return
		var is_auto: bool = gun["auto"]
		_burst = randi_range(3, 6) if is_auto else (1 if gun.get("shells", false) else randi_range(1, 2))
		if d > 45.0 and is_auto:
			_burst = randi_range(2, 3)
	if _cd > 0.0:
		return
	# his own cover, right in front of the muzzle
	if Obstacles.segment(from, from + aim * 2.2) < 1.0:
		_strafe = 1.0 if randf() < 0.5 else -1.0
		_strafe_t = 0.5
		_kneel = false
		_cd = 0.2
		return
	# How far off he is. Worse at range, worse on the move, worse at a target
	# that is moving, and much worse in the first moment after seeing it --
	# which is the moment you have to get behind something.
	var err: float = 0.0095 / skill
	err *= 1.0 + d / 80.0
	if vel.length() > 1.0:
		err *= 1.6
	if "vel" in target and (target.vel as Vector3).length() > 3.0:
		err *= 1.4
	if crouching:
		err *= 0.75
	# with rounds going past his head he is not taking aim, he is pointing
	err *= 1.0 + 2.2 * _pinned
	err *= 1.0 + 1.3 * exp(-(_acquired - react) * 1.5)
	var b := Basis.looking_at(aim, Vector3.UP)
	aim = (b * Vector3(randfn(0.0, err), randfn(0.0, err), -1.0)).normalized()
	# `dmg_scale` is the allowance made for the player, who is one man being
	# shot at by six. Between the two squads a round is a round.
	Firearm.fire(world, self, team, gun, from, aim, float(gun["ads"]) + 0.002,
		dmg_scale if target is Walker else 1.0)
	arena.heard(from, team)
	loud = 1.6
	body.kick(clampf(float(gun["kick"]) * 34.0, 0.3, 1.5))
	_rounds -= 1
	_burst -= 1
	_cd = float(gun["cd"]) if gun["auto"] else maxf(float(gun["cd"]), 0.26) + randf() * 0.25
	if _burst <= 0:
		_pause = randf_range(0.35, 0.95) / skill * (1.0 + 2.0 * _pinned)

func _near_sound(id: String, db: float) -> void:
	var ear := get_viewport().get_camera_3d()
	if ear != null and ear.global_position.distance_to(global_position) < 35.0:
		Sfx.play_at(get_tree().current_scene, id, global_position + Vector3(0, 1.3, 0),
			db, randf_range(0.95, 1.05), 40.0)

# ---------------------------------------------------------------------- figure
func _pose(delta: float, moved: Vector3) -> void:
	var ear := get_viewport().get_camera_3d()
	var far: float = 0.0 if ear == null else ear.global_position.distance_to(global_position)
	# as far as he looks, not as far as he is: through a scope a man at three
	# hundred metres fills as much of the screen as one at forty
	var looks: float = far
	if ear != null and ear.fov < 60.0:
		looks *= ear.fov / 60.0
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	body.in_move = Vector2(moved.dot(right), moved.dot(fwd))
	body.in_crouch = crouching
	body.in_air = 0
	body.in_pitch = pitch
	var busy: bool = state == FIGHT or state == COVER or (state == HUNT and _at_goal(14.0))
	body.in_ready = 1.0 if busy or _alert > 0.0 and moved.length() < 4.9 else 0.0
	body.in_ads = 1.0 if state == FIGHT else 0.0
	body.in_reload = (1.0 - clampf(_reload / _reload_span, 0.0, 1.0)) if _reload > 0.0 else -1.0
	body.in_foot_ik = far < 45.0
	_anim_acc += delta
	_anim_n += 1
	var every: int = 1 if looks < 60.0 else (2 if looks < 130.0 else 4)
	if _anim_n >= every:
		_anim_n = 0
		body.animate(_anim_acc)
		_anim_acc = 0.0
	if body.steps != _steps_seen:
		_steps_seen = body.steps
		if far < 32.0 and moved.length() > 1.0:
			Sfx.play_at(get_tree().current_scene, ["step_a", "step_b", "step_c"][randi() % 3],
				global_position, -13.0 if moved.length() > 4.0 else -19.0,
				randf_range(0.88, 1.1), 40.0)
