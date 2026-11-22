class_name MatchSession
extends RefCounted
## Multiplayer sessions and getting back into a running match: hosting into
## a lobby, joining and starting whatever the host launches, choosing what to be
## in on arrival, the REDEPLOY offer after going down, and where each mode puts
## an aircraft or a man to start.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

# ------------------------------------------------------------------ redeploy
## Down, in a mode that is not a street fight: after a moment the hangar comes
## up to choose what to go back in as, and REDEPLOY puts you back into the same
## match. There was nothing at all -- a joiner who was shot down could not
## restart a match that was not his, and sat looking at his wreck.
var _redeploy_wait := false

## The choice replaces what he is in now, rather than following its loss: see
## `choose_in_match`.
var _redeploy_replace := false

func _init(w: World) -> void:
	world = w

## On foot on the flight line: the aeroplane parked on the apron, canopy up,
## and the man beside it, free to walk to it or to any other.
func foot_at_field() -> void:
	if not is_instance_valid(world.player):
		return
	# one aeroplane on the spot: the one left there by the last time
	var spot := Vector3(150.0, 0.0, -150.0)
	for j in world.parked.duplicate():
		if is_instance_valid(j) and j != world.player and (j as Node3D).global_position.distance_to(
				Vector3(spot.x, (j as Node3D).global_position.y, spot.z)) < 15.0:
			world.parked.erase(j)
			(j as Node).queue_free()
	world.player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(150.0, world._apron_y(150.0, -150.0) + world._stance(world.player.spec), -150.0))
	world.player.linear_velocity = Vector3.ZERO
	world.player.angular_velocity = Vector3.ZERO
	world.player.gear_down = true
	world.player.gear_anim = 1.0
	world.player.throttle = 0.0
	world.player.power = 0.0
	world.player.active = false
	world.player.set_canopy(true, true)
	world.player.add_to_group("boardable")
	if not world.parked.has(world.player):
		world.parked.append(world.player)
	world._reset_interp(world.player)
	var nose: float = maxf(absf(world.player.bounds.position.z), absf(world.player.bounds.end.z))
	world.crew.spawn_walker(world.player.global_transform * Vector3(0.0, 0.0, -(nose + 5.0)))
	# Not stepped out to a spawn slot afterwards: that moved the aeroplane a
	# hundred metres from the man standing beside it. A parked aeroplane is
	# only on its own player's screen, so there is nothing for it to collide
	# with.
	world._slot_home = Vector3(1e9, 0, 0)

func offer_redeploy() -> void:
	if _redeploy_wait or is_instance_valid(world.cqb) or not world.running:
		return
	_redeploy_wait = true
	var gen := world._mission_started
	await world.get_tree().create_timer(3.5).timeout
	_redeploy_wait = false
	if not world.running or gen != world._mission_started or not world.is_inside_tree():
		return
	# still down? something else may already have put him back
	var down: bool = (world.on_foot and is_instance_valid(world.walker) and world.walker.dead) \
		or (is_instance_valid(world.tank) and not world.tank.alive) \
		or (not world.on_foot and not is_instance_valid(world.tank) and (not is_instance_valid(world.player)
			or not world.player.is_alive()))
	if not down:
		return
	Sim.report("choose what to go back in as, and REDEPLOY", Sim.Ev.INFO)
	world.menu.set_redeploy(true)
	world.menu.visible = true
	Sim.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func on_crew_down(who: Node) -> void:
	if who == world.tank:
		offer_redeploy()

## LAUNCH, or REDEPLOY when the hangar is up for that.
func on_launch(id: String, mission: String) -> void:
	if world.menu.redeploy:
		redeploy(id)
	else:
		world._start(id, mission)

