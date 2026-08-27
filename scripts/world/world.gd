extends Node3D
## Main scene: builds the map, runs the hangar menu, spawns the mission and
## keeps score.

const NATO_JETS := ["f16", "f15", "typhoon", "rafale"]
const OPFOR_JETS := ["su35", "mig29", "su57", "j20"]
const NATO_HELIS := ["ah64", "tiger"]
const OPFOR_HELIS := ["mi28", "z10"]
## Aircraft the AI flies for something other than air-to-air: a mud mover that
## works the ground and the shipping, and a transport going about its business.
const NATO_CAS := ["a10", "f16"]
const OPFOR_CAS := ["su35", "mig29"]
const AI_TRANSPORTS := ["c130", "ac130"]

var terrain: Terrain
var base: Airbase
var scenery: Scenery
var weather: Weather
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _psm: ShaderMaterial
var menu: Menu
var hud: HUD
var cam: ChaseCamera
var menu_cam: Camera3D
var preview: Node3D
var player: Aircraft
var running := false
var _preview_id := ""
var spin := true
var _landing_watch := false
var _shot := ""
var _shot_frames := 0
var _stop_t := 0.0
var _auto := ""
var _dump := 0
var _dump_t := 0.0
var _view := ""
var _nocockpit := false
var _openbay := false
var _dist := 0.0
var _fx := false
var _tank_test := false
var _wreck_test := false
var _overlap_test := false
var _heli_test := false
var _heli_t := 0.0
var _heli_lo := 1e9
var _heli_hi := -1e9
var _heli_up := 0.0
var _ctl_test := 0.0
var _ctl_t := 0.0
var _ctl_roll := 0.0
var _ctl_pitch := 0.0
var _ctl_racc := 0.0
var _ctl_pacc := 0.0
var _ctl_pr := 0.0
var _ctl_rr := 0.0
var _hover_test := false
var _hov_t := 0.0
var _hov_y0 := 0.0
var _pod_test := false
var _pod_t := 0.0
var _pod_want := -1
var _admin_test := false
var _admin_t := 0.0
var _admin_from := ""
var _restart_test := false
var _restart_t := 0.0
var _restart_n := 0
var _shiptest := ""
var _shipt := 0.0
var _ship_p0 := Vector3.ZERO
var _wcam_test := false
var _wcam_t := 0.0
var _naval_test := false
var _naval_t := 0.0
var _naval_hp := 0.0
var _naval_ship: Node3D = null
var _naval_shot := false
var _naval_weapon := "gbu32"
var _naval_said := -1
var _cm_test := ""
var _cm_t := 0.0
var _cm_step := 0
var _cm_sam: Node3D = null
var _clutter_test := false
var _clutter_agl := 200.0
var _clutter_t2 := 0.0
var _clutter_step := 0
var _break_test := false
var _break_rng := 8000.0
var _break_t := 0.0
var _break_step := 0
var _break_min := 1e9
var _break_alt := 6000.0
var _break_w := "aim120"
var _bat_test := false
var _bat_t := 0.0
var _bat_a: Node3D = null
var _bat_b: Node3D = null
var _bat_hp := [0.0, 0.0]
var _bat_said := 0
var _cas_test := false
var _cas_t := 0.0
var _cas_said := 0
var _cas_hp := {}
var _chat_test := false
var _chat_t := 0.0
var _chat_step := 0
var _flight_lead: AIPlane = null
var _cas_lead: AIPlane = null
var _form_test := false
var _form_t := 0.0
var _form_said := 0
var _form_sum := 0.0
var _form_n := 0
var _form_worst := 0.0
var _mask_test := false
var _mask_t := 0.0
var mask_seeker_ok := false
var _shipnet := false
var _shipnet_t := 0.0
var _shipnet_said := 0
var _splash_test := false
var _splash_t := 0.0
var _splash_step := 0
var _auto_diag := false
var _auto_diag_t := 0.0
var _auto_diag_n := 0
var _vls_test := false
var _vls_t := 0.0
var _vls_step := 0
var _vls_ship: Node3D = null
var _vls_best := 1e9
var _town_test := false
var _sky_test := false
var _sky_short := 0
var _nettest := false
var _slot_home := Vector3.INF
var _slot_said := -1
var _mission_started := 0
var _splash_aim := Vector3.INF
var _splash_hit := Vector3.INF
var _splash_r := 0.0
var _dc_test := false
var _dc_t := 0.0
var _dc_ship: Node3D = null
var _dc_said := 0
var _trig_test := false
var _trig_t := 0.0
var _seam_test := false
var _laser_test := false
var _laser_t := 0.0
var _hud_test := false
var _hud_view := ""
var _hud_t := 0.0
var _fire_test := false
var _fire_t := 0.0
var _view_test := false
var _view_t := 0.0
var _shake_test := false
var _shake_t := 0.0
var _salvo_test := false
var _salvo_t := 0.0
var _salvo_dropped := 0
var _salvo_aim := Vector3.INF
var _lock_test := false
var _lock_t := 0.0
var _flap_test := false
var _flap_t := 0.0
var _sea_test := false
var _sub_test := false
var _sub_t := 0.0
var _sub_before := 0
var _sub_aim := Vector3.ZERO
var _fleet_test := false
var _fleet_t := 0.0
var _fleet_p0 := Vector3.ZERO
var _aim_test := false
var _aim_t := 0.0
var _seat_test := false
var _seat_t := 0.0
var _key_test := ""
var _key_t := 0.0
var _tvc_test := 0.0
var _tvc_t := 0.0
var _tvc_peak := 0.0
var _tvc_aoa := 0.0
var _tvc_defl := 0.0
var _board_test := false
var _boardtest_t := 0.0
var _jolt_test := false
var _jolt_t := 0.0
var _jolt_prev := Vector3.ZERO
var _jolt_worst := 0.0
var _jolt_when := 0.0
var _jolt_n := 0
var _jolt_sum := 0.0
var _jolt_gmin := 99.0
var _jolt_gmax := -99.0
var _overlap_t := 0.0
var _arty_test := ""
var _arty_t := 0.0
var _arty_off := 100.0
var _arty_fired := false
var _arty_aim := Vector3.ZERO
var _wreck_t2 := 0.0
var _cam_test := false
var _boom_test := false
var _fps_log := false
var _fps_t := 0.0
var _fps_n := 0
var _fps_sum := 0.0
var _dash_alt := 1000.0
var _bank_deg := 0.0
var _net_host := false
var _net_join := ""
var _net_log := false
var _turn_test := 0.0
var _turn_t := 0.0
var _turn_hdg := 0.0
var _turn_n := 0
var _turn_sum_g := 0.0
var _turn_sum_r := 0.0
var _turn_sum_a := 0.0
var _turn_sum_v := 0.0
var _run_for := 0.0
var _run_t := 0.0
var _net_t := 0.0
var _wtest := ""
var _wt_t := 0.0
var _wt_stage := 0
var _nuke_before := 0
var _nuke_aim := Vector3.ZERO
var _wt_mark: Node = null
var _drive_kind := ""
var _cam_t := 0.0
var _tank_t := 0.0
var _orbit := Vector2.ZERO
var _fx_t := 0.0
var pilot: Pilot
var board_cam: Camera3D
var boarding := false
var audio: AudioRig
var pod: SensorPod
var actions: ActionMenu
var map: MapView
var carrier: Carrier
var fleet_count := 0
var weapon_cam_on := false
var chat: ChatBox = null
var ship: Ship = null
var _ship_kind := ""
var admin: AdminMenu
var _traffic: Array[Aircraft] = []
var mode: GameMode
var veil: GVeil
var net: NetLink
var walker: Walker
var parked: Array = []
var tank: Tank = null
var on_foot := false
var gunning := false
var _gunner_test := false
var _gt := 0.0
var _pre_gun_auto := ""
var _station_walker: Node = null
var _board_t := 0.0
var _board_from := Vector3.ZERO
var _board_ladder := Vector3.ZERO
var _board_seat := Vector3.ZERO
var _skip_board := false
var _shot_at := 0
var _at := Vector3.ZERO

func _ready() -> void:
	_environment()
	scenery = Scenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	scenery.plan()                     # road network before the ground is painted

	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build()
	if OS.is_debug_build():
		print("[terrain] ", terrain.stats)
	base = Airbase.new()
	base.name = "Airbase"
	add_child(base)
	base.build()
	scenery.build()
	carrier = Carrier.new()
	carrier.name = "Carrier"
	add_child(carrier)
	carrier.build(Vector3(24000.0, 0.0, 1200.0), deg_to_rad(-18.0))
	_build_fleet()

	menu_cam = Camera3D.new()
	menu_cam.far = 45000.0
	menu_cam.fov = 42.0
	menu_cam.position = Vector3(30, 263.5, -30)
	add_child(menu_cam)
	menu_cam.look_at(Vector3(0, 258, 0), Vector3.UP)
	menu_cam.rotate_y(deg_to_rad(19.0))
	menu_cam.current = true

	preview = Node3D.new()
	preview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	preview.position = Vector3(0, 258, 0)
	add_child(preview)

	net = NetLink.new()
	net.name = "NetLink"
	net.world = self
	add_child(net)
	Sim.net = net

	var ui := CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var shell := Shell.new()
	shell.world = self
	ui.add_child(shell)
	hud = HUD.new()
	hud.base = base
	hud.visible = false
	ui.add_child(hud)
	# Over the HUD, not under it. Grey-out is what the pilot's eyes are doing,
	# and the instruments are the first thing to go: leaving the symbology
	# crisp over a blacked out world read as a bug, and it was one.
	veil = GVeil.new()
	ui.add_child(veil)
	pod = SensorPod.new()
	pod.visible = false
	ui.add_child(pod)
	_place_pod()
	get_viewport().size_changed.connect(_place_pod)
	chat = ChatBox.new()
	ui.add_child(chat)
	map = MapView.new()
	map.world = self
	ui.add_child(map)
	map.bake()
	admin = AdminMenu.new()
	admin.chose.connect(_do_admin)
	ui.add_child(admin)
	actions = ActionMenu.new()
	actions.set_anchors_preset(Control.PRESET_FULL_RECT)
	actions.chose.connect(_do_action)
	ui.add_child(actions)
	menu = Menu.new()
	menu.jet_changed.connect(_set_preview)
	menu.weather_changed.connect(set_weather)
	menu.start_requested.connect(_start)
	menu.host_requested.connect(_host_game)
	# the slot depends on the roster, which arrives after the mission starts
	net.roster_changed.connect(_offset_for_peer)
	menu.mission_changed.connect(_on_lobby_mission)
	menu.join_requested.connect(_join_game)
	menu.resume_requested.connect(_resume)
	ui.add_child(menu)
	_set_preview(menu.jet_id)
	_parse_cmdline()

func _place_pod() -> void:
	if pod:
		var vs := get_viewport().get_visible_rect().size
		pod.position = Vector2(vs.x - SensorPod.SIZE.x - 26.0, vs.y * 0.5 - SensorPod.SIZE.y * 0.5)

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = Weather.SKY_SHADER
	psm.shader = sh
	sky.sky_material = psm
	# The clouds are marched every frame and they move, so the sky cannot be
	# baked once. Real time keeps the radiance following the sun.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	# A realtime sky only accepts 256; anything else is overridden internally
	# and warns about it every launch.
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.0
	_env = env
	_psm = psm
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.68, 0.76, 0.86)
	env.fog_density = 0.0
	env.fog_depth_begin = 6500.0
	env.fog_depth_end = 38000.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.08
	env.glow_enabled = true
	env.glow_intensity = 0.65
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 1.05
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 136, 0)
	sun.light_energy = 1.18
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2600.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	add_child(sun)
	_sun = sun

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -44, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.72, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)
	_fill = fill

	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.apply(Sim.weather, _env, _sun, _fill, _psm)

# ---------------------------------------------------------------- preview
func _set_preview(id: String) -> void:
	if id == _preview_id:
		return
	_preview_id = id
	for c in preview.get_children():
		c.queue_free()
	if id.begins_with("sea:"):
		# a ship on the turntable, scaled right down: they are enormous
		var sh := Ship.new()
		sh.setup(id.substr(4), 0)
		sh.set_physics_process(false)
		sh.remove_from_group("boardable")
		sh.remove_from_group("hittable")
		sh.remove_from_group("ships")
		preview.add_child(sh)
		sh.position = Vector3(0, 0, 0)
		preview.scale = Vector3.ONE * (16.0 / maxf(float(Ship.KINDS[id.substr(4)]["len"]), 20.0))
		return
	if id.begins_with("veh:"):
		# ground vehicles get a turntable model too, not a stand-in aircraft
		var t := Tank.new()
		t.setup(0, id.substr(4))
		t.freeze = true
		t.gravity_scale = 0.0
		t.remove_from_group("boardable")
		t.remove_from_group("hittable")
		# and not a vehicle either: the menu turntable sits 256 m up in the
		# preview rig, and gameplay code that went looking for "the m109" found
		# this one first and put the player in the sky.
		t.remove_from_group("vehicles")
		t.set_physics_process(false)
		preview.add_child(t)
		t.position = Vector3(0, -1.4, 0)
		preview.scale = Vector3.ONE * 1.55
		return
	var m := JetFactory.build(JetSpec.get_spec(id))
	preview.add_child(m["root"])
	for g in m["gear"]:
		g.rotation.x = deg_to_rad(88.0)
		g.visible = false
	var scale_fix: float = 15.0 / maxf(JetSpec.get_spec(id)["span"], 8.0)
	preview.scale = Vector3.ONE * scale_fix

