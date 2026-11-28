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
	elif a == "--spikeshot":
		# the minimap up and the two nearest hostiles tracking you, for --shot
		_spike_shot = true
	elif a.begins_with("--sideview="):
		# a camera off the player's left side at wheel height, DIST metres
		# out: for photographing how an aeroplane sits on its gear
		_side_dist = float(a.substr(11))
	elif a == "--nocockpit":
		world._nocockpit = true
	elif a == "--openbay":
		world._openbay = true
	elif a.begins_with("--dist="):
		world._dist = float(a.substr(7))
	elif a.begins_with("--frames="):
		world.shot_at = int(a.substr(9))
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
	elif a.begins_with("--satview="):
		# --satview=ALT[,TILT_DEG[,PAN_KM]]: up into the satellite view, for a --shot
		var sv := a.substr(10).split(",")
		_sat_alt = float(sv[0])
		_sat_tilt = deg_to_rad(float(sv[1])) if sv.size() > 1 else 0.0
		_sat_pan = float(sv[2]) * 1000.0 if sv.size() > 2 else 0.0
		SatView.clear_air = sv.size() > 3 and sv[3] == "clear"
	elif a.begins_with("--menuflow="):
		# --menuflow=MISSION[,TOWN] (windowed, no preset, with --intro
		# --introshots=DIR): the hangar's satellite view, the mission picked,
		# photographed once it has gone there, and launched
		var mf := a.substr(11).split(",")
		_mf_mission = mf[0]
		_mf_town = int(mf[1]) if mf.size() > 1 else -1
	elif a.begins_with("--handoff="):
		# --handoff=SECS[,click]: the same, skipping the way down part way with
		# a key (W) or a click, as a player taking over would
		var hv := a.substr(10).split(",")
		_ho_skip = float(hv[0])
		_ho_click = hv.size() > 1 and hv[1] == "click"
		_handoff = true
		_intro_prof = true
	elif a == "--handoff":
		# with --intro: each drawn frame either side of the end of the way
		# down -- which camera, in what mode, how far from the aircraft
		_handoff = true
		_intro_prof = true
	elif a == "--introprof":
		# with --intro: every slow frame of the way down, and what it was
		_intro_prof = true
		Sim.profiling = true
	elif a.begins_with("--introshots="):
		# with --intro, windowed: a picture every half second of the way down
		# out of orbit into the match, into DIR
		_intro_dir = a.substr(13)
	elif a.begins_with("--satpan="):
		# with --satview: pan north this many km a second, to measure a pan
		_sat_pan_rate = float(a.substr(9)) * 1000.0
	elif a.begins_with("--at="):
		var av := a.substr(5).split(",")
		if av.size() == 3:
			world.start_at = Vector3(float(av[0]), float(av[1]), float(av[2]))
	elif a.begins_with("--smallarms"):
		# --smallarms or --smallarms=KIT: magazines of KIT into a parked aircraft
		_sa_kit = a.substr(12) if a.begins_with("--smallarms=") else "carbine"
		# KIT,tail / KIT,main / KIT,body: at the player's helicopter instead
		if _sa_kit.contains(","):
			_sa_aim = _sa_kit.get_slice(",", 1)
			_sa_kit = _sa_kit.get_slice(",", 0)
	elif a.begins_with("--groundtest="):
		_gt_mode = a.substr(13)
	elif a.begins_with("--wingstrike"):
		# --wingstrike (a tower off the right wing) or --wingstrike=0 (dead ahead)
		_ws_off = float(a.substr(13)) if a.begins_with("--wingstrike=") else 12.0
		_ws_on = true
	elif a == "--noboard":
		world.skip_board = true
	elif a == "--cqbquiet":
		CqbMatch.quiet = true
		CqbMatch.plain = true
	elif a.begins_with("--cqbview="):
		# with --preset=cqb --shot=: fp, ads, adsup, adsdown, ads_<kit id>, look,
		# tp, tpads, reload, dmr, pistol, run
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
	elif a == "--soundlog":
		_sound_log = true
	elif a == "--soundquit":
		_sl_quit = true
	elif a == "--ramptest":
		_ramp_test = true
	elif a == "--uexit":
		_uexit = true
	elif a == "--midairtest":
		_midair_test = true
	elif a == "--soundtrace":
		_trace_guns = true
		_sound_log = true
	elif a == "--phantomtest":
		_phantom = true
		_sound_log = true
	elif a.begins_with("--soundswitch="):
		_sound_switch = a.substr(14)
		_sound_log = true
		_sl_quit = true
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
		world.shot_frames -= 1
		if world.shot_frames <= 0:
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

var _spike_shot := false

func tick_spike_shot() -> void:
	if not _spike_shot or not world.running or not is_instance_valid(world.player):
		return
	Sim.panel_left = 3
	var me: Aircraft = world.player
	var near: Array = []
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if n is Node3D and "team" in n and int(n.team) != me.team and n != me:
			near.append(n)
	near.sort_custom(func(a, b): return (a as Node3D).global_position.distance_to(me.global_position) \
		< (b as Node3D).global_position.distance_to(me.global_position))
	for n2 in near.slice(0, 2):
		me.spike(n2)

