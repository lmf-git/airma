class_name SceneryMeshes
extends RefCounted
## The meshes the world's scenery is built from: street furniture, landmarks,
## town blocks, airfield clutter, trees, rocks, pylons and fences. Each is made
## from its arguments alone. Split out of `scenery.gd`, which places them.

static func lamp_mesh(tone: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	# A box, stood up. It was a cone, and `MeshKit.cone` runs along z: the
	# column was lying flat along the pavement, under the surface more often
	# than not, with the arm and the lantern hanging in the air where the top
	# of it should have been.
	MeshKit.box(st, Vector3(0.15, 5.4, 0.15), Vector3(0, 2.7, 0))
	MeshKit.box(st, Vector3(0.30, 0.35, 0.30), Vector3(0, 0.17, 0))
	MeshKit.box(st, Vector3(0.14, 0.10, 1.1), Vector3(0, 5.4, -0.45))
	MeshKit.box(st, Vector3(0.34, 0.16, 0.62), Vector3(0, 5.28, -0.95))
	return MeshKit.finish(st, MeshKit.mat(tone.darkened(0.45), 0.6, 0.35))

static func seat_mesh(tone: Color, biome: String) -> ArrayMesh:
	var st := MeshKit.begin()
	# stone in the dry country, timber where there are trees to cut
	var stone: bool = biome == "desert" or biome == "rock"
	MeshKit.box(st, Vector3(1.9, 0.14, 0.52), Vector3(0, 0.46, 0))
	if stone:
		MeshKit.box(st, Vector3(1.9, 0.42, 0.44), Vector3(0, 0.21, 0))
	else:
		for sx in [-0.75, 0.75]:
			MeshKit.box(st, Vector3(0.10, 0.44, 0.44), Vector3(sx, 0.22, 0))
		MeshKit.box(st, Vector3(1.9, 0.44, 0.10), Vector3(0, 0.72, 0.21))
	var col: Color = Color(0.62, 0.60, 0.56) if stone else Color(0.40, 0.28, 0.17)
	return MeshKit.finish(st, MeshKit.mat(col.lerp(tone, 0.25), 0.8, 0.0))

static func kiosk_mesh(tone: Color, faction: String) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(2.2, 2.6, 1.9), Vector3(0, 1.3, 0))
	match faction:
		"russia", "china":
			# a flat canopy on posts, which is what a street kiosk looks like there
			MeshKit.box(st, Vector3(3.0, 0.14, 2.6), Vector3(0, 2.72, 0))
		"uk", "usa":
			# a pitched roof and a hanging sign
			MeshKit.box(st, Vector3(2.7, 0.30, 2.4), Vector3(0, 2.75, 0))
			MeshKit.box(st, Vector3(1.7, 0.30, 1.5), Vector3(0, 3.05, 0))
			MeshKit.box(st, Vector3(1.3, 0.5, 0.08), Vector3(0, 2.1, -1.0))
		_:
			# an awning, angled out over the front
			MeshKit.box(st, Vector3(2.6, 0.10, 1.5), Vector3(0, 2.5, -1.2))
	return MeshKit.finish(st, MeshKit.mat(tone.lightened(0.12), 0.7, 0.05))