func _process(delta: float) -> void:
	if preview and preview.visible and spin:
		preview.rotate_y(delta * 0.35)
	if _gunner_test and is_instance_valid(player):
		_gt += delta
		if _gt > 2.0 and not gunning:
			toggle_gunner()
		elif gunning and fmod(_gt, 3.0) < delta:
			var b := player.global_transform.basis
			var aim: Vector3 = pod.aim_point()
			print("[gunner] t=%4.1f alt=%6.1f bank=%+5.1f spd=%5.1f  pod=%s  gun=%s" % [
				_gt, player.global_position.y, rad_to_deg(atan2(-b.x.y, b.y.y)),
				player.linear_velocity.length(),
				"locked" if aim != Vector3.INF else "no point",
				player.weapon_label(player.current_weapon())])
			if aim != Vector3.INF:
				player.fire_gunship(self, aim)
	if pod and pod.active and is_instance_valid(tank):
		pod.toggle()
		pod.set_fullscreen(false)
		if cam:
			cam.pod_slew = false
	if pod and pod.active and not gunning and is_instance_valid(player):
		_sensor_input()
	if gunning:
		_gunner_input(delta)
	if pod and pod.active and not gunning \
			and (not running or on_foot or not is_instance_valid(player)):
		pod.toggle()
	if audio and cam and not on_foot:
		audio.cockpit = cam.mode == ChaseCamera.Mode.COCKPIT and not boarding
	# A head-up display is glass in front of the pilot's face. From a chase or
	# orbit camera you are outside the aeroplane and there is nothing to read it
	# off, so the flight page only draws from the cockpit. Checked on its own:
	# hanging it off the audio rig meant it never ran if there was no sound.
	Sim.ui_modal = (is_instance_valid(map) and map.visible) \
		or (is_instance_valid(actions) and actions.visible) \
		or (is_instance_valid(chat) and chat.typing) \
		or get_tree().paused
	if _nettest and net != null:
		_nettest = false
		print("[net] before hosting: %s" % net.status_line())
		print("[net] local address: %s" % net.local_ip())
		var ok := net.host("f16")
		print("[net] host() -> %s, listening on %d" % [str(ok), net.port])
		print("[net] hangar shows: %s" % net.status_line())
		print("[net] join address: %s" % net.join_address())
		# and again, without leaving, which used to be fatal
		var ok2 := net.host("f16")
		print("[net] host() a second time without leaving -> %s, port %d" % [
			str(ok2), net.port])
		net.shutdown()
		print("[net] after shutdown(): active=%s" % str(net.active))
		net.leave()
		print("[net] after leave: %s" % net.status_line())
		var ok3 := net.host("f16")
		print("[net] host() after leave -> %s, port %d" % [str(ok3), net.port])
		net.leave()
		get_tree().quit()
	# Keep the hangar's session line current. It carries the address a joiner
	# has to type, including the port, which is not something to leave to a
	# mission-log message that scrolls away.
	if is_instance_valid(menu) and menu.visible and net != null:
		menu.set_net_status(net.status_line())
		# and who is allowed to choose the match
		var role := ""
		if net.active:
			role = "host" if net.is_host else "client"
		menu.set_net_role(role, String(net.lobby_mission))
	# The cloud volume rides with whatever camera is actually current — the
	# cockpit, the chase, the sensor pod, a ship's bridge — not with the
	# aircraft chase camera specifically. Handing the sky the wrong eye position
	# is what made it look welded to the view.
	if is_instance_valid(weather):
		var eye := get_viewport().get_camera_3d()
		if eye != null:
			weather.follow(eye.global_position)
	if is_instance_valid(hud) and is_instance_valid(cam) and running:
		hud.flight_page = (cam.mode == ChaseCamera.Mode.COCKPIT)
	if boarding:
		_tick_boarding(delta)
	if running and is_instance_valid(player) and not boarding and not on_foot:
		_watch_landing(delta)
	if _dump > 0 and is_instance_valid(player):
		_dump_t += delta
		if _dump_t > float(_dump) * 0.008333:
			_dump_t = 0.0
			var b := player.global_transform.basis
			var bank := rad_to_deg(atan2(-b.x.y, b.y.y))
			var pit := rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0)))
			var hdg := fmod(rad_to_deg(atan2(-b.z.x, b.z.z)) + 360.0, 360.0)
			var av := player.angular_velocity
			print("t=%5.1f kias=%5.1f alt=%7.1f agl=%7.1f vs=%+6.1f aoa=%+5.1f beta=%+5.1f g=%+4.1f bank=%+6.1f pitch=%+5.1f hdg=%5.1f p=%+5.2f q=%+5.2f r=%+5.2f thr=%.2f pwr=%.2f fuel=%6.0f gnd=%s x=%7.1f z=%8.1f" % [
				Time.get_ticks_msec() * 0.001, player.ias * 1.94384, player.global_position.y,
				player.agl, player.vspeed, rad_to_deg(player.aoa), rad_to_deg(player.beta), player.g_load,
				bank, pit, hdg, av.dot(-b.z), av.dot(b.x), av.dot(b.y),
				player.throttle, player.power, player.fuel, str(player.on_ground),
				player.global_position.x, player.global_position.z])
	if _net_log and net and net.active:
		_net_t += delta
		if _net_t > 2.0:
			_net_t = 0.0
			var names: Array = []
			for pid in net.ghosts:
				var g = net.ghosts[pid]
				if is_instance_valid(g):
					names.append("%d@%s" % [pid, str(g.global_position.round())])
			var ai_n := 0
			var ai_where := ""
			var ai_keys: Array = net.ai_ghosts.keys()
			ai_keys.sort()          # a stable sample: dictionary order moves as ghosts die
			for k in ai_keys:
				if is_instance_valid(net.ai_ghosts[k]) and net.ai_ghosts[k].alive:
					ai_n += 1
					if ai_where == "":
						var gg = net.ai_ghosts[k]
						ai_where = "#%d %s v=%.0f" % [k,
							str(gg.global_position.round()),
							(gg.get_meta("net_vel", Vector3.ZERO) as Vector3).length()]
			var me := "-"
			if is_instance_valid(player):
				me = str(player.global_position.round())
			elif is_instance_valid(walker):
				me = str(walker.position.round())
			names.append("me" + me)
			if not net.is_host:
				var gn := 0
				var gd := ""
				for z in get_tree().get_nodes_in_group("zones"):
					for a in z.assets:
						if is_instance_valid(a) and a.has_meta("gnd_pos"):
							gn += 1
							if gd == "":
								gd = "%.2f m" % a.global_position.distance_to(
									a.get_meta("gnd_pos") as Vector3)
				names.append("garrison=%d lag=%s" % [gn, gd])
			if is_instance_valid(player):
				var tn := "none"
				if player.target != null and is_instance_valid(player.target):
					tn = "%s@%.0fkm" % [str(player.target.name).left(12),
						player.global_position.distance_to(player.target.global_position) * 0.001]
				var load_s := ""
				for wt in player.weapon_types:
					load_s += "%s:%d " % [wt, player.count_remaining(wt)]
				names.append("tgt=" + tn + " w=" + player.current_weapon()
					+ " jet=" + str(player.spec["name"]) + " [" + load_s.strip_edges() + "]")
			if not net.is_host:
				print("[net] %s  id=%d  roster=%d  ghosts=%d  ai=%d %s  tx=%d rx=%d  %s" % [
					net.status, net.my_id, net.roster.size(), net.ghosts.size(),
					ai_n, ai_where, net.tx, net.rx, ", ".join(PackedStringArray(names))])
			else:
				var host_ai := 0
				var lowest := 1e9
				for n in get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.is_alive():
						host_ai += 1
						lowest = minf(lowest, n.global_position.y)
				var worst: Node3D = null
				for n in get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.global_position.y == lowest:
						worst = n
				if worst != null:
					names.append("lowest bandit y=%.0f agl=%.0f alive=%s wrecked=%s frozen=%s sleep=%s" % [
						lowest, worst.get("agl"), str(worst.get("alive")),
						str(worst.get("wrecked")), str(worst.get("freeze")),
						str(worst.get("sleeping"))])
				print("[net] %s  id=%d  roster=%d  ghosts=%d  ai(sim)=%d  tx=%d rx=%d  %s" % [
					net.status, net.my_id, net.roster.size(), net.ghosts.size(),
					host_ai, net.tx, net.rx, ", ".join(PackedStringArray(names))])
	if _wtest != "":
		# the checks must outlive the shooter: a bomb keeps guiding after the
		# aircraft that dropped it has been shot down
		if _wt_stage > 1 or is_instance_valid(player):
			_run_weapon_test(delta)
	if _fps_log:
		_fps_t += delta
		_fps_sum += Engine.get_frames_per_second()
		_fps_n += 1
		if _fps_t >= 2.0:
			print("[perf] fps=%5.1f  draw calls=%5d  objects=%5d  prims=%8d  mem=%4d MB" % [
				_fps_sum / float(maxi(_fps_n, 1)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
				int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
			_fps_t = 0.0
			_fps_n = 0
			_fps_sum = 0.0
	if _boom_test:
		_boom_test = false
		for spot in [Vector3(2600, 0, 4200), Vector3(-2300, 0, -5200), Vector3(150, 0, -300)]:
			var y := Sim.height_at(spot.x, spot.z)
			var n := scenery.damage_area(Vector3(spot.x, y, spot.z), 140.0)
			print("[demolish] blast at %s flattened %d structures" % [str(spot.round()), n])
	if _cam_test and is_instance_valid(player) and cam:
		_cam_t += delta
		# sweep the look angles and report how the rig behaves
		cam.free_yaw = clampf(sin(_cam_t * 0.30) * 2.6, -2.7, 2.7)
		cam.free_pitch = clampf(sin(_cam_t * 0.19) * 1.1, -1.25, 1.25)
		cam.diag = true
		if fmod(_cam_t, 0.8) < delta and not cam.last_diag.is_empty():
			var d: Dictionary = cam.last_diag
			print("[cam] yaw=%+6.1f pitch=%+6.1f  boom=%5.1f m  jet off-centre=%5.2f deg" % [
				d["yaw"], d["pitch"], d["boom"], d["off"]])
	if _arty_test != "" and is_instance_valid(tank):
		_arty_t += delta
		if _arty_t > 2.0 and _arty_aim == Vector3.ZERO:
			# designate well off the current bearing: the whole point is to make
			# the piece traverse a long way before it may shoot
			var brg: float = tank.rotation.y + deg_to_rad(_arty_off)
			var p := tank.global_position + Vector3(sin(brg), 0, -cos(brg)) * 6000.0
			_arty_aim = Vector3(p.x, Sim.height_at(p.x, p.z), p.z)
			tank.map_target = _arty_aim
			tank.aim_yaw = brg
			var went: bool = tank.fire_main(self)
			print("[arty] designated %s, %.0f deg off; fired immediately: %s" % [
				str(_arty_aim.round()), _arty_off, str(went)])
		elif _arty_aim != Vector3.ZERO and not _arty_fired:
			if tank.lay_error() <= 0.03 and tank._gun_cd <= 0.0:
				tank.fire_main(self)     # the crew pulls the trigger when laid
			if tank._gun_cd > 0.0:
				_arty_fired = true
				var tb: Vector3 = -tank._muzzle.global_transform.basis.z
				print("[arty]   projectile: %s" % ("rocket" if tank.is_ripple() else "shell"))
				var cf: Vector3 = -tank.cam.global_transform.basis.z
				print("[arty]   camera looks at bearing %.1f, tubes at %.1f" % [
					fmod(rad_to_deg(atan2(cf.x, -cf.z)) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(tb.x, -tb.z)) + 360.0, 360.0)])
				print("[arty]   readout bearing %.1f, tubes actually %.1f, target %.1f" % [
					fmod(rad_to_deg(tank.aim_yaw) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(tb.x, -tb.z)) + 360.0, 360.0),
					fmod(rad_to_deg(atan2(_arty_aim.x - tank.global_position.x,
						-(_arty_aim.z - tank.global_position.z))) + 360.0, 360.0)])
				print("[arty] rounds away at t=%.1f s, lay error now %.2f deg" % [
					_arty_t, rad_to_deg(tank.lay_error())])
			elif fmod(_arty_t, 1.0) < delta:
				print("[arty]   still laying, %.1f deg to go" % rad_to_deg(tank.lay_error()))
		elif _arty_fired and tank._gun_cd <= 0.0 and tank.rounds_left > 0:
			if tank.fire_main(self):
				print("[arty]   another round away, %d left on the rails" % tank.rounds_left)
	if _heli_test and is_instance_valid(player):
		_heli_t += delta
		if _heli_t < 0.05:
			player.global_transform = Transform3D(Basis(), Vector3(0, 500, 5000))
			player.linear_velocity = Vector3(0, 0, -30.0)
			player.auto = ""
			player.throttle = 0.5
			player.power = 0.5
			if "hold_alt" in player:
				player.hold_alt = 500.0
		elif _heli_t > 4.0 and _heli_t < 24.0:
			# hands off: it should simply stay where it is
			_heli_lo = minf(_heli_lo, player.global_position.y)
			_heli_hi = maxf(_heli_hi, player.global_position.y)
		elif _heli_t < 32.0:
			Input.action_press(&"throttle_up")     # SHIFT
		elif _heli_t < 33.0:
			Input.action_release(&"throttle_up")
			_heli_up = player.global_position.y
		elif _heli_t < 41.0:
			Input.action_press(&"throttle_down")   # Z / CTRL
		elif _heli_t >= 41.0:
			Input.action_release(&"throttle_down")
			_heli_test = false
			print("[heli]   climbed to %.0f m on the up lever, then down to %.0f m" % [
				_heli_up, player.global_position.y])
			print("[heli] %s hands off for 20 s: altitude %.1f to %.1f m (drift %.1f m), throttle %.2f" % [
				str(player.spec["name"]), _heli_lo, _heli_hi, _heli_hi - _heli_lo, player.throttle])
			get_tree().quit()
	if _ctl_test > 0.0 and is_instance_valid(player):
		_ctl_t += delta
		if _ctl_t < 0.05:
			player.global_transform = Transform3D(Basis(), Vector3(0, 4000, 9000))
			player.linear_velocity = Vector3(0, 0, -_ctl_test)
			player.gear_down = false
			player.gear_anim = 0.0
			player.auto = "hold"
			player.throttle = 0.7
			player.power = 0.7
		elif _ctl_t < 5.0:
			player.in_roll = 1.0            # full lateral stick
			player.in_pitch = 0.0
		elif _ctl_t < 9.0:
			player.in_roll = 0.0
			player.in_pitch = 1.0           # then full aft
		else:
			print("[ctl] %-20s assist=%-5s at %3.0f m/s: peak roll %6.1f deg/s (accel %5.0f deg/s2), peak pitch %5.1f deg/s (accel %5.0f deg/s2)" % [
				str(player.spec["name"]), str(player.assist), _ctl_test,
				rad_to_deg(_ctl_roll), rad_to_deg(_ctl_racc),
				rad_to_deg(_ctl_pitch), rad_to_deg(_ctl_pacc)])
			_ctl_test = 0.0
			get_tree().quit()
		if _ctl_t > 0.1:
			var b := player.global_transform.basis
			var av := player.angular_velocity
			var rr := av.dot(-b.z)
			var pr := av.dot(b.x)
			if _ctl_t < 5.0:
				_ctl_roll = maxf(_ctl_roll, absf(rr))
				_ctl_racc = maxf(_ctl_racc, absf(rr - _ctl_rr) / maxf(delta, 1e-5))
			else:
				_ctl_pitch = maxf(_ctl_pitch, absf(pr))
				_ctl_pacc = maxf(_ctl_pacc, absf(pr - _ctl_pr) / maxf(delta, 1e-5))
			_ctl_rr = rr
			_ctl_pr = pr
	if _hover_test and is_instance_valid(player):
		_hov_t += delta
		if _hov_t > 2.0 and player.auto != "hover":
			# well clear of the ground, and only once the mission has finished
			# putting the aeroplane where it wants it
			player.global_transform = Transform3D(Basis(), Vector3(0, 600, 4000))
			player.linear_velocity = Vector3(0, 0, -40.0)
			player.gear_down = true
			player.gear_anim = 1.0
			_reset_interp(player)
			_hov_y0 = 600.0
			player.auto = "hover"
			player.hover_alt = _hov_y0
			player.hover_cmd = true
		elif _hov_t > 26.0:
			_hover_test = false
			var b := player.global_transform.basis
			print("[hover] %s: jetborne=%.2f  alt %.0f (target %.0f)  speed %.1f m/s  pitch %+.1f bank %+.1f  alive=%s" % [
				str(player.spec["name"]), player.jetborne, player.global_position.y, _hov_y0,
				player.linear_velocity.length(),
				rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))),
				rad_to_deg(atan2(-b.x.y, b.y.y)), str(player.alive)])
			get_tree().quit()
	# hold the view on something real while following
	if is_instance_valid(admin) and admin.following and is_instance_valid(cam):
		if not is_instance_valid(cam.subject) or not _traffic.has(cam.subject):
			_follow_traffic(true)
	if _admin_test:
		_admin_t += delta
		if _admin_t > 3.0 and _traffic.is_empty():
			# optionally get out of the aeroplane first: the report is that
			# traffic only flies its approach while the player is in one
			if _admin_from != "":
				if _admin_from == "ship":
					for sh in get_tree().get_nodes_in_group("ships"):
						var v := sh as Ship
						if v != null and v.has_gun() and v.team == 0:
							_enter_ship(v)
							break
				elif _admin_from == "tank":
					for v in get_tree().get_nodes_in_group("vehicles"):
						if v is Tank and (v as Tank).alive:
							_enter_tank(v as Tank)
							break
				elif _admin_from == "foot":
					_try_dismount()
				print("[admin] player is now in: %s (aeroplane valid=%s active=%s)" % [
					_admin_from, str(is_instance_valid(player)),
					str(player.active) if is_instance_valid(player) else "-"])
			admin.jet_id = "f16"
			_do_admin("flight")
			if _admin_from != "":
				_do_admin("follow")     # and watch them, from wherever we are
			print("[admin] called a flight of %d" % _traffic.size())
		elif _admin_t > 8.0 and fmod(_admin_t, 25.0) < delta:
			for t in _traffic:
				if not is_instance_valid(t):
					continue
				var view := "none"
				if is_instance_valid(cam) and cam.current:
					view = "chase->%s" % (String(cam.subject.name) \
						if is_instance_valid(cam.subject) else "-")
				elif is_instance_valid(ship) and is_instance_valid(ship.cam) \
						and ship.cam.current:
					view = "ship"
				print("[admin] %-12s auto=%-8s active=%s  z=%8.1f y=%6.1f thr=%.2f gnd=%s  view=%s" % [
					t.name, t.auto, str(t.active), t.global_position.z,
					t.global_position.y, t.throttle, str(t.on_ground), view])
				break
		elif _admin_t > 210.0:
			_admin_test = false
			var down := 0
			var flying := 0
			for t in _traffic:
				if not is_instance_valid(t):
					continue
				if t.on_ground:
					down += 1
				else:
					flying += 1
			print("[admin] after 210 s: %d on the ground, %d still flying" % [down, flying])
			get_tree().quit()
	if _restart_test:
		_restart_t += delta
		if _restart_t > 3.0 and _restart_n < 3:
			_restart_n += 1
			# swap aircraft and restart, which is what the player was doing
			var picks := ["f22", "veh:m270", "f16"]
			_restart_t = 0.0
			_start(picks[_restart_n - 1], "ramp")
			return
		elif _restart_t > 3.0:
			_restart_test = false
			var craft := 0
			for n in get_tree().get_root().find_children("*", "Node3D", true, false):
				if is_instance_valid(n) and ("spec" in n) and (n.get("spec") is Dictionary):
					craft += 1
			print("[restart] after %d restarts: %d aircraft in the world" % [_restart_n, craft])
			get_tree().quit()
	if _shiptest != "" and is_instance_valid(ship):
		_shipt += delta
		if _shipt < 0.2:
			_ship_p0 = ship.global_position
		elif _shipt < 8.0:
			ship.telegraph = 1.0
			ship.helm = 0.6
			ship.aim_yaw = ship.heading + deg_to_rad(60.0)
		elif _shipt >= 8.0:
			_shiptest = ""
			var moved: float = ship.global_position.distance_to(_ship_p0)
			var g0: float = ship.gun_cd
			var fired: bool = ship.fire_gun()
			var mnt := 0.0
			if is_instance_valid(ship._gun):
				var mf: Vector3 = -ship._gun.global_transform.basis.z
				mnt = fmod(rad_to_deg(atan2(mf.x, -mf.z)) + 360.0, 360.0)
			# the pod must sit on the ship, and the context menu must be naval
			pod.toggle()
			var podx: float = pod._head_origin().distance_to(ship.global_position)
			var pody: float = pod._head_origin().y - ship.global_position.y
			pod.toggle()
			actions.open_for_vehicle(ship)
			var labels := ""
			for it in actions.items:
				labels += String(it["label"]) + "; "
			actions.close()
			print("[ship] pod head %.1f m from the ship (%.1f m up); menu: %s" % [
				podx, pody, labels])
			print("[ship] %s: made %.0f m in 8 s (%.1f kts), heading %03d, mount bearing %03d vs ordered %03d, gun fired=%s" % [
				ship.display_name(), moved, ship.speed * 1.94384,
				int(fmod(rad_to_deg(ship.heading) + 360.0, 360.0)), int(mnt),
				int(fmod(rad_to_deg(ship.aim_yaw) + 360.0, 360.0)), str(fired and g0 <= 0.0)])
			get_tree().quit()
	if _wcam_test and is_instance_valid(player) and cam:
		_wcam_t += delta
		if _wcam_t > 2.5 and not weapon_cam_on:
			weapon_cam_on = true
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			player.locked = true
			player.fire_cd = 0.0
			player.set_weapon(maxi(player.weapon_types.find("aim120"), 0))
			player.fire()
			cam.diag = true
			cam.wcam_jitter = 0.0
			cam.wcam_jsum = 0.0
			cam.wcam_jn = 0
		elif _wcam_t > 12.0:
			_wcam_test = false
			var riding: bool = cam.weapon_cam != null and is_instance_valid(cam.weapon_cam)
			var d := -1.0
			if riding:
				d = cam.global_position.distance_to((cam.weapon_cam as Node3D).global_position)
			# How steady the ride is: the frame-to-frame change in the boom
			# vector from the round to the camera. A rigid follow holds it near
			# zero; a camera stepping at the physics rate while the round is
			# drawn interpolated moves a whole tick of travel every frame.
			print("[wcam] armed=%s riding a round=%s, camera %.1f m from it" % [
				str(weapon_cam_on), str(riding), d])
			print("[wcam] boom wobble over %d frames: mean %.3f m, worst %.3f m" % [
				cam.wcam_jn, cam.wcam_jsum / maxf(float(cam.wcam_jn), 1.0),
				cam.wcam_jitter])
			get_tree().quit()
	if _naval_test and is_instance_valid(player):
		_naval_t += delta
		if _naval_t > 2.0 and _naval_ship == null:
			for sh in get_tree().get_nodes_in_group("ships"):
				if is_instance_valid(sh) and (sh as Ship).team != 0:
					_naval_ship = sh
					break
			if _naval_ship == null:
				print("[naval] no hostile shipping")
				_naval_test = false
				return
			_naval_hp = _naval_ship.get("health")
			player.global_transform = Transform3D(Basis(),
				_naval_ship.global_position + Vector3(0, 1500, 3000))
			player.linear_velocity = Vector3(0, 0, -250.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			# designate the ship with the pod laser, which is what the player
			# would do, rather than handing the bomb a radar contact
			pod.jet = player
			if not pod.active:
				pod.toggle()
			pod.mode = pod.POINT
			pod.tracked = _naval_ship
			if not pod.lasing:
				pod.toggle_laser()
			pod._process(0.016)
			player.locked = true
			player.set_weapon(maxi(player.weapon_types.find(_naval_weapon), 0))
			player.fire_cd = 0.0
			_reset_interp.call_deferred(player)
			player.target = _naval_ship
			print("[naval] attacking %s with %s, hull %.0f; laser spot %s (sea level %.0f)" % [
				_naval_ship.call("display_name"), _naval_weapon, _naval_hp,
				str(player.designated.round()), Sim.WATER_LEVEL])
		elif _naval_t > 2.0 and _naval_t < 5.0 and is_instance_valid(_naval_ship):
			if int(_naval_t * 4.0) != _naval_said:
				_naval_said = int(_naval_t * 4.0)
				var rel: Vector3 = _naval_ship.global_position - player.global_position
				print("[naval] t=%.2f  target=%s  %.1f deg below the nose, %.0f m  locked=%s lock_t=%.2f" % [
					_naval_t, str(is_instance_valid(player.target)),
					rad_to_deg((-player.global_transform.basis.z).angle_to(rel)),
					rel.length(), str(player.locked), player.lock_time])
		elif _naval_t > 5.0 and not _naval_shot:
			_naval_shot = true
			print("[naval] at release: pod active=%s lasing=%s mode=%d tracked=%s designated=%s node=%s" % [
				str(pod.active), str(pod.lasing), pod.mode,
				str(is_instance_valid(pod.tracked)), str(player.designated.round()),
				str(player.designated_node.name) if is_instance_valid(player.designated_node) else "none"])
			print("[naval] release: %s" % ("away" if player.fire() == "" else "refused"))
		elif _naval_t > 40.0:
			_naval_test = false
			var now: float = _naval_ship.get("health") if is_instance_valid(_naval_ship) else -1.0
			print("[naval] RESULT: hull %.0f -> %.0f (%s)" % [_naval_hp, now,
				"HIT" if now < _naval_hp else "no damage"])
			get_tree().quit()
	# Two hostile warships put within gun range of each other, left to it.
	if _bat_test:
		_bat_t += delta
		if _bat_t > 1.5 and not is_instance_valid(_bat_a):
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null or not v.has_gun():
					continue
				if v.team == 0 and _bat_a == null:
					_bat_a = v
				elif v.team == 1 and _bat_b == null:
					_bat_b = v
			if _bat_a == null or _bat_b == null:
				print("[fleet] need one warship a side")
				_bat_test = false
				return
			var mid: Vector3 = (_bat_a.global_position + _bat_b.global_position) * 0.5
			_bat_a.global_position = Vector3(mid.x - 4000.0, Sim.WATER_LEVEL, mid.z)
			_bat_b.global_position = Vector3(mid.x + 4000.0, Sim.WATER_LEVEL, mid.z)
			_bat_hp = [_bat_a.get("health"), _bat_b.get("health")]
			print("[fleet] %s (t0, hull %.0f) vs %s (t1, hull %.0f), 8.0 km apart" % [
				_bat_a.call("display_name"), _bat_hp[0],
				_bat_b.call("display_name"), _bat_hp[1]])
		else:
			var tick := int((_bat_t - 3.0) / 30.0) + 1
			if tick > _bat_said:
				_bat_said = tick
				var rng := -1.0
				if is_instance_valid(_bat_a) and is_instance_valid(_bat_b):
					rng = _bat_a.global_position.distance_to(_bat_b.global_position)
				for v in [_bat_a, _bat_b]:
					if is_instance_valid(v):
						print("[fleet] %6.1fs  %-26s %-46s spd %4.1f  fired %2d  rng %5.0f m" % [
							_bat_t, v.call("display_name"), v.call("damage_report"),
							v.get("speed"), int(v.get("rounds")), rng])
			if _bat_t > 150.0:
				_bat_test = false
				for i in 2:
					var v: Node3D = _bat_a if i == 0 else _bat_b
					if not is_instance_valid(v):
						print("[fleet] RESULT: side %d gone from the board" % i)
						continue
					print("[fleet] RESULT: side %d %-26s hull %.0f -> %.0f  %s" % [
						i, v.call("display_name"), _bat_hp[i], v.get("health"),
						"SUNK" if not bool(v.get("alive")) else "afloat"])
				get_tree().quit()
	# The sky: how much cloud there is, how it is banded, and where the sun
	# goes over a day.
	if _sky_test:
		_sky_test = false
		# The shader itself: headless never rasterises, so ask the compiler
		# directly rather than assuming a clean parse means a clean sky.
		var probe_sh := Shader.new()
		probe_sh.code = Weather.SKY_SHADER
		var unis := probe_sh.get_shader_uniform_list()
		var names := PackedStringArray()
		for u in unis:
			names.append(String(u["name"]))
		# A shader that fails to compile reports no uniforms at all and then
		# quietly draws nothing. That is not something to print and move past:
		# an array literal in the march cost a whole sky exactly this way.
		if unis.size() < 15:
			_sky_short += 1
		print("[sky] shader compiled with %d uniforms: %s" % [unis.size(),
			", ".join(names)])
		var fog_sh := Shader.new()
		fog_sh.code = Weather.FOG_SHADER
		if fog_sh.get_shader_uniform_list().size() < 6:
			_sky_short += 1
		print("[sky] fog shader compiled with %d uniforms; volume %s, box %s, froxel reach %.0f m" % [
			fog_sh.get_shader_uniform_list().size(),
			"present" if weather.has_volume() else "MISSING",
			str(weather.volume_size()), _env.volumetric_fog_length])
		var eye0 := get_viewport().get_camera_3d()
		if eye0 != null:
			weather.follow(eye0.global_position)
		print("[sky] eye handed to the sky: %s (current camera %s), march limit %.0f m" % [
			str(_psm.get_shader_parameter("cam_pos")),
			String(eye0.name) if eye0 != null else "none",
			float(_psm.get_shader_parameter("march_far"))])
		for id in Weather.ids():
			set_weather(id)
			var decks := 0
			for d in weather.get_children():
				if d is MultiMeshInstance3D:
					decks += 1
			var band: Vector2 = weather.cloud_band()
			var reach: float = weather.march_reach(id)
			if reach < Weather.MARCH_FAR:
				_sky_short += 1
			print("[sky] %-10s coverage %.2f, density %.2f, %d steps reaching %6.0f m of %.0f; cloud %.0f to %.0f m; %d draw calls, %d billboards" % [
				id, float(_psm.get_shader_parameter("coverage")),
				float(_psm.get_shader_parameter("density_mul")),
				int(_psm.get_shader_parameter("steps")), reach, Weather.MARCH_FAR,
				band.x, band.y, decks, weather.puff_count()])
		print("[sky] RESULT: %s" % ("ok" if _sky_short == 0 else
			"FAILED — %d fault(s): a shader that did not compile, or a preset that cannot march as far as it claims" % _sky_short))
		set_weather("scattered")
		print("[sky] a day, by the solar model:")
		for h in [0, 4, 6, 8, 12, 16, 18, 20, 22]:
			var sa := weather.solar_angles(float(h))
			weather.time_of_day = float(h)
			weather._apply_sun(true)
			print("[sky]   %02d:00  sun %+5.1f deg elevation, bearing %5.1f, light %.2f, ambient %.2f, daylight %.2f" % [
				h, rad_to_deg(sa.x), rad_to_deg(sa.y), _sun.light_energy,
				_env.ambient_light_energy, weather.daylight()])
		get_tree().quit()
	# Several JDAMs at one lased point, released a couple of seconds apart.
	if _salvo_test and is_instance_valid(player):
		_salvo_t += delta
		if _salvo_t > 2.0 and _salvo_aim == Vector3.INF:
			var gx := 2400.0
			var gz := -5200.0
			_salvo_aim = Vector3(gx, Sim.height_at(gx, gz), gz)
			var mark := GroundTarget.new()
			mark.team = 1
			mark.setup("radar")
			add_child(mark)
			mark.global_position = _salvo_aim
			player.global_transform = Transform3D(Basis(),
				_salvo_aim + Vector3(0, 2600.0, 7000.0))
			player.linear_velocity = Vector3(0, 0, -240.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			pod.jet = player
			if not pod.active:
				pod.toggle()
			pod.mode = pod.POINT
			pod.tracked = mark
			if not pod.lasing:
				pod.toggle_laser()
			pod._process(0.016)
			player.locked = true
			player.set_weapon(maxi(player.weapon_types.find("gbu32"), 0))
			_reset_interp.call_deferred(player)
			Sim.salvo_watch = true
			Sim.salvo_mark = _salvo_aim
			Sim.salvo_log.clear()
			print("[salvo] lasing %s; three JDAMs, two seconds apart" % str(_salvo_aim.round()))
		elif _salvo_aim != Vector3.INF and _salvo_dropped < 3 \
				and _salvo_t > 4.0 + float(_salvo_dropped) * 2.0:
			_salvo_dropped += 1
			player.fire_cd = 0.0
			var r := player.fire()
			print("[salvo] release %d: %s" % [_salvo_dropped,
				"away" if r == "" else r])
		elif _salvo_dropped >= 3 and _salvo_t > 80.0:
			_salvo_test = false
			for entry in Sim.salvo_log:
				print("[salvo]   %s" % String(entry))
			print("[salvo] RESULT: %d released, %d detonated" % [
				_salvo_dropped, Sim.salvo_log.size()])
			get_tree().quit()
	# How steady the sensor head is on the aeroplane carrying it.
	if _shake_test and is_instance_valid(player):
		_shake_t += delta
		if _shake_t > 2.0 and not pod.active:
			pod.jet = player
			pod.toggle()
			pod.diag = true
			pod.shake_worst = 0.0
			pod.shake_sum = 0.0
			pod.shake_n = 0
			player.in_roll = 0.35        # keep it manoeuvring, not gliding
			player.in_pitch = 0.2
		elif _shake_t > 26.0:
			_shake_test = false
			print("[pod] head against the aeroplane over %d frames: mean %.4f m, worst %.4f m" % [
				pod.shake_n, pod.shake_sum / maxf(float(pod.shake_n), 1.0),
				pod.shake_worst])
			get_tree().quit()
	# A missile launched from a given range at an aeroplane that then breaks
	# hard at full power: how close does it get?
	if _break_test and is_instance_valid(player):
		_break_t += delta
		if _break_t > 1.5 and _break_step == 0:
			_break_step = 1
			var shooter := AIPlane.new()
			shooter.setup("su35")
			shooter.team = 1
			shooter.name = "Shooter"
			add_child(shooter)
			var spot := Vector3(0.0, _break_alt, 0.0)
			shooter.global_transform = Transform3D(Basis(),
				spot + Vector3(0, 0, _break_rng))
			shooter.look_at_from_position(shooter.global_position, spot, Vector3.UP)
			shooter.linear_velocity = -shooter.global_transform.basis.z * 300.0
			player.team = 0
			player.global_transform = Transform3D(Basis(), spot)
			player.rotation.y = deg_to_rad(180.0)
			player.linear_velocity = -player.global_transform.basis.z * 380.0
			player.gear_down = false
			player.gear_anim = 0.0
			player.flares = 0
			player.chaff = 0
			player.throttle = 1.0
			player.power = 1.0
			_reset_interp(player)
			_reset_interp(shooter)
			# Nothing else in the world gets a vote. With the fleet left running
			# there were twenty-one rounds in the air and the closest approach
			# was whichever of them happened to be nearest — the measurement
			# came out identical whatever the missile physics were doing.
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.ai = false
					v2.cells_left = 0
			for g2 in get_tree().get_nodes_in_group("ground_targets"):
				if is_instance_valid(g2):
					g2.queue_free()
			for m2 in get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m2):
					m2.queue_free()
			shooter.target = player
			shooter.locked = true
			shooter.selected = maxi(shooter.weapon_types.find(_break_w), 0)
			shooter.fire_cd = 0.0
			print("[break] %s from %.1f km at %.0f m; the target then breaks at full power" % [
				_break_w, _break_rng * 0.001, _break_alt])
			shooter.fire()
		elif _break_step == 1 and _break_t > 2.0:
			# hard break, wings level nowhere near the missile
			player.in_roll = 1.0
			player.in_pitch = 1.0
			player.throttle = 1.0
			for m in get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m) and m.target == player \
						and String(m.wid) == _break_w:
					_break_min = minf(_break_min,
						(m as Node3D).global_position.distance_to(player.global_position))
			if _break_t > 34.0:
				_break_step = 2
				print("[break] RESULT: %s from %.1f km at %.0f m — closest %.0f m (fuse %.0f), player alive=%s" % [
					_break_w, _break_rng * 0.001, _break_alt, _break_min,
					float(WeaponSpec.get_spec(_break_w)["fuse"]),
					str(player.is_alive())])
				get_tree().quit()
	# Fly the same profile at different heights and see what the battery can do
	# about it.
	if _clutter_test and is_instance_valid(player):
		_clutter_t2 += delta
		if _clutter_t2 > 1.5 and _clutter_step == 0:
			_clutter_step = 1
			var at := Vector3(2000.0, 0.0, -3000.0)
			_cm_sam = GroundTarget.new()
			_cm_sam.team = 1
			_cm_sam.setup("sam")
			add_child(_cm_sam)
			_cm_sam.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
			player.team = 0
			var px := at.x
			var pz := at.z + 6000.0
			player.global_transform = Transform3D(Basis(),
				Vector3(px, Sim.height_at(px, pz) + _clutter_agl, pz))
			player.linear_velocity = Vector3(0, 0, -220.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.flares = 0
			player.chaff = 0             # no countermeasures: clutter alone
			_reset_interp(player)
			print("[clutter] running in at %.0f m agl, 6.0 km out, no countermeasures" % _clutter_agl)
		elif _clutter_step == 1 and _clutter_t2 > 30.0:
			_clutter_step = 2
			var fired := 0
			var tracking := 0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				fired += 1
				if m.target == player:
					tracking += 1
			print("[clutter] RESULT: %.0f m agl — %d rounds up, %d still tracking, player alive=%s, agl now %.0f" % [
				_clutter_agl, fired, tracking, str(player.is_alive()), player.agl])
			get_tree().quit()
	# Does a countermeasure actually break a shot? A SAM site fires at the
	# player from close range; the aeroplane either dispenses or does not.
	if _cm_test != "" and is_instance_valid(player):
		_cm_t += delta
		if _cm_t > 1.5 and _cm_step == 0:
			_cm_step = 1
			var at := Vector3(2000.0, 0.0, -3000.0)
			_cm_sam = GroundTarget.new()
			_cm_sam.team = 1
			_cm_sam.setup("sam")
			add_child(_cm_sam)
			_cm_sam.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
			player.team = 0
			player.global_transform = Transform3D(Basis(),
				at + Vector3(0.0, Sim.height_at(at.x, at.z) + 2000.0, 6000.0))
			player.linear_velocity = Vector3(0, 0, -230.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.flares = 240
			player.chaff = 240
			_reset_interp(player)
			print("[cm] SAM at %s, aeroplane 6.0 km out at 2000 m agl, mode=%s" % [
				str(_cm_sam.global_position.round()), _cm_test])
		elif _cm_step == 1 and _cm_t > 2.5:
			# let it shoot, then run the defence for the whole flight time
			var live := 0
			var tracking := 0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				live += 1
				if m.target == player:
					tracking += 1
			if live > 0:
				match _cm_test:
					"chaff":
						player.drop_chaff()
					"flare":
						player.drop_flare()
					"both":
						player.dispense_all()
					_:
						pass
			if _cm_t > 26.0:
				_cm_step = 2
				print("[cm] RESULT: %s — %d rounds up, %d still tracking; player alive=%s (flares %d, chaff %d left)" % [
					_cm_test, live, tracking, str(player.is_alive()),
					player.flares, player.chaff])
				get_tree().quit()
	# Where the towns ended up, how level they are, and whether the streets are
	# on the surface or buried in it.
	if _town_test:
		_town_test = false
		for t in scenery.sites:
			var c: Vector2 = t["c"]
			var r: float = float(t["r"])
			var moved: float = c.distance_to(t["was"] as Vector2)
			# worst height spread across a 24 m building footprint, sampled
			# across the town, and the mean gradient over the whole site
			var worst := 0.0
			var mean := 0.0
			var n := 0
			for i in 15:
				for j in 15:
					var q := c + Vector2(float(i - 7), float(j - 7)) * (r / 8.0)
					if q.distance_to(c) > r:
						continue
					var lo := 1e9
					var hi := -1e9
					for dx in [-12.0, 12.0]:
						for dz in [-12.0, 12.0]:
							var y := Sim.height_at(q.x + dx, q.y + dz)
							lo = minf(lo, y)
							hi = maxf(hi, y)
					worst = maxf(worst, hi - lo)
					mean += 1.0 - Sim.normal_at(q.x, q.y).y
					n += 1
			print("[town] %-14s at %s (moved %4.0f m)  gradient %.4f  worst footprint step %5.2f m" % [
				String(t["name"]), str(c.round()), moved,
				mean / maxf(float(n), 1.0), worst])
		# How clearly a street reads. Walk perpendicular across one and compare
		# the stain on the centreline with the stain halfway to the next street.
		var on_road := 0.0
		var between := 0.0
		var xs := 0
		for r in scenery._streets:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			if ra.distance_to(rb) < 200.0:
				continue
			var dirv := (rb - ra).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			for k in 5:
				var q: Vector2 = ra.lerp(rb, 0.2 + float(k) * 0.15)
				on_road += terrain.mask_at(q.x, q.y).x
				between += terrain.mask_at(q.x + nrm.x * 64.0, q.y + nrm.y * 64.0).x
				xs += 1
		print("[town] street contrast: stain %.2f on the centreline, %.2f halfway to the next street" % [
			on_road / maxf(float(xs), 1.0), between / maxf(float(xs), 1.0)])
		# and how much of the built-up area actually looks built up
		var paved := 0.0
		var edge_paved := 0.0
		var edge_n := 0
		var all_n := 0
		for t in scenery.sites:
			var tc: Vector2 = t["c"]
			var rad: float = float(t["r"])
			for i in 21:
				for j in 21:
					var q := tc + Vector2(float(i - 10), float(j - 10)) * (rad / 10.0)
					var dd := q.distance_to(tc)
					if dd > rad:
						continue
					var tf: float = terrain.mask_at(q.x, q.y).y
					paved += tf
					all_n += 1
					if dd > rad * 0.85:
						edge_paved += tf
						edge_n += 1
		var stained := 0
		var stain_n := 0
		for t in scenery.sites:
			var tc2: Vector2 = t["c"]
			var rad2: float = float(t["r"])
			for i in 61:
				for j in 61:
					var q := tc2 + Vector2(float(i - 30), float(j - 30)) * (rad2 / 30.0)
					if q.distance_to(tc2) > rad2:
						continue
					stain_n += 1
					if terrain.mask_at(q.x, q.y).x > 0.5:
						stained += 1
		var table: Array = Terrain.ring_table()
		for t in scenery.sites:
			var tc3: Vector2 = t["c"]
			var cheb: float = maxf(absf(tc3.x), absf(tc3.y))
			var cell := -1.0
			for ring in table:
				if cheb <= float(ring["coverage"]):
					cell = float(ring["cell"])
					break
			print("[town] %-14s %.1f km from the field: terrain cells are %.0f m there (street grid is 128 m)" % [
				String(t["name"]), cheb * 0.001, cell])
		# Roads over the airfield, and buildings standing in the road.
		var on_field := 0
		var on_apron := 0
		var on_runway := 0
		var pts_f := 0
		for r in Sim.ROADS:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var steps: int = maxi(int(ra.distance_to(rb) / 12.0), 2)
			for k in steps + 1:
				var q: Vector2 = ra.lerp(rb, float(k) / float(steps))
				pts_f += 1
				if not Sim.clear_of_airfield(q.x, q.y):
					on_field += 1
					if absf(q.x) < 620.0 and absf(q.y) < 2600.0:
						on_apron += 1
				if Sim.on_runway(q.x, q.y):
					on_runway += 1
		print("[town] trunk network over the airfield: %d of %d points inside the keep-out (%d of those on the field itself, %d on the runway)" % [
			on_field, pts_f, on_apron, on_runway])
		var clash := 0
		var nearest_clash := 1e9
		var built := 0
		var on_tarmac := 0
		for x in scenery.town_xforms:
			var xf: Transform3D = x
			built += 1
			# half the footprint, from the instance scale
			var halfw: float = maxf(xf.basis.x.length(), xf.basis.z.length()) * 0.5
			var d := Sim.road_distance(xf.origin.x, xf.origin.z)
			if d < halfw + 4.0:
				clash += 1
				nearest_clash = minf(nearest_clash, d)
			if terrain.mask_at(xf.origin.x, xf.origin.z).x > 0.35:
				on_tarmac += 1
		var pyl_bad := 0
		var pyl_n := 0
		for n in scenery.get_children():
			if not (n is MultiMeshInstance3D) or String(n.name) != "Pylons":
				continue
			var pm := (n as MultiMeshInstance3D).multimesh
			for i in pm.instance_count:
				pyl_n += 1
				var o: Vector3 = scenery.pylon_spots[i] if i < scenery.pylon_spots.size() \
					else Vector3.ZERO
				if not Sim.clear_of_roads(o.x, o.z, 12.0):
					pyl_bad += 1
		print("[town] pylons standing in a road: %d of %d" % [pyl_bad, pyl_n])
		print("[town] buildings in a road: %d of %d overlap the carriageway (closest centre %.1f m), %d stand on painted tarmac" % [
			clash, built, nearest_clash if clash > 0 else -1.0, on_tarmac])
		print("[town] tarmac covers %.1f%% of the built-up area" % [
			100.0 * float(stained) / maxf(float(stain_n), 1.0)])
		print("[town] made ground: %.2f across the footprint, %.2f in the outer ring where the buildings meet the country" % [
			paved / maxf(float(all_n), 1.0), edge_paved / maxf(float(edge_n), 1.0)])
		# The ribbon against the terrain *mesh*, which is what is actually
		# drawn. The chunk mesh samples the height field on a 30 m grid and
		# interpolates between, so over a dip the drawn ground sits above the
		# true height field — and the carriageway, laid 0.16 m over the field,
		# ends up underneath it.
		var sunk := 0
		var pts := 0
		var worst_sink := 0.0
		var sum_sink := 0.0
		for r in (Sim.ROADS + scenery._streets):
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var steps: int = maxi(int(ra.distance_to(rb) / 11.0), 2)
			for k in steps + 1:
				var q: Vector2 = ra.lerp(rb, float(k) / float(steps))
				var road_y := Sim.height_at(q.x, q.y) + 0.16
				# the drawn ground: bilinear over the innermost ring's cells
				var cs := 30.0
				var gx := floorf(q.x / cs) * cs
				var gz := floorf(q.y / cs) * cs
				var tx := (q.x - gx) / cs
				var tz := (q.y - gz) / cs
				var h00 := Sim.height_at(gx, gz)
				var h10 := Sim.height_at(gx + cs, gz)
				var h01 := Sim.height_at(gx, gz + cs)
				var h11 := Sim.height_at(gx + cs, gz + cs)
				var mesh_y := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
				pts += 1
				if mesh_y > road_y:
					sunk += 1
					sum_sink += mesh_y - road_y
					worst_sink = maxf(worst_sink, mesh_y - road_y)
		print("[town] carriageway vs the drawn ground: %d of %d points under it, mean %.2f m, worst %.2f m" % [
			sunk, pts, sum_sink / maxf(float(sunk), 1.0), worst_sink])
		# and the streets: are they on the ground or under it
		var buried := 0
		var total := 0
		var deepest := 0.0
		for seg in scenery._streets:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			for k in 12:
				var q: Vector2 = a.lerp(b, float(k) / 11.0)
				total += 1
				# the ribbon lays its surface 0.16 m above the sampled height,
				# so anything more than that below a neighbour is buried
				var here := Sim.height_at(q.x, q.y) + 0.16
				var around := -1e9
				for dx in [-6.0, 6.0]:
					for dz in [-6.0, 6.0]:
						around = maxf(around, Sim.height_at(q.x + dx, q.y + dz))
				if around > here:
					buried += 1
					deepest = maxf(deepest, around - here)
		print("[town] streets: %d segments, %d of %d sample points buried, deepest %.2f m" % [
			scenery._streets.size(), buried, total, deepest])
		# and the trunk network: how much climbing it does, and how steep it gets
		var climb := 0.0
		var length := 0.0
		var steepest := 0.0
		for r in Sim.ROADS:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var d := a.distance_to(b)
			length += d
			var steps: int = maxi(int(d / 50.0), 2)
			var last := Sim.height_at(a.x, a.y)
			for k in range(1, steps + 1):
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var y := Sim.height_at(q.x, q.y)
				climb += absf(y - last)
				steepest = maxf(steepest, absf(y - last) / (d / float(steps)))
				last = y
		for t in scenery.sites:
			var tc: Vector2 = t["c"]
			var near := 1e9
			for r in Sim.ROADS:
				near = minf(near, Geometry2D.get_closest_point_to_segment(
					tc, r[0], r[1]).distance_to(tc))
			print("[town] %-14s nearest trunk road %.0f m from the middle of it" % [
				String(t["name"]), near])
		# Does the baked field actually know where the roads are? The terrain
		# paints its road stain from this, so if the field cannot resolve a
		# carriageway the network is invisible from the air.
		var worst_err := 0.0
		var sum_err := 0.0
		var missed := 0
		var samples := 0
		for r in (Sim.ROADS + scenery._streets):
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			for k in 9:
				var q: Vector2 = ra.lerp(rb, float(k) / 8.0)
				if absf(q.x) >= 18000.0 or absf(q.y) >= 18000.0:
					continue
				var field := Sim.road_distance(q.x, q.y)
				var exact := Sim._road_distance_exact(q.x, q.y)
				samples += 1
				sum_err += absf(field - exact)
				worst_err = maxf(worst_err, absf(field - exact))
				if field >= 46.0:
					missed += 1      # the terrain paints no road stain here
		print("[town] road field on the centreline: mean error %.1f m, worst %.1f m; %d of %d points where the terrain paints nothing" % [
			sum_err / maxf(float(samples), 1.0), worst_err, missed, samples])
		for n in scenery.get_children():
			if n is MeshInstance3D and String(n.name) in ["Roads", "Kerbs"]:
				var mi := n as MeshInstance3D
				var ab := mi.get_aabb()
				var tris := 0
				if mi.mesh != null:
					for si in mi.mesh.get_surface_count():
						tris += mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX].size() / 3
				print("[town] mesh %-6s visible=%s tris=%d  aabb pos=%s size=%s  layers=%d" % [
					String(mi.name), str(mi.visible), tris,
					str(ab.position.round()), str(ab.size.round()), mi.layers])
		print("[town] scenery: %s" % str(scenery._stats))
		print("[town] trunk roads: %d legs, %.1f km of tarmac, %.0f m of climb (%.1f m per km), steepest %.1f%%" % [
			Sim.ROADS.size(), length * 0.001, climb, climb / maxf(length * 0.001, 1.0),
			steepest * 100.0])
		get_tree().quit()
	# Do the tubes actually reach an aeroplane, or does the round climb away.
	if _vls_test and is_instance_valid(player):
		_vls_t += delta
		if _vls_t > 2.0 and _vls_step == 0:
			_vls_step = 1
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.has_vls() and v.team != 0:
					_vls_ship = v
					break
			if _vls_ship == null:
				print("[vls] no hostile ship with tubes")
				_vls_test = false
				return
			# put the aeroplane where a strike aircraft would be: twelve
			# kilometres out and eight thousand feet up, running in
			var sp: Vector3 = _vls_ship.global_position
			player.team = 0
			player.global_transform = Transform3D(Basis(),
				sp + Vector3(0.0, 2400.0, 12000.0))
			player.linear_velocity = Vector3(0, 0, -240.0)
			player.gear_down = false
			player.gear_anim = 0.0
			_reset_interp(player)
			print("[vls] %s at %s, aeroplane 12.0 km out at 2400 m" % [
				_vls_ship.call("display_name"), str(sp.round())])
		elif _vls_step == 1 and _vls_t > 3.0:
			_vls_step = 2
			print("[vls] launch: %s" % str(_vls_ship.call("fire_vls", player)))
		elif _vls_step == 2:
			var live := 0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				live += 1
				_vls_best = minf(_vls_best,
					(m as Node3D).global_position.distance_to(player.global_position))
			if int(_vls_t) % 6 == 0 and int(_vls_t * 60.0) % 360 == 0:
				for m in get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(m):
						var mp: Vector3 = (m as Node3D).global_position
						print("[vls] t=%5.1f  round at %s  alt %6.0f  %.0f m from the aeroplane" % [
							_vls_t, str(mp.round()), mp.y,
							mp.distance_to(player.global_position)])
						break
			if _vls_t > 28.0:
				_vls_test = false
				print("[vls] RESULT: closest approach %.0f m, %d rounds still up, player alive=%s" % [
					_vls_best, live, str(player.is_alive())])
				get_tree().quit()
	# What the autoland is actually commanding on the way down.
	if _auto_diag and is_instance_valid(player):
		_auto_diag_t += delta
		var step := int(_auto_diag_t / 2.0)
		if step > _auto_diag_n:
			_auto_diag_n = step
			var pp := player.global_position
			print("[auto] t=%5.1f  x=%+7.1f z=%+8.1f y=%6.1f agl=%5.1f  ias=%5.1f kt  thr=%.2f  vs=%+5.2f  gnd=%s" % [
				_auto_diag_t, pp.x, pp.z, pp.y, player.agl, player.ias * 1.94384,
				player.throttle, player.linear_velocity.y, str(player.on_ground)])
	# A bomb into open water: is the fireball anywhere a player could see it.
	if _splash_test and is_instance_valid(player):
		_splash_t += delta
		if _splash_t > 2.0 and _splash_step == 0:
			_splash_step = 1
			var sea := _deep_water(Vector3(26000.0, 0.0, 3000.0))
			player.global_transform = Transform3D(Basis(),
				Vector3(sea.x, Sim.WATER_LEVEL + 1400.0, sea.z + 2600.0))
			player.linear_velocity = Vector3(0, 0, -230.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			# the shipping stands down, so the only thing going off out here is
			# the bomb rather than somebody's five inch practice
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
			# lase the water, the way a pilot would: without the pod running,
			# `designated` is cleared every frame and the bomb leaves unguided
			# Deliberately NOT lased. A bomb that reaches the water with nothing
			# to detonate on is the case that was broken: it falls through the
			# proximity fuse to the terminal water check, and that is where the
			# fireball used to be drawn under the sea.
			if pod.active:
				pod.toggle()
			_splash_aim = Vector3(sea.x, Sim.WATER_LEVEL, sea.z)
			player.locked = true
			player.set_weapon(maxi(player.weapon_types.find("gbu32"), 0))
			player.fire_cd = 0.0
			Sim.last_burst = Vector3.INF
			_reset_interp.call_deferred(player)
			print("[splash] aiming at open water %s, sea level %.0f" % [
				str(player.designated.round()), Sim.WATER_LEVEL])
		elif _splash_t > 4.5 and _splash_step == 1:
			_splash_step = 2
			print("[splash] release: %s" % ("away" if player.fire() == "" else "refused"))
		elif _splash_step == 2:
			# latch the burst that belongs to this bomb, not whatever else in the
			# world happened to go off last
			if Sim.last_burst != Vector3.INF \
					and Sim.last_burst.distance_to(_splash_aim) < 2500.0:
				_splash_hit = Sim.last_burst
				_splash_r = Sim.last_burst_r
			if _splash_t < 40.0:
				return
			_splash_test = false
			Sim.last_burst = _splash_hit
			Sim.last_burst_r = _splash_r
			if Sim.last_burst == Vector3.INF:
				print("[splash] RESULT: FAILED — nothing ever went off")
			else:
				var above: float = Sim.last_burst.y - Sim.WATER_LEVEL
				print("[splash] last fireball at %s, radius %.0f — %.1f m %s the surface" % [
					str(Sim.last_burst.round()), Sim.last_burst_r, absf(above),
					"above" if above >= 0.0 else "BELOW"])
				# and the reason it was invisible in the first place: the sea is
				# a transparent mesh sixty kilometres across, so it has to be
				# told to sort behind everything drawn at the surface
				var sea_pri := -99
				var boom_pri := -99
				for n in terrain.get_children():
					if n.name == "Water" and n is MeshInstance3D:
						var wm := (n as MeshInstance3D).material_override as StandardMaterial3D
						if wm != null:
							sea_pri = wm.render_priority
				var probe := Effects.Boom.new()
				add_child(probe)
				boom_pri = probe._mat.render_priority
				probe.queue_free()
				print("[splash] render order: sea %d, explosion %d (sea must be lower)" % [
					sea_pri, boom_pri])
				print("[splash] RESULT: %s" % ("ok" if above >= -0.5 \
					and sea_pri < boom_pri else "FAILED"))
			get_tree().quit()
	# What each end of a session thinks the fleet is doing.
	if _shipnet:
		_shipnet_t += delta
		var mark := int(_shipnet_t / 10.0)
		if mark > _shipnet_said:
			_shipnet_said = mark
			var side0 := "single"
			if net != null and net.active:
				side0 = "host" if net.is_host else "client"
			var afloat := 0
			var sunk := 0
			var broken := 0
			var going := 0
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 == null:
					continue
				if v2.alive:
					afloat += 1
				else:
					sunk += 1
				if v2.is_broken():
					broken += 1
				if v2.is_sinking():
					going += 1
			print("[shipnet] %-8s sky: %s at %05.2f h, sun %+.1f deg, wind_time %.1f, coverage %.2f | fleet: %d afloat, %d sunk, %d broken in two, %d going down" % [
				side0, weather.current, weather.time_of_day,
				rad_to_deg(weather.sun_elevation()),
				float(_psm.get_shader_parameter("wind_time")),
				float(_psm.get_shader_parameter("coverage")),
				afloat, sunk, broken, going])
			var side := "single"
			if net != null and net.active:
				side = "host" if net.is_host else "client %d" % net.my_id
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null or v.fleet_idx > 2:
					continue
				print("[shipnet] %-12s t=%3.0f  hull %d  %-26s pos %s  hdg %6.1f  hull %6.0f  ghost=%s" % [
					side, _shipnet_t, v.fleet_idx, v.display_name(),
					str(v.global_position.round()), rad_to_deg(v.heading),
					v.health, str(v.ghost)])
	# Does the terrain actually block a line, and does the radar respect it.
	if _mask_test and is_instance_valid(player):
		_mask_t += delta
		if _mask_t > 2.0:
			_mask_test = false
			# a pair of points either side of the highest ground we can find
			var best := Vector3.ZERO
			var bh := -1e9
			for i in 40:
				for j in 40:
					var q := Vector3(float(i - 20) * 700.0, 0.0, float(j - 20) * 700.0)
					var h := Sim.height_at(q.x, q.z)
					if h > bh:
						bh = h
						best = Vector3(q.x, h, q.z)
			print("[mask] highest ground nearby: %s at %.0f m" % [
				str(best.round()), bh])
			var a := best + Vector3(-3500.0, 0, 0)
			var b := best + Vector3(3500.0, 0, 0)
			a.y = Sim.height_at(a.x, a.z) + 40.0
			b.y = Sim.height_at(b.x, b.z) + 40.0
			print("[mask] low either side of it: clear=%s (expect false), depth %.0f m" % [
				str(Sim.line_of_sight(a, b)), Sim.masking_depth(a, b)])
			var ha := Vector3(a.x, bh + 2500.0, a.z)
			var hb := Vector3(b.x, bh + 2500.0, b.z)
			print("[mask] both well above it: clear=%s (expect true),  depth %.0f m" % [
				str(Sim.line_of_sight(ha, hb)), Sim.masking_depth(ha, hb)])
			# and what the radar does about it
			var ghost := AIPlane.new()
			ghost.setup("su35")
			ghost.team = 1
			ghost.name = "Masked bandit"
			add_child(ghost)
			ghost.global_position = b
			ghost.freeze = true
			player.global_position = a
			player.team = 0
			_reset_interp(player)
			player.target = null
			player.cycle_target()
			var got_masked: bool = is_instance_valid(player.target)
			ghost.global_position = Vector3(b.x, bh + 2500.0, b.z)
			player.global_position = Vector3(a.x, bh + 2500.0, a.z)
			player.target = null
			player.cycle_target()
			var got_clear: bool = is_instance_valid(player.target)
			print("[mask] radar lock: behind the ridge=%s (expect false), over it=%s (expect true)" % [
				str(got_masked), str(got_clear)])
			# and the scope, not just the lock: count what the radar page would
			# actually paint from behind the ridge and from over it
			ghost.global_position = b
			player.global_position = a
			var paint_masked := _radar_paints(ghost)
			ghost.global_position = Vector3(b.x, bh + 2500.0, b.z)
			player.global_position = Vector3(a.x, bh + 2500.0, a.z)
			var paint_clear := _radar_paints(ghost)
			print("[mask] radar scope: paints it behind the ridge=%s (expect false), over it=%s (expect true)" % [
				str(paint_masked), str(paint_clear)])
			# and what shoots at you. The battery stands on the ridge's far
			# side; the ship is at sea, with the player put behind the highest
			# ground on the line running inland from her.
			var sam := GroundTarget.new()
			sam.team = 1
			sam.setup("sam")
			add_child(sam)
			sam.global_position = Vector3(b.x, Sim.height_at(b.x, b.z), b.z)
			var fired_masked := 0
			var fired_clear := 0
			for phase in 2:
				var y: float = (bh + 2500.0) if phase == 1 else (Sim.height_at(a.x, a.z) + 40.0)
				player.global_position = Vector3(a.x, y, a.z)
				player.team = 0
				_reset_interp(player)
				sam._cool = 0.0
				var before := get_tree().get_nodes_in_group("missiles").size()
				for _i in 240:                     # two seconds of engagement
					sam._physics_process(1.0 / 120.0)
				var shots: int = get_tree().get_nodes_in_group("missiles").size() - before
				if phase == 0:
					fired_masked = shots
				else:
					fired_clear = shots
			print("[mask] battery launches: behind the ridge=%d (expect 0), over it=%d (expect 1)" % [
				fired_masked, fired_clear])
			# the ship's own acquisition, from her masthead over open water
			var sh := Ship.new()
			sh.setup("destroyer", 1)
			add_child(sh)
			var sea := _deep_water(Vector3(26000.0, 0.0, 2000.0))
			sh.global_position = Vector3(sea.x, Sim.WATER_LEVEL, sea.z)
			sh.ai = false
			# walk inland and find the highest ground on that bearing
			var peak := Vector3.ZERO
			var peak_h := -1e9
			var peak_t := 0.0
			for k in 220:
				var t := float(k) * 90.0
				var q := Vector3(sea.x - t, 0.0, sea.z)
				var hh := Sim.height_at(q.x, q.z)
				if hh > peak_h:
					peak_h = hh
					peak = q
					peak_t = t
			var behind := Vector3(peak.x - 3000.0, 0.0, peak.z)
			var ship_masked := 0
			var ship_clear := 0
			for phase2 in 2:
				var py: float = (peak_h + 3000.0) if phase2 == 1 \
					else (Sim.height_at(behind.x, behind.z) + 60.0)
				player.global_position = Vector3(behind.x, py, behind.z)
				_reset_interp(player)
				sh.vls_cd = 0.0
				var before2 := get_tree().get_nodes_in_group("missiles").size()
				if sh._pick_air() == player:
					sh.fire_vls(player)
				var shots2: int = get_tree().get_nodes_in_group("missiles").size() - before2
				if phase2 == 0:
					ship_masked = shots2
				else:
					ship_clear = shots2
			print("[mask] ship at %s, ridge %.0f m at %.1f km inland, player %.1f km beyond it" % [
				str(Vector2(sea.x, sea.z).round()), peak_h, peak_t * 0.001, 3.0])
			print("[mask] ship launches: player behind the ridge=%d (expect 0), above it=%d (expect 1)" % [
				ship_masked, ship_clear])
			# And a round already in the air: duck behind the ridge and it should
			# lose the track rather than fly through the hill. Built on its own
			# rather than borrowed from the engagement above — the rounds fired
			# there go off almost immediately at these ranges, and a detonated
			# missile answers every question with whatever it last held.
			var probe := Missile.new()
			# Low, and close in on the seaward side: a round at five thousand
			# metres looks down over a ridge and is not masked by it at all,
			# which is correct and makes for a useless test.
			var launch_at := Vector3(peak.x + 2400.0, peak_h - 450.0, peak.z)
			player.global_position = Vector3(behind.x, peak_h + 3000.0, behind.z)
			_reset_interp(player)
			var pdir := (player.global_position - launch_at).normalized()
			probe.launch("sm2", Transform3D(Basis.looking_at(pdir, Vector3.UP), launch_at),
				pdir * 300.0, null, player)
			add_child(probe)
			for _i in 48:                      # kept short: it is under boost
				probe._physics_process(1.0 / 120.0)
			var probe_before: bool = probe.target == player
			# now down behind the ridge
			player.global_position = Vector3(behind.x,
				Sim.height_at(behind.x, behind.z) + 60.0, behind.z)
			_reset_interp(player)
			for _i in 300:
				if probe.dead:
					break
				probe._physics_process(1.0 / 120.0)
			var probe_after: bool = probe.target == player
			mask_seeker_ok = probe_before and not probe_after and not probe.dead
			print("[mask] seeker: holding with a clear line=%s, still holding once masked=%s (round %.0f m up, its line to you clear=%s, detonated=%s)" % [
				str(probe_before), str(probe_after), probe.global_position.y,
				str(Sim.line_of_sight(probe.global_position, player.global_position)),
				str(probe.dead)])
			if is_instance_valid(probe):
				probe.queue_free()
			print("[mask] RESULT: %s" % ("ok" if not got_masked and got_clear \
				and not paint_masked and paint_clear \
				and fired_masked == 0 and fired_clear > 0 \
				and ship_masked == 0 and ship_clear > 0 \
				and mask_seeker_ok else "FAILED"))
			get_tree().quit()
	# Do the wingmen actually sit in the slot, and does the AI use the terrain.
	if _form_test:
		_form_t += delta
		if _form_t > 1.5 and _form_said == 0:
			_form_said = -1
			# Nothing to fight: the point of this test is the slot, not the
			# engagement, and a flight that splits for a bandit is measuring
			# how far apart two aeroplanes in a dogfight get.
			if is_instance_valid(player):
				player.global_position = Vector3(0.0, 9000.0, 62000.0)
				player.team = 9
				_reset_interp(player)
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
					v.cells_left = 0
			for g in get_tree().get_nodes_in_group("ground_targets"):
				if is_instance_valid(g):
					g.queue_free()
		if _form_t > 3.0:
			var step := int((_form_t - 3.0) / 15.0) + 1
			if step > maxi(_form_said, 0):
				_form_said = step
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or not is_instance_valid(a.leader):
						continue
					var want: Vector3 = a.leader.global_transform * a.slot
					var lcl: Vector3 = a.leader.global_transform.affine_inverse() \
						* a.global_position - a.slot
					print("[form] %6.1fs %-12s slot err %6.1f m form=%s st=%d  dx %+6.0f dy %+6.0f dz %+6.0f  thr %.2f rol %+.2f pit %+.2f  spd %3.0f/%3.0f" % [
						_form_t, a.name, a.global_position.distance_to(want),
						str(a.formating), a.state, lcl.x, lcl.y, lcl.z,
						a.throttle, a.in_roll, a.in_pitch,
						a.linear_velocity.length(), a.leader.linear_velocity.length()])
			# sample the settled error continuously, not just at the marks
			if _form_t > 40.0:      # after the rejoin: what it actually holds
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or not is_instance_valid(a.leader):
						continue
					# only while he is actually flying the slot: a wingman who
					# has broken off to attack something is not station keeping
					# badly, he is doing his job
					if not a.formating:
						continue
					var e: float = a.global_position.distance_to(
						a.leader.global_transform * a.slot)
					_form_sum += e
					_form_worst = maxf(_form_worst, e)
					_form_n += 1
			if _form_t > 75.0:
				_form_test = false
				var n_wings := 0
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a != null and is_instance_valid(a.leader):
						n_wings += 1
				var busy := 0
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a != null and is_instance_valid(a.leader) and not a.formating:
						busy += 1
				print("[form] RESULT: %d wingmen (%d off doing something else); while in the slot, over %d samples mean error %.1f m, worst %.1f m" % [
					n_wings, busy, _form_n, _form_sum / maxf(float(_form_n), 1.0),
					_form_worst])
				get_tree().quit()
	# Does the chat line take a message without the aeroplane flying itself.
	if _chat_test and is_instance_valid(player):
		_chat_t += delta
		if _chat_t > 1.5 and _chat_step == 0:
			_chat_step = 1
			_press(KEY_SLASH)
			print("[chat] after '/': typing=%s modal=%s" % [str(chat.typing),
				str(Sim.typing)])
		elif _chat_t > 2.0 and _chat_step == 1:
			_chat_step = 2
			# "wasd" is throttle, pitch and roll; here it has to be four letters
			var roll_before := player.in_roll
			var pitch_before := player.in_pitch
			for c in "wasd on the deck".to_utf8_buffer():
				_press(KEY_A, c)
			print("[chat] typed %d chars, draft=%s" % [chat.draft.length(), chat.draft])
			print("[chat] stick while typing: roll %+.2f -> %+.2f, pitch %+.2f -> %+.2f" % [
				roll_before, player.in_roll, pitch_before, player.in_pitch])
		elif _chat_t > 2.5 and _chat_step == 2:
			_chat_step = 3
			_press(KEY_ENTER)
			print("[chat] after enter: typing=%s, backlog=%d, last=%s" % [
				str(chat.typing), chat.log_lines.size(),
				String(chat.log_lines[-1]["text"]) if not chat.log_lines.is_empty() else "-"])
			print("[chat] RESULT: %s" % ("ok" if not chat.typing \
				and not chat.log_lines.is_empty() \
				and String(chat.log_lines[-1]["text"]) == "wasd on the deck" \
				else "FAILED"))
			get_tree().quit()
	# What the aeroplanes that are not fighters actually do: does the mud mover
	# find something on the ground, roll in on it and hurt it, and does the
	# transport get anywhere.
	if _cas_test:
		_cas_t += delta
		if _cas_t > 2.0 and _cas_hp.is_empty():
			# Its own scenario: the shipping is stood down so the movers are not
			# spending the whole run defending against naval SAMs, and the mud
			# is put where an aeroplane can get at it.
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
					v.cells_left = 0
			var seed_at := Vector3(2000.0, 0.0, -6000.0)
			for i in 4:
				var g := GroundTarget.new()
				g.team = 0
				g.setup(["sam", "radar", "fuel", "hangar"][i])
				add_child(g)
				var gp := seed_at + Vector3(float(i) * 260.0 - 400.0, 0, float(i) * 190.0)
				g.global_position = Vector3(gp.x, Sim.height_at(gp.x, gp.z), gp.z)
				g.name = "CAS target %d" % (i + 1)
			for n in get_tree().get_nodes_in_group("bandits"):
				var a := n as AIPlane
				if a == null or a.role != "cas":
					continue
				# put them fifteen kilometres out, pointed at the target area
				var start := seed_at + Vector3(-13000.0, 0, -7000.0 + float(a._runs) * 900.0)
				a.global_transform = Transform3D(Basis(),
					Vector3(start.x, Sim.height_at(start.x, start.z) + 3200.0, start.z))
				a.look_at_from_position(a.global_position, seed_at, Vector3.UP)
				a.linear_velocity = -a.global_transform.basis.z * 180.0
				_reset_interp(a)
			for n in get_tree().get_nodes_in_group("hittable"):
				if is_instance_valid(n) and not (n is Aircraft) and ("team" in n):
					_cas_hp[n.get_instance_id()] = [n, float(n.get("health"))]
			print("[cas] watching %d ground and surface targets" % _cas_hp.size())
		elif _cas_t > 2.0:
			var step := int(_cas_t / 12.0)
			if step > _cas_said:
				_cas_said = step
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or a.role == "fighter":
						continue
					var hr := -1.0
					if is_instance_valid(a.target):
						hr = Vector2(a.target.global_position.x - a.global_position.x,
							a.target.global_position.z - a.global_position.z).length()
					print("[cas] %6.1fs %-14s %-9s st=%d runs=%d alt %5.0f rng %6.0f spd %3.0f pit %+.2f rol %+.2f aoa %+4.1f stall=%s gun %d near %.0f ang %.1f tgt=%s" % [
						_cas_t, a.name, a.role, a.state, a._runs,
						a.global_position.y, hr, a.linear_velocity.length(),
						a.in_pitch, a.in_roll, rad_to_deg(a.aoa), str(a.stalling), a.ammo,
						a.min_slant, a.min_ang,
						String(a.target.name) if is_instance_valid(a.target) else "none"])
			if _cas_t > 150.0:
				_cas_test = false
				var hurt := 0
				var killed := 0
				for k in _cas_hp:
					var e: Array = _cas_hp[k]
					if not is_instance_valid(e[0]):
						killed += 1
					elif float(e[0].get("health")) < float(e[1]) - 0.5:
						hurt += 1
				var movers := 0
				var hauls := 0
				for n in get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null:
						continue
					if a.role == "cas":
						movers += 1
						print("[cas] RESULT: %s made %d attack runs, %d rounds left; closest %.0f m, best nose-on %.1f deg" % [
							a.name, a._runs, a.ammo, a.min_slant, a.min_ang])
					elif a.role == "transport":
						hauls += 1
						print("[cas] RESULT: %s on leg %d at %.0f m, %.0f m agl" % [
							a.name, a._leg, a.global_position.y, a.agl])
				print("[cas] RESULT: %d movers and %d transports still up; %d targets damaged, %d destroyed" % [
					movers, hauls, hurt, killed])
				get_tree().quit()
	# One ship hurt on purpose, then left alone to see if the party save her.
	if _dc_test:
		_dc_t += delta
		if _dc_t > 1.5 and not is_instance_valid(_dc_ship):
			# nobody fights: this is about the party, not the enemy
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null:
					continue
				if v.kind == "destroyer" and _dc_ship == null:
					_dc_ship = v          # she keeps her captain
				else:
					v.ai = false          # nobody else fights, or moves
					v.telegraph = 0.0
					v.speed = 0.0
			if _dc_ship == null:
				print("[dc] no destroyer")
				_dc_test = false
				return
			_dc_ship.set("telegraph", 1.0)
			print("[dc] %s hull %.0f, full ahead" % [_dc_ship.call("display_name"),
				_dc_ship.get("health")])
		elif is_instance_valid(_dc_ship) and _dc_t > 3.0 and _dc_said == 0:
			_dc_said = 1
			_dc_ship.call("take_hit", 620.0, null)
			_dc_ship.call("take_hit", 380.0, null)
			print("[dc] two hits for 1000 of 2200: %s" % _dc_ship.call("damage_report"))
		elif is_instance_valid(_dc_ship) and _dc_t > 3.0:
			var step := int((_dc_t - 3.0) / 12.0) + 1
			if step > _dc_said and step <= 10:
				_dc_said = step
				print("[dc] %6.1fs  %s  spd %4.1f  list %4.1f deg" % [
					_dc_t, _dc_ship.call("damage_report"), _dc_ship.get("speed"),
					rad_to_deg(float(_dc_ship.get("list_ang")))])
			if _dc_t > 132.0:
				_dc_test = false
				print("[dc] RESULT: hull %.0f, %s" % [_dc_ship.get("health"),
					"afloat" if bool(_dc_ship.get("alive")) else "sunk"])
				get_tree().quit()
	if _trig_test and is_instance_valid(player):
		_trig_t += delta
		if _trig_t > 2.5:
			_trig_test = false
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			player.set_weapon(maxi(player.weapon_types.find("aim120"), 0))
			player.locked = true
			# right click must NOT launch anything: it is the sensor page now
			var n0 := player.count_remaining("aim120")
			player.fire_cd = 0.0
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_RIGHT
			ev.pressed = true
			_shell_input(ev)
			player._pilot(0.016)
			var n1 := player.count_remaining("aim120")
			var opened: bool = pod.active
			if pod.active:
				pod.toggle()
				pod.set_fullscreen(false)
			print("[trigger] right click opened the sensor page: %s" % str(opened))
			# and with the map up, a click must do nothing to the weapons
			map.visible = true
			Sim.ui_modal = true
			var nm0 := player.count_remaining("aim120")
			player.fire_cd = 0.0
			Input.action_press(&"fire")
			player._pilot(0.016)
			Input.action_release(&"fire")
			var ev2 := InputEventMouseButton.new()
			ev2.button_index = MOUSE_BUTTON_RIGHT
			ev2.pressed = true
			_shell_input(ev2)
			print("[trigger] with the map up: fired=%s, sensor toggled=%s" % [
				str(player.count_remaining("aim120") < nm0), str(pod.active)])
			map.visible = false
			Sim.ui_modal = false
			# left click must
			player.fire_cd = 0.0
			Input.action_press(&"fire")
			player._pilot(0.016)
			Input.action_release(&"fire")
			var n2 := player.count_remaining("aim120")
			print("[trigger] stores %d -> right click %d -> left click %d  (right fired=%s, left fired=%s)" % [
				n0, n1, n2, str(n1 < n0), str(n2 < n1)])
			get_tree().quit()
	if _seam_test:
		_seam_test = false
		# T junction cracks: at a ring boundary the fine chunk has a vertex the
		# coarse one does not, and the coarse edge runs straight past it. The
		# gap is the height difference between that vertex and the straight
		# line, and it needs no rendering to measure.
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		var tbl: Array = Terrain.ring_table()
		for li in tbl.size() - 1:
			var fine: Dictionary = tbl[li]
			var cell: float = fine["cell"]
			var edge: float = fine["coverage"]     # where this ring ends
			# walk the boundary and compare the fine midpoints with the coarse chord
			var steps := int(edge * 2.0 / (cell * 2.0))
			for k in range(-steps, steps):
				var a0 := float(k) * cell * 2.0
				var a1 := a0 + cell * 2.0
				var mid := (a0 + a1) * 0.5
				for side in [edge, -edge]:
					var h0 := Sim.height_at(a0, side)
					var h1 := Sim.height_at(a1, side)
					var hm := Sim.height_at(mid, side)
					var gap: float = absf(hm - (h0 + h1) * 0.5)
					worst = maxf(worst, gap)
					sum += gap
					cnt += 1
					h0 = Sim.height_at(side, a0)
					h1 = Sim.height_at(side, a1)
					hm = Sim.height_at(side, mid)
					gap = absf(hm - (h0 + h1) * 0.5)
					worst = maxf(worst, gap)
					sum += gap
					cnt += 1
		print("[seam] T junction gaps across %d ring boundaries: mean %.2f m, worst %.2f m over %d samples" % [
			tbl.size() - 1, sum / maxf(float(cnt), 1.0), worst, cnt])
		get_tree().quit()
	if _laser_test and is_instance_valid(player):
		_laser_t += delta
		if _laser_t > 2.5:
			_laser_test = false
			pod.toggle()
			pod.set_fullscreen(true)
			pod.pitch = -0.5
			pod.toggle_laser()
			pod._process(0.016)
			var lit: bool = pod._beam != null and pod._beam.visible
			# lock something, then leave the page
			pod.designate()
			var mode1: int = pod.mode
			var trk = pod.tracked
			pod.toggle()
			pod._process(0.016)
			var lit_after: bool = pod._beam != null and pod._beam.visible
			var des2: bool = player.designated != Vector3.INF
			# and come back to it
			pod.toggle()
			pod._process(0.016)
			print("[laser] lit while up=%s; after closing: beam visible=%s, designation held=%s" % [
				str(lit), str(lit_after), str(des2)])
			print("[laser] track mode before=%d after reopening=%d (%s), tracked kept=%s" % [
				mode1, pod.mode, "PRESERVED" if pod.mode == mode1 else "LOST",
				str(pod.tracked == trk)])
			get_tree().quit()
	if _hud_test and is_instance_valid(player) and cam:
		_hud_t += delta
		if _hud_t > 2.5:
			_hud_test = false
			cam.mode = {"cockpit": 0, "chase": 1, "orbit": 2}.get(_hud_view, 0)
			# let the gate run one more frame with the new mode
			hud.flight_page = (cam.mode == ChaseCamera.Mode.COCKPIT)
			print("[hud] view=%s -> flight page drawn: %s" % [_hud_view, str(hud.flight_page)])
			get_tree().quit()
	if _fire_test and is_instance_valid(player):
		_fire_t += delta
		if _fire_t > 2.0:
			_fire_test = false
			var p2 := player
			# (1) a radar round with nothing locked must still leave the rail
			p2.target = null
			p2.locked = false
			p2.set_bays(true)
			p2.bays[p2.bays.keys()[0]]["anim"] = 1.0
			for k in p2.bays:
				p2.bays[k]["anim"] = 1.0
				p2.bays[k]["open"] = true
			p2.set_weapon(maxi(p2.weapon_types.find("aim120"), 0))
			p2.fire_cd = 0.0
			var n0 := p2.count_remaining("aim120")
			var r1: String = p2.fire()
			var n1 := p2.count_remaining("aim120")
			print("[fire] unlocked radar shot: result=%s, stores %d -> %d (%s)" % [
				"away" if r1 == "" else r1, n0, n1,
				"LAUNCHED" if n1 < n0 else "REFUSED"])
			# (2) ask for a shot with the doors shut, then change your mind
			for k in p2.bays:
				if String(p2.bays[k]["kind"]) == "internal":
					p2.bays[k]["anim"] = 0.0
					p2.bays[k]["open"] = false
			p2.fire_cd = 0.0
			p2.set_weapon(maxi(p2.weapon_types.find("aim120"), 0))
			var before := p2.count_remaining("aim9")
			var r2: String = p2.fire()
			var queued: bool = p2._pending_fire
			p2.set_weapon(maxi(p2.weapon_types.find("aim9"), 0))
			var still: bool = p2._pending_fire
			# let the doors finish and see whether anything goes off by itself
			for k in p2.bays:
				p2.bays[k]["anim"] = 1.0
				p2.bays[k]["open"] = true
			p2.fire_cd = 0.0
			var after := p2.count_remaining("aim9")
			print("[fire] queued behind doors: %s -> queued=%s; after switching queued=%s; aim9 %d -> %d (%s)" % [
				"waiting" if r2 != "" else "away", str(queued), str(still), before, after,
				"CANCELLED" if not still and after == before else "STILL ARMED"])
			get_tree().quit()
	if _view_test and is_instance_valid(player) and cam:
		_view_t += delta
		if _view_t > 2.0:
			_view_test = false
			# Anything in the cockpit that reaches above the eye line and sits
			# ahead of it is in the way. Measured off the meshes rather than by
			# raycast: the furniture is decoration and carries no collider.
			var eye: Vector3 = player.cockpit_offset()
			var worst := -9.0
			var worst_nm := "-"
			var n_above := 0
			for part in player._model.get("cockpit_parts", []):
				var mi := part as MeshInstance3D
				if not is_instance_valid(mi):
					continue
				var ab: AABB = mi.transform * mi.get_aabb()
				# only what is forward of the eye, where the view is
				if ab.position.z > eye.z:
					continue
				if ab.end.y > worst:
					worst = ab.end.y
					worst_nm = str(mi.name)
				if ab.end.y > eye.y:
					n_above += 1
			print("[view] %s: eye y=%.2f, highest forward furniture %.2f (%s), %d parts above the eye line" % [
				str(player.spec["name"]), eye.y, worst, worst_nm, n_above])
			# and the glazing: a bubble stands proud of the spine, a flight deck
			# window follows it
			var cnode: Node = player._model["root"].find_child("Canopy", true, false)
			if cnode == null:
				cnode = player._model["root"].find_child("CanopyHinge", true, false)
			if cnode != null:
				var mi2 := cnode as MeshInstance3D
				if mi2 == null:
					for c in (cnode as Node).get_children():
						if c is MeshInstance3D:
							mi2 = c
							break
				if mi2 != null:
					var gab: AABB = player.global_transform.affine_inverse() \
						* (mi2.global_transform * mi2.get_aabb())
					var secs: Array = player.spec["shape"]["sections"]
					var zc: float = gab.position.z + gab.size.z * 0.5
					var top := -9.0
					for i in secs.size() - 1:
						if zc >= minf(secs[i][0], secs[i+1][0]) and zc <= maxf(secs[i][0], secs[i+1][0]):
							var f: float = (zc - secs[i][0]) / maxf(secs[i+1][0] - secs[i][0], 0.001)
							top = lerpf(secs[i][2] + secs[i][3], secs[i+1][2] + secs[i+1][3], f)
							break
					print("[view]   glazing top y=%.2f, fuselage top y=%.2f -> %s" % [
						gab.end.y, top,
						"stands %.2f m proud (bubble)" % (gab.end.y - top) if gab.end.y > top + 0.05
						else "flush with the nose (flight deck)"])
			get_tree().quit()
	if _lock_test and is_instance_valid(player):
		_lock_t += delta
		if _lock_t > 2.0:
			_lock_test = false
			# The key path, not just the lock logic: an action that is unbound,
			# or a typing gate stuck open, stops T dead however well
			# cycle_target works when called directly.
			var evs := InputMap.action_get_events(&"cycle_target")
			var names := PackedStringArray()
			for ev in evs:
				names.append(ev.as_text())
			print("[lock] T path: action exists=%s bound to [%s]; Sim.typing=%s; chat open=%s" % [
				str(InputMap.has_action(&"cycle_target")), ", ".join(names),
				str(Sim.typing), str(is_instance_valid(chat) and chat.typing)])
			print("[lock] Sim.tapped would return %s (it is gated on typing)" % [
				str(not Sim.typing)])
			# and the whole path for real: a T event through Godot's own input
			# system, which is what `Input.is_action_just_pressed` reads
			# Press it repeatedly: acquiring once is not cycling.
			player.target = null
			player.lock_presses_seen = 0
			for press in 12:
				var kd := InputEventKey.new()
				kd.physical_keycode = KEY_T
				kd.keycode = KEY_T
				kd.pressed = true
				Input.parse_input_event(kd)
				# A whole frame between press and release, and more between
				# presses: a person cannot press T twice inside one frame, and
				# `parse_input_event` batches per frame, so doing it faster
				# measures the queue rather than the game.
				await get_tree().process_frame
				await get_tree().process_frame
				var ku := InputEventKey.new()
				ku.physical_keycode = KEY_T
				ku.keycode = KEY_T
				ku.pressed = false
				Input.parse_input_event(ku)
				await get_tree().process_frame
				await get_tree().process_frame
				pass
			var shipnames := PackedStringArray()
			for shn in get_tree().get_nodes_in_group("ships"):
				shipnames.append("%s(%s)" % [String(shn.name),
					String(shn.call("display_name")) if shn.has_method("display_name")
					else "?"])
			print("[lock] ship node names: %s" % ", ".join(shipnames))
			print("[lock] RELIABILITY: 12 presses sent, %d reached the handler" % [
				player.lock_presses_seen])
			player.target = null
			var down := InputEventKey.new()
			down.physical_keycode = KEY_T
			down.keycode = KEY_T
			down.pressed = true
			Input.parse_input_event(down)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var up := InputEventKey.new()
			up.physical_keycode = KEY_T
			up.keycode = KEY_T
			up.pressed = false
			Input.parse_input_event(up)
			if is_instance_valid(player.target):
				var gs := PackedStringArray()
				for g in player.target.get_groups():
					gs.append(String(g))
				print("[lock] after a real T press: target=%s  class=%s  groups=[%s]  team=%s" % [
					String(player.target.name), player.target.get_class(),
					", ".join(gs),
					str(player.target.get("team")) if "team" in player.target else "none"])
			else:
				print("[lock] after a real T press: NONE")
			var ships := get_tree().get_nodes_in_group("ships")
			var tgt: Node3D = null
			for sh in ships:
				if is_instance_valid(sh) and (sh as Ship).team != 0:
					tgt = sh
					break
			if tgt == null:
				print("[lock] no hostile shipping found")
				get_tree().quit()
				return
			# sit the aeroplane off the target and try to lock it
			player.global_transform = Transform3D(Basis(),
				tgt.global_position + Vector3(0, 2000, 9000))
			player.linear_velocity = Vector3(0, 0, -240.0)
			player.target = null
			# with a BOMB selected, which is how you would attack a ship
			player.selected = maxi(player.weapon_types.find("gbu32"), 0)
			player.cycle_target()
			var got := "nothing"
			if player.target != null and is_instance_valid(player.target):
				got = "%s at %.1f km" % [str(player.target.name),
					player.global_position.distance_to(player.target.global_position) * 0.001]
			print("[lock] weapon=%s" % player.weapon_label(player.current_weapon()))
			# would the HUD actually draw a box on it?
			var d2: float = player.global_position.distance_to(tgt.global_position)
			var in_reach: bool = d2 <= maxf(Sim.radar_range(), 26000.0)
			var los: bool = hud._los_clear(player.global_position, tgt.global_position)
			# and a contact deliberately put behind a hill
			var hill := Vector3(2600.0, 0, 4200.0)
			hill.y = Sim.height_at(hill.x, hill.z) - 30.0
			var blocked: bool = hud._los_clear(
				Vector3(hill.x, hill.y + 5.0, hill.z + 4000.0), hill)
			print("[lock] box drawn: in radar reach=%s (%.1f km, radar %.0f km), line of sight=%s; a target dug in behind terrain reads clear=%s" % [
				str(in_reach), d2 * 0.001, Sim.radar_range() * 0.001, str(los), str(blocked)])
			print("[lock] %d ships in the world; nearest hostile %s at %.1f km; cycle_target picked %s" % [
				ships.size(), tgt.display_name(),
				player.global_position.distance_to(tgt.global_position) * 0.001, got])
			print("[lock]   ship groups: hittable=%s team=%d alive=%s" % [
				str(tgt.is_in_group("hittable")), tgt.team, str(tgt.is_alive())])
			get_tree().quit()
	if _flap_test and is_instance_valid(player):
		_flap_t += delta
		if _flap_t < 3.0:
			player.flaps = 1.0
		elif _flap_t >= 3.0:
			_flap_test = false
			var fl: Array = player._model.get("flaps", [])
			var out := []
			for f in fl:
				var n := f as Node3D
				# a point on the trailing edge of each flap, in body coordinates
				var tip: Vector3 = player.global_transform.affine_inverse() \
					* (n.global_transform * Vector3(0.0, 0.0, 0.9))
				out.append("x=%+.2f dy=%+.3f" % [n.position.x, tip.y - n.position.y])
			print("[flap] %s flaps at full: %s" % [str(player.spec["name"]), ", ".join(out)])
			get_tree().quit()
	if _sea_test:
		_sea_test = false
		var deep := 0
		var total := 0
		var lo := 1e9
		for gx in range(0, 14):
			var line := ""
			for gz in range(-6, 7):
				var x := 12000.0 + float(gx) * 4000.0
				var z := float(gz) * 6000.0
				var hh := Sim.height_at(x, z)
				lo = minf(lo, hh)
				total += 1
				if hh < Sim.WATER_LEVEL - 15.0:
					deep += 1
					line += "~"
				else:
					line += "#"
			print("[sea] x=%6.0f  %s" % [12000.0 + float(gx) * 4000.0, line])
		print("[sea] %d of %d sample points are deep water; lowest %.0f m (sea level %.0f)" % [
			deep, total, lo, Sim.WATER_LEVEL])
		get_tree().quit()
	if _sub_test:
		_sub_t += delta
		if _sub_t > 2.0 and _sub_aim == Vector3.ZERO:
			var want := Vector3.ZERO
			var best := 0
			for cx in range(-12, 13):
				for cz in range(-12, 13):
					var q := Vector3(float(cx) * 900.0, 0.0, float(cz) * 900.0)
					var c := scenery.count_standing(q, 400.0)
					if c > best:
						best = c
						want = q
			want.y = Sim.height_at(want.x, want.z)
			_sub_aim = want
			_sub_before = scenery.count_standing(want, 3000.0)
			var boat: Ship = null
			for sh in get_tree().get_nodes_in_group("ships"):
				if is_instance_valid(sh) and (sh as Ship).can_launch():
					boat = sh
					break
			if boat == null:
				print("[sub] no boat able to launch")
				_sub_test = false
				return
			print("[sub] %s launching at %s, %d structures standing within 3 km" % [
				boat.display_name(), str(want.round()), _sub_before])
			boat.launch_strategic(want)
		elif _sub_t > 90.0 or (_sub_t > 12.0
				and get_tree().get_nodes_in_group("missiles").is_empty()):
			_sub_test = false
			var after := scenery.count_standing(_sub_aim, 3000.0)
			print("[sub] RESULT: %d of %d structures within 3 km destroyed" % [
				_sub_before - after, _sub_before])
			get_tree().quit()
	if _fleet_test:
		_fleet_t += delta
		var ships := get_tree().get_nodes_in_group("ships")
		if _fleet_t > 2.0 and _fleet_p0 == Vector3.ZERO and not ships.is_empty():
			_fleet_p0 = (ships[0] as Node3D).global_position
		elif _fleet_t > 14.0:
			_fleet_test = false
			var moved := 0.0
			var afloat := 0
			var lo := 1e9
			var hi := -1e9
			for sh in ships:
				if not is_instance_valid(sh):
					continue
				afloat += 1
				lo = minf(lo, (sh as Node3D).global_position.y)
				hi = maxf(hi, (sh as Node3D).global_position.y)
			if not ships.is_empty():
				moved = (ships[0] as Node3D).global_position.distance_to(_fleet_p0)
			print("[fleet] %d vessels, %d in the water group; lead ship made %.0f m; hull y from %.1f to %.1f (sea level %.1f)" % [
				fleet_count, afloat, moved, lo, hi, Sim.WATER_LEVEL])
			get_tree().quit()
	if _pod_test and is_instance_valid(player):
		_pod_t += delta
		if _pod_t > 2.0 and not pod.active:
			pod.toggle()
			pod.set_fullscreen(true)
			if _pod_want >= 0:
				while pod.channel != _pod_want:
					pod.cycle_channel()
				print("[pod] channel forced to %s" % SensorPod.CHANNEL_NAMES[pod.channel])
		elif _pod_t > 4.0 and _shot == "":
			_pod_test = false
			var tex_behind: bool = pod._tex.show_behind_parent
			# how many radar contacts the pod page would box
			var boxed := 0
			var reach: float = maxf(Sim.radar_range(), 26000.0)
			for n in get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == player or not (n is Node3D):
					continue
				if n.has_method("is_alive") and not n.is_alive():
					continue
				var wp: Vector3 = (n as Node3D).global_position
				if player.global_position.distance_to(wp) > reach:
					continue
				if pod._cam.is_position_behind(wp):
					continue
				var sp: Vector2 = pod._cam.unproject_position(wp)
				if sp.x > 4.0 and sp.y > 4.0 and sp.x < pod.size.x - 4.0 and sp.y < pod.size.y - 4.0:
					boxed += 1
			print("[pod] contacts boxed on the sensor page: %d; head AZ %+.0f EL %+.0f" % [
				boxed, rad_to_deg(pod.yaw), rad_to_deg(pod.pitch)])
			var mp = (pod._tex.material as ShaderMaterial).get_shader_parameter("channel")
			print("[pod] shader channel param = %s (pod.channel=%d)" % [str(mp), pod.channel])
			var ho: Vector3 = player.global_transform.affine_inverse() * pod._head_origin()
			var secs: Array = player.spec["shape"]["sections"]
			var bot := 0.0
			for i in secs.size() - 1:
				if -1.8 >= minf(secs[i][0], secs[i+1][0]) and -1.8 <= maxf(secs[i][0], secs[i+1][0]):
					var f: float = (-1.8 - secs[i][0]) / maxf(secs[i+1][0] - secs[i][0], 0.001)
					bot = lerpf(secs[i][3], secs[i+1][3], f) - lerpf(secs[i][2], secs[i+1][2], f)
					break
			print("[pod] head at %s, hull bottom y=%.2f -> %s the fuselage" % [
				str(ho.snapped(Vector3.ONE * 0.01)), bot,
				"CLEAR of" if ho.y < bot else "INSIDE"])
			print("[pod] active=%s fullscreen=%s size=%s picture behind overlay=%s channel=%s" % [
				str(pod.active), str(pod.fullscreen), str(pod.size), str(tex_behind),
				SensorPod.CHANNEL_NAMES[pod.channel]])
			get_tree().quit()
	if _aim_test and is_instance_valid(walker) and is_instance_valid(walker.body):
		_aim_t += delta
		if _aim_t > 2.0:
			_aim_test = false
			var body: Pilot = walker.body
			var worst := Vector2.ZERO
			var worst_at := 0.0
			for i in 37:
				var pitch := deg_to_rad(lerpf(-80.0, 80.0, float(i) / 36.0))
				body.pose_aim(pitch)
				body.force_update_transform()
				for c in body.find_children("*", "Node3D", true, false):
					(c as Node3D).force_update_transform()
				var e: Vector2 = body.grip_error()
				if e.x + e.y > worst.x + worst.y:
					worst = e
					worst_at = rad_to_deg(pitch)
			print("[aim] worst hand-to-grip error: right %.3f m, left %.3f m at %.0f deg pitch" % [
				worst.x, worst.y, worst_at])
			var zr := -9.0
			var zl := -9.0
			var yr := 9.0
			var yl := 9.0
			for i2 in 37:
				var pit := deg_to_rad(lerpf(-80.0, 80.0, float(i2) / 36.0))
				body.pose_aim(pit)
				body.force_update_transform()
				for c in body.find_children("*", "Node3D", true, false):
					(c as Node3D).force_update_transform()
				var eb: Array = body.elbow_pos()
				zr = maxf(zr, (eb[0] as Vector3).z)
				zl = maxf(zl, (eb[1] as Vector3).z)
				yr = minf(yr, (eb[0] as Vector3).y)
				yl = minf(yl, (eb[1] as Vector3).y)
			# torso half-depth is 0.12, so anything past that is outside the body
			print("[aim] elbow worst aft: right %+.2f, left %+.2f (torso back at +0.12); lowest y right %.2f left %.2f" % [
				zr, zl, yr, yl])
			get_tree().quit()
	if _seat_test and is_instance_valid(player) and is_instance_valid(pilot):
		_seat_t += delta
		# only once he is actually down on the pan, not part way down the rail
		if _seat_t > 1.0 and pilot.global_position.distance_to(_board_seat) < 0.02:
			_seat_test = false
			var inv := player.global_transform.affine_inverse()
			var seat: Vector3 = player.seat_offset()
			var hips_l: Vector3 = inv * pilot.hips.global_position
			var head_l: Vector3 = inv * pilot.head.global_position
			# the un-cut fuselage top at this station, from the raw section data
			var secs: Array = player.spec["shape"]["sections"]
			var top := -9.0
			for i in secs.size() - 1:
				var z0: float = secs[i][0]
				var z1: float = secs[i + 1][0]
				if seat.z >= minf(z0, z1) and seat.z <= maxf(z0, z1):
					var f: float = (seat.z - z0) / maxf(z1 - z0, 0.001)
					top = lerpf(float(secs[i][2]) + float(secs[i][3]),
						float(secs[i + 1][2]) + float(secs[i + 1][3]), f)
			print("[seat] %s: pan y=%.2f  hips y=%.2f  head y=%.2f  skin top y=%.2f  -> hips %s skin, head %+.2f above" % [
				str(player.spec["name"]), seat.y, hips_l.y, head_l.y, top,
				"BELOW" if hips_l.y < top else "ABOVE", head_l.y - top])
			get_tree().quit()
	if _key_test != "" and is_instance_valid(tank):
		_key_t += delta
		if _key_t > 3.0:
			var kind := tank.kind
			# M must still open the map from the driver's seat: that is how a
			# fire mission is designated
			var ev := InputEventKey.new()
			ev.physical_keycode = KEY_M
			ev.pressed = true
			_shell_input(ev)
			var map_open: bool = map.visible
			_shell_input(ev)                     # and close it again
			# right click with freelook held must NOT raise the sensor camera
			Input.action_press(&"freelook")
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_RIGHT
			mb.pressed = true
			_shell_input(mb)
			Input.action_release(&"freelook")
			# the side panels and radar range are on the same handler
			var before: int = Sim.panel_left
			var pv := InputEventKey.new()
			pv.physical_keycode = KEY_BRACKETLEFT
			pv.pressed = true
			_shell_input(pv)
			# left click must fire, and weapon select must swap main/coax
			var w0: String = tank.current_weapon()
			tank.cycle_weapon()
			var w1: String = tank.current_weapon()
			tank.set_weapon(0)
			var r_before: int = tank.rounds_left
			var cd0: float = tank._gun_cd
			Input.action_press(&"fire")
			tank._drive_input(0.016)
			Input.action_release(&"fire")
			var lc_fired: bool = tank.rounds_left < r_before or tank._gun_cd > cd0
			print("[keys] %s: weapons %s -> cycle gives %s; left click fired=%s" % [
				kind, w0, w1, str(lc_fired)])
			# and the sensor chord must not pull the trigger
			var rounds_before: int = tank.rounds_left
			var cd_before: float = tank._gun_cd
			Input.action_press(&"freelook")
			Input.action_press(&"fire")
			tank._drive_input(0.016)
			Input.action_release(&"fire")
			Input.action_release(&"freelook")
			var fired: bool = tank.rounds_left < rounds_before or tank._gun_cd > cd_before
			print("[keys] %s: M opens map=%s, pod stayed shut=%s, [ cycled panel=%s, chord fired gun=%s" % [
				kind, str(map_open), str(not pod.active), str(Sim.panel_left != before),
				str(fired)])
			_key_test = ""
			get_tree().quit()
	if _tvc_test > 0.0 and is_instance_valid(player):
		_tvc_t += delta
		if _tvc_t < 0.05:
			player.global_transform = Transform3D(Basis(), Vector3(0, 3000, 12000))
			player.linear_velocity = Vector3(0, 0, -_tvc_test)
			player.gear_down = false
			player.gear_anim = 0.0
			player.auto = "wait"
			player.throttle = 1.0
			player.power = 1.0
		elif _tvc_t < 4.0:
			# full aft stick at low speed: what can the aeroplane still do?
			player.in_pitch = 1.0
			player.throttle = 1.0
			var q: float = player.angular_velocity.dot(player.global_transform.basis.x)
			_tvc_peak = maxf(_tvc_peak, q)
			_tvc_aoa = maxf(_tvc_aoa, rad_to_deg(player.aoa))
			_tvc_defl = maxf(_tvc_defl, rad_to_deg(absf(player.nozzle_pitch)))
		else:
			var pivots: Array = player._nozzles
			var pv_deg := 0.0
			for pv in pivots:
				if is_instance_valid(pv):
					pv_deg = maxf(pv_deg, rad_to_deg(absf((pv as Node3D).rotation.x)))
			print("[tvc] %-20s at %3.0f m/s: peak pitch rate %5.1f deg/s, max AoA %5.1f, nozzle %4.1f deg, %d pivots at %4.1f deg" % [
				str(player.spec["name"]), _tvc_test,
				rad_to_deg(_tvc_peak), _tvc_aoa, _tvc_defl, pivots.size(), pv_deg])
			_tvc_test = 0.0
			get_tree().quit()
	if _board_test and is_instance_valid(walker):
		_boardtest_t += delta
		if _boardtest_t > 3.0:
			_board_test = false
			var ok := 0
			var miss := 0
			for n in get_tree().get_nodes_in_group("boardable"):
				if not is_instance_valid(n) or not n.has_method("hull_distance"):
					continue
				# stand two metres off the left flank of this machine
				var half: float = maxf(absf(n.bounds.position.x), absf(n.bounds.end.x))
				var spot: Vector3 = n.global_transform * Vector3(-(half + 2.0), 0, 0)
				walker.position = Vector3(spot.x, Sim.height_at(spot.x, spot.z), spot.z)
				walker._scan()
				var got = walker.target_jet
				var want_nm := _label_of(n)
				var got_nm := _label_of(got) if got != null else "nothing"
				if got == n:
					ok += 1
				else:
					miss += 1
					print("[board]  standing at %s but offered %s" % [want_nm, got_nm])
			print("[board] %d correct, %d wrong" % [ok, miss])
			get_tree().quit()
	if _jolt_test and is_instance_valid(player) and cam:
		_jolt_t += delta
		if _jolt_t < 1.0:
			player.auto = "tumble"
		# where the camera sits in the aircraft's own frame, as rendered. A rig
		# that is solid on the airframe holds this constant however hard the jet
		# manoeuvres; anything else is the jolt the pilot sees.
		cam.diag = true
		var axf: Transform3D = player.get_global_transform_interpolated()
		var loc: Vector3 = axf.affine_inverse() * cam.global_position
		if _jolt_t > 2.0:
			_jolt_gmin = minf(_jolt_gmin, player.g_load)
			_jolt_gmax = maxf(_jolt_gmax, player.g_load)
		if _jolt_prev != Vector3.ZERO and _jolt_t > 2.0:
			var d: float = (loc - _jolt_prev).length()
			_jolt_n += 1
			_jolt_sum += d
			if d > _jolt_worst:
				_jolt_worst = d
				_jolt_when = _jolt_t
		_jolt_prev = loc
		if _jolt_t > 14.0:
			_jolt_test = false
			print("[jolt] %s: boom %.2f m, mean step %.4f m, worst %.4f m at t=%.1f over %d frames, ground-clamped %d, agl %.0f" % [
				str(player.spec["name"]), loc.length(),
				_jolt_sum / maxf(float(_jolt_n), 1.0), _jolt_worst, _jolt_when, _jolt_n,
				cam.clamped_frames, player.agl])
			print("[jolt]   worst camera roll step %.2f deg at t=%.1f" % [
				cam.worst_roll, cam.worst_roll_t])
			print("[jolt]   g through the tumble: min %+.2f max %+.2f, grey-out %.0f%% red-out %.0f%%" % [
				_jolt_gmin, _jolt_gmax, player.g_strain * 100.0, player.g_red * 100.0])
			get_tree().quit()
	if _overlap_test:
		_overlap_t += delta
		if _overlap_t > 14.0:
			_overlap_test = false
			# Real world-space footprints, not circles round an origin: a
			# transport is far longer than it is wide and it is parked across
			# the apron, so a radius from the wingspan says nothing useful.
			var items: Array = []
			var seen := {}
			for grp in ["vehicles", "hittable", "ground_targets"]:
				for n in get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n) or not (n is Node3D):
						continue
					if seen.has(n.get_instance_id()):
						continue      # a tank is in "vehicles" AND "hittable"
					seen[n.get_instance_id()] = true
					var box := _footprint(n as Node3D)
					if box != Rect2():
						items.append([_label_of(n), box])
			# every aircraft in the tree, group membership or not
			for n in get_tree().get_root().find_children("*", "Node3D", true, false):
				var a := n as Node3D
				if not is_instance_valid(a) or not ("spec" in a):
					continue
				var sp = a.get("spec")
				if not (sp is Dictionary) or not (sp as Dictionary).has("name"):
					continue
				print("[aircraft] %-24s at %s  boardable=%s hittable=%s parent=%s" % [
					String((sp as Dictionary)["name"]), str(a.global_position.round()),
					str(a.is_in_group("boardable")), str(a.is_in_group("hittable")),
					str(a.get_parent().name)])
			print("[overlap] %d bodies on the ramp" % items.size())
			for it in items:
				var rr: Rect2 = it[1]
				print("[overlap]   %-28s centre (%7.1f,%8.1f) size %5.1f x %5.1f" % [
					it[0], rr.position.x + rr.size.x * 0.5,
					rr.position.y + rr.size.y * 0.5, rr.size.x, rr.size.y])
			var bad := 0
			for i in items.size():
				for j in range(i + 1, items.size()):
					var ra: Rect2 = items[i][1]
					var rb: Rect2 = items[j][1]
					if ra.intersects(rb):
						bad += 1
						var ov := ra.intersection(rb)
						print("[overlap]  %s overlaps %s by %.1f x %.1f m" % [
							items[i][0], items[j][0], ov.size.x, ov.size.y])
			print("[overlap] %d overlapping pairs" % bad)
	if _wreck_test:
		_wreck_t2 += delta
		if _wreck_t2 > 3.0 and _wreck_t2 < 3.0 + delta:
			for v in get_tree().get_nodes_in_group("vehicles"):
				if v is Tank and v.alive:
					v.apply_damage(9999.0)
			print("[wreck] every vehicle destroyed")
		if _wreck_t2 > 4.0 and fmod(_wreck_t2, 3.0) < delta:
			var lo := 1e9
			var n := 0
			for v in get_tree().get_nodes_in_group("vehicles"):
				if is_instance_valid(v):
					n += 1
					lo = minf(lo, v.global_position.y - Sim.height_at(
						v.global_position.x, v.global_position.z))
			var junk := get_tree().get_nodes_in_group("wreckage")
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
			for v in get_tree().get_nodes_in_group("vehicles"):
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
	if _tank_test:
		if tank == null and not parked.is_empty():
			for v in get_tree().get_nodes_in_group("vehicles"):
				_enter_tank(v as Tank)
				tank.scripted = true
				break
		elif is_instance_valid(tank):
			_tank_t += delta
			tank.in_throttle = 1.0
			tank.in_steer = 0.6 if _tank_t > 8.0 else 0.0
			tank.in_brake = _tank_t > 16.0
			if tank.is_indirect() and fmod(_tank_t, 6.0) < delta and _tank_t > 3.0:
				tank.aim_pitch = deg_to_rad(-6.0)
				tank.fire_main(self)
				if not tank.last_solution.is_empty():
					print("[arty] %s: %.1f km at %.0f deg, %d rounds, tof %.0f s" % [
						tank.display_name(), float(tank.last_solution["range"]) * 0.001,
						float(tank.last_solution["elev"]), int(tank.last_solution["salvo"]),
						float(tank.last_solution["tof"])])
			if fmod(_tank_t, 2.0) < delta:
				var b := tank.global_transform.basis
				print("[tank] t=%4.1f speed=%5.1f km/h  pitch=%+5.1f roll=%+5.1f  y=%6.1f agl=%+5.2f" % [
					_tank_t, tank.speed * 3.6,
					rad_to_deg(asin(clampf(-b.z.y, -1, 1))), rad_to_deg(atan2(-b.x.y, b.y.y)),
					tank.global_position.y,
					tank.global_position.y - Sim.height_at(tank.global_position.x, tank.global_position.z)])
	if _fx and is_instance_valid(player) and player.alive:
		_fx_t += delta
		player.set_bays(true)
		if _fx_t > 0.35:
			_fx_t = 0.0
			player.flares = 30
			player.chaff = 30
			player.dispense_all()
			if player.fire_cd <= 0.0 and player.count_remaining("aim120") > 0:
				player.selected = maxi(player.weapon_types.find("aim120"), 0)
				player.locked = true
				player.fire()
	if _turn_test > 0.0 and is_instance_valid(player):
		if _turn_t == 0.0:
			player.global_transform = Transform3D(Basis(), Vector3(0, 6000, 20000))
			player.linear_velocity = Vector3(0, 0, -_turn_test)
			player.gear_down = false
			player.gear_anim = 0.0
			player.throttle = 1.0
			player.power = 1.0
			player.auto = "turn"
			player.bank_deg = _bank_deg if _bank_deg != 0.0 else 80.0
			player.turn_speed = _turn_test
		_turn_t += delta
		var hb := player.global_transform.basis
		var hdg := atan2(hb.z.x, hb.z.z)
		var rate := rad_to_deg(wrapf(hdg - _turn_hdg, -PI, PI)) / maxf(delta, 1e-6)
		_turn_hdg = hdg
		# sample the steady part of the turn only: the first few seconds are the
		# roll-in, and anything past ten is a different aeroplane by then
		if _turn_t > 4.0 and _turn_t < 12.0:
			_turn_n += 1
			_turn_sum_g += player.g_load
			_turn_sum_r += absf(rate)
			_turn_sum_a += rad_to_deg(player.aoa)
			_turn_sum_v += player.linear_velocity.length()
		if _turn_t >= 12.0:
			var n := maxf(float(_turn_n), 1.0)
			var mv := _turn_sum_v / n
			var mr := _turn_sum_r / n
			print("[turn] %s assist=%-5s entry=%3.0f m/s -> mean tas=%5.1f  g=%4.2f  rate=%5.2f deg/s  radius=%6.0f m  aoa=%4.1f  bank=%5.1f  peak g=%4.2f  grey-out=%3.0f%%" % [
				str(player.spec["name"]), str(player.assist), _turn_test, mv,
				_turn_sum_g / n, mr, mv / maxf(deg_to_rad(mr), 1e-4),
				_turn_sum_a / n, rad_to_deg(atan2(-hb.x.y, hb.y.y)),
				player.g_peak, player.g_strain * 100.0])
			get_tree().quit()
	if _run_for > 0.0:
		# wall clock, not sim time: --fixed-fps decouples the two, and net
		# tests need two processes to overlap for a real number of seconds
		_run_t = Time.get_ticks_msec() * 0.001
		if _run_t >= _run_for:
			get_tree().quit()
	if _shot != "":
		_shot_frames -= 1
		if _shot_frames <= 0:
			_take_shot()

# ---------------------------------------------------------------- missions
func set_weather(id: String) -> void:
	Sim.weather = id
	if weather:
		weather.apply(id, _env, _sun, _fill, _psm)

func _start(id: String, mission: String) -> void:
	# a "veh:" selection means the player starts in the driver's seat instead
	var drive_kind := ""
	var ship_kind := ""
	if id.begins_with("sea:"):
		ship_kind = id.substr(4)
		id = "f16"
		mission = "ramp"
	if id.begins_with("veh:"):
		drive_kind = id.substr(4)
		id = "f16"
		mission = "ramp"
	_drive_kind = drive_kind
	_ship_kind = ship_kind
	Sim.selected_jet = id
	Sim.mission = mission
	Sim.score = 0
	get_tree().paused = false
	_clear_mission()
	menu.visible = false
	preview.visible = false
	hud.visible = true
	running = true
	_audit_spawns.call_deferred()
	_slot_home = Vector3.INF
	_slot_said = -1
	_mission_started = Time.get_ticks_msec()
	_offset_for_peer.call_deferred()

	var craft: Aircraft
	if JetSpec.is_rotary(id):
		craft = PlayerHeli.new()
	else:
		craft = PlayerJet.new()
	player = craft
	player.setup(id)
	player.team = 0
	player.name = "Player"
	player.assist = Sim.assist
	add_child(player)
	player.store_released.connect(_on_store_released)
	player.touched_down.connect(_on_touchdown)
	player.died.connect(func(_w): Sim.report("you were shot down", Sim.Ev.BAD))

	if cam == null:
		cam = ChaseCamera.new()
		add_child(cam)
	player.auto = _auto
	if "_dash_alt" in player:
		player._dash_alt = _dash_alt
	if "bank_deg" in player:
		player.bank_deg = _bank_deg
	if "_hover_alt" in player:
		player._hover_alt = _dash_alt
	if _view != "":
		cam.mode = {"cockpit": 0, "chase": 1, "orbit": 2}.get(_view, 0)
	if _dist > 0.0:
		cam.orbit_dist = _dist
		cam.orbit = _orbit if _orbit != Vector2.ZERO else Vector2(2.3, 0.18)
	if _openbay:
		player.set_bays(true)
	if _nocockpit:
		for n in player._model.get("cockpit_parts", []):
			n.visible = false
	player.debug_forces = _dump > 0
	cam.subject = player
	cam.current = true
	hud.jet = player
	veil.jet = player
	hud.cam = cam
	pod.jet = player
	map.jet = player
	if "pod" in player:
		player.pod = pod
	base.watcher = player
	_reset_interp.call_deferred(player)

	var gear_h := 0.0
	for g in player.spec["gear"]:
		gear_h = maxf(gear_h, absf(g["pos"].y) + g["r"])

	match mission:
		"takeoff":
			player.global_transform = Transform3D(Basis(), Vector3(0, gear_h + 0.02, 1380.0))
			_begin_boarding()
			player.gear_down = true
			player.gear_anim = 1.0
			player.throttle = 0.0
			player.flaps = 1.0
			player.flap_anim = 1.0
			Sim.report("Cleared for takeoff, runway 36. Wheel brakes with X.", Sim.Ev.INFO)
			Sim.report("Rotate around 150 kt, gear up with G.", Sim.Ev.INFO)
		"landing":
			var z := Airbase.AIM_Z + 12000.0
			player.global_transform = Transform3D(Basis(), Vector3(140.0, 640.0, z))
			player.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-1.2), 0.0)
			# Enter at this airframe's own speed. A fixed 148 m/s is a fighter's
			# approach and roughly twice what a Hercules flies, and no amount of
			# controller tuning stabilises an aircraft that starts a hundred
			# knots fast twelve miles out with the throttle already closed.
			var app: float = 148.0
			if player.has_method("ref_speed_kt"):
				app = player.ref_speed_kt() / 1.94384 * 1.35
			player.linear_velocity = -player.global_transform.basis.z * _entry_speed(app)
			player.gear_down = true
			player.gear_anim = 1.0
			player.flaps = 1.0
			player.throttle = 0.42
			player.power = 0.42
			Sim.report("Twelve out, cleared to land runway 36.", Sim.Ev.INFO)
			Sim.report("Two white two red on the PAPI is on slope.", Sim.Ev.INFO)
			_landing_watch = true
		"ramp":
			_setup_ramp()
		"conquest", "rush", "warlords", "tdm", "ffa":
			_setup_battle(mission)
		"carrier":
			_setup_carrier_approach()
		"free":
			player.global_transform = Transform3D(Basis(), Vector3(-600.0, 2400.0, 7000.0))
			player.rotation.y = deg_to_rad(-4.0)
			player.linear_velocity = -player.global_transform.basis.z * _entry_speed(230.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.throttle = 0.7
			player.power = 0.7
			Sim.report("Free flight. Empty skies — the valley runs north-south.", Sim.Ev.INFO)
			Sim.report("Runway 36 is ahead of you; gear down with G when you want to land.", Sim.Ev.INFO)
		_:
			player.global_transform = Transform3D(Basis(), Vector3(-900.0, 4200.0, 6500.0))
			player.rotation.y = deg_to_rad(-6.0)   # heading roughly north, into the fight
			player.linear_velocity = -player.global_transform.basis.z * _entry_speed(260.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.throttle = 0.85
			player.power = 0.85
			_spawn_threats()
			Sim.report("Bandits north of the field. Bays open before you shoot.", Sim.Ev.INFO)

## A body that was just teleported has stale interpolation history; without this
## it renders a smear from its old position to the new one.
func _reset_interp(n: Node3D) -> void:
	if is_instance_valid(n):
		n.reset_physics_interpolation()

# ------------------------------------------------------------- boarding
## Walk out, climb the ladder, strap in, canopy down. Any key skips it.
func _begin_boarding(from_ladder := false) -> void:
	if _skip_board or _auto != "":
		player.set_canopy(false, true)
		return
	boarding = true
	_board_t = 0.0
	_skip_board = false
	player.auto = "wait"
	# fighters lift the hood and drop a ladder; an airliner just opens a door
	var hooded: bool = player.has_canopy()
	if hooded:
		player.set_canopy(true, true)
	var lad: Vector3 = player.to_global(player.ladder_offset())
	_board_ladder = Vector3(lad.x, Sim.height_at(lad.x, lad.z), lad.z)
	_board_from = _board_ladder + (Vector3.ZERO if from_ladder else Vector3(-16.0, 0, 9.0))
	if from_ladder:
		_board_t = 4.9                       # skip the walk-out, start climbing
	# The seat pan, not a guess hung off the eye point: the pilot's origin is at
	# his feet and his hips sit 0.92 above it, so measuring from the eye put him
	# on top of the fuselage rather than down in the tub.
	_board_seat = player.to_global(player.seat_offset() - Vector3(0, 0.92, 0))
	pilot = Pilot.new()
	pilot.build()
	add_child(pilot)
	pilot.global_position = _board_from
	_face(pilot, _board_ladder)
	board_cam = Camera3D.new()
	board_cam.far = 45000.0
	board_cam.fov = 48.0
	add_child(board_cam)
	board_cam.current = true
	hud.visible = false
	Sim.report("Crew walking out. Press any key to skip.", Sim.Ev.INFO)

func _end_boarding() -> void:
	boarding = false
	if is_instance_valid(pilot):
		pilot.queue_free()
	if is_instance_valid(board_cam):
		board_cam.queue_free()
	if is_instance_valid(player):
		player.auto = _auto
		player.set_canopy(false)
	hud.visible = true
	if cam:
		cam.current = true

func _tick_boarding(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(pilot):
		_end_boarding()
		return
	_board_t += delta
	var t := _board_t
	var jet := player.global_position
	if t < 5.0:                                   # walk out
		var f := clampf(t / 5.0, 0.0, 1.0)
		var p := _board_from.lerp(_board_ladder, f)
		p.y = Sim.height_at(p.x, p.z)
		pilot.global_position = p
		_face(pilot, Vector3(_board_ladder.x, p.y, _board_ladder.z))
		pilot.pose_walk(t)
	elif t < (8.2 if player.has_canopy() else 6.6):    # climb
		var f := clampf((t - 5.0) / 3.2, 0.0, 1.0)
		var top := _board_seat + Vector3(_board_ladder.x - _board_seat.x, 0.35, 0) * 0.55
		pilot.global_position = _board_ladder.lerp(top, f)
		pilot.pose_climb(t)
	elif t < 9.6:                                 # step in and strap up
		var f := clampf((t - 8.2) / 1.4, 0.0, 1.0)
		var top := _board_seat + Vector3(_board_ladder.x - _board_seat.x, 0.35, 0) * 0.55
		pilot.global_position = top.lerp(_board_seat, f)
		pilot.rotation.y = lerp_angle(pilot.rotation.y, player.rotation.y, f)
		pilot.pose_seated()
	else:
		pilot.global_position = _board_seat
		pilot.rotation.y = player.rotation.y
		pilot.pose_seated()
		if player.canopy_open:
			player.set_canopy(false)
		if player.canopy_anim <= 0.01 or t > 13.5:
			_end_boarding()
			return
	# Camera: wide walk-out easing round to the cockpit. The pull-back is scaled
	# to the airframe, otherwise a big jet has its nose cut off in the shot.
	var f2: float = clampf(t / 11.0, 0.0, 1.0)
	var reach: float = maxf(float(player.spec["span"]), 14.0)
	var ang: float = lerpf(2.4, 3.4, f2)
	var dist: float = lerpf(reach * 1.55, reach * 0.72, pow(f2, 1.5))
	var hgt: float = lerpf(reach * 0.30, reach * 0.20, f2)
	var focus: Vector3 = pilot.global_position + Vector3(0, 0.9, 0)
	board_cam.global_position = jet + Vector3(cos(ang) * dist, hgt, sin(ang) * dist)
	# look at the middle of the aircraft, drifting toward the cockpit
	var centre := jet + Vector3(0, 1.2, 0)
	board_cam.look_at(centre.lerp(focus, 0.5 * (1.0 - f2)), Vector3.UP)

# ------------------------------------------------------------------ on foot
## Ramp start: the flown jet is parked and inert, and you begin beside it on
## foot with a line of other airframes to choose from.
## Battle modes: airborne start over the contested sectors, with the mode
## controller laying out objectives and keeping score.
func _setup_battle(id: String) -> void:
	player.global_transform = Transform3D(Basis(), Vector3(-500.0, 3600.0, 7200.0))
	player.rotation.y = deg_to_rad(-4.0)
	player.linear_velocity = -player.global_transform.basis.z * _entry_speed(250.0)
	player.gear_down = false
	player.gear_anim = 0.0
	player.throttle = 0.85
	player.power = 0.85
	mode = GameMode.new()
	mode.name = "GameMode"
	add_child(mode)
	mode.start(id)
	mode.finished.connect(_on_mode_finished)
	hud.mode = mode
	var wings: int = 3 if id in ["tdm", "ffa"] else 3
	_spawn_threats(wings)

func _on_mode_finished(_win: bool, _text: String) -> void:
	pass

## Three km final on the boat.
func _setup_carrier_approach() -> void:
	var deck := carrier.global_position
	var hdg := carrier.rotation.y
	var back := Vector3(sin(hdg), 0, cos(hdg))
	player.global_transform = Transform3D(Basis(Vector3.UP, hdg), deck + back * 3400.0
		+ Vector3(0, 210.0, 0))
	player.linear_velocity = -player.global_transform.basis.z * _entry_speed(72.0)
	player.gear_down = true
	player.gear_anim = 1.0
	player.flaps = 1.0
	player.hook_down = true
	player.hook_anim = 1.0
	player.throttle = 0.45
	player.power = 0.45
	Sim.report("Carrier three miles. Hook is down, aim for the two wire.", Sim.Ev.INFO)
	Sim.report("TAB opens aircraft actions if you need to reset anything.", Sim.Ev.INFO)

func _setup_ramp() -> void:
	var row := [["f22", -150.0], ["f35", -220.0], ["f16", -290.0], ["f15", -360.0]]
	var idx := 0
	for i in row.size():
		if row[i][0] == Sim.selected_jet:
			idx = i
	var slot: Array = row[idx]
	player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(150.0, _stance(player.spec), float(slot[1])))
	player.gear_down = true
	player.gear_anim = 1.0
	player.throttle = 0.0
	player.active = false
	player.add_to_group("boardable")
	parked = [player]
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
		add_child(j)
		j.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
			Vector3(150.0, _stance(j.spec), float(row[i][1])))
		j.gear_down = true
		j.gear_anim = 1.0
		j.set_canopy(true, true)
		j.add_to_group("boardable")
		j.add_to_group("hittable")
		_reset_interp.call_deferred(j)
		parked.append(j)
	player.set_canopy(true, true)
	var garage := ["m1a2", "t90", "type99", "m109", "msta", "m270", "bm30"]
	var lot: Array[Tank] = []
	for i in garage.size():
		lot.append(_spawn_tank(Vector3(196.0, 0, -424.0 - i * 15.0),
			deg_to_rad(-90.0), 0, garage[i]))
	# Stand clear of the nose, however big the aeroplane is. A fixed fourteen
	# metres to the side is outside an F-22 and inside an AC-130's wing.
	var nose: float = maxf(absf(player.bounds.position.z), absf(player.bounds.end.z))
	_spawn_walker(player.global_transform * Vector3(0.0, 0.0, -(nose + 5.0)))
	if _ship_kind != "":
		# put the captain on a ship of the chosen type rather than on the ramp
		var pick: Ship = null
		for sh in get_tree().get_nodes_in_group("ships"):
			if is_instance_valid(sh) and (sh as Ship).kind == _ship_kind:
				pick = sh
				break
		if pick == null:
			pick = Ship.new()
			pick.setup(_ship_kind, 0)
			add_child(pick)
			var at := _deep_water(Vector3(26000.0, 0, 2400.0))
			pick.global_position = Vector3(at.x, Sim.WATER_LEVEL, at.z)
		_ship_kind = ""
		_enter_ship(pick)
		return
	if _arty_test != "" and _drive_kind == "":
		_drive_kind = _arty_test
	if _drive_kind != "":
		# only the vehicles just parked on the ramp, never a group search
		for v in lot:
			if is_instance_valid(v) and v.kind == _drive_kind:
				_enter_tank(v)
				break
		_drive_kind = ""
		return
	Sim.report("Walk to a jet and press U to climb in.", Sim.Ev.INFO)
	Sim.report("WASD walk, SHIFT run, CTRL crouch, SPACE jump, V fire, C view.", Sim.Ev.INFO)

## Airborne starts should not fling a helicopter in at fighter speed.
func _entry_speed(want: float) -> float:
	var cap: float = float(player.spec.get("vne", 600.0)) * 0.62
	return minf(want, cap)

func _stance(spec: Dictionary) -> float:
	var h := 0.0
	for g in spec["gear"]:
		h = maxf(h, absf(g["pos"].y) + g["r"])
	return h + 0.02

## Footprint of a body on the ground, in world XZ, from its actual meshes.
func _footprint(n: Node3D) -> Rect2:
	var r := Rect2()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var ab: AABB = mi.get_aabb()
		var xf: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
		for k in 8:
			var corner: Vector3 = n.global_transform * (xf * (ab.position + Vector3(
				ab.size.x * float(k & 1), ab.size.y * float((k >> 1) & 1),
				ab.size.z * float((k >> 2) & 1))))
			var p := Vector2(corner.x, corner.z)
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r

func _label_of(n: Node) -> String:
	if n.has_method("display_name"):
		return String(n.call("display_name"))
	if "spec" in n:
		return String((n.get("spec") as Dictionary)["name"])
	return String(n.name)

## Turn a node to face a point on the level. Godot's look_at errors outright if
## the target is where the node already is, which happens the moment the pilot
## reaches the foot of the ladder and keeps being told to look at it.
func _face(n: Node3D, at: Vector3) -> void:
	if not is_instance_valid(n):
		return
	var d := Vector2(at.x - n.global_position.x, at.z - n.global_position.z)
	if d.length() < 0.02:
		return
	n.rotation.y = atan2(d.x, d.y) + PI

## How many things that can be shot are still alive inside a radius.
func _count_standing(at: Vector3, radius: float) -> int:
	var n := 0
	for x in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(x) or not (x is Node3D):
			continue
		if x.has_method("is_alive") and not x.is_alive():
			continue
		if (x as Node3D).global_position.distance_to(at) < radius:
			n += 1
	return n

## Shipping. A screen around the carrier, a submarine off the group, and some
## civil traffic further out so the ocean is not an empty blue plane.
## Call a strategic strike from a friendly submarine onto whatever is currently
## designated: the sensor aim point, or the map fire mission if one is set.
func _strategic_strike() -> void:
	var at := Vector3.INF
	if pod != null and pod.active:
		at = pod.aim_point()
	if at == Vector3.INF and map != null and map.has_method("target_point"):
		at = map.target_point()
	if at == Vector3.INF:
		Sim.report("strategic strike: designate a target first", Sim.Ev.BAD)
		return
	var boat: Ship = null
	for sh in get_tree().get_nodes_in_group("ships"):
		if is_instance_valid(sh) and (sh as Ship).team == 0 and (sh as Ship).can_launch():
			boat = sh
			break
	if boat == null:
		Sim.report("strategic strike: no boat on station", Sim.Ev.BAD)
		return
	boat.launch_strategic(at)

## Walk a berth seaward until it is over water deep enough to float in.
func _deep_water(at: Vector3) -> Vector3:
	var p := at
	for i in 60:
		if Sim.height_at(p.x, p.z) < Sim.WATER_LEVEL - 25.0:
			return p
		p.x += 900.0
	return p

func _build_fleet() -> void:
	var grp := Vector3(24000.0, 0.0, 1200.0)
	var plan := [
		["destroyer", Vector3(2600, 0, -1800), -18.0, 0],
		["type45",    Vector3(-2200, 0, 2400), -18.0, 0],
		["frigate",   Vector3(3800, 0, 3100), -18.0, 0],
		["sub",       Vector3(-4200, 0, -3400), -22.0, 0],
		["patrol",    Vector3(900, 0, 4200), -10.0, 0],
		["corvette",  Vector3(12000, 0, -9000), 140.0, 1],
		["type45",    Vector3(15500, 0, -12500), 140.0, 1],
		["patrol",    Vector3(9500, 0, -14000), 155.0, 1],
		["cargo",     Vector3(-6000, 0, 16000), 95.0, 2],
		["cargo",     Vector3(20000, 0, 12000), 265.0, 2],
	]
	for i in plan.size():
		var e: Array = plan[i]
		var sh := Ship.new()
		sh.setup(String(e[0]), int(e[3]))
		# Unique, so a second ship of the same class does not have its name
		# thrown away by the tree and replaced with "@Node3D@194".
		sh.name = "%s %d" % [sh.name, i + 1]
		sh.fleet_idx = i
		# every peer lays the same fleet down in the same order, so the index is
		# the whole address the network needs
		sh.ghost = net != null and net.active and not net.is_host
		add_child(sh)
		var at: Vector3 = grp + (e[1] as Vector3)
		# The coast is ragged and the shelf runs out to about 24 km, so a berth
		# has to be checked rather than assumed: a boat on a shoal is inside the
		# terrain, and a missile leaving its tube detonates on the seabed.
		at = _deep_water(at)
		sh.global_position = Vector3(at.x, Sim.WATER_LEVEL, at.z)
		sh.heading = deg_to_rad(float(e[2]))
	fleet_count = plan.size()

## Self check at mission start: anything that has spawned inside something else
## names itself in the log rather than waiting to be noticed on screen.
## Move this peer's aeroplane off the shared start point. Everybody loads the
## same mission, so without this two players who chose the same type begin
## inside one another.
## Move this peer off the shared start point.
##
## This cannot be done at mission start. A joiner launches its mission before
## the connection has finished — its own id is still the default 1 and the
## roster is empty, so it works out slot 0 and stays exactly where the host is.
## Measured with four peers: all four on the same coordinates. It is worked out
## when the roster arrives instead, which is a second or so later and long
## before anyone has flown anywhere.
## The host changed its mind in the hangar; tell everyone waiting in it.
func _on_lobby_mission(m: String) -> void:
	if net != null:
		net.announce_lobby(m)

func _offset_for_peer() -> void:
	if net == null or not net.active or not is_instance_valid(player):
		return
	if net.my_id == 1 and not net.is_host:
		return                          # the connection has not landed yet
	# Recomputed on every roster change, not latched on the first. A slot is a
	# rank among the peers present, and the first roster a joiner sees contains
	# only itself — so all three clients decided they were number one and piled
	# onto the same offset. It is always applied to the *original* start point
	# rather than to wherever the aeroplane is now, so refining the answer moves
	# it to the right place instead of shifting it again.
	if _slot_home == Vector3.INF:
		_slot_home = player.global_position
	if Time.get_ticks_msec() - _mission_started > 15000:
		return                          # the roster has settled; leave it alone
	var slot: int = net.spawn_slot()
	var off: Vector3 = net.spawn_offset()
	if off == Vector3.ZERO:
		return
	if player.on_ground or Sim.mission == "ramp" or Sim.mission == "takeoff":
		# on the ground, step along the apron and keep the wheels on it
		var p := _slot_home + Vector3(off.x, 0.0, off.z)
		p.y = Sim.height_at(p.x, p.z) + _stance(player.spec) + 0.02
		player.global_position = p
	else:
		player.global_position = _slot_home + off
	_reset_interp(player)
	if slot != _slot_said:
		_slot_said = slot
		Sim.report("spawn slot %d" % slot, Sim.Ev.INFO)

func _audit_spawns() -> void:
	var items: Array = []
	var seen := {}
	for grp in ["vehicles", "hittable", "ground_targets", "boardable"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(n) or not (n is Node3D):
				continue
			if n.is_in_group("ships") or n.is_in_group("carrier") \
					or n.is_queued_for_deletion() or seen.has(n.get_instance_id()):
				continue
			seen[n.get_instance_id()] = true
			var box := _footprint(n as Node3D)
			if box != Rect2():
				items.append([_label_of(n), box, n])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var ra: Rect2 = items[i][1]
			var rb: Rect2 = items[j][1]
			if not ra.intersects(rb):
				continue
			var ov := ra.intersection(rb)
			if ov.size.x < 0.5 or ov.size.y < 0.5:
				continue
			Sim.report("SPAWN CONFLICT: %s inside %s by %.1f x %.1f m" % [
				items[i][0], items[j][0], ov.size.x, ov.size.y], Sim.Ev.BAD)
			var na := items[i][2] as Node3D
			var nb := items[j][2] as Node3D
			push_warning("spawn conflict: [%s %s groups=%s parent=%s] at %s overlaps [%s %s] at %s" % [
				na.get_class(), na.name, str(na.get_groups()), str(na.get_parent().name),
				str(na.global_position.round()), nb.get_class(), nb.name,
				str(nb.global_position.round())])

func _spawn_tank(at: Vector3, yaw: float, team: int, kind := "m1a2") -> Tank:
	var t := Tank.new()
	t.setup(team, kind)
	t.name = "Tank"
	add_child(t)
	t.global_transform = Transform3D(Basis(Vector3.UP, yaw),
		Vector3(at.x, Sim.height_at(at.x, at.z) + 1.1, at.z))
	t.dismount_requested.connect(_leave_tank)
	_reset_interp.call_deferred(t)
	return t

func _spawn_walker(at: Vector3) -> void:
	on_foot = true
	walker = Walker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
	walker.yaw = deg_to_rad(90.0)
	walker.board_requested.connect(_board)
	walker.died.connect(_on_walker_died)
	walker.hold_requested.connect(_enter_hold)
	walker.station_requested.connect(_take_hold_station)
	walker.activate()
	hud.walker = walker
	hud.jet = null
	veil.jet = null
	if audio:
		audio.jet = null

## Hand the aircraft to the orbit autopilot and move the player back to the
## gun sight. Leaving puts them back in the front seat.
func toggle_gunner() -> void:
	if not is_instance_valid(player) or not player.spec.get("gunship", false):
		return
	gunning = not gunning
	if gunning:
		_pre_gun_auto = player.auto
		player.auto = "orbit"
		if "orbit_alt" in player:
			player.orbit_alt = maxf(player.global_position.y, 1200.0)
			player.orbit_speed = maxf(player.linear_velocity.length(), 110.0)
		if not pod.active:
			pod.toggle()
		pod.set_fullscreen(true)
		cam.pod_slew = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Sim.report("gunner station — mouse slews, CTRL+T tracks, 1/2/3 pick a gun",
			Sim.Ev.INFO)
		Sim.report("the aircraft is holding a left orbit; press G again to go forward",
			Sim.Ev.INFO)
	else:
		player.auto = _pre_gun_auto
		pod.set_fullscreen(false)
		if pod.active:
			pod.toggle()
		cam.pod_slew = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		Sim.report("back in the front seat", Sim.Ev.INFO)

## Gunner controls: the aircraft is on autopilot so the stick is free.
func _gunner_input(_delta: float) -> void:
	if not gunning or not is_instance_valid(player):
		return
	if not player.alive:
		toggle_gunner()
		return
	for i in 8:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))) \
				and i < player.weapon_types.size():
			player.set_weapon(i)
			Sim.report(player.weapon_label(player.current_weapon()), Sim.Ev.INFO)
	if Input.is_action_pressed(&"gun") or Input.is_action_pressed(&"fire"):
		var aim: Vector3 = pod.aim_point()
		if aim != Vector3.INF:
			player.fire_gunship(self, aim)

