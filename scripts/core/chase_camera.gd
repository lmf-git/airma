class_name ChaseCamera
extends Camera3D
## Chase / cockpit / orbit views with a bit of speed-driven FOV.

enum Mode { COCKPIT, CHASE, ORBIT }

var mode := Mode.COCKPIT
var subject: Aircraft = null
var orbit := Vector2(0.6, 0.3)
var orbit_dist := 45.0
var _pos := Vector3.ZERO
## How much bigger than a fighter the subject is. The boom was a fixed seventeen
## metres back and three up whatever was on the end of it, which frames an F-16
## and puts the camera inside the tailplane of a Hercules, under the wing of a
## B-2. Worked out from the airframe's own extents, once per subject.
const REF_SIZE := 16.0
var orbit_fixed := false
var _scaled_for: Aircraft = null
var _size_k := 1.0

func size_scale() -> float:
	if subject != _scaled_for:
		_scaled_for = subject
		_size_k = 1.0
		if is_instance_valid(subject):
			var b: AABB = subject.bounds
			var span: float = maxf(b.size.x, b.size.z)
			_size_k = clampf(span / REF_SIZE, 1.0, 5.0)
		# the orbit starts as far out as the aeroplane needs, too -- unless a
		# distance was asked for outright
		if not orbit_fixed:
			orbit_dist = 45.0 * _size_k
	return _size_k
var _boom := Vector3.ZERO
var _aim := Vector3.ZERO
var _shake := 0.0
var free_yaw := 0.0
var free_pitch := 0.0
var _free := false
var pod_slew := false
var diag := false
var clamped_frames := 0
var weapon_cam: Node3D = null:   # ride a round in flight
	set(v):
		weapon_cam = v
		_wcam_live = v != null
## Set while a ride is on, including the frames between the round going off and
## this camera noticing and starting to hold on the spot. Without it there was
## a frame in which nothing was being ridden and nothing held, and whoever was
## waiting for the ride to end took the screen back before the impact.
var _wcam_live := false
## How far across to the round the view has come, and what the draw distance
## was before it went out there.
var _wcam_blend := 1.0
var _wcam_far_was := 0.0
var _wcam_prev: Node3D = null
var _wcam_hold := 0.0
var _wcam_off := Vector3.ZERO
var _wcam_look := Vector3.FORWARD
var _wcam_side := Vector3.ZERO
var _wcam_up := Vector3.ZERO
var _wcam_diag := Vector3.ZERO
var wcam_jitter := 0.0        # worst frame-to-frame boom wobble, metres
var wcam_jsum := 0.0
var wcam_jn := 0
var _up_smooth := Vector3.ZERO
var _roll_now := Vector3.UP
var _roll_prev := Vector3.ZERO
var worst_roll := 0.0
var worst_roll_t := 0.0
var _diag_t := 0.0
var last_diag := {}
var _mouse_was := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	# The camera is positioned every render frame from the interpolated subject
	# transform, so it must not be interpolated itself — otherwise it lags the
	# thing it is following by up to one physics tick and the jet judders.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	current = true
	far = 45000.0
	near = 0.25
	fov = 65.0

## Held on the right mouse button: the view narrows to a third, the way a
## pilot leans in to look at something.
var zoom := false

func _zoom_mul() -> float:
	return 0.32 if zoom else 1.0

func cycle() -> void:
	mode = ((mode + 1) % 3) as Mode
	_pos = Vector3.ZERO
	_boom = Vector3.ZERO
	_aim = Vector3.ZERO

## On a round, or holding on where the last one went off.
## How far off a ridden round the camera stands, on the mouse wheel: 1 is
## what it would choose for itself.
var ride_zoom := 1.0
var _ride_s := 1.0

func riding() -> bool:
	return _wcam_live or _wcam_hold > 0.0

func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)

