class_name Scenery
extends Node3D
## Procedural settlements and support bases scattered along the valley floor.
## Everything is instanced through MultiMeshInstance3D so a few thousand
## buildings cost a handful of draw calls.

const TOWNS := [
	# centre, radius, density, tallest, name
	[Vector3(-2300, 0, -5200), 900.0, 0.62, 26.0, "Kestrel"],
	[Vector3(2600, 0, 4200), 1500.0, 0.70, 72.0, "Rampart City"],
	[Vector3(-1900, 0, 3100), 520.0, 0.55, 14.0, "Vane"],
	[Vector3(2100, 0, -9200), 620.0, 0.58, 18.0, "Northgate"],
]

var _rng := RandomNumberGenerator.new()

var _streets: Array = []
var _stats := {}
static var current: Scenery = null
# Batches that can be flattened: {mmi, xforms, dead, centre, radius}
var _breakable: Array = []

## Lay out the road network first. The terrain paints roads into its own vertex
## colours, so the street grid has to exist before the ground is generated or
## the towns end up with invisible streets.
func _ready() -> void:
	current = self

func plan() -> void:
	_streets.clear()
	for t in TOWNS:
		_plan_town_streets(t[0], t[1])
	_streets.append([Vector2(-1500, -6600), Vector2(-2300, -5200)])
	Sim.register_segments(_streets)
	_stats["streets"] = _streets.size()

func _plan_town_streets(centre: Vector3, radius: float) -> void:
	var block := 128.0
	var lines := int(radius / block)
	for i in range(-lines, lines + 1):
		var off := float(i) * block
		var half := sqrt(maxf(radius * radius - off * off, 0.0))
		if half < 40.0:
			continue
		_streets.append([Vector2(centre.x + off, centre.z - half),
			Vector2(centre.x + off, centre.z + half)])
		_streets.append([Vector2(centre.x - half, centre.z + off),
			Vector2(centre.x + half, centre.z + off)])
	_streets.append([Vector2(centre.x, centre.z), _nearest_trunk(Vector2(centre.x, centre.z))])

func build() -> void:
	_rng.seed = 20260821
	if _streets.is_empty():
		plan()
	for t in TOWNS:
		_town(t[0], t[1], t[2], t[3])
	_military(Vector3(-1500, 0, -6600))
	_farms()
	_build_roads()
	_powerlines()
	_comms_masts()
	_fences()
	_windfarm()
	_utility_props()
	_scatter_nature()
	_home_base()
	if OS.is_debug_build():
		print("[scenery] ", _stats)

# ---------------------------------------------------------------- buildings
func _block_mesh(w: float, h: float, d: float, roof: Color, wall: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
	var m := MeshKit.panelled(wall, 0.92, 0.0, 3.2)
	var mesh := MeshKit.finish(st, m)
	var st2 := MeshKit.begin()
	MeshKit.box(st2, Vector3(w * 1.04, 0.5, d * 1.04), Vector3(0, h + 0.2, 0))
	var arr: ArrayMesh = MeshKit.finish(st2, MeshKit.mat(roof, 0.95, 0.0))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr.surface_get_arrays(0))
	mesh.surface_set_material(1, MeshKit.mat(roof, 0.95, 0.0))
	return mesh

func _scatter(mesh: Mesh, xforms: Array, nm: String, breakable := false) -> void:
	if xforms.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	mmi.multimesh = mm
	add_child(mmi)
	if breakable:
		var centre := Vector3.ZERO
		var rad := 0.0
		for x in xforms:
			centre += (x as Transform3D).origin
		centre /= float(xforms.size())
		for x in xforms:
			rad = maxf(rad, centre.distance_to((x as Transform3D).origin))
		_breakable.append({"mmi": mmi, "xforms": xforms.duplicate(),
			"dead": PackedByteArray(), "centre": centre, "radius": rad})
		var d: PackedByteArray = _breakable[_breakable.size() - 1]["dead"]
		d.resize(xforms.size())
		_breakable[_breakable.size() - 1]["dead"] = d

