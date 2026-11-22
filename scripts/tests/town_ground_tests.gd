class_name TownGroundTests
extends TestSuite
## The ground a man walks on in and between the towns: probes of the drawn
## surface against what he stands on, bridge decks and their ends, junctions
## and the deck physics bodies.
##
## Command-line tests, split out of `infantry_tests.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--groundprobe":
		_ground_probe = true
	elif a == "--bridgeprobe":
		_bridge_probe = true
	elif a == "--bridgedrive":
		_bridge_drive = true
	elif a == "--rampground":
		_ramp_ground = true
	elif a == "--junctions":
		_junctions = true
	elif a.begins_with("--junctionshots="):
		_junctions = true
		_junction_shots = a.substr(16)
	elif a.begins_with("--rampshots="):
		_ramp_ground = true
		_ramp_shots = a.substr(12)
	elif a == "--spanbodies":
		_span_bodies = true
	else:
		return false
	return true


#region --groundprobe
## How far the drawn ground -- terrain chunks and road ribbons -- stands above
## the ground a man actually stands on, around where he is. --preset=cqb:f16 --groundprobe
var _ground_probe := false

func tick_ground_probe() -> void:
	if _ground_probe and is_instance_valid(world.walker):
		_ground_probe = false
		_run_ground_probe()

## The highest drawn triangle over (x, z) among `meshes`, or -INF.
func _drawn_top(meshes: Array, x: float, z: float) -> float:
	var best := -INF
	for mi in meshes:
		var m := mi as MeshInstance3D
		var ab: AABB = m.global_transform * m.get_aabb()
		if x < ab.position.x or x > ab.end.x or z < ab.position.z or z > ab.end.z:
			continue
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n: int = idx.size() if not idx.is_empty() else v.size()
			var xf: Transform3D = m.global_transform
			for t in range(0, n - 2, 3):
				var a: Vector3 = xf * v[idx[t] if not idx.is_empty() else t]
				var b: Vector3 = xf * v[idx[t + 1] if not idx.is_empty() else t + 1]
				var c: Vector3 = xf * v[idx[t + 2] if not idx.is_empty() else t + 2]
				var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
				if absf(d) < 1e-6:
					continue
				var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
				var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
				var l3 := 1.0 - l1 - l2
				if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
					continue
				best = maxf(best, a.y * l1 + b.y * l2 + c.y * l3)
	return best

func _run_ground_probe() -> void:
	for i in 240:
		await world.get_tree().physics_frame
	var w: Walker = world.walker
	var c: Vector3 = w.global_position
	var terr: Array = []
	var roads: Array = []
	for n in world.get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var nm := String(mi.name)
		if nm.begins_with("Roads") or nm.begins_with("Kerbs"):
			roads.append(mi)
		elif nm.begins_with("C") and mi.get_parent() is Terrain:
			terr.append(mi)
	print("[ground] %d terrain chunks, %d road meshes in the scene; man at %s, standing %.2f over height_at" % [
		terr.size(), roads.size(), str(c.round()), c.y - Sim.height_at(c.x, c.z)])
	var worst_t := -INF
	var worst_r := -INF
	var sum_t := 0.0
	var cnt := 0
	var over_t := 0
	var over_r := 0
	var on_road := 0
	for gx in range(-30, 31, 3):
		for gz in range(-30, 31, 3):
			var x: float = c.x + gx
			var z: float = c.z + gz
			var h: float = Sim.height_at(x, z)
			var ht: float = _drawn_top(terr, x, z)
			var hr: float = _drawn_top(roads, x, z)
			if ht > -INF:
				worst_t = maxf(worst_t, ht - h)
				sum_t += ht - h
				cnt += 1
				if ht - h > 0.15:
					over_t += 1
			if hr > -INF:
				on_road += 1
				worst_r = maxf(worst_r, hr - h)
				if hr - h > 0.15:
					over_r += 1
	print("[ground] terrain drawn over the ground: worst %+.2f m, mean %+.2f m, %d of %d points more than 15 cm up" % [
		worst_t, sum_t / maxf(cnt, 1), over_t, cnt])
	print("[ground] road drawn over the ground: worst %+.2f m, %d of %d road points more than 15 cm up" % [
		worst_r, over_r, on_road])
	# and every town's streets, not just this one
	var streets: Array = world.scenery.get("_streets") if is_instance_valid(world.scenery) else []
	var rw := -INF
	var rn := 0
	var rover := 0
	var tw := -INF
	var tover := 0
	for k in mini(streets.size(), 1500):
		var st: Array = streets[(k * 7919) % streets.size()]
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var q: Vector2 = a.lerp(b, randf())
		var h2: float = Sim.height_at(q.x, q.y)
		var hr2: float = _drawn_top(roads, q.x, q.y)
		if hr2 > -INF:
			rn += 1
			rw = maxf(rw, hr2 - h2)
			if hr2 - h2 > 0.15:
				rover += 1
		var ht2: float = _drawn_top(terr, q.x, q.y)
		if ht2 > -INF:
			tw = maxf(tw, ht2 - h2)
			if ht2 - h2 > 0.15:
				tover += 1
	print("[ground] across %d street points in every town: road worst %+.2f m (%d over 15 cm); terrain worst %+.2f m (%d over 15 cm)" % [
		rn, rw, rover, tw, tover])
	world.get_tree().quit()
