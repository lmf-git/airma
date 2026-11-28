class_name SatView
extends Camera3D
## The planet from a satellite: a camera hung over a point on the ground, from
## a few hundred metres up to past the moon's side of geostationary, that
## pans across the surface and winds in and out. The map is a painted sheet; this
## is the world itself -- the body from orbit, the ground as it is built when
## low -- with nothing to fly.
##
## F4 in and out. While it is up the controls are let go of (`Sim.spectating`):
## whatever you were in carries on without you.
##
## Kept as a point on the planet and a height, not as a position: the chart the
## world is numbered in moves under it (it is the chart's subject while it is
## up -- see `ChartFollow._chart_subject`), and a position would be left behind.

const ALT_LO := 150.0
const ALT_HI := 60_000_000.0
## Past this height the eye is not taken any further out: the planet, its air
## and its cloud are drawn smaller instead, by exactly as much as makes them
## look as they would from the real height (`Sim.view_scale`, which the
## spacecraft use the same way). Single precision at sixty thousand
## kilometres is metres, and a far plane that deep is past what the shadow
## culler can take; at this height neither is a problem.
const VIEW_CAP := 8_000_000.0
## Below this the ground follows the eye as usual; above it, while the view
## has a place to hold on, the ground is built at that place (see
## `World._sat_focus`).
const FOCUS_BELOW := 20_000.0
## The hangar's backdrop: the planet whole, turning slowly, off to the side of
## the menu panel; and, once a place is picked, held over it.
const MENU_ALT := 22_000_000.0
const MENU_FOCUS_ALT := 12_000_000.0
const MENU_SPIN := 0.035
const MENU_GLIDE := 3.5
## The share of the screen's half width the planet is moved right by.
const MENU_SHIFT := 0.5
const TILT_MAX := 1.25
## H in the view: the air, the cloud deck and the haze taken away, so the
## ground reads like a survey photograph rather than through thirty kilometres
## of blue. Kept between visits.
static var clear_air := false
## Whether a match opens with the view coming down out of orbit onto it (see
## `WorldControls.match_intro`). Off for a run started from the command line,
## unless it asks for it with --intro.
static var intro_on := true

## The point looked at, as a direction from the planet's centre.
var dir := Vector3.UP
## Height of the eye over that point, along the line of sight.
var alt := 600_000.0
## The place the view is holding on or coming down to, as a direction from the
## planet's centre; zero when there is none. The ground there is built ahead of
## the view, and the planet bakes its fine picture for it.
var focus_dir := Vector3.ZERO
## Which way the top of the screen faces: 0 is north.
var heading := 0.0
## Off the vertical: 0 looks straight down.
var tilt := 0.0

var _was_cam: Camera3D = null
var _was_mouse := Input.MOUSE_MODE_VISIBLE
var _was_hud := true
var _pan_drag := false
var _turn_drag := false
var _label: Label = null
var _alt_s := 600_000.0
var _hud: CanvasItem = null
## How long since the view last moved, for `settled`.
var _still_t := 0.0
var _was_dir := Vector3.ZERO
var _was_alt := 0.0

