class_name WalkerClimb
extends RefCounted
## Getting over and onto things: vaulting a low wall, climbing what is taller, taking hold of a wall or a ladder and climbing it. Split out of `walker.gd`; every walker has one as `climb`.

var w: Walker

var _trav_span := 0.5
## On a ladder rather than a bare wall: no going sideways, and quicker.
var _ladder := false



## The way over has a top to it -- a window -- so it is taken crouched.
var _trav_low := false

var _trav_t := 0.0

var _trav_a := Vector3.ZERO

var _trav_b := Vector3.ZERO

var _trav_top := 0.0

var _trav_grip := Vector3.ZERO

var _wall_n := Vector3.ZERO

var _wall_speed := 0.0

var _third_was := false

func _init(owner_node: Walker) -> void:
	w = owner_node

## Is there something in the way that he can get over or onto? `auto` is the
## version that happens without being asked -- running flat out into a low
## wall -- and only ever vaults: nobody climbs a container by accident.
func _begin_traverse(dir_in: Vector3, auto: bool) -> bool:
	var dir := Vector3(dir_in.x, 0.0, dir_in.z).normalized()
	var feet := w.global_position
	var id := -1
	var face := 0.0
	# What is actually there at the height asked about. These asked `blocks`,
	# which counts anything up to a man's height above the point -- so at a
	# window the thing found at his shins was as often the wall over the
	# window as the sill under it, and a sill to vault became a wall to climb.
	# Through a window was never the answer it gave.
	for step in 5:
		face = 0.3 + step * 0.2
		id = Obstacles.hit(feet + dir * face + Vector3(0, 0.25, 0), 0.05)
		if id >= 0:
			break
	if id < 0 and not auto:
		# nothing at his shins: perhaps something to catch hold of overhead
		face = 0.6
		id = Obstacles.hit(feet + dir * face + Vector3(0, 2.0, 0), 0.05)
		# a hand's reach higher: the edge of a scaffold deck, a balcony
		if id < 0:
			id = Obstacles.hit(feet + dir * face + Vector3(0, 2.35, 0), 0.1)
	if id < 0:
		return false
	var top: float = Obstacles.top_of(id)
	var rise: float = top - feet.y
	if rise < 0.45 or (auto and rise > Walker.VAULT_MAX):
		return false
	if rise > Walker.CLIMB_MAX:
		# too tall to haul up onto in one go, so it is a climb in the other
		# sense: onto the face of it, and up
		return _take_wall(id, feet + dir * face)
	var world := w.get_tree().current_scene
	_trav_top = top
	_trav_a = feet
	_trav_grip = feet + dir * face + Vector3(0, rise, 0)
	if rise <= Walker.VAULT_MAX:
		# Over it, if it is thin enough to get over: look for clear ground on
		# the far side within a stride and a half.
		for step in 9:
			var reach: float = face + 0.7 + step * 0.25
			var land: Vector3 = feet + dir * reach
			land.y = Sim.height_at(land.x, land.z)
			if land.y > feet.y + 0.5 or land.y < feet.y - 2.5:
				continue
			if Obstacles.blocks(land, Walker.BODY_R) < 0 \
					and Obstacles.floor_under(land.x, land.z, land.y + 1.0) < land.y + 0.3:
				# whatever is tallest along the way is what has to be cleared,
				# and if that is more than a vault this is not one
				var crest: float = top
				for k in 5:
					var q: Vector3 = feet.lerp(land, (k + 1) / 6.0)
					crest = maxf(crest, Obstacles.clear_over(q.x, q.z, feet.y + Walker.VAULT_MAX + 0.2))
				if crest - feet.y > Walker.VAULT_MAX:
					break
				# Through an opening rather than over a wall: something over
				# the top of the way across, a window's lintel. He goes
				# through low, head down, not stood up into the wall above.
				_trav_low = Obstacles.hit(Vector3(_trav_grip.x, crest + 1.15, _trav_grip.z), 0.15) >= 0
				_trav_top = crest
				w._trav = "vault"
				_trav_b = land
				_trav_span = 0.42 + reach * 0.09
				_trav_t = 0.0
				w.vel = dir * (reach / _trav_span)
				Sfx.play_at(world, "cloth", feet, -9.0, 0.8, 40.0)
				return true
	if auto:
		return false
	# Onto it. There has to be somewhere to stand once he is up.
	# Whatever is a pace in from the edge is what he ends up standing on, and
	# that is not always the thing his shins found: a car's bonnet is the way
	# onto its roof.
	var up: Vector3 = feet + dir * (face + 0.55)
	up.y = Obstacles.floor_under(up.x, up.z, feet.y + Walker.CLIMB_MAX)
	rise = up.y - feet.y
	if rise < 0.45 or rise > Walker.CLIMB_MAX or Obstacles.blocks(up, Walker.BODY_R * 0.6) >= 0:
		return false
	_trav_top = up.y
	_trav_grip = feet + dir * face + Vector3(0, rise, 0)
	w._trav = "climb"
	_trav_b = up
	_trav_span = 0.55 + rise * 0.36
	_trav_t = 0.0
	w.vel = Vector3.ZERO
	Sfx.play_at(world, "cloth", feet, -8.0, 0.7, 40.0)
	return true

