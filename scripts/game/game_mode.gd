class_name GameMode
extends Node
## Rule sets for the battle modes. The world hands it a mode id; it lays out the
## objectives, ticks scoring and reports state for the HUD.

signal finished(win: bool, text: String)

## The sectors that exist whatever else is on the map: the depot, the pass and
## the two airfields' approaches. Everything else is a settlement.
const FIXED := [
	[Vector3(-1500, 0, -6600), 280.0, "Depot"],
	[Vector3(1400, 0, -9400), 240.0, "The Pass"],
]

## Sectors, laid out over whatever country actually got generated.
##
## This was five hard-coded points, three of which happened to sit on the four
## towns the map had at the time. With sixteen settlements on it, a conquest
## fought over five fixed coordinates ignores most of the map -- so the sectors
## are the places: every town is worth taking, and so is the depot and the pass.
static func layout() -> Array:
	var out: Array = []
	var sc := Scenery.current
	if sc != null and not sc.sites.is_empty():
		for t in sc.sites:
			var c: Vector2 = t["c"]
			var r: float = float(t["r"])
			out.append([Vector3(c.x, 0.0, c.y), clampf(r * 0.45, 190.0, 430.0),
				String(t["name"])])
	for f in FIXED:
		out.append([f[0], f[1], f[2]])
	# nearest the airfield first, so a sequential push starts at home and works
	# outwards instead of opening in somebody else's back garden
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return (a[0] as Vector3).length_squared() < (b[0] as Vector3).length_squared())
	return out

## A, B ... Z, then AA, AB. Twenty-odd sectors run off the end of the alphabet.
static func sector_label(i: int) -> String:
	if i < 26:
		return String.chr(65 + i)
	var hi: int = int(floor(float(i) / 26.0))
	return String.chr(65 + hi - 1) + String.chr(65 + i - hi * 26)

var mode := "conquest"
var zones: Array[CaptureZone] = []
var tickets := {0: 400, 1: 400}
var kills := {0: 0, 1: 0}
var kill_goal := 25
var command_points := 0
var active_sector := 0
var running := false
var result := ""
var _bleed := 0.0
var _layout: Array = []
## Command points a minute at this instant, for the HUD.
var cp_rate := 0.0
var _cp_accum := 0.0
## How close you have to get before an unclaimed sector's garrison is built.
const GARRISON_REACH := 7000.0

func start(id: String) -> void:
	mode = id
	running = true
	result = ""
	_layout = layout()
	match mode:
		"conquest":
			tickets = {0: 400, 1: 400}
			# a third to us, a third to them, the rest up for grabs
			for i in _layout.size():
				_zone(i, 0 if i % 3 == 0 else (1 if i % 3 == 1 else -1))
		"rush":
			tickets = {0: 250, 1: 0}
			for i in _layout.size():
				_zone(i, 1)
			_gate_sequential()
		"warlords":
			tickets = {0: 300, 1: 300}
			command_points = 200
			for i in _layout.size():
				_zone(i, 1)
			_gate_sequential()
		"tdm", "ffa":
			kill_goal = 12 if mode == "ffa" else 20
		"cqb", "ground", "arms":
			kill_goal = CqbMatch.KILL_GOAL
			Sim.no_air_threat = mode != "arms"
		"strike":
			# Nothing on this range shoots at an aeroplane, whatever it is.
			Sim.no_air_threat = true
			_strike_wave()
	_announce()

func _zone(i: int, team: int) -> void:
	var l: Array = _layout[i]
	var lab := sector_label(i)
	var z := CaptureZone.new()
	z.name = "Zone %s" % lab
	get_parent().add_child(z)
	z.build(lab, l[0], float(l[1]), team)
	z.place = String(l[2])
	# A big settlement is worth more than a village: the radius the layout gave
	# it is a proxy for how much is standing there.
	z.income = snappedf(clampf(float(l[1]) * 0.11, 14.0, 60.0), 1.0)
	z.captured.connect(_on_captured)
	zones.append(z)

## Rush and Warlords only open one objective at a time.
func _gate_sequential() -> void:
	active_sector = 0
	for i in zones.size():
		zones[i].locked = i != active_sector
	# the one that is live is defended; the rest are stood up as you reach them
	if not zones.is_empty():
		zones[active_sector].ensure_garrison()

