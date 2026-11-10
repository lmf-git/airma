class_name TownSet
extends Node3D
## What is standing in a town's streets: the parked cars, the stalls, the
## garden walls, the building site and its crane, the scaffolding, the ladders.
##
## This began inside the street-fight mode, which meant a town had a crane and
## a market in it when you fought there on foot and was bare blocks when you
## flew over it or drove through it in anything else -- the same place, two
## different places. It belongs to the town. The world puts one of these down
## for whichever town you are near, in every mode, and a match fought there
## uses the one that is already standing.

const HALF := 132.0               # how far out from the crossroads it reaches
const CELL := 2.0                 # the grid everything is stood on

## Every set that is standing, so that anybody can ask for a ladder without
## knowing which town he is in.
static var live: Array = []

var centre := Vector2.ZERO
var stats := {"props": 0, "ruins": 0}
## What was put down and where: [kind, position, yaw].
var props: Array = []
var _boxes := PackedInt32Array()
var _rng := RandomNumberGenerator.new()

func _enter_tree() -> void:
	live.append(self)

func _exit_tree() -> void:
	live.erase(self)
	for id in _boxes:
		Obstacles.remove(id)

func _ground(x: float, z: float) -> float:
	return Sim.height_at(x, z)

## A ladder within reach of `p`, in whatever town that is, or nothing.
static func ladder_at(p: Vector3) -> Array:
	for t in live:
		if is_instance_valid(t) and Vector2(p.x - t.centre.x, p.z - t.centre.y).length() < HALF + 20.0:
			var l: Array = t.ladder_near(p)
			if not l.is_empty():
				return l
	return []

# ------------------------------------------------------------- dressing the set
#
# The first version of this laid the same military clutter in every town on the
# map: jersey barriers and shipping containers down a village high street in
# the desert, the same as in a city in the snow. A town already says where it
# is -- the scenery gives each one a country and the ground gives it a climate
# -- so what is lying in its streets is chosen from those. Only the two start
# lines look like an army has been there.

var faction := "usa"
var biome := "grass"
var tone := Color(0.5, 0.5, 0.5)
var site: Dictionary = {}

const CAR_TONES := {
	"usa": [Color(0.55, 0.10, 0.08), Color(0.12, 0.20, 0.38), Color(0.80, 0.80, 0.78), Color(0.10, 0.10, 0.11)],
	"uk": [Color(0.10, 0.24, 0.16), Color(0.14, 0.14, 0.30), Color(0.62, 0.63, 0.64), Color(0.42, 0.08, 0.08)],
	"france": [Color(0.72, 0.72, 0.68), Color(0.18, 0.28, 0.46), Color(0.62, 0.52, 0.20), Color(0.30, 0.30, 0.32)],
	"russia": [Color(0.78, 0.76, 0.70), Color(0.36, 0.10, 0.10), Color(0.20, 0.32, 0.40), Color(0.50, 0.52, 0.46)],
	"china": [Color(0.16, 0.16, 0.18), Color(0.80, 0.80, 0.80), Color(0.50, 0.08, 0.08), Color(0.20, 0.34, 0.50)],
	"iran": [Color(0.84, 0.82, 0.76), Color(0.28, 0.40, 0.52), Color(0.42, 0.40, 0.36), Color(0.20, 0.36, 0.28)],
}

func _solid(at: Vector3, size: Vector3, yaw: float) -> void:
	_boxes.append(Obstacles.add_box(at, size.x * 0.5, size.y, size.z * 0.5, yaw))

func _mesh(at: Vector3, yaw: float, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshKit.mi(MeshKit.finish(st, mat), "Prop")
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)

## Is there room for something `r` across here, with space to walk round it?
func _room(x: float, z: float, r: float) -> bool:
	return Obstacles.hit(Vector3(x, _ground(x, z) + 1.0, z), r) < 0

func _snap(v: float) -> float:
	return snappedf(v - CELL * 0.5, CELL) + CELL * 0.5

## The lowest the ground gets under a footprint `r` across -- of the surface
## that is drawn, which is not quite the one the height field describes. A
## thing stood at the height of its own middle floats wherever the ground
## falls away from it; stood at the lowest corner it is at worst a little
## buried on the uphill side, and everything here is built to be.
func _seat(x: float, z: float, r: float) -> float:
	var pts := PackedVector2Array([Vector2(x, z), Vector2(x - r, z - r), Vector2(x + r, z - r),
		Vector2(x - r, z + r), Vector2(x + r, z + r)])
	var lo := 1e9
	if Sim.native != null:
		for h in Sim.native.surfaces_at(pts, Terrain.BASE_CELL):
			lo = minf(lo, float(h))
	for q in pts:
		lo = minf(lo, Sim.height_at(q.x, q.y))
	return lo - 0.04