## Carry him along the move. A vault is one arc over the top; a climb is up
## the face and then forward onto the edge.
func _traverse(delta: float) -> void:
	_trav_t += delta / _trav_span
	var t: float = clampf(_trav_t, 0.0, 1.0)
	var p: Vector3
	if w._trav == "vault":
		var s: float = t * t * (3.0 - 2.0 * t)
		p = _trav_a.lerp(_trav_b, s)
		# straight line between the two ends, lifted to clear the top
		var base_y: float = lerpf(_trav_a.y, _trav_b.y, s)
		p.y = base_y + maxf(_trav_top + 0.12 - base_y, 0.0) * sin(t * PI)
	else:
		var lift: float = smoothstep(0.0, 0.68, t)
		var over: float = smoothstep(0.55, 1.0, t)
		var face: Vector3 = _trav_a.lerp(Vector3(_trav_b.x, _trav_a.y, _trav_b.z), 0.25)
		p = Vector3(lerpf(face.x, _trav_b.x, over), lerpf(_trav_a.y, _trav_b.y, lift),
			lerpf(face.z, _trav_b.z, over))
	w.global_position = p
	w.rotation.y = w.yaw
	w.on_floor = false
	w.crouching = _trav_low
	w._slide = 0.0
	w._sprint = false
	w._shot_cd = maxf(w._shot_cd, 0.15)
	w._fight_idle(delta)
	w.body.in_action = w._trav
	w.body.in_action_t = t
	w.body.in_point = _trav_grip
	w._animate(delta, w.vel, false)
	w._view(delta, Basis.IDENTITY)
	if t >= 1.0:
		var done := w._trav
		w._trav = ""
		w.body.in_action = ""
		w.on_floor = true
		w._fall_peak = 0.0
		w.vel = Vector3(w.vel.x, 0.0, w.vel.z) * (0.6 if done == "vault" else 0.0)
		Sfx.play_at(w.get_tree().current_scene, "land", w.global_position, -13.0,
			randf_range(0.95, 1.1), 40.0)
		if done == "climb":
			w._shot_cd = 0.3
			w.body._draw = 0.8         # the weapon comes back off the sling

# ------------------------------------------------------------------ on a wall
## Take hold of a face. Anything built can be climbed: a building, a crane's
## mast, a container stack. He goes where the keys say -- up, down, along --
## for as long as he stays on that face, and comes off it over the top, onto
## the ground, or by letting go.
func _take_wall(id: int, at: Vector3) -> bool:
	var f: Dictionary = Obstacles.face_of(id, at)
	var n: Vector3 = f["n"]
	var foot: Vector3 = f["foot"]
	# onto the plane of the face, a shoulder's width out from it
	var rel: Vector3 = w.global_position - foot
	var p: Vector3 = w.global_position - n * (rel.dot(n) - (Walker.BODY_R + 0.06))
	p.y = w.global_position.y
	w._wall = id
	_wall_n = n
	_ladder = false
	_third_was = w.third
	w.third = true                    # you climb by looking at the wall, not out of it
	w.global_position = p
	w.vel = Vector3.ZERO
	w.on_floor = false
	w.stance = 0
	w._slide = 0.0
	w._sprint = false
	w.reloading = 0.0
	Sfx.play_at(w.get_tree().current_scene, "cloth", p, -8.0, 0.8, 40.0)
	return true

## Step onto a ladder: [where its foot is, which way it faces, structure].
func _take_ladder(l: Array) -> void:
	var foot: Vector3 = l[0]
	var n: Vector3 = l[1]
	var keep_y: float = w.global_position.y
	w.global_position = Vector3(foot.x, keep_y, foot.z) + n * 0.3
	if _take_wall(int(l[2]), foot - n * 0.2):
		_ladder = true
		# square on to it, whatever part of the face that is
		w.global_position = Vector3(foot.x, keep_y, foot.z) + n * (Walker.BODY_R + 0.06)

func _leave_wall() -> void:
	w.body.position = Vector3.ZERO
	_ladder = false
	w._wall = -1
	w.third = _third_was
	w.body.in_action = ""
	w.body._draw = 0.8
	w._shot_cd = 0.35
	w._fall_peak = 0.0

