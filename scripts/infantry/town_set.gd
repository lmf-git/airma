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
	# and the buildings that were opened up are stood back on the ground
	for h in _hollowed:
		if not Obstacles.gone(int(h[0])):
			Obstacles.lift(int(h[0]), -float(h[1]))
			if is_instance_valid(scenery):
				scenery.lower_block(h[3])
	_hollowed.clear()

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

## The last mesh put down, so the boxes that follow it know what they belong to.
var _last_mesh: MeshInstance3D = null
## Structure id -> [mesh, kind]: what goes when something heavy drives into it.
var _breaks: Dictionary = {}
const UNBREAKABLE := ["container", "bus", "crane", "scaffold"]
## What a round goes through for a third of what its size says: see
## `Obstacles.set_light`.
const LIGHT := ["hedge", "stall", "car", "bus", "small", "fence"]

func _solid(at: Vector3, size: Vector3, yaw: float, kind := "") -> void:
	var id: int = Obstacles.add_box(at, size.x * 0.5, size.y, size.z * 0.5, yaw)
	_boxes.append(id)
	if LIGHT.has(kind):
		Obstacles.set_light(id)
	if kind != "" and not UNBREAKABLE.has(kind) and is_instance_valid(_last_mesh):
		_breaks[id] = [_last_mesh, kind]

func _mesh(at: Vector3, yaw: float, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshKit.mi(MeshKit.finish(st, mat), "Prop")
	add_child(mi)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_last_mesh = mi

## Something heavy is driving through `at`. Whatever of this town's clutter
## it is touching gives way: walls and stalls come apart, a car is flattened,
## a tree goes over. Buildings, containers and the crane do not.
static func crush(at: Vector3, r: float, push: Vector3) -> int:
	var n := 0
	for t in live:
		if not is_instance_valid(t) \
				or Vector2(at.x - t.centre.x, at.z - t.centre.y).length() > HALF + 40.0:
			continue
		for tries in 3:
			var id: int = Obstacles.hit(at, r)
			if id < 0 or not t._breaks.has(id):
				break
			t._smash(id, push)
			n += 1
	return n

func _smash(id: int, push: Vector3) -> void:
	var entry: Array = _breaks[id]
	var mi: MeshInstance3D = entry[0]
	var kind: String = entry[1]
	# every box that belongs to the same thing goes with it
	for other in _breaks.keys():
		if (_breaks[other] as Array)[0] == mi:
			Obstacles.remove(other)
			_breaks.erase(other)
	if not is_instance_valid(mi):
		return
	var world := get_tree().current_scene
	var at: Vector3 = mi.global_position
	var dir := Vector3(push.x, 0.0, push.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	Effects.dust(world, at + Vector3(0, 0.8, 0), 2.2)
	Sfx.play_at(world, "thump", at, -4.0, randf_range(1.2, 1.6), 300.0)
	if kind == "car":
		# flattened where it stands
		mi.scale = Vector3(1.08, 0.42, 1.05)
		return
	if kind == "tree":
		mi.global_transform = Transform3D(Basis(Vector3.UP.cross(dir).normalized(), deg_to_rad(84.0))
			* mi.global_transform.basis, at + Vector3(0, 0.2, 0))
		return
	# everything else comes apart
	var mat: Material = mi.mesh.surface_get_material(0) if mi.mesh != null else null
	for k in 6:
		var st := MeshKit.begin()
		MeshKit.box(st, Vector3(randf_range(0.3, 0.9), randf_range(0.2, 0.6), randf_range(0.3, 0.9)),
			Vector3.ZERO)
		var d := Effects.Debris.new()
		d.add_child(MeshKit.mi(MeshKit.finish(st, mat), "Bit"))
		d.vel = dir * randf_range(2.0, 6.0) + Vector3(randf_range(-2, 2), randf_range(2.0, 5.0), randf_range(-2, 2))
		d.spin = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
		d.rest_offset = 0.15
		d.life = 40.0
		world.add_child(d)
		d.global_position = at + Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.2), randf_range(-1.0, 1.0))
	mi.queue_free()