## The sensor page doubles as a weapon station: pick a store, shoot at whatever
## the pod is holding. Helicopters and gunships live here.
func _sensor_input() -> void:
	for i in 8:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))) \
				and i < player.weapon_types.size():
			player.set_weapon(i)
			Sim.report(player.weapon_label(player.current_weapon()), Sim.Ev.INFO)
	if Input.is_action_just_pressed(&"laser"):
		pod.toggle_laser()
	if Input.is_action_just_pressed(&"fire") or Input.is_action_pressed(&"gun"):
		var w: String = player.current_weapon()
		var aim: Vector3 = pod.aim_point()
		if player.is_gunship_weapon(w):
			if aim != Vector3.INF:
				player.fire_gunship(self, aim)
		elif w == "gun":
			player.fire_gun(self)
		elif Input.is_action_just_pressed(&"fire"):
			var res: String = player.fire()
			if res != "":
				Sim.report(res, Sim.Ev.INFO)

## Air traffic: put an aeroplane in the circuit and let its own pilot fly it.
func _do_admin(id: String) -> void:
	match id:
		"type":
			return
		"land":
			_call_traffic(admin.jet_id, "land", 0)
		"flight":
			for i in 3:
				_call_traffic(admin.jet_id, "land", i)
		"takeoff":
			_call_traffic(admin.jet_id, "takeoff", 0)
		"follow":
			admin.following = not admin.following
			_follow_traffic(admin.following)
		"clear":
			for t in _traffic:
				if is_instance_valid(t):
					t.queue_free()
			_traffic.clear()
			if is_instance_valid(cam) and is_instance_valid(player):
				cam.subject = player
	_traffic = _traffic.filter(func(t): return is_instance_valid(t))
	admin.traffic = _traffic.size()

