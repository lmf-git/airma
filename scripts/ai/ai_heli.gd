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
## Flying as a kill streak over a street fight: the arena whose men it hunts as
## well as everything on the radar picture, and how long it has left on station
## before it turns for home and is gone.
var arena: Node = null
var patrol_t := -1.0
## Called up from out of town and on its way in: flying, not fighting, and
## its time on station not yet started.
var inbound := false
## Close enough to the fight to count as there.
const ON_STATION := 500.0
## How low it runs in.
const NAP_AGL := 45.0
var _leaving := false
var _burst_t := 0.0

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
	_maws(delta)
	if inbound:
		var flat := Vector2(global_position.x - home.x, global_position.z - home.z).length()
		if flat > ON_STATION:
			# In low, at a transit speed: down among the hedges and roofs, where
			# a man with a tube on the far side of town has nothing to lock.
			# Coming in at its working height it was in the open sky for the
			# whole run, and the first one up shot it down every time.
			if missile_warn > 0.0:
				drop_flare()
			# and over whatever is ahead, which the working orbit looks out for
			# and this did not: at seventy with the nose down it flew into
			# the rising ground short of the town
			# over the tallest thing under it and on the way -- ground, roofs,
			# pylons -- not just the ground: run in at roof height it flew into
			# the first pylon on the line
			var want_h: float = _floor_ahead() + NAP_AGL
			var low: bool = global_position.y < want_h - 30.0
			_fly(home, want_h, 30.0 if low else 58.0, delta)
			return
		inbound = false
		Sim.report("%s on station for %d seconds — it hunts on its own" % [name, int(patrol_t)],
			Sim.Ev.GOOD)
	if patrol_t >= 0.0 and not _leaving:
		patrol_t -= delta
		if patrol_t <= 0.0:
			_leaving = true
			Sim.report("%s off station" % name, Sim.Ev.INFO)
	if _leaving:
		# away, low and fast, and gone once it is out of everyone's sight
		var out: Vector3 = global_position + (global_position - home).normalized() * 3000.0
		_fly(out, Sim.height_at(out.x, out.z) + 200.0, 70.0, delta)
		if global_position.distance_to(home) > 4000.0:
			queue_free()
		return
	_phase += delta * 0.12
	var foe := _find_enemy()
	target = foe

	if missile_warn > 0.0 and arena != null:
		# Called in over a fight it stays on the fight: flares out and the
		# nose kept on the target. Breaking away and down, which a bandit
		# does, had it turning its back on the town every time a man on the
		# other side shouldered a missile, and diving to thirty metres.
		# Flares only: what a man shoulders is a heat seeker, and chaff
		# dumped over the town drew off radar-guided rockets fired into it,
		# ours included.
		drop_flare()
		if state == STATION and foe:
			state = ENGAGE
	elif missile_warn > 0.0:
		state = BREAK
		_state_t = 0.0
	elif foe and global_position.distance_to(foe.global_position) < 6500.0:
		if state == STATION:
			state = ENGAGE
	elif _state_t > 5.0 and state != STATION:
		state = STATION

	# A bandit patrols wide; a gunship called in over a fight circles the
	# middle of it, where the fight is.
	var goal := home + Vector3(cos(_phase), 0, sin(_phase)) * (220.0 if arena != null else 900.0)
	var want_alt := Sim.height_at(goal.x, goal.z) + station_alt
	var want_speed := 22.0

	match state:
		ENGAGE:
			if foe:
				goal = foe.global_position
				want_alt = maxf(Sim.height_at(goal.x, goal.z) + (90.0 if foe is Soldier else 160.0),
					foe.global_position.y - 120.0)
				var d := global_position.distance_to(foe.global_position)
				# a man is worked from closer in than a vehicle, with the chin gun
				var stand: float = 700.0 if foe is Soldier else 1600.0
				if arena != null:
					# over the town, close enough for the gun and the rockets
					stand = 320.0 if foe is Soldier else 900.0
				want_speed = 0.0 if d < stand else 48.0
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

	# never fly into the hill in front -- nor the tower block: over a city
	# the working orbit and the run onto a man are flown lower than its roofs,
	# and only the hill was looked for
	var look := global_position + linear_velocity * 4.0
	want_alt = maxf(want_alt, Sim.height_at(look.x, look.z) + 120.0)
	want_alt = maxf(want_alt, _floor_ahead() + NAP_AGL)

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


## A missile approach warner, which a real attack helicopter has: it sees the
## motor of whatever is coming at it, radar or no radar. A shoulder-launched
## round is a heat seeker and lights up no warning receiver, so the gunship
## never knew one was coming: called over a ground fight it was killed on its
## way in, every time, by the first man on the other side with a tube. The
## flares now go out while one is closing.
var _maws_t := 0.0

func _maws(delta: float) -> void:
	_maws_t -= delta
	if _maws_t > 0.0:
		return
	_maws_t = 0.2
	for m in get_tree().get_nodes_in_group("missiles"):
		if not is_instance_valid(m) or m.get("target") != self or bool(m.get("dead")):
			continue
		var mn := m as Node3D
		var d: float = mn.global_position.distance_to(global_position)
		if d < 3000.0:
			warn_missile()
		# The flares in the last couple of seconds, when they work: a seeker
		# judges each salvo once and grows warier of the next, so a salvo
		# thrown four seconds out only taught it what to ignore.
		var closing: float = maxf((m.get("vel") as Vector3 - linear_velocity).dot(
			(global_position - mn.global_position).normalized()), 50.0)
		if d / closing < 2.4:
			drop_flare()
			return