## Back into the match that is running, as `id`: an aeroplane at this mode's
## start, a vehicle at the park, or on foot on the flight line.
func redeploy(id: String) -> void:
	# chosen in place of what he was in, rather than after losing it: that
	# one goes, rather than standing about on the runway
	if _redeploy_replace and is_instance_valid(world.player) and world.player.is_alive() \
			and not world.parked.has(world.player):
		world.player.queue_free()
		world.player = null
	_redeploy_replace = false
	world.menu.set_redeploy(false)
	world.menu.visible = false
	Sim.menu_open = false
	Sim.block_until_released([&"fire", &"gun"])
	if is_instance_valid(world.tank):
		world.tank.mount(false)
	world.tank = null
	world.hud.tank = null
	if is_instance_valid(world.walker) and not is_instance_valid(world.crew.station_walker):
		world.walker.queue_free()
	world.walker = null
	world.hud.walker = null
	world.on_foot = false
	var mission := String(Sim.mission)
	var jet := id
	if id == "foot" or id.begins_with("veh:") or id.begins_with("sea:"):
		jet = String(Sim.selected_jet) if not String(Sim.selected_jet).contains(":") else "f16"
	# the wreck stays where it fell; this is a new aeroplane
	if is_instance_valid(world.player) and world.player.is_alive() and not world.parked.has(world.player):
		world.parked.append(world.player)
	world.player = null
	world._make_player(jet)
	world.player.died.connect(func(_w): offer_redeploy())
	if id == "foot" or id.begins_with("veh:") or id.begins_with("sea:"):
		foot_at_field()
		if id.begins_with("veh:"):
			var b: Vector3 = world.base.global_position if is_instance_valid(world.base) else Vector3.ZERO
			var t := world._spawn_tank(Vector3(b.x + 196.0, 0.0, b.z - 470.0), deg_to_rad(-90.0), 0,
				id.substr(4))
			world.crew.enter_tank(t)
	else:
		place_at_start(mission)
		world._slot_home = Vector3.INF
	world._slot_said = -1
	world._mission_started = Time.get_ticks_msec()
	offset_for_peer.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sim.report("back in", Sim.Ev.GOOD)

## Where this mode starts an aeroplane: on the runway, on the approach, or in
## the air over the fight.
func place_at_start(mission: String) -> void:
	var gear_h := 0.0
	for g in world.player.spec["gear"]:
		gear_h = maxf(gear_h, absf(g["pos"].y) + g["r"])
	if mission in ["takeoff", "ramp", "sandbox"]:
		world.player.global_transform = Transform3D(Basis(),
			Vector3(0, world._apron_y(0.0, 1380.0) + gear_h + 0.02, 1380.0))
		world.player.gear_down = true
		world.player.gear_anim = 1.0
		world.player.throttle = 0.0
		world.player.flaps = 1.0
		world.player.flap_anim = 1.0
		world.player.set_canopy(false, true)
	elif mission == "landing":
		var z := Airbase.AIM_Z + 12000.0
		world.player.global_transform = Transform3D(Basis(), Vector3(140.0, world._apron_y(140.0, z) + 640.0, z))
		world.player.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-1.2), 0.0)
		world.player.linear_velocity = -world.player.global_transform.basis.z * world._entry_speed(148.0)
		world.player.gear_down = true
		world.player.gear_anim = 1.0
		world.player.flaps = 1.0
		world.player.throttle = 0.42
		world.player.power = 0.42
	else:
		var at := Vector3(-600.0, 2400.0, 7000.0)
		var yaw := deg_to_rad(-4.0)
		if mission in ["conquest", "rush", "warlords", "tdm", "ffa", "combat"]:
			at = Vector3(-500.0, 3600.0, 7200.0)
			if NetLink.local_team(0) == 1:
				at = Vector3(500.0, 3700.0, -12500.0)
				yaw = PI + deg_to_rad(4.0)
		world.player.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
		world.player.linear_velocity = -world.player.global_transform.basis.z * world._entry_speed(240.0)
		world.player.gear_down = false
		world.player.gear_anim = 0.0
		world.player.throttle = 0.8
		world.player.power = 0.8
	world._reset_interp(world.player)

func on_lobby_mission(m: String) -> void:
	if world.net != null:
		world.net.announce_lobby(m)

