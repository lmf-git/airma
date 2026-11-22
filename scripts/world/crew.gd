class_name Crew
extends RefCounted
## Getting into and out of things: the walk out to an aircraft and the climb
## in, getting out again or ejecting, taking a vehicle, a ship or the carrier,
## riding in another aircraft's hold or at its gun station, and the man on foot
## that every one of those puts back on the ground.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World
var _pre_gun_auto := ""
var station_walker: Node = null
var _board_t := 0.0
var _board_from := Vector3.ZERO
var _board_ladder := Vector3.ZERO
var _board_seat := Vector3.ZERO

func _init(w: World) -> void:
	world = w

## The man on foot put away: he has got into something.
func _put_away_walker() -> void:
	world.on_foot = false
	if is_instance_valid(world.walker):
		world.walker.queue_free()
	world.walker = null
	world.hud.walker = null

# ------------------------------------------------------------- boarding
## Walk out, climb the ladder, strap in, canopy down. Any key skips it.
func begin_boarding(from_ladder := false) -> void:
	# Nobody climbs into a drone: it is flown from a ground station.
	if world.skip_board or world._auto != "" or bool(world.player.spec.get("unmanned", false)):
		world.player.set_canopy(false, true)
		return
	world.boarding = true
	_board_t = 0.0
	world.skip_board = false
	world.player.auto = "wait"
	# fighters lift the hood and drop a ladder; an airliner just opens a door
	var hooded: bool = world.player.has_canopy()
	if hooded:
		world.player.set_canopy(true, true)
	var lad: Vector3 = world.player.to_global(world.player.ladder_offset())
	_board_ladder = Vector3(lad.x, Sim.height_at(lad.x, lad.z), lad.z)
	_board_from = _board_ladder + (Vector3.ZERO if from_ladder else Vector3(-16.0, 0, 9.0))
	if from_ladder:
		_board_t = 4.9                       # skip the walk-out, start climbing
	# The seat pan, not a guess hung off the eye point: the pilot's origin is at
	# his feet and his hips sit 0.92 above it, so measuring from the eye put him
	# on top of the fuselage rather than down in the tub.
	_board_seat = world.player.to_global(world.player.seat_offset() - Vector3(0, 0.92, 0))
	world.pilot = Pilot.new()
	world.pilot.build()
	world.add_child(world.pilot)
	world.pilot.global_position = _board_from
	world._face(world.pilot, _board_ladder)
	world.board_cam = Camera3D.new()
	world.board_cam.far = 45000.0
	world.board_cam.fov = 48.0
	world.add_child(world.board_cam)
	world.board_cam.current = true
	world.hud.visible = false
	Sim.report("Crew walking out. Press any key to skip.", Sim.Ev.INFO)

func end_boarding() -> void:
	world.boarding = false
	if is_instance_valid(world.pilot):
		world.pilot.queue_free()
	if is_instance_valid(world.board_cam):
		world.board_cam.queue_free()
	if is_instance_valid(world.player):
		world.player.auto = world._auto
		world.player.set_canopy(false)
	world.hud.visible = true
	if world.cam:
		world.cam.current = true