## Something very large has gone off at `at`. Everything of this town's that
## is standing within `r` of it is flattened where it stands -- cars, stalls,
## walls, and the things nothing else can break: containers, the scaffolding,
## the crane -- and none of it stops a round or a man afterwards.
func flatten(at: Vector3, r: float) -> int:
	if Vector2(at.x - centre.x, at.z - centre.y).length() > HALF + r + 60.0:
		return 0
	var down := {}
	for c in get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.has_meta("flat"):
			continue
		var p: Vector3 = mi.global_position
		if Vector2(p.x - at.x, p.z - at.z).length() > r:
			continue
		mi.set_meta("flat", true)
		down[mi] = true
		# pressed into its own footprint, and thrown a little out of true
		var b: Basis = mi.global_transform.basis.rotated(Vector3.UP, randf_range(-0.3, 0.3))
		mi.global_transform = Transform3D(b.scaled(Vector3(1.08, 0.1, 1.08)), p)
	for id in _breaks.keys():
		var m: Variant = (_breaks[id] as Array)[0]
		if not is_instance_valid(m) or down.has(m):
			_breaks.erase(id)
	for id in _boxes:
		var c2: Vector3 = Obstacles.centre_of(id)
		if Vector2(c2.x - at.x, c2.z - at.z).length() <= r:
			Obstacles.remove(id)
	return down.size()

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
			_solid(at, Vector3(3.2, 1.08, 0.62), yaw, kind)
		"sandbags":
			MeshKit.box(st, Vector3(2.8, DEEP, 0.80), d)
			for row in 4:
				var w: float = 2.8 - row * 0.18
				MeshKit.box(st, Vector3(w, 0.27, 0.80 - row * 0.08), Vector3(0, 0.135 + row * 0.27, 0))
			_mesh(at, yaw, st, MeshKit.mat(Color(0.60, 0.53, 0.38) if biome == "desert"
				else Color(0.50, 0.47, 0.36), 1.0, 0.0))
			_solid(at, Vector3(2.8, 1.08, 0.80), yaw, kind)
		"crates":
			MeshKit.box(st, Vector3(1.3, 1.1 + DEEP, 1.3), Vector3(0, 0.55, 0) + d)
			MeshKit.box(st, Vector3(1.0, 0.8, 1.0), Vector3(0.1, 1.5, -0.05))
			_mesh(at, yaw, st, MeshKit.mat(Color(0.40, 0.33, 0.22), 0.9, 0.0))
			_solid(at, Vector3(1.3, 1.9, 1.3), yaw, kind)
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
			_solid(at, Vector3(1.85, 0.94, 4.3), yaw, kind)
			_solid(at + Basis(Vector3.UP, yaw) * Vector3(0, 0, cab_z),
				Vector3(1.65, 0.93 + cab_h, cab_len), yaw, kind)
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
			_solid(at, Vector3(2.5, tall, 10.4), yaw, kind)
		"container":
			MeshKit.box(st, Vector3(2.44, 2.6 + DEEP, 6.06), Vector3(0, 1.3, 0) + d)
			for rib in 9:
				MeshKit.box(st, Vector3(2.50, 2.5, 0.10), Vector3(0, 1.3, -2.7 + rib * 0.675))
			var paint := [Color(0.50, 0.20, 0.12), Color(0.14, 0.30, 0.42), Color(0.30, 0.36, 0.24)]
			_mesh(at, yaw, st, MeshKit.mat(paint[_rng.randi() % paint.size()], 0.7, 0.3))
			_solid(at, Vector3(2.44, 2.6, 6.06), yaw, kind)
		"wall":
			# the garden wall of wherever this is
			MeshKit.box(st, Vector3(4.0, 1.25 + DEEP, 0.40), Vector3(0, 0.625, 0) + d)
			MeshKit.box(st, Vector3(4.1, 0.10, 0.50), Vector3(0, 1.28, 0))
			_mesh(at, yaw, st, MeshKit.mat(_masonry(), 0.95, 0.0))
			_solid(at, Vector3(4.0, 1.25, 0.40), yaw, kind)
		"panel":
			# precast concrete fencing, by the kilometre
			for seg in 2:
				MeshKit.box(st, Vector3(1.95, 2.4 + DEEP, 0.16), Vector3(-1.0 + seg * 2.0, 1.2, 0) + d)
			for post in 3:
				MeshKit.box(st, Vector3(0.22, 2.55 + DEEP, 0.26), Vector3(-2.0 + post * 2.0, 1.27, 0) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.60, 0.60, 0.58), 0.95, 0.0))
			_solid(at, Vector3(4.2, 2.4, 0.26), yaw, kind)
		"fence":
			# Boards on two rails. It hides a man completely and stops next
			# to nothing: everything else in a yard was masonry, and there
			# was nothing in town a rifle could be fired through.
			MeshKit.box(st, Vector3(4.0, 1.85 + DEEP, 0.05), Vector3(0, 0.92, 0) + d)
			for post in 3:
				MeshKit.box(st, Vector3(0.10, 1.95 + DEEP, 0.10),
					Vector3(-1.95 + post * 1.95, 0.97, 0.07) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.42, 0.30, 0.19), 0.95, 0.0))
			_solid(at, Vector3(4.0, 1.85, 0.08), yaw, kind)
		"hedge":
			MeshKit.box(st, Vector3(4.0, 1.35 + DEEP, 0.9), Vector3(0, 0.67, 0) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.16, 0.30, 0.14), 1.0, 0.0))
			_solid(at, Vector3(4.0, 1.35, 0.9), yaw, kind)
		"stall":
			# a market stall: a counter to get behind and an awning over it
			MeshKit.box(st, Vector3(2.6, 0.95 + DEEP, 1.0), Vector3(0, 0.47, 0) + d)
			for px in [-1.25, 1.25]:
				for pz in [-0.9, 0.9]:
					MeshKit.box(st, Vector3(0.07, 2.3 + DEEP, 0.07), Vector3(px, 1.15, pz) + d)
			_mesh(at, yaw, st, MeshKit.mat(Color(0.42, 0.32, 0.20), 0.9, 0.0))
			_solid(at, Vector3(2.6, 0.95, 1.0), yaw, kind)
			var counter := _last_mesh
			var aw := MeshKit.begin()
			MeshKit.box(aw, Vector3(3.0, 0.06, 2.3), Vector3(0, 2.32, 0))
			var cloth: Color = {"china": Color(0.70, 0.08, 0.06), "iran": Color(0.16, 0.42, 0.36),
				"france": Color(0.80, 0.74, 0.60), "russia": Color(0.20, 0.30, 0.52)}.get(
				faction, Color(0.64, 0.46, 0.18))
			_mesh(at, yaw, aw, MeshKit.mat(cloth, 0.95, 0.0))
			# the awning goes when the counter does
			_last_mesh.reparent(counter)
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
			_solid(at, size, yaw, kind)
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
			_solid(at, sz, yaw, kind)
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
			_last_mesh = mi
			_solid(at, Vector3(0.5, 3.0, 0.5), 0.0, kind)
		_:
			return false
	stats["props"] = int(stats["props"]) + 1
	props.append([kind, at, yaw])
	return true

