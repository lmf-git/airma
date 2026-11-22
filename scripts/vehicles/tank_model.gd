class_name TankModel
extends RefCounted
## Building a vehicle's model: the hull, running gear and turret of a tank or
## an armoured vehicle, the chassis of a light 4x4, a missile launcher's
## transporter and an air defence battery, with the nodes the vehicle aims and
## fires through (`_turret`, `_mantlet`, `_muzzle` and the rest) set on it.
##
## Split out of `tank.gd`, whose vehicle it builds through `tank`.

var tank: Tank
## The launch tubes, as the last chassis built them: how long, and how high
## their mouths sit, for where the muzzle goes.
var _tube_len := 3.0
var _tube_rise := 0.9

func _init(w: Tank) -> void:
	tank = w

# --------------------------------------------------------------------------
func build() -> void:
	var body := MeshKit.panelled(VehicleSpec.KINDS[tank.kind]["hull"], 0.92, 0.10, 1.1)
	var dark := MeshKit.mat(Color(0.11, 0.11, 0.12), 0.85, 0.2)

	var st := MeshKit.begin()
	if tank.vclass() == "tel" or tank.vclass() == "asat":
		_build_tel_chassis(st, body, dark)
		return
	if tank.vclass() == "lav":
		_build_light_chassis(st, body, dark)
		return
	if tank.vclass() == "sam":
		_build_battery(st, body, dark)
		return
	# lower hull, glacis and side skirts. An infantry vehicle and a gun tank
	# share the running gear but not the size of it: `k` is how much of a main
	# battle tank this one is.
	var k: float = 0.86 if tank.vclass() == "ifv" or tank.vclass() == "spaag" else 1.0
	MeshKit.box(st, Vector3(3.5 * k, 0.85, 7.3 * k), Vector3(0, 0.10, 0))
	var glacis := PackedVector2Array([
		Vector2(-1.75 * k, -3.65 * k), Vector2(1.75 * k, -3.65 * k),
		Vector2(1.75 * k, -1.30 * k), Vector2(-1.75 * k, -1.30 * k)])
	MeshKit.prism(st, glacis, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		PackedFloat32Array([0.06, 0.06, 0.40, 0.40]), Vector3(0, 0.72, 0))
	MeshKit.box(st, Vector3(3.42 * k, 0.62, 4.9 * k), Vector3(0, 0.86, 0.9 * k))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.16, 0.72, 7.0 * k), Vector3(sx * 1.79 * k, 0.62, 0.1))
		MeshKit.box(st, Vector3(0.55, 0.30, 1.5), Vector3(sx * 1.5 * k, 1.30, 2.9 * k))
	MeshKit.box(st, Vector3(1.2, 0.45, 1.1), Vector3(0, 1.28, 3.2 * k))   # engine deck
	if tank.vclass() == "spg":
		MeshKit.box(st, Vector3(2.6, 0.35, 1.2), Vector3(0, 0.30, 4.1))   # recoil spade
	tank.add_child(MeshKit.mi(MeshKit.finish(st, body), "Hull"))

	# tracks: belt shell plus separate road wheels that follow the suspension
	var tst := MeshKit.begin()
	for sx in [-1.0, 1.0]:
		var belt := PackedVector2Array([
			Vector2(-3.9 * k, 0.06), Vector2(-3.35 * k, 0.95), Vector2(3.35 * k, 0.95),
			Vector2(3.9 * k, 0.06), Vector2(3.35 * k, -0.30), Vector2(-3.35 * k, -0.30)])
		MeshKit.prism(tst, belt, Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0),
			PackedFloat32Array([0.30, 0.30, 0.30, 0.30, 0.30, 0.30]),
			Vector3(sx * Tank.TRACK_HALF * k, 0.02, 0))
	tank.add_child(MeshKit.mi(MeshKit.finish(tst, dark), "Tracks"))

	for sx in [-1.0, 1.0]:
		for i in Tank.WHEELS_PER_SIDE:
			var z := lerpf(-2.95 * k, 2.95 * k, float(i) / float(Tank.WHEELS_PER_SIDE - 1))
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = Tank.WHEEL_R * k
			cyl.bottom_radius = Tank.WHEEL_R * k
			cyl.height = 0.34
			cyl.radial_segments = 10
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.17, 0.18, 0.17), 0.9, 0.1)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * Tank.TRACK_HALF * k, -0.18, z)
			tank.add_child(w)
			tank._road_wheels.append({"node": w, "side": sx, "lat": sx * Tank.TRACK_HALF * k,
				"z": z, "rest_y": -0.18, "r": Tank.WHEEL_R, "comp": 0.0})

	# turret and gun
	tank._turret = Node3D.new()
	tank._turret.name = "Turret"
	tank._turret.position = Vector3(0, 1.20, 0.55)
	tank.add_child(tank._turret)
	var tu := MeshKit.begin()
	match tank.vclass():
		"ifv":
			# a small two-man turret with an autocannon and a missile box
			MeshKit.box(tu, Vector3(1.35, 0.62, 1.65), Vector3(0, 0.32, 0))
			MeshKit.box(tu, Vector3(0.42, 0.36, 0.70), Vector3(0.86, 0.46, 0.15))
			MeshKit.box(tu, Vector3(0.30, 0.24, 0.34), Vector3(-0.72, 0.72, -0.20))
		"spaag":
			# a wide radar-topped mount: two barrels and a dish
			MeshKit.box(tu, Vector3(2.30, 0.72, 1.85), Vector3(0, 0.36, 0))
			MeshKit.cone(tu, 0.46, 0.46, -0.10, 0.10, Vector3(0, 0.92, 0.55), 12)
			MeshKit.box(tu, Vector3(0.10, 0.62, 0.62), Vector3(0, 1.24, 0.55))
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
	tank._turret.add_child(MeshKit.mi(MeshKit.finish(tu, body), "TurretShell"))

	tank._mantlet = Node3D.new()
	tank._mantlet.name = "Mantlet"
	if tank.vclass() == "mlrs":
		tank._mantlet.position = Vector3(0, 1.25, 1.0)
	else:
		tank._mantlet.position = Vector3(0, 0.36, -1.55)
	tank._turret.add_child(tank._mantlet)
	var gst := MeshKit.begin()
	match tank.vclass():
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
		"ifv":
			MeshKit.box(gst, Vector3(0.42, 0.34, 0.44), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.055, 0.048, -2.35, 0.0, Vector3.ZERO, 8)
			# the coaxial, beside the cannon rather than inside it
			MeshKit.cone(gst, 0.024, 0.024, -0.62, 0.0, Vector3(0.15, 0, 0), 6)
		"spaag":
			# twin barrels side by side, which is what one of these looks like
			MeshKit.box(gst, Vector3(0.85, 0.38, 0.50), Vector3(0, 0, 0.1))
			for bx in [-0.30, 0.30]:
				MeshKit.cone(gst, 0.052, 0.045, -2.75, 0.0, Vector3(bx, 0, 0), 8)
		_:
			MeshKit.box(gst, Vector3(1.05, 0.62, 0.55), Vector3(0, 0, 0.1))
			MeshKit.cone(gst, 0.135, 0.115, -5.6, 0.0, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.030, 0.030, -0.80, 0.0, Vector3(0.36, 0, 0), 6)
			MeshKit.cone(gst, 0.20, 0.20, -4.3, -3.3, Vector3.ZERO, 10)
			MeshKit.cone(gst, 0.19, 0.19, -5.75, -5.35, Vector3.ZERO, 10)
	tank._mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	tank._muzzle = Node3D.new()
	match tank.vclass():
		"spg":
			tank._muzzle.position = Vector3(0, 0, -8.0)
		"mlrs":
			tank._muzzle.position = Vector3(0, 0.55, -2.1)
		"ifv":
			tank._muzzle.position = Vector3(0, 0, -2.45)
		"spaag":
			tank._muzzle.position = Vector3(0, 0, -2.85)
		_:
			tank._muzzle.position = Vector3(0, 0, -5.9)
	tank._mantlet.add_child(tank._muzzle)