func _on_wall(delta: float) -> void:
	var n := _wall_n
	var right := Vector3(n.z, 0.0, -n.x)            # his right, facing the wall
	var up_in: float = Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up") + w.test_climb
	var side_in: float = Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	var fast: bool = Sim.held(&"throttle_up") and w.stamina > 0.05
	w.stamina = clampf(w.stamina + delta * (-1.0 / 9.0 if fast else 1.0 / 12.0), 0.0, 1.0)
	var rate: float = 3.3 if fast else 2.2
	if _ladder:
		side_in = 0.0
		rate *= 1.3
	var p := w.global_position
	var f: Dictionary = Obstacles.face_of(w._wall, p - n * (Walker.BODY_R + 0.06))
	var top: float = f["top"]
	var step: Vector3 = Vector3.UP * up_in * rate * delta + right * side_in * rate * 0.8 * delta
	# stay on the face: at its edge there is no more wall to hold
	var along: float = float(f["along"])
	var half: float = float(f["half"]) - 0.25
	var q: Vector3 = p + step
	var f2: Dictionary = Obstacles.face_of(w._wall, q - n * (Walker.BODY_R + 0.06))
	if absf(float(f2["along"])) > half and absf(float(f2["along"])) > absf(along):
		q = p + Vector3.UP * up_in * rate * delta
	# something else built against this wall is in the way
	var other: int = Obstacles.blocks(q + Vector3(0, 0.9, 0), 0.2)
	if other >= 0 and other != w._wall:
		q = p
		# Unless it is something overhead he can get onto: a crane's jib
		# across the top of its mast, a deck. Then that is the top.
		var lip: float = Obstacles.top_of(other)
		if up_in > 0.1 and lip > p.y and lip - p.y < 4.3:
			_trav_a = p
			_trav_b = Vector3(p.x, lip, p.z) - n * 0.25
			_trav_top = lip
			_trav_grip = Vector3(p.x, lip, p.z) - n * 0.3
			w._trav = "climb"
			_trav_span = 1.3
			_trav_t = 0.0
			_leave_wall()
			w.body.in_action = "climb"
			return
	_wall_speed = (q - p).length() / maxf(delta, 0.001)
	w.global_position = q
	w.rotation.y = atan2(n.x, n.z)                     # chest to the wall
	# in close: the figure's arms are not long enough to climb at arm's length
	w.body.position = Vector3(0.0, 0.0, -0.17)
	w.crouching = false
	w.prone = false
	w._fight_idle(delta)
	var world := w.get_tree().current_scene
	# over the top
	if q.y + 1.5 >= top and up_in > 0.1:
		var roof: Vector3 = q - n * (Walker.BODY_R + 0.7)
		roof.y = top
		_trav_a = q
		_trav_b = roof
		_trav_top = top
		_trav_grip = Vector3(q.x, top, q.z) - n * (Walker.BODY_R + 0.06)
		w._trav = "climb"
		_trav_span = 0.75
		_trav_t = 0.0
		_leave_wall()
		w.body.in_action = "climb"
		return
	# back on the ground
	var floor_y: float = maxf(Sim.height_at(q.x, q.z), Obstacles.floor_under(q.x, q.z, q.y + 0.2))
	if q.y <= floor_y + 0.02 and up_in < 0.0:
		w.global_position.y = floor_y
		w.on_floor = true
		w.vel = Vector3.ZERO
		_leave_wall()
		return
	if Sim.tapped(&"jump"):
		# kicked off backwards
		w.vel = n * 4.6 + Vector3.UP * 4.2
		_leave_wall()
		Sfx.play_at(world, "cloth", q, -8.0, 1.0, 40.0)
		return
	if Sim.tapped(&"crouch"):
		w.vel = n * 0.6
		_leave_wall()
		return
	if _wall_speed > 0.4 and fmod(Time.get_ticks_msec() * 0.001, 0.42) < delta:
		Sfx.play_at(world, "step_a", q + Vector3(0, 1.6, 0) - n * 0.4, -17.0,
			randf_range(1.2, 1.5), 30.0)
	w.body.in_action = "ladder" if _ladder else "wall"
	w.body.in_action_t = 0.0
	w.body.in_point = q + Vector3(0, 1.70, 0) - n * (Walker.BODY_R + 0.04)
	w.body.in_move = Vector2(0.0, _wall_speed * (signf(up_in) if absf(up_in) > 0.05
		else (1.0 if absf(side_in) > 0.05 else 0.0)))
	w.body.in_crouch = false
	w.body.in_prone = false
	w.body.in_air = 0
	w.body.in_ready = 0.0
	w.body.in_ads = 0.0
	w.body.in_lean = 0.0
	w.body.in_reload = -1.0
	w.body.in_foot_ik = false
	w._ads = 0.0
	w.ads_latched = false
	w.binos = false
	w._bino = 0.0
	w.body.animate(delta)
	w._view(delta, Basis.IDENTITY)
