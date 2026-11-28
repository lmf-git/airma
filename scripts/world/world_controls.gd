class_name WorldControls
extends RefCounted
## The keys the world answers itself, outside any one vehicle: the shell's own
## input, the action menu's choices, and pausing, resuming and leaving a match
## (which in a session pauses nothing: see `pause`).
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

## The deploy screen and the pause menu cannot both be up: the deploy screen
## sat over the top of the menu and took every click meant for it, so with it
## open there was no getting at the menu at all. The pause menu wins. The
## deploy screen steps aside while it is up and comes back when it goes.
var _deploy_held := false

func _init(w: World) -> void:
	world = w

func do_action(id: String) -> void:
	# The orbital page first of all. These are the only actions that do not
	# belong to a machine — they work on foot, in a tank, on a bridge and in the
	# air — and they were sitting inside the aircraft handler, which returns
	# immediately when there is no aeroplane. On foot that is always.
	match id:
		"objclear":
			Sim.clear_objective()
		"asattgt":
			# Step through what is in orbit. The map can assign one with ctrl
			# and click, but you are not always at the map — and an ASAT
			# launcher with nothing assigned falls back to whatever its own
			# crew think is nearest, which is not always what you want dead.
			var sats: Array = []
			for n in world.get_tree().get_nodes_in_group("satellites"):
				if is_instance_valid(n) and (not ("team" in n) or int(n.team) != 0):
					sats.append(n)
			if sats.is_empty():
				Sim.report("nothing hostile in orbit", Sim.Ev.BAD)
			else:
				var at := sats.find(Sim.sat_target)
				Sim.sat_target = sats[(at + 1) % sats.size()] if at >= 0 else sats[0]
				if is_instance_valid(world.map):
					world.map.sat_target = Sim.sat_target
				Sim.report("ASAT target: %s" % Sim.label_of(Sim.sat_target),
					Sim.Ev.INFO)
		"satlink":
			# Ask the satellite what it can see, and put the answer somewhere
			# useful: the objective marker goes on the weight of it, so the
			# survey is something you can then fly to.
			var sv := Sim.satellite_survey(
				int(world.player.team) if is_instance_valid(world.player) else 0)
			if String(sv["sat"]) == "":
				Sim.report("no reconnaissance satellite of ours overhead", Sim.Ev.BAD)
			elif int(sv["seen"]) == 0:
				Sim.report("%s: downlink clear, nothing hostile in the footprint"
					% String(sv["sat"]), Sim.Ev.INFO)
			else:
				Sim.report("%s: %d hostile contact(s) in the footprint" % [
					String(sv["sat"]), int(sv["seen"])], Sim.Ev.GOOD)
				Sim.set_objective(sv["centre"] as Vector3)
		_:
			pass
	# vehicle and ship actions next: they are the ones on screen when crewing
	match id:
		"sensor":
			# Armour has a commander's sight too. This only ever opened for a
			# ship, so a tank crew had a sensor page they could never reach.
			if is_instance_valid(world.ship) or is_instance_valid(world.tank) or world.crew.at_conn():
				var mount: Node3D = world.tank
				if is_instance_valid(world.ship):
					mount = world.ship
				elif world.crew.at_conn():
					mount = world.carrier
				world.pod.platform = mount
				world.pod.toggle()
				world.pod.set_fullscreen(world.pod.active)
			return
		"allstop":
			if is_instance_valid(world.ship):
				world.ship.telegraph = 0.0
			elif world.crew.at_conn():
				world.carrier.telegraph = 0.0
			return
		"amidships":
			if is_instance_valid(world.ship):
				world.ship.helm = 0.0
			elif world.crew.at_conn():
				world.carrier.helm = 0.0
			return
		"dismount":
			if is_instance_valid(world.ship):
				world.crew.leave_ship()
				return
			if is_instance_valid(world.tank):
				world.crew.leave_tank()
				return
			if world.crew.at_conn():
				world.actions.close()
				world.crew.leave_carrier()
				return
			# otherwise it is the aeroplane's "climb out", below -- which
			# returning here unconditionally made a menu item that did nothing
		"weapon":
			if is_instance_valid(world.tank):
				world.tank.cycle_weapon()
			return
		"gunner":
			if is_instance_valid(world.tank):
				world.tank.gunner = not world.tank.gunner
				return
			# the gunship's station, below: the same id, and it never got there
		"clearfm":
			if is_instance_valid(world.tank):
				world.tank.map_target = Vector3.INF
				Sim.report("fire mission cancelled", Sim.Ev.INFO)
			return
		"map":
			world.map.toggle()
			return
	do_aircraft_action(id)