## The way into a match: see `descend`.
const INTRO_FROM := 6_500_000.0
const INTRO_SECS := 6.5
## The share of it spent coming down; the rest is the hand-over to the camera.
const DESCENT_END := 0.82
var _intro := false
var _intro_t := 0.0
var _intro_len := INTRO_SECS
var _intro_alt_from := INTRO_FROM
var _intro_alt_to := 60.0
var _intro_tilt_to := 0.0
var _intro_cam: Camera3D = null
var _intro_fov := 50.0
var _intro_done := Callable()
var _intro_dir_from := Vector3.ZERO
var _intro_head_from := 0.0
var _intro_head_to := 0.0
var _intro_to := Vector3.ZERO
## Where the place is from the camera being come down to: kept, so a camera
## that moves on the way (an aeroplane in the air) is followed down.
var _intro_off := Vector3.ZERO
var _intro_follow: Node3D = null
## How far over the ground the thing being come down to is: an aeroplane in
## the air, not the field under it.
var _lift := 0.0
## The point being come down to, in the world's own coordinates. Low down the
## view is placed from this and not from a direction off the planet's centre:
## six thousand kilometres out, single precision is good to about a metre, and
## a view a few tens of metres behind an aeroplane placed to a metre shakes.
var _local_tgt := Vector3.INF
## Below this the view is placed in the world's coordinates: see `_local_tgt`.
const LOCAL_BELOW := 50000.0
## Behind the hangar: see `enter_menu`.
var _menu := false
## The menu has just handed over to a match: the descent starts from here.
var _menu_held := false
var _glide_from := Vector3.ZERO
var _glide_to := Vector3.ZERO
var _glide_t := 1.0
## How far the planet sits off to the right of the menu panel, 0..1, eased.
var _shift := 0.0
## Set while this view has drawn the planet smaller, so only it puts it back.
var _scaled := false

func _ready() -> void:
	# After everything else this frame, the chase camera above all: the
	# descent ends by easing onto that camera, and read before it had moved
	# it was a frame behind -- four metres at an aeroplane's speed, every
	# frame, which is a shake.
	process_priority = 1000
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	far = 45000.0
	fov = 50.0
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	_label = Label.new()
	_label.position = Vector2(24, 18)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	cl.add_child(_label)
	cl.visible = false

## Not being panned or zoomed just now. The fine picture of the ground under
## the view is a 2048-square texture; baked and uploaded every time a pan took
## the view a fifth of the way across it, it was a tenth of a second's stall
## every second of panning. It is held while the view moves and baked once it
## stops.
func settled() -> bool:
	return _still_t > 0.35

## The height the view is at now, eased.
func view_height() -> float:
	return _alt_s

func active() -> bool:
	return current and Sim.spectating

func in_menu() -> bool:
	return _menu and current

## The hangar's backdrop: the planet from far out, turning. Nothing is
## controlled from here and nothing is let go of -- there is nothing to fly --
## so it is not `active` and the menu keeps the mouse.
func enter_menu() -> void:
	_menu = true
	_menu_held = false
	_intro = false
	# the planet whole to begin with, over home
	dir = Sim.chart_to_dir(0.0, 0.0)
	alt = MENU_ALT
	_alt_s = alt
	_glide_t = 1.0
	heading = 0.0
	tilt = 0.0
	fov = 50.0
	_shift = 0.0
	current = true
	(get_child(0) as CanvasLayer).visible = false
	_place()

## Off the hangar, for a match or for the turntable. What it was looking at
## is kept, so a descent can start from it.
func end_menu(for_match: bool) -> void:
	if not _menu:
		return
	_menu = false
	_menu_held = for_match
	current = false
	_unscale()

## Glide over to a place picked in the hangar, and hold over it at a height
## that shows the country round it. The ground there starts being built.
func menu_focus(target: Vector3, glide := true) -> void:
	var to: Vector3 = Sim.chart_to_dir(target.x, target.z)
	focus_dir = to
	if not _menu or not glide:
		return
	_glide_from = dir
	_glide_to = to
	_glide_t = 0.0
	alt = MENU_FOCUS_ALT

## The menu panel covers the left of the screen: the planet sits right of it
## as far as the panel is showing -- in step with it fading in, and back in
## the middle when it is put away.
var menu_panel: CanvasItem = null

func _tick_menu(delta: float) -> void:
	if _glide_t < 1.0:
		_glide_t = minf(_glide_t + delta / MENU_GLIDE, 1.0)
		var e: float = smoothstep(0.0, 1.0, _glide_t)
		dir = _glide_from.slerp(_glide_to, e).normalized()
	heading += delta * MENU_SPIN
	_alt_s = exp(lerpf(log(_alt_s), log(alt), clampf(delta * 1.2, 0.0, 1.0)))
	var want: float = 0.0
	if is_instance_valid(menu_panel) and menu_panel.is_visible_in_tree():
		want = clampf(menu_panel.modulate.a, 0.0, 1.0)
	_shift = lerpf(_shift, smoothstep(0.0, 1.0, want), clampf(delta * 4.0, 0.0, 1.0))
	_place()

