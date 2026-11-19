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
	elif a == "--nettest":
		_nettest = true
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
	world._start(world._jet_arg if world._jet_arg != "" else "f16", "free")
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
	world._pause_to_hangar()
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
		if _admin_t > 3.0 and world._traffic.is_empty():
			# optionally get out of the aeroplane first: the report is that
			# traffic only flies its approach while the player is in one
			if _admin_from != "":
				if _admin_from == "ship":
					for sh in world.get_tree().get_nodes_in_group("ships"):
						var v := sh as Ship
						if v != null and v.has_gun() and v.team == 0:
							world._enter_ship(v)
							break
				elif _admin_from == "tank":
					for v in world.get_tree().get_nodes_in_group("vehicles"):
						if v is Tank and (v as Tank).alive:
							world._enter_tank(v as Tank)
							break
				elif _admin_from == "foot":
					world._try_dismount()
				print("[admin] player is now in: %s (aeroplane valid=%s active=%s)" % [
					_admin_from, str(is_instance_valid(world.player)),
					str(world.player.active) if is_instance_valid(world.player) else "-"])
			world.admin.jet_id = "f16"
			world._do_admin("flight")
			if _admin_from != "":
				world._do_admin("follow")     # and watch them, from wherever we are
			print("[admin] called a flight of %d" % world._traffic.size())
		elif _admin_t > 8.0 and fmod(_admin_t, 25.0) < delta:
			for t in world._traffic:
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
			for t in world._traffic:
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

func tick_restart(delta: float) -> bool:
	if _restart_test:
		_restart_t += delta
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
			for k in Tank.KINDS.keys():
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
					"in the %s" % Tank.KINDS[got]["name"] if ok
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
