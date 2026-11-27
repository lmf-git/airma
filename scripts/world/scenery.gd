class_name Scenery
extends Node3D

## Where a street meets a road of the network, it meets it the way a street
## does. A road at the town's own level is a crossroads: the street stops at
## its edge and neither lays its kerb across the other (`ribbon` in
## raster.rs). A road a little up on a bank -- the foot of a ramp to a bridge,
## a road carried over a dip -- the street climbs to meet: its last few tens of
## metres are graded into the ground as an approach, like the road's own bank,
## and it is laid on that. One higher than that, it does not climb: it ends at
## the foot of the bank.
##
## They used to be cut back a fixed twenty metres and more from any ramp, which
## was neither: the street stopped on open ground short of the bank, with the
## made ground between, and the town's grid did not join the road through it.
const JOIN_FILL := 3.0

## Below this the road is at the street's level, near enough.
const JOIN_MIN := 0.3

## How steep a street's approach climbs: one in sixteen. (One in twelve and a
## half was drawn at one in five in places, the fifteen metre mesh folding the
## climb into the road's bank beside it.)
const STREET_GRADE := 0.06

const STREET_HALF := 5.0

## How far past the top of a street's climb its own bank still reaches: the
## shoulder a raised leg rounds off over, and the margin a street keeps.
const APPROACH_TAIL := 16.0

## For each street that climbs to meet a road, where along it (0 to 1) it does:
## street index -> [[t0, t1], ...].
var _approach_spans: Dictionary = {}

## Every place a street meets a road, for the harness: {p, dir (the street's),
## fill, kind: "level", "join" or "stop"}.
var junctions: Array = []

var _junctions_laid: Array = []

## The road network as it was handed to the painter, in the chart it was laid
## out in: carried into whatever chart there is and handed over again when the
## chart moves (`rechart`).
var _road_legs_laid := PackedFloat32Array()
## Procedural settlements and support bases scattered along the valley floor.
## Everything is instanced through MultiMeshInstance3D so a few thousand
## buildings cost a handful of draw calls.

## Centre, radius, density, tallest, name. Everything here has to sit inside the
## 18 km box the ground mask and the road distance field cover, or its streets
## are drawn but not painted and its buildings stand on unmade ground.
const TOWNS := [
	[Vector3(-2300, 0, -5200), 900.0, 0.62, 26.0, "Kestrel"],
	[Vector3(2600, 0, 4200), 1500.0, 0.70, 72.0, "Rampart City"],
	[Vector3(-1900, 0, 3100), 520.0, 0.55, 14.0, "Vane"],
	[Vector3(2100, 0, -9200), 620.0, 0.58, 18.0, "Northgate"],
	[Vector3(-9800, 0, -1400), 780.0, 0.60, 22.0, "Marrow"],
	[Vector3(8200, 0, -13500), 540.0, 0.52, 15.0, "Ashfen"],
	[Vector3(-12500, 0, 8600), 900.0, 0.64, 30.0, "Coldharbour"],
	[Vector3(6400, 0, 12800), 700.0, 0.58, 20.0, "Selby"],
	[Vector3(-6200, 0, -14200), 460.0, 0.50, 12.0, "Tarn"],
	[Vector3(12800, 0, 2400), 620.0, 0.56, 17.0, "Quayhead"],
	# villages: small, low and spread to the edges of the inhabited box, so a
	# conquest has ground to fight over rather than five objectives in a huddle
	[Vector3(-15200, 0, -8200), 420.0, 0.48, 11.0, "Redd"],
	[Vector3(11600, 0, -4200), 500.0, 0.52, 14.0, "Saltmarsh"],
	[Vector3(-3400, 0, 14800), 560.0, 0.54, 16.0, "Brackwater"],
	[Vector3(9800, 0, 10400), 480.0, 0.50, 13.0, "Fen End"],
	[Vector3(-16000, 0, 1200), 440.0, 0.49, 12.0, "Stonebridge"],
	[Vector3(1800, 0, -16200), 520.0, 0.53, 15.0, "Harrow"],
]

var _rng := RandomNumberGenerator.new()

var _streets: Array = []
var _stats := {}
static var current: Scenery = null
# Batches that can be flattened: {mmi, xforms, dead, centre, radius}
var _breakable: Array = []
## Every town building, so the harness can check them against the roads. The
## batches get generated node names once several towns collide on "Town0", so
## walking the children only ever found the first town's worth.
var town_xforms: Array = []
## Where the pylons ended up, for the same reason: a MultiMesh cannot be read
## back in headless, so the harness needs the source.
var pylon_spots: Array = []

## Lay out the road network first. The terrain paints roads into its own vertex
## colours, so the street grid has to exist before the ground is generated or
## the towns end up with invisible streets.
## Sites the towns and plans the roads: see `TownPlanner`.
var _planner := TownPlanner.new(self)

func _ready() -> void:
	_scat_clump.seed = 20260905
	_scat_clump.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_scat_clump.frequency = SCAT_CLUMP_FREQ
	_scat_clump.fractal_octaves = 2
	current = self

## Where each town actually ended up, after being moved onto workable ground.
var sites: Array = []
var _plan_cached := false

func plan() -> void:
	_streets.clear()
	# Siting sixteen towns on the flattest ground within reach of where each was
	# wanted, then routing a trunk network to them and surveying its cut and
	# fill, is the same answer every run and about three seconds of arriving at
	# it. The streets themselves are pure geometry off the result, so they are
	# cheap enough to lay out again either way.
	var cached_sites: Variant = WorldBake.get_baked("town_sites")
	var cached_roads: Variant = WorldBake.get_baked("roads")
	# At least the named towns, not exactly them: `sites` carries the distant
	# clusters as well now, so an equality check against the hand-written list
	# never matched and the whole network was routed from scratch every launch
	# -- twenty-eight seconds of it.
	var hit: bool = cached_sites is Array and cached_roads is Dictionary \
		and (cached_sites as Array).size() >= TOWNS.size()
	_plan_cached = hit
	if hit:
		sites = cached_sites
		Sim.roads.load_road_state(cached_roads)
	else:
		var t_s := Time.get_ticks_msec()
		_planner.site_towns()
		if Sim.roads.debug_roads:
			print("[plan] siting towns and dispatching routes: %d ms"
				% (Time.get_ticks_msec() - t_s))

## Is the network still being searched? The caller keeps drawing while it is.
func plan_busy() -> bool:
	return not _plan_cached and not Sim.roads.roads_routed()

## Everything that has to wait for the routes: the streets hang off the trunk
## network, so they cannot be laid until it exists.
func plan_finish() -> void:
	var t0 := Time.get_ticks_msec()
	if not _plan_cached:
		Sim.roads.finish_roads()
	var t1 := Time.get_ticks_msec()
	# Which trunk road each town runs out to meet, for all of them at once.
	var centres := PackedVector2Array()
	for t in sites:
		centres.append(t["c"] as Vector2)
	var trunks: PackedVector2Array = Sim.roads.nearest_trunk_many(centres)
	for i in sites.size():
		_planner.plan_town_streets(sites[i]["c"], float(sites[i]["r"]), trunks[i])
	var t2 := Time.get_ticks_msec()
	_streets.append([Vector2(-1500, -6600), Vector2(-2300, -5200)])
	_planner.plan_junctions()
	var t3 := t2
	var t4 := t2
	var t5 := t2
	if not _plan_cached:
		Sim.roads.register_segments(_streets)
		t3 = Time.get_ticks_msec()
		WorldBake.put("town_sites", sites)
		t4 = Time.get_ticks_msec()
		var st := Sim.roads.road_state()
		t5 = Time.get_ticks_msec()
		WorldBake.put("roads", st)
	if Sim.roads.debug_roads:
		print("[plan] finish_roads %d | streets %d | register_segments %d | bake sites %d | road_state %d | bake roads %d ms" % [
			t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4,
			Time.get_ticks_msec() - t5])
	_stats["streets"] = _streets.size()

## Put each town on the flattest ground within reach of where it was wanted,
## then level a platform under it. People build towns on the valley floor; they
## do not lay a grid of streets up the side of a mountain and live on the
## staircase. Both halves matter — moving alone still leaves a gradient, and
## levelling alone puts a cliff round a town that should never have been there.
## Settlement clusters elsewhere in the world, and the names their towns take.
##
## The map is twelve hundred kilometres across and everything anybody had built
## on it stood inside a thirty-six kilometre box around one airfield. These are
## found rather than written down, because a coordinate picked by hand lands in
## the ocean as often as not once the continent field decides where the land is:
## the map is swept for places with enough dry, workable ground, far from home
## and far from each other.
const REGIONS := 4
const REGION_TOWNS := 4
## Towns that belong to nobody, in the country between the factions.
const FREE_NAMES := ["Marchgate", "Tolland", "Verge", "Sallow Cross",
	"Kestrel", "Amberly", "Norwood Halt", "Fen Marsh", "Redlake", "Thorn"]

const REGION_NAMES := [
	["Calder", "Vasser Bay", "Ostmark", "Pell"],
	["Sarn", "Hollowfield", "Ridgeway", "Anselm"],
	["Kettering", "Draymoor", "Lowry", "Fenwick"],
	["Aubrey", "Stannard", "Colm", "Harrowgate"],
]

func build() -> void:
	_rng.seed = 20260821
	Obstacles.clear()
	if _streets.is_empty():
		plan()
	var tm := [Time.get_ticks_msec()]
	var mark := func(what: String) -> void:
		var now := Time.get_ticks_msec()
		_stats["ms_" + what] = now - int(tm[0])
		tm[0] = now
	for b in _plan_all_towns():
		_town_build(b)
	mark.call("towns")
	_military(Vector3(-1500, 0, -6600))
	_farms()
	mark.call("farms")
	_build_roads()
	_build_structures()
	mark.call("roads")
	_powerlines()
	_comms_masts()
	_fences()
	_windfarm()
	_utility_props()
	mark.call("utility")
	_scatter_nature()
	mark.call("nature")
	_town_detail()
	mark.call("detail")
	_landmarks()
	_home_base()
	mark.call("landmarks")
	_lay_down()

# -------------------------------------------------------------- chart moves
## Everything this built, as it was built, so it can be carried into whatever
## chart is current: see `Sim.boot_affine`. Each entry is the node, its
## transform as built, the point it is carried about, how it is carried, and
## for the pieces carried bit by bit, the bits as built.
##
## Nothing here was ever moved when the chart moved. Every building, lamp post,
## tree, road surface and fuel tank stayed at its old numbers, and in the new
## chart those numbers are another place at another height: fly a hundred and
## fifty kilometres and turn round, and the towns you left were standing in the
## sea, or under a hill, or in the air.
var _laid: Array = []
var _sites_laid: Array = []
var _streets_laid: Array = []
## Carried as one piece: the node's own transform. Good to a centimetre over a
## town, under a metre over a forty kilometre road mesh.
const CARRY_NODE := 0
## A MultiMesh spread too wide for one transform -- fuel tanks a hundred
## kilometres apart -- carried an instance at a time.
const CARRY_EACH := 1
## A mesh spread too wide for one transform, small enough to redo by vertex:
## the bridges and the power lines.
const CARRY_VERTS := 2
## Wider than this and one transform for the whole node will not do.
const ONE_PIECE := 8000.0
## ...unless it is too many vertices to redo, which the road surfaces are:
## thirty-odd of them came to a million vertices and a third of a second, every
## chart move. One transform does them to under a metre.
const VERTS_MAX := 20000
## The MultiMeshes carried an instance at a time, and their entries in `_laid`:
## anything that redraws one of their instances has to carry it the same way.
var _each: Dictionary = {}

