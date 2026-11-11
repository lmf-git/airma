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

static func kit_classes() -> Array:
	if classes.is_empty():
		for c in Firearm.CLASSES:
			classes.append((c as Dictionary).duplicate())
	return classes

## Aircraft over the town as well.
var air := false

## Vehicles in the fight as well as men.
var armour := false
var world: Node = null
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
## Everything a run of kills without dying can earn. Up to four are carried,
## chosen on the deploy screen; they are spent with 4 to 7, cheapest first.
const STREAK_POOL := [
	{"id": "uav", "name": "UAV", "at": 3,
		"note": "Every hostile on your map for thirty seconds."},
	{"id": "mortar", "name": "MORTAR BARRAGE", "at": 4,
		"note": "Ten rounds walked over a spot you pick on the map."},
	{"id": "strike", "name": "AIRSTRIKE", "at": 5,
		"note": "A stick of seven along the line to your mark."},
	{"id": "jdam", "name": "PRECISION BOMB", "at": 6,
		"note": "One heavy bomb, exactly where you put it."},
	{"id": "gunship", "name": "AC-130 GUNNER", "at": 7,
		"note": "You on the guns of a gunship over the town."},
	{"id": "carpet", "name": "B-2 CARPET BOMB", "at": 8,
		"note": "Two points on the map set the line; a B-2 comes over and lays a carpet along it."},
	{"id": "missile", "name": "FIRE MISSION", "at": 9,
		"note": "A launcher out of town lays rounds on your mark."},
	{"id": "tacnuke", "name": "TACTICAL NUKE", "at": 20,
		"note": "A small warhead on a spot you pick. Nothing within eighty metres lives and nothing there is left standing — you included."},
	{"id": "stratnuke", "name": "STRATEGIC NUKE", "at": 30,
		"note": "The town, everything in it and the match. Twenty seconds' warning and nowhere to go."},
]
const MAX_STREAKS := 4
## What he carries into the next life, by id. The four the game always had,
## until he changes them.
static var streak_pick: Array = ["uav", "strike", "gunship", "missile"]

## The carried ones, cheapest first, each with the key that spends it.
static func chosen_streaks() -> Array:
	var out: Array = []
	for k in STREAK_POOL:
		if streak_pick.has(String(k["id"])):
			out.append((k as Dictionary).duplicate())
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	for i in out.size():
		out[i]["key"] = 4 + i
	return out

const UAV_TIME := 30.0
var streak := 0
var bank := {"uav": 0, "mortar": 0, "strike": 0, "jdam": 0, "gunship": 0, "carpet": 0,
	"missile": 0, "tacnuke": 0, "stratnuke": 0}
## Warheads on their way: [seconds left, where, lethal radius, strategic].
var _nukes: Array = []
const TAC_LETHAL := 80.0
const STRAT_LETHAL := 1500.0
## The drone a UAV streak puts up, while it is up.
var _uav: UavDrone = null
## The first end of a carpet's line, while the map waits for the second.
var _carpet_from := Vector3.INF
var uav_t := 0.0
var map_tex: ImageTexture = null
## The player is somewhere else for a while -- at a gun station overhead --
## and the man standing in the street is not there to be shot.
var away := false
var _bombs: Array = []            # [seconds until it lands, where, how big]
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
	for t in [0, 1]:
		for i in side_size(t):
			if t == 0 and i == 0:
				continue                    # that one is you
			_spawn(t, i)

