class_name PlayerJet
extends Aircraft
## Keyboard/mouse pilot. Mouse mode treats cursor offset from screen centre as
## a spring-centred stick; the keyboard always works as a fallback.

var mouse_fly := false
var stick := Vector2.ZERO
var msg := ""
var msg_t := 0.0
var kills := 0
var _mouse := Vector2.ZERO
var auto := ""            # scripted pilot used by the test harness
var active := true        # false while parked and waiting for a pilot
var pod: Node = null      # targeting pod, supplies the gunship aim point
var _auto_t := 0.0
var turn_speed := 250.0    # entry speed the turn test holds
var hover_alt := 900.0     # height the scripted hover holds
var _dash_alt := 1000.0
var bank_deg := 0.0
var orbit_alt := 2500.0
var orbit_speed := 120.0

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("player")
	throttle = 0.0

func hit_radius() -> float:
	return 8.0

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
	if not active:
		throttle = 0.0
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		wheel_brake = true
		return
	if auto != "":
		_auto_pilot(delta)
		return
	if Sim.tapped(&"mouse_fly"):
		mouse_fly = not mouse_fly
		_mouse = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_fly else Input.MOUSE_MODE_VISIBLE
		say("mouse stick " + ("ON" if mouse_fly else "OFF"))

	var kp := Sim.strength(&"pitch_up") - Sim.strength(&"pitch_down")
	var kr := Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	var target_stick := Vector2(kr, kp)
	if mouse_fly:
		target_stick = Vector2(clampf(_mouse.x + kr, -1, 1), clampf(-_mouse.y + kp, -1, 1))
		_mouse = _mouse.lerp(Vector2.ZERO, delta * 0.9)
	var rate := 7.5 if not mouse_fly else 14.0
	stick = stick.lerp(target_stick, clampf(delta * rate, 0.0, 1.0))
	in_roll = stick.x
	in_pitch = stick.y
	in_yaw = Sim.strength(&"yaw_right") - Sim.strength(&"yaw_left")

	var t := Sim.strength(&"throttle_up") - Sim.strength(&"throttle_down")
	throttle = clampf(throttle + t * delta * 0.55, 0.0, 1.0)
	airbrake = Sim.held(&"brakes") and not on_ground
	wheel_brake = Sim.held(&"brakes") and on_ground

	if Sim.tapped(&"gear"):
		if on_ground and gear_down:
			say("gear locked down — weight on wheels")
		else:
			toggle_gear()
			say("gear " + ("down" if gear_down else "up"))
	if Sim.tapped(&"flaps"):
		flaps = 0.0 if flaps > 0.5 else 1.0
		say("flaps " + ("down" if flaps > 0.5 else "up"))
	if Sim.tapped(&"bay"):
		if bays.values().any(func(b): return b["kind"] == "internal"):
			var opening := not any_bay_open()
			set_bays(opening)
			say("weapon bay " + ("opening" if opening else "closing"))
		elif has_hold():
			toggle_ramp()
			say("cargo ramp " + ("opening" if ramp_open else "closing"))
		else:
			say("no internal bays on this airframe")
	if Sim.tapped(&"assist"):
		assist = not assist
		Sim.assist = assist
		say("fly-by-wire " + ("ON" if assist else "OFF — you are on your own"))
	if Sim.tapped(&"cycle_weapon"):
		cycle_weapon()
		_announce_weapon()
	for i in 8:
		if Sim.tapped(StringName("weapon_%d" % (i + 1))):
			if i < weapon_types.size():
				set_weapon(i)
				_announce_weapon()
			else:
				say("no station %d on this jet" % (i + 1))
	if Sim.tapped(&"cycle_target") \
			and not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		cycle_target()
		lock_presses_seen += 1
	if Sim.tapped(&"chaff"):
		drop_chaff()
	if Sim.tapped(&"flare"):
		if flares > 0:
			drop_flare()
		else:
			say("out of flares")
	if is_gunship_weapon(current_weapon()) and not Sim.ui_modal:
		if Sim.held(&"gun") or Sim.held(&"fire"):
			var aim := gunship_aim()
			if aim != Vector3.INF:
				fire_gunship(get_tree().current_scene, aim)
			else:
				say("no aim point — ALT+right click for the pod, CTRL+T to designate")
	elif Sim.held(&"gun") and current_weapon() == "gun" and not Sim.ui_modal:
		if not fire_gun(get_tree().current_scene) and ammo <= 0:
			say("gun dry")
	if Sim.tapped(&"fire") and not Sim.ui_modal:
		if current_weapon() == "gun":
			fire_gun(get_tree().current_scene)
		else:
			var r := fire()
			if r == "":
				say("%s away" % WeaponSpec.get_spec(current_weapon())["short"])
			else:
				say(r)