## Flatten anything inside the blast. Returns how many structures came down.
## How many breakable structures are still standing inside a radius.
func count_standing(pos: Vector3, radius: float) -> int:
	var n := 0
	for b in _breakable:
		var c: Vector3 = b["centre"]
		if c.distance_to(pos) > float(b["radius"]) + radius:
			continue
		var xf: Array = b["xforms"]
		var dead: PackedByteArray = b["dead"]
		for i in xf.size():
			if dead[i] == 0 and (xf[i] as Transform3D).origin.distance_to(pos) <= radius:
				n += 1
	return n

func damage_area(pos: Vector3, radius: float) -> int:
	var hits := 0
	for b in _breakable:
		var c: Vector3 = b["centre"]
		if c.distance_to(pos) > float(b["radius"]) + radius:
			continue
		var mm: MultiMesh = (b["mmi"] as MultiMeshInstance3D).multimesh
		var xf: Array = b["xforms"]
		var dead: PackedByteArray = b["dead"]
		for i in xf.size():
			if dead[i] != 0:
				continue
			var t: Transform3D = xf[i]
			if t.origin.distance_to(pos) > radius:
				continue
			dead[i] = 1
			hits += 1
			# collapse in place: squash, slump and sink into its own footprint
			var wreck := t.basis.rotated(Vector3.UP, randf_range(-0.25, 0.25))
			wreck = wreck.scaled(Vector3(1.05, 0.14, 1.05))
			wreck = wreck.rotated(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized(),
				randf_range(0.02, 0.09))
			mm.set_instance_transform(i, Transform3D(wreck, t.origin - Vector3(0, 0.4, 0)))
		b["dead"] = dead
	return hits

func _town(centre: Vector3, radius: float, density: float, tallest: float) -> void:
	var kinds := [
		_block_mesh(1.0, 1.0, 1.0, Color(0.26, 0.25, 0.23), Color(0.70, 0.67, 0.61)),
		_block_mesh(1.0, 1.0, 1.0, Color(0.22, 0.23, 0.25), Color(0.58, 0.59, 0.60)),
		_block_mesh(1.0, 1.0, 1.0, Color(0.29, 0.24, 0.21), Color(0.64, 0.58, 0.51)),
	]
	var buckets := [[], [], []]
	var block := 128.0
	# buildings, packed into the blocks with a setback from the kerb
	var step := 30.0
	var n := int(radius / step)
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var px := centre.x + gx * step + _rng.randf_range(-1.5, 1.5)
			var pz := centre.z + gz * step + _rng.randf_range(-1.5, 1.5)
			var d := Vector2(px - centre.x, pz - centre.z).length() / radius
			if d > 1.0 or _rng.randf() > density * (1.3 - d * 0.8):
				continue
			# keep clear of the kerb
			var fx := absf(fmod(absf(px - centre.x) + block * 0.5, block) - block * 0.5)
			var fz := absf(fmod(absf(pz - centre.z) + block * 0.5, block) - block * 0.5)
			if fx < 15.0 or fz < 15.0:
				continue
			if not Sim.buildable(px, pz, 0.90, 6.0):
				continue
			var core: float = clampf(1.0 - d * 1.35, 0.0, 1.0)
			var h: float = lerpf(7.0, tallest, pow(core, 1.7) * _rng.randf_range(0.35, 1.0))
			var w: float = _rng.randf_range(17.0, 24.0) * (1.0 + core * 0.3)
			var dep: float = _rng.randf_range(17.0, 24.0) * (1.0 + core * 0.3)
			var xf := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.015, 0.015)).scaled(
				Vector3(w, h, dep)), Vector3(px, Sim.height_at(px, pz) - 0.5, pz))
			buckets[_rng.randi() % 3].append(xf)
	for i in 3:
		_scatter(kinds[i], buckets[i], "Town%d" % i, true)
		_stats["buildings"] = int(_stats.get("buildings", 0)) + buckets[i].size()