func _exit_tree() -> void:
	Effects.credit = null
	Effects.spare_team = -1

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
	var free := 0
	for j in _n:
		for i in _n:
			var x: float = _corner.x + (i + 0.5) * CELL
			var z: float = _corner.y + (j + 0.5) * CELL
			var blocked: bool = Obstacles.blocks(Vector3(x, _ground(x, z) + 0.3, z), 0.5) >= 0
			if blocked:
				_nav.set_point_solid(Vector2i(i, j), true)
			else:
				free += 1
	# Hugging a wall is how a man gets hung up on its corner, so the open
	# middle of an alley is cheaper to walk than its edges.
	for j in _n:
		for i in _n:
			var id := Vector2i(i, j)
			if _nav.is_point_solid(id):
				continue
			var tight := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = id + d
				if _nav.is_in_boundsv(q) and _nav.is_point_solid(q):
					tight = true
			if tight:
				_nav.set_point_weight_scale(id, 1.6)
	stats["free_cells"] = free
	# And the same again for things too wide for an alley: a coarser grid
	# that only the streets and the squares are open on. Anything a tank
	# would simply drive through does not count as in its way.
	_vn = int(HALF * 2.0 / VCELL)
	_vnav.region = Rect2i(0, 0, _vn, _vn)
	_vnav.cell_size = Vector2(VCELL, VCELL)
	_vnav.offset = _corner + Vector2(VCELL, VCELL) * 0.5
	_vnav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_vnav.update()
	var open_v := 0
	for j in _vn:
		for i in _vn:
			var vx: float = _corner.x + (i + 0.5) * VCELL
			var vz: float = _corner.y + (j + 0.5) * VCELL
			var hit_id: int = Obstacles.hit(Vector3(vx, _ground(vx, vz) + 1.5, vz), 4.2)
			var soft: bool = hit_id >= 0 and is_instance_valid(dressing) \
				and dressing._breaks.has(hit_id)
			if hit_id >= 0 and not soft:
				_vnav.set_point_solid(Vector2i(i, j), true)
			else:
				open_v += 1
				if soft:
					# passable, but the open road is preferred to somebody's wall
					_vnav.set_point_weight_scale(Vector2i(i, j), 2.5)
	stats["vehicle_cells"] = open_v
	_comp = _components(_nav, _n)
	_vcomp = _components(_vnav, _vn)
	# The same survey, as a picture: what is solid and what is street. This
	# is the map in the corner of the screen.
	var img := Image.create(_n, _n, false, Image.FORMAT_RGBA8)
	for j in _n:
		for i in _n:
			img.set_pixel(i, j, Color(0.62, 0.68, 0.74, 0.78)
				if _nav.is_point_solid(Vector2i(i, j)) else Color(0.03, 0.06, 0.09, 0.62))
	map_tex = ImageTexture.create_from_image(img)

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
	var z: float = centre.y + (118.0 if team == 0 else -118.0)
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
	var by_player: bool = is_instance_valid(player) and killer == player
	if by_player:
		kills += 1
		streak += 1
		var carried: Array = chosen_streaks()
		var top := 1
		for k0 in carried:
			top = maxi(top, int(k0["at"]))
		for k in carried:
			# the ladder comes round again after the top rung of what he carries
			if (streak - 1) % top + 1 == int(k["at"]):
				bank[k["id"]] = int(bank[k["id"]]) + 1
				Sim.report("%d in a row — %s ready, press %d" % [streak, String(k["name"]),
					int(k["key"])], Sim.Ev.GOOD)
				Sfx.play_ui(world, "killmark", -4.0, 0.7)
		if head:
			headshots += 1
		Sim.score += 150 if head else 100
		Sim.report("you dropped %s%s" % [who.callsign, " — headshot" if head else ""], Sim.Ev.GOOD)
	elif who.team == 0:
		Sim.report("%s is down" % who.callsign, Sim.Ev.BAD)
	elif killer is Soldier:
		Sim.report("%s dropped %s" % [(killer as Soldier).callsign, who.callsign], Sim.Ev.INFO)
	if is_instance_valid(mode) and mode.running:
		mode.register_kill(who.team)
	_queue.append([RESPAWN, who.team, int(who.get_meta("slot", 0))])

