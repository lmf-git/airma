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
## oriented box per instance, in a spatial hash -- and answers the same
## question the ground does: is there something here. A query looks only in the
## cells its own footprint overlaps, which is a handful of boxes however big the
## map gets.
##
## Real static bodies are kept too, but only for the few dozen structures
## nearest the viewer, so that the things which *do* use physics (ragdolls) have
## something to land against. Those are the LOD part: they follow you and
## nothing else in the world pays for them.

## The spatial hash cell. It was 160 m, and every query walked the nine cells
## round it: a 480 m square, which in a town is the whole town -- 394 boxes
## tested for every step a soldier took, for each foot he planted and for every
## tick of every bullet in the air. At 24 m a man's query is one cell and a
## few boxes.
const CELL := 24.0
const MIN_HEIGHT := 2.5             # below this it is a fence post, not an obstacle
const STRIDE := 8                   # x, ybase, z, hx, height, hz, cos, -sin

## A box's turn is kept as cos and *minus* sin of its yaw. Every query takes
## a point into the box's frame as (dx c + dz s, -dx s + dz c), and with the
## plain sine that frame is the mesh's turned the other way: Godot turns a
## mesh's x axis to (cos, -sin), not (cos, sin). Anything set at an angle --
## a wall across a corner, a parked car, a block on a skewed street -- had its
## box mirrored about the street: rounds went through the corner you could
## see and stopped on air where it was not, and the same for men and tanks.
## Measured on the town's own props, 18 of 76 points well inside the drawn
## meshes were inside their boxes. Stored this way, every query is the mesh's.
static func _turn(yaw: float) -> PackedFloat32Array:
	return PackedFloat32Array([cos(yaw), -sin(yaw)])
const MAX_SEGMENT := 6000.0         # the longest line `segment` will walk

## Flat on purpose: the inner loop of a query reads this a few thousand times a
## second and an array of dictionaries spends all of it unboxing Variants.
static var _ent := PackedFloat32Array()
## What each entry is now: LIVE, GONE, or SOFT. A soft entry stops rounds and
## lines of sight and nothing else -- a parked lorry, a low wall, a kiosk, a
## planter. Anything that moves through the world asks `hit`, `blocks`,
## `top_at` or `floor_under`, which take only LIVE; `segment` takes both.
## They were left out of the field altogether, so a rifleman crouched behind a
## car was behind nothing, and every round went through it.
static var _dead := PackedByteArray()
const LIVE := 0
const GONE := 1
const SOFT := 2
static var _cells: Dictionary = {}
static var stats := {"count": 0, "cells": 0}
## Every entry again, laid out the same way, in the chart the world was built
## on: see `Sim.boot_affine`. `_ent` is these carried into the chart there is
## now. Before the chart has ever moved the two are the same numbers.
static var _laid := PackedFloat32Array()

## Where the field has changed since it was laid, for whatever keeps its own
## picture of it -- the street fight's route grids -- to bring that picture up
## to date: one rectangle of ground (x0, z0, x1, z1) per change, the newest
## last, numbered from `edit_base`. Something reading it keeps the number it
## has read up to; one that has fallen behind the oldest kept starts again.
## The men's routes were surveyed once, as the match began, and a house that
## went up after that, a heap where a block came down or the wreck of a tank
## was not on them: men were sent into and through all three.
static var edits: Array = []
static var edit_base := 0
const EDITS_KEEP := 4096

static func _edited(id: int) -> void:
	var b: int = id * STRIDE
	var reach: float = sqrt(_ent[b + 3] * _ent[b + 3] + _ent[b + 5] * _ent[b + 5])
	edits.append(Rect2(_ent[b] - reach, _ent[b + 2] - reach, reach * 2.0, reach * 2.0))
	if edits.size() > EDITS_KEEP:
		var drop: int = EDITS_KEEP >> 1
		edits = edits.slice(drop)
		edit_base += drop

## How many changes there have been, all told.
static func edit_count() -> int:
	return edit_base + edits.size()

## How many times the field has been cleared. Anything that put its own box in
## and wants it kept compares this with the count when it did.
static var generation := 0

static func clear() -> void:
	generation += 1
	edits.clear()
	edit_base += 1 << 20      # anyone reading starts again
	_light.clear()
	_squash.clear()
	_rubble_of.clear()
	_ent = PackedFloat32Array()
	_laid = PackedFloat32Array()
	_dead = PackedByteArray()
	_cells = {}
	stats = {"count": 0, "cells": 0}

