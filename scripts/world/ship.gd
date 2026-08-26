class_name Ship
extends Node3D
## Surface and sub-surface vessels. Hulls are lofted from a beam/draught profile
## so a destroyer and a submarine come out of the same code, and they steam
## along a heading on the water plane rather than being scenery.

const KINDS := {
	"destroyer": {
		"name": "Arleigh Burke destroyer", "len": 155.0, "beam": 20.0, "draught": 9.5,
		"free": 9.0, "hp": 2200.0, "speed": 15.4, "sub": false,
		"paint": Color(0.36, 0.39, 0.42), "deck": Color(0.30, 0.32, 0.34),
		"super": [[-0.10, 0.30, 26.0, 13.0], [0.12, 0.20, 16.0, 9.0]],
		"mast": 22.0, "guns": 2, "vls": 32, "class": "warship",
	},
	"frigate": {
		"name": "Type 23 frigate", "len": 133.0, "beam": 16.1, "draught": 7.3,
		"free": 8.0, "hp": 1500.0, "speed": 14.9, "sub": false,
		"paint": Color(0.33, 0.36, 0.40), "deck": Color(0.28, 0.30, 0.33),
		"super": [[-0.06, 0.28, 22.0, 11.0]],
		"mast": 19.0, "guns": 1, "vls": 16, "class": "warship",
	},
	"corvette": {
		"name": "Steregushchiy corvette", "len": 105.0, "beam": 13.0, "draught": 6.0,
		"free": 7.0, "hp": 1100.0, "speed": 13.4, "sub": false,
		"paint": Color(0.30, 0.33, 0.36), "deck": Color(0.26, 0.28, 0.31),
		"super": [[-0.04, 0.26, 18.0, 9.0]],
		"mast": 16.0, "guns": 1, "vls": 8, "class": "warship",
	},
	"patrol": {
		"name": "Patrol boat", "len": 38.0, "beam": 7.0, "draught": 2.2,
		"free": 3.4, "hp": 260.0, "speed": 18.0, "sub": false,
		"paint": Color(0.28, 0.31, 0.29), "deck": Color(0.24, 0.26, 0.25),
		"super": [[-0.05, 0.22, 7.5, 4.2]],
		"mast": 6.0, "guns": 1, "class": "boat",
	},
	"sub": {
		"name": "Attack submarine", "len": 110.0, "beam": 10.5, "draught": 8.0,
		"free": 1.6, "hp": 1400.0, "speed": 12.0, "sub": true,
		"paint": Color(0.14, 0.15, 0.16), "deck": Color(0.12, 0.13, 0.14),
		"super": [],
		"mast": 0.0, "guns": 0, "vls": 12, "class": "sub",
	},
	"cargo": {
		"name": "Container ship", "len": 210.0, "beam": 30.0, "draught": 12.0,
		"free": 14.0, "hp": 1800.0, "speed": 10.5, "sub": false,
		"paint": Color(0.42, 0.28, 0.22), "deck": Color(0.34, 0.32, 0.28),
		"super": [[0.34, 0.30, 26.0, 20.0]],
		"mast": 12.0, "guns": 0, "class": "civil",
	},
}

signal dismount_requested()

var kind := "destroyer"
var occupied := false
var cam: Camera3D
var helm := 0.0                   # wheel: -1 hard port, +1 hard starboard
var telegraph := 0.0              # engine order, 0 stop to 1 full ahead
var aim_yaw := 0.0                # gun bearing the captain wants
var aim_pitch := 0.0
var gun_cd := 0.0
var sel_weapon := 0               # 0 main battery, 1 vertical launch
var cells_left := 0
var vls_cd := 0.0
var _mount_yaw := 0.0
var _gun: Node3D
var _hull_mi: MeshInstance3D
var _fore: Node3D
var _aft: Node3D
var _broken := false
var _wreck_fire: GPUParticles3D
var _wreck_smoke: GPUParticles3D
var _vls_deck: Node3D
var _vls_muzzle := Vector3(0, 6, -20)
var team := 1
var health := 1000.0
var alive := true
var heading := 0.0
var speed := 0.0
var _t := 0.0
var _wake: GPUParticles3D

## Ships that nobody is conning fight for themselves.
var ai := true
var ai_target: Node3D = null
var _ai_scan := 0.0
var _ai_vls_cd := 0.0
var _ai_helm := 0.0
var rounds := 0                   # main battery rounds fired, for the harness

## Damage control. A warship does not stop existing when the hull bar empties:
## she floods, she burns, she lists, she loses way, and the crew fight it.
var flood := 0.0                  # 0 dry, 1 lost
var fires := 0.0                  # 0 out, 1 ablaze
var list_ang := 0.0               # roll from the free surface, radians
var crew := 1.0                   # fraction of the party still fighting
var _hit_ago := 99.0              # seconds since the last hit
var _sinking := -1.0              # >= 0 once she is going down
var _fire_fx: GPUParticles3D
var _flood_fx: GPUParticles3D
var list_side := 1.0              # which way the free surface took her
var ghost := false                # posed by the network, not simulated here
var fleet_idx := -1               # position in the fleet plan; the net key
var remote_conn := 0              # peer id that has the conn, host side

func setup(k := "destroyer", t := 1) -> void:
	kind = k if KINDS.has(k) else "destroyer"
	team = t
	var kd: Dictionary = KINDS[kind]
	health = float(kd["hp"])
	cells_left = int(kd.get("vls", 0))
	speed = float(kd["speed"])
	name = String(kd["name"])
	_build(kd)
	add_to_group("hittable")
	add_to_group("ships")
	if int(kd["guns"]) > 0:
		add_to_group("boardable")
	cam = Camera3D.new()
	cam.far = 48000.0
	cam.fov = 62.0
	add_child(cam)

