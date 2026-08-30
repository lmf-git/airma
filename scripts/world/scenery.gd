class_name Scenery
extends Node3D
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
func _ready() -> void:
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
		Sim.load_road_state(cached_roads)
	else:
		var t_s := Time.get_ticks_msec()
		_site_towns()
		if Sim.debug_roads:
			print("[plan] siting towns and dispatching routes: %d ms"
				% (Time.get_ticks_msec() - t_s))

## Is the network still being searched? The caller keeps drawing while it is.
func plan_busy() -> bool:
	return not _plan_cached and not Sim.roads_routed()

## Everything that has to wait for the routes: the streets hang off the trunk
## network, so they cannot be laid until it exists.
func plan_finish() -> void:
	var t0 := Time.get_ticks_msec()
	if not _plan_cached:
		Sim.finish_roads()
	var t1 := Time.get_ticks_msec()
	for t in sites:
		_plan_town_streets(t["c"], t["r"])
	var t2 := Time.get_ticks_msec()
	_streets.append([Vector2(-1500, -6600), Vector2(-2300, -5200)])
	var t3 := t2
	var t4 := t2
	var t5 := t2
	if not _plan_cached:
		Sim.register_segments(_streets)
		t3 = Time.get_ticks_msec()
		WorldBake.put("town_sites", sites)
		t4 = Time.get_ticks_msec()
		var st := Sim.road_state()
		t5 = Time.get_ticks_msec()
		WorldBake.put("roads", st)
	if Sim.debug_roads:
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
			var h := Sim.height_at(q.x, q.y)
			if h > Sim.WATER_LEVEL + 30.0 and h < 1500.0:
				dry += 1.0
	return dry / maxf(float(n), 1.0)

## Which regions each run of independent towns joins, and the sites in it:
## [region a, region b, [site index, ...]]. Region ids here are hub numbers --
## 0 is home, and hub k is region k.
var _free_chains: Array = []

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
				var sc := _land_score(c, 13000.0)
				if sc > 0.82:
					cand.append([sc - Sim.site_roughness(c, 9000.0) * 2.0, c])
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
		if found.size() >= REGIONS:
			break
	return found