func _lay_down() -> void:
	_laid.clear()
	_each.clear()
	for ch in get_children():
		if not (ch is Node3D):
			continue
		var n3: Node3D = ch
		var xf: Transform3D = n3.transform
		var entry: Array = [n3, xf, xf.origin, CARRY_NODE, null]
		if ch is MultiMeshInstance3D and (ch as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (ch as MultiMeshInstance3D).multimesh
			var ab: AABB = mm.get_aabb()
			entry[2] = xf * ab.get_center()
			if ab.size.length() > ONE_PIECE:
				var xs: Array = []
				for i in mm.instance_count:
					xs.append(mm.get_instance_transform(i))
				entry[3] = CARRY_EACH
				entry[4] = xs
				_each[ch] = entry
		elif ch is MeshInstance3D and (ch as MeshInstance3D).mesh is ArrayMesh:
			var me: ArrayMesh = (ch as MeshInstance3D).mesh
			var ab2: AABB = me.get_aabb()
			entry[2] = xf * ab2.get_center()
			if ab2.size.length() > ONE_PIECE:
				var surfs: Array = []
				var verts := 0
				for s in me.get_surface_count():
					var arr: Array = me.surface_get_arrays(s)
					verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
					surfs.append([me.surface_get_primitive_type(s), arr,
						me.surface_get_material(s)])
				if verts <= VERTS_MAX:
					entry[3] = CARRY_VERTS
					entry[4] = surfs
		_laid.append(entry)
	_sites_laid.clear()
	for t in sites:
		_sites_laid.append(t["c"])
	_streets_laid = _streets.duplicate(true)
	_junctions_laid = junctions.duplicate(true)

## The chart has moved: carry everything built into it. Worked from what was
## laid down every time, so there and back again is exactly where it started.
func rechart() -> void:
	# A heap is drawn where it fell, in the chart there was; it is cleared
	# rather than carried, with the box it stands for.
	for r in get_tree().get_nodes_in_group("rubble"):
		(r as Node).call("clear_now")
	# and those not built yet, the same
	for h in _heaps_due:
		var rid: int = Obstacles.rubble_of(int(h[2])) if int(h[2]) >= 0 else -1
		if rid >= 0:
			Obstacles.remove(rid)
	_heaps_due.clear()
	for entry in _laid:
		var n3: Node3D = entry[0]
		if not is_instance_valid(n3):
			continue
		var xf: Transform3D = entry[1]
		match int(entry[3]):
			CARRY_NODE:
				n3.transform = Sim.boot_affine(entry[2]) * xf
			CARRY_EACH:
				var mm: MultiMesh = (n3 as MultiMeshInstance3D).multimesh
				var xs: Array = entry[4]
				for i in xs.size():
					mm.set_instance_transform(i, _carried(xf, xs[i]))
			CARRY_VERTS:
				_carry_mesh(n3 as MeshInstance3D, xf, entry[4])
	for i in mini(sites.size(), _sites_laid.size()):
		sites[i]["c"] = _carried_xz(_sites_laid[i])
	for j in mini(_streets.size(), _streets_laid.size()):
		var sg: Array = _streets_laid[j]
		_streets[j] = [_carried_xz(sg[0]), _carried_xz(sg[1])]
	# The painted roads with them. As strips of geometry they were carried
	# like everything else built; painted, they are a list in the extension,
	# and left at their old numbers they were painted where the roads had been
	# in the old chart -- across fields, with the towns somewhere else.
	if not _road_legs_laid.is_empty():
		var moved := PackedFloat32Array(_road_legs_laid)
		for i in range(0, moved.size() - 7, 8):
			var a2: Vector2 = _carried_xz(Vector2(moved[i], moved[i + 1]))
			var b2: Vector2 = _carried_xz(Vector2(moved[i + 2], moved[i + 3]))
			moved[i] = a2.x
			moved[i + 1] = a2.y
			moved[i + 2] = b2.x
			moved[i + 3] = b2.y
		Sim.native.publish_road_pieces(moved)
		var terrain_node: Node = get_parent().get("terrain") if get_parent() != null else null
		if terrain_node != null and terrain_node.has_method("roads_changed"):
			terrain_node.roads_changed()
	# and where they meet the roads, which go with them
	for j in mini(junctions.size(), _junctions_laid.size()):
		var jl: Dictionary = _junctions_laid[j]
		var at: Vector2 = jl["p"]
		var to: Vector2 = _carried_xz(at + (jl["dir"] as Vector2))
		var pm: Vector2 = _carried_xz(at)
		junctions[j]["p"] = pm
		junctions[j]["dir"] = (to - pm).normalized()
		var ro: Vector2 = _carried_xz(at + (jl["along"] as Vector2))
		junctions[j]["along"] = (ro - pm).normalized()

## One instance of a MultiMesh carried on its own, in its node's own frame.
func _carried(node_xf: Transform3D, t: Transform3D) -> Transform3D:
	var w: Transform3D = node_xf * t
	return node_xf.affine_inverse() * (Sim.boot_affine(w.origin) * w)

func _carried_xz(p: Vector2) -> Vector2:
	var w: Vector3 = Sim.boot_to_world(Vector3(p.x, 0.0, p.y))
	return Vector2(w.x, w.z)

## A mesh redrawn with every vertex carried, a couple of kilometres of it at a
## time by one transform: right to a centimetre, and a transform per patch
## rather than per vertex.
func _carry_mesh(mi: MeshInstance3D, node_xf: Transform3D, surfs: Array) -> void:
	const PATCH := 2000.0
	var me := mi.mesh as ArrayMesh
	var back: Transform3D = node_xf.affine_inverse()
	var patches := {}
	me.clear_surfaces()
	for s in surfs:
		var arr: Array = (s[1] as Array).duplicate()
		var vin: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vout := PackedVector3Array()
		vout.resize(vin.size())
		var nin: Variant = arr[Mesh.ARRAY_NORMAL]
		var nout := PackedVector3Array()
		if nin is PackedVector3Array:
			nout.resize((nin as PackedVector3Array).size())
		for k in vin.size():
			var w: Vector3 = node_xf * vin[k]
			var key := Vector2i(int(floor(w.x / PATCH)), int(floor(w.z / PATCH)))
			var a: Variant = patches.get(key)
			if a == null:
				a = Sim.boot_affine(Vector3((float(key.x) + 0.5) * PATCH, 0.0,
					(float(key.y) + 0.5) * PATCH))
				patches[key] = a
			var at: Transform3D = a
			vout[k] = back * (at * w)
			if k < nout.size():
				nout[k] = (back.basis * (at.basis * (node_xf.basis
					* (nin as PackedVector3Array)[k]))).normalized()
		arr[Mesh.ARRAY_VERTEX] = vout
		if nout.size() > 0:
			arr[Mesh.ARRAY_NORMAL] = nout
		me.add_surface_from_arrays(int(s[0]), arr)
		if s[2] != null:
			me.surface_set_material(me.get_surface_count() - 1, s[2])

## Redraw one instance of a MultiMesh from where it stands in the chart the world
## was built on, carrying it the way its batch is carried -- and remember it
## that way, so the next chart move carries what it has become and not what it
## was built as.
func _redraw(mmi: MultiMeshInstance3D, i: int, t: Transform3D) -> void:
	var entry: Variant = _each.get(mmi)
	if entry == null:
		mmi.multimesh.set_instance_transform(i, t)
		return
	(entry[4] as Array)[i] = t
	mmi.multimesh.set_instance_transform(i, _carried(entry[1], t))

# -------------------------------------------------------------- town detail
## Street furniture: the things you only see when you are down among them.
## Drawn with a visibility range so they cost nothing from the air — a town is
## a grey smudge from twenty thousand feet and a place with lamp posts and
## planters in it when you are taxiing through, which is the whole point.
##
## What gets built is chosen by the country the town stands in and the biome
## around it, so a town in the desert does not get the same street trees as one
## in the pine forest, and the paint changes with the border.
const PROP_FADE := 520.0
## Room a piece of street furniture needs around and over it: a lamp post is the
## tallest of them, at five and a half metres, and a kiosk the widest.
const PROP_REACH := 1.5
const PROP_HEADROOM := 6.5

func _town_detail() -> void:
	var made := 0
	for t in sites:
		var c: Vector2 = t["c"]
		var r: float = float(t["r"])
		# An independent town carries its own allegiance -- which is none. The
		# faction field is a function of position, and the whole point of these
		# is that they sit in somebody else's part of the map without being
		# theirs.
		var faction: String = String(t.get("faction", ""))
		if faction == "":
			faction = Sim.region_faction(c.x, c.y)
		var ground: float = Sim.height_at(c.x, c.y)
		var biome: String = Sim.biomes.kind(c.x, c.y, ground,
			Sim.normal_at(c.x, c.y).y)
		var lamp: Array = []
		var seat: Array = []
		var kiosk: Array = []
		var planter: Array = []
		# Where every prop in this town would stand, before any of them is
		# placed.
		#
		# Standing one on the ground means knowing where the *drawn* surface is,
		# which is four heights interpolated over a terrain cell -- and asked one
		# prop at a time that is four crossings of the extension boundary each,
		# a hundred and eighty thousand of them for the world's thirty-six
		# thousand street props. Measured, 232 ms of the boot. Gathered first and
		# asked for in one call a town, it is forty-eight crossings and the
		# interpolation runs across every core.
		var at := PackedVector2Array()
		var yaw := PackedFloat32Array()
		var which := PackedInt32Array()
		# along the streets as they are drawn: a stretch cut back from a bank
		# or a low deck has no lamp posts standing along it in the open
		for seg in (street_draw if not street_draw.is_empty() else _streets):
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			if a.distance_to(c) > r * 1.2 and b.distance_to(c) > r * 1.2:
				continue
			var run := a.distance_to(b)
			if run < 40.0:
				continue
			var dir := (b - a) / run
			var side := Vector2(-dir.y, dir.x)
			var step := 38.0
			var n := int(run / step)
			var facing: float = atan2(dir.x, -dir.y)
			for i in range(1, n):
				var along: float = float(i) * step
				for sx in [-1.0, 1.0]:
					at.append(a + dir * along + side * (sx * 9.5))
					yaw.append(facing)
					which.append(i)
		var gys: PackedFloat32Array = Sim.native.surfaces_at(at,
			Terrain.BASE_CELL)
		# (only asked prop by prop of a town a bridge comes anywhere near)
		var box_lo := Vector2(INF, INF)
		var box_hi := Vector2(-INF, -INF)
		for q0 in at:
			box_lo = Vector2(minf(box_lo.x, q0.x), minf(box_lo.y, q0.y))
			box_hi = Vector2(maxf(box_hi.x, q0.x), maxf(box_hi.y, q0.y))
		var bridged: bool = Sim.roads.near_bridges(box_lo, box_hi, PROP_REACH)
		for k in at.size():
			var q: Vector2 = at[k]
			var gy: float = gys[k]
			if gy < Sim.sea_at(q.x, q.y) + 1.0:
				continue
			# Not on a ramp up to a bridge, and not under a deck it would
			# stand up through: the street it lines may go under one.
			if bridged and Sim.roads.bridge_headroom(q.x, q.y, PROP_REACH, gy) < PROP_HEADROOM:
				continue
			var xf := Transform3D(Basis(Vector3.UP, yaw[k]),
				Vector3(q.x, gy, q.y))
			var i2: int = which[k]
			if i2 % 2 == 0:
				lamp.append(xf)
			elif i2 % 5 == 1:
				seat.append(xf)
			elif i2 % 7 == 3:
				planter.append(xf)
			elif i2 % 11 == 5:
				kiosk.append(xf)
		var tone: Color = Sim.faction_colour(faction)
		made += _detail_batch(SceneryMeshes.lamp_mesh(tone), lamp, "Lamps_%s" % String(t["name"]))
		# Benches, kiosks and planters stop a round -- something to get behind
		# in a street fight -- but not a tank, which knocks them over. Lamp
		# posts do not: their box is the reach of the arm, and a round would
		# stop on the air under it.
		made += _detail_batch(SceneryMeshes.seat_mesh(tone, biome), seat, "Seats_%s" % String(t["name"]), true)
		made += _detail_batch(SceneryMeshes.kiosk_mesh(tone, faction), kiosk,
			"Kiosks_%s" % String(t["name"]), true)
		made += _detail_batch(SceneryMeshes.planter_mesh(tone, biome), planter,
			"Planters_%s" % String(t["name"]), true)
		_stats["town_faction_" + faction] = int(_stats.get("town_faction_" + faction, 0)) + 1
	_stats["street_props"] = made

## Street furniture, so that something driving down the pavement can find
## what it has just hit: [multimesh, transforms] per batch, and a coarse hash
## of where every piece stands. The hash is built the first time anybody asks
## -- thirty-six thousand entries is forty milliseconds nobody flying an
## aeroplane should pay at boot.
var _furniture: Array = []
var _furn_hash: Dictionary = {}
var _furn_down: Dictionary = {}
## Furniture code -> its soft obstacle entry, for the pieces that stop rounds,
## so that one knocked flat stops stopping them.
var _furn_obs: Dictionary = {}
const FURN_CELL := 12.0

func _furn_key(x: float, z: float) -> int:
	return int(floor(x / FURN_CELL)) * 1048576 + int(floor(z / FURN_CELL))

## Flatten whatever street furniture is within `r` of `at`: a lamp post goes
## over the way it was pushed, a bench or a kiosk is driven into the ground.
## Returns how many went.
func knock(at_in: Vector3, r: float, push: Vector3) -> int:
	if _furniture.is_empty():
		return 0
	# Where the furniture stands is recorded where it was built: see `_laid`.
	var at: Vector3 = Sim.world_to_boot(at_in)
	if _furn_hash.is_empty():
		for bi in _furniture.size():
			var xs: Array = _furniture[bi][1]
			for ii in xs.size():
				var o: Vector3 = (xs[ii] as Transform3D).origin
				var k := _furn_key(o.x, o.z)
				if not _furn_hash.has(k):
					_furn_hash[k] = PackedInt32Array()
				var arr: PackedInt32Array = _furn_hash[k]
				arr.append(bi * 65536 + ii)
				_furn_hash[k] = arr
	var n := 0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var k2 := _furn_key(at.x + dx * FURN_CELL, at.z + dz * FURN_CELL)
			if not _furn_hash.has(k2):
				continue
			for code in (_furn_hash[k2] as PackedInt32Array):
				if _furn_down.has(code):
					continue
				var bi2: int = code >> 16
				var ii2: int = code & 65535
				var xf: Transform3D = (_furniture[bi2][1] as Array)[ii2]
				if Vector2(xf.origin.x - at.x, xf.origin.z - at.z).length() > r + 0.5 \
						or absf(xf.origin.y - at.y) > 4.0:
					continue
				_furn_down[code] = true
				if _furn_obs.has(code):
					Obstacles.remove(int(_furn_obs[code]))
				# over, along the way it was pushed
				var dir := Vector3(push.x, 0.0, push.z)
				dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
				var axis := Vector3.UP.cross(dir).normalized()
				var fallen := Transform3D(Basis(axis, deg_to_rad(86.0)) * xf.basis,
					xf.origin + Vector3(0, 0.12, 0))
				(_furniture[bi2][0] as MultiMesh).set_instance_transform(ii2, fallen)
				n += 1
	return n

func _detail_batch(mesh: Mesh, xforms: Array, nm: String, stops_rounds := false) -> int:
	if xforms.is_empty() or mesh == null:
		return 0
	if stops_rounds:
		var ids: PackedInt32Array = Obstacles.add_batch(mesh, xforms, Obstacles.MIN_HEIGHT,
			0.3, true)
		for ii in ids.size():
			if ids[ii] >= 0:
				_furn_obs[_furniture.size() * 65536 + ii] = ids[ii]
	var mmi := MeshKit.multimesh(mesh, xforms, nm)
	_furniture.append([mmi.multimesh, xforms])
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the LOD itself: nothing at all beyond half a kilometre
	mmi.visibility_range_end = PROP_FADE
	mmi.visibility_range_end_margin = 90.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return xforms.size()

# ---------------------------------------------------------------- landmarks
## Something to fly at. The map runs to six hundred kilometres and almost all of
## it is empty ground; these give it places, and each one tells you whose
## country you are over. Every one is built out of the same primitives as the
## rest of the scenery, sited on the drawn surface so it does not float, and put
## far enough out that reaching one is a trip rather than a taxi.
const LANDMARKS := [
	{"id": "eiffel",   "name": "Iron Tower",       "faction": "france",
	 "at": Vector2(-88000.0, -132000.0), "h": 324.0},
	{"id": "clock",    "name": "Great Clock",      "faction": "uk",
	 "at": Vector2(-141000.0, -61000.0), "h": 96.0},
	{"id": "liberty",  "name": "Liberty",          "faction": "usa",
	 "at": Vector2(-163000.0, 44000.0), "h": 93.0},
	{"id": "onion",    "name": "Onion Domes",      "faction": "russia",
	 "at": Vector2(-38000.0, -258000.0), "h": 65.0},
	{"id": "pagoda",   "name": "Great Pagoda",     "faction": "china",
	 "at": Vector2(-212000.0, -119000.0), "h": 74.0},
	{"id": "wall",     "name": "The Long Wall",    "faction": "china",
	 "at": Vector2(-188000.0, -156000.0), "h": 9.0},
	{"id": "pyramid",  "name": "Great Pyramid",    "faction": "civil",
	 "at": Vector2(-47000.0, 197000.0), "h": 139.0},
	{"id": "minaret",  "name": "Blue Minarets",    "faction": "iran",
	 "at": Vector2(-186000.0, 118000.0), "h": 58.0},
	{"id": "opera",    "name": "Harbour Shells",   "faction": "civil",
	 "at": Vector2(-96000.0, 268000.0), "h": 65.0},
	{"id": "colossus", "name": "Standing Colossus", "faction": "civil",
	 "at": Vector2(-238000.0, -204000.0), "h": 108.0},
]

func _landmarks() -> void:
	var built := 0
	for lm in LANDMARKS:
		# On the surface as drawn, and never in the sea. Half of them fell in
		# the water on the first try, so rather than drop those, walk a spiral
		# out from where it was wanted until there is dry ground under it.
		var at: Vector2 = lm["at"]
		var g: float = Terrain.surface_height(at.x, at.y)
		if g < Sim.sea_at(at.x, at.y) + 6.0:
			var found := false
			for ring in range(1, 60):
				var step: float = float(ring) * 2500.0
				for k in 12:
					var a := TAU * float(k) / 12.0
					var q := at + Vector2(cos(a), sin(a)) * step
					if absf(q.x) > Sim.WORLD_HALF or absf(q.y) > Sim.WORLD_HALF:
						continue
					var gg: float = Terrain.surface_height(q.x, q.y)
					if gg >= Sim.sea_at(q.x, q.y) + 6.0:
						at = q
						g = gg
						found = true
						break
				if found:
					break
			if not found:
				push_warning("landmark %s found no dry ground near %s"
					% [String(lm["name"]), str(at.round())])
				continue
		var node := SceneryMeshes.landmark_mesh(String(lm["id"]), float(lm["h"]),
			Sim.faction_colour(String(lm["faction"])))
		if node == null:
			continue
		node.name = String(lm["name"]).replace(" ", "")
		node.position = Vector3(at.x, g, at.y)
		add_child(node)
		Sim.register_landmark(String(lm["name"]), String(lm["faction"]),
			Vector3(at.x, g, at.y), float(lm["h"]))
		built += 1
	_stats["landmarks"] = built

# ---------------------------------------------------------------- buildings

func _scatter(mesh: Mesh, xforms: Array, nm: String, breakable := false,
		foot := AABB()) -> void:
	if xforms.is_empty():
		return
	var mmi := MeshKit.multimesh(mesh, xforms, nm)
	add_child(mmi)
	# and into the obstacle field, so it is something you can fly into rather
	# than something you fly through
	var obs_ids: PackedInt32Array = Obstacles.add_batch(mesh, xforms, Obstacles.MIN_HEIGHT,
		0.45, false, foot)
	if breakable:
		# a blast brings these down to a heap of the height `damage_area`
		# draws them at; nothing else in the field comes down at all
		for oid in obs_ids:
			if oid >= 0:
				Obstacles.set_breakable(oid, BLOCK_HEAP)
		var centre := Vector3.ZERO
		var rad := 0.0
		for x in xforms:
			centre += (x as Transform3D).origin
		centre /= float(xforms.size())
		for x in xforms:
			rad = maxf(rad, centre.distance_to((x as Transform3D).origin))
		_breakable.append({"mmi": mmi, "xforms": xforms.duplicate(),
			"dead": PackedByteArray(), "centre": centre, "radius": rad, "ids": obs_ids})
		var d: PackedByteArray = _breakable[_breakable.size() - 1]["dead"]
		d.resize(xforms.size())
		_breakable[_breakable.size() - 1]["dead"] = d

## Flatten anything inside the blast. Returns how many structures came down.
## How many breakable structures are still standing inside a radius.
func count_standing(pos_in: Vector3, radius: float) -> int:
	# What is standing is recorded where it was built: see `_laid`.
	var pos: Vector3 = Sim.world_to_boot(pos_in)
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

## What is left of a town block brought down, as a share of its height: the
## squash below, and the heap `Obstacles` leaves in the field to match it.
const BLOCK_HEAP := 0.14

func damage_area(pos_in: Vector3, radius: float) -> int:
	# the benches, kiosks and planters in it go over as well, rather than
	# standing whole with nothing left in them to stop a round
	knock(pos_in, radius, Vector3.ZERO)
	# A building you can no longer see is a building you can no longer hit.
	# The field is in the chart there is now; what was built is recorded where
	# it was built.
	Obstacles.kill_near(pos_in, radius)
	return _fell(pos_in, radius, false)

## Buildings coming down, soonest first: [drawn transform, size, obstacle id,
## multimesh, instance, its hidden transform, when (msec)].
var _heaps_due: Array = []
## How long a frame may spend on them, and how fast the front goes out.
const HEAP_BUDGET_USEC := 3000
const SHOCK_SPEED := 500.0

func _process(_delta: float) -> void:
	if _heaps_due.is_empty():
		return
	var t0: int = Time.get_ticks_usec()
	var now: int = Time.get_ticks_msec()
	while not _heaps_due.is_empty() and int(_heaps_due[0][6]) <= now \
			and Time.get_ticks_usec() - t0 < HEAP_BUDGET_USEC:
		var h: Array = _heaps_due.pop_front()
		var mmi: MultiMeshInstance3D = h[3]
		if is_instance_valid(mmi):
			_redraw(mmi, int(h[4]), h[5])
		var heap := Rubble.new()
		heap.setup(h[0], h[1], int(h[2]))
		add_child(heap)

## A blast too light to flatten anything by itself -- a mortar bomb -- wearing
## down whatever it lands on or beside: see `Obstacles.batter`. What has had
## enough comes down as a bigger blast's would. Returns how many did.
func batter(pos_in: Vector3, radius: float, blow: float) -> int:
	var down: PackedInt32Array = Obstacles.batter(pos_in, radius, blow)
	if down.is_empty():
		return 0
	knock(pos_in, radius, Vector3.ZERO)
	var reach := radius
	for id in down:
		reach = maxf(reach, radius + Obstacles.half_of(id).length())
	return _fell(pos_in, reach, true)

## Draw down every breakable whose box has come out of the field near `pos_in`.
## `boxed_only`: leave alone what has no box, which is otherwise brought down
## by distance alone.
func _fell(pos_in: Vector3, radius: float, boxed_only: bool) -> int:
	var hits := 0
	var now: int = Time.get_ticks_msec()
	var pos: Vector3 = Sim.world_to_boot(pos_in)
	for b in _breakable:
		var c: Vector3 = b["centre"]
		if Vector2(c.x - pos.x, c.z - pos.z).length() > float(b["radius"]) + radius:
			continue
		var xf: Array = b["xforms"]
		var dead: PackedByteArray = b["dead"]
		var oids: PackedInt32Array = b.get("ids", PackedInt32Array())
		for i in xf.size():
			if dead[i] != 0:
				continue
			var t: Transform3D = xf[i]
			# Down exactly when its box came out of the field, so what is drawn
			# and what is solid cannot disagree. Measured separately they did:
			# the field by distance across the ground, the drawing by distance
			# through the air, and a blast up in the air took the box out from
			# under a block still drawn standing whole.
			if i < oids.size() and oids[i] >= 0:
				if not Obstacles.gone(oids[i]):
					continue
			elif boxed_only or Vector2(t.origin.x - pos.x, t.origin.z - pos.z).length() > radius:
				continue
			dead[i] = 1
			hits += 1
			# Down to a heap of rubble where it stood. It was the building
			# itself squashed to a seventh of its height: a big flat box
			# raised off the ground, which is not what a block comes down as,
			# and it stood there for the rest of the session.
			var mmi: MultiMeshInstance3D = b["mmi"]
			var drawn: Transform3D = mmi.global_transform * mmi.multimesh.get_instance_transform(i)
			var size: Vector3 = mmi.multimesh.mesh.get_aabb().size * drawn.basis.get_scale()
			# Brought down when the shock front gets there, nearest first, and a
			# few a frame (`_process`): a strategic strike levelled the whole
			# town in one frame, and building every heap's mesh there and then
			# was more than half a second. Its solid box is already in the field.
			var far: float = Vector2(t.origin.x - pos.x, t.origin.z - pos.z).length()
			_heaps_due.append([drawn, size, oids[i] if i < oids.size() else -1, mmi, i,
				Transform3D(t.basis.scaled(Vector3.ONE * 0.001), t.origin - Vector3(0, 60.0, 0)),
				now + int(far / SHOCK_SPEED * 1000.0)])
		b["dead"] = dead
	if hits > 0:
		_heaps_due.sort_custom(func(a: Array, c2: Array) -> bool: return int(a[6]) < int(c2[6]))
	return hits

## Where every building in one town goes.
##
## Ten towns of these cost four and a half seconds -- every candidate site asks
## the height field, the road distance field and the buildable test -- and none
## of it touches the scene tree, so it goes to the worker pool a town at a time
## and then straight into the bake. Each town carries its own generator seeded
## from its index, because one shared sequence read by ten threads is neither
## deterministic nor safe.
func _town_plan(idx: int) -> Array:
	var t: Dictionary = sites[idx]
	var centre: Vector2 = t["c"]
	var radius: float = float(t["r"])
	var density: float = float(t["density"])
	var tallest: float = float(t["tallest"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4111 + idx * 6907
	var buckets := [[], [], []]
	var block := 128.0
	# buildings, packed into the blocks with a setback from the kerb
	var step := 30.0
	var n := int(radius / step)
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var px := centre.x + gx * step + rng.randf_range(-1.5, 1.5)
			var pz := centre.y + gz * step + rng.randf_range(-1.5, 1.5)
			var d := Vector2(px - centre.x, pz - centre.y).length() / radius
			if d > 1.0 or rng.randf() > density * (1.3 - d * 0.8):
				continue
			# keep clear of the kerb
			var fx := absf(fmod(absf(px - centre.x) + block * 0.5, block) - block * 0.5)
			var fz := absf(fmod(absf(pz - centre.y) + block * 0.5, block) - block * 0.5)
			if fx < 15.0 or fz < 15.0:
				continue
			var core: float = clampf(1.0 - d * 1.35, 0.0, 1.0)
			var h: float = lerpf(7.0, tallest, pow(core, 1.7) * rng.randf_range(0.35, 1.0))
			var w: float = rng.randf_range(17.0, 24.0) * (1.0 + core * 0.3)
			var dep: float = rng.randf_range(17.0, 24.0) * (1.0 + core * 0.3)
			# Sized first, then sited: the clearance a building needs from a
			# road depends on how big the building is, and half of a wide one
			# is most of the carriageway.
			if not Sim.buildable(px, pz, 0.90, 6.0, maxf(w, dep) * 0.5):
				continue
			var xf := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.015, 0.015)).scaled(
				Vector3(w, h, dep)), Vector3(px, Sim.height_at(px, pz) - 0.5, pz))
			buckets[rng.randi() % 3].append(xf)
	return buckets