## How far the chart's own axes turn between the chart the world was built on
## and the one there is now, at `p` in the first: what a yaw laid down there is
## short of, here.
static func _turn_at(p: Vector3) -> float:
	var x: Vector3 = Sim.boot_affine(p).basis.x
	return atan2(-x.z, x.x)

## Keep the entry just added in the chart the world was built on too.
static func _lay_last() -> void:
	var b: int = _ent.size() - STRIDE
	if not Sim.off_boot_chart():
		_laid.append_array(_ent.slice(b))
		return
	var p: Vector3 = Sim.world_to_boot(Vector3(_ent[b], _ent[b + 1], _ent[b + 2]))
	var yaw: float = atan2(-_ent[b + 7], _ent[b + 6]) - _turn_at(p)
	_laid.append_array(PackedFloat32Array([p.x, p.y, p.z, _ent[b + 3], _ent[b + 4],
		_ent[b + 5]]))
	_laid.append_array(_turn(yaw))

## File one entry under every cell its footprint's bounding circle touches.
static func _file(id: int) -> void:
	var b: int = id * STRIDE
	var hx: float = _ent[b + 3]
	var hz: float = _ent[b + 5]
	var reach: float = sqrt(hx * hx + hz * hz)
	var ox: float = _ent[b]
	var oz: float = _ent[b + 2]
	for cj in range(int(floor((oz - reach) / CELL)), int(floor((oz + reach) / CELL)) + 1):
		for ci in range(int(floor((ox - reach) / CELL)), int(floor((ox + reach) / CELL)) + 1):
			var k := _key(ci, cj)
			var arr: PackedInt32Array = _cells.get(k, PackedInt32Array())
			arr.append(id)
			_cells[k] = arr

## The chart has moved: carry every entry into it.
##
## The field is filed by where things are, and where things are is numbered
## from the middle of the chart -- so after a move every box was still filed,
## and still standing, at its old numbers: an invisible town of walls a
## hundred and fifty kilometres from the one you could see, and nothing at all
## where the buildings were drawn. Worked from `_laid` every time, so moving
## the chart there and back puts every box exactly where it began.
##
## Carried a few kilometres of ground at a time, each patch by one transform
## worked out at its middle, which is right to a centimetre across the patch
## and costs one transform per patch rather than per box.
const PATCH := 3000.0

static func recharted() -> void:
	var n: int = _dead.size()
	if _laid.size() != _ent.size():
		return
	var patches := {}
	for id in n:
		var b: int = id * STRIDE
		var bx: float = _laid[b]
		var bz: float = _laid[b + 2]
		var key := _key(int(floor(bx / PATCH)), int(floor(bz / PATCH)))
		var pa: Variant = patches.get(key)
		if pa == null:
			var c := Vector3((floor(bx / PATCH) + 0.5) * PATCH, 0.0,
				(floor(bz / PATCH) + 0.5) * PATCH)
			var a: Transform3D = Sim.boot_affine(c)
			pa = [a, atan2(-a.basis.x.z, a.basis.x.x)]
			patches[key] = pa
		var xf: Transform3D = (pa as Array)[0]
		var w: Vector3 = xf * Vector3(bx, _laid[b + 1], bz)
		var yaw: float = atan2(-_laid[b + 7], _laid[b + 6]) + float((pa as Array)[1])
		_ent[b] = w.x
		_ent[b + 1] = w.y
		_ent[b + 2] = w.z
		_ent[b + 6] = cos(yaw)
		_ent[b + 7] = -sin(yaw)
	_cells = {}
	for id2 in n:
		_file(id2)
	stats["cells"] = _cells.size()

## Room for a cell index either way of 2^23, which at 24 m is two hundred
## thousand kilometres: the fields are seventeen thousand out, and at the old
## 2^20 their rows would have run into one another.
static func _key(ci: int, cj: int) -> int:
	return ci * 16777216 + cj