func _site_towns() -> void:
	sites.clear()
	var pads: Array = []
	for t in TOWNS:
		var want := Vector2(float(t[0].x), float(t[0].z))
		var r: float = float(t[1])
		var best := want
		var best_rough: float = Sim.site_roughness(want, r)
		# Every *candidate* was tested for dry land, but the position the town
		# was asked for never was -- so a settlement wanted somewhere that
		# turned out to be under water stayed there unless something else beat
		# it on roughness, and open sea is very smooth.
		if Sim.height_at(want.x, want.y) < Sim.WATER_LEVEL + 25.0 \
				or not Sim.clear_of_airfield(want.x, want.y):
			best_rough = 1e9
		var step: float = r * 0.45
		for i in range(-3, 4):
			for j in range(-3, 4):
				if i == 0 and j == 0:
					continue
				var q := want + Vector2(float(i), float(j)) * step
				# still near the airfield's valley, still on dry land
				if Sim.height_at(q.x, q.y) < Sim.WATER_LEVEL + 25.0:
					continue
				if not Sim.clear_of_airfield(q.x, q.y):
					continue
				var rough := Sim.site_roughness(q, r)
				if rough < best_rough:
					best_rough = rough
					best = q
		sites.append({"c": best, "r": r, "density": float(t[2]),
			"tallest": float(t[3]), "name": String(t[4]), "region": 0,
			"was": want, "rough": best_rough})
		pads.append({"c": best, "r": r})
	# and the clusters elsewhere on the map, each with its own towns
	var t_fr := Time.get_ticks_msec()
	var regions := find_regions()
	if Sim.debug_roads:
		print("[plan]   find_regions: %d ms" % (Time.get_ticks_msec() - t_fr))
	for ri in regions.size():
		var rc: Vector2 = regions[ri]
		for ti in REGION_TOWNS:
			var ang: float = TAU * (float(ti) + 0.35) / float(REGION_TOWNS)
			var want2: Vector2 = rc + Vector2(cos(ang), sin(ang)) * 7200.0
			var rad: float = [1100.0, 720.0, 560.0, 480.0][ti % 4]
			var best2 := want2
			var rough2: float = 1e9
			for i2 in range(-3, 4):
				for j2 in range(-3, 4):
					var q2: Vector2 = want2 + Vector2(float(i2), float(j2)) * (rad * 0.7)
					if Sim.height_at(q2.x, q2.y) < Sim.WATER_LEVEL + 30.0:
						continue
					var rg: float = Sim.site_roughness(q2, rad)
					if rg < rough2:
						rough2 = rg
						best2 = q2
			if rough2 > 1e8:
				continue                      # nowhere dry enough here
			sites.append({"c": best2, "r": rad,
				"density": [0.66, 0.58, 0.54, 0.50][ti % 4],
				"tallest": [46.0, 24.0, 17.0, 13.0][ti % 4],
				"name": String(REGION_NAMES[ri % REGION_NAMES.size()][ti % 4]),
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
					if Sim.height_at(q3.x, q3.y) < Sim.WATER_LEVEL + 30.0:
						continue
					var rg3: float = Sim.site_roughness(q3, rad3)
					if rg3 < rough3:
						rough3 = rg3
						best3 = q3
			if rough3 > 1e8:
				continue                      # open water the whole way across
			sites.append({"c": best3, "r": rad3, "density": 0.52,
				"tallest": 21.0,
				"name": String(FREE_NAMES[named % FREE_NAMES.size()]),
				"region": -1, "faction": "free", "was": want3, "rough": rough3})
			pads.append({"c": best3, "r": rad3})
			chain.append(sites.size() - 1)
			named += 1
		if not chain.is_empty():
			_free_chains.append([ba, hb, chain])
	var t_rp := Time.get_ticks_msec()
	Sim.register_town_pads(pads)
	if Sim.debug_roads:
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
	for t in sites:
		nodes.append(t["c"] as Vector2)
	nodes.append(Vector2(-1500.0, -6600.0))       # the depot
	nodes.append(Vector2(4200.0, 11000.0))        # and two legs out of the valley
	nodes.append(Vector2(-5200.0, -13000.0))
	var first_town := 2
	var n_towns: int = sites.size()
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
	Sim.begin_roads(nodes, _valid_links(links, nodes.size()))

## The town of a given region nearest a point, as a node index. Region 0 is the
## home cluster, which is also where the airfield gates are.
func _closest_in_region(nodes: Array, first_town: int, n_towns: int,
		region: int, near: Vector2) -> int:
	var best := -1
	var bd := 1e18
	for i in n_towns:
		if int((sites[i] as Dictionary).get("region", 0)) != region:
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
		var rg: int = int((sites[i] as Dictionary).get("region", 0))
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


func _plan_town_streets(centre: Vector2, radius: float) -> void:
	var block := 128.0
	var lines := int(radius / block)
	for i in range(-lines, lines + 1):
		var off := float(i) * block
		var half := sqrt(maxf(radius * radius - off * off, 0.0))
		if half < 40.0:
			continue
		_streets.append([Vector2(centre.x + off, centre.y - half),
			Vector2(centre.x + off, centre.y + half)])
		_streets.append([Vector2(centre.x - half, centre.y + off),
			Vector2(centre.x + half, centre.y + off)])
	_streets.append([centre, _nearest_trunk(centre)])

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
		var biome: String = Sim.biome_kind(c.x, c.y, ground,
			Sim.normal_at(c.x, c.y).y)
		var lamp: Array = []
		var seat: Array = []
		var kiosk: Array = []
		var planter: Array = []
		for seg in _streets:
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
			for i in range(1, n):
				var along: float = float(i) * step
				for sx in [-1.0, 1.0]:
					var q: Vector2 = a + dir * along + side * (sx * 9.5)
					var gy: float = Terrain.surface_height(q.x, q.y)
					if gy < Sim.WATER_LEVEL + 1.0:
						continue
					var xf := Transform3D(Basis(Vector3.UP,
						atan2(dir.x, -dir.y)), Vector3(q.x, gy, q.y))
					if i % 2 == 0:
						lamp.append(xf)
					elif i % 5 == 1:
						seat.append(xf)
					elif i % 7 == 3:
						planter.append(xf)
					elif i % 11 == 5:
						kiosk.append(xf)
		var tone: Color = Sim.faction_colour(faction)
		made += _detail_batch(_lamp_mesh(tone), lamp, "Lamps_%s" % String(t["name"]))
		made += _detail_batch(_seat_mesh(tone, biome), seat, "Seats_%s" % String(t["name"]))
		made += _detail_batch(_kiosk_mesh(tone, faction), kiosk,
			"Kiosks_%s" % String(t["name"]))
		made += _detail_batch(_planter_mesh(tone, biome), planter,
			"Planters_%s" % String(t["name"]))
		_stats["town_faction_" + faction] = int(_stats.get("town_faction_" + faction, 0)) + 1
	_stats["street_props"] = made

func _detail_batch(mesh: Mesh, xforms: Array, nm: String) -> int:
	if xforms.is_empty() or mesh == null:
		return 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the LOD itself: nothing at all beyond half a kilometre
	mmi.visibility_range_end = PROP_FADE
	mmi.visibility_range_end_margin = 90.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	return xforms.size()

func _lamp_mesh(tone: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.cone(st, 0.09, 0.06, 0.0, 5.4, Vector3.ZERO, 6, true)
	MeshKit.box(st, Vector3(0.14, 0.10, 1.1), Vector3(0, 5.4, -0.45))
	MeshKit.box(st, Vector3(0.34, 0.16, 0.62), Vector3(0, 5.28, -0.95))
	return MeshKit.finish(st, MeshKit.mat(tone.darkened(0.45), 0.6, 0.35))

func _seat_mesh(tone: Color, biome: String) -> ArrayMesh:
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

func _kiosk_mesh(tone: Color, faction: String) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(2.2, 2.6, 1.9), Vector3(0, 1.3, 0))
	match faction:
		"russia", "china":
			# a flat canopy on posts, which is what a street kiosk looks like there
			MeshKit.box(st, Vector3(3.0, 0.14, 2.6), Vector3(0, 2.72, 0))
		"uk", "usa":
			# a pitched roof and a hanging sign
			MeshKit.cone(st, 1.7, 0.1, 2.6, 3.5, Vector3.ZERO, 4, true)
			MeshKit.box(st, Vector3(1.3, 0.5, 0.08), Vector3(0, 2.1, -1.0))
		_:
			# an awning, angled out over the front
			MeshKit.box(st, Vector3(2.6, 0.10, 1.5), Vector3(0, 2.5, -1.2))
	return MeshKit.finish(st, MeshKit.mat(tone.lightened(0.12), 0.7, 0.05))

func _planter_mesh(tone: Color, biome: String) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.cone(st, 0.75, 0.62, 0.0, 0.75, Vector3.ZERO, 8, true)
	match biome:
		"desert":
			# a palm: a bare stem and a crown
			MeshKit.cone(st, 0.13, 0.09, 0.75, 4.4, Vector3.ZERO, 6, true)
			for k in 6:
				var a := TAU * float(k) / 6.0
				MeshKit.box(st, Vector3(2.0, 0.07, 0.34),
					Vector3(cos(a) * 0.9, 4.3, sin(a) * 0.9))
		"snow", "rock":
			MeshKit.cone(st, 0.9, 0.05, 0.75, 3.8, Vector3.ZERO, 7, true)
		_:
			MeshKit.cone(st, 0.16, 0.11, 0.75, 2.6, Vector3.ZERO, 6, true)
			MeshKit.cone(st, 1.25, 0.2, 2.4, 4.6, Vector3.ZERO, 8, true)
	return MeshKit.finish(st, MeshKit.mat(tone.lerp(Color(0.22, 0.36, 0.18), 0.6),
		0.85, 0.0))

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
		if g < Sim.WATER_LEVEL + 6.0:
			var found := false
			for ring in range(1, 60):
				var step: float = float(ring) * 2500.0
				for k in 12:
					var a := TAU * float(k) / 12.0
					var q := at + Vector2(cos(a), sin(a)) * step
					if absf(q.x) > Sim.WORLD_HALF or absf(q.y) > Sim.WORLD_HALF:
						continue
					var gg: float = Terrain.surface_height(q.x, q.y)
					if gg >= Sim.WATER_LEVEL + 6.0:
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
		var node := _landmark_mesh(String(lm["id"]), float(lm["h"]),
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

## Each one is a handful of primitives, not a model: enough silhouette that you
## know what you are looking at from a mile up, which is the only range anybody
## will see them from.
func _landmark_mesh(id: String, h: float, tone: Color) -> Node3D:
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
	# and into the obstacle field, so it is something you can fly into rather
	# than something you fly through
	Obstacles.add_batch(mesh, xforms)
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
	# A building you can no longer see is a building you can no longer hit.
	Obstacles.kill_near(pos, radius)
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
		_block_mesh(1.0, 1.0, 1.0, Color(0.26, 0.25, 0.23), Color(0.70, 0.67, 0.61)),
		_block_mesh(1.0, 1.0, 1.0, Color(0.22, 0.23, 0.25), Color(0.58, 0.59, 0.60)),
		_block_mesh(1.0, 1.0, 1.0, Color(0.29, 0.24, 0.21), Color(0.64, 0.58, 0.51)),
	]
	for i in 3:
		var lot: Array = buckets[i]
		_scatter(kinds[i], lot, "Town%d" % i, true)
		town_xforms.append_array(lot)
		_stats["buildings"] = int(_stats.get("buildings", 0)) + lot.size()

## True when a point falls inside a town footprint, so nothing tall gets planted
## on top of the buildings.
func _inside_town(p: Vector2) -> bool:
	for t in sites:
		if p.distance_to(t["c"] as Vector2) < float(t["r"]) * 1.15:
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

const SCAT_TASKS := 24
## Per slice, so the total is a round 150,000 without an integer division that
## quietly loses the remainder.
const SCAT_PER_TASK := 6250

var _scat_out: Array = []

func _scatter_nature() -> void:
	var meshes := {"tree": _tree_mesh(), "pine": _pine_mesh(), "rock": _rock_mesh(),
		"bush": _bush_mesh()}
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
		_scat_h = Sim.native.grounds_at(_scat_pts, true)
		_scat_slope = Sim.native.slopes_at(_scat_pts)
		# and the surface as the mesh draws it, which is four more heights
		# apiece and was the last thing the workers were crossing the boundary
		# for
		_scat_surf = Sim.native.surfaces_at(_scat_pts, Terrain.BASE_CELL)
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
		if y < Sim.WATER_LEVEL + 2.0 or y > 2400.0:
			continue
		# On the surface as it is drawn, not as the field computes it. The two
		# part company by more than the height of a tree as soon as the cells
		# get coarse, and a tree standing on the analytic height then hangs in
		# the air above the triangles -- which is what you see looking up at the
		# underside of the ground.
		y = _scat_surf[base + i]
		if absf(x) < 6000.0 and Sim.road_distance(x, z) < 15.0:
			continue
		var slope: float = _scat_slope[base + i]
		if slope < 0.55:
			continue                                        # nothing clings to a cliff
		var biome := Sim.biome_kind(x, z, y, slope)
		if rng.randf() > float(SCAT_DENSITY.get(biome, 0.3)):
			continue
		var options: Array = SCAT_SPECIES.get(biome, ["bush"])
		var kind: String = options[rng.randi() % options.size()]
		var sc := rng.randf_range(0.7, 1.7)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(sc, sc * rng.randf_range(0.8, 1.35), sc)), Vector3(x, y - 0.4, z))
		out.append(["%s_%d_%d" % [kind, int(floor(x / SCAT_CELL)),
			int(floor(z / SCAT_CELL))], xf])
	_scat_out[t] = out

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
## Carriageways and kerbs for every road and street on the map.
##
## Four height samples every eleven metres of every leg, and with sixteen towns
## on the map that is over three seconds. None of it touches the scene tree, so
## a leg at a time goes to the worker pool and only the two meshes are made
## here.
var _road_jobs: Array = []
var _road_out: Array = []