func offset_for_peer() -> void:
	if world.net == null or not world.net.active or not is_instance_valid(world.player):
		return
	if world.net.my_id == 1 and not world.net.is_host:
		return                          # the connection has not landed yet
	# Recomputed on every roster change, not latched on the first. A slot is a
	# rank among the peers present, and the first roster a joiner sees contains
	# only itself — so all three clients decided they were number one and piled
	# onto the same offset. It is always applied to the *original* start point
	# rather than to wherever the aeroplane is now, so refining the answer moves
	# it to the right place instead of shifting it again.
	if world._slot_home != Vector3.INF and world._slot_home.x >= 1e8:
		return                          # on foot on the flight line: see `_foot_at_field`
	if world._slot_home == Vector3.INF:
		world._slot_home = world.player.global_position
	if Time.get_ticks_msec() - world._mission_started > 15000:
		return                          # the roster has settled; leave it alone
	var slot: int = world.net.spawn_slot()
	var off: Vector3 = world.net.spawn_offset()
	if off == Vector3.ZERO:
		return
	# On the ground by where it is, not by `on_ground`: an aeroplane made this
	# frame says it is on the ground until its first physics step, so every
	# joiner in an airborne start -- free flight, a battle, an approach -- was
	# set down on the terrain at flying speed and destroyed before the first
	# frame was drawn. The host, slot 0, is never moved, so only joiners met
	# it: two players in a session who could not see each other.
	var agl: float = world._slot_home.y - Sim.height_at(world._slot_home.x, world._slot_home.z)
	if agl < 30.0 or Sim.mission == "ramp" or Sim.mission == "takeoff":
		# on the ground, step along the apron and keep the wheels on it
		var p := world._slot_home + Vector3(off.x, 0.0, off.z)
		p.y = Sim.height_at(p.x, p.z) + world._stance(world.player.spec) + 0.02
		world.player.global_position = p
	else:
		world.player.global_position = world._slot_home + off
	world._reset_interp(world.player)
	if slot != world._slot_said:
		world._slot_said = slot
		Sim.report("spawn slot %d" % slot, Sim.Ev.INFO)

func host_game(jet_id: String, _address: String) -> void:
	Sim.selected_jet = jet_id
	if world.net.host(jet_id):
		# Into a lobby, not into a match. HOST started whatever mode happened
		# to be selected the moment it was pressed; now the host stays in the
		# hangar, people join it there, and LAUNCH starts the match for all of
		# them. Hosting from a match already running keeps it running.
		world.net.announce_lobby(String(world.menu.mission_id))
		if world.running:
			world.net.running_mission = String(Sim.mission)
		else:
			Sim.report("hosting — choose a mode and press LAUNCH when everyone is in", Sim.Ev.GOOD)

## The host started a match: this client starts the same one, in whatever it
## picked in the hangar -- its own aeroplane, a vehicle or on foot.
func start_from_host(mission: String) -> void:
	var id := String(world.menu.jet_id) if is_instance_valid(world.menu) else ""
	if id == "":
		id = String(Sim.selected_jet)
	world._start(id, mission)
	# He has not chosen anything: the host chose the mode and the match began
	# with whatever happened to be highlighted in his hangar -- a fighter, for
	# anyone who had not touched it. The hangar comes up to choose in, the
	# aeroplane held where it is until he has, then replaced by his choice.
	# (A street fight asks on its own deploy screen.)
	if mission not in ["cqb", "ground", "arms", "range"]:
		choose_in_match("DEPLOY")

## The hangar over a running match, to choose what to be in: on arriving in a
## match the host started, and for a joiner who asks to change mid-match. What
## he is in now is held still and goes when the choice is made.
func choose_in_match(label: String) -> void:
	_redeploy_replace = true
	if is_instance_valid(world.player) and not world.on_foot and not is_instance_valid(world.tank):
		world.player.set_meta("choosing", true)
		world.player.freeze = true
	world.menu.set_redeploy(true, label)
	world.menu.visible = true
	Sim.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Let go of an aeroplane held while choosing, if the choice was not made.
func unhold_choice() -> void:
	if is_instance_valid(world.player) and world.player.has_meta("choosing"):
		world.player.remove_meta("choosing")
		world.player.freeze = false
	_redeploy_replace = false
	if world.menu.redeploy:
		world.menu.set_redeploy(false)

func join_game(jet_id: String, address: String) -> void:
	Sim.selected_jet = jet_id
	if world.net.join(address, jet_id):
		# Waits in the hangar for the host's match: it is started as soon as
		# the host says what it is running (`NetLink.net_match`). A placeholder
		# free flight was started here, which put the joiner in the air over
		# nothing until the host got round to launching.
		Sim.report("joined — waiting in the hangar for the host to launch", Sim.Ev.INFO)
