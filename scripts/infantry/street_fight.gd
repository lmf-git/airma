class_name StreetFight
extends RefCounted
## The street fight (CQB) and the firing range, as the world runs them: setting
## up the arena and the town dressing, deploying, the support that can be
## called in, and keeping the fight inside its bounds.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

const CQB_GUNSHIP_TIME := 120.0
## Two squads on foot in the middle of the nearest town. The aeroplane that
## was picked stays on the apron with the canopy shut: every page in the game
## expects there to be one, and this is a mission that never goes near it.
## The edges of a fight: see `setup_cqb`. INF while there is none.
const BOUNDS_CQB := 400.0
const BOUNDS_GROUND := 900.0
const BOUNDS_AIR := 15000.0
## Seconds out of bounds before it is the end of you.
const OOB_GRACE := 10.0
var _cqb_tel_fired := false
var _cqb_fall := -1.0
var _cqb_test := false
var _cqb_view := ""
var _bounds_ground := 0.0
var _bounds_air := 0.0
var _oob_t := 0.0
## Scenery hidden for the match, to be shown again after it.
var _hidden_far: Array = []
# ---------------------------------------------------------- town dressing
## What is standing in the streets of each town that has been visited, by its
## place in the scenery's list. One town, one set, whatever the mission: the
## crane you climbed in a street fight is there when you fly past it.
var _town_sets: Dictionary = {}
var _town_tick := 0.0


func _init(w: World) -> void:
	world = w


## A gunship overhead with the player at its guns. The same aeroplane, the
## same battery and the same station a man in the hold would take -- it is
## simply already in its orbit when he gets there, and it goes home when the
## time is up.
func cqb_gunship(centre: Vector3) -> bool:
	if is_instance_valid(world._cqb_gunship) or not is_instance_valid(world.walker) or not world.on_foot:
		return false
	var j := PlayerJet.new()
	j.setup("ac130")
	j.team = 0
	j.name = "Spooky"
	world.add_child(j)
	# Northbound with the town off the port wing, which is where the guns are.
	j.global_transform = Transform3D(Basis(), centre + Vector3(3000.0, 1500.0, 0.0))
	j.linear_velocity = Vector3(0, 0, -105.0)
	j.gear_down = false
	j.gear_anim = 0.0
	j.throttle = 0.6
	j.power = 0.6
	world._reset_interp.call_deferred(j)
	world._cqb_parked = world.player
	world._cqb_gunship = j
	world._cqb_gun_t = CQB_GUNSHIP_TIME
	world.cqb.set_away(true)
	world._take_hold_station(j)
	# laid on the middle of the fight to begin with; the mouse takes it from there
	world.pod.mode = SensorPod.AREA
	world.pod.area_point = centre
	# His ears go with him. The camera that draws the screen is still the one
	# in the street, so everything was heard from there: the guns he was
	# firing were a distant thump and the shells landing were on top of him.
	var ears := AudioListener3D.new()
	ears.name = "GunnerEars"
	j.add_child(ears)
	ears.make_current()
	Sim.report("AC-130 on station for %d seconds — you have the guns" % int(CQB_GUNSHIP_TIME),
		Sim.Ev.GOOD)
	return true


func _cqb_gunship_done() -> void:
	if is_instance_valid(world._station_walker):
		world._leave_hold_station()
	if is_instance_valid(world._cqb_parked):
		world.player = world._cqb_parked
		world.pod.platform = world.player
		world.map.aircraft = world.player
		if world.audio:
			world.audio.aircraft = world.player
	if is_instance_valid(world._cqb_gunship):
		var ears := world._cqb_gunship.get_node_or_null("GunnerEars") as AudioListener3D
		if ears != null:
			ears.clear_current()
		world._cqb_gunship.queue_free()
	world._cqb_gunship = null
	world._cqb_gun_t = 0.0
	if is_instance_valid(world.cqb):
		world.cqb.set_away(false)
	Sim.report("gunship off station", Sim.Ev.INFO)


