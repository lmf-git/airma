class_name Obstacles
extends Node3D
## Everything standing on the ground that you can fly into.
##
## Nothing in this game collides through the physics engine -- aeroplanes,
## helicopters and vehicles all sit on `collision_layer = 0` and ask the height
## field where the ground is. That works for the ground and leaves every
## building, hangar, mast and pylon as scenery you pass straight through: you
## could fly a jet through the middle of Rampart City at fifty feet and nothing
## would happen.
##
## Buildings are drawn as MultiMesh batches, so there are no nodes to give
## colliders to in the first place. This keeps the footprints instead -- an
## oriented box per instance, in a coarse spatial hash -- and answers the same
## question the ground does: is there something here. A query is the nine cells
## around a point, which is a handful of boxes however big the map gets.
##
## Real static bodies are kept too, but only for the few dozen structures
## nearest the viewer, so that the things which *do* use physics (ragdolls) have
## something to land against. Those are the LOD part: they follow you and
## nothing else in the world pays for them.

const CELL := 160.0                 # spatial hash cell
const MIN_HEIGHT := 2.5             # below this it is a fence post, not an obstacle
const STRIDE := 8                   # x, ybase, z, hx, height, hz, cos, sin

## Flat on purpose: the inner loop of a query reads this a few thousand times a
## second and an array of dictionaries spends all of it unboxing Variants.
static var _ent := PackedFloat32Array()
static var _dead := PackedByteArray()
static var _cells: Dictionary = {}
static var stats := {"count": 0, "cells": 0}

static func clear() -> void:
	_ent = PackedFloat32Array()
	_dead = PackedByteArray()
	_cells = {}
	stats = {"count": 0, "cells": 0}

static func _key(ci: int, cj: int) -> int:
	return ci * 1048576 + cj

## Take a MultiMesh batch: one box per instance, sized from the source mesh.
static func add_batch(mesh: Mesh, xforms: Array) -> void:
	if mesh == null or xforms.is_empty():
		return
	# The mesh's own size means nothing here: a town block is modelled as a unit
	# cube and given its real dimensions by the instance transform, so testing
	# the source mesh against a height in metres threw out every building in
	# every town and left 199 structures on the whole map. Height is a property
	# of the instance, and it is checked as one below.
	var ab := mesh.get_aabb()
	for t in xforms:
		var xf: Transform3D = t
		var sc := xf.basis.get_scale()
		# The mesh is modelled with its base at y = 0, so the AABB's own
		# position carries any offset the author gave it.
		var hx: float = ab.size.x * 0.5 * sc.x
		var hz: float = ab.size.z * 0.5 * sc.z
		var hy: float = (ab.position.y + ab.size.y) * sc.y
		if hy < MIN_HEIGHT:
			continue
		var yaw: float = xf.basis.get_euler().y
		var o := xf.origin
		var id: int = _dead.size()      # the entry index, not the float offset
		_ent.append_array(PackedFloat32Array([o.x, o.y, o.z, hx, hy, hz,
			cos(yaw), sin(yaw)]))
		_dead.append(0)
		# every cell the footprint's bounding circle touches
		var reach: float = sqrt(hx * hx + hz * hz)
		var lo_i: int = int(floor((o.x - reach) / CELL))
		var hi_i: int = int(floor((o.x + reach) / CELL))
		var lo_j: int = int(floor((o.z - reach) / CELL))
		var hi_j: int = int(floor((o.z + reach) / CELL))
		for cj in range(lo_j, hi_j + 1):
			for ci in range(lo_i, hi_i + 1):
				var k := _key(ci, cj)
				if not _cells.has(k):
					_cells[k] = PackedInt32Array()
				var arr: PackedInt32Array = _cells[k]
				arr.append(id)
				_cells[k] = arr
	stats["count"] = _dead.size()
	stats["cells"] = _cells.size()

## The structure a point is inside, allowing `r` of clearance around it, or -1.
## `r` is the radius of whatever is doing the asking -- a wing, a hull, a
## warhead -- so a wingtip clipping a roof counts.
static func hit(p: Vector3, r := 0.0) -> int:
	if _dead.is_empty():
		return -1
	var ci := int(floor(p.x / CELL))
	var cj := int(floor(p.z / CELL))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var k := _key(ci + di, cj + dj)
			if not _cells.has(k):
				continue
			for id in (_cells[k] as PackedInt32Array):
				if _dead[id] != 0:
					continue
				var b: int = id * STRIDE
				var dy: float = p.y - _ent[b + 1]
				if dy < -r or dy > _ent[b + 4] + r:
					continue
				# into the instance's own frame, where the box is axis aligned
				var dx: float = p.x - _ent[b]
				var dz: float = p.z - _ent[b + 2]
				var c: float = _ent[b + 6]
				var s: float = _ent[b + 7]
				var lx: float = dx * c + dz * s
				var lz: float = -dx * s + dz * c
				if absf(lx) <= _ent[b + 3] + r and absf(lz) <= _ent[b + 5] + r:
					return id
	return -1

