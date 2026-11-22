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
## `kind` "ac130" is the AC-130 high over the town; "chopper" is the CHOPPER
## GUNNER, an Apache in a low, tight orbit with the gunner on its door gun.
func cqb_gunship(centre: Vector3, kind := "ac130") -> bool:
	if is_instance_valid(world.called_gunship) or not is_instance_valid(world.walker) or not world.on_foot:
		return false
	var j: Aircraft
	if kind == "chopper":
		var h := PlayerHeli.new()
		h.setup("ah64g")
		h.orbit_centre = centre
		j = h
		j.name = "Gunner Six"
	else:
		j = PlayerJet.new()
		(j as PlayerJet).setup("ac130")
		j.name = "Spooky"
	j.team = 0
	world.add_child(j)
	# On every other screen it is this player's aircraft from now on, drawn as
	# what it is, and what it fires goes with it.
	if world.net != null and world.net.active:
		_shared_jet = String(world.net.roster.get(world.net.my_id, {}).get("jet", Sim.selected_jet))
		world.net.set_jet("ah64g" if kind == "chopper" else "ac130")
		j.store_released.connect(func(m: Node) -> void:
			if world.net != null:
				world.net.launches.share(j, m))
	if kind == "chopper":
		# Flown in, not conjured. It was put down already on its circle over
		# the town and the gunner was in its seat the same frame: a gunship
		# out of nowhere. Now it comes up from behind our own end of town,
		# where it can be seen and heard on the way, and the guns are his
		# once it is on station.
		var back := Vector3(0.0, 0.0, 1.0)
		if is_instance_valid(world.walker):
			var off: Vector3 = world.walker.global_position - centre
			off.y = 0.0
			if off.length() > 20.0:
				back = off.normalized()
		var at: Vector3 = centre + back * CHOPPER_IN
		at.y = Sim.height_at(at.x, at.z) + float(j.spec.get("orbit_agl", 230.0))
		j.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), at)
		j.linear_velocity = -back * 45.0
		j.gear_down = false
		j.gear_anim = 0.0
		j.throttle = 0.6
		j.power = 0.6
		var h := j as PlayerHeli
		h.orbit_alt = float(j.spec.get("orbit_agl", 230.0))
		h.orbit_speed = float(j.spec.get("orbit_speed", 22.0))
		h.auto = "inbound"
		world._reset_interp.call_deferred(j)
		world.called_gunship = j
		world.cqb_gun_t = CQB_GUNSHIP_TIME
		_gun_inbound = true
		_gun_centre = centre
		Sim.report("chopper gunner inbound from behind you — on station in about %d seconds" % int(
			(CHOPPER_IN - PlayerHeli.ORBIT_R - 200.0) / 60.0 + 3.0), Sim.Ev.GOOD)
		return true
	else:
		# Northbound with the town off the port wing, which is where the guns are.
		j.global_transform = Transform3D(Basis(), centre + Vector3(3000.0, 1500.0, 0.0))
		j.linear_velocity = Vector3(0, 0, -105.0)
	j.gear_down = false
	j.gear_anim = 0.0
	j.throttle = 0.6
	j.power = 0.6
	world._reset_interp.call_deferred(j)
	world.called_gunship = j
	world.cqb_gun_t = CQB_GUNSHIP_TIME
	_board_gunship(j, centre, kind)
	return true


## How far out the chopper gunner is called up from.
const CHOPPER_IN := 1400.0
## The chopper is on its way in and nobody is on its guns yet.
var _gun_inbound := false
var _gun_centre := Vector3.ZERO

## On the guns: the gunship has arrived, or (the AC-130) is already up there.
func _board_gunship(j: Aircraft, centre: Vector3, kind: String) -> void:
	world.cqb_parked = world.player
	world.cqb.set_away(true)
	world.crew.take_hold_station(j)
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
	Sim.report("%s on station for %d seconds — you have the guns" % [
		"Chopper gunner" if kind == "chopper" else "AC-130", int(CQB_GUNSHIP_TIME)], Sim.Ev.GOOD)


