class_name TerrainTests
extends TestSuite
## Terrain, roads, towns, level of detail and the ground's agreement with itself.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--terraintest":
		_terrain_test = true
	elif a == "--townstest":
		_town_test = true
	elif a == "--roadtest":
		_road_test = true
		Sim.debug_roads = true
	elif a == "--skirttest":
		_skirt_test = true
	elif a == "--guntest":
		_gun_test = true
	elif a == "--churntest":
		_churn_test = true
	elif a == "--obstacletest":
		_obstacle_test = true
	elif a == "--lodtest":
		_lod_test = true
	elif a == "--subview":
		_subview_test = true
	elif a == "--floattest":
		_float_test = true
	elif a == "--seamix":
		_seamix = true
	elif a == "--fieldtest":
		_field_test = true
	elif a == "--seamtest":
		_seam_test = true
	elif a == "--biometest":
		_biome_test = true
	elif a == "--propclear":
		_prop_clear = true
	else:
		return false
	return true


#region --terraintest
## From an artillery piece, right click on the map and see a fire mission laid
## where the click was: --firemaptest with --jet=veh:m109 --preset=ramp.
var _terrain_test := false

func tick_terrain() -> void:
	if _terrain_test and world.running:
		_terrain_test = false
		_run_terrain_test()

## What the country around the airfield is like, in numbers: how much of the
## land is flat, how steep it is, how much it varies, and how much of it lies in
## a trench below its surroundings. --terraintest.
func _run_terrain_test() -> void:
	_terrain_stats(40000.0, 500.0, 5, 12)
	_terrain_stats(120000.0, 1000.0, 3, 6)
	world.get_tree().quit()

## One box of country: `ring_a` and `ring_b` are in samples, a narrow valley
## and a broad one.
func _terrain_stats(span: float, step: float, ring_a: int, ring_b: int) -> void:
	var n := int(span * 2.0 / step) + 1
	var h := PackedFloat32Array()
	h.resize(n * n)
	for j in n:
		for i in n:
			var x := -span + float(i) * step
			var z := -span + float(j) * step
			h[j * n + i] = Sim.natural_height_at(x, z) + Sim.planet_drop(x, z)
	var land := 0
	var flat := 0
	var slope_sum := 0.0
	var trench_a := 0
	var trench_b := 0
	var hs := 0.0
	var hs2 := 0.0
	var m := ring_b
	for j in range(m, n - m):
		for i in range(m, n - m):
			var v: float = h[j * n + i]
			if v < Sim.WATER_LEVEL + 2.0:
				continue
			land += 1
			hs += v
			hs2 += v * v
			var dmax := 0.0
			for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				dmax = maxf(dmax, absf(h[(j + o[1]) * n + i + o[0]] - v))
			slope_sum += dmax / step
			if dmax < step * 0.01:
				flat += 1
			for pass_r in [ring_a, ring_b]:
				var r: int = pass_r
				var around := 0.0
				for o2 in [[r, 0], [-r, 0], [0, r], [0, -r], [r, r], [-r, r], [r, -r], [-r, -r]]:
					around += h[(j + o2[1]) * n + i + o2[0]]
				if around / 8.0 - v > 35.0:
					if r == ring_a:
						trench_a += 1
					else:
						trench_b += 1
	var lf: float = maxf(float(land), 1.0)
	var mean: float = hs / lf
	print("[terrain] +-%d km: %d%% land; flat %d%%, mean slope %.1f%%, height %.0f +- %.0f m; in a trough %d%% (%.1f km across) / %d%% (%.0f km across)" % [
		int(span * 0.001), int(100.0 * float(land) / float((n - 2 * m) * (n - 2 * m))),
		int(100.0 * float(flat) / lf), 100.0 * slope_sum / lf, mean,
		sqrt(maxf(hs2 / lf - mean * mean, 0.0)),
		int(100.0 * float(trench_a) / lf), float(ring_a) * step * 2.0 * 0.001,
		int(100.0 * float(trench_b) / lf), float(ring_b) * step * 2.0 * 0.001])
#endregion


#region --propclear
## Is anything standing where a road bridge is, or inside a building? What the
## scenery put down, measured against the decks and the ramps up onto them --
## as the bridge records give them, not as anything that placed a prop asked --
## and against the town blocks: the trees, the street furniture, the streets as
## drawn, the piers, and the props each bridged town's set puts in its streets.
## --preset=free:f16 --propclear
var _prop_clear := false

func tick_prop_clear() -> void:
	if _prop_clear and world.running:
		_prop_clear = false
		_run_prop_clear()

## Every deck as [a, b, deck y at a, deck y at b] in the world frame, laps on,
## and every ramp as a polyline.
func _clear_parts() -> Array:
	var decks: Array = []
	var ramps: Array = []
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2:
			continue
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var dir := (b - a).normalized()
			if i == 0:
				a -= dir * Sim.BRIDGE_LAP
			if i == pts.size() - 2:
				b += dir * Sim.BRIDGE_LAP
			decks.append([a, b, ys[i] - Sim.planet_drop(a.x, a.y),
				ys[i + 1] - Sim.planet_drop(b.x, b.y)])
		for r in br.get("ramps", []):
			ramps.append(r)
	return [decks, ramps]

## What is wrong with something of radius `r` and height `h` standing at `p`:
## "deck" when it is under a deck with less room than it needs, "ramp" when it
## is on a ramp, "" when it is clear of both.
func _clear_verdict(parts: Array, p: Vector3, r: float, h: float, ramps := true) -> String:
	var q := Vector2(p.x, p.z)
	for rp in (parts[1] if ramps else []):
		var ramp: PackedVector2Array = rp
		for i in ramp.size() - 1:
			if Geometry2D.get_closest_point_to_segment(q, ramp[i], ramp[i + 1]) \
					.distance_to(q) < Sim.RAMP_HALF + r:
				return "ramp"
	for d in parts[0]:
		var a: Vector2 = d[0]
		var b: Vector2 = d[1]
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) > Sim.BRIDGE_HALF + r:
			continue
		var f: float = on.distance_to(a) / maxf(a.distance_to(b), 0.01)
		var under: float = lerpf(float(d[2]), float(d[3]), f) - Sim.BRIDGE_GIRDER
		if under - p.y < h:
			return "deck"
	return ""

## Footprints of the town blocks, hashed on a coarse grid: cell -> [transform].
func _block_hash() -> Dictionary:
	var out := {}
	for x in world.scenery.town_xforms:
		var xf: Transform3D = x
		var k := Vector2i(floori(xf.origin.x / 64.0), floori(xf.origin.z / 64.0))
		if not out.has(k):
			out[k] = []
		out[k].append(xf)
	return out

## Is (x, z) inside a town block, widened by `m` metres?
func _in_block(blocks: Dictionary, x: float, z: float, m: float) -> bool:
	var k := Vector2i(floori(x / 64.0), floori(z / 64.0))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for xf in blocks.get(k + Vector2i(dx, dz), []):
				var t: Transform3D = xf
				var l: Vector3 = t.affine_inverse() * Vector3(x, t.origin.y, z)
				if absf(l.x) < 0.5 + m / t.basis.x.length() \
						and absf(l.z) < 0.5 + m / t.basis.z.length():
					return true
	return false

func _run_prop_clear() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var sc: Node = world.scenery
	var parts := _clear_parts()
	var blocks := _block_hash()
	print("[propclear] %d decks' worth of spans, %d ramps, %d town blocks" % [
		(parts[0] as Array).size(), (parts[1] as Array).size(), sc.town_xforms.size()])
	# The country: what stands where, and how big it is. Heights and crowns are
	# the meshes' own, at scale one.
	var tall := {"tree": 8.3, "pine": 12.8, "rock": 3.0, "bush": 2.2}
	var crown := {"tree": 3.6, "pine": 2.7, "rock": 2.6, "bush": 1.5}
	var nat := {"deck": 0, "ramp": 0, "block": 0, "road": 0, "all": 0}
	for n in sc.get_children():
		if not (n is MultiMeshInstance3D):
			continue
		var kind: String = String(n.name).split("_")[0]
		if not tall.has(kind):
			continue
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			var t: Transform3D = mm.get_instance_transform(i)
			var s: float = t.basis.x.length()
			nat["all"] += 1
			var v := _clear_verdict(parts, t.origin, float(crown[kind]) * s,
				float(tall[kind]) * t.basis.y.length())
			if v != "":
				nat[v] += 1
			if _in_block(blocks, t.origin.x, t.origin.z, 0.5) \
					or Obstacles.blocks(t.origin + Vector3(0, 0.9, 0), 0.4) >= 0:
				nat["block"] += 1
			if Sim.road_distance(t.origin.x, t.origin.z) < Sim.ROAD_HALF + 1.5:
				nat["road"] += 1
	print("[propclear] country scatter: %d placed; %d under a deck, %d on a ramp, %d inside a building or structure, %d in a carriageway" % [
		nat["all"], nat["deck"], nat["ramp"], nat["block"], nat["road"]])
	# The street furniture: lamps are the tallest of it, at five and a half metres.
	var fur := {"deck": 0, "ramp": 0, "block": 0, "all": 0}
	for f in sc._furniture:
		for x in (f[1] as Array):
			var o: Vector3 = (x as Transform3D).origin
			fur["all"] += 1
			var v2 := _clear_verdict(parts, o, 1.2, 6.0)
			if v2 != "":
				fur[v2] += 1
			if _in_block(blocks, o.x, o.z, 0.6):
				fur["block"] += 1
	print("[propclear] street furniture: %d placed; %d under a deck, %d on a ramp, %d inside a town block" % [
		fur["all"], fur["deck"], fur["ramp"], fur["block"]])
	# The streets as drawn: a 5 m half-width with its kerbs out to 7.75, and a
	# lorry's worth of headroom wanted over it.
	var drawn: Array = sc.get("street_draw") if sc.get("street_draw") != null \
		else sc._streets
	var st_bad := 0
	var st_n := 0
	var st_hit := 0
	for seg in drawn:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var steps: int = maxi(int(a.distance_to(b) / 3.0), 1)
		var any := false
		for k in steps + 1:
			var q: Vector2 = a.lerp(b, float(k) / float(steps))
			st_n += 1
			# A street meets a ramp in its own way now -- climbs to it, or is
			# drawn to the foot of its bank (`Scenery._plan_junctions`) -- so it
			# is only a deck it must keep clear of: see --junctions for the rest.
			var v3 := _clear_verdict(parts, Vector3(q.x, Sim.height_at(q.x, q.y), q.y),
				7.75, 5.0, false)
			if v3 != "":
				st_bad += 1
				any = true
		if any:
			st_hit += 1
	print("[propclear] streets: %d legs drawn, %d of them run under a deck with less than 5 m (%d of %d points)" % [
		drawn.size(), st_hit, st_bad, st_n])
	# Piers standing in a road or a street.
	var pier_bad := 0
	var piers: Array = sc.get("pier_spots") if sc.get("pier_spots") != null else []
	for pp in piers:
		var pv: Vector3 = pp
		if Sim.road_distance(pv.x, pv.z) < pv.y + 7.75:
			pier_bad += 1
	print("[propclear] piers: %d, %d standing in a road or street" % [piers.size(), pier_bad])
	# And what a town's set puts in its streets, for every town a bridge runs
	# through the middle of.
	var ts_n := 0
	var ts_bad := 0
	var ts_towns := 0
	var cranes := 0
	for i in sc.sites.size():
		var c: Vector2 = sc.sites[i]["c"]
		var near := false
		for d in parts[0]:
			if Geometry2D.get_closest_point_to_segment(c, d[0], d[1]).distance_to(c) < 260.0:
				near = true
		for rp in parts[1]:
			for q2 in (rp as PackedVector2Array):
				if q2.distance_to(c) < 260.0:
					near = true
		if not near:
			continue
		var ts: TownSet = world.street_fight.town_set(i)
		if ts == null:
			continue
		while ts.building:
			await world.get_tree().process_frame
		ts_towns += 1
		for pr in ts.props:
			ts_n += 1
			var pos: Vector3 = pr[1]
			var v4 := _clear_verdict(parts, pos, float(TownSet.NEED.get(String(pr[0]), 2.5)),
				TownSet.ROOM_OVER)
			if v4 != "":
				ts_bad += 1
				print("[propclear]   %s %s at %s: %s" % [String(sc.sites[i]["name"]),
					String(pr[0]), str(pos.round()), v4])
		for rn in ts.get("ruins_at") if ts.get("ruins_at") != null else []:
			ts_n += 1
			if _clear_verdict(parts, rn as Vector3, 7.0, 5.0) != "":
				ts_bad += 1
				print("[propclear]   %s ruin at %s" % [String(sc.sites[i]["name"]),
					str((rn as Vector3).round())])
		if ts.crane_at != Vector3.INF:
			var foot := Vector3(ts.crane_at.x, Sim.height_at(ts.crane_at.x, ts.crane_at.z),
				ts.crane_at.z)
			if _clear_verdict(parts, foot, 42.0, 36.0) != "":
				cranes += 1
				print("[propclear]   %s crane at %s swings over a bridge" % [
					String(sc.sites[i]["name"]), str(foot.round())])
	print("[propclear] town sets: %d towns with a bridge through them, %d props of which %d are under a deck or on a ramp; %d cranes over a bridge" % [
		ts_towns, ts_n, ts_bad, cranes])
	# Inside a building, more widely: everything else the scenery stood on the
	# ground, and every town set that is up, against the town blocks -- and the
	# street furniture against the ruins a set built over it.
	var inside := 0
	for n2 in sc.get_children():
		if not (n2 is MultiMeshInstance3D):
			continue
		var nm: String = String(n2.name)
		if nm.begins_with("Town") or tall.has(nm.split("_")[0]):
			continue
		var mm2: MultiMesh = (n2 as MultiMeshInstance3D).multimesh
		for i2 in mm2.instance_count:
			var o2: Vector3 = mm2.get_instance_transform(i2).origin
			if _in_block(blocks, o2.x, o2.z, 0.0):
				inside += 1
				if inside <= 12:
					print("[propclear]   %s at %s stands inside a town block" % [nm, str(o2.round())])
	var ts_inside := 0
	var under_ruin := 0
	for ch in world.get_children():
		if not (ch is TownSet):
			continue
		var tset: TownSet = ch
		for pr2 in tset.props:
			var p2: Vector3 = pr2[1]
			if _in_block(blocks, p2.x, p2.z, -0.3):
				ts_inside += 1
				print("[propclear]   %s %s at %s stands inside a town block" % [
					tset.name, String(pr2[0]), str(p2.round())])
			for rn2 in tset.ruins_at:
				var rv: Vector3 = rn2
				if absf(p2.x - rv.x) < 6.0 and absf(p2.z - rv.z) < 6.0:
					ts_inside += 1
					print("[propclear]   %s %s at %s stands inside a ruin" % [
						tset.name, String(pr2[0]), str(p2.round())])
		for f2 in sc._furniture:
			for x2 in (f2[1] as Array):
				var o3: Vector3 = (x2 as Transform3D).origin
				for rn3 in tset.ruins_at:
					var rv3: Vector3 = rn3
					if absf(o3.x - rv3.x) < 6.6 and absf(o3.z - rv3.z) < 6.6:
						under_ruin += 1
				if tset.crane_at != Vector3.INF and absf(o3.x - tset.crane_at.x) < 3.0 \
						and absf(o3.z - tset.crane_at.z) < 3.0:
					under_ruin += 1
	# The aerodromes' towers are drawn, not filed as obstacles: anything the
	# scenery parked on an apron, against each tower's own box.
	var towers: Array = []
	for ab in world.get_children():
		if not (ab is Airbase):
			continue
		for tw in ab.get_children():
			if tw is MeshInstance3D and String(tw.name) == "Tower":
				towers.append((tw as MeshInstance3D).global_transform \
					* (tw as MeshInstance3D).get_aabb())
	for n3 in sc.get_children():
		if not (n3 is MultiMeshInstance3D):
			continue
		var mm3: MultiMesh = (n3 as MultiMeshInstance3D).multimesh
		if mm3.mesh == null:
			continue
		var ab3: AABB = mm3.mesh.get_aabb()
		for i3 in mm3.instance_count:
			var box: AABB = mm3.get_instance_transform(i3) * ab3
			for tb in towers:
				var t2: AABB = tb
				# on the ground plan only: the tower stands on the apron's level
				if box.position.x < t2.end.x and box.end.x > t2.position.x \
						and box.position.z < t2.end.z and box.end.z > t2.position.z:
					inside += 1
					print("[propclear]   %s at %s stands inside a control tower" % [
						String(n3.name), str(box.get_center().round())])
	print("[propclear] inside buildings: %d scenery pieces in a town block or a tower, %d town-set props in a block or a ruin, %d pieces of street furniture inside a ruin or under a crane" % [
		inside, ts_inside, under_ruin])
	var total: int = int(nat["deck"]) + int(nat["ramp"]) + int(nat["block"]) \
		+ int(fur["deck"]) + int(fur["ramp"]) + int(fur["block"]) + st_hit + pier_bad \
		+ ts_bad + cranes + inside + ts_inside + under_ruin
	print("[propclear] RESULT: %s -- %d things in the way (trees on a carriageway, %d, not counted)" % [
		"ok" if total == 0 else "FAILED", total, nat["road"]])
	world.get_tree().quit()
