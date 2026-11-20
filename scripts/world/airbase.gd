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

## Every aerodrome is the same aerodrome.
##
## The pavement, the markings, the lighting and the buildings are laid out from
## constants -- there is nothing per-instance anywhere in them -- and the world
## has six of them, each building the identical geometry from scratch.
## Measured, 137 ms of the boot spent arriving six times at the same answer. A
## mesh is a resource and a resource can hang in six places at once, so each is
## built the first time it is asked for and shared after that.
##
## What is *not* shared is what actually differs between one field and the next:
## the PAPI's materials, which change colour with whoever is on the approach,
## and the hangars, which burn.
static var _shared: Dictionary = {}

## Whose field this is. Set before `build`: the hangars stand on this side.
## They were all on the player's, on every field in the world, so the patrol
## at a foreign base spent the first seconds of every session shooting up its
## own hangars and the menu reported each one as a kill.
var team := 0

func _enter_tree() -> void:
	add_to_group("airbase")

# ---------------------------------------------------------------- approaches
## Which runway end the landing aid is set to: {"base", "end"}, `end` being 36
## (landing toward local -z) or 18. Empty is AUTO -- the nearest field, and
## whichever end of it the aeroplane is out beyond.
static var pick: Dictionary = {}

## How far out the landing aid starts answering, and how far the menu looks
## for runways to offer.
const AID_REACH := 18000.0
const PICK_REACH := 40000.0

## The aiming point for one end, in the field's frame.
static func aim_for(end: int) -> Vector3:
	return Vector3(0, 0, AIM_Z if end == 36 else -AIM_Z)

## Every runway end within `reach` of `p`, nearest first.
static func approaches(tree: SceneTree, p: Vector3, reach := PICK_REACH) -> Array:
	var out: Array = []
	for n in tree.get_nodes_in_group("airbase"):
		var ab := n as Airbase
		if ab == null or not is_instance_valid(ab):
			continue
		var l: Vector3 = ab.to_local(p)
		for e in [36, 18]:
			var a := aim_for(e)
			var d := Vector2(l.x - a.x, l.z - a.z).length()
			if d < reach:
				out.append({"base": ab, "end": e, "d": d})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["d"]) < float(y["d"]))
	return out

## The approach the landing aid is flying: the one picked, while that field
## still stands, or else the nearest field and the end the aeroplane is beyond.
static func approach_for(tree: SceneTree, p: Vector3) -> Dictionary:
	if not pick.is_empty() and is_instance_valid(pick.get("base")):
		return pick
	pick = {}
	var best: Airbase = null
	var bd := INF
	for n in tree.get_nodes_in_group("airbase"):
		var ab := n as Airbase
		if ab == null or not is_instance_valid(ab):
			continue
		var d: float = ab.global_position.distance_to(p)
		if d < bd:
			bd = d
			best = ab
	if best == null:
		return {}
	return {"base": best, "end": 36 if best.to_local(p).z > 0.0 else 18}

## AUTO, then each runway end in reach, nearest first, and round again.
static func cycle_pick(tree: SceneTree, p: Vector3) -> void:
	var list := approaches(tree, p)
	var at := -1
	for i in list.size():
		if not pick.is_empty() and list[i]["base"] == pick.get("base") \
				and int(list[i]["end"]) == int(pick.get("end", 0)):
			at = i
			break
	var nxt := at + 1
	pick = {} if nxt >= list.size() else {"base": list[nxt]["base"], "end": list[nxt]["end"]}

## "HOME 03": whose field, and the runway number off the compass heading the
## aeroplane lands on. The fields are not laid north-south any more, so 36 and
## 18 were the right names only for the local frame.
static func end_label(ab: Airbase, end: int) -> String:
	var dir: Vector3 = ab.global_transform.basis * Vector3(0, 0, -1.0 if end == 36 else 1.0)
	var hdg := fposmod(rad_to_deg(atan2(dir.x, -dir.z)), 360.0)
	var num := int(roundf(hdg / 10.0))
	if num <= 0:
		num += 36
	var who := String(ab.name).trim_prefix("Airbase").strip_edges().to_upper()
	if ab.team == 0 or who == "":
		who = "HOME" if ab.team == 0 else "FIELD"
	return "%s %02d" % [who, num]

