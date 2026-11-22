class_name RoadNet
extends RefCounted
## The trunk road network: routing each leg between the towns and the
## airfields, surveying it onto the land, merging and tidying the result, the
## bridges and tunnels it needs, the corridor index the ground and the drawing
## read, the streets' approaches, the town platforms it joins, and every road and
## street segment for distance queries. All of it is baked to disk with the world
## (`road_state`).
##
## Split out of `sim.gd`; reached as `Sim.roads`.


## Road network, shared by the terrain painter and the placement rules. It is
## rebuilt once the towns have been sited, because the towns move: a trunk road
## drawn to where a town was originally wanted ends somewhere in a field.
var ROADS: Array = [
	[Vector2(0, 1700), Vector2(-2300, -5200)],
	[Vector2(0, -1700), Vector2(2600, 4200)],
	[Vector2(-2300, -5200), Vector2(2100, -9200)],
	[Vector2(-1900, 3100), Vector2(2600, 4200)],
	[Vector2(-1500, -6600), Vector2(-2300, -5200)],
	[Vector2(2600, 4200), Vector2(4200, 11000)],
	[Vector2(-2300, -5200), Vector2(-5200, -13000)],
]

# -------------------------------------------------------------- road corridor
const ROAD_HALF := 7.5           # carriageway half width
const ROAD_SHOULDER := 24.0      # graded shoulder either side of it
const ROAD_GRADE := 0.062        # steepest gradient a trunk road is built to
const SURVEY_STEP := 45.0        # spacing of the profile's stations

## How many weld-and-tie rounds the relaxation runs. Roads that meet have to
## agree about the height, and one pass moves a station by a few metres against
## a thirty-four metre reach.
const SURVEY_PASSES := 24

## What the survey actually builds to, read from the extension rather than
## written down again here: the ruling gradient, what it may be pushed to, the
## hairpin nothing may exceed, and the deepest cutting and tallest embankment
## a run that wanted a structure and did not earn one is allowed. Anything
## measuring the road has to measure it against the numbers it was built to.
var road_grade_max := 0.10
var road_grade_hairpin := 0.15
var road_cut_hard := 45.0
var road_fill_hard := 32.0

## Tallest embankment before it becomes a bridge.
##
## This was 14, and the span rule below only builds a bridge once the ground
## falls 24 -- so no embankment could ever reach the height that would hand the
## job over. Between the two the road simply gave up and lay on the ground at
## whatever gradient the ground had. The two numbers have to meet: fill up to
## here, and a bridge from here on.
const ROAD_FILL_MAX := 22.0

## Deepest cutting, on the same reasoning against TUNNEL_DEEP: dig to here, and
## bore from here on. Over a 31.5 m graded half-width, 34 m is about a one in
## one batter at the ends and shallower along the sides, which is a cutting
## through rock -- steep, but a real thing that gets built where the alternative
## is a road that cannot be driven.
const ROAD_CUT_MAX := 34.0

## The trunk network as polylines and the made height at each of their
## stations, in build order. Both come back from the extension's survey.
var trunk_lines: Array = []
var road_prof: Array = []

## The untouched ground under each station, so a cutting can be told from a
## road running along the floor of a valley.
var natural: Array = []
var road_bridges: Array = []     # spans carried on a deck: {a, b, ya, yb, pts, ys}

## The trunk network as it is drawn, leg by leg: ax, az, bx, bz, half width,
## design height at each end, and whether it is a structure approach. Not the
## same list as `ROADS`, which is what is painted into the ground -- the terrain
## under a bridge is untouched, but the road still has to reach the deck.
var road_draw := PackedFloat32Array()
var in_survey := false

## Two roads on one stretch are one road, and it is drawn once.
##
## Where the weld has pulled two routes onto the same line each of them still
## brought its own legs, so the carriageway was laid twice within a metre or two
## of itself and the two surfaces fought over every pixel -- a shimmer along
## every shared stretch, and over a viaduct a second deck's worth of road. A leg
## whose two ends and middle all lie on a road already drawn, at the same
## height, is dropped. Height matters: a road passing under another is not a
## duplicate of it.
const CARRIAGEWAY_NEAR := 3.5     # metres across, centreline to centreline
const CARRIAGEWAY_SAME := 2.5     # metres of height
const CARRIAGEWAY_CELL := 48.0

## Throw away any road that leads nowhere.
##
## A leg the router could not solve -- or refused to solve, because the only way
## across was a causeway over open sea -- leaves whatever was joined through it
## standing on its own. Some of that is rubbish: a single stretch of road
## between two points with no way in and no way out. Some of it is not: a
## cluster of towns three hundred kilometres away, joined to each other and cut
## off from home by an ocean, has exactly the road network it ought to have, and
## throwing it away left ten towns on the map with no road in them at all.
##
## So the test is whether a component is a network rather than whether it
## reaches the airfield. Endpoints are shared exactly between legs that meet, so
## joining them up is a matter of matching coordinates.
## Where two legs of the network run alongside one another, one road.
##
## Every leg is searched on its own, all of them at once, and none of them knows
## the others exist. Two legs into the same town from places in roughly the
## same direction both find the same cheap valley, and each builds its own road
## down it: a trunk road that splits in two a few kilometres out and enters the
## town twice, or a pair of carriageways a couple of hundred metres apart for
## twenty kilometres. That is what was reported -- a road forking off into two
## to head to the same city.
##
## So the legs are taken shortest first, and wherever a later one runs within
## `MERGE_NEAR` of a road already laid for longer than `MERGE_RUN`, that
## stretch is dropped: what is left of it joins the road it was shadowing, at a
## junction, and the road it joins is split there so the junction is an end of
## both -- which is what the survey welds and what the network is joined up by.
## Two roads meeting at an angle are close for only a few hundred metres and are
## left alone.
const MERGE_NEAR := 500.0
const MERGE_RUN := 1000.0
const MERGE_STEP := 100.0
const MERGE_CELL := 500.0

## Shorter than this, what is left of a leg is not worth a road of its own.
const MERGE_STUB := 250.0

## A junction this close to the end of the road it lands on is that end.
const MERGE_SNAP := 80.0
var debug_roads := false

## Where the made height stands too far above the land to be an embankment, the
## road is carried instead. Recorded as spans so the scenery can put a deck and
## piers under them.
## Where the alignment cannot simply be cut or filled into the country, the road
## needs a structure: a bridge over the low ground, a tunnel through the high.
##
## Without them a road has exactly two options, both wrong. Carve, and it leaves
## a slot through the hill with the carriageway at the bottom. Refuse to carve,
## and it climbs the hill instead, which is where the 22% gradients came from.
## A structure is the third answer: the alignment holds its grade and the ground
## is left completely alone underneath it.
##
## Which stations are inside one is decided by the survey, in `survey.rs`,
## because it is decided *with* the profile rather than after it: what has to be
## carried depends on where the alignment ended up, and where the alignment ends
## up depends on which stations are held to the ground. This side only groups
## the marked stations into the runs the scenery builds decks and portals over.
var road_tunnels: Array = []     # {a, b, ya, yb, pts, ys}

## Per surveyed station, whether the road is inside a structure there. The
## corridor leaves the ground alone across those, and the surface is drawn as a
## deck or not at all rather than painted on the hillside.
var _road_struct: Array = []
const F_BRIDGE := 1
const F_TUNNEL := 2

## How far out from a bridge's end its approach counts as part of it. While the
## road stands more than this over the ground it was built on, it is the ramp
## onto the deck -- a bank in the country, a walled ramp in a town -- and
## nothing else belongs on it or across it.
const RAMP_FILL := 1.0

## ...and never more stations of it than this.
const RAMP_STATIONS := 6