## What this player was flying, as the others saw it, before the gunship.
var _shared_jet := ""

func _cqb_gunship_done() -> void:
	if _shared_jet != "" and world.net != null and world.net.active:
		world.net.set_jet(_shared_jet)
	_shared_jet = ""
	if is_instance_valid(world.crew.station_walker):
		world.crew.leave_hold_station()
	if is_instance_valid(world.cqb_parked):
		world.player = world.cqb_parked
		world.pod.platform = world.player
		world.map.aircraft = world.player
		if world.audio:
			world.audio.aircraft = world.player
	if is_instance_valid(world.called_gunship):
		var ears := world.called_gunship.get_node_or_null("GunnerEars") as AudioListener3D
		if ears != null:
			ears.clear_current()
		# Off station: it flies away and is gone once it is well off, rather
		# than vanishing from over the town between one frame and the next.
		var gs: Aircraft = world.called_gunship
		if "auto" in gs:
			gs.set("auto", "depart")
		else:
			gs.queue_free()
	world.called_gunship = null
	world.cqb_gun_t = 0.0
	if is_instance_valid(world.cqb):
		world.cqb.set_away(false)
	Sim.report("gunship off station", Sim.Ev.INFO)


## A round from a launcher parked out of town: a rocket battery for a NATO
## side, a cruise missile off a TEL for anyone else. A real vehicle, laid and
## fired the way one driven by a player is -- so the round takes as long to
## arrive as it takes, and comes in from where the launcher actually is.
func cqb_fire_mission(mark: Vector3) -> bool:
	if world.cqb_tel_t > 0.0:
		Sim.report("fire mission: the battery is already working", Sim.Ev.BAD)
		return false
	if not is_instance_valid(world.cqb_tel) or not world.cqb_tel.alive:
		var nato: bool = CqbMatch.our_nato()
		world.cqb_tel = world._spawn_tank(Vector3(mark.x + 350.0, 0.0, mark.z + 2700.0), 0.0, 0,
			"m270" if nato else "tel_kalibr")
		world.cqb_tel.name = "Fire support"
	# what it fires is seen on every screen
	if world.net != null:
		world.net.launches.watch(world.cqb_tel)
	world.cqb_tel.map_target = mark
	world.cqb_tel_t = 45.0
	_cqb_tel_fired = false
	Sim.report("fire mission accepted — %s laying on your mark, keep clear of it"
		% world.cqb_tel.display_name(), Sim.Ev.GOOD)
	return true


func tick_cqb_support(delta: float) -> void:
	_tick_air()
	if _gun_inbound:
		var g: Aircraft = world.called_gunship
		if not is_instance_valid(g) or not g.is_alive() or not is_instance_valid(world.cqb):
			# shot down on the way in
			_gun_inbound = false
			world.called_gunship = null
			world.cqb_gun_t = 0.0
			if is_instance_valid(g):
				Sim.report("chopper gunner lost on the way in", Sim.Ev.BAD)
		elif String(g.get("auto")) == "orbit" and world.on_foot \
				and is_instance_valid(world.walker) and not world.walker.dead \
				and not (is_instance_valid(world.deploy_ui) and world.deploy_ui.visible):
			# on station, and he is somewhere he can take the guns from
			_gun_inbound = false
			_board_gunship(g, _gun_centre, "chopper")
		return
	if is_instance_valid(world.called_gunship):
		world.cqb_gun_t -= delta
		# time up, or he has stepped away from the guns himself
		if world.cqb_gun_t <= 0.0 or not is_instance_valid(world.crew.station_walker):
			_cqb_gunship_done()
	if world.cqb_tel_t > 0.0:
		world.cqb_tel_t -= delta
		if not is_instance_valid(world.cqb_tel):
			world.cqb_tel_t = 0.0
			return
		# Nobody is sitting in it to lay the tubes, so the mission does: the
		# bearing to the mark and the elevation that carries that far.
		if world.cqb_tel.vclass() != "tel" and world.cqb_tel.map_target != Vector3.INF:
			var mk: Vector3 = world.cqb_tel.map_target
			world.cqb_tel.turret_yaw = atan2(mk.x - world.cqb_tel.global_position.x,
				-(mk.z - world.cqb_tel.global_position.z))
			var sol: Dictionary = world.cqb_tel.fire_solution(mk, float(VehicleSpec.KINDS[world.cqb_tel.kind]["muzzle"]))
			if not sol.is_empty():
				world.cqb_tel.turret_pitch = float(sol["elev"])
				world.cqb_tel.turret_yaw = float(sol.get("yaw", world.cqb_tel.turret_yaw))
		if world.cqb_tel.lay_error() < 0.04 and world.cqb_tel.fire_main(world):
			if not _cqb_tel_fired:
				_cqb_tel_fired = true
				world.cqb_tel_t = minf(world.cqb_tel_t, 22.0)    # long enough for a ripple to land
		if _cqb_tel_fired and _cqb_test and world.cqb_tel.map_target != Vector3.INF:
			var fall: float = Sim.last_burst.distance_to(world.cqb_tel.map_target)
			if fall < 400.0 and fall != _cqb_fall:
				_cqb_fall = fall
				print("[cqb] fire mission: a round down %.0f m from the mark" % fall)
		if world.cqb_tel_t <= 0.0 and is_instance_valid(world.cqb_tel):
			world.cqb_tel.map_target = Vector3.INF


