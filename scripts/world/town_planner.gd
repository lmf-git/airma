class_name TownPlanner
extends RefCounted
## Where the towns go, and the road network between them: regions of good land,
## towns sited in them, trunk roads joining them (and bridged across water
## where a region would otherwise be cut off), the junctions, and each town's
## street grid. Split out of `scenery.gd`; what it decides is kept on the
## `Scenery` it plans for (`sites`, `junctions`, the street lists).

var sc: Scenery

## Which regions each run of independent towns joins, and the sites in it:
## [region a, region b, [site index, ...]]. Region ids here are hub numbers --
## 0 is home, and hub k is region k.
var _free_chains: Array = []

func _init(scenery: Scenery) -> void:
	sc = scenery

## How much of a disc is dry, workable land, 0 to 1.
static func _land_score(c: Vector2, r: float) -> float:
	var dry := 0.0
	var n := 0
	for i in 7:
		for j in 7:
			var q := c + Vector2(float(i - 3), float(j - 3)) * (r / 3.0)
			if q.distance_to(c) > r:
				continue
			n += 1
			# How high the ground stands over its own sea, which is the same
			# number in either frame -- the drop cancels. A ceiling written as
			# a world y instead put the whole band 1300 m out of place at the
			# far corner of the map, and moved where towns can be sited.
			var h: float = Sim.height_at(q.x, q.y) - Sim.sea_at(q.x, q.y)
			if h > 30.0 and h < 1535.0:
				dry += 1.0
	return dry / maxf(float(n), 1.0)

static func find_regions() -> Array:
	var found: Array = []
	var cand: Array = []
	var reach := 380000.0
	var step := 26000.0
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var c := Vector2(x, z)
			# well clear of home, or it is not a different part of the world
			if c.length() > 110000.0:
				var score := _land_score(c, 13000.0)
				if score > 0.82:
					cand.append([score - Sim.roads.site_roughness(c, 9000.0) * 2.0, c])
			z += step
		x += step
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for e in cand:
		var c2: Vector2 = e[1]
		var ok := true
		for g in found:
			if c2.distance_to(g as Vector2) < 130000.0:
				ok = false
				break
		if ok:
			found.append(c2)
		if found.size() >= Scenery.REGIONS:
			break
	return found

## Can a town stand here: on dry land, clear of the aerodromes and the depot.
static func _town_ok(q: Vector2, r: float, sea_margin: float) -> bool:
	return Sim.height_at(q.x, q.y) >= Sim.sea_at(q.x, q.y) + sea_margin \
		and Sim.town_clear(q, r)