var _town_out: Array = []

func _town_slice(i: int) -> void:
	_town_out[i] = _town_plan(i)

## Every town's buildings, planned on the pool or read back from the bake.
func _plan_all_towns() -> Array:
	var cached: Variant = WorldBake.get_baked("town_plans")
	if cached is Array and (cached as Array).size() == sites.size():
		return cached
	_town_out = []
	_town_out.resize(sites.size())
	var gid := WorkerThreadPool.add_group_task(_town_slice, sites.size(), -1, true,
		"town layout")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	var out := _town_out
	_town_out = []
	WorldBake.put("town_plans", out)
	return out

## Turn one town's plan into meshes. Main thread: it hangs things in the tree.
func _town_build(buckets: Array) -> void:
	var kinds := [
		SceneryMeshes.block_mesh(1.0, 1.0, 1.0, Color(0.26, 0.25, 0.23), Color(0.70, 0.67, 0.61)),
		SceneryMeshes.block_mesh(1.0, 1.0, 1.0, Color(0.22, 0.23, 0.25), Color(0.58, 0.59, 0.60)),
		SceneryMeshes.block_mesh(1.0, 1.0, 1.0, Color(0.29, 0.24, 0.21), Color(0.64, 0.58, 0.51)),
	]
	for i in 3:
		var lot: Array = buckets[i]
		# the walls' footprint: the roof slab overhangs them
		_scatter(kinds[i], lot, "Town%d" % i, true,
			AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0)))
		if not lot.is_empty():
			_breakable[_breakable.size() - 1]["town_kind"] = i
		town_xforms.append_array(lot)
		_stats["buildings"] = int(_stats.get("buildings", 0)) + lot.size()
		_foundations(lot)