var _side_dist := 0.0
var _side_cam: Camera3D = null

func tick_side_view() -> void:
	if _side_dist <= 0.0 or not world.running or not is_instance_valid(world.player):
		return
	if _side_cam == null:
		_side_cam = Camera3D.new()
		_side_cam.fov = 40.0
		world.add_child(_side_cam)
		if is_instance_valid(world.hud):
			world.hud.visible = false
	var p: Node3D = world.player
	var b: Basis = p.global_transform.basis
	var ground: float = Sim.height_at(p.global_position.x, p.global_position.z)
	var eye: Vector3 = p.global_position - b.x * _side_dist
	eye.y = ground + 1.0
	_side_cam.global_position = eye
	_side_cam.look_at(Vector3(p.global_position.x, ground + 1.5, p.global_position.z), Vector3.UP)
	_side_cam.current = true

var _sat_alt := -1.0
var _sat_tilt := 0.0
var _sat_pan := 0.0
var _sat_pan_rate := 0.0

var _intro_dir := ""
var _mf_mission := ""
var _mf_town := -1
var _mf_t := 0.0
var _mf_step := 0
var _mf_worst := 0.0
var _mf_frames := 0

func tick_menu_flow(delta: float) -> void:
	if _mf_mission == "" or world.booting or world.running:
		return
	_mf_t += delta
	if _mf_t > 0.5:
		_mf_worst = maxf(_mf_worst, delta)
		_mf_frames += 1
	var shots: String = _intro_dir if _intro_dir != "" else "user://menuflow"
	if _mf_step == 0 and _mf_t > 2.5:
		_mf_step = 1
		DirAccess.make_dir_recursive_absolute(shots)
		world.get_viewport().get_texture().get_image().save_png("%s/menu_0_boot.png" % shots)
		if _mf_town >= 0:
			CqbMatch.town = _mf_town
		world.menu._select_mission(_mf_mission)
		world.controls.menu_refocus()
		print("[menuflow] picked %s, town %d; sat in menu %s" % [_mf_mission, CqbMatch.town,
			str(world.sat_view.in_menu())])
	elif _mf_step == 1 and _mf_t > 9.0:
		_mf_step = 2
		world.get_viewport().get_texture().get_image().save_png("%s/menu_1_focus.png" % shots)
		print("[menuflow] held over it at %.0f km; ground chunks pending %d; menu frames %d, worst %.0f ms" % [
			world.sat_view.view_height() * 0.001, world.terrain.pending_count(), _mf_frames, _mf_worst * 1000.0])
		var la: Array = world.menu.launch_args()
		var t_l := Time.get_ticks_msec()
		if _handoff and not _ip_hooked:
			_ip_hooked = true
			RenderingServer.frame_post_draw.connect(_ip_after_draw)
		world.session.on_launch(String(la[0]), String(la[1]))
		print("[menuflow] launched %s: %d ms in the call" % [str(la), Time.get_ticks_msec() - t_l])
var _intro_t := 0.0
var _intro_n := 0
var _intro_after := -1.0

var _intro_prof := false
var _ip_us := 0
var _ip_slow: Array = []
var _ip_n := 0
var _ip_jerk := 0.0
var _ip_meas := false
var _ip_jerk_at := ""
var _ip_dt0 := 0.016
var _ip_dorm := false
var _ip_win := PackedFloat32Array()
var _ip_rel0 := Vector3.INF
var _ip_rel1 := Vector3.INF

func _tick_intro_prof() -> void:
	if not _intro_prof:
		return
	var sv: SatView = world.sat_view
	var now: int = Time.get_ticks_usec()
	var inn: bool = is_instance_valid(sv) and sv.in_intro()
	if (inn or (_handoff and world.running)) and not _ip_hooked:
		_ip_hooked = true
		RenderingServer.frame_post_draw.connect(_ip_after_draw)
	if inn and _ip_us > 0:
		var dt: float = (now - _ip_us) / 1000.0
		_ip_n += 1
		var vrid: RID = world.get_viewport().get_viewport_rid()
		if not _ip_meas:
			_ip_meas = true
			RenderingServer.viewport_set_measure_render_time(vrid, true)
		var events := PackedStringArray()
		var dorm: bool = world.planet.dormant
		if dorm != _ip_dorm:
			events.append("ground %s" % ("hidden" if dorm else "shown"))
			_ip_dorm = dorm
		var pw: PackedFloat32Array = world.planet._patch_win
		if pw != _ip_win:
			events.append("new orbit picture")
			_ip_win = pw.duplicate()
		var tv: bool = world.terrain.visible
		if dt > 25.0 or not events.is_empty():
			events.append("gpu %.1f cpu %.1f" % [RenderingServer.viewport_get_measured_render_time_gpu(vrid),
				RenderingServer.viewport_get_measured_render_time_cpu(vrid)])
			if dt <= 25.0:
				_ip_slow.append("(%.0f ms at %.0f m: %s, terrain visible %s)" % [dt, sv.view_height(), ", ".join(events), str(tv)])
		if dt > 25.0:
			var parts := PackedStringArray(events)
			for r in Sim.prof_report().slice(0, 12):
				if float(r[1]) > 300.0 and String(r[0]) != "world.total":
					parts.append("%s %.1f" % [String(r[0]), float(r[1]) * 0.001])
			_ip_slow.append("%.0f ms at %.0f m: %s" % [dt, sv.view_height(), ", ".join(parts)])
	Sim.prof_reset()
	_ip_us = now if inn else 0
	if not inn and _ip_n > 0:
		print("[introprof] %d frames, %d over 25 ms; worst jerk against the aircraft below 400 m: %.2f m (%s)" % [
			_ip_n, _ip_slow.size(), _ip_jerk, _ip_jerk_at])
		for l in _ip_slow:
			print("[introprof]   " + String(l))
		_ip_n = 0
		_ip_slow.clear()
		if not _handoff:
			world.get_tree().quit()