func site_towns() -> void:
	sc.sites.clear()
	Sim.keep_out = [[Vector2(-1500.0, -6600.0), 350.0]]     # the depot: see `_military`
	var _t_lm := Time.get_ticks_msec()
	# Which ground is reachable ground. A town across a strait is a town the
	# trunk network has to swim to.
	Sim.build_landmass()
	if Sim.roads.debug_roads:
		print("[plan]   build_landmass: %d ms" % (Time.get_ticks_msec() - _t_lm))
	var _t_named := Time.get_ticks_msec()
	var pads: Array = []
	for t in Scenery.TOWNS:
		var want := Vector2(float(t[0].x), float(t[0].z))
		var r: float = float(t[1])
		var best := want
		var best_rough: float = Sim.roads.site_roughness(want, r)
		# Every *candidate* was tested for dry land, but the position the town
		# was asked for never was -- so a settlement wanted somewhere that
		# turned out to be under water stayed there unless something else beat
		# it on roughness, and open sea is very smooth.
		if not _town_ok(want, r, 25.0) or not Sim.on_home_land(want.x, want.y):
			best_rough = 1e9
		var step: float = r * 0.45
		# The ring it was always looked for in, and further out only if
		# nothing in it is clear: a town is not put down on top of a runway
		# for want of somewhere better.
		for reach in [3, 6]:
			for i in range(-reach, reach + 1):
				for j in range(-reach, reach + 1):
					if (i == 0 and j == 0) or maxi(absi(i), absi(j)) <= reach - 3 and reach > 3:
						continue
					var q := want + Vector2(float(i), float(j)) * step
					# still near the airfield's valley, still on dry land, and
					# all of it clear of the aerodrome rather than its middle
					if not _town_ok(q, r, 25.0):
						continue
					# and on the same land as everything else, or the road to it
					# has to cross water
					if not Sim.on_home_land(q.x, q.y):
						continue
					var rough := Sim.roads.site_roughness(q, r)
					if rough < best_rough:
						best_rough = rough
						best = q
			if best_rough < 1e8:
				break
		if best_rough > 1e8:
			push_warning("no clear ground for %s: not built" % String(t[4]))
			continue
		sc.sites.append({"c": best, "r": r, "density": float(t[2]),
			"tallest": float(t[3]), "name": String(t[4]), "region": 0,
			"was": want, "rough": best_rough})
		pads.append({"c": best, "r": r})
	if Sim.roads.debug_roads:
		print("[plan]   the named towns: %d ms" % (Time.get_ticks_msec() - _t_named))
	# and the clusters elsewhere on the map, each with its own towns
	var t_fr := Time.get_ticks_msec()
	var regions := find_regions()
	if Sim.roads.debug_roads:
		print("[plan]   find_regions: %d ms" % (Time.get_ticks_msec() - t_fr))
	for ri in regions.size():
		var rc: Vector2 = regions[ri]
		for ti in Scenery.REGION_TOWNS:
			var ang: float = TAU * (float(ti) + 0.35) / float(Scenery.REGION_TOWNS)
			var want2: Vector2 = rc + Vector2(cos(ang), sin(ang)) * 7200.0
			var rad: float = [1100.0, 720.0, 560.0, 480.0][ti % 4]
			var best2 := want2
			var rough2: float = 1e9
			for i2 in range(-3, 4):
				for j2 in range(-3, 4):
					var q2: Vector2 = want2 + Vector2(float(i2), float(j2)) * (rad * 0.7)
					if not _town_ok(q2, rad, 30.0):
						continue
					var rg: float = Sim.roads.site_roughness(q2, rad)
					if rg < rough2:
						rough2 = rg
						best2 = q2
			if rough2 > 1e8:
				continue                      # nowhere dry enough here
			sc.sites.append({"c": best2, "r": rad,
				"density": [0.66, 0.58, 0.54, 0.50][ti % 4],
				"tallest": [46.0, 24.0, 17.0, 13.0][ti % 4],
				"name": String(Scenery.REGION_NAMES[ri % Scenery.REGION_NAMES.size()][ti % 4]),
				"region": ri + 1, "was": want2, "rough": rough2})
			pads.append({"c": best2, "r": rad})
	# Independent towns, in the country between the factions.
	#
	# Each sits on the line between two regional centres, so it is nobody's and
	# anyone moving between two factions comes through it. It also gives the
	# trunk network somewhere to stop: neighbouring regions are a hundred and
	# thirty kilometres apart by construction, and a single leg that long is
	# both a bad road and a search the router cannot finish.
	var hubs: Array = [Vector2.ZERO]
	for rc3 in regions:
		hubs.append(rc3 as Vector2)
	_free_chains = []
	var tied: Array = [0]
	var loose: Array = []
	for hi in range(1, hubs.size()):
		loose.append(hi)
	var named := 0
	while not loose.is_empty():
		var bd := 1e18
		var ba := 0
		var bo := 0
		for a2 in tied:
			for oi in loose.size():
				var d3: float = (hubs[int(a2)] as Vector2).distance_squared_to(
					hubs[int(loose[oi])] as Vector2)
				if d3 < bd:
					bd = d3
					ba = int(a2)
					bo = oi
		var hb: int = int(loose[bo])
		tied.append(hb)
		loose.remove_at(bo)
		var pa: Vector2 = hubs[ba]
		var pb: Vector2 = hubs[hb]
		var chain: Array = []
		for f in [0.34, 0.66]:
			var want3: Vector2 = pa.lerp(pb, float(f))
			var rad3 := 620.0
			var best3 := want3
			var rough3 := 1e9
			for i3 in range(-3, 4):
				for j3 in range(-3, 4):
					var q3: Vector2 = want3 + Vector2(float(i3), float(j3)) * 1100.0
					if not _town_ok(q3, rad3, 30.0):
						continue
					var rg3: float = Sim.roads.site_roughness(q3, rad3)
					if rg3 < rough3:
						rough3 = rg3
						best3 = q3
			if rough3 > 1e8:
				continue                      # open water the whole way across
			sc.sites.append({"c": best3, "r": rad3, "density": 0.52,
				"tallest": 21.0,
				"name": String(Scenery.FREE_NAMES[named % Scenery.FREE_NAMES.size()]),
				"region": -1, "faction": "free", "was": want3, "rough": rough3})
			pads.append({"c": best3, "r": rad3})
			chain.append(sc.sites.size() - 1)
			named += 1
		if not chain.is_empty():
			_free_chains.append([ba, hb, chain])
	var t_rp := Time.get_ticks_msec()
	# Sites whose ground is under water get no platform, so they get no town:
	# a settlement is not a reason to raise an island out of the sea. `sites`
	# and `pads` are built in step, so the survivors index the same way.
	var kept_pads: Array = Sim.roads.register_town_pads(pads)
	if kept_pads.size() < pads.size():
		var keep: Dictionary = {}
		for k in kept_pads:
			keep[(k as Dictionary)["c"]] = true
		var dry_sites: Array = []
		for si in sc.sites.size():
			var at_c: Variant = (sc.sites[si] as Dictionary).get("c")
			if keep.has(at_c):
				dry_sites.append(sc.sites[si])
		if Sim.roads.debug_roads:
			print("[plan]   %d of %d sites were under water and are not built" % [
				pads.size() - kept_pads.size(), pads.size()])
		sc.sites = dry_sites
	if Sim.roads.debug_roads:
		print("[plan]   register_town_pads (%d): %d ms" % [pads.size(),
			Time.get_ticks_msec() - t_rp])
	# The trunk network, laid to where the towns actually ended up.
	#
	# It hangs off a bypass running down the east side of the field rather than
	# off a single gate. A leg that starts beside an airfield and heads
	# south-west is inside the keep-out within a few hundred metres whatever the
	# router does about the middle of it, because the relaxation can only move
	# the waypoints, not the ends — measured, 362 of 4784 sample points inside
	# the keep-out and four of them on the runway itself. Starting from a road
	# that is already clear of the field removes the problem rather than
	# penalising it.
	var nodes: Array = [
		Vector2(980.0, 3100.0),        # 0: north gate
		Vector2(980.0, -3100.0),       # 1: south gate
	]
	var links: Array = [[0, 1]]        # the bypass itself
	for t in sc.sites:
		nodes.append(t["c"] as Vector2)
	nodes.append(Vector2(-1500.0, -6600.0))       # the depot
	nodes.append(Vector2(4200.0, 11000.0))        # and two legs out of the valley
	nodes.append(Vector2(-5200.0, -13000.0))
	var first_town := 2
	var n_towns: int = sc.sites.size()
	links.append_array(_plan_network(nodes, first_town, n_towns))
	# Thread the independents in: the nearest town of one region, along the
	# chain, and into the nearest town of the other. This is the road between
	# two factions, and it is built in forty kilometre legs the router can
	# actually survey rather than one long jump.
	for ch in _free_chains:
		var ra: int = int(ch[0])
		var rb: int = int(ch[1])
		var run: Array = ch[2]
		if run.is_empty():
			continue
		var head: int = first_town + int(run[0])
		var tail: int = first_town + int(run[run.size() - 1])
		var ta: int = _closest_in_region(nodes, first_town, n_towns, ra,
			nodes[head] as Vector2)
		var tb: int = _closest_in_region(nodes, first_town, n_towns, rb,
			nodes[tail] as Vector2)
		if ta >= 0:
			links.append([ta, head])
		if tb >= 0:
			links.append([tb, tail])
		for k in range(run.size() - 1):
			links.append([first_town + int(run[k]), first_town + int(run[k + 1])])
	Sim.roads.begin_roads(nodes, _valid_links(links, nodes.size()))

