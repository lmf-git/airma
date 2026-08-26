class_name AIPlane
extends Aircraft
## Bandit logic: fly a patrol orbit until something hostile is close, then run
## a lag-pursuit intercept, shoot, and defend against incoming missiles.

enum { PATROL, ENGAGE, EXTEND, DEFEND, ATTACK, EGRESS }

## What this aeroplane is for. A fighter hunts other aeroplanes, a CAS aircraft
## hunts what is on the ground and on the water, and a transport is going
## somewhere and would rather not be shot at.
var role := "fighter"
var route: PackedVector3Array = PackedVector3Array()
var _leg := 0
var _runs := 0
var min_slant := 1e9          # closest approach on a run, for the harness
var min_ang := 999.0          # best nose-on angle inside gun range, degrees

## Formation. A wingman holds a slot in the leader's frame and only leaves it
## when there is something to fight; when the fight is over it rejoins.
var leader: Aircraft = null
var slot := Vector3(70.0, -14.0, 95.0)   # starboard, down, astern
var form_error := 0.0                    # metres off the slot, for the harness
var formating := false                   # flying the slot this tick

## Terrain masking. An aeroplane being looked at by something it does not want
## to be looked at goes down and puts a hill between the two of them.
var mask_threats := true
var _masking := false
var _mask_alt := 0.0
var _mask_t := 0.0
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
	flares = 180
	chaff = 180
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
	# The slot comes before the job. A wingman with nothing to shoot at flies
	# his leader's wing whatever he is nominally for; checking this after the
	# role dispatch meant the mud movers returned early every frame and never
	# formated at all.
	if _try_formation(delta):
		return
	match role:
		"cas":
			_cas(delta)
			return
		"transport":
			_transport(delta)
			return
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
			# both dispensers: the aeroplane being shot at does not know what
			# is guiding the round any more than the pilot does
			dispense_all()
			if player:
				var away := (global_position - player.global_position).normalized()
				goal = global_position + (away + Vector3.UP * 0.35).normalized() * 3000.0
				# and if there is terrain to get behind, get behind it: running
				# away in a climb keeps you on the shooter's scope the whole way
				_mask_tick(player, delta)
				if _masking:
					goal = global_position + away * 3000.0
					goal.y = _mask_alt
			throttle = 1.0
			if _state_t > 4.0:
				state = ENGAGE

	# Ground proximity warning: sample the actual flight path several seconds
	# ahead, and if any of it is inside the dirt, roll upright and pull. A bandit
	# that pulls while inverted just arrives at the ground faster.
	if _gpws():
		_pull_up()
		state = PATROL
		return
	goal.y = clampf(goal.y, Sim.height_at(goal.x, goal.z) + 500.0, 13000.0)
	_steer_to(goal, delta)

## True when the projected path runs into rising ground. An aircraft rolling in
## on a target is deliberately pointed at the dirt, so the margins come right
## down for the run — with the fighter's numbers it aborts every attack at four
## kilometres and never fires a shot.
func _gpws() -> bool:
	var v := linear_velocity
	var run := role == "cas" and state == ATTACK
	if v.length() < 30.0:
		return agl < (90.0 if run else 200.0)
	var horizon: Array = [0.8, 1.6, 2.6] if run else [1.2, 2.4, 4.0, 6.0, 8.5]
	for t in horizon:
		var p: Vector3 = global_position + v * t
		var margin: float = (70.0 + t * 22.0) if run else (220.0 + t * 55.0)
		if p.y < Sim.height_at(p.x, p.z) + margin:
			return true
	return agl < (110.0 if run else 260.0)

