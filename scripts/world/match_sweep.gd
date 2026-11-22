class_name MatchSweep
extends RefCounted
## Clearing a match away before the next one: what was being crewed let go
## of, the aircraft, the mode and the street fight freed, the fleet refitted, and
## everything else the match put into the world swept up.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

## Everything put straight into the world while a match is running: rounds in
## flight, shells, bombs, warheads and their mushroom clouds, wrecks, debris,
## smoke, the men of a street fight and whatever they called in. Each kind used
## to be tidied up by its own line in `MatchSweep.clear_mission`, and every kind that
## nobody had written a line for -- a nuke still climbing, a burst of tracer, a
## gunship called in over the town -- carried on into the next match. Recording
## them as they arrive means a new kind is swept up without anyone having to
## remember to.
var _spawned: Array = []

## Print what each restart sweeps up: --sweeplog.
var verbose := false

func _init(w: World) -> void:
	world = w

func note_child(n: Node) -> void:
	if world.running and n.get_parent() == world:
		_spawned.append(n)

## Not the match's to sweep: other players and what the network layer built for
## them, the fleet and the carrier (furniture, refitted instead), and the
## camera, which is made once on the first launch and kept.
func _keeps(n: Node) -> bool:
	if n == world.cam or n == world.menu_cam or n == world.cine_cam:
		return true
	# a town's dressing is built once and kept for every visit: see
	# `StreetFight.town_set`
	if n is TownSet:
		return true
	# A strike wave's shipping is the match's; the standing fleet is not.
	if n.is_in_group(&"ships") and not n.has_meta("strike"):
		return true
	for g in [&"remote", &"carrier", &"persistent"]:
		if n.is_in_group(g):
			return true
	if world.net != null and n == world.net:
		return true
	if world.net != null and (world.net.ghosts.values().has(n) or world.net.foot_ghosts.values().has(n)):
		return true
	return false

func sweep() -> void:
	var swept := {}
	for n in _spawned:
		if not is_instance_valid(n) or n.is_queued_for_deletion() or _keeps(n):
			continue
		var k: String = n.get_class()
		if n.get_script() != null:
			k = n.get_script().get_global_name()
			if k == "":
				var props: Array = []
				for pr in n.get_script().get_script_property_list():
					if props.size() < 2 and not String(pr["name"]).contains(" "):
						props.append(String(pr["name"]))
				k = "(%s)" % ",".join(props)
		swept[k] = int(swept.get(k, 0)) + 1
		n.queue_free()
	_spawned.clear()
	# Anything parented somewhere else that still belongs to the match.
	for n in world.get_tree().get_nodes_in_group(&"transient"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	if verbose and not swept.is_empty():
		print("[sweep] %s" % str(swept))

func clear_mission() -> void:
	# The rocket and its pad go with the mission, and time goes back to normal.
	if is_instance_valid(world.rocket):
		world.rocket.mount(false)
		world.rocket.queue_free()
	world.rocket = null
	if is_instance_valid(world.hud):
		world.hud.rocket = null
	if is_instance_valid(world.missions.pad):
		world.missions.pad.queue_free()
	world.missions.pad = null
	Sim.space_warp = 1.0
	Sim.space_rate = 1.0
	Sim.view_scale = 1.0
	Sim.view_moon = Vector3.INF
	# and nothing called down in the last match is still marked on the map
	if is_instance_valid(world.map):
		world.map.pick_marks.clear()
	# the next mission decides for itself whether the range is a safe one
	Sim.no_air_threat = false
	if is_instance_valid(world.firing_range):
		world.firing_range.queue_free()
	world.firing_range = null
	world.on_foot = false
	if is_instance_valid(world.walker):
		world.walker.queue_free()
	world.walker = null
	# Let go of anything being crewed. A ship is world furniture and survives
	# the mission, so nothing ever dismounted you from one — restart and choose
	# an aeroplane and you were still stood on the submarine's bridge, because
	# `ship` was never cleared and every page still drew from it.
	if is_instance_valid(world.ship):
		world.ship.mount(false)
		if is_instance_valid(world.ship.cam):
			world.ship.cam.current = false
	world.ship = null
	world.hud.ship = null
	if is_instance_valid(world.map):
		world.map.ship = null
	if is_instance_valid(world.tank):
		world.tank.mount(false)
	world.tank = null
	world.hud.tank = null
	if is_instance_valid(world.map):
		world.map.tank = null
	if world.pod != null:
		world.stow_pod()
	if is_instance_valid(world.cam):
		world.cam.weapon_cam = null
		world.cam.current = true
	world._cam_was_ship = false
	world._cam_was_tank = false
	for j in world.parked:
		if is_instance_valid(j) and j != world.player:
			j.queue_free()
	world.parked.clear()
	for n in world.get_tree().get_nodes_in_group("hittable"):
		# Never sweep up other players: they are owned by the network layer, and
		# freeing them leaves dangling ghost entries that break the sync loop.
		# Shipping and the carrier are world furniture -- built once, outliving
		# the mission, so not the mission's to delete.
		if is_instance_valid(n) and not n.is_in_group("remote") \
				and not n.is_in_group("ships") and not n.is_in_group("carrier"):
			n.queue_free()
	# The fleet is furniture, but it is not *state*: a hull you sank stayed on
	# the bottom across a restart, so starting again handed you a sea already
	# won and only the aeroplane was new. Put them back the way they began.
	for sh in world.get_tree().get_nodes_in_group("ships"):
		var v := sh as Ship
		if v == null or v.is_in_group("remote"):
			continue
		v.refit()
	# The aeroplane you were flying goes with the mission. Skipping it here left
	# it standing on the apron after a restart, so the next mission parked a
	# fresh one straight through it.
	if is_instance_valid(world.player):
		world.player.queue_free()
	world.player = null
	world.hud.aircraft = null
	if is_instance_valid(world.veil):
		world.veil.aircraft = null
	for n in world.get_tree().get_nodes_in_group("missiles"):
		if is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(world.player):
		world.player.queue_free()
	world._landing_watch = false
	world._stop_t = 0.0
	if world.gunning:
		world.gunning = false
		world.pod.set_fullscreen(false)
	world.crew.station_walker = null
	if is_instance_valid(world.mode):
		world.mode.queue_free()
	world.mode = null
	world.hud.mode = null
	if is_instance_valid(world.cqb):
		world.cqb.queue_free()
	world.cqb = null
	if is_instance_valid(world.deploy_ui):
		world.deploy_ui.queue_free()
	world.deploy_ui = null
	world.called_gunship = null
	world.cqb_parked = null
	world.cqb_parked_at.clear()
	world.cqb_tel = null
	world.cqb_tel_t = 0.0
	world.cqb_gun_t = 0.0
	for z in world.get_tree().get_nodes_in_group("zones"):
		if is_instance_valid(z):
			z.queue_free()
	if world.boarding:
		world.crew.end_boarding()
	sweep()
	# What the last match left set rather than standing: a jammer or an EMP
	# still counting down, the range's slow motion, and a nuclear flash still
	# whiting the screen out as the next match opened.
	for tm in Killstreaks.jammed:
		Killstreaks.jammed[tm] = 0.0
	for tm in Killstreaks.emp_t:
		Killstreaks.emp_t[tm] = 0.0
	Engine.time_scale = 1.0
	world.vision_fx.clear_flash()
	if world.net != null and world.net.active:
		world.net.match_reset()