func _unhandled_input(e: InputEvent) -> void:
	if _free and not pod_slew and e is InputEventMouseMotion:
		var mm2 := Sim.mouse_rel(e as InputEventMouseMotion)
		free_yaw = clampf(free_yaw - mm2.x * 0.0042, -2.7, 2.7)
		free_pitch = clampf(free_pitch - mm2.y * 0.0042, -1.25, 1.25)
		return
	if mode == Mode.ORBIT and e is InputEventMouseMotion \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm := e as InputEventMouseMotion
		orbit.x -= mm.relative.x * 0.006
		orbit.y = clampf(orbit.y + mm.relative.y * 0.006, -1.3, 1.3)
	if e is InputEventMouseButton and weapon_cam != null and (e as InputEventMouseButton).pressed:
		var wb := e as InputEventMouseButton
		if wb.button_index == MOUSE_BUTTON_WHEEL_UP:
			ride_zoom = maxf(ride_zoom * 0.87, 0.35)
		elif wb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			ride_zoom = minf(ride_zoom * 1.15, 14.0)
	if e is InputEventMouseButton and mode == Mode.ORBIT:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = maxf(orbit_dist * 0.88, 12.0 * size_scale())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = minf(orbit_dist * 1.14, 400.0 * size_scale())

## Hold ALT to look around; the view eases back to boresight on release.
## Not while a screen that wants the pointer is up: see `Sim.ui_pointer`.
## Returns the head turn, yaw then pitch.
func _free_look(delta: float) -> Basis:
	var want_free := Input.is_action_pressed(&"freelook") and not pod_slew \
		and not Sim.ui_pointer
	if want_free != _free:
		_free = want_free
		if _free:
			_mouse_was = Input.mouse_mode
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = _mouse_was
	if not _free:
		var back_k := 1.0 - exp(-7.0 * delta)
		free_yaw = lerpf(free_yaw, 0.0, back_k)
		free_pitch = lerpf(free_pitch, 0.0, back_k)
	return Basis(Vector3.UP, free_yaw) * Basis(Vector3.RIGHT, free_pitch)

## A reference direction kept square to `axis` and eased toward `target` only
## as far as `target` means anything. Square to the axis `target` has a length
## of the sine of the angle between them: near zero it is noise, so the held
## direction is simply carried along; well clear of it the held one is turned
## toward it about the axis, which cannot pass through nothing the way a blend
## of two opposed vectors does.
func _carry(held: Vector3, axis: Vector3, target: Vector3, delta: float) -> Vector3:
	var h := held - axis * held.dot(axis)
	var t := target - axis * target.dot(axis)
	var tl := t.length()
	if h.length() < 0.001:
		if tl > 0.001:
			return t / tl
		h = axis.cross(Vector3.RIGHT)
		if h.length() < 0.01:
			h = axis.cross(Vector3.FORWARD)
		return h.normalized()
	h = h.normalized()
	var w := smoothstep(0.10, 0.42, tl)
	if w <= 0.0:
		return h
	var ang := h.signed_angle_to(t / tl, axis)
	return h.rotated(axis, ang * clampf(delta * 3.0 * w, 0.0, 1.0)).normalized()