## True when a point falls inside a town footprint, so nothing tall gets planted
## on top of the buildings.
func _inside_town(p: Vector2) -> bool:
	for t in TOWNS:
		var c: Vector3 = t[0]
		if p.distance_to(Vector2(c.x, c.z)) < float(t[1]) * 1.15:
			return true
	return false

func _nearest_trunk(p: Vector2) -> Vector2:
	var best := p
	var bd := 1e9
	for r in Sim.ROADS:
		var ra: Vector2 = r[0]
		var rb: Vector2 = r[1]
		var ab := rb - ra
		var t: float = clampf((p - ra).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var q := ra + ab * t
		var d := p.distance_to(q)
		if d < bd:
			bd = d
			best = q
	return best

# ---------------------------------------------------------------- military
func _military(centre: Vector3) -> void:
	var hangar := _hangar_mesh()
	var revet := _revetment_mesh()
	var hx := []
	var rx := []
	for i in 6:
		var px: float = centre.x + (i % 3) * 70.0
		var pz: float = centre.z + floorf(float(i) / 3.0) * 90.0
		hx.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(px, Sim.height_at(px, pz), pz)))
	for i in 8:
		var bearing := TAU * float(i) / 8.0
		var px: float = centre.x + cos(bearing) * 250.0
		var pz: float = centre.z + sin(bearing) * 250.0
		rx.append(Transform3D(Basis(Vector3.UP, -bearing),
			Vector3(px, Sim.height_at(px, pz), pz)))
	_scatter(hangar, hx, "Hangars", true)
	_scatter(revet, rx, "Revetments", true)
	# a strip of apron under it all
	var st := MeshKit.begin()
	var y := Sim.height_at(centre.x, centre.z) + 0.08
	var a := Vector3(centre.x - 200, y, centre.z - 120)
	var b := Vector3(centre.x + 240, y, centre.z - 120)
	var c := Vector3(centre.x + 240, y, centre.z + 220)
	var d := Vector3(centre.x - 200, y, centre.z + 220)
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.17, 0.17, 0.18), 0.95, 0.0)), "Apron"))

func _hangar_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rings := []
	for z in [-18.0, 18.0]:
		var r := PackedVector3Array()
		for i in 13:
			var a := PI * float(i) / 12.0
			r.append(Vector3(cos(a) * 16.0, sin(a) * 12.0, z))
		r.append(Vector3(-16.0, 0.0, z))
		rings.append(r)
	MeshKit.loft(st, rings, Vector3(0, 5, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.33, 0.35, 0.32), 0.9, 0.05))

func _revetment_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(30, 4.5, 3.0), Vector3(0, 2.2, -14.0))
	MeshKit.box(st, Vector3(3.0, 4.5, 26.0), Vector3(-13.5, 2.2, 0))
	MeshKit.box(st, Vector3(3.0, 4.5, 26.0), Vector3(13.5, 2.2, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.42, 0.40, 0.34), 0.95, 0.0))

# ---------------------------------------------------------------- landscape
func _farms() -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(26, 7, 14), Vector3(0, 3.5, 0))
	var barn := MeshKit.finish(st, MeshKit.mat(Color(0.40, 0.22, 0.18), 0.95, 0.0))
	var xf := []
	for i in 40:
		var px := _rng.randf_range(-4200.0, 4200.0)
		var pz := _rng.randf_range(-14000.0, 14000.0)
		if absf(px) < 700.0 and absf(pz) < 2200.0:
			continue
		if not Sim.buildable(px, pz, 0.93, 6.0) or Sim.height_at(px, pz) > 260.0:
			continue
		if not Sim.clear_of_airfield(px, pz) or _inside_town(Vector2(px, pz)):
			continue
		var gy := Sim.height_at(px, pz)
		xf.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), Vector3(px, gy, pz)))
	_scatter(barn, xf, "Farms", true)

