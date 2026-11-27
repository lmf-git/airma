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
const ALT_HI := 12_000_000.0
const TILT_MAX := 1.25
## H in the view: the air, the cloud deck and the haze taken away, so the
## ground reads like a survey photograph rather than through thirty kilometres
## of blue. Kept between visits.
static var clear_air := false

## The point looked at, as a direction from the planet's centre.
var dir := Vector3.UP
## Height of the eye over that point, along the line of sight.
var alt := 600_000.0
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

func _ready() -> void:
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

func leave(hud: CanvasItem) -> void:
	Sim.spectating = false
	current = false
	(get_child(0) as CanvasLayer).visible = false
	if is_instance_valid(_was_cam):
		_was_cam.current = true
	if hud != null:
		hud.visible = _was_hud
	Input.mouse_mode = _was_mouse
	_pan_drag = false
	_turn_drag = false

func _unhandled_input(e: InputEvent) -> void:
	if not active():
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
	if not active():
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
	var q: Vector2 = Sim.dir_to_chart(dir)
	var ground: Vector3 = Sim.world_to_space(Vector3(q.x, Sim.height_at(q.x, q.y), q.y))
	var g_r: float = maxf(ground.length(), Sim.PLANET_R)
	var target: Vector3 = dir * g_r
	var eye: Vector3 = target + (dir * cos(tilt) - fwd * sin(tilt)) * _alt_s
	var eye_w: Vector3 = Sim.space_to_world(eye)
	var tgt_w: Vector3 = Sim.space_to_world(target)
	global_position = eye_w
	# looking straight down, "up" on the screen is the heading
	var up_hint: Vector3 = Sim.planet_to_world_dir(fwd if tilt < 0.6 else dir)
	if (tgt_w - eye_w).length() > 0.01 and absf((tgt_w - eye_w).normalized().dot(up_hint.normalized())) < 0.999:
		look_at(tgt_w, up_hint)
