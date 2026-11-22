class_name CqbMatch
extends Node3D
## Close quarters, on foot, in the middle of a town.
##
## Two squads and a few blocks of streets. Nobody has a vehicle: the fight is
## alleys, corners and whatever is lying in the road to get behind. The town's
## buildings are solid blocks, so the match brings the clutter a street fight
## needs -- barricades, wrecks, containers, and a few roofless shells you can
## actually go inside -- and takes it away again when it ends.
##
## The buildings and the clutter all live in `Obstacles`, which is what stops a
## man and a bullet alike. Routes come from a grid laid over the same field, so
## the AI walks round exactly what the player has to walk round.

const HALF := 132.0               # the arena, either side of the crossroads
const CELL := 2.0                 # route grid
const SQUAD := 6                  # a side, the player included, unless chosen otherwise
## How many a side, chosen in the hangar: ours (the player is one of them) and
## theirs. They need not be the same.
static var size_us := SQUAD
static var size_them := SQUAD
const SIZES := [2, 3, 4, 6, 8, 10, 12, 16]

static func side_size(team: int) -> int:
	return clampi(size_us if team == 0 else size_them, 1, 24)
const RESPAWN := 4.5
const KILL_GOAL := 60
## What the match is played to, chosen on the mission screen.
const GOALS := [20, 30, 40, 60, 80, 100, 150, 200]
static var kill_goal := KILL_GOAL
const KITS := ["carbine", "smg", "carbine", "shotgun", "dmr", "carbine", "smg"]

## Chosen in the hangar before the match: which town.
static var town := 0
static var loadout: Array = ["carbine", "smg"]
static var quiet := false
## The classes as the player has them set up, and the one he last deployed as.
## Copies of `Firearm.CLASSES`, so the gunsmith's changes last the session.
static var classes: Array = []
static var class_pick := 0
## Set from the command line, to deploy with a plain loadout instead.
static var plain := false
## Offline, the side the player chose on arriving: 0 BLUE, the bloc of the
## aeroplane picked in the hangar, or 1 RED, the other one. In a session the
## side is `NetLink.abs_side` instead and this is not read.
static var offline_side := 0
## Set while a match restarts for a change of side, so that it does not ask
## again straight away.
static var side_settled := false

## Whether the player's own side (side 0 on this machine) fights with NATO
## kit. The hangar's aeroplane says, unless he chose RED offline.
static func our_nato() -> bool:
	var nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	if Sim.net == null or not Sim.net.active:
		nato = nato != (offline_side == 1)
	return nato

static func kit_classes() -> Array:
	if classes.is_empty():
		for c in Firearm.CLASSES:
			classes.append((c as Dictionary).duplicate())
	return classes

## Aircraft over the town as well.
var air := false
## The firing range: the town, the deploy screen and the rules of a street
## fight, and nobody else in it.
var range_mode := false

## Vehicles in the fight as well as men.
var armour := false
var world: Node = null
var streaks := Killstreaks.new(self)
var mode: GameMode = null
var centre := Vector2.ZERO
var player: Walker = null
var soldiers: Array = []
var over := false
var kills := 0
var deaths := 0
var headshots := 0

var _nav := AStarGrid2D.new()
## The streets, for anything on tracks: [`VCELL`] metre cells.
var _vnav := AStarGrid2D.new()
var _vn := 0
const VCELL := 6.0
var _drive_t := 0.0
var _n := 0
var _corner := Vector2.ZERO
var _teams := {0: [], 1: []}
var _contacts := {0: [], 1: []}
var _spots: Array = []
var _queue: Array = []            # [seconds left, team, slot]
var _rng := RandomNumberGenerator.new()


var map_tex: ImageTexture = null
## The player is somewhere else for a while -- at a gun station overhead --
## and the man standing in the street is not there to be shot.
var away := false
var stats := {"props": 0, "ruins": 0, "free_cells": 0}
## What was put down and where: [kind, position, yaw].
var props: Array = []

func setup(at: Vector2, game: GameMode, owner_world: Node, town_set: TownSet) -> void:
	dressing = town_set
	centre = town_set.centre if is_instance_valid(town_set) else Vector2(snappedf(at.x, CELL), snappedf(at.y, CELL))
	mode = game
	world = owner_world
	_rng.seed = 90210
	_n = int(HALF * 2.0 / CELL)
	_corner = centre - Vector2(HALF, HALF)
	if is_instance_valid(town_set):
		props = town_set.props
		ladders = town_set.ladders
		crane_at = town_set.crane_at
		faction = town_set.faction
		biome = town_set.biome
		for k in town_set.stats:
			stats[k] = town_set.stats[k]
	_survey()
	_spots = [Vector3(centre.x, 0, centre.y)]
	for o in [Vector2(-64, -64), Vector2(64, -64), Vector2(-64, 64), Vector2(64, 64),
			Vector2(0, -70), Vector2(0, 70), Vector2(-100, 0), Vector2(100, 0),
			Vector2(-36, 0), Vector2(36, 0)]:
		var p: Vector3 = _free_near(Vector3(centre.x + o.x, 0, centre.y + o.y))
		if p != Vector3.INF:
			_spots.append(p)
	Sfx.warm(Firearm.SOUNDS)
	if range_mode:
		return
	# In a session the host runs both squads; this end is sent pictures of
	# them (see `adopt_ghost`).
	if NetLink.mirroring():
		return
	for t in [0, 1]:
		for i in side_size(t):
			if t == 0 and i == 0:
				continue                    # that one is you
			_spawn(t, i)

func _exit_tree() -> void:
	Effects.credit = null
	Effects.spare_team = -1
	streaks.drop_warheads()

func _ground(x: float, z: float) -> float:
	return Sim.height_at(x, z)

# ------------------------------------------------------------- the ground
## The town itself -- what is standing in its streets -- is not the match's.
## It is the same `TownSet` the world puts down there in every other mode; the
## match borrows it, surveys routes through it, and leaves it where it was.
var dressing: TownSet = null
var faction := "usa"
var biome := "grass"
var crane_at := Vector3.INF
var ladders: Array = []
var site: Dictionary = {}