# ---------------------------------------------------------- bridge decks
## The road bridges as something to stand on. A deck was drawn and nothing
## more: a vehicle that climbed the approach bank reached the abutment and fell
## through the span to the valley floor. A deck is not part of the height field
## -- the ground under a bridge has to stay where it is, for whatever is down
## there -- so it is a floor for whatever arrives at its own level, which is
## the same rule a building's upper storey is.
const BRIDGE_HALF := 8.5            # matches `Scenery.DECK_HALF`
const BRIDGE_LAP := 2.5             # the end panels reach this far past the stations

## How far above something a deck can be and still be stepped onto: anything
## further below it is underneath the bridge, not on it.
const BRIDGE_STEP := 0.6

## Points across an end panel's outer edge: `Scenery.LAP_N`.
const LAP_N := 9

## How deep the deck is: the box girder under the running surface, which is
## what anything passing underneath has to clear.
const BRIDGE_GIRDER := 1.9          # matches the girder `Scenery` draws

## Half the width of a ramp onto a deck, out to the foot of its side slope:
## `RAMP_EDGE` in world.rs, which is where the made ground meets the town.
const RAMP_HALF := 20.0

## ...and round the end of one, where the bank's top widens under the deck end
## to a cell either side of it (`HEAD_REACH` in world.rs): the head's half
## width at its widest, 31 m, and its side slope.
const RAMP_HEAD := 40.0
var _deck_src: Array = []
var _deck_idx: Array = []           # {lo, hi, pts, ys, ramps}
const CORR_CELL := 64.0

## Every corridor leg, and which cells of a coarse grid each one touches.
## height_at asks for this on every call, and walking eight hundred legs to
## answer it cost more than the rest of the height field put together.
var corr: Array = []            # [a, b, ya, yb]

## Where a street climbs to meet a road a little up on its bank, the street's
## own approach, graded into the ground like the road's: each [a, b, made a,
## made b, ground a, ground b, LEG_APPROACH, half width]. Laid out by
## `Scenery.plan_finish` once the streets exist; not part of the bake, because
## the streets are not.
var _street_corr: Array = []
const LEG_APPROACH := 4

## Everything the approaches reach, so a question asked anywhere else -- a
## tree, a lamp post, most of the map -- is turned away at once.
var _approach_box := Rect2()

## A road between two places that goes round the hills instead of over them.
##
## This used to seed a straight line and slide each waypoint sideways along that
## line's normal, keeping whatever was cheapest. Greedy, local, one degree of
## freedom, and no way back: it could bow round a spur but it could not
## switchback, double back, or take a dogleg through a pass that lay behind it.
## Terrain it could not get round had to be solved with a tunnel instead, which
## is why a third of the network ended up bored through hills.
##
## This is a real search: A* over a coarse grid, with the edge cost being what a
## road actually costs -- length, climb, the square of the gradient, a heavy
## penalty past what a trunk road is built to, water, and the airfield keep-out.
## The result is then pulled straight, because a grid path arrives full of
## forty-five degree staircases that no surveyor would set out.
var _rt_jobs: Array = []
var _rt_out: Array = []
var _rt_gid := -1
var segments: Array = []          # every road and street, filled by Scenery

## Level ground for the settlements. Each pad is worked out from the land as it
## is before any of them exist, so the platform sits at the natural height of
## the site and the shoulders blend out over the last fifth of the radius.
var town_pads: Array = []

## How many road and street legs the distance index holds.
var segments_indexed := 0

## How far it is worth looking for a road before answering "nowhere near one".
## The ring search widens until it can prove nothing closer exists, so this only
## caps how much empty country it will sweep for a point in the middle of it.
const ROAD_REACH := 4000.0

## Lay the trunk network between the airfield and wherever the towns ended up,
## each leg routed round the worst of the ground rather than driven straight
## over it. `link` is a list of index pairs into `points`.
## The whole thing in one blocking go, for anything that is not the loading
## screen -- the harnesses, mostly.
func build_roads(points: Array, links: Array) -> void:
	# Collected apart and only published at the end: routing calls height_at,
	# and a half filled network is a road with no surveyed height to read.
	begin_roads(points, links)
	finish_roads()

## Send every link out to be searched. None of this touches the scene tree, so
## they all go at once -- and, more to the point, the caller can keep drawing
## while they run. Routing is the longest single thing in world generation, and
## doing it one leg at a time on the main thread is what made the window stop
## answering: the machine decides a program that has not drawn for a minute has
## hung, and offers to kill it.
func begin_roads(points: Array, links: Array) -> void:
	ROADS = []
	trunk_lines = []
	road_prof = []
	corr = []
	road_bridges = []
	_rt_jobs = []
	for pair in links:
		_rt_jobs.append([points[pair[0]], points[pair[1]]])
	_rt_out = []
	_rt_out.resize(_rt_jobs.size())
	_rt_gid = -1
	if _rt_jobs.is_empty():
		return
	# Every leg in one call, searched on every core inside the extension. It
	# goes out to a worker of its own so the loading screen keeps painting
	# while it runs.
	push_world()
	_rt_gid = WorkerThreadPool.add_group_task(_route_native, 1, -1, true,
		"road routing")

## What the router has to know about the world before it surveys anything: the
## platforms the towns have been levelled onto, and where the runways are.
func push_world() -> void:
	var pads := PackedFloat32Array()
	for pad in town_pads:
		var c: Vector2 = pad["c"]
		pads.append(c.x)
		pads.append(c.y)
		pads.append(float(pad["r"]))
		pads.append(float(pad["y"]))
	var fl := PackedFloat32Array()
	for fd in Sim.fields:
		var at: Vector2 = fd["at"]
		fl.append(at.x)
		fl.append(at.y)
		fl.append(float(fd["yaw"]))
		fl.append(float(fd["elev"]))
	Sim.native.set_world(pads, fl)

func _route_native(_i: int) -> void:
	var ends := PackedVector2Array()
	for j in _rt_jobs:
		ends.append(j[0] as Vector2)
		ends.append(j[1] as Vector2)
	var lines: Array = Sim.native.route_many(ends)
	for k in mini(lines.size(), _rt_out.size()):
		_rt_out[k] = lines[k]

## Are the searches done? Asked once a frame by the loading screen.
func roads_routed() -> bool:
	return _rt_gid == -1 or WorkerThreadPool.is_group_task_completed(_rt_gid)

func routes_left() -> int:
	return _rt_jobs.size()

## Collect the routes and survey them into a built network.
func finish_roads() -> void:
	var t_wait := Time.get_ticks_msec()
	if _rt_gid != -1:
		WorkerThreadPool.wait_for_group_task_completion(_rt_gid)
		_rt_gid = -1
	var _routed := Time.get_ticks_msec() - t_wait
	var lines: Array = []
	var failed := 0
	for ji in _rt_jobs.size():
		var line: Variant = _rt_out[ji]
		if line is PackedVector2Array and (line as PackedVector2Array).size() > 1:
			lines.append(line)
		else:
			failed += 1
	_rt_jobs = []
	_rt_out = []
	var t_mg := Time.get_ticks_msec()
	var n_before: int = lines.size()
	lines = _split_at_towns(lines)
	var n_split: int = lines.size()
	lines = _merge_parallel(lines)
	var n_merged: int = lines.size()
	lines = _drop_twins(_snap_into_towns(lines))
	if debug_roads:
		print("[roads] %d legs: %d after going into the towns they pass through, %d after merging where they ran side by side, %d once twins were dropped (%d ms)" % [
			n_before, n_split, n_merged, lines.size(), Time.get_ticks_msec() - t_mg])
	trunk_lines = _drop_orphans(lines)
	var t_sv := Time.get_ticks_msec()
	var verts := 0
	for l2 in lines:
		verts += (l2 as PackedVector2Array).size()
	_survey_roads()
	if debug_roads:
		var rs := Vector2.ZERO
		if Sim.native != null:
			rs = Sim.native.route_stats()
		print("[roads] %d legs (%d unroutable), %d waypoints -> search %d nodes in %d ms, survey %d ms" % [
			lines.size(), failed, verts, int(rs.x), int(rs.y),
			Time.get_ticks_msec() - t_sv])