# ---------------------------------------------------------------- scatter
## Vegetation is placed into a coarse cell grid, one MultiMesh per cell per
## species. Each cell carries a visibility range so distant ground cover stops
## drawing entirely instead of being frustum-culled triangle by triangle.
# Bigger cells, more of them filled. Cell size sets the MultiMesh count and so
# the draw calls; instance count sets how much is actually on the ground. Going
# up on both at once is what lets the ground read as ground at low level, which
# is most of what makes a fast jet feel fast.
const SCAT_CELL := 2200.0
const SCAT_HALF := 9                       # cells either side of the field
const SCAT_RANGE := {"tree": 6200.0, "pine": 7000.0, "rock": 4600.0, "bush": 2800.0}

## Species and density follow the biome field, so forest belts, steppe and the
## snow line all read differently on the ground.
const SCAT_DENSITY := {
	"forest": 1.0, "grass": 0.62, "steppe": 0.38, "marsh": 0.46,
	"rock": 0.26, "snow": 0.28, "sand": 0.12,
}
const SCAT_SPECIES := {
	"forest": ["tree", "tree", "tree", "pine", "bush"],
	"grass": ["tree", "bush", "bush", "rock"],
	"steppe": ["bush", "bush", "rock"],
	"marsh": ["bush", "tree"],
	"rock": ["rock", "rock", "pine"],
	"snow": ["pine", "rock"],
	"sand": ["rock", "bush"],
}

func _scatter_nature() -> void:
	var meshes := {"tree": _tree_mesh(), "pine": _pine_mesh(), "rock": _rock_mesh(),
		"bush": _bush_mesh()}
	var cells := {}
	for i in 150000:
		var x := _rng.randf_range(-SCAT_HALF * SCAT_CELL, SCAT_HALF * SCAT_CELL)
		var z := _rng.randf_range(-SCAT_HALF * SCAT_CELL * 1.6, SCAT_HALF * SCAT_CELL * 1.6)
		if absf(x) < 330.0 and absf(z) < 2150.0:
			continue                                        # keep the field clear
		var y := Sim.height_at(x, z)
		if y < Sim.WATER_LEVEL + 2.0 or y > 2400.0:
			continue
		if absf(x) < 6000.0 and Sim.road_distance(x, z) < 15.0:
			continue
		var slope := Sim.normal_at(x, z).y
		if slope < 0.55:
			continue                                        # nothing clings to a cliff
		var biome := Sim.biome_kind(x, z, y, slope)
		if _rng.randf() > float(SCAT_DENSITY.get(biome, 0.3)):
			continue
		var options: Array = SCAT_SPECIES.get(biome, ["bush"])
		var kind: String = options[_rng.randi() % options.size()]
		var sc := _rng.randf_range(0.7, 1.7)
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(
			Vector3(sc, sc * _rng.randf_range(0.8, 1.35), sc)), Vector3(x, y - 0.4, z))
		var key := "%s_%d_%d" % [kind, int(floor(x / SCAT_CELL)), int(floor(z / SCAT_CELL))]
		if not cells.has(key):
			cells[key] = []
		cells[key].append(xf)
	for key in cells:
		var kind: String = key.split("_")[0]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		var list: Array = cells[key]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = SCAT_RANGE.get(kind, 3000.0)
		mmi.visibility_range_end_margin = float(SCAT_RANGE.get(kind, 3000.0)) * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		_stats[kind] = int(_stats.get(kind, 0)) + list.size()
		_stats["scatter_cells"] = int(_stats.get("scatter_cells", 0)) + 1

func _bush_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rings := [
		MeshKit.ring(0.9, 0.5, 0.25, -0.7, 2.2, 6),
		MeshKit.ring(1.5, 1.0, 0.85, 0.2, 2.0, 6),
		MeshKit.ring(0.7, 0.5, 1.35, 0.9, 2.2, 6),
	]
	MeshKit.loft(st, rings, Vector3(0, 0.8, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.17, 0.25, 0.13), 0.97, 0.0))