## Take a MultiMesh batch: one box per instance, sized from the source mesh.
## `min_h` lets a caller register something shorter than the general rule
## allows. The rule exists so a scattering of bollards and signs does not fill
## the obstacle field with things nothing could hit; a fence is different,
## because it is a continuous line rather than a scattering, and an aeroplane
## that runs into one has run into all of it.
##
## Below `min_h` and above `soft_from` an instance is SOFT: a round stops on
## it, nothing else does. `all_soft` makes every instance soft whatever its
## height, for street furniture that a tank knocks over rather than stops at.
## Returns the entry for each instance, -1 where nothing was registered.
static func add_batch(mesh: Mesh, xforms: Array, min_h := MIN_HEIGHT, soft_from := 0.45,
		all_soft := false, foot := AABB()) -> PackedInt32Array:
	var ids := PackedInt32Array()
	if mesh == null or xforms.is_empty():
		return ids
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
		# Across, the caller's footprint if it gave one. The whole mesh's box
		# is the right height and can be the wrong width: a town block's roof
		# overhangs its walls by two per cent each way, and taken from the
		# mesh the obstacle did too -- all the way down to the street. Forty
		# centimetres of invisible wall in front of every face of a twenty
		# metre block, and at every corner a post of it that rounds struck
		# going past what anyone could see was the edge of the building.
		var fx: float = (foot.size.x if foot.size.x > 0.0 else ab.size.x) * 0.5
		var fz: float = (foot.size.z if foot.size.z > 0.0 else ab.size.z) * 0.5
		var hx: float = fx * sc.x
		var hz: float = fz * sc.z
		var hy: float = (ab.position.y + ab.size.y) * sc.y
		var state := LIVE
		if all_soft or hy < min_h:
			if hy < soft_from:
				ids.append(-1)
				continue
			state = SOFT
		var yaw: float = xf.basis.get_euler().y
		var o := xf.origin
		var id: int = _dead.size()      # the entry index, not the float offset
		ids.append(id)
		_ent.append_array(PackedFloat32Array([o.x, o.y, o.z, hx, hy, hz]))
		_ent.append_array(_turn(yaw))
		_lay_last()
		_dead.append(state)
		_edited(id)
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
	return ids

## The structure a point is inside, allowing `r` of clearance around it, or -1.
## `r` is the radius of whatever is doing the asking -- a wing, a hull, a
## warhead -- so a wingtip clipping a roof counts.
##
## Only the cells the query's own square overlaps. Every box is filed under
## each cell its bounding circle touches, so a box that could contain a point
## padded by `r` is filed in at least one cell within `r` of it.
static func hit(p: Vector3, r := 0.0) -> int:
	if _dead.is_empty():
		return -1
	for cj in range(int(floor((p.z - r) / CELL)), int(floor((p.z + r) / CELL)) + 1):
		for ci in range(int(floor((p.x - r) / CELL)), int(floor((p.x + r) / CELL)) + 1):
			var cell: Variant = _cells.get(_key(ci, cj))
			if cell == null:
				continue
			for id in (cell as PackedInt32Array):
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

## One box that is not part of a MultiMesh batch: a barricade, a wrecked car, a
## length of wall. Returns the entry, so whoever put it there can take it away
## again with `remove` when the match that wanted it is over.
static func add_box(origin: Vector3, half_x: float, height: float, half_z: float,
		yaw := 0.0) -> int:
	var id: int = _dead.size()
	_ent.append_array(PackedFloat32Array([origin.x, origin.y, origin.z, half_x,
		height, half_z]))
	_ent.append_array(_turn(yaw))
	_lay_last()
	_dead.append(0)
	_file(id)
	_edited(id)
	stats["count"] = _dead.size()
	stats["cells"] = _cells.size()
	return id

static func remove(id: int) -> void:
	if id >= 0 and id < _dead.size():
		_dead[id] = GONE
		_edited(id)

## The same question as `hit`, asked by something standing on the ground rather
## than flying through the air. `hit` pads the box by `r` in every direction,
## which is right for a wingtip and wrong for a man: it makes a waist-high wall
## as tall as he can jump plus his own shoulder width, so nothing could ever be
## vaulted. Here `r` is his width and his feet are a point.
static func blocks(p: Vector3, r: float) -> int:
	if _dead.is_empty():
		return -1
	for cj in range(int(floor((p.z - r) / CELL)), int(floor((p.z + r) / CELL)) + 1):
		for ci in range(int(floor((p.x - r) / CELL)), int(floor((p.x + r) / CELL)) + 1):
			var cell: Variant = _cells.get(_key(ci, cj))
			if cell == null:
				continue
			for id in (cell as PackedInt32Array):
				if _dead[id] != 0:
					continue
				var b: int = id * STRIDE
				var dy: float = p.y - _ent[b + 1]
				# under it by more than his own height is walking beneath it:
				# a crane's jib, a scaffold deck
				if dy < -1.85 or dy >= _ent[b + 4] - 0.02:
					continue
				var dx: float = p.x - _ent[b]
				var dz: float = p.z - _ent[b + 2]
				var c: float = _ent[b + 6]
				var s: float = _ent[b + 7]
				var lx: float = dx * c + dz * s
				var lz: float = -dx * s + dz * c
				if absf(lx) <= _ent[b + 3] + r and absf(lz) <= _ent[b + 5] + r:
					return id
	return -1