func _call_traffic(id: String, what: String, slot: int) -> void:
	var craft: Aircraft
	if JetSpec.is_rotary(id):
		craft = PlayerHeli.new()
	else:
		craft = PlayerJet.new()
	craft.setup(id)
	craft.team = 0
	craft.name = "Traffic %d" % (_traffic.size() + 1)
	craft.assist = true
	add_child(craft)
	var stance := _stance(craft.spec)
	if what == "takeoff":
		craft.global_transform = Transform3D(Basis(),
			Vector3(0.0, stance + 0.02, 1340.0 - float(slot) * 90.0))
		craft.gear_down = true
		craft.gear_anim = 1.0
		craft.flaps = 1.0
		craft.flap_anim = 1.0
	else:
		# spaced down the approach so a flight arrives in trail
		var z: float = Airbase.AIM_Z + 12000.0 + float(slot) * 2600.0
		craft.global_transform = Transform3D(Basis(), Vector3(140.0, 640.0 + slot * 60.0, z))
		craft.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-1.2), 0.0)
		var entry := 140.0
		if craft.has_method("ref_speed_kt"):
			entry = float(craft.call("ref_speed_kt")) / 1.94384 * 1.35
		craft.linear_velocity = -craft.global_transform.basis.z * entry
		craft.gear_down = true
		craft.gear_anim = 1.0
		craft.flaps = 1.0
	craft.auto = what
	craft.add_to_group("hittable")
	_reset_interp.call_deferred(craft)
	_traffic.append(craft)
	if admin.following:
		_follow_traffic(true)
	Sim.report("%s called in: %s" % [String(craft.spec["name"]), what], Sim.Ev.INFO)