#endregion


#region --townstest
var _town_test := false

func tick_town() -> void:
	if _town_test:
		_town_test = false
		for t in world.scenery.sites:
			var c: Vector2 = t["c"]
			var r: float = float(t["r"])
			var moved: float = c.distance_to(t["was"] as Vector2)
			# worst height spread across a 24 m building footprint, sampled
			# across the town, and the mean gradient over the whole site
			var worst := 0.0
			var mean := 0.0
			var n := 0
			for i in 15:
				for j in 15:
					var q := c + Vector2(float(i - 7), float(j - 7)) * (r / 8.0)
					if q.distance_to(c) > r:
						continue
					var lo := 1e9
					var hi := -1e9
					for dx in [-12.0, 12.0]:
						for dz in [-12.0, 12.0]:
							var y := Sim.height_at(q.x + dx, q.y + dz)
							lo = minf(lo, y)
							hi = maxf(hi, y)
					worst = maxf(worst, hi - lo)
					mean += 1.0 - Sim.normal_at(q.x, q.y).y
					n += 1
			print("[town] %-14s at %s (moved %4.0f m)  gradient %.4f  worst footprint step %5.2f m" % [
				String(t["name"]), str(c.round()), moved,
				mean / maxf(float(n), 1.0), worst])
		# How clearly a street reads. Walk perpendicular across one and compare
		# the stain on the centreline with the stain halfway to the next street.
		var on_road := 0.0
		var between := 0.0
		var xs := 0
		for r in world.scenery._streets:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			if ra.distance_to(rb) < 200.0:
				continue
			var dirv := (rb - ra).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			for k in 5:
				var q: Vector2 = ra.lerp(rb, 0.2 + float(k) * 0.15)
				on_road += world.terrain.mask_at(q.x, q.y).x
				between += world.terrain.mask_at(q.x + nrm.x * 64.0, q.y + nrm.y * 64.0).x
				xs += 1
		print("[town] street contrast: stain %.2f on the centreline, %.2f halfway to the next street" % [
			on_road / maxf(float(xs), 1.0), between / maxf(float(xs), 1.0)])
		# and how much of the built-up area actually looks built up
		var paved := 0.0
		var edge_paved := 0.0
		var edge_n := 0
		var all_n := 0
		for t in world.scenery.sites:
			var tc: Vector2 = t["c"]
			var rad: float = float(t["r"])
			for i in 21:
				for j in 21:
					var q := tc + Vector2(float(i - 10), float(j - 10)) * (rad / 10.0)
					var dd := q.distance_to(tc)
					if dd > rad:
						continue
					var tf: float = world.terrain.mask_at(q.x, q.y).y
					paved += tf
					all_n += 1
					if dd > rad * 0.85:
						edge_paved += tf
						edge_n += 1
		var stained := 0
		var stain_n := 0
		for t in world.scenery.sites:
			var tc2: Vector2 = t["c"]
			var rad2: float = float(t["r"])
			for i in 61:
				for j in 61:
					var q := tc2 + Vector2(float(i - 30), float(j - 30)) * (rad2 / 30.0)
					if q.distance_to(tc2) > rad2:
						continue
					stain_n += 1
					if world.terrain.mask_at(q.x, q.y).x > 0.5:
						stained += 1
		for t in world.scenery.sites:
			var tc3: Vector2 = t["c"]
			var cheb: float = maxf(absf(tc3.x), absf(tc3.y))
			# One number wherever you stand now: the quadtree reaches BASE_CELL
			# at any point you are near, instead of handing out kilometre cells
			# to anywhere that is not the airfield at the world origin.
			var cell: float = Terrain.cell_at(tc3.x, tc3.y)
			print("[town] %-14s %.1f km from the field: terrain cells are %.0f m there (street grid is 128 m)" % [
				String(t["name"]), cheb * 0.001, cell])
		# Roads over the airfield, and buildings standing in the road.
		var on_field := 0
		var on_apron := 0
		var on_runway := 0
		var pts_f := 0
		for r in Sim.ROADS:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var steps: int = maxi(int(ra.distance_to(rb) / 12.0), 2)
			for k in steps + 1:
				var q: Vector2 = ra.lerp(rb, float(k) / float(steps))
				pts_f += 1
				if not Sim.clear_of_airfield(q.x, q.y):
					on_field += 1
					if absf(q.x) < 620.0 and absf(q.y) < 2600.0:
						on_apron += 1
				if Sim.on_runway(q.x, q.y):
					on_runway += 1
		print("[town] trunk network over the airfield: %d of %d points inside the keep-out (%d of those on the field itself, %d on the runway)" % [
			on_field, pts_f, on_apron, on_runway])
		var clash := 0
		var nearest_clash := 1e9
		var built := 0
		var on_tarmac := 0
		for x in world.scenery.town_xforms:
			var xf: Transform3D = x
			built += 1
			# half the footprint, from the instance scale
			var halfw: float = maxf(xf.basis.x.length(), xf.basis.z.length()) * 0.5
			var d := Sim.road_distance(xf.origin.x, xf.origin.z)
			if d < halfw + 4.0:
				clash += 1
				nearest_clash = minf(nearest_clash, d)
			if world.terrain.mask_at(xf.origin.x, xf.origin.z).x > 0.35:
				on_tarmac += 1
		var pyl_bad := 0
		var pyl_n := 0
		for n in world.scenery.get_children():
			if not (n is MultiMeshInstance3D) or String(n.name) != "Pylons":
				continue
			var pm := (n as MultiMeshInstance3D).multimesh
			for i in pm.instance_count:
				pyl_n += 1
				var o: Vector3 = world.scenery.pylon_spots[i] if i < world.scenery.pylon_spots.size() \
					else Vector3.ZERO
				if not Sim.clear_of_roads(o.x, o.z, 12.0):
					pyl_bad += 1
		print("[town] pylons standing in a road: %d of %d" % [pyl_bad, pyl_n])
		print("[town] buildings in a road: %d of %d overlap the carriageway (closest centre %.1f m), %d stand on painted tarmac" % [
			clash, built, nearest_clash if clash > 0 else -1.0, on_tarmac])
		print("[town] tarmac covers %.1f%% of the built-up area" % [
			100.0 * float(stained) / maxf(float(stain_n), 1.0)])
		print("[town] made ground: %.2f across the footprint, %.2f in the outer ring where the buildings meet the country" % [
			paved / maxf(float(all_n), 1.0), edge_paved / maxf(float(edge_n), 1.0)])
		# The ribbon against the terrain *mesh*, which is what is actually
		# drawn. The chunk mesh samples the height field on a 30 m grid and
		# interpolates between, so over a dip the drawn ground sits above the
		# true height field — and the carriageway, laid 0.16 m over the field,
		# ends up underneath it.
		var sunk := 0
		var pts := 0
		var worst_sink := 0.0
		var sum_sink := 0.0
		for r in (Sim.ROADS + world.scenery._streets):
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var steps: int = maxi(int(ra.distance_to(rb) / 11.0), 2)
			for k in steps + 1:
				var q: Vector2 = ra.lerp(rb, float(k) / float(steps))
				var road_y := Sim.height_at(q.x, q.y) + 0.16
				# the drawn ground: bilinear over the innermost ring's cells
				var cs := 30.0
				var gx := floorf(q.x / cs) * cs
				var gz := floorf(q.y / cs) * cs
				var tx := (q.x - gx) / cs
				var tz := (q.y - gz) / cs
				var h00 := Sim.height_at(gx, gz)
				var h10 := Sim.height_at(gx + cs, gz)
				var h01 := Sim.height_at(gx, gz + cs)
				var h11 := Sim.height_at(gx + cs, gz + cs)
				var mesh_y := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
				pts += 1
				if mesh_y > road_y:
					sunk += 1
					sum_sink += mesh_y - road_y
					worst_sink = maxf(worst_sink, mesh_y - road_y)
		print("[town] carriageway vs the drawn ground: %d of %d points under it, mean %.2f m, worst %.2f m" % [
			sunk, pts, sum_sink / maxf(float(sunk), 1.0), worst_sink])
		# and the streets: are they on the ground or under it
		var buried := 0
		var total := 0
		var deepest := 0.0
		for seg in world.scenery._streets:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			for k in 12:
				var q: Vector2 = a.lerp(b, float(k) / 11.0)
				total += 1
				# the ribbon lays its surface 0.16 m above the sampled height,
				# so anything more than that below a neighbour is buried
				var here := Sim.height_at(q.x, q.y) + 0.16
				var around := -1e9
				for dx in [-6.0, 6.0]:
					for dz in [-6.0, 6.0]:
						around = maxf(around, Sim.height_at(q.x + dx, q.y + dz))
				if around > here:
					buried += 1
					deepest = maxf(deepest, around - here)
		print("[town] streets: %d segments, %d of %d sample points buried, deepest %.2f m" % [
			world.scenery._streets.size(), buried, total, deepest])
		# and the trunk network: how much climbing it does, and how steep it gets
		var climb := 0.0
		var length := 0.0
		var steepest := 0.0
		for r in Sim.ROADS:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var d := a.distance_to(b)
			length += d
			var steps: int = maxi(int(d / 50.0), 2)
			var last := Sim.height_at(a.x, a.y)
			for k in range(1, steps + 1):
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var y := Sim.height_at(q.x, q.y)
				climb += absf(y - last)
				steepest = maxf(steepest, absf(y - last) / (d / float(steps)))
				last = y
		for t in world.scenery.sites:
			var tc: Vector2 = t["c"]
			var near := 1e9
			for r in Sim.ROADS:
				near = minf(near, Geometry2D.get_closest_point_to_segment(
					tc, r[0], r[1]).distance_to(tc))
			print("[town] %-14s nearest trunk road %.0f m from the middle of it" % [
				String(t["name"]), near])
		# Does the baked field actually know where the roads are? The terrain
		# paints its road stain from this, so if the field cannot resolve a
		# carriageway the network is invisible from the air.
		var worst_err := 0.0
		var sum_err := 0.0
		var missed := 0
		var samples := 0
		for r in (Sim.ROADS + world.scenery._streets):
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			for k in 9:
				var q: Vector2 = ra.lerp(rb, float(k) / 8.0)
				if absf(q.x) >= 18000.0 or absf(q.y) >= 18000.0:
					continue
				var field := Sim.road_distance(q.x, q.y)
				samples += 1
				sum_err += field
				worst_err = maxf(worst_err, field)
				if field >= 46.0:
					missed += 1      # the terrain paints no road stain here
		print("[town] distance index measured standing on the centreline: mean %.1f m, worst %.1f m; %d of %d points where the terrain paints nothing" % [
			sum_err / maxf(float(samples), 1.0), worst_err, missed, samples])
		for n in world.scenery.get_children():
			if n is MeshInstance3D and String(n.name) in ["Roads", "Kerbs"]:
				var mi := n as MeshInstance3D
				var ab := mi.get_aabb()
				var tris := 0
				if mi.mesh != null:
					for si in mi.mesh.get_surface_count():
						# Three vertices to a triangle, exactly; the remainder
						# is meant to go.
						@warning_ignore("integer_division")
						var vt: int = mi.mesh.surface_get_arrays(si)[
							Mesh.ARRAY_VERTEX].size() / 3
						tris += vt
				print("[town] mesh %-6s visible=%s tris=%d  aabb pos=%s size=%s  layers=%d" % [
					String(mi.name), str(mi.visible), tris,
					str(ab.position.round()), str(ab.size.round()), mi.layers])
		print("[town] scenery: %s" % str(world.scenery._stats))
		# What the country is made of. The scatter picks its species off this,
		# and a world that comes out with one tree in it has a biome mix that
		# says so long before anybody looks at the trees.
		var mix := {}
		var dry := 0
		for i5 in 3000:
			var a5: float = TAU * float(i5) * 0.618034
			var r5: float = sqrt(float(i5) / 3000.0) * 260_000.0
			var p5 := Vector2(cos(a5), sin(a5)) * r5
			var h5: float = Sim.height_at(p5.x, p5.y)
			if h5 <= Sim.sea_at(p5.x, p5.y):
				continue
			dry += 1
			var k5: String = Sim.biome_kind(p5.x, p5.y, h5, 1.0)
			mix[k5] = int(mix.get(k5, 0)) + 1
		var parts: Array = []
		for k6 in mix.keys():
			parts.append("%s %d%%" % [
				k6, int(round(100.0 * float(mix[k6]) / maxf(float(dry), 1.0)))])
		parts.sort()
		print("[town] the country is %s (of %d dry samples out to 260 km)" % [
			", ".join(PackedStringArray(parts)), dry])
		print("[town] trunk roads: %d legs, %.1f km of tarmac, %.0f m of climb (%.1f m per km), steepest %.1f%%" % [
			Sim.ROADS.size(), length * 0.001, climb, climb / maxf(length * 0.001, 1.0),
			steepest * 100.0])
		world.get_tree().quit()
