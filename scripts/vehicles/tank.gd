class_name Tank
extends RigidBody3D
## Main battle tank. Each road wheel is an independent spring/damper contact
## against the terrain field with its own longitudinal and lateral friction, so
## the hull pitches over crests, rolls in turns and the tracks actually drive it
## rather than the body being slid around.

signal died(who)
signal dismount_requested()

const WHEELS_PER_SIDE := 7
const TRACK_HALF := 1.72          # half track width, wheel centreline
const WHEEL_R := 0.42
const REST := 0.55                # suspension travel at rest
const MAX_SPEED := 18.0           # governed, about 65 km/h
const POWER := 1_100_000.0        # 1500 hp at the sprockets
const DRIVE_MAX := 240000.0       # traction limit, roughly 0.4 g on 62 tonnes
const BRAKE := 420000.0
const ROLL_RESIST := 0.035

const KINDS := {
	"m1a2": {"name": "M1A2 Abrams", "class": "mbt", "hull": Color(0.31, 0.33, 0.27),
			 "hp": 300.0, "power": 1_100_000.0, "top": 18.0, "gun": 520.0,
			 "muzzle": 1580.0, "reload": 6.5, "blast": 11.0},
	"t90": {"name": "T-90M Proryv", "class": "mbt", "hull": Color(0.26, 0.30, 0.22),
			"hp": 250.0, "power": 840_000.0, "top": 16.5, "gun": 560.0,
			"muzzle": 1660.0, "reload": 7.5, "blast": 11.5},
	"type99": {"name": "ZTZ-99A", "class": "mbt", "hull": Color(0.29, 0.31, 0.26),
			   "hp": 260.0, "power": 1_000_000.0, "top": 17.5, "gun": 540.0,
			   "muzzle": 1600.0, "reload": 7.0, "blast": 11.0},
	"m109": {"name": "M109A7 Paladin", "class": "spg", "hull": Color(0.30, 0.32, 0.26),
			 "hp": 190.0, "power": 520_000.0, "top": 13.5, "gun": 900.0,
			 "muzzle": 560.0, "reload": 9.0, "blast": 26.0},
	"msta": {"name": "2S19 Msta-S", "class": "spg", "hull": Color(0.25, 0.29, 0.21),
			 "hp": 185.0, "power": 500_000.0, "top": 13.0, "gun": 940.0,
			 "muzzle": 590.0, "reload": 10.0, "blast": 27.0},
	"m270": {"name": "M270 MLRS", "class": "mlrs", "hull": Color(0.28, 0.31, 0.25),
			 "hp": 160.0, "power": 480_000.0, "top": 15.0, "gun": 420.0,
			 "muzzle": 420.0, "reload": 26.0, "blast": 19.0, "salvo": 12, "ripple": 0.55},
	"bm30": {"name": "BM-30 Smerch", "class": "mlrs", "hull": Color(0.24, 0.28, 0.20),
			 "hp": 150.0, "power": 440_000.0, "top": 14.0, "gun": 470.0,
			 "muzzle": 450.0, "reload": 30.0, "blast": 21.0, "salvo": 12, "ripple": 0.6},
}

var kind := "m1a2"
var team := 0
var health := 260.0
var alive := true
var occupied := false

# driver inputs
var in_throttle := 0.0            # -1 reverse .. +1 forward
var in_steer := 0.0               # -1 left .. +1 right
var in_brake := false
var turret_yaw := 0.0             # desired, world relative
var turret_pitch := 0.0

var speed := 0.0
var _turret: Node3D
var _mantlet: Node3D
var _muzzle: Node3D
var _road_wheels: Array = []      # {node, side, index, rest_y, spin}
var _wheel_spin := 0.0
var rounds_left := 1              # rounds on the rails, refilled on resupply
var bounds := AABB()              # local model extents, for hull_distance()
var sel_weapon := 0               # 0 main gun, 1 coax
var laying := false               # laid on? false once the piece is on target
var _gun_cd := 0.0
var cam: Camera3D
var gunner := false
var aim_yaw := 0.0
var aim_pitch := 0.0
var _cam_yaw := 0.0
var last_solution := {}
var _aim_cache := Vector3.ZERO
var _aim_cache_key := Vector3.ZERO
var _aim_cache_map := Vector3.INF
var _aim_cache_t := 0
## A point picked off the map overrides the barrel line.
var map_target := Vector3.INF
## Indirect pieces are laid by bearing and range. Trying to place a crosshair on
## distant ground with a barrel that only depresses a few degrees is hopeless:
## a tenth of a degree is a kilometre of range.
var arty_range := 4000.0
var _coax_cd := 0.0