# --------------------------------------------------------------------------
## A surface-to-air battery: the launcher lorry with four rounds canted up on
## the back and a search radar behind the cab. It does not lay a gun — it
## acquires an aircraft and sends a round — so the "turret" carries the rail
## pack and the elevation is a launch angle, not an aiming one.
func _build_battery(st: SurfaceTool, body: Material, dark: Material) -> void:
	# chassis and cab, the same lorry a launcher rides on
	MeshKit.box(st, Vector3(3.0, 0.42, 9.6), Vector3(0, 0.95, 0.4))
	MeshKit.box(st, Vector3(2.7, 0.34, 8.6), Vector3(0, 1.28, 0.4))
	MeshKit.box(st, Vector3(2.80, 1.55, 2.9), Vector3(0, 1.62, -3.9))
	MeshKit.box(st, Vector3(2.50, 0.62, 0.12), Vector3(0, 2.15, -5.30))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.70, 0.72, 3.4))
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.70, 0.72, -1.8))
	# the search radar: a flat panel on a mast behind the cab, which is the one
	# thing that tells you what this lorry is from a distance
	MeshKit.box(st, Vector3(0.34, 1.30, 0.34), Vector3(0, 2.20, -2.20))
	MeshKit.box(st, Vector3(2.30, 1.70, 0.16), Vector3(0, 3.45, -2.10))
	tank.add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))
	var axles := [-4.3, -3.1, 0.6, 1.9, 3.2]
	for sx2 in [-1.0, 1.0]:
		for i in axles.size():
			var z: float = float(axles[i])
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = Tank.TEL_WHEEL_R
			cyl.bottom_radius = Tank.TEL_WHEEL_R
			cyl.height = 0.46
			cyl.radial_segments = 12
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.09, 0.09, 0.10), 0.95, 0.0)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx2 * 1.40, Tank.TEL_WHEEL_R, z)
			tank.add_child(w)
			tank._road_wheels.append({"node": w, "side": sx2, "lat": sx2 * 1.40, "z": z,
				"rest_y": Tank.TEL_WHEEL_R, "r": Tank.TEL_WHEEL_R, "comp": 0.0,
				"steer": i < 2})
	tank._turret = Node3D.new()
	tank._turret.name = "Turret"
	tank._turret.position = Vector3(0, 1.55, 1.6)
	tank.add_child(tank._turret)
	var tu := MeshKit.begin()
	MeshKit.box(tu, Vector3(2.2, 0.32, 2.4), Vector3(0, 0.08, 0))
	tank._turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Deck"))
	tank._mantlet = Node3D.new()
	tank._mantlet.name = "Mantlet"
	tank._mantlet.position = Vector3(0, 0.36, 2.2)
	tank._turret.add_child(tank._mantlet)
	# four rounds in their tubes, in a two by two pack
	var gst := MeshKit.begin()
	var tube := 2.9
	MeshKit.box(gst, Vector3(1.90, 0.24, tube * 1.9), Vector3(0, 0.06, -tube * 0.85))
	for cx in [-0.52, 0.52]:
		for cy in [0.44, 1.06]:
			MeshKit.cone(gst, 0.26, 0.26, -tube * 1.85, 0.05,
				Vector3(cx, cy, 0), 10)
			MeshKit.cone(gst, 0.29, 0.29, -tube * 1.9, -tube * 1.78,
				Vector3(cx, cy, 0), 10)
	_tube_len = tube
	_tube_rise = 0.75
	tank._mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	tank._muzzle = Node3D.new()
	tank._muzzle.position = Vector3(0, 0.75, -tube * 1.9)
	tank._mantlet.add_child(tank._muzzle)

