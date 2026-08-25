class_name PlayerHeli
extends Helicopter
## The player's helicopter. Shares every control binding with the fixed wing
## pilot; the difference is what the airframe does with them.

var mouse_fly := false
var stick := Vector2.ZERO
var msg := ""
var msg_t := 0.0
var kills := 0
var active := true
var auto := ""
var hold_alt := 0.0        # height the stability system is holding
var _coll_trim := 0.5      # slowly learned hover power
var pod: Node = null
var _mouse := Vector2.ZERO

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("player")
	throttle = 0.0

func hit_radius() -> float:
	return 6.0

func _unhandled_input(e: InputEvent) -> void:
	if not alive:
		return
	if e is InputEventMouseMotion and mouse_fly:
		var vp := get_viewport().get_visible_rect().size
		_mouse += (e as InputEventMouseMotion).relative / (vp.y * 0.42)
		_mouse.x = clampf(_mouse.x, -1.0, 1.0)
		_mouse.y = clampf(_mouse.y, -1.0, 1.0)

func _pilot(delta: float) -> void:
	msg_t = maxf(msg_t - delta, 0.0)
	if auto != "":
		_auto_pilot(delta)
		return
	if not active:
		throttle = 0.0
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		wheel_brake = true
		return
	if Input.is_action_just_pressed(&"mouse_fly"):
		mouse_fly = not mouse_fly
		_mouse = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_fly else Input.MOUSE_MODE_VISIBLE
	var kp := Input.get_action_strength(&"pitch_up") - Input.get_action_strength(&"pitch_down")
	var kr := Input.get_action_strength(&"roll_right") - Input.get_action_strength(&"roll_left")
	var target_stick := Vector2(kr, kp)
	if mouse_fly:
		target_stick = Vector2(clampf(_mouse.x + kr, -1, 1), clampf(-_mouse.y + kp, -1, 1))
		_mouse = _mouse.lerp(Vector2.ZERO, delta * 0.9)
	stick = stick.lerp(target_stick, clampf(delta * 8.0, 0.0, 1.0))
	in_roll = stick.x
	in_pitch = stick.y
	in_yaw = Input.get_action_strength(&"yaw_right") - Input.get_action_strength(&"yaw_left")
	# Collective. With the stability system in, the lever commands a rate of
	# climb and centring it holds the height you have -- a helicopter that
	# wanders up and down whenever you take your hand off it is not flyable.
	# Switch the assist off and it goes back to being raw engine power.
	var t := Input.get_action_strength(&"throttle_up") - Input.get_action_strength(&"throttle_down")
	if assist and not on_ground:
		if absf(t) > 0.01:
			hold_alt = global_position.y          # follow the lever, then hold there
			_collective(t * 6.0, delta)
		else:
			_collective(clampf((hold_alt - global_position.y) * 1.10, -6.0, 6.0), delta)
	else:
		hold_alt = global_position.y
		_coll_trim = throttle
		throttle = clampf(throttle + t * delta * 0.7, 0.0, 1.0)
	wheel_brake = Input.is_action_pressed(&"brakes") and on_ground

	if Input.is_action_just_pressed(&"gear"):
		toggle_gear()
	if Input.is_action_just_pressed(&"cycle_weapon"):
		cycle_weapon()
	for i in 8:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))) and i < weapon_types.size():
			set_weapon(i)
	if Input.is_action_just_pressed(&"cycle_target") \
			and not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		cycle_target()
	if Input.is_action_just_pressed(&"flare"):
		drop_flare()
	if Input.is_action_pressed(&"gun") and current_weapon() == "gun" and not Sim.ui_modal:
		fire_gun(get_tree().current_scene)
	if Input.is_action_just_pressed(&"fire") and not Sim.ui_modal:
		if current_weapon() == "gun":
			fire_gun(get_tree().current_scene)
		else:
			var r := fire()
			if r != "":
				say(r)

## Drive the collective toward a commanded vertical speed. The throttle is
## itself an integrator and the rotor has spool lag on top, so integrating the
## error into it as well gives three lags in series and the machine porpoises
## between full up and full down. A slow integral finds the power that holds a
## hover and a fast proportional term damps what is left.
func _collective(want_vs: float, delta: float) -> void:
	var err := want_vs - linear_velocity.y
	_coll_trim = clampf(_coll_trim + err * delta * 0.045, 0.0, 1.0)
	throttle = clampf(_coll_trim + err * 0.055, 0.0, 1.0)

func cycle_target() -> void:
	var cand: Array = []
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self:
			continue
		if "team" in n and n.team == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		cand.append(n)
	if cand.is_empty():
		target = null
		say("no targets")
		return
	var fwd := -global_transform.basis.z
	# Rank on angle *and* range. Sorting on boresight angle alone locks the
	# radar onto whatever happens to be dead ahead, so a contact ninety
	# kilometres away and opening beat one two kilometres off the nose.
	var reach: float = float(Sim.RADAR_RANGES[Sim.radar_range_idx])
	var cost := func(n: Node3D) -> float:
		var rel: Vector3 = n.global_position - global_position
		return fwd.angle_to(rel) + rel.length() / reach * 1.2
	cand = cand.filter(func(n): return \
		global_position.distance_to(n.global_position) < reach)
	if cand.is_empty():
		say("no targets")
		target = null
		return
	cand.sort_custom(func(a, b): return cost.call(a) < cost.call(b))
	var i := cand.find(target)
	target = cand[(i + 1) % cand.size()]
	lock_time = 0.0

func say(t: String) -> void:
	msg = t
	msg_t = 3.2


## Scripted rotary pilot: hold a height and a heading, used by the harness.
func _auto_pilot(_delta: float) -> void:
	var want_alt: float = _hover_alt
	var err: float = want_alt - global_position.y
	var want_vs: float = clampf(err * 0.35, -6.0, 8.0)
	throttle = clampf(0.5 + (want_vs - linear_velocity.y) * 0.10, 0.0, 1.0)
	var b := global_transform.basis
	var bank := atan2(-b.x.y, b.y.y)
	var pitch_att := asin(clampf(-b.z.y, -1.0, 1.0))
	in_roll = clampf(-bank * 2.2 - linear_velocity.dot(b.x) * 0.05, -1.0, 1.0)
	in_pitch = clampf(-pitch_att * 2.2 + (_hover_speed - linear_velocity.dot(-b.z)) * 0.03,
		-1.0, 1.0)
	in_yaw = 0.0

var _hover_alt := 120.0
var _hover_speed := 0.0