## Hide every piece of scenery that lies wholly beyond `reach` of the fight:
## towns, road cells, the trees and rocks of the open country. They are drawn
## in batches by area, and a batch with nothing anywhere near the fight is a
## batch nobody in it can see. Hidden rather than freed, so the next mission
## has its country back without building it again.
##
## And the rest of the world with it: the airfields, the other towns' streets,
## and every garrison vehicle, installation and ship -- hidden, and stopped,
## since a tank three hundred kilometres away still thought, aimed and drove
## every tick of a street fight. The terrain stays: it is already drawn coarser
## the further off it is, and without it the town would stand on a plateau in
## an empty sea.
func _hide_far_scenery(c: Vector3, reach: float) -> void:
	show_far_scenery()
	var c2 := Vector2(c.x, c.z)
	if is_instance_valid(world.scenery):
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
	# airfields: a couple of kilometres of pavement, so by their middle with
	# room for that
	for ab in world.bases:
		if not is_instance_valid(ab):
			continue
		if Vector2((ab as Node3D).global_position.x,
				(ab as Node3D).global_position.z).distance_to(c2) > reach + 2500.0:
			_park_far(ab as Node3D)
	# By the town each set is built round. The set's own node stands at the
	# origin with everything in it placed in the world, so measured by that
	# the town being fought over was always "far away" -- and its props and
	# the ground floors of its buildings were hidden while their walls stayed
	# solid: invisible cover, and every hollowed building floating.
	for k in _town_sets:
		if not is_instance_valid(_town_sets[k]):
			continue
		var ts: TownSet = _town_sets[k]
		if ts.centre.distance_to(c2) > reach + 600.0:
			_park_far(ts)
	for grp in ["vehicles", "ground_targets", "ships"]:
		for n2 in world.get_tree().get_nodes_in_group(grp):
			var nd := n2 as Node3D
			if nd == null or nd == world.tank or world.parked.has(nd):
				continue
			if Vector2(nd.global_position.x, nd.global_position.z).distance_to(c2) > reach:
				_park_far(nd)
	print("[bounds] kept %.1f km round the fight: %d scenery batches hidden, %d airfields, towns, vehicles, installations and ships stood down" % [
		reach * 0.001, _hidden_far.size(), _parked_far.size()])

## Out of sight and out of the simulation until the next mission.
func _park_far(n: Node3D) -> void:
	if not n.visible and n.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	_parked_far.append([n, n.visible, n.process_mode])
	n.visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED

## What `_park_far` stopped: [node, was visible, process mode it had].
var _parked_far: Array = []

