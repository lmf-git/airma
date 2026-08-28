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
		"ffa":
			Sim.report("FREE FOR ALL — %d kills wins, everyone is hostile." % kill_goal, Sim.Ev.INFO)

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
	if mode in ["tdm", "ffa"] and kills[scorer] >= kill_goal:
		_finish(scorer == 0, "KILL LIMIT REACHED")
	if mode in ["conquest", "warlords"]:
		tickets[team_of_victim] = maxi(int(tickets[team_of_victim]) - 5, 0)

func _process(delta: float) -> void:
	if not running:
		return
	# Gathered once for the whole match. Every sector used to walk the entire
	# hittable group for itself, so the cost of a conquest was the number of
	# sectors times the number of things alive -- fine at five sectors, not at
	# twenty.
	var holders: Array = []
	for n in get_tree().get_nodes_in_group("hittable"):
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
		"cp_rate": cp_rate, "held": held, "objective": obj}