func tick_boarding(delta: float) -> void:
	if not is_instance_valid(world.player) or not is_instance_valid(world.pilot):
		end_boarding()
		return
	_board_t += delta
	var t := _board_t
	var jet := world.player.global_position
	if t < 5.0:                                   # walk out
		var f := clampf(t / 5.0, 0.0, 1.0)
		var p := _board_from.lerp(_board_ladder, f)
		p.y = Sim.height_at(p.x, p.z)
		world.pilot.global_position = p
		world._face(world.pilot, Vector3(_board_ladder.x, p.y, _board_ladder.z))
		world.pilot.pose_walk(t)
	elif t < (8.2 if world.player.has_canopy() else 6.6):    # climb
		var f := clampf((t - 5.0) / 3.2, 0.0, 1.0)
		var top := _board_seat + Vector3(_board_ladder.x - _board_seat.x, 0.35, 0) * 0.55
		world.pilot.global_position = _board_ladder.lerp(top, f)
		world.pilot.pose_climb(t)
	elif t < 9.6:                                 # step in and strap up
		var f := clampf((t - 8.2) / 1.4, 0.0, 1.0)
		var top := _board_seat + Vector3(_board_ladder.x - _board_seat.x, 0.35, 0) * 0.55
		world.pilot.global_position = top.lerp(_board_seat, f)
		world.pilot.rotation.y = lerp_angle(world.pilot.rotation.y, world.player.rotation.y, f)
		world.pilot.pose_seated()
	else:
		world.pilot.global_position = _board_seat
		world.pilot.rotation.y = world.player.rotation.y
		world.pilot.pose_seated()
		if world.player.canopy_open:
			world.player.set_canopy(false)
		if world.player.canopy_anim <= 0.01 or t > 13.5:
			end_boarding()
			return
	# Camera: wide walk-out easing round to the cockpit. The pull-back is scaled
	# to the airframe, otherwise a big jet has its nose cut off in the shot.
	var f2: float = clampf(t / 11.0, 0.0, 1.0)
	var reach: float = maxf(float(world.player.spec["span"]), 14.0)
	var ang: float = lerpf(2.4, 3.4, f2)
	var dist: float = lerpf(reach * 1.55, reach * 0.72, pow(f2, 1.5))
	var hgt: float = lerpf(reach * 0.30, reach * 0.20, f2)
	var focus: Vector3 = world.pilot.global_position + Vector3(0, 0.9, 0)
	world.board_cam.global_position = jet + Vector3(cos(ang) * dist, hgt, sin(ang) * dist)
	# look at the middle of the aircraft, drifting toward the cockpit
	var centre := jet + Vector3(0, 1.2, 0)
	world.board_cam.look_at(centre.lerp(focus, 0.5 * (1.0 - f2)), Vector3.UP)

## `thrown` puts the man in the air with that velocity and a canopy over him,
## which is what an ejection is. Left at zero he is simply stood on the ground.
func spawn_walker(at: Vector3, thrown := Vector3.ZERO) -> void:
	# A man put on his feet does not fire until the trigger has been let go.
	# The left button and K fire his rifle, and they are the cockpit's fire
	# and cannon too -- and the action menu's EJECT is clicked with the left
	# button -- so whatever was held as he left the aircraft went straight on
	# firing his rifle, for nothing, until it was released: phantom gunfire
	# after ejecting, after a crash, and from the LAUNCH click on the range.
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
	world.on_foot = true
	world.walker = Walker.new()
	world.walker.name = "Walker"
	world.add_child(world.walker)
	if thrown == Vector3.ZERO:
		world.walker.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
	else:
		world.walker.global_position = at
		world.walker.vel = thrown
		world.walker.on_floor = false
		world.walker.set_chute(true)
	world.walker.yaw = deg_to_rad(90.0)
	world.walker.board_requested.connect(board)
	world.walker.died.connect(on_walker_died)
	world.walker.hold_requested.connect(enter_hold)
	world.walker.station_requested.connect(take_hold_station)
	world.walker.activate()
	world.hud.walker = world.walker
	world.hud.aircraft = null
	world.veil.aircraft = null
	if world.audio:
		world.audio.aircraft = null