## How far along a segment the first structure is, as a fraction of it, or 1.0
## if the way is clear. This is what stops a bullet, and what decides whether
## one man can see another: a slab test against each box near the line, so a
## thin wall stops a round that would have stepped clean over it between ticks.
##
## What it met is left in `seg_id`, with `seg_exit` -- how far along the same
## line it comes out the other side, which may be past the end of it -- and
## `seg_soft`. A round that can go through things asks how much there is to
## go through.
## Entries that are a great deal less to go through than their size: a hedge,
## a car's bodywork, a board fence. They count as soft to a round passing
## through and as solid to everything else.
static var _light := {}

static func set_light(id: int) -> void:
	_light[id] = true

static func is_light(id: int) -> bool:
	return _light.has(id)

static var seg_id := -1
static var seg_exit := 1.0
static var seg_soft := false

static func segment(from: Vector3, to_in: Vector3) -> float:
	seg_id = -1
	if _dead.is_empty():
		return 1.0
	# Never further than this. The cells are walked along the line, and a
	# caller asking about a target in another country -- which a tank crew
	# scanning the whole contact list does -- was asking for seventy thousand
	# cells each way. Nothing built stops a line of sight that long anyway;
	# the curve of the ground does.
	var to := to_in
	var full: float = from.distance_to(to_in)
	# Something that has left the world -- an aeroplane whose physics has gone
	# to infinity on its way into a hillside -- has a position that is not a
	# number, and a line to it has no length to walk. Asked anyway, the walk
	# below ran for ever, and the match stopped with it.
	if not is_finite(full) or not from.is_finite() or not to_in.is_finite():
		return 1.0
	var part := 1.0
	if full > MAX_SEGMENT:
		part = MAX_SEGMENT / full
		to = from.lerp(to_in, part)
	var best := 1.0
	var hit_id := -1
	var hit_exit := 1.0
	var d := to - from
	# The cells the line actually passes through, in order along it, and
	# nothing either side. Every box is filed under each cell its bounding
	# circle touches, so wherever a box meets the line, the cell holding that
	# point is one of these and the box is filed there. In order, so once the
	# nearest wall found is nearer than the next cell begins, nothing further
	# along can beat it and the walk stops -- a bullet step, a few metres long,
	# is one or two cells and is over.
	#
	# It was a walk of samples with the nine cells round each, collected into
	# two dictionaries allocated per call and then every box in them tested:
	# with 160 m cells, the whole of a town for every tick of every round.
	var ci := int(floor(from.x / CELL))
	var cj := int(floor(from.z / CELL))
	var ce := int(floor(to.x / CELL))
	var cje := int(floor(to.z / CELL))
	var si: int = 1 if d.x > 0.0 else -1
	var sj: int = 1 if d.z > 0.0 else -1
	# where along the line (as a fraction of it) the next x and z boundaries are
	var tmx := INF
	var tdx := INF
	if absf(d.x) > 1e-9:
		tmx = ((float(ci) + (1.0 if si > 0 else 0.0)) * CELL - from.x) / d.x
		tdx = CELL / absf(d.x)
	var tmz := INF
	var tdz := INF
	if absf(d.z) > 1e-9:
		tmz = ((float(cj) + (1.0 if sj > 0 else 0.0)) * CELL - from.z) / d.z
		tdz = CELL / absf(d.z)
	var t_in := 0.0
	# More than the line can cross, as a guard against a walk that never
	# reaches its last cell through rounding: MAX_SEGMENT is 250 cells each way.
	for _guard in 1100:
		if t_in > best:
			break
		var cell: Variant = _cells.get(_key(ci, cj))
		if cell != null:
			for id in (cell as PackedInt32Array):
				# soft as well as live: a round stops on a car
				if _dead[id] == GONE:
					continue
				var b: int = id * STRIDE
				var c: float = _ent[b + 6]
				var s: float = _ent[b + 7]
				var ox: float = from.x - _ent[b]
				var oz: float = from.z - _ent[b + 2]
				# origin and direction in the box's own frame
				var px: float = ox * c + oz * s
				var pz: float = -ox * s + oz * c
				var py: float = from.y - _ent[b + 1]
				var vx: float = d.x * c + d.z * s
				var vz: float = -d.x * s + d.z * c
				var t0 := 0.0
				var t1: float = best
				var x1 := INF
				var hx: float = _ent[b + 3]
				var hz: float = _ent[b + 5]
				var hy: float = _ent[b + 4]
				# x slab
				if absf(vx) < 1e-7:
					if absf(px) > hx:
						continue
				else:
					var a: float = (-hx - px) / vx
					var e: float = (hx - px) / vx
					t0 = maxf(t0, minf(a, e))
					t1 = minf(t1, maxf(a, e))
					x1 = minf(x1, maxf(a, e))
					if t0 > t1:
						continue
				# z slab
				if absf(vz) < 1e-7:
					if absf(pz) > hz:
						continue
				else:
					var a2: float = (-hz - pz) / vz
					var e2: float = (hz - pz) / vz
					t0 = maxf(t0, minf(a2, e2))
					t1 = minf(t1, maxf(a2, e2))
					x1 = minf(x1, maxf(a2, e2))
					if t0 > t1:
						continue
				# y slab, base to roof
				if absf(d.y) < 1e-7:
					if py < 0.0 or py > hy:
						continue
				else:
					var a3: float = (0.0 - py) / d.y
					var e3: float = (hy - py) / d.y
					t0 = maxf(t0, minf(a3, e3))
					t1 = minf(t1, maxf(a3, e3))
					x1 = minf(x1, maxf(a3, e3))
					if t0 > t1:
						continue
				best = t0
				hit_id = id
				hit_exit = x1
		if ci == ce and cj == cje:
			break
		# into whichever neighbour the line crosses into first
		if tmx < tmz:
			t_in = tmx
			tmx += tdx
			ci += si
		else:
			t_in = tmz
			tmz += tdz
			cj += sj
		if t_in > 1.0:
			break
	# as a fraction of the line that was asked about, not the part looked at
	if best < 1.0:
		seg_id = hit_id
		seg_exit = hit_exit * part
		seg_soft = hit_id >= 0 and (_dead[hit_id] == SOFT or _light.has(hit_id))
	return 1.0 if best >= 1.0 else best * part