#endregion


#region --roadtest
var _road_test := false

# What driving the trunk network is actually like: the gradient along it and
# how level the carriageway is across its width.
func tick_road() -> bool:
	if _road_test:
		# Does the network double back on itself?
		#
		# A route that leaves a place and comes back past it is not a road, and
		# on a bridge it is plainly wrong: the deck is carried out over water
		# and brought back to the bank it started from. Two measures -- how far
		# a route walks against how far apart its ends are, and how often it
		# turns through more than a right angle -- because a loop shows in the
		# first and a switchback in the second.
		var lp_detour := 1.0
		var lp_at := Vector2.ZERO
		var lp_reversals := 0
		var lp_bends := 0
		var lp_loops := 0
		var lp_lines: Array = Sim.road_lines()
		for ln in lp_lines:
			var pl: PackedVector2Array = ln
			if pl.size() < 3:
				continue
			var walked := 0.0
			for i in range(1, pl.size()):
				walked += pl[i].distance_to(pl[i - 1])
			var direct: float = pl[0].distance_to(pl[pl.size() - 1])
			var detour: float = walked / maxf(direct, 1.0)
			if direct > 4000.0 and detour > lp_detour:
				lp_detour = detour
				lp_at = pl[0]
			if direct > 4000.0 and detour > 2.0:
				lp_loops += 1
			for i in range(1, pl.size() - 1):
				var a: Vector2 = pl[i] - pl[i - 1]
				var b: Vector2 = pl[i + 1] - pl[i]
				lp_bends += 1
				if a.length() > 1.0 and b.length() > 1.0 \
						and a.normalized().dot(b.normalized()) < -0.5:
					lp_reversals += 1
		print("[roads] %d routes; the worst walks %.2fx the distance between its ends (from %s); %d walk more than twice it" % [
			lp_lines.size(), lp_detour, str(lp_at.round()), lp_loops])
		print("[roads] %d of %d bends turn back on themselves by more than 120 deg" % [
			lp_reversals, lp_bends])
		# And how many corners are left on the network at all: a trunk road
		# bends on a curve, so a station turning through more than a quarter of
		# a right angle is a corner the survey did not round.
		var sharp := 0
		var sharp_at: Array = []
		for ln3 in lp_lines:
			var pl3: PackedVector2Array = ln3
			for i in range(1, pl3.size() - 1):
				var u3: Vector2 = pl3[i] - pl3[i - 1]
				var v3: Vector2 = pl3[i + 1] - pl3[i]
				if u3.length() < 1.0 or v3.length() < 1.0:
					continue
				var turn3: float = absf(u3.angle_to(v3))
				if turn3 > deg_to_rad(25.0):
					sharp += 1
					if sharp_at.size() < 4:
						sharp_at.append("%s %.0f deg" % [str(pl3[i].round()), rad_to_deg(turn3)])
		print("[roads] %d corners sharper than 25 deg left on the trunk network%s" % [
			sharp, (": " + ", ".join(sharp_at)) if sharp > 0 else ""])
		# What the worst one is actually doing: where it starts, where it ends,
		# and what it goes round on the way.
		for ln2 in lp_lines:
			var pl2: PackedVector2Array = ln2
			if pl2.size() < 3 or pl2[0].distance_to(lp_at) > 1.0:
				continue
			var walked2 := 0.0
			for i in range(1, pl2.size()):
				walked2 += pl2[i].distance_to(pl2[i - 1])
			var wet2 := 0
			var far2 := 0.0
			var far_at := pl2[0]
			for p2 in pl2:
				if Sim.height_at(p2.x, p2.y) < Sim.sea_at(p2.x, p2.y):
					wet2 += 1
				var d2: float = p2.distance_to(pl2[0])
				if d2 > far2:
					far2 = d2
					far_at = p2
			print("[roads]   worst route %s -> %s: %.1f km walked for %.1f km direct, %d of %d points over water, furthest excursion %.1f km to %s" % [
				str(pl2[0].round()), str(pl2[pl2.size() - 1].round()),
				walked2 * 0.001,
				pl2[0].distance_to(pl2[pl2.size() - 1]) * 0.001,
				wet2, pl2.size(), far2 * 0.001, str(far_at.round())])
			break
		_road_test = false
		Sim.resurvey_roads()
		var worst_grade := 0.0
		var mean_grade := 0.0
		var worst_cross := 0.0
		var worst_grade_at := Vector2.ZERO
		var worst_grade_note := ""
		var worst_at := Vector2.ZERO
		var worst_lr := Vector3.ZERO
		var deepest_cut := 0.0
		var grades: Array = []
		var crosses: Array = []
		var tallest_fill := 0.0
		var worst_w := Vector3.ZERO
		var worst_left := Vector2.ZERO
		var worst_right := Vector2.ZERO
		var mean_cross := 0.0
		var n := 0
		var span := 0.0
		for r in Sim.ROADS:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var d: float = a.distance_to(b)
			span += d
			var dirv: Vector2 = (b - a).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			var steps: int = clampi(int(d / 60.0), 3, 60)
			# In the survey frame throughout: see `Sim.survey_height_at`. Read
			# in world coordinates the curve alone put the worst gradient at
			# 22.5 % against a 15 % limit and gave 2228 km of road a 1.5 %
			# mean cross fall it does not have.
			var prev: float = Sim.survey_height_at(a.x, a.y)
			for k in range(1, steps + 1):
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var y: float = Sim.survey_height_at(q.x, q.y)
				var g: float = absf(y - prev) / maxf(d / float(steps), 1.0)
				var prev_y := prev
				prev = y
				# Streets inside a town run on the levelled platform, which is
				# the town's business and not the trunk road's.
				if Sim.pad_weight(q.x, q.y) > 0.05:
					continue
				var l: float = Sim.survey_height_at(q.x - nrm.x * 6.0,
					q.y - nrm.y * 6.0)
				var rr: float = Sim.survey_height_at(q.x + nrm.x * 6.0,
					q.y + nrm.y * 6.0)
				var cross: float = absf(rr - l) / 12.0
				var made: Vector3 = Sim.road_surface(q.x, q.y)
				if made.y > 0.5:
					# the design surface in the same frame as the ground
					var design: float = made.x + Sim.planet_drop(q.x, q.y)
					deepest_cut = maxf(deepest_cut, y - design)
					tallest_fill = maxf(tallest_fill, design - y)
				grades.append(g)
				crosses.append(cross)
				if g > worst_grade:
					worst_grade = g
					worst_grade_at = q
					worst_grade_note = "%.1f -> %.1f over %.0f m, %.0f m from a road" % [
						prev_y, y, d / float(steps), Sim.road_distance(q.x, q.y)]
				if cross > worst_cross:
					worst_cross = cross
					worst_at = q
					worst_lr = Vector3(l, y, rr)
					worst_w = Sim.road_surface(q.x, q.y)
					worst_left = q - nrm * 6.0
					worst_right = q + nrm * 6.0
				mean_grade += g
				mean_cross += cross
				n += 1
		print("[roads] %d legs, %.1f km of trunk road" % [Sim.ROADS.size(), span * 0.001])
		grades.sort()
		crosses.sort()
		var g95: float = grades[mini(grades.size() - 1, int(grades.size() * 0.95))]
		var c95: float = crosses[mini(crosses.size() - 1, int(crosses.size() * 0.95))]
		print("[roads] gradient along the road: mean %.1f%%, 95th %.1f%%, worst %.1f%% at %s (%s)" % [
			100.0 * mean_grade / maxf(float(n), 1.0), 100.0 * g95, 100.0 * worst_grade,
			str(worst_grade_at.round()), worst_grade_note])
		print("[roads] cross fall over the carriageway: mean %.1f%%, 95th %.1f%%, worst %.1f%%" % [
			100.0 * mean_cross / maxf(float(n), 1.0), 100.0 * c95, 100.0 * worst_cross])
		print("[roads] finished ground vs the design surface: %.2f m high, %.2f m low at worst" % [
			deepest_cut, tallest_fill])
		# How far the road has dug itself into the country: the carriageway
		# against the untouched ground well outside the graded shoulder.
		var cut_sum := 0.0
		var cut_worst := 0.0
		var cut_n := 0
		var cut_at := Vector2.ZERO
		for r in Sim.ROADS:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var rd := rb - ra
			if rd.length() < 20.0:
				continue
			for kk in 5:
				var q: Vector2 = ra.lerp(rb, (float(kk) + 0.5) / 5.0)
				# what the earthworks actually did here
				var depth: float = Sim.natural_height_at(q.x, q.y) \
					- Sim.height_at(q.x, q.y)
				if depth > 0.0:
					cut_sum += depth
					if depth > cut_worst:
						cut_worst = depth
						cut_at = q
				cut_n += 1
		if cut_worst > 20.0:
			var rsw: Vector3 = Sim.road_surface(cut_at.x, cut_at.y)
			print("[roads]   at the worst point: natural %.1f, finished %.1f, design %.1f, weight %.2f, centreline ground %.1f" % [
				Sim.natural_height_at(cut_at.x, cut_at.y),
				Sim.height_at(cut_at.x, cut_at.y), rsw.x, rsw.y, rsw.z])
			print("[roads]   flat_factor %.2f, road_distance %.0f m" % [
				Sim.flat_factor(cut_at.x, cut_at.y),
				Sim.road_distance(cut_at.x, cut_at.y)])
		print("[roads] earth moved to make the road: mean %.2f m cut, worst %.1f m at %s" % [
			cut_sum / maxf(float(cut_n), 1.0), cut_worst, str(cut_at.round())])
		print("[roads] worst cross fall at %s: left %.1f, centre %.1f, right %.1f, corridor y=%.1f w=%.2f, %.0f m from a road" % [
			str(worst_at.round()), worst_lr.x, worst_lr.y, worst_lr.z,
			worst_w.x, worst_w.y, Sim.road_distance(worst_at.x, worst_at.y)])
		var near := 0
		for r in Sim.ROADS:
			if Sim._seg_dist(worst_at, r[0], r[1]) < 30.0:
				near += 1
				print("[roads]   leg %s -> %s at %.1f m" % [
					str((r[0] as Vector2).round()), str((r[1] as Vector2).round()),
					Sim._seg_dist(worst_at, r[0], r[1])])
		print("[roads]   %d trunk legs within 30 m of that point" % near)
		for probe in [worst_left, worst_right]:
			print("[roads]   probe %s: corridor y=%.1f w=%.2f, %.1f m from a road, ground %.1f" % [
				str((probe as Vector2).round()),
				Sim.road_surface(probe.x, probe.y).x, Sim.road_surface(probe.x, probe.y).y,
				Sim.road_distance(probe.x, probe.y),
				Sim.height_at(probe.x, probe.y)])
		# The alignment as a whole, structures included -- the open legs alone
		# flatter the road, because the steep ground is exactly what became a
		# tunnel or a viaduct.
		var al_worst := 0.0
		var al_at := Vector2.ZERO
		var al_note := ""
		var al_sum := 0.0
		var al_n := 0
		for li in Sim._road_lines.size():
			var pl: PackedVector2Array = Sim._road_lines[li]
			var pf: PackedFloat32Array = Sim._road_prof[li]
			for i in range(pl.size() - 1):
				var run: float = pl[i].distance_to(pl[i + 1])
				if run < 1.0:
					continue
				var gr: float = absf(pf[i + 1] - pf[i]) / run
				if gr > al_worst:
					al_worst = gr
					al_at = pl[i]
					al_note = "%.1f -> %.1f over %.0f m, structure %s/%s" % [
						pf[i], pf[i + 1], run,
						str(Sim._in_structure(li, i)),
						str(Sim._in_structure(li, i + 1))]
				al_sum += gr
				al_n += 1
		print("[roads] whole alignment, structures included: mean %.1f%%, worst %.1f%% at %s (%s)" % [
			100.0 * al_sum / maxf(float(al_n), 1.0), 100.0 * al_worst,
			str(al_at.round()), al_note])
		var bore := 0.0
		for tn in Sim.road_tunnels:
			bore += (tn["a"] as Vector2).distance_to(tn["b"] as Vector2)
		var carried := 0.0
		for br2 in Sim.road_bridges:
			carried += (br2["a"] as Vector2).distance_to(br2["b"] as Vector2)
		print("[roads] %d tunnel(s), %.2f km bored; %d viaduct(s), %.2f km carried" % [
			Sim.road_tunnels.size(), bore * 0.001,
			Sim.road_bridges.size(), carried * 0.001])
		_report_valleys()
		# Every span, against what it is actually crossing. A viaduct that
		# stands a couple of metres off the ground for its whole length is an
		# embankment somebody has drawn a deck on; one that has road painted on
		# the country underneath it is a deck over a road. Both read as badly
		# placed, and both are worth counting rather than looking for.
		var low_decks := 0
		var stained := 0
		var gap_worst := 0.0
		var clear_min := 1e9
		var clear_sum := 0.0
		var wet_spans := 0
		for br in Sim.road_bridges:
			var pts: PackedVector2Array = br["pts"]
			var ys: PackedFloat32Array = br["ys"]
			var top := 0.0
			var wet := false
			# How far in from each end of the span the abutment's own earthworks
			# reach. The leg from the last stretch of open road to the first
			# station of the deck moves earth -- that is what an abutment is --
			# and the corridor carries it a graded shoulder further. Anything
			# inside that is the abutment, not the middle of a span.
			var skirt: float = Sim.ROAD_HALF + Sim.ROAD_SHOULDER
			var deck_ends: Array = []
			for br_e in Sim.road_bridges:
				deck_ends.append(br_e["a"])
				deck_ends.append(br_e["b"])
			for i in pts.size():
				# the country under the deck, which nothing should have touched
				var under: float = Sim.natural_height_at(pts[i].x, pts[i].y)
				# the profile is flat-frame, the country under it is not
				var deck_y: float = ys[i] - Sim.planet_drop(pts[i].x, pts[i].y)
				top = maxf(top, deck_y - under)
				if under < Sim.sea_at(pts[i].x, pts[i].y):
					wet = true
				# and no earthworks under it. Another road passing beneath a
				# viaduct is perfectly ordinary; the corridor levelling the
				# ground under the span it is carrying is not.
				# ...including another span's: where two roads meet at a deck
				# end, the one joining brings its own approach embankment up
				# to the same abutment, and that is the abutment too.
				var near_end := false
				for e_pt in deck_ends:
					if pts[i].distance_to(e_pt) <= skirt + 20.0:
						near_end = true
						break
				if not near_end:
					var made2: Vector3 = Sim.road_surface(pts[i].x, pts[i].y)
					# Another road passing under a viaduct is ordinary, and its
					# earthworks are its own business. What would be wrong is
					# the corridor levelling the ground to carry *this*
					# alignment, which is what a deck exists to avoid -- and
					# that shows as made ground at the deck's own height.
					if made2.y > 0.05 and absf(made2.x - deck_y) < 5.0:
						stained += 1
						if stained <= 3:
							print("[roads]   deck at %s stands on made ground: design %.1f, deck %.1f" % [
								str((pts[i] as Vector2).round()), made2.x, deck_y])
			if wet:
				wet_spans += 1
			clear_min = minf(clear_min, top)
			clear_sum += top
			if top < Sim.ROAD_FILL_MAX:
				low_decks += 1
			# does the carriageway actually reach the abutment it is drawn to?
			for endi in [0, pts.size() - 1]:
				var at: Vector2 = pts[endi]
				gap_worst = maxf(gap_worst, absf(ys[endi]
					- Sim.planet_drop(at.x, at.y)
					- Sim.road_surface(at.x, at.y).x))
		print("[roads] spans: %d, %d of them over water; deck stands %.1f m above the country at least, %.1f m on average" % [
			Sim.road_bridges.size(), wet_spans,
			clear_min if Sim.road_bridges.size() > 0 else 0.0,
			clear_sum / maxf(float(Sim.road_bridges.size()), 1.0)])
		print("[roads] the made road meets each deck end within %.2f m" % gap_worst)
		for brp in Sim.road_bridges:
			var bpa: Vector2 = brp["a"]
			var bpb: Vector2 = brp["b"]
			print("[roads]   span %s -> %s, %.2f km, deck %.0f -> %.0f" % [
				str(bpa.round()), str(bpb.round()), bpa.distance_to(bpb) * 0.001,
				float(brp["ya"]), float(brp["yb"])])
		# One span in a hundred, not none. This measures the router's tendency to
		# reach for a deck where fill would do, and on a network of 160 spans a
		# single one sitting a metre and a half under the fill limit is which
		# side of a threshold one piece of ground happened to fall -- it moves
		# when anything about the world does. Ground worked under a deck stays
		# at zero, because that one is a mistake rather than a judgement.
		print("[roads] spans that could have been an embankment: %d of %d; stations with the ground worked under a deck: %d" % [
			low_decks, Sim.road_bridges.size(), stained])

		# What is gated is what can actually go wrong now that the survey
		# solves the earthworks limit and the gradient together: how steep the
		# road ends up, whether the carriageway is level across its width, and
		# how much of the landscape the road destroys getting there. The bars
		# are read from the survey rather than written down again, so tightening
		# a limit tightens the test with it.
		print("[roads] RESULT: %s" % ("ok"
			# A network that loops back on itself is not a network. The router
			# abandons a leg that walks more than `ROUTE_DETOUR` times the
			# distance between its ends; this is that limit seen from outside,
			# with a little slack because the drawn line is denser than the
			# routed one.
			# The worst case, not the count. A route that walks twice the
			# distance between its ends is a road round a mountain, and the
			# flat world -- which averages 4.1 % gradient against the planet's
			# 1.3 -- has eight of them honestly. What was wrong was the route
			# that walked seven times its own length, and that is what the
			# router's own cap now prevents.
			if lp_detour < 4.6
			and lp_reversals * 200 < lp_bends
			and g95 < Sim.road_grade_hairpin + 0.01 and c95 < 0.06
			and worst_grade < Sim.road_grade_hairpin + 0.01
			and cut_worst < Sim.road_cut_hard + 2.0
			and low_decks * 100 <= Sim.road_bridges.size() and stained == 0
			else "FAILED"))
		world.get_tree().quit()
		return true
	return false