func _announce() -> void:
	match mode:
		"conquest":
			Sim.report("CONQUEST — hold the sectors, bleed their tickets.", Sim.Ev.INFO)
		"rush":
			Sim.report("RUSH — take sector %s. Destroy the garrison or hold the ring."
				% zones[0].label, Sim.Ev.INFO)
		"warlords":
			Sim.report("WARLORDS — capture sectors in order, spend command points on assets.",
				Sim.Ev.INFO)
		"tdm":
			Sim.report("TEAM DEATHMATCH — first side to %d kills." % kill_goal, Sim.Ev.INFO)
		"cqb":
			Sim.report("CQB — two squads on foot in the middle of town. First side to %d kills." % kill_goal,
				Sim.Ev.INFO)
		"ground":
			Sim.report("GROUND COMBAT — infantry and armour in the streets. First side to %d kills." % kill_goal,
				Sim.Ev.INFO)
		"arms":
			Sim.report("COMBAT — infantry, armour and aircraft over one town. First side to %d kills." % kill_goal,
				Sim.Ev.INFO)
		"ffa":
			Sim.report("FREE FOR ALL — %d kills wins, everyone is hostile." % kill_goal, Sim.Ev.INFO)
		"strike":
			Sim.report("STRIKE — armour, shipping and helicopters to hunt. Nothing down there shoots at aeroplanes.",
				Sim.Ev.INFO)

func _on_captured(z: CaptureZone, team: int) -> void:
	Sim.report("sector %s taken by %s" % [z.label, "us" if team == 0 else "them"],
		Sim.Ev.GOOD if team == 0 else Sim.Ev.BAD)
	if team == 0:
		Sim.score += 250
		command_points += 120
	if mode in ["rush", "warlords"] and team == 0:
		active_sector += 1
		if active_sector >= zones.size():
			_finish(true, "ALL SECTORS TAKEN")
			return
		for i in zones.size():
			zones[i].locked = i != active_sector
		zones[active_sector].ensure_garrison()
		Sim.report("next objective: sector %s (%s)" % [zones[active_sector].label,
			zones[active_sector].place], Sim.Ev.INFO)

func register_kill(team_of_victim: int) -> void:
	var scorer: int = 1 - team_of_victim
	kills[scorer] = int(kills.get(scorer, 0)) + 1
	if mode in ["tdm", "ffa", "cqb", "ground", "arms"] and kills[scorer] >= kill_goal:
		_finish(scorer == 0, "KILL LIMIT REACHED")
	if mode in ["conquest", "warlords"]:
		tickets[team_of_victim] = maxi(int(tickets[team_of_victim]) - 5, 0)

## How often the match is counted. A sector takes four and a half seconds to
## change hands with one vehicle standing in it, tickets bleed every two, and
## reinforcements are looked at every nine: none of it is a thing that happens
## in a frame, and all of it was being worked out at the frame rate -- a walk
## of everything alive and then every sector against every one of them, a
## quarter of a millisecond a frame in a conquest. Five times a second, with
## the time that has actually passed, comes to the same match.
const COUNT_EVERY := 0.2
var _count_dt := COUNT_EVERY

func _process(frame_dt: float) -> void:
	if not running:
		return
	_count_dt += frame_dt
	if _count_dt < COUNT_EVERY:
		return
	var _pm := Sim.prof_at()
	_count(_count_dt)
	_count_dt = 0.0
	Sim.prof_end(&"mode.count", _pm)

