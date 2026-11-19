class_name DevOptions
extends TestSuite
## Developer launch options: screenshots, scripted flights, camera placement,
## logging and boot switches. Not tests as such, but driven the same way.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a.begins_with("--shot="):
		world._shot = a.substr(7)
	elif a.begins_with("--auto="):
		world._auto = a.substr(7)
	elif a.begins_with("--dump="):
		world._dump = int(a.substr(7))
	elif a.begins_with("--view="):
		world._view = a.substr(7)
	elif a == "--nocockpit":
		world._nocockpit = true
	elif a == "--openbay":
		world._openbay = true
	elif a.begins_with("--dist="):
		world._dist = float(a.substr(7))
	elif a.begins_with("--frames="):
		world._shot_at = int(a.substr(9))
	elif a == "--holdgun":
		_hold_gun = true
	elif a == "--zoom":
		_shot_zoom = true
	elif a == "--podmark":
		_shot_podmark = true
	elif a == "--objshot":
		_shot_obj = true
	elif a.begins_with("--lookfrom="):
		var lv := a.substr(11).split(",")
		if lv.size() == 6:
			_look_from = Vector3(float(lv[0]), float(lv[1]), float(lv[2]))
			_look_at = Vector3(float(lv[3]), float(lv[4]), float(lv[5]))
	elif a.begins_with("--at="):
		var av := a.substr(5).split(",")
		if av.size() == 3:
			world._at = Vector3(float(av[0]), float(av[1]), float(av[2]))
	elif a == "--noboard":
		world._skip_board = true
	elif a == "--cqbquiet":
		CqbMatch.quiet = true
		CqbMatch.plain = true
	elif a.begins_with("--cqbview="):
		# with --preset=cqb --shot=: fp, ads, tp, tpads, reload, dmr, pistol, run
		world.street_fight._cqb_view = a.substr(10)
	elif a.begins_with("--gtest="):
		world.veil.debug_strain = float(a.substr(8))
	elif a.begins_with("--runfor="):
		_run_for = float(a.substr(9))
	elif a == "--netlog":
		_net_log = true
		world.net.verbose = true
	elif a.begins_with("--bankdeg="):
		world._bank_deg = float(a.substr(10))
	elif a.begins_with("--dashalt="):
		world._dash_alt = float(a.substr(10))
	elif a.begins_with("--nukeshot="):
		for v in a.substr(11).split(","):
			_nuke_shot.append(float(v))
	elif a.begins_with("--roadprobe="):
		var rp := a.substr(12).split(",")
		_road_probe = Vector2(float(rp[0]), float(rp[1]))
	elif a == "--autodiag":
		world._auto_diag = true
	elif a == "--nobake" or a == "--clearbake" or a == "--boottime" \
			or a == "--debugroads":
		pass                       # already handled, before the bake loaded
	elif a == "--fx":
		_fx = true
	else:
		return false
	return true


#region --shot=

func tick_shot() -> void:
	if world._shot != "":
		world._shot_frames -= 1
		if world._shot_frames <= 0:
			harness._take_shot()
#endregion


#region --auto=
#endregion


#region --dump=
var _dump_t := 0.0

func tick_dump(delta: float) -> void:
	if world._dump > 0 and is_instance_valid(world.player):
		_dump_t += delta
		if _dump_t > float(world._dump) * 0.008333:
			_dump_t = 0.0
			var b := world.player.global_transform.basis
			var bank := rad_to_deg(atan2(-b.x.y, b.y.y))
			var pit := rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0)))
			var hdg := fmod(rad_to_deg(atan2(-b.z.x, b.z.z)) + 360.0, 360.0)
			var av := world.player.angular_velocity
			print("t=%5.1f kias=%5.1f alt=%7.1f agl=%7.1f vs=%+6.1f aoa=%+5.1f beta=%+5.1f g=%+4.1f bank=%+6.1f pitch=%+5.1f hdg=%5.1f p=%+5.2f q=%+5.2f r=%+5.2f thr=%.2f pwr=%.2f fuel=%6.0f gnd=%s x=%7.1f z=%8.1f" % [
				Time.get_ticks_msec() * 0.001, world.player.ias * 1.94384, world.player.global_position.y,
				world.player.agl, world.player.vspeed, rad_to_deg(world.player.aoa), rad_to_deg(world.player.beta), world.player.g_load,
				bank, pit, hdg, av.dot(-b.z), av.dot(b.x), av.dot(b.y),
				world.player.throttle, world.player.power, world.player.fuel, str(world.player.on_ground),
				world.player.global_position.x, world.player.global_position.z])
#endregion


#region --view=
#endregion


#region --nocockpit
#endregion


#region --openbay
#endregion