func do_aircraft_action(id: String) -> void:
	if not is_instance_valid(world.player):
		return
	match id:
		"hook":
			world.player.toggle_hook()
			world.player.say("tailhook " + ("down" if world.player.hook_down else "up"))
		"bay":
			world.player.set_bays(not world.player.any_bay_open())
		"gear":
			world.player.toggle_gear()
		"flaps":
			world.player.flaps = 0.0 if world.player.flaps > 0.5 else 1.0
		"rwy":
			Airbase.cycle_pick(world.get_tree(), world.player.global_position)
			world.player.say("landing aid: " + Airbase.pick_label(world.get_tree(), world.player.global_position))
		"canopy":
			world.player.set_canopy(not world.player.canopy_open)
		"ramp":
			world.player.toggle_ramp()
			world.player.say("cargo ramp " + ("opening" if world.player.ramp_open else "closing"))
		"fbw":
			world.player.assist = not world.player.assist
			Sim.assist = world.player.assist
		"hover":
			if world.player is PlayerHeli:
				(world.player as PlayerHeli).toggle_hover_hold()
		"aphold":
			world.player.set_autopilot("hold")
		"aploiter":
			world.player.set_autopilot("loiter")
		"apgoto":
			world.player.set_autopilot("goto")
		"apturn":
			world.player.toggle_orbit_direction()
		"jammer":
			world.player.toggle_jammer()
		"nav":
			world.player.toggle_nav_lights()
		"lamp":
			world.player.toggle_lights()
		"dismount":
			world.actions.close()
			world.crew.try_dismount()
		"gunner":
			world.actions.close()
			world.crew.toggle_gunner()
		"eject":
			world.actions.close()
			world.crew.eject()

func resume() -> void:
	Sim.menu_open = false
	world.session.unhold_choice()
	world.menu.visible = false
	if is_instance_valid(world.pause_menu):
		world.pause_menu.close()
	show_roster(false)
	world.get_tree().paused = false
	# RESUME on the hangar left the cockpit sound paused: only ESC undid it.
	if world.audio:
		world.audio.set_paused(false)
	# the click on RESUME is still down, and SPACE on a focused button is fire
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
	var crewed: bool = is_instance_valid(world.tank) or is_instance_valid(world.ship) or world.crew.at_conn()
	if world.on_foot and is_instance_valid(world.walker):
		# his own eyes, not the camera on the aeroplane parked back at the field
		world.walker.activate()
	elif is_instance_valid(world.player) and not crewed:
		world.cam.current = true
	# Whatever had the mouse before the pause gets it back. Only the walker and
	# the mouse stick did: a tank, a ship or the sensor page came back with the
	# pointer free, and the gun would not lay until something captured it again.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _wants_grab() else Input.MOUSE_MODE_VISIBLE
	deploy_yield(false)

func pause() -> void:
	var can_restart: bool = world.menu.net_role != "client"
	world.pause_menu.open(pause_context(), can_restart)
	# The session list comes up with the pause menu rather than instead of it.
	# Put on its own key it simply took escape over, and there was then no way
	# to reach the menu at all.
	show_roster(true)
	# In a session the match goes on: one player cannot stop everybody else's
	# game, and freezing his own copy of it while theirs ran put the two out of
	# step. His controls are let go of instead (`Sim.menu_open`).
	var online: bool = world.net != null and world.net.active
	Sim.menu_open = true
	if not online:
		world.get_tree().paused = true
		if world.audio:
			world.audio.set_paused(true)
	else:
		Sim.report("menu open — the match goes on around you", Sim.Ev.INFO)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	deploy_yield(true)

