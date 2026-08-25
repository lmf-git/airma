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
		"mast": 0.0, "guns": 0, "class": "sub",
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
var team := 1
var health := 1000.0
var alive := true
var heading := 0.0
var speed := 0.0
var _t := 0.0
var _wake: GPUParticles3D

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
	var dr: float = kd["draught"]
	var fb: float = kd["free"]
	var st := MeshKit.begin()
	var rings := []
	# station, half beam factor, keel, deck edge
	var stations := [[-0.50, 0.06], [-0.42, 0.36], [-0.28, 0.72], [-0.05, 1.00],
		[0.22, 0.98], [0.42, 0.86], [0.50, 0.72]]
	for s in stations:
		var z: float = float(s[0]) * l
		var hw: float = float(s[1]) * b * 0.5
		var pts := PackedVector3Array()
		var n := 10
		for i in n:
			var a := TAU * float(i) / float(n)
			var x: float = cos(a) * hw
			var y: float = sin(a)
			y = (fb * y) if y > 0.0 else (dr * y)
			pts.append(Vector3(x, y, z))
		rings.append(pts)
	MeshKit.loft(st, rings, Vector3(0, 0, 0))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(kd["paint"], 0.85, 0.05)), "Hull"))

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

## Take the conn. Everything below is only run for the ship the player is on.
func mount(on: bool) -> void:
	occupied = on
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
	var from: Vector3 = global_position + Vector3(0, float(KINDS[kind]["free"]) + 3.0,
		-float(KINDS[kind]["len"]) * 0.30)
	var m := Missile.new()
	# straight up out of the cell; it tips over onto the contact once clear
	var xf := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), from)
	m.launch("aim120", xf, Vector3(0, 55.0, 0), self, tgt)
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
	var w := Input.get_action_strength(&"roll_right") - Input.get_action_strength(&"roll_left")
	helm = move_toward(helm, w, delta * 1.4)
	var t := Input.get_action_strength(&"pitch_down") - Input.get_action_strength(&"pitch_up")
	telegraph = clampf(telegraph + t * delta * 0.35, -0.25, 1.0)
	if Input.is_action_just_pressed(&"interact"):
		dismount_requested.emit()
	if Input.is_action_just_pressed(&"cycle_weapon"):
		cycle_weapon()
	for wi in weapons().size():
		if Input.is_action_just_pressed(StringName("weapon_%d" % (wi + 1))):
			set_weapon(wi)
	if Input.is_action_pressed(&"fire") and not Sim.ui_modal:
		if current_weapon() == "vls":
			if Input.is_action_just_pressed(&"fire"):
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

func fire_gun() -> bool:
	if gun_cd > 0.0 or not alive or not has_gun():
		return false
	gun_cd = 2.6
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
	return true

func hit_radius() -> float:
	return float(KINDS[kind]["beam"]) * 0.7

func is_alive() -> bool:
	return alive

func display_name() -> String:
	return String(KINDS[kind]["name"])

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	_launch_cd = maxf(_launch_cd - delta, 0.0)
	gun_cd = maxf(gun_cd - delta, 0.0)
	vls_cd = maxf(vls_cd - delta, 0.0)
	if occupied:
		_conn(delta)
		# under helm and telegraph rather than steaming a fixed course
		heading = wrapf(heading + helm * delta * 0.10, -PI, PI)
		speed = move_toward(speed, telegraph * float(KINDS[kind]["speed"]), delta * 0.55)
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
	rotation = Vector3(sin(_t * 0.31) * 0.012, heading, sin(_t * 0.24) * 0.02)
	# turn back at the edge of the world rather than steaming off it
	if absf(global_position.x) > Sim.WORLD_HALF - 3000.0 \
			or absf(global_position.z) > Sim.WORLD_HALF - 3000.0:
		heading = wrapf(heading + PI, -PI, PI)

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

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
		speed = 0.0
		Effects.explosion(get_tree().current_scene,
			global_position + Vector3(0, 6, 0), float(KINDS[kind]["beam"]) * 1.6)
		var smoke := Effects.trail_particles(Color(0.22, 0.22, 0.23), 12.0, 40)
		smoke.emitting = true
		add_child(smoke)
		remove_from_group("hittable")
		Sim.score += 400
		Sim.report("%s sunk" % display_name(), Sim.Ev.GOOD)