## Hand the aircraft to the orbit autopilot and move the player back to the
## gun sight. Leaving puts them back in the front seat.
func toggle_gunner() -> void:
	if not is_instance_valid(world.player) or not world.player.spec.get("gunship", false):
		return
	world.gunning = not world.gunning
	if world.gunning:
		_pre_gun_auto = world.player.auto
		world.player.auto = "orbit"
		if "orbit_alt" in world.player and world.player is PlayerHeli:
			# a helicopter's is height above the ground, and low
			world.player.orbit_alt = float(world.player.spec.get("orbit_agl", 250.0))
			world.player.orbit_speed = float(world.player.spec.get("orbit_speed", 30.0))
		elif "orbit_alt" in world.player:
			world.player.orbit_alt = maxf(world.player.global_position.y, 1200.0)
			# Slow, the way a gunship works. Kept at the entry speed -- usually
			# a hundred and forty-odd metres a second -- the circle round the
			# mark was so wide that, banked to fly it, the sight line ran along
			# the port wing and the battery, which points below it, could not
			# reach. At a hundred it orbits a mark three kilometres out at
			# twenty degrees of bank with the mark well under the wing, and
			# still has a third over its stall in the turn.
			world.player.orbit_speed = float(world.player.spec.get("orbit_speed", 100.0))
		if not world.pod.active:
			world.pod.toggle()
		world.pod.set_fullscreen(true)
		world.cam.pod_slew = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Sim.report("gunner station — mouse slews, CTRL+T tracks, 1/2/3 pick a gun",
			Sim.Ev.INFO)
		Sim.report("the aircraft is holding a left orbit; press G again to go forward",
			Sim.Ev.INFO)
	else:
		world.player.auto = _pre_gun_auto
		world.pod.set_fullscreen(false)
		if world.pod.active:
			world.pod.toggle()
		world.cam.pod_slew = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Sim.report("back in the front seat", Sim.Ev.INFO)

## Gunner controls: the aircraft is on autopilot so the stick is free.
func gunner_input(_delta: float) -> void:
	if not world.gunning or not is_instance_valid(world.player):
		return
	if not world.player.alive:
		toggle_gunner()
		return
	_weapon_keys()
	# The page says "L laser" at the gun station as well, and L was only ever
	# read on the pilot's sensor page: once it was on here it stayed on.
	if Input.is_action_just_pressed(&"laser") and not Sim.ui_modal:
		world.pod.toggle_laser()
	if (Input.is_action_pressed(&"gun") or Input.is_action_pressed(&"fire")) \
			and not Sim.ui_modal:
		var aim: Vector3 = world.pod.aim_point()
		if aim != Vector3.INF:
			world.player.fire_gunship(world, aim)

## 1 to 8 pick a store, at the gun station and on the sensor page alike.
func _weapon_keys() -> void:
	for i in 8:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))) \
				and i < world.player.weapon_types.size() and not Sim.menu_keys:
			world.player.set_weapon(i)
			Sim.report(world.player.weapon_label(world.player.current_weapon()), Sim.Ev.INFO)

## The sensor page doubles as a weapon station: pick a store, shoot at whatever
## the pod is holding. Helicopters and gunships live here.
func sensor_input() -> void:
	# The rest of this reads the aeroplane's stores. A tank commander's sight
	# has none of that -- it lases, and the laid piece is fired from the normal
	# gunnery controls -- so take that path out before touching `player`.
	if not is_instance_valid(world.player) or (world.pod.platform != null and world.pod.platform != world.player):
		if Input.is_action_just_pressed(&"laser"):
			world.pod.toggle_laser()
		return
	_weapon_keys()
	if Input.is_action_just_pressed(&"laser"):
		world.pod.toggle_laser()
	# The gun is held, the stores are not. The whole block was entered on the
	# press of the fire button, so with the chin gun selected and the trigger
	# squeezed on the sensor page an Apache put out one shot and stopped until
	# the button was let go and pulled again.
	var gun_sel: bool = world.player.current_weapon() == "gun" \
		or world.player.is_gunship_weapon(world.player.current_weapon())
	if Input.is_action_just_pressed(&"fire") or Input.is_action_pressed(&"gun") \
			or (gun_sel and Input.is_action_pressed(&"fire")):
		var w: String = world.player.current_weapon()
		var aim: Vector3 = world.pod.aim_point()
		if world.player.is_gunship_weapon(w):
			# The pilot can work the battery off the sensor page when nobody is
			# on it. If somebody *is*, they have it: two people firing the same
			# guns at two different marks is not a division of labour.
			if is_instance_valid(station_walker):
				Sim.report("the gunner has the battery", Sim.Ev.INFO)
			elif aim != Vector3.INF:
				world.player.fire_gunship(world, aim)
		elif w == "gun":
			# On the fire button as well as the gun key, and for as long as it
			# is down: see below. Reaching this branch on the press alone gave
			# a chin gun one shot per click.
			world.player.fire_gun(world)
		elif Input.is_action_just_pressed(&"fire"):
			var res: String = world.player.fire()
			if res != "":
				Sim.report(res, Sim.Ev.INFO)

