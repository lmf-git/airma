class_name MissionSetup
extends RefCounted
## Setting up each mission's own pieces once the world is built: the battle
## and its allied flights, a strike, the carrier approach, the ramp start and its
## line of airframes, a launch from the pad, the strategic strike, forces sent
## abroad, and the opposition sent up against you.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World
var _flight_lead: AIPlane = null
var _cas_lead: AIPlane = null

## Our own flight and a pair of gunships, flying our side's hardware. They find
## their own fights the same way the opposition does, by team.
const ALLY_WINGS := 3

# ------------------------------------------------------------------ the rocket
var pad: Node3D = null
var _apron_count := 0

## Which nationalities the search could not find ground for. A map generated
## from noise does not guarantee every country holds territory within reach of
## this particular airfield, and saying so is better than quietly dropping them.
var _abroad_missed: Dictionary = {}

func _init(w: World) -> void:
	world = w

# ------------------------------------------------------------------ on foot
## Ramp start: the flown jet is parked and inert, and you begin beside it on
## foot with a line of other airframes to choose from.
## Battle modes: airborne start over the contested sectors, with the mode
## controller laying out objectives and keeping score.
func setup_battle(id: String) -> void:
	world.player.global_transform = Transform3D(Basis(), Vector3(-500.0, 3600.0, 7200.0))
	world.player.rotation.y = deg_to_rad(-4.0)
	if NetLink.local_team(0) == 1:
		# RED, in a session: from behind the far side's sectors, heading south
		# at the BLUE side coming up from the field
		world.player.global_transform = Transform3D(Basis(), Vector3(500.0, 3700.0, -12500.0))
		world.player.rotation.y = PI + deg_to_rad(4.0)
	world.player.linear_velocity = -world.player.global_transform.basis.z * world._entry_speed(250.0)
	world.player.gear_down = false
	world.player.gear_anim = 0.0
	world.player.throttle = 0.85
	world.player.power = 0.85
	world.mode = GameMode.new()
	world.mode.name = "GameMode"
	world.add_child(world.mode)
	world.mode.start(id)
	world.mode.finished.connect(world._on_mode_finished)
	world.hud.mode = world.mode
	# the war is fought over the sectors; the rest of the world waits
	world.street_fight.hide_beyond_sectors(world.mode._layout)
	var wings: int = 3 if id in ["tdm", "ffa"] else 3
	spawn_threats(wings)
	# Somebody on our side. Every battle mode put the player up alone against a
	# flight, a pair of gunships and the ground war -- a team deathmatch with a
	# team of one. Free for all is the one where there is no side to be on.
	if id != "ffa":
		_spawn_allies()

func _spawn_allies() -> void:
	if world.net != null and world.net.active and not world.net.is_host:
		return
	var nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	var jets: Array = World.NATO_JETS if nato else World.OPFOR_JETS
	var rotary: Array = World.NATO_HELIS if nato else World.OPFOR_HELIS
	var lead: AIPlane = null
	for i in ALLY_WINGS:
		var b := AIPlane.new()
		b.setup(jets[i % jets.size()])
		b.team = 0
		b.name = "Blue %d" % (i + 1)
		b.home = Vector3(1200.0 * i - 1200.0, 0.0, -2600.0)
		b.patrol_r = 2600.0 + i * 500.0
		world.add_child(b)
		# off the player's wing, heading the same way into the fight
		var at := Vector3(-500.0 + (i + 1) * 420.0, 3500.0 - i * 120.0, 7500.0 + i * 260.0)
		b.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-4.0)), at)
		b.linear_velocity = -b.global_transform.basis.z * 230.0
		if i % 2 == 1 and is_instance_valid(lead):
			b.leader = lead
			b.slot = Vector3(90.0, -18.0, 120.0)
		else:
			lead = b
		b.died.connect(_on_ally_down)
		world._reset_interp.call_deferred(b)
	for i in 2:
		var h := AIHeli.new()
		h.setup(rotary[i % rotary.size()])
		h.team = 0
		h.name = "Blue Gunship %d" % (i + 1)
		h.home = Vector3(-1200.0 + i * 2400.0, 0.0, -3400.0)
		world.add_child(h)
		var hz: float = 600.0 + i * 300.0
		var hx: float = -800.0 + i * 1600.0
		h.global_transform = Transform3D(Basis(Vector3.UP, 0.0),
			Vector3(hx, Sim.height_at(hx, hz) + 220.0, hz))
		h.died.connect(_on_ally_down)
		world._reset_interp.call_deferred(h)
	Sim.report("friendlies up: %d fighters and a pair of gunships on our side" % ALLY_WINGS,
		Sim.Ev.INFO)