## A vehicle was knocked out. It counts the same as a man.
func vehicle_down(team: int, what: String) -> void:
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
			if s is Soldier:
				s.take_hit(600.0, driver)
				if world.get("tank") == t:
					# the man who would be credited is inside the vehicle
					run_over += 1
					kills += 1
					streak += 1
					Sim.report("you ran over %s" % (s as Soldier).callsign, Sim.Ev.GOOD)
					Sim.score += 100
			else:
				s.take_hit(600.0, t)

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
		var route: PackedVector2Array = _route_for(t, key, here, goal)
		if route.size() < 2:
			t.set_meta("cqb_goal", Vector3.INF)
			_routes.erase(key)
			continue
		# aim a couple of cells along it, so corners are cut no finer than
		# the street allows
		var at: int = int((_routes[key] as Array)[2])
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
	streak = 0
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
	_support(delta)
	_under_wheels()
	_drive_armour(delta)
	Sim.prof_end(&"cqb.match", _pc)
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

## Where the player is looking, on the ground or a wall.
func _mark() -> Vector3:
	if not is_instance_valid(player) or not is_instance_valid(player.cam):
		return Vector3.INF
	var eye: Vector3 = player.cam.global_position
	var look: Vector3 = -player.cam.global_transform.basis.z
	var d: float = Firearm.sight_range(eye, look, 500.0)
	if d >= 499.0:
		return Vector3.INF
	var p: Vector3 = eye + look * d
	return Vector3(p.x, _ground(p.x, p.z), p.z)

func _support(delta: float) -> void:
	# Whatever falls out of the sky during this match was called by him, and
	# is not meant for his own side.
	# With armour about that stops being true: a shell is a shell, whoever
	# fired it and whoever is standing where it lands.
	Effects.credit = player if (is_instance_valid(player) and not armour) else null
	Effects.spare_team = -1 if armour else 0
	uav_t = maxf(uav_t - delta, 0.0)
	if uav_t <= 0.0 and is_instance_valid(_uav):
		_uav.queue_free()
		_uav = null
	var still: Array = []
	for nk in _nukes:
		nk[0] = float(nk[0]) - delta
		if float(nk[0]) > 0.0:
			still.append(nk)
		else:
			_nuke(nk[1], float(nk[2]), bool(nk[3]))
	_nukes = still
	_plan_tick(delta)
	if _picking and world.get("map") != null and is_instance_valid(world.map) \
			and not world.map.pick_cb.is_valid():
		_picking = false
	if is_instance_valid(player) and player.is_alive() and not away:
		for k in chosen_streaks():
			if int(bank[k["id"]]) > 0 and Sim.tapped(StringName("weapon_%d" % int(k["key"]))):
				if _call(String(k["id"])):
					bank[k["id"]] = int(bank[k["id"]]) - 1
	var keep: Array = []
	for b in _bombs:
		b[0] = float(b[0]) - delta
		if float(b[0]) > 0.0:
			keep.append(b)
			continue
		_bomb(b[1], float(b[2]) if b.size() > 2 else 1.0)
	_bombs = keep