#region --dist=
#endregion


#region --frames=
#endregion


#region --holdgun
## Hold the jet's trigger down, for a picture of what its gun puts out.
var _hold_gun := false

func tick_hold_gun() -> void:
	if _hold_gun and world.running and is_instance_valid(world.player) and not world.on_foot:
		world.player.fire_gun(world)
#endregion


#region --zoom
## For pictures of the main view: hold the zoom, and put the pod on a point four
## kilometres ahead and close its page, so the mark it leaves can be seen.
var _shot_zoom := false

func tick_shot_zoom() -> void:
	if _shot_zoom and world.running and is_instance_valid(world.cam):
		world.cam.zoom = true
#endregion


#region --podmark
var _shot_podmark := false
var _shot_mark_t := 0.0

func tick_shot_podmark(delta: float) -> void:
	if _shot_podmark and world.running and is_instance_valid(world.player):
		_shot_mark_t += delta
		if _shot_mark_t > 1.5:
			_shot_podmark = false
			world.pod.platform = world.player
			if not world.pod.active:
				world.pod.toggle()
			var hh: float = world.player.global_position.y - Sim.height_at(
				world.player.global_position.x, world.player.global_position.z)
			world.pod.yaw = 0.25
			world.pod.pitch = -atan2(hh, 4000.0)
			world.pod._process(0.016)
			world.pod.designate()
			world.pod.toggle()
#endregion


#region --objshot
## and an objective six kilometres out, for a picture of how it shows in flight
var _shot_obj := false

func tick_shot_obj() -> void:
	if _shot_obj and world.running and is_instance_valid(world.player):
		_shot_obj = false
		var fo: Vector3 = -world.player.global_transform.basis.z
		var lo: Vector3 = -world.player.global_transform.basis.x
		var op: Vector3 = world.player.global_position + fo * 5500.0 + lo * 2200.0
		Sim.set_objective(Vector3(op.x, Sim.height_at(op.x, op.z), op.z))
#endregion


#region --lookfrom=
## A fixed eye for screenshots: where it stands and what it looks at, in chart
## x and z and world y. The aeroplane cameras all chase something moving, so a
## picture of one piece of ground -- an abutment, a coastline -- had to be got
## by flying past it at the right moment.
var _look_from := Vector3.INF
var _look_at := Vector3.INF
var _look_cam: Camera3D = null

func tick_look_from() -> void:
	if _look_from != Vector3.INF and world.running:
		if _look_cam == null:
			_look_cam = Camera3D.new()
			_look_cam.fov = 60.0
			world.add_child(_look_cam)
			_look_cam.global_position = _look_from
			_look_cam.look_at(_look_at, Vector3.UP)
			if is_instance_valid(world.hud):
				world.hud.visible = false
		if not _look_cam.current:
			_look_cam.current = true
#endregion


#region --at=
#endregion


#region --noboard
#endregion


#region --cqbquiet
#endregion


#region --cqbview=

func tick_cqb_view() -> void:
	if world.street_fight._cqb_view != "" and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		# pose the player for a photograph
		var cv := world.street_fight._cqb_view
		world.walker.third = cv.begins_with("tp")
		world.walker.hold_ads = cv in ["ads", "tpads", "dmr"]
		var want_kit: int = Firearm.index_of("dmr" if cv == "dmr" else ("pistol" if cv == "pistol"
			else ("shotgun" if cv == "shotgun" else "carbine")))
		if world.walker.kit_idx != want_kit:
			if cv != "fp" and cv != "tp" and cv != "ads" and cv != "tpads" and cv != "reload":
				world.walker.slots[world.walker.slot] = want_kit
				world.walker.rearm()
			world.walker._take_up(want_kit, false)
		if cv == "reload" and world.walker.reloading <= 0.0:
			world.walker.ammo = 3
			world.walker._begin_reload(world.walker.gun_spec())
		if cv == "reload" and world.walker.reloading < world.walker._reload_span * 0.55:
			world.walker.reloading = world.walker._reload_span * 0.55
		if cv == "look":
			world.walker.pitch = -0.9
		if cv.ends_with("chute") and not world.walker.chute:
			world.walker.global_position += Vector3(0, 150.0, 0)
			world.walker.on_floor = false
			world.walker.set_chute(true)
			world.walker.third = true
		if cv.begins_with("prone"):
			world.walker.prone = true
			world.walker.pitch = 0.0
			if cv == "pronetp":
				world.walker.third = true
#endregion


#region --gtest=
#endregion


#region --runfor=
var _run_for := 0.0
var _run_t := 0.0