func _on_ally_down(who: Node) -> void:
	if world.mode and world.mode.running:
		world.mode.register_kill(0)
	Sim.report("%s is down" % who.name, Sim.Ev.BAD)

## The range with nothing on it that can hurt an aeroplane: armour columns,
## shipping and helicopters to find and hit, wave after wave.
func setup_strike() -> void:
	if world._drive_kind != "" or world._ship_kind != "":
		# in a vehicle or a boat: the ramp parks the aeroplanes and puts you
		# in the seat, and the range is laid out round it the same as ever
		setup_ramp()
	else:
		world.player.global_transform = Transform3D(Basis(), Vector3(-500.0, 3000.0, 6000.0))
		world.player.rotation.y = deg_to_rad(-4.0)
		world.player.linear_velocity = -world.player.global_transform.basis.z * world._entry_speed(230.0)
		world.player.gear_down = false
		world.player.gear_anim = 0.0
		world.player.throttle = 0.8
		world.player.power = 0.8
	world.mode = GameMode.new()
	world.mode.name = "GameMode"
	world.add_child(world.mode)
	world.mode.start("strike")
	world.mode.finished.connect(world._on_mode_finished)
	world.hud.mode = world.mode
	Sim.report("the column is up the valley, the shipping is offshore east; M for the map",
		Sim.Ev.INFO)

func in_rocket() -> bool:
	return is_instance_valid(world.rocket) and world.rocket.occupied

## Somewhere level and dry near the field to stand a rocket on: east of the
## runway for choice, so the first thing it flies over is not the flight line.
func _pad_site() -> Vector3:
	var best := Vector3(2800.0, 0.0, -400.0)
	var best_rough := 1e9
	for o in [Vector2(2800, -400), Vector2(3600, 900), Vector2(2800, -2400),
			Vector2(4800, 0), Vector2(-2800, -400), Vector2(-3600, 1200),
			Vector2(0, -5200), Vector2(0, 5200)]:
		var c: Vector2 = o
		var h: float = Sim.height_at(c.x, c.y)
		if h < Sim.sea_at(c.x, c.y) + 3.0:
			continue
		var rough := 0.0
		for d in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
			rough = maxf(rough, absf(Sim.height_at(c.x + d.x, c.y + d.y) - h))
		if rough < best_rough:
			best_rough = rough
			best = Vector3(c.x, 0.0, c.y)
		if rough < 2.0:
			break
	return best

## On the pad, in the capsule, with everything still to do.
func setup_launch(which := "orbital") -> void:
	setup_ramp()
	var at := _pad_site()
	var ground: float = maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z))
	pad = Node3D.new()
	pad.name = "LaunchPad"
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(70.0, 8.0, 70.0), Vector3(0.0, -4.0, 0.0))
	# the flame trench, and the tower beside it
	MeshKit.box(st, Vector3(9.0, 108.0, 9.0), Vector3(22.0, 54.0, 0.0))
	for arm_y in [28.0, 58.0, 82.0, 96.0]:
		MeshKit.box(st, Vector3(16.0, 1.6, 2.4), Vector3(12.0, arm_y, 0.0))
	pad.add_child(MeshKit.mi(MeshKit.finish(st,
		MeshKit.mat(Color(0.52, 0.50, 0.47), 0.85, 0.1)), "Pad"))
	world.add_child(pad)
	pad.global_position = Vector3(at.x, ground, at.z)
	world.rocket = LaunchVehicle.new()
	world.rocket.name = "LaunchVehicle"
	world.rocket.setup(Vector3(at.x, ground, at.z), which)
	world.add_child(world.rocket)
	enter_rocket()