# ------------------------------------------------------------ close air support
## A gun and bomb aircraft works a target rather than circling it: roll in from
## height, put the nose on, release, pull off, come round and do it again. The
## whole thing is two states and a re-attack timer.
func _cas(delta: float) -> void:
	var tgt := _find_ground()
	target = tgt
	# something shooting at us beats anything on the ground
	if missile_warn > 0.0:
		state = DEFEND
		_state_t = 0.0
	if tgt == null:
		if state != PATROL:
			state = PATROL
			_state_t = 0.0
	elif state == PATROL:
		state = ATTACK
		_state_t = 0.0
	elif state == EGRESS and _state_t > 6.0 \
			and global_position.distance_to(tgt.global_position) > 7000.0:
		# Come round properly. Re-attacking on a timer alone put the aeroplane
		# back into the run with the target three kilometres below it, which is
		# not a run-in but a vertical scissors: it pulled up through ten
		# thousand metres and stalled there.
		state = ATTACK
		_state_t = 0.0
	var goal := _patrol_point()
	match state:
		ATTACK:
			var rel: Vector3 = tgt.global_position - global_position
			var slant := rel.length()
			throttle = 0.9
			goal = tgt.global_position
			# Run in at height and only push over inside five kilometres. Diving
			# from twenty out means arriving at the deck with nineteen to go.
			if slant > 5000.0:
				# Terrain masking on the run-in. If there is a ridge between the
				# aeroplane and what it is about to attack, go down behind it and
				# come up late; if the ground between is flat there is nothing to
				# hide behind and the energy is better spent up high.
				_mask_tick(tgt, delta)
				if _masking and slant > 7000.0:
					goal.y = _mask_alt
				else:
					goal.y = maxf(tgt.global_position.y + 1500.0,
						Sim.height_at(goal.x, goal.z) + 1200.0)
			else:
				_strafe(tgt, slant, delta)
			# Pulled through, or too close to stay in. The nose test only counts
			# once the target is near: straight off an egress turn the aeroplane
			# is pointed the wrong way and this fired every single time, so no
			# attack ever got past the first second.
			var closing := (-global_transform.basis.z).dot(rel.normalized())
			if slant < 550.0 or (slant < 3200.0 and closing < 0.15) or agl < 90.0:
				state = EGRESS
				_state_t = 0.0
				_runs += 1
		EGRESS:
			var away := -global_transform.basis.z
			if is_instance_valid(tgt):
				away = global_position - tgt.global_position
				away.y = 0.0
			goal = global_position + away.normalized() * 6000.0 + Vector3.UP * 1200.0
			throttle = 1.0
			if _state_t > 45.0:      # never leave for good
				state = PATROL
				_state_t = 0.0
		DEFEND:
			dispense_all()
			goal = global_position - global_transform.basis.z * 2000.0 + Vector3.UP * 900.0
			throttle = 1.0
			if _state_t > 4.0:
				state = PATROL
		_:
			throttle = 0.75
	if _gpws():
		_pull_up()
		return
	if state == ATTACK and is_instance_valid(tgt):
		# A ceiling on the run-in. Without one the steering saturates the moment
		# the target slides behind the wing, and the aeroplane leaves on a zoom
		# climb: measured at nine kilometres, still nominally attacking. Inside
		# three kilometres the clamp comes off entirely — holding the goal sixty
		# metres above the target leaves the nose that much high, and with the
		# steering lag on top the best gun angle measured 11.4 degrees, which is
		# outside any sane trigger gate.
		if global_position.distance_to(tgt.global_position) > 3000.0:
			goal.y = clampf(goal.y, Sim.height_at(goal.x, goal.z) + 60.0,
				tgt.global_position.y + 3000.0)
	else:
		goal.y = clampf(goal.y, Sim.height_at(goal.x, goal.z) + 500.0, 9000.0)
	_steer_to(goal, delta)

## On the run: bombs first at stand-off, then the gun.
func _strafe(tgt: Node3D, slant: float, delta: float) -> void:
	var rel: Vector3 = tgt.global_position - global_position
	var ang := rad_to_deg((-global_transform.basis.z).angle_to(rel))
	min_slant = minf(min_slant, slant)
	if slant < 3200.0:
		min_ang = minf(min_ang, ang)
	if slant < 3200.0 and ang < 12.0:
		fire_gun(get_tree().current_scene)
	_fire_wait -= delta
	if _fire_wait > 0.0 or ang > 8.0 or slant > 3600.0 or slant < 1200.0:
		return
	if count_remaining("gbu32") <= 0:
		return
	selected = weapon_types.find("gbu32")
	if selected < 0:
		return
	designated = tgt.global_position
	designated_node = tgt
	locked = true
	if bays.size() > 0:
		set_bays(true)
	if fire() == "":
		_fire_wait = randf_range(6.0, 10.0)

## Nearest hostile that is not an aeroplane: armour, a battery, a ship.
func _find_ground() -> Node3D:
	var best: Node3D = null
	var bd := 26000.0
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self or n is Aircraft:
			continue
		if not ("team" in n) or int(n.team) == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

# ------------------------------------------------------------------ transport
## A transport is going somewhere. It flies its route at height and, if
## something shoots at it, it does the only thing a transport can: flares, and
## down into the weeds.
func _transport(delta: float) -> void:
	if route.is_empty():
		route = PackedVector3Array([
			home + Vector3(14000, 0, -9000), home + Vector3(-12000, 0, -14000),
			home + Vector3(-16000, 0, 6000), home + Vector3(9000, 0, 11000)])
	var wp: Vector3 = route[_leg % route.size()]
	var cruise := 5200.0
	if missile_warn > 0.0:
		state = DEFEND
		_state_t = 0.0
	if state == DEFEND:
		dispense_all()
		cruise = 900.0
		throttle = 1.0
		if is_instance_valid(target):
			_mask_tick(target, delta)
			if _masking:
				cruise = maxf(_mask_alt - Sim.height_at(global_position.x,
					global_position.z), 120.0)
		if _state_t > 6.0:
			state = PATROL
	else:
		throttle = 0.72
	var goal := Vector3(wp.x, Sim.height_at(wp.x, wp.z) + cruise, wp.z)
	if Vector2(goal.x - global_position.x, goal.z - global_position.z).length() < 2200.0:
		_leg += 1
	if _gpws():
		_pull_up()
		return
	_steer_to(goal, delta)