## Leaving the aeroplane. You go with the seat: the pilot is the player from
## here, under canopy, and lands as a man on foot rather than as a ragdoll
## somebody else watches fall.
func eject() -> void:
	if not is_instance_valid(world.player) or not world.player.alive:
		return
	Sim.report("EJECT — canopy out", Sim.Ev.BAD)
	var seat: Vector3 = world.player.global_transform * world.player.cockpit_offset()
	# up the rails first, and carrying half of what the aeroplane had
	var thrown: Vector3 = world.player.linear_velocity * 0.5 + Vector3(0, 24.0, 0)
	world.player.break_part("canopy")
	# The pilot is leaving in the seat, so the wreck does not throw one as well.
	world.player.explode(false)
	spawn_walker(seat, thrown)

## Take command of a ship. The helm is the same stick as a tank's, the mount is
## laid with the mouse, and U puts you back where you came from.
func enter_ship(sh: Ship) -> void:
	if not is_instance_valid(sh) or not sh.alive:
		return
	_put_away_walker()
	world.ship = sh
	# so the map can lay a strategic aiming point, which needs to know which
	# boat is asking whether it has a round to send
	world.map.ship = sh
	# so the weapon camera can ride a round out of her tubes
	if not sh.store_released.is_connected(world._on_store_released):
		sh.store_released.connect(world._on_store_released)
	sh.mount(true)
	if world.net != null and world.net.active:
		world.net.ships.take_conn(sh.fleet_idx, true)
	world.pod.platform = sh
	world.hud.ship = sh
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse lays the battery, left click fires, U to hand over", Sim.Ev.INFO)

func leave_ship() -> void:
	if not is_instance_valid(world.ship):
		return
	world.ship.mount(false)
	if world.net != null and world.net.active:
		world.net.ships.take_conn(world.ship.fleet_idx, false)
	world.stow_pod()
	var at: Vector3 = world.ship.global_position
	world.hud.ship = null
	world.map.ship = null
	world.ship = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# ...and nothing else after it. `Crew.spawn_walker` makes the man's own camera
	# current, and forcing the chase camera live again immediately afterwards
	# handed the view back to whatever it was still following — the aeroplane
	# parked on the apron. Handing over the conn put you in a jet you were not
	# in and could not fly. Leaving a tank has never done this because it does
	# not touch the camera at all.
	spawn_walker(at + Vector3(0, 12.0, 0))

## Take the conn of the carrier. She is not a `Ship` -- she has no gun, no
## tubes and a deck instead -- so she gets her own pair rather than being bent
## into the ship plumbing that expects a main mount.
func enter_carrier() -> void:
	if not is_instance_valid(world.carrier) or not world.carrier.alive:
		return
	_put_away_walker()
	if not world.carrier.dismount_requested.is_connected(leave_carrier):
		world.carrier.dismount_requested.connect(leave_carrier)
	world.carrier.mount(true)
	world.hud.carrier = world.carrier
	# The sensor is hers while she is crewed. Left alone it stayed hung off the
	# aeroplane parked on the ramp, and the page that opened from the bridge
	# was that jet's -- its gun, its stores, its weapon select.
	world.pod.platform = world.carrier
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse looks out from the island, RMB sensor page, U to hand over",
		Sim.Ev.INFO)

## At the carrier's conn. She has no gun and no seat to climb out of, and the
## aeroplane left parked on the ramp is not what is being commanded -- but the
## aeroplane's keys went on reaching it from here: the sensor page opened on a
## jet two hundred kilometres away with its gun and stores, J put you in a
## gunship's gunner station, TAB listed its stores and U climbed out of it.
func at_conn() -> bool:
	return is_instance_valid(world.carrier) and world.carrier.occupied