## Watch the traffic, from whatever the player happens to be crewing.
##
## Setting the chase camera's subject is not enough on its own. A player on a
## ship or in a tank is looking through *that* vehicle's camera, so the aircraft
## camera can be pointed at a landing aeroplane all it likes and the view never
## moves — which reads as the traffic not flying at all, rather than as the
## camera being somewhere else.
func _follow_traffic(on: bool) -> void:
	if not is_instance_valid(cam):
		return
	if on:
		var subject: Node3D = null
		for t in _traffic:
			if is_instance_valid(t):
				subject = t
				break
		if subject == null:
			admin.following = false
			Sim.report("nothing in the circuit to follow", Sim.Ev.BAD)
			return
		cam.subject = subject as Aircraft
		cam.mode = ChaseCamera.Mode.CHASE
		cam.current = true          # take the view off the ship or the tank
		Sim.report("following %s" % subject.name, Sim.Ev.INFO)
		return
	cam.subject = player if is_instance_valid(player) else null
	# and give it back to whatever the player is actually riding
	if is_instance_valid(ship) and ship.occupied:
		ship.cam.current = true
	elif is_instance_valid(tank) and is_instance_valid(tank.cam):
		tank.cam.current = true
	else:
		cam.current = true

func _do_action(id: String) -> void:
	# vehicle and ship actions first: they are the ones on screen when crewing
	match id:
		"sensor":
			if is_instance_valid(ship):
				pod.toggle()
				pod.set_fullscreen(pod.active)
			return
		"allstop":
			if is_instance_valid(ship):
				ship.telegraph = 0.0
			return
		"amidships":
			if is_instance_valid(ship):
				ship.helm = 0.0
			return
		"dismount":
			if is_instance_valid(ship):
				_leave_ship()
			elif is_instance_valid(tank):
				_leave_tank()
			return
		"weapon":
			if is_instance_valid(tank):
				tank.cycle_weapon()
			return
		"gunner":
			if is_instance_valid(tank):
				tank.gunner = not tank.gunner
			return
		"clearfm":
			if is_instance_valid(tank):
				tank.map_target = Vector3.INF
				Sim.report("fire mission cancelled", Sim.Ev.INFO)
			return
		"map":
			map.toggle()
			return
	_do_aircraft_action(id)