## How high the structures at a point stand, or the ground if there are none.
## What a helicopter has to clear to hover over a town.
static func top_at(x: float, z: float) -> float:
	var best := -1e9
	var ci := int(floor(x / CELL))
	var cj := int(floor(z / CELL))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var k := _key(ci + di, cj + dj)
			if not _cells.has(k):
				continue
			for id in (_cells[k] as PackedInt32Array):
				if _dead[id] != 0:
					continue
				var b: int = id * STRIDE
				var dx: float = x - _ent[b]
				var dz: float = z - _ent[b + 2]
				var c: float = _ent[b + 6]
				var s: float = _ent[b + 7]
				var lx: float = dx * c + dz * s
				var lz: float = -dx * s + dz * c
				if absf(lx) <= _ent[b + 3] and absf(lz) <= _ent[b + 5]:
					best = maxf(best, _ent[b + 1] + _ent[b + 4])
	return best

static func centre_of(id: int) -> Vector3:
	var b := id * STRIDE
	return Vector3(_ent[b], _ent[b + 1], _ent[b + 2])

## Take everything inside a blast out of the field. Called by whatever flattens
## the meshes, so the two stay in step -- a building you can no longer see is a
## building you can no longer hit.
static func kill_near(pos: Vector3, radius: float) -> void:
	if _dead.is_empty():
		return
	var reach: int = int(ceil(radius / CELL)) + 1
	var ci := int(floor(pos.x / CELL))
	var cj := int(floor(pos.z / CELL))
	var r2 := radius * radius
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var k := _key(ci + di, cj + dj)
			if not _cells.has(k):
				continue
			for id in (_cells[k] as PackedInt32Array):
				var b: int = id * STRIDE
				var dx: float = _ent[b] - pos.x
				var dz: float = _ent[b + 2] - pos.z
				if dx * dx + dz * dz <= r2:
					_dead[id] = 1

# ------------------------------------------------------------ near colliders
## Real bodies for the structures nearest the viewer. Everything else in the
## world is answered by `hit` and costs nothing until it is asked.
const NEAR := 260.0
const NEAR_MAX := 64

var _near: Array = []
var _near_at := Vector3(1e12, 0, 1e12)

func _ready() -> void:
	for i in NEAR_MAX:
		var sb := StaticBody3D.new()
		# the layer the ragdolls are on, so a body thrown down a street has the
		# buildings to land against rather than falling through them
		sb.collision_layer = 4
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		sb.add_child(cs)
		sb.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(sb)
		_near.append(sb)

## Move the pool to wherever the viewer is. Cheap and idempotent.
func follow(eye: Vector3) -> void:
	if _near_at.distance_squared_to(eye) < 2500.0:
		return
	_near_at = eye
	var found: Array = []
	var reach: int = int(ceil(NEAR / CELL))
	var ci := int(floor(eye.x / CELL))
	var cj := int(floor(eye.z / CELL))
	var seen: Dictionary = {}
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var k := _key(ci + di, cj + dj)
			if not _cells.has(k):
				continue
			for id in (_cells[k] as PackedInt32Array):
				if _dead[id] != 0 or seen.has(id):
					continue
				seen[id] = true
				var b: int = id * STRIDE
				var d := Vector2(_ent[b] - eye.x, _ent[b + 2] - eye.z).length()
				if d < NEAR:
					found.append([d, id])
	found.sort_custom(func(a: Array, c: Array) -> bool: return a[0] < c[0])
	for i in NEAR_MAX:
		var sb: StaticBody3D = _near[i]
		if i >= found.size():
			sb.process_mode = Node.PROCESS_MODE_DISABLED
			sb.position = Vector3(0.0, -100000.0, 0.0)
			continue
		var id2: int = found[i][1]
		var b2: int = id2 * STRIDE
		var cs := sb.get_child(0) as CollisionShape3D
		var box := cs.shape as BoxShape3D
		box.size = Vector3(_ent[b2 + 3] * 2.0, _ent[b2 + 4], _ent[b2 + 5] * 2.0)
		cs.position = Vector3(0.0, _ent[b2 + 4] * 0.5, 0.0)
		sb.position = Vector3(_ent[b2], _ent[b2 + 1], _ent[b2 + 2])
		sb.rotation = Vector3(0.0, atan2(_ent[b2 + 7], _ent[b2 + 6]), 0.0)
		sb.process_mode = Node.PROCESS_MODE_INHERIT
