class_name ChaseCamera
extends Camera3D
## Chase / cockpit / orbit views with a bit of speed-driven FOV.

enum Mode { COCKPIT, CHASE, ORBIT }

var mode := Mode.COCKPIT
var subject: Aircraft = null
var orbit := Vector2(0.6, 0.3)
var orbit_dist := 45.0
var _pos := Vector3.ZERO
var _boom := Vector3.ZERO
var _aim := Vector3.ZERO
var _shake := 0.0
var free_yaw := 0.0
var free_pitch := 0.0
var _free := false
var pod_slew := false
var diag := false
var clamped_frames := 0
var weapon_cam: Node3D = null    # ride a round in flight
## How far across to the round the view has come, and what the draw distance
## was before it went out there.
var _wcam_blend := 1.0
var _wcam_far_was := 0.0
var _wcam_prev: Node3D = null
var _wcam_hold := 0.0
var _wcam_off := Vector3.ZERO
var _wcam_look := Vector3.FORWARD
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

func cycle() -> void:
	mode = ((mode + 1) % 3) as Mode
	_pos = Vector3.ZERO
	_boom = Vector3.ZERO
	_aim = Vector3.ZERO

func shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)

func _unhandled_input(e: InputEvent) -> void:
	if _free and not pod_slew and e is InputEventMouseMotion:
		var mm2 := e as InputEventMouseMotion
		free_yaw = clampf(free_yaw - mm2.relative.x * 0.0042, -2.7, 2.7)
		free_pitch = clampf(free_pitch - mm2.relative.y * 0.0042, -1.25, 1.25)
		return
	if mode == Mode.ORBIT and e is InputEventMouseMotion \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mm := e as InputEventMouseMotion
		orbit.x -= mm.relative.x * 0.006
		orbit.y = clampf(orbit.y + mm.relative.y * 0.006, -1.3, 1.3)
	if e is InputEventMouseButton and mode == Mode.ORBIT:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_dist = maxf(orbit_dist * 0.88, 12.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_dist = minf(orbit_dist * 1.14, 400.0)

func _process(delta: float) -> void:
	# Weapon cam: ride whatever was last let go, until it goes off.
	if weapon_cam != null:
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
			var wv := Vector3.FORWARD
			if "vel" in weapon_cam:
				wv = weapon_cam.get("vel")
			elif "linear_velocity" in weapon_cam:
				wv = weapon_cam.linear_velocity
			if wv.length() < 1.0:
				wv = -wxf.basis.z
			var wdir := wv.normalized()
			var want := wp - wdir * 22.0 + Vector3(0, 5.0, 0)
			want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 3.0)
			# Rigid on the round, eased on the boom. Lerping the world position
			# toward a target doing six hundred metres a second leaves a steady
			# state lag of v over the gain — about seventy metres — so the
			# camera never catches the round. Smoothing the offset instead keeps
			# the tracking exact while taking the steps out of the arm: the
			# direction of flight swings as the weapon guides, and the terrain
			# floor snaps as the ground comes up under it.
			var off := want - wp
			if _wcam_prev != weapon_cam:
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
			global_position = wp + _wcam_off
			var up_ref := Vector3.UP if absf(_wcam_look.y) < 0.985 else Vector3.FORWARD
			look_at(wp + _wcam_look * 40.0, up_ref)
			fov = lerpf(fov, 58.0, delta * 4.0)
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

	# hold ALT to look around; the view eases back to boresight on release
	var want_free := Input.is_action_pressed(&"freelook") and not pod_slew
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
	var free_b := Basis(Vector3.UP, free_yaw) * Basis(Vector3.RIGHT, free_pitch)

	match mode:
		Mode.COCKPIT:
			var seat := xf * subject.cockpit_offset()
			var head := xf.basis * free_b
			if look_back:
				head = head * Basis(Vector3.UP, PI)
			global_transform = Transform3D(head, seat)
			fov = lerpf(fov, 78.0, delta * 4.0)
		Mode.ORBIT:
			var c := xf.origin
			var off := Vector3(
				cos(orbit.x) * cos(orbit.y), sin(orbit.y), sin(orbit.x) * cos(orbit.y)) * orbit_dist
			global_position = c + off
			look_at(c, Vector3.UP)
			fov = lerpf(fov, 60.0, delta * 4.0)
		_:
			var back := 1.0 if not look_back else -1.0
			# The boom swings about a pivot on the aircraft itself, not about the
			# point the camera happens to be aimed at. Free look then reads as
			# walking round the jet rather than the whole rig slewing away.
			var pivot := xf.origin + xf.basis.y * 1.5
			var look_lead: float = clampf((absf(free_yaw) + absf(free_pitch)) / 0.35, 0.0, 1.0)
			var look_amt := look_lead
			# The boom is smoothed in the aircraft's own frame, not in world
			# space. Easing a world position makes the camera trail a fast jet by
			# metres, which stretches and squashes the orbit as you look around;
			# easing the local boom keeps the rig rigidly attached and still lags
			# naturally through a turn.
			var lead := (xf.basis.inverse() * subject.linear_velocity) * 0.010 * (1.0 - look_lead)
			var want_boom := free_b * Vector3(0, 2.9, 17.0 * back) + Vector3(0, 0, lead.z * -1.0)
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
			var lead_pt := pivot + (-xf.basis.z * back) * 40.0 + xf.basis.y * 0.5
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
			fov = lerpf(fov, 62.0 + clampf(speed * 0.055, 0.0, 22.0), delta * 3.0)
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
