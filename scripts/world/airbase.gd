class_name Airbase
extends Node3D
## Runway 18/36 with markings, lighting, PAPI and a small support base.

const HALF := Sim.RUNWAY_LEN * 0.5
const W := Sim.RUNWAY_HALF_W
const AIM_Z := 1180.0        # touchdown aiming point for runway 36
const GLIDE := 3.0
## How far short of the aiming point the glide slope is anchored. The slope is
## flown to the threshold; the wheels go down in the zone past it.
const THRESH_BIAS := 150.0

var papi: Array[MeshInstance3D] = []
var _papi_mats: Array[StandardMaterial3D] = []
var watcher: Node3D = null

func build() -> void:
	_pavement()
	_markings()
	_lights()
	_buildings()

func _tri_quad(st: SurfaceTool, cx: float, cz: float, hw: float, hl: float, y: float) -> void:
	var a := Vector3(cx - hw, y, cz - hl)
	var b := Vector3(cx + hw, y, cz - hl)
	var c := Vector3(cx + hw, y, cz + hl)
	var d := Vector3(cx - hw, y, cz + hl)
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)

func _pavement() -> void:
	var st := MeshKit.begin()
	_tri_quad(st, 0, 0, W, HALF, 0.06)                       # runway
	_tri_quad(st, 0, 0, W + 8.0, HALF + 60.0, 0.02)          # shoulders / overrun
	for s in [-1.0, 1.0]:
		_tri_quad(st, s * 76.0, 0, 11.0, HALF - 40.0, 0.05)  # parallel taxiways
		_tri_quad(st, s * 44.0, HALF - 60.0, 33.0, 11.0, 0.05)
		_tri_quad(st, s * 44.0, -HALF + 60.0, 33.0, 11.0, 0.05)
		_tri_quad(st, s * 44.0, 0.0, 33.0, 11.0, 0.05)
	_tri_quad(st, 150.0, -420.0, 62.0, 150.0, 0.05)          # apron
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.115, 0.12, 0.128), 0.92, 0.0)), "Pavement"))

func _markings() -> void:
	var st := MeshKit.begin()
	var y := 0.09
	for s in [-1.0, 1.0]:
		_tri_quad(st, float(s) * (W - 1.2), 0, 0.45, HALF, y)                     # edge lines
	var z := -HALF + 90.0
	while z < HALF - 90.0:
		_tri_quad(st, 0, z, 0.45, 15.0, y)                                 # centreline
		z += 60.0
	for end in [-1.0, 1.0]:
		var thr: float = float(end) * (HALF - 6.0)
		for i in 8:
			var off := (float(i) - 3.5) * 4.6
			_tri_quad(st, off, thr - float(end) * 14.0, 1.7, 14.0, y)      # piano keys
		for pair in [[150.0, 22.0], [300.0, 15.0], [450.0, 15.0], [600.0, 15.0], [750.0, 15.0]]:
			for s in [-1.0, 1.0]:
				_tri_quad(st, float(s) * 10.5, thr - float(end) * float(pair[0]), 1.6, float(pair[1]), y)
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.86, 0.87, 0.86), 0.85, 0.0)), "Markings"))

	for pair in [[HALF - 40.0, "36", 0.0], [-HALF + 40.0, "18", 180.0]]:
		var t := TextMesh.new()
		t.text = pair[1]
		t.font_size = 128
		t.depth = 0.02
		t.pixel_size = 0.16
		var mi := MeshKit.mi(t, "Number")
		mi.material_override = MeshKit.mat(Color(0.88, 0.89, 0.88), 0.85, 0.0)
		mi.position = Vector3(0, 0.1, pair[0])
		mi.rotation_degrees = Vector3(-90, pair[2], 0)
		add_child(mi)

