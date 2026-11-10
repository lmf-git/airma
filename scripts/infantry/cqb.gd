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
const SQUAD := 6                  # a side, the player included
const RESPAWN := 4.5
const KILL_GOAL := 40
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
## What a run of kills without dying earns, and the key that spends it.
const STREAKS := [
	{"id": "uav", "name": "UAV", "at": 3, "key": 4},
	{"id": "strike", "name": "AIRSTRIKE", "at": 5, "key": 5},
	{"id": "gunship", "name": "AC-130 GUNNER", "at": 7, "key": 6},
	{"id": "missile", "name": "FIRE MISSION", "at": 9, "key": 7},
]
const UAV_TIME := 30.0
var streak := 0
var bank := {"uav": 0, "strike": 0, "gunship": 0, "missile": 0}
var uav_t := 0.0
var map_tex: ImageTexture = null
## The player is somewhere else for a while -- at a gun station overhead --
## and the man standing in the street is not there to be shot.
var away := false
var _bombs: Array = []            # [seconds until it lands, where]
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
		for i in SQUAD:
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

## A way from one place to another round everything solid, as points to walk.
func path(from: Vector3, to: Vector3) -> PackedVector2Array:
	var a := _free_cell(_cell(from))
	var b := _free_cell(_cell(to))
	if a.x < 0 or b.x < 0:
		return PackedVector2Array()
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
			score -= absf(float(k - 4) - (float(slot) - SQUAD * 0.5) * 1.5) * 3.0
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
	elif air and slot == 4:
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
		for k in STREAKS:
			# the ladder comes round again after the top rung
			if (streak - 1) % 9 + 1 == int(k["at"]):
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
	for v in get_tree().get_nodes_in_group("hittable"):
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
	for v in get_tree().get_nodes_in_group("hittable"):
		var t := v as Tank
		if t == null or not t.alive or not t.ai or t.occupied:
			continue
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
		var route: PackedVector2Array = _vnav.get_point_path(_vcell(here), _vcell(goal), true)
		if route.size() < 2:
			t.set_meta("cqb_goal", Vector3.INF)
			continue
		# aim a couple of cells along it, so corners are cut no finer than
		# the street allows
		var wp: Vector2 = route[mini(2, route.size() - 1)]
		var dir := Vector3(wp.x - here.x, 0.0, wp.y - here.z)
		if dir.length() < 0.5:
			continue
		# The driver stops short of wherever he is told to go by a long way --
		# that is right for a sector and no use for a street corner -- so the
		# point he is given is well beyond the one that is meant.
		t.ai_goal = here + dir.normalized() * 400.0

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
	_support(delta)
	_under_wheels()
	_drive_armour(delta)
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

## A shot, or a man running: everyone on the other side within earshot turns.
func heard(at: Vector3, by_team: int, radius := 75.0) -> void:
	for s in _teams[1 - by_team]:
		if is_instance_valid(s) and s is Soldier \
				and (s as Soldier).global_position.distance_to(at) < radius:
			(s as Soldier).hear(at)

## Where a man with nothing to shoot at should go.
func objective_for(s: Soldier) -> Vector3:
	# towards the last place anyone on his side saw the enemy
	var list: Array = _contacts[s.team]
	if not list.is_empty() and _rng.randf() < 0.8:
		var c: Array = list[_rng.randi() % list.size()]
		var p: Vector3 = _free_near((c[0] as Vector3)
			+ Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8)))
		if p != Vector3.INF:
			return p
	# some of your own side stay with you, which is what makes it a squad
	if s.team == 0 and is_instance_valid(player) and player.is_alive() \
			and int(s.get_meta("slot", 0)) % 2 == 1:
		var back := Vector3(_rng.randf_range(-7, 7), 0, _rng.randf_range(-7, 7))
		var near: Vector3 = _free_near(player.global_position + back)
		if near != Vector3.INF:
			return near
	# otherwise push: the crossroads, the yards, and the other side's half
	var pick: Vector3 = _spots[_rng.randi() % _spots.size()]
	var push: float = -1.0 if s.team == 0 else 1.0
	if _rng.randf() < 0.45:
		var deep: Vector3 = _free_near(Vector3(centre.x + _rng.randf_range(-90, 90), 0,
			centre.y + push * _rng.randf_range(40.0, 105.0)))
		if deep != Vector3.INF:
			return deep
	return pick

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
	if _picking and world.get("map") != null and is_instance_valid(world.map) \
			and not world.map.pick_cb.is_valid():
		_picking = false
	if is_instance_valid(player) and player.is_alive() and not away:
		for k in STREAKS:
			if int(bank[k["id"]]) > 0 and Sim.tapped(StringName("weapon_%d" % int(k["key"]))):
				if _call(String(k["id"])):
					bank[k["id"]] = int(bank[k["id"]]) - 1
	var keep: Array = []
	for b in _bombs:
		b[0] = float(b[0]) - delta
		if float(b[0]) > 0.0:
			keep.append(b)
			continue
		_bomb(b[1])
	_bombs = keep

func _call(id: String) -> bool:
	match id:
		"uav":
			uav_t = UAV_TIME
			Sim.report("UAV overhead — hostiles on the map for %d seconds" % int(UAV_TIME), Sim.Ev.GOOD)
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

## One bomb of the stick. It does not care about walls and it does not care
## whose side anyone is on, the man who called it included.
func _bomb(at: Vector3) -> void:
	Effects.mute_blast = true
	Effects.explosion(world, at + Vector3(0, 1.0, 0), 5.0)
	Effects.he_impact(world, at + Vector3(0, 0.6, 0), 4.5)
	Effects.mute_blast = false
	for n in soldiers.duplicate():
		if not is_instance_valid(n) or (n as Soldier).team == 0:
			continue
		var d: float = (n as Soldier).global_position.distance_to(at)
		if d < 14.0:
			(n as Soldier).take_hit(320.0 * pow(1.0 - d / 14.0, 1.1), player)
	if is_instance_valid(player) and not away:
		var dp: float = player.global_position.distance_to(at)
		if dp < 9.0:
			player.take_hit(160.0 * (1.0 - dp / 9.0), player)

func hud_state() -> Dictionary:
	# who shows on the map: your own side always, theirs when a UAV is up or
	# when they have just given themselves away by firing
	var dots: Array = []
	for s in soldiers:
		if not is_instance_valid(s):
			continue
		var sd := s as Soldier
		if sd.team == 0:
			dots.append([map_uv(sd.global_position), 0])
		elif uav_t > 0.0 or sd.loud > 0.0:
			dots.append([map_uv(sd.global_position), 1])
	return {"kills": kills, "deaths": deaths, "headshots": headshots,
		"blue": (_teams[0] as Array).size(), "red": (_teams[1] as Array).size(),
		"streak": streak, "bank": bank, "streaks": STREAKS, "uav": uav_t,
		"map": map_tex, "dots": dots,
		"me": map_uv(player.global_position) if is_instance_valid(player) else Vector2(0.5, 0.5),
		"yaw": player.yaw if is_instance_valid(player) else 0.0}