## Hull, superstructure and mast. The hull is a lofted box section that tapers
## to a stem forward and a transom aft, sitting so the waterline falls at the
## designed draught.
func _build(kd: Dictionary) -> void:
	var l: float = kd["len"]
	var b: float = kd["beam"]
	var fb: float = kd["free"]
	_hull_mi = MeshKit.mi(_loft_hull(kd, -0.50, 0.50, 0.0), "Hull")
	add_child(_hull_mi)

	if not kd["super"].is_empty():
		var sst := MeshKit.begin()
		for blk in kd["super"]:
			var cz: float = float(blk[0]) * l
			var hgt: float = float(blk[1]) * b
			MeshKit.box(sst, Vector3(float(blk[3]), hgt, float(blk[2])),
				Vector3(0, fb + hgt * 0.5, cz))
		add_child(MeshKit.mi(MeshKit.finish(sst, MeshKit.mat(kd["deck"], 0.8, 0.0)), "Super"))
	if float(kd["mast"]) > 0.0:
		var mst := MeshKit.begin()
		MeshKit.box(mst, Vector3(0.9, float(kd["mast"]), 0.9),
			Vector3(0, fb + float(kd["mast"]) * 0.5, -l * 0.04))
		add_child(MeshKit.mi(MeshKit.finish(mst,
			MeshKit.mat(Color(0.22, 0.23, 0.25), 0.7, 0.2)), "Mast"))
	if bool(kd["sub"]):
		# sail, and the boat rides almost awash
		var cst := MeshKit.begin()
		MeshKit.box(cst, Vector3(2.6, 7.0, 14.0), Vector3(0, fb + 3.5, -l * 0.06))
		add_child(MeshKit.mi(MeshKit.finish(cst, MeshKit.mat(kd["deck"], 0.8, 0.0)), "Sail"))
	# Launch tubes. A VLS farm is a flush deck of square hatches, so it reads as
	# armament from the air rather than the ship looking unarmed between the
	# mount and the mast. A boat carries hers in the casing forward of the sail.
	var cells: int = int(kd.get("vls", 0))
	if cells > 0:
		var vst := MeshKit.begin()
		var cols := 4 if cells >= 16 else 2
		var rows: int = maxi(int(ceil(float(cells) / float(cols))), 1)
		var pitch := 1.55
		var cz: float = (-l * 0.24) if not bool(kd["sub"]) else (l * 0.02)
		var top: float = (fb + 0.35) if not bool(kd["sub"]) else (fb + 0.20)
		var hatch := MeshKit.mat(Color(0.20, 0.21, 0.23), 0.6, 0.25)
		for r in rows:
			for c in cols:
				if r * cols + c >= cells:
					break
				MeshKit.box(vst, Vector3(pitch * 0.82, 0.5, pitch * 0.82),
					Vector3((float(c) - float(cols - 1) * 0.5) * pitch, top,
						cz + (float(r) - float(rows - 1) * 0.5) * pitch))
		_vls_deck = MeshKit.mi(MeshKit.finish(vst, hatch), "Tubes")
		add_child(_vls_deck)
		# the cell the next round comes out of
		_vls_muzzle = Vector3(0, top + 0.4, cz)
	if int(kd["guns"]) > 0:
		_gun = Node3D.new()
		_gun.name = "Mount"
		_gun.position = Vector3(0, fb + 1.2, -l * 0.36)
		add_child(_gun)
		var gst := MeshKit.begin()
		MeshKit.box(gst, Vector3(4.0, 2.4, 5.0), Vector3.ZERO)
		MeshKit.box(gst, Vector3(0.5, 0.5, 6.0), Vector3(0, 0.8, -3.0))
		_gun.add_child(MeshKit.mi(MeshKit.finish(gst,
			MeshKit.mat(Color(0.26, 0.27, 0.29), 0.7, 0.1)), "Gun"))
	_wake = Effects.trail_particles(Color(0.86, 0.90, 0.92), float(kd["beam"]) * 0.5, 30)
	_wake.position = Vector3(0, 0.4, l * 0.48)
	_wake.emitting = true
	add_child(_wake)

## The hull section between two stations, as a fraction of the length. The whole
## ship is one call with the full range; a wreck is two calls either side of the
## break, with the ends interpolated so the two pieces actually meet. `shift`
## moves the geometry along z so a section can be built about its own break end.
func _loft_hull(kd: Dictionary, z0: float, z1: float, shift: float) -> Mesh:
	var l: float = kd["len"]
	var b: float = kd["beam"]
	var dr: float = kd["draught"]
	var fb: float = kd["free"]
	# station, half beam factor
	var stations := [[-0.50, 0.06], [-0.42, 0.36], [-0.28, 0.72], [-0.05, 1.00],
		[0.22, 0.98], [0.42, 0.86], [0.50, 0.72]]
	var picked := []
	for st in stations:
		if float(st[0]) > z0 and float(st[0]) < z1:
			picked.append(st)
	# the two cut ends, interpolated onto the profile
	picked.push_front([z0, _beam_at(stations, z0)])
	picked.append([z1, _beam_at(stations, z1)])
	var sf := MeshKit.begin()
	var rings := []
	for st in picked:
		var z: float = float(st[0]) * l + shift
		var hw: float = float(st[1]) * b * 0.5
		var pts := PackedVector3Array()
		var n := 10
		for i in n:
			var a := TAU * float(i) / float(n)
			var y: float = sin(a)
			pts.append(Vector3(cos(a) * hw, (fb * y) if y > 0.0 else (dr * y), z))
		rings.append(pts)
	MeshKit.loft(sf, rings, Vector3.ZERO)
	return MeshKit.finish(sf, MeshKit.mat(kd["paint"], 0.85, 0.05))