## The town of a given region nearest a point, as a node index. Region 0 is the
## home cluster, which is also where the airfield gates are.
func _closest_in_region(nodes: Array, first_town: int, n_towns: int,
		region: int, near: Vector2) -> int:
	var best := -1
	var bd := 1e18
	for i in n_towns:
		if int((sc.sites[i] as Dictionary).get("region", 0)) != region:
			continue
		var d: float = (nodes[first_town + i] as Vector2).distance_squared_to(near)
		if d < bd:
			bd = d
			best = first_town + i
	# the home cluster hangs off the bypass if it has no town of its own
	if best < 0 and region == 0:
		return 0
	return best

## Only the links that name two different places that exist.
func _valid_links(links: Array, n: int) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for pair in links:
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		if a >= n or b >= n or a == b:
			continue
		var key: int = mini(a, b) * 100000 + maxi(a, b)
		if seen.has(key):
			continue
		seen[key] = true
		out.append([a, b])
	return out

## The trunk network: the shortest set of links that joins every place to every
## other, plus a couple of extra hops so it reads as a network and not a tree.
##
## This was a full ring round the towns *and* a spoke from each of them to the
## bypass, plus depot legs -- thirty-six routes for sixteen towns, most of them
## running parallel to another one a kilometre away. Every one of those is
## routed, surveyed, cut into the ground and drawn, so the redundancy cost real
## time and real triangles as well as looking like a mess.
func _plan_network(nodes: Array, first_town: int, n_towns: int) -> Array:
	var out: Array = []
	var by_region: Dictionary = {}
	for i in n_towns:
		var rg: int = int((sc.sites[i] as Dictionary).get("region", 0))
		if rg < 0:
			continue                      # independents are chained separately
		if not by_region.has(rg):
			by_region[rg] = []
		(by_region[rg] as Array).append(first_town + i)
	for rg2 in by_region:
		var group: Array = (by_region[rg2] as Array).duplicate()
		if int(rg2) == 0:
			# the home cluster hangs off the airfield bypass and its depot
			group.append(0)
			group.append(1)
			for extra_node in range(first_town + n_towns, nodes.size()):
				group.append(extra_node)
			out.append([0, 1])
		out.append_array(_spanning(nodes, group, 2 if group.size() > 5 else 1))
	# Join the regions to one another. Each got a spanning tree of its own and
	# nothing more: only region zero was ever tied to the airfield bypass and
	# the depot, so every other region was an island -- its towns joined to each
	# other, no road out of it, and its trunk legs simply stopping in open
	# country. Linked here on the shortest hop between any two places in them,
	# which is where a road between two regions would actually be built.
	var regions: Array = by_region.keys()
	if regions.size() > 1:
		var joined: Array = [regions[0]]
		var left: Array = regions.slice(1)
		while not left.is_empty():
			var best := 1e18
			var best_from: Variant = null
			var best_at := 0
			for ra in joined:
				for li in left.size():
					for na in (by_region[ra] as Array):
						for nb in (by_region[left[li]] as Array):
							var d: float = (nodes[int(na)] as Vector2) \
								.distance_squared_to(nodes[int(nb)] as Vector2)
							if d < best:
								best = d
								best_from = ra
								best_at = li
			if best_from == null:
				break
			# Unless the independent towns between them already make the road.
			# They are sited on the line between the two regions, so the
			# direct link ran down the same corridor a couple of kilometres off
			# the chain for a hundred kilometres: two roads between every pair
			# of regions, side by side, all the way.
			if _chained(int(best_from), int(left[best_at])):
				joined.append(left[best_at])
				left.remove_at(best_at)
				continue
			# Two roads between them, not one. A single link makes the whole of
			# one faction's country hang off one bridge: cut it and half the map
			# is unreachable, and it reads as a chain of places rather than as
			# two road systems that meet.
			# One direct link. The independent towns between the two already
			# carry a road of their own, so this is the second way round
			# rather than the only one -- and a second hundred-and-thirty
			# kilometre leg costs as much to survey as the first.
			out.append_array(_bridge_regions(nodes, by_region[best_from] as Array,
				by_region[left[best_at]] as Array, 1))
			joined.append(left[best_at])
			left.remove_at(best_at)
	return out