## ESC, one step at a time: out of the settings page, out of the hangar back to
## the pause page, and out of the pause page back into the match.
func on_escape() -> void:
	if world.pause_menu.visible:
		if not world.pause_menu.back() and world.running:
			resume()
		return
	if not world.running:
		return
	# One layer at a time, the top one first. ESC went straight to the pause
	# page from anywhere, leaving the map or the satellite view up under it --
	# and with them whatever they had decided the mouse should be.
	if is_instance_valid(world.sat_view) and world.sat_view.active():
		toggle_sat_view()
		return
	if is_instance_valid(world.map) and world.map.visible:
		world.map.toggle()
		return
	if is_instance_valid(world.actions) and world.actions.visible:
		world.actions.close()
		return
	if is_instance_valid(world.admin) and world.admin.visible:
		return                        # it closes itself on ESC
	if world.menu.visible:
		# the hangar was opened from the pause page: back to it
		world.menu.visible = false
		world.pause_menu.open(pause_context(), world.menu.net_role != "client")
		show_roster(true)
		return
	pause()

## CHANGE MODE: the hangar, over the paused match. Its RESUME goes back to the
## match and its LAUNCH ends it for whatever is picked there.
func pause_to_hangar() -> void:
	world.pause_menu.close()
	show_roster(false)
	world.menu.set_paused(true)
	world.menu.visible = true
	# A joiner cannot change the mode, but he can change what he is in.
	if world.net != null and world.net.active and not world.net.is_host and world.running \
			and not is_instance_valid(world.cqb):
		world.session.choose_in_match("CHANGE")

## The same mode and the same vehicle, from the top.
func restart_match() -> void:
	world.pause_menu.close()
	show_roster(false)
	if world.audio:
		world.audio.set_paused(false)
	var a: Array = world.menu.launch_args()
	world._start(String(a[0]), String(a[1]))

func show_roster(on: bool) -> void:
	if is_instance_valid(world.roster_view):
		world.roster_view.visible = on and world.net != null and world.net.active
		world.roster_view.set_process(world.roster_view.visible)

## The line under PAUSED: what is being played, and with whom.
func pause_context() -> String:
	var mode_name := String(Sim.mission)
	for m in Menu.MISSIONS:
		if String(m[0]) == String(world.menu.mission_id):
			mode_name = String(m[1])
	var what := ""
	if world.on_foot:
		what = "on foot"
	elif is_instance_valid(world.tank):
		what = world.tank.display_name()
	elif is_instance_valid(world.ship):
		what = world.ship.display_name()
	elif is_instance_valid(world.player):
		what = String(world.player.spec.get("name", ""))
	var line := mode_name if what == "" else "%s  ·  %s" % [mode_name, what]
	if world.net != null and world.net.active:
		line += "\n" + world.net.status_line()
	return line