func _build_roads() -> void:
	_road_jobs = []
	for r in Sim.ROADS:
		_road_jobs.append([r[0], r[1], 7.5])
	for r in _streets:
		_road_jobs.append([r[0], r[1], 5.0])
	_road_out = []
	_road_out.resize(_road_jobs.size())
	var gid := WorkerThreadPool.add_group_task(_ribbon_job, _road_jobs.size(), -1,
		true, "road surfaces")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	# Sized once. Appending 450 arrays onto a growing PackedVector3Array
	# reallocates and copies the whole thing over and over.
	var ns := 0
	var nk := 0
	for o0 in _road_out:
		ns += ((o0 as Array)[0] as PackedVector3Array).size()
		nk += ((o0 as Array)[1] as PackedVector3Array).size()
	var surf := PackedVector3Array()
	var kerb := PackedVector3Array()
	surf.resize(ns)
	kerb.resize(nk)
	var ws := 0
	var wk := 0
	for o in _road_out:
		var a0: PackedVector3Array = (o as Array)[0]
		for v in a0:
			surf[ws] = v
			ws += 1
		var b0: PackedVector3Array = (o as Array)[1]
		for v2 in b0:
			kerb[wk] = v2
			wk += 1
	_road_jobs = []
	_road_out = []
	add_child(MeshKit.mi(_flat_mesh(kerb,
		MeshKit.mat(Color(0.34, 0.32, 0.28), 0.98, 0.0)), "Kerbs"))
	add_child(MeshKit.mi(_flat_mesh(surf,
		MeshKit.mat(Color(0.105, 0.105, 0.115), 0.94, 0.0)), "Roads"))