## A concrete foundation under every town block that the ground falls away
## from. A block is set down by the ground at its middle; on a slope, or beside
## the bank of a bridge ramp, one side of a twenty metre footprint then stood
## clear of the ground with daylight under it. The foundation fills from the
## lowest ground under the footprint up to a hand's breadth above the block's
## own base, so the low side reads as a plinth and the high side buries it.
const FOUNDATION_LIP := 0.25
static var _found_mesh: ArrayMesh = null

func _foundations(lot: Array) -> void:
	if _found_mesh == null:
		var st := MeshKit.begin()
		MeshKit.box(st, Vector3(1.0, 1.0, 1.0), Vector3(0.0, 0.5, 0.0))
		_found_mesh = MeshKit.finish(st, MeshKit.panelled(Color(0.47, 0.46, 0.43), 0.95, 0.0, 1.2))
	var out: Array = []
	for x in lot:
		var xf: Transform3D = x
		var sx: float = xf.basis.x.length() * 0.5
		var sz: float = xf.basis.z.length() * 0.5
		var bx: Vector3 = xf.basis.x.normalized()
		var bz: Vector3 = xf.basis.z.normalized()
		var base: float = xf.origin.y
		var low := INF
		for fx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for fz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				var q: Vector3 = xf.origin + bx * sx * fx + bz * sz * fz
				low = minf(low, Sim.height_at(q.x, q.z))
		# the block's own walls go half a metre into the ground at its middle;
		# only where the ground is lower than that is there anything to fill
		if low > base - 0.05:
			continue
		var top: float = base + FOUNDATION_LIP
		var bottom: float = low - 0.4
		out.append(Transform3D(Basis(bx * sx * 2.06, Vector3.UP * (top - bottom), bz * sz * 2.06),
			Vector3(xf.origin.x, bottom, xf.origin.z)))
	if out.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Foundations"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _found_mesh
	mm.instance_count = out.size()
	for i in out.size():
		mm.set_instance_transform(i, out[i])
	mmi.multimesh = mm
	add_child(mmi)
	_stats["foundations"] = int(_stats.get("foundations", 0)) + out.size()

## What the three kinds of town block are faced in, for anything built to
## match one: see `_town_build`.
const TOWN_WALLS := [Color(0.70, 0.67, 0.61), Color(0.58, 0.59, 0.60), Color(0.64, 0.58, 0.51)]

## The town block standing at `at`, as [batch, index in it], or nothing.
func _block_at(at_in: Vector3) -> Array:
	# Asked with a point in the chart there is now -- the obstacle field's, which
	# is where the ground floors are cut from -- of blocks recorded where they
	# were built.
	var at: Vector3 = Sim.world_to_boot(at_in)
	for b in _breakable:
		if not b.has("town_kind"):
			continue
		if Vector2(at.x - b["centre"].x, at.z - b["centre"].z).length() > float(b["radius"]) + 2.0:
			continue
		var xf: Array = b["xforms"]
		var dead: PackedByteArray = b["dead"]
		for i in xf.size():
			var o: Vector3 = (xf[i] as Transform3D).origin
			if dead[i] == 0 and absf(o.x - at.x) < 0.3 and absf(o.z - at.z) < 0.3:
				return [b, i]
	return []

## Lift the bottom `dy` of the town block at `at` off the ground, roof staying
## where it is, so that a ground floor somebody can walk into can be built
## underneath it. Returns which kind of block it is, or -1 if there is none.
## Only what is drawn moves: the record of where the building stands does not,
## so a bomb still brings it down onto its own footprint.
func raise_block(at: Vector3, dy: float) -> int:
	var found := _block_at(at)
	if found.is_empty():
		return -1
	var b: Dictionary = found[0]
	var t: Transform3D = (b["xforms"] as Array)[found[1]]
	var h: float = t.basis.y.length()
	if h - dy < 1.0:
		return -1
	var cut := Basis(t.basis.x, t.basis.y * ((h - dy) / h), t.basis.z)
	_redraw(b["mmi"], found[1], Transform3D(cut, t.origin + Vector3(0, dy, 0)))
	return int(b["town_kind"])

## ...and stand it back on the ground.
func lower_block(at: Vector3) -> void:
	var found := _block_at(at)
	if found.is_empty():
		return
	var b: Dictionary = found[0]
	_redraw(b["mmi"], found[1], (b["xforms"] as Array)[found[1]])

## True when a point falls inside a town footprint, so nothing tall gets planted
## on top of the buildings.
func _inside_town(p: Vector2) -> bool:
	for t in sites:
		if p.distance_to(t["c"] as Vector2) < float(t["r"]) * 1.15:
			return true
	return false

# ---------------------------------------------------------------- military
func _military(centre: Vector3) -> void:
	var hangar := SceneryMeshes.hangar_mesh()
	var revet := SceneryMeshes.revetment_mesh()
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
		if not Sim.buildable(px, pz, 0.93, 6.0) \
				or Sim.height_at(px, pz) - Sim.sea_at(px, pz) > 295.0:
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
## How much of a biome's ground carries something, before clumping.
##
## Thinned by about half. Every candidate that passed was planted, which put an
## even carpet of trees across whole biomes -- and country does not look like
## that from the air. What reads as woodland is a *pattern*: thickets, glades
## and edges. The numbers below set how much there is; `SCAT_CLUMP` sets where.
const SCAT_DENSITY := {
	"forest": 0.62, "grass": 0.34, "steppe": 0.20, "marsh": 0.26,
	"rock": 0.15, "snow": 0.16, "sand": 0.07,
}
## Where it clumps. A slow field over the ground, so trees gather into stands
## with open country between them instead of being spread evenly over
## everything that will take them.
const SCAT_CLUMP_FREQ := 0.0013
const SCAT_CLUMP_LO := 0.34
const SCAT_CLUMP_HI := 0.74
## What the thickest part of a stand gets back, so clumping thins the open
## ground rather than the whole world.
const SCAT_CLUMP_GAIN := 1.9
const SCAT_SPECIES := {
	"forest": ["tree", "tree", "tree", "pine", "bush"],
	"grass": ["tree", "bush", "bush", "rock"],
	"steppe": ["bush", "bush", "rock"],
	"marsh": ["bush", "tree"],
	"rock": ["rock", "rock", "pine"],
	"snow": ["pine", "rock"],
	"sand": ["rock", "bush"],
}

## Trees, rocks and bushes over the whole map.
##
## A hundred and fifty thousand candidate points, each asking the height field
## about ten times over -- once for the water test, four for the drawn surface,
## four for the slope, and the biome on top. That was four and a quarter seconds
## of the start on its own, and none of it touches the scene tree, so it goes to
## the worker pool in slices.
##
## Each slice carries its own generator seeded from its index rather than
## drawing from the shared one, because a single sequence read by several
## threads is neither deterministic nor safe. The layout is different from the
## one the serial version produced; it is the same layout every run.
var _scat_pts := PackedVector2Array()
var _scat_h := PackedFloat32Array()
var _scat_slope := PackedFloat32Array()
var _scat_surf := PackedFloat32Array()