func _unscale() -> void:
	if _scaled:
		_scaled = false
		Sim.view_scale = 1.0
		Sim.view_moon = Vector3.INF

## Up over wherever the view is now.
func enter(from: Camera3D, hud: CanvasItem) -> void:
	_was_cam = from
	_hud = hud
	_was_mouse = Input.mouse_mode
	var p: Vector3 = from.global_position if from != null else Vector3.ZERO
	dir = Sim.chart_to_dir(p.x, p.z)
	# a view of the country round you first; the wheel takes it out to the planet
	alt = clampf(maxf(Sim.altitude(p) * 3.0, 25_000.0), ALT_LO, ALT_HI)
	_alt_s = alt
	heading = 0.0
	tilt = 0.0
	if hud != null:
		_was_hud = hud.visible
		hud.visible = false
	Sim.spectating = true
	current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(get_child(0) as CanvasLayer).visible = true
	_place()

## Down out of orbit onto `target`, ending where `to_cam` is and handing the
## screen to it: the way into a match, so the place the fight is in is shown
## on the planet before you are put in it -- and the ground there has the few
## seconds it takes to be built before anyone is standing on it. `done` is
## called once it is over, skipped or not (any key, a click or ESC).
func descend(target: Vector3, to_cam: Camera3D, hud: CanvasItem, done: Callable,
		from_alt := INTRO_FROM, secs := INTRO_SECS, follow: Node3D = null) -> void:
	_intro_follow = follow
	# Straight on from the hangar's view of the planet when there was one:
	# from where it was, at the height it was, swinging over to the place.
	var from_menu: bool = _menu_held
	var was_dir: Vector3 = dir
	var was_head: float = heading
	if from_menu:
		from_alt = maxf(_alt_s, 1000.0)
	_menu_held = false
	enter(to_cam, hud)
	dir = Sim.chart_to_dir(target.x, target.z)
	focus_dir = dir
	var d: Vector3 = to_cam.global_position - target
	# A camera that has not been put on its subject yet (a chase camera
	# catches up on its own next frame) is somewhere else entirely: come down
	# to a view from behind and above instead, and the hand-over at the end
	# finds the camera wherever it has got to.
	if d.length() > 2000.0:
		d = Vector3(0.0, 18.0, 45.0)
		if is_instance_valid(follow):
			d = follow.global_basis * Vector3(0.0, 0.0, 45.0) + Vector3(0.0, 18.0, 0.0)
	_intro_off = d
	_local_tgt = target
	_lift = maxf(target.y - maxf(Sim.height_at(target.x, target.z), Sim.sea_at(target.x, target.z)), 0.0)
	_intro_alt_to = clampf(d.length(), ALT_LO * 0.2, 5000.0)
	_intro_tilt_to = clampf(acos(clampf(d.normalized().dot(Vector3.UP), -1.0, 1.0)), 0.0, TILT_MAX)
	# the top of the screen faces the way the camera at the bottom will look
	var f: Array = _frame()
	var look: Vector3 = Sim.world_to_planet_dir(Vector3(-d.x, 0.0, -d.z).normalized())
	look = (look - dir * look.dot(dir)).normalized()
	var north: Vector3 = f[1]
	heading = atan2(look.dot(dir.cross(north)), look.dot(north)) if look.length() > 0.5 else 0.0
	alt = from_alt
	_alt_s = from_alt
	_intro_alt_from = from_alt
	tilt = 0.0
	_intro_head_to = heading
	_intro_dir_from = Vector3.ZERO
	if from_menu and was_dir.angle_to(dir) > 1e-5:
		_intro_dir_from = was_dir
		_intro_head_from = was_head
	elif from_menu:
		_intro_head_from = was_head
		_intro_dir_from = dir
	_intro_to = dir
	_intro = true
	_intro_t = 0.0
	_intro_len = maxf(secs, 0.5)
	_intro_cam = to_cam
	_intro_fov = fov
	_intro_done = done
	_place()

