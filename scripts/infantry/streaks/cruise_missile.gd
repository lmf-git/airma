class_name CruiseMissile
extends Node3D
## A cruise missile sent at a mark on the map. It flies itself most of the way,
## level and high; a kilometre and a half out and as far up, the picture is the
## view from its nose and the mouse steers it the rest of the way down, with
## every hostile man and vehicle boxed. Left alone it goes where it was sent.

## A picture of a strike called on another machine: flies and goes off
## here, and hurts nobody. See `Killstreaks.call_picture`.
var picture := false
const SPEED := 240.0
const RANGE := 5200.0
## How far out, over the ground, the player is given it.
const HANDOVER := 2100.0
## It comes down a straight slope onto the mark from the start, this steep,
## so that it is already flying the line when it is handed over.
const DIVE := 0.74
const BLAST := 2.4
## How it is flown. The mouse is where you want it to go -- move it and the
## aim moves, leave it and the aim stays -- and the missile turns its
## flight onto that as hard as its wings let it. The picture looks where
## you aim, from just behind the missile, level with the horizon.
##
## It was a stick that sprang back to the middle, through an angle-of-attack
## loop, with the camera bolted to the airframe's own attitude. Pulling
## meant the nose came up first and the flight followed after, so the
## crosshair was never where it was going; letting go of the mouse let the
## stick go back to centre, so holding a dive meant moving the mouse the
## whole way down; and every bit of that was seen through a camera that
## pitched and rolled with the airframe. Steered by where it is aimed, the
## middle of the screen is the target and the missile comes round onto it.
const TURN_G := 9.0            # the most its wings pull
const AIM_SENS := 0.0021       # radians of aim per pixel of mouse
const KEY_RATE := 0.75         # radians a second of aim off the keys
const AIM_UP := 0.55           # how far above the horizon it may be aimed
const AIM_DOWN := 1.45         # and how far below
## Four tail fins in an X, as a Tomahawk has, each turning about its own
## span: pitch, yaw and roll all show as trailing edges moving. Two fins
## welded flat and edge-on to a camera directly behind them did move, and
## nobody could see it.
const FIN_MAX := 0.45
var _fins: Array = []          # [hinge, angle round the body]
var _aim := Vector3.FORWARD
var _aim_seen := Vector3.FORWARD
var _bank := 0.0
var _cmd := Vector3.ZERO       # pitch, yaw, roll demand, -1..1, for the fins
var _defl: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var vel := Vector3.ZERO
var arena: CqbMatch = null
var target := Vector3.ZERO
var from_dir := Vector3.BACK
var eta := 0.0
var dir := Vector3.FORWARD
var guided := false
var _cam: Camera3D
var _view: CanvasLayer
var _body: Node3D
var _done := -1.0
var _held := false

func _init() -> void:
	top_level = true

func _ready() -> void:
	var st := MeshKit.begin()
	MeshKit.cone(st, 0.26, 0.26, -2.2, 2.6, Vector3.ZERO, 10)
	MeshKit.cone(st, 0.02, 0.26, -3.0, -2.2, Vector3.ZERO, 10)
	MeshKit.box(st, Vector3(2.6, 0.04, 0.5), Vector3(0, -0.1, 0.2))
	var skin := MeshKit.mat(Color(0.62, 0.64, 0.66), 0.5, 0.4)
	_body = MeshKit.mi(MeshKit.finish(st, skin), "Body")
	add_child(_body)
	for k in 4:
		var ang: float = PI * 0.25 + PI * 0.5 * float(k)
		var hinge := Node3D.new()
		hinge.position = Vector3(0.0, 0.0, 2.3)
		hinge.rotation.z = ang
		var flap := Node3D.new()
		hinge.add_child(flap)
		var fs := MeshKit.begin()
		# out along the hinge's own x from the skin, chord along the body,
		# the hinge a third of the way back from the leading edge
		MeshKit.box(fs, Vector3(0.58, 0.035, 0.46), Vector3(0.26 + 0.29, 0.0, 0.08))
		flap.add_child(MeshKit.mi(MeshKit.finish(fs, skin), "Fin"))
		_body.add_child(hinge)
		_fins.append([flap, ang])
	_cam = Camera3D.new()
	_cam.fov = 58.0
	_cam.near = 0.5
	_cam.far = 45000.0
	# Behind and a little above, looking the way it is going. The camera
	# was on the tip of the nose: a view of the ground coming up with
	# nothing in it to say what you were flying, or that you were flying
	# anything. From here the missile is in the bottom of the picture and
	# the cross above it is still where it is pointed -- the two lines are
	# parallel and two metres apart.
	# Its own node in the world, not bolted to the missile: see `_trail_cam`.
	_cam.top_level = true
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam)
	# and something burning at the back of it, which from behind is most of
	# what there is to see
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.72, 0.35)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.25)
	fm.emission_energy_multiplier = 4.0
	var fc := CylinderMesh.new()
	fc.top_radius = 0.16
	fc.bottom_radius = 0.02
	fc.height = 1.6
	fc.radial_segments = 8
	fc.material = fm
	var flame := MeshInstance3D.new()
	flame.mesh = fc
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the cylinder stands on Y; laid along the body, wide end at the nozzle
	flame.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	flame.position = Vector3(0.0, 0.0, 3.4)
	_body.add_child(flame)
	var start: Vector3 = target + from_dir * RANGE
	start.y = target.y + RANGE * tan(DIVE)
	dir = (target - start).normalized()
	vel = dir * SPEED
	global_position = start
	look_at(start + dir, Vector3.UP)
	reset_physics_interpolation()
	_aim = dir
	_aim_seen = dir
	_cam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP),
		start - dir * 10.0 + Vector3.UP * 1.8)
	eta = (RANGE - HANDOVER) / cos(DIVE) / SPEED
	Sfx.play_at(get_parent(), "roar", start, 8.0, 1.1, 9000.0)