## Half beam factor at any station, by linear interpolation of the profile.
func _beam_at(stations: Array, at: float) -> float:
	if at <= float(stations[0][0]):
		return float(stations[0][1])
	for i in range(1, stations.size()):
		var a: Array = stations[i - 1]
		var c: Array = stations[i]
		if at <= float(c[0]):
			var t: float = (at - float(a[0])) / maxf(float(c[0]) - float(a[0]), 1e-4)
			return lerpf(float(a[1]), float(c[1]), t)
	return float(stations[-1][1])

## Take the conn. Everything below is only run for the ship the player is on.
func mount(on: bool) -> void:
	occupied = on
	# the AI captain stands down while somebody has the conn, and takes it back
	# when they leave rather than the ship drifting for the rest of the match
	ai = not on and alive
	if on:
		cam.current = true
		aim_yaw = heading
		_mount_yaw = heading
		telegraph = clampf(speed / maxf(float(KINDS[kind]["speed"]), 1.0), 0.0, 1.0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func mast_height() -> float:
	return float(KINDS[kind]["free"]) + float(KINDS[kind].get("mast", 12.0)) + 4.0

func tubes() -> int:
	return int(KINDS[kind].get("vls", 0))

func has_vls() -> bool:
	return tubes() > 0 and cells_left > 0

## Main battery, then the tubes if the ship has any.
func weapons() -> PackedStringArray:
	var w := PackedStringArray(["main"])
	if tubes() > 0:
		w.append("vls")
	return w

func current_weapon() -> String:
	var w := weapons()
	return w[clampi(sel_weapon, 0, w.size() - 1)]

func set_weapon(i: int) -> void:
	var w := weapons()
	if i < 0 or i >= w.size() or i == sel_weapon:
		return
	sel_weapon = i
	Sim.report(weapon_label(), Sim.Ev.INFO)

func cycle_weapon() -> void:
	set_weapon((sel_weapon + 1) % weapons().size())

## Launch a cell at whatever the ship is holding, or at the nearest hostile.
func fire_vls(at_node: Node3D = null) -> bool:
	if not has_vls() or vls_cd > 0.0 or not alive:
		return false
	if ghost:
		vls_cd = 1.6
		if Sim.net != null and Sim.net.active:
			Sim.net.request_ship_fire(fleet_idx, 1, aim_yaw, aim_pitch)
		return true
	var tgt: Node3D = at_node
	if tgt == null:
		var best := 1e9
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == self or not (n is Node3D):
				continue
			if ("team" in n) and n.team == team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			var d: float = global_position.distance_to((n as Node3D).global_position)
			if d < best and d < 42000.0:
				best = d
				tgt = n as Node3D
	if tgt == null:
		Sim.report("no contact for the tubes", Sim.Ev.BAD)
		return false
	cells_left -= 1
	vls_cd = 1.6
	var from: Vector3 = global_transform * (_vls_muzzle + Vector3(0, 2.5, 0))
	var m := Missile.new()
	# Off the rail already leaning at the contact. A round fired straight up
	# does not tip over onto anything: at six hundred metres a second pulling a
	# few g the turn radius is kilometres, so a vertical launch simply carries
	# on being vertical and the missile climbs out of the sky doing nothing.
	# A real cell does its pitch-over in the first second; this launches into
	# the end of that, steeply enough to be clear of the ship's own mast and
	# leaning enough to have somewhere to go.
	var rel: Vector3 = tgt.global_position - from
	var brg := atan2(rel.x, -rel.z)
	var el := deg_to_rad(62.0)
	var dir := Vector3(sin(brg) * cos(el), sin(el), -cos(brg) * cos(el)).normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var xf := Transform3D(Basis.looking_at(dir, up_ref), from)
	m.launch("sm2", xf, dir * 60.0, self, tgt)
	get_tree().current_scene.add_child(m)
	Sim.report("cell away — %d remaining" % cells_left, Sim.Ev.GOOD)
	return true

func has_gun() -> bool:
	return int(KINDS[kind]["guns"]) > 0

func weapon_label() -> String:
	return "MAIN BATTERY" if current_weapon() == "main" else "VLS  %d CELLS" % cells_left

func _unhandled_input(e: InputEvent) -> void:
	if not occupied or not alive:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		aim_yaw -= mm.relative.x * 0.0026
		aim_pitch = clampf(aim_pitch - mm.relative.y * 0.0020,
			deg_to_rad(-8.0), deg_to_rad(70.0))

## Helm and telegraph. A ship answers slowly: the wheel sets a rate of turn and
## the engines take a while to build or shed way.
func _conn(delta: float) -> void:
	var w := Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	helm = move_toward(helm, w, delta * 1.4)
	var t := Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up")
	telegraph = clampf(telegraph + t * delta * 0.35, -0.25, 1.0)
	if Sim.tapped(&"interact"):
		dismount_requested.emit()
	if Sim.tapped(&"cycle_weapon"):
		cycle_weapon()
	for wi in weapons().size():
		if Sim.tapped(StringName("weapon_%d" % (wi + 1))):
			set_weapon(wi)
	if Sim.held(&"fire") and not Sim.ui_modal:
		if current_weapon() == "vls":
			if Sim.tapped(&"fire"):
				fire_vls()
		elif has_gun():
			fire_gun()
	# a mast-head view, looking where the guns are laid
	var eye: Vector3 = global_position + Vector3(0, float(KINDS[kind]["free"]) + 14.0, 0)
	var back := Vector3(-sin(aim_yaw), 0, cos(aim_yaw))
	# the boom drops as the battery goes up, so a high angle shot is not taken
	# through the back of your own superstructure
	var lift: float = 6.0 + 26.0 * clampf(aim_pitch / deg_to_rad(70.0), 0.0, 1.0)
	cam.global_position = eye + back * (26.0 - 8.0 * clampf(aim_pitch, 0.0, 1.2)) \
		+ Vector3(0, lift, 0)
	var look := eye + Vector3(sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch),
		-cos(aim_yaw) * cos(aim_pitch)) * 400.0
	cam.look_at(look, Vector3.UP)