## How high the structures at a point stand, or the ground if there are none.
## What a helicopter has to clear to hover over a town.
static func top_at(x: float, z: float) -> float:
	var best := -1e9
	# a point is inside a box only in the one cell it is in
	var cell: Variant = _cells.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cell == null:
		return best
	for id in (cell as PackedInt32Array):
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

## The floor a man at height `y` would be standing on here: the highest roof
## that is not above him. `top_at` answers "how tall is what is here", which is
## the right question for a helicopter and the wrong one for somebody walking
## underneath a scaffold -- it puts him on top of it.
static func floor_under(x: float, z: float, y: float) -> float:
	# a bridge deck is a floor too, for whoever is up at its level
	var best: float = Sim.roads.bridge_floor(x, z, y)
	var cell: Variant = _cells.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cell == null:
		return best
	for id in (cell as PackedInt32Array):
		if _dead[id] != 0:
			continue
		var b: int = id * STRIDE
		var top: float = _ent[b + 1] + _ent[b + 4]
		if top > y + 0.55 or top <= best:
			continue
		var dx: float = x - _ent[b]
		var dz: float = z - _ent[b + 2]
		var c: float = _ent[b + 6]
		var s: float = _ent[b + 7]
		if absf(dx * c + dz * s) <= _ent[b + 3] and absf(-dx * s + dz * c) <= _ent[b + 5]:
			best = top
	return best

## The highest top, here, of anything that starts below `below`: what a body
## going over at that height has to clear. `floor_under` takes anything whose
## top is low enough and does not ask where it starts, so the wall *over* a
## window -- which starts above a man's head and ends a metre above that --
## counted as something to vault, and no window could be got through.
static func clear_over(x: float, z: float, below: float) -> float:
	var best := -1e9
	var cell: Variant = _cells.get(_key(int(floor(x / CELL)), int(floor(z / CELL))))
	if cell == null:
		return best
	for id in (cell as PackedInt32Array):
		if _dead[id] != 0:
			continue
		var b: int = id * STRIDE
		if _ent[b + 1] >= below:
			continue
		var top: float = _ent[b + 1] + _ent[b + 4]
		if top <= best:
			continue
		var dx: float = x - _ent[b]
		var dz: float = z - _ent[b + 2]
		var c: float = _ent[b + 6]
		var s: float = _ent[b + 7]
		if absf(dx * c + dz * s) <= _ent[b + 3] and absf(-dx * s + dz * c) <= _ent[b + 5]:
			best = top
	return best