# -------------------------------------------------------------------- routes
func _survey() -> void:
	_nav.region = Rect2i(0, 0, _n, _n)
	_nav.cell_size = Vector2(CELL, CELL)
	_nav.offset = _corner + Vector2(CELL, CELL) * 0.5
	_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_nav.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_nav.update()
	# And the same again for things too wide for an alley: a coarser grid
	# that only the streets and the squares are open on. Anything a tank
	# would simply drive through does not count as in its way.
	_vn = int(HALF * 2.0 / VCELL)
	_vnav.region = Rect2i(0, 0, _vn, _vn)
	_vnav.cell_size = Vector2(VCELL, VCELL)
	_vnav.offset = _corner + Vector2(VCELL, VCELL) * 0.5
	_vnav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_vnav.update()
	_edit_seen = Obstacles.edit_count()
	_mark_men(Vector2i.ZERO, Vector2i(_n - 1, _n - 1))
	_mark_vehicles(Vector2i.ZERO, Vector2i(_vn - 1, _vn - 1))
	_comp = _components(_nav, _n)
	_vcomp = _components(_vnav, _vn)
	_paint_map()

## How far through `Obstacles.edits` the grids have been brought up to date.
var _edit_seen := 0
var _edit_t := 0.0

## Bring the route grids up to date with whatever has gone up or come down
## since they were surveyed: the rest of a town still being built as the match
## began, the heap a block leaves, a wreck. Twice a second at most; only the
## cells under what changed are looked at again.
func _refresh_routes(delta: float) -> void:
	_edit_t -= delta
	if _edit_t > 0.0 or Obstacles.edit_count() == _edit_seen:
		return
	_edit_t = 0.5
	var arena := Rect2(_corner, Vector2(HALF, HALF) * 2.0)
	var dirty: Array = []
	if _edit_seen < Obstacles.edit_base:
		dirty.append(arena)              # fallen behind: all of it
	else:
		for k in range(_edit_seen - Obstacles.edit_base, Obstacles.edits.size()):
			var r: Rect2 = Obstacles.edits[k]
			if r.intersects(arena):
				dirty.append(r.intersection(arena))
	_edit_seen = Obstacles.edit_count()
	if dirty.is_empty():
		return
	for r in dirty:
		var rr: Rect2 = (r as Rect2).grow(BODY_PAD + CELL)
		_mark_men(_cell_of(rr.position, CELL, _n), _cell_of(rr.end, CELL, _n))
		var rv: Rect2 = (r as Rect2).grow(VCELL)
		_mark_vehicles(_cell_of(rv.position, VCELL, _vn), _cell_of(rv.end, VCELL, _vn))
	_comp = _components(_nav, _n)
	_vcomp = _components(_vnav, _vn)
	_paint_map()

func _cell_of(p: Vector2, size: float, n: int) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - _corner.x) / size)), 0, n - 1),
		clampi(int(floor((p.y - _corner.y) / size)), 0, n - 1))

## How wide a man is, as far as the routes are concerned: `Soldier.BODY_R`.
const BODY_PAD := 0.36
## How far either way from the middle of a cell its cross reaches. With the
## pad, a wall anywhere on the line between two cells' middles is under one
## cross or the other.
const ARM := CELL * 0.5 - BODY_PAD

## The men's grid over cells `lo` to `hi`, from the footprints of what stands
## there. Each cell was asked about its middle only, so a garden wall or a
## fence -- forty centimetres through, lying between two middles two metres
## apart -- was on neither, and the route went straight through it: the men
## walked into it and stood there. Now a cell is shut if any structure that
## would stop a man there, padded by his width, crosses the cross through its
## middle: the two lines along which a route leaves it.
func _mark_men(lo: Vector2i, hi: Vector2i) -> void:
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			_nav.set_point_solid(Vector2i(i, j), false)
	var w0: Vector2 = _corner + Vector2(lo) * CELL - Vector2.ONE * (BODY_PAD + CELL)
	var w1: Vector2 = _corner + Vector2(hi + Vector2i.ONE) * CELL + Vector2.ONE * (BODY_PAD + CELL)
	for oid in Obstacles.ids_in(w0, w1):
		_stamp(oid, lo, hi)
	# Hugging a wall is how a man gets hung up on its corner, so the open
	# middle of an alley is cheaper to walk than its edges.
	var free := 0
	for j in range(maxi(lo.y - 1, 0), mini(hi.y + 1, _n - 1) + 1):
		for i in range(maxi(lo.x - 1, 0), mini(hi.x + 1, _n - 1) + 1):
			var id := Vector2i(i, j)
			if _nav.is_point_solid(id):
				continue
			var tight := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = id + d
				if _nav.is_in_boundsv(q) and _nav.is_point_solid(q):
					tight = true
			_nav.set_point_weight_scale(id, 1.6 if tight else 1.0)
	for j in _n:
		for i in _n:
			if not _nav.is_point_solid(Vector2i(i, j)):
				free += 1
	stats["free_cells"] = free

## One structure onto the men's grid, within cells `lo` to `hi`.
func _stamp(oid: int, lo: Vector2i, hi: Vector2i) -> void:
	var half: Vector2 = Obstacles.half_of(oid)
	var at: Vector3 = Obstacles.centre_of(oid)
	var top: float = Obstacles.top_of(oid)
	var yaw: float = Obstacles.yaw_of(oid)
	var c: float = cos(yaw)
	var s: float = -sin(yaw)                 # as `Obstacles` keeps it
	var ex: float = half.x + BODY_PAD
	var ez: float = half.y + BODY_PAD
	var reach: float = sqrt(half.x * half.x + half.y * half.y) + BODY_PAD + ARM
	var a: Vector2i = _cell_of(Vector2(at.x - reach, at.z - reach), CELL, _n)
	var b: Vector2i = _cell_of(Vector2(at.x + reach, at.z + reach), CELL, _n)
	for j in range(maxi(a.y, lo.y), mini(b.y, hi.y) + 1):
		for i in range(maxi(a.x, lo.x), mini(b.x, hi.x) + 1):
			var id := Vector2i(i, j)
			if _nav.is_point_solid(id):
				continue
			var x: float = _corner.x + (i + 0.5) * CELL
			var z: float = _corner.y + (j + 0.5) * CELL
			# what stops a man standing here, as `Obstacles.blocks` has it:
			# not a deck he walks under, not a kerb under his boots
			var dy: float = _ground(x, z) - at.y
			if dy < -1.85 or dy >= top - at.y - 0.02:
				continue
			var dx: float = x - at.x
			var dz: float = z - at.z
			var lx: float = dx * c + dz * s
			var lz: float = -dx * s + dz * c
			# the cross: world x is (c, -s) in the box's frame, world z (s, c)
			if _seg_in_box(lx, lz, c, -s, ex, ez) or _seg_in_box(lx, lz, s, c, ex, ez):
				_nav.set_point_solid(id, true)