## Whether a chain of independent towns, with at least one town in it, runs
## between two regions. Hub indices and region numbers are the same thing: hub
## zero is home, which is region zero.
func _chained(ra: int, rb: int) -> bool:
	for ch in _free_chains:
		var a: int = int(ch[0])
		var b: int = int(ch[1])
		if ((a == ra and b == rb) or (a == rb and b == ra)) and not (ch[2] as Array).is_empty():
			return true
	return false

## The `k` shortest hops between two groups of places, each using a different
## town at either end -- so the second road is a separate route through
## different country, not a twin running alongside the first.
func _bridge_regions(nodes: Array, ga: Array, gb: Array, k: int) -> Array:
	var pairs: Array = []
	for na in ga:
		for nb in gb:
			pairs.append([(nodes[int(na)] as Vector2).distance_squared_to(
				nodes[int(nb)] as Vector2), int(na), int(nb)])
	pairs.sort_custom(func(x: Array, y: Array) -> bool:
		return float(x[0]) < float(y[0]))
	var out: Array = []
	var used_a: Dictionary = {}
	var used_b: Dictionary = {}
	for pr in pairs:
		if out.size() >= k:
			break
		if used_a.has(pr[1]) or used_b.has(pr[2]):
			continue
		used_a[pr[1]] = true
		used_b[pr[2]] = true
		out.append([int(pr[1]), int(pr[2])])
	return out