func _leafy(trunk_r: float, trunk_h: float, canopy_r: float, canopy_h: float,
		trunk_c: Color, leaf_c: Color, seg: int) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.cone(st, trunk_r, trunk_r * 0.7, 0.0, trunk_h, Vector3.ZERO, 4)
	var m := MeshKit.finish(st, MeshKit.mat(trunk_c, 0.96, 0.0))
	var st2 := MeshKit.begin()
	var rings := [MeshKit.ring(canopy_r, canopy_r, trunk_h * 0.55, 0.0, 2.0, seg),
		MeshKit.ring(canopy_r * 0.08, canopy_r * 0.08, trunk_h * 0.55 + canopy_h, 0.0, 2.0, seg)]
	MeshKit.loft(st2, rings, Vector3(0, trunk_h * 0.55 + canopy_h * 0.4, 0))
	var leaves: ArrayMesh = MeshKit.finish(st2, MeshKit.mat(leaf_c, 0.96, 0.0))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.surface_get_arrays(0))
	m.surface_set_material(1, MeshKit.mat(leaf_c, 0.96, 0.0))
	return m

func _tree_mesh() -> ArrayMesh:
	return _leafy(0.42, 4.2, 3.6, 6.0, Color(0.21, 0.15, 0.11), Color(0.15, 0.27, 0.12), 5)

func _pine_mesh() -> ArrayMesh:
	return _leafy(0.34, 5.0, 2.7, 10.0, Color(0.19, 0.14, 0.10), Color(0.10, 0.21, 0.13), 5)

func _rock_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rings := [
		MeshKit.ring(1.4, 0.9, 0.0, -2.0, 2.4, 6),
		MeshKit.ring(2.6, 1.9, 0.6, 0.0, 2.0, 6),
		MeshKit.ring(1.2, 0.8, 0.2, 2.2, 2.4, 6),
	]
	MeshKit.loft(st, rings, Vector3(0, 0.8, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.33, 0.31, 0.29), 0.98, 0.0))

# ------------------------------------------------------- home base clutter
func _home_base() -> void:
	# parked jets on the apron
	var park := [["f16", Vector3(96, 0, -300), 90.0], ["f16", Vector3(96, 0, -340), 90.0],
		["f15", Vector3(96, 0, -390), 90.0], ["f35", Vector3(200, 0, -470), -90.0]]
	for p in park:
		var m := JetFactory.build(JetSpec.get_spec(p[0]))
		var node: Node3D = m["root"]
		var spec := JetSpec.get_spec(p[0])
		var gh := 0.0
		for g in spec["gear"]:
			gh = maxf(gh, absf(g["pos"].y) + g["r"])
		node.position = (p[1] as Vector3) + Vector3(0, gh, 0)
		node.rotation_degrees = Vector3(0, p[2], 0)
		for h in m["stores"].values():
			h.visible = false
		add_child(node)
	# vehicles, blast walls and fuel bowsers
	var truck := _truck_mesh()
	var wall := _wall_mesh()
	var tx := []
	var wx := []
	for i in 9:
		var px := 120.0 + float(i % 3) * 26.0
		var pz := -560.0 - floorf(float(i) / 3.0) * 22.0
		tx.append(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(px, 0, pz)))
	for i in 12:
		wx.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(60.0 + i * 16.0, 0, -690.0)))
	_scatter(truck, tx, "Vehicles")
	_scatter(wall, wx, "BlastWalls")

func _truck_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(2.4, 1.6, 6.2), Vector3(0, 1.5, 0))
	MeshKit.box(st, Vector3(2.2, 1.4, 2.0), Vector3(0, 2.6, -2.0))
	for sx in [-1.0, 1.0]:
		for zz in [-2.0, 1.2, 2.4]:
			MeshKit.cone(st, 0.5, 0.5, -0.2, 0.2, Vector3(sx * 1.25, 0.5, zz), 6)
	return MeshKit.finish(st, MeshKit.mat(Color(0.24, 0.28, 0.20), 0.9, 0.1))

func _wall_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(14.0, 3.2, 1.2), Vector3(0, 1.6, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.46, 0.45, 0.40), 0.96, 0.0))