func enter_rocket() -> void:
	if not is_instance_valid(world.rocket):
		return
	world.on_foot = false
	if is_instance_valid(world.walker):
		world.walker.queue_free()
	world.walker = null
	world.hud.walker = null
	if not world.rocket.dismount_requested.is_connected(leave_rocket):
		world.rocket.dismount_requested.connect(leave_rocket)
	world.rocket.mount(true)
	world.hud.rocket = world.rocket
	Sim.report("%s — hold SHIFT for full throttle; it lifts when thrust beats weight, or H flies it" %
		world.rocket.display_name().to_upper(), Sim.Ev.GOOD)
	Sim.report("straight up first, then lean east a little at a time. T sets the attitude hold; SPACE drops a dry stage",
		Sim.Ev.INFO)
	Sim.report("orbit is about 7.8 km/s ACROSS at 200 km, not up. The panel shows the orbit's high and low points",
		Sim.Ev.INFO)

func leave_rocket() -> void:
	if not is_instance_valid(world.rocket):
		return
	if world.rocket.alive and (not world.rocket.landed or world.rocket.throttle > 0.01):
		Sim.report("not from up here: put it on the ground first", Sim.Ev.BAD)
		return
	var at: Vector3 = world.rocket.global_position + Vector3(16.0, 0.0, 6.0)
	world.rocket.mount(false)
	world.hud.rocket = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.crew.spawn_walker(Vector3(at.x, maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z)) + 1.2, at.z))

## Three km final on the boat.
func setup_carrier_approach() -> void:
	var deck := world.carrier.global_position
	var hdg := world.carrier.rotation.y
	var back := Vector3(sin(hdg), 0, cos(hdg))
	world.player.global_transform = Transform3D(Basis(Vector3.UP, hdg), deck + back * 3400.0
		+ Vector3(0, 210.0, 0))
	world.player.linear_velocity = -world.player.global_transform.basis.z * world._entry_speed(72.0)
	world.player.gear_down = true
	world.player.gear_anim = 1.0
	world.player.flaps = 1.0
	world.player.hook_down = true
	world.player.hook_anim = 1.0
	world.player.throttle = 0.45
	world.player.power = 0.45
	Sim.report("Carrier three miles. Hook is down, aim for the two wire.", Sim.Ev.INFO)
	Sim.report("TAB opens aircraft actions if you need to reset anything.", Sim.Ev.INFO)