## Where the battery is shooting: the pod point if it has one, otherwise a
## ray out of the left beam onto the ground.
func gunship_aim() -> Vector3:
	if pod != null and is_instance_valid(pod) and pod.active:
		var p: Vector3 = pod.aim_point()
		if p != Vector3.INF:
			return p
	var origin := global_position
	var dir := (-global_transform.basis.x - global_transform.basis.y * 1.4).normalized()
	var t := 40.0
	while t < 12000.0:
		var q := origin + dir * t
		if q.y <= Sim.height_at(q.x, q.z):
			return q
		t += 30.0
	return Vector3.INF

func _announce_weapon() -> void:
	var w := current_weapon()
	if w == "gun":
		say("gun selected — %d rounds" % ammo)
		return
	if is_gunship_weapon(w):
		say("%s selected" % weapon_label(w))
		return
	var ws := WeaponSpec.get_spec(w)
	var extra := ""
	if not any_bay_open() and bays.values().any(func(b): return b["kind"] == "internal"):
		extra = "  (press B to open the bay)"
	say("%s selected — %d left%s" % [ws["name"], count_remaining(w), extra])

## Threshold speed: 1.3 times the stall speed at the current weight, in knots
## indicated, which is what every approach in aviation is actually flown at.
func ref_speed_kt() -> float:
	var cl_max: float = spec["cl_alpha"] * spec["cl_max_aoa"] + float(spec.get("flap_cl", 0.42))
	var w: float = mass * 9.81
	var v_stall := sqrt(2.0 * w / (1.225 * spec["wing_area"] * maxf(cl_max, 0.4)))
	return v_stall * 1.3 * 1.94384

## How many T presses actually reached the handler, for the harness.
var lock_presses_seen := 0

func cycle_target() -> void:
	var w := current_weapon()
	var ws := WeaponSpec.get_spec(w if w != "gun" else "aim9")
	# A bomb looks for things on the surface. Shipping is on the surface too,
	# and searching only "ground_targets" meant a warship could be locked with a
	# missile selected and became invisible the moment you reached for a bomb.
	var cand: Array = []
	var groups := ["hittable"]
	if String(ws["kind"]) == "bomb":
		groups = ["ground_targets", "ships"]
	for grp in groups:
		for n in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(n) or n == self:
				continue
			# An explicit hostile team, not merely the absence of a friendly
			# one. The carrier carries no `team` at all and sits in "hittable",
			# so it passed this test and the radar cycled onto your own ship.
			if not ("team" in n) or int(n.team) == team:
				continue
			if n.is_in_group("no_lock"):
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if not cand.has(n):
				cand.append(n)
	if cand.is_empty():
		say("no targets")
		target = null
		return
	if Sim.debug_weapons:
		print("[lock] %d hostile(s) in the world" % cand.size())
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
	# Terrain masking. A radar cannot see through a mountain: a contact in the
	# next valley is not a lock, and something sitting behind a ridge is hidden
	# until one of you comes up. Anything within a couple of kilometres stays
	# available so a target does not blink out as it crosses a hedge.
	var visible_now: Array = cand.filter(func(n): return \
		global_position.distance_to(n.global_position) < 2000.0 \
		or Sim.line_of_sight(global_position + Vector3(0, 4, 0),
			(n as Node3D).global_position + Vector3(0, 4, 0), 250.0))
	if Sim.debug_weapons:
		print("[lock] %d within radar range, %d of those not terrain masked" % [
			cand.size(), visible_now.size()])
	if not visible_now.is_empty():
		cand = visible_now
	else:
		say("no radar contacts — terrain masked")
		target = null
		return
	if cand.is_empty():
		say("no targets")
		target = null
		return
	if Sim.debug_weapons:
		print("[lock] %d candidate(s) survived: reach %.0f km, weapon %s" % [
			cand.size(), reach * 0.001, w])
	# Two orders, deliberately. Which contact to take when the radar is empty is
	# a question about the here and now, so that one is ranked on cost. Which
	# contact comes *next* must not be: cost is boresight angle plus range, you
	# turn toward whatever you just locked, that makes it rank first again, and
	# the next press hands back the same neighbour. T walked between two
	# contacts for ever and never reached the third — which is exactly what
	# "it works sometimes" looks like from the cockpit.
	var order := cand.duplicate()
	order.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var i := order.find(target)
	if i < 0:
		# nothing held, or what was held is gone: take the best one there is
		cand.sort_custom(func(a, b): return cost.call(a) < cost.call(b))
		target = cand[0]
	else:
		target = order[(i + 1) % order.size()]
	lock_time = 0.0
	var d := global_position.distance_to(target.global_position) * 0.001
	say("target %s  %.1f km" % [Sim.label_of(target).left(18), d])