## Which face of a structure a point is against, and where on it: the outward
## normal, how far along the face the point is, and how long the face is either
## side of its middle. What somebody climbing it needs to know.
static func face_of(id: int, p: Vector3) -> Dictionary:
	var b := id * STRIDE
	var c: float = _ent[b + 6]
	var s: float = _ent[b + 7]
	var dx: float = p.x - _ent[b]
	var dz: float = p.z - _ent[b + 2]
	var lx: float = dx * c + dz * s
	var lz: float = -dx * s + dz * c
	var hx: float = _ent[b + 3]
	var hz: float = _ent[b + 5]
	var nx := 0.0
	var nz := 0.0
	var along := 0.0
	var half := 0.0
	var off := 0.0
	if hx - absf(lx) < hz - absf(lz):
		nx = signf(lx) if lx != 0.0 else 1.0
		along = lz
		half = hz
		off = hx
	else:
		nz = signf(lz) if lz != 0.0 else 1.0
		along = lx
		half = hx
		off = hz
	var n := Vector3(nx * c - nz * s, 0.0, nx * s + nz * c)
	var centre := Vector3(_ent[b], 0.0, _ent[b + 2])
	return {"n": n, "along": along, "half": half, "foot": centre + n * off,
		"base": _ent[b + 1], "top": _ent[b + 1] + _ent[b + 4]}

## Every structure standing inside a rectangle of ground, as footprints:
## [centre, half extents, yaw, height]. For drawing them -- a map zoomed in
## far enough to show a street has to show what the street runs between.
static func footprints(lo: Vector2, hi: Vector2, limit := 1500) -> Array:
	var out: Array = []
	for id in _ids_in(lo, hi):
		var b: int = id * STRIDE
		out.append([Vector2(_ent[b], _ent[b + 2]), Vector2(_ent[b + 3], _ent[b + 5]),
			atan2(-_ent[b + 7], _ent[b + 6]), _ent[b + 4]])
		if out.size() >= limit:
			return out
	return out

## Every standing structure filed in a rectangle of ground, once each. A
## rectangle with more cells in it than there are cells filled -- a map zoomed
## out over kilometres, a big blast -- is cheaper as one pass over every box
## than as a lookup per cell, most of which are empty.
static func _ids_in(lo: Vector2, hi: Vector2, soft := false) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i0 := int(floor(lo.x / CELL))
	var i1 := int(floor(hi.x / CELL))
	var j0 := int(floor(lo.y / CELL))
	var j1 := int(floor(hi.y / CELL))
	if (i1 - i0 + 1) * (j1 - j0 + 1) > _cells.size():
		for id in _dead.size():
			if _dead[id] == GONE or (_dead[id] == SOFT and not soft):
				continue
			var b: int = id * STRIDE
			var reach: float = sqrt(_ent[b + 3] * _ent[b + 3] + _ent[b + 5] * _ent[b + 5])
			if _ent[b] + reach < lo.x or _ent[b] - reach > hi.x \
					or _ent[b + 2] + reach < lo.y or _ent[b + 2] - reach > hi.y:
				continue
			out.append(id)
		return out
	var seen: Dictionary = {}
	for cj in range(j0, j1 + 1):
		for ci in range(i0, i1 + 1):
			var cell: Variant = _cells.get(_key(ci, cj))
			if cell == null:
				continue
			for id in (cell as PackedInt32Array):
				if _dead[id] == GONE or (_dead[id] == SOFT and not soft) or seen.has(id):
					continue
				seen[id] = true
				out.append(id)
	return out

## Every standing structure filed in a rectangle of ground.
static func ids_in(lo: Vector2, hi: Vector2) -> PackedInt32Array:
	return _ids_in(lo, hi)

static func gone(id: int) -> bool:
	return id < 0 or id >= _dead.size() or _dead[id] == GONE

## Half the footprint of one structure, in its own frame, and which way that
## frame is turned.
static func half_of(id: int) -> Vector2:
	var b := id * STRIDE
	return Vector2(_ent[b + 3], _ent[b + 5])

static func yaw_of(id: int) -> float:
	var b := id * STRIDE
	return atan2(-_ent[b + 7], _ent[b + 6])

## Take the bottom `dy` of a structure away and leave the rest standing where
## it was: its roof does not move. What is left is a box that begins above the
## ground, which every query here already understands -- a man walks under it
## the way he walks under a scaffold deck. Negative puts it back.
static func lift(id: int, dy: float) -> void:
	var b := id * STRIDE
	_ent[b + 1] += dy
	_ent[b + 4] -= dy
	_edited(id)
	if b + 4 < _laid.size():
		_laid[b + 1] += dy
		_laid[b + 4] -= dy

## The height of one structure's roof, in the world.
static func top_of(id: int) -> float:
	var b := id * STRIDE
	return _ent[b + 1] + _ent[b + 4]