# ------------------------------------------------------------------ AI conn
## A ship nobody is standing on fights herself: she looks for a contact, opens
## or closes to a range her battery can make, lays the mount with a proper
## ballistic and lead solution, and puts a round in the air. Air contacts get
## the tubes instead — a five inch mount cannot track an aeroplane.
func _captain(delta: float) -> void:
	_ai_vls_cd = maxf(_ai_vls_cd - delta, 0.0)
	_ai_scan -= delta
	if _ai_scan <= 0.0:
		_ai_scan = 1.5
		ai_target = _pick_contact()
		var air := _pick_air()
		if air != null and has_vls() and _ai_vls_cd <= 0.0 and vls_cd <= 0.0:
			_ai_vls_cd = randf_range(3.5, 7.0)
			fire_vls(air)
	var kd: Dictionary = KINDS[kind]
	var want_speed: float = float(kd["speed"]) * 0.45
	var want_brg := heading
	if is_instance_valid(ai_target):
		var rel: Vector3 = ai_target.global_position - global_position
		var rng := Vector2(rel.x, rel.z).length()
		var brg := atan2(rel.x, -rel.z)
		# Flooding badly, break off: a ship fighting for her life does not also
		# fight the enemy. Otherwise open the range if she is inside knife
		# fighting distance and close it if the battery cannot reach.
		if flood > 0.45 or crew < 0.35:
			want_brg = wrapf(brg + PI, -PI, PI)
			want_speed = float(kd["speed"]) * 0.5
		elif rng < 4000.0:
			want_brg = wrapf(brg + PI * 0.75, -PI, PI)
			want_speed = float(kd["speed"])
		elif rng > 11000.0:
			want_brg = brg
			want_speed = float(kd["speed"])
		else:
			# hold her on the beam so the whole battery bears
			want_brg = wrapf(brg + PI * 0.5, -PI, PI)
			want_speed = float(kd["speed"]) * 0.7
		if has_gun() and _lay_on(ai_target) and gun_cd <= 0.0 and rng < 22000.0:
			fire_gun()
	else:
		# no contact: a long patrol leg, altered every so often
		if _ai_scan > 1.49:
			want_brg = wrapf(heading + randf_range(-0.5, 0.5), -PI, PI)
	_steer(want_brg, want_speed, delta)

## Wheel and telegraph toward a course and a speed, at a ship's rates.
func _steer(brg: float, spd: float, delta: float) -> void:
	var err := wrapf(brg - heading, -PI, PI)
	_ai_helm = move_toward(_ai_helm, clampf(err * 1.8, -1.0, 1.0), delta * 1.2)
	helm = _ai_helm
	telegraph = clampf(spd / maxf(float(KINDS[kind]["speed"]), 1.0), -0.25, 1.0)

## The nearest hostile that floats, or a coastal structure worth shelling.
func _pick_contact() -> Node3D:
	if not has_gun():
		return null
	var best: Node3D = null
	var bd := 22000.0
	for n in get_tree().get_nodes_in_group("ships"):
		if not is_instance_valid(n) or n == self or not (n is Ship):
			continue
		var o := n as Ship
		# merchant traffic is not a gun action, and neither is a friend
		if o.team == team or String(KINDS[o.kind]["class"]) == "civil":
			continue
		if not o.alive:
			continue
		var d: float = global_position.distance_to(o.global_position)
		if d >= bd:
			continue
		if not Sim.line_of_sight(global_position + Vector3(0, mast_height(), 0),
				o.global_position + Vector3(0, 6.0, 0)):
			continue
		bd = d
		best = o
	if best != null:
		return best
	# nothing afloat: shore bombardment, if anything hostile is within reach
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == self or not (n is Node3D):
			continue
		if n is Aircraft or n is Ship:
			continue
		if ("team" in n) and int(n.team) == team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

## The nearest hostile aeroplane inside the missile envelope.
func _pick_air() -> Node3D:
	var best: Node3D = null
	var bd := 38000.0
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not (n is Aircraft):
			continue
		if int(n.team) == team or not n.is_alive():
			continue
		if n.is_in_group("remote"):
			continue
		var d: float = global_position.distance_to((n as Node3D).global_position)
		if d >= bd:
			continue
		# Terrain masking. A ship's radar horizon is a mast head and a lot of
		# open water, but the moment the contact is over land with a ridge in
		# between there is nothing to shoot at — and an aeroplane down in the
		# valley was being engaged through the hillside.
		if not Sim.line_of_sight(global_position + Vector3(0, mast_height(), 0),
				(n as Node3D).global_position):
			continue
		bd = d
		best = n as Node3D
	return best