## A building with the roof off and the doors gone: four walls, a partition,
## and ways in. The only rooms in town, and so the only place the fight goes
## properly indoors. Walls stand on route grid lines and doors on grid points,
## for the same reason the clutter does.
var _ruin_mat: Material = null

func _ruin(cx: float, cz: float) -> void:
	var o := Vector3(cx, _seat(cx, cz, 6.5), cz)
	if _ruin_mat == null:
		_ruin_mat = MeshKit.mat(_masonry().lightened(0.08), 0.95, 0.0)
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
	stats["ruins"] = int(stats["ruins"]) + 1

func _ruin_wall(st: SurfaceTool, o: Vector3, base: Vector3, along_x: bool, from: float,
		to: float, h: float) -> void:
	if to - from < 0.2:
		return
	var mid: float = (from + to) * 0.5
	var size := Vector3(to - from, h, 0.5) if along_x else Vector3(0.5, h, to - from)
	var at: Vector3 = base + (Vector3(mid, 0, 0) if along_x else Vector3(0, 0, mid))
	# its own mesh, not a part of the building's: a wall that can be driven
	# through has to be able to go without taking the other three with it
	var seg := MeshKit.begin()
	MeshKit.box(seg, size + Vector3(0, DEEP, 0), Vector3(0, (h - DEEP) * 0.5, 0))
	_mesh(at, 0.0, seg, _ruin_mat)
	_solid(at, size, 0.0, "wall")
	if st == null or o == Vector3.INF:
		return