func deploy_yield(to_menu: bool) -> void:
	if not is_instance_valid(world.deploy_ui):
		_deploy_held = false
		return
	if to_menu:
		if world.deploy_ui.visible:
			_deploy_held = true
			world.deploy_ui.visible = false
	elif _deploy_held:
		_deploy_held = false
		world.deploy_ui.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func shell_input(e: InputEvent) -> void:
	# The chat line comes first and eats everything while it is open, so that
	# typing "w" is a letter rather than full throttle.
	if is_instance_valid(world.chat) and e is InputEventKey:
		var ke := e as InputEventKey
		if world.chat.typing:
			world.chat.handle_key(ke)
			Sim.typing = world.chat.typing
			return
		if ke.pressed and not ke.echo and ke.keycode == KEY_SLASH and world.running \
				and not Sim.ui_modal:
			world.chat.open_line()
			Sim.typing = true
			return
	# Letting go of the right button lets the view back out.
	if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		world._hull_zoom = false
		if is_instance_valid(world.cam):
			world.cam.zoom = false
	# ALT + right click raises the targeting pod; the wheel zooms it.
	if e is InputEventMouseButton and world.missions.in_rocket():
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and world.running \
			and not world.on_foot and not Sim.ui_modal:
		var mb := e as InputEventMouseButton
		# Not while driving: right click is the gun there, and META counts as
		# freelook on a Mac, so firing a howitzer threw the player into the
		# sensor camera. This guard belongs on the pod alone -- putting it at
		# the top of the handler took the map, the radar ranges, the side
		# panels and the action menu with it.
		# ...and not on foot, where the right button is the sights.
		# Plain right click zooms the view while it is held; the sensor page is
		# on O, or ALT with the right button.
		if mb.button_index == MOUSE_BUTTON_RIGHT and not is_instance_valid(world.tank) \
				and not world.on_foot and not Input.is_action_pressed(&"freelook") \
				and not world.pod.active:
			if is_instance_valid(world.ship) or world.crew.at_conn():
				# a bridge's own camera, eased in by `_ease_hull_zoom`
				world._hull_zoom = true
				return
			if is_instance_valid(world.cam) and world.cam.current:
				world.cam.zoom = true
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and world.gunning:
			# At a gun station the sight is the seat. Right click stowed it,
			# which left the gunner looking out of whatever camera was behind
			# it -- from a gunship called in over a street fight, his own eyes
			# back on the ground.
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and not is_instance_valid(world.tank) \
				and not world.on_foot:
			if world.crew.at_conn():
				# her own masthead, not the jet parked back on the ramp
				world.pod.platform = world.carrier
			world.pod.toggle()
			world.pod.set_fullscreen(world.pod.active)
			if world.cam:
				world.cam.pod_slew = world.pod.active
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if world.pod.active \
				else Input.MOUSE_MODE_VISIBLE
			return
		if world.pod.active and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			world.pod.zoom(1)
			return
		if world.pod.active and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			world.pod.zoom(-1)
			return
	# At a gun station the mouse has nothing else to do -- the aircraft is flying
	# itself -- and the station says "mouse slews". It needed ALT held as well,
	# so the sight sat wherever the station had laid it and felt locked there.
	if world.pod.active and e is InputEventMouseMotion \
			and (Input.is_action_pressed(&"freelook") or world.gunning):
		world.pod.slew(Sim.mouse_rel(e as InputEventMouseMotion))
		return
	if world.boarding and not (is_instance_valid(world.sat_view) and world.sat_view.in_intro()) \
			and ((e is InputEventKey and e.pressed and not e.echo) \
			or (e is InputEventMouseButton and e.pressed)):
		world.crew.end_boarding()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		# In the capsule the keyboard is the rocket's. The aeroplane left on the
		# ramp must not hear any of it: P would cycle its camera away from the
		# rocket, U would climb out of it, TAB would open its stores.
		if k == KEY_F4 and world.running and Sim.globe and not Sim.typing:
			toggle_sat_view()
			return
		if world.missions.in_rocket() and not k in [KEY_ESCAPE, KEY_M, KEY_F1, KEY_F2, KEY_F3,
				KEY_PERIOD, KEY_COMMA, KEY_SLASH, KEY_APOSTROPHE]:
			return
		if (k == KEY_PERIOD or k == KEY_COMMA) and world.running and not Sim.typing:
			# Time warp, for whatever of yours is coasting above the air.
			Sim.warp_step(1 if k == KEY_PERIOD else -1)
			Sim.report("time warp x%d — applies above the air, in free fall" % int(Sim.space_warp),
				Sim.Ev.INFO)
		elif k == KEY_EQUAL and world.running:
			Sim.radar_range_idx = mini(Sim.radar_range_idx + 1, Sim.RADAR_RANGES.size() - 1)
			Sim.report("radar range %d km" % int(Sim.radar_range() * 0.001), Sim.Ev.INFO)
		elif k == KEY_MINUS and world.running:
			Sim.radar_range_idx = maxi(Sim.radar_range_idx - 1, 0)
			Sim.report("radar range %d km" % int(Sim.radar_range() * 0.001), Sim.Ev.INFO)
		elif k == KEY_BRACKETLEFT and world.running:
			Sim.panel_left = (Sim.panel_left + 1) % 4
			Sim.report("left panel: %s" % HUD.PANEL_NAMES[Sim.panel_left], Sim.Ev.INFO)
		elif k == KEY_BRACKETRIGHT and world.running:
			Sim.panel_right = (Sim.panel_right + 1) % 4
			Sim.report("right panel: %s" % HUD.PANEL_NAMES[Sim.panel_right], Sim.Ev.INFO)
		elif k == KEY_H and world.running and is_instance_valid(world.player) and not world.crew.at_conn() \
				and bool(world.player.spec.get("stovl", false)):
			world.player.hover_cmd = not world.player.hover_cmd
			Sim.report("STOVL: %s" % ("converting to jetborne" if world.player.hover_cmd
				else "converting to wingborne"), Sim.Ev.INFO)
		elif k == KEY_M and world.running:
			world.map.toggle()
		elif k == KEY_O and world.running:
			# The sensor page, which is what every key card says O is. This
			# opened the map -- M already does -- and being first in the chain
			# it took the key from both sensor branches below it, so O never
			# raised the sensor anywhere: not in a cockpit, not on a bridge,
			# not in a turret.
			if world.gunning:
				# At the guns the sensor *is* the station. O stowed it, which
				# dropped a man called up to a gunship back to the camera in
				# the street with the guns still his; J is the way out.
				pass
			elif world.on_foot:
				# nothing to look through on foot; the map is what it did
				world.map.toggle_globe()
			elif is_instance_valid(world.ship) or is_instance_valid(world.tank) or world.crew.at_conn():
				# whatever is crewed owns the sensor: the action menu's path,
				# which hangs the head off the hull
				do_action("sensor")
			elif is_instance_valid(world.player):
				world.pod.platform = world.player
				world.pod.toggle()
				world.pod.set_fullscreen(world.pod.active)
				if world.cam:
					world.cam.pod_slew = world.pod.active
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if world.pod.active \
					else Input.MOUSE_MODE_VISIBLE
				Sim.report("sensor page %s" % ("up" if world.pod.active else "stowed"),
					Sim.Ev.INFO)
		elif k == KEY_TAB and world.running:
			if world.actions.visible:
				world.actions.close()
			elif world.on_foot:
				# On foot there is no aeroplane and no vehicle, but there is
				# still the orbital picture to command. TAB used to do nothing
				# at all out here.
				world.actions.open_for_foot()
			elif is_instance_valid(world.ship):
				world.actions.open_for_vehicle(world.ship)
			elif is_instance_valid(world.tank):
				world.actions.open_for_vehicle(world.tank)
			elif world.crew.at_conn():
				world.actions.open_for_vehicle(world.carrier)
			elif is_instance_valid(world.player):
				world.actions.open_for(world.player)
		elif k == KEY_K and world.running:
			world.missions.strategic_strike()
		elif k == KEY_Y and world.running:
			# not F: that is the flap lever
			world.weapon_cam_on = not world.weapon_cam_on
			if not world.weapon_cam_on and is_instance_valid(world.cam):
				world.cam.weapon_cam = null
			Sim.report("weapon camera %s" % ("armed" if world.weapon_cam_on else "off"),
				Sim.Ev.INFO)
		elif k == KEY_L and world.running and not world.pod.active and not world.crew.at_conn() \
				and is_instance_valid(world.player) and world.player.has_method("toggle_lights"):
			world.player.toggle_lights()
		elif (k == KEY_I or k == KEY_N) and world.pod.active:
			# N as well as I. N is the night vision key everywhere else, so
			# reaching for it on the sensor page is the obvious thing to do --
			# and with the goggles suppressed while the page is up it now has
			# somewhere sensible to go.
			world.pod.cycle_channel()
			Sim.report("sensor: %s" % SensorPod.CHANNEL_NAMES[world.pod.channel], Sim.Ev.INFO)
		elif k == KEY_T and world.pod.active and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
			# again on what is held lets it go; see `SensorPod.toggle_track`
			world.pod.toggle_track()
		elif k == KEY_F3 and world.running:
			if world.admin.visible:
				world.admin.close()
			else:
				world.admin.open()
		elif k == KEY_F2:
			world.hud.show_help = not world.hud.show_help
		elif k == KEY_ESCAPE and (world.running or world.pause_menu.visible):
			on_escape()
		elif k == KEY_P and world.running and not world.on_foot and not world.crew.at_conn():
			world.cam.cycle()
		elif k == KEY_J and world.running and is_instance_valid(world.crew.station_walker):
			world.crew.leave_hold_station()
		elif k == KEY_J and world.running and not world.on_foot and not world.crew.at_conn() \
				and is_instance_valid(world.player) and world.player.spec.get("gunship", false):
			world.crew.toggle_gunner()
		elif k == KEY_U and world.running and not world.on_foot and not world.boarding \
				and not world.crew.at_conn():
			# The carrier takes U herself, from the conn. Let through here as
			# well it reached the aeroplane parked back on the ramp and climbed
			# out of that, two hundred kilometres from the bridge.
			if is_instance_valid(world.ship):
				world.crew.leave_ship()
			else:
				world.crew.try_dismount()
		# R used to restart the mission outright. That is far too easy to hit by
		# accident mid-sortie; restarting belongs behind the pause menu.

