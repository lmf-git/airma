class_name SessionTests
extends TestSuite
## Game modes, spawning, the pause and admin menus, chat and networking.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--pausetest":
		_pause_test = true
	elif a == "--admintest":
		_admin_test = true
	elif a == "--objtest":
		_obj_test = true
	elif a == "--modetest":
		_mode_test = true
	elif a.begins_with("--adminfrom="):
		_admin_test = true
		_admin_from = a.substr(12)
	elif a == "--restarttest":
		_restart_test = true
	elif a.begins_with("--restartmodes="):
		# each mode in turn, fought for a while, then the next: what is left
		# standing after each change is counted (see `MatchSweep.sweep`)
		_restart_test = true
		_restart_modes = a.substr(15).split(",")
		world.sweep.verbose = true
	elif a == "--sweeplog":
		world.sweep.verbose = true
	elif a == "--chattest":
		_chat_test = true
	elif a == "--warlordstest":
		_warlords_test = true
	elif a == "--respawntest":
		_respawn_test = true
	elif a == "--spawntest":
		_spawn_test = true
	elif a == "--factiontest":
		_faction_test = true
	elif a.begins_with("--holdnet="):
		_hn_role = a.substr(10)
	elif a.begins_with("--holdshots="):
		_hn_shots = a.substr(12)
	elif a == "--nettest":
		_nettest = true
	elif a.begins_with("--netport="):
		NetLink.port_override = int(a.substr(10))
	elif a == "--ejecttest":
		_ej_test = true
	elif a == "--redeploytest":
		_rd_test = true
	elif a.begins_with("--lobbytest="):
		_lb_role = a.substr(12)
	elif a.begins_with("--mpside="):
		_mp_side = int(a.substr(9))
	elif a.begins_with("--mphostside="):
		_mp_hostside = int(a.substr(13))
	elif a.begins_with("--mpflip="):
		_mp_flip = float(a.substr(9))
	elif a.begins_with("--mptest="):
		# two copies: --mptest=host, then --mptest=join on the same machine
		_mp_role = a.substr(9)
	else:
		return false
	return true


#region --pausetest
## ESC through the pause page, the settings page and the hangar and back.
var _pause_test := false

func tick_pause() -> bool:
	if _pause_test:
		_pause_test = false
		await _run_pause_test()
		return true
	return false