## Does the segment from p - d ARM to p + d ARM touch the box of half size
## (ex, ez) about the origin?
static func _seg_in_box(px: float, pz: float, dx: float, dz: float, ex: float, ez: float) -> bool:
	var t0 := -ARM
	var t1 := ARM
	for k in 2:
		var p: float = px if k == 0 else pz
		var d: float = dx if k == 0 else dz
		var e: float = ex if k == 0 else ez
		if absf(d) < 1e-6:
			if absf(p) > e:
				return false
			continue
		var ta: float = (-e - p) / d
		var tb: float = (e - p) / d
		if ta > tb:
			var sw := ta
			ta = tb
			tb = sw
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true

## The vehicles' grid over cells `lo` to `hi`. Its cells are wider than the
## pad it asks with is short of, so a wall between two middles is caught.
func _mark_vehicles(lo: Vector2i, hi: Vector2i) -> void:
	var open_v := 0
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var vx: float = _corner.x + (i + 0.5) * VCELL
			var vz: float = _corner.y + (j + 0.5) * VCELL
			var hit_id: int = Obstacles.hit(Vector3(vx, _ground(vx, vz) + 1.5, vz), 4.2)
			var soft: bool = hit_id >= 0 and is_instance_valid(dressing) \
				and dressing._breaks.has(hit_id)
			var vid := Vector2i(i, j)
			_vnav.set_point_solid(vid, hit_id >= 0 and not soft)
			# passable, but the open road is preferred to somebody's wall
			_vnav.set_point_weight_scale(vid, 2.5 if soft else 1.0)
	for j in _vn:
		for i in _vn:
			if not _vnav.is_point_solid(Vector2i(i, j)):
				open_v += 1
	stats["vehicle_cells"] = open_v

## The survey as a picture: what is solid and what is street. This is the
## map in the corner of the screen.
func _paint_map() -> void:
	var img := Image.create(_n, _n, false, Image.FORMAT_RGBA8)
	for j in _n:
		for i in _n:
			img.set_pixel(i, j, Color(0.62, 0.68, 0.74, 0.78)
				if _nav.is_point_solid(Vector2i(i, j)) else Color(0.03, 0.06, 0.09, 0.62))
	if map_tex == null:
		map_tex = ImageTexture.create_from_image(img)
	else:
		map_tex.update(img)

## A point in the world as a place on the map, 0 to 1 each way, north at the top.
func map_uv(p: Vector3) -> Vector2:
	return Vector2((p.x - _corner.x) / (HALF * 2.0), (p.z - _corner.y) / (HALF * 2.0))

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - _corner.x) / CELL)), 0, _n - 1),
		clampi(int(floor((p.z - _corner.y) / CELL)), 0, _n - 1))

func _cell_pos(id: Vector2i) -> Vector3:
	var x: float = _corner.x + (id.x + 0.5) * CELL
	var z: float = _corner.y + (id.y + 0.5) * CELL
	return Vector3(x, _ground(x, z), z)

## The nearest grid point a man can stand on.
func _free_cell(id: Vector2i) -> Vector2i:
	if not _nav.is_point_solid(id):
		return id
	for r in range(1, 9):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := Vector2i(id.x + di, id.y + dj)
				if _nav.is_in_boundsv(q) and not _nav.is_point_solid(q):
					return q
	return Vector2i(-1, -1)

func _free_near(p: Vector3) -> Vector3:
	var id := _free_cell(_cell(p))
	return Vector3.INF if id.x < 0 else _cell_pos(id)

## The same, for the men: the nearest place a man can stand.
func free_near(p: Vector3) -> Vector3:
	return _free_near(p)

## Which connected piece of open ground each cell is in, -1 for solid. A route
## is asked for with a partial path allowed, so that a man sent somewhere he
## cannot get to walks as near as he can -- and A* finds that out by visiting
## every cell he *can* reach first. A courtyard with no way in, the gap behind
## a row of houses: a goal in one cost a search of the whole town, ten
## milliseconds and more in a single frame. Labelled once here, the goal is
## moved to the nearest place he can reach before anything is searched.
##
## Four neighbours are enough: the grids only cut a corner when both cells
## beside it are open, so a diagonal never joins two pieces that a pair of
## straight steps would not.
var _comp := PackedInt32Array()
var _vcomp := PackedInt32Array()

static func _components(grid: AStarGrid2D, n: int) -> PackedInt32Array:
	var comp := PackedInt32Array()
	comp.resize(n * n)
	comp.fill(-1)
	# solid or not, read once: the fill below looks at every cell four times
	var open := PackedByteArray()
	open.resize(n * n)
	for j in n:
		for i in n:
			open[j * n + i] = 0 if grid.is_point_solid(Vector2i(i, j)) else 1
	var label := 0
	var stack := PackedInt32Array()
	for start in n * n:
		if comp[start] >= 0 or open[start] == 0:
			continue
		comp[start] = label
		stack.append(start)
		while not stack.is_empty():
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var ci: int = c % n
			# the four neighbours, those that are in the grid
			if ci + 1 < n and comp[c + 1] < 0 and open[c + 1] == 1:
				comp[c + 1] = label
				stack.append(c + 1)
			if ci > 0 and comp[c - 1] < 0 and open[c - 1] == 1:
				comp[c - 1] = label
				stack.append(c - 1)
			if c + n < n * n and comp[c + n] < 0 and open[c + n] == 1:
				comp[c + n] = label
				stack.append(c + n)
			if c - n >= 0 and comp[c - n] < 0 and open[c - n] == 1:
				comp[c - n] = label
				stack.append(c - n)
		label += 1
	return comp

