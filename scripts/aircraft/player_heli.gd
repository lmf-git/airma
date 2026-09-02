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
## Where the harness is holding the collective, or INF when a person has it.
var lever := INF
## True while the collective is off centre, so the hold knows when it has just
## been handed the aircraft.
var _coll_held := false
## How much of the climb still in the machine counts toward the height it will
## settle at: about the time the collective takes to arrest it.
const COLL_LEAD := 1.15
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
	if Sim.tapped(&"mouse_fly"):
		mouse_fly = not mouse_fly
		_mouse = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_fly else Input.MOUSE_MODE_VISIBLE
	var kp := Sim.strength(&"pitch_up") - Sim.strength(&"pitch_down")
	var kr := Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	var target_stick := Vector2(kr, kp)
	if mouse_fly:
		target_stick = Vector2(clampf(_mouse.x + kr, -1, 1), clampf(-_mouse.y + kp, -1, 1))
		_mouse = _mouse.lerp(Vector2.ZERO, delta * 0.9)
	stick = stick.lerp(target_stick, clampf(delta * 8.0, 0.0, 1.0))
	in_roll = stick.x
	in_pitch = stick.y
	in_yaw = Sim.strength(&"yaw_right") - Sim.strength(&"yaw_left")
	# The hover has the cyclic, the pedals and the lever until the pilot takes
	# them back — which is any real input on any of them. It does NOT take the
	# rest of the cockpit: you can still work the weapons and the gear while it
	# holds the machine still, which is most of the point of having it.
	if hover_hold:
		var kt: float = Sim.strength(&"throttle_up") - Sim.strength(&"throttle_down")
		if absf(in_pitch) > 0.15 or absf(in_roll) > 0.15 \
				or absf(in_yaw) > 0.15 or absf(kt) > 0.01:
			set_hover_hold(false)
		else:
			fly_hover(delta)
	# Collective. With the stability system in, the lever commands a rate of
	# climb and centring it holds the height you have -- a helicopter that
	# wanders up and down whenever you take your hand off it is not flyable.
	# Switch the assist off and it goes back to being raw engine power.
	# The collective lever, or whatever the harness is holding it at.
	#
	# A headless session reports the shift key as held from the moment it
	# starts, so a test that drives the lever through the input map is really
	# measuring the operating system: `--helitest` read the lever hard up for
	# the whole of its "hands off" window and has never once measured the
	# altitude hold it exists to measure.
	var t: float = lever if is_finite(lever) \
		else Sim.strength(&"throttle_up") - Sim.strength(&"throttle_down")
	if hover_hold:
		# the hover already set the collective; the height hold below would
		# only fight it
		pass
	elif assist and not on_ground:
		if absf(t) > 0.01:
			_coll_held = true
			_collective(t * 6.0, delta)
		else:
			if _coll_held:
				# Centring the lever holds the height the machine is going to
				# reach, not the one it happens to be passing through.
				#
				# Grabbing the current altitude on release means the loop is
				# instantly six metres a second fast at a target it has already
				# left behind: it chops the collective to arrest the climb,
				# overshoots the other way, and the trim it wound up during the
				# climb takes seconds to come back out. Measured, an Apache let
				# go after an eight second climb sank seventeen metres through
				# the height it was at before settling -- which is what dropping
				# when you release the lever feels like. Leading the target out
				# by the climb it still has in it gives the loop nothing to
				# fight, and it settles where the lever left it.
				_coll_held = false
				hold_alt = global_position.y + linear_velocity.y * COLL_LEAD
			_collective(clampf((hold_alt - global_position.y) * 1.10, -6.0, 6.0), delta)
	else:
		_coll_held = false
		hold_alt = global_position.y
		_coll_trim = throttle
		throttle = clampf(throttle + t * delta * 0.7, 0.0, 1.0)
	wheel_brake = Sim.held(&"brakes") and on_ground

	if Sim.tapped(&"gear"):
		toggle_gear()
	if Sim.tapped(&"cycle_weapon"):
		cycle_weapon()
	for i in 8:
		if Sim.tapped(StringName("weapon_%d" % (i + 1))) and i < weapon_types.size():
			set_weapon(i)
	if Sim.tapped(&"cycle_target") \
			and not (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
		cycle_target()
	if Sim.tapped(&"chaff"):
		drop_chaff()
	if Sim.tapped(&"flare"):
		drop_flare()
	if (Sim.held(&"gun") or Sim.held(&"fire")) and current_weapon() == "gun" \
			and not Sim.ui_modal:
		fire_gun(get_tree().current_scene)
	if Sim.tapped(&"fire") and not Sim.ui_modal:
		if current_weapon() == "gun":
			pass                          # held above, for as long as it is held
		else:
			var r := fire()
			if r != "":
				say(r)

# --------------------------------------------------------------------------
## Auto hover: hold this spot, this height and wings level, hands off.
##
## The hover the machine had was a proportional-integral loop on vertical speed
## inside a proportional loop on height. It held a NUMBER — it did not hold the
## aircraft. Attitude was not in it anywhere, so a helicopter that had been
## tipped over stayed tipped over and accelerated away from where you left it,
## and there was no derivative term anywhere so what it did hold, it hunted.
##
## This is the proper cascade, which is how a real stability augmentation works:
##
##   drift  ->  attitude demand  ->  cyclic
##   height ->  vertical speed   ->  collective
##   heading ->                      pedal
##
## The outer loops are slow and the inner ones fast, so they do not fight.
var hover_hold := false
var _hover_at := Vector3.ZERO
var _hover_hdg := 0.0

# Outer: where we are against where we want to be, giving a speed to fly.
var _pid_pos_x := Pid.new(0.32, 0.010, 0.05, 0.25, 6.0)
var _pid_pos_z := Pid.new(0.32, 0.010, 0.05, 0.25, 6.0)
var _pid_alt := Pid.new(0.60, 0.020, 0.10, 0.60, 6.0)
# Inner: the speed error turned into an attitude to fly, and the attitude error
# turned into stick. Both clamped hard — a hover is small angles.
var _pid_vx := Pid.new(0.055, 0.004, 0.012, 0.10, 0.35)
var _pid_vz := Pid.new(0.055, 0.004, 0.012, 0.10, 0.35)
var _pid_att_p := Pid.new(2.6, 0.05, 0.30, 0.20, 1.0)
var _pid_att_r := Pid.new(2.6, 0.05, 0.30, 0.20, 1.0)
var _pid_yaw := Pid.new(1.6, 0.02, 0.18, 0.15, 1.0)
var _pid_vs := Pid.new(0.075, 0.030, 0.010, 0.45, 1.0)

func set_hover_hold(on: bool) -> void:
	hover_hold = on
	for c in [_pid_pos_x, _pid_pos_z, _pid_alt, _pid_vx, _pid_vz,
			_pid_att_p, _pid_att_r, _pid_yaw, _pid_vs]:
		(c as Pid).reset()
	if on:
		_hover_at = global_position
		_hover_hdg = global_rotation.y
		_coll_trim = throttle
		say("auto hover — holding this spot at %d ft" % int(global_position.y * 3.28084))
	else:
		say("auto hover off")

func toggle_hover_hold() -> void:
	set_hover_hold(not hover_hold)

## Fly it. Sets the same four controls a pilot has, so the flight model and the
## stability augmentation underneath are untouched.
func fly_hover(delta: float) -> void:
	if not hover_hold or not alive:
		return
	var b := global_transform.basis
	# Worked in the aircraft's own flattened axes, taken straight off the basis.
	# The first cut of this built the frame by hand out of sines and cosines and
	# got the forward axis inverted, which is why it would arrest the drift
	# neatly and then sit thirty-five metres downwind of the spot with a
	# standing seven degrees of bank on: the position loop was pushing the wrong
	# way and the velocity loop was holding it there.
	var fwd := -b.z
	var rgt := b.x
	fwd.y = 0.0
	rgt.y = 0.0
	if fwd.length_squared() < 0.01 or rgt.length_squared() < 0.01:
		return                        # pointed straight up or down; nothing to do
	fwd = fwd.normalized()
	rgt = rgt.normalized()
	var off: Vector3 = global_position - _hover_at
	var v := linear_velocity
	var ahead: float = off.dot(fwd)      # positive: in front of the spot
	var starboard: float = off.dot(rgt)  # positive: right of the spot
	var v_ahead: float = v.dot(fwd)
	var v_stbd: float = v.dot(rgt)

	# --- outer: being in front of the spot asks for a speed backwards
	var want_v_ahead: float = -_pid_pos_z.step(ahead, delta)
	var want_v_stbd: float = -_pid_pos_x.step(starboard, delta)

	# --- middle: the speed we are short by asks for an attitude. A helicopter
	# accelerates the way the disc is tilted: NOSE DOWN to go forward, so
	# wanting more forward speed is a negative pitch attitude. Wanting to go
	# right is a positive bank.
	var want_pitch: float = -_pid_vz.step(want_v_ahead - v_ahead, delta)
	var want_roll: float = _pid_vx.step(want_v_stbd - v_stbd, delta)

	# --- inner: attitude error works the cyclic
	var pitch_att: float = asin(clampf(-b.z.y, -1.0, 1.0))
	var bank: float = atan2(-b.x.y, b.y.y)
	in_pitch = _pid_att_p.step(want_pitch - pitch_att, delta)
	in_roll = _pid_att_r.step(want_roll - bank, delta)

	# --- heading, on the pedals
	in_yaw = _pid_yaw.step(wrapf(_hover_hdg - global_rotation.y, -PI, PI), delta)

	# --- height, through the collective
	var want_vs: float = _pid_alt.step(_hover_at.y - global_position.y, delta)
	_coll_trim = clampf(_coll_trim + (want_vs - v.y) * delta * 0.045, 0.0, 1.0)
	throttle = clampf(_coll_trim + _pid_vs.step(want_vs - v.y, delta), 0.0, 1.0)

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

func say(t: String) -> void:
	msg = t
	msg_t = 3.2


## Scripted rotary pilot: hold a height and a heading, used by the harness.
func _auto_pilot(_delta: float) -> void:
	# "wait" is not a flight mode. It is what the world sets while the pilot is
	# still walking out to the aircraft and climbing into it, and the fixed wing
	# side has always understood it. This did not: any value of `auto` at all
	# fell straight through to the hover hold, so a helicopter on the pad lifted
	# off and climbed away to a hundred and twenty metres while its pilot was
	# still on the ladder.
	if auto == "wait":
		throttle = 0.0
		in_pitch = 0.0
		in_roll = 0.0
		in_yaw = 0.0
		wheel_brake = true
		return
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