## A round from a launcher parked out of town: a rocket battery for a NATO
## side, a cruise missile off a TEL for anyone else. A real vehicle, laid and
## fired the way one driven by a player is -- so the round takes as long to
## arrive as it takes, and comes in from where the launcher actually is.
func cqb_fire_mission(mark: Vector3) -> bool:
	if world._cqb_tel_t > 0.0:
		Sim.report("fire mission: the battery is already working", Sim.Ev.BAD)
		return false
	if not is_instance_valid(world._cqb_tel) or not world._cqb_tel.alive:
		var nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
		world._cqb_tel = world._spawn_tank(Vector3(mark.x + 350.0, 0.0, mark.z + 2700.0), 0.0, 0,
			"m270" if nato else "tel_kalibr")
		world._cqb_tel.name = "Fire support"
	world._cqb_tel.map_target = mark
	world._cqb_tel_t = 45.0
	_cqb_tel_fired = false
	Sim.report("fire mission accepted — %s laying on your mark, keep clear of it"
		% world._cqb_tel.display_name(), Sim.Ev.GOOD)
	return true


func tick_cqb_support(delta: float) -> void:
	if is_instance_valid(world._cqb_gunship):
		world._cqb_gun_t -= delta
		# time up, or he has stepped away from the guns himself
		if world._cqb_gun_t <= 0.0 or not is_instance_valid(world._station_walker):
			_cqb_gunship_done()
	if world._cqb_tel_t > 0.0:
		world._cqb_tel_t -= delta
		if not is_instance_valid(world._cqb_tel):
			world._cqb_tel_t = 0.0
			return
		# Nobody is sitting in it to lay the tubes, so the mission does: the
		# bearing to the mark and the elevation that carries that far.
		if world._cqb_tel.vclass() != "tel" and world._cqb_tel.map_target != Vector3.INF:
			var mk: Vector3 = world._cqb_tel.map_target
			world._cqb_tel.turret_yaw = atan2(mk.x - world._cqb_tel.global_position.x,
				-(mk.z - world._cqb_tel.global_position.z))
			var sol: Dictionary = world._cqb_tel.fire_solution(mk, float(Tank.KINDS[world._cqb_tel.kind]["muzzle"]))
			if not sol.is_empty():
				world._cqb_tel.turret_pitch = float(sol["elev"])
				world._cqb_tel.turret_yaw = float(sol.get("yaw", world._cqb_tel.turret_yaw))
		if world._cqb_tel.lay_error() < 0.04 and world._cqb_tel.fire_main(world):
			if not _cqb_tel_fired:
				_cqb_tel_fired = true
				world._cqb_tel_t = minf(world._cqb_tel_t, 22.0)    # long enough for a ripple to land
		if _cqb_tel_fired and _cqb_test and world._cqb_tel.map_target != Vector3.INF:
			var fall: float = Sim.last_burst.distance_to(world._cqb_tel.map_target)
			if fall < 400.0 and fall != _cqb_fall:
				_cqb_fall = fall
				print("[cqb] fire mission: a round down %.0f m from the mark" % fall)
		if world._cqb_tel_t <= 0.0 and is_instance_valid(world._cqb_tel):
			world._cqb_tel.map_target = Vector3.INF


## Hide every piece of scenery that lies wholly beyond `reach` of the fight:
## towns, road cells, the trees and rocks of the open country. They are drawn
## in batches by area, and a batch with nothing anywhere near the fight is a
## batch nobody in it can see. Hidden rather than freed, so the next mission
## has its country back without building it again.
func _hide_far_scenery(c: Vector3, reach: float) -> void:
	show_far_scenery()
	if not is_instance_valid(world.scenery):
		return
	for n in world.scenery.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		if gi == null or not gi.visible:
			continue
		var wab: AABB = gi.global_transform * gi.get_aabb()
		var near := Vector2(clampf(c.x, wab.position.x, wab.end.x),
			clampf(c.z, wab.position.z, wab.end.z))
		if near.distance_to(Vector2(c.x, c.z)) > reach:
			gi.visible = false
			_hidden_far.append(gi)


func show_far_scenery() -> void:
	for gi in _hidden_far:
		if is_instance_valid(gi):
			(gi as GeometryInstance3D).visible = true
	_hidden_far.clear()