# ---------------------------------------------------------------- roads
## Trunk roads and town streets as a single hugging surface. Sampled tightly so
## it follows the ground instead of floating over it, with a kerb strip either
## side to hide the seam.
func _build_roads() -> void:
	var st := MeshKit.begin()
	var kerb := MeshKit.begin()
	for r in Sim.ROADS:
		_ribbon(st, kerb, r[0], r[1], 7.5)
	for r in _streets:
		_ribbon(st, kerb, r[0], r[1], 5.0)
	add_child(MeshKit.mi(MeshKit.finish(kerb, MeshKit.mat(Color(0.34, 0.32, 0.28), 0.98, 0.0)), "Kerbs"))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.105, 0.105, 0.115), 0.94, 0.0)), "Roads"))

func _ribbon(st: SurfaceTool, kerb: SurfaceTool, a: Vector2, b: Vector2, half: float) -> void:
	var len2 := a.distance_to(b)
	if len2 < 1.0:
		return
	var steps := maxi(int(len2 / 11.0), 2)
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var prev := []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var row := []
		for k in [-1.55, -1.0, 1.0, 1.55]:
			var q: Vector2 = p + nrm * half * float(k)
			var y := Sim.height_at(q.x, q.y)
			row.append(Vector3(q.x, y + 0.16, q.y))
		# lift the surface to the highest of the two kerbs so it never sinks in
		var top: float = maxf(row[1].y, row[2].y)
		row[1] = Vector3(row[1].x, top, row[1].z)
		row[2] = Vector3(row[2].x, top, row[2].z)
		row[0] = Vector3(row[0].x, minf(row[0].y, top) - 0.04, row[0].z)
		row[3] = Vector3(row[3].x, minf(row[3].y, top) - 0.04, row[3].z)
		if i > 0:
			_strip(st, prev[1], prev[2], row[2], row[1])
			_strip(kerb, prev[0], prev[1], row[1], row[0])
			_strip(kerb, prev[2], prev[3], row[3], row[2])
		prev = row

func _strip(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)

# ---------------------------------------------------------------- infrastructure
const PYLON_ROUTES := [
	[Vector2(900, 3100), Vector2(-2100, -4900), Vector2(-1500, -6600)],
	[Vector2(1100, -3200), Vector2(2400, 3900), Vector2(4300, 10600)],
	[Vector2(-1900, 3100), Vector2(2400, 4000)],
]

func _pylon_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var h := 34.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			# splayed legs: two boxes each, meeting at the waist
			MeshKit.box(st, Vector3(0.5, h * 0.55, 0.5),
				Vector3(sx * 2.6, h * 0.28, sz * 2.6))
			MeshKit.box(st, Vector3(0.4, h * 0.5, 0.4),
				Vector3(sx * 1.1, h * 0.75, sz * 1.1))
	MeshKit.box(st, Vector3(15.0, 0.7, 0.7), Vector3(0, h * 0.70, 0))
	MeshKit.box(st, Vector3(11.0, 0.6, 0.6), Vector3(0, h * 0.88, 0))
	MeshKit.box(st, Vector3(0.6, 2.4, 0.6), Vector3(0, h + 1.0, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.42, 0.43, 0.45), 0.85, 0.35))

func _powerlines() -> void:
	var mesh := _pylon_mesh()
	var xf := []
	var wire := MeshKit.begin()
	for route in PYLON_ROUTES:
		var pts: Array = []
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var span := a.distance_to(b)
			var n := maxi(int(span / 190.0), 1)
			for k in n:
				var q: Vector2 = a.lerp(b, float(k) / float(n))
				if Sim.height_at(q.x, q.y) < Sim.WATER_LEVEL + 3.0:
					continue
				if not Sim.clear_of_airfield(q.x, q.y) or _inside_town(q):
					continue
				pts.append(q)
		pts.append(route[route.size() - 1])
		var prev := Vector3.INF
		for q in pts:
			var y: float = Sim.height_at(q.x, q.y)
			xf.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(q.x, y - 1.0, q.y)))
			var top := Vector3(q.x, y + 23.8, q.y)
			if prev != Vector3.INF:
				_catenary(wire, prev, top)
			prev = top
	_scatter(mesh, xf, "Pylons")
	add_child(MeshKit.mi(MeshKit.finish(wire, MeshKit.mat(Color(0.07, 0.07, 0.08), 0.9, 0.1)), "Wires"))
	_stats["pylons"] = xf.size()