## Up to the satellite view, or back down to whatever the view was on.
func toggle_sat_view() -> void:
	if not is_instance_valid(world.sat_view):
		world.sat_view = SatView.new()
		world.sat_view.name = "SatView"
		world.add_child(world.sat_view)
	if world.sat_view.active():
		world.sat_view.leave(world.hud)
	else:
		world.sat_view.enter(world.get_viewport().get_camera_3d(), world.hud)

## Into a match from orbit: the satellite view starts over the place the
## match is in -- the town of a street fight, the aircraft or the field
## otherwise -- and comes down onto the camera you will play from. The deploy
## screen waits until it is down, and so does the walk out to the aeroplane.
## Not for the rocket missions, which start on the pad and go the other way,
## nor off the round planet.
func match_intro() -> void:
	if is_instance_valid(world.sat_view) and not SatView.intro_on:
		world.sat_view.end_menu(false)
	if not SatView.intro_on or not Sim.globe or not world.running \
			or DisplayServer.get_name() == "headless" \
			or String(Sim.mission) in ["launch", "moon"]:
		return
	# Walking out to the aeroplane: down onto the walk-out's own camera, put
	# where its first frame has it; the walk waits for the view to arrive.
	if world.boarding:
		world.crew.tick_boarding(0.0)
	var cam: Camera3D = world.get_viewport().get_camera_3d()
	if cam == null or cam is SatView:
		return
	var target: Vector3 = cam.global_position - cam.global_basis.z * 60.0
	var follow: Node3D = null
	if is_instance_valid(world.cqb) and world.on_foot:
		target = Vector3(world.cqb.centre.x, Sim.height_at(world.cqb.centre.x, world.cqb.centre.y),
			world.cqb.centre.y)
	elif is_instance_valid(world.tank) and world.tank.is_inside_tree():
		target = world.tank.global_position
		follow = world.tank
	elif is_instance_valid(world.player):
		target = world.player.global_position
		# in the air it goes on flying while the view comes down to it
		if not world.boarding:
			follow = world.player
			# and it comes down to the outside of it, from behind: arriving
			# in the cockpit, the view went through the airframe to get there
			if is_instance_valid(world.cam) and cam == world.cam \
					and world.cam.mode == ChaseCamera.Mode.COCKPIT:
				world.cam.mode = ChaseCamera.Mode.CHASE
				world.cam.cycle()
				world.cam.mode = ChaseCamera.Mode.CHASE
	if not is_instance_valid(world.sat_view):
		world.sat_view = SatView.new()
		world.sat_view.name = "SatView"
		world.add_child(world.sat_view)
	var held := is_instance_valid(world.deploy_ui) and world.deploy_ui.visible
	if held:
		world.deploy_ui.visible = false
	world.sat_view.descend(target, cam, world.hud, func() -> void:
		if held and is_instance_valid(world.deploy_ui) and is_instance_valid(world.cqb) \
				and not world.deploy_ui.visible:
			world.deploy_ui.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE,
		SatView.INTRO_FROM, SatView.INTRO_SECS, follow)