func _do_aircraft_action(id: String) -> void:
	if not is_instance_valid(player):
		return
	match id:
		"hook":
			player.toggle_hook()
			player.say("tailhook " + ("down" if player.hook_down else "up"))
		"bay":
			player.set_bays(not player.any_bay_open())
		"gear":
			player.toggle_gear()
		"flaps":
			player.flaps = 0.0 if player.flaps > 0.5 else 1.0
		"canopy":
			player.set_canopy(not player.canopy_open)
		"ramp":
			player.toggle_ramp()
			player.say("cargo ramp " + ("opening" if player.ramp_open else "closing"))
		"fbw":
			player.assist = not player.assist
			Sim.assist = player.assist
		"dismount":
			actions.close()
			_try_dismount()
		"gunner":
			actions.close()
			toggle_gunner()
		"eject":
			actions.close()
			_eject()

func _eject() -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	Sim.report("EJECT", Sim.Ev.BAD)
	var rd := Ragdoll.new()
	rd.spawn_from(Transform3D(player.global_transform.basis,
		player.global_transform * player.cockpit_offset()),
		player.linear_velocity * 0.5 + Vector3(0, 24.0, 0))
	add_child(rd)
	player.break_part("canopy")
	player.explode()

## Take command of a ship. The helm is the same stick as a tank's, the mount is
## laid with the mouse, and U puts you back where you came from.
func _enter_ship(sh: Ship) -> void:
	if not is_instance_valid(sh) or not sh.alive:
		return
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	ship = sh
	sh.mount(true)
	if net != null and net.active:
		net.take_ship_conn(sh.fleet_idx, true)
	pod.host = sh
	hud.ship = sh
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse lays the battery, left click fires, U to hand over", Sim.Ev.INFO)