func setup_ramp() -> void:
	var row := [["f22", -150.0], ["f35", -220.0], ["f16", -290.0], ["f15", -360.0]]
	var idx := 0
	for i in row.size():
		if row[i][0] == Sim.selected_jet:
			idx = i
	var slot: Array = row[idx]
	world.player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(150.0, world._apron_y(150.0, float(slot[1])) + world._stance(world.player.spec),
			float(slot[1])))
	world.player.gear_down = true
	world.player.gear_anim = 1.0
	world.player.throttle = 0.0
	world.player.active = false
	world.player.add_to_group("boardable")
	world.parked = [world.player]
	for i in row.size():
		if i == idx:
			continue
		var j: Aircraft
		if JetSpec.is_rotary(row[i][0]):
			j = PlayerHeli.new()
		else:
			j = PlayerJet.new()
		j.setup(row[i][0])
		j.team = 0
		j.name = "Parked %s" % row[i][0]
		j.active = false
		world.add_child(j)
		j.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
			Vector3(150.0, world._apron_y(150.0, float(row[i][1])) + world._stance(j.spec),
				float(row[i][1])))
		j.gear_down = true
		j.gear_anim = 1.0
		j.set_canopy(true, true)
		j.add_to_group("boardable")
		j.add_to_group("hittable")
		world._reset_interp.call_deferred(j)
		world.parked.append(j)
	world.player.set_canopy(true, true)
	# The apron parks OUR vehicles, and only ours. It used to lay out a T-90, a
	# ZTZ-99 and a Msta on the home flight line alongside the Abrams and hand
	# them all to the player on team 0 — a Russian tank in American markings
	# parked outside an American hangar, friendly to the side it belongs to the
	# other of. Everybody else's kit belongs in their own country, and this
	# world already knows where that is: `Sim.region_faction` says whose ground
	# any point on the map is.
	var mine := String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa"))
	var garage := PackedStringArray()
	var abroad := PackedStringArray()
	for k in VehicleSpec.KINDS:
		var f := String(VehicleSpec.KINDS[k].get("faction", ""))
		if f == mine:
			garage.append(String(k))
		elif f != "":
			abroad.append(String(k))
	var lot: Array[Tank] = []
	for i in garage.size():
		# Twenty-four metres apart, not fifteen: an ASAT launcher is over
		# fourteen metres long and a Patriot not much less, so at the old
		# spacing the long vehicles sat almost nose to tail.
		lot.append(world._spawn_tank(Vector3(196.0, 0, -424.0 - i * 24.0),
			deg_to_rad(-90.0), 0, garage[i]))
	_apron_count = garage.size()
	deploy_abroad(abroad)
	# Stand clear of the nose, however big the aeroplane is. A fixed fourteen
	# metres to the side is outside an F-22 and inside an AC-130's wing.
	var nose: float = maxf(absf(world.player.bounds.position.z), absf(world.player.bounds.end.z))
	world.crew.spawn_walker(world.player.global_transform * Vector3(0.0, 0.0, -(nose + 5.0)))
	if world._ship_kind == "carrier":
		world._ship_kind = ""
		world.crew.enter_carrier()
		return
	if world._ship_kind != "":
		# put the captain on a ship of the chosen type rather than on the ramp
		var pick: Ship = null
		for sh in world.get_tree().get_nodes_in_group("ships"):
			if is_instance_valid(sh) and (sh as Ship).kind == world._ship_kind:
				pick = sh
				break
		if pick == null:
			pick = Ship.new()
			pick.setup(world._ship_kind, 0)
			world.add_child(pick)
			var at := world.fleet_yard.deep_water(Vector3(26000.0, 0, 2400.0))
			pick.global_position = Vector3(at.x, Sim.sea_surface(at.x, at.z), at.z)
		world._ship_kind = ""
		world.crew.enter_ship(pick)
		return
	if world.arty_test != "" and world._drive_kind == "":
		world._drive_kind = world.arty_test
	if world._drive_kind != "":
		# only the vehicles just parked on the ramp, never a group search
		var got: Tank = null
		for v in lot:
			if is_instance_valid(v) and v.kind == world._drive_kind:
				got = v
				break
		if got == null:
			# The ramp parks a fixed set, and anything outside it — a launcher,
			# say — was offered in the menu, previewed, and then left you
			# standing on the apron beside an aeroplane wondering what happened.
			# If it is not parked, put one there.
			var spot: Vector3 = Vector3(-260.0, 0.0, 900.0)
			if is_instance_valid(world.player):
				spot = world.player.global_position + Vector3(-38.0, 0.0, 26.0)
			got = world._spawn_tank(spot, deg_to_rad(90.0), 0, world._drive_kind)
			lot.append(got)
		if is_instance_valid(got):
			world.crew.enter_tank(got)
		world._drive_kind = ""
		return
	Sim.report("Walk to a jet and press U to climb in.", Sim.Ev.INFO)
	Sim.report("WASD walk, SHIFT run, CTRL crouch, SPACE jump, V fire, C view.", Sim.Ev.INFO)

## Shipping. A screen around the carrier, a submarine off the group, and some
## civil traffic further out so the ocean is not an empty blue plane.
## Call a strategic strike from a friendly submarine onto whatever is currently
## designated: the sensor aim point, or the map fire mission if one is set.
func strategic_strike() -> void:
	var at := Vector3.INF
	if world.pod != null and world.pod.active:
		at = world.pod.aim_point()
	if at == Vector3.INF and world.map != null and world.map.has_method("target_point"):
		at = world.map.target_point()
	if at == Vector3.INF:
		Sim.report("strategic strike: designate a target first", Sim.Ev.BAD)
		return
	var boat: Ship = null
	for sh in world.get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(sh) and (sh as Ship).team == 0 and (sh as Ship).can_launch():
			boat = sh
			break
	if boat == null:
		Sim.report("strategic strike: no boat on station", Sim.Ev.BAD)
		return
	boat.launch_strategic(at)

## Kept here for the scripts that reach it by name: see `FleetYard.deep_water_near`.
func deep_water_near(at: Vector3, rings: int) -> Vector3:
	return world.fleet_yard.deep_water_near(at, rings)