## Masonry for this part of the world: mud brick, stone or fired brick.
func _masonry() -> Color:
	match biome:
		"desert":
			return Color(0.74, 0.62, 0.45)
		"snow", "rock":
			return Color(0.52, 0.52, 0.54)
	return Color(0.52, 0.33, 0.26).lerp(tone, 0.2)

## Everything a prop is, in one place: what it looks like and what of it is
## solid. `DEEP` of every base is underground, so a slope never shows a gap.
const DEEP := 0.7

func _prop(kind: String, x_in: float, z_in: float, yaw: float) -> bool:
	# On a grid point of the route survey, always. Something lying between two
	# of them is something the AI cannot see is there.
	var x: float = centre.x + _snap(x_in - centre.x)
	var z: float = centre.y + _snap(z_in - centre.y)
	var need: float = {"car": 3.4, "bus": 6.4, "container": 4.6, "stall": 2.6, "small": 1.6,
		"tree": 1.6}.get(kind, 2.5)
	if not _room(x, z, need):
		return false
	var at := Vector3(x, _seat(x, z, need * 0.45), z)
	var st := MeshKit.begin()
	var d := Vector3(0, -DEEP * 0.5, 0)
	match kind:
		"barrier":
			MeshKit.box(st, Vector3(3.2, 0.55 + DEEP, 0.62), Vector3(0, 0.275, 0) + d)
			MeshKit.box(st, Vector3(3.2, 0.55, 0.30), Vector3(0, 0.80, 0))
			_mesh(at, yaw, st, MeshKit.mat(Color(0.62, 0.61, 0.58), 0.9, 0.0))
			_solid(at, Vector3(3.2, 1.08, 0.62), yaw)
		"sandbags":
			MeshKit.box(st, Vector3(2.8, DEEP, 0.80), d)
			for row in 4:
				var w: float = 2.8 - row * 0.18
				MeshKit.box(st, Vector3(w, 0.27, 0.80 - row * 0.08), Vector3(0, 0.135 + row * 0.27, 0))
			_mesh(at, yaw, st, MeshKit.mat(Color(0.60, 0.53, 0.38) if biome == "desert"
				else Color(0.50, 0.47, 0.36), 1.0, 0.0))
			_solid(at, Vector3(2.8, 1.08, 0.80), yaw)
		"crates":
			MeshKit.box(st, Vector3(1.3, 1.1 + DEEP, 1.3), Vector3(0, 0.55, 0) + d)
			MeshKit.box(st, Vector3(1.0, 0.8, 1.0), Vector3(0.1, 1.5, -0.05))
			_mesh(at, yaw, st, MeshKit.mat(Color(0.40, 0.33, 0.22), 0.9, 0.0))
			_solid(at, Vector3(1.3, 1.9, 1.3), yaw)
		"car":
			# The same four wheels everywhere, and a body that says where: a
			# pickup, a hatchback, a van, a three-box saloon.
			var style: String = {"usa": "pickup", "iran": "pickup", "uk": "hatch", "france": "van",
				"russia": "saloon", "china": "saloon"}.get(faction, "saloon")
			if _rng.randf() < 0.35:
				style = "saloon"
			MeshKit.box(st, Vector3(1.85, 0.62, 4.3), Vector3(0, 0.62, 0))
			var cab_z := 0.25
			var cab_len := 2.1
			var cab_h := 0.55
			match style:
				"pickup":
					cab_z = -0.55
					cab_len = 1.5
					for sx in [-0.86, 0.86]:
						MeshKit.box(st, Vector3(0.10, 0.34, 1.9), Vector3(sx, 1.08, 1.15))
				"hatch":
					cab_z = 0.45
					cab_len = 2.7
				"van":
					cab_z = 0.35
					cab_len = 3.3
					cab_h = 0.95
			MeshKit.box(st, Vector3(1.65, cab_h, cab_len), Vector3(0, 0.93 + cab_h * 0.5, cab_z))
			for wx in [-0.85, 0.85]:
				for wz in [-1.4, 1.4]:
					MeshKit.box(st, Vector3(0.24, 0.62 + DEEP, 0.62), Vector3(wx, 0.31, wz) + d)
			var tones: Array = CAR_TONES.get(faction, CAR_TONES["usa"])
			_mesh(at, yaw, st, MeshKit.mat(tones[_rng.randi() % tones.size()], 0.5, 0.35))
			_solid(at, Vector3(1.85, 0.94, 4.3), yaw)
			_solid(at + Basis(Vector3.UP, yaw) * Vector3(0, 0, cab_z),
				Vector3(1.65, 0.93 + cab_h, cab_len), yaw)
		"bus":
			# what every street fight in a British town has lying across it
			var tall: float = 4.3 if faction == "uk" else 3.1
			MeshKit.box(st, Vector3(2.5, tall - 0.45, 10.4), Vector3(0, 0.45 + (tall - 0.45) * 0.5, 0))
			for wz in [-3.6, 3.4]:
				for wx in [-1.1, 1.1]:
					MeshKit.box(st, Vector3(0.3, 0.95 + DEEP, 0.95), Vector3(wx, 0.47, wz) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.66, 0.07, 0.06) if faction in ["uk", "china"]
				else Color(0.80, 0.66, 0.16) if faction == "usa" else Color(0.72, 0.74, 0.76), 0.5, 0.3))
			var glass := MeshKit.begin()
			for lvl in (2 if faction == "uk" else 1):
				MeshKit.box(glass, Vector3(2.54, 0.75, 9.4), Vector3(0, 1.75 + lvl * 1.85, 0))
			_mesh(at, yaw, glass, MeshKit.mat(Color(0.07, 0.09, 0.11), 0.2, 0.6))
			_solid(at, Vector3(2.5, tall, 10.4), yaw)
		"container":
			MeshKit.box(st, Vector3(2.44, 2.6 + DEEP, 6.06), Vector3(0, 1.3, 0) + d)
			for rib in 9:
				MeshKit.box(st, Vector3(2.50, 2.5, 0.10), Vector3(0, 1.3, -2.7 + rib * 0.675))
			var paint := [Color(0.50, 0.20, 0.12), Color(0.14, 0.30, 0.42), Color(0.30, 0.36, 0.24)]
			_mesh(at, yaw, st, MeshKit.mat(paint[_rng.randi() % paint.size()], 0.7, 0.3))
			_solid(at, Vector3(2.44, 2.6, 6.06), yaw)
		"wall":
			# the garden wall of wherever this is
			MeshKit.box(st, Vector3(4.0, 1.25 + DEEP, 0.40), Vector3(0, 0.625, 0) + d)
			MeshKit.box(st, Vector3(4.1, 0.10, 0.50), Vector3(0, 1.28, 0))
			_mesh(at, yaw, st, MeshKit.mat(_masonry(), 0.95, 0.0))
			_solid(at, Vector3(4.0, 1.25, 0.40), yaw)
		"panel":
			# precast concrete fencing, by the kilometre
			for seg in 2:
				MeshKit.box(st, Vector3(1.95, 2.4 + DEEP, 0.16), Vector3(-1.0 + seg * 2.0, 1.2, 0) + d)
			for post in 3:
				MeshKit.box(st, Vector3(0.22, 2.55 + DEEP, 0.26), Vector3(-2.0 + post * 2.0, 1.27, 0) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.60, 0.60, 0.58), 0.95, 0.0))
			_solid(at, Vector3(4.2, 2.4, 0.26), yaw)
		"hedge":
			MeshKit.box(st, Vector3(4.0, 1.35 + DEEP, 0.9), Vector3(0, 0.67, 0) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.16, 0.30, 0.14), 1.0, 0.0))
			_solid(at, Vector3(4.0, 1.35, 0.9), yaw)
		"stall":
			# a market stall: a counter to get behind and an awning over it
			MeshKit.box(st, Vector3(2.6, 0.95 + DEEP, 1.0), Vector3(0, 0.47, 0) + d)
			for px in [-1.25, 1.25]:
				for pz in [-0.9, 0.9]:
					MeshKit.box(st, Vector3(0.07, 2.3 + DEEP, 0.07), Vector3(px, 1.15, pz) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.42, 0.32, 0.20), 0.9, 0.0))
			var aw := MeshKit.begin()
			MeshKit.box(aw, Vector3(3.0, 0.06, 2.3), Vector3(0, 2.32, 0))
			var cloth: Color = {"china": Color(0.70, 0.08, 0.06), "iran": Color(0.16, 0.42, 0.36),
				"france": Color(0.80, 0.74, 0.60), "russia": Color(0.20, 0.30, 0.52)}.get(
				faction, Color(0.64, 0.46, 0.18))
			_mesh(at, yaw, aw, MeshKit.mat(cloth, 0.95, 0.0))
			_solid(at, Vector3(2.6, 0.95, 1.0), yaw)
		"small":
			# one thing that belongs on this country's pavements
			var size := Vector3(1.9, 1.3, 1.2)
			var col := Color(0.12, 0.28, 0.16)            # a dumpster
			match faction:
				"uk":
					size = Vector3(0.95, 2.5, 0.95)       # a telephone box
					col = Color(0.70, 0.06, 0.05)
				"france":
					size = Vector3(1.1, 2.9, 1.1)         # an advertising column
					col = Color(0.20, 0.30, 0.24)
				"russia":
					size = Vector3(2.4, 2.5, 1.9)         # a kiosk
					col = tone.lightened(0.15)
				"china":
					size = Vector3(1.6, 1.25, 0.8)        # a row of parked bicycles
					col = Color(0.20, 0.42, 0.62)
				"iran":
					size = Vector3(1.5, 1.7, 1.5)         # a water tank
					col = Color(0.78, 0.80, 0.82)
			MeshKit.box(st, size + Vector3(0, DEEP, 0), Vector3(0, size.y * 0.5, 0) + d)
			if faction == "uk":
				MeshKit.box(st, Vector3(1.05, 0.12, 1.05), Vector3(0, 2.56, 0))
			_mesh(at, yaw, st, MeshKit.mat(col, 0.6, 0.2))
			_solid(at, size, yaw)
		"stack":
			# what the climate stacks by the road: firewood, bales, sacks
			var sz := Vector3(2.2, 1.2, 1.2)
			var sc := Color(0.72, 0.62, 0.30)             # straw
			if biome == "snow" or biome == "rock":
				sc = Color(0.36, 0.25, 0.15)              # logs
				sz = Vector3(3.0, 1.2, 1.1)
			elif biome == "desert":
				sc = Color(0.70, 0.64, 0.52)              # sacks
			MeshKit.box(st, sz + Vector3(0, DEEP, 0), Vector3(0, sz.y * 0.5, 0) + d)
			MeshKit.box(st, Vector3(sz.x * 0.62, 0.5, sz.z * 0.8), Vector3(0, sz.y + 0.25, 0))
			_mesh(at, yaw, st, MeshKit.mat(sc, 1.0, 0.0))
			_solid(at, sz, yaw)
		"tree":
			# a street tree of the right kind; the trunk stops a round
			if biome == "desert":
				MeshKit.cone(st, 0.20, 0.14, -DEEP, 5.2, Vector3.ZERO, 6, true)
				for k in 6:
					var a := TAU * float(k) / 6.0
					# (in the cone's frame, which runs along z until it is stood up)
					MeshKit.box(st, Vector3(2.4, 0.40, 0.08), Vector3(cos(a) * 1.1, sin(a) * 1.1, 5.1))
			elif biome == "snow" or biome == "rock":
				MeshKit.cone(st, 0.18, 0.14, -DEEP, 1.6, Vector3.ZERO, 6, true)
				MeshKit.cone(st, 1.5, 0.05, 1.4, 6.5, Vector3.ZERO, 7, true)
			else:
				MeshKit.cone(st, 0.24, 0.16, -DEEP, 3.0, Vector3.ZERO, 6, true)
				MeshKit.cone(st, 2.1, 0.5, 2.7, 6.2, Vector3.ZERO, 8, true)
			var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.20, 0.33, 0.17), 0.9, 0.0)), "Tree")
			add_child(mi)
			# cones are lofted along z, so stand it up
			mi.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), at)
			_solid(at, Vector3(0.5, 3.0, 0.5), 0.0)
		_:
			return false
	stats["props"] = int(stats["props"]) + 1
	props.append([kind, at, yaw])
	return true