## The nearest cell to `id` in piece `want`, a ring at a time, or (-1, -1).
static func _in_piece(comp: PackedInt32Array, n: int, id: Vector2i, want: int,
		rings: int) -> Vector2i:
	for r in range(0, rings + 1):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var qi: int = id.x + di
				var qj: int = id.y + dj
				if qi >= 0 and qj >= 0 and qi < n and qj < n and comp[qj * n + qi] == want:
					return Vector2i(qi, qj)
	return Vector2i(-1, -1)

## A way from one place to another round everything solid, as points to walk.
func path(from: Vector3, to: Vector3) -> PackedVector2Array:
	var a := _free_cell(_cell(from))
	var b := _free_cell(_cell(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
	if _comp.size() == _n * _n:
		var mine: int = _comp[a.y * _n + a.x]
		if _comp[b.y * _n + b.x] != mine:
			# Somewhere he cannot get to from here: the nearest place he can,
			# forty metres round it. Further than that and the old partial
			# search is the answer, as it always was.
			var near := _in_piece(_comp, _n, b, mine, 20)
			if near.x >= 0:
				b = near
	var pts: PackedVector2Array = _nav.get_point_path(a, b, true)
	# the first point is the cell he is already standing in
	if pts.size() > 1:
		pts.remove_at(0)
	return pts

## Somewhere close that the threat cannot see into, even kneeling.
func find_cover(from: Vector3, threat: Vector3) -> Vector3:
	var home := _cell(from)
	var best := Vector3.INF
	var best_d := 1e9
	for r in range(1, 8):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if maxi(absi(di), absi(dj)) != r:
					continue
				var q := Vector2i(home.x + di, home.y + dj)
				if not _nav.is_in_boundsv(q) or _nav.is_point_solid(q):
					continue
				var p := _cell_pos(q)
				if p.distance_to(threat) < 7.0:
					continue
				if Firearm.can_see(p + Vector3(0, 1.1, 0), threat):
					continue
				var d: float = p.distance_to(from) + p.distance_to(threat) * 0.05
				if d < best_d:
					best_d = d
					best = p
		if best != Vector3.INF and r >= 2:
			break
	return best

# -------------------------------------------------------------------- the men
func enemies_of(team: int) -> Array:
	return _teams[1 - team]

## What a man of `team` can see and shoot at: the other side's men, and
## anything of theirs put down that fights -- a sentry gun. Kept apart from
## the men's own list, which is what is counted and scored.
func targets_of(team: int) -> Array:
	var out: Array = (_teams[1 - team] as Array).duplicate()
	for n in get_tree().get_nodes_in_group("sentries"):
		if is_instance_valid(n) and int(n.get("team")) != team and n.is_alive():
			out.append(n)
	return out

func friends_of(team: int) -> Array:
	return _teams[team]

func set_player(w: Walker) -> void:
	for t in _teams:
		var keep: Array = []
		for n in _teams[t]:
			if is_instance_valid(n) and not (n is Walker):
				keep.append(n)
		_teams[t] = keep
	player = w
	if is_instance_valid(w):
		w.side = 0
		w.arena = self
		w.regen = true
		if plain:
			w.set_loadout(String(loadout[0]), String(loadout[1]), quiet)
		else:
			var all: Array = kit_classes()
			w.apply_class(all[clampi(class_pick, 0, all.size() - 1)])
		(_teams[0] as Array).append(w)

## Where a side comes back in. Along its own street, at whichever point the
## other side is furthest from and cannot see.
func spawn_point(team: int, slot := -1) -> Vector3:
	# on the range, back on the firing line
	if range_mode and world != null:
		var fr: Variant = world.get("firing_range")
		if fr != null and is_instance_valid(fr):
			return (fr as FiringRange).origin - (fr as FiringRange).dir * 1.5
	# which end of town is the absolute side's, not this machine's "us": a
	# RED player's side 0 comes in from RED's end
	var z: float = centre.y + (118.0 if NetLink.local_team(team) == 0 else -118.0)
	var best := Vector3.INF
	var best_score := -1e9
	for k in 9:
		var x: float = centre.x + (k - 4) * 13.0
		var p: Vector3 = _free_near(Vector3(x, 0, z + _rng.randf_range(-6.0, 6.0)))
		if p == Vector3.INF:
			continue
		var score: float = _rng.randf_range(0.0, 12.0)
		if slot >= 0:
			score -= absf(float(k - 4) - (float(slot) - float(side_size(team)) * 0.5) * 1.5) * 3.0
		for e in enemies_of(team):
			if not is_instance_valid(e) or not e.is_alive():
				continue
			var d: float = p.distance_to((e as Node3D).global_position)
			score += minf(d, 80.0) * 0.4
			if d < 70.0 and Firearm.can_see(p + Vector3(0, 1.6, 0),
					(e as Node3D).global_position + Vector3(0, 1.5, 0)):
				score -= 80.0
		for f in friends_of(team):
			if is_instance_valid(f) and p.distance_to((f as Node3D).global_position) < 2.0:
				score -= 30.0
		if score > best_score:
			best_score = score
			best = p
	return best if best != Vector3.INF else Vector3(centre.x, _ground(centre.x, z), z)

func _spawn(team: int, slot: int) -> void:
	var s := Soldier.new()
	s.team = team
	s.kit = KITS[(slot + team * 2) % KITS.size()]
	# the other side carries the other side's rifle
	if team == 1 and s.kit == "carbine":
		s.kit = "ak"
	s.callsign = ("Viper %d" if team == 0 else "Hostile %d") % (slot + 1)
	s.name = s.callsign
	s.set_meta("slot", slot)
	s.arena = self
	s.skill = _rng.randf_range(0.8, 1.2)
	# what kills the player is a little weaker than what the player kills with:
	# he is one man being shot at by six
	s.dmg_scale = 0.62 if team == 1 else 1.0
	# One man in each squad carries the rockets when there is armour about,
	# and one the missile when there is anything overhead.
	if armour and slot == 2:
		s.launcher = "law"
		s.callsign += " (AT)"
	elif slot == 4 or (slot == 1 and side_size(team) < 5):
		# always one, air or no air: the other side can put a drone up, and a
		# drone is a thing a man with a missile can do something about
		s.launcher = "stinger"
		s.rounds_heavy = 2
		s.callsign += " (AA)"
	s.yaw = 0.0 if team == 0 else PI
	add_child(s)
	s.global_position = spawn_point(team, slot)
	s.died.connect(_on_died)
	(_teams[team] as Array).append(s)
	soldiers.append(s)

func _on_died(who: Soldier, killer: Node, head: bool) -> void:
	(_teams[who.team] as Array).erase(who)
	soldiers.erase(who)
	_feed(killer, who.callsign, who.team, who.last_cause, head)
	var by_player: bool = killer != null and is_instance_valid(killer) \
		and (killer == player or (not is_instance_valid(player) and killer == streaks.caller()))
	# A hit a player on another machine landed: his kill, for his streaks.
	if Sim.net != null and Sim.net.active and Sim.net.is_host and int(Sim.net.units.crediting) > 1:
		Sim.net.units.credit_kill(int(Sim.net.units.crediting), who.callsign, head)
	elif by_player:
		credit_kill(who.callsign, head)
	# the rest is the kill feed's: see `_feed`
	if is_instance_valid(mode) and mode.running:
		mode.register_kill(who.team)
	_queue.append([RESPAWN, who.team, int(who.get_meta("slot", 0))])

## A man dropped by the player on this machine: the count, the streak and what
## the streak has earned. Called for a kill made here, and in a session for one
## the host says this machine's player made.
func credit_kill(victim: String, head: bool) -> void:
	kills += 1
	streaks.earn(head)
	if head:
		headshots += 1
	Sim.score += 150 if head else 100
	Sim.report("you dropped %s%s" % [victim, " — headshot" if head else ""], Sim.Ev.GOOD)


## A picture of one of the host's men, in a session: counted on his side so
## everything here that looks for the other side's men finds him.
func adopt_ghost(s: Soldier) -> void:
	(_teams[s.team] as Array).append(s)
	soldiers.append(s)

func forget_ghost(s: Soldier) -> void:
	(_teams[s.team] as Array).erase(s)
	soldiers.erase(s)

## Host: a player on another machine was killed in the fight.
func remote_down(vside := 0) -> void:
	if is_instance_valid(mode) and mode.running:
		mode.register_kill(vside)

## Host: the other players on foot are men of the side for the AI to fight
## beside and against. See `NetMan`.
func _sync_net_men() -> void:
	for n in get_tree().get_nodes_in_group("net_men"):
		var t: int = int(n.team)
		# changed sides: out of the other list
		(_teams[1 - t] as Array).erase(n)
		if not (_teams[t] as Array).has(n):
			(_teams[t] as Array).append(n)
			n.tree_exiting.connect(func() -> void: (_teams[t] as Array).erase(n),
				CONNECT_ONE_SHOT)

## One line of the kill feed. A man in a vehicle is credited as the vehicle's
## driver, and the player as YOU.
func _feed(killer: Node, victim: String, victim_team: int, weapon: String,
		head := false) -> void:
	# Either of them may be gone by now -- the man who fired the round dead
	# before it landed, the player's walker freed when he climbed into
	# something -- and a freed object handed to a typed parameter is an error
	# before the function can look at it.
	var me: Node = player if is_instance_valid(player) else null
	var by: Node = killer if is_instance_valid(killer) else null
	if by is Tank and is_instance_valid(world) and world.get("tank") == by:
		by = me
	var kname: String = KillFeed.name_of(by, me)
	var kteam: int = KillFeed.team_of(by)
	if by != null and by == me:
		kteam = 0
	if kname == victim:
		kname = ""
	Sim.kill(kname, kteam, victim, victim_team, weapon, head)
	if Sim.net != null and Sim.net.active and Sim.net.is_host:
		Sim.net.broadcast_feed(kname if kname != "YOU" else Sim.net.name_of(1), kteam,
			victim, victim_team, weapon, head)

## The player went down.
func feed_player(by: Node, weapon: String) -> void:
	_feed(by, "YOU", 0, weapon)

## A vehicle was knocked out. It counts the same as a man.
func vehicle_down(team: int, what: String, who: Node = null) -> void:
	var by: Node = who.get("last_by") if is_instance_valid(who) and "last_by" in who else null
	var cause: String = String(who.get("last_cause")) \
		if is_instance_valid(who) and "last_cause" in who else "explosion"
	_feed(by, what, team, cause if cause != "" else "explosion")
	if team == 1 and by != null and is_instance_valid(by) and by == streaks.caller():
		streaks.points += 300
		credit_kill(what, false)
	Sim.report("%s %s knocked out" % ["our" if team == 0 else "their", what],
		Sim.Ev.BAD if team == 0 else Sim.Ev.GOOD)
	if is_instance_valid(mode) and mode.running:
		mode.register_kill(team)

## Anything on tracks or wheels, moving, kills whoever it drives over: the
## other side's men, and you if you are standing in front of it. Not its own
## side -- the AI does not look where it is going well enough for that to be
## anything but a way of losing your own squad.
func _under_wheels() -> void:
	if not armour:
		return
	for v in get_tree().get_nodes_in_group("vehicles"):
		var t := v as Tank
		if t == null or not t.alive or t.linear_velocity.length() < 2.2:
			continue
		var reach: float = t.hull_radius() + 0.3
		var driver: Node = player if (is_instance_valid(world) and world.get("tank") == t) else null
		for s in enemies_of(t.team).duplicate():
			if not is_instance_valid(s) or not s.is_alive():
				continue
			var rel: Vector3 = (s as Node3D).global_position - t.global_position
			if absf(rel.y) > 2.5 or Vector2(rel.x, rel.z).length() > reach:
				continue
			# in front of the way it is going, not merely beside it
			if rel.dot(t.linear_velocity) < 0.0:
				continue
			KillFeed.cause = "roadkill"
			if s is Soldier and (s as Soldier).ghost:
				# the host decides, and credits the kill back
				s.take_hit(600.0, driver)
			elif s is Soldier:
				s.take_hit(600.0, driver)
				if world.get("tank") == t:
					# the man who would be credited is inside the vehicle
					run_over += 1
					kills += 1
					streaks.streak += 1
					Sim.report("you ran over %s" % (s as Soldier).callsign, Sim.Ev.GOOD)
					Sim.score += 100
			else:
				s.take_hit(600.0, t)
			KillFeed.cause = ""

var run_over := 0

func _vcell(p: Vector3) -> Vector2i:
	var id := Vector2i(clampi(int(floor((p.x - _corner.x) / VCELL)), 0, _vn - 1),
		clampi(int(floor((p.z - _corner.y) / VCELL)), 0, _vn - 1))
	if not _vnav.is_point_solid(id):
		return id
	for r in range(1, 6):
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				var q := Vector2i(id.x + di, id.y + dj)
				if _vnav.is_in_boundsv(q) and not _vnav.is_point_solid(q):
					return q
	return id

## Take the AI's vehicles round by the streets. Left to itself a tank points
## at where it was told to go and drives, which in a town is into the first
## building in the way, where it stays. So it is given the next corner
## instead, a route at a time, and somewhere new to go when it arrives.
func _drive_armour(delta: float) -> void:
	if not armour:
		return
	_drive_t -= delta
	if _drive_t > 0.0:
		return
	_drive_t = 0.35
	# The vehicles, gathered once. This walked everything on the radar picture
	# to find the tanks, and then walked it again inside the loop for every
	# tank it found to see whether another one was in the way.
	var hulls: Array[Tank] = []
	for v in get_tree().get_nodes_in_group("vehicles"):
		var hv := v as Tank
		if hv != null and is_instance_valid(hv) and hv.alive:
			hulls.append(hv)
	var live := {}
	for t in hulls:
		if not t.ai or t.occupied:
			continue
		var key: int = t.get_instance_id()
		live[key] = true
		var goal: Vector3 = t.get_meta("cqb_goal", Vector3.INF)
		var here: Vector3 = t.global_position
		if goal == Vector3.INF or Vector2(here.x - goal.x, here.z - goal.z).length() < 14.0:
			# arrived, or never sent: another street corner, anywhere in town
			var pick: Vector3 = _spots[_rng.randi() % _spots.size()]
			if _rng.randf() < 0.5:
				pick = Vector3(centre.x + [-128.0, 0.0, 128.0][_rng.randi() % 3], 0.0,
					centre.y + _rng.randf_range(-118.0, 118.0))
			goal = _vcell_pos(_vcell(pick))
			t.set_meta("cqb_goal", goal)
		# Somebody else's hull in the way, whoever's it is. Nothing in a
		# driver's head says another vehicle is there, so two of them sent
		# down the same street drove into each other and stayed. The one
		# that finds the other in front of it stops and lets it by; if it is
		# still there after a few seconds, it goes somewhere else.
		var ahead: Vector3 = -t.global_transform.basis.z
		var blocked := false
		for ot in hulls:
			if ot == t:
				continue
			var gap: Vector3 = ot.global_position - here
			gap.y = 0.0
			var dist: float = gap.length()
			if dist < 15.0 and gap.dot(ahead) > dist * 0.45:
				# two nose to nose: the one that was made later gives way
				if (-ot.global_transform.basis.z).dot(ahead) < -0.3 \
						and ot.ai and not ot.occupied \
						and t.get_instance_id() < ot.get_instance_id():
					continue
				blocked = true
		if blocked:
			var waited: float = float(t.get_meta("cqb_wait", 0.0)) + 0.35
			t.set_meta("cqb_wait", waited)
			t.ai_goal = here                     # which is "stop"
			if waited > 4.0:
				t.set_meta("cqb_wait", 0.0)
				t.set_meta("cqb_goal", Vector3.INF)
				_routes.erase(key)
			continue
		t.set_meta("cqb_wait", 0.0)
		# Not getting anywhere -- nosed into a wreck, a wall the grid did not
		# know about, a corner too tight to turn in: somewhere else.
		var prog: Array = t.get_meta("cqb_prog", [here, 0.0])
		# Stopped to shoot is not stuck: the crew halts while it has a
		# target on the ground (see `Tank._ai_drive`), and the route it was
		# on was thrown away after every fight that lasted eight seconds.
		var engaged: Variant = t.get("_ai_target")
		if not (is_instance_valid(engaged) and not (engaged is Aircraft)):
			prog[1] = float(prog[1]) + 0.35
		if (prog[0] as Vector3).distance_to(here) > 5.0:
			prog = [here, 0.0]
		t.set_meta("cqb_prog", prog)
		if float(prog[1]) > 8.0:
			t.set_meta("cqb_prog", [here, 0.0])
			t.set_meta("cqb_goal", Vector3.INF)
			_routes.erase(key)
			continue
		var route: PackedVector2Array = _route_for(t, key, here, goal)
		if route.size() < 2:
			t.set_meta("cqb_goal", Vector3.INF)
			_routes.erase(key)
			continue
		# aim a couple of cells along it, so corners are cut no finer than
		# the street allows
		var at: int = int((_routes[key] as Array)[2])
		if at >= route.size() - 2:
			# The end of the route and not the goal: a route that stops
			# short is as near as it gets. It sat there pointing at the
			# goal for good.
			t.set_meta("cqb_goal", Vector3.INF)
			_routes.erase(key)
			continue
		var wp: Vector2 = route[mini(at + 2, route.size() - 1)]
		var dir := Vector3(wp.x - here.x, 0.0, wp.y - here.z)
		if dir.length() < 0.5:
			continue
		# The driver stops short of wherever he is told to go by a long way --
		# that is right for a sector and no use for a street corner -- so the
		# point he is given is well beyond the one that is meant.
		t.ai_goal = here + dir.normalized() * 400.0
	# routes of what has been knocked out or taken over since
	if _routes.size() > live.size():
		for k in _routes.keys():
			if not live.has(k):
				_routes.erase(k)

## Each driver's route, kept: [the cell it leads to, the route, how far along it
## he has got, how long he has had it].
##
## A route through the town was searched for afresh for every vehicle every
## third of a second -- from wherever it had got to, to the same corner as last
## time, giving the same streets less the one cell it had covered. The town
## does not change under it. So the route is planned once, the driver's place
## on it is found by looking a few cells on from where he last was, and it is
## planned again only when he is sent somewhere else, has been pushed off it,
## or has had it long enough that it is worth a second look.
var _routes := {}
const ROUTE_KEEP := 6.0

func _route_for(t: Tank, key: int, here: Vector3, goal: Vector3) -> PackedVector2Array:
	var va := _vcell(here)
	var vb := _vcell(goal)
	var flat := Vector2(here.x, here.z)
	var kept: Array = _routes.get(key, [])
	if not kept.is_empty() and kept[0] == vb:
		var route: PackedVector2Array = kept[1]
		var at: int = kept[2]
		# where he is on it now: the nearest of the next few points
		var best: int = at
		var bd: float = flat.distance_squared_to(route[at])
		for k in range(at + 1, mini(at + 5, route.size())):
			var dk: float = flat.distance_squared_to(route[k])
			if dk < bd:
				bd = dk
				best = k
		kept[2] = best
		kept[3] = float(kept[3]) + 0.35
		if bd < (VCELL * 2.5) * (VCELL * 2.5) and float(kept[3]) < ROUTE_KEEP:
			return route
	if _vcomp.size() == _vn * _vn and _vcomp[vb.y * _vn + vb.x] != _vcomp[va.y * _vn + va.x]:
		# a street it cannot reach from this one: the nearest it can, and
		# that is where it is going now
		var vnear := _in_piece(_vcomp, _vn, vb, _vcomp[va.y * _vn + va.x], 12)
		if vnear.x >= 0:
			vb = vnear
			t.set_meta("cqb_goal", _vcell_pos(vb))
	var fresh: PackedVector2Array = _vnav.get_point_path(va, vb, true)
	_routes[key] = [vb, fresh, 0, 0.0]
	return fresh

func _vcell_pos(id: Vector2i) -> Vector3:
	var x: float = _corner.x + (id.x + 0.5) * VCELL
	var z: float = _corner.y + (id.y + 0.5) * VCELL
	return Vector3(x, _ground(x, z), z)

## The player went down. The world brings him back; this keeps the score.
func player_down() -> void:
	deaths += 1
	streaks.streak = 0
	(_teams[0] as Array).erase(player)
	if is_instance_valid(mode) and mode.running:
		mode.register_kill(0)

func _process(delta: float) -> void:
	if is_instance_valid(mode) and not mode.running and not over:
		over = true
		for s in soldiers:
			if is_instance_valid(s):
				(s as Soldier).state = Soldier.ROAM
				(s as Soldier).set_process(false)
	if over:
		return
	var _pc := Sim.prof_at()
	_refresh_routes(delta)
	streaks.support(delta)
	_under_wheels()
	_drive_armour(delta)
	Sim.prof_end(&"cqb.match", _pc)
	if Sim.net != null and Sim.net.active and Sim.net.is_host:
		_sync_net_men()
	for q in _queue:
		q[0] = float(q[0]) - delta
	while not _queue.is_empty() and float(_queue[0][0]) <= 0.0:
		var q2: Array = _queue.pop_front()
		_spawn(int(q2[1]), int(q2[2]))
	for t in _contacts:
		var keep: Array = []
		for c in _contacts[t]:
			c[1] = float(c[1]) + delta
			if float(c[1]) < 12.0:
				keep.append(c)
		_contacts[t] = keep

# ------------------------------------------------------------ shared knowledge
## Somebody on `team` can see an enemy there. The rest of the side hears of it.
func contact(team: int, at: Vector3) -> void:
	var list: Array = _contacts[team]
	for c in list:
		if (c[0] as Vector3).distance_to(at) < 10.0:
			c[0] = at
			c[1] = 0.0
			return
	list.append([at, 0.0])
	if list.size() > 6:
		list.pop_front()
	# Something new. The men near it turn to it, and a side that was sweeping
	# for want of anything better stops and works out what to do about it.
	for m in _teams[team]:
		if is_instance_valid(m) and m is Soldier \
				and (m as Soldier).global_position.distance_to(at) < 55.0:
			(m as Soldier).hear(at)
	if String(plan[team]) == "sweep":
		_plan_t[team] = minf(float(_plan_t[team]), 0.6)

## A shot, or a man running: everyone on the other side within earshot turns.
func heard(at: Vector3, by_team: int, radius := 75.0) -> void:
	for s in _teams[1 - by_team]:
		if is_instance_valid(s) and s is Soldier \
				and (s as Soldier).global_position.distance_to(at) < radius:
			(s as Soldier).hear(at)

## Where a man with nothing to shoot at should go: wherever his fire team has
## been sent, and near the others in it rather than on top of them.
func objective_for(s: Soldier) -> Vector3:
	var ft: int = fireteam_of(s)
	# the fire team you are in stays with you, which is what makes it yours
	if s.team == 0 and ft == 0 and is_instance_valid(player) and player.is_alive() \
			and not away and String(plan[0]) != "hold":
		var back := Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
		var near: Vector3 = _free_near(player.global_position + back)
		if near != Vector3.INF:
			return near
	var goal: Vector3 = _team_goal(s.team, ft)
	var spot: Vector3 = _free_near(goal
		+ Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6)))
	return spot if spot != Vector3.INF else goal