## The routed trunk lines, as chart polylines. Read-only to everything outside;
## the map and the tests both want to see the network as it was laid.
func road_lines() -> Array:
	return trunk_lines

## Lay out the whole alignment: stations at survey spacing, a design profile
## for each line, the relaxation that makes roads meeting at a junction agree
## about the height, and the classification of what has to be carried on a deck
## or bored through the hill.
##
## One call. This used to be a dozen passes over eighty thousand stations
## alternating between here and the extension -- chain, sample, grade, weld,
## tie, classify, hold, settle, float -- and marshalling the network across the
## boundary between each of them cost more than the arithmetic did. It is also
## the only place the profile is decided now, so the ruling gradient and the cut
## and fill limits are written down once, in `survey.rs`, instead of in both
## languages and drifting apart.
func _survey_roads() -> void:
	in_survey = true
	road_prof = []
	natural = []
	_road_struct = []
	var flat := PackedVector2Array()
	var starts := PackedInt32Array()
	for line in trunk_lines:
		starts.append(flat.size())
		flat.append_array(line as PackedVector2Array)
	starts.append(flat.size())
	var res: Array = Sim.native.survey(flat, starts, SURVEY_PASSES)
	var op: PackedVector2Array = res[0]
	var oy: PackedFloat32Array = res[1]
	var og: PackedFloat32Array = res[2]
	var of: PackedByteArray = res[3]
	var os: PackedInt32Array = res[4]
	for li in trunk_lines.size():
		var a0: int = os[li]
		var a1: int = os[li + 1]
		trunk_lines[li] = op.slice(a0, a1)
		road_prof.append(oy.slice(a0, a1))
		natural.append(og.slice(a0, a1))
		_road_struct.append(of.slice(a0, a1))
	_group_structures()
	_index_corridor()
	_push_segments()
	# The painted network has to follow the earthworks, or the carriageway is
	# stained across ground that was never levelled for it. Only the legs
	# actually laid on the ground: a tunnel is inside the hill and a bridge is
	# above it, so neither is painted onto the terrain or drawn as a ribbon
	# lying on the country.
	ROADS = []
	road_draw = PackedFloat32Array()
	for li2 in trunk_lines.size():
		var pl: PackedVector2Array = trunk_lines[li2]
		var pf: PackedFloat32Array = road_prof[li2]
		for i in range(pl.size() - 1):
			var sa := in_structure(li2, i)
			var sb := in_structure(li2, i + 1)
			if sa and sb:
				continue                      # inside the bore or on the deck
			if not sa and not sb:
				ROADS.append([pl[i], pl[i + 1]])
			# The approach: one end on the ground and the other at an abutment
			# or a portal. Left out of the drawn network the carriageway simply
			# stopped short of every structure on the map and the deck floated
			# clear of it, so it is drawn -- on the alignment, which is
			# continuous, rather than on the ground, which is not.
			road_draw.append_array(PackedFloat32Array([
				pl[i].x, pl[i].y, pl[i + 1].x, pl[i + 1].y, ROAD_HALF,
				# which end is the structure: 1 the first, 2 the second
				pf[i], pf[i + 1], 1.0 if sa else (2.0 if sb else 0.0)]))
	road_draw = _one_carriageway(road_draw)
	if debug_roads:
		print("[survey] %d lines, %d stations, worst neighbour disagreement %.1f m"
			% [trunk_lines.size(), op.size(), Sim.native.worst_tie(op, oy, of, os)])
	in_survey = false

func _one_carriageway(legs: PackedFloat32Array) -> PackedFloat32Array:
	var grid: Dictionary = {}
	var out := PackedFloat32Array()
	var dropped := 0
	for i in range(0, legs.size(), 8):
		var a := Vector2(legs[i], legs[i + 1])
		var b := Vector2(legs[i + 2], legs[i + 3])
		var ya: float = legs[i + 5]
		var yb: float = legs[i + 6]
		if _on_drawn(out, grid, a, ya) and _on_drawn(out, grid, b, yb) \
				and _on_drawn(out, grid, (a + b) * 0.5, (ya + yb) * 0.5):
			dropped += 1
			continue
		var at := out.size()
		out.append_array(legs.slice(i, i + 8))
		# into every cell the leg's box touches, grown by the tolerance
		var lo := Vector2i(floori((minf(a.x, b.x) - CARRIAGEWAY_NEAR) / CARRIAGEWAY_CELL),
			floori((minf(a.y, b.y) - CARRIAGEWAY_NEAR) / CARRIAGEWAY_CELL))
		var hi := Vector2i(floori((maxf(a.x, b.x) + CARRIAGEWAY_NEAR) / CARRIAGEWAY_CELL),
			floori((maxf(a.y, b.y) + CARRIAGEWAY_NEAR) / CARRIAGEWAY_CELL))
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var k2 := Vector2i(cx, cz)
				if not grid.has(k2):
					grid[k2] = []
				(grid[k2] as Array).append(at)
	if debug_roads:
		print("[roads] %d of %d drawn legs were a second carriageway on a road already drawn" % [
			dropped, int(legs.size() / 8.0)])
	return out

## Whether a point at a height lies on a leg already in `drawn`.
func _on_drawn(drawn: PackedFloat32Array, grid: Dictionary, p: Vector2, y: float) -> bool:
	var k := Vector2i(floori(p.x / CARRIAGEWAY_CELL), floori(p.y / CARRIAGEWAY_CELL))
	for li in grid.get(k, []):
		var o: int = li
		var a := Vector2(drawn[o], drawn[o + 1])
		var b := Vector2(drawn[o + 2], drawn[o + 3])
		var ab := b - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if p.distance_to(a + ab * t) < CARRIAGEWAY_NEAR \
				and absf(y - lerpf(drawn[o + 5], drawn[o + 6], t)) < CARRIAGEWAY_SAME:
			return true
	return false

static func _poly_len(pl: PackedVector2Array) -> float:
	var s := 0.0
	for k in range(pl.size() - 1):
		s += pl[k].distance_to(pl[k + 1])
	return s