func on_weapon_hit(what: Node, _wid: String) -> void:
	if what.has_method("is_alive") and not what.is_alive():
		return
	say("splash")

func say(t: String) -> void:
	msg = t
	msg_t = 3.2

func explode() -> void:
	if alive:
		Sim.report("AIRCRAFT DESTROYED", Sim.Ev.BAD)
	super.explode()


# ---------------------------------------------------------------------------
## Scripted pilot: flies a circuit without a human. Used by the command line
## test harness and available as a demo.
func _auto_pilot(delta: float) -> void:
	_auto_t += delta
	var _kias := ias * 1.94384
	match auto:
		"takeoff":
			throttle = 1.0
			wheel_brake = _auto_t < 1.0
			if on_ground:
				flaps = 1.0
				in_pitch = 0.6 if ias > rotate_speed() else 0.0
				in_roll = 0.0
				in_yaw = clampf(-global_position.x * 0.05 - linear_velocity.x * 0.2, -0.5, 0.5)
			else:
				in_yaw = 0.0
				if agl > 40.0:
					gear_down = false
					flaps = 0.0
				if global_position.y < 550.0:
					_hold_pitch(14.0, 0.0)
				else:
					_hold(900.0, 0.0, 250.0)
		"land":
			_fly_approach()
		"fight":
			set_bays(true)
			if missile_warn > 0.0:
				# break into the missile and pump flares
				drop_flare()
				throttle = 1.0
				in_roll = 1.0
				in_pitch = 0.85
				in_yaw = 0.0
				return
			if target == null or not is_instance_valid(target) \
					or (target.has_method("is_alive") and not target.is_alive()):
				cycle_target()
			if target and is_instance_valid(target):
				var rel: Vector3 = target.global_position - global_position
				_hold_pitch(clampf(rad_to_deg(asin(clampf(rel.normalized().y, -1, 1))), -15.0, 20.0),
					rad_to_deg(atan2(rel.x, -rel.z)))
				throttle = 0.9
				var d := rel.length()
				var ang := rad_to_deg((-global_transform.basis.z).angle_to(rel))
				# Pick by range, then fall back to whatever is actually left.
				# Choosing the weapon and deciding to shoot were separate before,
				# so it emptied the Sidewinder rails at seven miles where they
				# cannot reach, then spent the rest of the fight pulling the
				# trigger on a rail with nothing on it.
				var want := "aim120" if d > 8000.0 else "aim9"
				if count_remaining(want) <= 0:
					want = "aim9" if want == "aim120" else "aim120"
				var reach := 22000.0 if want == "aim120" else 8000.0
				if ang < 12.0 and d < reach and fire_cd <= 0.0 \
						and count_remaining(want) > 0:
					selected = maxi(weapon_types.find(want), 0)
					var res := fire()
					if res != "":
						say(res)
				if d < 1200.0 and ang < 4.0:
					fire_gun(get_tree().current_scene)
			else:
				_hold(4000.0, 0.0, 250.0)
		"dash":
			# full burner, hold altitude, let it run out to its top speed
			throttle = 1.0
			_hold(_dash_alt, 0.0, 9999.0)
			throttle = 1.0
		"bank":
			# hold a commanded bank angle with the stick centred in pitch, so the
			# only thing acting on the flight path is where the lift vector points
			throttle = 0.72
			var b := global_transform.basis
			var bank := atan2(-b.x.y, b.y.y)
			in_roll = clampf((deg_to_rad(bank_deg) - bank) * 2.0, -1.0, 1.0)
			in_pitch = 0.0
			in_yaw = 0.0
		"turn":
			# Sustained turn: roll to the commanded bank and hold full aft stick,
			# with the throttle trimming to hold the entry speed. Leaving the
			# burner in instead just accelerates out of the turn, which measures
			# nothing -- the jet ends up at Mach 2 pulling the same g at a third
			# of the turn rate.
			throttle = clampf(0.5 + (turn_speed - linear_velocity.length()) * 0.03,
				0.0, 1.0)
			var tb := global_transform.basis
			var tbank := atan2(-tb.x.y, tb.y.y)
			in_roll = clampf((deg_to_rad(bank_deg) - tbank) * 2.2, -1.0, 1.0)
			in_pitch = 1.0 if _auto_t > 2.0 else 0.0
			in_yaw = 0.0
		"tumble":
			# through every attitude there is: continuous roll with the nose
			# tracing a loop, so the camera meets inverted flight, the vertical
			# and everything between
			throttle = 1.0
			in_roll = 1.0
			in_pitch = 0.55 + 0.45 * sin(_auto_t * 0.7)
			in_yaw = 0.0
		"hold":
			pass          # the harness drives the stick directly
		"hover":
			# Convert first, then add power. Swivelling the nozzle with the
			# throttle already open just accelerates the aeroplane down the
			# runway while the doors are still moving.
			hover_cmd = true
			in_roll = 0.0
			in_yaw = 0.0
			if jetborne < 0.98:
				throttle = 0.0
				in_pitch = 0.0
			else:
				# throttle is now a height lever
				throttle = clampf(0.62 + (hover_alt - global_position.y) * 0.05
					- linear_velocity.y * 0.11, 0.0, 1.0)
				# and the nose comes up to kill any drift, not down
				var fwd_v: float = linear_velocity.dot(-global_transform.basis.z)
				in_pitch = clampf(fwd_v * 0.06, -0.4, 0.4)
		"orbit":
			# left hand pylon turn: what the aircraft does while the crew is aft
			# working the guns
			var b := global_transform.basis
			var bank := atan2(-b.x.y, b.y.y)
			var want_bank := deg_to_rad(-24.0)
			in_roll = clampf((want_bank - bank) * 1.6, -1.0, 1.0)
			var err := orbit_alt - global_position.y
			var want_vs := clampf(err * 0.16, -12.0, 12.0)
			in_pitch = clampf((want_vs - linear_velocity.y) * 0.09 + 0.10, -0.4, 0.6)
			in_yaw = 0.0
			throttle = clampf(0.45 + (orbit_speed - linear_velocity.length()) * 0.02, 0.1, 1.0)
		"wait":
			throttle = 0.0
			in_pitch = 0.0
			in_roll = 0.0
			in_yaw = 0.0
			wheel_brake = true
		_:
			throttle = 0.75
			_hold(2000.0, 0.0, 240.0)