func setup(t := 0, k := "m1a2") -> void:
	team = t
	kind = k if KINDS.has(k) else "m1a2"
	var kd: Dictionary = KINDS[kind]
	health = float(kd["hp"])
	rounds_left = int(kd.get("salvo", 1))
	mass = 62000.0
	inertia = Vector3(120000.0, 140000.0, 60000.0)
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	collision_layer = 0
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.7, 2.0, 7.9)
	shape.shape = box
	add_child(shape)
	_build()
	_cache_bounds()
	add_to_group("hittable")
	add_to_group("vehicles")
	add_to_group("boardable")
	cam = Camera3D.new()
	cam.far = 45000.0
	cam.near = 0.15
	cam.fov = 70.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)

# --------------------------------------------------------------------------
func _build() -> void:
	var body := MeshKit.panelled(KINDS[kind]["hull"], 0.92, 0.10, 1.1)
	var dark := MeshKit.mat(Color(0.11, 0.11, 0.12), 0.85, 0.2)

	var st := MeshKit.begin()
	# lower hull, glacis and side skirts
	MeshKit.box(st, Vector3(3.5, 0.85, 7.3), Vector3(0, 0.10, 0))
	var glacis := PackedVector2Array([Vector2(-1.75, -3.65), Vector2(1.75, -3.65),
		Vector2(1.75, -1.30), Vector2(-1.75, -1.30)])
	MeshKit.prism(st, glacis, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		PackedFloat32Array([0.06, 0.06, 0.40, 0.40]), Vector3(0, 0.72, 0))
	MeshKit.box(st, Vector3(3.42, 0.62, 4.9), Vector3(0, 0.86, 0.9))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.16, 0.72, 7.0), Vector3(sx * 1.79, 0.62, 0.1))
		MeshKit.box(st, Vector3(0.55, 0.30, 1.5), Vector3(sx * 1.5, 1.30, 2.9))
	MeshKit.box(st, Vector3(1.2, 0.45, 1.1), Vector3(0, 1.28, 3.2))   # engine deck
	if vclass() == "spg":
		MeshKit.box(st, Vector3(2.6, 0.35, 1.2), Vector3(0, 0.30, 4.1))   # recoil spade
	add_child(MeshKit.mi(MeshKit.finish(st, body), "Hull"))

	# tracks: belt shell plus separate road wheels that follow the suspension
	var tst := MeshKit.begin()
	for sx in [-1.0, 1.0]:
		var belt := PackedVector2Array([
			Vector2(-3.9, 0.06), Vector2(-3.35, 0.95), Vector2(3.35, 0.95), Vector2(3.9, 0.06),
			Vector2(3.35, -0.30), Vector2(-3.35, -0.30)])
		MeshKit.prism(tst, belt, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
			PackedFloat32Array([0.30, 0.30, 0.30, 0.30, 0.30, 0.30]),
			Vector3(sx * TRACK_HALF, 0.02, 0))
	add_child(MeshKit.mi(MeshKit.finish(tst, dark), "Tracks"))

	for sx in [-1.0, 1.0]:
		for i in WHEELS_PER_SIDE:
			var z := lerpf(-2.95, 2.95, float(i) / float(WHEELS_PER_SIDE - 1))
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = WHEEL_R
			cyl.bottom_radius = WHEEL_R
			cyl.height = 0.34
			cyl.radial_segments = 10
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.17, 0.18, 0.17), 0.9, 0.1)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * TRACK_HALF, -0.18, z)
			add_child(w)
			_road_wheels.append({"node": w, "side": sx, "z": z, "rest_y": -0.18, "comp": 0.0})

	# turret and gun
	_turret = Node3D.new()
	_turret.name = "Turret"
	_turret.position = Vector3(0, 1.20, 0.55)
	add_child(_turret)
	var tu := MeshKit.begin()
	match vclass():
		"mlrs":
			# armoured cab up front, rotating launcher cradle behind it
			MeshKit.box(tu, Vector3(2.9, 1.05, 2.3), Vector3(0, 0.50, -1.4))
			MeshKit.box(tu, Vector3(2.5, 0.35, 0.9), Vector3(0, 1.05, -0.3))
		"spg":
			var plan_spg := PackedVector2Array([Vector2(-1.45, -1.60), Vector2(-1.60, 0.30),
				Vector2(-1.35, 2.20), Vector2(1.35, 2.20), Vector2(1.60, 0.30), Vector2(1.45, -1.60)])
			MeshKit.prism(tu, plan_spg, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
				PackedFloat32Array([0.52, 0.58, 0.58, 0.58, 0.58, 0.52]), Vector3(0, 0.52, 0))
			MeshKit.box(tu, Vector3(2.4, 0.55, 0.7), Vector3(0, 0.60, 2.35))   # ammo bustle
			MeshKit.box(tu, Vector3(0.55, 0.35, 0.55), Vector3(-0.85, 1.15, 0.4))
		_:
			var plan := PackedVector2Array([Vector2(-1.30, -1.85), Vector2(-1.55, -0.20),
				Vector2(-1.25, 1.75), Vector2(1.25, 1.75), Vector2(1.55, -0.20), Vector2(1.30, -1.85)])
			MeshKit.prism(tu, plan, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
				PackedFloat32Array([0.34, 0.40, 0.40, 0.40, 0.40, 0.34]), Vector3(0, 0.34, 0))
			MeshKit.box(tu, Vector3(0.75, 0.30, 0.85), Vector3(-0.55, 0.80, 0.55))
			MeshKit.box(tu, Vector3(0.42, 0.22, 0.60), Vector3(0.72, 0.78, 0.30))
			MeshKit.box(tu, Vector3(1.9, 0.42, 0.28), Vector3(0, 0.42, 1.80))
	_turret.add_child(MeshKit.mi(MeshKit.finish(tu, body), "TurretShell"))

	_mantlet = Node3D.new()
	_mantlet.name = "Mantlet"
	_mantlet.position = Vector3(0, 0.36, -1.55) if vclass() != "mlrs" else Vector3(0, 1.25, 1.0)
	_turret.add_child(_mantlet)
	var gst := MeshKit.begin()
	match vclass():
		"mlrs":
			# two pods of six tubes on an elevating cradle
			for px in [-0.62, 0.62]:
				for row in 2:
					for col in 3:
						var cy := 0.30 + float(row) * 0.44
						var cx: float = float(px) + (float(col) - 1.0) * 0.42
						MeshKit.cone(gst, 0.19, 0.19, -1.9, 1.9, Vector3(cx, cy, 0), 8)
			MeshKit.box(gst, Vector3(2.9, 0.22, 0.5), Vector3(0, 0.05, 1.2))
		"spg":
			MeshKit.box(gst, Vector3(1.15, 0.72, 0.62), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.19, 0.155, -7.4, 0.0, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.30, 0.30, -2.4, -1.2, Vector3.ZERO, 10)   # fume extractor
			MeshKit.cone(gst, 0.27, 0.27, -7.7, -7.2, Vector3.ZERO, 10)   # muzzle brake
		_:
			MeshKit.box(gst, Vector3(1.05, 0.62, 0.55), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.135, 0.115, -5.6, 0.0, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.20, 0.20, -4.3, -3.3, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.19, 0.19, -5.75, -5.35, Vector3.ZERO, 10)
	_mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -8.0) if vclass() == "spg" else (
		Vector3(0, 0.55, -2.1) if vclass() == "mlrs" else Vector3(0, 0, -5.9))
	_mantlet.add_child(_muzzle)