# ------------------------------------------------------------------ support
## Take the player out of the fight, or put him back. He is still the one the
## kills belong to; he is just not standing in the street to be shot.
func set_away(on: bool) -> void:
	away = on
	(_teams[0] as Array).erase(player)
	if not on and is_instance_valid(player):
		(_teams[0] as Array).append(player)


# ----------------------------------------------------------------- team plans
## What each side is doing as a side. Every man used to choose for himself: a
## place somebody had seen the enemy, or a street picked at random. Twelve men
## doing that are twelve men, not a team -- they arrive one at a time and are
## shot one at a time. A side now has a plan, looked at again every quarter of
## a minute, and is split into fire teams of three that move together:
##
##   assault  there is a contact. One fire team goes straight at it and fixes
##            it; the others go round, one each side, and arrive on its flanks.
##   sweep    nobody has seen anything. The fire teams go forward in line
##            abreast, a street apart, so nothing is walked past.
##   hold     outnumbered three to two or worse. Back to their own end, each
##            fire team on a corner of it, until the numbers come back.
const FIRETEAM := 3
const PLAN_EVERY := 14.0
var plan := {0: "sweep", 1: "sweep"}
var _plan_t := {0: 1.0, 1: 2.5}
var _plan_at := {0: Vector3.INF, 1: Vector3.INF}
## Where each fire team is going: team -> {fire team -> [where, seconds left]}.
var _ft_goal := {0: {}, 1: {}}
const PLAN_SAY := {
	"assault": "squad: contact — one team fixing it, the others going round",
	"sweep": "squad: nothing seen — sweeping forward in line",
	"hold": "squad: outnumbered — holding our end until they are back up",
}

