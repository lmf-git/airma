class_name GameMode
extends Node
## Rule sets for the battle modes. The world hands it a mode id; it lays out the
## objectives, ticks scoring and reports state for the HUD.

signal finished(win: bool, text: String)

const LAYOUT := [
	["A", Vector3(-2300, 0, -5200), 260.0],
	["B", Vector3(1400, 0, -9400), 240.0],
	["C", Vector3(2600, 0, 4200), 300.0],
	["D", Vector3(-1900, 0, 3100), 220.0],
	["E", Vector3(-1500, 0, -6600), 280.0],
]

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

func start(id: String) -> void:
	mode = id
	running = true
	result = ""
	match mode:
		"conquest":
			tickets = {0: 400, 1: 400}
			for i in LAYOUT.size():
				_zone(i, 1 if i < 3 else -1)
		"rush":
			tickets = {0: 250, 1: 0}
			for i in LAYOUT.size():
				_zone(i, 1)
			_gate_sequential()
		"warlords":
			tickets = {0: 300, 1: 300}
			command_points = 200
			for i in LAYOUT.size():
				_zone(i, 1)
			_gate_sequential()
		"tdm", "ffa":
			kill_goal = 12 if mode == "ffa" else 20
	_announce()

func _zone(i: int, team: int) -> void:
	var l: Array = LAYOUT[i]
	var z := CaptureZone.new()
	z.name = "Zone %s" % l[0]
	get_parent().add_child(z)
	z.build(l[0], l[1], l[2], team)
	z.captured.connect(_on_captured)
	zones.append(z)

## Rush and Warlords only open one objective at a time.
func _gate_sequential() -> void:
	active_sector = 0
	for i in zones.size():
		zones[i].locked = i != active_sector

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
		Sim.report("next objective: sector %s" % zones[active_sector].label, Sim.Ev.INFO)

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
	for z in zones:
		if is_instance_valid(z):
			z.tick(delta)
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
				"contested": z.contested, "locked": z.locked, "pos": z.global_position})
	return {"mode": mode, "tickets": tickets, "kills": kills, "goal": kill_goal,
		"zones": zs, "cp": command_points, "result": result, "running": running}