var _ip_hooked := false
var _handoff := false
var _ho_after := -1
var _ho_log: Array = []

var _ho_pre := 0
var _ho_skip := -1.0
var _ho_min := INF
var _ho_min_at := ""
var _ho_click := false

func _ho_frame() -> void:
	var sv: SatView = world.sat_view
	var inn: bool = is_instance_valid(sv) and sv.in_intro()
	if _ho_after < 0 and _ho_pre < 4 and not inn:
		_ho_pre += 1
		var c: Camera3D = world.get_viewport().get_camera_3d()
		print("[handoff] launch frame %d: %s%s intro %s" % [_ho_pre, c.name,
			" mode %d" % int((c as ChaseCamera).mode) if c is ChaseCamera else "", str(inn)])
	if inn:
		_ho_after = 0
	elif _ho_after >= 0:
		_ho_after += 1
	if _ho_after < 0 or _ho_after > 8:
		return
	if inn and _ho_skip > 0.0 and sv._intro_t >= _ho_skip:
		_ho_skip = -1.0
		if _ho_click:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			Input.parse_input_event(mb)
		else:
			var k := InputEventKey.new()
			k.physical_keycode = KEY_W
			k.keycode = KEY_W
			k.pressed = true
			Input.parse_input_event(k)
	var cam: Camera3D = world.get_viewport().get_camera_3d()
	var m := ""
	if cam is ChaseCamera:
		m = " mode %d" % int((cam as ChaseCamera).mode)
	var d := -1.0
	if is_instance_valid(world.player) and world.player.is_inside_tree():
		d = cam.global_position.distance_to(world.player.get_global_transform_interpolated().origin)
	if inn and d >= 0.0 and d < _ho_min:
		_ho_min = d
		_ho_min_at = "%.2f s in, %.0f m up" % [sv._intro_t, sv.view_height()]
	if _ho_after == 1:
		print("[handoff] closest to the aircraft on the way down: %.1f m at %s" % [_ho_min, _ho_min_at])
	var l := "%s %s%s far %.0f, %.1f m from the aircraft, fov %.0f%s" % [
		"in" if inn else "after %d" % _ho_after, cam.name, m, cam.far, d, cam.fov,
		", %.2f s in, %.0f m up" % [sv._intro_t, sv.view_height()] if inn else ""]
	_ho_log.append(l)
	if _intro_dir != "" and (not inn or sv._intro_t > sv._intro_len - 0.06):
		DirAccess.make_dir_recursive_absolute(_intro_dir)
		world.get_viewport().get_texture().get_image().save_png("%s/ho_%s.png" % [_intro_dir,
			"a%d" % _ho_after if not inn else "i%.2f" % sv._intro_t])
	if inn:
		_ho_log = _ho_log.slice(-3)
	if _ho_after == 8:
		for x in _ho_log:
			print("[handoff] " + String(x))
		world.get_tree().quit()

## Measured once the frame is drawn, so the view and the aeroplane are both as
## they were drawn: before the view's own update it is a frame behind, and an
## aeroplane at 230 m/s against uneven frames reads as a shake that is not there.
func _ip_after_draw() -> void:
	if _handoff:
		_ho_frame()
		return
	var sv: SatView = world.sat_view
	if not is_instance_valid(sv) or not sv.in_intro() or not is_instance_valid(world.player) \
			or not world.player.is_inside_tree() or world.on_foot:
		return
	var rel: Vector3 = sv.global_position - world.player.get_global_transform_interpolated().origin
	var fdt: float = maxf(world.get_process_delta_time(), 0.001)
	if _ip_rel1 != Vector3.INF and _ip_rel0 != Vector3.INF and sv.view_height() < 400.0:
		# a change of velocity, as metres a frame at sixty frames a second
		var jk: float = ((rel - _ip_rel1) / fdt - (_ip_rel1 - _ip_rel0) / _ip_dt0).length() / 60.0
		if jk > _ip_jerk:
			_ip_jerk = jk
			_ip_jerk_at = "%.0f m up, %.2f s in, frame %.1f ms" % [sv.view_height(), sv._intro_t, fdt * 1000.0]
	_ip_rel0 = _ip_rel1
	_ip_rel1 = rel
	_ip_dt0 = fdt