# --------------------------------------------------------------------------
## Garrison crew: find something hostile, traverse onto it and shoot. Direct
## fire vehicles lead the target; the artillery pieces arc onto it.
func _ai_think(delta: float) -> void:
	_ai_scan -= delta
	if _ai_scan <= 0.0:
		_ai_scan = 1.2
		_ai_target = null
		var best := 1e9
		var reach: float = 22000.0 if is_indirect() else 2600.0
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == self:
				continue
			if ("team" in n) and n.team == team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			# an artillery piece does not shoot at aircraft
			if is_indirect() and (n is Aircraft):
				continue
			var d: float = global_position.distance_to(n.global_position)
			var agl: float = n.global_position.y - Sim.height_at(n.global_position.x,
				n.global_position.z)
			if n is Aircraft and agl > 900.0:
				continue
			if d < reach and d < best:
				best = d
				_ai_target = n
	if _ai_target == null or not is_instance_valid(_ai_target):
		return
	var tp: Vector3 = _ai_target.global_position
	if "linear_velocity" in _ai_target:
		var tof: float = global_position.distance_to(tp) / 1500.0
		tp += (_ai_target.linear_velocity as Vector3) * tof
	if is_indirect():
		aim_yaw = atan2(tp.x - global_position.x, -(tp.z - global_position.z))
		map_target = Vector3(tp.x, Sim.height_at(tp.x, tp.z), tp.z)
	else:
		aim_at(tp)
		aim_yaw = turret_yaw
		aim_pitch = turret_pitch
	var lay: float = absf(wrapf(-turret_yaw - (rotation.y + _turret.rotation.y), -PI, PI))
	if lay < 0.05 and _gun_cd <= 0.0:
		fire_main(get_tree().current_scene)
	if not is_indirect() and lay < 0.08 \
			and global_position.distance_to(_ai_target.global_position) < 1400.0:
		fire_coax(get_tree().current_scene)