## Prim's algorithm over the given places, then the shortest few links that were
## not needed to join them up, so there is more than one way round.
func _spanning(nodes: Array, group: Array, loops: int) -> Array:
	var out: Array = []
	if group.size() < 2:
		return out
	var inside: Array = [group[0]]
	var outside: Array = group.slice(1)
	while not outside.is_empty():
		var best_d := 1e18
		var best_i := 0
		var best_o := 0
		for a in inside:
			for oi in outside.size():
				var d: float = (nodes[a] as Vector2).distance_squared_to(
					nodes[outside[oi]] as Vector2)
				if d < best_d:
					best_d = d
					best_i = a
					best_o = oi
		out.append([best_i, outside[best_o]])
		inside.append(outside[best_o])
		outside.remove_at(best_o)
	# and a few short links that close a loop
	var spare: Array = []
	for i in group.size():
		for j in range(i + 1, group.size()):
			var pair := [group[i], group[j]]
			var already := false
			for e in out:
				if (e[0] == pair[0] and e[1] == pair[1]) \
						or (e[0] == pair[1] and e[1] == pair[0]):
					already = true
					break
			if not already:
				spare.append([(nodes[pair[0]] as Vector2).distance_squared_to(
					nodes[pair[1]] as Vector2), pair])
	spare.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in mini(loops, spare.size()):
		out.append(spare[k][1])
	return out

func plan_junctions() -> void:
	sc._approach_spans = {}
	sc.junctions = []
	var flat := PackedFloat32Array()
	for seg in sc._streets:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		flat.append_array(PackedFloat32Array([a.x, a.y, b.x, b.y]))
	var got: PackedFloat32Array = Sim.native.street_crossings(flat)
	var legs: Array = []
	var joins := 0
	var stops := 0
	for i in range(0, got.size() - 7, 8):
		var si: int = int(got[i])
		var t: float = got[i + 1]
		var p := Vector2(got[i + 2], got[i + 3])
		var road_y: float = got[i + 4]
		var town_y: float = got[i + 5]
		var along := Vector2(got[i + 6], got[i + 7])
		var fill: float = road_y - town_y
		var a2: Vector2 = sc._streets[si][0]
		var b2: Vector2 = sc._streets[si][1]
		var run: float = a2.distance_to(b2)
		if run < 1.0:
			continue
		var dir: Vector2 = (b2 - a2) / run
		var kind := "level" if absf(fill) < Scenery.JOIN_MIN else ("stop" if absf(fill) > Scenery.JOIN_FILL else "join")
		sc.junctions.append({"p": p, "dir": dir, "along": along, "fill": fill, "kind": kind,
			"t": t, "street": si})
		if kind == "level":
			continue
		if kind == "stop":
			stops += 1
			continue
		# out of the road's carriageway and kerbs, measured along the street,
		# which may cross it at an angle
		var start: float = Sim.roads.ROAD_HALF * 1.55 / maxf(absf(dir.cross(along)), 0.4)
		var reach: float = clampf(absf(fill) / Scenery.STREET_GRADE, 8.0, 50.0)
		for side in [-1.0, 1.0]:
			# only on the side of the road the street goes on to
			var room: float = t * run if side < 0.0 else (1.0 - t) * run
			if room < start + 2.0:
				continue
			var l: float = minf(reach, room - start)
			var q0: Vector2 = p + dir * side * start
			var q1: Vector2 = p + dir * side * (start + l)
			legs.append([q0, q1, road_y, town_y, town_y, town_y,
				Sim.roads.LEG_APPROACH, Scenery.STREET_HALF])
			# out past the end of the climb by as far as its bank rounds off,
			# so the street's own approach is never taken for a bank it has to
			# keep clear of (`_streets_clear_of_bridges`)
			var t1: float = clampf(t + side * (start + l + Scenery.APPROACH_TAIL) / run, 0.0, 1.0)
			if not sc._approach_spans.has(si):
				sc._approach_spans[si] = []
			(sc._approach_spans[si] as Array).append([minf(t, t1), maxf(t, t1)])
			joins += 1
	Sim.roads.set_street_approaches(legs)
	sc._stats["street_joins"] = joins
	sc._stats["street_stops"] = stops

func plan_town_streets(centre: Vector2, radius: float, trunk: Vector2) -> void:
	var block := 128.0
	var lines := int(radius / block)
	for i in range(-lines, lines + 1):
		var off := float(i) * block
		var half := sqrt(maxf(radius * radius - off * off, 0.0))
		if half < 40.0:
			continue
		sc._streets.append([Vector2(centre.x + off, centre.y - half),
			Vector2(centre.x + off, centre.y + half)])
		sc._streets.append([Vector2(centre.x - half, centre.y + off),
			Vector2(centre.x + half, centre.y + off)])
	sc._streets.append([centre, trunk])