## The shortest move across the ground that takes a circle of radius `r` at
## `p` clear of box `id`: out through whichever face of the footprint is
## nearest, not away from its middle. Away from the middle is the wrong way for
## anything long -- along the wall of a terrace rather than out of it. Zero if
## the circle is already clear.
static func push_out(id: int, p: Vector3, r: float) -> Vector3:
	var b := id * STRIDE
	var c: float = _ent[b + 6]
	var s: float = _ent[b + 7]
	var dx: float = p.x - _ent[b]
	var dz: float = p.z - _ent[b + 2]
	var lx: float = dx * c + dz * s
	var lz: float = -dx * s + dz * c
	var px: float = _ent[b + 3] + r - absf(lx)
	var pz: float = _ent[b + 5] + r - absf(lz)
	if px <= 0.0 or pz <= 0.0:
		return Vector3.ZERO
	var mx := 0.0
	var mz := 0.0
	if px < pz:
		mx = (signf(lx) if lx != 0.0 else 1.0) * px
	else:
		mz = (signf(lz) if lz != 0.0 else 1.0) * pz
	return Vector3(mx * c - mz * s, 0.0, mx * s + mz * c)

static func centre_of(id: int) -> Vector3:
	var b := id * STRIDE
	return Vector3(_ent[b], _ent[b + 1], _ent[b + 2])

## What a blast may bring down, and how much of it is left as rubble: the
## fraction of its height the heap stands. Only what something draws coming
## down is registered -- a town's blocks, the props in its streets. Everything
## else in the field used to be taken out by any blast in reach as well, and
## stood there drawn and whole with nothing in it: a fence, a control tower, a
## block of flats you could walk and shoot through.
static var _squash := {}
## A structure brought down -> the heap left where it stood.
static var _rubble_of := {}

static func set_breakable(id: int, squash: float) -> void:
	if id >= 0 and id < _dead.size():
		_squash[id] = squash

## Where a structure stood, a heap the height of what is drawn there now: low,
## on the ground, solid. It was nothing at all, so the wreck of a block was
## something you walked through and a round went through at knee height.
static func _leave_rubble(id: int, squash: float) -> void:
	var b: int = id * STRIDE
	var x: float = _ent[b]
	var z: float = _ent[b + 2]
	# on the ground, whatever the box began at: a block with a ground floor
	# opened up in it starts a storey up, and its heap does not
	var ground: float = Sim.height_at(x, z)
	var whole: float = _ent[b + 1] + _ent[b + 4] - ground
	var h: float = whole * squash
	if whole > 4.0:
		h -= 0.4                         # the block sinks into its footprint
	if h < 0.35:
		return
	var rid := add_box(Vector3(x, ground - 0.3, z), _ent[b + 3] * 1.04, h + 0.3,
		_ent[b + 5] * 1.04, yaw_of(id))
	_rubble_of[id] = rid

## The heap a structure left, or -1.
static func rubble_of(id: int) -> int:
	return int(_rubble_of.get(id, -1))

## Take everything inside a blast out of the field. Called by whatever flattens
## the meshes, so the two stay in step -- a building you can no longer see is a
## building you can no longer hit.
static func kill_near(pos: Vector3, radius: float) -> void:
	if _dead.is_empty():
		return
	var r2 := radius * radius
	for id in _ids_in(Vector2(pos.x - radius, pos.z - radius),
			Vector2(pos.x + radius, pos.z + radius), true):
		if not _squash.has(id) or _dead[id] == GONE:
			continue
		var b: int = id * STRIDE
		var dx: float = _ent[b] - pos.x
		var dz: float = _ent[b + 2] - pos.z
		if dx * dx + dz * dz <= r2:
			_dead[id] = GONE
			_edited(id)
			_leave_rubble(id, float(_squash[id]))

# ------------------------------------------------------------ near colliders
## Real bodies for the structures nearest the viewer. Everything else in the
## world is answered by `hit` and costs nothing until it is asked.
const NEAR := 260.0
const NEAR_MAX := 64

var _near: Array = []
var _near_at := Vector3(1e12, 0, 1e12)

## The road bridges' decks, the same way: a box for each span between two
## stations -- the running surface and the girder under it, as `Scenery` draws
## them -- for the spans within reach of the viewer, and nothing for the rest.
## Nothing that walks or drives needs them; men and vehicles stand on a deck
## by `Sim.roads.bridge_floor`, which is exact. What needs them is the physics: a man
## killed on a viaduct went down as a ragdoll onto a patch of ground laid at
## the height of the valley floor, and fell through the deck to it.
const SPAN_NEAR := 320.0
const SPAN_MAX := 48
var _spans: Array = []
## Every span on the map as [centre, basis, length], worked out once per set of
## bridges: the pool only picks from it.
var _span_all: Array = []
var _span_src: Array = []
## Where a test has put the viewer for the pools, whatever the camera says:
## off while x is out at 1e12.
var _pin := Vector3(1e12, 0.0, 1e12)