# --------------------------------------------------------------------------
## A light 4x4: ladder chassis, crew cab, load bed and four independently
## sprung wheels, the front pair of which steer. Nothing about a tank's hull
## fits one of these -- there are no tracks to build, the body is a metre and
## a half tall rather than three, and what is on the roof is a ring mount with
## a machine gun on it, not a turret.
func _build_light_chassis(st: SurfaceTool, body: Material, dark: Material) -> void:
	var ch: Dictionary = VehicleSpec.KINDS[tank.kind].get("chassis", {})
	var ln: float = float(ch.get("len", 4.9))
	var wd: float = float(ch.get("wide", 2.2))
	var ht: float = float(ch.get("tall", 1.42))
	var wb: float = float(ch.get("wb", 3.30))
	var tk: float = float(ch.get("track", wd * 0.42))
	var wr: float = float(ch.get("r", 0.47))
	var open_top: bool = String(ch.get("mount", "ring")) == "open"
	# The body origin sits at the axle line, so the wheels hang either side of
	# it and rest_height() has something square to work from.
	var deck: float = wr + 0.22                      # top of the chassis rails
	var sill: float = deck + 0.16

	# ladder chassis
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.16, 0.20, ln * 0.94), Vector3(sx * tk * 0.55, deck - 0.12, 0))
	MeshKit.box(st, Vector3(tk * 1.1, 0.14, 0.5), Vector3(0, deck - 0.12, -wb * 0.5))
	MeshKit.box(st, Vector3(tk * 1.1, 0.14, 0.5), Vector3(0, deck - 0.12, wb * 0.5))
	# hull tub, with the nose and tail cut back so it does not overhang the tyres
	MeshKit.box(st, Vector3(wd, 0.44, ln * 0.90), Vector3(0, sill, 0))
	# bonnet: a flat deck over the engine, sloped up to the windscreen
	var nose_z: float = -ln * 0.30
	MeshKit.box(st, Vector3(wd * 0.92, 0.30, ln * 0.30), Vector3(0, sill + 0.34, nose_z))
	var scuttle := PackedVector2Array([
		Vector2(-wd * 0.46, nose_z + ln * 0.15), Vector2(wd * 0.46, nose_z + ln * 0.15),
		Vector2(wd * 0.46, nose_z + ln * 0.30), Vector2(-wd * 0.46, nose_z + ln * 0.30)])
	MeshKit.prism(st, scuttle, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
		PackedFloat32Array([0.06, 0.06, 0.34, 0.34]), Vector3(0, sill + 0.49, 0))
	# radiator grille and a brush guard, which is the front of one of these
	MeshKit.box(st, Vector3(wd * 0.80, 0.42, 0.14), Vector3(0, sill + 0.30, nose_z - ln * 0.16))
	MeshKit.box(st, Vector3(wd * 0.86, 0.12, 0.12), Vector3(0, sill + 0.52, nose_z - ln * 0.20))
	MeshKit.box(st, Vector3(wd * 0.86, 0.12, 0.12), Vector3(0, sill + 0.08, nose_z - ln * 0.20))
	# crew compartment: sides and a rear bulkhead, roofed unless it is open
	var cab_z: float = -ln * 0.02
	var cab_l: float = ln * 0.40
	var cab_h: float = ht * 0.66
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.12, cab_h, cab_l), Vector3(sx * wd * 0.44, sill + 0.22 + cab_h * 0.5, cab_z))
	MeshKit.box(st, Vector3(wd * 0.88, cab_h, 0.12), Vector3(0, sill + 0.22 + cab_h * 0.5, cab_z + cab_l * 0.5))
	if not open_top:
		MeshKit.box(st, Vector3(wd * 0.90, 0.10, cab_l), Vector3(0, sill + 0.22 + cab_h, cab_z))
		# A pillars, so the windscreen reads as glass in a frame
		for sx in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0.10, cab_h, 0.10),
				Vector3(sx * wd * 0.42, sill + 0.22 + cab_h * 0.5, cab_z - cab_l * 0.5))
	# load bed behind the cab
	var bed_z: float = ln * 0.30
	MeshKit.box(st, Vector3(wd * 0.94, 0.34, ln * 0.30), Vector3(0, sill + 0.28, bed_z))
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.10, 0.30, ln * 0.30), Vector3(sx * wd * 0.46, sill + 0.52, bed_z))
	# spare wheel on the tail, jerry cans on the flank
	MeshKit.box(st, Vector3(0.30, 0.34, 0.22), Vector3(wd * 0.30, sill + 0.62, bed_z + ln * 0.10))
	# arches over each wheel, or the tyres cut straight through the body side
	for sx in [-1.0, 1.0]:
		for zz in [-wb * 0.5, wb * 0.5]:
			MeshKit.box(st, Vector3(0.10, 0.44, wr * 2.5),
				Vector3(sx * (tk + 0.22), deck + 0.10, zz))
			MeshKit.box(st, Vector3(tk * 0.6, 0.10, wr * 2.5),
				Vector3(sx * (tk * 0.7 + 0.22), deck + 0.30, zz))
	tank.add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))

	# glass: windscreen and door windows, dark so they read as glazing
	if not open_top:
		var gst := MeshKit.begin()
		var wind := PackedVector2Array([
			Vector2(-wd * 0.40, nose_z + ln * 0.16), Vector2(wd * 0.40, nose_z + ln * 0.16),
			Vector2(wd * 0.40, nose_z + ln * 0.29), Vector2(-wd * 0.40, nose_z + ln * 0.29)])
		MeshKit.prism(gst, wind, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0),
			PackedFloat32Array([0.05, 0.05, 0.30, 0.30]), Vector3(0, sill + 0.52, 0))
		for sx in [-1.0, 1.0]:
			MeshKit.box(gst, Vector3(0.05, cab_h * 0.52, cab_l * 0.58),
				Vector3(sx * wd * 0.45, sill + 0.28 + cab_h * 0.66, cab_z - cab_l * 0.10))
		tank.add_child(MeshKit.mi(MeshKit.finish(gst,
			MeshKit.mat(Color(0.07, 0.09, 0.10), 0.18, 0.5)), "Glass"))

	# four wheels on coils, the front pair steered
	var tyre := MeshKit.mat(Color(0.08, 0.08, 0.09), 0.95, 0.0)
	for sx in [-1.0, 1.0]:
		for zz in [-wb * 0.5, wb * 0.5]:
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = wr
			cyl.bottom_radius = wr
			cyl.height = wr * 0.62
			cyl.radial_segments = 14
			w.mesh = cyl
			w.material_override = tyre
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx * tk, wr, zz)
			tank.add_child(w)
			tank._road_wheels.append({"node": w, "side": sx, "lat": sx * tk, "z": zz,
				"rest_y": wr, "r": wr, "comp": 0.0, "steer": zz < 0.0})

	# the ring mount stands in for the turret, so laying and elevating work
	# exactly as they do on everything else
	tank._turret = Node3D.new()
	tank._turret.name = "Turret"
	tank._turret.position = Vector3(0, sill + 0.22 + (cab_h if not open_top else cab_h * 0.55),
		cab_z + (0.0 if not open_top else -cab_l * 0.10))
	tank.add_child(tank._turret)
	var tu := MeshKit.begin()
	MeshKit.cone(tu, 0.46, 0.46, -0.09, 0.09, Vector3(0, 0.10, 0), 12)
	MeshKit.box(tu, Vector3(0.62, 0.22, 0.14), Vector3(0, 0.28, 0.34))   # gun shield mount
	MeshKit.box(tu, Vector3(0.72, 0.34, 0.06), Vector3(0, 0.44, -0.22))  # shield plate
	tank._turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Ring"))

	tank._mantlet = Node3D.new()
	tank._mantlet.name = "Mantlet"
	tank._mantlet.position = Vector3(0, 0.34, 0.06)
	tank._turret.add_child(tank._mantlet)
	var gst2 := MeshKit.begin()
	MeshKit.box(gst2, Vector3(0.16, 0.20, 0.62), Vector3(0, 0, 0.16))    # receiver
	MeshKit.cone(gst2, 0.045, 0.038, -0.92, -0.10, Vector3.ZERO, 8)      # barrel
	MeshKit.box(gst2, Vector3(0.10, 0.10, 0.22), Vector3(0, 0.13, 0.10)) # ammo box
	MeshKit.box(gst2, Vector3(0.06, 0.14, 0.06), Vector3(0, -0.14, -0.30))
	tank._mantlet.add_child(MeshKit.mi(MeshKit.finish(gst2,
		MeshKit.mat(Color(0.10, 0.10, 0.11), 0.85, 0.25)), "Gun"))
	tank._muzzle = Node3D.new()
	tank._muzzle.position = Vector3(0, 0, -0.95)
	tank._mantlet.add_child(tank._muzzle)