func _unhandled_input(e: InputEvent) -> void:
	if not guided or not _held or _done >= 0.0 or not (e is InputEventMouseMotion):
		return
	var m: Vector2 = Sim.mouse_rel(e as InputEventMouseMotion)
	_turn_aim(-m.x * AIM_SENS, -m.y * AIM_SENS)

## Move the aim: left and right about the vertical, up and down about the
## aim's own level across, and never over the top.
func _turn_aim(yaw: float, pitch: float) -> void:
	var a: Vector3 = _aim.rotated(Vector3.UP, yaw)
	var el: float = asin(clampf(a.y, -1.0, 1.0))
	var want: float = clampf(el + pitch, -AIM_DOWN, AIM_UP)
	var flat := Vector3(a.x, 0.0, a.z)
	flat = flat.normalized() if flat.length() > 1e-4 else Vector3.FORWARD
	_aim = (flat * cos(want) + Vector3.UP * sin(want)).normalized()

func _take() -> void:
	guided = true
	# already on the line to the mark, and trimmed: doing nothing hits it
	var p: Walker = arena.player if is_instance_valid(arena) else null
	if p == null or not is_instance_valid(p) or p.dead or not p.cam.current:
		return                      # nobody to give it to: it flies itself in
	_held = true
	arena.set_away(true)
	_aim = vel.normalized()
	_cam.current = true
	_view = CanvasLayer.new()
	_view.layer = 20
	var v := CruiseView.new()
	v.missile = self
	_view.add_child(v)
	add_child(_view)
	Sim.report("CRUISE MISSILE — you have it. Aim with the mouse (or W/S/A/D) and it turns onto it.", Sim.Ev.GOOD)

func _physics_process(delta: float) -> void:
	if _done >= 0.0:
		_done -= delta
		if _done <= 0.0:
			queue_free()
		return
	var here := global_position
	if not guided:
		var flat := Vector2(target.x - here.x, target.z - here.z).length()
		if flat <= HANDOVER:
			_take()
	_fly(delta)
	var nxt: Vector3 = here + vel * delta
	var wall: float = Obstacles.segment(here, nxt)
	var hit := wall < 1.0
	if hit:
		nxt = here.lerp(nxt, wall)
	var gy: float = Sim.height_at(nxt.x, nxt.z)
	if nxt.y <= gy:
		nxt.y = gy
		hit = true
	if hit:
		_go_off(nxt)
		return
	global_position = nxt

## The camera, every drawn frame rather than every physics tick.
##
## It was a child of the missile, moved sixty times a second with it: every
## twitch of the airframe was a twitch of the whole picture, and on a
## display faster than the physics it stepped. It follows now -- where the
## missile is drawn this frame, and round to its attitude over a fifth of a
## second, so a roll is something you watch the missile do against a
## horizon that follows it over rather than the world snapping on its side.
func _process(delta: float) -> void:
	if _done >= 0.0 or not is_instance_valid(_cam):
		return
	var xf: Transform3D = get_global_transform_interpolated()
	# Behind it along where it is aimed, a little above, and level: the
	# horizon stays the horizon while the missile banks under it.
	_aim_seen = _aim_seen.slerp(_aim, clampf(delta * 9.0, 0.0, 1.0)).normalized()
	var want: Vector3 = xf.origin - _aim_seen * 10.0 + Vector3.UP * 1.8
	# A camera ten metres behind a missile going down a street is inside
	# the building it has just passed.
	var clear: float = Obstacles.segment(xf.origin, want)
	if clear < 1.0:
		want = xf.origin.lerp(want, maxf(clear - 0.1, 0.15))
	want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 0.6)
	var look: Vector3 = xf.origin + _aim_seen * 60.0 - want
	if look.length() > 0.01:
		var up_ref := Vector3.UP if absf(look.normalized().y) < 0.995 else Vector3.BACK
		_cam.global_transform = Transform3D(Basis.looking_at(look.normalized(), up_ref), want)
	# and the tail, deflected to what is being asked of it, each fin about
	# its own span: an X tail mixes all three into every fin
	var k: float = clampf(delta * 14.0, 0.0, 1.0)
	for i in _fins.size():
		var flap: Node3D = _fins[i][0]
		var ang: float = _fins[i][1]
		var d: float = clampf(-_cmd.x * cos(ang) * 1.41 - _cmd.y * sin(ang) * 1.41
			+ _cmd.z, -1.0, 1.0) * FIN_MAX
		_defl[i] = lerpf(_defl[i], d, k)
		flap.rotation.x = _defl[i]