func _lights() -> void:
	var white := MeshKit.mat(Color.BLACK, 0.4, 0.0, Color(1.0, 0.97, 0.9))
	var green := MeshKit.mat(Color.BLACK, 0.4, 0.0, Color(0.15, 1.0, 0.35))
	var red := MeshKit.mat(Color.BLACK, 0.4, 0.0, Color(1.0, 0.12, 0.12))
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.7
	bulb.radial_segments = 6
	bulb.rings = 3
	var mm := func(mat: Material, positions: Array, nm: String) -> void:
		var multi := MultiMeshInstance3D.new()
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.mesh = bulb
		m.instance_count = positions.size()
		for i in positions.size():
			m.set_instance_transform(i, Transform3D(Basis(), positions[i]))
		multi.multimesh = m
		multi.material_override = mat
		multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		multi.name = nm
		add_child(multi)

	var edge := []
	var z := -HALF
	while z <= HALF:
		edge.append(Vector3(-W - 1.5, 0.4, z))
		edge.append(Vector3(W + 1.5, 0.4, z))
		z += 60.0
	mm.call(white, edge, "EdgeLights")
	var thr_g := []
	var app := []
	for i in 9:
		var d := 60.0 + i * 90.0
		app.append(Vector3(0, 0.6 + i * 0.15, HALF + d))
		app.append(Vector3(-4.5, 0.6 + i * 0.15, HALF + d))
		app.append(Vector3(4.5, 0.6 + i * 0.15, HALF + d))
	for i in 11:
		var x := (float(i) - 5.0) * 4.4
		thr_g.append(Vector3(x, 0.4, HALF - 1.0))
		thr_g.append(Vector3(x, 0.4, -HALF + 1.0))
	mm.call(green, thr_g, "ThresholdLights")
	mm.call(white, app, "ApproachLights")
	mm.call(red, [Vector3(0, 0.4, HALF + 20.0), Vector3(0, 0.4, -HALF - 20.0)], "EndLights")

	# PAPI, left of the runway abeam the aiming point
	for i in 4:
		var box := BoxMesh.new()
		box.size = Vector3(1.6, 1.0, 1.2)
		var mat := MeshKit.mat(Color.BLACK, 0.3, 0.0, Color(1, 1, 1))
		var mi := MeshKit.mi(box, "PAPI%d" % i)
		mi.material_override = mat
		mi.position = Vector3(-W - 12.0 - i * 3.2, 0.8, AIM_Z)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		papi.append(mi)
		_papi_mats.append(mat)

func _buildings() -> void:
	var st := MeshKit.begin()
	var conc := MeshKit.mat(Color(0.52, 0.52, 0.50), 0.85, 0.0)
	# control tower
	MeshKit.box(st, Vector3(11, 26, 11), Vector3(150, 13, -600))
	MeshKit.box(st, Vector3(17, 5.5, 17), Vector3(150, 28, -600))
	add_child(MeshKit.mi(MeshKit.finish(st, conc), "Tower"))
	var g := MeshKit.begin()
	MeshKit.box(g, Vector3(16, 4.4, 16), Vector3(150, 30.6, -600))
	add_child(MeshKit.mi(MeshKit.finish(g, MeshKit.mat(Color(0.20, 0.28, 0.32), 0.15, 0.8)), "TowerGlass"))
	for i in 4:
		var t := GroundTarget.new()
		t.team = 0
		t.setup("hangar")
		# Behind the apron, not on it. These sat at x=150, which is exactly the
		# line the ramp start parks its aircraft along -- so a jet spawned
		# inside a hangar and the two clipped through each other.
		t.position = Vector3(268.0, 0, -300.0 + i * 40.0)
		t.rotation_degrees = Vector3(0, 90, 0)
		# friendly, so the target cycler skips them, but they still burn
		add_child(t)

func _process(_dt: float) -> void:
	if watcher == null or not is_instance_valid(watcher):
		return
	var p: Vector3 = watcher.global_position
	var origin := Vector3(0, 0, AIM_Z)
	var d := Vector2(p.x - origin.x, p.z - origin.z).length()
	var ang := rad_to_deg(atan2(maxf(p.y, 0.0), maxf(d, 1.0)))
	var facing := p.z > AIM_Z and d < 12000.0
	for i in _papi_mats.size():
		var limit := GLIDE + 0.5 - float(i) * 0.34    # inner unit needs the most height
		var white := ang > limit
		var c := Color(1, 1, 1) if white else Color(1.0, 0.1, 0.1)
		if not facing:
			c = Color(0.35, 0.35, 0.35)
		_papi_mats[i].emission = c
		_papi_mats[i].emission_energy_multiplier = 3.0 if facing else 0.6