## Three sagging conductors between two pylon tops.
func _catenary(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var sag: float = a.distance_to(b) * 0.045
	var side := (b - a).cross(Vector3.UP).normalized()
	for lane in [-5.6, 0.0, 5.6]:
		var off: Vector3 = side * float(lane) + Vector3(0, 3.2 if lane == 0.0 else 0.0, 0)
		var prev_a := Vector3.ZERO
		var prev_b := Vector3.ZERO
		var seg := 8
		for i in seg + 1:
			var t := float(i) / float(seg)
			var p: Vector3 = a.lerp(b, t) + off
			p.y -= sag * (1.0 - 4.0 * pow(t - 0.5, 2.0))
			var l := p + Vector3(0, 0.09, 0)
			var r := p - Vector3(0, 0.09, 0)
			if i > 0:
				for v in [prev_a, prev_b, r, prev_a, r, l]:
					st.set_normal(Vector3.UP)
					st.add_vertex(v)
			prev_a = l
			prev_b = r

func _comms_masts() -> void:
	var st := MeshKit.begin()
	for i in 5:
		var w: float = lerpf(2.4, 0.7, float(i) / 4.0)
		MeshKit.box(st, Vector3(w, 12.0, w), Vector3(0, 6.0 + i * 12.0, 0))
	MeshKit.box(st, Vector3(5.5, 0.5, 0.5), Vector3(0, 44.0, 0))
	MeshKit.box(st, Vector3(0.5, 0.5, 5.5), Vector3(0, 50.0, 0))
	var mast := MeshKit.finish(st, MeshKit.mat(Color(0.55, 0.42, 0.36), 0.9, 0.3))
	var spots := [Vector2(-4200, 1900), Vector2(3200, -2400), Vector2(-2400, -9800),
		Vector2(5200, 6400), Vector2(-5600, 4200), Vector2(1200, 12800)]
	var xf := []
	for q in spots:
		var y := Sim.height_at(q.x, q.y)
		if y < Sim.WATER_LEVEL + 5.0 or not Sim.clear_of_airfield(q.x, q.y) or _inside_town(q):
			continue
		xf.append(Transform3D(Basis(), Vector3(q.x, y, q.y)))
		var beacon := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 1.1
		sp.height = 2.2
		sp.radial_segments = 6
		sp.rings = 4
		beacon.mesh = sp
		beacon.material_override = MeshKit.mat(Color.BLACK, 0.4, 0.0, Color(1.0, 0.12, 0.10))
		beacon.position = Vector3(q.x, y + 68.0, q.y)
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beacon)
	_scatter(mast, xf, "CommsMasts")

func _fences() -> void:
	var post := MeshKit.begin()
	MeshKit.box(post, Vector3(0.14, 2.4, 0.14), Vector3(0, 1.2, 0))
	var post_mesh := MeshKit.finish(post, MeshKit.mat(Color(0.40, 0.40, 0.38), 0.9, 0.2))
	var mesh_st := MeshKit.begin()
	var xf := []
	var ring := [Vector2(-300, -1780), Vector2(300, -1780), Vector2(300, 1780), Vector2(-300, 1780)]
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		var n := maxi(int(a.distance_to(b) / 9.0), 1)
		for k in n:
			var q: Vector2 = a.lerp(b, float(k) / float(n))
			var y := Sim.height_at(q.x, q.y)
			xf.append(Transform3D(Basis(Vector3.UP, atan2(b.x - a.x, b.y - a.y)),
				Vector3(q.x, y, q.y)))
			var q2: Vector2 = a.lerp(b, float(k + 1) / float(n))
			var y2 := Sim.height_at(q2.x, q2.y)
			_fence_panel(mesh_st, Vector3(q.x, y, q.y), Vector3(q2.x, y2, q2.y))
	_scatter(post_mesh, xf, "FencePosts")
	add_child(MeshKit.mi(MeshKit.finish(mesh_st,
		MeshKit.mat(Color(0.36, 0.37, 0.36), 0.95, 0.1)), "FenceMesh"))
	_stats["fence_posts"] = xf.size()