func mount(on: bool) -> void:
	occupied = on
	if on:
		cam.current = true
		aim_yaw = -(rotation.y + _turret.rotation.y)
		_cam_yaw = rotation.y
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func display_name() -> String:
	return String(KINDS[kind]["name"])

func _unhandled_input(e: InputEvent) -> void:
	if not occupied or not alive:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		aim_yaw -= mm.relative.x * 0.0026
		if is_indirect():
			# pushing away walks the fall of shot out, pulling back brings it in
			arty_range = clampf(arty_range - mm.relative.y * 18.0, 300.0, 32000.0)
			map_target = Vector3.INF
		else:
			aim_pitch = clampf(aim_pitch - mm.relative.y * 0.0022,
				deg_to_rad(-9.0), deg_to_rad(20.0))

func _drive_input(delta: float) -> void:
	in_throttle = Input.get_action_strength(&"pitch_down") - Input.get_action_strength(&"pitch_up")
	in_steer = Input.get_action_strength(&"roll_right") - Input.get_action_strength(&"roll_left")
	in_brake = Input.is_action_pressed(&"brakes")
	turret_yaw = aim_yaw
	if is_indirect():
		# lay the barrel at the live firing solution so what you see is what the
		# gun will actually do
		var aim := ground_aim()
		var sol := fire_solution(aim, float(KINDS[kind]["muzzle"])) if aim != Vector3.INF else {}
		turret_pitch = float(sol["elev"]) if not sol.is_empty() else deg_to_rad(40.0)
		if map_target != Vector3.INF:
			turret_yaw = atan2(map_target.x - global_position.x,
				-(map_target.z - global_position.z))
			# and the readout follows the piece. aim_yaw is what the HUD prints
			# as BEARING and what the wheel steers; leaving it on the mouse
			# heading while the tubes swung to the map target is why the
			# displayed bearing disagreed with where the launcher was facing.
			aim_yaw = turret_yaw
	else:
		turret_pitch = aim_pitch
	if Input.is_action_just_pressed(&"camera"):
		gunner = not gunner
	# Weapon select works the way it does in the air: cycle, or pick directly.
	# The trigger is then just a trigger, whichever weapon is up.
	if Input.is_action_just_pressed(&"cycle_weapon"):
		cycle_weapon()
	for wi in weapons().size():
		if Input.is_action_just_pressed(StringName("weapon_%d" % (wi + 1))):
			set_weapon(wi)
	# ALT/META + right click is the sensor page chord. The trigger is also on
	# right click, so without this the act of opening the sensors fired the gun.
	var chord := Input.is_action_pressed(&"freelook") or Sim.ui_modal
	var held := Input.is_action_pressed(&"fire") and not chord
	var tapped := Input.is_action_just_pressed(&"fire") and not chord
	if current_weapon() == "coax":
		if held:
			fire_coax(get_tree().current_scene)
	else:
		# a launcher walks its pod out while the trigger is held; everything
		# else is one round per press. Designating on the map lays the piece and
		# nothing more -- the round goes when the crew is told.
		if tapped or (is_ripple() and held):
			fire_main(get_tree().current_scene)
	# V still works as a dedicated coax key whatever is selected
	if Input.is_action_pressed(&"gun") and current_weapon() != "coax":
		fire_coax(get_tree().current_scene)
	if Input.is_action_just_pressed(&"interact"):
		dismount_requested.emit()
	# camera
	if gunner:
		var sight: Vector3 = _mantlet.global_transform * Vector3(0.55, 0.55, -0.4)
		cam.global_position = sight
		cam.global_transform.basis = _mantlet.global_transform.basis
		cam.fov = lerpf(cam.fov, 24.0, clampf(delta * 6.0, 0, 1))
	else:
		_cam_yaw = lerp_angle(_cam_yaw, aim_yaw, clampf(delta * 3.0, 0, 1))
		# Sit the camera BEHIND the bearing the turret is laid on. Built with a
		# positive sine the rig ended up looking along the mirror image of it:
		# tubes on 010, camera on 349. The gun then appeared to swing the
		# opposite way to the cursor.
		var back := Vector3(-sin(_cam_yaw), 0, cos(_cam_yaw))
		var want := global_position + Vector3(0, 4.2, 0) + back * 11.0
		want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 2.2)
		cam.global_position = cam.global_position.lerp(want, clampf(delta * 8.0, 0, 1)) \
			if cam.global_position.length() > 0.1 else want
		cam.look_at(global_position + Vector3(0, 1.8, 0), Vector3.UP)
		cam.fov = lerpf(cam.fov, 70.0, clampf(delta * 6.0, 0, 1))

