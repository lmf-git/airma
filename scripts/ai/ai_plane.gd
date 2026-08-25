class_name AIPlane
extends Aircraft
## Bandit logic: fly a patrol orbit until something hostile is close, then run
## a lag-pursuit intercept, shoot, and defend against incoming missiles.

enum { PATROL, ENGAGE, EXTEND, DEFEND }

var state := PATROL
var home := Vector3.ZERO
var patrol_r := 3500.0
var _phase := 0.0
var _state_t := 0.0
var _skill := 0.75
var _fire_wait := 12.0

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("bandits")
	assist = true
	flares = 48
	throttle = 0.85
	gear_down = false
	gear_anim = 0.0
	set_bays(false)
	_phase = randf() * TAU

func hit_radius() -> float:
	return 7.0

func _pilot(delta: float) -> void:
	_state_t += delta
	_phase += delta * 0.08
	var player := _find_enemy()
	target = player
	var goal := _patrol_point()

	if missile_warn > 0.0:
		state = DEFEND
		_state_t = 0.0
	elif player and global_position.distance_to(player.global_position) < 14000.0:
		if state != ENGAGE and state != EXTEND:
			state = ENGAGE
	elif _state_t > 6.0 and state != PATROL:
		state = PATROL

	match state:
		PATROL:
			throttle = 0.62
		ENGAGE:
			if player:
				goal = _intercept(player)
				goal.y = maxf(goal.y, Sim.height_at(goal.x, goal.z) + 450.0)
				throttle = 0.95
				_try_shoot(player, delta)
				var d := global_position.distance_to(player.global_position)
				if d < 500.0 and (-global_transform.basis.z).dot(
						(player.global_position - global_position).normalized()) < -0.2:
					state = EXTEND
					_state_t = 0.0
		EXTEND:
			if player:
				goal = global_position + (global_position - player.global_position).normalized() * 4000.0 \
					+ Vector3.UP * 600.0
			throttle = 1.0
			if _state_t > 7.0:
				state = ENGAGE
		DEFEND:
			drop_flare()
			if player:
				var away := (global_position - player.global_position).normalized()
				goal = global_position + (away + Vector3.UP * 0.35).normalized() * 3000.0
			throttle = 1.0
			if _state_t > 4.0:
				state = ENGAGE

	# Ground proximity warning: sample the actual flight path several seconds
	# ahead, and if any of it is inside the dirt, roll upright and pull. A bandit
	# that pulls while inverted just arrives at the ground faster.
	if _gpws():
		var b := global_transform.basis
		var bank := atan2(-b.x.y, b.y.y)
		in_roll = clampf(-bank * 2.2, -1.0, 1.0)
		in_yaw = 0.0
		in_pitch = clampf(1.0 - absf(bank) * 0.55, 0.15, 1.0)
		throttle = 1.0
		state = PATROL
		_state_t = 0.0
		return
	goal.y = clampf(goal.y, Sim.height_at(goal.x, goal.z) + 500.0, 13000.0)
	_steer_to(goal, delta)

## True when the projected path runs into rising ground.
func _gpws() -> bool:
	var v := linear_velocity
	if v.length() < 30.0:
		return agl < 200.0
	for t in [1.2, 2.4, 4.0, 6.0, 8.5]:
		var p: Vector3 = global_position + v * t
		var margin: float = 220.0 + t * 55.0
		if p.y < Sim.height_at(p.x, p.z) + margin:
			return true
	return agl < 260.0

func _find_enemy() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self:
			continue
		if not (n is Aircraft) or n.team == team:
			continue
		if not n.is_alive():
			continue
		var d: float = global_position.distance_to(n.global_position)
		d /= maxf(n.radar_cross_section(), 0.05) if n.has_method("radar_cross_section") else 1.0
		if d < bd:
			bd = d
			best = n
	return best

func _patrol_point() -> Vector3:
	var p := home + Vector3(cos(_phase), 0, sin(_phase)) * patrol_r
	return Vector3(p.x, Sim.height_at(p.x, p.z) + 2600.0, p.z)

func _intercept(p: Node3D) -> Vector3:
	var rel: Vector3 = p.global_position - global_position
	var tv: Vector3 = p.linear_velocity if "linear_velocity" in p else Vector3.ZERO
	var t := clampf(rel.length() / maxf(linear_velocity.length(), 120.0), 0.0, 6.0)
	return p.global_position + tv * t * _skill

func _steer_to(goal: Vector3, _delta: float) -> void:
	var b := global_transform.basis
	var to := (goal - global_position)
	if to.length_squared() < 1.0:
		return
	var dir := to.normalized()
	var local := b.inverse() * dir
	var pitch_err := atan2(local.y, maxf(-local.z, 0.05))
	var yaw_err := atan2(local.x, maxf(-local.z, 0.05))
	if -local.z < 0.0:
		yaw_err = signf(local.x if absf(local.x) > 0.01 else 1.0) * PI * 0.5
	# roll so that "up" points at the target, classic bank-to-turn
	var want_roll := clampf(yaw_err * 2.2, -1.4, 1.4)
	var cur_roll := atan2(-b.x.y, b.y.y)
	var roll_err := wrapf(want_roll - cur_roll, -PI, PI)
	in_roll = clampf(roll_err * 1.5, -1.0, 1.0)
	in_pitch = clampf(pitch_err * 2.6 + absf(want_roll) * 0.25, -0.6, 1.0)
	in_yaw = clampf(yaw_err * 0.4, -0.4, 0.4)
	if stalling:
		in_pitch *= 0.3

func _try_shoot(p: Node3D, delta: float) -> void:
	_fire_wait -= delta
	var rel: Vector3 = p.global_position - global_position
	var d := rel.length()
	var ang := rad_to_deg((-global_transform.basis.z).angle_to(rel))
	if d < 900.0 and ang < 3.0:
		fire_gun(get_tree().current_scene)
	if _fire_wait > 0.0:
		return
	if ang > 25.0:
		return
	var want := ""
	if d < 7000.0 and count_remaining("aim9") > 0:
		want = "aim9"
	elif d < 15000.0 and count_remaining("aim120") > 0:
		want = "aim120"
	if want == "":
		return
	selected = weapon_types.find(want)
	if selected < 0:
		selected = 0
		return
	if bays.size() > 0:
		set_bays(true)
	locked = true
	var r := fire()
	if r == "":
		_fire_wait = randf_range(9.0, 16.0)
		await get_tree().create_timer(2.0).timeout
		if is_instance_valid(self) and alive:
			set_bays(false)