## Lay the mount for a ballistic shot with lead. Returns true once the solution
## is good enough to pull the lanyard. A shell at 820 m/s takes twelve seconds
## to reach ten kilometres, so a ship making fifteen knots has moved the better
## part of two hundred metres by the time it arrives: without the lead every
## round lands in her wake.
func _lay_on(tgt: Node3D) -> bool:
	var muzzle := 820.0
	var aim: Vector3 = tgt.global_position
	var tv := Vector3.ZERO
	if "linear_velocity" in tgt:
		tv = tgt.linear_velocity
	elif tgt is Ship:
		var sh := tgt as Ship
		tv = Vector3(sin(sh.heading), 0, -cos(sh.heading)) * sh.speed
	var here: Vector3 = global_position + Vector3(0, float(KINDS[kind]["free"]) + 1.2, 0)
	# two passes is plenty: the flight time barely moves once the lead is in
	for _i in 2:
		var d := here.distance_to(aim)
		var tof := d / maxf(muzzle, 1.0)
		aim = tgt.global_position + tv * tof
	var rel := aim - here
	var flat := Vector2(rel.x, rel.z).length()
	# low-angle ballistic solution; out of range when the discriminant goes bad
	var arg := (9.81 * flat) / (muzzle * muzzle)
	if arg > 0.98:
		return false
	var el := 0.5 * asin(clampf(arg, -1.0, 1.0)) + atan2(rel.y, maxf(flat, 1.0)) * 0.5
	aim_yaw = atan2(rel.x, -rel.z)
	aim_pitch = clampf(el, deg_to_rad(-8.0), deg_to_rad(70.0))
	# the mount has to actually be there before the round goes
	var laid := absf(wrapf(_mount_yaw - aim_yaw, -PI, PI))
	_mount_yaw = aim_yaw
	return laid < deg_to_rad(2.0)

# ------------------------------------------------------- damage control
## Fires burn the hull down, flooding takes away her speed and lays her over,
## and the party fights both. Effectiveness falls with the crew, and the crew
## falls with the damage, so a ship that has been hit hard cannot save herself.
func _damage_control(delta: float) -> void:
	_hit_ago += delta
	if fires > 0.0:
		health -= fires * 9.0 * delta
		flood += fires * 0.004 * delta
	if flood > 0.0:
		# free surface: she lists to whichever side took it, and she is slow
		list_ang = move_toward(list_ang, flood * 0.42, delta * 0.10)
	else:
		list_ang = move_toward(list_ang, 0.0, delta * 0.06)
	crew = clampf(health / maxf(float(KINDS[kind]["hp"]), 1.0), 0.0, 1.0)
	# the party needs a moment without being hit again to make headway
	var work: float = crew * (1.0 if _hit_ago > 4.0 else 0.25)
	# A fire is fought in minutes and flooding in tens of minutes; scaled down
	# to a match, that is about half a minute for the one and a minute and a
	# half for the other, with a full party.
	fires = maxf(fires - work * 0.030 * delta, 0.0)
	flood = maxf(flood - work * 0.0065 * delta, 0.0)
	if is_instance_valid(_fire_fx):
		_fire_fx.emitting = fires > 0.05
	if is_instance_valid(_flood_fx):
		_flood_fx.emitting = flood > 0.15
	if flood >= 1.0 and alive:
		Sim.report("%s: flooding out of control" % display_name(), Sim.Ev.BAD)
		_founder()

## Rate of advance, after the water she has taken on.
func _damage_speed_factor() -> float:
	return clampf(1.0 - flood * 0.65 - fires * 0.15, 0.15, 1.0)

func fire_gun() -> bool:
	if gun_cd > 0.0 or not alive or not has_gun():
		return false
	gun_cd = 2.6
	rounds += 1
	if ghost:
		# the hull belongs to the host; ask, and watch the round come back
		if Sim.net != null and Sim.net.active:
			Sim.net.request_ship_fire(fleet_idx, 0, aim_yaw, aim_pitch)
		return true
	var muzzle: Vector3 = _gun.global_position + Vector3(0, 1.0, 0) \
		+ Vector3(sin(aim_yaw), 0, -cos(aim_yaw)) * 4.0
	var v := Vector3(sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch),
		-cos(aim_yaw) * cos(aim_pitch)) * 820.0
	var shell := Aircraft.Shell.new()
	shell.vel = v
	shell.damage = 240.0
	shell.blast = 14.0
	shell.arm_dist = 60.0
	shell.shooter = self
	shell.team = team
	get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle
	Effects.muzzle_flash(get_tree().current_scene, muzzle,
		Vector3(sin(aim_yaw), 0, -cos(aim_yaw)), 3.2)
	if Sim.net != null and Sim.net.active and Sim.net.is_host and fleet_idx >= 0:
		Sim.net.rpc("net_ship_shot", fleet_idx, aim_yaw, aim_pitch)
	return true

func is_broken() -> bool:
	return _broken

func is_sinking() -> bool:
	return _sinking >= 0.0

func sink_fraction() -> float:
	return clampf(_sinking / 46.0, 0.0, 1.0) if _sinking >= 0.0 else 0.0

## A round somebody else's ship fired, drawn locally so the battery is visible
## from every screen and not only from the hull that owns it.
func show_shot(yaw: float, pitch: float) -> void:
	aim_yaw = yaw
	aim_pitch = pitch
	if not is_instance_valid(_gun):
		return
	var muzzle: Vector3 = _gun.global_position + Vector3(0, 1.0, 0) \
		+ Vector3(sin(yaw), 0, -cos(yaw)) * 4.0
	Effects.muzzle_flash(get_tree().current_scene, muzzle,
		Vector3(sin(yaw), 0, -cos(yaw)), 3.2)
	var shell := Aircraft.Shell.new()
	shell.vel = Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * 820.0
	shell.damage = 0.0             # the host decides what it hits
	shell.blast = 14.0
	shell.arm_dist = 60.0
	shell.shooter = self
	shell.team = team
	get_tree().current_scene.add_child(shell)
	shell.global_position = muzzle