var scripted := false          # test harness drives the sticks directly
var ai := false                # garrison crews traverse and shoot on their own
var _ai_target: Node3D = null
var _ai_scan := 0.0

func _physics_process(delta: float) -> void:
	if ai and alive and not occupied:
		_ai_think(delta)
	if occupied and alive and not scripted:
		_drive_input(delta)
	elif occupied and alive:
		turret_yaw = aim_yaw
		turret_pitch = aim_pitch
	_gun_cd = maxf(_gun_cd - delta, 0.0)
	_coax_cd = maxf(_coax_cd - delta, 0.0)
	if _gun_cd <= 0.0 and int(KINDS[kind].get("salvo", 1)) <= 1:
		rounds_left = 1
	if not alive:
		return
	# turret slew, rate limited like a real drive
	# A node rotated about +Y by theta points its -Z axis at bearing -theta, so
	# the yaw command has to be negated to drive the barrel to a world bearing.
	# Without this the turret laid on the mirror image of the target: the fall
	# of shot was right because the solution supplies its own vector, but the
	# tubes visibly pointed twenty degrees the other way.
	var yaw_err := wrapf(-turret_yaw - (rotation.y + _turret.rotation.y), -PI, PI)
	_turret.rotation.y += clampf(yaw_err, -0.9 * delta, 0.9 * delta)
	var max_el: float = deg_to_rad(70.0) if vclass() != "mbt" else deg_to_rad(20.0)
	_mantlet.rotation.x = lerp_angle(_mantlet.rotation.x,
		clampf(turret_pitch, deg_to_rad(-9.0), max_el), clampf(delta * 2.2, 0, 1))
	_wheel_spin += speed / WHEEL_R * delta
	for w in _road_wheels:
		var n: Node3D = w["node"]
		n.position.y = lerpf(n.position.y, float(w["rest_y"]) + float(w["comp"]),
			clampf(delta * 14.0, 0, 1))
		n.transform.basis = Basis(Vector3(1, 0, 0), _wheel_spin) * Basis(Vector3(0, 0, 1), PI * 0.5)

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	# A knocked out tank keeps its suspension. Skipping the whole physics step
	# because the crew is dead leaves nothing holding the hull up and the hulk
	# sinks through the terrain for ever: there is no world collision mesh, the
	# ground only exists because these wheels look it up.
	if not alive:
		in_throttle = 0.0      # nothing is driving a wreck; let it roll to a stop
		in_steer = 0.0
		in_brake = true
	var xf := state.transform
	var fwd := -xf.basis.z
	speed = state.linear_velocity.dot(fwd)

	var contacts := 0
	var k: float = mass * 9.81 * 2.6 / REST
	var c: float = 1.05 * sqrt(k * mass / float(WHEELS_PER_SIDE * 2))
	for w in _road_wheels:
		var lp := Vector3(float(w["side"]) * TRACK_HALF, float(w["rest_y"]), float(w["z"]))
		var wp: Vector3 = xf * lp
		var ground := Sim.height_at(wp.x, wp.z)
		var comp: float = (ground + WHEEL_R) - wp.y
		w["comp"] = clampf(comp, -REST, REST * 0.6)
		if comp <= 0.0:
			continue
		contacts += 1
		comp = minf(comp, REST)
		var n := Sim.normal_at(wp.x, wp.z)
		var arm := wp - xf.origin
		var pv := state.linear_velocity + state.angular_velocity.cross(arm)
		var fn: float = maxf(k * comp - c * pv.dot(n), 0.0) / float(WHEELS_PER_SIDE * 2) * 2.0
		fn = minf(fn, mass * 9.81 * 1.6)
		var f := n * fn
		# tracks: strong lateral bite, drive split left and right for steering
		var roll_dir := (fwd - n * fwd.dot(n)).normalized()
		var lat_dir := n.cross(roll_dir).normalized()
		var grip: float = Sim.surface_grip(wp.x, wp.z)
		var mu_lat: float = 2.4 * grip
		f += lat_dir * clampf(-pv.dot(lat_dir) * mass * 1.6, -mu_lat * fn, mu_lat * fn)
		var side_cmd: float = in_throttle + in_steer * float(w["side"]) * 0.85
		side_cmd = clampf(side_cmd, -1.0, 1.0)
		var v_roll := pv.dot(roll_dir)
		# power limited tractive effort: strong off the mark, tailing off with
		# road speed the way a real drivetrain does
		var want: float = side_cmd * float(KINDS[kind]["top"]) * (0.65 if grip < 0.9 else 1.0)
		var avail: float = minf(DRIVE_MAX, float(KINDS[kind]["power"]) / maxf(absf(v_roll), 3.0)) \
			/ float(WHEELS_PER_SIDE * 2) * 2.0
		var drive: float = clampf((want - v_roll) * mass * 0.30, -avail, avail)
		drive -= signf(v_roll) * ROLL_RESIST * fn
		if in_brake:
			drive = clampf(-v_roll * mass * 2.0, -BRAKE / float(WHEELS_PER_SIDE),
				BRAKE / float(WHEELS_PER_SIDE))
		var mu_roll: float = 1.5 * grip
		drive = clampf(drive, -mu_roll * fn, mu_roll * fn)
		f += roll_dir * drive
		state.apply_force(f, arm)

	if contacts == 0:
		return
	# resist the hull trying to spin up on its own
	state.apply_torque(-Vector3(0, state.angular_velocity.y, 0) * mass * 2.4)