func _pitch_deg() -> float:
	return rad_to_deg(asin(clampf(-global_transform.basis.z.y, -1.0, 1.0)))

func _bank() -> float:
	var b := global_transform.basis
	return atan2(-b.x.y, b.y.y)

## Hold a pitch attitude and wings level on the given heading.
func _hold_pitch(deg: float, hdg_deg: float) -> void:
	in_pitch = clampf((deg - _pitch_deg()) * 0.09, -0.6, 0.9)
	var fwd := -global_transform.basis.z
	var hdg := rad_to_deg(atan2(fwd.x, -fwd.z))
	var herr := wrapf(hdg_deg - hdg, -180.0, 180.0)
	# Bank authority has to match the aeroplane. Commanding 43 degrees on a
	# transport that rolls at 0.95 rad/s means the correction is still going in
	# long after it was needed, and the approach turns into a 1.5 Hz wallow.
	var auth: float = clampf(float(spec["max_roll_rate"]) / 4.1, 0.22, 1.0)
	var lim: float = 0.75 * auth
	var want_bank := clampf(deg_to_rad(herr * 2.5 * auth), -lim, lim)
	# Damp on measured roll rate as well as bank error. Without it a large
	# aeroplane, which cannot roll anywhere near as fast as the loop expects,
	# overshoots every correction and wallows through plus and minus forty
	# degrees all the way down the approach.
	var roll_rate: float = angular_velocity.dot(-global_transform.basis.z)
	in_roll = clampf((want_bank - _bank()) * 1.8 - roll_rate * (0.8 / auth), -1.0, 1.0)
	in_yaw = 0.0