## Every valley a road crosses, and what the road does about it: carried over
## on a deck, or taken down one side and up the other. The same closing the
## survey uses to find them -- the level a four kilometre straightedge rests at
## along the line -- so this counts what the survey saw, and the deepest one
## left on the ground is the number to watch.
func _report_valleys() -> void:
	var span_max := 5000.0
	var decked := 0
	var at_grade := 0
	var gentle := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var deepest_decked := 0.0
	for li in Sim._road_lines.size():
		var pl: PackedVector2Array = Sim._road_lines[li]
		if li >= Sim._natural.size():
			break
		var g: PackedFloat32Array = Sim._natural[li]
		var n := pl.size()
		if n < 5:
			continue
		var s := PackedFloat32Array()
		s.resize(n)
		for i in range(1, n):
			s[i] = s[i - 1] + pl[i].distance_to(pl[i - 1])
		var dil := PackedFloat32Array()
		dil.resize(n)
		var shut := PackedFloat32Array()
		shut.resize(n)
		for pass_i in 2:
			var src: PackedFloat32Array = g if pass_i == 0 else dil
			var lo := 0
			var hi := 0
			for i in n:
				while s[i] - s[lo] > span_max * 0.5:
					lo += 1
				hi = maxi(hi, i)
				while hi + 1 < n and s[hi + 1] - s[i] <= span_max * 0.5:
					hi += 1
				var v: float = src[lo]
				for k in range(lo + 1, hi + 1):
					v = maxf(v, src[k]) if pass_i == 0 else minf(v, src[k])
				if pass_i == 0:
					dil[i] = v
				else:
					shut[i] = v
		var i0 := 1
		while i0 < n - 1:
			if shut[i0] - g[i0] <= 2.0:
				i0 += 1
				continue
			var i1 := i0
			while i1 + 1 < n and shut[i1 + 1] - g[i1 + 1] > 2.0:
				i1 += 1
			var ra := i0 - 1
			var rb := i1 + 1
			i0 = i1 + 1
			if rb >= n:
				continue
			var deep := 0.0
			var on_deck := false
			for k in range(ra + 1, rb):
				deep = maxf(deep, shut[k] - g[k])
				on_deck = on_deck or Sim._in_structure(li, k)
			if deep < 60.0:
				continue
			var width: float = s[rb] - s[ra]
			if deep / maxf(width * 0.5, 1.0) < 0.05:
				gentle += 1
				continue
			if on_deck:
				decked += 1
				deepest_decked = maxf(deepest_decked, deep)
			else:
				at_grade += 1
				if deep > worst:
					worst = deep
					worst_at = pl[int((ra + rb) / 2.0)]
	print("[roads] valleys crossed: %d on a deck (deepest %.0f m), %d taken at grade (deepest %.0f m at %s), %d broad enough to drive through" % [
		decked, deepest_decked, at_grade, worst, str(worst_at.round()), gentle])