## How far past the edge of the fight the world is kept: a walk, or for
## aircraft room to turn and come back in.
const KEEP_FOOT := 1000.0
const KEEP_AIR := 15000.0

## A battle over the sectors: everything that matters is within reach of one
## of them, and aircraft fly over all of it.
func hide_beyond_sectors(layout: Array) -> void:
	if layout.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for z in layout:
		var p: Vector3 = z[0]
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	var mid: Vector2 = (lo + hi) * 0.5
	var r: float = mid.distance_to(hi)
	_hide_far_scenery(Vector3(mid.x, 0.0, mid.y), r + KEEP_AIR)

func show_far_scenery() -> void:
	for gi in _hidden_far:
		if is_instance_valid(gi):
			(gi as GeometryInstance3D).visible = true
	_hidden_far.clear()
	for e in _parked_far:
		if not is_instance_valid(e[0]):
			continue
		var n: Node3D = e[0]
		n.visible = bool(e[1])
		n.process_mode = int(e[2]) as Node.ProcessMode
	_parked_far.clear()


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
	if is_instance_valid(world.crew.station_walker) or world.gunning:
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
	_hide_far_scenery(c3, (_bounds_air + KEEP_AIR) if kind == "arms" else (_bounds_ground + KEEP_FOOT))
	if kind not in ["cqb", "range"]:
		_cqb_armour(c3)
	_air_earned = {0: 0, 1: 0}
	_gun_inbound = false
	if kind == "arms":
		# Nobody's air is up when it starts. It used to open with four of
		# theirs -- a pair of fighters and a pair of gunships -- and four of
		# ours, before anyone on the ground had fired a shot; now each side
		# earns its aircraft with kills. See `_tick_air`.
		Sim.report("air is earned: every %d kills a side puts something up" % AIR_EVERY,
			Sim.Ev.INFO)
	if flying:
		# In from the south at a height to see the town from, with the fight
		# already going on under the nose.
		# (from the north on the RED side)
		var sgn: float = 1.0 if NetLink.local_team(0) == 0 else -1.0
		world.player.global_transform = Transform3D(Basis(Vector3.UP, 0.0 if sgn > 0.0 else PI),
			c3 + Vector3(0.0, 1500.0, 7000.0 * sgn))
		world.player.linear_velocity = Vector3(0, 0, -world._entry_speed(230.0) * sgn)
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
		world.cqb_parked_at.append(start)
		var mine := world._spawn_tank(start, 0.0, 0, world._drive_kind)
		mine.died.connect(_on_cqb_vehicle_down)
		world._drive_kind = ""
		world.crew.enter_tank(mine)
		Sim.report("you are crewing the %s — the fight is up the street; U to get out and go on foot"
			% mine.display_name(), Sim.Ev.INFO)
		return
	if kind == "range":
		_setup_range(c3)
		return
	world.crew.spawn_walker(world.cqb.spawn_point(0, 0))
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
	var site: Array = FiringRange.site_near(c3, _range_town_r(), _range_towns())
	var at: Vector3 = c3
	var facing := Vector3.FORWARD
	if not site.is_empty():
		at = site[0]
		facing = site[1]
	world.firing_range = FiringRange.new()
	world.firing_range.name = "FiringRange"
	world.firing_range.setup(world, at, facing)
	world.firing_range.keep_out = _range_towns()
	world.add_child(world.firing_range)
	# the edges are round the range, not the town
	world._bounds_c = at + facing * FiringRange.LANE_LEN * 0.5
	world.crew.spawn_walker(at - facing * 1.5)
	world.walker.yaw = atan2(-facing.x, -facing.z)
	world.cqb.set_player(world.walker)
	# the range is out past the town: keep the country down it drawn
	_hide_far_scenery(world._bounds_c, _bounds_ground + KEEP_FOOT)
	cqb_deploy(true)

## How far the range's town reaches from its middle.
func _range_town_r() -> float:
	return float(world.cqb.site.get("r", 0.0)) if world.cqb != null else 0.0