static func planter_mesh(tone: Color, biome: String) -> ArrayMesh:
	var st := MeshKit.begin()
	# Boxes, every part: a cone here runs along z, so the tub, the stem and
	# the crown were all lying on their sides.
	MeshKit.box(st, Vector3(1.4, 0.75, 1.4), Vector3(0, 0.37, 0))
	match biome:
		"desert":
			# a palm: a bare stem and a crown
			MeshKit.box(st, Vector3(0.22, 3.7, 0.22), Vector3(0, 2.6, 0))
			for k in 6:
				var a := TAU * float(k) / 6.0
				MeshKit.box(st, Vector3(2.0, 0.07, 0.34),
					Vector3(cos(a) * 0.9, 4.3, sin(a) * 0.9))
		"snow", "rock":
			MeshKit.box(st, Vector3(0.20, 1.0, 0.20), Vector3(0, 1.2, 0))
			for lvl in 4:
				var w: float = 1.7 - lvl * 0.4
				MeshKit.box(st, Vector3(w, 0.62, w), Vector3(0, 1.7 + lvl * 0.6, 0))
		_:
			MeshKit.box(st, Vector3(0.26, 2.0, 0.26), Vector3(0, 1.7, 0))
			MeshKit.box(st, Vector3(2.2, 1.5, 2.2), Vector3(0, 3.3, 0))
			MeshKit.box(st, Vector3(1.4, 0.8, 1.4), Vector3(0, 4.3, 0))
	return MeshKit.finish(st, MeshKit.mat(tone.lerp(Color(0.22, 0.36, 0.18), 0.6),
		0.85, 0.0))

