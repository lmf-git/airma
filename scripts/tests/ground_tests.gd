class_name GroundTests
extends TestSuite
## Ground vehicles, artillery, launchers and rockets.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--boomtest":
		_boom_test = true
	elif a.begins_with("--artyoff="):
		_arty_off = float(a.substr(10))
	elif a.begins_with("--artytest="):
		world.arty_test = a.substr(11)
	elif a == "--mirvlocktest":
		_mirv_lock_test = true
	elif a == "--maplocktest":
		_map_lock_test = true
	elif a == "--launchtest":
		_launch_test = true
	elif a == "--moontest":
		_moon_test = true
	elif a.begins_with("--rocketview="):
		_rocket_view = a.substr(13)
	elif a.begins_with("--icbmtest="):
		_icbm_test = a.substr(11)
	elif a.begins_with("--telrangetest="):
		_tel_range = a.substr(15)
	elif a == "--firemaptest":
		_fire_map_test = true
	elif a == "--trackkilltest":
		_track_kill = "kill"
	elif a == "--trackkilltest=free":
		_track_kill = "free"
	elif a == "--fieldsvctest":
		_field_svc_test = true
	elif a.begins_with("--drivetest="):
		_drive_test = a.substr(12)
	elif a.begins_with("--telrig="):
		_tel_rig = a.substr(9)
	elif a == "--telrig":
		_tel_rig = "tel_kalibr"
	elif a == "--slopetest":
		_slope_test = true
	elif a == "--svctest":
		_svc_test = true
	elif a == "--teltest":
		_tel_test = true
	elif a == "--susptest":
		_susp_test = true
	elif a == "--tanksensor":
		_tanksensor = true
	elif a.begins_with("--keytest="):
		_key_test = a.substr(10)
	elif a == "--wrecktest":
		_wreck_test = true
	elif a == "--tankdrive":
		_tank_test = true
	elif a == "--wallram":
		_ram_test = true
	elif a.begins_with("--tankair"):
		_air_test = true
		_air_kind = a.substr(10) if a.length() > 10 else "m1a2"
	else:
		return false
	return true


#region --boomtest
var _boom_test := false

func tick_boom() -> void:
	if _boom_test:
		_boom_test = false
		for spot in [Vector3(2600, 0, 4200), Vector3(-2300, 0, -5200), Vector3(150, 0, -300)]:
			var y := Sim.height_at(spot.x, spot.z)
			var n := world.scenery.damage_area(Vector3(spot.x, y, spot.z), 140.0)
			print("[demolish] blast at %s flattened %d structures" % [str(spot.round()), n])
#endregion


#region --artyoff= --artytest=
var _arty_t := 0.0
var _arty_off := 100.0
var _arty_fired := false
var _arty_aim := Vector3.ZERO

func tick_arty(delta: float) -> void:
	if world.arty_test != "" and is_instance_valid(world.tank):
		_arty_t += delta
		if _arty_t > 2.0 and _arty_aim == Vector3.ZERO:
			# designate well off the current bearing: the whole point is to make
			# the piece traverse a long way before it may shoot
			var brg: float = world.tank.rotation.y + deg_to_rad(_arty_off)
			var p := world.tank.global_position + Vector3(sin(brg), 0, -cos(brg)) * 6000.0
			_arty_aim = Vector3(p.x, Sim.height_at(p.x, p.z), p.z)
			world.tank.map_target = _arty_aim
			world.tank.aim_yaw = brg
			var went: bool = world.tank.fire_main(world)
			print("[arty] designated %s, %.0f deg off; fired immediately: %s" % [
				str(_arty_aim.round()), _arty_off, str(went)])
		elif _arty_aim != Vector3.ZERO and not _arty_fired:
			if world.tank.lay_error() <= 0.03 and world.tank._gun_cd <= 0.0:
				world.tank.fire_main(world)     # the crew pulls the trigger when laid
			if world.tank._gun_cd > 0.0:
				_arty_fired = true
				var tb: Vector3 = -world.tank._muzzle.global_transform.basis.z
				print("[arty]   projectile: %s" % ("rocket" if world.tank.is_ripple() else "shell"))
				var cf: Vector3 = -world.tank.cam.global_transform.basis.z
				print("[arty]   camera looks at bearing %.1f, tubes at %.1f" % [
					fmod(rad_to_deg(atan2(cf.x, -cf.z)) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(tb.x, -tb.z)) + 360.0, 360.0)])
				print("[arty]   readout bearing %.1f, tubes actually %.1f, target %.1f" % [
					fmod(rad_to_deg(world.tank.aim_yaw) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(tb.x, -tb.z)) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(_arty_aim.x - world.tank.global_position.x,
						-(_arty_aim.z - world.tank.global_position.z))) + 360.0, 360.0)])
				print("[arty] rounds away at t=%.1f s, lay error now %.2f deg" % [
					_arty_t, rad_to_deg(world.tank.lay_error())])
			elif fmod(_arty_t, 1.0) < delta:
				print("[arty]   still laying, %.1f deg to go" % rad_to_deg(world.tank.lay_error()))
		elif _arty_fired and world.tank._gun_cd <= 0.0 and world.tank.rounds_left > 0:
			if world.tank.fire_main(world):
				print("[arty]   another round away, %d left on the rails" % world.tank.rounds_left)
#endregion


#region --mirvlocktest
## Lay a multiple-warhead fire mission the way a player does -- right click
## near one hostile, shift and right click near others, none of them exactly
## on the dot -- then fire and see what each warhead goes for:
## --mirvlocktest, with --jet=veh:tel_oreshnik --preset=strike.
var _mirv_lock_test := false
var _mirv_lock_t := 0.0
var _mirv_other := false

func tick_mirv_lock(delta: float) -> void:
	if _mirv_lock_test and world.running and is_instance_valid(world.tank):
		_mirv_lock_t += delta
		if _mirv_lock_t > 6.0:
			_mirv_lock_test = false
			_run_mirv_lock_test()