## Viaducts and tunnel portals.
##
## The alignment crosses low ground on a deck and high ground in a bore, and
## neither is laid on the terrain -- which is the point, it is what stops the
## road gouging a trench or climbing a mountain. But with nothing drawn for
## them, a road simply stopped at one side of a valley and started again at the
## other, and disappeared into a hillside with no way in.
const PIER_STEP := 90.0
const DECK_HALF := 8.5

func _build_structures() -> void:
	var st := MeshKit.begin()
	var dark := MeshKit.begin()
	var decks := 0
	var piers := 0
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2:
			continue
		decks += 1
		var since := 0.0
		for i in range(pts.size() - 1):
			var a2: Vector2 = pts[i]
			var b2: Vector2 = pts[i + 1]
			var run := a2.distance_to(b2)
			if run < 0.5:
				continue
			var dir := (b2 - a2) / run
			var nrm := Vector2(-dir.y, dir.x)
			var ya: float = ys[i]
			var yb: float = ys[i + 1]
			# the running surface
			var p0 := Vector3(a2.x + nrm.x * DECK_HALF, ya, a2.y + nrm.y * DECK_HALF)
			var p1 := Vector3(a2.x - nrm.x * DECK_HALF, ya, a2.y - nrm.y * DECK_HALF)
			var p2 := Vector3(b2.x - nrm.x * DECK_HALF, yb, b2.y - nrm.y * DECK_HALF)
			var p3 := Vector3(b2.x + nrm.x * DECK_HALF, yb, b2.y + nrm.y * DECK_HALF)
			MeshKit.quad_n(st, p0, p1, p2, p3, Vector3.UP)
			# the box girder under it, so the deck has a thickness
			var u0 := p0 - Vector3(0, 1.9, 0)
			var u1 := p1 - Vector3(0, 1.9, 0)
			var u2 := p2 - Vector3(0, 1.9, 0)
			var u3 := p3 - Vector3(0, 1.9, 0)
			MeshKit.quad_n(st, u1, u0, u3, u2, Vector3.DOWN)
			MeshKit.quad_n(st, p0, p3, u3, u0, Vector3(nrm.x, 0, nrm.y))
			MeshKit.quad_n(st, p2, p1, u1, u2, Vector3(-nrm.x, 0, -nrm.y))
			# parapets
			for sx in [1.0, -1.0]:
				var e0 := Vector3(a2.x + nrm.x * DECK_HALF * sx, ya + 0.55,
					a2.y + nrm.y * DECK_HALF * sx)
				var e1 := Vector3(b2.x + nrm.x * DECK_HALF * sx, yb + 0.55,
					b2.y + nrm.y * DECK_HALF * sx)
				var i0 := e0 - Vector3(nrm.x * 0.4 * sx, 0, nrm.y * 0.4 * sx)
				var i1 := e1 - Vector3(nrm.x * 0.4 * sx, 0, nrm.y * 0.4 * sx)
				MeshKit.quad_n(st, e0, e1, i1, i0, Vector3.UP)
			# and a pier every so often, down to whatever is underneath
			since += run
			if since >= PIER_STEP:
				since = 0.0
				var g: float = Sim.height_at(b2.x, b2.y)
				var clear: float = yb - 1.9 - g
				if clear > 5.0:
					piers += 1
					MeshKit.box(st, Vector3(4.4, clear, 4.4),
						Vector3(b2.x, g + clear * 0.5, b2.y))
	var portals := 0
	for tn in Sim.road_tunnels:
		var tp: PackedVector2Array = tn.get("pts", PackedVector2Array())
		var ty: PackedFloat32Array = tn.get("ys", PackedFloat32Array())
		if tp.size() < 2:
			continue
		for endi in [0, tp.size() - 1]:
			portals += 1
			var at: Vector2 = tp[endi]
			var toward: Vector2 = tp[1] if endi == 0 else tp[tp.size() - 2]
			var d2 := (at - toward).normalized()
			var y2: float = ty[endi]
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
	add_child(MeshKit.mi(MeshKit.finish(dark,
		MeshKit.mat(Color(0.04, 0.04, 0.05), 0.98, 0.0)), "TunnelMouths"))
	_stats["viaducts"] = decks
	_stats["piers"] = piers
	_stats["portals"] = portals

