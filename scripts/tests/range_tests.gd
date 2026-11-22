class_name RangeTests
extends TestSuite
## The firing range: shooting it, listening to it, and its camera.
##
## Command-line tests, split out of `infantry_tests.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--rangetest":
		_range_test = true
	elif a == "--rangelisten":
		_range_listen = true
	elif a == "--rangeafter":
		# come to the range from a busy mission, the way a player does
		_range_after = true
	elif a.begins_with("--rangecam="):
		_range_cam = a.substr(11)
	else:
		return false
	return true


#region --rangetest
## Ten aimed rounds at every board on the range, and how many it counted.
## --preset=range:f16 --rangetest
var _range_test := false

func tick_range() -> void:
	if _range_test and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		_range_test = false
		_run_range_test()

func _run_range_test() -> void:
	for i in 120:
		await world.get_tree().physics_frame
	# the readout's numbers against the round's own path, for one shot
	var gd: Dictionary = Firearm.spec("fifty")
	var e0: Vector3 = world.walker.global_position + Vector3(0, 1.5, 0)
	var dd: Vector3 = (world.firing_range.targets[5].global_position + Vector3(0, 1.25, 0) - e0).normalized()
	Engine.time_scale = 0.05
	var real0 := Time.get_ticks_msec()
	Firearm.fire(world, world.walker, 0, gd, e0, dd, 0.0)
	var rr0: Dictionary = world.firing_range.rounds[world.firing_range.rounds.size() - 1]
	var ticks := 0
	while float(rr0["t"]) < 0.2:
		await world.get_tree().physics_frame
		ticks += 1
	Engine.time_scale = 1.0
	print("[range] slow motion: 0.2 s of flight took %d physics ticks and %.1f s of real time" % [
		ticks, float(Time.get_ticks_msec() - real0) * 0.001])
	var p0: Vector3 = rr0["muzzle"]
	var pn: Vector3 = rr0["pos"]
	var along0: float = (pn - p0).dot(dd)
	var side0: Vector3 = (pn - p0) - dd * along0
	print("[range] one .50 round, %.0f m out: off the line it was fired along by %.3f m (%s); fired from %s, recorded from %s; dir0 vs dd %.4f deg" % [
		along0, side0.length(), str(side0), str(e0), str(p0), rad_to_deg((rr0["dir0"] as Vector3).angle_to(dd))])
	var g: Dictionary = Firearm.spec("dmr")
	var eye: Vector3 = world.walker.global_position + Vector3(0, 1.5, 0)
	var bad := 0
	for t in world.firing_range.targets:
		var rt: FiringRange.RangeTarget = t
		var aim_at: Vector3 = rt.global_position + Vector3(0, rt.cy, 0)
		for k in 10:
			# held up for the drop, the way the walker lays a shot
			var d: Vector3 = world.walker._lay(eye, aim_at, float(g["muzzle"]), 9.81, false, Firearm.drag_of(g))
			Firearm.fire(world, world.walker, 0, g, eye, d, 0.0)
			for f in 3:
				await world.get_tree().physics_frame
		# until every round is down: physics here is 120 a second, so "sixty
		# frames" was half a second and the long rounds were still flying
		for f in 600:
			await world.get_tree().physics_frame
			var flying := false
			for rr in world.firing_range.rounds:
				if bool(rr["live"]):
					flying = true
					break
			if not flying:
				break
		if not world.firing_range.rounds.is_empty():
			var lr: Dictionary = world.firing_range.rounds[world.firing_range.rounds.size() - 1]
			var lp: Vector3 = lr["pos"]
			print("[range]     last round: %.2f s, %.0f m flown, ended %.1f m short of the board, %+.2f m vs its middle, %.0f m/s; %s" % [
				float(lr["t"]), float(lr["flown"]), eye.distance_to(aim_at) - eye.distance_to(lp),
				lp.y - aim_at.y, (lr["vel"] as Vector3).length(), String(lr["hit"])])
		var los: float = Firearm.sight_range(eye, (aim_at - eye).normalized(), eye.distance_to(aim_at) + 5.0)
		print("[range] %3d m board: %d of 10 counted (line of sight clear to %.0f of %.0f m; ground at board %+.1f m vs line)" % [
			int(rt.distance), rt.hits, los, eye.distance_to(aim_at),
			Sim.height_at(rt.global_position.x, rt.global_position.z) - rt.global_position.y])
		if rt.hits < 8:
			bad += 1
	print("[range] RESULT: %s" % ("ok" if bad == 0 else "FAILED — %d boards missed rounds" % bad))
	world.get_tree().quit()
#endregion


#region --rangelisten --rangeafter
## Forty seconds on the range doing nothing, and every round and every gunshot
## that happens anyway, with who or where. --preset=range:f16 --rangelisten
var _range_listen := false
var _range_after := false

func tick_range_listen() -> void:
	if _range_listen and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		_range_listen = false
		_run_range_listen()

