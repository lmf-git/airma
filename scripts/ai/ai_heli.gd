class_name AIHeli
extends Helicopter
## Rotary wing bandit. Holds a low station, translates by tipping the nose over,
## keeps the nose on the target with pedal, and breaks away when spooked.

enum { STATION, ENGAGE, BREAK }

var state := STATION
var home := Vector3.ZERO
var station_alt := 260.0
var _phase := 0.0
var _state_t := 0.0
var _fire_wait := 8.0

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("bandits")
	assist = true
	flares = 150
	chaff = 150
	throttle = 0.55
	# A helicopter's skids and wheels do not retract, and this was copied from
	# the fixed wing bandit. With the gear stowed there is no ground contact at
	# all, so the aircraft has nothing to stand on and nothing to stop it.
	gear_down = true
	gear_anim = 1.0
	_phase = randf() * TAU

func hit_radius() -> float:
	return 6.0

func _pilot(delta: float) -> void:
	_state_t += delta
	_phase += delta * 0.12
	var foe := _find_enemy()
	target = foe

	if missile_warn > 0.0:
		state = BREAK
		_state_t = 0.0
	elif foe and global_position.distance_to(foe.global_position) < 6500.0:
		if state == STATION:
			state = ENGAGE
	elif _state_t > 5.0 and state != STATION:
		state = STATION

	var goal := home + Vector3(cos(_phase), 0, sin(_phase)) * 900.0
	var want_alt := Sim.height_at(goal.x, goal.z) + station_alt
	var want_speed := 22.0

	match state:
		ENGAGE:
			if foe:
				goal = foe.global_position
				want_alt = maxf(Sim.height_at(goal.x, goal.z) + 160.0,
					foe.global_position.y - 120.0)
				var d := global_position.distance_to(foe.global_position)
				want_speed = 0.0 if d < 1600.0 else 48.0
				_shoot(foe, delta)
		BREAK:
			dispense_all()
			if foe:
				var away := (global_position - foe.global_position).normalized()
				goal = global_position + away * 1800.0
			want_alt = Sim.height_at(goal.x, goal.z) + 90.0
			want_speed = 60.0
			if _state_t > 5.0:
				state = ENGAGE
		_:
			want_speed = 22.0

	# never fly into the hill in front
	var look := global_position + linear_velocity * 4.0
	var ahead := Sim.height_at(look.x, look.z) + 120.0
	want_alt = maxf(want_alt, ahead)

	# Up in the air, down to land. It was down for good, because with it
	# stowed a helicopter has nothing to stand on -- so every one on station
	# flew its whole sortie with its wheels hanging. Raised once it is well
	# clear of the ground and lowered again on the way down, with a gap
	# between the two so it does not cycle on the way through.
	var clear: float = global_position.y - Sim.height_at(global_position.x, global_position.z)
	if gear_down and clear > 40.0 and not on_ground:
		gear_down = false
	elif not gear_down and clear < 20.0:
		gear_down = true

	_fly(goal, want_alt, want_speed, delta)


## Who to fight, looked for a few times a second rather than on every tick.
## Every AI pilot walked every contact on the map at 120 Hz -- twice a tick for
## a wingman, which asks once to decide whether to formate and again to fight
## -- to find a nearest that cannot change in a hundredth of a second. What is
## held is let go at once if it dies or goes away.
var _foe_at := {}

func _held(kind: String, scan: Callable) -> Node3D:
	var c: Variant = _foe_at.get(kind)
	if c != null and _life_t < float(c[0]):
		var n: Variant = c[1]
		if n == null:
			return null
		if is_instance_valid(n) and (not n.has_method("is_alive") or n.is_alive()):
			return n
	var got: Node3D = scan.call()
	_foe_at[kind] = [_life_t + 0.25 + randf() * 0.1, got]
	return got

func _find_enemy() -> Node3D:
	return _held("any", _scan_enemy)

func _scan_enemy() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self:
			continue
		if not ("team" in n) or n.team == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if Sim.no_air_threat and (n is Aircraft):
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < bd:
			bd = d
			best = n
	return best

## Collective holds the height, pedal points the nose, and the nose tips over to
## translate: the three things a helicopter pilot is actually doing.
func _fly(goal: Vector3, want_alt: float, want_speed: float, _delta: float) -> void:
	var b := global_transform.basis
	var to := goal - global_position
	var bearing := atan2(to.x, -to.z)
	var hdg := atan2(-b.z.x, b.z.z)
	var yaw_err := wrapf(bearing - hdg, -PI, PI)
	in_yaw = clampf(yaw_err * 1.4, -1.0, 1.0)

	var fwd_speed := linear_velocity.dot(-b.z)
	var want_att := clampf((want_speed - fwd_speed) * 0.010, -0.22, 0.30)
	var pitch_att := asin(clampf(-b.z.y, -1.0, 1.0))
	in_pitch = clampf((-want_att - pitch_att) * 2.4, -1.0, 1.0)

	var bank := atan2(-b.x.y, b.y.y)
	in_roll = clampf(-bank * 2.2 - linear_velocity.dot(b.x) * 0.03, -1.0, 1.0)

	var err := want_alt - global_position.y
	var want_vs := clampf(err * 0.30, -8.0, 10.0)
	throttle = clampf(0.52 + (want_vs - linear_velocity.y) * 0.055, 0.0, 1.0)

func _shoot(foe: Node3D, delta: float) -> void:
	_fire_wait -= delta
	var rel: Vector3 = foe.global_position - global_position
	var d := rel.length()
	var ang := rad_to_deg((-global_transform.basis.z).angle_to(rel))
	if d < 1300.0 and ang < 5.0:
		fire_gun(get_tree().current_scene)
	if _fire_wait > 0.0 or ang > 16.0:
		return
	var want := ""
	if d < 5200.0 and count_remaining("aim120") > 0:
		want = "aim120"
	elif d < 3200.0 and count_remaining("aim9") > 0:
		want = "aim9"
	if want == "":
		return
	selected = maxi(weapon_types.find(want), 0)
	locked = true
	if fire() == "":
		_fire_wait = randf_range(7.0, 13.0)