## Who is out of bounds, and for how long. Ten seconds to get back, and then
## the fight ends you. Not while choosing a class, and not from the back of a
## gunship called in over the town, which orbits outside it by design.
func tick_bounds(delta: float) -> void:
	if world._bounds_c == Vector3.INF or not world.running or not is_instance_valid(world.cqb):
		if is_instance_valid(world.hud):
			world.hud.oob_left = -1.0
		return
	var who: Node3D = null
	var r: float = _bounds_ground
	if is_instance_valid(world._station_walker) or world.gunning:
		who = null
	elif world.on_foot and is_instance_valid(world.walker) and not world.walker.dead and not world.walker.sheltered:
		who = world.walker
	elif is_instance_valid(world.tank):
		who = world.tank
	elif is_instance_valid(world.player) and world.player.alive and not world.on_foot and _bounds_air > 0.0:
		who = world.player
		r = _bounds_air
	if who == null:
		_oob_t = 0.0
		world.hud.oob_left = -1.0
		return
	var d: float = Vector2(who.global_position.x - world._bounds_c.x,
		who.global_position.z - world._bounds_c.z).length()
	if d <= r:
		_oob_t = 0.0
		world.hud.oob_left = -1.0
		return
	_oob_t += delta
	world.hud.oob_left = maxf(OOB_GRACE - _oob_t, 0.0)
	if _oob_t >= OOB_GRACE:
		_oob_t = 0.0
		world.hud.oob_left = -1.0
		Sim.report("out of bounds too long", Sim.Ev.BAD)
		if who.has_method("take_hit"):
			who.call("take_hit", 100000.0, null)


func setup_cqb(kind := "cqb") -> void:
	var flying: bool = kind == "arms" and not world._cqb_on_foot and world._drive_kind == ""
	world.player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(150.0, world._apron_y(150.0, -150.0) + world._stance(world.player.spec), -150.0))
	world.player.gear_down = true
	world.player.gear_anim = 1.0
	world.player.throttle = 0.0
	world.player.active = flying
	world.player.set_canopy(false, true)
	world.parked = [world.player]
	world.mode = GameMode.new()
	world.mode.name = "GameMode"
	world.add_child(world.mode)
	world.mode.start(kind)
	world.mode.finished.connect(world._on_mode_finished)
	world.hud.mode = world.mode
	var town := Vector2(-2300.0, -5200.0)
	var town_name := "Kestrel"
	if is_instance_valid(world.scenery) and not world.scenery.sites.is_empty():
		var site: Dictionary = world.scenery.sites[clampi(CqbMatch.town, 0, world.scenery.sites.size() - 1)]
		town = site["c"]
		town_name = String(site.get("name", "town"))
	if kind != "range":
		Sim.report("the fight is in %s" % town_name, Sim.Ev.INFO)
	world.cqb = CqbMatch.new()
	world.cqb.name = "Cqb"
	world.cqb.armour = kind not in ["cqb", "range"]
	world.cqb.range_mode = kind == "range"
	world.cqb.air = kind == "arms"
	if is_instance_valid(world.scenery) and not world.scenery.sites.is_empty():
		world.cqb.site = world.scenery.sites[clampi(CqbMatch.town, 0, world.scenery.sites.size() - 1)]
	world.add_child(world.cqb)
	world.cqb.setup(town, world.mode, world, town_set(clampi(CqbMatch.town, 0, maxi(world.scenery.sites.size() - 1, 0))))
	if is_instance_valid(world.map):
		# Close enough in to see a street fight when the map is opened, on
		# the chart and on him. Setting the chart's zoom alone did nothing:
		# the map opens as the planet, and the chart was only reached by
		# picking a strike. Zooming out from here goes on to the planet.
		world.map.globe = false
		world.map.zoom = 2400.0
		world.map.follow = true
	var c3 := Vector3(world.cqb.centre.x, Sim.height_at(world.cqb.centre.x, world.cqb.centre.y), world.cqb.centre.y)
	# The fight has edges. A street fight is the town, a battle with armour the
	# ground round it, and the aircraft over a combined fight get the sky for
	# fifteen kilometres; past that is out of bounds. The country beyond the
	# edge and a margin is hidden for the match -- nobody is going to stand in
	# it -- and comes back with the next mission.
	world._bounds_c = c3
	_bounds_ground = BOUNDS_CQB if kind == "cqb" else BOUNDS_GROUND
	if kind == "range":
		_bounds_ground = BOUNDS_CQB + FiringRange.LANE_LEN + 450.0
	_bounds_air = BOUNDS_AIR if kind == "arms" else 0.0
	_oob_t = 0.0
	_hide_far_scenery(c3, (_bounds_air + 10000.0) if kind == "arms" else (_bounds_ground + 1500.0))
	if kind not in ["cqb", "range"]:
		_cqb_armour(c3)
	if kind == "arms":
		_cqb_air(c3)
	if flying:
		# In from the south at a height to see the town from, with the fight
		# already going on under the nose.
		world.player.global_transform = Transform3D(Basis(), c3 + Vector3(0.0, 1500.0, 7000.0))
		world.player.linear_velocity = Vector3(0, 0, -world._entry_speed(230.0))
		world.player.gear_down = false
		world.player.gear_anim = 0.0
		world.player.throttle = 0.8
		world.player.power = 0.8
		world._reset_interp.call_deferred(world.player)
		Sim.report("the town is seven kilometres off the nose; armour in the streets, their aircraft above it",
			Sim.Ev.INFO)
		world.player.died.connect(_on_cqb_air_down)
		return
	if world._drive_kind != "":
		var start: Vector3 = _cqb_vehicle_spot(c3, 0)
		world._cqb_parked_at.append(start)
		var mine := world._spawn_tank(start, 0.0, 0, world._drive_kind)
		mine.died.connect(_on_cqb_vehicle_down)
		world._drive_kind = ""
		world._enter_tank(mine)
		Sim.report("you are crewing the %s — the fight is up the street; U to get out and go on foot"
			% mine.display_name(), Sim.Ev.INFO)
		return
	if kind == "range":
		_setup_range(c3)
		return
	world._spawn_walker(world.cqb.spawn_point(0, 0))
	world.walker.yaw = 0.0                       # facing up the street, at them
	world.cqb.set_player(world.walker)
	Sim.report("SPACE vaults low cover and climbs what is taller; F picks up a dropped weapon; F2 for the keys",
		Sim.Ev.INFO)
	cqb_deploy(true)