## Put everybody else's vehicles where they belong: on ground that is actually
## theirs. The map is generated with a nationality per region, so this walks out
## looking for a patch that answers to the right country and leaves the vehicle
## standing on it — friendly or hostile according to which bloc it is from,
## rather than everything being handed to the player.
func deploy_abroad(kinds: PackedStringArray) -> void:
	var placed := 0
	for k in kinds:
		var want := String(VehicleSpec.KINDS[k].get("faction", ""))
		if want == "":
			continue
		var at := Vector3.INF
		# A ring search out from the field: near enough to find on a sortie,
		# far enough to be somebody else's country. Widened after measuring —
		# a narrower ring left about a third of the foreign kit unplaced,
		# because a given nationality does not necessarily hold much ground
		# within thirty kilometres of this particular airfield.
		# Across the world, not across a theatre.
		#
		# The ring used to stop at 120 km because that was as far as the
		# authored square went, and a nationality that held no ground inside it
		# simply had no kit anywhere. There is no square now: the terrain, the
		# coastlines and the borders all run to the far side of the planet, so
		# the search does too. It walks outward -- near ground first, because
		# kit you can reach on a sortie is worth more than kit you cannot -- and
		# only goes long if the near country belongs to somebody else.
		for attempt in 1400:
			var a := randf() * TAU
			var reach: float = lerpf(20_000.0, 2_400_000.0,
				pow(float(attempt) / 1400.0, 2.0))
			var r: float = randf_range(8000.0, reach)
			var q := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if Sim.region_faction(q.x, q.z) != want:
				continue
			# not in the sea, and not up a cliff
			var h := Sim.height_at(q.x, q.z)
			if h < Sim.sea_at(q.x, q.z) + 6.0:
				continue
			var n := Sim.normal_at(q.x, q.z)
			if n.dot(Vector3.UP) < 0.93:
				continue
			at = Vector3(q.x, h, q.z)
			break
		if at == Vector3.INF:
			_abroad_missed[want] = int(_abroad_missed.get(want, 0)) + 1
			continue
		# Hostile or not according to which side WE are on, not according to a
		# fixed idea of who the good guys are. Flying for Russia, an Abrams
		# standing in Kansas is the enemy; `Tank.team_of` alone would have
		# handed it to the player as a friend.
		var mine_bloc := String(JetSpec.FACTIONS.get(
			String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa")), {}
			).get("bloc", "nato"))
		var their_bloc := String(JetSpec.FACTIONS.get(want, {}).get("bloc", "nato"))
		var t := world._spawn_tank(at, randf() * TAU,
			0 if their_bloc == mine_bloc else 1, k)
		t.ai = true
		placed += 1
	var miss := PackedStringArray()
	for f2 in _abroad_missed:
		miss.append("%s x%d" % [String(f2), int(_abroad_missed[f2])])
	print("[garage] flying %s (%s): %d of ours on the apron, %d foreign vehicle(s) in their own country%s"
		% [Sim.selected_jet,
			String(JetSpec.get_spec(Sim.selected_jet).get("faction", "?")),
			_apron_count, placed,
			"" if miss.is_empty() else
			"; no ground found for " + ", ".join(miss)])