## What the menu shows for the current setting.
static func pick_label(tree: SceneTree, p: Vector3) -> String:
	if not pick.is_empty() and is_instance_valid(pick.get("base")):
		return end_label(pick["base"], int(pick["end"]))
	var ap := approach_for(tree, p)
	return "AUTO" if ap.is_empty() else "AUTO (%s)" % end_label(ap["base"], int(ap["end"]))

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
	if not _shared.has("pavement"):
		var st := MeshKit.begin()
		_tri_quad(st, 0, 0, W, HALF, 0.06)                       # runway
		_tri_quad(st, 0, 0, W + 8.0, HALF + 60.0, 0.02)          # shoulders / overrun
		for s in [-1.0, 1.0]:
			_tri_quad(st, s * 76.0, 0, 11.0, HALF - 40.0, 0.05)  # parallel taxiways
			_tri_quad(st, s * 44.0, HALF - 60.0, 33.0, 11.0, 0.05)
			_tri_quad(st, s * 44.0, -HALF + 60.0, 33.0, 11.0, 0.05)
			_tri_quad(st, s * 44.0, 0.0, 33.0, 11.0, 0.05)
		_tri_quad(st, 150.0, -420.0, 62.0, 150.0, 0.05)          # apron
		_shared["pavement"] = MeshKit.finish(st,
			MeshKit.mat(Color(0.115, 0.12, 0.128), 0.92, 0.0))
	add_child(MeshKit.mi(_shared["pavement"], "Pavement"))

func _markings() -> void:
	if _shared.has("markings"):
		add_child(MeshKit.mi(_shared["markings"], "Markings"))
		for k in [0, 1]:
			var num := MeshKit.mi(_shared["number%d" % k], "Number")
			num.material_override = _shared["number_mat"]
			num.transform = _shared["number_at%d" % k]
			add_child(num)
		return
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
	_shared["markings"] = MeshKit.finish(st,
		MeshKit.mat(Color(0.86, 0.87, 0.86), 0.85, 0.0))
	add_child(MeshKit.mi(_shared["markings"], "Markings"))
	# The two runway numbers are text turned into geometry, which means a font
	# outline tessellated -- and that is nearly the whole of what an aerodrome
	# costs to build: 135 ms of the 140 for the world's six, arriving six times
	# at the same two numbers. Kept with the rest.
	_shared["number_mat"] = MeshKit.mat(Color(0.88, 0.89, 0.88), 0.85, 0.0)
	var made := 0

	for pair in [[HALF - 40.0, "36", 0.0], [-HALF + 40.0, "18", 180.0]]:
		var t := TextMesh.new()
		t.text = pair[1]
		t.font_size = 128
		t.depth = 0.02
		t.pixel_size = 0.16
		var mi := MeshKit.mi(t, "Number")
		mi.material_override = _shared["number_mat"]
		mi.position = Vector3(0, 0.1, float(pair[0]))
		mi.rotation_degrees = Vector3(-90, float(pair[2]), 0)
		add_child(mi)
		_shared["number%d" % made] = t
		_shared["number_at%d" % made] = mi.transform
		made += 1

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
		if not _shared.has(nm):
			var m := MultiMesh.new()
			m.transform_format = MultiMesh.TRANSFORM_3D
			m.mesh = bulb
			m.instance_count = positions.size()
			for i in positions.size():
				m.set_instance_transform(i, Transform3D(Basis(), positions[i]))
			_shared[nm] = m
		multi.multimesh = _shared[nm]
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
	if not _shared.has("tower"):
		var st := MeshKit.begin()
		var conc := MeshKit.mat(Color(0.52, 0.52, 0.50), 0.85, 0.0)
		# control tower
		MeshKit.box(st, Vector3(11, 26, 11), Vector3(150, 13, -600))
		MeshKit.box(st, Vector3(17, 5.5, 17), Vector3(150, 28, -600))
		_shared["tower"] = MeshKit.finish(st, conc)
		var g := MeshKit.begin()
		MeshKit.box(g, Vector3(16, 4.4, 16), Vector3(150, 30.6, -600))
		_shared["glass"] = MeshKit.finish(g,
			MeshKit.mat(Color(0.20, 0.28, 0.32), 0.15, 0.8))
	add_child(MeshKit.mi(_shared["tower"], "Tower"))
	add_child(MeshKit.mi(_shared["glass"], "TowerGlass"))
	# Something to hit. The scenery clears `Obstacles` when it builds, which
	# is after the fields are laid out, so this waits for that.
	_tower_box.call_deferred()
	for i in 4:
		var t := GroundTarget.new()
		t.team = team
		t.setup("hangar")
		# Behind the apron, not on it. These sat at x=150, which is exactly the
		# line the ramp start parks its aircraft along -- so a jet spawned
		# inside a hangar and the two clipped through each other.
		t.position = Vector3(268.0, 0, -300.0 + i * 40.0)
		t.rotation_degrees = Vector3(0, 90, 0)
		# the base's own side: at home the target cycler skips them, but they
		# still burn; on someone else's field they are theirs to lose
		add_child(t)

var _tower_id := -1

func _tower_box() -> void:
	if not is_inside_tree():
		return
	var gx := global_transform
	var foot: Vector3 = gx * Vector3(150.0, 0.0, -600.0)
	_tower_id = Obstacles.add_box(foot, 8.5, 33.0, 8.5, atan2(-gx.basis.x.z, gx.basis.x.x))

func _process(_dt: float) -> void:
	if watcher == null or not is_instance_valid(watcher):
		return
	# In the field's own frame. Taken in the world's, every PAPI on the planet
	# was answering for the home runway at the origin.
	var p: Vector3 = to_local(watcher.global_position)
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
