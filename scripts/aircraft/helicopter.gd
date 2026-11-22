class_name Helicopter
extends Aircraft
## Rotary wing flight model. The main rotor makes thrust along the disc axis, so
## you fly it the way you fly a real helicopter: tilt the aircraft and the thrust
## vector goes with it. Collective is on the throttle, the tail rotor holds the
## nose, and translational lift makes it happier once it is moving.

const HOVER_MARGIN := 1.35        # thrust available over hover weight at full pull
## Heave damping, per second: see `_integrate_forces`.
const HEAVE_DAMP := 0.25
## The rate of turn full pedal asks for, radians a second, where a spec does not
## give its own `max_yaw_rate`: about seventy degrees.
const MAX_YAW_RATE := 1.2

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if ghost or not alive:
		return
	var xf := state.transform
	var b := xf.basis
	var pos := xf.origin
	var vel := state.linear_velocity
	var av := state.angular_velocity
	var speed := vel.length()
	var fwd := -b.z
	var up := b.y
	var right := b.x

	# the ground, or a bridge's deck if it is under the skids (see
	# `Aircraft._gear_forces`)
	var ground := maxf(Sim.height_at(pos.x, pos.z), Sim.roads.bridge_floor(pos.x, pos.z, pos.y))
	agl = pos.y - ground
	vspeed = vel.y
	var rho: float = RHO0 * exp(-maxf(pos.y, 0.0) / 8500.0)
	ias = speed * sqrt(rho / RHO0)
	mach = speed / 340.0
	var lv := b.inverse() * vel
	var vf := -lv.z
	if speed > 1.5:
		aoa = atan2(-lv.y, maxf(absf(vf), 1.0))
		beta = atan2(lv.x, maxf(absf(vf), 1.0))
	else:
		aoa = 0.0
		beta = 0.0

	# ---- rotor -----------------------------------------------------------
	power = move_toward(power, throttle if fuel > 0.0 else 0.0, state.step / spec["spool"])
	var hover: float = mass * 9.81
	# translational lift: the disc works better in clean air once you are moving
	var trans: float = 1.0 + 0.16 * clampf(vf / 26.0, 0.0, 1.0)
	# ground cushion
	var ge: float = 1.0 + 0.22 * clampf(1.0 - agl / maxf(spec["rotor_radius"] * 1.6, 1.0), 0.0, 1.0)
	var density: float = clampf(pow(rho / RHO0, 0.75), 0.25, 1.0)
	var thrust: float = hover * HOVER_MARGIN * power * trans * ge * density
	var burn: float = thrust * 0.000021 * state.step
	fuel = maxf(fuel - burn, 0.0)
	var force := up * thrust
	# Heave damping. A rotor disc resists being moved along its own axis: in a
	# climb the air comes through it from above and every blade sees less
	# angle, in a descent the other way. Without it the full collective
	# accelerated the machine upward without limit -- thirty-five metres a
	# second in eight -- and the height hold, fighting a body with nothing to
	# slow it but the rotor's spool lag, rode up and down before it settled.
	# Sized so full power over the hover climbs at about fourteen metres a
	# second.
	force -= up * vel.dot(up) * mass * HEAVE_DAMP * density

	# ---- airframe drag ---------------------------------------------------
	var q := 0.5 * rho * speed * speed
	if speed > 0.5:
		var vdir := vel / speed
		var cd: float = spec["cd0"] + 0.020 * gear_anim + (0.05 if airbrake else 0.0) + _pen_drag
		# a fuselage side-on is far draggier than nose-on
		cd += absf(beta) * 0.34 + absf(aoa) * 0.20
		force += -vdir * q * spec["wing_area"] * cd
		# the fin and stabiliser still do something at speed
		force += -right * q * spec["wing_area"] * 0.9 * beta
	g_load = force.dot(up) / (mass * 9.81)

	# ---- control ---------------------------------------------------------
	var qn: float = clampf(0.35 + q / 9000.0, 0.0, 1.3)
	var auth: float = maxf(qn, 0.55 * clampf(power, 0.15, 1.0))   # cyclic works in a hover
	var rr := av.dot(fwd)
	var pr := av.dot(right)
	var yr := av.dot(up)
	var p_cmd := in_pitch
	var r_cmd := in_roll
	var y_cmd := in_yaw
	if assist:
		# Rates, and nothing more: the stick asks for a rate of pitch and roll
		# and the system flies it. It used to hold the attitude inside 48
		# degrees of pitch and 72 of bank whatever the stick said, which made a
		# loop or a roll impossible -- the pilot who wants to go over the top
		# is allowed to. Let go and the rates go to zero: it holds whatever
		# attitude it is in, and it is the pilot's to recover.
		var want_pr: float = in_pitch * spec["max_pitch_rate"]
		var want_rr: float = in_roll * spec["max_roll_rate"]
		p_cmd = clampf((want_pr - pr) * 3.0, -1.0, 1.0)
		r_cmd = clampf((want_rr - rr) * 2.4, -1.0, 1.0)
		# The pedals command a rate of turn, as the cyclic commands rates of
		# pitch and roll. They were added to a yaw damper and a sideslip
		# loop, both of which opposed them: an Apache in the hover turned on
		# full pedal at sixteen degrees a second, and at speed the sideslip
		# term took most of what was left. Below translational speed the
		# sideslip angle is noise, so it fades in as you accelerate -- and out
		# again while a pedal is held, which is asking for the sideslip.
		var want_yr: float = -in_yaw * float(spec.get("max_yaw_rate", MAX_YAW_RATE))
		var beta_w: float = clampf((speed - 12.0) / 25.0, 0.0, 1.0) \
			* (1.0 - clampf(absf(in_yaw) * 1.5, 0.0, 1.0))
		y_cmd = clampf((yr - want_yr) * 2.5 + beta * 4.5 * beta_w, -1.0, 1.0)
	var torque := Vector3.ZERO
	torque += right * p_cmd * spec["pitch_torque"] * auth * _pen_pitch
	torque += fwd * r_cmd * spec["roll_torque"] * auth * _pen_roll_auth
	# The tail rotor is driven off the main rotor's gearbox and blows its own
	# air: it has its authority in the hover, where it was cut to half with
	# the cyclic's low-speed factor.
	torque += -up * y_cmd * spec["yaw_torque"]
	# main rotor torque reaction. With the stability system on, the tail rotor
	# trims it out automatically; switch the assist off and you hold the pedal.
	if not assist:
		torque += up * thrust * spec["rotor_radius"] * 0.011
	torque -= fwd * rr * spec["roll_damp"] * (qn + 0.35)
	torque -= right * pr * spec["pitch_damp"] * (qn + 0.35)
	torque -= up * yr * spec["yaw_damp"] * (qn + 0.35)
	# the fixed surfaces only bite once there is airflow over them -- along
	# them, from ahead: in a fast climb or descent the air comes up or down
	# through the disc and past the tail edge on, and taken as airflow it
	# pitched the nose twenty degrees on its own
	var aero_w: float = clampf((absf(vf) - 10.0) / 30.0, 0.0, 1.0)
	torque -= right * aoa * spec["pitch_stab"] * qn * aero_w
	torque += -up * beta * spec["yaw_stab"] * qn * aero_w

	# ---- undercarriage and impact ---------------------------------------
	var contacts := 0
	if gear_anim > 0.9:
		contacts = _gear_forces(state, force, torque, ground)
	on_ground = contacts > 0
	if _was_airborne and on_ground and _life_t > 1.2:
		_register_touchdown(vel, b)
	_was_airborne = not on_ground
	if agl < 1.0 and absf(b.y.dot(Vector3.UP)) < 0.68:
		_impact(vel.length())
	# The fixed wing model has this and the rotary one did not: an upright
	# helicopter that got below the terrain simply kept going, because the only
	# other crash test needed it to be banked past 47 degrees. Bandit gunships
	# were ending up 190 km underground, still reporting themselves alive.
	# Buildings, hangars, masts and pylons, as an aeroplane strikes them
	# (`Aircraft._integrate_forces`): the rotary model had its own copy of the
	# rest of the crash tests and not this one, so a helicopter flew through
	# the town. Taken at the rotor's reach, which is what hits first.
	if alive and agl < OBSTACLE_CEILING:
		var reach: float = float(spec.get("rotor_radius", 6.0)) * 0.85
		var struck := Obstacles.hit(pos, reach)
		if struck >= 0:
			var sc := Scenery.current
			if is_instance_valid(sc):
				sc.damage_area(Obstacles.centre_of(struck), maxf(reach, 8.0))
			_impact(maxf(vel.length(), 30.0))
	if agl < -2.0:
		_impact(200.0)
	_midair(pos, vel)
	var sea_h: float = Sim.sea_at(pos.x, pos.z)
	if pos.y < sea_h and ground < sea_h:
		_impact(200.0)

	state.apply_central_force(force)
	state.apply_torque(torque)