## The clump field. Built once and read from the workers, which is safe because
## nothing writes it after setup.
static var _scat_clump := FastNoiseLite.new()

const SCAT_TASKS := 24
## How tall each kind of scatter stands and how far its crown spreads, at scale
## one: the meshes below.
const SCAT_TALL := {"tree": 8.3, "pine": 12.0, "rock": 3.0, "bush": 2.2}
const SCAT_CROWN := {"tree": 3.6, "pine": 2.7, "rock": 2.6, "bush": 1.5}

## Per slice, so the total is a round 150,000 without an integer division that
## quietly loses the remainder.
const SCAT_PER_TASK := 6250

var _scat_out: Array = []

func _scatter_nature() -> void:
	var meshes := {"tree": SceneryMeshes.tree_mesh(), "pine": SceneryMeshes.pine_mesh(), "rock": SceneryMeshes.rock_mesh(),
		"bush": SceneryMeshes.bush_mesh()}
	var cells := {}
	var cached: Variant = WorldBake.get_baked("scatter")
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		cells = cached
	else:
		# Every candidate position first, then the field for the whole lot in
		# two calls.
		#
		# Asked for a point at a time this was five crossings of the extension
		# boundary per tree -- the height, and four more for the slope -- from
		# twenty-four workers at once, and they queue there: measured, a call
		# that costs a quarter of a microsecond on its own cost six in the
		# crowd, and scattering the world took eighty-six seconds. Batched, the
		# workers touch nothing outside GDScript and the arithmetic runs across
		# the cores inside the extension instead.
		_scat_pts = PackedVector2Array()
		_scat_pts.resize(SCAT_TASKS * SCAT_PER_TASK)
		for t in SCAT_TASKS:
			var prng := RandomNumberGenerator.new()
			prng.seed = 20260821 + t * 7919
			for i in SCAT_PER_TASK:
				_scat_pts[t * SCAT_PER_TASK + i] = Vector2(
					prng.randf_range(-SCAT_HALF * SCAT_CELL, SCAT_HALF * SCAT_CELL),
					prng.randf_range(-SCAT_HALF * SCAT_CELL * 1.6,
						SCAT_HALF * SCAT_CELL * 1.6))
		_scat_h = Sim.native.grounds_at(_scat_pts, Sim.G_ALL)
		_scat_slope = Sim.native.slopes_at(_scat_pts)
		# and the surface as the mesh draws it, which is four more heights
		# apiece and was the last thing the workers were crossing the boundary
		# for
		_scat_surf = Sim.native.surfaces_at(_scat_pts, Terrain.BASE_CELL)
		# read by every worker, so built here first
		Sim.roads.index_bridges()
		_scat_out = []
		_scat_out.resize(SCAT_TASKS)
		var gid := WorkerThreadPool.add_group_task(_scat_slice, SCAT_TASKS, -1, true,
			"nature scatter")
		WorkerThreadPool.wait_for_group_task_completion(gid)
		for t in SCAT_TASKS:
			var got: Array = _scat_out[t]
			for e in got:
				var key: String = e[0]
				if not cells.has(key):
					cells[key] = []
				cells[key].append(e[1])
		_scat_out = []
		WorldBake.put("scatter", cells)
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

## Runs on a worker. Reads the height, road and biome fields, which are all
## built by now and none of which it writes to.
func _scat_slice(t: int) -> void:
	# Positions and ground come in already worked out; this RNG only dresses
	# what survives, so its stream no longer has to line up with the one that
	# placed the candidates.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210041 + t * 7919
	var base: int = t * SCAT_PER_TASK
	var out: Array = []
	for i in SCAT_PER_TASK:
		var p: Vector2 = _scat_pts[base + i]
		var x := p.x
		var z := p.y
		if absf(x) < 330.0 and absf(z) < 2150.0:
			continue                                        # keep the field clear
		var y: float = _scat_h[base + i]
		# Still the flat frame here: this is the raw field, so it is the flat
		# sea it gets compared against. The drop goes on below, once the height
		# we actually stand the thing on has been picked.
		if y < Sim.WATER_LEVEL + 2.0 or y > 2400.0:
			continue
		# On the surface as it is drawn, not as the field computes it. The two
		# part company by more than the height of a tree as soon as the cells
		# get coarse, and a tree standing on the analytic height then hangs in
		# the air above the triangles -- which is what you see looking up at the
		# underside of the ground.
		# In the world frame already: `surfaces_at` answers what `Sim.height_at`
		# answers, so the drop is under the interpolation rather than taken off
		# after it.
		y = _scat_surf[base + i]
		if absf(x) < 6000.0 and Sim.roads.road_distance(x, z) < 15.0:
			continue
		var slope: float = _scat_slope[base + i]
		if slope < 0.55:
			continue                                        # nothing clings to a cliff
		var biome := Sim.biomes.kind(x, z, y, slope)
		# Thickets and glades, not a carpet. The clump field is slow -- about
		# 800 m across -- so a stand is the size of a wood rather than the size
		# of a bush, and the open ground between stands is genuinely open.
		var clump: float = (_scat_clump.get_noise_2d(x, z) + 1.0) * 0.5
		var dens: float = float(SCAT_DENSITY.get(biome, 0.3)) \
			* smoothstep(SCAT_CLUMP_LO, SCAT_CLUMP_HI, clump) * SCAT_CLUMP_GAIN
		if rng.randf() > dens:
			continue
		var options: Array = SCAT_SPECIES.get(biome, ["bush"])
		var kind: String = options[rng.randi() % options.size()]
		var sc := rng.randf_range(0.7, 1.7)
		var sy: float = sc * rng.randf_range(0.8, 1.35)
		# Clear of the road bridges: off the ramps, and under a deck only
		# where the deck is well over the top of it -- a valley viaduct, not
		# the low end of a town flyover.
		if Sim.roads.bridge_headroom(x, z, float(SCAT_CROWN.get(kind, 2.0)) * sc, y) \
				< float(SCAT_TALL.get(kind, 3.0)) * sy + 1.0:
			continue
		# and not inside anything built: a barn, a hangar, a fuel tank
		if Obstacles.blocks(Vector3(x, y + 0.5, z), 0.4) >= 0:
			continue
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(sc, sy, sc)), Vector3(x, y - 0.4, z))
		out.append(["%s_%d_%d" % [kind, int(floor(x / SCAT_CELL)),
			int(floor(z / SCAT_CELL))], xf])
	_scat_out[t] = out

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
	var truck := SceneryMeshes.truck_mesh()
	var wall := SceneryMeshes.wall_mesh()
	var tx := []
	var wx := []
	# Three rows of three, north of the tower. They were 22 m apart from
	# z = -560, and the third row came down at -604 -- inside the control
	# tower, which stands at (150, -600) and is seventeen metres across at the
	# cab: one lorry was parked in the ground floor of it.
	for i in 9:
		var px := 120.0 + float(i % 3) * 26.0
		var pz := -548.0 - floorf(float(i) / 3.0) * 18.0
		tx.append(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(px, 0, pz)))
	for i in 12:
		wx.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(60.0 + i * 16.0, 0, -690.0)))
	_scatter(truck, tx, "Vehicles")
	_scatter(wall, wx, "BlastWalls")

# ---------------------------------------------------------------- roads
## Trunk roads and town streets as a single hugging surface. Sampled tightly so
## it follows the ground instead of floating over it, with a kerb strip either
## side to hide the seam.
## Carriageways and kerbs for every road and street on the map.
##
## Four height samples every eleven metres of every leg, and with sixteen towns
## on the map that is over three seconds. None of it touches the scene tree, so
## a leg at a time goes to the worker pool and only the two meshes are made
## here.
func _build_roads() -> void:
	# The roads are painted into the ground, not laid over it.
	#
	# They were strips of geometry, bucketed into meshes: a carriageway and a
	# kerb either side, hugging the drawn ground. Where two met, the two strips
	# fought for the same pixels and one's kerb ran across the other; wherever
	# the terrain bent between two of its samples it came up through them. The
	# ground's own material paints them now (`Terrain.follow_roads`): a
	# junction is one surface, the kerb stops at every mouth, and nothing can
	# come through a road that is the ground. This hands the network over --
	# the trunk legs and the streets as drawn, the approach stretches marked --
	# and the extension works out which parts of each street are drawn.
	var legs := PackedFloat32Array(Sim.roads.road_draw)
	street_draw = _streets_clear_of_bridges()
	for r in street_draw:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		# 3: an approach climbing to a road, laid on its made ground
		legs.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y,
			STREET_HALF, 0.0, 0.0, float(r[2]) if r.size() > 2 else 0.0]))
	_road_legs_laid = legs
	var t_rib := Time.get_ticks_msec()
	_stats["road_pieces"] = Sim.native.publish_road_pieces(legs)
	_stats["ms_road_pieces"] = Time.get_ticks_msec() - t_rib
	var terrain_node: Node = get_parent().get("terrain") if get_parent() != null else null
	if terrain_node != null and terrain_node.has_method("roads_changed"):
		terrain_node.roads_changed()

## The streets as they are drawn: `_streets`, less wherever one runs into a
## road bridge -- across the ramp up to it, or underneath the deck where there
## is not the headroom for a lorry. With the room, a street goes under.
var street_draw: Array = []
## The headroom a street needs under a deck, girder to ground.
const STREET_HEADROOM := 5.0
## Half a street, kerbs and all: `ribbon` draws the kerb strip out to 1.55 of
## its five metre half width.
const STREET_REACH := 7.75

func _streets_clear_of_bridges() -> Array:
	var out: Array = []
	const STEP := 3.0
	var cut_back := 0
	for si in _streets.size():
		var seg: Array = _streets[si]
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var run := a.distance_to(b)
		if run < 1.0:
			continue
		var spans: Array = _approach_spans.get(si, [])
		# Where it cannot go: under a deck too low to pass beneath, or over a
		# bank -- the side of a ramp, or a road raised on one it does not
		# climb to meet -- and a margin round it. As [t0, t1].
		var blocked: Array = []
		if not Sim.roads.road_bridges.is_empty() and Sim.roads.near_bridges(
				Vector2(minf(a.x, b.x), minf(a.y, b.y)),
				Vector2(maxf(a.x, b.x), maxf(a.y, b.y)), STREET_REACH):
			var n: int = maxi(int(ceil(run / STEP)), 1)
			var from := -1.0
			for k in n + 1:
				var t := float(k) / float(n)
				var q: Vector2 = a.lerp(b, t)
				var ok: bool = Sim.roads.bridge_headroom(q.x, q.y, STREET_REACH, NAN, false) \
					>= STREET_HEADROOM
				if not ok and from < 0.0:
					from = t
				elif ok and from >= 0.0:
					blocked.append([from, t])
					from = -1.0
			if from >= 0.0:
				blocked.append([from, 1.0])
		var clear: PackedFloat32Array = Sim.native.street_clear(a, b, STREET_HALF)
		var c0 := 0.0
		for k2 in range(0, clear.size() - 1, 2):
			if clear[k2] > c0:
				_block_outside(blocked, c0, clear[k2], spans)
			c0 = clear[k2 + 1]
		if c0 < 1.0:
			_block_outside(blocked, c0, 1.0, spans)
		var keep: Array = [[0.0, 1.0]]
		if not blocked.is_empty():
			# Cut back to the junctions either side. Stopped where it was
			# blocked, a street ran up to the side of a ramp, or to a deck too
			# low to pass under, and stopped there -- two dead ends facing each
			# other across a bridge. A street that cannot get through ends at
			# the last street it meets on the way, which makes that a T.
			var joins := _street_joins(si, a, b)
			var cuts: Array = []
			for bl in blocked:
				var lo := 0.0
				var hi := 1.0
				for t2 in joins:
					if t2 <= bl[0] and t2 > lo:
						lo = t2
					if t2 >= bl[1] and t2 < hi:
						hi = t2
				cuts.append([lo, hi])
			keep = _subtract_spans([[0.0, 1.0]], cuts)
			cut_back += 1
		# and the stretches that climb to a road, drawn as approaches
		for kp in keep:
			var marks: Array = [kp[0], kp[1]]
			for sp in spans:
				for e in sp:
					if e > kp[0] and e < kp[1]:
						marks.append(e)
			marks.sort()
			for c in marks.size() - 1:
				var t0: float = marks[c]
				var t1: float = marks[c + 1]
				if (t1 - t0) * run < 1.0:
					continue
				var mid: float = (t0 + t1) * 0.5
				var climbs := false
				for sp in spans:
					if mid >= sp[0] and mid <= sp[1]:
						climbs = true
				# 4: laid clear of every bank here already; 3: an approach
				out.append([a.lerp(b, t0), b if t1 >= 1.0 else a.lerp(b, t1),
					3.0 if climbs else 4.0])
	_stats["streets_cut"] = cut_back
	return out