## ESC is the pause page and not the hangar; the settings page steps back to
## it; CHANGE MODE is the hangar and ESC from there is the pause page again;
## and a slider reaches its bus. Nothing is left changed in the settings file.
func _run_pause_test() -> void:
	world._start(world.jet_arg if world.jet_arg != "" else "f16", "free")
	for i in 30:
		await world.get_tree().physics_frame
	var bad: Array = []
	harness._press(KEY_ESCAPE)
	if not world.pause_menu.visible or world.menu.visible or not world.get_tree().paused:
		bad.append("ESC did not bring up the pause page by itself (pause %s, hangar %s, paused %s)" % [
			str(world.pause_menu.visible), str(world.menu.visible), str(world.get_tree().paused)])
	world.pause_menu._show_settings()
	var was: float = float(Sim.volumes[&"Effects"])
	(world.pause_menu._vol_sliders[&"Effects"] as HSlider).value = 40.0
	var bus := AudioServer.get_bus_index(&"Effects")
	if bus < 0 or absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.4)) > 0.05:
		bad.append("the effects slider did not reach its bus")
	(world.pause_menu._vol_sliders[&"Effects"] as HSlider).value = was * 100.0
	harness._press(KEY_ESCAPE)
	if not world.pause_menu.visible or world.pause_menu._settings.visible:
		bad.append("ESC on the settings page did not step back to the pause page")
	world.controls.pause_to_hangar()
	if not world.menu.visible or world.pause_menu.visible:
		bad.append("CHANGE MODE did not bring up the hangar")
	harness._press(KEY_ESCAPE)
	if world.menu.visible or not world.pause_menu.visible:
		bad.append("ESC on the hangar did not go back to the pause page")
	harness._press(KEY_ESCAPE)
	if world.pause_menu.visible or world.menu.visible or world.get_tree().paused:
		bad.append("ESC on the pause page did not resume")
	for b in bad:
		print("[pause] %s" % b)
	print("[pause] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --admintest --adminfrom=
var _admin_test := false
var _admin_t := 0.0
var _admin_from := ""

func tick_admin(delta: float) -> void:
	if _admin_test:
		_admin_t += delta
		if _admin_t > 3.0 and world.admin_desk.traffic.is_empty():
			# optionally get out of the aeroplane first: the report is that
			# traffic only flies its approach while the player is in one
			if _admin_from != "":
				if _admin_from == "ship":
					for sh in world.get_tree().get_nodes_in_group("ships"):
						var v := sh as Ship
						if v != null and v.has_gun() and v.team == 0:
							world.crew.enter_ship(v)
							break
				elif _admin_from == "tank":
					for v in world.get_tree().get_nodes_in_group("vehicles"):
						if v is Tank and (v as Tank).alive:
							world.crew.enter_tank(v as Tank)
							break
				elif _admin_from == "foot":
					world.crew.try_dismount()
				print("[admin] player is now in: %s (aeroplane valid=%s active=%s)" % [
					_admin_from, str(is_instance_valid(world.player)),
					str(world.player.active) if is_instance_valid(world.player) else "-"])
			world.admin.jet_id = "f16"
			world.admin_desk.do_admin("flight")
			if _admin_from != "":
				world.admin_desk.do_admin("follow")     # and watch them, from wherever we are
			print("[admin] called a flight of %d" % world.admin_desk.traffic.size())
		elif _admin_t > 8.0 and fmod(_admin_t, 25.0) < delta:
			for t in world.admin_desk.traffic:
				if not is_instance_valid(t):
					continue
				var view := "none"
				if is_instance_valid(world.cam) and world.cam.current:
					view = "chase->%s" % (String(world.cam.subject.name) \
						if is_instance_valid(world.cam.subject) else "-")
				elif is_instance_valid(world.ship) and is_instance_valid(world.ship.cam) \
						and world.ship.cam.current:
					view = "ship"
				print("[admin] %-12s auto=%-8s active=%s  z=%8.1f y=%6.1f thr=%.2f gnd=%s  view=%s" % [
					t.name, t.auto, str(t.active), t.global_position.z,
					t.global_position.y, t.throttle, str(t.on_ground), view])
				break
		elif _admin_t > 210.0:
			_admin_test = false
			var down := 0
			var flying := 0
			for t in world.admin_desk.traffic:
				if not is_instance_valid(t):
					continue
				if t.on_ground:
					down += 1
				else:
					flying += 1
			print("[admin] after 210 s: %d on the ground, %d still flying" % [down, flying])
			world.get_tree().quit()
#endregion


#region --objtest
## Shift and click on the map, and see the objective land where the click was
## and stay put with the map closed: --objtest.
var _obj_test := false
var _obj_t := 0.0

func tick_obj(delta: float) -> void:
	if _obj_test and world.running and is_instance_valid(world.player):
		_obj_t += delta
		if _obj_t > 3.0:
			_obj_test = false
			_run_obj_test()

func _run_obj_test() -> void:
	var bad := PackedStringArray()
	Sim.clear_objective()
	if not world.map.visible:
		world.map.toggle()
	await world.get_tree().process_frame
	var c: Vector2 = world.map.get_viewport_rect().size * 0.5 + Vector2(12.0, -8.0)
	var want: Vector2 = world.map._globe_point(c) if world.map.globe else Vector2.INF
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.shift_pressed = true
	click.position = c
	world.map._gui_input(click)
	if Sim.objective == Vector3.INF:
		bad.append("shift+click set no objective")
	else:
		var off: float = Vector2(Sim.objective.x - want.x, Sim.objective.z - want.y).length() \
			if want.x != INF else 0.0
		print("[obj] shift+click set the objective %.1f km from the aircraft, %.1f m from the point under the cursor" % [
			Vector2(Sim.objective.x - world.player.global_position.x,
				Sim.objective.z - world.player.global_position.z).length() * 0.001, off])
		if off > 5.0:
			bad.append("objective landed %.0f m from the click" % off)
	world.map.toggle()
	await world.get_tree().process_frame
	if Sim.objective == Vector3.INF:
		bad.append("the objective went away with the map")
	# and a second shift+click on it takes it off again
	world.map.toggle()
	await world.get_tree().process_frame
	world.map._gui_input(click)
	if Sim.objective != Vector3.INF:
		bad.append("a second shift+click did not clear it")
	for b in bad:
		print("[obj]   ", b)
	print("[obj] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --modetest
## What is on each side of a mode, whether the armour goes anywhere, and whether
## anything is shooting at the player: --modetest with --preset=MODE:JET.
var _mode_test := false
var _mode_t := 0.0
var _mode_pos: Dictionary = {}
var _mode_at_player := 0
var _mode_seen: Dictionary = {}

func tick_mode(delta: float) -> void:
	if _mode_test and world.running and is_instance_valid(world.player):
		_tick_mode_test(delta)

func _tick_mode_test(delta: float) -> void:
	_mode_t += delta
	# rounds sent at the player, counted once each
	for m in world.get_tree().get_nodes_in_group("missiles"):
		if is_instance_valid(m) and not _mode_seen.has(m) and m.get("target") == world.player:
			_mode_seen[m] = true
			_mode_at_player += 1
	if _mode_t > 8.0 and _mode_pos.is_empty():
		for n in world.get_tree().get_nodes_in_group("hittable"):
			if n is Tank and (n as Tank).ai and (n as Tank).alive:
				_mode_pos[n] = (n as Node3D).global_position
	if _mode_t < 50.0:
		return
	_mode_test = false
	var tanks := {0: 0, 1: 0}
	var air := {0: 0, 1: 0}
	var moved := 0
	var far := 0.0
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not ("team" in n):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var tm: int = int(n.team)
		if n is Tank and (n as Tank).ai:
			tanks[tm] = int(tanks.get(tm, 0)) + 1
			if _mode_pos.has(n):
				var dd: float = (n as Node3D).global_position.distance_to(_mode_pos[n])
				far = maxf(far, dd)
				if dd > 40.0:
					moved += 1
		elif n is Aircraft and n != world.player:
			air[tm] = int(air.get(tm, 0)) + 1
	print("[modes] %s: aircraft ours %d / theirs %d, armour ours %d / theirs %d" % [
		Sim.mission, int(air.get(0, 0)), int(air.get(1, 0)), int(tanks.get(0, 0)),
		int(tanks.get(1, 0))])
	print("[modes] %d of %d AI vehicles moved more than 40 m in 42 s (furthest %.0f m)" % [
		moved, _mode_pos.size(), far])
	# and what the ones that did not are doing about it
	for n2 in _mode_pos.keys():
		if not is_instance_valid(n2) or not (n2 as Tank).alive:
			continue
		var tk := n2 as Tank
		if tk.global_position.distance_to(_mode_pos[n2]) > 40.0:
			continue
		var gd: float = tk.global_position.distance_to(tk.ai_goal) \
			if tk.ai_goal != Vector3.INF else -1.0
		var here2: float = Sim.height_at(tk.global_position.x, tk.global_position.z)
		print("[modes]   stuck: %s (%s) speed %.1f, throttle %.2f steer %+.2f brake %s, target %s, goal %.0f m away, %.1f m off the ground, up %.2f" % [
			tk.name, tk.kind, tk.speed, tk.in_throttle, tk.in_steer, str(tk.in_brake),
			Sim.label_of(tk._ai_target), gd, tk.global_position.y - here2,
			tk.global_transform.basis.y.dot(Vector3.UP)])
	print("[modes] rounds sent at the player: %d; player %s" % [_mode_at_player,
		"alive" if is_instance_valid(world.player) and world.player.alive else "DOWN"])
	if world.mode != null:
		print("[modes] mode state: wave %d, %d strike targets left, kills %s" % [
			world.mode.wave, world.mode._strike_left(), str(world.mode.kills)])
	world.get_tree().quit()
#endregion


#region --restarttest
var _restart_test := false
var _restart_t := 0.0
var _restart_n := 0
var _restart_modes: PackedStringArray = []

## What is in the world right now that a match put there.
func _restart_report() -> void:
	var kinds := {}
	for n in world.get_children():
		var k: String = n.get_script().get_global_name() if n.get_script() != null else ""
		if k == "":
			k = n.get_class()
		kinds[k] = int(kinds.get(k, 0)) + 1
	var groups := {}
	for g in ["infantry", "hittable", "missiles", "vehicles", "ships", "bandits"]:
		groups[g] = world.get_tree().get_nodes_in_group(g).size()
	print("[restart] %s children=%d groups=%s" % [String(Sim.mission),
		world.get_child_count(), str(groups)])

func tick_restart(delta: float) -> bool:
	if _restart_test:
		_restart_t += delta
		if not _restart_modes.is_empty():
			if _restart_t > 12.0:
				_restart_t = 0.0
				if _restart_n >= _restart_modes.size():
					_restart_test = false
					_restart_report()
					world.get_tree().quit()
					return true
				var m: String = _restart_modes[_restart_n]
				_restart_n += 1
				_restart_report()
				print("[restart] -> %s" % m)
				world._start("foot" if m in ["cqb", "range"] else "f16", m)
				# set the fight off: a nuke and a strike in a street fight,
				# missiles in the air anywhere else
				if is_instance_valid(world.cqb) and not world.cqb.range_mode:
					var c: Vector2 = world.cqb.centre
					world.cqb.streaks.add_nuke(3.0, Vector3(c.x + 40.0, Sim.height_at(c.x + 40.0, c.y),
						c.y), Killstreaks.TAC_LETHAL, false)
					world.cqb.streaks.bomb(Vector3(c.x - 30.0, 0.0, c.y), 1.0, true)
			return true
		if _restart_t > 3.0 and _restart_n < 3:
			_restart_n += 1
			# swap aircraft and restart, which is what the player was doing
			var picks := ["f22", "veh:m270", "f16"]
			_restart_t = 0.0
			world._start(picks[_restart_n - 1], "ramp")
			return true
		elif _restart_t > 3.0:
			_restart_test = false
			var craft := 0
			for n in world.get_tree().get_root().find_children("*", "Node3D", true, false):
				if is_instance_valid(n) and ("spec" in n) and (n.get("spec") is Dictionary):
					craft += 1
			print("[restart] after %d restarts: %d aircraft in the world" % [_restart_n, craft])
			world.get_tree().quit()
	return false
#endregion


#region --chattest
var _chat_test := false
var _chat_t := 0.0
var _chat_step := 0

# Does the chat line take a message without the aeroplane flying itself.
func tick_chat(delta: float) -> void:
	if _chat_test and is_instance_valid(world.player):
		_chat_t += delta
		if _chat_t > 1.5 and _chat_step == 0:
			_chat_step = 1
			harness._press(KEY_SLASH)
			print("[chat] after '/': typing=%s modal=%s" % [str(world.chat.typing),
				str(Sim.typing)])
		elif _chat_t > 2.0 and _chat_step == 1:
			_chat_step = 2
			# "wasd" is throttle, pitch and roll; here it has to be four letters
			var roll_before := world.player.in_roll
			var pitch_before := world.player.in_pitch
			for c in "wasd on the deck".to_utf8_buffer():
				harness._press(KEY_A, c)
			print("[chat] typed %d chars, draft=%s" % [world.chat.draft.length(), world.chat.draft])
			print("[chat] stick while typing: roll %+.2f -> %+.2f, pitch %+.2f -> %+.2f" % [
				roll_before, world.player.in_roll, pitch_before, world.player.in_pitch])
		elif _chat_t > 2.5 and _chat_step == 2:
			_chat_step = 3
			harness._press(KEY_ENTER)
			print("[chat] after enter: typing=%s, backlog=%d, last=%s" % [
				str(world.chat.typing), world.chat.log_lines.size(),
				String(world.chat.log_lines[-1]["text"]) if not world.chat.log_lines.is_empty() else "-"])
			print("[chat] RESULT: %s" % ("ok" if not world.chat.typing \
				and not world.chat.log_lines.is_empty() \
				and String(world.chat.log_lines[-1]["text"]) == "wasd on the deck" \
				else "FAILED"))
			world.get_tree().quit()
#endregion


#region --warlordstest
var _warlords_test := false

# Warlords over the whole country: how many sectors there are, whether they
# are actually the places on the map, what a frame of it costs, and whether
# the command point economy pays anything.
func tick_warlords() -> bool:
	if _warlords_test:
		_warlords_test = false
		world._start("f16", "warlords")
		await world.get_tree().process_frame
		await world.get_tree().physics_frame
		var st: Dictionary = world.mode.hud_state()
		var zs: Array = st["zones"]
		print("[wl] %d sectors" % zs.size())
		var labels := {}
		var dupes := 0
		var placed := 0
		for z in zs:
			var lb: String = String(z["label"])
			if labels.has(lb):
				dupes += 1
			labels[lb] = true
			if String(z["place"]) != "":
				placed += 1
		print("[wl] labels unique: %s; %d of them named after somewhere" % [
			str(dupes == 0), placed])
		# every settlement should be worth taking
		var towns: int = world.scenery.sites.size()
		var matched := 0
		for t in world.scenery.sites:
			var tc: Vector2 = t["c"]
			for z2 in zs:
				var p: Vector3 = z2["pos"]
				if Vector2(p.x - tc.x, p.z - tc.y).length() < 60.0:
					matched += 1
					break
		print("[wl] %d of %d settlements are sectors" % [matched, towns])
		# garrisons are lazy: only the live one should be standing
		var built := 0
		for z3 in world.mode.zones:
			if (z3 as CaptureZone).has_garrison():
				built += 1
		print("[wl] garrisons standing at kick-off: %d of %d" % [built, world.mode.zones.size()])
		# what a frame of the mode costs with this many sectors
		var t0 := Time.get_ticks_usec()
		for f in 120:
			world.mode._process(1.0 / 60.0)
		var per := float(Time.get_ticks_usec() - t0) / 120000.0
		print("[wl] GameMode._process costs %.3f ms a frame over %d sectors" % [
			per, world.mode.zones.size()])
		# and the economy: hand ourselves some ground and see it pay
		for i in mini(4, world.mode.zones.size()):
			var z4: CaptureZone = world.mode.zones[i]
			z4.owner_team = 0
			z4.progress = 1.0
		var cp0: int = world.mode.command_points
		for f2 in 600:
			world.mode._process(1.0 / 60.0)
		var st2: Dictionary = world.mode.hud_state()
		var gained: int = world.mode.command_points - cp0
		print("[wl] holding 4 sectors pays %.0f points a minute; 10 s gave %d" % [
			float(st2["cp_rate"]), gained])
		print("[wl] banner reports %d held, objective '%s'" % [
			int(st2["held"]), str(st2["objective"])])
		# Nothing may be standing inside anything else.
		var vs: Array = []
		for v2 in world.get_tree().get_nodes_in_group("vehicles"):
			if is_instance_valid(v2):
				vs.append((v2 as Node3D).global_position)
		var stacked := 0
		var closest := 1e9
		for i6 in vs.size():
			for j6 in range(i6 + 1, vs.size()):
				var gap: float = Vector2(vs[i6].x - vs[j6].x,
					vs[i6].z - vs[j6].z).length()
				closest = minf(closest, gap)
				if gap < 9.0:
					stacked += 1
		print("[wl] %d vehicles on the map, closest pair %.1f m apart, %d overlapping" % [
			vs.size(), closest if vs.size() > 1 else 0.0, stacked])
		var ok: bool = stacked == 0 and zs.size() >= 14 and dupes == 0 and matched == towns \
			and built <= 2 and per < 1.5 and float(st2["cp_rate"]) > 0.0 \
			and gained > 0 and str(st2["objective"]) != ""
		print("[wl] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --respawntest
var _respawn_test := false
var _respawn_t := 0.0
var _respawn_step := 0

# Lose the boat, press R, and see what you come back in.
func tick_respawn(delta: float) -> bool:
	if _respawn_test:
		_respawn_t += delta
		if _respawn_step == 0 and _respawn_t > 2.0:
			_respawn_step = 1
			world.menu._select("sea:sub")
			world._start("sea:sub", "free")
			print("[respawn] started with \"sea:sub\"; crewing %s" % [
				Sim.label_of(world.ship) if is_instance_valid(world.ship) else "nothing"])
		elif _respawn_step == 1 and _respawn_t > 4.0:
			_respawn_step = 2
			if is_instance_valid(world.ship):
				print("[respawn] sinking the boat under us")
				world.ship.take_hit(999999.0, null)
			print("[respawn] the menu still holds \"%s\"" % str(world.menu.jet_id))
		elif _respawn_step == 2 and _respawn_t > 6.0:
			_respawn_step = 3
			# the menu is the only way back: launch again from what it holds
			world._start(String(world.menu.jet_id), Sim.mission)
		elif _respawn_step == 3 and _respawn_t > 8.0:
			_respawn_test = false
			var back: String = Sim.label_of(world.ship) if is_instance_valid(world.ship) else "nothing"
			var kind: String = str(world.ship.kind) if is_instance_valid(world.ship) else "-"
			print("[respawn] after restart: crewing %s (kind %s), aeroplane=%s" % [
				back, kind, "yes" if is_instance_valid(world.player) else "no"])
			print("[respawn] RESULT: %s" % ("ok" if kind == "sub"
				else "FAILED — came back in %s, not the boat" % back))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --spawntest
var _spawn_test := false
var _spawn_t := 0.0

func tick_spawn(delta: float) -> bool:
	if _spawn_test:
		_spawn_t += delta
		if _spawn_t > 2.5:
			_spawn_test = false
			var bad := 0
			# and the same going the other way: crew a boat first, so a
			# selection has to actually let go of it
			world._start("sea:sub", "free")
			await world.get_tree().process_frame
			await world.get_tree().physics_frame
			print("[spawn] started in a boat: crewing %s" % [
				Sim.label_of(world.ship) if is_instance_valid(world.ship) else "nothing"])
			for k in VehicleSpec.KINDS.keys():
				world._start("veh:" + String(k), "free")
				await world.get_tree().process_frame
				await world.get_tree().physics_frame
				var got: String = world.tank.kind if is_instance_valid(world.tank) else "-"
				var ok: bool = got == String(k) and not is_instance_valid(world.ship)
				if not ok:
					bad += 1
				# and it should not look like every other vehicle on the field
				var mesh_names := PackedStringArray()
				if is_instance_valid(world.tank):
					for ch in world.tank.get_children():
						if ch is MeshInstance3D:
							mesh_names.append(String(ch.name))
				print("[spawn]   body: %s" % ", ".join(mesh_names))
				# The crew have to be IN it and the gun has to be clear of it.
				# Both are placed by hand per class, and a station written for a
				# tank's three-metre hull puts a light 4x4's driver a metre
				# above his own roof and its muzzle inside the bonnet.
				if is_instance_valid(world.tank):
					var inv := world.tank.global_transform.affine_inverse()
					var crew: Vector3 = inv * world.tank.crew_position()
					var muz: Vector3 = inv * world.tank._muzzle.global_position
					var seated: bool = world.tank.bounds.grow(0.35).has_point(crew)
					# A muzzle deep inside the bodywork is a gun firing through
					# its own vehicle — but a launcher's rails STOW flat along
					# the deck and are raised before anything leaves them, so
					# the stowed tube mouth sitting over the cab is correct and
					# this does not apply to them.
					var launcher: bool = world.tank.vclass() == "tel" \
						or world.tank.vclass() == "sam"
					var buried: bool = not launcher \
						and world.tank.bounds.grow(-0.45).has_point(muz)
					var sight: float = world.tank.sight_height()
					var roof: float = world.tank.bounds.end.y
					var perched: bool = sight > roof + 1.2
					if not seated or buried or perched:
						bad += 1
					print("[spawn]   crew %s, muzzle %s, sight %.2f m vs roof %.2f m%s" % [
						"seated" if seated else "OUTSIDE THE VEHICLE",
						"BURIED IN THE BODY" if buried else "clear",
						sight, roof, "   <- PERCHED" if perched else ""])
				print("[spawn] chose %-13s -> %s%s" % [String(k),
					"in the %s" % VehicleSpec.KINDS[got]["name"] if ok
					else "STILL ON THE BOAT" if is_instance_valid(world.ship)
					else "NOT IN IT (crewing %s, aeroplane=%s)" % [got,
						"yes" if is_instance_valid(world.player) else "no"],
					"" if ok else "   <- WRONG"])
			print("[spawn] RESULT: %s" % ("ok" if bad == 0 else
				"FAILED — %d vehicle(s) wrong: not crewed, crew outside it, or gun in the bodywork" % bad))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --factiontest
var _faction_test := false

# Six countries, and no centre.
func tick_faction() -> bool:
	if _faction_test:
		_faction_test = false
		_run_faction_test()
		world.get_tree().quit()
		return true
	return false

## The countries.
##
## There is no centre to this planet and no main airfield, so what has to be
## true is true of all six equally: each has land under it, each is far enough
## from the others to be somewhere else and near enough to fly to, and whichever
## one you start in is the one the world is built around.
func _run_faction_test() -> void:
	var names: Array = Sim.HOMELANDS.keys()
	var wet := 0
	var nearest := 1e30
	var furthest := 0.0
	print("[faction] flying for %s; the chart's origin is its aerodrome" % Sim.home_faction)
	for who in names:
		var d: Vector3 = Sim.homeland_dir(String(who))
		var q: Vector2 = Sim.dir_to_chart(d)
		# Land under it, looked at as its own country rather than through this
		# one's chart: a place 1300 km off is still a place.
		var elev: float = Sim.height_at(q.x, q.y) - Sim.sea_at(q.x, q.y)
		if elev <= 0.0:
			wet += 1
		var km: float = q.length() * 0.001
		if String(who) != Sim.home_faction:
			nearest = minf(nearest, km)
			furthest = maxf(furthest, km)
		print("[faction]   %-7s %6.0f km off, ground %5.0f m above its own sea" % [
			String(who), km, elev])
	print("[faction] the nearest other country is %.0f km, the furthest %.0f km" % [
		nearest, furthest])
	# The aerodrome is at the middle of the chart whoever you fly for, because
	# the chart is put on the country you began in.
	var home_up: float = Sim.height_at(0.0, 0.0) - Sim.sea_at(0.0, 0.0)
	var has_field: bool = not Sim.fields.is_empty()
	print("[faction] the aerodrome stands %.0f m above sea at the middle of the chart; registered: %s" % [
		home_up, str(has_field)])
	# Spread over the planet, not clustered on one continent.
	#
	# This asked for the nearest other country to be inside 2500 km, which is
	# what the old written-down table gave: six latitudes and longitudes within
	# twenty degrees of each other, with the terrain raised under all of them.
	# They are searched for on the planet's own land now, so how far apart they
	# come out is a fact about the terrain -- and they should be far apart,
	# because a planet with six nations huddled in one corner of it is not a
	# planet. What still has to hold is that every one of them is on dry land.
	print("[faction] RESULT: %s" % ("ok" if wet == 0 and has_field
		and home_up > 0.0 and nearest > 2000.0
		else "FAILED — %d of %d countries are under water" % [wet, names.size()]))
#endregion


#region --holdnet
## Two copies of the game on one machine, networked, watching the same thing:
## a C-130 flown by the host, first straight and level and then in an orbit,
## with the client's man on foot in its hold -- walking up and down it, then
## standing still. Each window shows the hold from a camera fixed inside it,
## with a chase view from outside in the corner, and each logs once a second
## where the passenger is in the hold as that machine sees it. The client's
## numbers are the man himself; the host's are his ghost. Put side by side
## (tools/holdnet.sh does all of it) they say whether the two agree, how far
## the ghost lags and jitters, and whether anyone falls out of the aircraft.
##   --preset=free:c130 --holdnet=host|join [--holdshots=dir]
var _hn_role := ""
var _hn_shots := ""
var _hn_t := -1.0
var _hn_log := 0.0
var _hn_shot := 0.0
var _hn_boarded := false
var _hn_cam_in: Camera3D = null
var _hn_cam_out: Camera3D = null
var _hn_view: SubViewport = null
var _hn_prev := Vector3.INF
var _hn_seen := 0.0
## The carrier's step from one physics tick to the next, as this machine moves
## it: how even it is says whether the hold -- and everyone in it -- is carried
## smoothly or jerked along.
var _hn_jet_prev := Vector3.INF
var _hn_steps: Array = []
var _hn_pf_prev := 0
var _hn_had_peer := false
var _hn_jit := 0.0
var _hn_jn := 0
## The host flies level for this long, then orbits.
const HN_LEVEL := 30.0
## The client walks up and down the hold this long after boarding, then stands.
const HN_WALK := 40.0
const HN_STAND := 20.0
## Seconds since the client got aboard.
var _hn_aboard := 0.0

func _hn_phase() -> String:
	if _hn_role == "host":
		return "level" if _hn_t < HN_LEVEL else "orbit"
	if not _hn_boarded:
		return "not aboard"
	return "walking" if _hn_aboard < HN_WALK else "standing still"

func tick_holdnet(delta: float) -> void:
	if _hn_role == "" or not world.running or world.net == null:
		return
	if _hn_t < 0.0:
		_hn_t = 0.0
		if _hn_role == "host":
			world.net.host("c130")
			_hn_fly_setup()
		else:
			world.net.join("127.0.0.1", "c130")
		print("[holdnet] %s up" % _hn_role)
		return
	_hn_t += delta
	var jet: Aircraft = _hn_jet()
	if _hn_role == "host":
		if is_instance_valid(world.player):
			if _hn_t > HN_LEVEL and world.player.ap_mode != "loiter":
				world.player.set_autopilot("loiter")
	else:
		# A joiner restarts into the host's mission, which takes the man it
		# was given away with the old one: board (again) once that is done
		# and the host's aeroplane has been heard from for a while.
		if _hn_boarded and (not is_instance_valid(world.walker) or world.walker.frame == null):
			_hn_boarded = false
		if not _hn_boarded and is_instance_valid(jet) and jet.has_hold() and jet.has_meta("t_rx") \
				and String(Sim.mission) == "free":
			_hn_seen += delta
			if _hn_seen > 3.0:
				_hn_board(jet)
		if _hn_boarded and is_instance_valid(world.walker):
			_hn_aboard += delta
			_hn_walk()
	if is_instance_valid(jet) and jet.has_hold():
		_hn_cameras(jet)
	_hn_log += delta
	if _hn_log >= 1.0:
		_hn_log = 0.0
		_hn_report(jet)
	_hn_measure()
	if is_instance_valid(jet):
		var hp: Vector3 = jet.hold_node().global_position
		# Per physics tick, which is when it moves: a screen frame covers one,
		# two or three of those, and measured per frame that alone read as
		# the aircraft lurching.
		var pf: int = Engine.get_physics_frames()
		if _hn_jet_prev != Vector3.INF and pf > _hn_pf_prev and _hn_t > 8.0:
			_hn_steps.append(hp.distance_to(_hn_jet_prev) / float(pf - _hn_pf_prev))
		_hn_jet_prev = hp
		_hn_pf_prev = pf
	if _hn_shots != "":
		_hn_shot += delta
		if _hn_shot >= 5.0:
			_hn_shot = 0.0
			var img: Image = world.get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%03d.png" % [_hn_shots, _hn_role, int(_hn_t)])
	var finished: bool = _hn_aboard > HN_WALK + HN_STAND if _hn_role == "join" \
		else (_hn_t > 240.0 or (_hn_had_peer and world.net.roster.size() <= 1))
	if _hn_role == "host" and world.net.roster.size() > 1:
		_hn_had_peer = true
	if finished:
		print("[holdnet] %s done: passenger jitter in the hold, frame to frame, mean %.3f m" % [
			_hn_role, _hn_jit / maxf(float(_hn_jn), 1.0)])
		# the carrier: each tick's step against its neighbours' average
		var uneven := 0.0
		var worst := 0.0
		var n := 0
		for i in range(2, _hn_steps.size() - 2):
			var around: float = (float(_hn_steps[i - 2]) + float(_hn_steps[i - 1])
				+ float(_hn_steps[i + 1]) + float(_hn_steps[i + 2])) * 0.25
			if around < 0.01:
				continue
			var e: float = absf(float(_hn_steps[i]) - around) / around
			uneven += e
			worst = maxf(worst, e)
			n += 1
		print("[holdnet] %s done: the aircraft carrying him moves unevenly by %.0f%% a tick on average, %.0f%% at worst (%d ticks)" % [
			_hn_role, uneven / maxf(float(n), 1.0) * 100.0, worst * 100.0, n])
		world.net.leave()
		world.get_tree().quit()

## The transport everyone is in: the host's own, or the host's ghost.
func _hn_jet() -> Aircraft:
	if _hn_role == "host":
		return world.player
	for pid in world.net.ghosts:
		var g: Variant = world.net.ghosts[pid]
		if is_instance_valid(g) and (g as Aircraft).has_hold():
			return g
	return null

## The host's C-130 up at a height and a speed to carry people, level.
func _hn_fly_setup() -> void:
	var p: Aircraft = world.player
	if not is_instance_valid(p):
		return
	var at := Vector3(0.0, Sim.height_at(0.0, -6000.0) + 1500.0, -6000.0)
	p.global_transform = Transform3D(Basis.IDENTITY, at)
	p.linear_velocity = Vector3(0, 0, -105.0)
	p.gear_down = false
	p.gear_anim = 0.0
	p.throttle = 0.7
	p.power = 0.7
	p.active = true
	world._reset_interp.call_deferred(p)
	p.set_autopilot("hold")

## On the client: its own aeroplane out of the way, and its man into the hold
## of the host's.
func _hn_board(jet: Aircraft) -> void:
	if is_instance_valid(world.player):
		world.player.active = false
		world.player.freeze = true
		world.player.global_position += Vector3(0, -3000, 0)
		world.player.visible = false
	var hold: Node3D = jet.hold_node()
	world.crew.spawn_walker(hold.global_position)
	world.walker.global_transform = hold.global_transform
	world.walker.enter_frame(hold, jet)
	world.walker.activate()
	world.walker.yaw = 0.0          # facing up the hold
	_hn_boarded = true
	print("[holdnet] client: boarded the host's %s" % jet.name)

## Up the hold and back for the first minute, then still.
func _hn_walk() -> void:
	var still: bool = _hn_aboard > HN_WALK
	var fwd: bool = fmod(_hn_aboard, 8.0) < 4.0
	Input.action_release(&"pitch_down")
	Input.action_release(&"pitch_up")
	if not still:
		Input.action_press(&"pitch_down" if fwd else &"pitch_up", 0.5)
		world.walker.hold_ads = false
		return
	# standing: on the sights, a round every two seconds up the hold, so the
	# other machine has a man aiming and firing to show
	world.walker.hold_ads = true
	world.walker.yaw = 0.0
	world.walker.pitch = -0.05
	if fmod(_hn_aboard, 2.0) < 0.1:
		Input.action_press(&"foot_fire")
	else:
		Input.action_release(&"foot_fire")

## The view: from the back of the hold up it, with the outside in a corner.
func _hn_cameras(jet: Aircraft) -> void:
	var hold: Node3D = jet.hold_node()
	if not is_instance_valid(_hn_cam_in):
		_hn_cam_in = Camera3D.new()
		_hn_cam_in.name = "HoldCam"
		_hn_cam_in.near = 0.05
		_hn_cam_in.fov = 80.0
		hold.add_child(_hn_cam_in)
		_hn_cam_in.position = Vector3(0.0, 1.9, 5.5)
		_hn_cam_in.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
		var box := SubViewportContainer.new()
		box.stretch = true
		box.size = Vector2(420, 260)
		box.position = Vector2(12, 12)
		_hn_view = SubViewport.new()
		_hn_view.world_3d = world.get_viewport().world_3d
		_hn_view.size = Vector2i(420, 260)
		box.add_child(_hn_view)
		_hn_cam_out = Camera3D.new()
		_hn_cam_out.far = 20000.0
		_hn_view.add_child(_hn_cam_out)
		var layer := CanvasLayer.new()
		layer.layer = 50
		layer.add_child(box)
		world.add_child(layer)
	# the host watches from the back of the hold; the client is the man, seen
	# over his shoulder, since his own camera has to be the one in use for
	# him to move at all
	if _hn_role == "join" and is_instance_valid(world.walker):
		world.walker.third = true
		world.walker.cam.current = true
	else:
		_hn_cam_in.current = true
	# outside, off the left quarter and a little above, looking at it
	var xf: Transform3D = jet.get_global_transform_interpolated()
	var eye: Vector3 = xf.origin + xf.basis * Vector3(-45.0, 12.0, 35.0)
	_hn_cam_out.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(xf.origin, xf.basis.y)

## Where the passenger is in the hold, as this machine has him.
func _hn_passenger() -> Node3D:
	if _hn_role == "join":
		return world.walker if _hn_boarded and is_instance_valid(world.walker) else null
	for pid in world.net.foot_ghosts:
		var g: Variant = world.net.foot_ghosts[pid]
		if is_instance_valid(g):
			return g
	return null

func _hn_measure() -> void:
	var p: Node3D = _hn_passenger()
	if p == null:
		_hn_prev = Vector3.INF
		return
	var jet: Aircraft = _hn_jet()
	if not is_instance_valid(jet) or p.get_parent() != jet.hold_node():
		return
	# only while he stands still: walking moves him on purpose. The host
	# does not know when that is; it takes the last stretch it saw him in
	# without moving at all.
	var standing: bool = _hn_aboard > HN_WALK + 2.0 if _hn_role == "join" \
		else (_hn_prev != Vector3.INF and p.position.distance_to(_hn_prev) < 0.05)
	if standing or _hn_prev == Vector3.INF:
		if _hn_prev != Vector3.INF:
			_hn_jit += p.position.distance_to(_hn_prev)
			_hn_jn += 1
		_hn_prev = p.position

func _hn_report(jet: Aircraft) -> void:
	var p: Node3D = _hn_passenger()
	var in_hold := false
	var local := Vector3.INF
	var wp := Vector3.INF
	if p != null:
		wp = p.global_position
		in_hold = is_instance_valid(jet) and p.get_parent() == jet.hold_node()
		local = p.position if in_hold else (jet.hold_node().global_transform.affine_inverse() * wp
			if is_instance_valid(jet) else Vector3.INF)
	var spd: float = jet.linear_velocity.length() if is_instance_valid(jet) else 0.0
	var bank: float = rad_to_deg(asin(clampf(-jet.global_transform.basis.x.y, -1.0, 1.0))) \
		if is_instance_valid(jet) else 0.0
	print("[holdnet] %s w=%d t=%5.1f %-22s jet %s %3.0f m/s bank %+4.0f | passenger %s in hold %s at %s" % [
		_hn_role, int(Time.get_unix_time_from_system() * 1000.0), _hn_t, _hn_phase(), "up" if is_instance_valid(jet) else "--", spd, bank,
		"seen" if p != null else "none", in_hold, str(local.snapped(Vector3.ONE * 0.01))])
#endregion

#region --nettest
var _nettest := false

func tick_nettest() -> void:
	if _nettest and world.net != null:
		_nettest = false
		print("[net] before hosting: %s" % world.net.status_line())
		print("[net] local address: %s" % world.net.local_ip())
		var ok := world.net.host("f16")
		print("[net] host() -> %s, listening on %d" % [str(ok), world.net.port])
		print("[net] hangar shows: %s" % world.net.status_line())
		print("[net] join address: %s" % world.net.join_address())
		# and again, without leaving, which used to be fatal
		var ok2 := world.net.host("f16")
		print("[net] host() a second time without leaving -> %s, port %d" % [
			str(ok2), world.net.port])
		world.net.shutdown()
		print("[net] after shutdown(): active=%s" % str(world.net.active))
		world.net.leave()
		print("[net] after leave: %s" % world.net.status_line())
		var ok3 := world.net.host("f16")
		print("[net] host() after leave -> %s, port %d" % [str(ok3), world.net.port])
		world.net.leave()
		world.get_tree().quit()
#endregion


#region --mptest
## A session across the modes, from both ends. The host starts a ground fight,
## restarts it, changes to STRIKE and then to CQB; the client follows and once
## a second says what it is looking at -- which match, how many of the host's
## men and vehicles it has pictures of -- and puts rounds into the nearest of
## the host's men, which only the host can kill. The host says what it is
## running and what it has been sent.
##   --preset=ground:foot --mptest=host     then     --preset=ground:foot --mptest=join
var _mp_role := ""
## The client's side: 0 BLUE with the host, 1 RED against it.
var _mp_side := 0
var _mp_hostside := 0
## Seconds into the session at which the client changes side, or -1.
var _mp_flip := -1.0
var _mp_cqb_t := 0.0
var _mp_act := 0
var _mp_ammo0 := 0
var _mp_t := 0.0
var _mp_said := 0.0
var _mp_step := 0
var _mp_shot := 0.0

func tick_mptest(delta: float) -> void:
	if _mp_role == "" or world.net == null:
		return
	_mp_t += delta
	if _mp_role == "host" and _mp_step == 0 and world.running:
		_mp_step = 1
		world.net.host("f16")
		world.net.set_side(_mp_hostside)
		world.net.running_mission = String(world.menu.mission_id) if world.menu != null else "ground"
		world.net.running_mission = "ground"
		print("[mp] host: hosting, running ground")
	elif _mp_role == "join" and _mp_step == 0 and world.running:
		_mp_step = 1
		world.net.set_side(_mp_side)
		world.net.join("127.0.0.1", "f16")
		print("[mp] join: joining as %s" % ("RED" if _mp_side == 1 else "BLUE"))
	if _mp_role == "host":
		var peers: int = world.net.roster.size()
		if _mp_step == 1 and peers > 1:
			_mp_step = 2
			_mp_t = 0.0
			_mp_said = 0.0
		elif _mp_step == 2 and _mp_t > 25.0:
			_mp_step = 3
			print("[mp] host: restart")
			world._start("foot", "ground")
		elif _mp_step == 3 and _mp_t > 45.0:
			_mp_step = 4
			print("[mp] host: change to strike")
			world._start("f16", "strike")
		elif _mp_step == 4 and _mp_t > 65.0:
			_mp_step = 5
			print("[mp] host: change to cqb")
			world._start("foot", "cqb")
		elif _mp_step == 5 and _mp_t > 85.0:
			_mp_step = 6
			print("[mp] host: change to conquest")
			world._start("f16", "conquest")
		elif _mp_step == 6 and _mp_t > 125.0:
			print("[mp] host: done")
			world.get_tree().quit()
		if _mp_t - _mp_said > 3.0:
			_mp_said = _mp_t
			var men := 0
			var kills := "-"
			if is_instance_valid(world.cqb):
				men = world.cqb.soldiers.size()
			if is_instance_valid(world.mode):
				kills = "%d:%d" % [int(world.mode.kills.get(0, 0)), int(world.mode.kills.get(1, 0))]
			var gjet := "-"
			for gid in world.net.ghosts:
				var gg: Variant = world.net.ghosts[gid]
				if is_instance_valid(gg):
					gjet = "%s%s" % [String((gg as Node).get_meta("jet", "?")),
						" seen" if (gg as Node3D).visible else " hidden"]
			print("[mp] host t=%.0f gen=%d mission=%s peers=%d men=%d units=%d net_men=%d kills=%s launches_sent=%d drawn=%d their_aircraft=%s" % [
				_mp_t, world.net.match_gen, String(Sim.mission), peers, men, world.net.units.by_key.size(),
				world.get_tree().get_nodes_in_group("net_men").size(), kills, world.net.launches.sent,
				world.net.launches.drawn, gjet])
		return
	# the client
	if _mp_t - _mp_said > 3.0:
		_mp_said = _mp_t
		var kinds := {}
		for k in world.net.units.by_key:
			var u: Variant = world.net.units.by_key[k]
			if is_instance_valid(u):
				var nm: String = "man" if u is Soldier else ("tank" if u is Tank else "ship")
				kinds[nm] = int(kinds.get(nm, 0)) + 1
		var kills := "-"
		if is_instance_valid(world.mode):
			kills = "%d:%d" % [int(world.mode.kills.get(0, 0)), int(world.mode.kills.get(1, 0))]
		var mine := -1
		if is_instance_valid(world.cqb):
			mine = world.cqb.kills
		var hp: float = world.walker.health if is_instance_valid(world.walker) else -1.0
		# which end of town he is at, and who is on whose side here
		if is_instance_valid(world.cqb) and is_instance_valid(world.walker):
			var by_team := {0: 0, 1: 0}
			for k2 in world.net.units.by_key:
				var u3: Variant = world.net.units.by_key[k2]
				if is_instance_valid(u3) and u3 is Soldier:
					by_team[(u3 as Soldier).team] = int(by_team[(u3 as Soldier).team]) + 1
			print("[mp] join sides: me at %+.0f m north-south of the middle; host's men here: %d ours, %d theirs; zones %s" % [
				world.walker.global_position.z - world.cqb.centre.y, int(by_team[0]), int(by_team[1]),
				str(world.get_tree().get_nodes_in_group("zones").map(func(z): return int(z.owner_team)))])
		print("[mp] join t=%.0f gen=%d mission=%s units=%s ai=%d my_kills=%d match_kills=%s mirror=%s vehicle_rounds=%s launches_drawn=%d missiles=%d hp=%.0f" % [
			_mp_t, world.net.match_gen, String(Sim.mission), str(kinds), world.net.ai_ghosts.size(),
			mine, kills, str(NetLink.mirroring()), str(world.net.units.vehicle_rounds_drawn), world.net.launches.drawn,
			world.get_tree().get_nodes_in_group("missiles").size(), hp])
	if _mp_flip > 0.0 and _mp_t > _mp_flip:
		_mp_flip = -1.0
		world.net.set_side(1 - world.net.abs_side)
		if is_instance_valid(world.walker) and is_instance_valid(world.cqb):
			world.walker.global_position = world.cqb.spawn_point(0, 0)
		print("[mp] join: switched to %s (frame side %d)" % ["RED" if world.net.abs_side == 1 else "BLUE",
			world.net.side])
	# In the street fight: everything a man can send over -- a grenade, a
	# flashbang, a rocket off the shoulder -- then a strike and the chopper
	# gunner, once each, for the host to say it saw.
	if world.net.match_gen >= 4 and String(Sim.mission) == "cqb" and is_instance_valid(world.walker) \
			and is_instance_valid(world.cqb):
		_mp_cqb_t += delta
		var w: Walker = world.walker
		if _mp_act == 0 and _mp_cqb_t > 2.0:
			_mp_act = 1
			w.arms._throw_flash = false
			w.arms._throw()
			w.arms._throw_flash = true
			w.arms._throw()
			Firearm.rocket(world, w, w.side, Firearm.spec("law"), w.global_position + Vector3(0, 1.6, 0),
				Vector3(0, 0.05, -1).normalized())
			print("[mp] join: threw a grenade and a flashbang, fired a rocket")
		elif _mp_act == 1 and _mp_cqb_t > 4.0:
			_mp_act = 2
			world.cqb.streaks.bank["strike"] = 1
			var c := Vector3(world.cqb.centre.x, 0.0, world.cqb.centre.y - 40.0)
			world.cqb.streaks.picked("strike", c)
			print("[mp] join: called an airstrike")
		elif _mp_act == 3 and _mp_cqb_t > 9.0:
			_mp_act = 4
			_mp_ammo0 = w.ammo
			Sim.menu_open = false
			Input.action_press(&"foot_fire")
			print("[mp] join: trigger down")
		elif _mp_act == 4 and _mp_cqb_t > 11.0:
			_mp_act = 5
			Input.action_release(&"foot_fire")
			print("[mp] join: trigger up, %d rounds fired" % (_mp_ammo0 - w.ammo))
		elif _mp_act == 2 and _mp_cqb_t > 6.0:
			_mp_act = 3
			world.cqb.streaks.bank["chopper"] = 1
			var ok: bool = world.cqb.streaks.call_in("chopper")
			print("[mp] join: called the chopper gunner: %s" % str(ok))
	# a burst into the nearest of the host's men every second
	_mp_shot += delta
	if _mp_shot > 1.0 and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_mp_shot = 0.0
		for k in world.net.units.by_key:
			var u2: Variant = world.net.units.by_key[k]
			if is_instance_valid(u2) and u2 is Soldier and (u2 as Soldier).team == 1 \
					and (u2 as Soldier).alive:
				(u2 as Soldier).take_hit(45.0, world.walker)
				break
	if _mp_t > 175.0:
		world.get_tree().quit()
#endregion


#region --lobbytest
## The session as a player makes it: HOST and JOIN from the hangar, the host
## presses LAUNCH, and each end says, every few seconds, whether it can see
## the other -- the ghost of his aircraft or the figure of his man on foot,
## where, and whether it is drawn.
##   --lobbytest=host     then     --lobbytest=join   (no preset: from the hangar)
## Add --lobbymode=MODE:VEHICLE for what the host launches (default cqb:foot).
var _lb_role := ""
var _lb_t := 0.0
var _lb_said := 0.0
var _lb_step := 0
var _lb_mode := "cqb:foot"
var _lb_launched := -1.0

func tick_lobby(delta: float) -> void:
	if _lb_role == "" or world.net == null or world.booting:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lobbymode="):
			_lb_mode = a.substr(12)
	_lb_t += delta
	if _lb_step == 0 and _lb_t > 2.0:
		_lb_step = 1
		if _lb_role == "host":
			world.session.host_game(String(world.menu.jet_id), "")
			print("[lobby] host: HOST pressed; running=%s" % str(world.running))
		else:
			world.session.join_game(String(world.menu.jet_id), "127.0.0.1")
			print("[lobby] join: JOIN pressed; running=%s" % str(world.running))
	if _lb_role == "host" and _lb_step == 1 and world.net.roster.size() > 1 and _lb_t > 8.0:
		_lb_step = 2
		var parts := _lb_mode.split(":")
		print("[lobby] host: LAUNCH %s" % _lb_mode)
		_lb_launched = _lb_t
		world._start(parts[1] if parts.size() > 1 else "f16", parts[0])
	if _lb_role == "join" and _lb_launched < 0.0 and world.running:
		_lb_launched = _lb_t
	if _lb_t - _lb_said < 3.0:
		return
	_lb_said = _lb_t
	var me: Node3D = null
	if world.on_foot and is_instance_valid(world.walker):
		me = world.walker
	elif is_instance_valid(world.tank):
		me = world.tank
	elif is_instance_valid(world.player):
		me = world.player
	var seen: Array = []
	for pid in world.net.ghosts:
		var g: Variant = world.net.ghosts[pid]
		if is_instance_valid(g):
			seen.append("jet%d=%s vis=%s in_tree=%s %s" % [pid, String((g as Node).get_meta("jet", "?")),
				str((g as Node3D).visible),
				str((g as Node).is_inside_tree()),
				"%.0fm" % (g as Node3D).global_position.distance_to(me.global_position) if me != null else "-"])
	for pid2 in world.net.foot_ghosts:
		var f: Variant = world.net.foot_ghosts[pid2]
		if is_instance_valid(f):
			seen.append("man%d vis=%s %s" % [pid2, str((f as Node3D).visible),
				"%.0fm" % (f as Node3D).global_position.distance_to(me.global_position) if me != null else "-"])
	for pid3 in world.net.veh_ghosts:
		var v: Variant = world.net.veh_ghosts[pid3]
		if is_instance_valid(v):
			seen.append("veh%d vis=%s" % [pid3, str((v as Node3D).visible)])
	print("[lobby] %s t=%.0f running=%s mission=%s gen=%d roster=%d me=%s on_foot=%s tx=%d rx=%d sees: %s" % [
		_lb_role, _lb_t, str(world.running), String(Sim.mission), world.net.match_gen,
		world.net.roster.size(), str(me.global_position.round()) if me != null else "-",
		str(world.on_foot), world.net.tx, world.net.rx, ", ".join(PackedStringArray(seen))])
	if _lb_launched > 0.0 and _lb_t - _lb_launched > 40.0:
		world.get_tree().quit()
	if _lb_t > 400.0:
		world.get_tree().quit()
#endregion


#region --redeploytest
## As a joiner in a runway start: get out with U, get killed on foot, come back
## in a tank, lose it, come back on foot, then in an aeroplane -- each step
## said, and each checked. With --lobbytest=join and the host on takeoff.
var _rd_test := false
var _rd_step := 0
var _rd_t := 0.0
var _rd_bad: Array = []

func tick_redeploy(delta: float) -> void:
	if not _rd_test or not world.running or world.net == null or world.net.match_gen == 0:
		return
	_rd_t += delta
	match _rd_step:
		0:
			if _rd_t < 4.0:
				return
			if world.boarding:
				world.crew.end_boarding()
			var p: Aircraft = world.player
			p.linear_velocity = Vector3.ZERO
			p.throttle = 0.0
			p.on_ground = true
			# U, held as a man does: down for a few frames, the dismount on the
			# key event, the tap latched the way `Sim._input` latches it
			Input.action_press(&"interact")
			Sim._taps[&"interact"] = Time.get_ticks_msec()
			world.crew.try_dismount()
			_rd_step = 1
			_rd_t = 0.0
		1:
			if _rd_t > 0.1:
				Input.action_release(&"interact")
			if _rd_t < 1.5:
				return
			print("[redeploy] after U: on foot %s, boarding %s, in the seat %s" % [
				str(world.on_foot), str(world.boarding), str(not world.on_foot)])
			if not world.on_foot or world.boarding:
				_rd_bad.append("U did not get him out")
			world.walker.take_hit(5000.0, null)
			_rd_step = 2
			_rd_t = 0.0
		2:
			if _rd_t < 5.0:
				return
			print("[redeploy] dead on foot: chooser up %s, launch reads %s, enabled %s" % [
				str(world.menu.visible and world.menu.redeploy), world.menu._launch.text,
				str(not world.menu._launch.disabled)])
			if not world.menu.redeploy or world.menu._launch.disabled:
				_rd_bad.append("no redeploy after dying on foot")
			world.session.on_launch("veh:m1a2", String(Sim.mission))
			_rd_step = 3
			_rd_t = 0.0
		3:
			if _rd_t < 1.0:
				return
			var in_tank: bool = is_instance_valid(world.tank) and world.tank.alive
			print("[redeploy] back in: crewing %s" % (world.tank.display_name() if in_tank else "nothing"))
			if not in_tank:
				_rd_bad.append("no tank after redeploy")
				_rd_step = 9
				return
			world.tank.apply_damage(1.0e6)
			_rd_step = 4
			_rd_t = 0.0
		4:
			if _rd_t < 5.0:
				return
			print("[redeploy] tank knocked out: chooser up %s" % str(world.menu.redeploy))
			if not world.menu.redeploy:
				_rd_bad.append("no redeploy after losing the tank")
			world.session.on_launch("foot", String(Sim.mission))
			_rd_step = 5
			_rd_t = 0.0
		5:
			if _rd_t < 1.0:
				return
			var w: Walker = world.walker
			var near: float = w.global_position.distance_to(world.player.global_position) \
				if is_instance_valid(w) and is_instance_valid(world.player) else -1.0
			print("[redeploy] on foot: %s, %.0f m from his parked %s" % [str(world.on_foot), near,
				String(world.player.spec.get("name", "")) if is_instance_valid(world.player) else "-"])
			if not world.on_foot or near < 0.0 or near > 30.0:
				_rd_bad.append("on foot did not put him by the aeroplane")
			w.take_hit(5000.0, null)
			_rd_step = 6
			_rd_t = 0.0
		6:
			if _rd_t < 5.0:
				return
			world.session.on_launch("f16", String(Sim.mission))
			_rd_step = 7
			_rd_t = 0.0
		7:
			if _rd_t < 1.5:
				return
			var p2: Aircraft = world.player
			print("[redeploy] in an aeroplane: %s alive %s, %.0f m from the runway threshold" % [
				String(p2.spec.get("name", "")), str(p2.is_alive()),
				p2.global_position.distance_to(Vector3(0, p2.global_position.y, 1380.0))])
			if not p2.is_alive() or world.on_foot:
				_rd_bad.append("no aeroplane after redeploy")
			_rd_step = 9
		9:
			print("[redeploy] RESULT: %s" % ("ok" if _rd_bad.is_empty() else "FAILED -- " + ", ".join(_rd_bad)))
			_rd_test = false
			world.get_tree().quit()
#endregion


#region --ejecttest
## A joiner in a runway start ejects. With --soundtrace, every gun sound after
## it is printed with where it came from. --lobbytest=join --ejecttest
var _ej_test := false
var _ej_t := 0.0
var _ej_done := false

func tick_eject(delta: float) -> void:
	if not _ej_test or not world.running or world.net == null or world.net.match_gen == 0:
		return
	_ej_t += delta
	if not _ej_done and _ej_t > 4.0:
		_ej_done = true
		if world.menu.redeploy:
			world.session.on_launch("f16", String(Sim.mission))
		if world.boarding:
			world.crew.end_boarding()
		print("[eject] ejecting at t=%.1f" % _ej_t)
		world.crew.eject()
	if _ej_done and _ej_t > 34.0:
		print("[eject] done")
		world.get_tree().quit()
#endregion