func _ribbon_job(i: int) -> void:
	var j: Array = _road_jobs[i]
	_road_out[i] = _ribbon(j[0], j[1], float(j[2]))

## Ground-hugging triangles need no normal but up, so the mesh is a vertex list
## and nothing else.
func _flat_mesh(verts: PackedVector3Array, mat: Material) -> ArrayMesh:
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
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m

## Runs on a worker. Returns [carriageway, kerbs].
func _ribbon(a: Vector2, b: Vector2, half: float) -> Array:
	var surf := PackedVector3Array()
	var kerb := PackedVector3Array()
	var len2 := a.distance_to(b)
	if len2 < 1.0:
		return [surf, kerb]
	# One quad is enough for a leg shorter than a step. Routing chops the trunk
	# network into thousands of short segments, and a floor of two steps gave
	# every fifteen metre piece of road four rows of height samples and
	# thirty-six vertices it had no detail to put in them.
	var steps := maxi(int(round(len2 / (11.0 if half > 6.0 else 17.0))), 1)
	var dir := (b - a).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var prev: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var row: Array = []
		for k in [-1.55, -1.0, 1.0, 1.55]:
			var q: Vector2 = p + nrm * half * float(k)
			var y := Sim.height_at(q.x, q.y)
			if half > 6.0:
				# A trunk road on an embankment or a bridge rides on the design
				# surface, not on whatever is underneath it. Drawn on the ground
				# instead, a crossing was painted along the seabed and the road
				# ran through the water.
				var rs := Sim.road_surface(q.x, q.y)
				if rs.y > 0.35:
					y = maxf(y, rs.x)
			row.append(Vector3(q.x, y + 0.16, q.y))
		# lift the surface to the highest of the two kerbs so it never sinks in
		var top: float = maxf(row[1].y, row[2].y)
		row[1] = Vector3(row[1].x, top, row[1].z)
		row[2] = Vector3(row[2].x, top, row[2].z)
		row[0] = Vector3(row[0].x, minf(row[0].y, top) - 0.04, row[0].z)
		row[3] = Vector3(row[3].x, minf(row[3].y, top) - 0.04, row[3].z)
		if i > 0:
			_strip(surf, prev[1], prev[2], row[2], row[1])
			_strip(kerb, prev[0], prev[1], row[1], row[0])
			_strip(kerb, prev[2], prev[3], row[3], row[2])
		prev = row
	return [surf, kerb]