func _process(delta: float) -> void:
	# Weapon cam: ride whatever was last let go, until it goes off.
	#
	# Asked of the ride, not of the round. A round that has gone off is a freed
	# object, and a freed object reads as null -- so "is there a round" said no
	# the instant it burst, the branch below that holds on the impact never
	# ran, and the view snapped straight back to the aeroplane on the frame
	# the explosion it was there to watch began.
	if _wcam_live or weapon_cam != null:
		if not is_instance_valid(weapon_cam):
			# hold on the impact for a moment rather than snapping back the
			# instant the round frees itself: the explosion is the bit worth
			# watching and it happens on the frame the node goes away
			weapon_cam = null
			_wcam_hold = 1.6
			if _wcam_far_was > 0.0:
				far = _wcam_far_was
				_wcam_far_was = 0.0
		else:
			# The interpolated pose, not the raw one. A round is moved once per
			# physics tick; its mesh is then interpolated to the render frame,
			# but `global_position` still reads the stepped value. Riding the
			# stepped value while looking at the interpolated mesh is exactly
			# one tick of relative motion every frame, which is the judder.
			var wxf := weapon_cam.get_global_transform_interpolated()
			var wp: Vector3 = wxf.origin
			# Sized to what is being ridden. The boom was twenty metres for
			# everything, which is right for a missile four metres long and
			# inside the smoke of one twenty-two: an intercontinental round
			# filled the frame from nose to nozzle and the view pivoted about
			# the middle of a stack most of which had already been dropped.
			var rs: float = ride_zoom
			if weapon_cam.has_method("ride_scale"):
				rs *= float(weapon_cam.call("ride_scale"))
			if weapon_cam.has_method("ride_centre"):
				wp = wxf * (weapon_cam.call("ride_centre") as Vector3)
			_ride_s = lerpf(_ride_s, rs, clampf(delta * 2.0, 0.0, 1.0))
			rs = _ride_s
			var wv := Vector3.FORWARD
			if "vel" in weapon_cam:
				wv = weapon_cam.get("vel")
			elif "linear_velocity" in weapon_cam:
				wv = weapon_cam.linear_velocity
			if wv.length() < 1.0:
				wv = -wxf.basis.z
			var wdir := wv.normalized()
			# Off the centreline, not straight up the tailpipe.
			#
			# Directly astern the motor is between the camera and the round, so
			# what you watch is the plume: a rocket a metre and a half long with
			# a burning throat behind it reads as a glowing ball and nothing
			# else, however far back the boom is set. Stood off to one side and
			# a little above, the body is in profile with the flame behind it.
			#
			# Which side is carried, not worked out afresh. "Across the flight
			# and level" is flight crossed with up, and a round going straight
			# up has no such direction: the cross product is the size of the
			# wobble in its heading, so normalising it swung the boom anywhere
			# round the round from one frame to the next, and at pitch-over it
			# landed wherever the answer finally settled. A ballistic launch
			# spends its first seconds exactly there. Up is the planet's, too:
			# five thousand kilometres down range it is not the y axis.
			var fresh := _wcam_prev != weapon_cam
			var u := Sim.up_at(wp)
			if fresh or _wcam_side == Vector3.ZERO:
				_wcam_side = global_transform.basis.x
				_wcam_up = global_transform.basis.y
			_wcam_side = _carry(_wcam_side, wdir, wdir.cross(u), delta)
			var side := _wcam_side
			var want := wp - wdir * 20.0 * rs + side * 7.5 * rs + u * 5.5 * rs
			want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 3.0)
			# Rigid on the round, eased on the boom. Lerping the world position
			# toward a target doing six hundred metres a second leaves a steady
			# state lag of v over the gain — about seventy metres — so the
			# camera never catches the round. Smoothing the offset instead keeps
			# the tracking exact while taking the steps out of the arm: the
			# direction of flight swings as the weapon guides, and the terrain
			# floor snaps as the ground comes up under it.
			var off := want - wp
			if fresh:
				# Come across to the round rather than cutting to it. Snapping
				# the pose the instant a store is released throws the view
				# sideways and spins it round to the new heading in one frame,
				# which reads as the camera being knocked rather than as
				# following the shot away.
				_wcam_off = global_position - wp
				_wcam_look = (-global_transform.basis.z).normalized()
				_wcam_blend = 0.0
				# A hypersonic is twenty kilometres up and a hundred down range
				# within the minute; the aeroplane's horizon is not enough to
				# see where it is going.
				_wcam_far_was = far
				far = 240000.0
			if _wcam_blend < 1.0:
				_wcam_blend = minf(_wcam_blend + delta * 3.0, 1.0)
				var e: float = _wcam_blend * _wcam_blend * (3.0 - 2.0 * _wcam_blend)
				_wcam_off = _wcam_off.lerp(off, e)
				_wcam_look = _wcam_look.slerp(wdir, e).normalized()
			else:
				var k: float = clampf(delta * 7.0, 0.0, 1.0)
				_wcam_off = _wcam_off.lerp(off, k)
				_wcam_look = _wcam_look.slerp(wdir, k).normalized()
			_wcam_prev = weapon_cam
			# Free look rides with it: ALT swings the view round the round --
			# the boom and the line of sight together, about the round itself
			# -- so you can look back at the launcher, down at the target or
			# across at the rest of the load, and it eases back when let go.
			# The ride used to return before free look was ever read.
			_free_look(delta)
			# Which way up the picture is, for the view as it would be with
			# nobody looking round. This switched reference from the sky to
			# north at ten degrees off the vertical, which is a roll of
			# anything up to half a turn in one frame -- on the way up off the
			# launcher, and again on the way down onto the mark.
			_wcam_up = _carry(_wcam_up, _wcam_look, u, delta)
			# Looking round turns the whole view about the round, in the
			# view's own frame: left and right about the picture's own up,
			# up and down about its own across.
			#
			# It turned left and right about the PLANET'S up instead, and kept
			# the picture's up where it was while the camera went round. For a
			# round going along the ground those are the same thing. For one
			# going straight up -- every ballistic launch, for its first
			# minute -- the planet's up is the line of flight: turning about
			# it moved the camera round the round without turning the view at
			# all, so the round swung in a circle round the screen about a
			# point in empty sky, and the mouse seemed to spin the world.
			var turn := Basis.IDENTITY
			var looking: float = clampf((absf(free_yaw) + absf(free_pitch)) / 0.25, 0.0, 1.0)
			if looking > 0.002:
				var across := _wcam_look.cross(_wcam_up)
				if across.length_squared() < 0.0001:
					across = _wcam_side
				turn = Basis(_wcam_up.normalized(), free_yaw) \
					* Basis(across.normalized(), free_pitch)
			var look: Vector3 = (turn * _wcam_look).normalized()
			global_position = wp + turn * _wcam_off
			# ...and what it turns about is the round. Left looking at a point
			# well ahead of it, a look to one side put the round at the edge
			# of the picture and a look back put it behind the lens.
			var ahead: float = (40.0 if rs < 1.3 else 14.0 * rs) * (1.0 - looking)
			var aim: Vector3 = wp + look * ahead
			if aim.distance_to(global_position) < 0.5:
				aim = global_position + look
			look_at(aim, (turn * _wcam_up).normalized())
			fov = lerpf(fov, (58.0) * _zoom_mul(), delta * 4.0)
			if diag:
				var d := global_position - wp
				if _wcam_diag != Vector3.ZERO:
					wcam_jitter = maxf(wcam_jitter, (d - _wcam_diag).length())
					wcam_jsum += (d - _wcam_diag).length()
					wcam_jn += 1
				_wcam_diag = d
			return
	if _wcam_hold > 0.0:
		_wcam_hold -= delta
		if _wcam_hold > 0.0:
			return
	if subject == null or not is_instance_valid(subject):
		return
	var xf := subject.get_global_transform_interpolated()
	var speed := subject.linear_velocity.length()
	_shake = maxf(_shake - delta * 1.6, 0.0)
	var buffet := 0.55 if subject.stalling else 0.0
	var look_back := Input.is_action_pressed(&"look_back")

	var free_b := _free_look(delta)

	match mode:
		Mode.COCKPIT:
			var seat := xf * subject.cockpit_offset()
			var head := xf.basis * free_b
			if look_back:
				head = head * Basis(Vector3.UP, PI)
			global_transform = Transform3D(head, seat)
			fov = lerpf(fov, (78.0) * _zoom_mul(), delta * 4.0)
		Mode.ORBIT:
			size_scale()
			var c := xf.origin
			var off := Vector3(
				cos(orbit.x) * cos(orbit.y), sin(orbit.y), sin(orbit.x) * cos(orbit.y)) * orbit_dist
			global_position = c + off
			look_at(c, Vector3.UP)
			fov = lerpf(fov, (60.0) * _zoom_mul(), delta * 4.0)
		_:
			var back := 1.0 if not look_back else -1.0
			# The boom swings about a pivot on the aircraft itself, not about the
			# point the camera happens to be aimed at. Free look then reads as
			# walking round the jet rather than the whole rig slewing away.
			var k_size := size_scale()
			var pivot := xf.origin + xf.basis.y * 1.5 * k_size
			var look_lead: float = clampf((absf(free_yaw) + absf(free_pitch)) / 0.35, 0.0, 1.0)
			var look_amt := look_lead
			# The boom is smoothed in the aircraft's own frame, not in world
			# space. Easing a world position makes the camera trail a fast jet by
			# metres, which stretches and squashes the orbit as you look around;
			# easing the local boom keeps the rig rigidly attached and still lags
			# naturally through a turn.
			var lead := (xf.basis.inverse() * subject.linear_velocity) * 0.010 * (1.0 - look_lead)
			var want_boom := free_b * Vector3(0, 2.9 * k_size, 17.0 * k_size * back) \
				+ Vector3(0, 0, lead.z * -1.0)
			var rate: float = lerpf(6.0, 22.0, look_amt)
			var k := 1.0 - exp(-rate * delta)
			_boom = _boom.lerp(want_boom, k) if _boom != Vector3.ZERO else want_boom
			var want := pivot + xf.basis * _boom
			var ground := Sim.height_at(want.x, want.z) + 3.0
			if want.y < ground:
				want.y = ground
				if diag:
					clamped_frames += 1
			global_position = want
			_pos = want
			# Normally the view leads the nose; as soon as you look around it
			# locks onto the aircraft so it stays centred while you orbit.
			var lead_pt := pivot + (-xf.basis.z * back) * 40.0 * k_size + xf.basis.y * 0.5
			var aim: Vector3 = lead_pt.lerp(pivot, look_amt)
			if look_amt > 0.99:
				_aim = aim
			else:
				_aim = _aim.lerp(aim, 1.0 - exp(-11.0 * delta)) if _aim != Vector3.ZERO else aim
			# Roll reference. Straight-line lerping the airframe up toward world
			# up collapses near inverted flight -- the two are nearly opposite,
			# the blend shrinks to a tenth of a unit, and whatever sideways
			# component survives then decides the camera roll. That is the jolt:
			# a hard manoeuvre through the vertical would swing the horizon
			# round. Blend the two by ANGLE in the plane across the view
			# instead, which stays unit length whatever the aircraft is doing.
			var fwd := (_aim - global_position)
			if fwd.length_squared() < 1e-6:
				fwd = -xf.basis.z
			fwd = fwd.normalized()
			var a_up := xf.basis.y - fwd * xf.basis.y.dot(fwd)
			var w_up := Vector3.UP - fwd * Vector3.UP.dot(fwd)
			var up: Vector3
			if a_up.length() < 0.02:
				up = -xf.basis.z          # looking along the airframe up axis
			elif w_up.length() < 0.02:
				up = a_up.normalized()    # looking straight up or down the world
			else:
				a_up = a_up.normalized()
				w_up = w_up.normalized()
				# How much to level the horizon. Fade it out as the aircraft
				# rolls past knife edge: "55% of the way to world up" has no
				# continuous answer once the airframe up is pointing down, and
				# trying to compute one flips the camera 161 degrees in a single
				# frame every time the jet goes over the top. Inverted, the rig
				# simply rides the airframe, which is always well defined.
				var level: float = 0.55 * clampf(xf.basis.y.dot(Vector3.UP) * 1.6,
					0.0, 1.0)
				var ang := a_up.angle_to(w_up)
				var axis := a_up.cross(w_up)
				if level < 0.001 or ang < 0.001 or axis.length() < 0.02:
					up = a_up
				else:
					up = a_up.rotated(axis.normalized(), ang * level)
			# Whatever the reference does, the rig may only roll so fast. The
			# cases above switch between an airframe reference and a levelled
			# one, and a switch is a step however carefully it is chosen; this
			# turns any step into a short sweep the eye reads as camera motion.
			const ROLL_RATE := deg_to_rad(200.0)
			if _up_smooth == Vector3.ZERO:
				_up_smooth = up
			else:
				var step := _up_smooth.angle_to(up)
				if step > 0.0001:
					var lim: float = minf(step, ROLL_RATE * delta)
					var ax := _up_smooth.cross(up)
					if ax.length() > 1e-5:
						_up_smooth = _up_smooth.rotated(ax.normalized(), lim)
					else:
						_up_smooth = up
			up = _up_smooth
			look_at(_aim, up)
			_roll_now = up
			fov = lerpf(fov, (62.0 + clampf(speed * 0.055, 0.0, 22.0)) * _zoom_mul(), delta * 3.0)
			if diag:
				_diag_t += delta
				if _roll_prev != Vector3.ZERO:
					var step := rad_to_deg(_roll_prev.angle_to(_roll_now))
					if step > worst_roll:
						worst_roll = step
						worst_roll_t = _diag_t
				_roll_prev = _roll_now
			if diag:
				var to_jet := pivot - global_position
				last_diag = {"boom": to_jet.length(),
					"off": rad_to_deg((-global_transform.basis.z).angle_to(to_jet)),
					"yaw": rad_to_deg(free_yaw), "pitch": rad_to_deg(free_pitch)}

	if _shake > 0.01 or buffet > 0.01:
		var a := (_shake + buffet * 0.25) * 0.6
		rotate_object_local(Vector3.RIGHT, randf_range(-a, a) * 0.02)
		rotate_object_local(Vector3.UP, randf_range(-a, a) * 0.02)