## The range goes out from the edge of the town, along whichever bearing has
## three hundred metres of open ground in front of it, and the man starts on
## the line facing down it.
func _setup_range(c3: Vector3) -> void:
	if is_instance_valid(world.firing_range):
		world.firing_range.queue_free()
	var site: Array = FiringRange.site_near(c3)
	var at: Vector3 = c3
	var facing := Vector3.FORWARD
	if not site.is_empty():
		at = site[0]
		facing = site[1]
	world.firing_range = FiringRange.new()
	world.firing_range.name = "FiringRange"
	world.firing_range.setup(world, at, facing)
	world.add_child(world.firing_range)
	# the edges are round the range, not the town
	world._bounds_c = at + facing * FiringRange.LANE_LEN * 0.5
	world._spawn_walker(at - facing * 1.5)
	world.walker.yaw = atan2(-facing.x, -facing.z)
	world.cqb.set_player(world.walker)
	cqb_deploy(true)


func town_set(i: int, unhurried := false) -> TownSet:
	if _town_sets.has(i) and is_instance_valid(_town_sets[i]):
		var have: TownSet = _town_sets[i]
		if unhurried or not have.building:
			return have
		# Wanted whole and now, and it is only part built: start it again.
		# The pieces it had put down go with it.
		world.remove_child(have)
		have.free()
		_town_sets.erase(i)
	if not is_instance_valid(world.scenery) or i < 0 or i >= world.scenery.sites.size():
		return null
	var st: Dictionary = world.scenery.sites[i]
	var ts := TownSet.new()
	ts.name = "TownSet %s" % String(st.get("name", str(i)))
	ts.slow = unhurried
	ts.scenery = world.scenery
	world.add_child(ts)
	_town_sets[i] = ts
	# not waited for: with `slow` off it is finished when this returns, and
	# with it on nobody here needs it to be
	ts.build(st["c"], st)
	return ts


## Stand a town's set up as you come to it and take it down once it is well
## behind you. Never more than one in a tick: it is a couple of hundred meshes.
func tick_town_sets(delta: float) -> void:
	_town_tick -= delta
	if _town_tick > 0.0 or not is_instance_valid(world.scenery):
		return
	_town_tick = 1.0
	var eye := world.get_viewport().get_camera_3d()
	if eye == null:
		return
	var at := eye.global_position
	var built := false
	for i in world.scenery.sites.size():
		var c: Vector2 = world.scenery.sites[i]["c"]
		var d: float = Vector2(at.x - c.x, at.z - c.y).length()
		var have: bool = _town_sets.has(i) and is_instance_valid(_town_sets[i])
		if not have and d < 1300.0 and not built and world.running:
			town_set(i, true)
			built = true
		elif have and d > 3600.0:
			var ts: TownSet = _town_sets[i]
			if is_instance_valid(world.cqb) and world.cqb.dressing == ts:
				continue
			ts.queue_free()
			_town_sets.erase(i)