func _call(id: String) -> bool:
	match id:
		"uav":
			uav_t = UAV_TIME
			# A drone, in the sky, where it can be seen and shot at: the map
			# shows what it sees for as long as it is still flying.
			if not is_instance_valid(_uav):
				_uav = UavDrone.new()
				_uav.arena = self
				_uav.team = 0
				_uav.name = "UAV"
				world.add_child(_uav)
				_uav.station(Vector3(centre.x, _ground(centre.x, centre.y), centre.y))
			Sim.report("UAV overhead — hostiles on the map for %d seconds, unless they shoot it down" % int(UAV_TIME), Sim.Ev.GOOD)
			return true
		"tacnuke", "stratnuke":
			if world.get("map") != null and is_instance_valid(world.map) and not _picking:
				_picking = true
				world.map.pick("TACTICAL NUKE" if id == "tacnuke" else "STRATEGIC NUKE",
					func(p: Vector3): _picked(id, p))
			return false
		"tacnuke_at":
			var at3: Vector3 = _pick_at
			_nukes.append([12.0, Vector3(at3.x, _ground(at3.x, at3.z), at3.z), TAC_LETHAL, false])
			Sim.report("TACTICAL NUKE inbound — twelve seconds, get eighty metres clear of the mark", Sim.Ev.BAD)
			Sfx.play_at(world, "roar", at3 + Vector3(0, 900, 0), 9.0, 0.7, 9000.0)
			return true
		"stratnuke_at":
			var at4: Vector3 = _pick_at
			_nukes.append([20.0, Vector3(at4.x, _ground(at4.x, at4.z), at4.z), STRAT_LETHAL, true])
			Sim.report("STRATEGIC NUKE inbound — twenty seconds. It has been an honour.", Sim.Ev.BAD)
			Sfx.play_at(world, "roar", at4 + Vector3(0, 2000, 0), 10.0, 0.55, 12000.0)
			return true
		"strike":
			# On the map, not down the sights: what you want hit is usually
			# round a corner, which is why you are calling for it.
			if world.get("map") != null and is_instance_valid(world.map) and not _picking:
				_picking = true
				world.map.pick("AIRSTRIKE", func(p: Vector3): _picked("strike", p))
				return false
			return false
		"strike_at":
			var at: Vector3 = _pick_at
			# a stick of seven along the line from him to the mark
			var run := Vector3(at.x - player.global_position.x, 0.0, at.z - player.global_position.z)
			run = run.normalized() if run.length() > 1.0 else Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
			for i in 7:
				var p: Vector3 = at + run * (i - 2) * 12.0 \
					+ Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
				_bombs.append([3.0 + i * 0.16, Vector3(p.x, _ground(p.x, p.z), p.z)])
			Sim.report("airstrike inbound on your mark — three seconds, get down", Sim.Ev.GOOD)
			Sfx.play_at(world, "roar", at + Vector3(0, 160, 0) - run * 300.0, 8.0, 1.35, 4000.0)
			return true
		"mortar", "jdam":
			if world.get("map") != null and is_instance_valid(world.map) and not _picking:
				_picking = true
				world.map.pick("MORTAR BARRAGE" if id == "mortar" else "PRECISION BOMB",
					func(p: Vector3): _picked(id, p))
			return false
		"mortar_at":
			# ten rounds walked over the spot, a few seconds' flight apart
			for i in 10:
				var off := Vector3(_rng.randf_range(-20, 20), 0, _rng.randf_range(-20, 20))
				var p: Vector3 = _pick_at + off
				_bombs.append([4.0 + i * 0.7 + _rng.randf_range(0.0, 0.3),
					Vector3(p.x, _ground(p.x, p.z), p.z), 0.65])
			Sim.report("mortars on the way — ten rounds, first in four seconds", Sim.Ev.GOOD)
			return true
		"jdam_at":
			var at2: Vector3 = _pick_at
			_bombs.append([5.0, Vector3(at2.x, _ground(at2.x, at2.z), at2.z), 2.2])
			Sim.report("precision bomb released — five seconds, get clear", Sim.Ev.GOOD)
			Sfx.play_at(world, "roar", at2 + Vector3(0, 400, 0), 6.0, 1.2, 5000.0)
			return true
		"carpet":
			# two picks: where the carpet starts, then where it ends
			if world.get("map") != null and is_instance_valid(world.map) and not _picking:
				_picking = true
				_carpet_from = Vector3.INF
				world.map.pick("B-2 — click where the carpet STARTS", func(p: Vector3):
					_carpet_from = p
					world.map.pick("B-2 — click where the carpet ENDS",
						func(q: Vector3): _picked("carpet", q)))
			return false
		"carpet_at":
			if _carpet_from == Vector3.INF:
				return false
			var run := CarpetRun.new()
			run.arena = self
			run.from = _carpet_from
			run.to = _pick_at
			world.add_child(run)
			_carpet_from = Vector3.INF
			Sim.report("B-2 inbound — a carpet of %d along your line in about %d seconds" % [
				run.bombs, int(run.eta)], Sim.Ev.GOOD)
			return true
		"gunship":
			if world.has_method("cqb_gunship") and world.cqb_gunship(Vector3(centre.x,
					_ground(centre.x, centre.y), centre.y)):
				return true
			return false
		"missile":
			if world.get("map") != null and is_instance_valid(world.map) and not _picking:
				_picking = true
				world.map.pick("FIRE MISSION", func(p: Vector3): _picked("missile", p))
			return false
		"missile_at":
			return world.has_method("cqb_fire_mission") and world.cqb_fire_mission(_pick_at)
	return false