func _tick_intro_shots() -> void:
	_tick_intro_prof()
	if _intro_dir == "" or not world.running:
		return
	var sv: SatView = world.sat_view
	var dt: float = world.get_process_delta_time()
	if is_instance_valid(sv) and sv.in_intro():
		_intro_t += dt
		if _intro_t >= _intro_n * 0.5:
			DirAccess.make_dir_recursive_absolute(_intro_dir)
			world.get_viewport().get_texture().get_image().save_png("%s/intro_%02d.png" % [_intro_dir, _intro_n])
			print("[intro] %.1f s: %.0f m up, tilt %.2f" % [_intro_t, sv.view_height(), sv.tilt])
			_intro_n += 1
	elif _intro_n > 0:
		_intro_after = maxf(_intro_after, 0.0) + dt
		if _intro_after > 2.0:
			world.get_viewport().get_texture().get_image().save_png("%s/intro_after.png" % _intro_dir)
			print("[intro] done; camera %s, deploy up %s" % [world.get_viewport().get_camera_3d().name,
				str(is_instance_valid(world.deploy_ui) and world.deploy_ui.visible)])
			world.get_tree().quit()

func tick_sat_view() -> void:
	_tick_intro_shots()
	if _sat_pan_rate != 0.0 and is_instance_valid(world.sat_view) and world.sat_view.active():
		world.sat_view.call("_pan", 0.0, _sat_pan_rate * world.get_process_delta_time())
	if _sat_alt <= 0.0 or not world.running:
		return
	if not is_instance_valid(world.sat_view) or not world.sat_view.active():
		world.controls.toggle_sat_view()
		world.sat_view.alt = _sat_alt
		world.sat_view.set("_alt_s", _sat_alt)
		world.sat_view.tilt = _sat_tilt
		if _sat_pan != 0.0:
			world.sat_view.call("_pan", 0.0, _sat_pan)
		_sat_alt = -1.0

func tick_look_from() -> void:
	if _look_from != Vector3.INF and world.running:
		if _look_cam == null:
			# a height below -5000 is a height above the ground there instead:
			# -10000 + metres. For pictures of somewhere whose height is not known.
			if _look_from.y < -5000.0:
				_look_from.y = Sim.height_at(_look_from.x, _look_from.z) + (_look_from.y + 10000.0)
			if _look_at.y < -5000.0:
				_look_at.y = Sim.height_at(_look_at.x, _look_at.z) + (_look_at.y + 10000.0)
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
		world.walker.hold_ads = cv in ["ads", "tpads", "dmr", "adsup", "adsdown"] \
			or cv.begins_with("ads_")
		var want_kit: int = Firearm.index_of("dmr" if cv == "dmr" else ("pistol" if cv == "pistol"
			else ("shotgun" if cv == "shotgun" else "carbine")))
		# ads_<id>: on the sights of any weapon in the kit
		if cv.begins_with("ads_"):
			want_kit = Firearm.index_of(cv.substr(4))
		if world.walker.kit_idx != want_kit:
			if cv != "fp" and cv != "tp" and cv != "ads" and cv != "tpads" and cv != "reload" \
					and cv != "adsup" and cv != "adsdown":
				world.walker.slots[world.walker.slot] = want_kit
				world.walker.rearm()
			world.walker._take_up(want_kit, false)
		if cv == "reload" and world.walker.reloading <= 0.0:
			world.walker.ammo = 3
			world.walker.arms._begin_reload(world.walker.gun_spec())
		if cv == "reload" and world.walker.reloading < world.walker._reload_span * 0.55:
			world.walker.reloading = world.walker._reload_span * 0.55
		if cv == "look" or cv == "adsdown":
			world.walker.pitch = -0.9
		if cv == "adsup":
			world.walker.pitch = 0.9
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
		if (n.get_class() == "Node3D" and "lethal" in n and "_t" in n) or n is Shockwave:
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
	Sim.roads.resurvey_roads()
	var at := _road_probe
	print("[probe] limits: grade %.3f, max %.3f, hairpin %.3f" % [
		Sim.roads.road_grade_max, Sim.roads.road_grade_max, Sim.roads.road_grade_hairpin])
	for r in Sim.roads.ROADS:
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
			var made: Vector3 = Sim.roads.road_surface(q.x, q.y)
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


#region --soundlog
## Every positional sound, by kind, and how far from the ears it was: printed
## every five seconds. With --soundswitch=MODE:VEH the match is changed half
## way through, to hear what the last one leaves playing.
var _sound_log := false
var _sound_switch := ""
var _sl_quit := false
var _sl_t := 0.0
var _sl_hooked := false
var _sl: Dictionary = {}
var _phantom := false
## Every gun sound printed with where it came from: --soundtrace.
var _trace_guns := false
var _ph_step := 0