## A building with the roof off and the doors gone: four walls, a partition,
## and ways in. The only rooms in town, and so the only place the fight goes
## properly indoors. Walls stand on route grid lines and doors on grid points,
## for the same reason the clutter does.
func _ruin(cx: float, cz: float) -> void:
	var o := Vector3(cx, _seat(cx, cz, 6.5), cz)
	var st := MeshKit.begin()
	var e := 6.0
	var doors := {"n": -2.0, "s": 2.0, "w": 4.0, "e": -4.0}
	# windows are a wall you can shoot over
	var sills := {"n": 4.0, "s": -4.0, "w": -2.0, "e": 2.0}
	for wall in ["n", "s", "w", "e"]:
		var along_x: bool = wall in ["n", "s"]
		var base: Vector3 = o + (Vector3(0, 0, -e if wall == "n" else e) if along_x
			else Vector3(-e if wall == "w" else e, 0, 0))
		var cuts: Array = [[float(doors[wall]), 0.0], [float(sills[wall]), 1.05]]
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var from: float = -e - 0.25
		for c in cuts:
			var lo: float = float(c[0]) - 1.2
			_ruin_wall(st, o, base, along_x, from, lo, 3.1)
			if float(c[1]) > 0.0:
				_ruin_wall(st, o, base, along_x, lo, lo + 2.4, float(c[1]))
			from = lo + 2.4
		_ruin_wall(st, o, base, along_x, from, e + 0.25, 3.1)
	# the partition, with its own doorway
	_ruin_wall(st, o, o, false, -e, 0.8, 2.9)
	_ruin_wall(st, o, o, false, 3.2, e, 2.9)
	var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(_masonry().lightened(0.08), 0.95, 0.0)), "Ruin")
	add_child(mi)
	mi.global_position = o
	stats["ruins"] = int(stats["ruins"]) + 1