func _fence_panel(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var lo := 0.25
	var hi := 2.25
	for v in [a + Vector3(0, hi, 0), b + Vector3(0, hi, 0), b + Vector3(0, lo, 0),
			a + Vector3(0, hi, 0), b + Vector3(0, lo, 0), a + Vector3(0, lo, 0)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)

func _windfarm() -> void:
	var ridge := Vector2(-6200, -2200)
	for i in 9:
		var q := ridge + Vector2(float(i % 3) * 420.0, floorf(float(i) / 3.0) * 480.0)
		var y := Sim.height_at(q.x, q.y)
		if y < Sim.WATER_LEVEL + 20.0 or not Sim.clear_of_airfield(q.x, q.y):
			continue
		var t := Turbine.new()
		t.build()
		add_child(t)
		t.global_position = Vector3(q.x, y, q.y)
		t.rotation.y = randf() * TAU

func _utility_props() -> void:
	var tank := MeshKit.begin()
	MeshKit.cone(tank, 4.5, 4.5, 0.0, 9.0, Vector3.ZERO, 10)
	var tank_mesh := MeshKit.finish(tank, MeshKit.mat(Color(0.66, 0.66, 0.62), 0.7, 0.4))
	var tower := MeshKit.begin()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshKit.box(tower, Vector3(0.4, 16.0, 0.4), Vector3(sx * 2.2, 8.0, sz * 2.2))
	MeshKit.cone(tower, 5.0, 3.2, 0.0, 7.0, Vector3(0, 16.0, 0), 9)
	var tower_mesh := MeshKit.finish(tower, MeshKit.mat(Color(0.62, 0.63, 0.60), 0.85, 0.2))
	var tx := []
	var wx := []
	for t in TOWNS:
		var c: Vector3 = t[0]
		var r: float = t[1]
		for i in 3:
			var q := Vector2(c.x, c.z) + Vector2(cos(float(i) * 2.1), sin(float(i) * 2.1)) * (r * 1.15)
			if not Sim.buildable(q.x, q.y, 0.92, 6.0):
				continue
			var y := Sim.height_at(q.x, q.y)
			(tx if i % 2 == 0 else wx).append(Transform3D(Basis(), Vector3(q.x, y, q.y)))
	_scatter(tank_mesh, tx, "FuelTanks", true)
	_scatter(tower_mesh, wx, "WaterTowers", true)

## Slow-turning three blade turbine.
class Turbine extends Node3D:
	var hub: Node3D

	func build() -> void:
		var st := MeshKit.begin()
		MeshKit.cone(st, 2.2, 1.3, 0.0, 62.0, Vector3.ZERO, 9)
		var tw := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.86, 0.87, 0.88), 0.7, 0.1)), "Tower")
		tw.rotation_degrees = Vector3(-90, 0, 0)
		add_child(tw)
		hub = Node3D.new()
		hub.position = Vector3(0, 62.0, 0)
		add_child(hub)
		var nst := MeshKit.begin()
		MeshKit.box(nst, Vector3(2.6, 2.6, 7.0), Vector3(0, 0, 1.6))
		for i in 3:
			var a := TAU * float(i) / 3.0
			var dir := Vector3(cos(a), sin(a), 0.0)
			var poly := PackedVector2Array([Vector2(1.4, -0.9), Vector2(26.0, -0.35),
				Vector2(26.0, 0.35), Vector2(1.4, 1.1)])
			MeshKit.prism(nst, poly, dir, Vector3(0, 0, 1), dir.cross(Vector3(0, 0, 1)).normalized(),
				PackedFloat32Array([0.22, 0.06, 0.06, 0.22]), Vector3(0, 0, -1.2))
		hub.add_child(MeshKit.mi(MeshKit.finish(nst,
			MeshKit.mat(Color(0.90, 0.91, 0.92), 0.6, 0.1)), "Rotor"))

	func _process(delta: float) -> void:
		if hub:
			hub.rotate_z(delta * 0.85)