## Every town on the chart, {c, r}, for the range to stay out of.
func _range_towns() -> Array:
	var out: Array = []
	if is_instance_valid(world.scenery):
		for st in world.scenery.sites:
			out.append({"c": st["c"], "r": float(st.get("r", 0.0))})
	return out


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
		world.deploy_ui.side_picked.connect(_on_side_picked)
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
	var fac := String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa"))
	var online: bool = world.net != null and world.net.active
	if online:
		fac = world.net.side_faction(fac)
	elif CqbMatch.our_nato() != (JetSpec.bloc_of(Sim.selected_jet) == "nato"):
		# RED offline: the other bloc's vehicles first
		fac = "usa" if CqbMatch.our_nato() else "russia"
	world.deploy_ui.open(takes, first, fac,
		world.cqb.streaks.points if takes != "none" else -1)
	# Which side. Arriving in the match it is the first thing asked, in a
	# session or not; the range has nobody to be on a side against.
	var mine: int = world.net.abs_side if online else CqbMatch.offline_side
	var counts: Array = world.net.side_counts() if online else []
	if world.cqb.range_mode:
		world.deploy_ui.show_sides(-1, [])
	elif first and not CqbMatch.side_settled:
		world.deploy_ui.ask_side(mine, counts, _side_names())
	else:
		world.deploy_ui.show_sides(mine, counts, _side_names())
	CqbMatch.side_settled = false

## What each side fights as, for the buttons: BLUE is the hangar's bloc.
func _side_names() -> Array:
	var blue_nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	return ["NATO" if blue_nato else "EASTERN BLOC", "EASTERN BLOC" if blue_nato else "NATO"]


## Joined the other side on the deploy screen: announced, and the man moved
## to that side's end of town before he goes in.
func _on_side_picked(sd: int) -> void:
	if not is_instance_valid(world.cqb):
		return
	if world.net == null or not world.net.active:
		# Offline the other side is the other bloc's troops, armour and air,
		# all of it put down as the match was set up: so it starts again.
		if sd == CqbMatch.offline_side:
			return
		CqbMatch.offline_side = sd
		CqbMatch.side_settled = true
		Sim.report("you are %s — starting again on that side" % ("BLUE" if sd == 0 else "RED"), Sim.Ev.INFO)
		world.deploy_ui.visible = false
		# this mode, on foot, from the top: not whatever the main menu has
		# selected, which need not be the match being played
		world._start.call_deferred("foot", String(Sim.mission))
		return
	if sd == world.net.abs_side:
		return
	world.net.set_side(sd)
	Sim.report("you are %s" % ("BLUE" if sd == 0 else "RED"), Sim.Ev.INFO)
	if is_instance_valid(world.walker):
		world.walker.global_position = world.cqb.spawn_point(0, 0)
		world.walker.yaw = 0.0 if NetLink.local_team(0) == 0 else PI
	cqb_deploy(false)

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
	var cost: int = Killstreaks.ride_cost(what)
	if cost > world.cqb.streaks.points:
		# not earned yet: on foot instead
		_on_cqb_deploy("foot")
		return
	world.cqb.streaks.points -= cost
	if cost > 0:
		Sim.report("%d points spent — %d left" % [cost, world.cqb.streaks.points], Sim.Ev.INFO)
	if what.begins_with("veh:"):
		var at: Vector3 = _cqb_vehicle_spot(Vector3(world.cqb.centre.x,
			Sim.height_at(world.cqb.centre.x, world.cqb.centre.y), world.cqb.centre.y), 0)
		world.cqb.set_away(false)
		world.cqb.set_player(null)
		var mine := world._spawn_tank(at, 0.0, 0, what.substr(4))
		mine.died.connect(_on_cqb_vehicle_down)
		world.crew.enter_tank(mine)
		Sim.report("you are crewing the %s — U to get out and go on foot" % mine.display_name(),
			Sim.Ev.INFO)
		return
	# An aeroplane, earned: into the air over the town, the match going on.
	cqb_fly(what)