## Roll upright and pull. Shared, because a bandit that pulls while inverted
## just arrives at the ground faster.
func _pull_up() -> void:
	var b := global_transform.basis
	var bank := atan2(-b.x.y, b.y.y)
	in_roll = clampf(-bank * 2.2, -1.0, 1.0)
	in_yaw = 0.0
	in_pitch = clampf(1.0 - absf(bank) * 0.55, 0.15, 1.0)
	throttle = 1.0
	if role == "cas" and state == ATTACK:
		state = EGRESS
		_runs += 1
	_state_t = 0.0

## Fly the slot. The point is taken in the leader's frame and led along his
## velocity by the time it will take to get there, otherwise a wingman chases a
## position the leader has already left and sits permanently astern of it.
## True when this aeroplane flew the slot this tick. It leaves the slot for a
## missile, for a leader who has broken off, or for anything close enough to be
## its own business.
func _try_formation(delta: float) -> bool:
	formating = false
	if not is_instance_valid(leader) or not leader.is_alive():
		return false
	if missile_warn > 0.0:
		return false
	if leader is AIPlane and (leader as AIPlane).state != PATROL:
		return false
	var foe: Node3D = _find_ground() if role == "cas" else _find_enemy()
	var split: float = 9000.0 if role == "cas" else 11000.0
	if foe != null and global_position.distance_to(foe.global_position) < split:
		return false
	formating = true
	_formate(delta)
	return true

func _formate(delta: float) -> void:
	state = PATROL
	var lxf: Transform3D = leader.global_transform
	var want: Vector3 = lxf * slot
	form_error = want.distance_to(global_position)
	if _gpws():
		_pull_up()
		return
	if form_error > 2500.0:
		# A long way out: steer at the slot led along the leader's velocity, the
		# way an intercept works. The station keeper below is a formation-frame
		# controller and it is not an efficient way to cross five kilometres.
		var closing: float = maxf(linear_velocity.length(), 60.0)
		var lead_t: float = clampf(form_error / closing, 0.0, 2.5)
		var aim := want + leader.linear_velocity * lead_t
		aim.y = maxf(aim.y, Sim.height_at(aim.x, aim.z) + 120.0)
		throttle = clampf(leader.throttle + 0.30, 0.1, 1.0)
		_steer_to(aim, delta)
		return
	# Station keeping, in the leader's own frame: one axis to the throttle, one
	# to the bank, one to the pitch, on top of simply matching his attitude.
	#
	# Two things this needs that steering at a point cannot give it. Resolving
	# the error in his frame rather than the world's, because "outboard of the
	# slot" is a bank problem and "astern of it" is a throttle problem and a
	# single steering command cannot tell them apart. And a damping term on the
	# closure rate: without one the wingman drives at the slot, arrives with all
	# that speed still on, sails through, and comes round again — measured
	# swinging between three hundred metres and three kilometres, for ever.
	var local: Vector3 = lxf.affine_inverse() * global_position - slot
	var vlocal: Vector3 = lxf.basis.inverse() * (linear_velocity - leader.linear_velocity)
	var lb: float = atan2(-lxf.basis.x.y, lxf.basis.y.y)
	var lp: float = asin(clampf(-lxf.basis.z.y, -1.0, 1.0))
	var b := global_transform.basis
	var mb := atan2(-b.x.y, b.y.y)
	var mp := asin(clampf(-b.z.y, -1.0, 1.0))
	# +z in his frame is astern of the slot, so that is the throttle
	throttle = clampf(leader.throttle + local.z * 0.0030 + vlocal.z * 0.026,
		0.03, 1.0)
	# +x is outboard of the slot: bank back toward it, damped on closure
	var want_bank: float = lb + clampf(-(local.x * 0.0070 + vlocal.x * 0.13),
		-0.55, 0.55)
	in_roll = clampf(wrapf(want_bank - mb, -PI, PI) * 2.6, -1.0, 1.0)
	# +y is above it
	var want_pitch: float = lp + clampf(-(local.y * 0.0035 + vlocal.y * 0.13),
		-0.30, 0.30)
	in_pitch = clampf((want_pitch - mp) * 3.0, -1.0, 1.0)
	in_yaw = clampf(-local.x * 0.0012, -0.25, 0.25)

## Put a hill between us and whatever is looking. Returns the altitude to fly,
## or a negative number when there is nothing to hide behind. Going down for a
## threat that has clear sight of you anyway just gives away the energy.
func _mask_tick(threat: Node3D, delta: float) -> void:
	_mask_t -= delta
	if _mask_t > 0.0:
		return
	_mask_t = 0.6            # a ray march per threat, not one per frame
	var alt := _mask_altitude(threat)
	_masking = alt > 0.0
	_mask_alt = alt

func _mask_altitude(threat: Node3D) -> float:
	if not mask_threats or not is_instance_valid(threat):
		return -1.0
	var rel: Vector3 = threat.global_position - global_position
	var d := rel.length()
	if d < 2500.0 or d > 30000.0:
		return -1.0
	# how much lower we would have to be for the ridge line to cover us
	var depth: float = Sim.masking_depth(global_position, threat.global_position)
	if depth > 900.0:
		return -1.0            # open country between us; nothing to get behind
	var ground: float = Sim.height_at(global_position.x, global_position.z)
	return ground + maxf(90.0, depth * 0.35)

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