# --------------------------------------------------------------------------
func vclass() -> String:
	return String(KINDS[kind].get("class", "mbt"))

## A multiple launcher ripples its pod; a howitzer loads one round at a time.
## What this vehicle can shoot with, in selection order.
func weapons() -> PackedStringArray:
	var w := PackedStringArray([String(KINDS[kind].get("class", "mbt"))])
	w[0] = "main"
	if vclass() == "mbt":
		w.append("coax")
	return w

func current_weapon() -> String:
	var w := weapons()
	return w[clampi(sel_weapon, 0, w.size() - 1)]

func weapon_label() -> String:
	return "MAIN GUN" if current_weapon() == "main" else "COAXIAL"

func set_weapon(i: int) -> void:
	var w := weapons()
	if i < 0 or i >= w.size() or i == sel_weapon:
		return
	sel_weapon = i
	Sim.report(weapon_label(), Sim.Ev.INFO)

func cycle_weapon() -> void:
	set_weapon((sel_weapon + 1) % weapons().size())

func is_ripple() -> bool:
	return int(KINDS[kind].get("salvo", 1)) > 1

func is_indirect() -> bool:
	return vclass() != "mbt"

## March the barrel line onto the ground: where the crosshair is pointing. The
## march samples the height field a hundred times, so the answer is cached for a
## few frames rather than recomputed for the HUD and the gun separately.
func ground_aim() -> Vector3:
	# The march down the height field is expensive, so the answer is cached for
	# a few frames -- but the cache has to know what it was computed FROM.
	# Keyed on time alone, designating a target on the map and pressing fire in
	# the same breath laid the tubes on the new bearing and sent the rounds to
	# the old one, kilometres away.
	var key := Vector3(aim_yaw, arty_range, aim_pitch)
	var now := Time.get_ticks_msec()
	if now - _aim_cache_t < 100 and _aim_cache != Vector3.ZERO \
			and key.is_equal_approx(_aim_cache_key) \
			and map_target.is_equal_approx(_aim_cache_map):
		return _aim_cache
	_aim_cache_t = now
	_aim_cache_key = key
	_aim_cache_map = map_target
	_aim_cache = _ground_aim_now()
	return _aim_cache

func _ground_aim_now() -> Vector3:
	if map_target != Vector3.INF:
		return map_target
	var origin: Vector3 = _turret.global_position
	if is_indirect():
		# bearing and range: the wheel or the stick sets how far out to drop them
		var flat := Vector3(sin(aim_yaw), 0.0, -cos(aim_yaw)).normalized()
		var p := origin + flat * arty_range
		return Vector3(p.x, Sim.height_at(p.x, p.z), p.z)
	var dir := Vector3(sin(aim_yaw), tan(clampf(-aim_pitch, -1.2, -0.02)), -cos(aim_yaw)).normalized()
	var t := 15.0
	while t < 26000.0:
		var q := origin + dir * t
		if q.y <= Sim.height_at(q.x, q.z):
			return Vector3(q.x, Sim.height_at(q.x, q.z), q.z)
		t += maxf(t * 0.05, 12.0)
	return Vector3.INF

## Firing solution onto a ground point. Real artillery does not use the lofted
## root of the ballistic equation - that gives near vertical mortar arcs - it
## picks a propelling charge so the piece sits at a sensible quadrant elevation.
## So: hold about 40 degrees and solve for the velocity, and only flatten out at
## full charge when the target is beyond that.
const ARTY_QE := 40.0