## Into the air in the middle of a combined fight, in something earned on the
## deploy screen. It used to be offered only before the match had begun,
## because taking one restarted the match with you in the air.
func cqb_fly(id: String) -> void:
	var fight: CqbMatch = world.cqb
	if not is_instance_valid(fight):
		return
	var c3 := Vector3(fight.centre.x, Sim.height_at(fight.centre.x, fight.centre.y), fight.centre.y)
	var old: Aircraft = world.player
	if is_instance_valid(old) and old != world.called_gunship:
		world.parked.erase(old)
		old.queue_free()
	if is_instance_valid(world.walker):
		world.walker.queue_free()
	world.walker = null
	world.on_foot = false
	world.hud.walker = null
	fight.set_player(null)
	fight.set_away(false)
	world._make_player(id)
	var p: Aircraft = world.player
	p.active = true
	var rotary: bool = JetSpec.is_rotary(id)
	var sgn: float = 1.0 if NetLink.local_team(0) == 0 else -1.0
	p.global_transform = Transform3D(Basis(Vector3.UP, 0.0 if sgn > 0.0 else PI),
		c3 + (Vector3(0.0, 250.0, 1800.0 * sgn) if rotary else Vector3(0.0, 1500.0, 7000.0 * sgn)))
	p.linear_velocity = Vector3(0, 0, -(30.0 if rotary else world._entry_speed(230.0)) * sgn)
	p.gear_down = false
	p.gear_anim = 0.0
	p.throttle = 0.6 if rotary else 0.8
	p.power = p.throttle
	world._reset_interp.call_deferred(p)
	p.died.connect(_on_cqb_air_down)
	if world.audio:
		world.audio.aircraft = p
	Sim.report("%s — the town is off the nose" % String(p.spec.get("name", "")), Sim.Ev.INFO)


## Two vehicles a side on the start lines: a tank and something lighter, in
## each side's own kit. They go for the other end of town and fight what they
## meet on the way.
func _cqb_armour(c3: Vector3) -> void:
	# the host drives the armour; a client is sent pictures of it
	if NetLink.mirroring():
		return
	var nato: bool = CqbMatch.our_nato()
	var ours: Array = ["m1a2", "bradley"] if nato else ["t90", "bmp3"]
	var theirs: Array = ["t90", "bmp3"] if nato else ["m1a2", "bradley"]
	for team in [0, 1]:
		var kit: Array = ours if team == 0 else theirs
		var z_sign: float = 1.0 if team == 0 else -1.0
		for i in kit.size():
			if not VehicleSpec.KINDS.has(kit[i]):
				continue
			var at := _cqb_vehicle_spot(c3, team)
			var t := world._spawn_tank(at, 0.0 if team == 0 else PI, team, String(kit[i]))
			world.cqb_parked_at.append(at)
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
	world.crew.spawn_walker(fight.spawn_point(0, 0))
	world.walker.yaw = 0.0
	fight.set_player(world.walker)
	world.hud.aircraft = null
	cqb_deploy(false)


## Somewhere on a side's own street to put a vehicle down where nothing on
## the other side's street can see it. They were stood at fixed points, and
## two of those points looked straight at each other down the gaps between
## the buildings: the match opened with the tanks already laid on one another.
func _cqb_vehicle_spot(c3: Vector3, team: int) -> Vector3:
	var end: float = 126.0 if NetLink.local_team(team) == 0 else -126.0
	var z: float = c3.z + end
	var far_z: float = c3.z - end
	var best := Vector3(c3.x + 60.0, c3.y, z)
	var best_score := 1e9
	for k in 29:
		# working outwards from a little off the middle, alternating sides
		var x: float = c3.x + (20.0 + floorf(k * 0.5) * 8.0) * (1.0 if k % 2 == 0 else -1.0)
		var p := Vector3(x, Sim.height_at(x, z), z)
		if Obstacles.hit(p + Vector3(0, 1.5, 0), 4.5) >= 0:
			continue
		var crowded := false
		for q in world.cqb_parked_at:
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
		for q2 in world.cqb_parked_at:
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
			world.crew.leave_tank()
		if is_instance_valid(world.walker):
			world.walker.queue_free()
		world.crew.spawn_walker(fight.spawn_point(0, 0))
		world.walker.yaw = 0.0
		fight.set_player(world.walker)
		cqb_deploy(false)