## The ground floor of a town building, opened up.
##
## A town's blocks are solid: one box each, drawn as one box, with nothing to
## go into. The only rooms in a town were the two or three ruins, so a fight
## in the streets stayed in the streets -- most of what stood in it had no
## door at all. Here the bottom storey of the block is taken away (the block
## itself is lifted, roof staying where it was) and a ground floor is built
## under it out of walls: a door on the street side, one at the back and one
## in a side, windows to shoot out of, and a partition across the middle.
##
## The walls are one mesh and belong to the building: nothing drives through
## them, and when the building comes down they go with it.
const STOREY := 3.1
const DOOR_H := 2.25
const DOOR_W := 2.4
const WALL_T := 0.4
const PARTITION_T := 0.14
## The scenery that owns the blocks, given by whoever puts this set down.
var scenery: Node = null
## [structure, how far it was lifted, its ground floor mesh, where it stands,
## first of its wall boxes, one past the last]
var _hollowed: Array = []
var _wall_mats: Dictionary = {}
var _gone_t := 0.0

func _open_buildings() -> void:
	if not is_instance_valid(scenery) or not scenery.has_method("raise_block"):
		return
	var mine := {}
	for id in _boxes:
		mine[id] = true
	for id in Obstacles.ids_in(centre - Vector2(HALF, HALF), centre + Vector2(HALF, HALF)):
		if mine.has(id):
			continue
		_hollow(id)
		if not await _pause():
			return