func _hold(alt: float, hdg_deg: float, spd: float) -> void:
	var err := alt - global_position.y
	var want_pitch := clampf(err * 0.02 - linear_velocity.y * 0.9, -12.0, 15.0)
	_hold_pitch(want_pitch, hdg_deg)
	throttle = clampf(0.45 + (spd - linear_velocity.length()) * 0.02, 0.0, 1.0)

## Fly the 3 degree slope to runway 36 and flare.
func _fly_approach() -> void:
	var p := global_position
	var d := Vector2(p.x, p.z - Airbase.AIM_Z).length()
	gear_down = true
	flaps = 1.0
	if on_ground:
		throttle = 0.0
		wheel_brake = linear_velocity.length() < 70.0
		airbrake = true
		in_pitch = clampf(0.3 - linear_velocity.length() * 0.006, -0.3, 0.4)
		in_roll = 0.0
		in_yaw = clampf(-p.x * 0.04 - linear_velocity.x * 0.15, -0.5, 0.5)
		return
	# The slope is referenced to the threshold, not to the aiming point. Flown
	# straight at the aim point the aeroplane is only eighteen metres up three
	# hundred metres out, so the flare begins before the runway and the wheels
	# arrive on the threshold lip: measured, an F-22 touching at z=+1474 with
	# the paved surface ending at 1500, hard, and reported as a landing off the
	# paved surface because a few metres either way put it outside. A real three
	# degree approach crosses the threshold at fifty feet and touches down in
	# the zone beyond it, which is what the bias buys.
	var want_y: float = maxf((d + Airbase.THRESH_BIAS) * tan(deg_to_rad(Airbase.GLIDE)), 0.0)
	var err := want_y - p.y
	var want_vs := clampf(err * 0.28, -8.0, 6.0)
	# Flare on HEIGHT, not on a fixed sink rate. The old law commanded a steady
	# -0.7 m/s from the moment the aim point was inside 260 m, which is 13.6 m
	# up on a three degree slope: nineteen seconds in the air and most of a
	# kilometre of runway floating. Anything that could not out-sink its own
	# autothrottle simply flew the length of the runway and went around. Sink
	# proportional to height arrives at the ground promptly and still touches
	# down at half a metre a second.
	var flaring := p.y < 26.0
	if flaring:
		# Begun higher and shallower than it was. At 18 m the old law commanded
		# the eight metres a second the aeroplane was already doing, so there
		# was nothing left to arrest and a fighter arrived at 7.9 m/s — a hard
		# landing every time. Starting at 26 m with a gentler gradient gives the
		# elevator, which is clamped at eleven degrees, time to do the work.
		want_vs = -maxf(0.55, p.y * 0.28)
	var want_pitch := clampf((want_vs - linear_velocity.y) * 1.1 + 3.0, -6.0, 11.0)
	var hdg_err := clampf(-p.x * 0.10 - linear_velocity.x * 0.6, -14.0, 14.0)
	_hold_pitch(want_pitch, hdg_err)
	# Approach speed comes from the airframe, not a number. A fixed 160 kt was
	# fine for one weight and wrong for every other: fly a light jet at it and
	# there is so much surplus lift that it climbs away at idle rather than
	# coming down the slope.
	var want_kt: float = ref_speed_kt() * (1.08 if d > 900.0 else 1.0)
	# Thrust flies the path as well as the speed. On a heavy aeroplane the
	# elevator alone cannot buy a steeper descent while the autothrottle is busy
	# holding the speed it just lost: the two settle against each other and the
	# approach arrives high. Feeding the glide slope error into the throttle is
	# what actually brings it down, and it does nothing on an aircraft that is
	# already on slope.
	throttle = clampf(0.30 + (want_kt / 1.94384 - ias) * 0.045
		+ clampf(err, -80.0, 80.0) * 0.005, 0.0, 1.0)
	if flaring:
		# Closed at the very end rather than the moment the flare begins. A
		# fighter on approach is holding a lot of its weight on thrust; taking
		# it all away twenty-five metres up simply drops the aeroplane onto the
		# runway, and no amount of elevator inside an eleven degree clamp gets
		# it back. Idle below four metres, as you would.
		throttle = minf(throttle, 0.05 if p.y < 4.0 else 0.24)