func fireteam_of(s: Soldier) -> int:
	return floori(float(int(s.get_meta("slot", 0))) / float(FIRETEAM))

func _alive_on(team: int) -> int:
	var n := 0
	for m in _teams[team]:
		if is_instance_valid(m) and m.is_alive():
			n += 1
	return n

func _plan_tick(delta: float) -> void:
	for t in [0, 1]:
		for ft in (_ft_goal[t] as Dictionary):
			_ft_goal[t][ft][1] = float(_ft_goal[t][ft][1]) - delta
		_plan_t[t] = float(_plan_t[t]) - delta
		if float(_plan_t[t]) <= 0.0:
			_plan_t[t] = PLAN_EVERY + _rng.randf_range(-3.0, 3.0)
			_replan(t)

func _replan(t: int) -> void:
	var mine: int = _alive_on(t)
	var theirs: int = _alive_on(1 - t)
	# the freshest thing anyone on the side has seen
	var focus := Vector3.INF
	var age := 1e9
	for c in _contacts[t]:
		if float(c[1]) < age:
			age = float(c[1])
			focus = c[0]
	var was: String = plan[t]
	var now := "sweep"
	if mine * 3 <= theirs * 2 and theirs >= 3:
		now = "hold"
	elif focus != Vector3.INF:
		now = "assault"
	plan[t] = now
	_plan_at[t] = focus
	_ft_goal[t] = {}
	if t == 0 and now != was:
		Sim.report(String(PLAN_SAY[now]), Sim.Ev.INFO)
	# Whoever is standing about with nothing to do takes the new orders now
	# rather than when he next gets round to asking.
	for m in _teams[t]:
		if is_instance_valid(m) and m is Soldier and (m as Soldier).state == Soldier.ROAM:
			(m as Soldier).new_orders()