func _ruin_wall(st: SurfaceTool, o: Vector3, base: Vector3, along_x: bool, from: float,
		to: float, h: float) -> void:
	if to - from < 0.2:
		return
	var mid: float = (from + to) * 0.5
	var size := Vector3(to - from, h, 0.5) if along_x else Vector3(0.5, h, to - from)
	var at: Vector3 = base + (Vector3(mid, 0, 0) if along_x else Vector3(0, 0, mid))
	MeshKit.box(st, size + Vector3(0, DEEP, 0), at - o + Vector3(0, (h - DEEP) * 0.5, 0))
	_solid(at, size, 0.0)

## A building site: a tower crane you can climb and walk out along, and the
## stacks it was lifting. The mast is a wall like any other -- take hold of it
## and go up -- and from the top the jib is a road out over the rooftops.
func _crane(cx: float, cz: float) -> void:
	var o := Vector3(cx, _seat(cx, cz, 3.0), cz)
	var h := 30.0
	var yellow := MeshKit.mat(Color(0.86, 0.66, 0.10), 0.6, 0.3)
	var st := MeshKit.begin()
	# the mast: four legs and the lacing between them
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0.18, h + DEEP, 0.18), Vector3(sx, (h - DEEP) * 0.5, sz))
	var lvl := 1.5
	while lvl < h:
		for sx in [-1.0, 1.0]:
			MeshKit.box(st, Vector3(0.08, 0.08, 2.0), Vector3(sx, lvl, 0))
			MeshKit.box(st, Vector3(2.0, 0.08, 0.08), Vector3(0, lvl, sx))
		lvl += 1.5
	# the concrete it stands on
	MeshKit.box(st, Vector3(5.0, 0.5 + DEEP, 5.0), Vector3(0, 0.25 - DEEP * 0.5, 0))
	_solid(o, Vector3(2.2, h, 2.2), 0.0)
	var mast_id: int = _boxes[_boxes.size() - 1]
	# the jib one way, the counterweight the other
	var jib := 40.0
	var back := 12.0
	var along := Vector3(1, 0, 0) if absf(cx - centre.x) < absf(cz - centre.y) else Vector3(0, 0, 1)
	# out over the middle of town, where there is something to look down at
	var to_mid := Vector3(centre.x - cx, 0, centre.y - cz)
	if along.dot(to_mid) < 0.0:
		along = -along
	var is_x: bool = absf(along.x) > 0.5
	var mid_j: Vector3 = along * (jib - back) * 0.5
	var size_j := Vector3(jib + back, 0.9, 1.5) if is_x else Vector3(1.5, 0.9, jib + back)
	MeshKit.box(st, size_j, mid_j + Vector3(0, h - 0.45, 0))
	# handrails, so it reads as somewhere you are meant to be able to walk
	for sgn in [-1.0, 1.0]:
		var rail := Vector3(jib + back, 0.06, 0.06) if is_x else Vector3(0.06, 0.06, jib + back)
		var off := Vector3(0, 0, sgn * 0.72) if is_x else Vector3(sgn * 0.72, 0, 0)
		MeshKit.box(st, rail, mid_j + off + Vector3(0, h + 1.0, 0))
	_solid(o + mid_j + Vector3(0, h - 0.9, 0), size_j, 0.0)
	# the tower head and the ties
	MeshKit.box(st, Vector3(0.3, 6.0, 0.3), Vector3(0, h + 3.0, 0))
	# the hook, hanging where the load was
	MeshKit.box(st, Vector3(0.06, 14.0, 0.06), along * 24.0 + Vector3(0, h - 7.9, 0))
	MeshKit.box(st, Vector3(0.5, 0.7, 0.5), along * 24.0 + Vector3(0, h - 15.0, 0))
	var mi := MeshKit.mi(MeshKit.finish(st, yellow), "Crane")
	add_child(mi)
	mi.global_position = o
	var cw := MeshKit.begin()
	MeshKit.box(cw, Vector3(2.4, 2.2, 2.4), -along * (back - 1.6) + Vector3(0, h - 2.0, 0))
	var cm := MeshKit.mi(MeshKit.finish(cw, MeshKit.mat(Color(0.55, 0.55, 0.53), 0.95, 0.0)), "Weight")
	add_child(cm)
	cm.global_position = o
	# what it was lifting: containers two high, and pipe
	var side := Vector3(-along.z, 0, along.x)
	for k in 2:
		var px: float = cx + side.x * (7.0 + k * 0.1) - along.x * 4.0
		var pz: float = cz + side.z * (7.0 + k * 0.1) - along.z * 4.0
		if k == 0:
			_prop("container", px, pz, 0.0 if is_x else PI * 0.5)
	_prop("crates", cx - side.x * 6.0, cz - side.z * 6.0, 0.0)
	# the ladder up the mast, on the side the jib does not overhang
	_ladder(mast_id, o + Vector3(side.x, 0, side.z) * 5.0)
	stats["cranes"] = int(stats.get("cranes", 0)) + 1
	crane_at = o + Vector3(0, h, 0)