func _run_mirv_lock_test() -> void:
	var bad := PackedStringArray()
	if not is_instance_valid(world.tank) or world.tank.warheads() <= 0:
		print("[mirvlock] RESULT: FAILED — not crewing a multiple-warhead launcher")
		world.get_tree().quit()
		return
	if not world.map.visible:
		world.map.toggle()
	for i in 20:
		await world.get_tree().process_frame
	world.map._refresh_contacts()
	# The strike shipping, whether or not anybody on our side can see it yet:
	# what is under test is the click and the warheads, not the detection.
	var foes: Array = []
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if n is Ship and int(n.team) == 1 and (n as Ship).is_alive():
			foes.append(n)
	foes.sort_custom(func(x: Node3D, y: Node3D) -> bool:
		return x.global_position.distance_to(world.tank.global_position) \
			< y.global_position.distance_to(world.tank.global_position))
	if foes.size() < 2:
		print("[mirvlock] RESULT: FAILED — %d hostile ship(s) on the range" % foes.size())
		world.get_tree().quit()
		return
	foes = foes.slice(0, 3)
	for v in world.get_tree().get_nodes_in_group("hittable"):
		if v is Tank and (v as Tank).warheads() > 0 and v != world.tank:
			print("[mirvlock]   another multiple-warhead launcher: %s team %d ai=%s %.1f km away" % [
				Sim.label_of(v), int(v.team), str((v as Tank).ai),
				(v as Node3D).global_position.distance_to(world.tank.global_position) * 0.001])
	for f in foes:
		var seen := false
		for c in world.map._contacts:
			if c["n"] == f:
				seen = true
		if not seen:
			world.map._contacts.append({"n": f, "hostile": true, "neutral": false})
	world.map.globe_zoom = 400.0
	var vp: Vector2 = world.map.get_viewport_rect().size
	world.tank.map_lock = null
	world.tank.map_target = Vector3.INF
	world.tank.mirv_marks.clear()
	# A click a little off each one: on screen for the first, a kilometre off
	# on the ground for the rest.
	for i in foes.size():
		var f: Node3D = foes[i]
		var p: Vector3 = f.global_position
		if i > 0:
			p += Vector3(900.0, 0.0, -500.0)
		var q: Vector3 = world.map.globe_view._globe_at(Vector2(p.x, p.z), vp * 0.5,
			minf(vp.x, vp.y) * 0.42 * world.map.globe_zoom, world.map.globe_view._globe_basis())
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		click.shift_pressed = i > 0
		click.position = Vector2(q.x, q.y) + (Vector2(15, 9) if i == 0 else Vector2.ZERO)
		world.map._gui_input(click)
	var rvs: Array = world.tank.warhead_marks()
	var names := PackedStringArray()
	for mk in rvs:
		var u: Node3D = Tank.mark_unit(mk)
		names.append(Sim.label_of(u) if u != null else "ground")
	print("[mirvlock] marks laid: %s" % ", ".join(names))
	for i in foes.size():
		if i >= rvs.size() or Tank.mark_unit(rvs[i]) != foes[i]:
			bad.append("RV%d did not take the ship it was laid near" % (i + 1))
	world.map.toggle()
	# fire it and wait for the bus to open
	Engine.time_scale = 5.0
	world.tank._gun_cd = 0.0
	var waited := 0
	while world.tank._erect < 0.97 and waited < 1200:
		world.tank.fire_main(world)
		await world.get_tree().physics_frame
		waited += 1
	var fired: bool = world.tank.fire_main(world) if world.tank.rounds_left > 0 else true
	print("[mirvlock] launched: %s" % str(fired))
	var kids: Array = []
	var t0 := Time.get_ticks_msec()
	var next_dbg := 0.0
	var tt := 0.0
	while kids.is_empty() and Time.get_ticks_msec() - t0 < 240000:
		await world.get_tree().physics_frame
		tt += world.get_physics_process_delta_time()
		if tt >= next_dbg:
			next_dbg += 30.0
			var ms := PackedStringArray()
			for m2 in world.get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m2):
					var mm: Missile = m2
					ms.append("%s %.0fm up %.1fkm out tgt=%s" % [mm.wid,
						Sim.altitude(mm.global_position),
						mm.global_position.distance_to(world.tank.global_position) * 0.001,
						Sim.label_of(mm.target) if is_instance_valid(mm.target) else "-"])
			print("[mirvlock]   t=%.0f occupied=%s ai=%s rounds=%d jet alive=%s | %s" % [
				tt, str(world.tank.occupied), str(world.tank.ai), world.tank.rounds_left,
				str(world.player.alive) if is_instance_valid(world.player) else "gone", "; ".join(ms)])
		for m in world.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m) and not (m as Missile).siblings.is_empty():
				if (m as Missile).shooter != world.tank:
					if not _mirv_other:
						_mirv_other = true
						var sh: Variant = (m as Missile).shooter
						print("[mirvlock]   somebody else's %s opened, fired by %s (team %s) %.1f km from us" % [
							(m as Missile).wid, Sim.label_of(sh) if is_instance_valid(sh) else "?",
							str(sh.team) if is_instance_valid(sh) and ("team" in sh) else "?",
							(sh as Node3D).global_position.distance_to(world.tank.global_position) * 0.001
							if is_instance_valid(sh) else -1.0])
					continue
				kids = (m as Missile).siblings
				break
	Engine.time_scale = 1.0
	if kids.is_empty():
		bad.append("the bus never opened")
	var hits := {}
	for k in kids:
		if not is_instance_valid(k):
			continue
		var km: Missile = k
		var lbl: String = Sim.label_of(km.target) if km.locked_on_unit() else "ground"
		hits[lbl] = int(hits.get(lbl, 0)) + 1
		if not km.locked_on_unit():
			bad.append("a warhead is going for a patch of ground")
	print("[mirvlock] warheads: %s" % str(hits))
	for f in foes:
		if not hits.has(Sim.label_of(f)):
			bad.append("no warhead for %s" % Sim.label_of(f))
	for b in bad:
		print("[mirvlock]   ", b)
	print("[mirvlock] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --maplocktest
## In a launcher, right click a hostile's dot on the map and see the fire mission
## lock onto it: --maplocktest, with --jet=veh:KIND --preset=strike.
var _map_lock_test := false
var _map_lock_t := 0.0

func tick_map_lock(delta: float) -> void:
	if _map_lock_test and world.running and is_instance_valid(world.tank):
		_map_lock_t += delta
		if _map_lock_t > 6.0:
			_map_lock_test = false
			_run_map_lock_test()

func _run_map_lock_test() -> void:
	var bad := PackedStringArray()
	if not is_instance_valid(world.tank) or not world.tank.is_indirect():
		print("[maplock] RESULT: FAILED — not crewing a launcher or a gun")
		world.get_tree().quit()
		return
	if not world.map.visible:
		world.map.toggle()
	for i in 30:
		await world.get_tree().process_frame
	world.map._refresh_contacts()
	var foe: Node3D = null
	var n_host := 0
	for c in world.map._contacts:
		var nv: Variant = c["n"]
		if is_instance_valid(nv) and bool(c["hostile"]):
			n_host += 1
			if foe == null or ((nv as Node).has_meta("strike") and not foe.has_meta("strike")):
				foe = nv
	var n_strike := 0
	for t in world.get_tree().get_nodes_in_group("hittable"):
		if t.has_meta("strike"):
			n_strike += 1
			print("[maplock]   strike target %s at %.1f km" % [t.name,
				world.tank.global_position.distance_to((t as Node3D).global_position) * 0.001])
	print("[maplock] %d contacts, %d hostile; %d strike targets in the world" % [
		world.map._contacts.size(), n_host, n_strike])
	if foe == null:
		print("[maplock] RESULT: FAILED — no hostile on the map (%d contacts)" % world.map._contacts.size())
		world.get_tree().quit()
		return
	# zoom in on it, the way you would, and click on its dot
	world.map.globe_zoom = 60.0
	await world.get_tree().process_frame
	var vp: Vector2 = world.map.get_viewport_rect().size
	var q: Vector3 = world.map.globe_view._globe_at(Vector2(foe.global_position.x, foe.global_position.z),
		vp * 0.5, minf(vp.x, vp.y) * 0.42 * world.map.globe_zoom, world.map.globe_view._globe_basis())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = Vector2(q.x, q.y)
	world.tank.map_lock = null
	world.map._gui_input(click)
	print("[maplock] clicked %s's dot at %.1f km: fire mission locked on %s; satellite selected: %s" % [
		foe.name, world.tank.global_position.distance_to(foe.global_position) * 0.001,
		Sim.label_of(world.tank.map_lock), str(Sim.sat_target != null)])
	if world.tank.map_lock != foe:
		bad.append("the lock did not take the unit that was clicked")
	# and zoomed right out, where the satellites crowd the same few pixels
	world.map.globe_zoom = 1.0
	await world.get_tree().process_frame
	q = world.map.globe_view._globe_at(Vector2(foe.global_position.x, foe.global_position.z),
		vp * 0.5, minf(vp.x, vp.y) * 0.42 * world.map.globe_zoom, world.map.globe_view._globe_basis())
	click.position = Vector2(q.x, q.y)
	world.tank.map_lock = null
	world.map._gui_input(click)
	print("[maplock] zoomed out: locked on %s" % Sim.label_of(world.tank.map_lock))
	for b in bad:
		print("[maplock]   ", b)
	print("[maplock] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --launchtest
## The rocket, all the way: off the pad, three stages, into an orbit that
## closes, once round the planet on time warp to see that it comes back to
## where it was, a burn to come down, and the capsule onto the ground under its
## parachute. Flown by the ascent autopilot, which uses the same controls a
## player does. --launchtest
var _launch_test := false

func tick_launch() -> void:
	if _launch_test and not world.booting:
		_launch_test = false
		_run_launch_test()

func _run_launch_test() -> void:
	world._start("f16", "launch")
	# the picture, if one was asked for, is taken when the flight says so
	world.shot_frames = 1 << 30
	for i in 30:
		await world.get_tree().physics_frame
	var bad := PackedStringArray()
	if not world.missions.in_rocket():
		print("[launch] RESULT: FAILED — not in the rocket")
		world.get_tree().quit()
		return
	var r := world.rocket
	var g0: float = Sim.gravity_at(r.global_position).length()
	print("[launch] on the pad at %s: %.0f t, gravity %.3f m/s2, thrust to weight %.2f" % [
		str(r.global_position.round()), r.mass() * 0.001, g0,
		float(r.stages[0]["thrust"]) / (r.mass() * g0)])
	r.locked = true
	r.engage()
	Engine.time_scale = 8.0
	var charts0: int = world.chart_follow._rechart_n
	var t_wall := Time.get_ticks_msec()
	var next := 30.0
	while r.autopilot and r.alive and r.met < 1500.0:
		await world.get_tree().physics_frame
		if r.met >= next:
			next += 60.0
			var a0: Dictionary = Orbit.apsides(r._s)
			print("[launch]  T+%s stage %d %s: %.1f km up, %.0f m/s, high point %.0f km, %.1f g, %d%% propellant" % [
				LaunchVehicle._clock(r.met), r.stage + 1, r.auto_phase, r.alt() * 0.001,
				r.speed(), float(a0["ap"]) * 0.001, r.g_load, int(r.fuel() * 100.0)])
	var orb: Dictionary = Orbit.apsides(r._s)
	print("[launch] autopilot let go at T+%s: orbit %.1f by %.1f km, period %s, stage %d with %.0f m/s left; %d chart moves, %.0f s of wall clock" % [
		LaunchVehicle._clock(r.met), float(orb["ap"]) * 0.001, float(orb["pe"]) * 0.001,
		LaunchVehicle._clock(float(orb["period"])), r.stage + 1, r.delta_v(),
		world.chart_follow._rechart_n - charts0, float(Time.get_ticks_msec() - t_wall) * 0.001])
	if not r.alive or float(orb["pe"]) < 120000.0 or is_inf(float(orb["ap"])):
		bad.append("did not reach orbit")
	var entry_shots: bool = OS.get_cmdline_user_args().has("--entry")
	if world._shot != "" and not entry_shots:
		# a picture from orbit, and no further
		Engine.time_scale = 1.0
		r.throttle = 0.0
		world.shot_frames = 90
		return
	# once round, on time warp: does it come back to the orbit it left on
	Sim.space_warp = 100.0
	var lap_end: float = r.met + float(orb["period"])
	while r.alive and r.met < lap_end and not bad.size() > 0:
		await world.get_tree().physics_frame
	var orb2: Dictionary = Orbit.apsides(r._s)
	print("[launch] after one lap on time warp: %.2f by %.2f km (was %.2f by %.2f); %d chart moves in all, the longest %d ms" % [
		float(orb2["ap"]) * 0.001, float(orb2["pe"]) * 0.001,
		float(orb["ap"]) * 0.001, float(orb["pe"]) * 0.001, world.chart_follow._rechart_n - charts0, world.chart_follow._rechart_worst])
	if absf(float(orb2["pe"]) - float(orb["pe"])) > 2000.0:
		bad.append("the orbit drifted by %.1f km in a lap" % (
			absf(float(orb2["pe"]) - float(orb["pe"])) * 0.001))
	# and home: retrograde, burn until the low point is in the air, capsule only
	Sim.space_warp = 1.0
	r.sas = 3
	var before_stage: int = r.stage
	for i in 60 * 30:
		await world.get_tree().physics_frame
	# a stage only comes off dry: asked for with propellant in it, it stays on
	r.next_stage()
	if r.stage != before_stage:
		bad.append("a stage with propellant in it was dropped")
	r.throttle = 1.0
	while r.alive and r.stage < r.stages.size() - 1:
		await world.get_tree().physics_frame
		if r.fuel() <= 0.0:
			r.next_stage()
			r.throttle = 1.0
	# and the capsule's own engine, for whatever is left to take off
	while r.alive and float(Orbit.apsides(r._s)["pe"]) > 35000.0 and r.fuel() > 0.0:
		await world.get_tree().physics_frame
	r.throttle = 0.0
	Sim.space_warp = 50.0
	var peak_g := 0.0
	var chute_g := 0.0
	var t_dn: float = r.met
	var heat_shots := 0
	var peak_heat := 0.0
	while r.alive and not r.landed and r.met < t_dn + 6000.0:
		await world.get_tree().physics_frame
		peak_heat = maxf(peak_heat, r.heat)
		if r.alt() < 140000.0 and Sim.space_warp > 1.0:
			Sim.space_warp = 1.0
			Engine.time_scale = 2.0
		if entry_shots and heat_shots < 3 and r.heat > [0.3, 0.7, 0.9][heat_shots]:
			heat_shots += 1
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png("%s_heat%d.png" % [world._shot, heat_shots])
			print("[launch] picture at %.0f km, %.0f m/s, heat %.2f, %.1f g" % [r.alt() * 0.001,
				r.speed(), r.heat, r.g_load])
		if r.alt() < 100000.0 and not r.chute:
			peak_g = maxf(peak_g, r.g_load)
		elif r.chute:
			chute_g = maxf(chute_g, r.g_load)
	Engine.time_scale = 1.0
	print("[launch] down at T+%s: %s, peak %.1f g on the way in, %.1f g as the parachute opened, peak heat %.2f" % [
		LaunchVehicle._clock(r.met), "landed" if (r.alive and r.landed) else "LOST",
		peak_g, chute_g, peak_heat])
	if not (r.alive and r.landed):
		bad.append("the capsule did not land")
	print("[launch] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED — " + "; ".join(bad)))
	world.get_tree().quit()
#endregion


#region --moontest
## The moon rocket, to the moon: orbit, the burn out, five days of coast with
## the corrections on the way, and the burn that stops it there -- and then
## round the moon a few times on its own, to see that it stays. Flown by the
## same programs the H key gives a player. --moontest
var _moon_test := false

func tick_moon() -> void:
	if _moon_test and not world.booting:
		_moon_test = false
		_run_moon_test()

func _run_moon_test() -> void:
	world._start("f16", "moon")
	# the picture, if one was asked for, is taken when the flight says so
	world.shot_frames = 1 << 30
	for i in 30:
		await world.get_tree().physics_frame
	if not world.missions.in_rocket():
		print("[moon] RESULT: FAILED — not in the rocket")
		world.get_tree().quit()
		return
	var r := world.rocket
	var bad := PackedStringArray()
	r.locked = true
	print("[moon] %s on the pad: %.0f t, %d stages" % [r.display_name(), r.mass() * 0.001,
		r.stages.size()])
	r.engage()
	Engine.time_scale = 8.0
	var wall := Time.get_ticks_msec()
	while r.autopilot and r.alive and r.met < 1500.0:
		await world.get_tree().physics_frame
	var park: Dictionary = Orbit.apsides(r._s)
	print("[moon] parking orbit at T+%s: %.0f by %.0f km, stage %d with %.0f m/s in it, %.0f s of wall clock" % [
		LaunchVehicle._clock(r.met), float(park["ap"]) * 0.001, float(park["pe"]) * 0.001,
		r.stage + 1, r.delta_v(), float(Time.get_ticks_msec() - wall) * 0.001])
	if not r.alive or float(park["pe"]) < 120000.0:
		print("[moon] RESULT: FAILED — no parking orbit")
		world.get_tree().quit()
		return
	# the rest of the way: H again, and as much time warp as it will take
	r.engage()
	var said := ""
	var t_out: float = r.met
	var closest := 1e30
	while r.autopilot and r.alive and r.met < t_out + 12.0 * 86400.0:
		Sim.space_warp = 10000.0
		await world.get_tree().physics_frame
		closest = minf(closest, Orbit.moon_range(r._s))
		if r.program != said:
			said = r.program
			print("[moon]  T+%s  %s — %.0f km from the planet, %.0f km from the moon, %.0f m/s, stage %d" % [
				LaunchVehicle._clock(r.met), said, Orbit.radius(r._s) * 0.001,
				Orbit.moon_range(r._s) * 0.001, r.speed(), r.stage + 1])
	Sim.space_warp = 1.0
	var rel: PackedFloat64Array = Orbit.about_moon(r._s, Sim.space_time)
	var orb: Dictionary = Orbit.apsides(rel, Orbit.MOON_GM, Orbit.MOON_R)
	print("[moon] autopilot let go at T+%s: round the moon %.0f by %.0f km, %.0f m/s past it, stage %d with %.0f m/s left" % [
		LaunchVehicle._clock(r.met), float(orb["ap"]) * 0.001, float(orb["pe"]) * 0.001,
		Orbit.speed(rel), r.stage + 1, r.delta_v()])
	if not r.alive:
		bad.append("the vehicle was lost")
	if is_inf(float(orb["ap"])) or float(orb["pe"]) < 15000.0:
		bad.append("not in orbit round the moon")
	# Does it stay? Three laps, left alone, with the planet pulling at it.
	if bad.is_empty():
		var laps: float = float(orb["period"]) * 3.0
		var until: float = r.met + laps
		var lo := 1e30
		var hi := 0.0
		while r.alive and r.met < until:
			Sim.space_warp = 1000.0
			await world.get_tree().physics_frame
			var d: float = Orbit.moon_range(r._s) - Orbit.MOON_R
			lo = minf(lo, d)
			hi = maxf(hi, d)
		Sim.space_warp = 1.0
		print("[moon] three laps later: between %.0f and %.0f km over the moon, %s; view scale %.5f" % [
			lo * 0.001, hi * 0.001, "still there" if r.alive else "LOST", Sim.view_scale])
		if not r.alive or hi > 20.0e6:
			bad.append("it did not stay in orbit round the moon")
	Engine.time_scale = 1.0
	print("[moon] RESULT: %s  (%.0f s of wall clock)" % [
		"ok" if bad.is_empty() else "FAILED — " + "; ".join(bad),
		float(Time.get_ticks_msec() - wall) * 0.001])
	if world._shot != "":
		world.shot_frames = 30
		return
	world.get_tree().quit()
#endregion


#region --rocketview=
## What the rocket's camera sees at a run of heights, one picture each: the
## planet, its air and its cloud from the pad to half way to the moon, and the
## moon from its own orbit. --rocketview=DIR writes them there.
var _rocket_view := ""

func tick_rocket_view() -> void:
	if _rocket_view != "" and not world.booting:
		var vt_arg := _rocket_view
		_rocket_view = ""
		_run_rocket_view(vt_arg)

func _run_rocket_view(dir: String) -> void:
	world._start("f16", "moon")
	for i in 40:
		await world.get_tree().physics_frame
	var r := world.rocket
	r.locked = true
	r.landed = false
	r._lifted = true
	if is_instance_valid(world.hud):
		world.hud.show_help = false
	var here: Vector3 = Orbit.pos_of(r._s).normalized()
	var east: Vector3 = Sim.chart_east
	var heights: Array = [8.0, 30.0, 60.0, 90.0, 150.0, 290.0, 320.0, 1200.0, 20000.0, 200000.0]
	if OS.get_cmdline_user_args().has("--maponly"):
		heights = [290.0]
	for km in heights:
		var rad: float = Sim.PLANET_R + float(km) * 1000.0
		r._s = Orbit.make(here * rad, east * sqrt(Sim.GM / rad))
		r._att = Basis.looking_at(east, here)
		r._cam_pitch = 0.22
		r._cam_yaw = 2.2
		for i in 50:
			# held where it was put: this is about the picture, not the flight
			r._s = Orbit.make(here * rad, east * sqrt(Sim.GM / rad))
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png("%s/view_%06d.png" % [dir, int(km)])
		var vc := world.get_viewport().get_camera_3d()
		print("[view] %.0f km: far %.0f km, near %.1f m, scale %.4f" % [km, vc.far * 0.001,
			vc.near, Sim.view_scale])
	# the same height from four ways of looking: anything that moves across
	# the picture as the camera turns is a fault in how it is drawn
	for look in [[250.0, 0.4, -0.5], [250.0, 3.6, 0.9], [250.0, 5.0, -1.1],
			[6000.0, 0.4, -0.6], [6000.0, 3.6, 0.9]]:
		var rad2: float = Sim.PLANET_R + float(look[0]) * 1000.0
		r._cam_yaw = float(look[1])
		r._cam_pitch = float(look[2])
		for i in 40:
			r._s = Orbit.make(here * rad2, east * sqrt(Sim.GM / rad2))
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png("%s/look_%05d_%d.png" % [
			dir, int(look[0]), int(float(look[1]) * 10.0)])
	# and round the moon
	var ms: PackedFloat64Array = Orbit.moon_state(Sim.space_time)
	var mdir: Vector3 = Orbit.pos_of(ms).normalized()
	var side: Vector3 = mdir.cross(Vector3.UP).normalized()
	var mr: float = Orbit.MOON_R + 150000.0
	for i in 50:
		ms = Orbit.moon_state(Sim.space_time)
		r._s = Orbit.make(Orbit.pos_of(ms) + side * mr,
			Orbit.vel_of(ms) + mdir * sqrt(Orbit.MOON_GM / mr))
		r._cam_pitch = 0.5
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("%s/view_moon.png" % dir)
	# and the map: the lap round the moon, and then the planet with an orbit
	# and the reach out to the moon drawn round it
	world.map.toggle()
	world.map.globe = true
	world.map.globe_zoom = 0.014
	for i in 20:
		ms = Orbit.moon_state(Sim.space_time)
		r._s = Orbit.make(Orbit.pos_of(ms) + side * mr,
			Orbit.vel_of(ms) + mdir * sqrt(Orbit.MOON_GM / mr))
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("%s/map_moon.png" % dir)
	var rad3: float = Sim.PLANET_R + 300000.0
	world.map.globe_zoom = 0.6
	for which in [0, 1]:
		# a round orbit; then the same place going fast enough for the moon
		var sp3: float = sqrt(Sim.GM / rad3) + (3050.0 if which == 1 else 0.0)
		r._path_ms = -100000
		if which == 1:
			world.map.globe_zoom = 0.014
		for i in 20:
			r._s = Orbit.make(here * rad3, east * sp3)
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png("%s/map_orbit_%d.png" % [dir, which])
	print("[view] done")
	world.get_tree().quit()
#endregion


#region --icbmtest=
## An intercontinental shot, start to finish: does it burn three stages, cut
## its motor, open, and put every warhead on the mark it was given, from the
## far side of a quarter of the planet. --icbmtest=KIND,KM (with --preset=free).
var _icbm_test := ""

func tick_icbm() -> void:
	if _icbm_test != "" and world.running:
		var it_arg := _icbm_test
		_icbm_test = ""
		_run_icbm_test(it_arg)

func _run_icbm_test(arg: String) -> void:
	var parts := arg.split(",")
	var kind: String = parts[0] if parts[0] != "" else "tel_yars"
	var km: float = float(parts[1]) if parts.size() > 1 else 8000.0
	Sim.debug_weapons = true
	world.shot_frames = 1 << 30
	var t := world._spawn_tank(Vector3(1400.0, 0.0, -2600.0), 0.0, 0, kind)
	t.ai = false
	for i in 120:
		await world.get_tree().physics_frame
	var aim := Vector3(1400.0 + km * 707.0, 0.0, -2600.0 - km * 707.0)
	aim.y = Sim.height_at(aim.x, aim.z)
	t.map_target = aim
	var fired := false
	for i2 in 2400:
		await world.get_tree().physics_frame
		if t.fire_main(world):
			fired = true
			break
	if not fired:
		print("[icbm] RESULT: FAILED — %s did not fire" % kind)
		world.get_tree().quit()
		return
	if world._shot != "":
		# ridden on the weapon camera, with a picture at each stage of it
		world.shot_frames = 1 << 30
		var ridden: Icbm = null
		for n0 in world.get_tree().get_nodes_in_group("icbm"):
			ridden = n0 as Icbm
		if ridden != null:
			world._ride(ridden)
		var marks: Array = [8.0, 30.0, 70.0, 120.0, 170.0]
		var coast_shots := 0
		var low_shots := 0
		var last_alt := 0.0
		while is_instance_valid(ridden) and not ridden.dead:
			await world.get_tree().process_frame
			if not is_instance_valid(ridden):
				break
			var snap := ""
			# looked round at, for a few seconds of the climb: the round has to
			# stay in the middle of the picture while the view goes about it
			var turned: bool = ridden.age > 24.0 and ridden.age < 30.5
			if turned:
				world.cam.free_yaw = 1.3
				world.cam.free_pitch = 0.35
			if not marks.is_empty() and ridden.age >= float(marks[0]):
				snap = "boost_%03d" % int(marks.pop_front())
			elif marks.is_empty() and coast_shots < 2 and ridden.alt() > 600000.0 * float(coast_shots + 1):
				coast_shots += 1
				snap = "coast_%d" % coast_shots
				Sim.space_warp = 50.0
			elif coast_shots >= 1 and ridden.alt() < last_alt and low_shots < 3 \
					and ridden.alt() < [90000.0, 40000.0, 12000.0][low_shots]:
				low_shots += 1
				snap = "entry_%d" % low_shots
			elif marks.is_empty() and coast_shots == 0 and ridden.age > 260.0:
				Sim.space_warp = 25.0
			last_alt = ridden.alt()
			if snap != "":
				await RenderingServer.frame_post_draw
				world.get_viewport().get_texture().get_image().save_png("%s_%s.png" % [world._shot, snap])
				var vc := world.get_viewport().get_camera_3d()
				var on_screen: Vector2 = vc.unproject_position(
					ridden.get_global_transform_interpolated() * ridden.ride_centre())
				var vps: Vector2 = world.get_viewport().get_visible_rect().size
				print("[icbm] picture %s: %.0f km up, camera far %.0f km near %.2f m, %.0f m from the round, round drawn %.0f px from the middle%s" % [
					snap, ridden.alt() * 0.001, vc.far * 0.001, vc.near,
					vc.global_position.distance_to(ridden.global_position),
					on_screen.distance_to(vps * 0.5), " (looking round)" if turned else ""])
		world.get_tree().quit()
		return
	Sim.space_warp = 100.0
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	var seen := 0
	var said := {}
	var peak := 0.0
	var count := 0
	var done: Array = []
	while Time.get_ticks_msec() - t0 < 400000:
		await world.get_tree().physics_frame
		var live: Array = world.get_tree().get_nodes_in_group("icbm")
		for n in live:
			var m := n as Icbm
			if m == null:
				continue
			peak = maxf(peak, m.alt())
			if not said.has(m.get_instance_id()):
				said[m.get_instance_id()] = true
				seen += 1
				m.detonated.connect(func(w: Icbm) -> void:
					done.append(w.last_miss))
		count = maxi(count, live.size())
		if seen > 0 and live.is_empty():
			break
	for d in done:
		worst = maxf(worst, float(d))
	Engine.time_scale = 1.0
	var want: int = int(WeaponSpec.get_spec(String(VehicleSpec.KINDS[kind]["missile"])).get("mirv", 1))
	print("[icbm] %s over %.0f km: %d warheads released, %d detonated, worst %.0f m off its mark, peak %.0f km, %.0f s of wall clock" % [
		kind, km, count, done.size(), worst, peak * 0.001,
		float(Time.get_ticks_msec() - t0) * 0.001])
	print("[icbm] RESULT: %s" % ("ok" if done.size() == want and worst < 400.0
		else "FAILED"))
	world.get_tree().quit()
#endregion


#region --telrangetest=
## Fire a launcher at a mark a long way off and follow the round: how far it
## gets, how close it comes, and whether the motor is still shown burning along
## the way. --telrangetest=KIND,KM. Run at five times speed; a Zircon is six
## minutes in the air.
var _tel_range := ""

func tick_tel_range() -> void:
	if _tel_range != "" and world.running:
		var tr_arg := _tel_range
		_tel_range = ""
		_run_tel_range_test(tr_arg)

func _run_tel_range_test(arg: String) -> void:
	var parts := arg.split(",")
	var kind: String = parts[0]
	var km: float = float(parts[1]) if parts.size() > 1 else 500.0
	var t := world._spawn_tank(Vector3(1400.0, 0.0, -2600.0), 0.0, 0, kind)
	t.ai = false
	for i in 120:
		await world.get_tree().physics_frame
	var aim := Vector3(1400.0 + km * 1000.0, 0.0, -2600.0)
	aim.y = Sim.height_at(aim.x, aim.z)
	t.map_target = aim
	var before: Array = world.get_tree().get_nodes_in_group("missiles")
	var fired := false
	for i2 in 1800:
		await world.get_tree().physics_frame
		if t.fire_main(world):
			fired = true
			break
	if not fired:
		print("[telrange] %s did not fire at %.0f km" % [kind, km])
		world.get_tree().quit()
		return
	await world.get_tree().physics_frame
	var m: Node3D = null
	for n in world.get_tree().get_nodes_in_group("missiles"):
		if not before.has(n) and is_instance_valid(n):
			m = n
	if m == null:
		print("[telrange] no round in the air")
		world.get_tree().quit()
		return
	Engine.time_scale = 5.0
	var start: Vector3 = m.global_position
	var last := start
	var closest := 1e12
	var lit_log := PackedStringArray()
	var t0 := Time.get_ticks_msec()
	var next_log := 30.0
	var fin_over := 0.0
	var fin_after := 0.0
	var fin_now := 0.0
	while is_instance_valid(m):
		last = m.global_position
		closest = minf(closest, Vector2(last.x - aim.x, last.z - aim.z).length())
		var age: float = float(m.get("age"))
		# how hard the tail surfaces are working: through the pitch-over off
		# the rail, and afterwards on the way
		fin_now = 0.0
		for h in (m.get("_tails") as Array):
			fin_now = maxf(fin_now, absf((h as Node3D).rotation.x))
		if age < 6.0:
			fin_over = maxf(fin_over, fin_now)
		else:
			fin_after = maxf(fin_after, fin_now)
		if age >= next_log:
			var fl: Variant = m.get("_flame")
			lit_log.append("%ds %s %.0f m/s fins %.1f°" % [int(age),
				"lit" if (fl != null and is_instance_valid(fl) and (fl as Node3D).visible) else "dark",
				(m.get("vel") as Vector3).length(), rad_to_deg(fin_now)])
			next_log += 60.0
		await world.get_tree().physics_frame
		if Time.get_ticks_msec() - t0 > 400000:
			break
	Engine.time_scale = 1.0
	print("[telrange] %s at %.0f km: flew %.0f km, closest %.1f km to the mark" % [
		kind, km, Vector2(last.x - start.x, last.z - start.z).length() * 0.001,
		closest * 0.001])
	print("[telrange] motor: %s" % ", ".join(lit_log))
	print("[telrange] tail fins: up to %.1f° through the pitch-over, %.1f° after" % [
		rad_to_deg(fin_over), rad_to_deg(fin_after)])
	world.get_tree().quit()
#endregion


#region --firemaptest
var _fire_map_test := false
var _fire_map_t := 0.0

func tick_fire_map(delta: float) -> void:
	if _fire_map_test and world.running and is_instance_valid(world.tank):
		_fire_map_t += delta
		if _fire_map_t > 3.0:
			_fire_map_test = false
			_run_fire_map_test()

func _run_fire_map_test() -> void:
	var bad := PackedStringArray()
	if not is_instance_valid(world.tank) or not world.tank.is_indirect():
		print("[firemap] RESULT: FAILED — not crewing an artillery piece")
		world.get_tree().quit()
		return
	world.tank.map_target = Vector3.INF
	if not world.map.visible:
		world.map.toggle()
	await world.get_tree().process_frame
	var c: Vector2 = world.map.get_viewport_rect().size * 0.5 + Vector2(40.0, 30.0)
	var want: Vector2 = world.map._globe_point(c) if world.map.globe else Vector2.INF
	print("[firemap] map globe=%s tank on map=%s, ground under the click %s" % [
		str(world.map.globe), str(world.map.tank == world.tank), str(want.round())])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	click.position = c
	world.map._gui_input(click)
	if world.tank.map_target == Vector3.INF:
		bad.append("right click laid no fire mission (satellite picked: %s)" % str(Sim.sat_target != null))
	else:
		var off: float = Vector2(world.tank.map_target.x - want.x, world.tank.map_target.z - want.y).length() \
			if want.x != INF else 0.0
		print("[firemap] fire mission laid %.1f km from the gun, %.1f m from the point under the cursor" % [
			world.tank.global_position.distance_to(world.tank.map_target) * 0.001, off])
		if off > 5.0:
			bad.append("the mission landed %.0f m from the click" % off)
	for b in bad:
		print("[firemap]   ", b)
	print("[firemap] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --trackkilltest --trackkilltest=free
## Track a vehicle with the pod, kill it, and check the sensor holds the ground
## it was on rather than dropping back to slew: --trackkilltest[=free] (free
## takes the node out of the tree outright instead of killing it).
var _track_kill := ""
var _track_kill_t := 0.0

func tick_track_kill(delta: float) -> void:
	if _track_kill != "" and world.running and is_instance_valid(world.player):
		_track_kill_t += delta
		if _track_kill_t > 3.0 and _track_kill_t < 1e8:
			_track_kill_t = 1e9
			_run_track_kill_test()

func _run_track_kill_test() -> void:
	var bad := PackedStringArray()
	var fwd: Vector3 = -world.player.global_transform.basis.z
	fwd.y = 0.0
	var at: Vector3 = world.player.global_position + fwd.normalized() * 3500.0
	var spot := GameMode._dry_spot(at, 0.0, 300.0)
	var t := Tank.new()
	t.setup(1, Tank.pick_kind("mbt", 1, 7))
	t.ai = false
	world.add_child(t)
	t.global_transform = Tank.ground_pose(spot, 0.0, t.rest_height())
	await world.get_tree().create_timer(0.5).timeout
	world.pod.platform = world.player
	if not world.pod.active:
		world.pod.toggle()
	# point the head straight at it and take a point track
	var o: Vector3 = world.pod._head_origin()
	var rel: Vector3 = world.player.global_transform.basis.inverse() * (t.global_position - o)
	world.pod.yaw = atan2(-rel.x, -rel.z)
	world.pod.pitch = atan2(rel.y, Vector2(rel.x, rel.z).length())
	world.pod._process(0.016)
	world.pod.designate()
	if world.pod.mode != SensorPod.POINT or world.pod.tracked != t:
		bad.append("did not take a point track on the tank (mode %d)" % world.pod.mode)
	var where: Vector3 = t.global_position
	if _track_kill == "free":
		t.queue_free()
	else:
		t.take_hit(1e6, null)
	for i in 10:
		await world.get_tree().process_frame
	var held: float = Vector2(world.pod.area_point.x - where.x, world.pod.area_point.z - where.z).length()
	print("[trackkill] after the kill (%s): mode %s, holding %.1f m from where it was, aeroplane target %s, locked %s" % [
		"removed" if _track_kill == "free" else "destroyed",
		["SLEW", "AREA", "TRACK"][world.pod.mode], held, Sim.label_of(world.player.target), str(world.player.locked)])
	if world.pod.mode != SensorPod.AREA:
		bad.append("the sensor did not hold the area")
	elif held > 15.0:
		bad.append("held %.0f m away from the target" % held)
	# and it survives the page being shut
	world.pod.toggle()
	for i in 5:
		await world.get_tree().process_frame
	print("[trackkill] page closed: mode %s, aeroplane target %s" % [
		["SLEW", "AREA", "TRACK"][world.pod.mode], Sim.label_of(world.player.target)])
	if world.pod.mode != SensorPod.AREA or world.player.target == null:
		bad.append("closing the page let the area go")
	for b in bad:
		print("[trackkill]   ", b)
	print("[trackkill] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --fieldsvctest
## Where on the home field the ground crew will come out, and a rearm at the far
## end of the runway: --fieldsvctest.
var _field_svc_test := false
var _field_svc_t := 0.0

func tick_field_svc(delta: float) -> void:
	if _field_svc_test and world.running and is_instance_valid(world.player):
		_field_svc_t += delta
		if _field_svc_t > 3.0:
			_field_svc_test = false
			_run_field_svc_test()

func _run_field_svc_test() -> void:
	var bad := PackedStringArray()
	if not is_instance_valid(world.base):
		print("[fieldsvc] RESULT: FAILED — no home airbase")
		world.get_tree().quit()
		return
	var spots := [["far end of the runway", Vector3(0.0, 0.0, -1400.0), true],
		["near end of the runway", Vector3(0.0, 0.0, 1450.0), true],
		["the apron", Vector3(150.0, 0.0, -300.0), true],
		["by the hangars", Vector3(268.0, 0.0, -240.0), true],
		["a field 900 m off the side", Vector3(900.0, 0.0, 0.0), false]]
	world.player.active = false
	for sp in spots:
		var w: Vector3 = world.base.global_transform * (sp[1] as Vector3)
		w.y = Sim.height_at(w.x, w.z) + 2.0
		world.player.global_position = w
		var got: bool = world.player.near_service()
		print("[fieldsvc] %-28s crew %s" % [String(sp[0]), "comes out" if got else "stays in"])
		if got != bool(sp[2]):
			bad.append("%s: %s" % [String(sp[0]), "serviced" if got else "not serviced"])
	# and a full rearm out at the far end
	var far: Vector3 = world.base.global_transform * Vector3(0.0, 0.0, -1400.0)
	world.player.global_position = Vector3(far.x, Sim.height_at(far.x, far.z) + 2.0, far.z)
	world.player.fuel = float(world.player.spec["fuel"]) * 0.2
	var gone := 0
	for st in world.player.stores:
		st["gone"] = true
		gone += 1
	var fuel0: float = world.player.fuel
	var t := 0.0
	while t < 8.0:
		world.player.linear_velocity = Vector3.ZERO
		world.player.on_ground = true
		world.player.update_ground_service(1.0 / 60.0)
		await world.get_tree().process_frame
		t += 1.0 / 60.0
	var back := 0
	for st2 in world.player.stores:
		if not st2["gone"]:
			back += 1
	print("[fieldsvc] at the far end: crew working=%s, fuel %.0f -> %.0f kg, stores back %d of %d" % [
		str(world.player.servicing), fuel0, world.player.fuel, back, gone])
	if world.player.fuel <= fuel0 or (gone > 0 and back == 0):
		bad.append("the far end did not rearm or refuel")
	for b2 in bad:
		print("[fieldsvc]   ", b2)
	print("[fieldsvc] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --drivetest=
## Drive one vehicle straight, then on full lock, and say how far it went and
## how far it turned: --drivetest=KIND.
var _drive_test := ""

func tick_drive() -> void:
	if _drive_test != "" and world.running:
		var dk := _drive_test
		_drive_test = ""
		_run_drive_test(dk)

func _run_drive_test(kind: String) -> void:
	var t := Tank.new()
	t.setup(1, kind)
	t.ai = false
	world.add_child(t)
	# open country, clear of the airfield and the towns
	var at := GameMode._dry_spot(Vector3(4000.0, 0.0, -6000.0), 0.0, 400.0)
	t.global_transform = Tank.ground_pose(at, 0.0, t.rest_height())
	t.scripted = true
	t.occupied = true
	await world.get_tree().create_timer(1.5).timeout
	var p0 := t.global_position
	var y0: float = t.rotation.y
	for phase in [[0.6, 0.0], [0.6, 1.0], [0.0, 1.0], [0.3, 1.0]]:
		var p_a := t.global_position
		var y_a: float = t.global_transform.basis.get_euler().y
		var t0 := 0.0
		while t0 < 5.0:
			t.in_throttle = float(phase[0])
			t.in_steer = float(phase[1])
			await world.get_tree().physics_frame
			t0 += 1.0 / float(Engine.physics_ticks_per_second)
		var y_b: float = t.global_transform.basis.get_euler().y
		print("[drive] %s throttle %.1f steer %.1f: went %.0f m, turned %.0f deg, speed %.1f" % [
			kind, float(phase[0]), float(phase[1]),
			t.global_position.distance_to(p_a), rad_to_deg(absf(wrapf(y_b - y_a, -PI, PI))),
			t.speed])
	print("[drive] total %.0f m from the start, %s" % [t.global_position.distance_to(p0), str(y0)])
	world.get_tree().quit()
#endregion


#region --telrig= --telrig
var _tel_rig := ""

# Does the stitching actually hold across a change of detail? The seam stat
# only checks that a fine chunk's own edge is a straight line; it never
# compares that line with the coarse chunk on the other side of it. This
# reads the built meshes and asks both of them how high the ground is at the
# same point on the boundary.
# Is anything standing on the ground actually solid? Everything in the world
# except the terrain used to be scenery you flew through.
# Does the boat float, is there a ship under the flight deck, and can you
# actually take command of her?
# Does a launcher sit on its wheels, stay on them, and stand its canister up
# rather than slewing it round like a gun turret?
func tick_tel_rig() -> bool:
	if _tel_rig != "":
		var tk: String = _tel_rig
		_tel_rig = ""
		var t := world._spawn_tank(Vector3(1400.0, 0.0, -2600.0), 0.0, 0, tk)
		for i in 300:
			await world.get_tree().physics_frame
		var g: float = Sim.height_at(t.global_position.x, t.global_position.z)
		# where the tyres actually meet the ground
		var worst_sink := 0.0
		var worst_lift := 0.0
		for w in t._road_wheels:
			var n: Node3D = w["node"]
			var wr: float = float(w.get("r", Tank.WHEEL_R))
			var gw: float = Sim.height_at(n.global_position.x, n.global_position.z)
			var bottom: float = n.global_position.y - wr
			worst_sink = maxf(worst_sink, gw - bottom)
			worst_lift = maxf(worst_lift, bottom - gw)
		print("[tel] %s: %d wheels, hull %.2f m over the ground" % [tk,
			t._road_wheels.size(), t.global_position.y - g])
		print("[tel] tyres: worst %.2f m buried, worst %.2f m in the air" % [
			worst_sink, worst_lift])
		# and it has to be still, not hunting up and down
		var swing := 0.0
		var prev: float = t.global_position.y
		for i2 in 120:
			await world.get_tree().physics_frame
			swing = maxf(swing, absf(t.global_position.y - prev))
			prev = t.global_position.y
		print("[tel] settled: largest step in hull height over 1 s is %.4f m" % swing)
		# now give it something to shoot at and watch the canister. The AI is
		# off: it has a mark of its own and would keep taking this one away,
		# which shows up as an erector that goes up and down.
		t.ai = false
		t.map_target = Vector3(28000.0, 0.0, -9000.0)
		# 120 Hz physics, and the erector takes four seconds: 700 frames is
		# just under six, with room to spare.
		var yaw_moved := 0.0
		for i3 in 700:
			await world.get_tree().physics_frame
			yaw_moved = maxf(yaw_moved, absf(t._turret.rotation.y))
		print("[tel] erector at %.0f%% after 6 s, canister %.1f deg up, turret slewed %.3f deg" % [
			t._erect * 100.0, rad_to_deg(t._mantlet.rotation.x),
			rad_to_deg(yaw_moved)])
		var before: int = t.rounds_left
		Sim.debug_weapons = true
		t._gun_cd = 0.0
		print("[tel] fire_main returned %s" % str(t.fire_main(world)))
		await world.get_tree().physics_frame
		var went_up := -1.0
		for m in world.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m) and (m as Node3D).global_position.distance_to(
					t.global_position) < 40.0:
				went_up = (m as Missile).vel.normalized().y
		print("[tel] fired: %d -> %d rounds, round left the rail %.2f up" % [
			before, t.rounds_left, went_up])
		# It goes up. The question is whether it then goes anywhere: a vertical
		# launch that never pitches over onto the bearing is a firework.
		var mark: Vector3 = t.map_target
		# the round *this* launcher just sent, not whichever one happens to be
		# last in the group -- there are other shooters in the world
		var shot: Missile = null
		var nearest := 1e18
		for m2 in world.get_tree().get_nodes_in_group("missiles"):
			if not is_instance_valid(m2):
				continue
			var dd2: float = (m2 as Node3D).global_position.distance_to(
				t.global_position)
			if dd2 < nearest:
				nearest = dd2
				shot = m2
		print("[tel] following %s, %.0f m from the launcher" % [
			String(shot.wid) if shot != null else "nothing", nearest])
		var start_gap := 0.0
		var best_gap := 1e18
		var closed := false
		if shot != null:
			start_gap = Vector2(shot.global_position.x - mark.x,
				shot.global_position.z - mark.z).length()
			var lived := 0
			for f3 in 12000:                   # a hundred seconds: a ballistic
				# shot across the valley is a minute in the air, and cutting
				# the measurement off at thirty called every one of them a miss
				await world.get_tree().physics_frame
				if not is_instance_valid(shot):
					# A bus that has opened is gone on purpose. Follow whichever
					# of its load is nearest the mark instead of calling the
					# shot lost.
					# only this bus's own load, not whatever else the mission
					# happens to have in the air
					var kid := String(WeaponSpec.get_spec(
						String(t.KINDS[tk]["missile"])).get("mirv_child", ""))
					var heir: Missile = null
					var hd := 1e18
					for m3 in world.get_tree().get_nodes_in_group("missiles"):
						if not is_instance_valid(m3) or String(m3.wid) != kid:
							continue
						var md: float = (m3 as Node3D).global_position.distance_to(mark)
						if md < hd:
							hd = md
							heir = m3
					if heir == null:
						break
					shot = heir
				lived = f3
				var gap: float = Vector2(shot.global_position.x - mark.x,
					shot.global_position.z - mark.z).length()
				best_gap = minf(best_gap, gap)
				if f3 % 600 == 0:
					print("[tel]   t=%4.1f s  at %s  speed %.0f m/s  gap %.1f km  vls=%s target=%s" % [
						float(f3) / 120.0, str(shot.global_position.round()),
						shot.vel.length(), gap * 0.001, str(shot._vls),
						str(is_instance_valid(shot.target))])
			print("[tel]   round lasted %.1f s" % (float(lived) / 120.0))
			closed = best_gap < start_gap * 0.8
			print("[tel] mark %.1f km off at launch; closest approach was %.1f km" % [
				start_gap * 0.001, best_gap * 0.001])
		else:
			print("[tel] no round in the air to follow")
		var ok: bool = worst_sink < 0.12 and worst_lift < 0.25 and swing < 0.02 \
			and t._erect > 0.97 and yaw_moved < 0.001 \
			and t.rounds_left == before - 1 and went_up > 0.9 and closed
		print("[tel] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --slopetest
var _slope_test := false
var _slope_t := 0.0
var _slope_step := 0
var _slope_veh: Tank = null
var _slope_p0 := Vector3.ZERO
var _slope_from := Vector3.ZERO
var _slope_list: Array = ["m1a2", "m109", "bradley", "shilka"]
var _slope_i := 0
var _slope_note: Array = []

func tick_slope(delta: float) -> bool:
	if _slope_test:
		_slope_t += delta
		if _slope_step == 0 and _slope_t > 2.5:
			_slope_step = 1
			_slope_t = 0.0
			# somewhere with a real side slope, found rather than assumed
			var best := Vector3.ZERO
			var steepest := 0.0
			for i in 400:
				var q := Vector3(randf_range(-9000.0, 9000.0), 0.0,
					randf_range(-9000.0, 9000.0))
				var n := Sim.normal_at(q.x, q.z)
				var tilt: float = rad_to_deg(acos(clampf(n.dot(Vector3.UP), -1.0, 1.0)))
				if tilt > steepest and tilt < 18.0:
					steepest = tilt
					best = q
			_slope_p0 = best
			_slope_note.append("slope found: %.1f degrees at %s" % [
				steepest, str(best.round())])
		elif _slope_step == 1:
			if not is_instance_valid(_slope_veh):
				if _slope_i >= _slope_list.size():
					_slope_test = false
					var bad := 0
					for n2 in _slope_note:
						print("[slope] %s" % String(n2))
						if String(n2).contains("SLID"):
							bad += 1
					print("[slope] RESULT: %s" % ("ok" if bad == 0 else
						"FAILED — %d vehicle(s) will not stay parked" % bad))
					world.get_tree().quit()
					return true
				# Across the slope, which is the worst case: a hull pointed
				# along it is held by its own tracks fore and aft.
				_slope_veh = world._spawn_tank(_slope_p0, deg_to_rad(90.0), 0,
					String(_slope_list[_slope_i]))
				_slope_veh.in_brake = true
				# From where it actually ended up, not where it was asked for:
				# `_spawn_tank` looks for a clear spot and can move the vehicle
				# sixty metres doing it, which this then scored as sixty metres
				# of sliding.
				_slope_from = _slope_veh.global_position
				_slope_t = 0.0
				return true
			_slope_veh.in_throttle = 0.0
			_slope_veh.in_steer = 0.0
			_slope_veh.in_brake = true
			if _slope_t > 8.0:
				var moved: float = Vector2(
					_slope_veh.global_position.x - _slope_from.x,
					_slope_veh.global_position.z - _slope_from.z).length()
				var nn := Sim.normal_at(_slope_from.x, _slope_from.z)
				var tilt2: float = rad_to_deg(acos(clampf(nn.dot(Vector3.UP), -1.0, 1.0)))
				_slope_note.append("%-9s on %.1f deg: drifted %.2f m in 8 s with the brakes on%s" % [
					_slope_veh.kind, tilt2, moved, "   <- SLID" if moved > 3.0 else ""])
				_slope_veh.queue_free()
				_slope_veh = null
				_slope_i += 1
				_slope_t = 0.0
		return true
	return false
#endregion


#region --svctest
var _svc_test := false
var _svc_t := 0.0
var _svc_step := 0
var _svc_note: Array = []
var _svc_fuel0 := 0.0
var _svc_ammo0 := 0
var _svc_tanker: Aircraft = null

func tick_svc(delta: float) -> bool:
	if _svc_test and is_instance_valid(world.player):
		_svc_t += delta
		match _svc_step:
			0:
				if _svc_t > 2.5:
					_svc_step = 1
					_svc_t = 0.0
					# A ground battery's own search radar: it should widen the
					# side's picture the same way an aircraft or a satellite
					# does, and be named as the source.
					var pat := world._spawn_tank(
						world.player.global_position + Vector3(300.0, 0.0, 300.0),
						0.0, 0, "patriot")
					pat.ai = true
					_svc_note.append("a Patriot on the ground: radar %.0f km, in the air_radar group=%s" % [
						pat.radar_range() * 0.001,
						str(pat.is_in_group("air_radar"))])
					_svc_note.append("the side's picture with only that battery: %.0f km (%s)" % [
						Sim.coverage(0) * 0.001, Sim.coverage_source(0)])
					# what the side can see with nothing helping it
					# All three figures, because "coverage" is only meaningful
					# against what the aeroplane can do on its own.
					_svc_note.append("the aeroplane's own radar: %.0f km" % (
						Sim.radar_range() * 0.001))
					_svc_note.append("with a recon satellite up: %.0f km (%s)" % [
						Sim.coverage(0) * 0.001, Sim.coverage_source(0)])
					# put an E-3 up and ask again
					var awacs := AIPlane.new()
					awacs.setup("e3")
					awacs.team = 0
					awacs.role = "transport"
					world.add_child(awacs)
					awacs.global_position = world.player.global_position \
						+ Vector3(4000.0, 500.0, 0.0)
					awacs.linear_velocity = Vector3(0, 0, -180.0)
					world._reset_interp.call_deferred(awacs)
			1:
				if _svc_t > 1.0:
					_svc_step = 2
					_svc_t = 0.0
					_svc_note.append("with an E-3 airborne: %.0f km (%s)" % [
						Sim.coverage(0) * 0.001, Sim.coverage_source(0)])
					# now the tanker, and the aeroplane put in the box behind it
					var tk := AIPlane.new()
					tk.setup("kc135")
					tk.team = 0
					tk.role = "transport"
					world.add_child(tk)
					tk.global_position = world.player.global_position + Vector3(0, 40.0, -900.0)
					tk.linear_velocity = -tk.global_transform.basis.z * 190.0
					world._reset_interp.call_deferred(tk)
					_svc_tanker = tk
			2:
				if is_instance_valid(_svc_tanker) and _svc_t > 1.5:
					# fly the receiver into the contact position and burn some
					# fuel off first so there is room to put any in
					world.player.fuel = float(world.player.spec["fuel"]) * 0.4
					_svc_fuel0 = world.player.fuel
					var boom: Vector3 = _svc_tanker.global_transform \
						* (_svc_tanker.spec.get("boom", Vector3(0, -2, 24)) as Vector3)
					world.player.global_transform = Transform3D(
						_svc_tanker.global_transform.basis, boom + Vector3(0, -2.0, 6.0))
					world.player.linear_velocity = _svc_tanker.linear_velocity
					world._reset_interp.call_deferred(world.player)
					_svc_step = 3
					_svc_t = 0.0
			3:
				# hold station: the harness flies formation the crude way
				if is_instance_valid(_svc_tanker):
					var boom2: Vector3 = _svc_tanker.global_transform \
						* (_svc_tanker.spec.get("boom", Vector3(0, -2, 24)) as Vector3)
					world.player.global_transform = Transform3D(
						_svc_tanker.global_transform.basis, boom2 + Vector3(0, -2.0, 6.0))
					world.player.linear_velocity = _svc_tanker.linear_velocity
					world.player.update_refuel(delta)
				if _svc_t > 6.0:
					_svc_note.append("refuelling: %.0f kg -> %.0f kg in 6 s (contact=%s)" % [
						_svc_fuel0, world.player.fuel, str(world.player.refuelling)])
					_svc_step = 4
					_svc_t = 0.0
					# and now on the ground, empty and shot up
					var b: Vector3 = world.base.global_position if is_instance_valid(world.base) \
						else Vector3.ZERO
					world.player.global_transform = Transform3D(Basis(),
						Vector3(b.x + 40.0, Sim.height_at(b.x + 40.0, b.z) + 2.0, b.z))
					world.player.linear_velocity = Vector3.ZERO
					world.player.angular_velocity = Vector3.ZERO
					world.player.on_ground = true
					world.player.fuel = float(world.player.spec["fuel"]) * 0.1
					world.player.health = 42.0
					world.player.ammo = 20
					_svc_ammo0 = world.player.ammo
					_svc_fuel0 = world.player.fuel
					world._reset_interp.call_deferred(world.player)
			4:
				world.player.linear_velocity = Vector3.ZERO
				world.player.on_ground = true
				world.player.update_ground_service(delta)
				if _svc_t > 12.0:
					_svc_note.append("ground crew: fuel %.0f -> %.0f kg, hull 42 -> %.0f, %d -> %d rounds (working=%s)" % [
						_svc_fuel0, world.player.fuel, world.player.health,
						_svc_ammo0, world.player.ammo, str(world.player.servicing)])
					_svc_test = false
					for n in _svc_note:
						print("[svc] %s" % String(n))
					# What the crew delivered, not what the tank happens to
					# hold: the bar used to be half a full load, which at
					# 120 kg a second is 28 seconds of pumping and the test
					# only waits twelve. Waiting it out is not an option
					# either -- parked and damaged, the aeroplane is shot up
					# where it stands before half a minute is out. The rate is
					# the thing being tested, and it does not care how long
					# the window is.
					var ok: bool = Sim.coverage(0) > 100000.0 \
						and world.player.fuel - _svc_fuel0 > Aircraft.SERVICE_FUEL * 10.0 \
						and world.player.health > 60.0 and world.player.ammo > _svc_ammo0
					print("[svc] RESULT: %s" % ("ok" if ok else "FAILED"))
					world.get_tree().quit()
		return true
	return false
#endregion


#region --teltest
var _tel_test := false
## What the screen looked like from high on the arc: the haze and the camera
## the HUD was projecting its boxes through.
var _tel_hz := ""
var _tel_hz_bad := false
var _tel_salvo := 0
var _tel_t := 0.0
var _tel_step := 0
var _tel: Tank = null
var _tel_kids := 0
## Where the launcher was told to put the round, and how far off each warhead
## of the bus ended up.
var _tel_aim := Vector3.ZERO
## Marks assigned to individual warheads, and how near each got to the one it
## was given.
var _tel_rv: Array = []
var _tel_miss: Dictionary = {}
var _tel_cam := false

# A launcher, a hypersonic round and a warhead bus that opens on the way in.
func tick_tel(delta: float) -> bool:
	if _tel_test:
		_tel_t += delta
		if _tel_step == 0 and _tel_t > 2.5:
			_tel_step = 1
			# through the menu path, so the camera and the crewing are the real
			# ones rather than a launcher conjured beside a world with no
			# mission running and no camera in it
			world._start("veh:tel_oreshnik", "free")
			await world.get_tree().process_frame
			await world.get_tree().physics_frame
			if not is_instance_valid(world.tank):
				print("[tel] could not crew a launcher")
				_tel_test = false
				world.get_tree().quit()
				return true
			_tel = world.tank
			var here: Vector3 = _tel.global_position
			var mark := Vector3(here.x - 60000.0, 0.0, here.z - 40000.0)
			mark.y = Sim.height_at(mark.x, mark.z)
			_tel.map_target = mark
			_tel_aim = mark
			# Two of the six warheads are given marks of their own, so the test
			# covers what "independently targetable" is supposed to mean as well
			# as the footprint the rest of them spread over.
			_tel_rv = [mark + Vector3(3500.0, 0.0, 0.0),
				mark + Vector3(-2800.0, 0.0, 2200.0)]
			for k4 in _tel_rv.size():
				var q4: Vector3 = _tel_rv[k4]
				q4.y = Sim.height_at(q4.x, q4.z)
				_tel_rv[k4] = q4
			_tel.mirv_marks = _tel_rv.duplicate()
			print("[tel] %s with %d round(s), aiming point %.0f km away" % [
				_tel.display_name(), _tel.rounds_left,
				_tel.global_position.distance_to(mark) * 0.001])
			_tel._gun_cd = 0.0
			world.weapon_cam_on = true
			# A launcher will not fire lying down any more: it stands the
			# canister up first, and that takes four seconds.
			var waited := 0
			while _tel._erect < 0.97 and waited < 900:
				await world.get_tree().physics_frame
				waited += 1
			print("[tel] canister up (%.0f%%) after %d frames" % [
				_tel._erect * 100.0, waited])
			print("[tel] launch: %s" % str(_tel.fire_main(world)))
			_tel_cam = is_instance_valid(world.cam) and is_instance_valid(world.cam.weapon_cam) \
				and String(world.cam.weapon_cam.get("wid")) == "oreshnik"
			print("[tel] weapon camera riding the round: %s (chase camera has the screen: %s)" % [
				str(_tel_cam),
				str(world.cam.current) if is_instance_valid(world.cam) else "no camera"])
		elif _tel_step == 1:
			var bus := 0
			var kids := 0
			var top := 0.0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				if String(m.wid) == "oreshnik":
					bus += 1
					top = maxf(top, (m as Node3D).global_position.y)
				elif String(m.wid) == "orehead":
					kids += 1
			# The first frame after the bus opens: the camera should be on one
			# warhead and know about all of them, and the map open over it has
			# to draw the lot.
			if kids > 0 and _tel_kids == 0:
				var rv: Variant = world.cam.get("weapon_cam") if is_instance_valid(world.cam) else null
				if rv != null and is_instance_valid(rv) and rv is Missile:
					var pk: Array = (rv as Missile).salvo()
					var on_units := 0
					for k5 in pk:
						if (k5 as Missile).locked_on_unit():
							on_units += 1
					print("[tel] riding a warhead: it knows of %d in its load, %d on units" % [
						pk.size(), on_units])
					_tel_salvo = pk.size()
				if not world.map.visible:
					world.map.toggle()
			_tel_kids = maxi(_tel_kids, kids)
			# Riding the round high on its arc: the haze is the thin air at the
			# eye, and the HUD draws through the camera that is on screen.
			# Checked against the thinning the camera's own height calls for:
			# the launcher's would leave it at the sea-level figure.
			if is_instance_valid(world.cam) and world.cam.current \
					and is_instance_valid(world.cam.weapon_cam) \
					and Sim.altitude(world.cam.global_position) > 1500.0:
				var live: Camera3D = world.hud._live_camera()
				var ca: float = Sim.altitude(world.cam.global_position)
				var cx: float = ca / 8500.0
				var want_end: float = world.weather.fog_far * cx / (1.0 - exp(-cx))
				_tel_hz = "at %.1f km up: fog ends %.0f km (%.0f km for that height, %.0f at the launcher's); HUD projects through %s" % [
					ca * 0.001, world._env.fog_depth_end * 0.001, want_end * 0.001,
					world.weather.fog_far * 0.001,
					"the weapon camera" if live == world.cam else str(live)]
				# a frame behind at most, while the round climbs
				_tel_hz_bad = _tel_hz_bad or live != world.cam \
					or absf(world._env.fog_depth_end - want_end) > want_end * 0.08
			if fmod(_tel_t, 15.0) < delta:
				print("[tel]   t=%5.1f  bus up %d (apogee so far %.0f m), warheads %d" % [
					_tel_t, bus, top, kids])
			# Where the load is going, not merely that there is some.
			#
			# This checked that the bus opened and that the camera followed it,
			# and stopped there -- so a shot whose warheads came down nowhere
			# near the aiming point passed every time. The number that matters
			# is how far each one is off the mark when it goes off.
			for m2 in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m2) or String(m2.wid) != "orehead":
					continue
				var mp2: Vector3 = (m2 as Node3D).global_position
				# against the nearest mark it could have been given, since the
				# bus deals them out in its own order
				var off := 1e9
				for a4 in ([_tel_aim] + _tel_rv):
					off = minf(off, Vector2(mp2.x - (a4 as Vector3).x,
						mp2.z - (a4 as Vector3).z).length())
				_tel_miss[m2.get_instance_id()] = off
			if (bus == 0 and _tel_t > 12.0 and _tel_kids > 0
					and world.get_tree().get_nodes_in_group("missiles").is_empty()) \
					or _tel_t > 300.0:
				_tel_test = false
				print("[tel] the bus opened into %d warhead(s)" % _tel_kids)
				var offs: Array = _tel_miss.values()
				offs.sort()
				var worst: float = float(offs[offs.size() - 1]) if not offs.is_empty() else -1.0
				var mean := 0.0
				for o in offs:
					mean += float(o)
				mean /= maxf(float(offs.size()), 1.0)
				print("[tel] warheads down: mean %.0f m from the aiming point, worst %.0f m" % [
					mean, worst])
				# A bus with a 900 m footprint should put its load inside about
				# that; anything kilometres out is a warhead that never flew to
				# the mark at all.
				print("[tel] %s" % (_tel_hz if _tel_hz != ""
					else "never saw the weapon camera off the ground"))
				print("[tel] RESULT: %s" % ("ok" if _tel_kids >= 4 and _tel_cam
					and not offs.is_empty() and worst < 2600.0
					and _tel_hz != "" and not _tel_hz_bad
					and _tel_salvo == _tel_kids else "FAILED"))
				world.get_tree().quit()
		# a picture from the ride, when one was asked for: --shot with --frames,
		# counted from the launch rather than from the start of the test
		if world._shot != "" and _tel_cam:
			world.shot_frames -= 1
			if world.shot_frames == 0:
				harness._take_shot()
		return true
	return false
#endregion


#region --susptest
## Does a vehicle put on the ground stay on it? Every ground spawn used to drop
## the hull from a flat 1.1 m onto a level basis, and a launcher -- whose wheel
## centres sit a tyre radius ABOVE its origin -- therefore arrived a metre in
## the air and bounced on springs damped at a fifth of critical.
var _susp_test := false
var _susp_t := 0.0

func tick_susp(delta: float) -> bool:
	if _susp_test:
		_susp_t += delta
		if _susp_t > 2.0:
			_susp_test = false
			await _run_suspension_test()
			world.get_tree().quit()
		return true
	return false

## Stand one of everything on the ground and watch it settle. A vehicle that
## is put down where its suspension says it belongs should barely move; one
## that is dropped bounces, and the peak excursion here is exactly the fault
## the launchers had.
func _run_suspension_test() -> void:
	var bad := 0
	for kind in VehicleSpec.KINDS.keys():
		var t := world._spawn_tank(Vector3(3200.0, 0.0, -3200.0), 0.4, 0, String(kind))
		await world.get_tree().physics_frame
		var rest: float = t.global_position.y
		var lo := 0.0
		var hi := 0.0
		var settle := 0.0
		for i in 180:                       # three seconds at 60 Hz
			await world.get_tree().physics_frame
			if not is_instance_valid(t):
				break
			var d: float = t.global_position.y - rest
			lo = minf(lo, d)
			hi = maxf(hi, d)
			if absf(d) > 0.04 or t.linear_velocity.length() > 0.35:
				settle = float(i + 1) / 60.0
		var swing: float = hi - lo
		var ok: bool = swing < 0.30 and settle < 1.2
		# and then drive it: full throttle and full lock, to see that it gets
		# up to something like its governed speed and that the hull actually
		# comes round. A wheeled vehicle steers on its front axle now, and
		# nothing was checking that the axle turned the lorry.
		var top := 0.0
		var turned := 0.0
		if is_instance_valid(t):
			t.occupied = true
			t.scripted = true
			t.in_throttle = 1.0
			t.in_steer = 0.0
			for i in 720:                   # twelve seconds down the valley
				await world.get_tree().physics_frame
				if not is_instance_valid(t):
					break
				top = maxf(top, absf(t.speed))
			# and then put it on full lock, which is the part the front axle
			# has to do now that a wheeled vehicle no longer skid-steers
			var head0: float = t.rotation.y
			t.in_steer = 1.0
			for i in 300:
				await world.get_tree().physics_frame
				if not is_instance_valid(t):
					break
				turned += absf(wrapf(t.rotation.y - head0, -PI, PI))
				head0 = t.rotation.y
		var want: float = float(VehicleSpec.KINDS[kind]["top"])
		# What counts as "it came round" depends on what it is. A jeep on its
		# front axle turns smartly; a six-axle launcher fourteen metres long
		# does not, and a tracked hull has to drag a track sideways against a
		# lot of lateral bite and barely turns at all at road speed -- which is
		# how armour has always behaved here, so that only asks that it turns.
		var need := 0.5
		match String(VehicleSpec.KINDS[kind].get("class", "mbt")):
			"mbt", "spg", "mlrs", "ifv", "spaag":
				need = 0.05          # tracked: it turns by dragging a track
			"tel", "asat":
				need = 0.35          # a very long lorry on a very long wheelbase
		var moves: bool = top > want * 0.45 and turned > need
		if not moves:
			bad += 1
		print("[susp] %-13s swing %5.2f m, still at %4.2f s, %4.1f of %4.1f m/s, turned %3.0f deg%s" % [
			String(kind), swing, settle, top, want, rad_to_deg(turned),
			"" if ok and moves else ("   <- BOUNCING" if not ok else "   <- WILL NOT DRIVE")])
		if is_instance_valid(t):
			t.queue_free()
		await world.get_tree().process_frame
	print("[susp] RESULT: %s" % ("ok" if bad == 0 else
		"FAILED — %d vehicle(s) would not sit still or would not drive" % bad))
#endregion


#region --tanksensor
var _tanksensor := false
var _tanksensor_t := 0.0

# The same page from an armoured vehicle: does it open at all, does it sit
# at the commander's sight rather than a masthead, does the mouse belong to
# the sight instead of the turret, and does lasing lay the piece.
func tick_tanksensor(delta: float) -> bool:
	if _tanksensor:
		_tanksensor_t += delta
		if _tanksensor_t > 2.5:
			_tanksensor = false
			_run_tanksensor()
			world.get_tree().quit()
			return true
	return false

func _run_tanksensor() -> void:
	# An artillery piece for preference -- the fire mission the sight hands over
	# is what a self propelled gun actually does with a laser.
	var tk: Tank = null
	for n in world.get_tree().get_nodes_in_group("vehicles"):
		var v := n as Tank
		if v == null or v.team != 0 or not v.alive:
			continue
		if tk == null or (v.is_indirect() and not tk.is_indirect()):
			tk = v
	if tk == null:
		# Nothing on the ramp in this mission: put a gun on the ground for the
		# test rather than skipping it.
		var here: Vector3 = Vector3.ZERO
		if is_instance_valid(world.player):
			here = world.player.global_position
		tk = world._spawn_tank(Vector3(here.x + 60.0, 0, here.z + 60.0), 0.0, 0, "m109")
	print("[tanksensor] vehicle %s, indirect=%s" % [tk.display_name(), str(tk.is_indirect())])
	world.running = true          # the harness fires before the menu hands over
	world.crew.enter_tank(tk)
	world.controls.do_action("sensor")
	for _f in 12:
		world._process(0.016)
	print("[tanksensor] on %s: pod active=%s, carrier=%s (running=%s on_foot=%s occupied=%s)" % [
		tk.display_name(), str(world.pod.active), Sim.label_of(world.pod.platform),
		str(world.running), str(world.on_foot), str(tk.occupied)])
	# the sight sits at the commander's hatch, not eighteen metres up a mast
	var lift: float = world.pod._head_origin().y - tk.global_position.y
	print("[tanksensor] sight height %.2f m above the hull (mast assumption was 18.00)" % lift)
	# the mouse belongs to the sight: slewing must not walk the turret round
	var sweep := Vector2(220.0, 0.0)
	var yaw0: float = tk.aim_yaw
	tk.aim_mouse(sweep)
	var with_sight: float = absf(tk.aim_yaw - yaw0)
	tk.sight_active = false
	yaw0 = tk.aim_yaw
	tk.aim_mouse(sweep)
	var without: float = absf(tk.aim_yaw - yaw0)
	tk.sight_active = true
	print("[tanksensor] same mouse sweep: %.4f rad of turret with the sight up, %.4f rad with it down" % [
		with_sight, without])
	# point the sight at something hostile and lase: the piece takes the mark
	var foe: Node3D = null
	var bd := 1e9
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not (n is Node3D) or n == tk:
			continue
		if not ("team" in n) or int(n.team) == tk.team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = tk.global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			foe = n as Node3D
	tk.map_target = Vector3.INF
	if foe != null:
		# The pod aims in the carrier's own frame: dir = basis * (yaw, pitch).
		# Working the angles off world axes points the sight somewhere else
		# entirely the moment the hull is sitting on a slope.
		var rel: Vector3 = foe.global_position - world.pod._head_origin()
		var loc: Vector3 = (tk.global_transform.basis.inverse() * rel).normalized()
		world.pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
		world.pod.yaw = atan2(-loc.x, -loc.z)
		world.pod.mode = world.pod.SLEW
		world.pod._process(0.016)
		world.pod.designate()
		if not world.pod.lasing:
			world.pod.toggle_laser()
		world.pod._process(0.016)
		var laid: bool = tk.map_target != Vector3.INF
		var err := 0.0
		if laid:
			err = Vector2(tk.map_target.x - foe.global_position.x,
				tk.map_target.z - foe.global_position.z).length()
		print("[tanksensor] lased %s at %.1f km: mode=%d (0=SLEW 1=AREA 2=POINT) tracked=%s lasing=%s" % [
			Sim.label_of(foe), bd * 0.001, world.pod.mode, Sim.label_of(world.pod.tracked), str(world.pod.lasing)])
		print("[tanksensor] fire mission set=%s, %.1f m from the target" % [str(laid), err])
	# contacts drawn on the sight picture, which used to bail out on a null jet
	var painted := 0
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == tk or not (n is Node3D):
			continue
		if tk.global_position.distance_to((n as Node3D).global_position) < 26000.0:
			painted += 1
	print("[tanksensor] %d contacts in sight range (platform is %s, aircraft is %s)" % [
		painted, Sim.label_of(world.pod.platform), "null" if world.pod.platform == null else "set"])
	# and dismounting puts the sight away
	world.crew.leave_tank()
	world._process(0.016)
	print("[tanksensor] after dismount: pod active=%s, host=%s" % [
		str(world.pod.active), "null" if world.pod.platform == null else str(world.pod.platform)])
	print("[tanksensor] RESULT: %s" % ("ok" if lift < 4.0 and not world.pod.active
		and with_sight < 1e-6 and without > 1e-3 else "FAILED"))
#endregion


#region --keytest=
var _key_test := ""
var _key_t := 0.0

func tick_key(delta: float) -> void:
	if _key_test != "" and is_instance_valid(world.tank):
		_key_t += delta
		if _key_t > 3.0:
			var kind := world.tank.kind
			# M must still open the map from the driver's seat: that is how a
			# fire mission is designated
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_M
			ev.pressed = true
			world.controls.shell_input(ev)
			var map_open: bool = world.map.visible
			world.controls.shell_input(ev)                     # and close it again
			# right click with freelook held must NOT raise the sensor camera
			Input.action_press(&"freelook")
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = true
			world.controls.shell_input(mb)
			Input.action_release(&"freelook")
			# the side panels and radar range are on the same handler
			var before: int = Sim.panel_left
			var pv := InputEventKey.new()
			pv.physical_keycode = KEY_BRACKETLEFT
			pv.pressed = true
			world.controls.shell_input(pv)
			# left click must fire, and weapon select must swap main/coax
			var w0: String = world.tank.current_weapon()
			world.tank.cycle_weapon()
			var w1: String = world.tank.current_weapon()
			world.tank.set_weapon(0)
			var r_before: int = world.tank.rounds_left
			var cd0: float = world.tank._gun_cd
			Input.action_press(&"fire")
			world.tank._drive_input(0.016)
			Input.action_release(&"fire")
			var lc_fired: bool = world.tank.rounds_left < r_before or world.tank._gun_cd > cd0
			print("[keys] %s: weapons %s -> cycle gives %s; left click fired=%s" % [
				kind, w0, w1, str(lc_fired)])
			# and the sensor chord must not pull the trigger
			var rounds_before: int = world.tank.rounds_left
			var cd_before: float = world.tank._gun_cd
			Input.action_press(&"freelook")
			Input.action_press(&"fire")
			world.tank._drive_input(0.016)
			Input.action_release(&"fire")
			Input.action_release(&"freelook")
			var fired: bool = world.tank.rounds_left < rounds_before or world.tank._gun_cd > cd_before
			print("[keys] %s: M opens map=%s, pod stayed shut=%s, [ cycled panel=%s, chord fired gun=%s" % [
				kind, str(map_open), str(not world.pod.active), str(Sim.panel_left != before),
				str(fired)])
			_key_test = ""
			world.get_tree().quit()
#endregion


#region --wrecktest
var _wreck_test := false
var _wreck_t2 := 0.0

func tick_wreck(delta: float) -> void:
	if _wreck_test:
		_wreck_t2 += delta
		if _wreck_t2 > 3.0 and _wreck_t2 < 3.0 + delta:
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				if v is Tank and v.alive:
					v.apply_damage(9999.0)
			print("[wreck] every vehicle destroyed")
		if _wreck_t2 > 4.0 and fmod(_wreck_t2, 3.0) < delta:
			var lo := 1e9
			var n := 0
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				if is_instance_valid(v):
					n += 1
					lo = minf(lo, v.global_position.y - Sim.height_at(
						v.global_position.x, v.global_position.z))
			var junk := world.get_tree().get_nodes_in_group("wreckage")
			var loose := 0
			var settled := 0
			var turrets := 0
			for w in junk:
				if not is_instance_valid(w) or not (w is Effects.Debris):
					continue
				loose += 1
				if String(w.name).ends_with("turret"):
					turrets += 1
				if (w as Effects.Debris).at_rest():
					settled += 1
			var burning := 0
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				if is_instance_valid(v) and bool(v.get("_wrecked")):
					burning += 1
			var sample := ""
			for w in junk:
				if is_instance_valid(w) and w is Effects.Debris:
					var rb := w as Effects.Debris
					sample = " first: agl %.2f v %.2f" % [
						rb.global_position.y - Sim.height_at(rb.global_position.x,
							rb.global_position.z), rb.vel.length()]
					break
			print("[wreck] t=%4.1f  vehicles=%d  lowest above ground=%.2f m  burning=%d  debris=%d (%d turrets, %d at rest)%s" % [
				_wreck_t2, n, lo, burning, loose, turrets, settled, sample])
#endregion


#region --wallram
## A tank driven flat out at a building, square on and then at a slant: how far
## the hull's centreline gets inside the footprint, which should be nothing
## more than the hull's own half-width past the wall line.
var _ram_test := false
var _ram_t := 0.0
var _ram_box := -1
var _ram_case := 0
var _ram_deep := 0.0
var _ram_top := 0.0
var _ram_start := Transform3D.IDENTITY
## The last is a hangar, which is kept outside `Obstacles`.
const RAM_CASES := [0.0, 35.0, 70.0, 20.0]
var _ram_hangar: GroundTarget = null
var _ram_tank: Tank = null

func _tick_ram(delta: float) -> void:
	if not _ram_test:
		return
	if not is_instance_valid(_ram_tank):
		for v in world.get_tree().get_nodes_in_group("vehicles"):
			world.crew.enter_tank(v as Tank)
			if world.tank == null:
				continue
			_ram_tank = world.tank
			_ram_tank.scripted = true
			_ram_start = _ram_tank.global_transform
			break
		return
	var t: Tank = _ram_tank
	# the scenario's own armour is about; this is not a test of that
	t.health = maxf(t.health, 1.0e6)
	if not t.alive:
		print("[ram] the tank was knocked out by %s; RESULT: inconclusive" % [t.last_cause])
		_ram_test = false
		world.get_tree().quit()
		return
	if _ram_box < 0:
		# a building thirty metres ahead, turned by this case's angle
		var fwd: Vector3 = -_ram_start.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var at: Vector3 = _ram_start.origin + fwd * 30.0
		var yaw: float = atan2(fwd.x, fwd.z) + deg_to_rad(float(RAM_CASES[_ram_case]))
		at.y = Sim.height_at(at.x, at.z) - 1.0
		if _ram_case == RAM_CASES.size() - 1:
			_ram_hangar = GroundTarget.new()
			_ram_hangar.setup("hangar")
			world.add_child(_ram_hangar)
			_ram_hangar.global_transform = Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0, 1.0, 0))
			_ram_box = 0
		else:
			_ram_box = Obstacles.add_box(at, 9.0, 12.0, 6.0, yaw)
		t.global_transform = _ram_start
		t.linear_velocity = Vector3.ZERO
		t.angular_velocity = Vector3.ZERO
		_ram_t = 0.0
		_ram_deep = 0.0
		_ram_top = 0.0
		return
	_ram_t += delta
	t.in_throttle = 1.0
	t.in_steer = 0.0
	t.in_brake = false
	_ram_top = maxf(_ram_top, absf(t.speed))
	var xf: Transform3D = t.global_transform
	for lz in t._hull_z:
		var p: Vector3 = xf * Vector3(0.0, 0.6, lz)
		var inside: Vector3 = GroundTarget.push_out_any(p, 0.0) if is_instance_valid(_ram_hangar) \
			else Obstacles.push_out(_ram_box, p, 0.0)
		_ram_deep = maxf(_ram_deep, inside.length())
	if _ram_t > 14.0:
		print("[ram] %s %s at %2.0f deg: top %.1f km/h, centreline at most %.2f m inside (half-width %.2f), ends at %.1f km/h" % [
			t.display_name(), "hangar" if is_instance_valid(_ram_hangar) else "building",
			float(RAM_CASES[_ram_case]), _ram_top * 3.6, _ram_deep,
			t.hull_radius(), absf(t.speed) * 3.6])
		if is_instance_valid(_ram_hangar):
			_ram_hangar.queue_free()
			_ram_hangar = null
		else:
			Obstacles.remove(_ram_box)
		_ram_box = -1
		_ram_case += 1
		if _ram_case >= RAM_CASES.size():
			_ram_test = false
			print("[ram] RESULT: %s" % "done")
			world.get_tree().quit()
#endregion

#region --tankair
## A garrison vehicle and a helicopter it ought to engage: hanging still low
## over the field, hanging high and close, and crossing slowly. Whether the crew
## takes it as its target, how many rounds go, and what they do to it.
## --preset=ground:veh:m1a2 --tankair[=kind]
var _air_test := false
var _air_kind := "m1a2"
var _air_tank: Tank = null
var _air_heli: AIHeli = null
var _air_case := 0
var _air_t := 0.0
var _air_shots := 0
var _air_coax := 0
var _air_locked := 0.0
var _air_cd_was := 0.0
var _air_coax_was := 0.0
var _air_hp0 := 0.0
## [range m, height above the tank m, crossing speed m/s]
## The second is above a main battle tank's gun. The last is a jet running in
## from two kilometres: taken while it is far enough off for the turret to stay
## on it, which is also when a crew would have the time to.
const AIR_CASES := [[700.0, 110.0, 0.0], [350.0, 230.0, 0.0], [800.0, 90.0, 25.0],
	[1500.0, 250.0, 60.0], [400.0, 60.0, 230.0]]

func _tick_air(delta: float) -> void:
	if not _air_test:
		return
	if not is_instance_valid(_air_tank):
		if not world.running:
			return
		# well away from everything else: its own garrison, our parked armour
		var at: Vector3 = Vector3(9000.0, 0.0, 9000.0)
		at.y = Sim.height_at(at.x, at.z) + 1.5
		_air_tank = Tank.new()
		_air_tank.setup(1, _air_kind)
		world.add_child(_air_tank)
		_air_tank.global_transform = Transform3D(Basis.IDENTITY, at)
		_air_tank.health = 1.0e6
		_air_tank.ai = true
		_air_t = -3.0
		return
	if not is_instance_valid(_air_heli):
		_air_heli = AIHeli.new()
		_air_heli.setup("ah64")
		_air_heli.team = 0
		world.add_child(_air_heli)
		_air_heli.freeze = true
		_air_heli.set_physics_process(false)
		_air_hp0 = _air_heli.health
		_air_t = 0.0
		_air_shots = 0
		_air_coax = 0
		_air_locked = 0.0
		_place_air(0.0)
		return
	_air_t += delta
	_place_air(_air_t)
	var t: Tank = _air_tank
	t.health = 1.0e6
	if t._gun_cd > _air_cd_was + 0.01:
		_air_shots += 1
	if t._coax_cd > _air_coax_was + 0.01:
		_air_coax += 1
	_air_cd_was = t._gun_cd
	_air_coax_was = t._coax_cd
	if t._ai_target == _air_heli:
		_air_locked += delta
	if _air_t > 20.0 or (is_instance_valid(_air_heli) and _air_heli.health <= 0.0):
		var c2: Array = AIR_CASES[_air_case]
		var el: float = rad_to_deg(atan2(float(c2[1]), float(c2[0])))
		print("[tankair] %s vs helicopter %4.0f m out, %3.0f m up (%2.0f deg), crossing %2.0f m/s: on it %4.1f of %4.1f s, %d rounds, %d coax bursts, %.0f damage" % [
			t.display_name(), float(c2[0]), float(c2[1]), el, float(c2[2]), _air_locked, _air_t,
			_air_shots, _air_coax, _air_hp0 - (_air_heli.health if is_instance_valid(_air_heli) else 0.0)])
		if is_instance_valid(_air_heli):
			_air_heli.queue_free()
		_air_heli = null
		_air_case += 1
		if _air_case >= AIR_CASES.size():
			_air_test = false
			print("[tankair] RESULT: done")
			world.get_tree().quit()

func _place_air(t: float) -> void:
	if not is_instance_valid(_air_heli) or not is_instance_valid(_air_tank):
		return
	var c: Array = AIR_CASES[_air_case]
	var base: Vector3 = _air_tank.global_position
	var p := base + Vector3(0.0, float(c[1]), -float(c[0]))
	p.x += float(c[2]) * (t - 10.0)
	_air_heli.global_transform = Transform3D(Basis.IDENTITY, p)
	_air_heli.linear_velocity = Vector3(float(c[2]), 0.0, 0.0)
#endregion

#region --tankdrive
var _tank_test := false
var _tank_t := 0.0

func tick_tank(delta: float) -> void:
	_tick_ram(delta)
	_tick_air(delta)
	if _tank_test:
		if world.tank == null and not world.parked.is_empty():
			for v in world.get_tree().get_nodes_in_group("vehicles"):
				world.crew.enter_tank(v as Tank)
				world.tank.scripted = true
				break
		elif is_instance_valid(world.tank):
			_tank_t += delta
			world.tank.in_throttle = 1.0
			world.tank.in_steer = 0.6 if _tank_t > 8.0 else 0.0
			world.tank.in_brake = _tank_t > 16.0
			if world.tank.is_indirect() and fmod(_tank_t, 6.0) < delta and _tank_t > 3.0:
				world.tank.aim_pitch = deg_to_rad(-6.0)
				world.tank.fire_main(world)
				if not world.tank.last_solution.is_empty():
					print("[arty] %s: %.1f km at %.0f deg, %d rounds, tof %.0f s" % [
						world.tank.display_name(), float(world.tank.last_solution["range"]) * 0.001,
						float(world.tank.last_solution["elev"]), int(world.tank.last_solution["salvo"]),
						float(world.tank.last_solution["tof"])])
			if fmod(_tank_t, 2.0) < delta:
				var b := world.tank.global_transform.basis
				print("[tank] t=%4.1f speed=%5.1f km/h  pitch=%+5.1f roll=%+5.1f  y=%6.1f agl=%+5.2f" % [
					_tank_t, world.tank.speed * 3.6,
					rad_to_deg(asin(clampf(-b.z.y, -1, 1))), rad_to_deg(atan2(-b.x.y, b.y.y)),
					world.tank.global_position.y,
					world.tank.global_position.y - Sim.height_at(world.tank.global_position.x, world.tank.global_position.z)])
#endregion