func tick_run_for() -> void:
	if _run_for > 0.0:
		# wall clock, not sim time: --fixed-fps decouples the two, and net
		# tests need two processes to overlap for a real number of seconds
		_run_t = Time.get_ticks_msec() * 0.001
		if _run_t >= _run_for:
			world.get_tree().quit()
#endregion


#region --netlog
var _net_log := false
var _net_t := 0.0

func tick_net_log(delta: float) -> void:
	if _net_log and world.net and world.net.active:
		_net_t += delta
		if _net_t > 2.0:
			_net_t = 0.0
			var names: Array = []
			for pid in world.net.ghosts:
				var g = world.net.ghosts[pid]
				if is_instance_valid(g):
					names.append("%d@%s" % [pid, str(g.global_position.round())])
			var ai_n := 0
			var ai_where := ""
			var ai_keys: Array = world.net.ai_ghosts.keys()
			ai_keys.sort()          # a stable sample: dictionary order moves as ghosts die
			for k in ai_keys:
				if is_instance_valid(world.net.ai_ghosts[k]) and world.net.ai_ghosts[k].alive:
					ai_n += 1
					if ai_where == "":
						var gg = world.net.ai_ghosts[k]
						ai_where = "#%d %s v=%.0f" % [k,
							str(gg.global_position.round()),
							(gg.get_meta("net_vel", Vector3.ZERO) as Vector3).length()]
			var me := "-"
			if is_instance_valid(world.player):
				me = str(world.player.global_position.round())
			elif is_instance_valid(world.walker):
				me = str(world.walker.position.round())
			names.append("me" + me)
			if not world.net.is_host:
				var gn := 0
				var gd := ""
				for z in world.get_tree().get_nodes_in_group("zones"):
					for a in z.assets:
						if is_instance_valid(a) and a.has_meta("gnd_pos"):
							gn += 1
							if gd == "":
								gd = "%.2f m" % a.global_position.distance_to(
									a.get_meta("gnd_pos") as Vector3)
				names.append("garrison=%d lag=%s" % [gn, gd])
			if is_instance_valid(world.player):
				var tn := "none"
				if world.player.target != null and is_instance_valid(world.player.target):
					tn = "%s@%.0fkm" % [str(world.player.target.name).left(12),
						world.player.global_position.distance_to(world.player.target.global_position) * 0.001]
				var load_s := ""
				for wt in world.player.weapon_types:
					load_s += "%s:%d " % [wt, world.player.count_remaining(wt)]
				names.append("tgt=" + tn + " w=" + world.player.current_weapon()
					+ " jet=" + str(world.player.spec["name"]) + " [" + load_s.strip_edges() + "]")
			if not world.net.is_host:
				var wire: Vector2 = world.net.wire_rate()
				print("[net] %s  id=%d  roster=%d  ghosts=%d  ai=%d %s  tx=%d rx=%d (%.1f/%.1f kB/s, rtt %.0f ms)  %s" % [
					world.net.status, world.net.my_id, world.net.roster.size(), world.net.ghosts.size(),
					ai_n, ai_where, world.net.tx, world.net.rx, wire.x / 1024.0, wire.y / 1024.0, world.net.round_trip_ms(),
					", ".join(PackedStringArray(names))])
			else:
				var host_ai := 0
				var lowest := 1e9
				for n in world.get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.is_alive():
						host_ai += 1
						lowest = minf(lowest, n.global_position.y)
				var worst: Node3D = null
				for n in world.get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.global_position.y == lowest:
						worst = n
				if worst != null:
					names.append("lowest bandit y=%.0f agl=%.0f alive=%s wrecked=%s frozen=%s sleep=%s" % [
						lowest, worst.get("agl"), str(worst.get("alive")),
						str(worst.get("wrecked")), str(worst.get("freeze")),
						str(worst.get("sleeping"))])
				var wire2: Vector2 = world.net.wire_rate()
				print("[net] %s  id=%d  roster=%d  ghosts=%d  ai(sim)=%d  tx=%d rx=%d (%.1f/%.1f kB/s, rtt %.0f ms)  %s" % [
					world.net.status, world.net.my_id, world.net.roster.size(), world.net.ghosts.size(),
					host_ai, world.net.tx, world.net.rx, wire2.x / 1024.0, wire2.y / 1024.0, world.net.round_trip_ms(),
					", ".join(PackedStringArray(names))])
#endregion


#region --bankdeg=
#endregion


#region --dashalt=
#endregion


#region --nukeshot=
## A mushroom cloud of a given age, set off in front of a --lookfrom camera so
## its shape can be photographed: --nukeshot=X,Z,LETHAL,AGE with --shot.
var _nuke_shot := PackedFloat32Array()
var _nuke_shot_done := false