## Runway start: a bomb off the rails on the runway, then out of the seat.
func _tick_phantom() -> void:
	var p: Aircraft = world.player
	if _ph_step == 0 and _sl_t > 3.0:
		_ph_step = 1
		if world.boarding:
			world.crew.end_boarding()
		for i in p.weapon_types.size():
			if String(WeaponSpec.get_spec(String(p.weapon_types[i])).get("kind", "")) == "bomb":
				p.selected = i
		print("[phantom] releasing %s on the runway: %s" % [p.current_weapon(), p.fire()])
	elif _ph_step == 1 and _sl_t > 20.0:
		_ph_step = 2
		print("[phantom] ejecting")
		world.crew.eject()

func tick_sound_log(delta: float) -> void:
	if not _sound_log or not world.running:
		return
	if not _sl_hooked:
		_sl_hooked = true
		Sfx.listen = func(id: String, pos: Vector3) -> void:
			var eye := world.get_viewport().get_camera_3d()
			var d: float = -1.0 if (eye == null or pos == Vector3.INF) \
				else eye.global_position.distance_to(pos)
			if (_phantom or _trace_guns) and id in ["rifle", "mg", "autocannon", "gun", "carbine", "smg", "shot_far",
					"dmr", "pistol", "shotgun", "lmg", "suppressed"]:
				print("[phantom] %s at %s (%.0f m), stack: %s" % [id, str(pos.round()), d,
					" < ".join(PackedStringArray(get_stack().slice(1, 5).map(
						func(f): return "%s:%d" % [String(f["source"]).get_file(), int(f["line"])])))])
			var e: Array = _sl.get(id, [0, 1e9, 0.0])
			e[0] = int(e[0]) + 1
			if d >= 0.0:
				e[1] = minf(float(e[1]), d)
			_sl[id] = e
	_sl_t += delta
	if _phantom:
		_tick_phantom()
	if fmod(_sl_t, 5.0) < delta:
		var parts: Array = []
		for k in _sl:
			parts.append("%s x%d (nearest %.0f m)" % [k, int(_sl[k][0]), float(_sl[k][1])])
		print("[sound] t=%.0f %s: %s" % [_sl_t, String(Sim.mission), ", ".join(PackedStringArray(parts))])
		_sl.clear()
	if _sound_switch != "" and _sl_t > 30.0:
		var parts2 := _sound_switch.split(":")
		_sound_switch = ""
		print("[sound] -> %s" % parts2[0])
		world._start(parts2[1] if parts2.size() > 1 else "f16", parts2[0])
	if _sl_t > 60.0 and _sl_quit:
		world.get_tree().quit()
#endregion


#region --midairtest
## Head-on with another aeroplane: the player's must come apart. --preset=free:f16
var _midair_test := false
var _ma_t := 0.0
var _ma_other: Aircraft = null

func tick_midair(delta: float) -> void:
	if not _midair_test or not world.running or not is_instance_valid(world.player):
		return
	_ma_t += delta
	var p: Aircraft = world.player
	if _ma_other == null and _ma_t > 2.0:
		_ma_other = PlayerJet.new()
		_ma_other.setup("su35")
		_ma_other.team = 1
		_ma_other.name = "Oncoming"
		world.add_child(_ma_other)
		var fwd: Vector3 = -p.global_transform.basis.z
		_ma_other.global_transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP),
			p.global_position + fwd * 600.0)
		_ma_other.linear_velocity = -fwd * 200.0
		_ma_other.throttle = 0.8
		print("[midair] an Su-35 600 m ahead, coming the other way, closing at %.0f m/s" % (
			(p.linear_velocity + fwd * 200.0).length()))
	if _ma_other != null and _ma_t > 8.0:
		print("[midair] RESULT: player %s, the other %s" % [
			"destroyed" if not p.is_alive() else "still flying",
			"destroyed" if not (is_instance_valid(_ma_other) and _ma_other.is_alive()) else "still flying"])
		world.get_tree().quit()
#endregion


#region --uexit
## U tapped as a man taps it -- a key event down, the same key up a moment
## later -- on the runway, stopped: he must be out and stay out.
## --preset=takeoff:f16 --uexit
var _uexit := false
var _ux_t := 0.0
var _ux_step := 0