var _picking := false
var _pick_at := Vector3.ZERO

## The map came back with a place. Spend the streak on it, if it is still
## there to spend.
func _picked(id: String, at: Vector3) -> void:
	_picking = false
	if int(bank.get(id, 0)) <= 0 or not is_instance_valid(player):
		return
	_pick_at = at
	if _call(id + "_at"):
		bank[id] = int(bank[id]) - 1

## A B-2 down a line the player drew on the map, laying a carpet of bombs
## along it. It comes in from well short of the line at height, lets each bomb
## go early enough that it falls onto its own stretch of the line -- worked out
## by dropping one in the same flight model the bombs fly -- and goes on out the
## far side. The bombs are real: they fall, and where they land they go off as
## the match's own bombs do, credited to the man who called it.
class CarpetRun extends Node3D:
	const SPEED := 230.0
	const HEIGHT := 1100.0
	## Between canisters. Each one opens over the line and covers sixty metres
	## of it with bomblets, so the footprints overlap at this.
	const SPACING := 24.0
	const LONGEST := 600.0
	const RUN_IN := 7000.0
	var arena: CqbMatch = null
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var bombs := 0
	var eta := 0.0
	var _dir := Vector3.FORWARD
	var _start := Vector3.ZERO
	var _along := 0.0
	var _drops: Array = []            # along-track distances to let go at
	var _end := 0.0

	func _init() -> void:
		top_level = true

	func _enter_tree() -> void:
		if not _drops.is_empty():
			return
		var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
		var length: float = minf(flat.length(), LONGEST)
		_dir = flat.normalized() if flat.length() > 1.0 else Vector3.FORWARD
		bombs = clampi(int(length / SPACING) + 1, 8, 51)
		var base: float = from.y
		# How far forward of its release a bomb lands from this height and speed,
		# flown in the model the bombs fly.
		var p := Vector3(0.0, base + HEIGHT, 0.0)
		var v := Vector3(0.0, 0.0, -SPEED)
		var flown := 0.0
		var t := 0.0
		while p.y > base and t < 60.0:
			v = Ballistics.step(p, v, CarpetBomb.DRAG, 1.0 / 120.0, flown)
			p += v / 120.0
			flown += v.length() / 120.0
			t += 1.0 / 120.0
		var lead: float = -p.z
		_start = from - _dir * (lead + RUN_IN)
		_start.y = base + HEIGHT
		for i in bombs:
			var s: float = length * float(i) / float(maxi(bombs - 1, 1))
			_drops.append(RUN_IN + s)
		_end = RUN_IN + lead + length + RUN_IN
		eta = (RUN_IN + lead) / SPEED
		# A carpet is cluster bombs, every one. The B-2 as it is set out carries
		# a B83 and a B61 in its bays; this one is loaded for the job, and
		# flies it with the doors open and the load showing.
		var spec: Dictionary = JetSpec.get_spec("b2").duplicate(true)
		for bay in spec["bays"]:
			var st: Array = bay["stations"]
			for i in st.size():
				st[i]["weapon"] = "cbu97"
		var m: Dictionary = JetFactory.build(spec)
		var root: Node3D = m["root"]
		for g in m["gear"]:
			(g as Node3D).visible = false
		for bay2 in spec["bays"]:
			for d in (m["doors"] as Dictionary).get(bay2["id"], []):
				(d as Node3D).rotation.z = deg_to_rad(float(bay2["door_angle"])) \
					* float((d as Node).get_meta("side", 1.0))
		for k in m["stores"]:
			(m["stores"][k] as Node3D).visible = true
		add_child(root)
		global_position = _start
		look_at(_start + _dir, Vector3.UP)
		# put there, not flown there: without this the first frame is drawn
		# part way between the middle of the world and the start of the run
		reset_physics_interpolation()
		Sfx.play_at(get_parent(), "roar", _start, 10.0, 0.8, 9000.0)

	func _physics_process(delta: float) -> void:
		_along += SPEED * delta
		global_position = _start + _dir * _along
		while not _drops.is_empty() and _along >= float(_drops[0]):
			_drops.pop_front()
			var b := CarpetBomb.new()
			b.arena = arena
			b.vel = _dir * SPEED
			b.cluster = true
			get_parent().add_child(b)
			b.place(global_position + Vector3(0.0, -3.0, 0.0))
		if _along >= _end:
			queue_free()