func hit_radius() -> float:
	return float(KINDS[kind]["beam"]) * 0.7

func is_alive() -> bool:
	return alive

func display_name() -> String:
	return String(KINDS[kind]["name"])

func _physics_process(delta: float) -> void:
	_t += delta
	# A ship somebody else is simulating is a picture: the host does the moving
	# and the fighting. The conn still runs, because that is what draws the
	# camera and reads the wheel — the orders just go over the wire instead of
	# into the hull.
	if ghost:
		gun_cd = maxf(gun_cd - delta, 0.0)
		vls_cd = maxf(vls_cd - delta, 0.0)
		if occupied:
			_conn(delta)
		if is_instance_valid(_gun):
			_gun.rotation.y = wrapf(-aim_yaw - rotation.y, -PI, PI)
			_gun.rotation.x = -aim_pitch
		if is_instance_valid(_fire_fx):
			_fire_fx.emitting = fires > 0.05
		if is_instance_valid(_flood_fx):
			_flood_fx.emitting = flood > 0.15
		return
	if _sinking >= 0.0:
		_sink(delta)
		return
	if not alive:
		return
	_launch_cd = maxf(_launch_cd - delta, 0.0)
	gun_cd = maxf(gun_cd - delta, 0.0)
	vls_cd = maxf(vls_cd - delta, 0.0)
	_damage_control(delta)
	if occupied:
		_conn(delta)
	elif ai and String(KINDS[kind]["class"]) != "civil":
		_captain(delta)
	if occupied or ai or remote_conn != 0:
		# under helm and telegraph rather than steaming a fixed course
		heading = wrapf(heading + helm * delta * 0.10, -PI, PI)
		speed = move_toward(speed, telegraph * float(KINDS[kind]["speed"]), delta * 0.55)
	# Whatever the telegraph says, the water she has taken on decides what she
	# actually makes — and it applies to a hull under nobody's orders too, so a
	# damaged ship left to herself does not keep steaming at full speed.
	speed = minf(speed, float(KINDS[kind]["speed"]) * _damage_speed_factor())
	if is_instance_valid(_gun):
		_gun.rotation.y = wrapf(-aim_yaw - rotation.y, -PI, PI)
		_gun.rotation.x = -aim_pitch
	# steam ahead, with a slow scend so a ship at sea is not a static prop
	global_position += Vector3(sin(heading), 0.0, -cos(heading)) * speed * delta
	# The origin rides ON the waterline; the hull is lofted from keel to deck
	# around it. Sinking the origin to half draught put the whole ship under the
	# sea as far as anything else was concerned, so a weapon aimed at it
	# detonated on the surface above and never touched it.
	global_position.y = Sim.WATER_LEVEL + sin(_t * 0.35) * 0.35
	rotation = Vector3(sin(_t * 0.31) * 0.012, heading,
		sin(_t * 0.24) * 0.02 + list_ang * list_side)
	# turn back at the edge of the world rather than steaming off it
	if absf(global_position.x) > Sim.WORLD_HALF - 3000.0 \
			or absf(global_position.z) > Sim.WORLD_HALF - 3000.0:
		heading = wrapf(heading + PI, -PI, PI)

## She goes down over the better part of a minute: way comes off, the list
## opens out, and the hull settles until the deck is under.
## Where the two halves sit at a given point through the sinking, 0 to 1. The
## after section, which is where the machinery and most of the water is, goes
## down first and steeper. Shared, because a client is told how far along she is
## rather than running the clock itself.
func _pose_sections(t: float, down: float) -> void:
	var l: float = float(KINDS[kind]["len"])
	var age := t * 46.0
	if is_instance_valid(_fore):
		_fore.rotation.x = -clampf(age * 0.020, 0.0, 0.62)
		_fore.rotation.z = list_ang * list_side * 0.4
		_fore.position.y = -down * t * 0.25
		_fore.position.z = l * 0.05 - clampf(age * 0.30, 0.0, 7.0)
	if is_instance_valid(_aft):
		_aft.rotation.x = clampf(age * 0.032, 0.0, 0.95)
		_aft.rotation.z = list_ang * list_side * 1.3
		_aft.position.y = -down * t * 0.85
		_aft.position.z = l * 0.05 + clampf(age * 0.45, 0.0, 11.0)

func _sink(delta: float) -> void:
	_sinking += delta
	speed = move_toward(speed, 0.0, delta * 0.9)
	list_ang = move_toward(list_ang, 1.15, delta * 0.06)
	global_position += Vector3(sin(heading), 0.0, -cos(heading)) * speed * delta
	var kd: Dictionary = KINDS[kind]
	var down: float = float(kd["free"]) + float(kd["draught"]) + 6.0
	var t: float = clampf(_sinking / 46.0, 0.0, 1.0)
	global_position.y = Sim.WATER_LEVEL - down * t
	rotation = Vector3(clampf(_sinking * 0.006, 0.0, 0.20), heading,
		list_ang * list_side)
	if _broken:
		_pose_sections(t, down)
	# the fire drowns before the smoke does
	if is_instance_valid(_wreck_fire) and _sinking > 22.0:
		_wreck_fire.emitting = false
	if is_instance_valid(_wreck_smoke) and _sinking > 40.0:
		_wreck_smoke.emitting = false
	if _sinking > 58.0:
		queue_free()

## Strategic launch. Only a submarine carries one, it comes off the rail
## vertically and pitches over onto the target, and the boat carries two.
var missiles_left := 2
var _launch_cd := 0.0

func can_launch() -> bool:
	return alive and bool(KINDS[kind]["sub"]) and missiles_left > 0 and _launch_cd <= 0.0