func _find_enemy() -> Node3D:
	return _held("any", _scan_enemy)

func _scan_enemy() -> Node3D:
	# Whatever is the most danger to it first, then what it is for: the air
	# defence and the men with missiles, a helicopter of theirs; then the
	# armour its missiles are for; then the rest. It took the nearest armour
	# it could see before anything else, and left the gun that was tracking
	# it until there was no tank left. Weighed against how near, as a crew
	# in armour weighs its own (`Tank.threat_to_aircraft`).
	var best: Node3D = null
	var bs := 1e9
	if arena != null:
		for v in get_tree().get_nodes_in_group("vehicles"):
			if not is_instance_valid(v) or not (v is Tank) or (v as Tank).team == team \
					or not (v as Tank).alive:
				continue
			var dv: float = global_position.distance_to((v as Node3D).global_position)
			if dv > 3500.0:
				continue
			var sv: float = dv / Tank.threat_to_aircraft(v)
			if sv < bs and Firearm.can_see(global_position,
					(v as Node3D).global_position + Vector3(0, 2.0, 0)):
				bs = sv
				best = v
	# over a street fight it hunts the men in it as well, any it can see
	if arena != null and is_instance_valid(arena):
		for n in arena.enemies_of(team):
			if not is_instance_valid(n) or not n.is_alive():
				continue
			var d0: float = global_position.distance_to(n.global_position)
			var s0: float = d0 / Tank.threat_to_aircraft(n)
			if s0 < bs and Firearm.can_see(global_position, Soldier.chest_of(n)):
				bs = s0
				best = n
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self:
			continue
		if not ("team" in n) or n.team == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if Sim.no_air_threat and (n is Aircraft):
			continue
		# nothing it carries catches a jet
		if n is Aircraft and not (n is Helicopter):
			continue
		var d: float = global_position.distance_to(n.global_position)
		var s1: float = d / Tank.threat_to_aircraft(n)
		if s1 < bs:
			bs = s1
			best = n
	return best

## Collective holds the height, pedal points the nose, and the nose tips over to
## translate: the three things a helicopter pilot is actually doing.
## The highest thing under the next five seconds of track -- ground, roofs,
## pylons -- as wide as the rotor reaches, which is what strikes first. Hovering
## it looks round where it is.
func _floor_ahead() -> float:
	var floor_h := -1e9
	var reach: float = float(spec.get("rotor_radius", 6.0)) + 4.0
	for k in 5:
		var q: Vector3 = global_position + linear_velocity * (float(k) * 1.2)
		floor_h = maxf(floor_h, Sim.height_at(q.x, q.z))
		var hit_id: int = Obstacles.hit(Vector3(q.x, global_position.y, q.z), reach)
		if hit_id >= 0:
			floor_h = maxf(floor_h, Obstacles.top_of(hit_id))
	return floor_h

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
	# A man: the chin gun laid on him -- a burst, a pause -- as long as he is
	# somewhere the turret will reach. Waiting for the nose to come within
	# five degrees of a man under a hovering helicopter, it never fired.
	if foe is Soldier:
		gun_aim = Soldier.chest_of(foe) + Vector3(randfn(0.0, 0.6), 0.0, randfn(0.0, 0.6))
		var dm: float = global_position.distance_to(foe.global_position)
		_burst_t += delta
		if dm < 1100.0 and fmod(_burst_t, 2.2) < 0.8:
			fire_gun(get_tree().current_scene)
		# and over a fight, a pair of rockets into him now and then
		var rel_s: Vector3 = foe.global_position - global_position
		if arena != null and _fire_wait <= 0.0 and dm < 2500.0 and count_remaining("hydra") > 0 \
				and rad_to_deg((-global_transform.basis.z).angle_to(rel_s)) < 20.0:
			selected = maxi(weapon_types.find("hydra"), 0)
			target = foe
			locked = true
			if fire() == "":
				_fire_wait = randf_range(2.5, 4.0) if randf() < 0.5 else 0.3
		return
	gun_aim = Vector3.INF
	var rel: Vector3 = foe.global_position - global_position
	var d := rel.length()
	var ang := rad_to_deg((-global_transform.basis.z).angle_to(rel))
	if arena != null and foe is Tank:
		_strike_armour(foe, d, ang, delta)
		return
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


## A vehicle, from a gunship over a fight: Hellfires while it has them, then
## the rockets, and the chin gun laid on it throughout. It had nothing for a
## tank but the air to air missiles -- which it does not carry -- so it hovered
## in front of the armour and did nothing.
func _strike_armour(foe: Node3D, d: float, ang: float, delta: float) -> void:
	gun_aim = foe.global_position + Vector3(0, 1.5, 0)
	_burst_t += delta
	if d < 1500.0 and fmod(_burst_t, 2.4) < 1.0:
		fire_gun(get_tree().current_scene)
	if _fire_wait > 0.0 or ang > 20.0 or d > 7000.0:
		return
	var want := ""
	if count_remaining("agm114") > 0:
		want = "agm114"
	elif d < 4500.0 and count_remaining("hydra") > 0:
		want = "hydra"
	if want == "":
		return
	selected = maxi(weapon_types.find(want), 0)
	target = foe
	locked = true
	if fire() == "":
		# a Hellfire every few seconds; a pair of rockets in quick succession
		_fire_wait = randf_range(3.5, 5.0) if want == "agm114" else randf_range(0.35, 0.6)