## The drone a UAV streak puts up. It is there: it circles the town where it
## can be seen, it is a contact like any other aircraft, and anything that can
## reach it -- a man with a missile, a gun, another aeroplane -- can bring it
## down, which takes the picture off the map with it.
class UavDrone extends Node3D:
	const HEIGHT := 650.0
	const RADIUS := 520.0
	const SPEED := 58.0
	var arena: CqbMatch = null
	var team := 0
	var health := 30.0
	var alive := true
	var linear_velocity := Vector3.ZERO
	var _mid := Vector3.ZERO
	var _a := 0.0

	func _init() -> void:
		top_level = true

	func _ready() -> void:
		add_to_group("hittable")
		add_to_group("drones")
		var m: Dictionary = JetFactory.build(JetSpec.get_spec("mq9"))
		for g in m["gear"]:
			(g as Node3D).visible = false
		add_child(m["root"])

	func station(over: Vector3) -> void:
		_mid = over
		_a = randf() * TAU
		_fly(0.0)
		reset_physics_interpolation()

	func display_name() -> String:
		return "UAV"

	func is_alive() -> bool:
		return alive

	func hit_radius() -> float:
		return 6.0

	func get_velocity() -> Vector3:
		return linear_velocity

	func _fly(delta: float) -> void:
		_a += SPEED / RADIUS * delta
		var at := _mid + Vector3(cos(_a) * RADIUS, HEIGHT, sin(_a) * RADIUS)
		linear_velocity = Vector3(-sin(_a), 0.0, cos(_a)) * SPEED
		global_position = at
		look_at(at + linear_velocity, Vector3.UP)
		# banked into its circle
		rotate_object_local(Vector3.FORWARD, -atan(SPEED * SPEED / (9.81 * RADIUS)))

	func _physics_process(delta: float) -> void:
		if alive:
			_fly(delta)

	func take_hit(amount: float, _from: Node = null) -> void:
		if not alive:
			return
		health -= amount
		if health > 0.0:
			return
		alive = false
		remove_from_group("hittable")
		Effects.explosion(get_tree().current_scene, global_position, 9.0)
		if is_instance_valid(arena):
			arena.uav_lost()
		queue_free()