## Hold the pools at `eye` (a test's, not the camera's); `unpin` lets go.
func pin(eye: Vector3) -> void:
	_pin = eye
	follow(eye)

func unpin() -> void:
	_pin = Vector3(1e12, 0.0, 1e12)

func _ready() -> void:
	for i in SPAN_MAX:
		var sb := StaticBody3D.new()
		sb.name = "Span%d" % i
		sb.collision_layer = 4
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		sb.add_child(cs)
		sb.process_mode = Node.PROCESS_MODE_DISABLED
		sb.position = Vector3(0.0, -100000.0, 0.0)
		add_child(sb)
		_spans.append(sb)
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
func follow(eye_in: Vector3) -> void:
	var eye: Vector3 = _pin if _pin.x < 1e11 else eye_in
	var decks_moved: bool = not is_same(_span_src, Sim.roads.road_bridges)
	if _near_at.distance_squared_to(eye) < 2500.0 and not decks_moved:
		return
	_near_at = eye
	_follow_spans(eye)
	var found: Array = []
	for id in _ids_in(Vector2(eye.x - NEAR, eye.z - NEAR), Vector2(eye.x + NEAR, eye.z + NEAR)):
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
		sb.rotation = Vector3(0.0, atan2(-_ent[b2 + 7], _ent[b2 + 6]), 0.0)
		sb.process_mode = Node.PROCESS_MODE_INHERIT

## Every span of every road bridge as a box: [centre, basis, length]. The deck
## is drawn station to station, each end panel lapping `Sim.roads.BRIDGE_LAP` past
## its abutment, and sloped with the profile -- the same panels `Scenery`
## builds, so the body is where the deck is seen.
func _index_spans() -> void:
	_span_src = Sim.roads.road_bridges
	_span_all = []
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2 or ys.size() != pts.size():
			continue
		var last := pts.size() - 2
		for i in pts.size() - 1:
			var a2: Vector2 = pts[i]
			var c2: Vector2 = pts[i + 1]
			var run := a2.distance_to(c2)
			if run < 0.5:
				continue
			var dir := (c2 - a2) / run
			if i == 0:
				a2 -= dir * Sim.roads.BRIDGE_LAP
			if i == last:
				c2 += dir * Sim.roads.BRIDGE_LAP
			var ta := Vector3(a2.x, ys[i] - Sim.planet_drop(a2.x, a2.y), a2.y)
			var tc := Vector3(c2.x, ys[i + 1] - Sim.planet_drop(c2.x, c2.y), c2.y)
			var fwd := (tc - ta).normalized()
			var across := Vector3(dir.y, 0.0, -dir.x)
			var up := fwd.cross(across).normalized()
			var turn := Basis(across, up, fwd)
			var centre := (ta + tc) * 0.5 - up * (Sim.roads.BRIDGE_GIRDER * 0.5)
			_span_all.append([centre, turn, ta.distance_to(tc)])

## The spans nearest the viewer get the bodies; the rest are switched off.
func _follow_spans(eye: Vector3) -> void:
	if not is_same(_span_src, Sim.roads.road_bridges):
		_index_spans()
	var found: Array = []
	for k in _span_all.size():
		var sp: Array = _span_all[k]
		var c: Vector3 = sp[0]
		# to the nearer end of the span, on the flat
		var d: float = maxf(Vector2(c.x - eye.x, c.z - eye.z).length() - float(sp[2]) * 0.5, 0.0)
		if d < SPAN_NEAR:
			found.append([d, k])
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in SPAN_MAX:
		var sb: StaticBody3D = _spans[i]
		if i >= found.size():
			sb.process_mode = Node.PROCESS_MODE_DISABLED
			sb.position = Vector3(0.0, -100000.0, 0.0)
			continue
		var sp2: Array = _span_all[found[i][1]]
		var box := (sb.get_child(0) as CollisionShape3D).shape as BoxShape3D
		box.size = Vector3(Sim.roads.BRIDGE_HALF * 2.0, Sim.roads.BRIDGE_GIRDER, float(sp2[2]))
		sb.global_transform = Transform3D(sp2[1], sp2[0])
		sb.process_mode = Node.PROCESS_MODE_INHERIT

## How many deck spans have a body right now, for the tests.
func live_spans() -> int:
	var n := 0
	for sb in _spans:
		if (sb as StaticBody3D).process_mode != Node.PROCESS_MODE_DISABLED:
			n += 1
	return n