## Called in as the start of a match, not opened with F4.
func in_intro() -> bool:
	return _intro

func _tick_intro(delta: float) -> void:
	_intro_t += delta
	var p: float = clampf(_intro_t / _intro_len, 0.0, 1.0)
	# Height on a log scale, so each second covers the same ratio of it, eased
	# at both ends; the last part leans over into the camera's view of the place.
	var a: float = smoothstep(0.0, DESCENT_END, p)
	_alt_s = exp(lerpf(log(_intro_alt_from), log(_intro_alt_to), a))
	alt = _alt_s
	if is_instance_valid(_intro_follow) or is_instance_valid(_intro_cam):
		# Where it is drawn, not where the physics has it: the aeroplane is
		# drawn between ticks, and followed by its ticks the view stepped.
		var cp: Vector3 = _intro_follow.get_global_transform_interpolated().origin \
			if is_instance_valid(_intro_follow) and _intro_follow.is_inside_tree() \
			else _intro_cam.global_position - _intro_off
		_lift = maxf(cp.y - maxf(Sim.height_at(cp.x, cp.z), Sim.sea_at(cp.x, cp.z)), 0.0)
		_local_tgt = cp
		_intro_to = Sim.chart_to_dir(cp.x, cp.z)
		if _intro_dir_from == Vector3.ZERO:
			dir = _intro_to
		focus_dir = _intro_to
	if _intro_dir_from != Vector3.ZERO:
		# over to the place first, high, then down onto it
		var sw: float = smoothstep(0.0, DESCENT_END * 0.45, p)
		dir = _intro_dir_from.slerp(_intro_to, sw).normalized()
		heading = lerp_angle(_intro_head_from, _intro_head_to, sw)
	_shift = lerpf(_shift, 0.0, clampf(delta * 2.5, 0.0, 1.0))
	tilt = _intro_tilt_to * smoothstep(DESCENT_END * 0.55, DESCENT_END, p)
	_place()
	# and then onto the camera itself: whatever is left between them, eased out
	var w: float = smoothstep(DESCENT_END, 1.0, p)
	if w > 0.0 and is_instance_valid(_intro_cam):
		var to: Transform3D = _intro_cam.global_transform
		global_transform = Transform3D(global_transform.basis.slerp(to.basis.orthonormalized(), w),
			global_position.lerp(to.origin, w))
		fov = lerpf(_intro_fov, _intro_cam.fov, w)
	if p >= 1.0:
		leave(_hud)

func leave(hud: CanvasItem) -> void:
	var intro_done: Callable = _intro_done if _intro else Callable()
	if _intro:
		_intro = false
		_intro_done = Callable()
		_intro_cam = null
		fov = _intro_fov
	Sim.spectating = false
	current = false
	(get_child(0) as CanvasLayer).visible = false
	if is_instance_valid(_was_cam):
		# The planet sets the drawing camera's far plane each frame, and this
		# runs after it (process_priority): the camera handed the screen would
		# draw one frame with whatever far plane it last had, short enough to
		# cut the air's shell -- a disc of black space round the aircraft.
		# Same place, same height: this view's own planes are the right ones.
		if not _was_cam.has_meta(&"ride_planes"):
			_was_cam.far = maxf(_was_cam.far, far)
			_was_cam.near = minf(_was_cam.near, maxf(near, 0.05))
		_was_cam.current = true
	if hud != null:
		hud.visible = _was_hud
	Input.mouse_mode = _was_mouse
	_pan_drag = false
	_turn_drag = false
	_unscale()
	focus_dir = Vector3.ZERO
	if intro_done.is_valid():
		intro_done.call()