## Put the deploy screen up. The man is already standing at the start line
## behind it; until DEPLOY is pressed he does nothing and nothing can see him.
func cqb_deploy(first: bool) -> void:
	# A harness run has nobody to press the button, and a command line that
	# names a loadout has already chosen.
	if _cqb_test or _cqb_view != "" or CqbMatch.plain or DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(world.walker) or not is_instance_valid(world.cqb):
		return
	if not is_instance_valid(world.deploy_ui):
		world.deploy_ui = DeployMenu.new()
		world.deploy_ui.name = "Deploy"
		world.menu.get_parent().add_child(world.deploy_ui)
		# under the pause menu, never over it
		world.menu.get_parent().move_child(world.deploy_ui, world.menu.get_index())
		world.deploy_ui.deploy.connect(_on_cqb_deploy)
	world.walker.set_physics_process(false)
	world.walker.shelter(true)
	world.cqb.set_away(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Somewhere to look from while choosing. The man is not being ticked, so
	# his camera was never put anywhere: it sat at his own origin, which is the
	# soles of his boots, looking along the ground from inside it -- and what
	# you see from inside the ground is the sea. Up behind the start line
	# instead, looking over the town he is about to go into.
	var mid := Vector3(world.cqb.centre.x, Sim.height_at(world.cqb.centre.x, world.cqb.centre.y), world.cqb.centre.y)
	var back: Vector3 = world.walker.global_position - mid
	back.y = 0.0
	back = back.normalized() if back.length() > 1.0 else Vector3(0, 0, 1)
	var eye: Vector3 = world.walker.global_position + back * 34.0 + Vector3(0, 30.0, 0)
	eye.y = maxf(eye.y, Sim.height_at(eye.x, eye.z) + 12.0)
	world.walker.cam.global_transform = Transform3D(Basis.looking_at(
		(mid + Vector3(0, 6.0, 0) - eye).normalized(), Vector3.UP), eye)
	world.walker.cam.fov = 62.0
	world.walker.cam.current = true
	world.walker.body.visible = true
	world.walker.body.set_head_visible(true)
	var takes: String = {"ground": "ground", "arms": "any"}.get(String(Sim.mission), "none")
	world.deploy_ui.open(takes, first, String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa")))


func _on_cqb_deploy(what: String) -> void:
	if not is_instance_valid(world.cqb):
		return
	# the click on the button is still down
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if what == "foot" or not is_instance_valid(world.walker):
		if is_instance_valid(world.walker):
			var all: Array = CqbMatch.kit_classes()
			world.walker.apply_class(all[clampi(CqbMatch.class_pick, 0, all.size() - 1)])
			world.walker.shelter(false)
			world.walker.set_physics_process(true)
			world.walker.activate()
		world.cqb.set_away(false)
		return
	if what.begins_with("veh:"):
		var at: Vector3 = _cqb_vehicle_spot(Vector3(world.cqb.centre.x,
			Sim.height_at(world.cqb.centre.x, world.cqb.centre.y), world.cqb.centre.y), 0)
		world.cqb.set_away(false)
		world.cqb.set_player(null)
		var mine := world._spawn_tank(at, 0.0, 0, what.substr(4))
		mine.died.connect(_on_cqb_vehicle_down)
		world._enter_tank(mine)
		Sim.report("you are crewing the %s — U to get out and go on foot" % mine.display_name(),
			Sim.Ev.INFO)
		return
	# An aeroplane. Only offered before the match has begun, because taking
	# one means beginning it again with you in the air.
	world._start(what, String(Sim.mission))


## Two vehicles a side on the start lines: a tank and something lighter, in
## each side's own kit. They go for the other end of town and fight what they
## meet on the way.
func _cqb_armour(c3: Vector3) -> void:
	var nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	var ours: Array = ["m1a2", "bradley"] if nato else ["t90", "bmp3"]
	var theirs: Array = ["t90", "bmp3"] if nato else ["m1a2", "bradley"]
	for team in [0, 1]:
		var kit: Array = ours if team == 0 else theirs
		var z_sign: float = 1.0 if team == 0 else -1.0
		for i in kit.size():
			if not Tank.KINDS.has(kit[i]):
				continue
			var at := _cqb_vehicle_spot(c3, team)
			var t := world._spawn_tank(at, 0.0 if team == 0 else PI, team, String(kit[i]))
			world._cqb_parked_at.append(at)
			t.ai = true
			# the match routes it there by the streets; see `_drive_armour`
			t.set_meta("cqb_goal", c3 + Vector3(-30.0 + i * 60.0, 0.0, -z_sign * 110.0))
			t.name = "%s %s" % ["Blue" if team == 0 else "Red", String(kit[i])]
			t.died.connect(_on_cqb_vehicle_down)


## Shot down over the town. The match goes on, so you go on in it: back at
## your side's start line on foot, with the deploy screen up. It used to leave
## you looking at a wreck with nothing to do, which reads as the game having
## stopped.
func _on_cqb_air_down(_who: Variant = null) -> void:
	var fight := world.cqb
	if not is_instance_valid(fight):
		return
	fight.vehicle_down(0, "aircraft")
	await world.get_tree().create_timer(4.0).timeout
	if not is_instance_valid(fight) or fight != world.cqb or not world.running:
		return
	if world.on_foot and is_instance_valid(world.walker):
		# got out in time: he is already on the ground somewhere
		fight.set_player(world.walker)
		return
	world._spawn_walker(fight.spawn_point(0, 0))
	world.walker.yaw = 0.0
	fight.set_player(world.walker)
	world.hud.aircraft = null
	cqb_deploy(false)


## Somewhere on a side's own street to put a vehicle down where nothing on
## the other side's street can see it. They were stood at fixed points, and
## two of those points looked straight at each other down the gaps between
## the buildings: the match opened with the tanks already laid on one another.
func _cqb_vehicle_spot(c3: Vector3, team: int) -> Vector3:
	var z: float = c3.z + (126.0 if team == 0 else -126.0)
	var far_z: float = c3.z - (126.0 if team == 0 else -126.0)
	var best := Vector3(c3.x + 60.0, c3.y, z)
	var best_score := 1e9
	for k in 29:
		# working outwards from a little off the middle, alternating sides
		var x: float = c3.x + (20.0 + floorf(k * 0.5) * 8.0) * (1.0 if k % 2 == 0 else -1.0)
		var p := Vector3(x, Sim.height_at(x, z), z)
		if Obstacles.hit(p + Vector3(0, 1.5, 0), 4.5) >= 0:
			continue
		var crowded := false
		for q in world._cqb_parked_at:
			if (q as Vector3).distance_to(p) < 16.0:
				crowded = true
		if crowded:
			continue
		# how much of the far street can see this spot, and whether anything
		# already parked over there can
		var score := 0.0
		for j in 23:
			var fx: float = c3.x - 110.0 + j * 10.0
			if Obstacles.segment(p + Vector3(0, 2.2, 0),
					Vector3(fx, Sim.height_at(fx, far_z) + 2.2, far_z)) >= 1.0:
				score += 1.0
		for q2 in world._cqb_parked_at:
			if absf((q2 as Vector3).z - z) > 60.0 and Obstacles.segment(p + Vector3(0, 2.2, 0),
					(q2 as Vector3) + Vector3(0, 2.2, 0)) >= 1.0:
				score += 50.0
		score += absf(x - c3.x) * 0.01
		if score < best_score:
			best_score = score
			best = p
	return best


func _on_cqb_vehicle_down(who: Node) -> void:
	if is_instance_valid(world.cqb) and who is Tank:
		world.cqb.vehicle_down((who as Tank).team, (who as Tank).display_name(), who)
	if who == world.tank and is_instance_valid(world.cqb):
		# it was yours: out of the wreck, back to the start line, and choose
		# again what to go in as
		var fight := world.cqb
		await world.get_tree().create_timer(3.0).timeout
		if not is_instance_valid(fight) or fight != world.cqb:
			return
		if is_instance_valid(world.tank):
			world._leave_tank()
		if is_instance_valid(world.walker):
			world.walker.queue_free()
		world._spawn_walker(fight.spawn_point(0, 0))
		world.walker.yaw = 0.0
		fight.set_player(world.walker)
		cqb_deploy(false)


## Both sides' aircraft, moved to wherever the town is. The flights are laid
## out round the home valley; over a town three hundred kilometres away they
## are the same flights, shifted.
func _cqb_air(c3: Vector3) -> void:
	var before: Array = world.get_tree().get_nodes_in_group("hittable")
	world._spawn_threats(2)
	world._spawn_allies()
	var shift: Vector3 = c3 - Vector3(-1084.0, 256.0, -6414.0)
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if before.has(n) or not (n is Aircraft):
			continue
		var a := n as Aircraft
		a.global_position += shift
		if "home" in a:
			a.home += Vector3(shift.x, 0.0, shift.z)
		world._reset_interp.call_deferred(a)