func fire_solution(target: Vector3, v_max: float) -> Dictionary:
	var origin: Vector3 = _muzzle.global_position
	var d := Vector2(target.x - origin.x, target.z - origin.z).length()
	var dy := target.y - origin.y
	var g := 9.81
	if d < 60.0:
		return {}
	var el := deg_to_rad(ARTY_QE)
	var denom := 2.0 * (d * tan(el) - dy)
	if denom > 0.0:
		var need := d / cos(el) * sqrt(g / denom)
		if need <= v_max:
			return {"elev": el, "speed": need,
				"tof": d / (need * cos(el)), "range": d, "charge": need / v_max}
	# beyond the 40 degree arc: full charge on the low angle solution
	var root := v_max * v_max * v_max * v_max - g * (g * d * d + 2.0 * dy * v_max * v_max)
	if root < 0.0:
		return {}
	var low := atan((v_max * v_max - sqrt(root)) / (g * d))
	return {"elev": low, "speed": v_max, "tof": d / (v_max * cos(low)),
		"range": d, "charge": 1.0}

func aim_at(point: Vector3) -> void:
	var to := point - _turret.global_position
	turret_yaw = atan2(to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	turret_pitch = atan2(to.y, maxf(flat, 0.1))

func fire_main(world: Node) -> bool:
	var kd: Dictionary = KINDS[kind]
	if _gun_cd > 0.0 or not alive:
		return false
	if is_indirect():
		# Wait until the launcher is actually laid. The solution is worked out
		# the instant you designate, but the traverse takes 0.9 rad/s and the
		# elevation longer, so firing straight away sent rockets off the correct
		# bearing while the tubes were still pointing somewhere else entirely.
		# tight, because at six kilometres a degree of quadrant elevation is
		# nearly forty metres of range and the tubes are now the launch axis
		var off := lay_error()
		if off > 0.006:
			laying = true
			return false
		laying = false
		if rounds_left <= 0:
			if int(kd.get("salvo", 1)) <= 1:
				# a gun, not a rack: the loader is already working and pulling
				# the trigger again must not send him back to the start
				return false
			# pod empty: the crew reloads the whole rack before anything else
			_gun_cd = float(kd["reload"])
			rounds_left = int(kd.get("salvo", 1))
			return false
		var pod: int = int(kd.get("salvo", 1))
		_gun_cd = float(kd.get("ripple", 0.55)) if pod > 1 else float(kd["reload"])
		_fire_indirect(world, kd)
		return true
	_gun_cd = float(kd["reload"])
	_lob(world, -_muzzle.global_transform.basis.z * float(kd["muzzle"]),
		float(kd["gun"]), float(kd["blast"]), 3.4)
	apply_central_impulse(_muzzle.global_transform.basis.z * 34000.0)
	return true

## How far the piece still is from the bearing and elevation it needs, in
## radians: the worst of the two axes. Zero means it is laid and may fire.
func lay_error() -> float:
	var aim := ground_aim()
	if aim == Vector3.INF:
		return PI
	var sol := fire_solution(aim, float(KINDS[kind]["muzzle"]))
	if sol.is_empty():
		return PI
	var want_yaw := atan2(aim.x - global_position.x, -(aim.z - global_position.z))
	var yaw_off := absf(wrapf(-want_yaw - (rotation.y + _turret.rotation.y), -PI, PI))
	var max_el: float = deg_to_rad(70.0) if vclass() != "mbt" else deg_to_rad(20.0)
	var want_el: float = clampf(float(sol["elev"]), deg_to_rad(-9.0), max_el)
	return maxf(yaw_off, absf(want_el - _mantlet.rotation.x))

## Howitzers and rocket launchers arc onto wherever the barrel is pointing.
func _fire_indirect(world: Node, kd: Dictionary) -> bool:
	var aim := ground_aim()
	if aim == Vector3.INF:
		return false
	var sol := fire_solution(aim, float(kd["muzzle"]))
	if sol.is_empty():
		return false
	# Straight out of the tubes. The lay check has already established that the
	# barrels are pointing at the solution, so using their actual axis is both
	# the correct direction and the one the player is looking at -- a round that
	# leaves on a computed bearing while the tubes point somewhere else is the
	# thing that looks wrong however good the fall of shot is.
	var origin: Vector3 = _muzzle.global_position
	var el: float = sol["elev"]
	var tube := (-_muzzle.global_transform.basis.z).normalized()
	var flat := Vector2(aim.x - origin.x, aim.z - origin.z)
	var dir := Vector3(flat.x, 0, flat.y).normalized()
	if Sim.debug_weapons:
		# the tubes and the ballistics must agree, or the round leaves in a
		# direction the player can see is wrong however good the impact is
		print("[lay] el sol %.2f tube %.2f | bearing sol %.2f tube %.2f" % [
			rad_to_deg(el), rad_to_deg(asin(clampf(tube.y, -1.0, 1.0))),
			rad_to_deg(atan2(dir.x, -dir.z)), rad_to_deg(atan2(tube.x, -tube.z))])
	var launch := (dir * cos(el) + Vector3.UP * sin(el)) * float(sol["speed"])
	var salvo: int = int(kd.get("salvo", 1))

	last_solution = {"range": sol["range"], "elev": rad_to_deg(el),
		"salvo": rounds_left, "tof": sol["tof"], "charge": sol["charge"]}
	# One round per trigger press. Holding the trigger walks the rest of the pod
	# out at the ripple rate, so a fire mission is yours to place rather than an
	# all or nothing dump of everything on the rails.
	var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4),
		randf_range(-1.0, 1.0)) * (4.0 if salvo > 1 else 0.35)
	# an indirect round climbs away over its own battery, so it needs room
	_lob(world, launch + spread, float(kd["gun"]), float(kd["blast"]),
		2.2 if salvo > 1 else 4.2, aim, 90.0, salvo > 1)
	rounds_left = maxi(rounds_left - 1, 0)
	return true