## Each one is a handful of primitives, not a model: enough silhouette that you
## know what you are looking at from a mile up, which is the only range anybody
## will see them from.
static func landmark_mesh(id: String, h: float, tone: Color) -> Node3D:
	var st := MeshKit.begin()
	var pale := MeshKit.mat(tone, 0.7, 0.05)
	match id:
		"eiffel":
			# four splayed legs, two decks and a spire
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var foot := Vector3(sx * h * 0.16, 0.0, sz * h * 0.16)
					MeshKit.cone(st, h * 0.020, h * 0.008, 0.0, h * 0.62,
						foot, 6, true)
			MeshKit.box(st, Vector3(h * 0.30, h * 0.012, h * 0.30),
				Vector3(0, h * 0.185, 0))
			MeshKit.box(st, Vector3(h * 0.16, h * 0.012, h * 0.16),
				Vector3(0, h * 0.40, 0))
			MeshKit.cone(st, h * 0.045, h * 0.006, h * 0.40, h * 0.94,
				Vector3.ZERO, 8, true)
			MeshKit.cone(st, h * 0.008, h * 0.001, h * 0.94, h, Vector3.ZERO, 6, true)
		"clock":
			MeshKit.box(st, Vector3(h * 0.20, h * 0.72, h * 0.20),
				Vector3(0, h * 0.36, 0))
			# the faces, one to each side
			for a in 4:
				var ang := TAU * float(a) / 4.0
				MeshKit.box(st, Vector3(h * 0.13, h * 0.13, h * 0.02),
					Vector3(sin(ang) * h * 0.105, h * 0.66, cos(ang) * h * 0.105))
			MeshKit.cone(st, h * 0.13, h * 0.005, h * 0.76, h, Vector3.ZERO, 8, true)
		"liberty":
			# plinth, star fort, figure, arm and torch
			MeshKit.box(st, Vector3(h * 0.52, h * 0.10, h * 0.52),
				Vector3(0, h * 0.05, 0))
			MeshKit.box(st, Vector3(h * 0.30, h * 0.32, h * 0.30),
				Vector3(0, h * 0.26, 0))
			MeshKit.cone(st, h * 0.10, h * 0.07, h * 0.42, h * 0.86,
				Vector3.ZERO, 10, true)
			MeshKit.cone(st, h * 0.030, h * 0.026, h * 0.72, h * 0.99,
				Vector3(h * 0.09, 0, 0), 6, true)
			MeshKit.cone(st, h * 0.045, h * 0.012, h * 0.99, h * 1.06,
				Vector3(h * 0.09, 0, 0), 8, true)
		"onion":
			MeshKit.box(st, Vector3(h * 0.62, h * 0.34, h * 0.62),
				Vector3(0, h * 0.17, 0))
			var spots := [Vector3(0, 0, 0), Vector3(h * 0.26, 0, h * 0.26),
				Vector3(-h * 0.26, 0, h * 0.26), Vector3(h * 0.26, 0, -h * 0.26),
				Vector3(-h * 0.26, 0, -h * 0.26)]
			for i in spots.size():
				var big: float = 1.0 if i == 0 else 0.62
				var base := (spots[i] as Vector3) + Vector3(0, h * 0.34, 0)
				MeshKit.cone(st, h * 0.075 * big, h * 0.085 * big, 0.0,
					h * 0.26 * big, base, 10, true)
				var top := base + Vector3(0, h * 0.26 * big, 0)
				# the dome: fat in the middle, drawn to a point
				MeshKit.cone(st, h * 0.085 * big, h * 0.10 * big, 0.0,
					h * 0.07 * big, top, 12, true)
				MeshKit.cone(st, h * 0.10 * big, h * 0.005 * big, h * 0.07 * big,
					h * 0.24 * big, top, 12, true)
		"pagoda":
			var tiers := 7
			for i in tiers:
				var f := 1.0 - float(i) / float(tiers) * 0.62
				var y := h * 0.06 + float(i) * h * 0.115
				MeshKit.box(st, Vector3(h * 0.26 * f, h * 0.085, h * 0.26 * f),
					Vector3(0, y, 0))
				# the eaves, wider than the storey they sit on
				MeshKit.cone(st, h * 0.21 * f, h * 0.05 * f, y + h * 0.045,
					y + h * 0.085, Vector3.ZERO, 4, true)
			MeshKit.cone(st, h * 0.02, h * 0.004, h * 0.86, h, Vector3.ZERO, 6, true)
		"wall":
			# a long rampart with towers along it, running over the ground
			var seg := 26
			for i in seg:
				var x := (float(i) - float(seg) * 0.5) * 260.0
				var z := sin(float(i) * 0.7) * 190.0
				var gy: float = Terrain.surface_height(x, z)
				MeshKit.box(st, Vector3(250.0, h, 22.0), Vector3(x, gy + h * 0.5, z))
				if i % 4 == 0:
					MeshKit.box(st, Vector3(34.0, h * 2.0, 34.0),
						Vector3(x, gy + h, z))
		"pyramid":
			# stepped, so it reads as masonry rather than a cone
			var steps := 14
			for i in steps:
				var f := 1.0 - float(i) / float(steps)
				MeshKit.box(st, Vector3(h * 1.05 * f, h / float(steps), h * 1.05 * f),
					Vector3(0, h * (float(i) + 0.5) / float(steps), 0))
		"minaret":
			MeshKit.box(st, Vector3(h * 0.70, h * 0.30, h * 0.70),
				Vector3(0, h * 0.15, 0))
			MeshKit.cone(st, h * 0.32, h * 0.30, h * 0.30, h * 0.38,
				Vector3.ZERO, 14, true)
			MeshKit.cone(st, h * 0.30, h * 0.02, h * 0.38, h * 0.66,
				Vector3.ZERO, 14, true)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var b := Vector3(sx * h * 0.40, 0.0, sz * h * 0.40)
					MeshKit.cone(st, h * 0.035, h * 0.030, 0.0, h * 0.82, b, 8, true)
					MeshKit.cone(st, h * 0.045, h * 0.004, h * 0.82, h, b, 8, true)
		"opera":
			# a row of leaning shells on a podium
			MeshKit.box(st, Vector3(h * 1.5, h * 0.14, h * 0.9),
				Vector3(0, h * 0.07, 0))
			for i in 4:
				var f2 := 1.0 - float(i) * 0.17
				var x2 := (float(i) - 1.5) * h * 0.34
				MeshKit.cone(st, h * 0.30 * f2, h * 0.02, h * 0.14, h * f2,
					Vector3(x2, 0, sin(float(i)) * h * 0.10), 10, false)
		"colossus":
			MeshKit.box(st, Vector3(h * 0.44, h * 0.12, h * 0.44),
				Vector3(0, h * 0.06, 0))
			for sx2 in [-1.0, 1.0]:
				MeshKit.cone(st, h * 0.055, h * 0.045, h * 0.12, h * 0.52,
					Vector3(sx2 * h * 0.10, 0, 0), 8, true)
			MeshKit.box(st, Vector3(h * 0.28, h * 0.30, h * 0.18),
				Vector3(0, h * 0.67, 0))
			MeshKit.cone(st, h * 0.085, h * 0.075, h * 0.82, h * 0.95,
				Vector3.ZERO, 10, true)
			# a raised arm
			MeshKit.cone(st, h * 0.040, h * 0.032, h * 0.62, h * 1.0,
				Vector3(h * 0.20, 0, 0), 8, true)
		_:
			return null
	var mi := MeshKit.mi(MeshKit.finish(st, pale), "Mesh")
	var root := Node3D.new()
	root.add_child(mi)
	return root