## Air over a combined fight, earned. Each side puts an aircraft up for every
## `AIR_EVERY` kills it makes -- a helicopter, then a fighter, in turn -- with no
## more than `AIR_MAX` of its own up at once.
const AIR_EVERY := 12
const AIR_MAX := 2
var _air_earned := {0: 0, 1: 0}
var _air_up := {0: [], 1: []}

func _tick_air() -> void:
	var fight: CqbMatch = world.cqb
	if not is_instance_valid(fight) or not fight.air or NetLink.mirroring() \
			or not is_instance_valid(world.mode) or not world.mode.running:
		return
	for team in [0, 1]:
		var due: int = int(int(world.mode.kills.get(team, 0)) / float(AIR_EVERY))
		if due <= int(_air_earned[team]):
			continue
		var up: Array = []
		for a in _air_up[team]:
			if is_instance_valid(a) and a.is_alive():
				up.append(a)
		_air_up[team] = up
		if up.size() >= AIR_MAX:
			continue
		_air_earned[team] = due
		up.append(_air_one(team, due, fight))

func _air_one(team: int, n: int, fight: CqbMatch) -> Aircraft:
	var c3 := Vector3(fight.centre.x, Sim.height_at(fight.centre.x, fight.centre.y), fight.centre.y)
	var nato: bool = CqbMatch.our_nato() == (team == 0)
	# from behind its own side's end of the town
	var back := Vector3(0.0, 0.0, 1.0 if team == 0 else -1.0)
	var a: Aircraft
	if n % 2 == 1:
		var rotary: Array = World.NATO_HELIS if nato else World.OPFOR_HELIS
		var h := AIHeli.new()
		h.setup(rotary[n % rotary.size()])
		h.arena = fight
		h.home = c3
		h.station_alt = 150.0
		a = h
	else:
		var jets: Array = World.NATO_JETS if nato else World.OPFOR_JETS
		var b := AIPlane.new()
		b.setup(jets[n % jets.size()])
		b.home = Vector3(c3.x, 0.0, c3.z)
		b.patrol_r = 2500.0
		a = b
	a.team = team
	a.name = "%s %s" % ["Blue" if team == 0 else "Red", String(a.spec.get("name", "air"))]
	world.add_child(a)
	var fast: bool = a is AIPlane
	var at: Vector3 = c3 + back * (6000.0 if fast else 1800.0) + Vector3(0, 1800.0 if fast else 200.0, 0)
	a.global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), at)
	a.linear_velocity = -back * (220.0 if fast else 30.0)
	world._reset_interp.call_deferred(a)
	a.died.connect(_on_cqb_air_lost.bind(team))
	Sim.report("%s %s is up" % ["our" if team == 0 else "their", String(a.spec.get("name", "aircraft"))],
		Sim.Ev.GOOD if team == 0 else Sim.Ev.BAD)
	return a

func _on_cqb_air_lost(_who: Variant, team: int) -> void:
	if is_instance_valid(world.cqb):
		world.cqb.vehicle_down(team, "aircraft")


## Both sides' aircraft, moved to wherever the town is. The flights are laid
## out round the home valley; over a town three hundred kilometres away they
## are the same flights, shifted.
func _cqb_air(c3: Vector3) -> void:
	var before: Array = world.get_tree().get_nodes_in_group("hittable")
	world.missions.spawn_threats(2)
	world.missions._spawn_allies()
	var shift: Vector3 = c3 - Vector3(-1084.0, 256.0, -6414.0)
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if before.has(n) or not (n is Aircraft):
			continue
		var a := n as Aircraft
		a.global_position += shift
		if "home" in a:
			a.home += Vector3(shift.x, 0.0, shift.z)
		world._reset_interp.call_deferred(a)