func _run_range_listen() -> void:
	if _range_after:
		_range_after = false
		world._start("f16", "sandbox")
		for i in 120 * 15:
			await world.get_tree().physics_frame
		world._start("f16", "range")
		for i in 240:
			await world.get_tree().physics_frame
	var heard: Dictionary = {}
	var shots: Dictionary = {}
	var me: Walker = world.walker
	if not is_instance_valid(me):
		print("[listen] no walker")
		world.get_tree().quit()
		return
	var keep_log: Callable = Effects.round_log
	Effects.round_log = func(shot: Node3D, shooter: Node) -> void:
		var who: String = "nobody" if shooter == null or not is_instance_valid(shooter) \
			else "%s (%s)" % [shooter.name, shooter.get_class()]
		if shooter == me:
			who = "the player"
		var k: String = "%s: %s" % [who, shot.get_script().get_global_name() if shot.get_script() else shot.get_class()]
		shots[k] = int(shots.get(k, 0)) + 1
		if keep_log.is_valid():
			keep_log.call(shot, shooter)
	Sfx.listen = func(id: String, pos: Vector3) -> void:
		var d: float = 0.0 if pos == Vector3.INF else pos.distance_to(me.global_position)
		var k: String = "%s, %s" % [id, "within 100 m" if d < 100.0 else ("%d km off" % int(d / 1000.0) if d > 1000.0 else "%d m off" % int(d))]
		heard[k] = int(heard.get(k, 0)) + 1
	var playing: Dictionary = {}
	for i in 120 * 40:
		await world.get_tree().physics_frame
		# hold the trigger for two seconds in the middle, as he would
		if i == 120 * 10:
			world.weapon_cam_on = true
			Input.action_press(&"fire")
		if i == 120 * 12:
			Input.action_release(&"fire")
		if i % 30 != 0:
			continue
		# anything at all making a noise, however it was started
		for n in world.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
			var ap := n as AudioStreamPlayer3D
			if ap.playing and ap.stream != null:
				var nm: String = ap.stream.resource_path.get_file() if ap.stream.resource_path != "" else String(ap.name)
				var k2: String = "3D %s under %s, %d m off" % [nm, ap.get_parent().name,
					int(ap.global_position.distance_to(me.global_position))]
				playing[k2] = int(playing.get(k2, 0)) + 1
		for n in world.get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
			var ap2 := n as AudioStreamPlayer
			if ap2.playing and ap2.stream != null and ap2.volume_db > -50.0:
				var k3: String = "flat %s under %s at %.0f dB" % [ap2.name, ap2.get_parent().name, ap2.volume_db]
				playing[k3] = int(playing.get(k3, 0)) + 1
	print("[listen] players found playing (sampled 4x a second):")
	for k in playing:
		print("[listen]   %4d  %s" % [int(playing[k]), k])
	Sfx.listen = Callable()
	Effects.round_log = keep_log
	print("[listen] rounds fired in 40 s:")
	for k in shots:
		print("[listen]   %4d  %s" % [int(shots[k]), k])
	print("[listen] sounds played in 40 s:")
	for k in heard:
		print("[listen]   %4d  %s" % [int(heard[k]), k])
	world.get_tree().quit()
#endregion


#region --rangecam=
## The bullet camera on the range, photographed: riding a round in slow motion,
## and the traces after. --preset=range:f16 --rangecam=DIR
var _range_cam := ""

func tick_range_cam() -> void:
	if _range_cam != "" and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		var rc := _range_cam
		_range_cam = ""
		_run_range_cam(rc)

func _run_range_cam(arg: String) -> void:
	var parts := arg.split(",")
	var dir: String = parts[0]
	var kit: String = parts[1] if parts.size() > 1 else "fifty"
	for i in 240:
		await world.get_tree().physics_frame
	world.weapon_cam_on = true
	var rt: FiringRange.RangeTarget = world.firing_range.targets[5]
	var g: Dictionary = Firearm.spec(kit)
	world.walker._take_up(Firearm.index_of(kit), false)
	var eye: Vector3 = world.walker.cam.global_position
	var aim_at: Vector3 = rt.global_position + Vector3(0, rt.cy, 0)
	var d: Vector3 = world.walker._lay(eye, aim_at, float(g["muzzle"]), 9.81, false, Firearm.drag_of(g))
	var t0 := Time.get_ticks_msec()
	Firearm.fire(world, world.walker, 0, g, eye + d * 1.2, d, 0.0)
	var shot_mid := false
	while Time.get_ticks_msec() - t0 < 20000:
		await world.get_tree().process_frame
		var real: float = float(Time.get_ticks_msec() - t0) * 0.001
		if not shot_mid and real > 1.5:
			shot_mid = true
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png("%s/range_chase_%s.png" % [dir, kit])
			var ridden: Variant = world.cam.get("weapon_cam")
			if ridden != null and is_instance_valid(ridden):
				var rn: Node3D = ridden
				print("[rangecam] riding %s: cal %s, ride scale %.4f, camera %.3f m off it, near %.3f, round model %s" % [
					kit, str((rn as Effects.Tracer).cal.get("name", "none")), float(rn.call("ride_scale")),
					world.cam.global_position.distance_to(rn.get_global_transform_interpolated().origin), world.cam.near,
					str((rn as Effects.Tracer)._round != null and (rn as Effects.Tracer)._round.visible)])
			print("[rangecam] mid-flight: time scale %.3f, physics %d a second, riding %s" % [
				Engine.time_scale, Engine.physics_ticks_per_second, str(world.cam.riding())])
			print("[rangecam] panel:\n%s" % world.firing_range._panel.text)
		if shot_mid and not world.cam.riding() and Engine.time_scale == 1.0:
			break
	print("[rangecam] back to full speed after %.1f s real; time scale %.2f" % [
		float(Time.get_ticks_msec() - t0) * 0.001, Engine.time_scale])
	for i in 30:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("%s/range_traces.png" % dir)
	print("[rangecam] panel after:\n%s" % world.firing_range._panel.text)
	world.get_tree().quit()
#endregion