var crane_at := Vector3.INF

## Ladders: [foot, outward normal, structure id, top]. A ladder is a line up a
## face that somebody has bolted rungs to; the man climbing it is on the same
## wall he would be without it, held to that line and going faster.
var ladders: Array = []

func ladder_near(p: Vector3) -> Array:
	for l in ladders:
		var foot: Vector3 = l[0]
		var n: Vector3 = l[1]
		var at: Vector3 = foot + n * 0.5
		if Vector2(p.x - at.x, p.z - at.z).length() < 1.0 and p.y < float(l[3]) - 1.0 \
				and p.y > foot.y - 1.0 and Obstacles._dead[int(l[2])] == 0:
			return l
	return []

## Rails and rungs up a face of structure `id`, from the ground to its top.
func _ladder(id: int, toward: Vector3, shift := 0.0) -> void:
	var f: Dictionary = Obstacles.face_of(id, toward)
	var n: Vector3 = f["n"]
	var t := Vector3(n.z, 0.0, -n.x)
	var foot: Vector3 = (f["foot"] as Vector3) + t * clampf(shift, -float(f["half"]) + 0.6, float(f["half"]) - 0.6)
	# `foot` is on the face at the structure's middle; slide it to where on
	# the face the caller asked for
	var c: Vector3 = Obstacles.centre_of(id)
	foot = Vector3(c.x, 0.0, c.z) + n * ((f["foot"] as Vector3) - Vector3(c.x, 0.0, c.z)).dot(n) \
		+ t * clampf(shift, -float(f["half"]) + 0.6, float(f["half"]) - 0.6)
	foot.y = _seat(foot.x + n.x * 0.4, foot.z + n.z * 0.4, 0.4)
	var top: float = float(f["top"])
	var h: float = top - foot.y
	if h < 2.5:
		return
	var st := MeshKit.begin()
	var yaw: float = atan2(n.x, n.z)
	for sx in [-0.24, 0.24]:
		MeshKit.box(st, Vector3(0.05, h + 0.9 + DEEP, 0.05), Vector3(sx, (h + 0.9 - DEEP) * 0.5, 0.10))
	var ry: float = snappedf(foot.y, Pilot.RUNG) - foot.y + Pilot.RUNG
	while ry < h + 0.4:
		MeshKit.box(st, Vector3(0.48, 0.035, 0.035), Vector3(0, ry, 0.10))
		ry += Pilot.RUNG
	var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.62, 0.63, 0.66), 0.4, 0.7)), "Ladder")
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), foot)
	ladders.append([foot, n, id, top])
	stats["ladders"] = int(stats.get("ladders", 0)) + 1