# --------------------------------------------------------------------------
## A launcher is a lorry, not a tank. It was being given the tracked hull, the
## glacis, the side skirts and the road wheels of an armoured vehicle, so a
## TEL came out looking exactly like everything else on the field with a
## canister balanced on top of it.
func _build_tel_chassis(st: SurfaceTool, body: Material, dark: Material) -> void:
	# a long flat load bed on a chassis
	MeshKit.box(st, Vector3(3.1, 0.42, 11.6), Vector3(0, 0.95, 0.6))
	MeshKit.box(st, Vector3(2.7, 0.34, 10.4), Vector3(0, 1.28, 0.6))
	# the cab, forward and separate, with glass in it
	MeshKit.box(st, Vector3(2.85, 1.55, 3.0), Vector3(0, 1.62, -4.6))
	MeshKit.box(st, Vector3(2.55, 0.62, 0.12), Vector3(0, 2.15, -6.05))
	# outriggers, which is what holds it down when it launches
	for sx in [-1.0, 1.0]:
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.75, 0.72, 3.9))
		MeshKit.box(st, Vector3(0.9, 0.22, 0.6), Vector3(sx * 1.75, 0.72, -2.2))
	tank.add_child(MeshKit.mi(MeshKit.finish(st, body), "Chassis"))
	# eight wheels a side on a proper wheelbase, not a track run
	var axles := [-5.1, -3.9, -0.6, 0.7, 2.0, 3.3]
	for sx2 in [-1.0, 1.0]:
		for i in axles.size():
			var z: float = float(axles[i])
			var w := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.72
			cyl.bottom_radius = 0.72
			cyl.height = 0.46
			cyl.radial_segments = 12
			w.mesh = cyl
			w.material_override = MeshKit.mat(Color(0.09, 0.09, 0.10), 0.95, 0.0)
			w.rotation_degrees = Vector3(0, 0, 90)
			w.position = Vector3(sx2 * 1.42, Tank.TEL_WHEEL_R, z)
			tank.add_child(w)
			# the front bogie steers, as it does on the real lorry
			tank._road_wheels.append({"node": w, "side": sx2, "lat": sx2 * 1.42, "z": z,
				"rest_y": Tank.TEL_WHEEL_R, "r": Tank.TEL_WHEEL_R, "comp": 0.0,
				"steer": i < 2})
	# the erector and its canisters live on the turret node, as with everything
	# else, so laying and elevating work unchanged
	tank._turret = Node3D.new()
	tank._turret.name = "Turret"
	tank._turret.position = Vector3(0, 1.55, 1.1)
	tank.add_child(tank._turret)
	var tu := MeshKit.begin()
	MeshKit.box(tu, Vector3(2.2, 0.36, 2.0), Vector3(0, 0.10, 0))
	_add_turret_mesh(tu, dark)