func _count(delta: float) -> void:
	# Gathered once for the whole match. Every sector used to walk the entire
	# hittable group for itself, so the cost of a conquest was the number of
	# sectors times the number of things alive -- fine at five sectors, not at
	# twenty.
	var holders: Array = []
	Sim.hit_scan()
	for n in Sim.hit_nodes:
		if not is_instance_valid(n) or (n.has_method("is_alive") and not n.is_alive()):
			continue
		if n is GroundTarget:
			continue
		if n is Aircraft and (n as Aircraft).agl > 260.0:
			continue                                   # too high to hold ground
		holders.append([(n as Node3D).global_position, n.team if "team" in n else 0])
	for z in zones:
		if is_instance_valid(z):
			z.tick(delta, holders)
	_garrison_near(holders)
	_reinforce_ground(delta)
	_tick_strike(delta)
	_earn(delta)
	if mode == "conquest":
		var mine := 0
		var theirs := 0
		for z in zones:
			if z.owner_team == 0:
				mine += 1
			elif z.owner_team == 1:
				theirs += 1
		_bleed += delta
		if _bleed >= 2.0:
			# one ticket per net sector every two seconds: a losing side has time
			# to do something about it rather than being drained in half a minute
			_bleed = 0.0
			if mine > theirs:
				tickets[1] = maxi(int(tickets[1]) - (mine - theirs), 0)
			elif theirs > mine:
				tickets[0] = maxi(int(tickets[0]) - (theirs - mine), 0)
			if int(tickets[1]) <= 0:
				_finish(true, "ENEMY TICKETS EXHAUSTED")
			elif int(tickets[0]) <= 0:
				_finish(false, "OUR TICKETS EXHAUSTED")

## Stand up the garrison of any sector somebody has got close to. A sector
## nobody has been near is scenery, and scenery does not need six crewed assets
## sitting in it being thought about every frame.
func _garrison_near(holders: Array) -> void:
	for z in zones:
		if not is_instance_valid(z) or z.has_garrison():
			continue
		for h in holders:
			if int(h[1]) != 0:
				continue
			if (h[0] as Vector3).distance_to(z.global_position) < GARRISON_REACH:
				z.ensure_garrison()
				break

## How many crewed ground units a side fields when nobody has taken the slot.
const AI_GROUND_PER_SIDE := 6
## The modes that are fought on the ground as well as in the air.
const GROUND_MODES := ["conquest", "rush", "warlords", "tdm"]
var _reinforce := 4.0

## Keep both sides in armour, less whatever people are crewing themselves.
##
## The sectors had garrisons and nothing else: away from a flag the ground was
## empty, so a battle for the map was fought by two aeroplanes over country
## nobody was holding. Every slot a person takes is one the machine does not
## fill, so a full server fields no AI at all and a single player gets a whole
## opposing force.
func _reinforce_ground(delta: float) -> void:
	if not GROUND_MODES.has(mode):
		return
	_reinforce -= delta
	if _reinforce > 0.0:
		return
	_reinforce = 9.0
	_assign_ground_goals()
	for team in [0, 1]:
		var want: int = AI_GROUND_PER_SIDE - _crewed_on(team)
		var have := 0
		for n in get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or not (n is Tank):
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if int(n.team) == team and ("ai" in n) and bool(n.ai):
				have += 1
		if have < want:
			_send_up_armour(team)

## Units on a side that a person is crewing. Anything that is not under AI
## control is somebody's, whether that is the host or a player who has joined.
func _crewed_on(team: int) -> int:
	var n := 0
	for x in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(x) or not ("team" in x) or int(x.team) != team:
			continue
		if x.has_method("is_alive") and not x.is_alive():
			continue
		if ("ai" in x) and not bool(x.ai):
			n += 1
	return n

## Each side's end of the field, for a mode with no sectors to start from: ours
## north of the home airfield, theirs up the valley where their sites stand.
const HOME_GROUND := {0: Vector3(-900.0, 0.0, -2600.0), 1: Vector3(400.0, 0.0, -9600.0)}

## One vehicle, put down at a sector the side holds -- or, with nothing held,
## at the one nearest home.
func _send_up_armour(team: int) -> void:
	var at := Vector3.INF
	var best := 1e18
	for z in zones:
		if not is_instance_valid(z):
			continue
		if z.owner_team == team:
			at = z.global_position
			break
		var d: float = z.global_position.length_squared()
		if d < best:
			best = d
			at = z.global_position
	# A team deathmatch has no sectors at all, and this returned -- so the mode
	# that lists armour among the things fighting had none on either side.
	if at == Vector3.INF:
		at = HOME_GROUND[team]
	var p := _dry_spot(at, 240.0, 620.0)
	if p == Vector3.INF:
		return
	var a := randf() * TAU
	# One in three reinforcements is a patrol vehicle rather than a tank: they
	# are quick to get to a sector and they are what a side actually has most of.
	var roll := randi()
	var t := Tank.new()
	t.setup(team, Tank.pick_kind("lav" if roll % 3 == 0 else "mbt", team, roll >> 4))
	t.ai = true
	t.name = "%s %d" % ["patrol" if roll % 3 == 0 else "armour", roll % 100000]
	get_parent().add_child(t)
	t.global_transform = Tank.ground_pose(p, a, t.rest_height())