func launch_strategic(at: Vector3) -> bool:
	if not can_launch():
		return false
	missiles_left -= 1
	_launch_cd = 25.0
	var m := Missile.new()
	# Clear of the water. The boat rides with its deck at the surface and the
	# hull below it, so a tube exit six metres up is still under the sea as far
	# as the height field is concerned, and the round detonated on the rail.
	var from := Vector3(global_position.x, Sim.WATER_LEVEL + 25.0, global_position.z)
	# Lofted onto the target bearing rather than fired straight up. A rocket at
	# two and a half thousand metres a second pulling six g has a turn radius
	# of a hundred kilometres, so anything launched vertically simply carries on
	# vertically: the trajectory has to be right off the rail.
	var flat := Vector2(at.x - from.x, at.z - from.z)
	var brg := atan2(flat.x, -flat.y)
	var el := deg_to_rad(42.0)
	var dir := Vector3(sin(brg) * cos(el), sin(el), -cos(brg) * cos(el)).normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var xf := Transform3D(Basis.looking_at(dir, up_ref), from)
	var mark := _Aimpoint.new()
	mark.global_position = at
	get_tree().current_scene.add_child(mark)
	m.launch("slbm", xf, dir * 80.0, self, mark)
	get_tree().current_scene.add_child(m)
	Sim.report("%s: strategic launch, %d remaining" % [display_name(), missiles_left],
		Sim.Ev.BAD)
	return true

## A bare node the missile can guide onto, since a patch of ground is not a
## target the seeker can hold by itself.
class _Aimpoint extends Node3D:
	var team := 1
	func is_alive() -> bool:
		return true
	func hit_radius() -> float:
		return 4.0
	func take_hit(_a: float, _f: Node = null) -> void:
		pass

func take_hit(amount: float, from: Node = null) -> void:
	if not alive or amount <= 0.0:
		return
	# In a session the owner of the hull decides whether it died; everyone else
	# reports the hit and waits to be told.
	if ghost:
		if Sim.net != null and Sim.net.active:
			Sim.net.report_ship_damage(self, amount)
		return
	health -= amount
	_hit_ago = 0.0
	# Where it landed decides what it does. A warhead that reaches the water
	# alongside opens her up; one that goes off in the superstructure starts a
	# fire. Both are scaled by how much of the hull the hit represents.
	var frac: float = amount / maxf(float(KINDS[kind]["hp"]), 1.0)
	var below := false
	if from is Node3D:
		below = (from as Node3D).global_position.y < global_position.y + 1.5
	if below or randf() < 0.45:
		flood = clampf(flood + frac * 1.35, 0.0, 1.2)
		if list_ang < 0.02:
			list_side = 1.0 if randf() < 0.5 else -1.0
		if _flood_fx == null:
			_flood_fx = Effects.trail_particles(Color(0.80, 0.84, 0.88), 6.0, 30)
			_flood_fx.position = Vector3(float(KINDS[kind]["beam"]) * 0.4 * list_side,
				0.5, 0.0)
			add_child(_flood_fx)
	else:
		fires = clampf(fires + frac * 1.6, 0.0, 1.0)
		if _fire_fx == null:
			_fire_fx = Effects.trail_particles(Color(0.30, 0.28, 0.27), 9.0, 40)
			_fire_fx.position = Vector3(0, float(KINDS[kind]["free"]) + 3.0, 0)
			add_child(_fire_fx)
	# a mission kill first: she stops fighting well before she goes down
	if health <= 0.0:
		_founder()

## Hull gone, or flooded past saving. She is out of the fight from here and on
## her way to the bottom; she is no longer a target worth shooting at.
func _founder() -> void:
	if not alive:
		return
	alive = false
	_sinking = 0.0
	telegraph = 0.0
	occupied = false
	ai = false
	Effects.explosion(get_tree().current_scene,
		global_position + Vector3(0, 6, 0), float(KINDS[kind]["beam"]) * 1.6)
	_break_up()
	remove_from_group("hittable")
	remove_from_group("boardable")
	Sim.score += 400
	Sim.report("%s sunk" % display_name(), Sim.Ev.GOOD)