## One of the carpet: a cluster canister that falls, opens over the line and
## lets its bomblets go, each of which goes off on whatever it meets first -- a
## roof or the road. All of it falls in the same flight model a round flies.
class CarpetBomb extends Node3D:
	## What the air takes off it per metre. A canister with its fins out is a
	## draggy thing: it sheds the bomber's two hundred and thirty metres a
	## second inside the first few hundred metres and comes down steepening, at
	## about eighty a second and most of the way to vertical by the time it
	## opens -- which is the thing you recognise as bombs falling. At a sixth
	## of this it kept its forward speed all the way down and came in flat and
	## fast like a missile. The run works its release point out with this same
	## figure, so the carpet still lands where it was drawn.
	const DRAG := 0.0015
	## The short streak a bomblet trails: one mesh and one material for all of
	## them. The canisters trail nothing -- a long white line behind a falling
	## bomb is what made a stick of them read as rockets.
	static var trail_mesh: BoxMesh = null

	## Put it where it starts. Set down and left, a new body is drawn for its
	## first tick somewhere between the middle of the world and where it was
	## put -- every bomb of the stick arrived as a line flashed across the map.
	func place(at: Vector3) -> void:
		global_position = at
		if vel.length_squared() > 1.0:
			look_at(at + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)
		reset_physics_interpolation()
	## Where a cluster canister opens, above the ground, and what is in it.
	const OPEN_AT := 250.0
	const BOMBLETS := 12
	var arena: CqbMatch = null
	var vel := Vector3.ZERO
	var cluster := false
	## A bomblet out of a canister rather than a bomb.
	var bomblet := false
	var _flown := 0.0

	func _ready() -> void:
		top_level = true
		var st := MeshKit.begin()
		if bomblet:
			MeshKit.cone(st, 0.09, 0.09, -0.18, 0.18, Vector3.ZERO, 6)
		else:
			# the canister: body, and the fins that slow it
			MeshKit.cone(st, 0.2, 0.2, -1.2, 1.1, Vector3.ZERO, 8)
			MeshKit.box(st, Vector3(0.7, 0.03, 0.5), Vector3(0, 0, 1.0))
			MeshKit.box(st, Vector3(0.03, 0.7, 0.5), Vector3(0, 0, 1.0))
		add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(
			Color(0.42, 0.40, 0.22) if cluster or bomblet else Color(0.22, 0.23, 0.22), 0.6, 0.3)), "Bomb"))
		if not bomblet:
			return
		if CarpetBomb.trail_mesh == null:
			var tm := BoxMesh.new()
			tm.size = Vector3(0.16, 0.16, 1.0)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.92, 0.93, 0.95, 0.32)
			tm.material = mat
			CarpetBomb.trail_mesh = tm
		var trail := MeshInstance3D.new()
		trail.mesh = CarpetBomb.trail_mesh
		trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# behind it: the body points down -Z along the way it is falling
		trail.scale = Vector3(0.5, 0.5, 3.0)
		trail.position = Vector3(0.0, 0.0, 1.8)
		add_child(trail)

	func _physics_process(delta: float) -> void:
		vel = Ballistics.step(global_position, vel, DRAG, delta, _flown)
		var nxt: Vector3 = global_position + vel * delta
		_flown += vel.length() * delta
		var floor_y: float = maxf(Sim.height_at(nxt.x, nxt.z), Obstacles.top_at(nxt.x, nxt.z))
		if cluster and nxt.y - floor_y < OPEN_AT:
			# the canister opens and the bomblets go their own ways over the
			# street below
			var fwd := Vector3(vel.x, 0.0, vel.z)
			fwd = fwd.normalized() if fwd.length() > 0.5 else Vector3.FORWARD
			var side: Vector3 = fwd.cross(Vector3.UP)
			for i in BOMBLETS:
				var c := CarpetBomb.new()
				c.arena = arena
				c.bomblet = true
				# strung out along the run and kept narrow across it: thrown
				# evenly all round, each canister made a patch ninety metres
				# wide and the carpet was broader than the line it was drawn on
				c.vel = vel + fwd * randf_range(-12.0, 12.0) + side * randf_range(-3.5, 3.5) \
					+ Vector3(0.0, randf_range(-4.0, 4.0), 0.0)
				get_parent().add_child(c)
				c.place(nxt)
			Effects.dust(get_tree().current_scene, nxt, 4.0)
			queue_free()
			return
		if nxt.y <= floor_y:
			if is_instance_valid(arena):
				arena._bomb(Vector3(nxt.x, floor_y, nxt.z), 0.5 if bomblet else 1.25)
			else:
				Effects.explosion(get_tree().current_scene, Vector3(nxt.x, floor_y, nxt.z), 6.0)
			queue_free()
			return
		global_position = nxt
		if vel.length_squared() > 1.0:
			look_at(nxt + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)