## Scaffolding up the face of a building: netted, so it stops a round, and the
## quick way to a roof.
func _scaffold(lot: Vector2) -> void:
	var gy: float = _ground(lot.x, lot.y)
	var id: int = Obstacles.blocks(Vector3(lot.x, gy + 2.0, lot.y), 0.5)
	if id < 0:
		return
	var out: Vector3 = Vector3(centre.x - lot.x, 0, centre.y - lot.y)
	var f: Dictionary = Obstacles.face_of(id, Vector3(lot.x, 0, lot.y) + out.normalized() * 40.0)
	var n: Vector3 = f["n"]
	var top: float = float(f["top"])
	var foot: Vector3 = f["foot"]
	var is_x: bool = absf(n.x) > 0.5
	var run: float = minf(float(f["half"]) * 2.0 - 2.0, 12.0)
	if run < 5.0 or top - gy < 5.0:
		return
	var h: float = minf(top - gy - 1.2, 13.0)
	var mid: Vector3 = foot + n * 0.85
	mid.y = _seat(mid.x, mid.z, 1.0)
	if Obstacles.hit(mid + n * 1.4 + Vector3(0, 1.0, 0), 0.6) >= 0:
		return
	var size := Vector3(1.5, h, run) if is_x else Vector3(run, h, 1.5)
	var st := MeshKit.begin()
	var poles := int(run / 2.4) + 1
	for k in poles + 1:
		var s: float = -run * 0.5 + run * float(k) / float(poles)
		for dep in [-0.7, 0.7]:
			var pp := Vector3(dep, (h - DEEP) * 0.5, s) if is_x else Vector3(s, (h - DEEP) * 0.5, dep)
			MeshKit.box(st, Vector3(0.07, h + DEEP, 0.07), pp)
	var deck := 2.3
	while deck <= h + 0.01:
		MeshKit.box(st, Vector3(1.5, 0.07, run) if is_x else Vector3(run, 0.07, 1.5), Vector3(0, deck, 0))
		deck += 2.3
	var fm := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.55, 0.56, 0.58), 0.5, 0.6)), "Scaffold")
	add_child(fm)
	fm.global_position = mid
	var net := MeshKit.begin()
	var face_off: Vector3 = n * 0.76
	MeshKit.box(net, Vector3(0.03, h - 0.4, run) if is_x else Vector3(run, h - 0.4, 0.03),
		Vector3(face_off.x, h * 0.5 + 0.2, face_off.z))
	var nm := MeshKit.mat(Color(0.14, 0.36, 0.26, 0.82), 1.0, 0.0)
	nm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	nm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var nmi := MeshKit.mi(MeshKit.finish(net, nm), "Net")
	add_child(nmi)
	nmi.global_position = mid
	_solid(mid, size, 0.0)
	# and the ladder up the outside of it
	_ladder(_boxes[_boxes.size() - 1], mid + n * 6.0, run * 0.5 - 1.0)
	stats["scaffolds"] = int(stats.get("scaffolds", 0)) + 1