func _hollow(id: int) -> void:
	var half: Vector2 = Obstacles.half_of(id)
	if minf(half.x, half.y) < 6.0:
		return
	stats["blocks"] = int(stats.get("blocks", 0)) + 1
	var c: Vector3 = Obstacles.centre_of(id)
	var yaw: float = Obstacles.yaw_of(id)
	var bs := Basis(Vector3.UP, yaw)
	# the ground it stands on: too much of a slope and one end of the floor
	# would be a cellar
	var g_lo := 1e9
	var g_hi := -1e9
	for sx in [-1.0, 0.0, 1.0]:
		for sz in [-1.0, 0.0, 1.0]:
			var q: Vector3 = c + bs * Vector3(sx * half.x, 0, sz * half.y)
			var g: float = _ground(q.x, q.z)
			g_lo = minf(g_lo, g)
			g_hi = maxf(g_hi, g)
	if g_hi - g_lo > 1.2 or Obstacles.top_of(id) - g_hi < STOREY + 2.5:
		stats["too_steep"] = int(stats.get("too_steep", 0)) + 1
		return
	var dy: float = g_hi + STOREY - c.y
	var kind: int = scenery.raise_block(c, dy)
	if kind < 0:
		return
	Obstacles.lift(id, dy)
	if not _wall_mats.has(kind):
		_wall_mats[kind] = MeshKit.panelled(scenery.TOWN_WALLS[kind], 0.92, 0.0, 3.2)
	var o := Vector3(c.x, g_lo, c.z)
	var top: float = g_hi + STOREY + 0.15 - g_lo      # into the block above
	var sill: float = g_hi + 1.0 - g_lo
	var lintel: float = g_hi + DOOR_H - g_lo
	var st := MeshKit.begin()
	var first: int = _boxes.size()
	# A partition across the long way, when there is the room for two rooms.
	var long_x: bool = half.x >= half.y
	var parted: bool = maxf(half.x, half.y) > 9.0
	# Which face is the front: the one looking at the nearest street. The
	# back and one side get a door as well; the other side has windows only.
	var to_street := Vector3.ZERO
	var best_d := 1e9
	for line in [-128.0, 0.0, 128.0]:
		var ddx: float = centre.x + line - c.x
		var ddz: float = centre.y + line - c.z
		if absf(ddx) < best_d:
			best_d = absf(ddx)
			to_street = Vector3(signf(ddx), 0, 0)
		if absf(ddz) < best_d:
			best_d = absf(ddz)
			to_street = Vector3(0, 0, signf(ddz))
	var faces: Array = []
	for f in [[true, -1.0], [true, 1.0], [false, -1.0], [false, 1.0]]:
		# a face that runs along x looks out along z, and the other way about
		var n_l := Vector3(0, 0, f[1]) if f[0] else Vector3(f[1], 0, 0)
		faces.append([f[0], f[1], (bs * n_l).dot(to_street)])
	faces.sort_custom(func(a: Array, b: Array) -> bool: return a[2] > b[2])
	# front, a side, a side, back -> front, back, then whichever side
	var order: Array = [faces[0], faces[3], faces[1 + _rng.randi() % 2]]
	var doors := 0
	for f in faces:
		var along_x: bool = f[0]
		var sgn: float = f[1]
		var run: float = half.x if along_x else half.y          # half its length
		var off: float = (half.y if along_x else half.x) - WALL_T * 0.5
		var n_l := Vector3(0, 0, sgn) if along_x else Vector3(sgn, 0, 0)
		var a_l := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var cuts: Array = []            # [where along it, half width, sill]
		if order.has(f):
			# a door, somewhere along it that nothing is standing in front of
			var tries: Array = [0.0, run * 0.45, -run * 0.45, run * 0.25, -run * 0.25]
			if parted and along_x == long_x:
				tries = [run * 0.45, -run * 0.45, run * 0.25, -run * 0.25]
			for u_try in tries:
				# on the route grid, so the men who plan on it can use it
				var w: Vector3 = o + bs * (a_l * float(u_try) + n_l * off)
				var w2 := Vector3(_snap(w.x), 0, _snap(w.z)) - o
				var u: float = clampf((bs.inverse() * w2).dot(a_l),
					-run + DOOR_W * 0.5 + 1.0, run - DOOR_W * 0.5 - 1.0)
				var clear := true
				for step in [0.9, 1.9]:
					var p: Vector3 = o + bs * (a_l * u + n_l * (off + float(step)))
					p.y = _ground(p.x, p.z) + 0.3
					if Obstacles.blocks(p, 0.55) >= 0:
						clear = false
				if clear:
					cuts.append([u, DOOR_W * 0.5, 0.0])
					doors += 1
					break
		# windows every so often along the rest of it
		var pitch: float = 5.5
		var k_n: int = int((run * 2.0 - 3.0) / pitch)
		for k in k_n + 1:
			var wu: float = (float(k) - float(k_n) * 0.5) * pitch
			var room := true
			for cut in cuts:
				if absf(wu - float(cut[0])) < float(cut[1]) + 1.9:
					room = false
			if room and absf(wu) < run - 1.8:
				cuts.append([wu, 0.8, sill])
		cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var from: float = -run
		for cut in cuts:
			var lo: float = float(cut[0]) - float(cut[1])
			_storey_wall(st, o, bs, a_l, n_l * off, from, lo, 0.0, lintel)
			if float(cut[2]) > 0.0:
				_storey_wall(st, o, bs, a_l, n_l * off, lo, lo + float(cut[1]) * 2.0, 0.0,
					float(cut[2]))
			from = lo + float(cut[1]) * 2.0
		_storey_wall(st, o, bs, a_l, n_l * off, from, run, 0.0, lintel)
		# and the wall over all of them, door and window alike
		_storey_wall(st, o, bs, a_l, n_l * off, -run, run, lintel, top)
	if parted:
		var p_a := Vector3(0, 0, 1) if long_x else Vector3(1, 0, 0)
		var p_run: float = (half.y if long_x else half.x) - WALL_T
		var gap: float = p_run * 0.35 * (1.0 if _rng.randf() < 0.5 else -1.0)
		# a stud wall, not masonry: a rifle round goes through it
		_storey_wall(st, o, bs, p_a, Vector3.ZERO, -p_run, gap - DOOR_W * 0.5, 0.0, lintel, PARTITION_T)
		_storey_wall(st, o, bs, p_a, Vector3.ZERO, gap + DOOR_W * 0.5, p_run, 0.0, lintel, PARTITION_T)
		_storey_wall(st, o, bs, p_a, Vector3.ZERO, -p_run, p_run, lintel, top, PARTITION_T)
	var mi := MeshKit.mi(MeshKit.finish(st, _wall_mats[kind]), "GroundFloor")
	add_child(mi)
	mi.global_transform = Transform3D(bs, o)
	_hollowed.append([id, dy, mi, c, first, _boxes.size()])
	stats["interiors"] = int(stats.get("interiors", 0)) + 1
	stats["doors"] = int(stats.get("doors", 0)) + doors