## Where a fire team is going under the side's plan. Worked out once and kept
## for a few seconds, so the three of them are given the same place.
func _team_goal(t: int, ft: int) -> Vector3:
	var have: Dictionary = _ft_goal[t]
	if have.has(ft) and float(have[ft][1]) > 0.0:
		return have[ft][0]
	# towards the other side's end is -z for us and +z for them
	var fwd: float = -1.0 if t == 0 else 1.0
	var teams_n: int = maxi(ceili(float(side_size(t)) / float(FIRETEAM)), 1)
	var lane: float = (float(ft) - float(teams_n - 1) * 0.5) * minf(52.0, 180.0 / float(teams_n))
	var at := Vector3.INF
	match String(plan[t]):
		"assault":
			var focus: Vector3 = _plan_at[t]
			if focus != Vector3.INF:
				# the line from our end to the contact, and the two sides of it
				var from := Vector3(centre.x, 0.0, centre.y - fwd * 110.0)
				var axis := Vector3(focus.x - from.x, 0.0, focus.z - from.z)
				axis = axis.normalized() if axis.length() > 1.0 else Vector3(0, 0, fwd)
				var side := Vector3(-axis.z, 0.0, axis.x)
				match ft % 3:
					0:
						at = focus - axis * 22.0          # short of it: the base of fire
					1:
						at = focus + side * 30.0 + axis * 6.0
					_:
						at = focus - side * 30.0 + axis * 6.0
		"hold":
			at = Vector3(centre.x + lane, 0.0,
				centre.y - fwd * _rng.randf_range(45.0, 85.0))
	if at == Vector3.INF:
		# the sweep, and whatever could not be placed: forward in its own lane
		at = Vector3(centre.x + lane, 0.0, centre.y + fwd * _rng.randf_range(10.0, 100.0))
	at.x = clampf(at.x, centre.x - HALF + 8.0, centre.x + HALF - 8.0)
	at.z = clampf(at.z, centre.y - HALF + 8.0, centre.y + HALF - 8.0)
	var p: Vector3 = _free_near(at)
	if p == Vector3.INF:
		p = _spots[_rng.randi() % _spots.size()]
	have[ft] = [p, _rng.randf_range(7.0, 11.0)]
	return p