## The hangar's backdrop: the planet from orbit, held over whatever the menu
## has picked. False where there is no round planet to show, or headless.
func menu_backdrop() -> bool:
	if not Sim.globe or DisplayServer.get_name() == "headless" or world.running:
		return false
	if not is_instance_valid(world.sat_view):
		world.sat_view = SatView.new()
		world.sat_view.name = "SatView"
		world.add_child(world.sat_view)
	world.sat_view.menu_panel = world.menu
	world.sat_view.enter_menu()
	# what the hangar has picked is got ready from the start; the view only
	# goes to it once something is picked
	menu_refocus(false)
	return true

## Where a mission picked in the hangar takes place, on the chart.
func mission_target(mission: String) -> Vector3:
	if mission in ["cqb", "ground", "arms", "range"] and is_instance_valid(world.scenery) \
			and not world.scenery.sites.is_empty():
		var c: Vector2 = world.scenery.sites[clampi(CqbMatch.town, 0, world.scenery.sites.size() - 1)]["c"]
		return Vector3(c.x, 0.0, c.y)
	if mission == "carrier" and is_instance_valid(world.carrier):
		return world.carrier.global_position
	if mission in ["takeoff", "ramp", "sandbox", "landing", "launch", "moon"]:
		return Vector3.ZERO
	# the air starts, a few kilometres short of the field
	return Vector3(-600.0, 0.0, 7000.0)