## One length of a ground floor's wall, from `from` to `to` along `along` and
## `y0` to `y1` up it, in the building's own frame.
func _storey_wall(st: SurfaceTool, o: Vector3, bs: Basis, along: Vector3, off: Vector3,
		from: float, to: float, y0: float, y1: float, thick := WALL_T) -> void:
	if to - from < 0.15 or y1 - y0 < 0.1:
		return
	var is_x: bool = absf(along.x) > 0.5
	var span: float = to - from
	var size := Vector3(span, y1 - y0, thick) if is_x else Vector3(thick, y1 - y0, span)
	var mid: Vector3 = off + along * ((from + to) * 0.5)
	# the part that stands on the ground goes a little way into it
	var deep: float = DEEP if y0 <= 0.0 else 0.0
	MeshKit.box(st, size + Vector3(0, deep, 0), mid + Vector3(0, (y0 + y1 - deep) * 0.5, 0))
	var id: int = Obstacles.add_box(o + bs * (mid + Vector3(0, y0, 0)), size.x * 0.5, size.y,
		size.z * 0.5, bs.get_euler().y)
	_boxes.append(id)

## A building that has come down takes its ground floor with it.
func _process(delta: float) -> void:
	_gone_t -= delta
	if _gone_t > 0.0:
		return
	_gone_t = 0.5
	for i in range(_hollowed.size() - 1, -1, -1):
		var h: Array = _hollowed[i]
		if not Obstacles.gone(int(h[0])):
			continue
		for k in range(int(h[4]), int(h[5])):
			Obstacles.remove(_boxes[k])
		if is_instance_valid(h[2]):
			(h[2] as Node).queue_free()
		_hollowed.remove_at(i)

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
## Stood up a little at a time, when nobody is waiting for it.
##
## A town's set is three hundred and twenty nodes -- every car, wall and stall
## its own mesh, because each can be knocked down on its own -- and flying
## toward a town built all of them in one frame: thirty-five milliseconds, the
## worst hitch left in a battle, a mile and more before any of it could be
## seen. With `slow` set the same build, in the same order off the same dice,
## stops for a frame after every couple of dozen pieces. A street fight still
## asks for the whole town at once, because it surveys routes through it
## before the first frame, and gets it: with `slow` off this never waits.
var slow := false
var building := false
var _paced := 0
const PACE := 22

func _pause() -> bool:
	if not slow or get_child_count() - _paced < PACE:
		return true
	await get_tree().process_frame
	if not is_inside_tree():
		return false
	_paced = get_child_count()
	return true

func build(at: Vector2, of_site: Dictionary) -> void:
	building = true
	await _build(at, of_site)
	building = false

func _build(at: Vector2, of_site: Dictionary) -> void:
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
		if not await _pause():
			return
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
		if not await _pause():
			return

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
				if not await _pause():
					return
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
		_prop(["wall", "stack", "crates", "fence", "hedge" if biome != "desert" else "wall",
			"small"][_rng.randi() % 6], ax, az, float(_rng.randi() % 2) * PI * 0.5)
		if not await _pause():
			return
	# Last, so that a door is only cut where nothing has been stood in front
	# of it: the ground floors of the buildings themselves.
	await _open_buildings()