## Lay the town out. The same town always comes out the same: the seed is the
## town's own position, not the match's.
func build(at: Vector2, of_site: Dictionary) -> void:
	centre = Vector2(snappedf(at.x, CELL), snappedf(at.y, CELL))
	site = of_site
	_rng.seed = 90210 + int(absf(centre.x) * 3.0 + absf(centre.y) * 7.0)
	var c3 := Vector3(centre.x, _ground(centre.x, centre.y), centre.y)
	faction = String(site.get("faction", ""))
	if faction == "":
		faction = Sim.region_faction(centre.x, centre.y)
	biome = Sim.biome_kind(centre.x, centre.y, c3.y, Sim.normal_at(centre.x, centre.y).y)
	tone = Sim.faction_colour(faction)
	stats["faction"] = faction
	stats["biome"] = biome

	# The lots the town left empty, and the ones it built on.
	var empty: Array = []
	var built: Array = []
	for gx in range(-4, 5):
		for gz in range(-4, 5):
			var lx: float = gx * 30.0
			var lz: float = gz * 30.0
			# not in a street, and not on top of either side's start line
			if absf(fmod(absf(lx) + 64.0, 128.0) - 64.0) < 22.0 \
					or absf(fmod(absf(lz) + 64.0, 128.0) - 64.0) < 22.0:
				continue
			if absf(lz) > 100.0 or absf(lx) > 100.0:
				continue
			# centred on a grid point, so the walls land on grid lines
			var cx: float = centre.x + _snap(lx)
			var cz: float = centre.y + _snap(lz)
			if _room(cx, cz, 9.6):
				empty.append(Vector2(cx, cz))
			elif Obstacles.blocks(Vector3(cx, _ground(cx, cz) + 2.0, cz), 0.5) >= 0:
				built.append(Vector2(cx, cz))
	empty.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_to(centre) < b.distance_to(centre))
	built.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_to(centre) < b.distance_to(centre))
	# One of the empty lots is a building site; the others are what was there
	# before the fighting.
	var placed: Array = []
	for l in empty:
		var ok := true
		for q in placed:
			if (q as Vector2).distance_to(l) < 50.0:
				ok = false
		if not ok or placed.size() >= 5:
			continue
		placed.append(l)
		if placed.size() == 2 or (placed.size() == 1 and empty.size() == 1):
			_crane((l as Vector2).x, (l as Vector2).y)
		else:
			_ruin((l as Vector2).x, (l as Vector2).y)
	if crane_at == Vector3.INF and not placed.is_empty():
		# every lot went to a ruin: put the crane in the widest bit of street
		_crane(centre.x + _snap(20.0), centre.y + _snap(40.0))
	var scaf := 0
	for l2 in built:
		if scaf >= 4:
			break
		var before: int = int(stats.get("scaffolds", 0))
		_scaffold(l2)
		if int(stats.get("scaffolds", 0)) > before:
			scaf += 1

	# Fire ladders on a few more: the ordinary way onto an ordinary roof.
	var fire := 0
	for l3 in built:
		if fire >= 6:
			break
		var lot3: Vector2 = l3
		var bid: int = Obstacles.blocks(Vector3(lot3.x, _ground(lot3.x, lot3.y) + 2.0, lot3.y), 0.5)
		if bid < 0 or Obstacles.top_of(bid) - _ground(lot3.x, lot3.y) > 26.0:
			continue
		var taken := false
		for have in ladders:
			if int(have[2]) == bid:
				taken = true
		if taken:
			continue
		# on the side away from the middle of town: the back of the building
		var rear := Vector3(lot3.x - centre.x, 0, lot3.y - centre.y).normalized()
		var before_n: int = ladders.size()
		_ladder(bid, Vector3(lot3.x, 0, lot3.y) + rear * 40.0, 3.0)
		if ladders.size() > before_n:
			var lf: Vector3 = (ladders[ladders.size() - 1][0] as Vector3)
			var ln: Vector3 = (ladders[ladders.size() - 1][1] as Vector3)
			# nothing standing where you would stand to get on it
			if Obstacles.blocks(lf + ln * 0.6 + Vector3(0, 0.4, 0), 0.4) >= 0:
				ladders.pop_back()
				get_child(get_child_count() - 1).queue_free()
			else:
				fire += 1

	# What the streets of this town have in them. Cars at the kerb, the odd
	# one abandoned in the carriageway, a bus across a junction, stalls and
	# street trees along the pavement, and garden walls of the local stone.
	var kerb: Array = ["car", "car", "car", "tree", "tree", "small", "stack"]
	var road: Array = ["car", "car", "wall", "stack"]
	match faction:
		"uk":
			kerb.append_array(["hedge", "hedge", "small"])
			road.append("bus")
		"france":
			kerb.append_array(["stall", "hedge", "small"])
		"russia":
			kerb.append_array(["panel", "panel", "small"])
			road.append("panel")
		"china":
			kerb.append_array(["stall", "stall", "small"])
			road.append("bus")
		"iran":
			kerb.append_array(["stall", "stall", "wall", "small"])
		_:
			kerb.append_array(["small", "hedge"])
			road.append("bus")
	if biome == "desert":
		kerb.append_array(["wall", "stall"])
	for line in [-128.0, 0.0, 128.0]:
		for along_x in [true, false]:
			var s: float = -HALF + 9.0
			var flip := 1.0
			while s < HALF - 6.0:
				var at_kerb: bool = _rng.randf() < 0.68
				var lat: float = flip * (_rng.randf_range(9.5, 12.5) if at_kerb
					else _rng.randf_range(1.5, 6.0))
				flip = -flip
				var kind: String = kerb[_rng.randi() % kerb.size()] if at_kerb \
					else road[_rng.randi() % road.size()]
				var street_yaw: float = PI * 0.5 if along_x else 0.0
				var yaw: float = street_yaw
				if at_kerb:
					# parked: along the street, give or take
					yaw += _rng.randf_range(-0.06, 0.06)
				else:
					# left where it stopped
					yaw += _rng.randf_range(-0.9, 0.9)
					if kind in ["wall", "panel"]:
						yaw = street_yaw + PI * 0.5
				var px: float = centre.x + (s if along_x else line + lat)
				var pz: float = centre.y + (line + lat if along_x else s)
				# keep the crossroads themselves passable
				var near_x: float = absf(fmod(absf(px - centre.x) + 64.0, 128.0) - 64.0)
				var near_z: float = absf(fmod(absf(pz - centre.y) + 64.0, 128.0) - 64.0)
				if not (near_x < 9.0 and near_z < 9.0):
					_prop(kind, px, pz, yaw)
				s += _rng.randf_range(9.0, 16.0)
	# The two start lines are the only places an army has been.
	for sgn in [-1.0, 1.0]:
		for k in 7:
			var mx: float = centre.x + (k - 3) * 15.0 + _rng.randf_range(-3, 3)
			var mz: float = centre.y + sgn * (104.0 + _rng.randf_range(-3.0, 3.0))
			_prop(["sandbags", "barrier", "sandbags", "crates"][_rng.randi() % 4], mx, mz, PI * 0.5 * 0.0)
	# The yards and alleys between the buildings.
	for i in 150:
		var ax: float = centre.x + _rng.randf_range(-HALF + 8.0, HALF - 8.0)
		var az: float = centre.y + _rng.randf_range(-HALF + 8.0, HALF - 8.0)
		var in_street: bool = absf(fmod(absf(ax - centre.x) + 64.0, 128.0) - 64.0) < 15.0 \
			or absf(fmod(absf(az - centre.y) + 64.0, 128.0) - 64.0) < 15.0
		if in_street:
			continue
		_prop(["wall", "stack", "crates", "wall", "hedge" if biome != "desert" else "wall",
			"small"][_rng.randi() % 6], ax, az, float(_rng.randi() % 2) * PI * 0.5)