## Somewhere a vehicle can stand, in a ring about `at`: not in the water.
static func _dry_spot(at: Vector3, r0: float, r1: float) -> Vector3:
	for i in 16:
		var a := randf() * TAU
		var p := at + Vector3(cos(a), 0.0, sin(a)) * randf_range(r0, r1 + 120.0 * i)
		if Sim.height_at(p.x, p.z) <= Sim.sea_at(p.x, p.z) + 3.0:
			continue
		# and not in a town, where a column put down among the buildings spent
		# the match pressed against them
		var in_town := false
		for pad in Sim._town_pads:
			if Vector2(p.x, p.z).distance_to(pad["c"] as Vector2) < float(pad["r"]) * 1.3:
				in_town = true
				break
		if not in_town:
			return p
	return Vector3.INF

## Send every crewed vehicle somewhere. A garrison holds its sector; the rest go
## for the nearest sector their side does not hold -- the one that is open, in
## the modes that open them one at a time -- and with no sectors at all, for the
## other side's end of the field.
func _assign_ground_goals() -> void:
	for n in get_tree().get_nodes_in_group("hittable"):
		if not (n is Tank) or not is_instance_valid(n):
			continue
		var t := n as Tank
		if not t.ai or not t.alive or t.occupied or t.has_meta("zone_asset") \
				or t.has_meta("strike"):
			continue
		var goal := Vector3.INF
		var bd := 1e18
		for i in zones.size():
			var z: CaptureZone = zones[i]
			if not is_instance_valid(z) or z.owner_team == t.team or z.locked:
				continue
			var d: float = z.global_position.distance_squared_to(t.global_position)
			if d < bd:
				bd = d
				goal = z.global_position
		if goal == Vector3.INF and zones.is_empty() and mode == "tdm":
			goal = HOME_GROUND[1 - t.team]
		t.ai_goal = goal

## Command points accrue from the sectors you hold, not just from taking them.
## Without an income the number sat still between captures and told you nothing
## about whether you were winning.
func _earn(delta: float) -> void:
	var rate := 0.0
	for z in zones:
		if is_instance_valid(z) and z.owner_team == 0:
			rate += z.income
	cp_rate = rate
	if mode != "warlords":
		return
	_cp_accum += rate * delta / 60.0
	var whole := int(floor(_cp_accum))
	if whole > 0:
		command_points += whole
		_cp_accum -= float(whole)

func spend(cost: int) -> bool:
	if command_points < cost:
		return false
	command_points -= cost
	return true

func _finish(win: bool, text: String) -> void:
	if not running:
		return
	running = false
	result = ("VICTORY — " if win else "DEFEAT — ") + text
	Sim.report(result, Sim.Ev.GOOD if win else Sim.Ev.BAD)
	finished.emit(win, text)

func hud_state() -> Dictionary:
	var zs: Array = []
	for z in zones:
		if is_instance_valid(z):
			zs.append({"label": z.label, "team": z.owner_team, "prog": z.progress,
				"contested": z.contested, "locked": z.locked, "pos": z.global_position,
				"place": z.place, "income": z.income})
	var held := 0
	for z2 in zones:
		if is_instance_valid(z2) and z2.owner_team == 0:
			held += 1
	var obj := ""
	if mode in ["rush", "warlords"] and active_sector < zones.size():
		obj = "%s — %s" % [zones[active_sector].label, zones[active_sector].place]
	return {"mode": mode, "tickets": tickets, "kills": kills, "goal": kill_goal,
		"zones": zs, "cp": command_points, "result": result, "running": running,
		"cp_rate": cp_rate, "held": held, "objective": obj,
		"wave": wave, "left": _strike_left(), "destroyed": destroyed}

# ------------------------------------------------------------------ strike
## A range to practise on: columns of armour on the move, shipping, and
## helicopters, none of which can hurt an aeroplane. A wave is everything that
## was put up at once; clear it and the next comes in, a little bigger.
var wave := 0
var destroyed := 0
var _wave_units: Array = []
var _strike_check := 2.0