func _add_turret_mesh(tu: SurfaceTool, dark: Material) -> void:
	tank._turret.add_child(MeshKit.mi(MeshKit.finish(tu, dark), "Deck"))
	tank._mantlet = Node3D.new()
	tank._mantlet.name = "Mantlet"
	# At the back of the load bed, where a launcher's erector is actually
	# hinged.
	tank._mantlet.position = Vector3(0, 0.45, 4.0)
	tank._turret.add_child(tank._mantlet)
	var gst := MeshKit.begin()
	# One canister or two, and how big, follows the round it carries. Every
	# launcher was given the same twin tubes, so an Oreshnik — fourteen and a
	# half metres of it — rode in the same pair of pipes as a Kalibr.
	var mid: Dictionary = WeaponSpec.get_spec(
		String(VehicleSpec.KINDS[tank.kind].get("missile", "kalibr")))
	var bore: float = maxf(float(mid.get("dia", 0.5)) * 0.62, 0.30)
	var tube: float = maxf(float(mid.get("length", 6.0)) * 0.5, 2.4)
	var twin: bool = float(mid.get("dia", 0.5)) < 0.7
	# The whole load sits *forward* of the hinge rather than straddling it. Built
	# centred on the pivot, raising the canister swung its back half down
	# through the chassis at the same rate as its nose went up -- the missiles
	# rotated through the vehicle they were sitting on.
	var back: float = -tube * 0.94
	MeshKit.box(gst, Vector3(bore * 4.2, 0.30, tube * 1.9), Vector3(0, 0.10, 0.4 + back))
	var lanes: Array = [-bore * 1.15, bore * 1.15] if twin else [0.0]
	for cx in lanes:
		MeshKit.cone(gst, bore, bore, -tube + back, tube * 0.94 + back,
			Vector3(cx, bore + 0.3, 0), 12)
		MeshKit.cone(gst, bore * 1.11, bore * 1.11, -tube - 0.1 + back,
			-tube + 0.2 + back, Vector3(cx, bore + 0.3, 0), 12)
	MeshKit.box(gst, Vector3(bore * 4.6, 0.5, 0.5),
		Vector3(0, 0.30, tube * 0.82 + back))
	_tube_len = tube
	_tube_rise = bore + 0.3
	tank._mantlet.add_child(MeshKit.mi(MeshKit.finish(gst, dark), "Gun"))
	tank._muzzle = Node3D.new()
	tank._muzzle.position = Vector3(0, _tube_rise, -_tube_len - tube * 0.94)
	tank._mantlet.add_child(tank._muzzle)