func leave_carrier() -> void:
	if not is_instance_valid(world.carrier):
		return
	world.carrier.mount(false)
	world.hud.carrier = null
	world.stow_pod()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# put the captain down on his own flight deck
	spawn_walker(world.carrier.global_position
		+ Vector3(0.0, Carrier.DECK_Y + 1.5, 0.0)
		+ world.carrier.global_transform.basis * Vector3(-6.0, 0.0, -70.0))

func enter_tank(t: Tank) -> void:
	if not is_instance_valid(t) or not t.alive:
		return
	if Sim.debug_weapons:
		print("[mount] %s at %s, %.1f m above ground, mission=%s" % [t.kind,
			str(t.global_position.round()),
			t.global_position.y - Sim.height_at(t.global_position.x, t.global_position.z),
			str(Sim.mission)])
	# knocked out with him in it, outside a street fight (which has its own
	# way back): the choice of what to go back in as
	if not is_instance_valid(world.cqb) and not t.died.is_connected(world.session.on_crew_down):
		t.died.connect(world.session.on_crew_down)
	_put_away_walker()
	world.tank = t
	# so the weapon camera can ride a round off a launcher
	if not t.store_released.is_connected(world._on_store_released):
		t.store_released.connect(world._on_store_released)
	t.mount(true)
	world.hud.tank = t
	world.map.tank = t
	Sim.report("in the driver's seat — W/S drive, A/D steer, mouse lays the gun", Sim.Ev.INFO)
	# A light 4x4 has no main gun and no coaxial: it has the thing on the roof.
	if t.vclass() == "lav":
		Sim.report("SPACE roof gun, C sight, U to get out", Sim.Ev.INFO)
	else:
		Sim.report("SPACE main gun, V coax, C gunner sight, U to get out", Sim.Ev.INFO)

func leave_tank() -> void:
	if not is_instance_valid(world.tank):
		return
	var out: Vector3 = world.tank.global_transform * Vector3(-3.4, 0.5, 0.0)
	world.tank.mount(false)
	world.tank.in_throttle = 0.0
	world.tank.in_steer = 0.0
	world.tank.in_brake = true
	world.tank.sight_active = false
	if world.pod and world.pod.platform == world.tank:
		world.stow_pod()
		if world.cam:
			world.cam.pod_slew = false
	world.hud.tank = null
	world.map.tank = null
	world.tank = null
	spawn_walker(out)

func on_walker_died(where: Vector3) -> void:
	var fight := world.cqb
	if is_instance_valid(fight):
		var by: Node = world.walker.last_attacker if is_instance_valid(world.walker) else null
		# In a session the round that did it was fired on the host, and only
		# its name came over with the damage.
		var net_by: String = String(world.walker.get_meta("net_by", "")) \
			if is_instance_valid(world.walker) else ""
		var by_name := "your own grenade"
		if is_instance_valid(by) and by is Soldier:
			by_name = String(by.get("callsign"))
		elif net_by != "":
			by_name = net_by
		Sim.report("you were dropped by %s" % by_name, Sim.Ev.BAD)
		var cause := String(world.walker.last_cause) if is_instance_valid(world.walker) else "explosion"
		fight.feed_player(by if by != world.walker else null, cause)
		fight.player_down()
		if world.net != null and world.net.active:
			world.net.report_down(world.net.name_of(world.net.my_id),
				by_name if by_name != "your own grenade" else "", cause,
				bool(world.walker._last_head) if is_instance_valid(world.walker) else false)
	else:
		Sim.report("pilot down", Sim.Ev.BAD)
		# outside a street fight: choose what to go back in as
		world.session.offer_redeploy()
		return
	await world.get_tree().create_timer(3.5).timeout
	if not world.on_foot or not world.is_inside_tree():
		return
	if is_instance_valid(world.walker):
		world.walker.queue_free()
	# Back in with the rest of the side, not six paces from where it happened:
	# in a street fight that is six paces from whoever did it.
	if is_instance_valid(fight) and fight == world.cqb:
		spawn_walker(fight.spawn_point(0, 0))
		world.walker.yaw = 0.0
		fight.set_player(world.walker)
		world.street_fight.cqb_deploy(false)
		return
	if is_instance_valid(world.cqb) or is_instance_valid(fight):
		return
	spawn_walker(where + Vector3(6.0, 0, 6.0))