func _leave_ship() -> void:
	if not is_instance_valid(ship):
		return
	ship.mount(false)
	if net != null and net.active:
		net.take_ship_conn(ship.fleet_idx, false)
	pod.host = null
	if pod.active:
		pod.toggle()
		pod.set_fullscreen(false)
	var at: Vector3 = ship.global_position
	hud.ship = null
	ship = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_walker(at + Vector3(0, 12.0, 0))
	if is_instance_valid(cam):
		cam.current = true

func _enter_tank(t: Tank) -> void:
	if not is_instance_valid(t) or not t.alive:
		return
	if Sim.debug_weapons:
		print("[mount] %s at %s, %.1f m above ground, mission=%s" % [t.kind,
			str(t.global_position.round()),
			t.global_position.y - Sim.height_at(t.global_position.x, t.global_position.z),
			str(Sim.mission)])
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	tank = t
	t.mount(true)
	hud.tank = t
	map.tank = t
	Sim.report("in the driver's seat — W/S drive, A/D steer, mouse lays the gun", Sim.Ev.INFO)
	Sim.report("SPACE main gun, V coax, C gunner sight, U to get out", Sim.Ev.INFO)

func _leave_tank() -> void:
	if not is_instance_valid(tank):
		return
	var out: Vector3 = tank.global_transform * Vector3(-3.4, 0.5, 0.0)
	tank.mount(false)
	tank.in_throttle = 0.0
	tank.in_steer = 0.0
	tank.in_brake = true
	hud.tank = null
	map.tank = null
	tank = null
	_spawn_walker(out)

## End to end checks for the weapon chains, driven from the command line.
func _run_weapon_test(delta: float) -> void:
	_wt_t += delta
	match _wtest:
		"bomb":
			if _wt_stage == 0 and _wt_t > 1.0:
				for sam in get_tree().get_nodes_in_group("hittable"):
					if sam is GroundTarget and (sam as GroundTarget).kind == "sam":
						(sam as GroundTarget).alive = false     # quiet range
				for n in get_tree().get_nodes_in_group("ground_targets"):
					if is_instance_valid(n) and n.is_alive() and n.is_in_group("hittable") \
							and n.team != 0:
						_wt_mark = n
						break
				if _wt_mark == null:
					print("[wt] no ground target in this mission")
					_wtest = ""
					return
				var tp: Vector3 = _wt_mark.global_position
				var from := tp + Vector3(0, 700.0, 1500.0)
				player.global_transform = Transform3D(Basis(), from)
				player.look_at(tp, Vector3.UP)
				player.linear_velocity = -player.global_transform.basis.z * 240.0
				player.gear_down = false
				player.gear_anim = 0.0
				player.throttle = 0.8
				player.power = 0.8
				player.set_bays(true)
				player.target = _wt_mark
				_reset_interp.call_deferred(player)
				print("[wt] bomb run: %s at %.0f m, health %.0f" % [
					_wt_mark.name, from.distance_to(tp), _wt_mark.health])
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 3.5:
				player.selected = maxi(player.weapon_types.find("gbu32"), 0)
				var res: String = player.fire()
				print("[wt] release: %s  (bay %s)" % [
					"away" if res == "" else res,
					"open" if player.any_bay_open() else "shut"])
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2:
				if not is_instance_valid(_wt_mark) or not _wt_mark.is_alive():
					print("[wt] RESULT: target destroyed at t=%.1f" % _wt_t)
					_wtest = ""
					return
				var live := get_tree().get_nodes_in_group("missiles")
				if fmod(_wt_t, 2.0) < delta:
					var d := -1.0
					for m in live:
						if is_instance_valid(m) and m.wid == "gbu32":
							d = m.global_position.distance_to(_wt_mark.global_position)
					print("[wt]   t=%4.1f  bombs airborne=%d  miss distance=%.0f m  target hp=%.0f"
						% [_wt_t, live.size(), d, _wt_mark.health])
				if _wt_t > 30.0:
					print("[wt] RESULT: no kill, target health %.0f" % _wt_mark.health)
					_wtest = ""
		"aamground":
			# put a Sidewinder into a built-up area and see what it does
			if _wt_stage == 0 and _wt_t > 1.0:
				# find somewhere actually built up rather than assuming
				var want := Vector3.ZERO
				var best := 0
				for cx in range(-12, 13):
					for cz in range(-12, 13):
						var q := Vector3(float(cx) * 900.0, 0.0, float(cz) * 900.0)
						var c := scenery.count_standing(q, 120.0)
						if c > best:
							best = c
							want = q
				want.y = Sim.height_at(want.x, want.z)
				_nuke_aim = want
				# count at the SAME point the after-count uses, or the two
				# radii are measured from different heights and disagree
				_nuke_before = scenery.count_standing(want, 120.0)
				player.global_transform = Transform3D(Basis(), want + Vector3(0, 900.0, 2600.0))
				player.rotation = Vector3(deg_to_rad(-19.0), 0.0, 0.0)
				player.linear_velocity = -player.global_transform.basis.z * 250.0
				player.gear_down = false
				player.gear_anim = 0.0
				player.throttle = 0.8
				player.power = 0.8
				player.set_bays(true)
				player.target = null
				_reset_interp.call_deferred(player)
				print("[wt] AAM into the ground: %d structures standing within 120 m" % _nuke_before)
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 4.0:
				player.selected = maxi(player.weapon_types.find("aim9"), 0)
				player.locked = true
				var res: String = player.fire()
				print("[wt] release: %s" % ("away" if res == "" else res))
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2 and _wt_t > 12.0:
				var after := scenery.count_standing(_nuke_aim, 120.0)
				print("[wt] RESULT: %d of %d structures within 120 m brought down" % [
					_nuke_before - after, _nuke_before])
				_wtest = ""
		"nuke", "nuke2":
			if _wt_stage == 0 and _wt_t > 1.0:
				# designate something real: a guided bomb needs a target, and
				# without one it simply falls where it was let go
				var best: Node3D = null
				var bd := 1e9
				var want := Vector3(2600.0, 0, 4200.0)
				for g in get_tree().get_nodes_in_group("ground_targets"):
					if not is_instance_valid(g):
						continue
					var dd: float = Vector2(g.global_position.x - want.x,
						g.global_position.z - want.z).length()
					if dd < bd:
						bd = dd
						best = g
				if best == null:
					print("[wt] no ground target to aim at")
					_wtest = ""
					return
				_wt_mark = best
				var tgt: Vector3 = best.global_position
				_nuke_before = _count_standing(tgt, 1400.0)
				player.global_transform = Transform3D(Basis(),
					tgt + Vector3(0, 700.0, 2400.0))
				player.rotation.y = 0.0        # facing -Z, which is toward the target
				player.linear_velocity = -player.global_transform.basis.z * 190.0
				player.gear_down = false
				player.gear_anim = 0.0
				player.throttle = 0.6
				player.power = 0.6
				player.set_bays(true)
				player.target = _wt_mark
				_nuke_aim = tgt
				_reset_interp.call_deferred(player)
				print("[wt] nuclear run (%s): aim %s, %d units standing within 1400 m" % [
					"b83 strategic" if _wtest == "nuke2" else "b61 tactical",
					str(tgt.round()), _nuke_before])
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 4.0:
				var wid := "b83" if _wtest == "nuke2" else "b61"
				player.selected = maxi(player.weapon_types.find(wid), 0)
				player.locked = true
				var res: String = player.fire()
				print("[wt] release: %s" % ("away" if res == "" else res))
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2 and _wt_t > 8.0 \
					and get_tree().get_nodes_in_group("missiles").is_empty():
				var after := _count_standing(_nuke_aim, 1400.0)
				print("[wt] RESULT: %d of %d units within 1400 m destroyed" % [
					_nuke_before - after, _nuke_before])
				_wtest = ""
		"gun":
			if _wt_stage == 0 and _wt_t > 1.0:
				for n in get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.is_alive():
						_wt_mark = n
						break
				if _wt_mark == null:
					print("[wt] no bandit to shoot at")
					_wtest = ""
					return
				print("[wt] gun run on %s, health %.0f" % [_wt_mark.name, _wt_mark.health])
				_wt_stage = 1
			elif _wt_stage >= 1 and is_instance_valid(_wt_mark):
				# sit 500 m astern and hose it
				var tp: Vector3 = _wt_mark.global_position
				var tb: Basis = _wt_mark.global_transform.basis
				player.global_transform = Transform3D(tb, tp + tb.z * 500.0)
				player.linear_velocity = _wt_mark.linear_velocity
				player.fire_gun(self)
				if not _wt_mark.is_alive():
					print("[wt] RESULT: bandit shot down with the gun at t=%.1f" % _wt_t)
					_wtest = ""
				elif _wt_t > 25.0:
					print("[wt] RESULT: gun did %.0f damage in 25 s" % (100.0 - _wt_mark.health))
					_wtest = ""
		"capture":
			if _wt_stage == 0 and _wt_t > 1.0:
				for z in get_tree().get_nodes_in_group("zones"):
					if is_instance_valid(z) and z.owner_team == 1:
						_wt_mark = z
						break
				if _wt_mark == null:
					print("[wt] no hostile sector")
					_wtest = ""
					return
				print("[wt] sector %s: owner=%d progress=%.2f assets=%d" % [
					_wt_mark.label, _wt_mark.owner_team, _wt_mark.progress,
					_wt_mark.alive_assets()])
				for a in _wt_mark.assets:
					if is_instance_valid(a) and a.has_method("take_hit"):
						a.take_hit(9999.0)
				print("[wt] garrison flattened, assets alive: %d" % _wt_mark.alive_assets())
				_wt_stage = 1
			elif _wt_stage == 1:
				if not is_instance_valid(_wt_mark):
					_wtest = ""
				elif _wt_mark.owner_team == 0:
					print("[wt] RESULT: sector %s captured at t=%.1f" % [_wt_mark.label, _wt_t])
					_wtest = ""
				elif fmod(_wt_t, 2.0) < delta:
					print("[wt]   progress %.2f owner=%d assets alive=%d" % [
						_wt_mark.progress, _wt_mark.owner_team, _wt_mark.alive_assets()])
				elif _wt_t > 30.0:
					print("[wt] RESULT: sector not taken, progress %.2f" % _wt_mark.progress)
					_wtest = ""
		"trap":
			if _wt_stage == 0 and _wt_t > 1.0:
				var deck: Vector3 = carrier.global_position
				var hdg: float = carrier.rotation.y + Carrier.ANGLE
				var back := Vector3(sin(hdg), 0, cos(hdg))
				player.global_transform = Transform3D(Basis(Vector3.UP, hdg),
					deck + back * 260.0 + Vector3(0, Carrier.DECK_Y + 16.0, 0))
				player.linear_velocity = (-player.global_transform.basis.z * 66.0
					+ Vector3(0, -3.4, 0))
				player.gear_down = true
				player.gear_anim = 1.0
				player.hook_down = true
				player.hook_anim = 1.0
				player.flaps = 1.0
				player.throttle = 0.45
				player.power = 0.45
				_reset_interp.call_deferred(player)
				print("[wt] carrier approach: 260 m out, 16 m above the deck, hook down")
				_wt_stage = 1
			elif _wt_stage == 1:
				if player.trapped:
					print("[wt] RESULT: TRAPPED at t=%.1f, speed %.1f m/s" % [
						_wt_t, player.linear_velocity.length()])
					_wt_stage = 2
				elif _wt_t > 25.0:
					print("[wt] RESULT: no trap. on ground=%s alt=%.1f speed=%.1f" % [
						str(player.on_ground), player.global_position.y,
						player.linear_velocity.length()])
					_wtest = ""
			elif _wt_stage == 2 and player.linear_velocity.length() < 2.0:
				print("[wt] stopped on deck at %.1f m, %.1f s after touchdown" % [
					player.global_position.y, _wt_t])
				_wtest = ""

func _on_walker_died(where: Vector3) -> void:
	Sim.report("pilot down", Sim.Ev.BAD)
	await get_tree().create_timer(3.5).timeout
	if not on_foot or not is_inside_tree():
		return
	if is_instance_valid(walker):
		walker.queue_free()
	_spawn_walker(where + Vector3(6.0, 0, 6.0))