## The drone went down: the picture goes with it.
func uav_lost() -> void:
	uav_t = 0.0
	_uav = null
	Sim.report("UAV shot down — the map is dark again", Sim.Ev.BAD)

## A warhead going off at `at`. Everything that can be hurt inside `lethal`
## is, whoever's side it is on and the man who called it included; every
## building and everything standing in the street inside it comes down. The
## strategic one ends the match as well: there is nobody left to play it.
func _nuke(at: Vector3, lethal: float, strategic: bool) -> void:
	var scn: Variant = world.get("scenery")
	var flat := lethal * 1.2
	if scn != null and is_instance_valid(scn) and scn.has_method("damage_area"):
		scn.damage_area(at, flat)
	else:
		Obstacles.kill_near(at, flat)
	for t in TownSet.live:
		if is_instance_valid(t):
			(t as TownSet).flatten(at, flat)
	Effects.mute_blast = true
	Effects.nuke(world, at, lethal)
	Effects.mute_blast = false
	var seen := {}
	var hurt: Array = soldiers.duplicate()
	hurt.append_array(get_tree().get_nodes_in_group("hittable"))
	if is_instance_valid(player) and not away:
		hurt.append(player)
	var credit: Node = player if is_instance_valid(player) else null
	for n in hurt:
		if not is_instance_valid(n) or not (n is Node3D) or seen.has(n) \
				or not n.has_method("take_hit"):
			continue
		seen[n] = true
		var d: float = (n as Node3D).global_position.distance_to(at)
		if d < lethal:
			n.take_hit(4000.0 * clampf(1.0 - d / lethal, 0.3, 1.0), credit)
		elif d < lethal * 1.6:
			# outside it, the blast: hurt, not killed
			n.take_hit(70.0 * (1.0 - (d - lethal) / (lethal * 0.6)), credit)
	if strategic and is_instance_valid(mode) and mode.running:
		mode._finish(true, "STRATEGIC STRIKE")

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

## One bomb of the stick, one mortar round, or the one big bomb: `big` is
## how much bigger or smaller than a stick bomb it is. It does not care about
## walls and it does not care whose side anyone is on, the man who called it
## included.
func _bomb(at: Vector3, big := 1.0) -> void:
	Effects.mute_blast = true
	Effects.explosion(world, at + Vector3(0, 1.0, 0), 5.0 * big)
	Effects.he_impact(world, at + Vector3(0, 0.6, 0), 4.5 * big)
	Effects.mute_blast = false
	var kill_r: float = 14.0 * big
	for n in soldiers.duplicate():
		if not is_instance_valid(n) or (n as Soldier).team == 0:
			continue
		var d: float = (n as Soldier).global_position.distance_to(at)
		if d < kill_r:
			(n as Soldier).take_hit(320.0 * pow(1.0 - d / kill_r, 1.1), player)
	if is_instance_valid(player) and not away:
		var dp: float = player.global_position.distance_to(at)
		if dp < 9.0 * big:
			player.take_hit(160.0 * (1.0 - dp / (9.0 * big)), player)

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
		elif uav_t > 0.0 or sd.loud > 0.0:
			dots.append([map_uv(sd.global_position), 1])
			dots_w.append([at, 1])
	return {"kills": kills, "deaths": deaths, "headshots": headshots,
		"blue": (_teams[0] as Array).size(), "red": (_teams[1] as Array).size(),
		"streak": streak, "bank": bank, "streaks": chosen_streaks(), "uav": uav_t,
		"map": map_tex, "dots": dots, "dots_w": dots_w,
		"area": Rect2(_corner, Vector2(HALF * 2.0, HALF * 2.0)),
		"me_w": Vector2(player.global_position.x, player.global_position.z)
			if is_instance_valid(player) else centre,
		"me": map_uv(player.global_position) if is_instance_valid(player) else Vector2(0.5, 0.5),
		"yaw": player.yaw if is_instance_valid(player) else 0.0}