func _strip(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	out.append(a)
	out.append(b)
	out.append(c)
	out.append(a)
	out.append(c)
	out.append(d)

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
		if Sim.height_at(t.x, t.y) < Sim.WATER_LEVEL + 3.0:
			continue
		if not Sim.clear_of_airfield(t.x, t.y) or _inside_town(t):
			continue
		if Sim.clear_of_roads(t.x, t.y, 12.0):
			return t
	return Vector2.INF

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
				# A pylon has a base about eight metres across and stands
				# thirty-four metres up; putting one in the carriageway is worse
				# than putting a house there. Nudged aside rather than dropped,
				# so the line still gets there.
				if not Sim.clear_of_roads(q.x, q.y, 12.0):
					var moved := _off_the_road(q, a, b)
					if moved == Vector2.INF:
						continue
					q = moved
				pts.append(q)
		# The last pylon on a run goes through the same test as the rest of
		# them. Appended unconditionally it was the one that ended up in the
		# carriageway: 1 of 128.
		var last: Vector2 = route[route.size() - 1]
		if Sim.clear_of_roads(last.x, last.y, 12.0):
			pts.append(last)
		else:
			var shifted := _off_the_road(last, route[route.size() - 2], last)
			if shifted != Vector2.INF:
				pts.append(shifted)
		var prev := Vector3.INF
		for q in pts:
			var y: float = Sim.height_at(q.x, q.y)
			xf.append(Transform3D(Basis(Vector3.UP, 0.0), Vector3(q.x, y - 1.0, q.y)))
			pylon_spots.append(Vector3(q.x, y, q.y))
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
		if hub:
			hub.rotate_z(delta * 0.85)