## The mission or the town in the hangar has changed: the backdrop goes to
## it (back from the turntable if that was up), and what can be got ready
## there ahead of LAUNCH is started -- the ground, and a town's set.
func menu_refocus(glide := true) -> void:
	if world.running or world.booting or not Sim.globe \
			or DisplayServer.get_name() == "headless":
		return
	if not is_instance_valid(world.sat_view):
		return
	var mission := String(world.menu.mission_id)
	var target: Vector3 = mission_target(mission)
	if not world.sat_view.in_menu():
		world.preview.visible = false
		world.sat_view.enter_menu()
	world.sat_view.menu_focus(target, glide)
	if mission in ["cqb", "ground", "arms", "range"] and is_instance_valid(world.scenery) \
			and not world.scenery.sites.is_empty():
		var ts: TownSet = world.street_fight.town_set(clampi(CqbMatch.town, 0, world.scenery.sites.size() - 1), true)
		_presurvey_when_built(ts)

## Survey the town's routes for the match once its set is all standing: see
## `CqbMatch.presurvey`. Only while the hangar is still over it.
func _presurvey_when_built(ts: TownSet) -> void:
	while is_instance_valid(ts) and ts.building and not world.running:
		await world.get_tree().process_frame
	if is_instance_valid(ts) and not world.running:
		CqbMatch.presurvey(ts)