## She breaks her back. The intact hull is put away and two sections are lofted
## from the same station profile either side of the break, each hung on a node
## at the break itself so it tips about the fracture rather than about the
## middle of a ship that no longer exists. They go down at different rates and
## different angles, which is what makes it read as a breakup rather than as a
## whole ship being lowered into the sea.
func _break_up() -> void:
	var kd: Dictionary = KINDS[kind]
	var l: float = kd["len"]
	var fb: float = kd["free"]
	# Small craft do not break in two; they burn, fill and go under. A frigate
	# and up is long enough for the sea to do it.
	_broken = l > 90.0
	if is_instance_valid(_hull_mi) and _broken:
		_hull_mi.visible = false
	if _broken:
		var brk := 0.05                     # just abaft midships
		_fore = Node3D.new()
		_fore.name = "ForeSection"
		_fore.position = Vector3(0, 0, brk * l)
		add_child(_fore)
		_fore.add_child(MeshKit.mi(_loft_hull(kd, -0.50, brk, -brk * l), "Fore"))
		_aft = Node3D.new()
		_aft.name = "AftSection"
		_aft.position = Vector3(0, 0, brk * l)
		add_child(_aft)
		_aft.add_child(MeshKit.mi(_loft_hull(kd, brk, 0.50, -brk * l), "Aft"))
		# torn plating at the fracture, on both faces
		for sec in [_fore, _aft]:
			var tst := MeshKit.begin()
			for i in 7:
				var ang := TAU * float(i) / 7.0
				MeshKit.box(tst, Vector3(randf_range(1.5, 4.0), randf_range(1.0, 3.0),
					randf_range(1.0, 2.5)),
					Vector3(cos(ang) * float(kd["beam"]) * 0.30,
						sin(ang) * 3.0 + fb * 0.3, randf_range(-1.5, 1.5)))
			sec.add_child(MeshKit.mi(MeshKit.finish(tst,
				MeshKit.mat(Color(0.16, 0.16, 0.17), 0.75, 0.3)), "Torn"))
		Sim.report("%s breaks in two" % display_name(), Sim.Ev.BAD)
	# burning, then smoking, for as long as anything is still above water
	var fire := Effects.ember_particles(Color(1.0, 0.55, 0.15), 5.0, 34)
	fire.emitting = true
	fire.position = Vector3(0, fb + 2.0, -l * 0.12)
	add_child(fire)
	_wreck_fire = fire
	var smoke := Effects.trail_particles(Color(0.16, 0.16, 0.17), 16.0, 52)
	smoke.emitting = true
	smoke.position = Vector3(0, fb + 5.0, -l * 0.10)
	add_child(smoke)
	_wreck_smoke = smoke
	if is_instance_valid(_wake):
		_wake.emitting = false
	# and wreckage on the water, which is what is left once she has gone
	var host := get_parent()
	for i in 9:
		if host == null:
			break
		var d := Effects.Debris.new()
		d.floats = true
		d.life = 240.0
		var sz := Vector3(randf_range(0.8, 3.4), randf_range(0.3, 1.0),
			randf_range(0.8, 4.0))
		d.rest_offset = sz.y * 0.4
		var db := MeshKit.begin()
		MeshKit.box(db, sz, Vector3.ZERO)
		d.add_child(MeshKit.mi(MeshKit.finish(db,
			MeshKit.mat(Color(kd["paint"]).darkened(0.35), 0.9, 0.1)), "Flotsam"))
		host.add_child(d)
		d.global_position = global_position + Vector3(randf_range(-8, 8),
			fb + 3.0, randf_range(-l * 0.3, l * 0.3))
		d.vel = Vector3(randf_range(-7, 7), randf_range(3, 9), randf_range(-7, 7))
		d.spin = Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))

## Host-side state arriving on a client. The hull is posed rather than
## simulated, and the damage state comes with it so the fires and the list look
## the same on every screen.
func net_apply(pos: Vector3, yaw: float, hp: float, fl: float, fi: float,
		side: float, flags: int) -> void:
	global_position = pos
	heading = yaw
	health = hp
	flood = fl
	fires = fi
	list_side = side
	list_ang = flood * 0.42
	crew = clampf(health / maxf(float(KINDS[kind]["hp"]), 1.0), 0.0, 1.0)
	var was := alive
	alive = (flags & 1) != 0
	if fires > 0.05 and _fire_fx == null:
		_fire_fx = Effects.trail_particles(Color(0.30, 0.28, 0.27), 9.0, 40)
		_fire_fx.position = Vector3(0, float(KINDS[kind]["free"]) + 3.0, 0)
		add_child(_fire_fx)
	if flood > 0.15 and _flood_fx == null:
		_flood_fx = Effects.trail_particles(Color(0.80, 0.84, 0.88), 6.0, 30)
		_flood_fx.position = Vector3(float(KINDS[kind]["beam"]) * 0.4 * list_side, 0.5, 0)
		add_child(_flood_fx)
	if was and not alive:
		Effects.explosion(get_tree().current_scene, global_position + Vector3(0, 6, 0),
			float(KINDS[kind]["beam"]) * 1.6)
		# She breaks up here too. Without this a client watched a ship it had
		# just helped sink go quietly still and stay whole, while on the host
		# she was in two pieces and burning.
		_break_up()
		remove_from_group("hittable")
		remove_from_group("boardable")
		Sim.report("%s sunk" % display_name(), Sim.Ev.GOOD)
	if (flags & 2) != 0:
		# going down: take the settle and the list straight from the host
		var frac: float = clampf(float(flags >> 8) / 255.0, 0.0, 1.0)
		_sinking = frac * 46.0
		list_ang = 1.15 * frac
		var kd: Dictionary = KINDS[kind]
		var down: float = float(kd["free"]) + float(kd["draught"]) + 6.0
		global_position.y = Sim.WATER_LEVEL - down * frac
		if _broken:
			_pose_sections(frac, down)
		if is_instance_valid(_wreck_fire):
			_wreck_fire.emitting = frac < 0.48
		if is_instance_valid(_wreck_smoke):
			_wreck_smoke.emitting = frac < 0.87
	rotation = Vector3(0.0, heading, list_ang * list_side)

## Orders from whoever holds the conn, applied on the host.
func net_orders(h: float, tg: float, yaw: float, pitch: float) -> void:
	helm = h
	telegraph = tg
	aim_yaw = yaw
	aim_pitch = pitch

## What the crew are dealing with, for the conn readout.
func damage_report() -> String:
	if not alive:
		return "ABANDON SHIP"
	var bits := PackedStringArray()
	bits.append("HULL %d%%" % int(round(100.0 * clampf(
		health / maxf(float(KINDS[kind]["hp"]), 1.0), 0.0, 1.0))))
	if fires > 0.05:
		bits.append("FIRE %d%%" % int(round(fires * 100.0)))
	if flood > 0.05:
		bits.append("FLOOD %d%%" % int(round(flood * 100.0)))
	if flood > 0.05 or fires > 0.05:
		bits.append("DC PARTY %d%%" % int(round(crew * 100.0)))
	return "  ".join(bits)