## A stretch of street that the banks block, less any part of it that is the
## street's own approach climbing to the road (which is meant to be raised).
static func _block_outside(blocked: Array, t0: float, t1: float, spans: Array) -> void:
	for piece in _subtract_spans([[t0, t1]], spans):
		blocked.append(piece)

## `spans` less `cuts`, both lists of [t0, t1].
static func _subtract_spans(spans: Array, cuts: Array) -> Array:
	var out: Array = spans.duplicate(true)
	for c in cuts:
		var next: Array = []
		for sp in out:
			if c[1] <= sp[0] or c[0] >= sp[1]:
				next.append(sp)
				continue
			if c[0] > sp[0]:
				next.append([sp[0], c[0]])
			if c[1] < sp[1]:
				next.append([c[1], sp[1]])
		out = next
	return out

## Where along street `si` (0 to 1) it meets another street or a road of the
## network.
func _street_joins(si: int, a: Vector2, b: Vector2) -> Array:
	var ts: Array = []
	var run := a.distance_to(b)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	for oi in _streets.size():
		if oi == si:
			continue
		var c: Vector2 = _streets[oi][0]
		var d: Vector2 = _streets[oi][1]
		if maxf(c.x, d.x) < lo.x or minf(c.x, d.x) > hi.x \
				or maxf(c.y, d.y) < lo.y or minf(c.y, d.y) > hi.y:
			continue
		var x: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
		if x != null:
			ts.append(a.distance_to(x) / run)
	for j in junctions:
		if int(j["street"]) == si:
			ts.append(float(j["t"]))
	return ts

## A road surface that wins against the ground it lies on without being lifted
## off it. Each vertex is pulled a fraction of its own distance toward the eye
## before projection: the picture is unchanged, only the depth moves, and by an
## amount that grows with range exactly as the depth buffer's coarseness does --
## a few millimetres under your boots, a few decimetres a kilometre off. It used
## to be done by standing the ribbon sixteen centimetres up, and every soldier
## on a street was in it to the ankles.
static var _road_sh: Shader = null
## The markings, and the surface's own grain, are drawn only as near as they
## can be seen: the lines fade out between 180 and 320 m, the grain by 120 m,
## so a road across the country is the plain dark ribbon it always was and the
## one under the wheels has a centre line, its edges and some texture. `marked`
## is the carriageway; a kerb has the grain and no lines. The lines are found
## from UV: across the carriageway, -1 at one edge to 1 at the other, and the
## length along it in metres (`ribbon` in raster.rs) -- so a street and a trunk
## road get the same lines in proportion.
static func _road_shader(col: Color, rough: float, marked := false) -> ShaderMaterial:
	if _road_sh == null:
		_road_sh = Shader.new()
		_road_sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 albedo : source_color;