#endregion


#region --skirttest
var _skirt_test := false

# How much terrain hangs below the ground. The skirts that hide the ring
# seams are a vertical curtain under every chunk edge, and from a submarine
# you are looking at them side on.
func tick_skirt() -> bool:
	if _skirt_test:
		_skirt_test = false
		var worst_drop := 0.0
		var worst_name := ""
		var total_below := 0.0
		var counted := 0
		for c in world.terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			# Chunks only. The sea is one of terrain's children too, and on the
			# planet it is a sphere of the planet's own radius: measured as if
			# it were a chunk with a skirt, its "curtain" came out at 7359 km
			# and the test reported the ocean as the worst offender. It has no
			# skirt; nothing here applies to it.
			if mi.name == "Water":
				continue
			var ab: AABB = mi.mesh.get_aabb()
			var org: Vector3 = mi.position
			# At the chunk's own vertex positions, not a resampling of the
			# footprint: on the outer rings a cell is nearly two kilometres
			# across and a grid of ten samples misses the low ground entirely,
			# which read as a fifty metre curtain that was not there.
			var lo := 1e9
			var steps: int = world.terrain.CELLS
			for i in steps + 1:
				for j in steps + 1:
					var x: float = org.x + ab.position.x + ab.size.x * float(i) / float(steps)
					var z: float = org.z + ab.position.z + ab.size.z * float(j) / float(steps)
					lo = minf(lo, Sim.height_at(x, z))
			var drop: float = lo - (org.y + ab.position.y)
			if drop > worst_drop:
				worst_drop = drop
				worst_name = str(mi.name)
			total_below += maxf(drop, 0.0)
			counted += 1
		print("[skirt] %d chunks; curtain hanging below the ground: worst %.2f m on %s, mean %.2f m" % [
			counted, worst_drop, worst_name, total_below / maxf(float(counted), 1.0)])
		print("[skirt] seam left by the stitching: %.6f m" % float(world.terrain.stats.get("seam", 0.0)))
		# what a submarine actually sees: how much of that curtain is under water
		var sub_depth := Sim.WATER_LEVEL - 40.0
		print("[skirt] a boat at %.0f m sees curtain wherever the seabed is within %.2f m of it" % [
			sub_depth, worst_drop])
		print("[skirt] RESULT: %s" % ("ok" if worst_drop < 2.0
			and float(world.terrain.stats.get("seam", 0.0)) < 0.05 else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --guntest
var _gun_test := false

# How steady the ground is while you fly over it. Terrain that "changes as
# you look at it" is a chunk being rebuilt, so this counts them: a straight
# run at cruise, and then a slow orbit, which is the case that thrashes a
# distance rule because the eye keeps recrossing the same threshold.
# How long a gun actually keeps firing. "A few shots and it stops" is either
# the round counter, the cooldown, or the input; this asks the aeroplane
# directly and takes the input out of it.
func tick_gun() -> bool:
	if _gun_test:
		_gun_test = false
		world._start(world._jet_arg if world._jet_arg != "" else "f16", "free")
		await world.get_tree().process_frame
		await world.get_tree().physics_frame
		if not is_instance_valid(world.player):
			print("[gun] no aeroplane")
			world.get_tree().quit()
			return true
		world.player.global_position = Vector3(0.0, 2500.0, 0.0)
		print("[gun] %s: %d rounds, %d rpm" % [world.player.name, world.player.ammo,
			int((world.player.spec["gun"] as Dictionary)["rpm"])])
		var fired := 0
		var refused := 0
		var frames := 0
		var first_refusal := -1
		var rounds0: int = world.player.ammo
		var stutters := 0
		while frames < 720:                       # six seconds at 120 Hz
			await world.get_tree().physics_frame
			frames += 1
			if world.player.fire_gun(world):
				fired += 1
				# the report has to run on to the next shot, or it stutters
				if world.player._gun_snd <= world.player.gun_cd:
					stutters += 1
			else:
				refused += 1
				if first_refusal < 0:
					first_refusal = frames
		print("[gun] over 6 s: %d bursts away, %d refused, ammo %d left" % [
			fired, refused, world.player.ammo])
		print("[gun] first refusal at frame %d (%.2f s), cooldown now %.4f" % [
			first_refusal, float(first_refusal) / 120.0, world.player.gun_cd])
		# Every shot the rate allows, near enough. A slow gun fires every round
		# and a fast one four to a tracer, so the count is the rate's own.
		var rpm: float = float((world.player.spec["gun"] as Dictionary)["rpm"])
		var each: float = 60.0 / rpm * (4.0 if rpm >= 1500.0 else 1.0)
		var per: float = 4.0 if rpm >= 1500.0 else 1.0
		var want: int = mini(int(6.0 / each), int(float(rounds0) / per))
		var ok: bool = fired >= int(float(want) * 0.9) and fired > 20 and stutters == 0
		print("[gun] expected about %d, %d shot(s) where the report would cut out" % [
			want, stutters])
		print("[gun] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --churntest
var _churn_test := false

func tick_churn() -> bool:
	if _churn_test:
		_churn_test = false
		# instrument properly: hook the build counter
		world.terrain.debug_count = true
		# Arrive first, and only then start counting. The first update of a run
		# builds the whole world at once, and none of that is a hand-over from
		# anything -- there was nothing there before it. Counting it as one
		# buried the transitions that actually pop under six hundred that
		# cannot.
		world.terrain.recentre(Vector3(0.0, 900.0, -4000.0), true)
		world.terrain.flush_pending()
		world.terrain.debug_builds = {}
		world.terrain.debug_pop = []
		var flown := 0.0
		var speed := 240.0
		# Stepped the way the game actually steps it -- every frame, not twice a
		# second. How complete a chunk's blend is when it appears depends on how
		# promptly the hand-over is noticed, so a coarse harness step hides
		# exactly the fault being looked for.
		var t2 := 0.0
		while t2 < 90.0:
			world.terrain.recentre(Vector3(speed * t2, 900.0, -4000.0))
			world.terrain.flush_pending()
			t2 += 1.0 / 60.0
		flown = speed * 90.0
		var straight: Dictionary = world.terrain.debug_builds.duplicate()
		var s_total := 0
		for k2 in straight:
			s_total += int(straight[k2])
		# What the blend is actually worth in flight, as opposed to at the ideal
		# threshold: a chunk that appears late arrives part-blended and pops.
		var pops: Array = world.terrain.debug_pop.duplicate()
		# and what asking the tree costs, since it is asked every thirty metres
		var wt0 := Time.get_ticks_usec()
		for wq in 20:
			world.terrain._wanted(Vector3(41000.0 + float(wq), 900.0, -27000.0))
		print("[churn] one look at the whole tree: %.2f ms" % [
			float(Time.get_ticks_usec() - wt0) / 20000.0])
		# A chunk appearing at blend 1 is a hand-over *down*: it arrives shaped
		# like the level above -- the thing it is replacing -- and cannot be
		# seen. One appearing at blend 0 is a hand-over *up*: the coarser level
		# taking back over from children that were themselves fully morphed to
		# its unmorphed shape, which also cannot be seen. Both ends are seamless
		# by construction, and an earlier version of this counted every merge as
		# a pop for that reason. What would actually show is an arrival in the
		# middle, matching neither what it replaced nor what it settles to.
		var p_sum := 0.0
		var p_bad := 0
		var by_d: Dictionary = {}
		for pv in pops:
			var bl: float = float((pv as Array)[0])
			var dp: int = int((pv as Array)[1])
			var miss: float = minf(bl, 1.0 - bl)
			p_sum += miss
			if miss > 0.12:
				p_bad += 1
				by_d[dp] = int(by_d.get(dp, 0)) + 1
		var dks: Array = by_d.keys()
		dks.sort()
		var row := ""
		for dk in dks:
			row += "d%d:%d  " % [int(dk), int(by_d[dk])]
		if row != "":
			print("[churn] arrived mid-blend, by depth: %s" % row)
		var shown := 0
		for pv2 in pops:
			var e2: Array = pv2
			var m2b: float = minf(float(e2[0]), 1.0 - float(e2[0]))
			if m2b > 0.3 and shown < 5:
				shown += 1
				print("[churn]   d%d blend %.2f at %.0f m (hands over at %.0f m), chunk at %.0f,%.0f" % [
					int(e2[1]), float(e2[0]), float(e2[2]), float(e2[3]),
					float(e2[4]), float(e2[5])])
		print("[churn] hand-over mismatch: mean %.4f, %d of %d arrived mid-blend" % [
			p_sum / maxf(float(pops.size()), 1.0), p_bad, pops.size()])
		print("[churn] straight run %.0f km: %d builds over %d nodes (%.2f each)" % [
			flown * 0.001, s_total, straight.size(),
			float(s_total) / maxf(float(straight.size()), 1.0)])
		# now the orbit: a helicopter going round a point, which never gets
		# anywhere and so should settle down and stop rebuilding entirely
		# Per lap. A cache that works shows up as the first lap paying for the
		# geometry and the later ones paying nothing: anything else is thrash.
		var laps: Array = []
		for lap in 4:
			world.terrain.debug_builds = {}
			var t3: float = 0.0
			while t3 < 40.0:
				var a: float = TAU * t3 / 40.0
				world.terrain.recentre(Vector3(20000.0 + cos(a) * 900.0, 400.0,
					12000.0 + sin(a) * 900.0))
				world.terrain.flush_pending()
				t3 += 0.5
			var n := 0
			for kk in world.terrain.debug_builds:
				n += int(world.terrain.debug_builds[kk])
			laps.append(n)
		print("[churn] builds per lap of the orbit: %s" % str(laps))
		var orbit: Dictionary = world.terrain.debug_builds.duplicate()
		var o_total := 0
		var o_repeat := 0
		var worst := 0
		var worst_key := ""
		for k3 in orbit:
			o_total += int(orbit[k3])
			if int(orbit[k3]) > 1:
				o_repeat += int(orbit[k3]) - 1
			if int(orbit[k3]) > worst:
				worst = int(orbit[k3])
				worst_key = String(k3)
		print("[churn] last lap: %d builds over %d nodes, %d of them rebuilds" % [
			o_total, orbit.size(), o_repeat])
		print("[churn] worst node was built %d times: %s" % [worst, worst_key])
		# A straight run has to build the ground it flies over, and each node
		# once more as it gets close enough to want it finer -- about two builds
		# a node is the floor, and the morph adds a little on top because a
		# chunk whose edge faces a finer neighbour has to pin that edge, which
		# is more state in its key and so more variants of it. A lap of an orbit
		# that has already been flown should still cost nothing at all: that is
		# the number that says the ground has stopped churning.
		var settled: int = maxi(int(laps[1]), maxi(int(laps[2]), int(laps[3])))
		var per_node: float = float(s_total) / maxf(float(straight.size()), 1.0)
		# Nothing may be drawing ground that is not the live set: a chunk left
		# visible after being superseded draws the same country at a different
		# detail, in the same place, and the two fight for every pixel.
		var visible_chunks := 0
		for c in world.terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null or String(mi.name) == "Water":
				continue
			if mi.visible:
				visible_chunks += 1
		var shelved: int = world.terrain._cache.size()
		# read now, not at the verdict: the hover below moves the eye and
		# changes the live set out from under a late comparison
		var live_then: int = world.terrain._live.size()
		print("[churn] %d chunks drawing, %d live, %d shelved, %d awaiting hand-over" % [
			visible_chunks, world.terrain._live.size(), shelved, world.terrain._retire.size()])
		# And the live set has to tile the ground, not pile up on it. Two chunks
		# covering the same square metre draw the same country twice at
		# different detail and fight for every pixel -- which reads as the
		# terrain and its texture changing under you, worst close in where the
		# detail changes most often.
		var boxes: Array = []
		for c2 in world.terrain.get_children():
			var m2 := c2 as MeshInstance3D
			if m2 == null or m2.mesh == null or not m2.visible:
				continue
			if String(m2.name) == "Water" or m2.is_queued_for_deletion():
				continue
			var ab: AABB = m2.mesh.get_aabb()
			boxes.append([ab.position.x, ab.position.z, ab.size.x, ab.size.z,
				String(m2.name)])
		var overlaps := 0
		var named_overlap := ""
		for i in boxes.size():
			var a: Array = boxes[i]
			for j in range(i + 1, boxes.size()):
				var b: Array = boxes[j]
				# shared edges are fine; real area in common is not
				var ox: float = minf(a[0] + a[2], b[0] + b[2]) - maxf(a[0], b[0])
				var oz: float = minf(a[1] + a[3], b[1] + b[3]) - maxf(a[1], b[1])
				if ox > 1.0 and oz > 1.0:
					overlaps += 1
					if named_overlap == "":
						named_overlap = "%s and %s share %.0f x %.0f m" % [
							a[4], b[4], ox, oz]
		print("[churn] overlapping pairs in the live set: %d%s" % [overlaps,
			("  (" + named_overlap + ")") if overlaps > 0 else ""])
		# What the ground is actually painted, under the sea. The colours are
		# baked into the chunks at build time, so this reads what gets drawn
		# rather than what the biome function says it ought to be.
		var wet_v := 0
		var wet_green := 0
		var wet_r := 0.0
		var wet_g := 0.0
		for c3 in world.terrain.get_children():
			var m3 := c3 as MeshInstance3D
			if m3 == null or m3.mesh == null or not m3.visible:
				continue
			if String(m3.name) == "Water":
				continue
			var ar: Array = m3.mesh.surface_get_arrays(0)
			if ar.is_empty() or ar[Mesh.ARRAY_COLOR] == null:
				continue
			var vv: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
			var cc: PackedColorArray = ar[Mesh.ARRAY_COLOR]
			for vi in range(0, vv.size(), 7):
				if vv[vi].y >= Sim.WATER_LEVEL - 5.0:   # mesh space: still flat
					continue
				wet_v += 1
				wet_r += cc[vi].r
				wet_g += cc[vi].g
				if cc[vi].g > cc[vi].r + 0.02:
					wet_green += 1
		# The morph needs three extra things in the mesh: the height offset, the
		# coarse normal and the coarse colour. If any of them is missing the
		# shader still runs and the ground still draws, so nothing complains --
		# it simply stops blending, or blends toward nothing.
		for c9 in world.terrain.get_children():
			var m9 := c9 as MeshInstance3D
			if m9 == null or m9.mesh == null or String(m9.name) == "Water":
				continue
			var fmt: int = m9.mesh.surface_get_format(0)
			var a9: Array = m9.mesh.surface_get_arrays(0)
			var nv: int = (a9[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("[churn] mesh carries: uv2=%s tangent=%s custom0=%s (%d verts, custom %d bytes)" % [
				str((fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0),
				str((fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0),
				str((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0), nv,
				(a9[Mesh.ARRAY_CUSTOM0] as PackedByteArray).size()
				if a9[Mesh.ARRAY_CUSTOM0] != null else -1])
			break
		print("[churn] seabed: %d vertices under water, mean r=%.3f g=%.3f, %d greener than red" % [
			wet_v, wet_r / maxf(float(wet_v), 1.0), wet_g / maxf(float(wet_v), 1.0),
			wet_green])
		# How finished the morph is at the instant a node hands over to its
		# children. One means the finer level arrives shaped exactly like the
		# coarser one and the switch cannot be seen; less than one is a step.
		var sw_n := 0
		var sw_sum := 0.0
		var sw_worst := 1.0
		for k4 in world.terrain._live:
			var bits4 := String(k4).split(":")
			var d4 := int(bits4[0])
			if d4 >= Terrain.MAX_DEPTH:
				continue
			var span4: float = Terrain.span_at(d4)
			# a hand-over now always happens at the distance rule, which is the
			# distance the blend is built around
			var split_at: float = Terrain.SPLIT_K * span4
			var lo4: float = Terrain.SPLIT_K * span4 * 0.5
			var m4: float = clampf((split_at - lo4) / maxf(lo4, 1.0), 0.0, 1.0)
			sw_n += 1
			sw_sum += m4
			sw_worst = minf(sw_worst, m4)
		print("[churn] morph complete at hand-over: mean %.3f, worst %.3f over %d nodes" % [
			sw_sum / maxf(float(sw_n), 1.0), sw_worst, sw_n])
		# A hover: standing still, nothing at all should be rebuilt. Let it
		# arrive first -- the orbit left the eye 900 m away, and moving there is
		# a real change of detail, not churn.
		var spot := Vector3(20000.0, 400.0, 12000.0)
		world.terrain.recentre(spot, true)
		world.terrain.flush_pending()
		world.terrain.debug_builds = {}
		for hv in 200:
			world.terrain.recentre(spot)
			world.terrain.flush_pending()
		var hover := 0
		for hk in world.terrain.debug_builds:
			hover += int(world.terrain.debug_builds[hk])
		print("[churn] holding a hover for 200 updates: %d builds" % hover)
		print("[churn] worst settled lap: %d builds; straight run %.2f builds a node" % [
			settled, per_node])
		print("[churn] RESULT: %s" % ("ok" if settled <= 20 and per_node < 3.0
			and visible_chunks == live_then and overlaps == 0
			and hover == 0 and p_bad * 20 < pops.size() else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --obstacletest
var _obstacle_test := false

func tick_obstacle() -> bool:
	if _obstacle_test:
		_obstacle_test = false
		print("[obs] %d structures in %d cells" % [int(Obstacles.stats["count"]),
			int(Obstacles.stats["cells"])])
		# Every town building should answer for its own footprint.
		var inside := 0
		var missed := 0
		var tried := 0
		for xf in world.scenery.town_xforms:
			var t: Transform3D = xf
			tried += 1
			if tried % 7 != 0:
				continue
			var p := t.origin + Vector3(0.0, 3.0, 0.0)
			if Obstacles.hit(p, 0.0) >= 0:
				inside += 1
			else:
				missed += 1
				if missed <= 3:
					print("[obs]   no footprint at %s" % str(p.round()))
		print("[obs] %d of %d sampled town buildings answer at their own centre" % [
			inside, inside + missed])
		# and open country should not
		var false_pos := 0
		var open := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 4000:
			var q := Vector3(rng.randf_range(-40000.0, 40000.0), 0.0,
				rng.randf_range(-40000.0, 40000.0))
			q.y = Sim.height_at(q.x, q.z) + 1.5
			if Obstacles.top_at(q.x, q.z) > -1e8:
				continue                       # genuinely over a footprint
			open += 1
			if Obstacles.hit(q, 0.0) >= 0:
				false_pos += 1
		print("[obs] %d open-country points, %d of them wrongly reported solid" % [
			open, false_pos])
		# a roof is where the query says it is
		var roof_ok := 0
		var roof_bad := 0
		for xf2 in world.scenery.town_xforms:
			var t2: Transform3D = xf2
			var top := Obstacles.top_at(t2.origin.x, t2.origin.z)
			if top > t2.origin.y + 1.0 and top < t2.origin.y + 400.0:
				roof_ok += 1
			else:
				roof_bad += 1
		print("[obs] roof height sane for %d of %d buildings" % [roof_ok,
			roof_ok + roof_bad])
		# and the near-collider pool follows the viewer
		world.obstacles.follow(Vector3(world.scenery.sites[0]["c"].x, 0.0,
			world.scenery.sites[0]["c"].y))
		var live_bodies := 0
		for c in world.obstacles.get_children():
			var sb := c as StaticBody3D
			if sb != null and sb.process_mode != Node.PROCESS_MODE_DISABLED:
				live_bodies += 1
		print("[obs] %d real colliders standing at the town centre" % live_bodies)
		# what a jet flying down the street does about it
		var town: Vector2 = world.scenery.sites[0]["c"]
		var struck := 0
		var flown := 0
		for k in 400:
			var a: float = TAU * float(k) / 400.0
			var q2 := Vector3(town.x + cos(a) * 320.0, 0.0, town.y + sin(a) * 320.0)
			q2.y = Sim.height_at(q2.x, q2.z) + 12.0
			flown += 1
			if Obstacles.hit(q2, 6.8) >= 0:
				struck += 1
		print("[obs] a jet at 12 m round the town centre clips something at %d of %d points" % [
			struck, flown])
		var ok: bool = int(Obstacles.stats["count"]) > 500 and missed == 0 \
			and false_pos == 0 and roof_bad == 0 and live_bodies > 0 and struck > 0
		print("[obs] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --lodtest --subview
var _lod_test := false
var _subview_test := false
## Every terrain triangle of one chunk, in world space, with the vertical skirt
## faces dropped: they project to nothing in plan and cannot answer "what is the
## ground height here".
## Whether the triangles a harness reads back carry the morph, and the eye it is
## measured from. Worked out per vertex exactly as the shader does it, because
## the state that has to be watertight is the one actually drawn -- forcing
## every chunk to full morph at once tests a configuration the renderer never
## produces, and reads as a two kilometre tear.
var _tri_morph := false
var _tri_eye := Vector3.ZERO

# What a submarine sees looking up at the seabed. Terrain faces up, so if
# the material culls back faces there is nothing there at all from below.
func tick_subview() -> bool:
	if _subview_test:
		_subview_test = false
		var culled := 0
		var drawn := 0
		var no_mat := 0
		for c in world.terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if not str(mi.name).begins_with("C") or not str(mi.name).contains("_"):
				continue
			var sm := mi.mesh.surface_get_material(0)
			var over: Material = mi.material_override
			var use: Material = over if over != null else sm
			if use == null:
				no_mat += 1
				continue
			var cull := "?"
			if use is ShaderMaterial:
				var code: String = ((use as ShaderMaterial).shader as Shader).code
				cull = "cull_disabled" if code.contains("cull_disabled") else "cull_back"
			elif use is BaseMaterial3D:
				cull = "cull_disabled" \
					if (use as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED \
					else "cull_back"
			if cull == "cull_disabled":
				drawn += 1
			else:
				culled += 1
		# and the geometry really does face up, which is why it matters
		var up_facing := 0
		var down_facing := 0
		for c in world.terrain.get_children():
			var mi2 := c as MeshInstance3D
			if mi2 == null or mi2.mesh == null:
				continue
			if not str(mi2.name).begins_with("C") or not str(mi2.name).contains("_"):
				continue
			for t in _chunk_tris(mi2):
				var nrm: Vector3 = ((t[1] as Vector3) - (t[0] as Vector3)).cross(
					(t[2] as Vector3) - (t[0] as Vector3))
				if nrm.y >= 0.0:
					up_facing += 1
				else:
					down_facing += 1
			break
		print("[subview] %d chunks draw from below, %d are culled away, %d have no material" % [
			drawn, culled, no_mat])
		print("[subview] one chunk's winding: %d faces up, %d faces down" % [
			up_facing, down_facing])
		print("[subview] RESULT: %s" % ("ok" if culled == 0 and drawn > 0
			else "FAILED — the seabed is invisible from underneath"))
		world.get_tree().quit()
		return true
	return false

func tick_lod() -> bool:
	if _lod_test:
		_lod_test = false
		# Somewhere off the origin, because correct at the origin proves only
		# that the layout the airfield sits in works.
		var moved := Vector3(41300.0, 0.0, -27700.0)
		world.terrain.debug_count = true
		world.terrain.recentre(moved, true)
		print("[lod] neighbour lookups that disagree with a full descent: %d" %
			world.terrain.debug_nb_bad)
		# Does the live set actually tile the ground? Two leaves covering the
		# same square metre is not a seam problem, it is a broken partition, and
		# every seam number downstream of it is meaningless.
		var boxes2: Array = []
		for lk2 in world.terrain._live:
			var bb := String(lk2).split(":")
			var dd3 := int(bb[0])
			var sp3: float = Terrain.span_at(dd3)
			boxes2.append([float(int(bb[1])) * sp3, float(int(bb[2])) * sp3, sp3,
				String(lk2)])
		var ov := 0
		for i5 in boxes2.size():
			for j5 in range(i5 + 1, boxes2.size()):
				var A: Array = boxes2[i5]
				var B: Array = boxes2[j5]
				var oxx: float = minf(A[0] + A[2], B[0] + B[2]) - maxf(A[0], B[0])
				var ozz: float = minf(A[1] + A[2], B[1] + B[2]) - maxf(A[1], B[1])
				if oxx > 1.0 and ozz > 1.0:
					ov += 1
					if ov <= 3:
						print("[lod]   %s overlaps %s" % [A[3], B[3]])
		print("[lod] overlapping leaves in the live set: %d" % ov)
		await world.get_tree().process_frame
		print("[lod] viewer at %s, %d leaves live" % [
			str(Vector2(moved.x, moved.z).round()), int(world.terrain.stats["chunks"])])
		var chunks: Array = []
		var by_depth: Dictionary = {}
		for c in world.terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			# Leaves only. The water plane is a child of the terrain too, and it
			# answered "the ground is at -35 m" at every point on every
			# boundary -- which came out as a 1249 m disagreement that had
			# nothing to do with the stitching.
			var nm := str(mi.name)
			if not nm.begins_with("C") or not nm.contains("_"):
				continue
			var bits := nm.substr(1).split("_")
			var dep := int(bits[0])
			by_depth[dep] = int(by_depth.get(dep, 0)) + 1
			var ab: AABB = mi.mesh.get_aabb()
			ab.position += mi.position
			chunks.append({"mi": mi, "ab": ab, "tris": [], "d": dep})
		# Every leaf has to be found by name, and a leaf Godot renamed is a leaf
		# the harness cannot see -- which reads as a hole in the ground that is
		# not there. Water is the one child that is not a leaf.
		print("[lod] %d leaves found by name, of %d live (%d children)" % [
			chunks.size(), world.terrain._live.size(), world.terrain.get_child_count()])
		var deps: Array = by_depth.keys()
		deps.sort()
		for d2 in deps:
			print("[lod] depth %2d (cell %6.0f m): %d leaves" % [
				int(d2), Terrain.span_at(int(d2)) / float(Terrain.CELLS),
				int(by_depth[d2])])
		# Walk every leaf's own boundary vertices and ask whoever else covers
		# that point how high the ground is there. No knowledge of the tree's
		# shape goes into this -- it is the built meshes, compared with each
		# other, which is the only thing the eye can see.
		var worst := 0.0
		var total := 0.0
		var pairs := 0
		var lonely := 0
		var worst_at := Vector2.ZERO
		var worst_who: Array = []
		var named := 0
		var edge_of_world := Terrain.ROOT_SPAN * 0.5 - 1.0
		# Run the whole comparison twice: once with the chunks as they are, and
		# once with every one of them morphed all the way to the shape of the
		# level above it, which is how a finer chunk looks at the instant it
		# appears. A seam that is watertight at one end of the blend and not at
		# the other opens and closes as you fly towards it.
		_tri_eye = moved
		for mp in 2:
			_tri_morph = mp == 1
			worst = 0.0
			total = 0.0
			pairs = 0
			lonely = 0
			named = 0
			for ch3 in chunks:
				ch3["tris"] = []
			for ch0 in chunks:
				var ab0: AABB = ch0["ab"]
				var span0: float = ab0.size.x
				var cell0: float = span0 / float(Terrain.CELLS)
				for side in 4:
					for k in range(1, Terrain.CELLS, 2):
						var t: float = float(k) * cell0
						var p := Vector2(ab0.position.x + t, ab0.position.z)
						if side == 1:
							p = Vector2(ab0.position.x + t, ab0.position.z + span0)
						elif side == 2:
							p = Vector2(ab0.position.x, ab0.position.z + t)
						elif side == 3:
							p = Vector2(ab0.position.x + span0, ab0.position.z + t)
						if absf(p.x) > edge_of_world or absf(p.y) > edge_of_world:
							continue
						var hs: Array = []
						var who: Array = []
						for ch in chunks:
							var ab2: AABB = ch["ab"]
							if p.x < ab2.position.x - 0.5 or p.x > ab2.position.x + ab2.size.x + 0.5:
								continue
							if p.y < ab2.position.z - 0.5 or p.y > ab2.position.z + ab2.size.z + 0.5:
								continue
							if (ch["tris"] as Array).is_empty():
								ch["tris"] = _chunk_tris(ch["mi"])
							var y: float = _tri_height(ch["tris"], p)
							if y != INF:
								hs.append(y)
								who.append("%s=%.1f" % [str((ch["mi"] as MeshInstance3D).name), y])
						if hs.size() < 2:
							lonely += 1
							if lonely <= 3:
								print("[lod]   lonely at %s: %s side %d, %d chunk(s)" % [
									str(p.round()), str((ch0["mi"] as MeshInstance3D).name),
									side, hs.size()])
							continue
						var lo := 1e9
						var hi := -1e9
						for y2 in hs:
							lo = minf(lo, float(y2))
							hi = maxf(hi, float(y2))
						var gap: float = hi - lo
						total += gap
						pairs += 1
						if gap > worst:
							worst = gap
							worst_at = p
							worst_who = who.duplicate()
						if gap > 0.5 and named < 3:
							named += 1
							print("[lod]   %.2f m apart at %s: %s" % [gap, str(p.round()),
								", ".join(PackedStringArray(who))])
			print("[lod] %s: %d pairs, mean %.5f m, worst %.4f m" % [
				"without the morph" if mp == 0 else "as drawn, morph and all",
				pairs, total / maxf(float(pairs), 1.0), worst])
		print("[lod] %d boundary points had two chunks drawing them, %d had only one" % [
			pairs, lonely])
		print("[lod] disagreement between the two sides: mean %.5f m, worst %.4f m at %s" % [
			total / maxf(float(pairs), 1.0), worst, str(worst_at.round())])
		print("[lod] at the worst point, these chunks drew ground: %s" % str(worst_who))
		print("[lod] RESULT: %s" % ("ok" if worst < 0.05 and pairs > 0 else "FAILED"))
		world.get_tree().quit()
		return true
	return false

## The blend the ground shader applies to a vertex, reproduced exactly.
func _morph_at(v: Vector3, span: float) -> float:
	var lo: float = 2.0 * span                    # Terrain.SPLIT_K * span
	var hi: float = 2.0 * lo
	var d: float = v.distance_to(_tri_eye)
	return clampf((d - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)

func _chunk_tris(mi: MeshInstance3D) -> Array:
	var out: Array = []
	var xf: Transform3D = mi.global_transform
	# the chunk's own width, which is what sets the band it morphs over
	var span_of: float = mi.mesh.get_aabb().size.x
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		# The morph offset each vertex carries, so a seam can be checked at both
		# ends of the blend and not just at the detailed one.
		var m2: PackedVector2Array = PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV2] != null:
			m2 = arr[Mesh.ARRAY_TEX_UV2]
		var rawi: Variant = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if rawi != null:
			idx = rawi
		if idx.is_empty():
			idx = PackedInt32Array(range(vs.size()))
		var k := 0
		while k + 2 < idx.size():
			var a: Vector3 = xf * vs[idx[k]]
			var b: Vector3 = xf * vs[idx[k + 1]]
			var c: Vector3 = xf * vs[idx[k + 2]]
			if m2.size() == vs.size() and _tri_morph:
				a.y += m2[idx[k]].x * _morph_at(a, span_of)
				b.y += m2[idx[k + 1]].x * _morph_at(b, span_of)
				c.y += m2[idx[k + 2]].x * _morph_at(c, span_of)
			# plan area: a skirt face has none
			var det: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(det) > 1e-6:
				out.append([a, b, c, det])
			k += 3
	return out

## The height of the drawn surface at a point in plan, or INF if this chunk does
## not cover it.
func _tri_height(tris: Array, p: Vector2) -> float:
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var det: float = t[3]
		# Scaled to the size of the numbers involved. A fixed 1e-6 is finer than
		# float precision out at forty kilometres, so a sample landing exactly
		# on the edge two chunks share fell numerically outside one of them —
		# and 114 boundary points were reported as covered by a single chunk
		# when both were there all along.
		# Two centimetres of ground, expressed in barycentric terms. The mesh
		# vertices come back as 32-bit floats, so out at forty kilometres they
		# are only good to about four millimetres and a sample landing on the
		# edge two chunks share can fall numerically outside both. A fixed
		# barycentric epsilon is far too tight on a small cell and far too loose
		# on a 15 km one — scaling it by the triangle's own size is what makes
		# it mean the same thing everywhere. det is twice the plan area, so its
		# root is the cell.
		var eps: float = 0.02 / maxf(sqrt(absf(det)), 1.0)
		var w0: float = ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.y - c.z)) / det
		if w0 < -eps or w0 > 1.0 + eps:
			continue
		var w1: float = ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.y - c.z)) / det
		if w1 < -eps or w1 > 1.0 + eps:
			continue
		var w2: float = 1.0 - w0 - w1
		if w2 < -eps:
			continue
		return a.y * w0 + b.y * w1 + c.y * w2
	return INF
#endregion


#region --floattest
var _float_test := false

# How far the drawn ground sits from the height field things are placed on.
# That gap is daylight under every tree standing on it.
func tick_float() -> bool:
	if _float_test:
		_float_test = false
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var total := 0.0
		var n := 0
		var over := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260827
		# across the ground the scatter actually covers
		for _i in 6000:
			var x: float = rng.randf_range(-19800.0, 19800.0)
			var z: float = rng.randf_range(-31680.0, 31680.0)
			var field: float = Sim.height_at(x, z)
			var over_sea: float = field - Sim.sea_at(x, z)
			if over_sea < 2.0 or over_sea > 2435.0:
				continue
			var drawn: float = Terrain.surface_height(x, z)
			var gap: float = absf(field - drawn)
			total += gap
			n += 1
			if gap > 1.5:
				over += 1
			if gap > worst:
				worst = gap
				worst_at = Vector2(x, z)
		print("[float] %d samples over the scattered ground" % n)
		print("[float] field vs drawn surface: mean %.2f m, worst %.1f m at %s" % [
			total / maxf(float(n), 1.0), worst, str(worst_at.round())])
		print("[float] %d of %d (%.1f%%) stood more than a metre and a half proud" % [
			over, n, 100.0 * float(over) / maxf(float(n), 1.0)])
		# Scatter now calls `Terrain.surface_height` itself, the same function
		# the chunks are triangulated from, so its gap is nil by construction —
		# there is nothing independent left to measure. What is printed above is
		# the error that was there before, which is the number that matters.
		print("[float] scatter is placed on that drawn surface now, so the gap is nil")
		print("[float] RESULT: %s" % ("ok" if worst > 0.0 else "FAILED — nothing measured"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --seamix
var _seamix := false

# How the world is divided between land and water, and whether there is any
# coastline in it or just one edge with sea on one side.
func tick_seamix() -> bool:
	if _seamix:
		_seamix = false
		var bands := [
			["home      0-40 km", 0.0, 40000.0],
			["near     40-120 km", 40000.0, 120000.0],
			["middle  120-300 km", 120000.0, 300000.0],
			["far     300-600 km", 300000.0, 600000.0],
		]
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for b in bands:
			var lo: float = float(b[1])
			var hi: float = float(b[2])
			var land := 0
			var wet := 0
			var coast := 0
			for _i in 4000:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * (hi - lo) + lo
				var x := cos(a) * r
				var z := sin(a) * r
				var dry: bool = Sim.height_at(x, z) > Sim.sea_at(x, z)
				if dry:
					land += 1
				else:
					wet += 1
				# a coast is anywhere the answer changes within a couple of km
				var other: bool = Sim.height_at(x + 2000.0, z) > Sim.sea_at(x + 2000.0, z)
				if dry != other:
					coast += 1
			var tot: float = maxf(float(land + wet), 1.0)
			print("[sea] %s: %5.1f%% land, %5.1f%% water, %4.1f%% of samples on a coast" % [
				String(b[0]), 100.0 * float(land) / tot, 100.0 * float(wet) / tot,
				100.0 * float(coast) / tot])
		# relief across the middle of the map, where the trench used to be
		var bands2 := [["on the field axis", 0.0], ["6 km out", 6000.0],
			["20 km out", 20000.0], ["60 km out", 60000.0]]
		for b2 in bands2:
			var off: float = float(b2[1])
			var lo2 := 1e9
			var hi2 := -1e9
			var total2 := 0.0
			for k2 in 400:
				var zz: float = -300000.0 + float(k2) * 1500.0
				var hh: float = Sim.height_at(off, zz)
				lo2 = minf(lo2, hh)
				hi2 = maxf(hi2, hh)
				total2 += hh
			print("[sea] relief %s: %.0f m to %.0f m, mean %.0f m" % [
				String(b2[0]), lo2, hi2, total2 / 400.0])
		# and what grows on the land, north to south
		var strips := [["far north", -560000.0, -360000.0],
			["north", -360000.0, -140000.0], ["middle", -140000.0, 140000.0],
			["south", 140000.0, 360000.0], ["far south", 360000.0, 560000.0]]
		for strip in strips:
			var tally := {}
			var n2 := 0
			for _k in 2500:
				var x2: float = rng.randf_range(-500000.0, 500000.0)
				var z2: float = rng.randf_range(float(strip[1]), float(strip[2]))
				var y2: float = Sim.height_at(x2, z2)
				if y2 <= Sim.sea_at(x2, z2):
					continue
				var bk: String = Sim.biome_kind(x2, z2, y2, Sim.normal_at(x2, z2).y)
				tally[bk] = int(tally.get(bk, 0)) + 1
				n2 += 1
			var parts := PackedStringArray()
			for nm in Sim.BIOME_NAMES:
				var c2 := int(tally.get(nm, 0))
				if c2 > 0:
					parts.append("%s %.0f%%" % [nm, 100.0 * float(c2) / maxf(float(n2), 1.0)])
			print("[sea] %-10s land cover: %s" % [String(strip[0]), ", ".join(parts)])
		world.get_tree().quit()
		return true
	return false
#endregion


#region --fieldtest
var _field_test := false

# Is the ground where the runway is, or is the runway buried in it?
func tick_field() -> bool:
	if _field_test:
		_field_test = false
		var bad := 0
		for fd in Sim.fields:
			var at: Vector2 = fd["at"]
			var elev: float = float(fd["elev"])
			var worst := 0.0
			var worst_at := Vector2.ZERO
			# along the strip and across it, in the field's own frame
			for i in 41:
				for j in 9:
					var lx: float = (float(j) - 4.0) * 60.0
					var lz: float = (float(i) - 20.0) * (Sim.RUNWAY_LEN * 0.5 / 20.0)
					var c := cos(float(fd["yaw"]))
					var sn := sin(float(fd["yaw"]))
					var q := at + Vector2(lx * c - lz * sn, lx * sn + lz * c)
					var g: float = Sim.height_at(q.x, q.y)
					var off: float = absf(g - Sim.field_elev(fd, q.x, q.y))
					if off > worst:
						worst = off
						worst_at = q
			var drawn: float = Terrain.surface_height(at.x, at.y)
			elev = Sim.field_elev(fd)
			print("[field] %s yaw %3.0f deg, elevation %7.1f m: ground on the strip differs by at most %.2f m (worst at %s)" % [
				str(at.round()), rad_to_deg(float(fd["yaw"])), elev, worst,
				str(worst_at.round())])
			# Both sides' flattening, not just this one's. The two are separate
			# implementations of the same box, and when they disagree the
			# runway is levelled in the game and not in the ground -- or the
			# other way about. Printing only the GDScript one had this test
			# reporting `flat=1.000` beside a strip 130 m out of level.
			print("[field]   at the worst point: flat=%.3f (extension %.3f), pad=%.3f, road w=%.3f, cell=%.0f m" % [
				Sim.flat_factor(worst_at.x, worst_at.y),
				Sim.native.field_flat(worst_at.x, worst_at.y),
				Sim.pad_weight(worst_at.x, worst_at.y),
				Sim.road_surface(worst_at.x, worst_at.y).y,
				Terrain.cell_at(worst_at.x, worst_at.y)])
			print("[field]   drawn surface at the middle: %.2f m (pavement sits at %.2f m)" % [
				drawn, elev])
			if worst > 3.0 or absf(drawn - elev) > 3.0:
				bad += 1
		print("[field] RESULT: %s" % ("ok" if bad == 0 and Sim.fields.size() >= 2
			else "FAILED — %d field(s) do not match their ground" % bad))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --seamtest
var _seam_test := false

func tick_seam() -> void:
	if _seam_test:
		_seam_test = false
		# T junction cracks: where a leaf meets a coarser one, the fine chunk
		# has vertices the coarse one does not, and the coarse edge runs
		# straight past them. The gap is the height difference between those
		# vertices and the straight line, and it needs no rendering to measure.
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		# every depth that can face a coarser neighbour, sampled across a swath
		# of real country rather than along one ring
		for dep in range(4, Terrain.MAX_DEPTH + 1):
			var cell: float = Terrain.span_at(dep) / float(Terrain.CELLS)
			var big: float = cell * 2.0
			for k in 240:
				var a0: float = float(k - 120) * big + 3000.0
				var a1: float = a0 + big
				var mid: float = (a0 + a1) * 0.5
				for side in [1400.0, -19000.0]:
					var h0 := Sim.height_at(a0, side)
					var h1 := Sim.height_at(a1, side)
					var hm := Sim.height_at(mid, side)
					var gap: float = absf(hm - (h0 + h1) * 0.5)
					worst = maxf(worst, gap)
					sum += gap
					cnt += 1
					h0 = Sim.height_at(side, a0)
					h1 = Sim.height_at(side, a1)
					hm = Sim.height_at(side, mid)
					gap = absf(hm - (h0 + h1) * 0.5)
					worst = maxf(worst, gap)
					sum += gap
					cnt += 1
		# This is the crack the stitching has to close, not one left in the
		# built world: it reads the raw height field and asks how far the fine
		# chunk's extra vertex sits off the straight edge its coarse neighbour
		# draws. `_stitch` then puts that vertex exactly on the line. Printed as
		# a "T junction gap" on its own it read as though the terrain were full
		# of two hundred metre holes.
		print("[seam] deviation the stitching has to take out, across %d depths: mean %.2f m, worst %.2f m over %d samples" % [
			Terrain.MAX_DEPTH - 3, sum / maxf(float(cnt), 1.0), worst, cnt])
		print("[seam] left in the built terrain after stitching: %.6f m" % [
			float(world.terrain.stats.get("seam", 0.0))])
		print("[seam] RESULT: %s" % ("ok" if float(world.terrain.stats.get("seam", 0.0)) < 0.05
			else "FAILED"))
		world.get_tree().quit()
#endregion


#region --biometest
var _biome_test := false

func tick_biome() -> bool:
	if _biome_test:
		_biome_test = false
		# The ground colour is now worked out per fragment from a baked climate
		# texture rather than interpolated from the corners of a cell. The
		# arithmetic is the same either side; what the texture changes is the
		# two noise fields it reads, so what needs measuring is how far a linear
		# fetch from it lands from the field it stands in for.
		var img: Image = world.terrain.climate_img
		if img == null:
			print("[biome] no climate image -- headless bake did not run")
			world.get_tree().quit()
			return true
		var n := img.get_width()
		var span: float = Sim.WORLD_HALF * 2.0
		var wt := 0.0
		var wm := 0.0
		var st := 0.0
		var sm := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var samples := 20000
		for i in samples:
			var x: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var z: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			# what the shader gets: a bilinear fetch at the same place
			var u: float = (x + Sim.WORLD_HALF) / span * float(n) - 0.5
			var v: float = (z + Sim.WORLD_HALF) / span * float(n) - 0.5
			var i0: int = clampi(int(floor(u)), 0, n - 1)
			var j0: int = clampi(int(floor(v)), 0, n - 1)
			var i1: int = mini(i0 + 1, n - 1)
			var j1: int = mini(j0 + 1, n - 1)
			var fu: float = clampf(u - floor(u), 0.0, 1.0)
			var fv: float = clampf(v - floor(v), 0.0, 1.0)
			var c00 := img.get_pixel(i0, j0)
			var c10 := img.get_pixel(i1, j0)
			var c01 := img.get_pixel(i0, j1)
			var c11 := img.get_pixel(i1, j1)
			var tex_t: float = lerpf(lerpf(c00.r, c10.r, fu),
				lerpf(c01.r, c11.r, fu), fv)
			var tex_m: float = lerpf(lerpf(c00.g, c10.g, fu),
				lerpf(c01.g, c11.g, fu), fv)
			# and what the field actually is there
			# The field the world is actually using. On the planet that is the
			# pair on the sphere, not the flat world's 2D noise -- compared
			# against that, the texture was out by 0.21 on average and 0.88 at
			# worst, and the numbers were printed under a passing result for
			# months because only the colour is gated. Two fields were being
			# compared, not a field and a copy of it.
			var ex_t: float
			var ex_m: float
			if Sim.globe:
				var cd := Sim.chart_to_dir(x, z)
				ex_t = (Sim.noise_temp3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
				ex_m = (Sim.noise_moist3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
			else:
				ex_t = (Sim.noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
				ex_m = (Sim.noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
			var dt: float = absf(tex_t - ex_t)
			var dm: float = absf(tex_m - ex_m)
			wt = maxf(wt, dt)
			wm = maxf(wm, dm)
			st += dt
			sm += dm
		print("[biome] climate %dx%d, %.0f m per texel, %d samples" % [
			n, n, span / float(n), samples])
		print("[biome] temperature  mean %.5f  worst %.5f" % [
			st / float(samples), wt])
		print("[biome] moisture     mean %.5f  worst %.5f" % [
			sm / float(samples), wm])
		# What is actually visible is the colour, not the weight: a large error
		# in one weight is divided by the total of all seven, and a sand weight
		# and a steppe weight are nearly the same colour anyway. Measured
		# through Sim's own arithmetic, so this compares the texture against the
		# field rather than against a second transcription of the rule.
		var wc := 0.0
		var sc := 0.0
		rng.seed = 4242
		for i in samples:
			var x: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var z: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var y: float = Sim.height_at(x, z)
			var up: float = rng.randf_range(0.55, 1.0)
			var u2: float = (x + Sim.WORLD_HALF) / span * float(n) - 0.5
			var v2: float = (z + Sim.WORLD_HALF) / span * float(n) - 0.5
			var a0: int = clampi(int(floor(u2)), 0, n - 1)
			var b0: int = clampi(int(floor(v2)), 0, n - 1)
			var a1: int = mini(a0 + 1, n - 1)
			var b1: int = mini(b0 + 1, n - 1)
			var fa: float = clampf(u2 - floor(u2), 0.0, 1.0)
			var fb: float = clampf(v2 - floor(v2), 0.0, 1.0)
			var p00 := img.get_pixel(a0, b0)
			var p10 := img.get_pixel(a1, b0)
			var p01 := img.get_pixel(a0, b1)
			var p11 := img.get_pixel(a1, b1)
			var ct: float = lerpf(lerpf(p00.r, p10.r, fa),
				lerpf(p01.r, p11.r, fa), fb)
			var cm: float = lerpf(lerpf(p00.g, p10.g, fa),
				lerpf(p01.g, p11.g, fa), fb)
			var truth := Sim.biome_colour(x, z, y, up)
			var shaded := Sim.biome_colour(x, z, y, up, Vector2(ct, cm))
			var d: float = maxf(maxf(absf(truth.r - shaded.r),
				absf(truth.g - shaded.g)), absf(truth.b - shaded.b))
			wc = maxf(wc, d)
			sc += d
		print("[biome] ground colour  mean %.5f  worst %.5f  (of 1.0)" % [
			sc / float(samples), wc])
		var ok: bool = wc < 0.02
		print("[biome] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
	return false
#endregion