func _key_u(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_U
	e.physical_keycode = KEY_U
	e.pressed = down
	Input.parse_input_event(e)

func tick_uexit(delta: float) -> void:
	if not _uexit or not world.running or not is_instance_valid(world.player):
		return
	_ux_t += delta
	if _ux_step == 0 and _ux_t > 3.0:
		if world.boarding:
			world.crew.end_boarding()
		world.player.linear_velocity = Vector3.ZERO
		world.player.throttle = 0.0
		_ux_step = 1
		_ux_t = 0.0
	elif _ux_step == 1 and _ux_t > 1.0:
		_key_u(true)
		_ux_step = 2
		_ux_t = 0.0
	elif _ux_step == 2 and _ux_t > 0.05:
		_key_u(false)
		_ux_step = 3
		_ux_t = 0.0
	elif _ux_step == 3 and _ux_t > 2.0:
		var out: bool = world.on_foot and not world.boarding
		print("[uexit] a quick tap of U: on foot %s, boarding %s -> %s" % [str(world.on_foot),
			str(world.boarding), "ok" if out else "FAILED, back in"])
		# and U again by the aeroplane gets him in, as it should
		_key_u(true)
		_ux_step = 4
		_ux_t = 0.0
	elif _ux_step == 4 and _ux_t > 0.05:
		_key_u(false)
		_ux_step = 5
		_ux_t = 0.0
	elif _ux_step == 5 and _ux_t > 2.0:
		print("[uexit] U again beside it: on foot %s, boarding %s -> %s" % [str(world.on_foot),
			str(world.boarding), "ok" if not world.on_foot else "FAILED, still out"])
		world.get_tree().quit()
#endregion


#region --ramptest
## Up the open ramp of a C-130 and into its hold on foot, then back out down it:
## the man is walked with the keys, and his height over the ground and where he
## is are printed as he goes. --preset=ramp:c130 --ramptest
var _ramp_test := false
var _rt_t := 0.0
var _rt_step := 0
var _rt_jet: Aircraft = null

func tick_ramp_test(delta: float) -> void:
	if not _ramp_test or not world.running or not is_instance_valid(world.walker):
		return
	_rt_t += delta
	var w: Walker = world.walker
	if _rt_step == 0 and _rt_t > 2.0:
		for j in world.parked:
			if is_instance_valid(j) and j.has_hold():
				_rt_jet = j
		if _rt_jet == null:
			print("[ramp] RESULT: FAILED -- no transport on the line")
			world.get_tree().quit()
			return
		_rt_jet.ramp_open = true
		_rt_jet.ramp_anim = 1.0
		var hold: Node3D = _rt_jet.hold_node()
		var half: Vector3 = hold.get_meta("half")
		var behind: Vector3 = hold.global_transform * Vector3(0.0, 0.0, half.z * 1.62 + 6.0)
		behind.y = Sim.height_at(behind.x, behind.z) + 0.1
		w.global_position = behind
		var fwd: Vector3 = (hold.global_position - behind)
		w.yaw = atan2(-fwd.x, -fwd.z)
		Input.action_press(&"pitch_down")
		_rt_step = 1
		_rt_t = 0.0
	elif _rt_step == 1:
		if fmod(_rt_t, 0.5) < delta:
			var g: float = Sim.height_at(w.global_position.x, w.global_position.z)
			print("[ramp] t=%.1f %.1f m over the ground, in the hold %s" % [_rt_t,
				w.global_position.y - g, str(w.frame != null)])
		if w.frame != null and _rt_t > 1.0:
			print("[ramp] aboard after %.1f s" % _rt_t)
			Input.action_release(&"pitch_down")
			_rt_step = 2
			_rt_t = 0.0
		elif _rt_t > 12.0:
			Input.action_release(&"pitch_down")
			print("[ramp] RESULT: FAILED -- never got aboard")
			world.get_tree().quit()
	elif _rt_step == 2 and _rt_t > 1.0:
		# and back out, down the ramp
		w.yaw += PI
		Input.action_press(&"pitch_down")
		_rt_step = 3
		_rt_t = 0.0
	elif _rt_step == 3:
		if fmod(_rt_t, 0.5) < delta:
			print("[ramp] out: t=%.1f local z %.1f y %.2f, in the hold %s" % [_rt_t,
				w.position.z, w.position.y, str(w.frame != null)])
		if w.frame == null:
			Input.action_release(&"pitch_down")
			var g2: float = Sim.height_at(w.global_position.x, w.global_position.z)
			print("[ramp] off the ramp after %.1f s, %.1f m over the ground" % [_rt_t,
				w.global_position.y - g2])
			print("[ramp] RESULT: ok")
			world.get_tree().quit()
		elif _rt_t > 15.0:
			print("[ramp] RESULT: FAILED -- could not walk out")
			world.get_tree().quit()
#endregion


#region --wingstrike
## Fly the aeroplane past a tower standing in its way: off to one side, so
## only a wing goes through it, or dead ahead. What it says after is which
## parts it lost and whether it is still flying. --preset=free:c130 --wingstrike
var _ws_on := false
var _ws_off := 12.0
var _ws_t := 0.0
var _ws_box := -1
var _ws_said := false

func tick_wing_strike(delta: float) -> void:
	if not _ws_on or not world.running or not is_instance_valid(world.player):
		return
	var jet: Aircraft = world.player
	_ws_t += delta
	if _ws_box < 0 and _ws_t > 2.0:
		# low enough for there to be anything to hit (`OBSTACLE_CEILING`)
		var gp: Vector3 = jet.global_position
		jet.global_position = Vector3(gp.x, Sim.height_at(gp.x, gp.z) + 100.0, gp.z)
		var xf := jet.global_transform
		var fwd: Vector3 = -xf.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var at: Vector3 = jet.global_position + fwd * 260.0 + right * _ws_off
		at.y = jet.global_position.y - 30.0
		_ws_box = Obstacles.add_box(at, 2.0, 60.0, 2.0, atan2(-fwd.x, -fwd.z))
		print("[wingstrike] %s at %.0f m/s; tower %.0f m right of its track, 260 m ahead" % [
			jet.name, jet.linear_velocity.length(), _ws_off])
		_ws_t = 0.0
	# a second after the tower, before a one-winged aeroplane reaches the
	# ground: what it lost, and whether it is still in one piece otherwise
	if _ws_box >= 0 and not _ws_said and _ws_t > 2.8:
		_ws_said = true
		var wings_lost: int = int(jet.lost.has("wing_l")) + int(jet.lost.has("wing_r"))
		print("[wingstrike] after: alive=%s health=%.0f lost=%s -- %s" % [str(jet.alive), jet.health,
			str(jet.lost.keys()), ("RESULT: wing torn off, still flying" if jet.alive and wings_lost == 1
				else ("RESULT: destroyed" if not jet.alive else "RESULT: untouched"))])
		Obstacles.remove(_ws_box)
		world.get_tree().quit()
#endregion


#region --groundtest
## The airframe on the ground. taxi: under power on the wheels for fifteen
## seconds -- nothing should touch but the tyres. belly: wheels up, level, a
## metre and a half off the ground at 65 m/s and sinking slowly -- it should
## slide to a stop. slam: the same at 25 m/s down -- a crash. wing: banked
## 35 degrees at that height -- the low wing should go.
## --preset=takeoff:c130 --groundtest=taxi, --preset=free:c130 --groundtest=belly
var _gt_mode := ""
var _gt_t := 0.0
var _gt_set := false
var _gt_said := false

var _gt_jet: Aircraft = null

func tick_ground_test(delta: float) -> void:
	# not running any more is fine once it has started: a crash ends the run
	if _gt_mode == "" or (not world.running and not _gt_set):
		return
	if _gt_jet == null and is_instance_valid(world.player):
		_gt_jet = world.player
	if _gt_jet == null:
		return
	if not is_instance_valid(_gt_jet):
		# gone: it was destroyed and cleared away
		if _gt_set and not _gt_said:
			_gt_said = true
			print("[groundtest] %s after %.1f s: destroyed and gone -- RESULT: %s" % [_gt_mode, _gt_t,
				"ok" if _gt_mode == "slam" else "FAILED"])
			world.get_tree().quit()
		return
	var jet: Aircraft = _gt_jet
	_gt_t += delta
	if _gt_set and not _gt_said and not world.running:
		_gt_said = true
		print("[groundtest] %s after %.1f s: alive=%s, the run ended -- RESULT: %s" % [_gt_mode, _gt_t,
			str(jet.alive), "ok" if _gt_mode == "slam" and not jet.alive else "FAILED"])
		world.get_tree().quit()
		return
	if not _gt_set and _gt_t > 2.0:
		_gt_set = true
		_gt_t = 0.0
		if world.boarding:
			world.crew.end_boarding()
		if _gt_mode == "taxi":
			jet.throttle = 0.55
			jet.power = 0.55
		else:
			var gp: Vector3 = jet.global_position
			var fwd: Vector3 = -jet.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var yaw: float = atan2(-fwd.x, -fwd.z)
			var bank: float = deg_to_rad(35.0) if _gt_mode == "wing" else 0.0
			var lift: float = 2.4 if _gt_mode == "wing" else 1.5
			var g: float = Sim.height_at(gp.x, gp.z)
			jet.gear_down = false
			jet.gear_anim = 0.0
			jet.throttle = 0.0
			jet.power = 0.0
			var body_low: float = 0.0
			var sh: Dictionary = jet.spec.get("shape", {})
			for sec in sh.get("sections", []):
				body_low = maxf(body_low, float(sec[2]) - float(sec[3]))
			jet.global_transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, bank),
				Vector3(gp.x, g + body_low * 0.8 + lift, gp.z))
			jet.linear_velocity = fwd * 65.0 + Vector3(0, -25.0 if _gt_mode == "slam" else -1.0, 0)
			jet.angular_velocity = Vector3.ZERO
			world._reset_interp(jet)
		print("[groundtest] %s: %s" % [_gt_mode, jet.name])
		# a crash stops the harness ticking, so the end is heard, not looked for
		jet.died.connect(func(_w: Variant = null) -> void:
			if _gt_said:
				return
			_gt_said = true
			print("[groundtest] %s after %.1f s: destroyed -- RESULT: %s" % [_gt_mode, _gt_t,
				"ok" if _gt_mode == "slam" else "FAILED"])
			world.get_tree().quit())
	if _gt_set and not _gt_said and (_gt_t > 30.0 or not jet.alive):
		_gt_said = true
		var res := ""
		match _gt_mode:
			"taxi":
				res = "ok" if jet.alive and jet.health >= 99.0 and jet.lost.is_empty() else "FAILED"
			"belly":
				res = "ok" if jet.alive and jet.linear_velocity.length() < 8.0 else "FAILED"
			"slam":
				res = "ok" if not jet.alive else "FAILED"
			"wing":
				res = "ok" if (jet.lost.has("wing_l") or jet.lost.has("wing_r")) else "FAILED"
		print("[groundtest] %s after %.1f s: alive=%s health=%.0f speed %.1f agl %.1f lost=%s -- RESULT: %s" % [
			_gt_mode, _gt_t, str(jet.alive), jet.health, jet.linear_velocity.length(), jet.agl,
			str(jet.lost.keys()), res])
		world.get_tree().quit()