# ------------------------------------------------------------------ the mouse
## Whether the pointer is captured, worked out afresh every frame from what is
## on the screen and what you are in, and set only when it is wrong.
##
## Every screen used to take the mouse when it opened and hand back whatever it
## had found when it closed. Stacked -- the map open under the pause page, ESC
## pressed while freelook held it, a redeploy over the map, an aircraft swapped
## for a rifle while paused -- each put back a mode that was no longer true, and
## the pointer came back free in a firefight or stayed locked over a menu. Those
## places still set it, for the frame they act on; this has the last word.
func sync_mouse() -> void:
	if not world.running or world.booting:
		return
	var want := Input.MOUSE_MODE_CAPTURED if _wants_grab() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

## A screen that is worked with the pointer is up.
func pointer_screen() -> bool:
	return Sim.menu_open or world.get_tree().paused or Sim.ui_pointer \
		or (is_instance_valid(world.pause_menu) and world.pause_menu.visible) \
		or (is_instance_valid(world.menu) and world.menu.visible) \
		or (is_instance_valid(world.map) and world.map.visible) \
		or (is_instance_valid(world.deploy_ui) and world.deploy_ui.visible) \
		or (is_instance_valid(world.chat) and world.chat.typing) \
		or (is_instance_valid(world.sat_view) and world.sat_view.active())

## What you are in steers with the mouse.
func _wants_grab() -> bool:
	if pointer_screen():
		return false
	if world.on_foot:
		if not is_instance_valid(world.walker):
			return false
		# dead in a street fight the view goes over the shoulder and waits for
		# the deploy screen; dead anywhere else the pointer is wanted
		return not world.walker.dead or is_instance_valid(world.cqb)
	if is_instance_valid(world.rocket) and world.rocket.occupied:
		return true
	if is_instance_valid(world.tank) or is_instance_valid(world.ship) or world.crew.at_conn() \
			or world.gunning or (is_instance_valid(world.pod) and world.pod.active):
		return true
	# In a cockpit the pointer is captured too. It was left free unless the
	# mouse stick was on, so a jet spawned straight into the air had the
	# cursor sitting over the view, and resuming from the menu put it back
	# there: nothing in a cockpit is worked by pointing -- the map, the menus
	# and the sensor page are screens of their own above.
	return is_instance_valid(world.player) and world.player.alive

## Back in the window after another had it. The system lets go of a captured
## pointer when the window loses focus, but the mode still reads as captured,
## so `sync_mouse` saw nothing to put right and the view would not turn until
## something else took the mouse again. Let go and take it again.
func regrab() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sync_mouse()

# --------------------------------------------------------------- the presence
## Tell `Sim` what is really being played and sat in, for the Discord line.
func sync_presence() -> void:
	if not world.running:
		Sim.presence_mode = ""
		Sim.presence_seat = ""
		return
	var mode := String(Sim.mission)
	if is_instance_valid(world.cqb):
		mode = "range" if world.cqb.range_mode else ("arms" if world.cqb.air \
			else ("ground" if world.cqb.armour else "cqb"))
	Sim.presence_mode = mode
	var seat := ""
	if is_instance_valid(world.sat_view) and world.sat_view.active():
		seat = "@Watching from orbit"
	elif world.missions.in_rocket():
		seat = "@Riding a rocket"
	elif world.on_foot:
		seat = "@On foot"
	elif is_instance_valid(world.tank):
		seat = "@Driving " + String(world.tank.display_name())
	elif world.crew.at_conn() and is_instance_valid(world.carrier):
		seat = "@At the conn, " + String(world.carrier.display_name())
	elif is_instance_valid(world.ship):
		seat = "@In command, " + String(world.ship.display_name())
	elif world.gunning and is_instance_valid(world.player):
		seat = "@On the guns, " + String(world.player.display_name())
	elif is_instance_valid(world.player):
		seat = "@Flying " + String(world.player.display_name())
	# the deploy screen, a respawn: in the match, not in anything yet
	if seat == "" or (is_instance_valid(world.deploy_ui) and world.deploy_ui.visible):
		seat = "@Choosing what to go in as"
	Sim.presence_seat = seat