func _tick_strike(delta: float) -> void:
	if mode != "strike":
		return
	_strike_check -= delta
	if _strike_check > 0.0:
		return
	_strike_check = 2.0
	var left := _strike_left()
	destroyed = maxi(destroyed, _wave_total - left + _destroyed_before)
	if left == 0:
		_destroyed_before = destroyed
		Sim.score += 500 * wave
		Sim.report("wave %d cleared" % wave, Sim.Ev.GOOD)
		_strike_wave()

var _wave_total := 0
var _destroyed_before := 0

func _strike_left() -> int:
	var n := 0
	for u in _wave_units:
		if is_instance_valid(u) and (not u.has_method("is_alive") or u.is_alive()):
			n += 1
	return n

func _strike_wave() -> void:
	wave += 1
	_wave_units.clear()
	var world: Node = get_parent()
	# Armour on the move: a column put down somewhere along the valley and sent
	# across it, so it is a target that goes somewhere rather than a tank park.
	var size: int = mini(4 + wave * 2, 12)
	var from := _dry_spot(Vector3(randf_range(-6000.0, 6000.0), 0.0,
		randf_range(-14000.0, -6000.0)), 0.0, 400.0)
	if from != Vector3.INF:
		var dest := _dry_spot(from + Vector3(randf_range(-7000.0, 7000.0), 0.0,
			randf_range(4000.0, 8000.0)), 0.0, 600.0)
		var classes := ["mbt", "ifv", "lav", "mbt", "ifv", "lav"]
		for i in size:
			var cls: String = classes[i % classes.size()]
			var t := Tank.new()
			t.setup(1, Tank.pick_kind(cls, 1, randi()))
			t.ai = true
			t.name = "Column %d-%d" % [wave, i + 1]
			t.set_meta("strike", true)
			world.add_child(t)
			# pointed the way it is going: put down facing north with a goal to
			# the south, each one had to turn round before it went anywhere
			var head := 0.0
			if dest != Vector3.INF:
				var to_dest := dest - from
				head = atan2(-to_dest.x, -to_dest.z)
			var basis_h := Basis(Vector3.UP, head)
			var lane: Vector3 = basis_h * Vector3(float(i % 3 - 1) * 28.0, 0.0,
				floorf(float(i) / 3.0) * 60.0)
			var at := from + lane
			t.global_transform = Tank.ground_pose(at, head, t.rest_height())
			t.ai_goal = dest if dest != Vector3.INF else Vector3.INF
			_wave_units.append(t)
	# Shipping: merchantmen and gun boats. A destroyer's tubes would be an air
	# threat, so nothing that carries any is put on this range.
	if world.has_method("_deep_water"):
		var ships: int = mini(1 + wave, 5)
		for i in ships:
			var sh := Ship.new()
			sh.setup("cargo" if i % 2 == 0 else "patrol", 1)
			world.add_child(sh)
			var sea: Vector3 = world.call("_deep_water",
				Vector3(22000.0 + float(i) * 2600.0, 0.0, -3000.0 + float(i) * 1800.0))
			sh.global_position = Vector3(sea.x, Sim.sea_surface(sea.x, sea.z), sea.z)
			sh.name = "Shipping %d-%d" % [wave, i + 1]
			_wave_units.append(sh)
	# And helicopters, working low over the column.
	var helis: int = mini(1 + int(wave / 2.0), 4)
	var rotary: Array = ["mi28", "z10"] if JetSpec.bloc_of(Sim.selected_jet) == "nato" \
		else ["ah64", "tiger"]
	for i in helis:
		var h := AIHeli.new()
		h.setup(rotary[i % rotary.size()])
		h.team = 1
		h.name = "Helicopter %d-%d" % [wave, i + 1]
		var hp: Vector3 = from if from != Vector3.INF else Vector3(0, 0, -9000)
		h.home = hp + Vector3(float(i) * 900.0 - 450.0, 0.0, 600.0)
		world.add_child(h)
		h.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)),
			Vector3(h.home.x, Sim.height_at(h.home.x, h.home.z) + 180.0, h.home.z))
		_wave_units.append(h)
	_wave_total = _wave_units.size()
	Sim.report("wave %d: a column of %d, %d ship(s) and %d helicopter(s)" % [
		wave, size if from != Vector3.INF else 0,
		_wave_units.filter(func(u): return u is Ship).size(), helis], Sim.Ev.INFO)