func hud_state() -> Dictionary:
	# who shows on the map: your own side always, theirs when a UAV is up or
	# when they have just given themselves away by firing
	var dots: Array = []
	# and the same in metres, for a map that follows him rather than one fixed
	# to the arena
	var dots_w: Array = []
	for s in soldiers:
		if not is_instance_valid(s):
			continue
		var sd := s as Soldier
		var at := Vector2(sd.global_position.x, sd.global_position.z)
		if sd.team == 0:
			dots.append([map_uv(sd.global_position), 0])
			dots_w.append([at, 0])
		elif streaks.uav_t > 0.0 or sd.loud > 0.0:
			dots.append([map_uv(sd.global_position), 1])
			dots_w.append([at, 1])
	return {"kills": kills, "deaths": deaths, "headshots": headshots,
		"blue": (_teams[0] as Array).size(), "red": (_teams[1] as Array).size(),
		"streak": streaks.streak, "bank": streaks.bank, "streaks": Killstreaks.chosen_streaks(), "uav": streaks.uav_t,
		"jammed": float(Killstreaks.jammed[0]),
		"emp": float(Killstreaks.emp_t[0]),
		"map": map_tex, "dots": dots, "dots_w": dots_w,
		"area": Rect2(_corner, Vector2(HALF * 2.0, HALF * 2.0)),
		"me_w": Vector2(player.global_position.x, player.global_position.z)
			if is_instance_valid(player) else centre,
		"me": map_uv(player.global_position) if is_instance_valid(player) else Vector2(0.5, 0.5),
		"yaw": player.yaw if is_instance_valid(player) else 0.0}