#endregion


#region --bridgeprobe
## The ground at every bridge end, walked out along the road: how steep, how
## rough and how far below the deck. --preset=free:f16 --bridgeprobe
var _bridge_probe := false

func tick_bridge_probe() -> void:
	if _bridge_probe and world.running:
		_bridge_probe = false
		_run_bridge_probe()

func _run_bridge_probe() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var ends: Array = []
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2:
			continue
		for e in 2:
			var a: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var inner: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			var ya: float = ys[0] if e == 0 else ys[ys.size() - 1]
			var out: Vector2 = (a - inner).normalized()
			var side := Vector2(-out.y, out.x)
			var hs: Array = []
			var worst_g := 0.0
			var worst_x := 0.0
			var rough := 0.0
			# along the road itself, not a straight line off the end of the deck:
			# the surveyed line through this end, walked away from the span
			var path := PackedVector2Array()
			var lines: Array = Sim.roads.road_lines()
			for ln in lines:
				var pl: PackedVector2Array = ln
				for si in pl.size():
					if pl[si].distance_to(a) < 0.5:
						var stepdir: int = -1 if (si + 1 < pl.size() and pl[si + 1].distance_to(inner) < 0.5) else 1
						var at_i: int = si
						path.append(pl[si])
						while path.size() < 40 and at_i + stepdir >= 0 and at_i + stepdir < pl.size():
							at_i += stepdir
							path.append(pl[at_i])
						break
				if path.size() > 0:
					break
			var walk: Array = []
			if path.size() >= 2:
				for pi2 in path.size() - 1:
					var p0: Vector2 = path[pi2]
					var p1: Vector2 = path[pi2 + 1]
					var seg: float = p0.distance_to(p1)
					var d2 := 0.0
					while d2 < seg and walk.size() < 151:
						walk.append([p0.lerp(p1, d2 / maxf(seg, 0.001)), (p1 - p0).normalized()])
						d2 += 2.0
			else:
				for k in 151:
					walk.append([a + out * float(k) * 2.0, out])
			for k in walk.size():
				var q: Vector2 = walk[k][0]
				side = Vector2(-(walk[k][1] as Vector2).y, (walk[k][1] as Vector2).x)
				hs.append(Sim.height_at(q.x, q.y))
				var l: Vector2 = q + side * 5.0
				var r: Vector2 = q - side * 5.0
				worst_x = maxf(worst_x, absf(Sim.height_at(l.x, l.y) - Sim.height_at(r.x, r.y)) / 10.0)
			for k in range(5, hs.size()):
				worst_g = maxf(worst_g, absf(float(hs[k]) - float(hs[k - 5])) / 10.0)
			for k in range(1, hs.size() - 1):
				rough = maxf(rough, absf(float(hs[k + 1]) - 2.0 * float(hs[k]) + float(hs[k - 1])))
			var town: float = sqrt(Sim.pad_weight(a.x, a.y))
			# the bank's sides: off the road either way, a little way out
			var side_worst := 0.0
			for along in [10.0, 40.0, 80.0]:
				var c0: Vector2 = a + out * along
				for sgn in [-1.0, 1.0]:
					var prev: float = Sim.height_at(c0.x, c0.y)
					for st in range(2, 46):
						var q1: Vector2 = c0 + side * sgn * float(st) * 2.0
						var hq: float = Sim.height_at(q1.x, q1.y)
						if st >= 5:
							side_worst = maxf(side_worst, absf(hq - prev) / 2.0)
						prev = hq
			ends.append({"at": a, "step": ya - float(hs[0]) - Sim.planet_drop(a.x, a.y), "grade": worst_g,
				"cross": worst_x, "rough": rough, "town": town, "side": side_worst})
	ends.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["grade"]) > float(y["grade"]))
	var steep := 0
	for e2 in ends:
		if float(e2["grade"]) > 0.15:
			steep += 1
	var walls := 0
	var wall_tris := 0
	if is_instance_valid(world.scenery):
		for n in world.scenery.get_children():
			if String(n.name).begins_with("Walls") and n is MeshInstance3D:
				walls += 1
				wall_tris += int(((n as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	print("[bridge] %d retaining wall meshes, %d triangles" % [walls, wall_tris])
	print("[bridge] %d bridge ends; %d with ground steeper than 15%% within 300 m" % [ends.size(), steep])
	for i in mini(ends.size(), 10):
		var e3: Dictionary = ends[i]
		print("[bridge]   at %s: deck %+.1f m over the ground at the abutment, grade %.0f%%, cross fall %.0f%%, bank sides up to %.0f%%, roughness %.2f m, town weight %.2f" % [
			str((e3["at"] as Vector2).round()), float(e3["step"]), float(e3["grade"]) * 100.0,
			float(e3["cross"]) * 100.0, float(e3["side"]) * 100.0, float(e3["rough"]), float(e3["town"])])
	world.get_tree().quit()
#endregion


#region --rampground
## Round every bridge end in a town: is the ground a man stands on the ground
## that is drawn, is the road on it, and does the drawn ramp reach the deck --
## across the deck's width, where its end panel laps over the ramp? Drawn at
## the finest cell, too: nothing coarser can hold the seat under the deck.
## --preset=free:f16 --rampground
var _ramp_ground := false
## With --rampshots=DIR, a picture of each end from up the road and one from
## beside the deck end, low: not headless.
var _ramp_shots := ""

func tick_ramp_ground() -> void:
	if _ramp_ground and world.running:
		_ramp_ground = false
		_run_ramp_ground()

## The height of whatever triangle of `tris` lies over (x, z), or NAN.
static func _tri_y(tris: PackedVector3Array, x: float, z: float) -> float:
	var best := NAN
	for t in range(0, tris.size() - 2, 3):
		var a: Vector3 = tris[t]
		var b: Vector3 = tris[t + 1]
		var c: Vector3 = tris[t + 2]
		var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-6:
			continue
		var l1: float = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var l2: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		var l3: float = 1.0 - l1 - l2
		if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
			continue
		var y: float = a.y * l1 + b.y * l2 + c.y * l3
		if is_nan(best) or y > best:
			best = y
	return best

## The meshes under `root` named with `prefix` whose box comes within `r` of
## `at`, each as [its box, its triangles in world space, its depth if a terrain
## chunk].
static func _tris_near(root: Node, prefix: String, at: Vector2, r: float) -> Array:
	var out: Array = []
	for n in root.get_children():
		if not (n is MeshInstance3D):
			continue
		# a retired terrain chunk stays drawn until its replacement stands
		if not String(n.name).begins_with(prefix) and not (prefix == "C" and String(n.name).begins_with("X")):
			continue
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if at.x < ab.position.x - r or at.x > ab.end.x + r \
				or at.y < ab.position.z - r or at.y > ab.end.z + r:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var xf: Transform3D = mi.global_transform
		var tris := PackedVector3Array()
		if idx.is_empty():
			for q in v:
				tris.append(xf * q)
		else:
			for i in idx:
				tris.append(xf * v[i])
		var depth := -1
		if prefix == "C":
			depth = int(round(log(Terrain.ROOT_SPAN / maxf(ab.size.x, 1.0)) / log(2.0)))
		out.append([ab, tris, depth])
	return out

## The highest surface of `meshes` over (x, z); for terrain chunks only the
## finest one there, which is the one drawn.
static func _meshes_y(meshes: Array, x: float, z: float) -> float:
	var best := NAN
	var best_depth := -2
	for m in meshes:
		var ab: AABB = m[0]
		if x < ab.position.x or x > ab.end.x or z < ab.position.z or z > ab.end.z:
			continue
		var d: int = m[2]
		if d < best_depth:
			continue
		var y: float = _tri_y(m[1], x, z)
		if is_nan(y):
			continue
		if d > best_depth or is_nan(best) or y > best:
			best = y if d > best_depth else maxf(best, y)
			best_depth = d
	return best

## Two pictures of one bridge end, for --rampshots.
func _ramp_photos(a: Vector2, out: Vector2, side: Vector2, n: int) -> void:
	var top: float = Sim.roads.bridge_floor(a.x, a.y, 1e6)
	if top < -1e8:
		top = Sim.height_at(a.x, a.y)
	var at := Vector3(a.x, top, a.y)
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	if is_instance_valid(world.hud):
		world.hud.visible = false
	# `out` points from the deck down the ramp
	var views := [
		["road", out * 50.0 + side * 14.0, 6.0],
		["side", out * 12.0 + side * 60.0, 4.0],
	]
	for v in views:
		# a stray Escape pauses the match, and the picture is of the menu
		if world.get_tree().paused:
			world.controls.resume()
		var off: Vector2 = v[1]
		cam.global_position = at + Vector3(off.x, float(v[2]), off.y)
		cam.look_at(at + Vector3(0.0, -1.0, 0.0), Vector3.UP)
		cam.current = true
		world.terrain.paint_roads_now(cam.global_position)
		for i in 45:
			await world.get_tree().process_frame
		world.terrain.flush_pending()
		for i in 15:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := world.get_viewport().get_texture().get_image()
		var path := "%s/end%02d_%s.png" % [_ramp_shots, n, v[0]]
		img.save_png(path)
		print("[rampground]   picture: ", path)
	cam.queue_free()

func _run_ramp_ground() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var worst_sink := 0.0
	var worst_meet := 0.0
	var coarse := 0
	var ends := 0
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		for e in 2:
			var a: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var inner: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			if Sim.pad_weight(a.x, a.y) < 0.3:
				continue
			ends += 1
			var out: Vector2 = (a - inner).normalized()
			var side := Vector2(-out.y, out.x)
			var eye := Vector3(a.x, Sim.height_at(a.x, a.y) + 1.7, a.y)
			# Until the chunks the tree wants here are the ones drawn: the old
			# coarse ones stay up until their replacements are in, and measured
			# in the meantime they read as metres of gap that is not there. The
			# eye is put back every time -- the world points the tree at its
			# camera each frame, which is somewhere else.
			var want_depth: int = world.terrain.depth_at(a.x, a.y, eye)
			var ground: Array = []
			for tries in 12:
				world.terrain.recentre(eye, true)
				world.terrain.flush_pending()
				await world.get_tree().process_frame
				ground = _tris_near(world.terrain, "C", a, 80.0)
				var have := -1
				for m0 in ground:
					var ab0: AABB = m0[0]
					if a.x >= ab0.position.x and a.x <= ab0.end.x and a.y >= ab0.position.z and a.y <= ab0.end.z:
						have = maxi(have, int(m0[2]))
				if have >= want_depth:
					break
			var sink := 0.0
			var sink_at := Vector2.ZERO
			var bad_pts := 0
			for along in range(-30, 61, 3):
				for across in range(-40, 41, 3):
					var q: Vector2 = a + out * float(along) + side * float(across)
					var drawn: float = _meshes_y(ground, q.x, q.y)
					if is_nan(drawn):
						continue
					# the chunks are drawn flat and bent by their shader
					if not Sim.globe:
						drawn -= Sim.planet_drop(q.x, q.y)
					var stood: float = Terrain.drawn_ground(q.x, q.y, eye)
					# a man stands on the deck where there is one over him
					var deck: float = Sim.roads.bridge_floor(q.x, q.y, drawn + 1.0)
					var foot: float = maxf(stood, deck)
					if drawn - foot > sink:
						sink = drawn - foot
						sink_at = Vector2(along, across)
					if drawn - foot > 0.3:
						bad_pts += 1
			var drawn_depth := -1
			for m in ground:
				var ab3: AABB = m[0]
				if a.x >= ab3.position.x and a.x <= ab3.end.x and a.y >= ab3.position.z and a.y <= ab3.end.z:
					drawn_depth = maxi(drawn_depth, int(m[2]))
			# is this end one the corridor knows as an abutment -- what the
			# terrain tree is told to draw at the finest cell round?
			var flagged := 0
			for leg in Sim.roads.corr:
				var fl: int = int(leg[6]) if leg.size() > 6 else 0
				if (fl & 1 and (leg[0] as Vector2).distance_to(a) < 3.0) \
						or (fl & 2 and (leg[1] as Vector2).distance_to(a) < 3.0):
					flagged += 1
			print("[rampground] end %s: globe %s, drawn at depth %d, the quadtree wants %d; %d corridor legs flag it an abutment" % [
				str(a.round()), str(Sim.globe), drawn_depth, world.terrain.depth_at(a.x, a.y, eye), flagged])
			if is_nan(_meshes_y(ground, a.x, a.y)):
				var names: Array = []
				for n in world.terrain.get_children():
					if n is MeshInstance3D:
						var ab2: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
						if a.x >= ab2.position.x and a.x <= ab2.end.x and a.y >= ab2.position.z and a.y <= ab2.end.z:
							names.append("%s vis=%s" % [n.name, str((n as MeshInstance3D).visible)])
				print("[rampground] end %s: no terrain chunk drawn there; over it: %s; %d meshes near" % [str(a.round()), str(names), ground.size()])
			print("[rampground] end %s: drawn ground over where he stands by up to %.2f m (at %s along/across, %d points > 0.3 m)" % [
				str(a.round()), sink, str(sink_at), bad_pts])
			# Where the deck's end panel meets the road it laps onto, across the
			# width of the deck: what a man stands on there (the panel falls to
			# the road, see `Scenery._deck_lap`) against the ground drawn under
			# it. Above it, the panel stands proud of the road; below, the road
			# comes up through it.
			var meet := 0.0
			var meet_at := Vector2.ZERO
			# (out along `out`, which points from the deck onto the ramp: the
			# panel laps over the ramp, not back over the deck)
			for along2 in [2.4]:
				for across2 in range(-8, 9, 2):
					var q2: Vector2 = a + out * float(along2) + side * float(across2)
					var dk: float = Sim.roads.bridge_floor(q2.x, q2.y, 1e6)
					var dg: float = _meshes_y(ground, q2.x, q2.y)
					if dk < -1e8 or is_nan(dg):
						continue
					if not Sim.globe:
						dg -= Sim.planet_drop(q2.x, q2.y)
					if absf(dk - dg) > absf(meet):
						meet = dk - dg
						meet_at = Vector2(along2, across2)
			print("[rampground]   the deck's end panel %.2f m off the road where it meets it (at %s)" % [
				meet, str(meet_at)])
			# and the road it meets, painted: asphalt out along the approach,
			# and how many of the drawn network's legs come to this end at all
			var patch: PackedByteArray = Sim.native.road_paint(256, 32.0, a, false)
			var legs_here := 0
			var lines_up: Array = []
			for li in range(0, Sim.roads.road_draw.size() - 7, 8):
				var la := Vector2(Sim.roads.road_draw[li], Sim.roads.road_draw[li + 1])
				var lb := Vector2(Sim.roads.road_draw[li + 2], Sim.roads.road_draw[li + 3])
				if la.distance_to(a) < 3.0 or lb.distance_to(a) < 3.0:
					legs_here += 1
					# which way it runs into the deck, against the deck's own
					var far2: Vector2 = lb if la.distance_to(a) < 3.0 else la
					lines_up.append("%.2f" % (a - far2).normalized().dot(-out))
			var ys2: PackedFloat32Array = br.get("ys", PackedFloat32Array())
			var own_deck: float = (ys2[0] if e == 0 else ys2[ys2.size() - 1]) - Sim.planet_drop(a.x, a.y)
			print("[rampground]   this deck %.2f, the highest deck read here %.2f; legs arriving line up with it %s" % [
				own_deck, Sim.roads.bridge_floor(a.x, a.y, 1e6), str(lines_up)])
			print("[rampground]   asphalt painted %.2f at 10 m out, %.2f at 30 m; %d drawn legs end here" % [
				_paint_at(patch, 256, 32.0, a, a + out * 10.0, 0),
				_paint_at(patch, 256, 32.0, a, a + out * 30.0, 0), legs_here])
			if drawn_depth < 13:
				coarse += 1
			if _ramp_shots != "" and ends <= 4:
				await _ramp_photos(a, out, side, ends)
			worst_meet = maxf(worst_meet, absf(meet))
			worst_sink = maxf(worst_sink, sink)
	print("[rampground] RESULT: %s — %d town bridge ends, %d drawn coarser than the finest cell; drawn ground over his feet by up to %.2f m, the deck's end panel off the road it meets by up to %.2f m" % [
		"ok" if worst_sink < 0.35 and worst_meet < 0.1 and coarse == 0 else "FAILED",
		ends, coarse, worst_sink, worst_meet])
	world.get_tree().quit()
#endregion


#region --junctions
## Where the town streets meet the roads of the network: does a street that
## climbs to meet a road climb on drawn ground with its road on it, is there a
## kerb laid across any junction, and does a street that stops at a bank stop
## at its foot? --preset=free:f16 --junctions [--junctionshots=DIR, windowed]
var _junctions := false
var _junction_shots := ""

func tick_junctions() -> void:
	if _junctions and world.running:
		_junctions = false
		_run_junctions()

## Is any drawn street piece (`Scenery.street_draw`) within a metre of `q`?
## A street cut back from a bank or a low deck is not drawn there by design.
static func _street_drawn(sc: Node, q: Vector2) -> bool:
	for sd in sc.street_draw:
		if Geometry2D.get_closest_point_to_segment(q, sd[0], sd[1]).distance_to(q) < 1.0:
			return true
	return false

## One channel of a painted patch at a point: 0 to 1, or -1 off the patch.
static func _paint_at(buf: PackedByteArray, n: int, half: float, c: Vector2,
		q: Vector2, ch: int) -> float:
	var i := int(floor((q.x - c.x + half) * n / (half * 2.0)))
	var j := int(floor((q.y - c.y + half) * n / (half * 2.0)))
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1.0
	return float(buf[(j * n + i) * 4 + ch]) / 255.0

func _run_junctions() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	# painted as the eye goes, without being asked?
	for i in 240:
		await world.get_tree().process_frame
	var cam3: Camera3D = world.get_viewport().get_camera_3d()
	var lvs: Array = []
	for lv in world.terrain._road_lv:
		lvs.append("%s at %s, task %d" % [lv["u"], str(lv["centre"]), int(lv["task"])])
	print("[junctions] following the eye at %s: painted %d times; %s" % [
		str(cam3.global_position.round()) if cam3 != null else "none",
		world.terrain.roads_painted, ", ".join(lvs)])
	var sc: Node = world.scenery
	var all: Array = sc.junctions
	var kinds := {"level": 0, "join": 0, "stop": 0}
	for j in all:
		kinds[j["kind"]] = int(kinds[j["kind"]]) + 1
	print("[junctions] %d places a street meets a road: %d level, %d climbing to it, %d stopping at its bank; %d road pieces painted" % [
		all.size(), kinds["level"], kinds["join"], kinds["stop"], int(sc._stats.get("road_pieces", 0))])
	# what a full near square costs to paint, somewhere busy
	if not all.is_empty():
		var t0 := Time.get_ticks_usec()
		Sim.native.road_paint(2048, 256.0, all[0]["p"], true)
		print("[junctions] a near square, 2048 texels a side: %.1f ms" % [
			(Time.get_ticks_usec() - t0) / 1000.0])
	const PN := 512
	const PH := 64.0
	var worst_grade := 0.0
	var bare := 0
	var probed := 0
	var kerbs_across := 0
	var gaps := 0
	var crossings := 0
	var worst_stop := 0.0
	var stops := 0
	var shots := 0
	for j in all:
		var p: Vector2 = j["p"]
		var dir: Vector2 = j["dir"]
		var side := Vector2(-dir.y, dir.x)
		var kind: String = j["kind"]
		var buf: PackedByteArray = Sim.native.road_paint(PN, PH, p, false)
		var street: Array = sc._streets[int(j["street"])]
		var t: float = j["t"]
		var run: float = (street[0] as Vector2).distance_to(street[1])
		# (under a deck too low to go under, the street is cut on purpose)
		var decked: bool = Sim.roads.bridge_headroom(p.x, p.y, 20.0, NAN, false) < sc.STREET_HEADROOM
		if kind != "stop" and not decked:
			crossings += 1
			# a kerb across the junction: on the street's line, inside the
			# road it meets and its kerbs, on whichever side the street goes
			var across := false
			var drawn_side := {-1: _street_drawn(sc, p - dir * 14.0), 1: _street_drawn(sc, p + dir * 14.0)}
			for s2 in range(-11, 12):
				var room2: float = t * run if s2 < 0 else (1.0 - t) * run
				if room2 < 12.0 or not drawn_side[-1 if s2 < 0 else 1]:
					continue
				for o in [-3.0, 0.0, 3.0]:
					if _paint_at(buf, PN, PH, p, p + dir * float(s2) + side * o, 1) > 0.5:
						across = true
			if across:
				kerbs_across += 1
				if kerbs_across <= 3:
					print("[junctions]   a kerb across the junction at %s (%s), fill %.2f" % [
						str(p.round()), kind, float(j["fill"])])
				if kerbs_across <= 1:
					# what is painted along the street's line, and what the
					# ground is doing there against the town's own level
					var town0: float = Sim.height_at(p.x + dir.x * 60.0, p.y + dir.y * 60.0)
					for s5 in range(-11, 12):
						for o5 in [-3.0, 0.0, 3.0]:
							var q5: Vector2 = p + dir * float(s5) + side * o5
							if _paint_at(buf, PN, PH, p, q5, 1) <= 0.5:
								continue
							print("[junctions]     s=%+d o=%+.0f asphalt %.2f kerb %.2f; trunk %.1f m off; ground %+.2f on the town" % [
								s5, o5, _paint_at(buf, PN, PH, p, q5, 0), _paint_at(buf, PN, PH, p, q5, 1),
								Sim.native.trunk_distance(q5.x, q5.y), Sim.height_at(q5.x, q5.y) - town0])
			# and the asphalt unbroken from the road out along the street, on
			# whichever side it goes -- where it meets the road at all: one that
			# runs into it at a shallow angle merges along it, and has no mouth
			var shallow: bool = absf(dir.cross(j.get("along", side) as Vector2)) < 0.5
			for sgn in ([] if shallow else [-1.0, 1.0]):
				var room: float = t * run if sgn < 0.0 else (1.0 - t) * run
				if room < 25.0 or decked or not _street_drawn(sc, p + dir * sgn * 14.0):
					continue
				var broke := false
				for s3 in range(0, 24):
					if _paint_at(buf, PN, PH, p, p + dir * sgn * float(s3), 0) < 0.5:
						broke = true
				if broke:
					gaps += 1
					if gaps <= 3:
						print("[junctions]   the asphalt breaks between the road and the street at %s (%s), street %d at t %.3f of %.0f m" % [
							str(p.round()), kind, int(j["street"]), t, run])
						var row := ""
						for s6 in range(0, 24, 2):
							var q6: Vector2 = p + dir * sgn * float(s6)
							row += " %d:%.1f/%.0f/%s" % [s6, _paint_at(buf, PN, PH, p, q6, 0),
								Sim.native.trunk_distance(q6.x, q6.y), "d" if _street_drawn(sc, q6) else "-"]
						print("[junctions]     along it, asphalt / road distance / drawn:%s" % row)
		if kind == "join":
			var sides_drawn := 0
			for sgn2 in [-1.0, 1.0]:
				if _street_drawn(sc, p + dir * sgn2 * 20.0):
					sides_drawn += 1
			print("[junctions]   climb at %s: fill %.2f, crossing at %.0f deg, street drawn on %d sides" % [
				str(p.round()), float(j["fill"]), rad_to_deg(absf(asin(clampf(dir.cross(
					Vector2(cos(0.0), 0.0)), -1.0, 1.0)))), sides_drawn])
			for sgn in [-1.0, 1.0]:
				if not _street_drawn(sc, p + dir * sgn * 20.0):
					continue
				var prev := NAN
				for s3 in range(12, 50):
					var q: Vector2 = p + dir * sgn * float(s3)
					var g: float = Sim.native.surfaces_at(PackedVector2Array([q]), Terrain.BASE_CELL)[0]
					if not is_nan(prev):
						worst_grade = maxf(worst_grade, absf(g - prev))
					prev = g
					var a: float = _paint_at(buf, PN, PH, p, q, 0)
					if a < 0.0:
						continue
					probed += 1
					if a < 0.5:
						bare += 1
		elif kind == "stop":
			var town_y: float = Sim.height_at(p.x + dir.x * 80.0, p.y + dir.y * 80.0)
			for sgn in [-1.0, 1.0]:
				var toe := -1.0
				var end := -1.0
				for s4 in range(0, 64):
					var q: Vector2 = p + dir * sgn * float(s4)
					if toe < 0.0 and absf(Sim.height_at(q.x, q.y) - town_y) < 0.3:
						toe = float(s4)
					if end < 0.0 and Sim.native.trunk_distance(q.x, q.y) > 9.0 \
							and _paint_at(buf, PN, PH, p, q, 0) > 0.5:
						end = float(s4)
				if toe >= 0.0 and end >= 0.0:
					stops += 1
					worst_stop = maxf(worst_stop, absf(end - toe))
		if _junction_shots != "" and shots < 8 and (kind != "level" or shots < 4):
			shots += 1
			await _junction_photo(p, dir, shots, kind)
	print("[junctions] climbs: worst %.2f m a metre as drawn; %d of %d points along them without asphalt" % [
		worst_grade, bare, probed])
	print("[junctions] %d streets cut back to a junction from a bank or a low deck" % int(sc._stats.get("streets_cut", 0)))
	print("[junctions] %d of %d junctions with a kerb across them, %d sides where the asphalt breaks; streets stopping at a bank end within %.1f m of its foot (%d ends)" % [
		kerbs_across, crossings, gaps, worst_stop, stops])
	var ok: bool = kerbs_across == 0 and gaps == 0 and worst_grade < 0.2 \
		and (probed == 0 or bare * 10 < probed) and worst_stop <= 3.0
	print("[junctions] RESULT: %s" % ("ok" if ok else "FAILED"))
	world.get_tree().quit()

func _junction_photo(p: Vector2, dir: Vector2, n: int, kind: String) -> void:
	var side := Vector2(-dir.y, dir.x)
	var eye2: Vector2 = p + dir * 45.0 + side * 25.0
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	if is_instance_valid(world.hud):
		world.hud.visible = false
	cam.global_position = Vector3(eye2.x, Sim.height_at(eye2.x, eye2.y) + 14.0, eye2.y)
	cam.look_at(Vector3(p.x, Sim.height_at(p.x, p.y), p.y), Vector3.UP)
	cam.current = true
	world.terrain.paint_roads_now(cam.global_position)
	for i in 45:
		if world.get_tree().paused:
			world.controls.resume()
		await world.get_tree().process_frame
	world.terrain.flush_pending()
	for i in 15:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/junction%02d_%s.png" % [_junction_shots, n, kind]
	world.get_viewport().get_texture().get_image().save_png(path)
	print("[junctions]   picture: ", path)
	cam.queue_free()
#endregion


#region --spanbodies
## The bridge decks' physics bodies, which only the spans near the viewer get:
## over every bridge in turn, does a ray dropped on the deck land on its top,
## and far from all of them are there none? --preset=free:f16 --spanbodies
var _span_bodies := false

func tick_span_bodies() -> void:
	if _span_bodies and world.running:
		_span_bodies = false
		_run_span_bodies()

func _run_span_bodies() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var obs: Obstacles = world.obstacles
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var tried := 0
	var landed := 0
	var worst := 0.0
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 3:
			continue
		# the middle of a middle span, where the deck is over nothing
		var k: int = int(pts.size() / 2.0) - 1
		var q: Vector2 = (pts[k] + pts[k + 1]) * 0.5
		var deck: float = (ys[k] + ys[k + 1]) * 0.5 - Sim.planet_drop(q.x, q.y)
		obs.pin(Vector3(q.x, deck + 2.0, q.y))
		await world.get_tree().physics_frame
		await world.get_tree().physics_frame
		var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, deck + 10.0, q.y),
			Vector3(q.x, deck - 10.0, q.y), 4)
		var hit: Dictionary = space.intersect_ray(rq)
		tried += 1
		if hit.is_empty():
			print("[spanbodies] deck at %s: nothing under the ray (%d spans live)" % [
				str(q.round()), obs.live_spans()])
			continue
		var off: float = absf((hit["position"] as Vector3).y - deck)
		worst = maxf(worst, off)
		if off < 0.25:
			landed += 1
		else:
			print("[spanbodies] deck at %s: hit %.2f m off the deck top" % [str(q.round()), off])
		if tried >= 20:
			break
	# and somewhere no bridge is near
	obs.pin(Vector3(1e6, 0.0, 1e6))
	await world.get_tree().physics_frame
	var far: int = obs.live_spans()
	obs.unpin()
	print("[spanbodies] RESULT: %s — %d of %d decks caught the ray, worst %.2f m off the top; %d span bodies live far from any bridge" % [
		"ok" if tried > 0 and landed == tried and far == 0 else "FAILED", landed, tried, worst, far])
	world.get_tree().quit()
#endregion


#region --bridgedrive
## An AI tank sent across every road bridge: does it ride the deck or fall
## through it? --preset=free:f16 --bridgedrive
var _bridge_drive := false

func tick_bridge_drive() -> void:
	if _bridge_drive and world.running:
		_bridge_drive = false
		_run_bridge_drive()

func _run_bridge_drive() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var ok := 0
	var tried := 0
	for br in Sim.roads.road_bridges:
		var pts: PackedVector2Array = br["pts"]
		var ys: PackedFloat32Array = br["ys"]
		if pts.size() < 2:
			continue
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[pts.size() - 1]
		var out_a: Vector2 = (a - pts[1]).normalized()
		var out_b: Vector2 = (b - pts[pts.size() - 2]).normalized()
		var start2: Vector2 = a + out_a * 45.0
		var goal2: Vector2 = b + out_b * 300.0
		var start := Vector3(start2.x, Sim.height_at(start2.x, start2.y), start2.y)
		var head: float = atan2(out_a.x, out_a.y)          # facing back along -out
		var t := world._spawn_tank(start, head, 0, "humvee")
		t.ai = true
		t.ai_goal = Vector3(goal2.x, Sim.height_at(goal2.x, goal2.y), goal2.y)
		tried += 1
		var mid: Vector2 = pts[int(pts.size() / 2.0)]
		var mid_deck: float = ys[int(ys.size() / 2.0)] - Sim.planet_drop(mid.x, mid.y)
		var crossed := false
		var fell := false
		var worst := 0.0
		for f in 60 * 90:
			await world.get_tree().physics_frame
			if not is_instance_valid(t):
				break
			var p: Vector3 = t.global_position
			if f % 300 == 0:
				print("[bridgedrive]   t=%ds at %s, %.0f m to go; speed %.1f throttle %.2f steer %+.2f brake %s; building %d; floor %.1f deck %.1f" % [
					int(f / 60.0), str(p.round()), Vector2(p.x, p.z).distance_to(goal2),
					t.speed, t.in_throttle, t.in_steer, str(t.in_brake),
					Obstacles.hit(p, t.hull_radius()), Sim.height_at(p.x, p.z),
					Sim.roads.bridge_floor(p.x, p.z, p.y)])
			var deck: float = Sim.roads.bridge_floor(p.x, p.z, p.y)
			var on_span: bool = Sim.height_at(p.x, p.z) < mid_deck - 4.0 \
				and Vector2(p.x, p.z).distance_to(mid) < a.distance_to(b) * 0.5
			if on_span:
				if deck < -1e8 or p.y < deck - 1.5:
					fell = true
					break
				worst = maxf(worst, absf(p.y - deck - t.rest_height()))
			# across: at the far abutment, still up at the deck's level
			if Vector2(p.x, p.z).distance_to(b) < 25.0:
				crossed = true
				break
		print("[bridgedrive] bridge %s -> %s (%.0f m, ground under the middle %.0f m below the deck): %s, rode the deck within %.2f m" % [
			str(a.round()), str(b.round()), a.distance_to(b),
			mid_deck - Sim.height_at(mid.x, mid.y),
			"FELL THROUGH" if fell else ("crossed" if crossed else "did not get across"), worst])
		if crossed and not fell:
			ok += 1
		if is_instance_valid(t):
			t.queue_free()
	print("[bridgedrive] RESULT: %s — %d of %d crossed" % ["ok" if ok == tried else "FAILED", ok, tried])
	world.get_tree().quit()
#endregion