static func block_mesh(w: float, h: float, d: float, roof: Color, wall: Color) -> ArrayMesh:
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

static func hangar_mesh() -> ArrayMesh:
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

static func revetment_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(30, 4.5, 3.0), Vector3(0, 2.2, -14.0))
	MeshKit.box(st, Vector3(3.0, 4.5, 26.0), Vector3(-13.5, 2.2, 0))
	MeshKit.box(st, Vector3(3.0, 4.5, 26.0), Vector3(13.5, 2.2, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.42, 0.40, 0.34), 0.95, 0.0))

static func bush_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rings := [
		MeshKit.ring(0.9, 0.5, 0.25, -0.7, 2.2, 6),
		MeshKit.ring(1.5, 1.0, 0.85, 0.2, 2.0, 6),
		MeshKit.ring(0.7, 0.5, 1.35, 0.9, 2.2, 6),
	]
	MeshKit.loft(st, rings, Vector3(0, 0.8, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.17, 0.25, 0.13), 0.97, 0.0))

## A tree stood up: trunk, then a crown of `rings` -- each [radius, height up
## the crown] as shares of `canopy_r` and `canopy_h` -- the crown starting at
## `crown_from` of the trunk's height.
##
## These were built the way `MeshKit` lofts, along z, and the scatter only
## turns each one about the vertical: every tree in the country lay on its side
## with its trunk along the ground, and the crown -- two rings at the same z,
## one high and one low -- was a flat sheet standing on edge, the shape of a
## tree from one side and a line from the other.
static func leafy(trunk_r: float, trunk_h: float, canopy_r: float, canopy_h: float,
		trunk_c: Color, leaf_c: Color, seg: int, crown: Array, crown_from := 0.55) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.cone(st, trunk_r, trunk_r * 0.7, 0.0, trunk_h, Vector3.ZERO, 5)
	var m := MeshKit.finish(st, MeshKit.mat(trunk_c, 0.96, 0.0))
	var st2 := MeshKit.begin()
	var base: float = trunk_h * crown_from
	# A crown is one or more lofts (a pine's tiers); each starts a new list.
	for tier in crown:
		var rings: Array = []
		var lo := INF
		var hi := -INF
		for i in (tier as Array).size():
			var rr: Vector2 = tier[i]
			var z: float = base + rr.y * canopy_h
			# a little out of round, and turned from ring to ring, so it is not
			# a lathe turning
			var wob: float = 1.0 + 0.08 * sin(float(i) * 2.3)
			rings.append(_turned(MeshKit.ring(canopy_r * rr.x * wob, canopy_r * rr.x / wob,
				0.0, z, 2.0, seg), float(i) * 0.45))
			lo = minf(lo, z)
			hi = maxf(hi, z)
		MeshKit.loft(st2, rings, Vector3(0, 0, (lo + hi) * 0.5))
	var leaves: ArrayMesh = MeshKit.finish(st2, MeshKit.mat(leaf_c, 0.96, 0.0))
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, leaves.surface_get_arrays(0))
	m.surface_set_material(1, MeshKit.mat(leaf_c, 0.96, 0.0))
	return upright(m)