## Crew in the back of a gunship can take the gun station without flying it.
func take_hold_station(jet: Node) -> void:
	if not is_instance_valid(jet) or not jet.spec.get("gunship", false):
		return
	if not is_instance_valid(world.walker):
		return
	station_walker = world.walker
	world.walker.visible = false
	world.walker.set_process(false)
	world.walker.set_physics_process(false)
	world.hud.walker = null
	world.on_foot = false
	world.player = jet as Aircraft
	world.hud.aircraft = world.player
	world.veil.aircraft = world.player
	world.pod.platform = world.player
	world.map.aircraft = world.player
	if "pod" in world.player:
		world.player.pod = world.pod
	if world.audio:
		world.audio.aircraft = world.player
	world.gunning = false
	toggle_gunner()

func leave_hold_station() -> void:
	if not is_instance_valid(station_walker):
		return
	if world.gunning:
		toggle_gunner()
	var w := station_walker
	station_walker = null
	w.visible = true
	w.set_process(true)
	w.set_physics_process(true)
	w.activate()
	world.walker = w
	world.hud.walker = w
	world.hud.aircraft = null
	world.veil.aircraft = null
	world.on_foot = true

func enter_hold(jet: Node) -> void:
	if is_instance_valid(world.walker) and jet.has_method("hold_node"):
		world.walker.enter_frame(jet.hold_node(), jet)

func board(jet: Node) -> void:
	if jet is Ship:
		enter_ship(jet as Ship)
		return
	if jet is Tank:
		enter_tank(jet as Tank)
		return
	if not is_instance_valid(jet) or not (jet is Aircraft):
		return
	if jet.is_in_group("remote"):
		return                     # another player's: its hold, never its seat
	_put_away_walker()
	world.player = jet as Aircraft
	world.player.active = true
	world.player.remove_from_group("boardable")
	# into another aeroplane on the line: that is what the others now see
	if world.net != null and world.net.active:
		world.net.set_jet(world.net._kind_of(world.player))
	for j in world.parked:
		if is_instance_valid(j) and j != world.player:
			j.set_canopy(false)
	world.show_player()
	if world.audio:
		world.audio.aircraft = world.player
	if not world.player.died.is_connected(on_player_died):
		world.player.died.connect(on_player_died)
	if not world.player.touched_down.is_connected(world._on_touchdown):
		world.player.touched_down.connect(world._on_touchdown)
	if world.player.spec.is_empty():
		Sim.selected_jet = String(JetSpec.ids()[0])
	begin_boarding(true)

func on_player_died(_w: Node) -> void:
	Sim.report("you were shot down", Sim.Ev.BAD)

## Leave the jet: only with the wheels stopped and the throttle closed.
func try_dismount() -> void:
	if not is_instance_valid(world.player) or world.on_foot or world.boarding:
		return
	if not world.player.on_ground or world.player.linear_velocity.length() > 1.5 or world.player.throttle > 0.02:
		if is_instance_valid(world.player):
			world.player.say("stop the jet and close the throttle first")
		return
	world.player.active = false
	world.player.set_canopy(true)
	world.player.add_to_group("boardable")
	if not world.parked.has(world.player):
		world.parked.append(world.player)
	var out: Vector3 = world.player.to_global(world.player.ladder_offset() + Vector3(-1.6, 0, 0))
	# U is getting out and getting in. The press that got him out was still
	# latched as "interact", and the man stood beside the aircraft read it on
	# his first step and climbed straight back in: the boarding sequence again,
	# every time.
	Sim.block_until_released([&"interact"])
	spawn_walker(out)