## Crew in the back of a gunship can take the gun station without flying it.
func _take_hold_station(jet: Node) -> void:
	if not is_instance_valid(jet) or not jet.spec.get("gunship", false):
		return
	if not is_instance_valid(walker):
		return
	_station_walker = walker
	walker.visible = false
	walker.set_process(false)
	walker.set_physics_process(false)
	hud.walker = null
	on_foot = false
	player = jet as Aircraft
	hud.jet = player
	veil.jet = player
	pod.jet = player
	map.jet = player
	if "pod" in player:
		player.pod = pod
	if audio:
		audio.jet = player
	gunning = false
	toggle_gunner()

func _leave_hold_station() -> void:
	if not is_instance_valid(_station_walker):
		return
	if gunning:
		toggle_gunner()
	var w := _station_walker
	_station_walker = null
	w.visible = true
	w.set_process(true)
	w.set_physics_process(true)
	w.activate()
	walker = w
	hud.walker = w
	hud.jet = null
	veil.jet = null
	on_foot = true

func _enter_hold(jet: Node) -> void:
	if is_instance_valid(walker) and jet.has_method("hold_node"):
		walker.enter_frame(jet.hold_node(), jet)

func _board(jet: Node) -> void:
	if jet is Ship:
		_enter_ship(jet as Ship)
		return
	if jet is Tank:
		_enter_tank(jet as Tank)
		return
	if not is_instance_valid(jet) or not (jet is Aircraft):
		return
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	player = jet as Aircraft
	player.active = true
	player.remove_from_group("boardable")
	for j in parked:
		if is_instance_valid(j) and j != player:
			j.set_canopy(false)
	cam.subject = player
	cam.current = true
	hud.jet = player
	veil.jet = player
	hud.cam = cam
	pod.jet = player
	map.jet = player
	if "pod" in player:
		player.pod = pod
	base.watcher = player
	if audio:
		audio.jet = player
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)
	if not player.touched_down.is_connected(_on_touchdown):
		player.touched_down.connect(_on_touchdown)
	if player.spec.is_empty():
		Sim.selected_jet = String(JetSpec.ids()[0])
	_begin_boarding(true)

func _on_player_died(_w: Node) -> void:
	Sim.report("you were shot down", Sim.Ev.BAD)

## Leave the jet: only with the wheels stopped and the throttle closed.
func _try_dismount() -> void:
	if not is_instance_valid(player) or on_foot or boarding:
		return
	if not player.on_ground or player.linear_velocity.length() > 1.5 or player.throttle > 0.02:
		if is_instance_valid(player):
			player.say("stop the jet and close the throttle first")
		return
	player.active = false
	player.set_canopy(true)
	player.add_to_group("boardable")
	if not parked.has(player):
		parked.append(player)
	var out: Vector3 = player.to_global(player.ladder_offset() + Vector3(-1.6, 0, 0))
	_spawn_walker(out)

func _host_game(jet_id: String, _address: String) -> void:
	Sim.selected_jet = jet_id
	if net.host(jet_id):
		# host whatever match is selected; joiners are told to load the same one
		_start(jet_id, String(menu.mission_id))

func _join_game(jet_id: String, address: String) -> void:
	Sim.selected_jet = jet_id
	if net.join(address, jet_id):
		# a placeholder match until the host says which one it is running
		_start(jet_id, "free")

func _clear_mission() -> void:
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	for j in parked:
		if is_instance_valid(j) and j != player:
			j.queue_free()
	parked.clear()
	for n in get_tree().get_nodes_in_group("hittable"):
		# Never sweep up other players: they are owned by the network layer, and
		# freeing them leaves dangling ghost entries that break the sync loop.
		# Shipping and the carrier are world furniture -- built once, outliving
		# the mission, so not the mission's to delete.
		if is_instance_valid(n) and not n.is_in_group("remote") \
				and not n.is_in_group("ships") and not n.is_in_group("carrier"):
			n.queue_free()
	# The aeroplane you were flying goes with the mission. Skipping it here left
	# it standing on the apron after a restart, so the next mission parked a
	# fresh one straight through it.
	if is_instance_valid(player):
		player.queue_free()
	player = null
	hud.jet = null
	if is_instance_valid(veil):
		veil.jet = null
	for n in get_tree().get_nodes_in_group("missiles"):
		if is_instance_valid(n):
			n.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	_landing_watch = false
	_stop_t = 0.0
	if gunning:
		gunning = false
		pod.set_fullscreen(false)
	_station_walker = null
	if is_instance_valid(mode):
		mode.queue_free()
	mode = null
	hud.mode = null
	for z in get_tree().get_nodes_in_group("zones"):
		if is_instance_valid(z):
			z.queue_free()
	if boarding:
		_end_boarding()

func _spawn_threats(count := -1) -> void:
	# in a session, only the host simulates the opposition; clients receive it
	if net != null and net.active and not net.is_host:
		return
	# the opposition flies the other bloc's hardware
	var enemy: Array = OPFOR_JETS if JetSpec.bloc_of(Sim.selected_jet) == "nato" else NATO_JETS
	var n: int = 3 if count < 0 else count
	for i in n:
		var b := AIPlane.new()
		b.setup(enemy[i % enemy.size()])
		b.team = 1
		b.name = "Bandit %d" % (i + 1)
		b.home = Vector3(1400.0 * i - 1400.0, 0, -4200.0)
		b.patrol_r = 2400.0 + i * 600.0
		add_child(b)
		b.global_transform = Transform3D(Basis(), Vector3(-1700.0 + i * 1900.0, 3900.0 + i * 450.0, -2600.0 - i * 900.0))
		b.rotation.y = deg_to_rad(170.0 + 8.0 * i)   # nose-on to the player
		b.linear_velocity = -b.global_transform.basis.z * 240.0
		_reset_interp.call_deferred(b)
		b.died.connect(_on_bandit_down)
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
	if mode == null or mode.mode not in ["tdm", "ffa"]:
		var rotary: Array = OPFOR_HELIS if JetSpec.bloc_of(Sim.selected_jet) == "nato" \
			else NATO_HELIS
		for i in 2:
			var h := AIHeli.new()
			h.setup(rotary[i % rotary.size()])
			h.team = 1
			h.name = "Gunship %d" % (i + 1)
			h.home = Vector3(-1200.0 + i * 2400.0, 0, -5200.0)
			add_child(h)
			var hx: float = h.home.x
			var hz: float = h.home.z + 400.0
			h.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)),
				Vector3(hx, Sim.height_at(hx, hz) + 260.0, hz))
			h.died.connect(_on_bandit_down)
			_reset_interp.call_deferred(h)
	if mode != null and mode.mode in ["tdm", "ffa"]:
		return
	# A pair working the ground: the aeroplanes that are not trying to shoot
	# you down are the ones that make the field feel busy.
	var cas: Array = OPFOR_CAS if JetSpec.bloc_of(Sim.selected_jet) == "nato" \
		else NATO_CAS
	for i in 2:
		var m := AIPlane.new()
		m.setup(cas[i % cas.size()])
		m.role = "cas"
		m.team = 1
		m.name = "Mud Mover %d" % (i + 1)
		m.home = Vector3(-2000.0 + i * 3800.0, 0, -7000.0)
		m.patrol_r = 3200.0
		add_child(m)
		var mx: float = m.home.x
		var mz: float = m.home.z - 5000.0
		m.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0 + 10.0 * i)),
			Vector3(mx, Sim.height_at(mx, mz) + 2400.0 + i * 300.0, mz))
		m.linear_velocity = -m.global_transform.basis.z * 175.0
		m.died.connect(_on_bandit_down)
		if i == 1 and is_instance_valid(_cas_lead):
			m.leader = _cas_lead
			m.slot = Vector3(-110.0, -20.0, 150.0)
			m.global_transform = Transform3D(_cas_lead.global_transform.basis,
				_cas_lead.global_transform * m.slot)
			m.linear_velocity = _cas_lead.linear_velocity
		else:
			_cas_lead = m
		_reset_interp.call_deferred(m)
	# and one transport on a milk run, which is a target rather than a threat
	var hauler := AIPlane.new()
	hauler.setup(AI_TRANSPORTS[randi() % AI_TRANSPORTS.size()])
	hauler.role = "transport"
	hauler.team = 1
	hauler.name = "Heavy 1"
	hauler.home = Vector3(0, 0, -12000.0)
	add_child(hauler)
	hauler.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(120.0)),
		Vector3(6000.0, Sim.height_at(6000.0, -16000.0) + 5200.0, -16000.0))
	hauler.linear_velocity = -hauler.global_transform.basis.z * 150.0
	hauler.died.connect(_on_bandit_down)
	_reset_interp.call_deferred(hauler)
	for p in picks:
		var g := GroundTarget.new()
		g.team = 1
		g.setup(p[0])
		add_child(g)
		var pos: Vector3 = p[1]
		g.global_position = Vector3(pos.x, Sim.height_at(pos.x, pos.z), pos.z)
		g.name = "%s site" % p[0]

func _on_store_released(m: Node) -> void:
	# Ride it out if the weapon cam is armed. It lets go on its own when the
	# round goes off, because the node stops being valid.
	if weapon_cam_on and is_instance_valid(cam) and m is Node3D:
		cam.weapon_cam = m as Node3D
	if net and net.active and is_instance_valid(m):
		net.report_fire(m.wid, m.global_transform, m.vel)

func _on_bandit_down(who: Node) -> void:
	if mode and mode.running:
		mode.register_kill(1)
	Sim.score += 400
	if is_instance_valid(player):
		player.kills += 1
	Sim.report("%s splashed" % who.name, Sim.Ev.GOOD)

# ---------------------------------------------------------------- landing
func _on_touchdown(info: Dictionary) -> void:
	if Sim.debug_weapons or _auto_diag:
		print("[td] x=%+.1f z=%+.1f on_runway=%s vs=%.2f gs=%.0f pitch=%+.1f bank=%+.1f" % [
			float(info["offset"]),
			player.global_position.z if is_instance_valid(player) else 0.0,
			str(info["on_runway"]), float(info["vs"]), float(info["gs"]),
			float(info["pitch"]), float(info["bank"])])
	if not info["on_runway"]:
		Sim.report("touchdown off the paved surface", Sim.Ev.BAD)
		return
	var vs: float = absf(info["vs"])
	var grade := "GREASED"
	var pts := 500
	if vs > 5.0:
		grade = "HARD"
		pts = 120
	elif vs > 2.6:
		grade = "FIRM"
		pts = 300
	elif vs > 1.2:
		grade = "GOOD"
		pts = 420
	var off: float = absf(info["offset"])
	if off > 12.0:
		pts -= 120
		grade += " / OFF CENTRE"
	Sim.score += maxi(pts, 0)
	Sim.report("%s — %.1f m/s, %.0f m off centre" % [grade, vs, off], Sim.Ev.GOOD if pts > 250 else Sim.Ev.BAD)
	_stop_t = 0.0

func _watch_landing(delta: float) -> void:
	if not player.alive or not player.on_ground:
		return
	var gs := Vector2(player.linear_velocity.x, player.linear_velocity.z).length()
	if gs > 6.0:
		_stop_t = 0.0
		return
	_stop_t += delta
	if _stop_t > 1.5 and _landing_watch:
		_landing_watch = false
		var rem := Sim.RUNWAY_LEN * 0.5 - absf(player.global_position.z)
		Sim.report("FULL STOP — %d m of runway to spare. Score %d." % [int(rem), Sim.score], Sim.Ev.GOOD)

# ---------------------------------------------------------------- shell
func _resume() -> void:
	menu.visible = false
	get_tree().paused = false
	if is_instance_valid(player):
		cam.current = true
		if player.mouse_fly:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## What the radar page would draw for one contact: the same masking test the
## scope itself applies.
func _radar_paints(n: Node3D) -> bool:
	if not is_instance_valid(player) or not is_instance_valid(n):
		return false
	var d := player.global_position.distance_to(n.global_position)
	if d > Sim.radar_range():
		return false
	return d <= 2000.0 or Sim.line_of_sight(player.global_position + Vector3(0, 4, 0),
		n.global_position + Vector3(0, 4, 0))

## Synthesise a key for the harness, straight into the same handler the shell
## uses, so the test exercises the real path rather than calling chat methods.
func _press(code: Key, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	e.pressed = true
	_shell_input(e)

func _shell_input(e: InputEvent) -> void:
	# The chat line comes first and eats everything while it is open, so that
	# typing "w" is a letter rather than full throttle.
	if is_instance_valid(chat) and e is InputEventKey:
		var ke := e as InputEventKey
		if chat.typing:
			chat.handle_key(ke)
			Sim.typing = chat.typing
			return
		if ke.pressed and not ke.echo and ke.keycode == KEY_SLASH and running \
				and not Sim.ui_modal:
			chat.open_line()
			Sim.typing = true
			return
	# ALT + right click raises the targeting pod; the wheel zooms it.
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and running \
			and not on_foot and not Sim.ui_modal:
		var mb := e as InputEventMouseButton
		# Not while driving: right click is the gun there, and META counts as
		# freelook on a Mac, so firing a howitzer threw the player into the
		# sensor camera. This guard belongs on the pod alone -- putting it at
		# the top of the handler took the map, the radar ranges, the side
		# panels and the action menu with it.
		if mb.button_index == MOUSE_BUTTON_RIGHT and not is_instance_valid(tank):
			pod.toggle()
			pod.set_fullscreen(pod.active)
			if cam:
				cam.pod_slew = pod.active
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if pod.active \
				else Input.MOUSE_MODE_VISIBLE
			return
		if pod.active and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			pod.zoom(1)
			return
		if pod.active and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pod.zoom(-1)
			return
	if pod.active and e is InputEventMouseMotion and Input.is_action_pressed(&"freelook"):
		pod.slew((e as InputEventMouseMotion).relative)
		return
	if boarding and ((e is InputEventKey and e.pressed and not e.echo) \
			or (e is InputEventMouseButton and e.pressed)):
		_end_boarding()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		if k == KEY_EQUAL and running:
			Sim.radar_range_idx = mini(Sim.radar_range_idx + 1, Sim.RADAR_RANGES.size() - 1)
			Sim.report("radar range %d km" % int(Sim.radar_range() * 0.001), Sim.Ev.INFO)
		elif k == KEY_MINUS and running:
			Sim.radar_range_idx = maxi(Sim.radar_range_idx - 1, 0)
			Sim.report("radar range %d km" % int(Sim.radar_range() * 0.001), Sim.Ev.INFO)
		elif k == KEY_BRACKETLEFT and running:
			Sim.panel_left = (Sim.panel_left + 1) % 4
			Sim.report("left panel: %s" % HUD.PANEL_NAMES[Sim.panel_left], Sim.Ev.INFO)
		elif k == KEY_BRACKETRIGHT and running:
			Sim.panel_right = (Sim.panel_right + 1) % 4
			Sim.report("right panel: %s" % HUD.PANEL_NAMES[Sim.panel_right], Sim.Ev.INFO)
		elif k == KEY_H and running and is_instance_valid(player) \
				and bool(player.spec.get("stovl", false)):
			player.hover_cmd = not player.hover_cmd
			Sim.report("STOVL: %s" % ("converting to jetborne" if player.hover_cmd
				else "converting to wingborne"), Sim.Ev.INFO)
		elif k == KEY_M and running:
			map.toggle()
		elif k == KEY_TAB and running and not on_foot:
			if actions.visible:
				actions.close()
			elif is_instance_valid(ship):
				actions.open_for_vehicle(ship)
			elif is_instance_valid(tank):
				actions.open_for_vehicle(tank)
			elif is_instance_valid(player):
				actions.open_for(player)
		elif k == KEY_K and running:
			_strategic_strike()
		elif k == KEY_Y and running:
			# not F: that is the flap lever
			weapon_cam_on = not weapon_cam_on
			if not weapon_cam_on and is_instance_valid(cam):
				cam.weapon_cam = null
			Sim.report("weapon camera %s" % ("armed" if weapon_cam_on else "off"),
				Sim.Ev.INFO)
		elif k == KEY_O and running and not on_foot and not is_instance_valid(tank) \
				and is_instance_valid(player):
			pod.toggle()
			pod.set_fullscreen(pod.active)
			if cam:
				cam.pod_slew = pod.active
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if pod.active \
				else Input.MOUSE_MODE_VISIBLE
			Sim.report("sensor page %s" % ("up" if pod.active else "stowed"), Sim.Ev.INFO)
		elif k == KEY_N and pod.active:
			pod.cycle_channel()
			Sim.report("sensor: %s" % SensorPod.CHANNEL_NAMES[pod.channel], Sim.Ev.INFO)
		elif k == KEY_T and pod.active and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
			pod.designate()
		elif k == KEY_F3 and running:
			if admin.visible:
				admin.close()
			else:
				admin.open()
		elif k == KEY_F2:
			hud.show_help = not hud.show_help
		elif k == KEY_ESCAPE and running:
			menu.visible = not menu.visible
			menu.set_paused(true)
			get_tree().paused = menu.visible
			if audio:
				audio.set_paused(menu.visible)
			if menu.visible:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif is_instance_valid(player) and player.mouse_fly:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif k == KEY_C and running and not on_foot:
			cam.cycle()
		elif k == KEY_G and running and is_instance_valid(_station_walker):
			_leave_hold_station()
		elif k == KEY_G and running and not on_foot and is_instance_valid(player) \
				and player.spec.get("gunship", false):
			toggle_gunner()
		elif k == KEY_U and running and not on_foot and not boarding:
			if is_instance_valid(ship):
				_leave_ship()
			else:
				_try_dismount()
		# R used to restart the mission outright. That is far too easy to hit by
		# accident mid-sortie; restarting belongs behind the pause menu.

# ---------------------------------------------------------------- screenshots
func _parse_cmdline() -> void:
	var preset := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--weather="):
			set_weather(a.substr(10))
		elif a.begins_with("--jet="):
			menu._select(a.substr(6))
		elif a.begins_with("--auto="):
			_auto = a.substr(7)
		elif a.begins_with("--dump="):
			_dump = int(a.substr(7))
		elif a.begins_with("--view="):
			_view = a.substr(7)
		elif a == "--nocockpit":
			_nocockpit = true
		elif a == "--openbay":
			_openbay = true
		elif a.begins_with("--dist="):
			_dist = float(a.substr(7))
		elif a.begins_with("--frames="):
			_shot_at = int(a.substr(9))
		elif a.begins_with("--at="):
			var av := a.substr(5).split(",")
			if av.size() == 3:
				_at = Vector3(float(av[0]), float(av[1]), float(av[2]))
		elif a == "--noboard":
			_skip_board = true
		elif a.begins_with("--weapontest="):
			_wtest = a.substr(13)
		elif a == "--host":
			_net_host = true
		elif a.begins_with("--join="):
			_net_join = a.substr(7)
		elif a.begins_with("--gtest="):
			veil.debug_strain = float(a.substr(8))
		elif a == "--noassist":
			Sim.assist = false
		elif a.begins_with("--turntest="):
			_turn_test = float(a.substr(11))
		elif a.begins_with("--runfor="):
			_run_for = float(a.substr(9))
		elif a.begins_with("--mission="):
			menu.mission_id = a.substr(10)
		elif a == "--netlog":
			_net_log = true
			net.verbose = true
		elif a.begins_with("--bankdeg="):
			_bank_deg = float(a.substr(10))
		elif a.begins_with("--dashalt="):
			_dash_alt = float(a.substr(10))
		elif a == "--gunnertest":
			_gunner_test = true
		elif a.begins_with("--fpslog"):
			_fps_log = true
		elif a == "--debugweapons":
			Sim.debug_weapons = true
		elif a == "--boomtest":
			_boom_test = true
		elif a == "--camtest":
			_cam_test = true
		elif a.begins_with("--artyoff="):
			_arty_off = float(a.substr(10))
		elif a.begins_with("--artytest="):
			_arty_test = a.substr(11)
		elif a == "--hovertest":
			_hover_test = true
		elif a.begins_with("--podch="):
			_pod_want = int(a.substr(8))
			_pod_test = true
		elif a == "--admintest":
			_admin_test = true
		elif a.begins_with("--adminfrom="):
			_admin_test = true
			_admin_from = a.substr(12)
		elif a == "--restarttest":
			_restart_test = true
		elif a.begins_with("--shiptest="):
			_shiptest = a.substr(11)
		elif a == "--wcamtest":
			_wcam_test = true
		elif a == "--navaltest":
			_naval_test = true
		elif a.begins_with("--navaltest="):
			_naval_test = true
			_naval_weapon = a.substr(12)
		elif a == "--battletest":
			_bat_test = true
		elif a == "--castest":
			_cas_test = true
		elif a == "--chattest":
			_chat_test = true
		elif a == "--formtest":
			_form_test = true
		elif a == "--masktest":
			_mask_test = true
		elif a == "--shipnet":
			_shipnet = true
		elif a == "--splashtest":
			_splash_test = true
		elif a == "--autodiag":
			_auto_diag = true
		elif a == "--vlstest":
			_vls_test = true
		elif a == "--townstest":
			_town_test = true
		elif a == "--skytest":
			_sky_test = true
		elif a == "--nettest":
			_nettest = true
		elif a.begins_with("--cmtest="):
			_cm_test = a.substr(9)
		elif a == "--salvotest":
			_salvo_test = true
		elif a == "--shaketest":
			_shake_test = true
		elif a.begins_with("--breaktest="):
			# range[,altitude[,weapon]]
			var bits := a.substr(12).split(",")
			_break_rng = float(bits[0])
			if bits.size() > 1:
				_break_alt = float(bits[1])
			if bits.size() > 2:
				_break_w = String(bits[2])
			_break_test = true
		elif a.begins_with("--cluttertest="):
			_clutter_agl = float(a.substr(14))
			_clutter_test = true
		elif a == "--dctest":
			_dc_test = true
		elif a == "--triggertest":
			_trig_test = true
		elif a == "--seamtest":
			_seam_test = true
		elif a == "--lasertest":
			_laser_test = true
		elif a.begins_with("--hudtest="):
			_hud_view = a.substr(10)
			_hud_test = true
		elif a == "--firetest":
			_fire_test = true
		elif a == "--viewtest":
			_view_test = true
		elif a == "--locktest":
			_lock_test = true
		elif a == "--flaptest":
			_flap_test = true
		elif a == "--seatest":
			_sea_test = true
		elif a == "--subtest":
			_sub_test = true
		elif a == "--fleettest":
			_fleet_test = true
		elif a == "--podtest":
			_pod_test = true
		elif a == "--aimtest":
			_aim_test = true
		elif a == "--seattest":
			_seat_test = true
		elif a.begins_with("--keytest="):
			_key_test = a.substr(10)
		elif a == "--helitest":
			_heli_test = true
		elif a.begins_with("--ctltest="):
			_ctl_test = float(a.substr(10))
		elif a.begins_with("--tvctest="):
			_tvc_test = float(a.substr(10))
		elif a == "--boardtest":
			_board_test = true
		elif a == "--jolttest":
			_jolt_test = true
		elif a == "--overlaptest":
			_overlap_test = true
		elif a == "--wrecktest":
			_wreck_test = true
		elif a == "--tankdrive":
			_tank_test = true
		elif a == "--fx":
			_fx = true
		elif a.begins_with("--orbit="):
			var pv := a.substr(8).split(",")
			if pv.size() == 2:
				_orbit = Vector2(float(pv[0]), float(pv[1]))
	if _net_host:
		_host_game(menu.jet_id, "")
		return
	if _net_join != "":
		_join_game(menu.jet_id, _net_join)
		return
	if preset == "" and _shot == "" and _auto == "":
		return
	if preset == "" and _auto != "":
		preset = "takeoff" if _auto == "takeoff" else "landing" 
	_shot_frames = 70
	match preset:
		"", "menu":
			pass
		"hangar":
			menu.visible = false
			spin = false
			preview.rotation.y = deg_to_rad(215.0)
			menu_cam.position = Vector3(13, 261.5, -15)
			menu_cam.look_at(Vector3(0, 258.4, 0), Vector3.UP)
			_shot_frames = 20
		_:
			var parts := preset.split(":")
			_start(menu.jet_id if parts.size() < 2 else parts[1], parts[0])
			if _at != Vector3.ZERO and is_instance_valid(player):
				player.global_position = _at
				player.linear_velocity = -player.global_transform.basis.z * 170.0
				_reset_interp.call_deferred(player)
			_shot_frames = _shot_at if _shot_at > 0 else 140

func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot)
	print("shot saved: ", _shot)
	get_tree().quit()


class Shell extends Node:
	var world: Node = null

	func _input(e: InputEvent) -> void:
		if world:
			world._shell_input(e)