## The part of a polyline between two distances along it.
static func _sub_poly(pl: PackedVector2Array, a: float, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var s := 0.0
	for k in range(pl.size() - 1):
		var p: Vector2 = pl[k]
		var q: Vector2 = pl[k + 1]
		var d: float = p.distance_to(q)
		var s1: float = s + d
		if s1 >= a and s <= b and d > 0.0:
			if out.is_empty():
				out.append(p.lerp(q, clampf((a - s) / d, 0.0, 1.0)))
			if s1 <= b:
				out.append(q)
			else:
				out.append(p.lerp(q, clampf((b - s) / d, 0.0, 1.0)))
				break
		s = s1
	return out

func _merge_parallel(lines: Array) -> Array:
	var order: Array = range(lines.size())
	var lens: Array = []
	for pl in lines:
		lens.append(_poly_len(pl as PackedVector2Array))
	order.sort_custom(func(x: int, y: int) -> bool: return float(lens[x]) < float(lens[y]))
	var kept: Array = []
	var grid: Dictionary = {}
	# where each kept road is to be cut for a junction landing on it
	var joins: Dictionary = {}
	var cell_of := func(p: Vector2) -> Vector2i:
		return Vector2i(int(floor(p.x / MERGE_CELL)), int(floor(p.y / MERGE_CELL)))
	# Nearest point of the kept network to `p`, within one cell's reach, as
	# [distance, line, distance along it, point]; distance is INF if none.
	var nearest := func(p: Vector2) -> Array:
		var best: Array = [INF, -1, 0.0, p]
		var c: Vector2i = cell_of.call(p)
		for dj in range(-1, 2):
			for di in range(-1, 2):
				var codes: Variant = grid.get(c + Vector2i(di, dj))
				if codes == null:
					continue
				for code in (codes as PackedInt32Array):
					var li: int = code >> 12
					var si: int = code & 4095
					var pl2: PackedVector2Array = kept[li]
					var a: Vector2 = pl2[si]
					var b: Vector2 = pl2[si + 1]
					var ab: Vector2 = b - a
					var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var q: Vector2 = a + ab * t
					var d: float = p.distance_to(q)
					if d < float(best[0]):
						var along := 0.0
						for k in si:
							along += pl2[k].distance_to(pl2[k + 1])
						best = [d, li, along + a.distance_to(q), q]
		return best
	var keep := func(pl3: PackedVector2Array) -> void:
		var li3: int = kept.size()
		kept.append(pl3)
		for si3 in range(mini(pl3.size() - 1, 4095)):
			var a3: Vector2 = pl3[si3]
			var b3: Vector2 = pl3[si3 + 1]
			var lo: Vector2i = cell_of.call(Vector2(minf(a3.x, b3.x), minf(a3.y, b3.y)))
			var hi: Vector2i = cell_of.call(Vector2(maxf(a3.x, b3.x), maxf(a3.y, b3.y)))
			for cj in range(lo.y, hi.y + 1):
				for ci in range(lo.x, hi.x + 1):
					var k3 := Vector2i(ci, cj)
					var arr: PackedInt32Array = grid.get(k3, PackedInt32Array())
					arr.append((li3 << 12) | si3)
					grid[k3] = arr
	for li0 in order:
		var pl: PackedVector2Array = lines[li0]
		var total: float = float(lens[li0])
		if pl.size() < 2 or total < 1.0:
			continue
		# which stretches of it shadow a road already laid
		var n: int = maxi(int(ceil(total / MERGE_STEP)), 1)
		var near := PackedByteArray()
		near.resize(n + 1)
		for k in n + 1:
			var p: Vector2 = _sub_poly(pl, float(k) * total / float(n),
				float(k) * total / float(n))[0] if k < n else pl[pl.size() - 1]
			near[k] = 1 if float(nearest.call(p)[0]) < MERGE_NEAR else 0
		var drops: Array = []
		var k0 := -1
		for k in n + 2:
			var on: bool = k <= n and near[k] == 1
			if on and k0 < 0:
				k0 = k
			elif not on and k0 >= 0:
				var a: float = float(k0) * total / float(n)
				var b: float = float(k - 1) * total / float(n)
				if b - a >= MERGE_RUN:
					drops.append([a, b])
				k0 = -1
		if drops.is_empty():
			keep.call(pl)
			continue
		# what is left between the dropped stretches, each end that was cut
		# joined to the road it ran beside
		var from := 0.0
		for di2 in drops.size() + 1:
			var to: float = total if di2 == drops.size() else float(drops[di2][0])
			var piece_cut_start: bool = di2 > 0
			var piece_cut_end: bool = di2 < drops.size()
			if to - from >= MERGE_STUB:
				var piece: PackedVector2Array = _sub_poly(pl, from, to)
				if piece.size() >= 2:
					if piece_cut_start:
						var j0: Array = nearest.call(piece[0])
						if int(j0[1]) >= 0:
							piece.insert(0, j0[3] as Vector2)
							(joins.get_or_add(int(j0[1]), []) as Array).append(float(j0[2]))
					if piece_cut_end:
						var j1: Array = nearest.call(piece[piece.size() - 1])
						if int(j1[1]) >= 0:
							piece.append(j1[3] as Vector2)
							(joins.get_or_add(int(j1[1]), []) as Array).append(float(j1[2]))
					keep.call(piece)
			if di2 < drops.size():
				from = float(drops[di2][1])
	# Split every kept road where something joins it, so each junction is the
	# end of every road that meets there.
	var out: Array = []
	for li4 in kept.size():
		var pl4: PackedVector2Array = kept[li4]
		var cuts: Array = joins.get(li4, [])
		var len4: float = _poly_len(pl4)
		var at: Array = []
		for c4 in cuts:
			var s4: float = float(c4)
			if s4 > MERGE_SNAP and s4 < len4 - MERGE_SNAP:
				at.append(s4)
		at.sort()
		var prev := 0.0
		for s5 in at:
			if float(s5) - prev > 1.0:
				out.append(_sub_poly(pl4, prev, float(s5)))
				prev = float(s5)
		out.append(_sub_poly(pl4, prev, len4))
	# A junction that landed within a snap of a road's end is that end, so the
	# piece that joins there has to end exactly on it.
	return _snap_ends(out)

## A leg that passes through a town on its way somewhere else goes into it.
##
## A leg is searched between its two ends and nothing else, so one bound for a
## town beyond another ran through the nearer town's streets and out the far
## side without stopping -- and the nearer town's own road to the same place
## was built alongside it. Cut at the town, each half ends at the middle of it
## like every other road there, and the half that duplicates the town's own
## road is then a twin of it and goes.
func _split_at_towns(lines: Array) -> Array:
	var out: Array = []
	for pl in lines:
		var queue: Array = [pl]
		var guard := 0
		while not queue.is_empty() and guard < 256:
			guard += 1
			var p: PackedVector2Array = queue.pop_back()
			var cut := false
			for pad in town_pads:
				var c: Vector2 = pad["c"]
				var r: float = float(pad["r"])
				if p[0].distance_to(c) < r * 1.2 or p[p.size() - 1].distance_to(c) < r * 1.2:
					continue
				var best_d := INF
				var best_s := 0.0
				var along := 0.0
				for k in range(p.size() - 1):
					var a: Vector2 = p[k]
					var ab: Vector2 = p[k + 1] - a
					var t: float = clampf((c - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
					var d: float = c.distance_to(a + ab * t)
					if d < best_d:
						best_d = d
						best_s = along + ab.length() * t
					along += ab.length()
				if best_d < r * 0.9:
					var head: PackedVector2Array = _sub_poly(p, 0.0, best_s)
					head.append(c)
					var tail: PackedVector2Array = _sub_poly(p, best_s, along)
					tail.insert(0, c)
					queue.push_back(head)
					queue.push_back(tail)
					cut = true
					break
			if not cut:
				out.append(p)
	return out

## A road that ends inside a town ends at its middle.
##
## Where a leg was cut back to a junction on the road it had been shadowing,
## that junction can fall inside a town's streets a few hundred metres short of
## the middle -- and a road from there to the next town is the same road as
## the town's own, but to the twin test it ran between different places.
func _snap_into_towns(lines: Array) -> Array:
	for li in lines.size():
		var p: PackedVector2Array = lines[li]
		if p.size() < 2:
			continue
		for which in [0, p.size() - 1]:
			var e: Vector2 = p[which]
			for pad in town_pads:
				var c: Vector2 = pad["c"]
				if e.distance_to(c) < float(pad["r"]) and e.distance_to(c) > 0.01:
					p[which] = c
					break
		lines[li] = p
	return lines

## Of two roads between the same two places along much the same way, the
## shorter. A loop round by a genuinely different route is left: past half as
## long again it is a second way round, not a twin.
static func _drop_twins(lines: Array) -> Array:
	var lens: Array = []
	for pl in lines:
		lens.append(_poly_len(pl as PackedVector2Array))
	var order: Array = range(lines.size())
	order.sort_custom(func(x: int, y: int) -> bool: return float(lens[x]) < float(lens[y]))
	var seen: Dictionary = {}
	var keep := PackedByteArray()
	keep.resize(lines.size())
	keep.fill(1)
	for li in order:
		var p: PackedVector2Array = lines[li]
		if p.size() < 2:
			keep[li] = 0
			continue
		var ka: Vector2i = Vector2i((p[0] / 20.0).round())
		var kb: Vector2i = Vector2i((p[p.size() - 1] / 20.0).round())
		if ka == kb:
			keep[li] = 0
			continue
		var key: String = "%s|%s" % [str(ka), str(kb)] if ka < kb else "%s|%s" % [str(kb), str(ka)]
		if seen.has(key) and float(lens[li]) < float(seen[key]) * 1.5:
			keep[li] = 0
			continue
		if not seen.has(key):
			seen[key] = float(lens[li])
	var out: Array = []
	for li2 in lines.size():
		if keep[li2] == 1:
			out.append(lines[li2])
	return out

## Pull every road end that is within `MERGE_SNAP` of another road's end onto it.
static func _snap_ends(lines: Array) -> Array:
	var ends: Array = []
	for pl in lines:
		var p: PackedVector2Array = pl
		if p.size() >= 2:
			ends.append(p[0])
			ends.append(p[p.size() - 1])
	for li in lines.size():
		var p2: PackedVector2Array = lines[li]
		if p2.size() < 2:
			continue
		for which in [0, p2.size() - 1]:
			var e: Vector2 = p2[which]
			var best: Vector2 = e
			var bd := MERGE_SNAP
			for o in ends:
				var d: float = e.distance_to(o as Vector2)
				if d > 0.01 and d < bd:
					bd = d
					best = o
			p2[which] = best
		lines[li] = p2
	return lines

func _drop_orphans(lines: Array) -> Array:
	if lines.size() < 2:
		return lines
	var root: Array = []
	root.resize(lines.size())
	for i in lines.size():
		root[i] = i
	var find := func(a: int) -> int:
		var r: int = a
		while int(root[r]) != r:
			r = int(root[r])
		return r
	var at: Dictionary = {}
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		if pl.size() < 2:
			continue
		for p in [pl[0], pl[pl.size() - 1]]:
			var k := "%d:%d" % [int(round(p.x / 60.0)), int(round(p.y / 60.0))]
			if at.has(k):
				var ra: int = find.call(li)
				var rb: int = find.call(int(at[k]))
				if ra != rb:
					root[ra] = rb
			else:
				at[k] = li
	var size: Dictionary = {}
	for li2 in lines.size():
		var r: int = find.call(li2)
		size[r] = int(size.get(r, 0)) + 1
	# the component the airfield is in is always kept, however small
	var home := -1
	var best := 1e18
	for li3 in lines.size():
		var pl3: PackedVector2Array = lines[li3]
		if pl3.size() < 2:
			continue
		var d: float = (pl3[0] as Vector2).length_squared()
		if d < best:
			best = d
			home = li3
	var keep_root: int = find.call(home) if home >= 0 else -1
	var out: Array = []
	var dropped := 0
	for li4 in lines.size():
		var r2: int = find.call(li4)
		if r2 == keep_root or int(size[r2]) >= 2:
			out.append(lines[li4])
		else:
			dropped += 1
	if dropped > 0 and debug_roads:
		print("[roads] dropped %d road(s) of %d that led nowhere; %d network(s) left"
			% [dropped, lines.size(), size.size()])
	return out

## Lay the network out again. The command line is parsed after the world has
## already built its roads, so the harness needs a way to watch the survey.
func resurvey_roads() -> void:
	road_prof = []
	corr = []
	_survey_roads()

func _group_structures() -> void:
	road_bridges = []
	road_tunnels = []
	for li in trunk_lines.size():
		var pl: PackedVector2Array = trunk_lines[li]
		var prof: PackedFloat32Array = road_prof[li]
		var flags: PackedByteArray = _road_struct[li]
		var i0 := 0
		while i0 < flags.size():
			if flags[i0] == 0:
				i0 += 1
				continue
			var kind: int = flags[i0]
			var i1 := i0
			while i1 + 1 < flags.size() and flags[i1 + 1] == kind:
				i1 += 1
			# the whole run, not just its ends: a span follows the alignment,
			# and a deck drawn as one straight beam between the abutments
			# leaves the road beside it
			var pts := PackedVector2Array()
			var ys := PackedFloat32Array()
			for k in range(i0, i1 + 1):
				pts.append(pl[k])
				ys.append(prof[k])
			var rec := {"a": pl[i0], "b": pl[i1],
				"ya": prof[i0], "yb": prof[i1], "pts": pts, "ys": ys}
			if kind == F_BRIDGE:
				# and the ramps up onto it, which belong to it as much as the
				# deck does: see `bridge_headroom`
				var ramps: Array = []
				if pts.size() >= 2:
					for r in [_ramp_from(li, i0, -1), _ramp_from(li, i1, 1)]:
						if (r as PackedVector2Array).size() >= 2:
							ramps.append(r)
				rec["ramps"] = ramps
				road_bridges.append(rec)
			else:
				road_tunnels.append(rec)
			i0 = i1 + 1

## The ramp off one end of a bridge: the end station, then the stations walking
## away from the deck (`step` is -1 or +1 along the line) for as long as the
## made road is still up on its fill. Always at least the leg onto the deck.
func _ramp_from(li: int, i: int, step: int) -> PackedVector2Array:
	var pl: PackedVector2Array = trunk_lines[li]
	var prof: PackedFloat32Array = road_prof[li]
	var nat: PackedFloat32Array = natural[li] if li < natural.size() else prof
	var flags: PackedByteArray = _road_struct[li]
	var out := PackedVector2Array([pl[i]])
	var k := i + step
	while k >= 0 and k < pl.size() and out.size() <= RAMP_STATIONS:
		if flags[k] != 0:
			break                           # straight onto another structure
		out.append(pl[k])
		if prof[k] - nat[k] <= RAMP_FILL:
			break
		k += step
	return out

## Is this station the end of a bridge -- the abutment, where the deck takes
## over from the ground? A run of one station is not a span at all and has no
## deck drawn over it.
func _bridge_end(li: int, k: int) -> bool:
	if li >= _road_struct.size():
		return false
	var flags: PackedByteArray = _road_struct[li]
	if k < 0 or k >= flags.size() or flags[k] != F_BRIDGE:
		return false
	var before := k > 0 and flags[k - 1] == F_BRIDGE
	var after := k + 1 < flags.size() and flags[k + 1] == F_BRIDGE
	return before != after

## How far an end panel falls at `across` (0 the deck's left edge, 1 its
## right), from the LAP_N heights starting at `at` in `laps`.
static func _lap_dy(laps: PackedFloat32Array, at: int, across: float) -> float:
	var f: float = clampf(across * float(LAP_N - 1), 0.0, float(LAP_N - 1))
	var k: int = mini(int(f), LAP_N - 2)
	return lerpf(laps[at + k], laps[at + k + 1], f - float(k))

func _index_bridge_decks() -> void:
	_deck_src = road_bridges
	_deck_idx = []
	for br in road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2 or ys.size() != pts.size():
			continue
		var ramps: Array = br.get("ramps", [])
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in pts:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var m := BRIDGE_HALF + BRIDGE_LAP + 1.0
		lo -= Vector2(m, m)
		hi += Vector2(m, m)
		for r in ramps:
			for q2 in (r as PackedVector2Array):
				lo = Vector2(minf(lo.x, q2.x - RAMP_HEAD), minf(lo.y, q2.y - RAMP_HEAD))
				hi = Vector2(maxf(hi.x, q2.x + RAMP_HEAD), maxf(hi.y, q2.y + RAMP_HEAD))
		# How far the end panels fall to meet the road at their outer edge:
		# `Scenery._deck_lap`, which draws them, and the same numbers.
		# ...at LAP_N points across its outer edge, as it is drawn, so what a
		# foot or a wheel stands on there is the panel that is seen: for each
		# end, from the deck's left edge (looking along it from the first
		# station to the last) to its right
		var laps := PackedFloat32Array()
		var along0: Vector2 = (pts[1] - pts[0]).normalized()
		var left0 := Vector2(-along0.y, along0.x)
		var along1: Vector2 = (pts[pts.size() - 1] - pts[pts.size() - 2]).normalized()
		var left1 := Vector2(-along1.y, along1.x)
		for e in 2:
			var st: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var nx: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			var tip: Vector2 = st + (st - nx).normalized() * BRIDGE_LAP
			var lf: Vector2 = left0 if e == 0 else left1
			var top: float = (ys[0] if e == 0 else ys[ys.size() - 1]) - Sim.planet_drop(st.x, st.y)
			var edge := PackedVector2Array()
			for k in LAP_N:
				edge.append(tip + lf * BRIDGE_HALF * (1.0 - 2.0 * float(k) / float(LAP_N - 1)))
			var got: PackedFloat32Array = Sim.native.surfaces_at(edge, Terrain.BASE_CELL)
			for k in LAP_N:
				var dy: float = got[k] + 0.03 - top if got.size() > k else 0.0
				laps.append(clampf(dy, -BRIDGE_STEP, BRIDGE_STEP))
		_deck_idx.append({"lo": lo, "hi": hi, "pts": pts, "ys": ys, "ramps": ramps,
			"laps": laps})

## Build the deck index now, on this thread, so that workers can read it. It is
## otherwise built by whoever asks first, and two workers asking at once would
## both be writing it.
func index_bridges() -> void:
	if not is_same(_deck_src, road_bridges):
		_index_bridge_decks()

## Could anything within `r` of the box from `lo` to `hi` be near a bridge? A
## cheap first question for something with a lot of points to ask about -- a
## street, a town's worth of lamp posts -- most of which are nowhere near one.
func near_bridges(lo: Vector2, hi: Vector2, r: float) -> bool:
	if road_bridges.is_empty():
		return false
	index_bridges()
	for b in _deck_idx:
		var blo: Vector2 = b["lo"]
		var bhi: Vector2 = b["hi"]
		if hi.x + r >= blo.x and lo.x - r <= bhi.x and hi.y + r >= blo.y and lo.y - r <= bhi.y:
			return true
	return false

## How much room there is under the road bridges within `r` of (x, z): from the
## ground to the underside of the lowest deck over that disc. INF where no deck
## reaches, and 0 on a ramp up to one, which has no underneath -- it is a bank,
## or in a town a walled ramp, and nothing stands on it or crosses it.
##
## Everything that puts something down near a road has to ask this as well as
## the kerb test. A bridge is not in the road index, because it is not a road
## on the ground, so the trees, the street furniture, the streets and the props
## in a town's streets were all laid out as if the deck were not there: in the
## carriageway of the approach, up through the deck, across the foot of the
## ramp. `ground` is the height the thing stands at, when the caller has it.
##
## `banks` false asks about the decks alone: a street meets a ramp or crosses
## it in its own way (`Scenery.plan_finish`), and does not want to be cut back
## from it here. With it, a street's approach to a raised road is a bank too.
func bridge_headroom(x: float, z: float, r: float, ground := NAN, banks := true) -> float:
	var q := Vector2(x, z)
	if banks and not _street_corr.is_empty() and _approach_box.grow(r).has_point(q):
		for ap in _street_corr:
			var half: float = float(ap[7]) * 1.6 + 8.0
			if seg_dist(q, ap[0], ap[1]) < half + r:
				return 0.0
	if road_bridges.is_empty():
		return INF
	index_bridges()
	var best := INF
	for b in _deck_idx:
		var lo: Vector2 = b["lo"]
		var hi: Vector2 = b["hi"]
		if x < lo.x - r or x > hi.x + r or z < lo.y - r or z > hi.y + r:
			continue
		for rp in (b["ramps"] as Array):
			var ramp: PackedVector2Array = rp
			if not banks:
				continue
			# the head of the bank, wider than the rest of it
			if q.distance_to(ramp[0]) < RAMP_HEAD + r:
				return 0.0
			for i in ramp.size() - 1:
				if seg_dist(q, ramp[i], ramp[i + 1]) < RAMP_HALF + r:
					return 0.0
		var pts: PackedVector2Array = b["pts"]
		var ys: PackedFloat32Array = b["ys"]
		var last := pts.size() - 2
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var c: Vector2 = pts[i + 1]
			var run := a.distance_to(c)
			if run < 0.5:
				continue
			var dir := (c - a) / run
			var a2 := a - dir * BRIDGE_LAP if i == 0 else a
			var c2 := c + dir * BRIDGE_LAP if i == last else c
			var t: float = clampf((q - a2).dot(dir), 0.0, a2.distance_to(c2))
			if q.distance_to(a2 + dir * t) > BRIDGE_HALF + r:
				continue
			if is_nan(ground):
				ground = Sim.height_at(x, z)
			var f: float = clampf((t - a.distance_to(a2)) / run, 0.0, 1.0)
			var under: float = lerpf(ys[i], ys[i + 1], f) - Sim.planet_drop(x, z) \
				- BRIDGE_GIRDER
			best = minf(best, maxf(under - ground, 0.0))
	return best

## The top of a road bridge's deck at (x, z), for something at height `y_ref`:
## -1e9 when there is no deck there, or when it is more than a step above.
func bridge_floor(x: float, z: float, y_ref: float) -> float:
	if road_bridges.is_empty():
		return -1e9
	if not is_same(_deck_src, road_bridges):
		_index_bridge_decks()
	var best := -1e9
	var q := Vector2(x, z)
	for b in _deck_idx:
		var lo: Vector2 = b["lo"]
		var hi: Vector2 = b["hi"]
		if x < lo.x or x > hi.x or z < lo.y or z > hi.y:
			continue
		var pts: PackedVector2Array = b["pts"]
		var ys: PackedFloat32Array = b["ys"]
		var last := pts.size() - 2
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var c: Vector2 = pts[i + 1]
			var run := a.distance_to(c)
			if run < 0.5:
				continue
			var dir := (c - a) / run
			var a2 := a - dir * BRIDGE_LAP if i == 0 else a
			var c2 := c + dir * BRIDGE_LAP if i == last else c
			var span := a2.distance_to(c2)
			var t: float = (q - a2).dot(dir)
			if t < 0.0 or t > span:
				continue
			var off: float = absf((q - a2).dot(Vector2(-dir.y, dir.x)))
			if off > BRIDGE_HALF:
				continue
			# along the station-to-station profile, as the deck is drawn
			var f: float = clampf((t - (a.distance_to(a2))) / run, 0.0, 1.0)
			var y: float = lerpf(ys[i], ys[i + 1], f) - Sim.planet_drop(x, z)
			# ...and on an end panel, falling to the road at its outer edge,
			# corner by corner across it
			var laps: PackedFloat32Array = b["laps"]
			var lead: float = a.distance_to(a2)
			# 0 on the deck's left edge, 1 on its right
			var across: float = clampf(0.5 - (q - a2).dot(Vector2(-dir.y, dir.x))
				/ (BRIDGE_HALF * 2.0), 0.0, 1.0)
			if i == 0 and t < lead:
				y += _lap_dy(laps, 0, across) * (lead - t) / BRIDGE_LAP
			elif i == last and t > lead + run:
				y += _lap_dy(laps, LAP_N, across) * (t - lead - run) / BRIDGE_LAP
			if y <= y_ref + BRIDGE_STEP and y > best:
				best = y
	return best

## The ground, or the deck of a bridge if he is up on one: what something
## moving on the surface stands on.
func drive_height(x: float, z: float, y_ref: float) -> float:
	return maxf(Sim.height_at(x, z), bridge_floor(x, z, y_ref))

## Is the road inside a structure at this station?
func in_structure(li: int, i: int) -> bool:
	if li >= _road_struct.size():
		return false
	var f: PackedByteArray = _road_struct[li]
	return i < f.size() and f[i] != 0

func _index_corridor() -> void:
	corr = []
	# Every deck end, and which way the deck leaves it. A road whose own line
	# stops at an abutment -- one that joins another there -- has no bridge
	# station of its own to say so, and its approach was graded as a plain road
	# ending: no seat under the deck and no head to the bank, and the drawn
	# ramp stopped most of a metre under the deck.
	var deck_ends: Array = []
	for br in road_bridges:
		var bp: PackedVector2Array = br.get("pts", PackedVector2Array())
		if bp.size() >= 2:
			deck_ends.append([bp[0], (bp[1] - bp[0]).normalized()])
			deck_ends.append([bp[bp.size() - 1],
				(bp[bp.size() - 2] - bp[bp.size() - 1]).normalized()])
	for li in trunk_lines.size():
		var pl: PackedVector2Array = trunk_lines[li]
		var prof: PackedFloat32Array = road_prof[li]
		# and the ground the earthworks started from, so the cut can be bounded
		# against the centreline rather than against whatever is under the point
		# being asked about -- which differs across the width of the road and
		# tips the carriageway over as soon as the bound bites
		var nat: PackedFloat32Array = natural[li] if li < natural.size() \
			else prof
		for i in range(pl.size() - 1):
			# A leg inside a structure moves no earth at all: the deck is above
			# the ground or the bore is inside the hill, and either way the
			# country under it is untouched.
			#
			# The leg *onto* one does. That is the abutment -- the embankment
			# carried up to meet the deck, or the cutting down to the portal --
			# and leaving it out stopped the earthworks a whole station short:
			# the road ended on a bank twenty metres up and the deck began in
			# mid air beyond it.
			if in_structure(li, i) and in_structure(li, i + 1):
				continue
			# Which end of it is an abutment. Past that end is the first span,
			# and the bank stops there instead of rounding off underneath it.
			var ends := 0
			if _bridge_end(li, i) or _runs_onto_deck(pl[i + 1], pl[i], deck_ends):
				ends |= 1
			if _bridge_end(li, i + 1) or _runs_onto_deck(pl[i], pl[i + 1], deck_ends):
				ends |= 2
			corr.append([pl[i], pl[i + 1], prof[i], prof[i + 1],
				nat[i], nat[i + 1], ends])
	_push_corridor()

## Does a leg running from `from` to `to` arrive at a deck end and carry on
## straight onto the deck? `deck_ends` is what `_index_corridor` gathered.
static func _runs_onto_deck(from: Vector2, to: Vector2, deck_ends: Array) -> bool:
	var run := from.distance_to(to)
	if run < 1.0:
		return false
	var dir := (to - from) / run
	for de in deck_ends:
		if (de[0] as Vector2).distance_to(to) < 1.0 and dir.dot(de[1] as Vector2) > 0.7:
			return true
	return false

## Hand the corridor to the extension, which is where its index lives: the
## network's legs and the streets' approaches to it, ten floats each (the last
## the half width, 0 for a trunk road's).
func _push_corridor() -> void:
	var flat := PackedFloat32Array()
	for leg in corr + _street_corr:
		var la: Vector2 = leg[0]
		var lb: Vector2 = leg[1]
		flat.append(la.x)
		flat.append(la.y)
		flat.append(lb.x)
		flat.append(lb.y)
		flat.append(float(leg[2]))
		flat.append(float(leg[3]))
		flat.append(float(leg[4]))
		flat.append(float(leg[5]))
		flat.append(float(leg[6]) if leg.size() > 6 else 0.0)
		flat.append(float(leg[7]) if leg.size() > 7 else 0.0)
	# Every deck end, the way the deck leaves it and its design height: the
	# bank at a bridge end is shaped from these (`world::Abut`), whatever angle
	# the road arrives at.
	var ends := PackedFloat32Array()
	for br in road_bridges:
		var bp: PackedVector2Array = br.get("pts", PackedVector2Array())
		var by: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if bp.size() < 2 or by.size() != bp.size():
			continue
		var last := bp.size() - 1
		for e in [[bp[0], bp[1], by[0]], [bp[last], bp[last - 1], by[last]]]:
			var at: Vector2 = e[0]
			var d: Vector2 = ((e[1] as Vector2) - at).normalized()
			ends.append_array(PackedFloat32Array([at.x, at.y, d.x, d.y, float(e[2])]))
	Sim.native.set_corridor(flat, ends)

func set_street_approaches(legs: Array) -> void:
	_street_corr = legs
	_box_approaches()
	_push_corridor()

func _box_approaches() -> void:
	_approach_box = Rect2()
	for i in _street_corr.size():
		var ap: Array = _street_corr[i]
		var r := Rect2(ap[0] as Vector2, Vector2.ZERO).expand(ap[1] as Vector2)
		_approach_box = r if i == 0 else _approach_box.merge(r)
	_approach_box = _approach_box.grow(40.0)

## The streets' approaches, for whatever has to keep off them as it keeps off
## a ramp.
func street_approaches() -> Array:
	return _street_corr

## The land as it was before any road was built on it. The corridor is the only
## thing `_in_survey` switches off, which is exactly the difference between the
## finished ground and the ground the earthworks started from -- so this is what
## a cutting or an embankment should be measured against. Comparing the road
## against the hillside beside it instead cannot tell a road running along the
## floor of a valley from a road in a ninety metre trench.
func natural_height_at(x: float, z: float) -> float:
	var was := in_survey
	in_survey = true
	var h := Sim.height_at(x, z)
	in_survey = was
	return h

## The made surface at a point: its height and how much of it applies here,
## falling from the whole carriageway out to nothing at the edge of the graded
## shoulder. Zero weight means the land is left as it was.
## Returns (made height, how much of it applies, the ground it was cut from).
func road_surface(x: float, z: float) -> Vector3:
	# The corridor is stamped into a grid inside the extension, which is the
	# only place it exists: `_corr` here is just the list handed over to it.
	if corr.is_empty() or road_prof.size() != trunk_lines.size():
		return Vector3.ZERO
	var r: Vector3 = Sim.native.road_surface_at(x, z)
	# x is the corridor's running surface and comes back in the extension's flat
	# frame; everything that compares it against the ground wants it on the
	# sphere, the same as `height_at`. y is a weight and is left alone.
	r.x -= Sim.planet_drop(x, z)
	return r

## Everything the height field and the road drawing depend on that comes out of
## routing the network: the pads the towns stand on, the trunk legs, the
## surveyed profile, the bridges and the corridor index. All of it is the same
## every run, and arriving at it costs the better part of three seconds, so it
## goes to disk with the rest of the bake.
func road_state() -> Dictionary:
	return {"pads": town_pads, "roads": ROADS, "lines": trunk_lines,
		"prof": road_prof, "bridges": road_bridges, "corr": corr,
		"segs": segments, "tunnels": road_tunnels, "draw": road_draw,
		"struct": _road_struct, "natural": natural}

func load_road_state(d: Dictionary) -> void:
	town_pads = d["pads"]
	ROADS = d["roads"]
	trunk_lines = d["lines"]
	road_prof = d["prof"]
	road_bridges = d["bridges"]
	corr = d["corr"]
	segments = d["segs"]
	road_tunnels = d.get("tunnels", [])
	road_draw = d.get("draw", PackedFloat32Array())
	_road_struct = d.get("struct", [])
	natural = d.get("natural", [])
	# The corridor's grid is not baked -- it is stamped inside the extension,
	# so a run that loads the network from disk has to hand the legs over just
	# as a run that surveyed them does. And the town platforms with them:
	# without, everything asked of the ground straight after a load -- the
	# streets' junctions with the roads among it -- read the towns as though
	# they had never been levelled.
	push_world()
	_push_corridor()
	_push_segments()

## Level the ground under each settlement, and report which sites survived it.
func register_town_pads(sites: Array) -> Array:
	town_pads.clear()
	var kept: Array = []
	for site in sites:
		var c: Vector2 = site["c"]
		var r: float = site["r"]
		# the mean of the land under the footprint, not the height at the middle
		var total := 0.0
		var n := 0
		for i in 9:
			for j in 9:
				var q := c + Vector2(float(i - 4), float(j - 4)) * (r * 0.22)
				if q.distance_to(c) > r:
					continue
				# In the flat frame, because this platform is handed to the
				# extension and stamped into the field there -- the same reason
				# an aerodrome's elevation is. Levelled to a curved height it
				# was dug in by the drop: a town 130 km out sat at the bottom
				# of a 1330 m pit, and the trunk roads reaching it inherited
				# gradients that no survey had asked for.
				total += Sim.survey_height_at(q.x, q.y)
				n += 1
		var y: float = (total / maxf(float(n), 1.0)) if n > 0 \
			else Sim.survey_height_at(c.x, c.y)
		# A town is not a reason to raise land out of the sea.
		#
		# This used to clamp the platform to at least eight metres above the
		# water, which on a world where every site was dry by construction was a
		# harmless floor. On a generated planet it is a licence to build: a site
		# whose ground averages below sea level got a pad above it anyway, and
		# the field obligingly lifted an island out of the ocean to stand one
		# small town on. Sites that are not already land are dropped, and the
		# caller is told which so it does not build a town on a pad that is not
		# there.
		# ...nor out of a lake: the platform has to stand clear of whichever
		# water is there, in the same flat reckoning it is levelled in.
		if y < Sim.sea_at(c.x, c.y) + Sim.planet_drop(c.x, c.y) + 8.0:
			continue
		kept.append(site)
		town_pads.append({"c": c, "r": r, "y": y})
	return kept

## Mean gradient over a footprint, as a fraction. Used to choose where a town
## goes: the flattest workable ground within reach of where it was wanted.
func site_roughness(c: Vector2, r: float) -> float:
	return site_roughness_many(PackedVector2Array([c]),
		PackedFloat64Array([r]))[0]

## The same for a whole list of candidates, which is how it is actually asked.
##
## The measure is 49 stations, each a normal, each of those four heights: 196
## crossings of the extension boundary for one candidate, and siting the world's
## settlements tries forty-nine candidates for each of forty-eight of them.
## Measured, four hundred and sixty thousand crossings and 550 ms of a four
## second cold start -- the largest single thing in laying out the road network.
## Asked as a list it is one crossing and the stations run across every core.
func site_roughness_many(centres: PackedVector2Array,
		radii: PackedFloat64Array) -> PackedFloat64Array:
	return Sim.native.roughness_at(centres, radii)

## Which trunk road each of these points would run out to meet.
##
## The whole network against every point, which is what it has to be -- but the
## network is twenty-nine thousand legs and walking it in script once per town
## was 156 ms of every launch, cached network or not.
func nearest_trunk_many(pts: PackedVector2Array) -> PackedVector2Array:
	var flat := PackedFloat32Array()
	flat.resize(ROADS.size() * 4)
	var w := 0
	for r in ROADS:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		flat[w] = a.x
		flat[w + 1] = a.y
		flat[w + 2] = b.x
		flat[w + 3] = b.y
		w += 4
	return Sim.native.nearest_on_lines(flat, pts)

func register_segments(segs: Array) -> void:
	segments = segs
	_push_segments()

## Hand the whole network to the extension, where it is indexed on a uniform
## grid and every distance query is answered exactly.
##
## What was here before was a 256 x 256 raster of the distance field over an
## eighteen kilometre box, and the reason it existed was that walking the
## segments in script cost more than the rest of world generation put together.
## It was also wrong: 141 m to a cell against a fifteen metre carriageway, so
## standing on the centreline it reported a mean of 30 m away and up to 85, and
## the answer had to be guarded by walking the segments properly wherever it
## mattered. An indexed exact query is both faster than the guard and right
## everywhere, and it covers the whole map rather than a box around home.
func _push_segments() -> void:
	var flat := PackedFloat32Array()
	var n := 0
	for src in [ROADS, segments]:
		n += (src as Array).size()
	flat.resize(n * 4)
	var w := 0
	for src in [ROADS, segments]:
		for r in (src as Array):
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			flat[w] = a.x
			flat[w + 1] = a.y
			flat[w + 2] = b.x
			flat[w + 3] = b.y
			w += 4
	Sim.native.set_segments(flat)
	segments_indexed = n

## Distance in metres from (x, z) to the nearest road or street centreline.
func road_distance(x: float, z: float) -> float:
	return Sim.native.road_distance_at(x, z, ROAD_REACH)

## The same, for a batch of points -- which is how anything scattering over the
## country should ask, so the whole set is answered across every core at once.
func road_distances(pts: PackedVector2Array) -> PackedFloat32Array:
	return Sim.native.road_distances_at(pts, ROAD_REACH)

func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Every position the network holds carried to the new chart by `move`, and
## handed to the extension again: see `Sim.rechart_world`.
func rechart(move: Callable) -> void:
	for i in ROADS.size():
		var r: Array = ROADS[i]
		ROADS[i] = [move.call(r[0]), move.call(r[1])]
	for li in trunk_lines.size():
		var line: PackedVector2Array = trunk_lines[li]
		var out := PackedVector2Array()
		for p in line:
			out.append(move.call(p))
		trunk_lines[li] = out
	for pad in town_pads:
		pad["c"] = move.call(pad["c"] as Vector2)
	for coll in [road_bridges, road_tunnels]:
		for b in coll:
			b["a"] = move.call(b["a"] as Vector2)
			b["b"] = move.call(b["b"] as Vector2)
			var pts: PackedVector2Array = b.get("pts", PackedVector2Array())
			var np := PackedVector2Array()
			for p2 in pts:
				np.append(move.call(p2))
			b["pts"] = np
			var ramps: Array = b.get("ramps", [])
			for ri in ramps.size():
				var rp: PackedVector2Array = ramps[ri]
				var nr := PackedVector2Array()
				for p3 in rp:
					nr.append(move.call(p3))
				ramps[ri] = nr
	# The decks are indexed off the list, which has just been moved in place:
	# the same list, so nothing asking about a deck knew to look again, and
	# every deck was stood on where it had been in the old chart.
	_deck_src = []
	# The town streets, which are pushed to the extension with the trunk roads
	# and were pushed again here unmoved: after a chart move the street stain
	# and the clearance the buildable test keeps from a kerb were both still
	# laid out wherever the towns had been in the old chart.
	for si in segments.size():
		var sg: Array = segments[si]
		segments[si] = [move.call(sg[0]), move.call(sg[1])]
	for ap in _street_corr:
		ap[0] = move.call(ap[0] as Vector2)
		ap[1] = move.call(ap[1] as Vector2)
	_box_approaches()
	_index_corridor()
	_push_segments()
	push_world()