static func _turned(ring: PackedVector3Array, a: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c := cos(a)
	var sn := sin(a)
	for p in ring:
		out.append(Vector3(p.x * c - p.y * sn, p.x * sn + p.y * c, p.z))
	return out

## A mesh lofted along z, stood up so that z is the vertical.
static func upright(m: ArrayMesh) -> ArrayMesh:
	var b := Basis(Vector3.RIGHT, -PI * 0.5)
	var out := ArrayMesh.new()
	for s in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] = b * v[i]
		arr[Mesh.ARRAY_VERTEX] = v
		if arr[Mesh.ARRAY_NORMAL] != null:
			var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in nn.size():
				nn[i] = b * nn[i]
			arr[Mesh.ARRAY_NORMAL] = nn
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(0, tg.size(), 4):
				var t3: Vector3 = b * Vector3(tg[i], tg[i + 1], tg[i + 2])
				tg[i] = t3.x
				tg[i + 1] = t3.y
				tg[i + 2] = t3.z
			arr[Mesh.ARRAY_TANGENT] = tg
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, m.surface_get_material(s))
	return out

## A broad leafy crown, fullest a third of the way up.
static func tree_mesh() -> ArrayMesh:
	return leafy(0.42, 4.2, 3.6, 6.0, Color(0.21, 0.15, 0.11), Color(0.15, 0.27, 0.12), 7,
		[[Vector2(0.45, 0.0), Vector2(0.92, 0.18), Vector2(1.0, 0.42), Vector2(0.82, 0.70),
			Vector2(0.42, 0.92), Vector2(0.08, 1.0)]])

## Three tiers of boughs, each a skirt narrowing to the next.
static func pine_mesh() -> ArrayMesh:
	return leafy(0.34, 5.0, 2.7, 10.0, Color(0.19, 0.14, 0.10), Color(0.10, 0.21, 0.13), 7,
		[[Vector2(0.25, 0.0), Vector2(1.0, 0.08), Vector2(0.35, 0.42)],
		[Vector2(0.25, 0.30), Vector2(0.78, 0.38), Vector2(0.25, 0.72)],
		[Vector2(0.2, 0.60), Vector2(0.55, 0.66), Vector2(0.03, 1.0)]], 0.4)

static func rock_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rings := [
		MeshKit.ring(1.4, 0.9, 0.0, -2.0, 2.4, 6),
		MeshKit.ring(2.6, 1.9, 0.6, 0.0, 2.0, 6),
		MeshKit.ring(1.2, 0.8, 0.2, 2.2, 2.4, 6),
	]
	MeshKit.loft(st, rings, Vector3(0, 0.8, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.33, 0.31, 0.29), 0.98, 0.0))

static func truck_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(2.4, 1.6, 6.2), Vector3(0, 1.5, 0))
	MeshKit.box(st, Vector3(2.2, 1.4, 2.0), Vector3(0, 2.6, -2.0))
	for sx in [-1.0, 1.0]:
		for zz in [-2.0, 1.2, 2.4]:
			MeshKit.cone(st, 0.5, 0.5, -0.2, 0.2, Vector3(sx * 1.25, 0.5, zz), 6)
	return MeshKit.finish(st, MeshKit.mat(Color(0.24, 0.28, 0.20), 0.9, 0.1))

static func wall_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(14.0, 3.2, 1.2), Vector3(0, 1.6, 0))
	return MeshKit.finish(st, MeshKit.mat(Color(0.46, 0.45, 0.40), 0.96, 0.0))

static func pylon_mesh() -> ArrayMesh:
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

## Three sagging conductors between two pylon tops.
static func catenary(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
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

static func fence_panel(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var lo := 0.25
	var hi := 2.25
	for v in [a + Vector3(0, hi, 0), b + Vector3(0, hi, 0), b + Vector3(0, lo, 0),
			a + Vector3(0, hi, 0), b + Vector3(0, lo, 0), a + Vector3(0, lo, 0)]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)