## Where it is told to go when nobody has it: straight at the mark.
func _autopilot() -> void:
	var to: Vector3 = target - global_position
	if to.length() > 1.0:
		_aim = to.normalized()

func _fly(delta: float) -> void:
	if guided and _held:
		var kx: float = Sim.strength(&"roll_left") - Sim.strength(&"roll_right") \
			+ Sim.strength(&"yaw_left") - Sim.strength(&"yaw_right")
		var ky: float = Sim.strength(&"pitch_up") - Sim.strength(&"pitch_down")
		if absf(kx) > 0.01 or absf(ky) > 0.01:
			_turn_aim(kx * KEY_RATE * delta, ky * KEY_RATE * delta)
	else:
		_autopilot()
	var v: float = maxf(vel.length(), 1.0)
	var was_dir: Vector3 = vel / v
	var vdir: Vector3 = was_dir
	# onto the aim, easing in as it gets there, never harder than it pulls
	var off: float = vdir.angle_to(_aim)
	var most: float = TURN_G * 9.81 / maxf(v, 60.0)
	var rate: float = minf(off * 2.6, most)
	var axis: Vector3 = vdir.cross(_aim)
	if axis.length() > 1e-6 and off > 1e-5:
		vdir = vdir.rotated(axis.normalized(), minf(rate * delta, off))
	# Speed: what a dive gives it and a climb takes, and an engine that
	# holds it near its cruise.
	v += (-9.81 * vdir.y * 0.7 + clampf((SPEED - v) * 0.35, -8.0, 6.0)) * delta
	v = clampf(v, 140.0, 330.0)
	vel = vdir * v
	dir = vdir
	# How the turn shows on the airframe: it banks into it, as hard as the
	# turn is, and the nose rides a little ahead of the flight path.
	var acc: Vector3 = (vdir - was_dir) / maxf(delta, 1e-4) * v
	var right: Vector3 = vdir.cross(Vector3.UP)
	right = right.normalized() if right.length() > 0.05 else Vector3.RIGHT
	var bank_want: float = clampf(atan2(acc.dot(right), 9.81), -1.3, 1.3)
	var bank_was: float = _bank
	_bank = lerpf(_bank, bank_want, clampf(delta * 3.5, 0.0, 1.0))
	var nose: Vector3 = vdir.slerp(_aim, clampf(rate / maxf(most, 1e-3), 0.0, 1.0) * 0.12)
	var up_ref := Vector3.UP if absf(nose.y) < 0.995 else Vector3.BACK
	var b := Basis.looking_at(nose, up_ref).rotated(nose, _bank)
	global_transform = Transform3D(b.orthonormalized(), global_position)
	# what the fins are asked for, in the airframe's own frame
	var a_n: float = clampf(acc.length() / (most * v), 0.0, 1.0)
	var a_dir: Vector3 = acc.normalized() if acc.length() > 0.01 else Vector3.ZERO
	_cmd = Vector3(a_dir.dot(b.y) * a_n, a_dir.dot(b.x) * a_n,
		clampf((_bank - bank_was) / maxf(delta, 1e-4) / 1.2, -1.0, 1.0))

func _go_off(at: Vector3) -> void:
	_body.visible = false
	if is_instance_valid(_view):
		_view.queue_free()
	if is_instance_valid(arena):
		arena.streaks.bomb(at, BLAST, false, "cruise", picture)
		arena.streaks.bomb(at + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)), BLAST * 0.6,
			false, "cruise", picture)
	# stand off and watch it for a moment before going back to the street
	var back: Vector3 = at - dir * 70.0 + Vector3(0, 25.0, 0)
	global_position = back
	look_at(at, Vector3.UP)
	# the stand-off view is from this point itself, not from behind it
	_cam.global_transform = global_transform
	reset_physics_interpolation()
	_done = 1.4 if _held else 0.05

func _exit_tree() -> void:
	if not _held:
		return
	_held = false
	if is_instance_valid(arena):
		arena.set_away(false)
		var p: Walker = arena.player
		if is_instance_valid(p) and is_instance_valid(p.cam) and _cam.current:
			p.cam.current = true