func tick_nuke_shot() -> void:
	if _nuke_shot.size() == 4 and not _nuke_shot_done and world.running:
		_nuke_shot_done = true
		_set_off_nuke_shot()

func _set_off_nuke_shot() -> void:
	var at := Vector3(_nuke_shot[0], 0.0, _nuke_shot[1])
	at.y = Sim.height_at(at.x, at.z)
	Effects.nuke(world, at, _nuke_shot[2])
	await world.get_tree().process_frame
	for n in world.get_children():
		if n.get_class() == "Node3D" and "lethal" in n and "_t" in n:
			n.set("_t", _nuke_shot[3])
	print("[nukeshot] %.0f m lethal radius at %s, aged %.0f s" % [
		_nuke_shot[2], str(at.round()), _nuke_shot[3]])
#endregion


#region --roadprobe=
## The road at one spot, a metre at a time: the finished ground against the
## design surface along every leg that passes within 40 m, with the weights
## and the drop, so a gradient the test flags can be put down to the design
## or to how the design was laid into the ground. --roadprobe=X,Z
var _road_probe := Vector2.INF

func tick_road_probe() -> void:
	if _road_probe != Vector2.INF:
		_run_road_probe()
		_road_probe = Vector2.INF

func _run_road_probe() -> void:
	Sim.resurvey_roads()
	var at := _road_probe
	print("[probe] limits: grade %.3f, max %.3f, hairpin %.3f" % [
		Sim.road_grade_max, Sim.road_grade_max, Sim.road_grade_hairpin])
	for r in Sim.ROADS:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var seg_d: float = a.distance_to(b)
		var t: float = clampf((at - a).dot(b - a) / maxf(seg_d * seg_d, 1e-6), 0.0, 1.0)
		if a.lerp(b, t).distance_to(at) > 40.0:
			continue
		print("[probe] leg %s -> %s, %.1f m, heading %.0f" % [str(a.round()), str(b.round()),
			seg_d, rad_to_deg(atan2(b.x - a.x, -(b.y - a.y)))])
		var prev_g := INF
		var prev_d := INF
		var steps: int = int(seg_d)
		for k in steps + 1:
			var q: Vector2 = a.lerp(b, float(k) / maxf(float(steps), 1.0))
			var g: float = Sim.survey_height_at(q.x, q.y)
			var made: Vector3 = Sim.road_surface(q.x, q.y)
			var dsg: float = made.x + Sim.planet_drop(q.x, q.y)
			var line := "[probe]   %5.1f m  ground %8.3f" % [float(k) * seg_d / maxf(float(steps), 1.0), g]
			if prev_g != INF:
				line += " (%+5.1f%%)" % ((g - prev_g) / (seg_d / maxf(float(steps), 1.0)) * 100.0)
			line += "  design %8.3f" % dsg
			if prev_d != INF:
				line += " (%+5.1f%%)" % ((dsg - prev_d) / (seg_d / maxf(float(steps), 1.0)) * 100.0)
			line += "  off %+.3f  w %.2f  pad %.2f" % [g - dsg, made.y, Sim.pad_weight(q.x, q.y)]
			print(line)
			prev_g = g
			prev_d = dsg
	world.get_tree().quit()
#endregion


#region --autodiag
var _auto_diag_t := 0.0
var _auto_diag_n := 0

# What the autoland is actually commanding on the way down.
func tick_auto_diag(delta: float) -> void:
	if world._auto_diag and is_instance_valid(world.player):
		_auto_diag_t += delta
		var step := int(_auto_diag_t / 2.0)
		if step > _auto_diag_n:
			_auto_diag_n = step
			var pp := world.player.global_position
			print("[auto] t=%5.1f  x=%+7.1f z=%+8.1f y=%6.1f agl=%5.1f  ias=%5.1f kt  thr=%.2f  vs=%+5.2f  gnd=%s" % [
				_auto_diag_t, pp.x, pp.z, pp.y, world.player.agl, world.player.ias * 1.94384,
				world.player.throttle, world.player.linear_velocity.y, str(world.player.on_ground)])
#endregion


#region --nobake --clearbake --boottime
#endregion


#region --fx
var _fx := false
var _fx_t := 0.0

func tick_fx_2(delta: float) -> void:
	if _fx and is_instance_valid(world.player) and world.player.alive:
		_fx_t += delta
		world.player.set_bays(true)
		if _fx_t > 0.35:
			_fx_t = 0.0
			world.player.flares = 30
			world.player.chaff = 30
			world.player.dispense_all()
			if world.player.fire_cd <= 0.0 and world.player.count_remaining("aim120") > 0:
				world.player.selected = maxi(world.player.weapon_types.find("aim120"), 0)
				world.player.locked = true
				world.player.fire()
#endregion