func spawn_threats(count := -1) -> void:
	# in a session, only the host simulates the opposition; clients receive it
	if world.net != null and world.net.active and not world.net.is_host:
		return
	# the opposition flies the other bloc's hardware
	var enemy: Array = World.OPFOR_JETS if JetSpec.bloc_of(Sim.selected_jet) == "nato" else World.NATO_JETS
	var n: int = 3 if count < 0 else count
	for i in n:
		var b := AIPlane.new()
		b.setup(enemy[i % enemy.size()])
		b.team = 1
		b.name = "Bandit %d" % (i + 1)
		b.home = Vector3(1400.0 * i - 1400.0, 0, -4200.0)
		b.patrol_r = 2400.0 + i * 600.0
		world.add_child(b)
		b.global_transform = Transform3D(Basis(), Vector3(-1700.0 + i * 1900.0, 3900.0 + i * 450.0, -2600.0 - i * 900.0))
		b.rotation.y = deg_to_rad(170.0 + 8.0 * i)   # nose-on to the player
		b.linear_velocity = -b.global_transform.basis.z * 240.0
		world._reset_interp.call_deferred(b)
		b.died.connect(world._on_bandit_down)
		# Pairs: number one leads, number two flies his wing, and so on down the
		# flight. They cruise in the slot and split when there is something to
		# fight, which is what a patrol actually looks like.
		if i % 2 == 1 and _flight_lead != null and is_instance_valid(_flight_lead):
			b.leader = _flight_lead
			b.slot = Vector3(90.0, -18.0, 120.0) if (i / 2.0) < 1.0 \
				else Vector3(-90.0, -18.0, 120.0)
			# in the slot from the start: a flight takes off together, and
			# making the wingman rejoin from two kilometres every match just
			# means he spends the first minute of it catching up
			b.global_transform = Transform3D(_flight_lead.global_transform.basis,
				_flight_lead.global_transform * b.slot)
			b.linear_velocity = _flight_lead.linear_velocity
		else:
			_flight_lead = b
	var picks := [["sam", Vector3(-900, 0, -8300)], ["sam", Vector3(1400, 0, -9400)],
		["radar", Vector3(200, 0, -8900)], ["fuel", Vector3(700, 0, -8600)],
		["hangar", Vector3(-300, 0, -9200)]]
	# a pair of gunships working low over the sectors
	if world.mode == null or world.mode.mode not in ["tdm", "ffa"]:
		var rotary: Array = World.OPFOR_HELIS if JetSpec.bloc_of(Sim.selected_jet) == "nato" \
			else World.NATO_HELIS
		for i in 2:
			var h := AIHeli.new()
			h.setup(rotary[i % rotary.size()])
			h.team = 1
			h.name = "Gunship %d" % (i + 1)
			h.home = Vector3(-1200.0 + i * 2400.0, 0, -5200.0)
			world.add_child(h)
			var hx: float = h.home.x
			var hz: float = h.home.z + 400.0
			h.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)),
				Vector3(hx, Sim.height_at(hx, hz) + 260.0, hz))
			h.died.connect(world._on_bandit_down)
			world._reset_interp.call_deferred(h)
	if world.mode != null and world.mode.mode in ["tdm", "ffa"]:
		return
	# A pair working the ground: the aeroplanes that are not trying to shoot
	# you down are the ones that make the field feel busy.
	var cas: Array = World.OPFOR_CAS if JetSpec.bloc_of(Sim.selected_jet) == "nato" \
		else World.NATO_CAS
	for i in 2:
		var m := AIPlane.new()
		m.setup(cas[i % cas.size()])
		m.role = "cas"
		m.team = 1
		m.name = "Mud Mover %d" % (i + 1)
		m.home = Vector3(-2000.0 + i * 3800.0, 0, -7000.0)
		m.patrol_r = 3200.0
		world.add_child(m)
		var mx: float = m.home.x
		var mz: float = m.home.z - 5000.0
		m.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0 + 10.0 * i)),
			Vector3(mx, Sim.height_at(mx, mz) + 2400.0 + i * 300.0, mz))
		m.linear_velocity = -m.global_transform.basis.z * 175.0
		m.died.connect(world._on_bandit_down)
		if i == 1 and is_instance_valid(_cas_lead):
			m.leader = _cas_lead
			m.slot = Vector3(-110.0, -20.0, 150.0)
			m.global_transform = Transform3D(_cas_lead.global_transform.basis,
				_cas_lead.global_transform * m.slot)
			m.linear_velocity = _cas_lead.linear_velocity
		else:
			_cas_lead = m
		world._reset_interp.call_deferred(m)
	# and one transport on a milk run, which is a target rather than a threat
	var hauler := AIPlane.new()
	hauler.setup(World.AI_TRANSPORTS[randi() % World.AI_TRANSPORTS.size()])
	hauler.role = "transport"
	hauler.team = 1
	hauler.name = "Heavy 1"
	hauler.home = Vector3(0, 0, -12000.0)
	world.add_child(hauler)
	hauler.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(120.0)),
		Vector3(6000.0, Sim.height_at(6000.0, -16000.0) + 5200.0, -16000.0))
	hauler.linear_velocity = -hauler.global_transform.basis.z * 150.0
	hauler.died.connect(world._on_bandit_down)
	world._reset_interp.call_deferred(hauler)
	for p in picks:
		var g := GroundTarget.new()
		g.team = 1
		g.setup(p[0])
		world.add_child(g)
		var pos: Vector3 = p[1]
		g.global_position = Vector3(pos.x, Sim.height_at(pos.x, pos.z), pos.z)
		g.name = "%s site" % p[0]