func _lob(world: Node, vel: Vector3, dmg: float, blast: float, flash: float,
		aim := Vector3.INF, arm := 12.0, as_rocket := false) -> void:
	var shell := Aircraft.Shell.new()
	shell.arm_dist = arm
	shell.rocket = as_rocket
	if aim != Vector3.INF:
		shell.set_meta("aim", aim)
		shell.set_meta("origin", global_position)
	shell.vel = vel + linear_velocity
	shell.damage = dmg
	shell.blast = blast
	shell.shooter = self
	shell.team = team
	world.add_child(shell)
	shell.global_position = _muzzle.global_position
	Effects.muzzle_flash(world, _muzzle.global_position, vel.normalized(), flash)
	Effects.dust(world, _muzzle.global_position, 4.5)
	Sfx.play_at(world, "boom", _muzzle.global_position, -2.0, 0.7, 4000.0)

func fire_coax(world: Node) -> bool:
	if _coax_cd > 0.0 or not alive:
		return false
	_coax_cd = 0.09
	var dir := -_muzzle.global_transform.basis.z
	dir = (dir + Vector3(randf_range(-0.006, 0.006), randf_range(-0.006, 0.006),
		randf_range(-0.006, 0.006))).normalized()
	Effects.tracer(world, _muzzle.global_position - dir * 1.5, dir * 900.0 + linear_velocity,
		self, 26.0, team)
	Effects.muzzle_flash(world, _muzzle.global_position - dir * 1.2, dir, 0.8)
	Sfx.play_at(world, "rifle", _muzzle.global_position, -8.0, 0.85, 600.0)
	return true

func hit_radius() -> float:
	return 3.4

func is_alive() -> bool:
	return alive

## See Aircraft.hull_distance: the walk-up scan has to compare like with like.
func _cache_bounds() -> void:
	var box := AABB()
	var first := true
	for c in find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var t: AABB = mi.transform * mi.get_aabb()
		box = t if first else box.merge(t)
		first = false
	bounds = box

func hull_distance(p: Vector3) -> float:
	var lp: Vector3 = global_transform.affine_inverse() * p
	var mn := bounds.position
	var mx := bounds.end
	var q := Vector3(clampf(lp.x, mn.x, mx.x), clampf(lp.y, mn.y, mx.y),
		clampf(lp.z, mn.z, mx.z))
	return lp.distance_to(q)

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	# Whoever simulates this vehicle decides whether it just died. A ghost of a
	# remote player's tank, or a garrison the host owns, reports the hit instead
	# of applying it, and learns the outcome from replicated state.
	if Sim.net != null and Sim.net.active and not Sim.net.is_host \
			and (has_meta("net_id") or has_meta("zone_asset")):
		Sim.net.report_ground_damage(self, amount)
		return
	apply_damage(amount)

## The damage itself, with no question of who is allowed to deal it.
func apply_damage(amount: float) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
		Effects.explosion(get_tree().current_scene, global_position + Vector3(0, 1.5, 0), 18.0)
		remove_from_group("boardable")
		var smoke := Effects.trail_particles(Color(0.25, 0.25, 0.25), 3.0, 32)
		smoke.emitting = true
		add_child(smoke)
		died.emit(self)

func crew_position() -> Vector3:
	return global_transform * Vector3(-0.55, 2.35, 1.0)