uniform float roughness = 0.94;
uniform bool marked = false;
uniform vec3 paint : source_color = vec3(0.86, 0.85, 0.80);
varying vec3 wpos;
varying float dist;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Toward the eye by a share of the distance. The terrain is drawn coarser
	// the further off it is, and its error grows with the distance: held to a
	// fixed twelfth of a percent the road lost to it nearly everywhere -- it
	// was drawn, under the grass, and the roads looked missing up to every
	// bridge and across every town.
	float d = length(v.xyz);
	dist = d;
	v.xyz -= v.xyz / max(d, 0.001) * clamp(d * 0.005, 0.10, 3.0);
	POSITION = PROJECTION_MATRIX * v;
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	vec3 col = albedo;
	// grain and patching, close to
	float near = 1.0 - smoothstep(40.0, 120.0, dist);
	if (near > 0.0) {
		vec2 q = mod(wpos.xz, 4096.0);
		float g = vnoise(q * 3.0) * 0.55 + vnoise(q * 0.3) * 0.45;
		col *= mix(1.0, 0.82 + 0.36 * g, near);
	}
	if (marked) {
		float fade = 1.0 - smoothstep(180.0, 320.0, dist);
		if (fade > 0.0) {
			float a = abs(UV.x);
			float fu = max(fwidth(UV.x), 1e-4);
			// a dashed centre line, six on and six off
			float centre = 1.0 - smoothstep(0.02 - fu, 0.02 + fu, a);
			float ph = fract(UV.y / 12.0);
			float fv = max(fwidth(UV.y / 12.0), 1e-4);
			float dash = smoothstep(0.0, fv, ph) * (1.0 - smoothstep(0.5 - fv, 0.5 + fv, ph));
			// and a solid line just in from each edge
			float edge = smoothstep(0.93 - fu, 0.93 + fu, a)
				* (1.0 - smoothstep(0.965 - fu, 0.965 + fu, a));
			// worn: a little of the road through the paint
			float wear = 0.8 + 0.2 * vnoise(mod(wpos.xz, 4096.0) * 1.7);
			col = mix(col, paint, max(centre * dash, edge) * fade * wear);
		}
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _road_sh
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("marked", marked)
	return m

## Viaducts and tunnel portals.
##
## The alignment crosses low ground on a deck and high ground in a bore, and
## neither is laid on the terrain -- which is the point, it is what stops the
## road gouging a trench or climbing a mountain. But with nothing drawn for
## them, a road simply stopped at one side of a valley and started again at the
## other, and disappeared into a hillside with no way in.
const PIER_STEP := 90.0
const DECK_HALF := 8.5
## The parapet along each edge of a deck: how tall over the running surface,
## and how thick.
const PARAPET_TALL := 1.0
const PARAPET_THICK := 0.35
## How far under the deck a walled ramp's abutment block reaches: `SHELF` in
## world.rs, which is the ground it stands for.
const ABUT_LEN := 4.5
## Where every pier stands: x and z, and half its width in y.
var pier_spots: Array = []

## The road along a deck: the same carriageway, material and markings as the
## ribbons on the ground (see `_road_shader`), a few centimetres over the deck
## so the deck's own grey is the margin either side of it. `a` to `b` is the
## centreline, with the heights at each end on the -1 and +1 sides.
var _deck_v := PackedVector3Array()
var _deck_uv := PackedVector2Array()

func _deck_road(a: Vector2, b: Vector2, ya_m: float, ya_p: float,
		yb_m: float, yb_p: float, b_edge := PackedFloat32Array()) -> void:
	var run := a.distance_to(b)
	if run < 0.1:
		return
	var dir := (b - a) / run
	var n := Vector2(-dir.y, dir.x)
	var va: float = fposmod(a.dot(dir), 1200.0)
	var vb: float = va + run
	var offs := [-1.0, -0.5, 0.0, 0.5, 1.0]
	for k in offs.size() - 1:
		var o0: float = offs[k]
		var o1: float = offs[k + 1]
		var corner := func(at: Vector2, o: float, ym: float, yp: float) -> Vector3:
			var q: Vector2 = at + n * Sim.roads.ROAD_HALF * o
			return Vector3(q.x, lerpf(ym, yp, (o + 1.0) * 0.5) + 0.03, q.y)
		var p00: Vector3 = corner.call(a, o0, ya_m, ya_p)
		var p01: Vector3 = corner.call(a, o1, ya_m, ya_p)
		var p11: Vector3 = corner.call(b, o1, yb_m, yb_p)
		var p10: Vector3 = corner.call(b, o0, yb_m, yb_p)
		# (a lap's outer edge, as `_deck_lap` laid it: the road's offset on
		# the deck's width)
		if b_edge.size() == LAP_N:
			p11.y = _lap_y(b_edge, o1 * Sim.roads.ROAD_HALF / DECK_HALF) + 0.03
			p10.y = _lap_y(b_edge, o0 * Sim.roads.ROAD_HALF / DECK_HALF) + 0.03
		_deck_v.append_array(PackedVector3Array([p00, p01, p11, p00, p11, p10]))
		_deck_uv.append_array(PackedVector2Array([Vector2(o0, va), Vector2(o1, va),
			Vector2(o1, vb), Vector2(o0, va), Vector2(o1, vb), Vector2(o0, vb)]))

## The end panel of a deck, lapped over the ramp from the abutment's line:
## level with the deck at the line and down on the road at its outer edge. Held
## level, as it was, it stood a few inches proud of the ramp the whole width of
## the road -- the ground meets the deck at the line only as nearly as a
## fifteen metre mesh can, and the road is laid on that mesh. So the panel
## meets the road where the road is: at each corner, the drawn ground (what
## `Terrain.drawn_ground` and the road ribbon are both laid on) and the
## ribbon's own couple of centimetres. `out` points away from the deck.
func _deck_lap(st: SurfaceTool, at: Vector2, out: Vector2, top: float) -> void:
	var nrm := Vector2(-out.y, out.x)
	var tip: Vector2 = at + out * Sim.roads.BRIDGE_LAP
	# The outer edge at LAP_N points across, from the +nrm side to the other,
	# each on the road it meets. Taken at the two corners alone and drawn
	# straight between them, the edge stood up to forty centimetres off a road
	# that bends across its width where the ground mesh's triangles meet.
	var pts := PackedVector2Array()
	for k in LAP_N:
		pts.append(tip + nrm * DECK_HALF * _lap_side(k))
	var got: PackedFloat32Array = Sim.native.surfaces_at(pts, Terrain.BASE_CELL)
	var hs := PackedFloat32Array()
	for k in LAP_N:
		var g: float = got[k] + 0.03 if got.size() > k else top
		# never more than a step off the deck: it is a lap, not a ramp
		hs.append(clampf(g, top - Sim.roads.BRIDGE_STEP, top + Sim.roads.BRIDGE_STEP))
	for k in LAP_N - 1:
		var sa: float = _lap_side(k)
		var sb: float = _lap_side(k + 1)
		var p0 := Vector3(at.x + nrm.x * DECK_HALF * sa, top, at.y + nrm.y * DECK_HALF * sa)
		var p1 := Vector3(at.x + nrm.x * DECK_HALF * sb, top, at.y + nrm.y * DECK_HALF * sb)
		var q0 := Vector3(pts[k].x, hs[k], pts[k].y)
		var q1 := Vector3(pts[k + 1].x, hs[k + 1], pts[k + 1].y)
		var up := (q0 - p0).cross(p1 - p0).normalized()
		if up.y < 0.0:
			up = -up
		# wound as the deck's own panels are
		MeshKit.quad_n(st, p0, p1, q1, q0, up)
	# and its two edges, down into the bank, so the side of the lap is not open
	var e_hi := Vector3(at.x + nrm.x * DECK_HALF, top, at.y + nrm.y * DECK_HALF)
	var e_lo := Vector3(at.x - nrm.x * DECK_HALF, top, at.y - nrm.y * DECK_HALF)
	var t_hi := Vector3(pts[0].x, hs[0], pts[0].y)
	var t_lo := Vector3(pts[LAP_N - 1].x, hs[LAP_N - 1], pts[LAP_N - 1].y)
	for e in [[e_hi, t_hi, nrm], [t_lo, e_lo, -nrm]]:
		var a3: Vector3 = e[0]
		var b3: Vector3 = e[1]
		var side3 := Vector3((e[2] as Vector2).x, 0.0, (e[2] as Vector2).y)
		MeshKit.quad_n(st, a3, b3, b3 - Vector3(0, 1.0, 0), a3 - Vector3(0, 1.0, 0), side3)
	# and the road over it, from the deck down onto the ramp, following the
	# same edge
	_deck_road(at, tip, top, top, 0.0, 0.0, hs)

## Points across a lap's outer edge, and where point `k` of them is: +1 on the
## +nrm side to -1 on the other.
const LAP_N := 9

static func _lap_side(k: int) -> float:
	return 1.0 - 2.0 * float(k) / float(LAP_N - 1)

## The height of a lap's outer edge at `side` (+1 to -1) across it.
static func _lap_y(hs: PackedFloat32Array, side: float) -> float:
	var f: float = clampf((1.0 - side) * 0.5 * float(LAP_N - 1), 0.0, float(LAP_N - 1))
	var k: int = mini(int(f), LAP_N - 2)
	return lerpf(hs[k], hs[k + 1], f - float(k))

func _build_structures() -> void:
	_deck_v = PackedVector3Array()
	_deck_uv = PackedVector2Array()
	var st := MeshKit.begin()
	var dark := MeshKit.begin()
	var decks := 0
	var piers := 0
	# Two roads welded onto one alignment are one road, and each of them came
	# back with the same span: drawn twice in the same place the deck fought
	# itself for every pixel.
	var drawn: Array = []
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2:
			continue
		var twin := false
		for d0 in drawn:
			var da: Vector2 = d0[0]
			var db: Vector2 = d0[1]
			if (da.distance_to(pts[0]) < 25.0 and db.distance_to(pts[pts.size() - 1]) < 25.0) \
					or (da.distance_to(pts[pts.size() - 1]) < 25.0 and db.distance_to(pts[0]) < 25.0):
				twin = true
				break
		if twin:
			continue
		drawn.append([pts[0], pts[pts.size() - 1]])
		decks += 1
		var since := 0.0
		var last := pts.size() - 2
		for i in range(pts.size() - 1):
			var a2: Vector2 = pts[i]
			var b2: Vector2 = pts[i + 1]
			var run := a2.distance_to(b2)
			if run < 0.5:
				continue
			var dir := (b2 - a2) / run
			var nrm := Vector2(-dir.y, dir.x)
			# The two end panels reach a couple of metres past the station, over
			# the end of the carriageway, so the join is a lap and not a seam --
			# drawn on their own, below.
			if i == 0:
				_deck_lap(st, a2, -dir, ys[i] - Sim.planet_drop(a2.x, a2.y))
			if i == last:
				_deck_lap(st, b2, dir, ys[i + 1] - Sim.planet_drop(b2.x, b2.y))
			# The surveyed profile is in the flat frame, like everything the
			# router produces. The piers under this deck reach down to
			# `height_at`, which is not -- so left flat the deck floated a
			# kilometre over the country at the far end of the network and
			# stood on kilometre-high legs.
			var ya: float = ys[i] - Sim.planet_drop(a2.x, a2.y)
			var yb: float = ys[i + 1] - Sim.planet_drop(b2.x, b2.y)
			# the running surface
			var p0 := Vector3(a2.x + nrm.x * DECK_HALF, ya, a2.y + nrm.y * DECK_HALF)
			var p1 := Vector3(a2.x - nrm.x * DECK_HALF, ya, a2.y - nrm.y * DECK_HALF)
			var p2 := Vector3(b2.x - nrm.x * DECK_HALF, yb, b2.y - nrm.y * DECK_HALF)
			var p3 := Vector3(b2.x + nrm.x * DECK_HALF, yb, b2.y + nrm.y * DECK_HALF)
			MeshKit.quad_n(st, p0, p1, p2, p3, Vector3.UP)
			_deck_road(a2, b2, ya, ya, yb, yb)
			# the box girder under it, so the deck has a thickness
			var u0 := p0 - Vector3(0, 1.9, 0)
			var u1 := p1 - Vector3(0, 1.9, 0)
			var u2 := p2 - Vector3(0, 1.9, 0)
			var u3 := p3 - Vector3(0, 1.9, 0)
			MeshKit.quad_n(st, u1, u0, u3, u2, Vector3.DOWN)
			MeshKit.quad_n(st, p0, p3, u3, u0, Vector3(nrm.x, 0, nrm.y))
			MeshKit.quad_n(st, p2, p1, u1, u2, Vector3(-nrm.x, 0, -nrm.y))
			# Parapets: a wall along each edge, faced on both sides and capped.
			# They were the cap alone -- a strip forty centimetres wide lying at
			# the parapet's height -- so from beside the bridge, or driving
			# along it, there was nothing there.
			for sx in [1.0, -1.0]:
				var side3 := Vector3(nrm.x * sx, 0.0, nrm.y * sx)
				var o0 := Vector3(a2.x + nrm.x * DECK_HALF * sx, ya, a2.y + nrm.y * DECK_HALF * sx)
				var o1 := Vector3(b2.x + nrm.x * DECK_HALF * sx, yb, b2.y + nrm.y * DECK_HALF * sx)
				var in0 := o0 - side3 * PARAPET_THICK
				var in1 := o1 - side3 * PARAPET_THICK
				var up := Vector3(0.0, PARAPET_TALL, 0.0)
				# outside, down over the edge of the girder too
				MeshKit.quad_n(st, o0 - Vector3(0, 0.3, 0), o1 - Vector3(0, 0.3, 0),
					o1 + up, o0 + up, side3)
				# inside, from the deck
				MeshKit.quad_n(st, in0, in1, in1 + up, in0 + up, -side3)
				# the cap
				MeshKit.quad_n(st, o0 + up, o1 + up, in1 + up, in0 + up, Vector3.UP)
				# and its ends, where a span starts or finishes
				if i == 0:
					MeshKit.quad_n(st, o0, in0, in0 + up, o0 + up, Vector3(-dir.x, 0.0, -dir.y))
				if i == last:
					MeshKit.quad_n(st, o1, in1, in1 + up, o1 + up, Vector3(dir.x, 0.0, dir.y))
			# An abutment under each end: the deck sits on a wall rather than
			# stopping in the air, whatever the embankment managed to reach.
			for endp in ([[a2, ya, pts[i], dir]] if i == 0 else []) \
					+ ([[b2, yb, pts[i + 1], -dir]] if i == last else []):
				var ep: Vector2 = endp[0]
				var ey: float = endp[1]
				var station: Vector2 = endp[2]
				var into: Vector2 = endp[3]
				# A walled ramp in a town ends in a block under the first few
				# metres of the deck, the ramp's full width: the ground there
				# is a shelf just under the deck (see `SHELF` in world.rs),
				# and drawn as nothing it was a slab of invisible ground.
				var probe: Vector2 = station + into * 2.0
				if Sim.height_at(probe.x, probe.y) - Sim.drawn_height_at(probe.x, probe.y) > 0.5:
					var top: float = ey - 0.3
					var foot := INF
					for k2 in 3:
						for sx2 in [-1.0, 0.0, 1.0]:
							var fq: Vector2 = station + into * (ABUT_LEN * float(k2) * 0.5) \
								+ Vector2(-into.y, into.x) * (Sim.roads.RAMP_HALF * sx2)
							foot = minf(foot, Sim.drawn_height_at(fq.x, fq.y))
					var deep: float = top - foot + 0.5
					var block := MeshKit.begin()
					MeshKit.box(block, Vector3(Sim.roads.RAMP_HALF * 2.0, deep, ABUT_LEN),
						Vector3(0.0, -deep * 0.5, ABUT_LEN * 0.5))
					var mi_block := MeshKit.mi(MeshKit.finish(block,
						MeshKit.mat(Color(0.58, 0.57, 0.55), 0.92, 0.0)), "Abutment")
					mi_block.position = Vector3(station.x, top, station.y)
					mi_block.rotation.y = atan2(into.x, into.y)
					add_child(mi_block)
					continue
				# Down to the ground as it is drawn, which under a ramp is not
				# the ramp's own top.
				var eg: float = Sim.drawn_height_at(ep.x, ep.y)
				var tall: float = ey - 1.9 - eg
				if tall > 0.5:
					var wall := MeshKit.begin()
					MeshKit.box(wall, Vector3(DECK_HALF * 2.0 + 1.0, tall + 3.0, 3.0),
						Vector3(0.0, -(tall + 3.0) * 0.5, 0.0))
					var mi_wall := MeshKit.mi(MeshKit.finish(wall,
						MeshKit.mat(Color(0.58, 0.57, 0.55), 0.92, 0.0)), "Abutment")
					mi_wall.position = Vector3(ep.x, ey - 1.9, ep.y)
					mi_wall.rotation.y = atan2(dir.x, dir.y)
					add_child(mi_wall)
			# and a pier every so often, down to whatever is underneath -- but
			# not into a road or a street passing under the deck: that pier
			# waits for the next station, and the span is a little longer.
			since += run
			if since >= PIER_STEP:
				var g: float = Sim.height_at(b2.x, b2.y)
				var clear: float = yb - 1.9 - g
				var pw0: float = clampf(4.4 + clear * 0.035, 4.4, 14.0)
				var in_road: bool = Sim.roads.segments_indexed > 0 \
					and Sim.roads.road_distance(b2.x, b2.y) < pw0 * 0.5 + STREET_REACH + 1.0
				if not in_road or since >= PIER_STEP * 2.2:
					since = 0.0
				if clear > 5.0 and not in_road:
					piers += 1
					# Thicker the taller it stands: a valley viaduct can be two
					# hundred metres off the floor, and at the width of a
					# flyover pier that reads as a matchstick.
					var pw: float = clampf(4.4 + clear * 0.035, 4.4, 14.0)
					MeshKit.box(st, Vector3(pw, clear, pw),
						Vector3(b2.x, g + clear * 0.5, b2.y))
					pier_spots.append(Vector3(b2.x, pw * 0.5, b2.y))
	var portals := 0
	for tn in Sim.roads.road_tunnels:
		var tp: PackedVector2Array = tn.get("pts", PackedVector2Array())
		var ty: PackedFloat32Array = tn.get("ys", PackedFloat32Array())
		if tp.size() < 2:
			continue
		for endi in [0, tp.size() - 1]:
			portals += 1
			var at: Vector2 = tp[endi]
			var toward: Vector2 = tp[1] if endi == 0 else tp[tp.size() - 2]
			var d2 := (at - toward).normalized()
			var y2: float = ty[endi] - Sim.planet_drop(at.x, at.y)
			# a headwall standing in the hillside, with the bore cut into it
			var face := at + d2 * 2.0
			var side := Vector2(-d2.y, d2.x)
			MeshKit.box(st, Vector3(3.0, 13.0, 2.5),
				Vector3(face.x + side.x * 9.5, y2 + 4.5, face.y + side.y * 9.5))
			MeshKit.box(st, Vector3(3.0, 13.0, 2.5),
				Vector3(face.x - side.x * 9.5, y2 + 4.5, face.y - side.y * 9.5))
			MeshKit.box(st, Vector3(22.0, 2.6, 2.5),
				Vector3(face.x, y2 + 10.4, face.y))
			# the mouth itself: a dark recess so it reads as an opening
			MeshKit.box(dark, Vector3(15.0, 8.6, 5.0),
				Vector3(at.x - d2.x * 3.0, y2 + 4.2, at.y - d2.y * 3.0))
	add_child(MeshKit.mi(MeshKit.finish(st,
		MeshKit.mat(Color(0.58, 0.57, 0.55), 0.92, 0.0)), "RoadStructures"))
	if not _deck_v.is_empty():
		# the painted ground's tarmac (`Terrain.GROUND_SHADER`), so the road on
		# the deck is the road it runs on from
		var dr := MeshKit.mi(_flat_mesh(_deck_v,
			_road_shader(Color(0.135, 0.133, 0.140), 0.94, true), _deck_uv), "DeckRoads")
		dr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(dr)
	add_child(MeshKit.mi(MeshKit.finish(dark,
		MeshKit.mat(Color(0.04, 0.04, 0.05), 0.98, 0.0)), "TunnelMouths"))
	_stats["viaducts"] = decks
	_stats["piers"] = piers
	_stats["portals"] = portals

## Ground-hugging triangles need no normal but up, so the mesh is a vertex list
## and nothing else.
func _flat_mesh(verts: PackedVector3Array, mat: Material,
		uv := PackedVector2Array()) -> ArrayMesh:
	var m := ArrayMesh.new()
	if verts.is_empty():
		return m
	var nrm := PackedVector3Array()
	nrm.resize(verts.size())
	nrm.fill(Vector3.UP)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	if uv.size() == verts.size():
		arr[Mesh.ARRAY_TEX_UV] = uv
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m

# ---------------------------------------------------------------- infrastructure
const PYLON_ROUTES := [
	[Vector2(900, 3100), Vector2(-2100, -4900), Vector2(-1500, -6600)],
	[Vector2(1100, -3200), Vector2(2400, 3900), Vector2(4300, 10600)],
	[Vector2(-1900, 3100), Vector2(2400, 4000)],
]

## Step a pylon sideways until it is out of the road, or give up on it. Moving
## along the run would just find the next place the line crosses; moving across
## it clears the carriageway and leaves the route where it was.
func _off_the_road(q: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	for step in [22.0, -22.0, 40.0, -40.0, 62.0, -62.0, 90.0, -90.0]:
		var t: Vector2 = q + nrm * float(step)
		if Sim.height_at(t.x, t.y) < Sim.sea_at(t.x, t.y) + 3.0:
			continue
		if not Sim.clear_of_airfield(t.x, t.y) or _inside_town(t):
			continue
		if _pylon_clear(t):
			return t
	return Vector2.INF

## Can a pylon stand here, as far as the roads go: out of the carriageway, and
## clear of a road bridge -- its ramps and anywhere under the deck. A bridge is
## not in the road index, so the kerb test alone put towers up through decks.
func _pylon_clear(q: Vector2) -> bool:
	return Sim.clear_of_roads(q.x, q.y, 12.0) and Sim.roads.bridge_headroom(q.x, q.y, 12.0) == INF

## Close a run of pylons off. A run of one carries no wire and is a tower
## standing on its own in a field, so it is dropped.
func _pylon_break(runs: Array, pts: Array) -> void:
	if pts.size() >= 2:
		runs.append(pts.duplicate())

func _powerlines() -> void:
	var mesh := SceneryMeshes.pylon_mesh()
	var xf := []
	var wire := MeshKit.begin()
	for route in PYLON_ROUTES:
		# Runs, not one list of points.
		#
		# A pylon that cannot stand -- in water, on the airfield, inside a town,
		# or on ground too steep to found one on -- used to be dropped from the
		# list, and the wire was then strung from the pylon before it to the
		# pylon after it. That is a conductor spanning two hundred metres of
		# open air with nothing holding it up, and across a lake it was
		# kilometres of it. A line that cannot be carried across something stops
		# at the edge of it and starts again on the far side, which is what a
		# real one does.
		var runs: Array = []
		var pts: Array = []
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var span := a.distance_to(b)
			var n := maxi(int(span / 190.0), 1)
			for k in n:
				var q: Vector2 = a.lerp(b, float(k) / float(n))
				if Sim.height_at(q.x, q.y) < Sim.sea_at(q.x, q.y) + 3.0:
					_pylon_break(runs, pts)
					pts = []
					continue
				if not Sim.clear_of_airfield(q.x, q.y) or _inside_town(q):
					_pylon_break(runs, pts)
					pts = []
					continue
				# Nothing is founded on a cliff. A tower needs a base eight
				# metres across, and on ground this steep it stands on one leg.
				if Sim.normal_at(q.x, q.y).dot(Vector3.UP) < 0.86:
					_pylon_break(runs, pts)
					pts = []
					continue
				# A pylon has a base about eight metres across and stands
				# thirty-four metres up; putting one in the carriageway is worse
				# than putting a house there. Nudged aside rather than dropped,
				# so the line still gets there.
				if not _pylon_clear(q):
					var moved := _off_the_road(q, a, b)
					if moved == Vector2.INF:
						_pylon_break(runs, pts)
						pts = []
						continue
					q = moved
				pts.append(q)
		# The last pylon on a run goes through the same test as the rest of
		# them. Appended unconditionally it was the one that ended up in the
		# carriageway: 1 of 128.
		var last: Vector2 = route[route.size() - 1]
		if Sim.height_at(last.x, last.y) < Sim.sea_at(last.x, last.y) + 3.0:
			_pylon_break(runs, pts)
			pts = []
		elif _pylon_clear(last):
			pts.append(last)
		else:
			var shifted := _off_the_road(last, route[route.size() - 2], last)
			if shifted != Vector2.INF:
				pts.append(shifted)
		_pylon_break(runs, pts)
		for r in runs:
			var prev := Vector3.INF
			for q in (r as Array):
				var qq: Vector2 = q
				var y: float = Sim.height_at(qq.x, qq.y)
				xf.append(Transform3D(Basis(Vector3.UP, 0.0),
					Vector3(qq.x, y - 1.0, qq.y)))
				pylon_spots.append(Vector3(qq.x, y, qq.y))
				var top := Vector3(qq.x, y + 23.8, qq.y)
				if prev != Vector3.INF:
					SceneryMeshes.catenary(wire, prev, top)
					# The longest thing a conductor is asked to cross. A span
					# that runs away is the run-breaking having failed, and it
					# is invisible in a count of towers.
					_stats["pylon_span"] = maxf(float(_stats.get(
						"pylon_span", 0.0)), prev.distance_to(top))
				prev = top
	_scatter(mesh, xf, "Pylons")
	add_child(MeshKit.mi(MeshKit.finish(wire, MeshKit.mat(Color(0.07, 0.07, 0.08), 0.9, 0.1)), "Wires"))
	_stats["pylons"] = xf.size()

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
		if y < Sim.sea_at(q.x, q.y) + 5.0 or not Sim.clear_of_airfield(q.x, q.y) or _inside_town(q):
			continue
		if not _pylon_clear(q):
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
			SceneryMeshes.fence_panel(mesh_st, Vector3(q.x, y, q.y), Vector3(q2.x, y2, q2.y))
	_scatter(post_mesh, xf, "FencePosts")
	# and into the obstacle field on its own terms. The general rule throws out
	# anything under two and a half metres, and a fence post is 2.4 -- so the
	# perimeter was drawn but nothing could touch it, and aircraft flew through
	# the wire as though it were not there.
	Obstacles.add_batch(post_mesh, xf, 1.6)
	add_child(MeshKit.mi(MeshKit.finish(mesh_st,
		MeshKit.mat(Color(0.36, 0.37, 0.36), 0.95, 0.1)), "FenceMesh"))
	_stats["fence_posts"] = xf.size()

func _windfarm() -> void:
	var ridge := Vector2(-6200, -2200)
	for i in 9:
		var q := ridge + Vector2(float(i % 3) * 420.0, floorf(float(i) / 3.0) * 480.0)
		var y := Sim.height_at(q.x, q.y)
		if y < Sim.sea_at(q.x, q.y) + 20.0 or not Sim.clear_of_airfield(q.x, q.y):
			continue
		if Sim.roads.bridge_headroom(q.x, q.y, 45.0) < INF:
			continue                        # a rotor sweeps forty metres
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
	for t in sites:
		var c: Vector2 = t["c"]
		var r: float = float(t["r"])
		for i in 3:
			var q := c + Vector2(cos(float(i) * 2.1), sin(float(i) * 2.1)) * (r * 1.15)
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
		var _ps := Sim.prof_at()
		_tick(delta)
		Sim.prof_end(&"scenery.process", _ps)

	func _tick(delta: float) -> void:
		if hub:
			hub.rotate_z(delta * 0.85)


## What a building comes down as: a low mound of broken concrete over its
## footprint and a little past it, higher in the middle, lumps of every size
## tumbled at every angle. It settles into the ground after a while and the
## heap in the obstacle field goes with it.
## What a block leaves when it comes down: a heap on the ground, drawn the
## height and the size of the solid box `Obstacles` leaves in the field for it,
## so what you see is what stops a round, a man and a soldier's eye.
##
## It was laid at the drawn block's own origin -- which for a block opened up
## at street level is a storey up, the ground floor being walls of its own --
## so the heap hung in the air; its lumps spilled out past the solid footprint
## onto ground that stopped nothing; and after two and a half minutes the box
## was taken out of the field and the heap sank away. It stays now.
class Rubble extends Node3D:
	var _oid := -1

	func setup(at: Transform3D, size: Vector3, oid: int) -> void:
		_oid = oid
		add_to_group("rubble")
		var yaw := Basis(Vector3.UP, at.basis.get_euler().y)
		var hx: float = size.x * 0.5
		var hz: float = size.z * 0.5
		# on the lowest ground under the footprint, so no corner of it is in the air
		var ground := INF
		for sx in [-1.0, 0.0, 1.0]:
			for sz in [-1.0, 0.0, 1.0]:
				var q: Vector3 = at.origin + yaw * Vector3(sx * hx, 0.0, sz * hz)
				ground = minf(ground, Sim.height_at(q.x, q.z))
		transform = Transform3D(yaw, Vector3(at.origin.x, ground, at.origin.z))
		# as tall as the solid heap, where there is one
		var peak: float = clampf(size.y * BLOCK_HEAP * 1.3, 1.0, 5.0)
		var rid: int = Obstacles.rubble_of(oid) if oid >= 0 else -1
		if rid >= 0:
			peak = maxf(Obstacles.top_of(rid) - ground, 0.6)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(at.origin)
		var st := MeshKit.begin()
		# the body of the heap: broad flat slabs lying over most of the
		# footprint, so the lumps sit on a mound and not on the grass
		for k in 7:
			var su: float = rng.randf_range(-0.4, 0.4)
			var sv: float = rng.randf_range(-0.4, 0.4)
			var slab := Vector3(hx * rng.randf_range(0.7, 1.1), peak * rng.randf_range(0.35, 0.6),
				hz * rng.randf_range(0.7, 1.1))
			var sb := Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
					rng.randf_range(0.05, 0.25))
			_box_at(st, sb, slab, Vector3(su * hx, slab.y * 0.15, sv * hz))
		var n: int = clampi(int(size.x * size.z / 4.0), 24, 110)
		for k in n:
			# anywhere over the footprint and a little past it, the big
			# lumps towards the middle and the small ones spilled out
			# inside the solid footprint (`Obstacles._leave_rubble` makes it
			# 1.04 of the block's): a lump outside it is a lump rounds pass through
			var u: float = rng.randf_range(-0.95, 0.95)
			var v: float = rng.randf_range(-0.95, 0.95)
			var r: float = clampf(sqrt(u * u * 0.5 + v * v * 0.5), 0.0, 1.0)
			var s: float = lerpf(2.4, 0.5, r) * rng.randf_range(0.6, 1.2)
			var lump := Vector3(s * rng.randf_range(0.8, 1.6), s * rng.randf_range(0.4, 0.9),
				s * rng.randf_range(0.8, 1.6))
			# the tallest lumps reach the top of the solid heap and no higher
			var y: float = minf(peak * (1.0 - r * r) - lump.y * 0.45, peak - lump.y * 0.5)
			var b := Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(),
					rng.randf_range(0.1, 0.6))
			_box_at(st, b, lump, Vector3(u * hx, maxf(y, -lump.y * 0.3), v * hz))
		var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.47, 0.45, 0.42), 0.95, 0.0)),
			"Rubble")
		add_child(mi)

	static func _box_at(st: SurfaceTool, b: Basis, size: Vector3, at: Vector3) -> void:
		var h := size * 0.5
		var c: Array = []
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					c.append(at + b * Vector3(h.x * sx, h.y * sy, h.z * sz))
		# faces as corner indices (x, y, z bits: 4 x + 2 y + z)
		for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
			var a: Vector3 = c[f[0]]
			var bb: Vector3 = c[f[1]]
			var cc: Vector3 = c[f[2]]
			var d: Vector3 = c[f[3]]
			var mid: Vector3 = (a + bb + cc + d) * 0.25
			MeshKit.quad_n(st, a, bb, cc, d, (mid - at).normalized())

	func clear_now() -> void:
		if _oid >= 0:
			var rid: int = Obstacles.rubble_of(_oid)
			if rid >= 0:
				Obstacles.remove(rid)
			_oid = -1
		queue_free()