#endregion


#region --smallarms
## A man with a rifle against a parked aircraft: three magazines into it from
## twenty-five metres, and what it has left after each. A carbine should not
## bring an aeroplane down. --preset=ramp:c130 --smallarms[=KIT]
var _sa_kit := ""
var _sa_t := 0.0
var _sa_n := 0
var _sa_jet: Aircraft = null
var _sa_aim := ""

func tick_small_arms(delta: float) -> void:
	if _sa_kit == "" or not world.running:
		return
	if _sa_aim == "" and not is_instance_valid(world.walker):
		return
	_sa_t += delta
	if _sa_jet == null:
		if _sa_t < 3.0:
			return
		if _sa_aim != "" and world.player is Helicopter:
			_sa_jet = world.player
			if _sa_jet.has_method("set_hover_hold"):
				_sa_jet.call("set_hover_hold", true)
		else:
			for j in world.parked:
				if is_instance_valid(j) and j is Aircraft:
					_sa_jet = j
		if _sa_jet == null:
			print("[smallarms] RESULT: FAILED -- nothing parked")
			world.get_tree().quit()
			return
		print("[smallarms] %s at %s, health %.0f" % [_sa_kit, _sa_jet.name, _sa_jet.health])
		_sa_t = 0.0
		return
	if not is_instance_valid(_sa_jet):
		print("[smallarms] after %d rounds: destroyed and gone -- RESULT: FAILED" % _sa_n)
		world.get_tree().quit()
		return
	var g: Dictionary = Firearm.spec(_sa_kit)
	var mag: int = int(g["mag"])
	if _sa_n < mag * 3 and _sa_t > 0.1:
		_sa_t = 0.0
		var c: Vector3 = _sa_jet.global_position + Vector3(0, 0.5, 0)
		var side: Vector3 = _sa_jet.global_transform.basis.x
		var from: Vector3 = c + side * 25.0 + Vector3(0, 0.5, 0)
		var mark: Vector3 = c + Vector3(randf_range(-2, 2), randf_range(-0.5, 0.5), randf_range(-4, 4))
		var rotors: Array = (_sa_jet.spec.get("shape", {}) as Dictionary).get("rotors", [])
		var xf: Transform3D = _sa_jet.global_transform
		if _sa_aim == "tail" and rotors.size() > 1:
			mark = xf * (rotors[1]["pos"] as Vector3) + Vector3(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6), 0)
			from = mark + side * 25.0
		elif _sa_aim == "main" and not rotors.is_empty():
			var hub: Vector3 = xf * (rotors[0]["pos"] as Vector3)
			mark = hub + xf.basis.x * randf_range(1.5, 6.0) * (1.0 if randf() < 0.5 else -1.0) \
				+ xf.basis.z * randf_range(-5.0, 5.0)
			# from off to the side and a little below, outboard of the body
			from = mark + Vector3(0, -4.0, 0) + side * 25.0 * signf((mark - hub).dot(side) + 0.001)
		var aim: Vector3 = (mark - from).normalized()
		# as the other side: rounds pass through their own side's aircraft
		var who: Node = world
		if is_instance_valid(world.walker):
			who = world.walker
		Firearm.fire(world, who, 1 - int(_sa_jet.team), g, from, aim, 0.0)
		_sa_n += 1
		if _sa_n % mag == 0:
			print("[smallarms] after %d rounds (%d magazines): alive=%s health=%.1f lost=%s%s" % [_sa_n,
				int(float(_sa_n) / float(mag)), str(_sa_jet.alive), _sa_jet.health, str(_sa_jet.lost.keys()),
				(" main rotor %.0f tail rotor %.0f" % [float(_sa_jet.get("main_rotor_hp")),
					float(_sa_jet.get("tail_rotor_hp"))]) if _sa_jet is Helicopter else ""])
	elif _sa_n >= mag * 3 and _sa_t > 3.0:
		print("[smallarms] RESULT: %s" % ("ok" if _sa_aim != "" or (_sa_jet.alive and _sa_jet.lost.is_empty()) else "FAILED"))
		world.get_tree().quit()
#endregion