func _unhandled_input(e: InputEvent) -> void:
	if not active():
		return
	if _intro:
		# Any key or click skips it. ESC is taken before this (`on_escape`)
		# and leaves the view the same way.
		if (e is InputEventKey and e.pressed and not e.echo) \
				or (e is InputEventMouseButton and e.pressed):
			get_viewport().set_input_as_handled()
			leave(_hud)
		return
	var ke := e as InputEventKey
	if ke != null and ke.pressed and not ke.echo and ke.physical_keycode == KEY_H:
		clear_air = not clear_air
		get_viewport().set_input_as_handled()
		return
	var mb := e as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					alt = maxf(alt / 1.22, ALT_LO)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					alt = minf(alt * 1.22, ALT_HI)
			MOUSE_BUTTON_LEFT:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_turn_drag = mb.pressed
		get_viewport().set_input_as_handled()
		return
	var mm := e as InputEventMouseMotion
	if mm != null:
		if _pan_drag:
			# the ground follows the pointer: a pixel is as many metres as the
			# view is across over the screen's height
			var vh: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
			var m_per_px: float = 2.0 * _alt_s * tan(deg_to_rad(fov) * 0.5) / vh
			_pan(-mm.relative.x * m_per_px, -mm.relative.y * m_per_px)
		elif _turn_drag:
			heading -= mm.relative.x * 0.006
			tilt = clampf(tilt + mm.relative.y * 0.004, 0.0, TILT_MAX)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Something else took the screen -- a respawn, a seat, a weapon camera:
	# give the controls back rather than leave them let go of with nobody
	# looking through this.
	if Sim.spectating and not current:
		leave(_hud)
		return
	if _menu:
		if current:
			_tick_menu(delta)
		return
	if not active():
		return
	if _intro:
		_tick_intro(delta)
		if _label != null:
			_label.text = "%s\nany key to skip" % _alt_text(_alt_s)
		return
	# keys straight off the keyboard: the actions they share are let go of
	var k := func(a: Key, b: Key) -> float:
		return 1.0 if Input.is_physical_key_pressed(a) or Input.is_physical_key_pressed(b) else 0.0
	var right: float = k.call(KEY_D, KEY_RIGHT) - k.call(KEY_A, KEY_LEFT)
	var up: float = k.call(KEY_W, KEY_UP) - k.call(KEY_S, KEY_DOWN)
	var fast: float = 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if right != 0.0 or up != 0.0:
		_pan(right * _alt_s * 0.8 * fast * delta, up * _alt_s * 0.8 * fast * delta)
	heading += (k.call(KEY_Q, KEY_Q) - k.call(KEY_E, KEY_E)) * 1.2 * delta
	tilt = clampf(tilt + (k.call(KEY_R, KEY_R) - k.call(KEY_F, KEY_F)) * 0.8 * delta, 0.0, TILT_MAX)
	if Input.is_physical_key_pressed(KEY_PAGEUP):
		alt = maxf(alt / pow(3.0, delta * fast), ALT_LO)
	if Input.is_physical_key_pressed(KEY_PAGEDOWN):
		alt = minf(alt * pow(3.0, delta * fast), ALT_HI)
	# the height eases to where the wheel put it, so a notch is a glide
	_alt_s = exp(lerpf(log(_alt_s), log(alt), clampf(delta * 8.0, 0.0, 1.0)))
	if dir.distance_to(_was_dir) * Sim.PLANET_R > _alt_s * 0.002 \
			or absf(_alt_s - _was_alt) > _alt_s * 0.002:
		_still_t = 0.0
	else:
		_still_t += delta
	_was_dir = dir
	_was_alt = _alt_s
	_place()
	if _label != null:
		_label.text = "SATELLITE VIEW   %s   heading %03d°%s\n" % [_alt_text(_alt_s),
			int(round(fposmod(rad_to_deg(-heading), 360.0))), "   CLEAR AIR" if clear_air else ""] \
			+ "wheel / PgUp PgDn height   drag or WASD pan (SHIFT faster)   right-drag or Q E R F turn and tilt   H clear air   F4 / ESC back"

