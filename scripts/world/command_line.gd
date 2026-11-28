class_name CommandLine
extends RefCounted
## The command line: presets, views, test switches and network options read
## once at boot and set on the world.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

func _init(w: World) -> void:
	world = w

# -------------------------------------------------------------- command line
func parse() -> void:
	var preset := ""
	var intro := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--weather="):
			world.set_weather(a.substr(10))
		elif a.begins_with("--jet="):
			world.menu._select(a.substr(6))
			world.jet_arg = a.substr(6)
		elif a.begins_with("--teams="):
			# --teams=8v12: how many a side in a street fight, ours then theirs
			var tv := a.substr(8).split("v")
			if tv.size() == 2:
				CqbMatch.size_us = maxi(int(tv[0]), 1)
				CqbMatch.size_them = maxi(int(tv[1]), 1)
		elif a.begins_with("--cqbtown="):
			CqbMatch.town = int(a.substr(10))
		elif a.begins_with("--cqbkit="):
			var kv := a.substr(9).split(",")
			if kv.size() >= 2:
				CqbMatch.loadout = [kv[0], kv[1]]
				CqbMatch.plain = true
		elif a.begins_with("--cqbclass="):
			CqbMatch.class_pick = int(a.substr(11))
		elif a == "--host":
			world.net_host = true
		elif a.begins_with("--join="):
			world.net_join = a.substr(7)
		elif a == "--noassist":
			Sim.assist = false
		elif a.begins_with("--mission="):
			# through the menu's own door, so what it lists follows the mode
			world.menu._select_mission(a.substr(10))
		elif a.begins_with("--physhz="):
			# The physics rate, for asking what it is worth. The flight model
			# integrates at it, so this is a measuring knob and not a setting:
			# what it answers is how much of a frame the physics step is.
			Engine.physics_ticks_per_second = maxi(int(a.substr(9)), 5)
		elif a == "--novsync":
			# Frame rate is pinned to the refresh rate otherwise, which makes
			# every measurement read "the same as every other" right up until
			# the machine can no longer keep up -- so a change that costs
			# a third of the frame budget is invisible until it costs all of it.
			if not OS.has_feature("headless"):
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_DISABLED)
		elif a == "--intro":
			intro = true
		elif a == "--debugweapons":
			Sim.debug_weapons = true
		elif a.begins_with("--orbit="):
			var pv := a.substr(8).split(",")
			if pv.size() == 2:
				world._orbit = Vector2(float(pv[0]), float(pv[1]))
		else:
			# Anything else is for the test harness, built on first use.
			if world.harness == null:
				world.harness = TestHarness.new(world)
			world.harness.parse_arg(a)
	# a harness run, a screenshot or a preset goes straight in
	if (world.harness != null or preset != "" or world._shot != "") and not intro:
		SatView.intro_on = false
	if world.net_host:
		world.session.host_game(world.menu.jet_id, "")
		# from the command line there is nobody to press LAUNCH
		world._start(world.menu.jet_id, String(world.menu.mission_id))
		return
	if world.net_join != "":
		world.session.join_game(world.menu.jet_id, world.net_join)
		return
	if preset == "" and world._shot == "" and world._auto == "":
		return
	if preset == "" and world._auto != "":
		preset = "takeoff" if world._auto == "takeoff" else "landing" 
	world.shot_frames = 70
	match preset:
		"", "menu":
			# The hangar as it opens, or as it looks some way into the flypast.
			if world.shot_at > 0:
				world.shot_frames = world.shot_at
		"hangar":
			world.menu.visible = false
			world._set_preview(world.menu.jet_id)
			world.menu_cam.current = true
			world.preview.visible = true
			world.spin = false
			world.preview.rotation.y = deg_to_rad(215.0)
			world._stand_rig()
			world.menu_cam.position = Vector3(13, world._rig_y + 3.5, -15)
			world.menu_cam.look_at(Vector3(0, world._rig_y + 0.4, 0), Vector3.UP)
			world.shot_frames = 20
		_:
			var parts := preset.split(":")
			world._start(world.menu.jet_id if parts.size() < 2 else parts[1], parts[0])
			if world.start_at != Vector3.ZERO and is_instance_valid(world.player):
				world.player.global_position = world.start_at
				world.player.linear_velocity = -world.player.global_transform.basis.z * 170.0
				world._reset_interp.call_deferred(world.player)
			world.shot_frames = world.shot_at if world.shot_at > 0 else 140