static func _alt_text(a: float) -> String:
	return "%d m" % int(a) if a < 10000.0 else "%d km" % int(a * 0.001)

## The surface frame at the point looked at: east and north along the ground.
func _frame() -> Array:
	var n: Vector3 = -Sim.PLANET_NORTH
	var north: Vector3 = n - dir * n.dot(dir)
	if north.length() < 1e-4:
		north = Sim.chart_south - dir * Sim.chart_south.dot(dir)
	north = north.normalized()
	var east: Vector3 = north.cross(dir).normalized()
	return [east, north]

## Move the point looked at by metres across the screen: right and up.
func _pan(right_m: float, up_m: float) -> void:
	var f: Array = _frame()
	var east: Vector3 = f[0]
	var north: Vector3 = f[1]
	var fwd: Vector3 = north.rotated(dir, heading)
	var rgt: Vector3 = east.rotated(dir, heading)
	var step: Vector3 = (rgt * right_m + fwd * up_m) / Sim.PLANET_R
	dir = (dir + step).normalized()

func _place() -> void:
	var f: Array = _frame()
	var fwd: Vector3 = (f[1] as Vector3).rotated(dir, heading)
	if _intro and _local_tgt != Vector3.INF and _alt_s < LOCAL_BELOW:
		var tgt_l: Vector3 = _local_tgt
		if _intro_dir_from != Vector3.ZERO and dir.angle_to(_intro_to) > 1e-4:
			var q2: Vector2 = Sim.dir_to_chart(dir)
			tgt_l = Vector3(q2.x, _local_tgt.y, q2.y)
		var off: Vector3 = Sim.planet_to_world_dir(dir * cos(tilt) - fwd * sin(tilt)).normalized()
		global_position = tgt_l + off * _alt_s
		var up_l: Vector3 = Sim.planet_to_world_dir(fwd if tilt < 0.6 else dir)
		if absf(off.dot(up_l.normalized())) < 0.999:
			look_at(tgt_l, up_l)
		return
	var q: Vector2 = Sim.dir_to_chart(dir)
	var ground: Vector3 = Sim.world_to_space(Vector3(q.x, Sim.height_at(q.x, q.y), q.y))
	var g_r: float = maxf(ground.length(), Sim.PLANET_R) + (_lift if _intro else 0.0)
	var target: Vector3 = dir * g_r
	var eye: Vector3 = target + (dir * cos(tilt) - fwd * sin(tilt)) * _alt_s
	# Far out, drawn at the cap with the planet shrunk to match: the same
	# picture, in numbers the renderer can hold.
	var cap: float = Sim.PLANET_R + VIEW_CAP
	if eye.length() > cap:
		var k: float = cap / eye.length()
		# the moon from where the eye really is, not from where it is drawn
		Sim.view_moon = Sim.moon_dir() * Sim.MOON_DIST - eye
		eye *= k
		target *= k
		Sim.view_scale = k
		_scaled = true
	elif _scaled:
		_scaled = false
		Sim.view_scale = 1.0
		Sim.view_moon = Vector3.INF
	var eye_w: Vector3 = Sim.space_to_world(eye)
	var tgt_w: Vector3 = Sim.space_to_world(target)
	global_position = eye_w
	# looking straight down, "up" on the screen is the heading
	var up_hint: Vector3 = Sim.planet_to_world_dir(fwd if tilt < 0.6 else dir)
	if (tgt_w - eye_w).length() > 0.01 and absf((tgt_w - eye_w).normalized().dot(up_hint.normalized())) < 0.999:
		look_at(tgt_w, up_hint)
	# Off to the right of the menu panel: the camera turned left by the angle
	# that puts the planet a share of the half width across. Turned, not slid
	# -- slid, the sky still drew the planet's silhouette where it had been.
	if _shift > 0.001:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var t_half: float = tan(deg_to_rad(fov) * 0.5) * vp.x / maxf(vp.y, 1.0)
		rotate_object_local(Vector3.UP, atan(MENU_SHIFT * t_half) * _shift)
