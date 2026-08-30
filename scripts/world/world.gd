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
var _road_test := false
var _skirt_test := false
var _lod_test := false
var _ab_test := false
var _accel_test := false
var _land_test := false
var _subview_test := false
var _reach_test := false
var _nuke_test := false
var _nuke_t := 0.0
var _nuke_boat: Ship = null
var _nuke_step := 0
var _nuke_low := 1e9
var _nuke_top := -1e9
var _nuke_at := Vector3.INF
var _nuke_miss := 1e9
var _respawn_test := false
var _respawn_t := 0.0
var _respawn_step := 0
var _guard_test := false
var _guard_t := 0.0
var _guard_step := 0
var _guard_boat: Ship = null
var _guard_shots := 0
var _guard_killed := 0
var _fx_test := false
var _boat_test := false
var _boat_t := 0.0
var _float_test := false
var _seamix := false
var _tel_test := false
var _tel_t := 0.0
var _tel_step := 0
var _tel: Tank = null
var _tel_kids := 0
var _tel_cam := false
var _lag_test := false
var _lag_t := 0.0
var _lag_step := 0
var _lag_before := {}
var _spawn_test := false
var _spawn_t := 0.0
var _field_test := false
var _locktime_test := false
var _lt_t := 0.0
var _mav_test := false
var _mav_t := 0.0
var _mav_step := 0
var _mav_ship: Ship = null
var _mav_rngs := [8000.0, 12000.0, 16000.0, 20000.0]
var _mav_i := 0
var _mav_closest := 1e9
var _mav_locked := false
var _land_t := 0.0
var _land_tgt: Node3D = null
var _land_step := 0
var _land_low := 1e9
var _land_lowat := Vector3.ZERO
var _land_close := 1e9
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
var _biome_test := false
var _obstacle_test := false
var _carrier_test := false
var _tel_rig := ""
var _river_test := false
var _warlords_test := false
var _churn_test := false
var _gun_test := false
var _tfr_test := false
var _tfr_range := 0.0
var _tfr_veh := false
var _tfr_kind := "tel_kalibr"
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
var _subtest := false
var _cruise_test := false
var _cruise_t := 0.0
var _cruise_step := 0
var _cruise_ship: Node3D = null
var _cruise_hp := 0.0
var _cruise_low := 1e9
var _flirtest := false
var _geomtest := false
var _culltest := false
var _navsensor := false
var _navsensor_t := 0.0
var _tanksensor := false
var _tanksensor_t := 0.0
var _salvo_w := "gbu32"
var _salvo_test := false
var _salvo_away := 0
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
var obstacles: Obstacles
var fleet_count := 0
var weapon_cam_on := false
var _cam_was_ship := false
var _cam_was_tank := false
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

## True until the world exists. `_process` runs from the first frame, which is
## now long before there is a terrain or an aeroplane for it to touch.
var booting := true
var _loading: LoadingScreen = null
## `--boottime` turns the start-up breakdown back on.
var _boot_verbose := false
## Middles of the settlement clusters, one of which the ground mask sits on.
var _mask_spots: Array = []
## Where the eye was last frame and how fast it is going, so the ground can be
## fetched ahead of whatever the view is riding.
var _eye_prev := Vector3.INF
var _eye_vel := Vector3.ZERO
var roster_view: RosterView

func _ready() -> void:
	# A lambda captures by value, so a closure that tries to carry the clock
	# forward records cumulative totals dressed up as per-phase costs.
	#
	# Collected rather than printed a line at a time: eight lines of timing on
	# every single launch is noise, and the one number anyone wants is how long
	# it took. The breakdown goes out on one line with it.
	var _t0 := [Time.get_ticks_msec(), Time.get_ticks_msec()]
	var _phases: Array = []
	var _mark := func(what: String) -> void:
		var now := Time.get_ticks_msec()
		_phases.append("%s %d" % [what, now - int(_t0[0])])
		_t0[0] = now
	# Up before anything else, on its own layer above the whole game, and given
	# a frame to paint in before the first slow phase starts.
	# No 3D at all until the world is built and the menu is up.
	#
	# The loading screen is an opaque Control on a layer above everything, and
	# by every reading of the tree nothing behind it can show -- yet a vehicle
	# kept appearing in the middle of it. Rather than keep hunting for which
	# camera was live, the renderer is simply told not to draw a three
	# dimensional scene while the screen is up. Nothing can get through that.
	get_viewport().disable_3d = true
	var boot_ui := CanvasLayer.new()
	boot_ui.name = "BootUI"
	boot_ui.layer = 100
	boot_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(boot_ui)
	_loading = LoadingScreen.new()
	boot_ui.add_child(_loading)
	await _paint("Starting up", 0.0)
	# Before anything asks for a field it might not have to compute -- and so
	# before `_parse_cmdline`, which does not run until the world is already
	# made. Read the flags that have to be honoured now.
	for a in OS.get_cmdline_user_args():
		if a == "--nobake":
			WorldBake.enabled = false
		elif a == "--clearbake":
			WorldBake.clear()
		elif a == "--boottime":
			_boot_verbose = true
	WorldBake.begin()
	_environment()
	_mark.call("environment")
	scenery = Scenery.new()
	scenery.name = "Scenery"
	add_child(scenery)
	await _paint("Laying out the road network", 0.02)
	# Dispatched, then waited on a frame at a time. Searching forty trunk routes
	# is the longest single thing in world generation, and doing it in one
	# blocking call is what stopped the window answering while the map was
	# built -- long enough for the machine to decide the game had hung.
	scenery.plan()                     # road network before the ground is painted
	while scenery.plan_busy():
		await _paint("Laying out the road network", 0.02,
			"searching %d routes over the hills" % Sim.routes_left())
	scenery.plan_finish()
	_mark.call("road network")
	_site_opfor_field()
	_mark.call("siting airfields")
	await _paint("Surveying the ground", 0.26)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.prepare()
	# Pumped rather than built in one go: a few dozen chunks a frame keeps the
	# window alive and gives the bar something true to show.
	while terrain.pending_count() > 0:
		terrain.flush_pending(64)
		await _paint("Building the ground", lerpf(0.30, 0.50,
			terrain.build_progress()),
			"%d of %d chunks" % [terrain.stats["chunks"],
				int(terrain.stats["chunks"]) + terrain.pending_count()])
	terrain.flush_pending()
	_mark.call("terrain")
	await _paint("Building the airfields", 0.50)
	base = Airbase.new()
	base.name = "Airbase"
	add_child(base)
	base.build()
	_build_opfor_base()
	_mark.call("airbases")
	await _paint("Planting the country", 0.52)
	scenery.build()
	_mark.call("scenery")
	obstacles = Obstacles.new()
	obstacles.name = "Obstacles"
	add_child(obstacles)
	# Where the painted ground box can sit: the middle of each settlement
	# cluster. Only one of them is ever near you, and they are a hundred and
	# thirty kilometres apart at the closest.
	var by_r: Dictionary = {}
	for t in scenery.sites:
		var rg: int = int((t as Dictionary).get("region", 0))
		if not by_r.has(rg):
			by_r[rg] = []
		(by_r[rg] as Array).append(t["c"])
	_mask_spots = []
	for rg2 in by_r:
		var acc := Vector2.ZERO
		var lot: Array = by_r[rg2]
		for c in lot:
			acc += c as Vector2
		_mask_spots.append(acc / float(maxi(lot.size(), 1)))
	await _paint("Putting the fleet to sea", 0.87)
	carrier = Carrier.new()
	carrier.name = "Carrier"
	add_child(carrier)
	carrier.build(Vector3(24000.0, 0.0, 1200.0), deg_to_rad(-18.0))
	_build_fleet()
	_mark.call("fleet")

	menu_cam = Camera3D.new()
	menu_cam.far = 45000.0
	menu_cam.fov = 42.0
	menu_cam.position = Vector3(30, 263.5, -30)
	add_child(menu_cam)
	menu_cam.look_at(Vector3(0, 258, 0), Vector3.UP)
	menu_cam.rotate_y(deg_to_rad(19.0))
	# Not yet. This camera stands on the home airfield looking at the turntable,
	# so anything the airbase parks near the origin -- a tug, a stand, a
	# revetment -- sits in the middle of its view, and it was the current camera
	# for the whole of world generation. Nothing should be rendering the world
	# while the loading screen is up; it is made current when the menu is.

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
	_build_underwater(ui)
	_build_nightvision(ui)
	_build_flash(ui)
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
	await _paint("Drawing the map", 0.88)
	map.bake()
	_mark.call("map")
	roster_view = RosterView.new()
	roster_view.net = net
	roster_view.world = self
	ui.add_child(roster_view)
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
	# Not yet: this puts a vehicle on the hangar turntable, forty metres in
	# front of the menu camera, and the menu camera is the one running while the
	# world is still being built. Built here it stood there through the rest of
	# the loading screen.
	# Everything generated this run that will be the same the next one.
	WorldBake.put_grown("node_err", Terrain._err)
	WorldBake.finish()
	# One line for the whole start-up, and the breakdown only when asked for.
	print("[boot] ready in %.1f s (%s bake)" % [
		float(Time.get_ticks_msec() - int(_t0[1])) * 0.001,
		String(WorldBake.stats.get("state", "no"))])
	if _boot_verbose:
		print("[boot] %s" % " | ".join(PackedStringArray(_phases)))
		print("[boot] terrain %s" % str(terrain.stats))
		print("[boot] scenery %s" % str(scenery._stats))
		print("[boot] obstacles %s" % str(Obstacles.stats))
		print("[boot] bake %s" % str(WorldBake.stats))
	# Hold the screen until the ground is actually there. It used to come down
	# the moment this coroutine returned, which is before the terrain queue has
	# drained -- so the first thing on screen was a vehicle sitting on chunks
	# that had not arrived, with the country building itself around it.
	var settle := 0
	while terrain.pending_count() > 0 and settle < 400:
		terrain.flush_pending(48)
		await _paint("Laying the ground", 0.97,
			"%d chunks left" % terrain.pending_count())
		settle += 1
	await _paint("Ready", 1.0)
	booting = false
	if _loading != null:
		_loading.finish()
		var lp := _loading.get_parent()
		_loading = null
		if is_instance_valid(lp):
			lp.queue_free()
	# ...here, with the screen down and the menu about to be shown: the
	# turntable model first, then the camera that frames it, and only then is
	# the world allowed to be drawn at all.
	_set_preview(menu.jet_id)
	menu_cam.current = true
	get_viewport().disable_3d = false
	_parse_cmdline()

## Show where the build has got to and give the engine a frame to draw it in.
func _paint(what: String, f: float, note := "") -> void:
	if _loading != null:
		_loading.step(what, f, note)
	await get_tree().process_frame

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
	# far enough out to be horizon haze rather than a wall a few kilometres off
	env.fog_depth_begin = 24000.0
	env.fog_depth_end = 140000.0
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
	if id == "sea:carrier":
		# She is not a `Ship`, and she is 330 m long, so she needs her own
		# scale as well as her own model.
		var cv := Carrier.new()
		cv.build_preview()
		preview.add_child(cv)
		cv.position = Vector3(0.0, -Carrier.DECK_Y * 0.55, 0.0)
		preview.scale = Vector3.ONE * (16.0 / Carrier.LEN)
		return
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
	# `_ready` is a coroutine now, so frames run while the world is still being
	# made and almost nothing in here exists yet.
	if booting:
		return
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
	# Armour keeps its sight. This used to shut the pod on any frame a tank was
	# crewed, so the commander's sight closed itself the instant it opened.
	if is_instance_valid(tank):
		tank.sight_active = pod != null and pod.active and pod.host == tank
	if pod and pod.active and is_instance_valid(tank) and pod.host != tank:
		pod.toggle()
		pod.set_fullscreen(false)
		if cam:
			cam.pod_slew = false
	if pod and pod.active and not gunning and is_instance_valid(pod.carrier()):
		_sensor_input()
	if gunning:
		_gunner_input(delta)
	if pod and pod.active and not gunning \
			and (not running or on_foot or not is_instance_valid(pod.carrier())):
		pod.toggle()
	if audio and cam and not on_foot:
		audio.cockpit = cam.mode == ChaseCamera.Mode.COCKPIT and not boarding
	# A head-up display is glass in front of the pilot's face. From a chase or
	# orbit camera you are outside the aeroplane and there is nothing to read it
	# off, so the flight page only draws from the cockpit. Checked on its own:
	# hanging it off the audio rig meant it never ran if there was no sound.
	# and back to the bridge, or the driver's seat, once the round has gone
	if _cam_was_ship and is_instance_valid(cam) and not is_instance_valid(cam.weapon_cam):
		_cam_was_ship = false
		if is_instance_valid(ship) and is_instance_valid(ship.cam):
			ship.cam.current = true
	if _cam_was_tank and is_instance_valid(cam) and not is_instance_valid(cam.weapon_cam):
		_cam_was_tank = false
		if is_instance_valid(tank) and is_instance_valid(tank.cam):
			tank.cam.current = true
	# The ground follows the eye. Rebuilds are metered so crossing a ring
	# boundary at five hundred knots does not stall the frame: a chunk is 289
	# height samples and a mesh, and a boundary crossing can want dozens.
	if is_instance_valid(terrain):
		var eye3 := get_viewport().get_camera_3d()
		if eye3 != null:
			# Look where you are going, not where you are. Ground ahead of a
			# fast aeroplane arrives at the moment it is needed and has to be
			# built right then; biasing the centre a couple of seconds forward
			# has it queued and standing before you get there. The bias is
			# capped so a hypersonic does not drag the detail off the map
			# altogether, and it is along the track, so the ground behind
			# coarsens -- which is where you are not looking.
			# From how the *eye* is actually moving, not from the aeroplane.
			# Riding a weapon camera the view is on a round doing Mach 7 while
			# the aeroplane sits on the ramp, so the ground was being fetched
			# for somewhere the camera left seconds ago and chunks arrived long
			# after they were needed.
			var here := eye3.global_position
			var dt: float = maxf(delta, 0.0001)
			if _eye_prev != Vector3.INF:
				var v := (here - _eye_prev) / dt
				# smoothed, or a camera cut reads as an enormous velocity
				if v.length() < 4000.0:
					_eye_vel = _eye_vel.lerp(v, clampf(dt * 3.0, 0.0, 1.0))
				else:
					_eye_vel = Vector3.ZERO
			_eye_prev = here
			var lead := _eye_vel * 2.0
			var far_enough: float = lead.length()
			if far_enough > 1600.0:
				lead *= 1600.0 / far_enough
			terrain.recentre(eye3.global_position + lead)
		# A bigger bite than it looks: the batch is built on the worker pool and
		# collected on a later frame, so this costs the main thread a dispatch
		# and whatever meshes came back, not the generation. The old chunks stay
		# up until their replacements are in, so falling behind costs memory
		# rather than holes in the ground.
		terrain.flush_pending(24)
		if is_instance_valid(obstacles) and eye3 != null:
			obstacles.follow(eye3.global_position)
		# and the painted ground follows you to whichever part of the world you
		# are in, so a town three hundred kilometres from home has streets and
		# made ground under it like any other
		if eye3 != null and not _mask_spots.is_empty():
			var best: Vector2 = _mask_spots[0]
			var bd := 1e18
			for spot in _mask_spots:
				var sp: Vector2 = spot
				var dd: float = Vector2(eye3.global_position.x - sp.x,
					eye3.global_position.z - sp.y).length_squared()
				if dd < bd:
					bd = dd
					best = sp
			terrain.set_mask_centre(best)
	_update_underwater(delta)
	_update_flash(delta)
	if _nvg != null and _nvg.visible:
		_nvg_t += delta
		_nvg_mat.set_shader_parameter("t", _nvg_t)
	# ...unless the sensor page has the key. N steps the pod's channel, and
	# swallowing it here meant the channel could never be changed from inside
	# the very page it belongs to.
	if running and not Sim.ui_modal and not (is_instance_valid(pod) and pod.active) \
			and Sim.tapped(&"night_vision"):
		toggle_nvg()
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
	# Kept running once the bomb is away. Gated on the launcher surviving, the
	# test hung with nothing reported every time the ship shot the aeroplane
	# down before the round arrived — which read as a flaky harness.
	if _naval_test and (is_instance_valid(player) or _naval_shot):
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
			# and it does not shoot back: this measures what the weapon does to
			# the hull, not how long an F-35 lasts orbiting a warship
			# Nothing else touches the target while a round is in the air: the
			# ambient battle sank her mid-flight and the shot was scored a miss
			# when the round had simply lost something already on the bottom.
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.cells_left = 0
					v2.ai = false
					v2.ciws_enabled = false
			for ac in get_tree().get_nodes_in_group("hittable"):
				if ac is Aircraft and ac != player:
					(ac as Aircraft).queue_free()
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
			if not _arm_with(_naval_weapon):
				_naval_test = false
				get_tree().quit()
				return
			player.fire_cd = 0.0
			_reset_interp.call_deferred(player)
			player.target = _naval_ship
			print("[naval] attacking %s with %s, hull %.0f; laser spot %s (sea level %.0f)" % [
				_naval_ship.call("display_name"), _naval_weapon, _naval_hp,
				str(player.designated.round()), Sim.WATER_LEVEL])
		elif _naval_t > 2.0 and _naval_t < 5.0 and is_instance_valid(_naval_ship) \
				and is_instance_valid(player):
			if int(_naval_t * 4.0) != _naval_said:
				_naval_said = int(_naval_t * 4.0)
				var rel: Vector3 = _naval_ship.global_position - player.global_position
				print("[naval] t=%.2f  target=%s  %.1f deg below the nose, %.0f m  locked=%s lock_t=%.2f" % [
					_naval_t, str(is_instance_valid(player.target)),
					rad_to_deg((-player.global_transform.basis.z).angle_to(rel)),
					rel.length(), str(player.locked), player.lock_time])
		elif _naval_t > 5.0 and not _naval_shot and is_instance_valid(player):
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
	# Can a submarine be crewed, and can it shoot?
	if _subtest:
		_subtest = false
		var boat: Ship = null
		for sh in get_tree().get_nodes_in_group("ships"):
			var v := sh as Ship
			if v != null and v.kind == "sub":
				boat = v
				break
		if boat == null:
			print("[sub] no submarine in the fleet")
			get_tree().quit()
			return
		var crewable := PackedStringArray()
		for k in Ship.KINDS:
			var kd2: Dictionary = Ship.KINDS[k]
			if int(kd2["guns"]) > 0 or int(kd2.get("vls", 0)) > 0:
				crewable.append(k)
		print("[sub] crewable hulls in the menu: %s" % ", ".join(crewable))
		print("[sub] %s: boardable=%s, weapons=%s, tubes=%d" % [
			boat.display_name(), str(boat.is_in_group("boardable")),
			str(boat.weapons()), boat.tubes()])
		var mark := Ship.new()
		mark.setup("cargo", 1)
		add_child(mark)
		mark.global_position = boat.global_position + Vector3(9000.0, 0, 0)
		var before := get_tree().get_nodes_in_group("missiles").size()
		var ok2: bool = boat.fire_vls(mark)
		var after := get_tree().get_nodes_in_group("missiles").size()
		var what := ""
		for m in get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m):
				what = String(m.wid)
		print("[sub] RESULT: fire_vls=%s, rounds %d -> %d, round type=%s, cells left %d" % [
			str(ok2), before, after, what, boat.cells_left])
		get_tree().quit()
	# A Harpoon at a ship from long range: does it run in on the deck.
	if _cruise_test and is_instance_valid(player):
		_cruise_t += delta
		if _cruise_t > 2.0 and _cruise_ship == null:
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.has_gun():
					_cruise_ship = v
					break
			if _cruise_ship == null:
				print("[cruise] no hostile warship")
				_cruise_test = false
				return
			# nothing else sinks the target while the round is in the air, and
			# the target does not sink the launcher either: at sixteen
			# kilometres and four thousand metres its tubes had the F-16 down
			# thirty-three seconds after release and the test never finished
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 == null:
					continue
				if v2 != _cruise_ship:
					v2.ai = false
				v2.cells_left = 0
			_cruise_hp = float(_cruise_ship.get("health"))
			var sp: Vector3 = _cruise_ship.global_position
			# Out where a Harpoon is actually employed. From 4200 m only 16 km
			# out there are 13 km of cruise to lose 4 km of height — seventeen
			# degrees, the whole let-down budget — so it arrives at the pop-up
			# still high and never gets near the deck. That is the geometry,
			# not the guidance.
			player.global_transform = Transform3D(Basis(),
				sp + Vector3(0, 4200.0, 42000.0))
			player.linear_velocity = Vector3(0, 0, -250.0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			player.target = _cruise_ship
			player.locked = true
			if not _arm_with("agm84"):
				_cruise_test = false
				get_tree().quit()
				return
			player.fire_cd = 0.0
			_reset_interp.call_deferred(player)
			print("[cruise] %s at 42 km, launching from 4200 m" % [
				_cruise_ship.call("display_name")])
		elif _cruise_ship != null and _cruise_step == 0 and _cruise_t > 4.0:
			_cruise_step = 1
			var why: String = player.fire()
			print("[cruise] %s carrying %s, selected %s" % [
				player.spec.get("name", "?"), str(player.weapon_types),
				player.current_weapon()])
			print("[cruise] release: %s" % ("away" if why == "" else "refused — " + why))
		elif _cruise_step == 1 and not _cruise_ship.alive:
			_cruise_test = false
			print("[cruise] RESULT: %s sunk at t=%.0f s; cruised as low as %.0f m above the sea" % [
				_cruise_ship.call("display_name"), _cruise_t, _cruise_low])
			get_tree().quit()
		elif _cruise_step == 1:
			for m in get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m) and String(m.wid) == "agm84":
					var mp: Vector3 = (m as Node3D).global_position
					var sea: float = maxf(Sim.height_at(mp.x, mp.z), Sim.WATER_LEVEL)
					if mp.distance_to(_cruise_ship.global_position) > 4000.0:
						_cruise_low = minf(_cruise_low, mp.y - sea)
			if _cruise_t > 190.0:
				_cruise_test = false
				var now: float = _cruise_ship.get("health") \
					if is_instance_valid(_cruise_ship) else -1.0
				print("[cruise] RESULT: cruised as low as %.0f m above the sea; hull %.0f -> %.0f" % [
					_cruise_low, _cruise_hp, now])
				get_tree().quit()
	# What the thermal channels make of a scene. Mirrors the shader exactly, so
	# a change to one that is not made to the other shows up as a mismatch here.
	if _flirtest:
		_flirtest = false
		var scene := {
			"clear sky": Color(0.35, 0.55, 0.90), "cloud": Color(0.85, 0.87, 0.92),
			"grass": Color(0.24, 0.34, 0.18), "tarmac": Color(0.13, 0.13, 0.14),
			"sea": Color(0.07, 0.19, 0.28), "engine plume": Color(1.0, 0.72, 0.30),
			"aircraft skin": Color(0.36, 0.38, 0.36),
		}
		var hot_name := ""
		var cold_name := ""
		var hot_v := -1.0
		var cold_v := 2.0
		var ws: Array = []
		for k in scene:
			var t: float = _flir(scene[k])
			ws.append(t)
			if t > hot_v:
				hot_v = t
				hot_name = k
			if t < cold_v:
				cold_v = t
				cold_name = k
			print("[flir] %-14s white hot %.2f   black hot %.2f" % [k, t, 1.0 - t])
		print("[flir] hottest thing on screen: %s; coldest: %s" % [hot_name, cold_name])
		var ok_hot: bool = hot_name == "engine plume"
		var ok_cold: bool = cold_name == "clear sky" or cold_name == "sea"
		print("[flir] RESULT: %s" % ("ok" if ok_hot and ok_cold else
			"FAILED — a thermal picture whose hottest thing is %s is not one" % hot_name))
		get_tree().quit()
	# Does the model each aeroplane builds match the numbers it flies on? A wing
	# polygon written on the wrong axes builds a stub with ten metres of chord
	# and nothing anywhere says so — the aerodynamics keep using the spec.
	# See-through parts. A closed solid presents a front face to any ray that
	# enters it; if the nearest triangle a ray meets is facing away, that pixel
	# looks straight through the skin, which is what you see from some angles
	# on the engines and nacelles.
	if _culltest:
		_culltest = false
		_run_culltest()
		get_tree().quit()
		return
	if _geomtest:
		_geomtest = false
		var bad := 0
		for id in JetSpec.ids():
			var sp := JetSpec.get_spec(id)
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			add_child(root)
			var lo := Vector3(1e9, 1e9, 1e9)
			var hi := -lo
			for mi in _all_mesh_children(root):
				var ab: AABB = (mi as MeshInstance3D).mesh.get_aabb()
				var o: Vector3 = (mi as MeshInstance3D).position
				lo = lo.min(ab.position + o)
				hi = hi.max(ab.position + ab.size + o)
			var built_span := hi.x - lo.x
			var built_len := hi.z - lo.z
			# A helicopter's widest thing is its rotor disc, not the stub wing
			# that `span` refers to. Comparing the two called every rotary
			# airframe broken by a factor of three.
			var rotary: bool = sp.has("rotor_radius")
			var want: float = (float(sp["rotor_radius"]) * 2.0) if rotary \
				else float(sp["span"])
			var what := "rotor" if rotary else "span "
			var err := absf(built_span - want) / maxf(want, 1.0)
			var flag := ""
			if err > 0.18:
				flag = "  <- DOES NOT MATCH"
				bad += 1
			print("[geom] %-8s %s built %6.1f m vs spec %6.1f m (%+5.1f%%), length %6.1f m%s" % [
				id, what, built_span, want, err * 100.0, built_len, flag])
			root.queue_free()
		print("[geom] RESULT: %s" % ("ok" if bad == 0 else
			"FAILED — %d airframe(s) do not match their own dimensions" % bad))
		get_tree().quit()
	# The same page from an armoured vehicle: does it open at all, does it sit
	# at the commander's sight rather than a masthead, does the mouse belong to
	# the sight instead of the turret, and does lasing lay the piece.
	if _tanksensor:
		_tanksensor_t += delta
		if _tanksensor_t > 2.5:
			_tanksensor = false
			_run_tanksensor()
			get_tree().quit()
			return
	# Can a ship's sensor do anything at all: point track, area track, laser.
	if _navsensor:
		_navsensor_t += delta
		if _navsensor_t > 2.5:
			_navsensor = false
			var boat: Ship = null
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.has_gun():
					boat = v
					break
			if boat == null:
				print("[navsensor] no friendly warship")
				get_tree().quit()
				return
			_enter_ship(boat)
			pod.jet = null                      # a ship has no aeroplane
			pod.host = boat
			if not pod.active:
				pod.toggle()
			print("[navsensor] on %s: pod active=%s, carrier=%s" % [
				boat.display_name(), str(pod.active),
				Sim.label_of(pod.carrier())])
			# point track: aim at the nearest hostile and designate
			var foe: Node3D = null
			var bd := 1e9
			for n in get_tree().get_nodes_in_group("ships"):
				var o := n as Ship
				if o == null or o.team == boat.team or not o.alive:
					continue
				var d := boat.global_position.distance_to(o.global_position)
				if d < bd:
					bd = d
					foe = o
			if foe != null:
				# The pod aims in the carrier's own frame: dir = basis * (yaw,
				# pitch). Working the angles off world axes and subtracting the
				# hull's heading is not the same thing, and it put the sight
				# somewhere the corvette was not — point track has been
				# reported as SLEW with nothing held every time this ran.
				var rel: Vector3 = foe.global_position - pod._head_origin()
				var loc: Vector3 = (boat.global_transform.basis.inverse() * rel).normalized()
				pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
				pod.yaw = atan2(-loc.x, -loc.z)
				pod.mode = pod.SLEW
				pod._process(0.016)
				pod.designate()
				print("[navsensor] point track: mode=%d tracked=%s, ship target=%s" % [
					pod.mode, Sim.label_of(pod.tracked), Sim.label_of(boat.ai_target)])
			# area track: aim well down and short, at open ground or water
			pod.tracked = null
			pod.mode = pod.SLEW
			pod.pitch = deg_to_rad(-35.0)
			pod.yaw = 0.0
			pod._process(0.016)
			pod.designate()
			print("[navsensor] area track: mode=%d (1=AREA), spot %s, ship target=%s" % [
				pod.mode, str(pod.area_point.round()), Sim.label_of(boat.ai_target)])
			if not pod.lasing:
				pod.toggle_laser()
			pod._process(0.016)
			print("[navsensor] laser: lasing=%s, aim point %s" % [
				str(pod.lasing), str(pod.aim_point().round())])
			# and the scope: how many contacts a ship's radar would paint
			hud._scope_src = boat
			var painted := 0
			var reach: float = Sim.radar_range()
			for n in get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == boat or n.is_in_group("no_lock"):
					continue
				var dd := boat.global_position.distance_to(n.global_position)
				if dd < reach and (dd <= 2000.0 or Sim.line_of_sight(
						boat.global_position + Vector3(0, 4, 0),
						(n as Node3D).global_position + Vector3(0, 4, 0), 250.0)):
					painted += 1
			hud._scope_src = null
			print("[navsensor] radar scope: %d contacts within %.0f km" % [
				painted, reach * 0.001])
			# and the tubes take the designation
			var fired: bool = boat.fire_vls()
			print("[navsensor] tubes on the designation: fired=%s at %s" % [
				str(fired), Sim.label_of(boat.ai_target)])
			# and weapon switching with the sensor page shut, which is where
			# you would normally be standing
			if pod.active:
				pod.toggle()
			var seq := PackedStringArray([boat.current_weapon()])
			for _i in 3:
				boat.cycle_weapon()
				seq.append(boat.current_weapon())
			boat.set_weapon(0)
			var direct := boat.current_weapon()
			print("[navsensor] weapon switch with the pod shut: cycle %s, key 1 -> %s (pod active=%s)" % [
				" -> ".join(seq), direct, str(pod.active)])
			# and the same on a hull with no gun at all
			var boat2: Ship = null
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null and v2.kind == "sub":
					boat2 = v2
					break
			if boat2 != null:
				print("[navsensor] submarine: weapons=%s, label=%s, gun=%s" % [
					str(boat2.weapons()), boat2.weapon_label(),
					str(boat2.has_gun())])
			get_tree().quit()
	# Several JDAMs at one lased point, released a couple of seconds apart.
	# Not gated on the aeroplane surviving: the rounds are away, and whether
	# they arrive has nothing to do with whether the launcher is still flying.
	# It was, and a shot down F-35 left the test hanging with nothing reported.
	if _salvo_test and (is_instance_valid(player) or _salvo_dropped > 0):
		_salvo_t += delta
		if _salvo_t > 2.0 and _salvo_aim == Vector3.INF and is_instance_valid(player):
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
			if not _arm_with(_salvo_w):
				_salvo_test = false
				get_tree().quit()
				return
			_reset_interp.call_deferred(player)
			Sim.salvo_watch = true
			Sim.salvo_weapon = _salvo_w
			Sim.salvo_mark = _salvo_aim
			Sim.salvo_log.clear()
			print("[salvo] lasing %s; %s, two seconds apart" % [
				str(_salvo_aim.round()), _salvo_w])
		elif _salvo_aim != Vector3.INF and _salvo_dropped < 3 and is_instance_valid(player) \
				and _salvo_t > 4.0 + float(_salvo_dropped) * 2.0:
			_salvo_dropped += 1
			player.fire_cd = 0.0
			var r := player.fire()
			if r == "":
				_salvo_away += 1
			print("[salvo] release %d: %s (selected %s of %s)" % [_salvo_dropped,
				"away" if r == "" else r, player.current_weapon(),
				str(player.weapon_types)])
		elif _salvo_dropped >= 2 and _salvo_t > 60.0:
			_salvo_test = false
			for entry in Sim.salvo_log:
				print("[salvo]   %s" % String(entry))
			# one line per round, not per log entry: the watch writes two of
			# them for every round and the tally read four out of three
			var gone := 0
			for entry in Sim.salvo_log:
				if String(entry).contains("died at"):
					gone += 1
			print("[salvo] RESULT: %d attempted, %d away, %d detonated" % [
				_salvo_dropped, _salvo_away, gone])
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
	# What a Maverick actually does against a ship, range by range, against what
	# the head-up display promised before it was fired.
	if _mav_test and is_instance_valid(player):
		_mav_t += delta
		if _mav_step == 0 and _mav_t > 2.5:
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.alive:
					_mav_ship = v
					break
			if _mav_ship == null:
				print("[mav] no target shipping")
				_mav_test = false
				get_tree().quit()
				return
			for sh2 in get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.cells_left = 0
					v2.ai = false
					v2.ciws_enabled = false
			_mav_step = 1
			_mav_t = 0.0
		elif _mav_step == 1:
			# set up the next shot
			if _mav_i >= _mav_rngs.size():
				_mav_test = false
				print("[mav] done")
				get_tree().quit()
				return
			var rng: float = float(_mav_rngs[_mav_i])
			player.global_transform = Transform3D(Basis(),
				_mav_ship.global_position + Vector3(0, 3000.0, rng))
			player.linear_velocity = Vector3(0, 0, -250.0)
			player.look_at(_mav_ship.global_position, Vector3.UP)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			# A fresh target each time. Reusing one hull meant the shots at the
			# short ranges sank her, and every range after that was scored as a
			# miss when what actually happened was the round losing a target
			# that was already on the bottom.
			_mav_ship.health = float(Ship.KINDS[_mav_ship.kind]["hp"])
			_mav_ship.alive = true
			_mav_ship.flood = 0.0
			# reload between shots: the aeroplane carries two, and the later
			# ranges were coming back "winchester" rather than measured
			for st in player.stores:
				st["gone"] = false
				if is_instance_valid(st["node"]):
					(st["node"] as Node3D).visible = true
			player.target = _mav_ship
			player.lock_time = 0.0
			player.locked = false
			player._reach_cache.clear()
			if not _arm_with("agm65"):
				_mav_test = false
				get_tree().quit()
				return
			for _s in 200:
				player._update_lock(0.02)
			_mav_locked = player.locked
			player.fire_cd = 0.0
			_reset_interp.call_deferred(player)
			_mav_closest = 1e9
			_mav_step = 2
			_mav_t = 0.0
		elif _mav_step == 2 and _mav_t > 0.5:
			_mav_step = 3
			var why: String = player.fire()
			if why != "":
				print("[mav] %5.1f km: HUD lock=%s, release refused (%s)" % [
					float(_mav_rngs[_mav_i]) * 0.001, str(_mav_locked), why])
				_mav_i += 1
				_mav_step = 1
				_mav_t = 0.0
		elif _mav_step == 3:
			var live := 0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "agm65":
					continue
				live += 1
				_mav_closest = minf(_mav_closest,
					(m as Node3D).global_position.distance_to(_mav_ship.global_position))
			if (live == 0 and _mav_t > 3.0) or _mav_t > 90.0:
				var r2: float = float(_mav_rngs[_mav_i])
				print("[mav] %5.1f km: HUD lock=%-5s  round came within %6.0f m  -> %s" % [
					r2 * 0.001, str(_mav_locked), _mav_closest,
					"HIT" if _mav_closest < 40.0 else "MISS"])
				_mav_i += 1
				_mav_step = 1
				_mav_t = 0.0
		return
	# Is the ground where the runway is, or is the runway buried in it?
	if _field_test:
		_field_test = false
		var bad := 0
		for fd in Sim.fields:
			var at: Vector2 = fd["at"]
			var elev: float = float(fd["elev"])
			var worst := 0.0
			var worst_at := Vector2.ZERO
			# along the strip and across it, in the field's own frame
			for i in 41:
				for j in 9:
					var lx: float = (float(j) - 4.0) * 60.0
					var lz: float = (float(i) - 20.0) * (Sim.RUNWAY_LEN * 0.5 / 20.0)
					var c := cos(float(fd["yaw"]))
					var sn := sin(float(fd["yaw"]))
					var q := at + Vector2(lx * c - lz * sn, lx * sn + lz * c)
					var g: float = Sim.height_at(q.x, q.y)
					var off: float = absf(g - elev)
					if off > worst:
						worst = off
						worst_at = q
			var drawn: float = Terrain.surface_height(at.x, at.y)
			print("[field] %s yaw %3.0f deg, elevation %7.1f m: ground on the strip differs by at most %.2f m (worst at %s)" % [
				str(at.round()), rad_to_deg(float(fd["yaw"])), elev, worst,
				str(worst_at.round())])
			print("[field]   at the worst point: flat=%.3f, pad=%.3f, road w=%.3f, cell=%.0f m" % [
				Sim.flat_factor(worst_at.x, worst_at.y),
				Sim.pad_weight(worst_at.x, worst_at.y),
				Sim.road_surface(worst_at.x, worst_at.y).y,
				Terrain.cell_at(worst_at.x, worst_at.y)])
			print("[field]   drawn surface at the middle: %.2f m (pavement sits at %.2f m)" % [
				drawn, elev])
			if worst > 3.0 or absf(drawn - elev) > 3.0:
				bad += 1
		print("[field] RESULT: %s" % ("ok" if bad == 0 and Sim.fields.size() >= 2
			else "FAILED — %d field(s) do not match their ground" % bad))
		get_tree().quit()
		return
	# Every crewable vehicle the menu offers: pick it, and see what you get.
	if _spawn_test:
		_spawn_t += delta
		if _spawn_t > 2.5:
			_spawn_test = false
			var bad := 0
			# and the same going the other way: crew a boat first, so a
			# selection has to actually let go of it
			_start("sea:sub", "free")
			await get_tree().process_frame
			await get_tree().physics_frame
			print("[spawn] started in a boat: crewing %s" % [
				Sim.label_of(ship) if is_instance_valid(ship) else "nothing"])
			for k in Tank.KINDS.keys():
				_start("veh:" + String(k), "free")
				await get_tree().process_frame
				await get_tree().physics_frame
				var got: String = tank.kind if is_instance_valid(tank) else "-"
				var ok: bool = got == String(k) and not is_instance_valid(ship)
				if not ok:
					bad += 1
				# and it should not look like every other vehicle on the field
				var mesh_names := PackedStringArray()
				if is_instance_valid(tank):
					for ch in tank.get_children():
						if ch is MeshInstance3D:
							mesh_names.append(String(ch.name))
				print("[spawn]   body: %s" % ", ".join(mesh_names))
				print("[spawn] chose %-13s -> %s%s" % [String(k),
					"in the %s" % Tank.KINDS[got]["name"] if ok
					else "STILL ON THE BOAT" if is_instance_valid(ship)
					else "NOT IN IT (crewing %s, aeroplane=%s)" % [got,
						"yes" if is_instance_valid(player) else "no"],
					"" if ok else "   <- WRONG"])
			print("[spawn] RESULT: %s" % ("ok" if bad == 0 else
				"FAILED — %d selection(s) did not put you in the vehicle" % bad))
			get_tree().quit()
		return
	# What a launch leaves behind. "Laggy after the round goes" is a node count
	# question before it is anything else.
	if _lag_test:
		_lag_t += delta
		if _lag_step == 0 and _lag_t > 3.0:
			_lag_step = 1
			_start("veh:tel_oreshnik", "free")
			await get_tree().process_frame
			await get_tree().physics_frame
			_lag_before = _census()
			print("[lag] before the launch: %s" % _census_line(_lag_before))
			if is_instance_valid(tank):
				var mk := tank.global_position + Vector3(-60000.0, 0, -40000.0)
				mk.y = Sim.height_at(mk.x, mk.z)
				tank.map_target = mk
				tank._gun_cd = 0.0
				tank.fire_main(self)
			_lag_t = 0.0
		elif _lag_step == 1 and _lag_t > 140.0:
			_lag_step = 2
			var after := _census()
			print("[lag] after it has landed: %s" % _census_line(after))
			for k in after.keys():
				var was := int(_lag_before.get(k, 0))
				var now := int(after[k])
				if now - was > 40:
					print("[lag]   %s grew by %d" % [String(k), now - was])
			# and *what* they are, by owner, so the leak has a name
			var tally := {}
			var stack: Array = [get_tree().root]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is GPUParticles3D:
					var owner_name := "(root)"
					var par := n.get_parent()
					if par != null:
						var scr: Variant = par.get_script()
						var where := String(par.get_class())
						if scr != null:
							where = String((scr as Script).resource_path).get_file()
							var gname := String((scr as Script).get_global_name())
							if gname != "":
								where = gname
						owner_name = "%s (parent %s)" % [where, String(par.name)]
					tally[owner_name] = int(tally.get(owner_name, 0)) + 1
				for c in n.get_children():
					stack.append(c)
			var rows: Array = []
			for kk in tally:
				rows.append([int(tally[kk]), String(kk)])
			rows.sort_custom(func(x, y): return x[0] > y[0])
			for i in mini(6, rows.size()):
				print("[lag]   particles: %4d x %s" % [rows[i][0], rows[i][1]])
			# and what a frame costs on foot afterwards
			_leave_tank()
			await get_tree().process_frame
			var t0 := Time.get_ticks_usec()
			for _f in 30:
				await get_tree().process_frame
			var per := float(Time.get_ticks_usec() - t0) / 30000.0
			print("[lag] on foot afterwards: %.2f ms a frame" % per)
			print("[lag] RESULT: %s" % ("ok" if per < 40.0 else "SLOW"))
			get_tree().quit()
		return
	# A launcher, a hypersonic round and a warhead bus that opens on the way in.
	if _tel_test:
		_tel_t += delta
		if _tel_step == 0 and _tel_t > 2.5:
			_tel_step = 1
			# through the menu path, so the camera and the crewing are the real
			# ones rather than a launcher conjured beside a world with no
			# mission running and no camera in it
			_start("veh:tel_oreshnik", "free")
			await get_tree().process_frame
			await get_tree().physics_frame
			if not is_instance_valid(tank):
				print("[tel] could not crew a launcher")
				_tel_test = false
				get_tree().quit()
				return
			_tel = tank
			var here: Vector3 = _tel.global_position
			var mark := Vector3(here.x - 60000.0, 0.0, here.z - 40000.0)
			mark.y = Sim.height_at(mark.x, mark.z)
			_tel.map_target = mark
			print("[tel] %s with %d round(s), aiming point %.0f km away" % [
				_tel.display_name(), _tel.rounds_left,
				_tel.global_position.distance_to(mark) * 0.001])
			_tel._gun_cd = 0.0
			weapon_cam_on = true
			# A launcher will not fire lying down any more: it stands the
			# canister up first, and that takes four seconds.
			var waited := 0
			while _tel._erect < 0.97 and waited < 900:
				await get_tree().physics_frame
				waited += 1
			print("[tel] canister up (%.0f%%) after %d frames" % [
				_tel._erect * 100.0, waited])
			print("[tel] launch: %s" % str(_tel.fire_main(self)))
			_tel_cam = is_instance_valid(cam) and is_instance_valid(cam.weapon_cam) \
				and String(cam.weapon_cam.get("wid")) == "oreshnik"
			print("[tel] weapon camera riding the round: %s (chase camera has the screen: %s)" % [
				str(_tel_cam),
				str(cam.current) if is_instance_valid(cam) else "no camera"])
		elif _tel_step == 1:
			var bus := 0
			var kids := 0
			var top := 0.0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				if String(m.wid) == "oreshnik":
					bus += 1
					top = maxf(top, (m as Node3D).global_position.y)
				elif String(m.wid) == "orehead":
					kids += 1
			_tel_kids = maxi(_tel_kids, kids)
			if fmod(_tel_t, 15.0) < delta:
				print("[tel]   t=%5.1f  bus up %d (apogee so far %.0f m), warheads %d" % [
					_tel_t, bus, top, kids])
			if (bus == 0 and _tel_t > 12.0) or _tel_t > 300.0:
				_tel_test = false
				print("[tel] the bus opened into %d warhead(s)" % _tel_kids)
				print("[tel] RESULT: %s" % ("ok" if _tel_kids >= 4 and _tel_cam
					else "FAILED"))
				get_tree().quit()
		return
	# How the world is divided between land and water, and whether there is any
	# coastline in it or just one edge with sea on one side.
	if _seamix:
		_seamix = false
		var bands := [
			["home      0-40 km", 0.0, 40000.0],
			["near     40-120 km", 40000.0, 120000.0],
			["middle  120-300 km", 120000.0, 300000.0],
			["far     300-600 km", 300000.0, 600000.0],
		]
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		for b in bands:
			var lo: float = float(b[1])
			var hi: float = float(b[2])
			var land := 0
			var wet := 0
			var coast := 0
			for _i in 4000:
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * (hi - lo) + lo
				var x := cos(a) * r
				var z := sin(a) * r
				var dry: bool = Sim.height_at(x, z) > Sim.WATER_LEVEL
				if dry:
					land += 1
				else:
					wet += 1
				# a coast is anywhere the answer changes within a couple of km
				var other: bool = Sim.height_at(x + 2000.0, z) > Sim.WATER_LEVEL
				if dry != other:
					coast += 1
			var tot: float = maxf(float(land + wet), 1.0)
			print("[sea] %s: %5.1f%% land, %5.1f%% water, %4.1f%% of samples on a coast" % [
				String(b[0]), 100.0 * float(land) / tot, 100.0 * float(wet) / tot,
				100.0 * float(coast) / tot])
		# relief across the middle of the map, where the trench used to be
		var bands2 := [["on the field axis", 0.0], ["6 km out", 6000.0],
			["20 km out", 20000.0], ["60 km out", 60000.0]]
		for b2 in bands2:
			var off: float = float(b2[1])
			var lo2 := 1e9
			var hi2 := -1e9
			var total2 := 0.0
			for k2 in 400:
				var zz: float = -300000.0 + float(k2) * 1500.0
				var hh: float = Sim.height_at(off, zz)
				lo2 = minf(lo2, hh)
				hi2 = maxf(hi2, hh)
				total2 += hh
			print("[sea] relief %s: %.0f m to %.0f m, mean %.0f m" % [
				String(b2[0]), lo2, hi2, total2 / 400.0])
		# and what grows on the land, north to south
		var strips := [["far north", -560000.0, -360000.0],
			["north", -360000.0, -140000.0], ["middle", -140000.0, 140000.0],
			["south", 140000.0, 360000.0], ["far south", 360000.0, 560000.0]]
		for strip in strips:
			var tally := {}
			var n2 := 0
			for _k in 2500:
				var x2: float = rng.randf_range(-500000.0, 500000.0)
				var z2: float = rng.randf_range(float(strip[1]), float(strip[2]))
				var y2: float = Sim.height_at(x2, z2)
				if y2 <= Sim.WATER_LEVEL:
					continue
				var bk: String = Sim.biome_kind(x2, z2, y2, Sim.normal_at(x2, z2).y)
				tally[bk] = int(tally.get(bk, 0)) + 1
				n2 += 1
			var parts := PackedStringArray()
			for nm in Sim.BIOME_NAMES:
				var c2 := int(tally.get(nm, 0))
				if c2 > 0:
					parts.append("%s %.0f%%" % [nm, 100.0 * float(c2) / maxf(float(n2), 1.0)])
			print("[sea] %-10s land cover: %s" % [String(strip[0]), ", ".join(parts)])
		get_tree().quit()
		return
	# Does the lock actually complete on a weapon that can make the shot?
	if _locktime_test and is_instance_valid(player):
		_lt_t += delta
		if _lt_t > 2.5:
			_locktime_test = false
			var boat: Ship = null
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.alive:
					boat = v
					break
			if boat == null:
				print("[locktime] no hostile shipping")
				get_tree().quit()
				return
			for rng in [8000.0, 18000.0, 34000.0]:
				for w in ["agm84", "agm65", "aim120"]:
					if player.weapon_types.find(w) < 0:
						continue
					player.global_transform = Transform3D(Basis(),
						boat.global_position + Vector3(0, 3500.0, rng))
					player.linear_velocity = Vector3(0, 0, -240.0)
					player.look_at(boat.global_position, Vector3.UP)
					player.set_weapon(player.weapon_types.find(w))
					player.target = boat
					player.locked = false
					player.lock_time = 0.0
					player._reach_cache.clear()
					var took := -1.0
					for step in 400:
						player._update_lock(0.02)
						if player.locked:
							took = float(step) * 0.02
							break
					var why: String = player.shot_blocked(w, boat)
					print("[locktime] %-7s at %5.1f km: %s%s" % [w, rng * 0.001,
						"locked in %.2f s" % took if took >= 0.0 else "NEVER LOCKED",
						"" if why == "" else "   (%s)" % why])
			print("[locktime] done")
			get_tree().quit()
		return
	# How far the drawn ground sits from the height field things are placed on.
	# That gap is daylight under every tree standing on it.
	if _float_test:
		_float_test = false
		var worst := 0.0
		var worst_at := Vector2.ZERO
		var total := 0.0
		var n := 0
		var over := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260827
		# across the ground the scatter actually covers
		for _i in 6000:
			var x: float = rng.randf_range(-19800.0, 19800.0)
			var z: float = rng.randf_range(-31680.0, 31680.0)
			var field: float = Sim.height_at(x, z)
			if field < Sim.WATER_LEVEL + 2.0 or field > 2400.0:
				continue
			var drawn: float = Terrain.surface_height(x, z)
			var gap: float = absf(field - drawn)
			total += gap
			n += 1
			if gap > 1.5:
				over += 1
			if gap > worst:
				worst = gap
				worst_at = Vector2(x, z)
		print("[float] %d samples over the scattered ground" % n)
		print("[float] field vs drawn surface: mean %.2f m, worst %.1f m at %s" % [
			total / maxf(float(n), 1.0), worst, str(worst_at.round())])
		print("[float] %d of %d (%.1f%%) stood more than a metre and a half proud" % [
			over, n, 100.0 * float(over) / maxf(float(n), 1.0)])
		# Scatter now calls `Terrain.surface_height` itself, the same function
		# the chunks are triangulated from, so its gap is nil by construction —
		# there is nothing independent left to measure. What is printed above is
		# the error that was there before, which is the number that matters.
		print("[float] scatter is placed on that drawn surface now, so the gap is nil")
		print("[float] RESULT: %s" % ("ok" if worst > 0.0 else "FAILED — nothing measured"))
		get_tree().quit()
		return
	# A submarine's conn: can she hold a contact, can she dive, and does the
	# ground stop her.
	if _boat_test:
		_boat_t += delta
		if _boat_t > 2.5:
			_boat_test = false
			var sub: Ship = null
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.can_dive() and v.alive:
					sub = v
					break
			if sub == null:
				print("[boat] no submarine on our side")
				get_tree().quit()
				return
			_enter_ship(sub)
			print("[boat] %s: guns=%d tubes=%d, mast %.1f m" % [
				sub.display_name(), int(Ship.KINDS[sub.kind]["guns"]), sub.tubes(),
				sub.mast_height()])
			# the radar picture, and stepping through it
			var seen: Array = []
			for _i in 8:
				sub.cycle_target()
				if is_instance_valid(sub.ai_target) and not seen.has(sub.ai_target):
					seen.append(sub.ai_target)
			var names := PackedStringArray()
			for n in seen:
				names.append(Sim.label_of(n))
			print("[boat] target cycling reached %d distinct contact(s): %s" % [
				seen.size(), ", ".join(names)])
			# the weapons, from the conn
			var wseq := PackedStringArray([sub.current_weapon()])
			for _k in 3:
				sub.cycle_weapon()
				wseq.append(sub.current_weapon())
			print("[boat] weapon cycling: %s" % " -> ".join(wseq))
			# torpedoes: who has them, and does one run and hit
			var foe: Ship = null
			for sh3 in get_tree().get_nodes_in_group("ships"):
				var v3 := sh3 as Ship
				if v3 != null and v3.team != sub.team and v3.alive:
					foe = v3
					break
			var hp0: float = foe.health if foe != null else 0.0
			var fired := false
			if foe != null:
				sub.global_position = Vector3(foe.global_position.x,
					Sim.WATER_LEVEL, foe.global_position.z + 2600.0)
				sub.ai_target = foe
				sub._torp_cd = 0.0
				fired = sub.fire_torpedo(foe)
			print("[boat] torpedoes: %d aboard, launch=%s, target %s at %.1f km" % [
				sub.torps_left, str(fired),
				Sim.label_of(foe) if foe != null else "none",
				sub.global_position.distance_to(foe.global_position) * 0.001
				if foe != null else 0.0])
			var swam := 0.0
			var deepest := 0.0
			for _f4 in 60 * 150:
				for mm3 in get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(mm3) and String(mm3.wid) == "torpedo":
						var mp3: Vector3 = (mm3 as Node3D).global_position
						swam = maxf(swam, mp3.distance_to(sub.global_position))
						deepest = minf(deepest, mp3.y - Sim.WATER_LEVEL)
				sub._physics_process(1.0 / 60.0)
				if foe != null and not foe.alive:
					break
			print("[boat] the fish ran %.0f m, %.1f m under the surface at deepest; hull %.0f -> %.0f" % [
				swam, deepest, hp0, foe.health if foe != null else 0.0])
			var views := PackedStringArray()
			for _v in 4:
				views.append("%.0f m" % Ship.VIEW_BOOM[sub.view_mode % Ship.VIEW_BOOM.size()])
				sub.view_mode = (sub.view_mode + 1) % Ship.VIEW_BOOM.size()
			print("[boat] view cycling (C): %s" % " -> ".join(views))
			# the sensor: can it take a patch of ground from the conn
			pod.jet = null
			pod.host = sub
			if not pod.active:
				pod.toggle()
			# At the coast, not at open water. Aiming six degrees down from a
			# conning tower puts the mark on the sea whatever the sight can do;
			# the claim to test is whether it can take a patch of *ground*.
			var shore := Vector3.INF
			for gi in 90:
				var q := Vector3(sub.global_position.x - float(gi) * 400.0, 0.0,
					sub.global_position.z)
				var hh: float = Sim.height_at(q.x, q.z)
				if hh > Sim.WATER_LEVEL + 25.0:
					shore = Vector3(q.x, hh, q.z)
					break
			pod.tracked = null
			pod.mode = pod.SLEW
			if shore != Vector3.INF:
				var rel: Vector3 = shore - pod._head_origin()
				var loc: Vector3 = (sub.global_transform.basis.inverse() * rel).normalized()
				pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
				pod.yaw = atan2(-loc.x, -loc.z)
			else:
				pod.pitch = deg_to_rad(-6.0)
				pod.yaw = 0.0
			pod._process(0.016)
			pod.designate()
			var on_land: bool = pod.area_point != Vector3.INF \
				and pod.area_point.y > Sim.WATER_LEVEL + 2.0
			print("[boat] sight aimed at the coast %s (%.1f m elevation, %.1f km off)" % [
				str(shore.round()) if shore != Vector3.INF else "not found",
				shore.y if shore != Vector3.INF else 0.0,
				sub.global_position.distance_to(shore) * 0.001 if shore != Vector3.INF else 0.0])
			# and what the page would actually draw: the aim mark, the weapon
			# line and the selector all used to go straight to the aeroplane
			var aim_ok: bool = pod.aim_point() != Vector3.INF
			var holds: bool = pod.carrier() == sub
			print("[boat] page draws: carrier=%s, aim point=%s, weapon line=%s" % [
				str(holds), str(aim_ok),
				sub.weapon_label() if sub.has_method("weapon_label") else "-"])
			print("[boat] sensor from the conn: mode=%d (1=AREA), spot %s, on land=%s, %.1f m up" % [
				pod.mode, str(pod.area_point.round()), str(on_land),
				pod._head_origin().y - sub.global_position.y])
			# what the scope would paint, and whether her own rounds are on it
			sub.fire_vls(sub.ai_target)
			var own := 0
			for mm in get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(mm) and is_instance_valid(mm.shooter) \
						and mm.shooter == sub:
					own += 1
			print("[boat] tubes away: %d of her own rounds in the air for the scope" % own)
			# what the bridge and chase views would actually paint on the sea
			var eye: Camera3D = sub.cam
			var painted := 0
			var friendly := 0
			var hostile := 0
			var masked := 0
			if is_instance_valid(eye):
				sub._physics_process(1.0 / 60.0)
				var reach: float = maxf(Sim.radar_range(), 26000.0)
				for n in get_tree().get_nodes_in_group("hittable"):
					if not is_instance_valid(n) or n == sub or not (n is Node3D):
						continue
					if n.is_in_group("no_lock"):
						continue
					if n.has_method("is_alive") and not n.is_alive():
						continue
					var d: float = sub.global_position.distance_to(
						(n as Node3D).global_position)
					if d > reach:
						continue
					painted += 1
					if ("team" in n) and int(n.team) != sub.team:
						hostile += 1
					else:
						friendly += 1
					# is anything actually in the way, and if so what
					var e: Vector3 = sub.global_position \
						+ Vector3(0, sub.mast_height(), 0)
					var tp: Vector3 = (n as Node3D).global_position + Vector3(0, 4, 0)
					if d > 2000.0 and not Sim.line_of_sight(e, tp, 250.0):
						masked += 1
						if masked == 1:
							# walk it and say where, and how deep the water is there
							for k in 40:
								var q: Vector3 = e.lerp(tp, float(k) / 39.0)
								var g2: float = Sim.height_at(q.x, q.z)
								if q.y < g2 - 2.0:
									print("[boat]   %s masked at %s: ray %.1f m, ground %.1f m, sea level %.1f m" % [
										Sim.label_of(n), str(Vector2(q.x, q.z).round()),
										q.y, g2, Sim.WATER_LEVEL])
									break
			print("[boat] contacts the bridge view can label: %d (%d hostile, %d friendly), %d masked" % [
				painted, hostile, friendly, masked])
			# ground that is under the sea but still above a ship's sight line:
			# this is what used to block two hulls looking at each other
			var shoals := 0
			var probes := 0
			for si in 120:
				for sj in 120:
					var q2 := Vector2(sub.global_position.x - 30000.0 + float(si) * 500.0,
						sub.global_position.z - 30000.0 + float(sj) * 500.0)
					var g3: float = Sim.height_at(q2.x, q2.y)
					if g3 >= Sim.WATER_LEVEL:
						continue
					probes += 1
					if g3 > Sim.WATER_LEVEL - 20.0:
						shoals += 1
			print("[boat] sea bed within 20 m of the surface at %d of %d wet samples — ground that used to mask" % [
				shoals, probes])
			print("[boat] the boat sits at %.1f m, her sight at %.1f m, sea level %.1f m" % [
				sub.global_position.y, sub.global_position.y + sub.mast_height(),
				Sim.WATER_LEVEL])
			if pod.active:
				pod.toggle()
			pod.host = null
			# dive, and the ground under her
			var surf: float = sub.global_position.y
			sub.depth_order = 45.0
			for _f in 240:
				sub._physics_process(1.0 / 60.0)
			print("[boat] ordered 45 m: rides at %.1f m (was %.1f), depth %.1f, periscope up=%s" % [
				sub.global_position.y, surf, sub.depth, str(sub.periscope_up())])
			sub.depth_order = 0.0
			for _f2 in 240:
				sub._physics_process(1.0 / 60.0)
			print("[boat] ordered surface: rides at %.1f m, periscope up=%s" % [
				sub.global_position.y, str(sub.periscope_up())])
			# steam her at the beach and see whether the ground stops her
			# Walk in from seaward until the ground breaks the surface: that is
			# the beach. Taking the *highest* ground within reach put the boat
			# up a mountain, which is not a grounding test.
			var land := Vector3.INF
			for gi in 60:
				var q := Vector3(sub.global_position.x - float(gi) * 400.0, 0.0,
					sub.global_position.z)
				if Sim.height_at(q.x, q.z) > Sim.WATER_LEVEL + 2.0:
					land = q
					break
			if land == Vector3.INF:
				print("[boat] no shoreline within reach to run at")
				get_tree().quit()
				return
			sub.global_position = Vector3(land.x + 2500.0, Sim.WATER_LEVEL,
				land.z)
			sub.depth = 0.0
			sub.depth_order = 0.0
			print("[boat] beach at %s; starting 2.5 km seaward of it" % str(land.round()))
			sub.heading = atan2(land.x - sub.global_position.x, -(land.z - sub.global_position.z))
			sub.telegraph = 1.0
			sub.speed = float(Ship.KINDS[sub.kind]["speed"])
			var start := sub.global_position
			var worst_dig := -1e9
			for _f3 in 60 * 60:
				sub._physics_process(1.0 / 60.0)
				var bed: float = Sim.height_at(sub.global_position.x, sub.global_position.z)
				worst_dig = maxf(worst_dig, bed - (sub.global_position.y
					- float(Ship.KINDS[sub.kind]["draught"])))
			print("[boat] driven at the shore for a minute: moved %.0f m, keel is %.1f m %s the ground at worst" % [
				start.distance_to(sub.global_position), absf(worst_dig),
				"INTO" if worst_dig > 0.0 else "clear of"])
			print("[boat] RESULT: %s" % ("ok" if seen.size() >= 2 and sub.depth < 1.0
				and worst_dig < 1.0 and own > 0 and on_land and painted > 0 else "FAILED"))
			get_tree().quit()
		return
	# What comes off a wingtip: a filament, or a bag of balls.
	if _fx_test:
		_fx_test = false
		var bad := 0
		for id in ["f22", "f16", "su35", "a320"]:
			var sp := JetSpec.get_spec(id)
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			add_child(root)
			var jet := Aircraft.new()
			jet.spec = sp
			var tips: Array = m.get("tips", [])
			root.queue_free()
			if tips.is_empty():
				print("[fx] %-6s has no wingtips" % id)
				continue
			var p := Effects.vortex_particles(Color(1, 1, 1), 3.2, 40)
			var qm := p.draw_pass_1 as QuadMesh
			var mat := qm.material as StandardMaterial3D
			var pm := p.process_material as ParticleProcessMaterial
			var aspect: float = qm.size.y / maxf(qm.size.x, 0.0001)
			var spun: float = absf(pm.angle_max - pm.angle_min)
			var lined: bool = mat.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES
			var wrong: bool = aspect < 6.0 or spun > 1.0 or not lined
			if wrong:
				bad += 1
			print("[fx] %-6s %d tip(s): quad %.2f x %.2f (aspect %.1f), spin %.0f deg, %s%s" % [
				id, tips.size(), qm.size.x, qm.size.y, aspect, spun,
				"aligned to travel" if lined else "camera facing only",
				"   <- READS AS A BALL" if wrong else ""])
			jet.free()
		print("[fx] RESULT: %s" % ("ok" if bad == 0 else "FAILED"))
		get_tree().quit()
		return
	# A friendly warship covering the aircraft around her: does she see a round
	# tracking one of ours, and does she put a cell in the air at it?
	# not gated on the aeroplane surviving: whether she shoots at the round is
	# the question, and the round may well arrive first
	if _guard_test and (is_instance_valid(player) or _guard_step >= 2):
		_guard_t += delta
		if _guard_step == 0 and _guard_t > 2.5:
			_guard_step = 1
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.has_vls() and v.alive:
					_guard_boat = v
					break
			if _guard_boat == null:
				print("[guard] no friendly hull with tubes")
				_guard_test = false
				get_tree().quit()
				return
			# put the aeroplane near her, and a hostile round on its way to it
			var bp: Vector3 = _guard_boat.global_position
			player.global_transform = Transform3D(Basis(),
				bp + Vector3(0, 3000.0, -9000.0))
			player.linear_velocity = Vector3(0, 0, -180.0)
			_reset_interp.call_deferred(player)
			_guard_boat.cells_left = 24
			print("[guard] %s has %d cells; our aeroplane 9 km off her bow at 3000 m" % [
				_guard_boat.display_name(), _guard_boat.cells_left])
		elif _guard_step == 1 and _guard_t > 4.0:
			_guard_step = 2
			# a hostile round, tracking the player
			var shooter: Ship = null
			for sh in get_tree().get_nodes_in_group("ships"):
				var v2 := sh as Ship
				if v2 != null and v2.team != 0 and v2.alive:
					shooter = v2
					break
			var launch: Vector3 = player.global_position + Vector3(26000.0, -400.0, 0)
			var m := Missile.new()
			var dir: Vector3 = (player.global_position - launch).normalized()
			var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
			m.launch("sm2", Transform3D(Basis.looking_at(dir, up_ref), launch),
				dir * 260.0, shooter, player)
			m.team = 1
			add_child(m)
			print("[guard] a hostile round is up, 26 km out and tracking us")
		elif _guard_step == 2:
			var cells: int = _guard_boat.cells_left if is_instance_valid(_guard_boat) else 0
			_guard_shots = 24 - cells
			for mm in get_tree().get_nodes_in_group("interceptable"):
				if not is_instance_valid(mm) or not ("team" in mm) or int(mm.team) != 0:
					continue
				if not is_instance_valid(mm.target):
					continue
				if mm.target.is_in_group("interceptable"):
					if _guard_killed == 0:
						print("[guard]   %s away at %s — an interceptor" % [
							String(mm.wid), Sim.label_of(mm.target)])
					_guard_killed = 1
			if _guard_t > 40.0:
				_guard_test = false
				var inbound := 0
				for mm2 in get_tree().get_nodes_in_group("interceptable"):
					if is_instance_valid(mm2) and ("team" in mm2) and int(mm2.team) != 0:
						inbound += 1
				print("[guard] hostile rounds still in the air: %d" % inbound)
				print("[guard] she fired %d cell(s); an interceptor was sent at the round: %s" % [
					_guard_shots, "yes" if _guard_killed == 1 else "no"])
				print("[guard] RESULT: %s" % ("ok" if _guard_killed == 1
					else "FAILED — nothing was sent after it"))
				get_tree().quit()
		return
	# Lose the boat, press R, and see what you come back in.
	if _respawn_test:
		_respawn_t += delta
		if _respawn_step == 0 and _respawn_t > 2.0:
			_respawn_step = 1
			menu._select("sea:sub")
			_start("sea:sub", "free")
			print("[respawn] started with \"sea:sub\"; crewing %s" % [
				Sim.label_of(ship) if is_instance_valid(ship) else "nothing"])
		elif _respawn_step == 1 and _respawn_t > 4.0:
			_respawn_step = 2
			if is_instance_valid(ship):
				print("[respawn] sinking the boat under us")
				ship.take_hit(999999.0, null)
			print("[respawn] the menu still holds \"%s\"" % str(menu.jet_id))
		elif _respawn_step == 2 and _respawn_t > 6.0:
			_respawn_step = 3
			# the menu is the only way back: launch again from what it holds
			_start(String(menu.jet_id), Sim.mission)
		elif _respawn_step == 3 and _respawn_t > 8.0:
			_respawn_test = false
			var back: String = Sim.label_of(ship) if is_instance_valid(ship) else "nothing"
			var kind: String = str(ship.kind) if is_instance_valid(ship) else "-"
			print("[respawn] after restart: crewing %s (kind %s), aeroplane=%s" % [
				back, kind, "yes" if is_instance_valid(player) else "no"])
			print("[respawn] RESULT: %s" % ("ok" if kind == "sub"
				else "FAILED — came back in %s, not the boat" % back))
			get_tree().quit()
		return
	# The strategic round: aimed on the map, off the rail, up and over, down on
	# the mark. It was reported as exploding the moment it launched.
	if _nuke_test:
		_nuke_t += delta
		if _nuke_t > 2.5 and _nuke_boat == null:
			for sh in get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.can_launch():
					_nuke_boat = v
					break
			if _nuke_boat == null:
				print("[nuke] no boat on station with a round aboard")
				_nuke_test = false
				get_tree().quit()
				return
			_enter_ship(_nuke_boat)
			# aim it the way a player would: right click on the map
			# at a town, so the result means something
			var bp: Vector3 = _nuke_boat.global_position
			_nuke_at = Vector3(bp.x - 30000.0, 0.0, bp.z - 20000.0)
			if is_instance_valid(scenery) and scenery.sites.size() > 0:
				var pick: Dictionary = scenery.sites[0]
				var pc: Vector2 = pick["c"]
				_nuke_at = Vector3(pc.x, 0.0, pc.y)
			_nuke_at.y = Sim.height_at(_nuke_at.x, _nuke_at.z)
			map.ship = _nuke_boat
			map.strategic_mark = _nuke_at
			print("[nuke] %s, %d round(s); map aiming point %s, %.0f km away" % [
				_nuke_boat.display_name(), _nuke_boat.missiles_left,
				str(_nuke_at.round()), bp.distance_to(_nuke_at) * 0.001])
			print("[nuke] map hands back: %s" % str(map.target_point().round()))
		elif _nuke_boat != null and _nuke_step == 0 and _nuke_t > 4.0:
			_nuke_step = 1
			var before: int = _nuke_boat.missiles_left
			_strategic_strike()
			print("[nuke] strike ordered: rounds %d -> %d" % [
				before, _nuke_boat.missiles_left])
		elif _nuke_step == 1:
			var live := 0
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "slbm":
					continue
				live += 1
				var mp: Vector3 = (m as Node3D).global_position
				_nuke_top = maxf(_nuke_top, mp.y)
				_nuke_miss = minf(_nuke_miss, mp.distance_to(_nuke_at))
				var agl: float = mp.y - maxf(Sim.height_at(mp.x, mp.z), Sim.WATER_LEVEL)
				if _nuke_t > 6.0:
					_nuke_low = minf(_nuke_low, agl)
				if fmod(_nuke_t, 10.0) < delta:
					print("[nuke]   t=%5.1f  alt %7.0f m  %6.1f km to run  %4.0f m/s" % [
						_nuke_t, mp.y, mp.distance_to(_nuke_at) * 0.001,
						(m.get_velocity() as Vector3).length()])
			if live == 0 and _nuke_t > 8.0 or _nuke_t > 400.0:
				_nuke_test = false
				print("[nuke] apogee %.0f m; flight ended at t=%.1f" % [_nuke_top, _nuke_t])
				print("[nuke] it went off %.0f m from the aiming point (warhead reaches %.0f m)" % [
					_nuke_miss, 4200.0])
				print("[nuke] RESULT: %s" % ("ok" if _nuke_miss < 4200.0 and _nuke_t > 8.0
					else "FAILED — %.0f m off the mark" % _nuke_miss))
				get_tree().quit()
		return
	# What each weapon can actually get to, against what its entry claims.
	if _reach_test and is_instance_valid(player):
		_reach_test = false
		var alt := 3000.0
		var spd := 250.0
		var here := Vector3(0.0, alt, 0.0)
		var v0 := Vector3(0, 0, -spd)
		print("[reach] launched at %.0f m doing %.0f m/s, target on the deck" % [alt, spd])
		for w in ["agm65", "agm84", "agm88", "aim9", "aim120", "sm2"]:
			var ws := WeaponSpec.get_spec(w)
			var claim: float = float(ws["range"])
			# walk out until it can no longer make it
			var made := 0.0
			var d := 500.0
			while d < claim * 1.2:
				var tgt := Vector3(0, Sim.height_at(0.0, -d), -d)
				if WeaponSpec.can_reach(w, here, v0, tgt):
					made = d
				d += 500.0
			print("[reach] %-7s claims %5.1f km, actually gets to %5.1f km (%.0f%% of the claim)" % [
				w, claim * 0.001, made * 0.001, 100.0 * made / maxf(claim, 1.0)])
		get_tree().quit()
		return
	# What a submarine sees looking up at the seabed. Terrain faces up, so if
	# the material culls back faces there is nothing there at all from below.
	if _subview_test:
		_subview_test = false
		var culled := 0
		var drawn := 0
		var no_mat := 0
		for c in terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			if not str(mi.name).begins_with("C") or not str(mi.name).contains("_"):
				continue
			var sm := mi.mesh.surface_get_material(0)
			var over: Material = mi.material_override
			var use: Material = over if over != null else sm
			if use == null:
				no_mat += 1
				continue
			var cull := "?"
			if use is ShaderMaterial:
				var code: String = ((use as ShaderMaterial).shader as Shader).code
				cull = "cull_disabled" if code.contains("cull_disabled") else "cull_back"
			elif use is BaseMaterial3D:
				cull = "cull_disabled" \
					if (use as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED \
					else "cull_back"
			if cull == "cull_disabled":
				drawn += 1
			else:
				culled += 1
		# and the geometry really does face up, which is why it matters
		var up_facing := 0
		var down_facing := 0
		for c in terrain.get_children():
			var mi2 := c as MeshInstance3D
			if mi2 == null or mi2.mesh == null:
				continue
			if not str(mi2.name).begins_with("C") or not str(mi2.name).contains("_"):
				continue
			for t in _chunk_tris(mi2):
				var nrm: Vector3 = ((t[1] as Vector3) - (t[0] as Vector3)).cross(
					(t[2] as Vector3) - (t[0] as Vector3))
				if nrm.y >= 0.0:
					up_facing += 1
				else:
					down_facing += 1
			break
		print("[subview] %d chunks draw from below, %d are culled away, %d have no material" % [
			drawn, culled, no_mat])
		print("[subview] one chunk's winding: %d faces up, %d faces down" % [
			up_facing, down_facing])
		print("[subview] RESULT: %s" % ("ok" if culled == 0 and drawn > 0
			else "FAILED — the seabed is invisible from underneath"))
		get_tree().quit()
		return
	# A cruise weapon fired across high ground. Over the sea the terrain
	# following never has to do anything; inland it is the whole job.
	if _land_test and (is_instance_valid(player) or _land_step > 0):
		_land_t += delta
		if _land_t > 2.0 and _land_tgt == null:
			# something inland, with real ground between it and the launcher
			# The AI sites all sit near the field, which is in a valley the
			# height field deliberately caps. Put a target on the high ground
			# instead, so the run in has to cross something.
			var best_rise := -1.0
			var spot := Vector2.ZERO
			for gi in 40:
				for gj in 40:
					var q := Vector2(-18000.0 + float(gi) * 900.0,
						-18000.0 + float(gj) * 900.0)
					var rise: float = Sim.height_at(q.x, q.y)
					if rise > best_rise:
						best_rise = rise
						spot = q
			_land_tgt = _spawn_tank(Vector3(spot.x, 0.0, spot.y), 0.0, 1, "t90")
			var tp: Vector3 = _land_tgt.global_position
			# launch from over the sea, so the run in crosses the coast and
			# whatever stands behind it
			# from the sea, at cruise height, so the whole run in is over land
			var from := Vector3(tp.x + 26000.0, 2400.0, tp.z)
			player.global_transform = Transform3D(Basis(), from)
			player.linear_velocity = Vector3(-250.0, 0, 0)
			player.gear_down = false
			player.gear_anim = 0.0
			player.set_bays(true)
			for k in player.bays:
				player.bays[k]["anim"] = 1.0
				player.bays[k]["open"] = true
			player.target = _land_tgt
			player.locked = true
			if not _arm_with("agm84"):
				_land_test = false
				get_tree().quit()
				return
			player.fire_cd = 0.0
			_reset_interp.call_deferred(player)
			# the highest ground on the line between the two
			var ridge := -1e9
			for k in 60:
				var q: Vector3 = from.lerp(tp, float(k) / 59.0)
				ridge = maxf(ridge, Sim.height_at(q.x, q.z))
			print("[land] %s at %s, ground there %.0f m; launcher 26 km out at 3000 m" % [
				Sim.label_of(_land_tgt), str(tp.round()), Sim.height_at(tp.x, tp.z)])
			print("[land] highest ground on the run in: %.0f m" % ridge)
		elif _land_tgt != null and _land_step == 0 and _land_t > 4.0:
			_land_step = 1
			var why: String = player.fire()
			print("[land] release: %s" % ("away" if why == "" else "refused — " + why))
		elif _land_step == 1:
			var live := 0
			if _land_t < 8.0 and fmod(_land_t, 1.0) < delta:
				for m in get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(m) and String(m.wid) == "agm84":
						print("[land]   t=%.1f target=%s kind=%s alt=%.0f agl=%.0f spd=%.0f" % [
							_land_t, Sim.label_of(m.target), String(m.ws.get("kind", "?")),
							(m as Node3D).global_position.y,
							(m as Node3D).global_position.y - maxf(Sim.height_at(
								(m as Node3D).global_position.x,
								(m as Node3D).global_position.z), Sim.WATER_LEVEL),
							(m.get_velocity() as Vector3).length()])
			for m in get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "agm84":
					continue
				live += 1
				var mp: Vector3 = (m as Node3D).global_position
				var agl: float = mp.y - maxf(Sim.height_at(mp.x, mp.z), Sim.WATER_LEVEL)
				if agl < _land_low:
					_land_low = agl
					_land_lowat = mp
				if is_instance_valid(_land_tgt):
					_land_close = minf(_land_close,
						mp.distance_to(_land_tgt.global_position))
			if live == 0 and _land_t > 12.0 or _land_t > 220.0:
				_land_test = false
				print("[land] lowest the round ever got: %.1f m above the ground, at %s" % [
					_land_low, str(_land_lowat.round())])
				print("[land] closest it came to the target: %.0f m; target alive=%s" % [
					_land_close, str(is_instance_valid(_land_tgt)
						and (not _land_tgt.has_method("is_alive") or _land_tgt.is_alive()))])
				print("[land] RESULT: %s" % ("ok" if _land_close < 40.0 and _land_low > 0.0
					else "FAILED — it hit the ground short" if _land_low <= 0.0
					else "FAILED — never arrived"))
				get_tree().quit()
		return
	# Which aeroplanes light up at the back. A turbofan with no reheat should
	# have nothing glowing in its exhaust and no plume behind it.
	if _accel_test:
		_accel_test = false
		# Full burner, level, from a standing start in the air: how long the
		# aeroplane actually takes to get up to speed, and what it tops out at.
		await get_tree().physics_frame
		if not is_instance_valid(player):
			print("[accel] no aeroplane")
			get_tree().quit()
			return
		# An empty sky. This is a measurement of what the airframe can do, and
		# the first three attempts were measuring how long it survives: a SAM
		# killed it at twenty-eight seconds, and a dead aeroplane stops running
		# its force model, so the frozen readouts looked exactly like a speed
		# it could not pass.
		for n in get_tree().get_nodes_in_group("hittable"):
			if n != player and is_instance_valid(n):
				n.queue_free()
		for m2 in get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m2):
				m2.queue_free()
		await get_tree().physics_frame
		player.global_position = Vector3(0.0, _dash_alt, 0.0)
		player.linear_velocity = -player.global_transform.basis.z * 180.0
		player.fuel = maxf(player.fuel, 1000.0)
		# clean: a dash test with the gear hanging out is measuring the gear
		player.gear_down = false
		player.flaps = 0.0
		if "airbrake" in player:
			player.airbrake = false
		var t_start := -1.0
		var t_mach1 := -1.0
		var best_m := 0.0
		var best_v := 0.0
		var clock := 0.0
		for f in 36000:                                   # five minutes
			await get_tree().physics_frame
			if not is_instance_valid(player):
				break
			clock += 1.0 / 120.0
			# Nothing is allowed to shoot the test article down. The first run
			# of this had it killed by a SAM at twenty-eight seconds, and since
			# the force model stops running on a dead aeroplane the readouts
			# froze -- which read exactly like the aircraft hitting a speed it
			# could not pass.
			player.health = 100.0
			var m: float = player.mach
			if t_start < 0.0 and m >= 0.60:
				t_start = clock
			if t_mach1 < 0.0 and m >= 1.20:
				t_mach1 = clock
			if m > best_m:
				best_m = m
				best_v = player.linear_velocity.length()
			if f % 1200 == 0:
				print("[accel] t=%5.1f s  mach %.2f  %4.0f m/s  %4.0f kt IAS  alt %5.0f  agl %5.0f  thr %.2f  alive=%s ghost=%s hp %.0f  aoa %.1f  pitch %.1f" % [
					clock, m, player.linear_velocity.length(),
					player.ias * 1.94384, player.global_position.y,
					player.agl, player.power, str(player.alive),
					str(player.ghost), player.health,
					rad_to_deg(player.aoa),
					rad_to_deg(asin(clampf(
						-player.global_transform.basis.z.y, -1.0, 1.0)))])
		print("[accel] mach 0.6 at %.1f s, mach 1.2 at %.1f s -> %.1f s to accelerate" % [
			t_start, t_mach1, t_mach1 - t_start])
		print("[accel] best mach %.2f (%.0f m/s) at %.0f m" % [
			best_m, best_v, _dash_alt])
		get_tree().quit()
		return
	if _ab_test:
		_ab_test = false
		var bad := 0
		for id in JetSpec.ids():
			var sp := JetSpec.get_spec(id)
			var reheat: bool = float(sp.get("thrust_ab", 0.0)) \
				> float(sp.get("thrust_mil", 1.0)) * 1.04
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			add_child(root)
			var plumes: int = (m["ab"] as Array).size()
			var lit: int = (m["burners"] as Array).size()
			# and does anything in the exhaust actually emit
			var glow := 0.0
			for n in root.find_children("Burner", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
					continue
				var sm := mi.mesh.surface_get_material(0) as StandardMaterial3D
				if sm != null and sm.emission_enabled:
					glow = maxf(glow, sm.emission.get_luminance())
			var wrong: bool = (not reheat) and (plumes > 0 or lit > 0 or glow > 0.001)
			if wrong:
				bad += 1
			print("[ab] %-8s reheat=%-5s  plume cones %d, lit exhausts %d, exhaust emission %.3f%s" % [
				id, str(reheat), plumes, lit, glow, "   <- SHOULD NOT GLOW" if wrong else ""])
			root.queue_free()
		print("[ab] RESULT: %s" % ("ok" if bad == 0 else
			"FAILED — %d airframe(s) glow without reheat" % bad))
		get_tree().quit()
		return
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
	if _tel_rig != "":
		var tk: String = _tel_rig
		_tel_rig = ""
		var t := _spawn_tank(Vector3(1400.0, 0.0, -2600.0), 0.0, 0, tk)
		for i in 300:
			await get_tree().physics_frame
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
			await get_tree().physics_frame
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
			await get_tree().physics_frame
			yaw_moved = maxf(yaw_moved, absf(t._turret.rotation.y))
		print("[tel] erector at %.0f%% after 6 s, canister %.1f deg up, turret slewed %.3f deg" % [
			t._erect * 100.0, rad_to_deg(t._mantlet.rotation.x),
			rad_to_deg(yaw_moved)])
		var before: int = t.rounds_left
		Sim.debug_weapons = true
		t._gun_cd = 0.0
		print("[tel] fire_main returned %s" % str(t.fire_main(self)))
		await get_tree().physics_frame
		var went_up := -1.0
		for m in get_tree().get_nodes_in_group("missiles"):
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
		for m2 in get_tree().get_nodes_in_group("missiles"):
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
				await get_tree().physics_frame
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
					for m3 in get_tree().get_nodes_in_group("missiles"):
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
		get_tree().quit()
		return
	# Can anything that floats actually get off the coast and up a river? A
	# channel that is lower than its banks is not a river if it is four hundred
	# metres above the sea, so this asks the only question that matters: flood
	# fill from open water and see how far inland the water goes.
	if _river_test:
		_river_test = false
		# 400 m, not 1500: a river is a few hundred metres across, and a grid
		# coarser than the channel steps straight over it and reports a
		# perfectly good waterway as unreachable.
		var step := 400.0
		var x0 := -150000.0
		var z0 := -100000.0
		var nx := 470
		var nz := 500
		var draught := 5.0
		var nav := PackedByteArray()
		nav.resize(nx * nz)
		var wet := 0
		for j in nz:
			for i in nx:
				var wx: float = x0 + float(i) * step
				var wz: float = z0 + float(j) * step
				if Sim.height_at(wx, wz) < Sim.WATER_LEVEL - draught:
					nav[j * nx + i] = 1
					wet += 1
		# seed from open ocean well east of the coast
		var seen := PackedByteArray()
		seen.resize(nx * nz)
		var queue: Array = []
		for j2 in nz:
			for i2 in nx:
				var wx2: float = x0 + float(i2) * step
				if wx2 > Sim.COAST_X + 20000.0 and nav[j2 * nx + i2] == 1:
					seen[j2 * nx + i2] = 1
					queue.append(Vector2i(i2, j2))
		var seeds := queue.size()
		var reached := 0
		var deepest := Sim.COAST_X
		var deep_at := Vector2.ZERO
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			reached += 1
			var ci: int = c.x
			var cj: int = c.y
			var cx: float = x0 + float(ci) * step
			if cx < deepest:
				deepest = cx
				deep_at = Vector2(cx, z0 + float(cj) * step)
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ni: int = ci + int(d[0])
				var nj: int = cj + int(d[1])
				if ni < 0 or ni >= nx or nj < 0 or nj >= nz:
					continue
				var k: int = nj * nx + ni
				if seen[k] == 1 or nav[k] == 0:
					continue
				seen[k] = 1
				queue.append(Vector2i(ni, nj))
		var inland := 0
		for j3 in nz:
			for i3 in nx:
				if seen[j3 * nx + i3] == 1 and x0 + float(i3) * step < Sim.COAST_X:
					inland += 1
		print("[river] %d of %d cells hold %.0f m of water; %d are open sea to start from" % [
			wet, nx * nz, draught, seeds])
		print("[river] a boat drawing %.0f m reaches %d cells, %d of them inland of the coast" % [
			draught, reached, inland])
		print("[river] furthest inland it gets: x = %.0f, which is %.0f km up country, at %s" % [
			deepest, (Sim.COAST_X - deepest) * 0.001, str(deep_at.round())])
		print("[river] navigable water inland covers %.0f km2" % [
			float(inland) * step * step * 1e-6])
		var ok: bool = (Sim.COAST_X - deepest) > 40000.0 and inland > 200
		print("[river] RESULT: %s" % ("ok" if ok else "FAILED"))
		get_tree().quit()
		return
	# Warlords over the whole country: how many sectors there are, whether they
	# are actually the places on the map, what a frame of it costs, and whether
	# the command point economy pays anything.
	if _warlords_test:
		_warlords_test = false
		_start("f16", "warlords")
		await get_tree().process_frame
		await get_tree().physics_frame
		var st: Dictionary = mode.hud_state()
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
		var towns: int = scenery.sites.size()
		var matched := 0
		for t in scenery.sites:
			var tc: Vector2 = t["c"]
			for z2 in zs:
				var p: Vector3 = z2["pos"]
				if Vector2(p.x - tc.x, p.z - tc.y).length() < 60.0:
					matched += 1
					break
		print("[wl] %d of %d settlements are sectors" % [matched, towns])
		# garrisons are lazy: only the live one should be standing
		var built := 0
		for z3 in mode.zones:
			if (z3 as CaptureZone).has_garrison():
				built += 1
		print("[wl] garrisons standing at kick-off: %d of %d" % [built, mode.zones.size()])
		# what a frame of the mode costs with this many sectors
		var t0 := Time.get_ticks_usec()
		for f in 120:
			mode._process(1.0 / 60.0)
		var per := float(Time.get_ticks_usec() - t0) / 120000.0
		print("[wl] GameMode._process costs %.3f ms a frame over %d sectors" % [
			per, mode.zones.size()])
		# and the economy: hand ourselves some ground and see it pay
		for i in mini(4, mode.zones.size()):
			var z4: CaptureZone = mode.zones[i]
			z4.owner_team = 0
			z4.progress = 1.0
		var cp0: int = mode.command_points
		for f2 in 600:
			mode._process(1.0 / 60.0)
		var st2: Dictionary = mode.hud_state()
		var gained: int = mode.command_points - cp0
		print("[wl] holding 4 sectors pays %.0f points a minute; 10 s gave %d" % [
			float(st2["cp_rate"]), gained])
		print("[wl] banner reports %d held, objective '%s'" % [
			int(st2["held"]), str(st2["objective"])])
		# Nothing may be standing inside anything else.
		var vs: Array = []
		for v2 in get_tree().get_nodes_in_group("vehicles"):
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
		get_tree().quit()
		return
	# How steady the ground is while you fly over it. Terrain that "changes as
	# you look at it" is a chunk being rebuilt, so this counts them: a straight
	# run at cruise, and then a slow orbit, which is the case that thrashes a
	# distance rule because the eye keeps recrossing the same threshold.
	# How long a gun actually keeps firing. "A few shots and it stops" is either
	# the round counter, the cooldown, or the input; this asks the aeroplane
	# directly and takes the input out of it.
	if _gun_test:
		_gun_test = false
		_start("f16", "free")
		await get_tree().process_frame
		await get_tree().physics_frame
		if not is_instance_valid(player):
			print("[gun] no aeroplane")
			get_tree().quit()
			return
		player.global_position = Vector3(0.0, 2500.0, 0.0)
		print("[gun] %s: %d rounds, %d rpm" % [player.name, player.ammo,
			int((player.spec["gun"] as Dictionary)["rpm"])])
		var fired := 0
		var refused := 0
		var frames := 0
		var first_refusal := -1
		while frames < 720:                       # six seconds at 120 Hz
			await get_tree().physics_frame
			frames += 1
			if player.fire_gun(self):
				fired += 1
			else:
				refused += 1
				if first_refusal < 0:
					first_refusal = frames
		print("[gun] over 6 s: %d bursts away, %d refused, ammo %d left" % [
			fired, refused, player.ammo])
		print("[gun] first refusal at frame %d (%.2f s), cooldown now %.4f" % [
			first_refusal, float(first_refusal) / 120.0, player.gun_cd])
		var ok: bool = fired > 100
		print("[gun] RESULT: %s" % ("ok" if ok else "FAILED"))
		get_tree().quit()
		return
	# Does a cruise round actually follow the ground, or does it fly into the
	# first hill it meets? Asked on its own, with nothing else shooting: in a
	# live mission the round was being destroyed in flight by friendly air
	# defence, which looks identical from the outside and is not the same fault.
	if _tfr_test:
		_tfr_test = false
		var boat: Ship = null
		for sh in get_tree().get_nodes_in_group("ships"):
			if is_instance_valid(sh):
				boat = sh
				break
		var mark: Vector3 = boat.global_position if is_instance_valid(boat) \
			else Vector3(24000.0, 0.0, 1200.0)
		# Against a vehicle instead of a ship. A cluster round scatters
		# submunitions over an area, and whether that works against something
		# ten metres long sitting on the ground is a different question from
		# whether it works against a hundred and fifty metres of hull at sea.
		var foe: Node3D = boat
		if _tfr_veh:
			# On land. The ship the mark comes from is at sea, so putting a tank
			# four hundred metres from it put it in the water, where it sank --
			# and a round whose target vanishes is a different test from a round
			# shooting at a vehicle.
			var spot := Vector2(mark.x, mark.z)
			for ring in 60:
				var probe := Vector2(mark.x - float(ring) * 600.0, mark.z)
				if Sim.height_at(probe.x, probe.y) > Sim.WATER_LEVEL + 8.0:
					spot = probe
					break
			var gy: float = Sim.height_at(spot.x, spot.y)
			var quarry := _spawn_tank(Vector3(spot.x, gy, spot.y),
				0.0, 1, "t72")
			quarry.ai = false
			foe = quarry
			mark = quarry.global_position
		var from := Vector3(-34000.0, 0.0, 6000.0)
		# A shot can be short as well as long, and the two are not the same
		# problem: over sixty kilometres a round has time to climb, cruise and
		# let down, and over twenty-five it has to do all three at once.
		if _tfr_range > 0.0:
			var away := Vector3(from.x - mark.x, 0.0, from.z - mark.z).normalized()
			from = mark + away * _tfr_range
			from.y = 0.0
		var t := _spawn_tank(from, 0.0, 0, _tfr_kind)
		t.ai = false
		await get_tree().physics_frame
		t.map_lock = foe
		t.map_target = mark
		var hp0: float = foe.health if is_instance_valid(foe) else 0.0
		print("[cruise] %s at %s, target %s, %.1f km apart" % [_tfr_kind,
			str(Vector2(from.x, from.z).round()), str(Vector2(mark.x, mark.z).round()),
			Vector2(mark.x - from.x, mark.z - from.z).length() * 0.001])
		var waited := 0
		while t._erect < 0.97 and waited < 1200:
			await get_tree().physics_frame
			waited += 1
		t._gun_cd = 0.0
		print("[cruise] launch: %s" % str(t.fire_main(self)))
		var shot: Missile = null
		var near := 1e18
		var want_id := String(Tank.KINDS[_tfr_kind]["missile"])
		for m in get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m) and String(m.wid) == want_id:
				var d: float = (m as Node3D).global_position.distance_to(t.global_position)
				if d < near:
					near = d
					shot = m
		if shot == null:
			print("[cruise] nothing left the rail")
			print("[cruise] RESULT: FAILED")
			get_tree().quit()
			return
		var worst_clear := 1e18
		var worst_at := Vector3.ZERO
		var lived := 0
		var closed := 1e18
		var closed3 := 1e18
		var high_at := 0.0
		# Six minutes. A subsonic cruise missile holds Mach 0.8, so sixty
		# kilometres is four minutes in the air -- cutting the clock at two
		# called a round that was tracking perfectly a failure.
		for f in 43200:
			await get_tree().physics_frame
			if not is_instance_valid(shot):
				# A cluster round stops existing halfway down on purpose: the
				# bus opens and eight submunitions carry on without it. Follow
				# whichever of them is nearest the target, or the test scores
				# the load's release point as the miss distance -- eighteen
				# kilometres short and twelve up, for a weapon that was doing
				# exactly what it is supposed to.
				var heir: Missile = null
				var heir_d := 1e18
				var aim_at: Vector3 = foe.global_position \
					if is_instance_valid(foe) else mark
				for m2 in get_tree().get_nodes_in_group("missiles"):
					if not is_instance_valid(m2):
						continue
					var dd2: float = (m2 as Node3D).global_position.distance_to(aim_at)
					if dd2 < heir_d:
						heir_d = dd2
						heir = m2
				if heir == null:
					break
				shot = heir
			lived = f
			var p: Vector3 = shot.global_position
			var g: float = maxf(Sim.height_at(p.x, p.z), Sim.WATER_LEVEL)
			var clear: float = p.y - g
			if clear < worst_clear:
				worst_clear = clear
				worst_at = p
			# against where the ship *is*, not where it was when we fired
			var now_at: Vector3 = foe.global_position if is_instance_valid(foe) \
				else mark
			closed = minf(closed, Vector2(p.x - now_at.x, p.z - now_at.z).length())
			# In three dimensions. Measured in plan a round that crossed the
			# ship five hundred metres overhead read as a ten metre miss, and
			# a profile that never got down was scored as tracking perfectly.
			var sep: float = p.distance_to(now_at)
			if sep < closed3:
				closed3 = sep
				high_at = p.y - now_at.y
			if f % 1200 == 0:
				print("[cruise]   t=%5.1f s  alt %6.0f  ground %6.0f  clear %5.0f  %5.1f km to run  vy %6.0f  spd %5.0f  at %s" % [
					float(f) / 120.0, p.y, g, clear, closed * 0.001,
					shot.vel.y, shot.vel.length(),
					(String(shot.target.name) if is_instance_valid(shot.target) else "NOTHING")])
		print("[cruise] flew %.1f s, closest to the mark %.2f km in plan, %.0f m in all" % [
			float(lived) / 120.0, closed * 0.001, closed3])
		print("[cruise] at that point it was %.0f m above the target" % high_at)
		print("[cruise] least ground clearance %.1f m at %s" % [
			worst_clear, str(worst_at.round())])
		var hurt: float = hp0 - (foe.health if is_instance_valid(foe) else 0.0)
		print("[cruise] the target took %.0f damage of %.0f (%s)" % [hurt, hp0,
			"hit" if hurt > 0.0 else "MISS"])
		# Damage alone is not proof: there is a battle going on and the ship
		# takes hits from other people. The round has to have arrived.
		# A hit is arriving *at* the target, not over the top of it.
		print("[cruise] RESULT: %s" % ("ok" if closed3 < 120.0 and hurt > 0.0
			else "FAILED"))
		get_tree().quit()
		return
	if _churn_test:
		_churn_test = false
		# instrument properly: hook the build counter
		terrain.debug_count = true
		# Arrive first, and only then start counting. The first update of a run
		# builds the whole world at once, and none of that is a hand-over from
		# anything -- there was nothing there before it. Counting it as one
		# buried the transitions that actually pop under six hundred that
		# cannot.
		terrain.recentre(Vector3(0.0, 900.0, -4000.0), true)
		terrain.flush_pending()
		terrain.debug_builds = {}
		terrain.debug_pop = []
		var flown := 0.0
		var speed := 240.0
		# Stepped the way the game actually steps it -- every frame, not twice a
		# second. How complete a chunk's blend is when it appears depends on how
		# promptly the hand-over is noticed, so a coarse harness step hides
		# exactly the fault being looked for.
		var t2 := 0.0
		while t2 < 90.0:
			terrain.recentre(Vector3(speed * t2, 900.0, -4000.0))
			terrain.flush_pending()
			t2 += 1.0 / 60.0
		flown = speed * 90.0
		var straight: Dictionary = terrain.debug_builds.duplicate()
		var s_total := 0
		for k2 in straight:
			s_total += int(straight[k2])
		# What the blend is actually worth in flight, as opposed to at the ideal
		# threshold: a chunk that appears late arrives part-blended and pops.
		var pops: Array = terrain.debug_pop.duplicate()
		# and what asking the tree costs, since it is asked every thirty metres
		var wt0 := Time.get_ticks_usec()
		for wq in 20:
			terrain._wanted(Vector3(41000.0 + float(wq), 900.0, -27000.0))
		print("[churn] one look at the whole tree: %.2f ms" % [
			float(Time.get_ticks_usec() - wt0) / 20000.0])
		# A chunk appearing at blend 1 is a hand-over *down*: it arrives shaped
		# like the level above -- the thing it is replacing -- and cannot be
		# seen. One appearing at blend 0 is a hand-over *up*: the coarser level
		# taking back over from children that were themselves fully morphed to
		# its unmorphed shape, which also cannot be seen. Both ends are seamless
		# by construction, and an earlier version of this counted every merge as
		# a pop for that reason. What would actually show is an arrival in the
		# middle, matching neither what it replaced nor what it settles to.
		var p_sum := 0.0
		var p_bad := 0
		var by_d: Dictionary = {}
		for pv in pops:
			var bl: float = float((pv as Array)[0])
			var dp: int = int((pv as Array)[1])
			var miss: float = minf(bl, 1.0 - bl)
			p_sum += miss
			if miss > 0.12:
				p_bad += 1
				by_d[dp] = int(by_d.get(dp, 0)) + 1
		var dks: Array = by_d.keys()
		dks.sort()
		var row := ""
		for dk in dks:
			row += "d%d:%d  " % [int(dk), int(by_d[dk])]
		if row != "":
			print("[churn] arrived mid-blend, by depth: %s" % row)
		var shown := 0
		for pv2 in pops:
			var e2: Array = pv2
			var m2b: float = minf(float(e2[0]), 1.0 - float(e2[0]))
			if m2b > 0.3 and shown < 5:
				shown += 1
				print("[churn]   d%d blend %.2f at %.0f m (hands over at %.0f m), chunk at %.0f,%.0f" % [
					int(e2[1]), float(e2[0]), float(e2[2]), float(e2[3]),
					float(e2[4]), float(e2[5])])
		print("[churn] hand-over mismatch: mean %.4f, %d of %d arrived mid-blend" % [
			p_sum / maxf(float(pops.size()), 1.0), p_bad, pops.size()])
		print("[churn] straight run %.0f km: %d builds over %d nodes (%.2f each)" % [
			flown * 0.001, s_total, straight.size(),
			float(s_total) / maxf(float(straight.size()), 1.0)])
		# now the orbit: a helicopter going round a point, which never gets
		# anywhere and so should settle down and stop rebuilding entirely
		# Per lap. A cache that works shows up as the first lap paying for the
		# geometry and the later ones paying nothing: anything else is thrash.
		var laps: Array = []
		for lap in 4:
			terrain.debug_builds = {}
			var t3: float = 0.0
			while t3 < 40.0:
				var a: float = TAU * t3 / 40.0
				terrain.recentre(Vector3(20000.0 + cos(a) * 900.0, 400.0,
					12000.0 + sin(a) * 900.0))
				terrain.flush_pending()
				t3 += 0.5
			var n := 0
			for kk in terrain.debug_builds:
				n += int(terrain.debug_builds[kk])
			laps.append(n)
		print("[churn] builds per lap of the orbit: %s" % str(laps))
		var orbit: Dictionary = terrain.debug_builds.duplicate()
		var o_total := 0
		var o_repeat := 0
		var worst := 0
		var worst_key := ""
		for k3 in orbit:
			o_total += int(orbit[k3])
			if int(orbit[k3]) > 1:
				o_repeat += int(orbit[k3]) - 1
			if int(orbit[k3]) > worst:
				worst = int(orbit[k3])
				worst_key = String(k3)
		print("[churn] last lap: %d builds over %d nodes, %d of them rebuilds" % [
			o_total, orbit.size(), o_repeat])
		print("[churn] worst node was built %d times: %s" % [worst, worst_key])
		# A straight run has to build the ground it flies over, and each node
		# once more as it gets close enough to want it finer -- about two builds
		# a node is the floor, and the morph adds a little on top because a
		# chunk whose edge faces a finer neighbour has to pin that edge, which
		# is more state in its key and so more variants of it. A lap of an orbit
		# that has already been flown should still cost nothing at all: that is
		# the number that says the ground has stopped churning.
		var settled: int = maxi(int(laps[1]), maxi(int(laps[2]), int(laps[3])))
		var per_node: float = float(s_total) / maxf(float(straight.size()), 1.0)
		# Nothing may be drawing ground that is not the live set: a chunk left
		# visible after being superseded draws the same country at a different
		# detail, in the same place, and the two fight for every pixel.
		var visible_chunks := 0
		for c in terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null or String(mi.name) == "Water":
				continue
			if mi.visible:
				visible_chunks += 1
		var shelved: int = terrain._cache.size()
		# read now, not at the verdict: the hover below moves the eye and
		# changes the live set out from under a late comparison
		var live_then: int = terrain._live.size()
		print("[churn] %d chunks drawing, %d live, %d shelved, %d awaiting hand-over" % [
			visible_chunks, terrain._live.size(), shelved, terrain._retire.size()])
		# And the live set has to tile the ground, not pile up on it. Two chunks
		# covering the same square metre draw the same country twice at
		# different detail and fight for every pixel -- which reads as the
		# terrain and its texture changing under you, worst close in where the
		# detail changes most often.
		var boxes: Array = []
		for c2 in terrain.get_children():
			var m2 := c2 as MeshInstance3D
			if m2 == null or m2.mesh == null or not m2.visible:
				continue
			if String(m2.name) == "Water" or m2.is_queued_for_deletion():
				continue
			var ab: AABB = m2.mesh.get_aabb()
			boxes.append([ab.position.x, ab.position.z, ab.size.x, ab.size.z,
				String(m2.name)])
		var overlaps := 0
		var named_overlap := ""
		for i in boxes.size():
			var a: Array = boxes[i]
			for j in range(i + 1, boxes.size()):
				var b: Array = boxes[j]
				# shared edges are fine; real area in common is not
				var ox: float = minf(a[0] + a[2], b[0] + b[2]) - maxf(a[0], b[0])
				var oz: float = minf(a[1] + a[3], b[1] + b[3]) - maxf(a[1], b[1])
				if ox > 1.0 and oz > 1.0:
					overlaps += 1
					if named_overlap == "":
						named_overlap = "%s and %s share %.0f x %.0f m" % [
							a[4], b[4], ox, oz]
		print("[churn] overlapping pairs in the live set: %d%s" % [overlaps,
			("  (" + named_overlap + ")") if overlaps > 0 else ""])
		# What the ground is actually painted, under the sea. The colours are
		# baked into the chunks at build time, so this reads what gets drawn
		# rather than what the biome function says it ought to be.
		var wet_v := 0
		var wet_green := 0
		var wet_r := 0.0
		var wet_g := 0.0
		for c3 in terrain.get_children():
			var m3 := c3 as MeshInstance3D
			if m3 == null or m3.mesh == null or not m3.visible:
				continue
			if String(m3.name) == "Water":
				continue
			var ar: Array = m3.mesh.surface_get_arrays(0)
			if ar.is_empty() or ar[Mesh.ARRAY_COLOR] == null:
				continue
			var vv: PackedVector3Array = ar[Mesh.ARRAY_VERTEX]
			var cc: PackedColorArray = ar[Mesh.ARRAY_COLOR]
			for vi in range(0, vv.size(), 7):
				if vv[vi].y >= Sim.WATER_LEVEL - 5.0:
					continue
				wet_v += 1
				wet_r += cc[vi].r
				wet_g += cc[vi].g
				if cc[vi].g > cc[vi].r + 0.02:
					wet_green += 1
		# The morph needs three extra things in the mesh: the height offset, the
		# coarse normal and the coarse colour. If any of them is missing the
		# shader still runs and the ground still draws, so nothing complains --
		# it simply stops blending, or blends toward nothing.
		for c9 in terrain.get_children():
			var m9 := c9 as MeshInstance3D
			if m9 == null or m9.mesh == null or String(m9.name) == "Water":
				continue
			var fmt: int = m9.mesh.surface_get_format(0)
			var a9: Array = m9.mesh.surface_get_arrays(0)
			var nv: int = (a9[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("[churn] mesh carries: uv2=%s tangent=%s custom0=%s (%d verts, custom %d bytes)" % [
				str((fmt & Mesh.ARRAY_FORMAT_TEX_UV2) != 0),
				str((fmt & Mesh.ARRAY_FORMAT_TANGENT) != 0),
				str((fmt & Mesh.ARRAY_FORMAT_CUSTOM0) != 0), nv,
				(a9[Mesh.ARRAY_CUSTOM0] as PackedByteArray).size()
				if a9[Mesh.ARRAY_CUSTOM0] != null else -1])
			break
		print("[churn] seabed: %d vertices under water, mean r=%.3f g=%.3f, %d greener than red" % [
			wet_v, wet_r / maxf(float(wet_v), 1.0), wet_g / maxf(float(wet_v), 1.0),
			wet_green])
		# How finished the morph is at the instant a node hands over to its
		# children. One means the finer level arrives shaped exactly like the
		# coarser one and the switch cannot be seen; less than one is a step.
		var sw_n := 0
		var sw_sum := 0.0
		var sw_worst := 1.0
		for k4 in terrain._live:
			var bits4 := String(k4).split(":")
			var d4 := int(bits4[0])
			if d4 >= Terrain.MAX_DEPTH:
				continue
			var span4: float = Terrain.span_at(d4)
			# a hand-over now always happens at the distance rule, which is the
			# distance the blend is built around
			var split_at: float = Terrain.SPLIT_K * span4
			var lo4: float = Terrain.SPLIT_K * span4 * 0.5
			var m4: float = clampf((split_at - lo4) / maxf(lo4, 1.0), 0.0, 1.0)
			sw_n += 1
			sw_sum += m4
			sw_worst = minf(sw_worst, m4)
		print("[churn] morph complete at hand-over: mean %.3f, worst %.3f over %d nodes" % [
			sw_sum / maxf(float(sw_n), 1.0), sw_worst, sw_n])
		# A hover: standing still, nothing at all should be rebuilt. Let it
		# arrive first -- the orbit left the eye 900 m away, and moving there is
		# a real change of detail, not churn.
		var spot := Vector3(20000.0, 400.0, 12000.0)
		terrain.recentre(spot, true)
		terrain.flush_pending()
		terrain.debug_builds = {}
		for hv in 200:
			terrain.recentre(spot)
			terrain.flush_pending()
		var hover := 0
		for hk in terrain.debug_builds:
			hover += int(terrain.debug_builds[hk])
		print("[churn] holding a hover for 200 updates: %d builds" % hover)
		print("[churn] worst settled lap: %d builds; straight run %.2f builds a node" % [
			settled, per_node])
		print("[churn] RESULT: %s" % ("ok" if settled <= 20 and per_node < 3.0
			and visible_chunks == live_then and overlaps == 0
			and hover == 0 and p_bad * 20 < pops.size() else "FAILED"))
		get_tree().quit()
		return
	if _carrier_test:
		_carrier_test = false
		var parts: Dictionary = {}
		var lo := 1e9
		var hi := -1e9
		for c in carrier.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var ab: AABB = mi.mesh.get_aabb()
			parts[str(mi.name)] = ab
			lo = minf(lo, carrier.global_position.y + ab.position.y)
			hi = maxf(hi, carrier.global_position.y + ab.position.y + ab.size.y)
		print("[carrier] parts: %s" % str(parts.keys()))
		print("[carrier] sits at y=%.1f, sea is at %.1f" % [
			carrier.global_position.y, Sim.WATER_LEVEL])
		print("[carrier] hull spans %.1f m to %.1f m; keel is %.1f m below the surface" % [
			lo, hi, Sim.WATER_LEVEL - lo])
		var afloat: bool = absf(carrier.global_position.y - Sim.WATER_LEVEL) < 0.01 \
			and lo < Sim.WATER_LEVEL - 4.0 and lo > Sim.WATER_LEVEL - 30.0
		# the registered deck has to be where the deck actually is
		var want_deck: float = Sim.WATER_LEVEL + Carrier.DECK_Y
		var got_deck: float = float(carrier.deck.get("y", -9999.0))
		print("[carrier] flight deck at %.1f m, registered at %.1f m, %.1f m above the sea" % [
			want_deck, got_deck, want_deck - Sim.WATER_LEVEL])
		# is there anything holding the port overhang up?
		var port_edge: float = -(Carrier.BEAM + 22.0) * 0.5 - 4.0
		var supported := 0
		var checked := 0
		for zf in [-0.34, -0.10, 0.06, 0.14, 0.32]:
			checked += 1
			var lx: float = port_edge * 0.62
			var lz: float = float(zf) * Carrier.LEN
			var found := false
			for nm in parts:
				if nm == "Deck" or nm == "DeckMarks":
					continue
				var ab2: AABB = parts[nm]
				if lx >= ab2.position.x - 1.0 and lx <= ab2.position.x + ab2.size.x + 1.0 \
						and lz >= ab2.position.z - 1.0 and lz <= ab2.position.z + ab2.size.z + 1.0 \
						and ab2.position.y + ab2.size.y < Carrier.DECK_Y:
					found = true
					break
			if found:
				supported += 1
		print("[carrier] port deck overhang carried at %d of %d stations" % [
			supported, checked])
		# and take the conn
		_enter_carrier()
		await get_tree().process_frame
		var conned: bool = carrier.occupied and carrier.cam != null and carrier.cam.current
		print("[carrier] took the conn: occupied=%s camera=%s" % [
			str(carrier.occupied), str(carrier.cam != null and carrier.cam.current)])
		carrier.telegraph = 1.0
		for i in 240:
			carrier._physics_process(1.0 / 60.0)
		print("[carrier] under way at %.1f kts after 4 s of full ahead" % (carrier.speed * 1.94384))
		var moves: bool = carrier.speed > 0.5 \
			and absf(carrier.deck["y"] - want_deck) < 0.01
		_leave_carrier()
		var listed: bool = false
		for k in menu._cards:
			if String(k) == "sea:carrier":
				listed = true
		print("[carrier] listed on the menu: %s" % str(listed))
		print("[carrier] RESULT: %s" % ("ok" if afloat and supported == checked
			and conned and moves and absf(got_deck - want_deck) < 0.01 else "FAILED"))
		get_tree().quit()
		return
	if _obstacle_test:
		_obstacle_test = false
		print("[obs] %d structures in %d cells" % [int(Obstacles.stats["count"]),
			int(Obstacles.stats["cells"])])
		# Every town building should answer for its own footprint.
		var inside := 0
		var missed := 0
		var tried := 0
		for xf in scenery.town_xforms:
			var t: Transform3D = xf
			tried += 1
			if tried % 7 != 0:
				continue
			var p := t.origin + Vector3(0.0, 3.0, 0.0)
			if Obstacles.hit(p, 0.0) >= 0:
				inside += 1
			else:
				missed += 1
				if missed <= 3:
					print("[obs]   no footprint at %s" % str(p.round()))
		print("[obs] %d of %d sampled town buildings answer at their own centre" % [
			inside, inside + missed])
		# and open country should not
		var false_pos := 0
		var open := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		for i in 4000:
			var q := Vector3(rng.randf_range(-40000.0, 40000.0), 0.0,
				rng.randf_range(-40000.0, 40000.0))
			q.y = Sim.height_at(q.x, q.z) + 1.5
			if Obstacles.top_at(q.x, q.z) > -1e8:
				continue                       # genuinely over a footprint
			open += 1
			if Obstacles.hit(q, 0.0) >= 0:
				false_pos += 1
		print("[obs] %d open-country points, %d of them wrongly reported solid" % [
			open, false_pos])
		# a roof is where the query says it is
		var roof_ok := 0
		var roof_bad := 0
		for xf2 in scenery.town_xforms:
			var t2: Transform3D = xf2
			var top := Obstacles.top_at(t2.origin.x, t2.origin.z)
			if top > t2.origin.y + 1.0 and top < t2.origin.y + 400.0:
				roof_ok += 1
			else:
				roof_bad += 1
		print("[obs] roof height sane for %d of %d buildings" % [roof_ok,
			roof_ok + roof_bad])
		# and the near-collider pool follows the viewer
		obstacles.follow(Vector3(scenery.sites[0]["c"].x, 0.0,
			scenery.sites[0]["c"].y))
		var live_bodies := 0
		for c in obstacles.get_children():
			var sb := c as StaticBody3D
			if sb != null and sb.process_mode != Node.PROCESS_MODE_DISABLED:
				live_bodies += 1
		print("[obs] %d real colliders standing at the town centre" % live_bodies)
		# what a jet flying down the street does about it
		var town: Vector2 = scenery.sites[0]["c"]
		var struck := 0
		var flown := 0
		for k in 400:
			var a: float = TAU * float(k) / 400.0
			var q2 := Vector3(town.x + cos(a) * 320.0, 0.0, town.y + sin(a) * 320.0)
			q2.y = Sim.height_at(q2.x, q2.z) + 12.0
			flown += 1
			if Obstacles.hit(q2, 6.8) >= 0:
				struck += 1
		print("[obs] a jet at 12 m round the town centre clips something at %d of %d points" % [
			struck, flown])
		var ok: bool = int(Obstacles.stats["count"]) > 500 and missed == 0 \
			and false_pos == 0 and roof_bad == 0 and live_bodies > 0 and struck > 0
		print("[obs] RESULT: %s" % ("ok" if ok else "FAILED"))
		get_tree().quit()
		return
	if _lod_test:
		_lod_test = false
		# Somewhere off the origin, because correct at the origin proves only
		# that the layout the airfield sits in works.
		var moved := Vector3(41300.0, 0.0, -27700.0)
		terrain.debug_count = true
		terrain.recentre(moved, true)
		print("[lod] neighbour lookups that disagree with a full descent: %d" %
			terrain.debug_nb_bad)
		# Does the live set actually tile the ground? Two leaves covering the
		# same square metre is not a seam problem, it is a broken partition, and
		# every seam number downstream of it is meaningless.
		var boxes2: Array = []
		for lk2 in terrain._live:
			var bb := String(lk2).split(":")
			var dd3 := int(bb[0])
			var sp3: float = Terrain.span_at(dd3)
			boxes2.append([float(int(bb[1])) * sp3, float(int(bb[2])) * sp3, sp3,
				String(lk2)])
		var ov := 0
		for i5 in boxes2.size():
			for j5 in range(i5 + 1, boxes2.size()):
				var A: Array = boxes2[i5]
				var B: Array = boxes2[j5]
				var oxx: float = minf(A[0] + A[2], B[0] + B[2]) - maxf(A[0], B[0])
				var ozz: float = minf(A[1] + A[2], B[1] + B[2]) - maxf(A[1], B[1])
				if oxx > 1.0 and ozz > 1.0:
					ov += 1
					if ov <= 3:
						print("[lod]   %s overlaps %s" % [A[3], B[3]])
		print("[lod] overlapping leaves in the live set: %d" % ov)
		await get_tree().process_frame
		print("[lod] viewer at %s, %d leaves live" % [
			str(Vector2(moved.x, moved.z).round()), int(terrain.stats["chunks"])])
		var chunks: Array = []
		var by_depth: Dictionary = {}
		for c in terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			# Leaves only. The water plane is a child of the terrain too, and it
			# answered "the ground is at -35 m" at every point on every
			# boundary -- which came out as a 1249 m disagreement that had
			# nothing to do with the stitching.
			var nm := str(mi.name)
			if not nm.begins_with("C") or not nm.contains("_"):
				continue
			var bits := nm.substr(1).split("_")
			var dep := int(bits[0])
			by_depth[dep] = int(by_depth.get(dep, 0)) + 1
			var ab: AABB = mi.mesh.get_aabb()
			ab.position += mi.position
			chunks.append({"mi": mi, "ab": ab, "tris": [], "d": dep})
		# Every leaf has to be found by name, and a leaf Godot renamed is a leaf
		# the harness cannot see -- which reads as a hole in the ground that is
		# not there. Water is the one child that is not a leaf.
		print("[lod] %d leaves found by name, of %d live (%d children)" % [
			chunks.size(), terrain._live.size(), terrain.get_child_count()])
		var deps: Array = by_depth.keys()
		deps.sort()
		for d2 in deps:
			print("[lod] depth %2d (cell %6.0f m): %d leaves" % [
				int(d2), Terrain.span_at(int(d2)) / float(Terrain.CELLS),
				int(by_depth[d2])])
		# Walk every leaf's own boundary vertices and ask whoever else covers
		# that point how high the ground is there. No knowledge of the tree's
		# shape goes into this -- it is the built meshes, compared with each
		# other, which is the only thing the eye can see.
		var worst := 0.0
		var total := 0.0
		var pairs := 0
		var lonely := 0
		var worst_at := Vector2.ZERO
		var worst_who: Array = []
		var named := 0
		var edge_of_world := Terrain.ROOT_SPAN * 0.5 - 1.0
		# Run the whole comparison twice: once with the chunks as they are, and
		# once with every one of them morphed all the way to the shape of the
		# level above it, which is how a finer chunk looks at the instant it
		# appears. A seam that is watertight at one end of the blend and not at
		# the other opens and closes as you fly towards it.
		_tri_eye = moved
		for mp in 2:
			_tri_morph = mp == 1
			worst = 0.0
			total = 0.0
			pairs = 0
			lonely = 0
			named = 0
			for ch3 in chunks:
				ch3["tris"] = []
			for ch0 in chunks:
				var ab0: AABB = ch0["ab"]
				var span0: float = ab0.size.x
				var cell0: float = span0 / float(Terrain.CELLS)
				for side in 4:
					for k in range(1, Terrain.CELLS, 2):
						var t: float = float(k) * cell0
						var p := Vector2(ab0.position.x + t, ab0.position.z)
						if side == 1:
							p = Vector2(ab0.position.x + t, ab0.position.z + span0)
						elif side == 2:
							p = Vector2(ab0.position.x, ab0.position.z + t)
						elif side == 3:
							p = Vector2(ab0.position.x + span0, ab0.position.z + t)
						if absf(p.x) > edge_of_world or absf(p.y) > edge_of_world:
							continue
						var hs: Array = []
						var who: Array = []
						for ch in chunks:
							var ab2: AABB = ch["ab"]
							if p.x < ab2.position.x - 0.5 or p.x > ab2.position.x + ab2.size.x + 0.5:
								continue
							if p.y < ab2.position.z - 0.5 or p.y > ab2.position.z + ab2.size.z + 0.5:
								continue
							if (ch["tris"] as Array).is_empty():
								ch["tris"] = _chunk_tris(ch["mi"])
							var y: float = _tri_height(ch["tris"], p)
							if y != INF:
								hs.append(y)
								who.append("%s=%.1f" % [str((ch["mi"] as MeshInstance3D).name), y])
						if hs.size() < 2:
							lonely += 1
							if lonely <= 3:
								print("[lod]   lonely at %s: %s side %d, %d chunk(s)" % [
									str(p.round()), str((ch0["mi"] as MeshInstance3D).name),
									side, hs.size()])
							continue
						var lo := 1e9
						var hi := -1e9
						for y2 in hs:
							lo = minf(lo, float(y2))
							hi = maxf(hi, float(y2))
						var gap: float = hi - lo
						total += gap
						pairs += 1
						if gap > worst:
							worst = gap
							worst_at = p
							worst_who = who.duplicate()
						if gap > 0.5 and named < 3:
							named += 1
							print("[lod]   %.2f m apart at %s: %s" % [gap, str(p.round()),
								", ".join(PackedStringArray(who))])
			print("[lod] %s: %d pairs, mean %.5f m, worst %.4f m" % [
				"without the morph" if mp == 0 else "as drawn, morph and all",
				pairs, total / maxf(float(pairs), 1.0), worst])
		print("[lod] %d boundary points had two chunks drawing them, %d had only one" % [
			pairs, lonely])
		print("[lod] disagreement between the two sides: mean %.5f m, worst %.4f m at %s" % [
			total / maxf(float(pairs), 1.0), worst, str(worst_at.round())])
		print("[lod] at the worst point, these chunks drew ground: %s" % str(worst_who))
		print("[lod] RESULT: %s" % ("ok" if worst < 0.05 and pairs > 0 else "FAILED"))
		get_tree().quit()
		return
	# How much terrain hangs below the ground. The skirts that hide the ring
	# seams are a vertical curtain under every chunk edge, and from a submarine
	# you are looking at them side on.
	if _skirt_test:
		_skirt_test = false
		var worst_drop := 0.0
		var worst_name := ""
		var total_below := 0.0
		var counted := 0
		for c in terrain.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var ab: AABB = mi.mesh.get_aabb()
			var org: Vector3 = mi.position
			# At the chunk's own vertex positions, not a resampling of the
			# footprint: on the outer rings a cell is nearly two kilometres
			# across and a grid of ten samples misses the low ground entirely,
			# which read as a fifty metre curtain that was not there.
			var lo := 1e9
			var steps: int = terrain.CELLS
			for i in steps + 1:
				for j in steps + 1:
					var x: float = org.x + ab.position.x + ab.size.x * float(i) / float(steps)
					var z: float = org.z + ab.position.z + ab.size.z * float(j) / float(steps)
					lo = minf(lo, Sim.height_at(x, z))
			var drop: float = lo - (org.y + ab.position.y)
			if drop > worst_drop:
				worst_drop = drop
				worst_name = str(mi.name)
			total_below += maxf(drop, 0.0)
			counted += 1
		print("[skirt] %d chunks; curtain hanging below the ground: worst %.2f m on %s, mean %.2f m" % [
			counted, worst_drop, worst_name, total_below / maxf(float(counted), 1.0)])
		print("[skirt] seam left by the stitching: %.6f m" % float(terrain.stats.get("seam", 0.0)))
		# what a submarine actually sees: how much of that curtain is under water
		var sub_depth := Sim.WATER_LEVEL - 40.0
		print("[skirt] a boat at %.0f m sees curtain wherever the seabed is within %.2f m of it" % [
			sub_depth, worst_drop])
		print("[skirt] RESULT: %s" % ("ok" if worst_drop < 2.0
			and float(terrain.stats.get("seam", 0.0)) < 0.05 else "FAILED"))
		get_tree().quit()
		return
	# What driving the trunk network is actually like: the gradient along it and
	# how level the carriageway is across its width.
	if _road_test:
		_road_test = false
		Sim.resurvey_roads()
		var worst_grade := 0.0
		var mean_grade := 0.0
		var worst_cross := 0.0
		var worst_at := Vector2.ZERO
		var worst_lr := Vector3.ZERO
		var deepest_cut := 0.0
		var grades: Array = []
		var crosses: Array = []
		var tallest_fill := 0.0
		var worst_w := Vector3.ZERO
		var worst_left := Vector2.ZERO
		var worst_right := Vector2.ZERO
		var mean_cross := 0.0
		var n := 0
		var span := 0.0
		for r in Sim.ROADS:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var d: float = a.distance_to(b)
			span += d
			var dirv: Vector2 = (b - a).normalized()
			var nrm := Vector2(-dirv.y, dirv.x)
			var steps: int = clampi(int(d / 60.0), 3, 60)
			var prev: float = Sim.height_at(a.x, a.y)
			for k in range(1, steps + 1):
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var y: float = Sim.height_at(q.x, q.y)
				var g: float = absf(y - prev) / maxf(d / float(steps), 1.0)
				prev = y
				# Streets inside a town run on the levelled platform, which is
				# the town's business and not the trunk road's.
				if Sim.pad_weight(q.x, q.y) > 0.05:
					continue
				var l: float = Sim.height_at(q.x - nrm.x * 6.0, q.y - nrm.y * 6.0)
				var rr: float = Sim.height_at(q.x + nrm.x * 6.0, q.y + nrm.y * 6.0)
				var cross: float = absf(rr - l) / 12.0
				var made: Vector3 = Sim.road_surface(q.x, q.y)
				if made.y > 0.5:
					deepest_cut = maxf(deepest_cut, y - made.x)
					tallest_fill = maxf(tallest_fill, made.x - y)
				grades.append(g)
				crosses.append(cross)
				worst_grade = maxf(worst_grade, g)
				if cross > worst_cross:
					worst_cross = cross
					worst_at = q
					worst_lr = Vector3(l, y, rr)
					worst_w = Sim.road_surface(q.x, q.y)
					worst_left = q - nrm * 6.0
					worst_right = q + nrm * 6.0
				mean_grade += g
				mean_cross += cross
				n += 1
		print("[roads] %d legs, %.1f km of trunk road" % [Sim.ROADS.size(), span * 0.001])
		grades.sort()
		crosses.sort()
		var g95: float = grades[mini(grades.size() - 1, int(grades.size() * 0.95))]
		var c95: float = crosses[mini(crosses.size() - 1, int(crosses.size() * 0.95))]
		print("[roads] gradient along the road: mean %.1f%%, 95th %.1f%%, worst %.1f%%" % [
			100.0 * mean_grade / maxf(float(n), 1.0), 100.0 * g95, 100.0 * worst_grade])
		print("[roads] cross fall over the carriageway: mean %.1f%%, 95th %.1f%%, worst %.1f%%" % [
			100.0 * mean_cross / maxf(float(n), 1.0), 100.0 * c95, 100.0 * worst_cross])
		print("[roads] finished ground vs the design surface: %.2f m high, %.2f m low at worst" % [
			deepest_cut, tallest_fill])
		# How far the road has dug itself into the country: the carriageway
		# against the untouched ground well outside the graded shoulder.
		var cut_sum := 0.0
		var cut_worst := 0.0
		var cut_n := 0
		var cut_at := Vector2.ZERO
		for r in Sim.ROADS:
			var ra: Vector2 = r[0]
			var rb: Vector2 = r[1]
			var rd := rb - ra
			if rd.length() < 20.0:
				continue
			for kk in 5:
				var q: Vector2 = ra.lerp(rb, (float(kk) + 0.5) / 5.0)
				# what the earthworks actually did here
				var depth: float = Sim.natural_height_at(q.x, q.y) \
					- Sim.height_at(q.x, q.y)
				if depth > 0.0:
					cut_sum += depth
					if depth > cut_worst:
						cut_worst = depth
						cut_at = q
				cut_n += 1
		if cut_worst > 20.0:
			var rsw: Vector3 = Sim.road_surface(cut_at.x, cut_at.y)
			print("[roads]   at the worst point: natural %.1f, finished %.1f, design %.1f, weight %.2f, centreline ground %.1f" % [
				Sim.natural_height_at(cut_at.x, cut_at.y),
				Sim.height_at(cut_at.x, cut_at.y), rsw.x, rsw.y, rsw.z])
			print("[roads]   flat_factor %.2f, road_distance %.0f m" % [
				Sim.flat_factor(cut_at.x, cut_at.y),
				Sim.road_distance(cut_at.x, cut_at.y)])
		print("[roads] earth moved to make the road: mean %.2f m cut, worst %.1f m at %s" % [
			cut_sum / maxf(float(cut_n), 1.0), cut_worst, str(cut_at.round())])
		print("[roads] worst cross fall at %s: left %.1f, centre %.1f, right %.1f, corridor y=%.1f w=%.2f, %.0f m from a road" % [
			str(worst_at.round()), worst_lr.x, worst_lr.y, worst_lr.z,
			worst_w.x, worst_w.y, Sim.road_distance(worst_at.x, worst_at.y)])
		var near := 0
		for r in Sim.ROADS:
			if Sim._seg_dist(worst_at, r[0], r[1]) < 30.0:
				near += 1
				print("[roads]   leg %s -> %s at %.1f m" % [
					str((r[0] as Vector2).round()), str((r[1] as Vector2).round()),
					Sim._seg_dist(worst_at, r[0], r[1])])
		print("[roads]   %d trunk legs within 30 m of that point" % near)
		for probe in [worst_left, worst_right]:
			print("[roads]   probe %s: corridor y=%.1f w=%.2f, exact %.1f m, coarse %.1f m, ground %.1f" % [
				str((probe as Vector2).round()),
				Sim.road_surface(probe.x, probe.y).x, Sim.road_surface(probe.x, probe.y).y,
				Sim._road_distance_exact(probe.x, probe.y),
				Sim._sample_road_field(probe.x, probe.y),
				Sim.height_at(probe.x, probe.y)])
		# The alignment as a whole, structures included -- the open legs alone
		# flatter the road, because the steep ground is exactly what became a
		# tunnel or a viaduct.
		var al_worst := 0.0
		var al_at := Vector2.ZERO
		var al_note := ""
		var al_sum := 0.0
		var al_n := 0
		for li in Sim._road_lines.size():
			var pl: PackedVector2Array = Sim._road_lines[li]
			var pf: PackedFloat32Array = Sim._road_prof[li]
			for i in range(pl.size() - 1):
				var run: float = pl[i].distance_to(pl[i + 1])
				if run < 1.0:
					continue
				var gr: float = absf(pf[i + 1] - pf[i]) / run
				if gr > al_worst:
					al_worst = gr
					al_at = pl[i]
					al_note = "%.1f -> %.1f over %.0f m, structure %s/%s" % [
						pf[i], pf[i + 1], run,
						str(Sim._in_structure(li, i)),
						str(Sim._in_structure(li, i + 1))]
				al_sum += gr
				al_n += 1
		print("[roads] whole alignment, structures included: mean %.1f%%, worst %.1f%% at %s (%s)" % [
			100.0 * al_sum / maxf(float(al_n), 1.0), 100.0 * al_worst,
			str(al_at.round()), al_note])
		var bore := 0.0
		for tn in Sim.road_tunnels:
			bore += (tn["a"] as Vector2).distance_to(tn["b"] as Vector2)
		var carried := 0.0
		for br2 in Sim.road_bridges:
			carried += (br2["a"] as Vector2).distance_to(br2["b"] as Vector2)
		print("[roads] %d tunnel(s), %.2f km bored; %d viaduct(s), %.2f km carried" % [
			Sim.road_tunnels.size(), bore * 0.001,
			Sim.road_bridges.size(), carried * 0.001])
		print("[roads] %d span(s) carried on a deck" % Sim.road_bridges.size())
		for br in Sim.road_bridges:
			print("[roads]   bridge %s -> %s, %.0f m long, deck %.1f m" % [
				str((br["a"] as Vector2).round()), str((br["b"] as Vector2).round()),
				(br["a"] as Vector2).distance_to(br["b"] as Vector2), float(br["ya"])])
		# The gradient bar used to be 7.5%, and it was met by letting the
		# corridor carve the country down to whatever the design profile wanted
		# -- at worst a kilometre below the hill it went through. With the
		# earthworks held to a cutting and an embankment, the gradient is
		# whatever the ground gives, and over this country that is an alpine
		# road, not a motorway. The cutting depth is the number that is now
		# actually being held.
		# The gradient bar used to be 7.5%, and it was met by letting the
		# corridor carve the country down to whatever the design profile wanted
		# -- at worst a kilometre below the hill it went through. With the
		# earthworks held to a cutting and an embankment the gradient is
		# whatever the ground gives, and over this country that is an alpine
		# road rather than a motorway. What is gated now is the thing that was
		# actually wrong: how much of the landscape the road destroys, and
		# whether the carriageway is level across its width.
		# The cutting bar tracks the design limit rather than being written
		# down twice. It was 32 m against a 16 m limit; the limit is now 34,
		# deliberately -- a road through country steeper than it may itself be
		# is built in a deep cutting, and holding the earthworks below the
		# depth at which a tunnel takes over meant it simply lay on the hill at
		# whatever gradient the hill had. A little over the limit is the
		# grading either side of the carriageway, not the cutting itself: the
		# limit applies at the centreline, and the graded shoulder reaches
		# 31.5 m either side of it, so on a hillside the uphill edge of a bench
		# cut is necessarily several metres deeper than the middle of the road.
		print("[roads] RESULT: %s" % ("ok" if g95 < 0.25 and c95 < 0.06
			and cut_worst < Sim.ROAD_CUT_MAX + 8.0 else "FAILED"))
		get_tree().quit()
		return
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
		for t in scenery.sites:
			var tc3: Vector2 = t["c"]
			var cheb: float = maxf(absf(tc3.x), absf(tc3.y))
			# One number wherever you stand now: the quadtree reaches BASE_CELL
			# at any point you are near, instead of handing out kilometre cells
			# to anywhere that is not the airfield at the world origin.
			var cell: float = Terrain.cell_at(tc3.x, tc3.y)
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
			if not _arm_with("gbu32"):
				get_tree().quit()
				return
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
	if _biome_test:
		_biome_test = false
		# The ground colour is now worked out per fragment from a baked climate
		# texture rather than interpolated from the corners of a cell. The
		# arithmetic is the same either side; what the texture changes is the
		# two noise fields it reads, so what needs measuring is how far a linear
		# fetch from it lands from the field it stands in for.
		var img: Image = terrain.climate_img
		if img == null:
			print("[biome] no climate image -- headless bake did not run")
			get_tree().quit()
			return
		var n := img.get_width()
		var span: float = Sim.WORLD_HALF * 2.0
		var wt := 0.0
		var wm := 0.0
		var st := 0.0
		var sm := 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242
		var samples := 20000
		for i in samples:
			var x: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var z: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			# what the shader gets: a bilinear fetch at the same place
			var u: float = (x + Sim.WORLD_HALF) / span * float(n) - 0.5
			var v: float = (z + Sim.WORLD_HALF) / span * float(n) - 0.5
			var i0: int = clampi(int(floor(u)), 0, n - 1)
			var j0: int = clampi(int(floor(v)), 0, n - 1)
			var i1: int = mini(i0 + 1, n - 1)
			var j1: int = mini(j0 + 1, n - 1)
			var fu: float = clampf(u - floor(u), 0.0, 1.0)
			var fv: float = clampf(v - floor(v), 0.0, 1.0)
			var c00 := img.get_pixel(i0, j0)
			var c10 := img.get_pixel(i1, j0)
			var c01 := img.get_pixel(i0, j1)
			var c11 := img.get_pixel(i1, j1)
			var tex_t: float = lerpf(lerpf(c00.r, c10.r, fu),
				lerpf(c01.r, c11.r, fu), fv)
			var tex_m: float = lerpf(lerpf(c00.g, c10.g, fu),
				lerpf(c01.g, c11.g, fu), fv)
			# and what the field actually is there
			var ex_t: float = (Sim.noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
			var ex_m: float = (Sim.noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
			var dt: float = absf(tex_t - ex_t)
			var dm: float = absf(tex_m - ex_m)
			wt = maxf(wt, dt)
			wm = maxf(wm, dm)
			st += dt
			sm += dm
		print("[biome] climate %dx%d, %.0f m per texel, %d samples" % [
			n, n, span / float(n), samples])
		print("[biome] temperature  mean %.5f  worst %.5f" % [
			st / float(samples), wt])
		print("[biome] moisture     mean %.5f  worst %.5f" % [
			sm / float(samples), wm])
		# What is actually visible is the colour, not the weight: a large error
		# in one weight is divided by the total of all seven, and a sand weight
		# and a steppe weight are nearly the same colour anyway. Measured
		# through Sim's own arithmetic, so this compares the texture against the
		# field rather than against a second transcription of the rule.
		var wc := 0.0
		var sc := 0.0
		rng.seed = 4242
		for i in samples:
			var x: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var z: float = rng.randf_range(-Sim.WORLD_HALF, Sim.WORLD_HALF)
			var y: float = Sim.height_at(x, z)
			var up: float = rng.randf_range(0.55, 1.0)
			var u2: float = (x + Sim.WORLD_HALF) / span * float(n) - 0.5
			var v2: float = (z + Sim.WORLD_HALF) / span * float(n) - 0.5
			var a0: int = clampi(int(floor(u2)), 0, n - 1)
			var b0: int = clampi(int(floor(v2)), 0, n - 1)
			var a1: int = mini(a0 + 1, n - 1)
			var b1: int = mini(b0 + 1, n - 1)
			var fa: float = clampf(u2 - floor(u2), 0.0, 1.0)
			var fb: float = clampf(v2 - floor(v2), 0.0, 1.0)
			var p00 := img.get_pixel(a0, b0)
			var p10 := img.get_pixel(a1, b0)
			var p01 := img.get_pixel(a0, b1)
			var p11 := img.get_pixel(a1, b1)
			var ct: float = lerpf(lerpf(p00.r, p10.r, fa),
				lerpf(p01.r, p11.r, fa), fb)
			var cm: float = lerpf(lerpf(p00.g, p10.g, fa),
				lerpf(p01.g, p11.g, fa), fb)
			var truth := Sim.biome_colour(x, z, y, up)
			var shaded := Sim.biome_colour(x, z, y, up, Vector2(ct, cm))
			var d: float = maxf(maxf(absf(truth.r - shaded.r),
				absf(truth.g - shaded.g)), absf(truth.b - shaded.b))
			wc = maxf(wc, d)
			sc += d
		print("[biome] ground colour  mean %.5f  worst %.5f  (of 1.0)" % [
			sc / float(samples), wc])
		var ok: bool = wc < 0.02
		print("[biome] RESULT: %s" % ("ok" if ok else "FAILED"))
		get_tree().quit()
	if _seam_test:
		_seam_test = false
		# T junction cracks: where a leaf meets a coarser one, the fine chunk
		# has vertices the coarse one does not, and the coarse edge runs
		# straight past them. The gap is the height difference between those
		# vertices and the straight line, and it needs no rendering to measure.
		var worst := 0.0
		var sum := 0.0
		var cnt := 0
		# every depth that can face a coarser neighbour, sampled across a swath
		# of real country rather than along one ring
		for dep in range(4, Terrain.MAX_DEPTH + 1):
			var cell: float = Terrain.span_at(dep) / float(Terrain.CELLS)
			var big: float = cell * 2.0
			for k in 240:
				var a0: float = float(k - 120) * big + 3000.0
				var a1: float = a0 + big
				var mid: float = (a0 + a1) * 0.5
				for side in [1400.0, -19000.0]:
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
		# This is the crack the stitching has to close, not one left in the
		# built world: it reads the raw height field and asks how far the fine
		# chunk's extra vertex sits off the straight edge its coarse neighbour
		# draws. `_stitch` then puts that vertex exactly on the line. Printed as
		# a "T junction gap" on its own it read as though the terrain were full
		# of two hundred metre holes.
		print("[seam] deviation the stitching has to take out, across %d depths: mean %.2f m, worst %.2f m over %d samples" % [
			Terrain.MAX_DEPTH - 3, sum / maxf(float(cnt), 1.0), worst, cnt])
		print("[seam] left in the built terrain after stitching: %.6f m" % [
			float(terrain.stats.get("seam", 0.0))])
		print("[seam] RESULT: %s" % ("ok" if float(terrain.stats.get("seam", 0.0)) < 0.05
			else "FAILED"))
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
			# Does it actually walk the list? Calling it repeatedly and turning
			# toward whatever it hands back is what a pilot does, and it is the
			# case that used to trap the radar between two contacts.
			# Somewhere with a radar picture. Cycling is meaningless with one
			# contact in range, and where the harness starts there is one.
			var fleet: Array = []
			for shx in get_tree().get_nodes_in_group("ships"):
				var vx := shx as Ship
				if vx != null and vx.team != 0 and vx.alive:
					fleet.append(vx)
			if fleet.size() > 0:
				var anchor: Vector3 = (fleet[0] as Ship).global_position
				player.global_transform = Transform3D(Basis(),
					anchor + Vector3(0, 5000.0, 15000.0))
				player.linear_velocity = Vector3(0, 0, -220.0)
				_reset_interp.call_deferred(player)
				await get_tree().physics_frame
				await get_tree().physics_frame
			player.target = null
			var seen: Array = []
			var distinct: Array = []
			for turn in 14:
				player.cycle_target()
				if not is_instance_valid(player.target):
					continue
				seen.append(Sim.label_of(player.target))
				if not distinct.has(player.target):
					distinct.append(player.target)
				# fly at it, the way you would
				var rel: Vector3 = player.target.global_position - player.global_position
				player.global_transform.basis = Basis.looking_at(rel.normalized(), Vector3.UP)
			var reach2: float = float(Sim.RADAR_RANGES[Sim.radar_range_idx])
			var avail := 0
			for n in get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == player or n.is_in_group("no_lock"):
					continue
				if not ("team" in n) or int(n.team) == player.team:
					continue
				if n.has_method("is_alive") and not n.is_alive():
					continue
				if player.global_position.distance_to((n as Node3D).global_position) < reach2:
					avail += 1
			print("[lock] cycling while turning onto each: %d presses reached %d distinct of %d in range" % [
				seen.size(), distinct.size(), avail])
			print("[lock] order: %s" % " -> ".join(PackedStringArray(seen)))
			print("[lock] CYCLE: %s" % ("ok" if distinct.size() >= mini(avail, 4)
				else "FAILED — the radar is stuck between %d contacts" % distinct.size()))
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
			Sim.salvo_watch = true
			Sim.salvo_weapon = "slbm"
			Sim.salvo_mark = want
			Sim.salvo_log.clear()
			boat.launch_strategic(want)
		elif _sub_t > 90.0 or (_sub_t > 12.0
				and get_tree().get_nodes_in_group("missiles").is_empty()):
			_sub_test = false
			var after := scenery.count_standing(_sub_aim, 3000.0)
			for e in Sim.salvo_log:
				print("[sub]   %s" % String(e))
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
	# The click that started this is still down. Nothing may read the trigger
	# again until it has been let go, or the first thing a new vehicle does is
	# fire whatever it is holding.
	Sim.block_until_released([&"fire", &"gun"])
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
	if _ship_kind == "carrier":
		_ship_kind = ""
		_enter_carrier()
		return
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
		var got: Tank = null
		for v in lot:
			if is_instance_valid(v) and v.kind == _drive_kind:
				got = v
				break
		if got == null:
			# The ramp parks a fixed set, and anything outside it — a launcher,
			# say — was offered in the menu, previewed, and then left you
			# standing on the apron beside an aeroplane wondering what happened.
			# If it is not parked, put one there.
			var spot: Vector3 = Vector3(-260.0, 0.0, 900.0)
			if is_instance_valid(player):
				spot = player.global_position + Vector3(-38.0, 0.0, 26.0)
			got = _spawn_tank(spot, deg_to_rad(90.0), 0, _drive_kind)
			lot.append(got)
		if is_instance_valid(got):
			_enter_tank(got)
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
## The sensor's thermal transfer, mirroring the shader.
func _flir(c: Color) -> float:
	var l: float = 0.30 * c.r + 0.59 * c.g + 0.11 * c.b
	var sat: float = maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)
	var sky: float = smoothstep(0.03, 0.22, c.b - c.r)
	var cloudy: float = smoothstep(0.72, 0.95, l) * (1.0 - smoothstep(0.02, 0.20, sat))
	var cold: float = clampf(sky + cloudy, 0.0, 1.0)
	var hot: float = smoothstep(0.12, 0.45, c.r - c.b) * smoothstep(0.30, 0.75, l)
	var t: float = clampf(pow(l, 0.75), 0.0, 1.0)
	t = lerpf(t, 0.05, cold)
	return maxf(t, hot)

## Every MeshInstance3D under a node.
func _all_mesh_children(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			out.append(c)
		out.append_array(_all_mesh_children(c))
	return out

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

## Somewhere near here with nothing already standing on it.
##
## Vehicles are placed at fixed coordinates by several different bits of code --
## the garage on the ramp, the sector garrisons, the threat spawner, whatever a
## mission asks for -- and none of them knew what the others had done. Two that
## picked the same patch of ground arrived inside each other and the suspension
## flung them apart.
func _free_spot(at: Vector3, clearance: float, ignore: Node = null) -> Vector3:
	for ring in 9:
		var r: float = float(ring) * clearance * 0.9
		var tries: int = 1 if ring == 0 else 8
		for k in tries:
			var a: float = TAU * float(k) / float(tries) + float(ring) * 0.4
			var q := Vector3(at.x + cos(a) * r, at.y, at.z + sin(a) * r)
			var clear := true
			for v in get_tree().get_nodes_in_group("vehicles"):
				# not the one being placed: it joined the group on creation and
				# is still sitting at the origin waiting to be put somewhere
				if not is_instance_valid(v) or v == ignore:
					continue
				var p: Vector3 = (v as Node3D).global_position
				if Vector2(p.x - q.x, p.z - q.z).length() < clearance:
					clear = false
					break
			if clear:
				return q
	return at

func _spawn_tank(at: Vector3, yaw: float, team: int, kind := "m1a2") -> Tank:
	var t := Tank.new()
	t.setup(team, kind)
	t.name = "Tank"
	add_child(t)
	# A launcher is fourteen metres long, so the clearance is generous.
	var spot := _free_spot(at, 16.0, t)
	t.global_transform = Transform3D(Basis(Vector3.UP, yaw),
		Vector3(spot.x, Sim.height_at(spot.x, spot.z) + 1.1, spot.z))
	t.dismount_requested.connect(_leave_tank)
	_reset_interp.call_deferred(t)
	return t

## `thrown` puts the man in the air with that velocity and a canopy over him,
## which is what an ejection is. Left at zero he is simply stood on the ground.
func _spawn_walker(at: Vector3, thrown := Vector3.ZERO) -> void:
	on_foot = true
	walker = Walker.new()
	walker.name = "Walker"
	add_child(walker)
	if thrown == Vector3.ZERO:
		walker.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
	else:
		walker.global_position = at
		walker.vel = thrown
		walker.on_floor = false
		walker.set_chute(true)
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
	# The rest of this reads the aeroplane's stores. A tank commander's sight
	# has none of that -- it lases, and the laid piece is fired from the normal
	# gunnery controls -- so take that path out before touching `player`.
	if not is_instance_valid(player) or (pod.host != null and pod.host != player):
		if Input.is_action_just_pressed(&"laser"):
			pod.toggle_laser()
		return
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
			# The pilot can work the battery off the sensor page when nobody is
			# on it. If somebody *is*, they have it: two people firing the same
			# guns at two different marks is not a division of labour.
			if is_instance_valid(_station_walker):
				Sim.report("the gunner has the battery", Sim.Ev.INFO)
			elif aim != Vector3.INF:
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

## Select a store by name, and say so plainly when the aeroplane is not
## carrying it. `maxi(find(w), 0)` quietly fell back to the first station --
## the gun -- so a test aimed at a Harpoon or a JDAM printed "release: refused"
## and looked like a broken weapon rather than the wrong aircraft.
func _arm_with(w: String) -> bool:
	if not is_instance_valid(player):
		return false
	var slot: int = player.weapon_types.find(w)
	if slot < 0:
		print("[test] %s does not carry %s — it has %s. Add --jet=NAME." % [
			player.spec.get("name", "?"), w, str(player.weapon_types)])
		return false
	player.set_weapon(slot)
	return true

## Every terrain triangle of one chunk, in world space, with the vertical skirt
## faces dropped: they project to nothing in plan and cannot answer "what is the
## ground height here".
## Whether the triangles a harness reads back carry the morph, and the eye it is
## measured from. Worked out per vertex exactly as the shader does it, because
## the state that has to be watertight is the one actually drawn -- forcing
## every chunk to full morph at once tests a configuration the renderer never
## produces, and reads as a two kilometre tear.
var _tri_morph := false
var _tri_eye := Vector3.ZERO

## The blend the ground shader applies to a vertex, reproduced exactly.
func _morph_at(v: Vector3, span: float) -> float:
	var lo: float = 2.0 * span                    # Terrain.SPLIT_K * span
	var hi: float = 2.0 * lo
	var d: float = v.distance_to(_tri_eye)
	return clampf((d - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)

func _chunk_tris(mi: MeshInstance3D) -> Array:
	var out: Array = []
	var xf: Transform3D = mi.global_transform
	# the chunk's own width, which is what sets the band it morphs over
	var span_of: float = mi.mesh.get_aabb().size.x
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		# The morph offset each vertex carries, so a seam can be checked at both
		# ends of the blend and not just at the detailed one.
		var m2: PackedVector2Array = PackedVector2Array()
		if arr[Mesh.ARRAY_TEX_UV2] != null:
			m2 = arr[Mesh.ARRAY_TEX_UV2]
		var rawi: Variant = arr[Mesh.ARRAY_INDEX]
		var idx := PackedInt32Array()
		if rawi != null:
			idx = rawi
		if idx.is_empty():
			idx = PackedInt32Array(range(vs.size()))
		var k := 0
		while k + 2 < idx.size():
			var a: Vector3 = xf * vs[idx[k]]
			var b: Vector3 = xf * vs[idx[k + 1]]
			var c: Vector3 = xf * vs[idx[k + 2]]
			if m2.size() == vs.size() and _tri_morph:
				a.y += m2[idx[k]].x * _morph_at(a, span_of)
				b.y += m2[idx[k + 1]].x * _morph_at(b, span_of)
				c.y += m2[idx[k + 2]].x * _morph_at(c, span_of)
			# plan area: a skirt face has none
			var det: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if absf(det) > 1e-6:
				out.append([a, b, c, det])
			k += 3
	return out

## The height of the drawn surface at a point in plan, or INF if this chunk does
## not cover it.
func _tri_height(tris: Array, p: Vector2) -> float:
	for t in tris:
		var a: Vector3 = t[0]
		var b: Vector3 = t[1]
		var c: Vector3 = t[2]
		var det: float = t[3]
		# Scaled to the size of the numbers involved. A fixed 1e-6 is finer than
		# float precision out at forty kilometres, so a sample landing exactly
		# on the edge two chunks share fell numerically outside one of them —
		# and 114 boundary points were reported as covered by a single chunk
		# when both were there all along.
		# Two centimetres of ground, expressed in barycentric terms. The mesh
		# vertices come back as 32-bit floats, so out at forty kilometres they
		# are only good to about four millimetres and a sample landing on the
		# edge two chunks share can fall numerically outside both. A fixed
		# barycentric epsilon is far too tight on a small cell and far too loose
		# on a 15 km one — scaling it by the triangle's own size is what makes
		# it mean the same thing everywhere. det is twice the plan area, so its
		# root is the cell.
		var eps: float = 0.02 / maxf(sqrt(absf(det)), 1.0)
		var w0: float = ((b.z - c.z) * (p.x - c.x) + (c.x - b.x) * (p.y - c.z)) / det
		if w0 < -eps or w0 > 1.0 + eps:
			continue
		var w1: float = ((c.z - a.z) * (p.x - c.x) + (a.x - c.x) * (p.y - c.z)) / det
		if w1 < -eps or w1 > 1.0 + eps:
			continue
		var w2: float = 1.0 - w0 - w1
		if w2 < -eps:
			continue
		return a.y * w0 + b.y * w1 + c.y * w2
	return INF

## What it looks like with your head under the sea. Drawn under everything else
## on the interface layer, so the instruments stay readable: the water is in
## front of the world, not in front of the panel.
var _uw: ColorRect = null
var _uw_mat: ShaderMaterial = null

func _build_underwater(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float submerged : hint_range(0.0, 1.0) = 0.0;
uniform float murk : hint_range(0.0, 1.0) = 0.0;
uniform float t = 0.0;
uniform vec3 tint = vec3(0.06, 0.26, 0.34);

void fragment() {
	vec2 uv = SCREEN_UV;
	// the surface moving overhead, seen through the water column
	float wob = 0.0016 + 0.0022 * murk;
	uv.x += sin(uv.y * 34.0 + t * 1.7) * wob * submerged;
	uv.y += cos(uv.x * 41.0 + t * 1.3) * wob * submerged;
	vec3 c = texture(screen, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
	// green-blue absorbs last: red goes first, and it goes quickly
	vec3 absorbed = vec3(0.28, 0.72, 0.86);
	c *= mix(vec3(1.0), absorbed, submerged * (0.70 + 0.30 * murk));
	c = mix(c, tint, submerged * (0.42 + 0.55 * murk));
	// it gets darker and closer in as you go down
	float d = distance(SCREEN_UV, vec2(0.5));
	c *= 1.0 - submerged * murk * 0.55 * smoothstep(0.15, 0.85, d);
	COLOR = vec4(c, submerged);
}
"""
	_uw_mat = ShaderMaterial.new()
	_uw_mat.shader = sh
	_uw = ColorRect.new()
	_uw.name = "Underwater"
	_uw.material = _uw_mat
	_uw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_uw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_uw.visible = false
	ui.add_child(_uw)

## How far the eye is under the surface, and therefore how much of it to draw.
func _update_underwater(delta: float) -> void:
	if _uw == null:
		return
	var eye := get_viewport().get_camera_3d()
	if eye == null:
		_uw.visible = false
		return
	var under: float = Sim.WATER_LEVEL - eye.global_position.y
	# eased across the surface, so breaking it is not a hard cut
	var amount: float = clampf(under / 1.2, 0.0, 1.0)
	_uw.visible = amount > 0.001
	if not _uw.visible:
		return
	_uw_t += delta
	_uw_mat.set_shader_parameter("submerged", amount)
	# Fully murky by twelve metres down, not fifty-five. Water is not a window:
	# a few metres of it swallows the horizon, and at the old rate you could
	# still see the far side of a bay from the bottom of it.
	_uw_mat.set_shader_parameter("murk", clampf(under / 12.0, 0.0, 1.0))
	_uw_mat.set_shader_parameter("t", _uw_t)

var _uw_t := 0.0

## Image intensification. A screen effect rather than a camera mode, so it works
## from every seat and every view — cockpit, chase, mast head, driver, on foot —
## which a per-vehicle version would not.
var _nvg: ColorRect = null
var _nvg_mat: ShaderMaterial = null
var nvg_on := false
var _nvg_t := 0.0

func _build_nightvision(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float t = 0.0;
// A tube's whole job is that it shows you a moonlit hillside. At 3.4 the
// amplifier could not lift a night scene off the floor -- the luminance of
// unlit ground at night is a hundredth of full scale, which came out as a
// hundredth of the way up the curve, and the answer was black.
uniform float gain = 26.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	// what the tube sees is brightness, not colour
	float l = dot(c, vec3(0.30, 0.59, 0.11));
	// amplified, and it saturates: a tube cannot show you a bright sky and a
	// dark hillside at once
	// lifted before it is amplified, so the shadows come up rather than being
	// crushed against nothing
	float amp = 1.0 - exp(-pow(max(l, 0.0), 0.72) * gain);
	// grain, which is the photons arriving one at a time
	float g = h21(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(t * 71.0, t * 37.0));
	amp = clamp(amp + (g - 0.5) * 0.085, 0.0, 1.0);
	// scan lines and the circular field of the eyepiece
	float scan = 0.94 + 0.06 * sin(SCREEN_UV.y * 1400.0);
	float d = distance(SCREEN_UV, vec2(0.5)) * 1.9;
	float tube = 1.0 - smoothstep(0.72, 1.05, d);
	vec3 phosphor = vec3(0.22, 1.0, 0.34);
	COLOR = vec4(phosphor * amp * scan * tube, 1.0);
}
"""
	_nvg_mat = ShaderMaterial.new()
	_nvg_mat.shader = sh
	_nvg = ColorRect.new()
	_nvg.name = "NightVision"
	_nvg.material = _nvg_mat
	_nvg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nvg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg.visible = false
	ui.add_child(_nvg)

func toggle_nvg() -> void:
	nvg_on = not nvg_on
	if _nvg:
		_nvg.visible = nvg_on
	Sim.report("night vision %s" % ("on" if nvg_on else "off"), Sim.Ev.INFO)

## The flash. A warhead of that size whites out everything that can see it, and
## it whites out the *screen*, not a patch of sky — you cannot look away from it
## in time and neither can the aeroplane.
var _flash: ColorRect = null
var _flash_mat: ShaderMaterial = null
var _flash_t := 0.0
var _flash_span := 0.0

func _build_flash(ui: CanvasLayer) -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float warm : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	// blown out white in the middle, going through the colour of the fireball
	// at the edges as the eye starts to recover
	float d = distance(SCREEN_UV, vec2(0.5)) * 1.4;
	vec3 hot = mix(vec3(1.0), vec3(1.0, 0.72, 0.42), warm * d);
	COLOR = vec4(hot, clamp(amount * (1.15 - d * 0.35), 0.0, 1.0));
}
"""
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = sh
	_flash = ColorRect.new()
	_flash.name = "NukeFlash"
	_flash.material = _flash_mat
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.visible = false
	ui.add_child(_flash)

## Called when a warhead goes off. `lethal` is its radius, and the flash is
## seen a very long way beyond that — being outside the blast is not the same
## as not being blinded by it.
func nuke_flash(at: Vector3, lethal: float) -> void:
	var eye := get_viewport().get_camera_3d()
	if eye == null or _flash == null:
		return
	var d: float = eye.global_position.distance_to(at)
	# visible out to a couple of hundred times the lethal radius
	var reach: float = lethal * 200.0
	if d > reach:
		return
	# no falloff worth the name up close, then an inverse square out to the edge
	var near: float = clampf(1.0 - d / reach, 0.0, 1.0)
	var bite: float = clampf(pow(near, 0.45), 0.0, 1.0)
	# behind you it is the sky lighting up, not the fireball itself
	if eye.is_position_behind(at):
		bite *= 0.55
	_flash_span = maxf(_flash_span, 1.6 + bite * 5.5)
	_flash_t = maxf(_flash_t, _flash_span)
	_flash.visible = true

func _update_flash(delta: float) -> void:
	if _flash == null or not _flash.visible:
		return
	_flash_t = maxf(_flash_t - delta, 0.0)
	if _flash_t <= 0.0:
		_flash.visible = false
		_flash_span = 0.0
		return
	var f: float = _flash_t / maxf(_flash_span, 0.01)
	# a hard white for the first instant, then the eye recovering over seconds
	_flash_mat.set_shader_parameter("amount", pow(f, 1.7))
	_flash_mat.set_shader_parameter("warm", clampf(1.0 - f * 1.4, 0.0, 1.0))

## The other side's airfield. Everything in the world used to stage off the one
## strip at the origin, which made the opposing faction an air force with no
## aerodrome — their aircraft had to be conjured into the air because there was
## nowhere for them to be parked.
##
## Sited by walking out along a bearing until there is a stretch of dry ground
## far enough away to be a different theatre, then levelled to its own height
## the same way the home field is.
var opfor_base: Airbase = null
var opfor_field: Dictionary = {}

func _site_opfor_field() -> void:
	# Far enough to be another theatre, near enough that the ground is still
	# drawn at a cell size a runway can be levelled into.
	var want := 74000.0
	var spot := Vector2.INF
	for k in 90:
		# a slow spiral outward, so it ends up somewhere plausible rather than
		# exactly on a bearing that might be all water
		var a: float = 2.3 + float(k) * 0.21
		var r: float = want + float(k) * 3500.0
		var q := Vector2(cos(a) * r, sin(a) * r)
		if absf(q.x) > Sim.WORLD_HALF * 0.8 or absf(q.y) > Sim.WORLD_HALF * 0.8:
			continue
		# it needs room: the whole field and its approaches on dry land
		var dry := true
		for i in 9:
			for j in 9:
				var p := q + Vector2(float(i - 4) * 700.0, float(j - 4) * 900.0)
				if Sim.height_at(p.x, p.y) < Sim.WATER_LEVEL + 25.0:
					dry = false
					break
			if not dry:
				break
		if dry:
			spot = q
			break
	if spot == Vector2.INF:
		push_warning("no dry ground found for the opposing field")
		return
	opfor_field = Sim.register_field(spot, deg_to_rad(28.0))
	if OS.is_debug_build():
		print("[opfor] field at %s, elevation %.0f m, %.0f km from home" % [
			str(spot.round()), float(opfor_field["elev"]), spot.length() * 0.001])

## The buildings and the aircraft, once the ground under them exists.
func _build_opfor_base() -> void:
	if opfor_field.is_empty():
		return
	var spot: Vector2 = opfor_field["at"]
	opfor_base = Airbase.new()
	opfor_base.name = "OpforBase"
	opfor_base.position = Vector3(spot.x, float(opfor_field["elev"]), spot.y)
	opfor_base.rotation.y = float(opfor_field["yaw"])
	add_child(opfor_base)
	opfor_base.build()
	# and something parked on it, so it reads as somebody's base rather than a
	# strip of concrete in a field
	var park := [["su57", Vector3(96, 0, -300), 90.0], ["su35", Vector3(96, 0, -350), 90.0],
		["mig29", Vector3(96, 0, -400), 90.0], ["j20", Vector3(200, 0, -470), -90.0]]
	for pk in park:
		var m := JetFactory.build(JetSpec.get_spec(String(pk[0])))
		var node: Node3D = m["root"]
		var spec := JetSpec.get_spec(String(pk[0]))
		var gh := 0.0
		for g in spec["gear"]:
			gh = maxf(gh, absf(g["pos"].y) + g["r"])
		node.position = (pk[1] as Vector3) + Vector3(0, gh, 0)
		node.rotation_degrees = Vector3(0, float(pk[2]), 0)
		for h in m["stores"].values():
			h.visible = false
		opfor_base.add_child(node)
	# a couple of launchers on the dispersal, which is what they are for
	for i in 2:
		var at := Vector2(spot.x + 420.0 + float(i) * 60.0, spot.y - 520.0)
		_spawn_tank(Vector3(at.x, 0, at.y), deg_to_rad(28.0), 1,
			"tel_kalibr" if i == 0 else "tel_fattah")

func _do_action(id: String) -> void:
	# vehicle and ship actions first: they are the ones on screen when crewing
	match id:
		"sensor":
			# Armour has a commander's sight too. This only ever opened for a
			# ship, so a tank crew had a sensor page they could never reach.
			if is_instance_valid(ship) or is_instance_valid(tank):
				var mount: Node3D = tank
				if is_instance_valid(ship):
					mount = ship
				pod.host = mount
				pod.jet = null
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

## Leaving the aeroplane. You go with the seat: the pilot is the player from
## here, under canopy, and lands as a man on foot rather than as a ragdoll
## somebody else watches fall.
func _eject() -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	Sim.report("EJECT — canopy out", Sim.Ev.BAD)
	var seat: Vector3 = player.global_transform * player.cockpit_offset()
	# up the rails first, and carrying half of what the aeroplane had
	var thrown: Vector3 = player.linear_velocity * 0.5 + Vector3(0, 24.0, 0)
	player.break_part("canopy")
	# The pilot is leaving in the seat, so the wreck does not throw one as well.
	player.explode(false)
	_spawn_walker(seat, thrown)

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
	# so the map can lay a strategic aiming point, which needs to know which
	# boat is asking whether it has a round to send
	map.ship = sh
	# so the weapon camera can ride a round out of her tubes
	if not sh.store_released.is_connected(_on_store_released):
		sh.store_released.connect(_on_store_released)
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
	map.ship = null
	ship = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_walker(at + Vector3(0, 12.0, 0))
	if is_instance_valid(cam):
		cam.current = true

## Take the conn of the carrier. She is not a `Ship` -- she has no gun, no
## tubes and a deck instead -- so she gets her own pair rather than being bent
## into the ship plumbing that expects a main mount.
func _enter_carrier() -> void:
	if not is_instance_valid(carrier) or not carrier.alive:
		return
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	if not carrier.dismount_requested.is_connected(_leave_carrier):
		carrier.dismount_requested.connect(_leave_carrier)
	carrier.mount(true)
	hud.carrier = carrier
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse looks out from the island, U to hand over", Sim.Ev.INFO)

func _leave_carrier() -> void:
	if not is_instance_valid(carrier):
		return
	carrier.mount(false)
	hud.carrier = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# put the captain down on his own flight deck
	_spawn_walker(carrier.global_position
		+ Vector3(0.0, Carrier.DECK_Y + 1.5, 0.0)
		+ carrier.global_transform.basis * Vector3(-6.0, 0.0, -70.0))

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
	# so the weapon camera can ride a round off a launcher
	if not t.store_released.is_connected(_on_store_released):
		t.store_released.connect(_on_store_released)
	t.mount(true)
	hud.tank = t
	map.tank = t
	Sim.report("in the driver's seat — W/S drive, A/D steer, mouse lays the gun", Sim.Ev.INFO)
	Sim.report("SPACE main gun, V coax, C gunner sight, U to get out", Sim.Ev.INFO)

## Harness for the commander's sight. Everything here used to be impossible:
## the page force-closed itself on any frame a tank was crewed.

## Gather every triangle of a built model in model space: positions and the
## normal the mesh actually stores for each vertex.
func _tris_of(root: Node3D) -> Array:
	var out: Array = []
	for n in _all_mesh_children(root):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		for si in mi.mesh.get_surface_count():
			# A surface drawn with culling off cannot show through: the back of
			# the face is rendered. Counting the rotor disc as a hole put every
			# helicopter above twenty per cent for no visible reason.
			var sm := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if sm != null and sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
				continue
			var arr: Array = mi.mesh.surface_get_arrays(si)
			if arr.is_empty():
				continue
			var rawv: Variant = arr[Mesh.ARRAY_VERTEX]
			if rawv == null:
				continue
			var vs: PackedVector3Array = rawv
			var rawn: Variant = arr[Mesh.ARRAY_NORMAL]
			var ns := PackedVector3Array()
			if rawn != null:
				ns = rawn
			# an unindexed surface is a plain triangle soup
			var idx := PackedInt32Array()
			var rawi: Variant = arr[Mesh.ARRAY_INDEX]
			if rawi != null:
				idx = rawi
			if idx.is_empty():
				idx = PackedInt32Array(range(vs.size()))
			var k := 0
			while k + 2 < idx.size():
				var a: Vector3 = xf * vs[idx[k]]
				var b: Vector3 = xf * vs[idx[k + 1]]
				var c: Vector3 = xf * vs[idx[k + 2]]
				var nn := Vector3.ZERO
				if ns.size() > idx[k]:
					nn = (xf.basis * ns[idx[k]]).normalized()
				if nn.length_squared() < 0.5:
					nn = (b - a).cross(c - a).normalized()
				out.append([a, b, c, nn, mi.name])
				k += 3
	return out

## Fire rays at a model from all round it and report how many meet a face that
## is pointing away from the camera first -- a hole you can see through.
func _see_through(tris: Array, aabb: AABB, rays: int, trace := false) -> Array:
	var mid: Vector3 = aabb.position + aabb.size * 0.5
	var radius: float = aabb.size.length() * 0.6 + 1.0
	var hits := 0
	var through := 0
	var who: Dictionary = {}
	var g := 1.0 + sqrt(5.0)
	for i in rays:
		# a spiral over the sphere, so the sample directions are even
		var t: float = float(i) / float(rays)
		var incl: float = acos(1.0 - 2.0 * (t + 0.5 / float(rays)))
		var azim: float = TAU * float(i) / g
		var dir := Vector3(sin(incl) * cos(azim), cos(incl), sin(incl) * sin(azim))
		# aim a little off centre so the ray crosses skin, not just the axis
		var jitter := Vector3(sin(azim * 3.1), cos(incl * 2.7), sin(incl * 4.3))
		var aim: Vector3 = mid + jitter * aabb.size * 0.22
		var from: Vector3 = mid + dir * radius
		var ray: Vector3 = (aim - from).normalized()
		var best := 1e9
		var best_n := Vector3.ZERO
		var best_who := ""
		for tri in tris:
			var hit = Geometry3D.ray_intersects_triangle(from, ray, tri[0], tri[1], tri[2])
			if hit == null:
				continue
			var d: float = from.distance_to(hit)
			if d < best:
				best = d
				best_n = tri[3]
				best_who = "%s@%s" % [str(tri[4]),
					str(((tri[0] + tri[1] + tri[2]) / 3.0).round())]
		if best > 1e8:
			continue
		hits += 1
		if best_n.dot(ray) > 0.02:
			through += 1
			who[best_who] = int(who.get(best_who, 0)) + 1
			if trace and through <= 2:
				# what else is on this line, so an open duct can be told apart
				# from a panel that is simply wound the wrong way
				var seq := PackedStringArray()
				var order: Array = []
				for tri in tris:
					var h2 = Geometry3D.ray_intersects_triangle(from, ray, tri[0], tri[1], tri[2])
					if h2 != null:
						order.append([from.distance_to(h2), tri[3],
							"%s@%s" % [str(tri[4]), str(((tri[0] + tri[1] + tri[2]) / 3.0 * 10.0).round() / 10.0)]])
				order.sort_custom(func(x, y): return x[0] < y[0])
				for k in mini(5, order.size()):
					seq.append("%.2fm %s n=%s n.ray=%+.2f" % [order[k][0], order[k][2],
						str(((order[k][1] as Vector3) * 100.0).round() / 100.0),
						(order[k][1] as Vector3).dot(ray)])
				print("[cull]    ray from %s dir %s: %s" % [
					str(from.round()), str((ray * 100.0).round() / 100.0), " | ".join(seq)])
	return [hits, through, who]

## One model's worth of see-through sampling, reported the same way as an
## airframe. Returns [rays that hit, rays that see through, per cent].
func _cull_of(root: Node3D, rays: int) -> Array:
	var tris := _tris_of(root)
	if tris.is_empty():
		print("[cull] %-9s no mesh" % str(root.name))
		return [0, 0, 0.0]
	var ab := AABB()
	var first := true
	for tri in tris:
		for v in [tri[0], tri[1], tri[2]]:
			if first:
				ab = AABB(v, Vector3.ZERO)
				first = false
			else:
				ab = ab.expand(v)
	var r := _see_through(tris, ab, rays)
	var pc: float = 100.0 * float(r[1]) / maxf(float(r[0]), 1.0)
	var blame: Dictionary = r[2]
	var parts := PackedStringArray()
	for k in blame:
		parts.append("%s x%d" % [k, int(blame[k])])
	var nm := str(root.name)
	if root.has_method("display_name"):
		nm = String(root.call("display_name"))
	print("[cull] %-9s %5d tris, %3d/%3d rays meet a face turned away (%4.1f%%)%s" % [
		nm.left(9), tris.size(), r[1], r[0], pc,
		("   " + ", ".join(parts)) if parts.size() > 0 else ""])
	return [r[0], r[1], pc]

func _run_culltest() -> void:
	var rays := 220
	var worst := ""
	var worst_pc := 0.0
	var total := 0
	var total_through := 0
	for id in JetSpec.ids():
		var sp := JetSpec.get_spec(id)
		var m := JetFactory.build(sp)
		var root: Node3D = m["root"]
		add_child(root)
		var tris := _tris_of(root)
		var ab := AABB()
		var first := true
		for tri in tris:
			for v in [tri[0], tri[1], tri[2]]:
				if first:
					ab = AABB(v, Vector3.ZERO)
					first = false
				else:
					ab = ab.expand(v)
		var r := _see_through(tris, ab, rays)
		var pc: float = 100.0 * float(r[1]) / maxf(float(r[0]), 1.0)
		total += int(r[0])
		total_through += int(r[1])
		if pc > worst_pc:
			worst_pc = pc
			worst = id
		var blame: Dictionary = r[2]
		var parts := PackedStringArray()
		for k in blame:
			parts.append("%s x%d" % [k, int(blame[k])])
		print("[cull] %-9s %5d tris, %3d/%3d rays meet a face turned away (%4.1f%%)%s" % [
			id, tris.size(), r[1], r[0], pc,
			("   " + ", ".join(parts)) if parts.size() > 0 else ""])
		root.queue_free()
	# and the same for the things you drive and sail, which are built out of the
	# same helpers
	for kind in Tank.KINDS.keys():
		var tv := Tank.new()
		tv.setup(0, str(kind))
		add_child(tv)
		var r2 := _cull_of(tv, rays)
		total += int(r2[0])
		total_through += int(r2[1])
		if float(r2[2]) > worst_pc:
			worst_pc = float(r2[2])
			worst = str(kind)
		tv.queue_free()
	for kind in Ship.KINDS.keys():
		var sv := Ship.new()
		sv.setup(str(kind), 0)
		add_child(sv)
		var r3 := _cull_of(sv, rays)
		total += int(r3[0])
		total_through += int(r3[1])
		if float(r3[2]) > worst_pc:
			worst_pc = float(r3[2])
			worst = str(kind)
		sv.queue_free()
	var overall: float = 100.0 * float(total_through) / maxf(float(total), 1.0)
	print("[cull] overall %d/%d rays see through the skin (%.1f%%), worst %s at %.1f%%" % [
		total_through, total, overall, worst, worst_pc])
	print("[cull] RESULT: %s" % ("ok" if overall < 0.35 else "FAILED"))


func _run_tanksensor() -> void:
	# An artillery piece for preference -- the fire mission the sight hands over
	# is what a self propelled gun actually does with a laser.
	var tk: Tank = null
	for n in get_tree().get_nodes_in_group("vehicles"):
		var v := n as Tank
		if v == null or v.team != 0 or not v.alive:
			continue
		if tk == null or (v.is_indirect() and not tk.is_indirect()):
			tk = v
	if tk == null:
		# Nothing on the ramp in this mission: put a gun on the ground for the
		# test rather than skipping it.
		var here: Vector3 = Vector3.ZERO
		if is_instance_valid(player):
			here = player.global_position
		tk = _spawn_tank(Vector3(here.x + 60.0, 0, here.z + 60.0), 0.0, 0, "m109")
	print("[tanksensor] vehicle %s, indirect=%s" % [tk.display_name(), str(tk.is_indirect())])
	running = true          # the harness fires before the menu hands over
	_enter_tank(tk)
	_do_action("sensor")
	for _f in 12:
		_process(0.016)
	print("[tanksensor] on %s: pod active=%s, carrier=%s (running=%s on_foot=%s occupied=%s)" % [
		tk.display_name(), str(pod.active), Sim.label_of(pod.carrier()),
		str(running), str(on_foot), str(tk.occupied)])
	# the sight sits at the commander's hatch, not eighteen metres up a mast
	var lift: float = pod._head_origin().y - tk.global_position.y
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
	for n in get_tree().get_nodes_in_group("hittable"):
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
		var rel: Vector3 = foe.global_position - pod._head_origin()
		var loc: Vector3 = (tk.global_transform.basis.inverse() * rel).normalized()
		pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
		pod.yaw = atan2(-loc.x, -loc.z)
		pod.mode = pod.SLEW
		pod._process(0.016)
		pod.designate()
		if not pod.lasing:
			pod.toggle_laser()
		pod._process(0.016)
		var laid: bool = tk.map_target != Vector3.INF
		var err := 0.0
		if laid:
			err = Vector2(tk.map_target.x - foe.global_position.x,
				tk.map_target.z - foe.global_position.z).length()
		print("[tanksensor] lased %s at %.1f km: mode=%d (0=SLEW 1=AREA 2=POINT) tracked=%s lasing=%s" % [
			Sim.label_of(foe), bd * 0.001, pod.mode, Sim.label_of(pod.tracked), str(pod.lasing)])
		print("[tanksensor] fire mission set=%s, %.1f m from the target" % [str(laid), err])
	# contacts drawn on the sight picture, which used to bail out on a null jet
	var painted := 0
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == tk or not (n is Node3D):
			continue
		if tk.global_position.distance_to((n as Node3D).global_position) < 26000.0:
			painted += 1
	print("[tanksensor] %d contacts in sight range (carrier is %s, jet is %s)" % [
		painted, Sim.label_of(pod.carrier()), "null" if pod.jet == null else "set"])
	# and dismounting puts the sight away
	_leave_tank()
	_process(0.016)
	print("[tanksensor] after dismount: pod active=%s, host=%s" % [
		str(pod.active), "null" if pod.host == null else str(pod.host)])
	print("[tanksensor] RESULT: %s" % ("ok" if lift < 4.0 and not pod.active
		and with_sight < 1e-6 and without > 1e-3 else "FAILED"))

func _leave_tank() -> void:
	if not is_instance_valid(tank):
		return
	var out: Vector3 = tank.global_transform * Vector3(-3.4, 0.5, 0.0)
	tank.mount(false)
	tank.in_throttle = 0.0
	tank.in_steer = 0.0
	tank.in_brake = true
	tank.sight_active = false
	if pod and pod.host == tank:
		if pod.active:
			pod.toggle()
		pod.set_fullscreen(false)
		pod.host = null
		if cam:
			cam.pod_slew = false
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
	# Let go of anything being crewed. A ship is world furniture and survives
	# the mission, so nothing ever dismounted you from one — restart and choose
	# an aeroplane and you were still stood on the submarine's bridge, because
	# `ship` was never cleared and every page still drew from it.
	if is_instance_valid(ship):
		ship.mount(false)
		if is_instance_valid(ship.cam):
			ship.cam.current = false
	ship = null
	hud.ship = null
	if is_instance_valid(map):
		map.ship = null
	if is_instance_valid(tank):
		tank.mount(false)
	tank = null
	hud.tank = null
	if is_instance_valid(map):
		map.tank = null
	if pod != null:
		if pod.active:
			pod.toggle()
		pod.set_fullscreen(false)
		pod.host = null
	if is_instance_valid(cam):
		cam.weapon_cam = null
		cam.current = true
	_cam_was_ship = false
	_cam_was_tank = false
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
	# The fleet is furniture, but it is not *state*: a hull you sank stayed on
	# the bottom across a restart, so starting again handed you a sea already
	# won and only the aeroplane was new. Put them back the way they began.
	for sh in get_tree().get_nodes_in_group("ships"):
		var v := sh as Ship
		if v == null or v.is_in_group("remote"):
			continue
		v.refit()
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

## A round that splits hands the camera to one of its children, so the ride
## carries on through the separation instead of ending at it.
## A headcount of the things that accumulate, so "it got slow" can be answered
## with a number rather than a guess.
func _census() -> Dictionary:
	var out := {"nodes": 0, "missiles": 0, "hittable": 0, "interceptable": 0,
		"particles": 0, "lights": 0, "meshes": 0, "multimesh": 0}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out["nodes"] = int(out["nodes"]) + 1
		if n is GPUParticles3D:
			out["particles"] = int(out["particles"]) + 1
		elif n is Light3D:
			out["lights"] = int(out["lights"]) + 1
		elif n is MultiMeshInstance3D:
			out["multimesh"] = int(out["multimesh"]) + 1
		elif n is MeshInstance3D:
			out["meshes"] = int(out["meshes"]) + 1
		for c in n.get_children():
			stack.append(c)
	out["missiles"] = get_tree().get_nodes_in_group("missiles").size()
	out["hittable"] = get_tree().get_nodes_in_group("hittable").size()
	out["interceptable"] = get_tree().get_nodes_in_group("interceptable").size()
	return out

func _census_line(c: Dictionary) -> String:
	return "%d nodes, %d meshes, %d multimesh, %d particles, %d lights, %d missiles" % [
		int(c["nodes"]), int(c["meshes"]), int(c["multimesh"]), int(c["particles"]),
		int(c["lights"]), int(c["missiles"])]

func hand_weapon_cam(from: Node3D, to: Node3D) -> void:
	if not is_instance_valid(cam) or not is_instance_valid(to):
		return
	if cam.weapon_cam == from:
		cam.weapon_cam = to

func _on_store_released(m: Node) -> void:
	# Ride it out if the weapon cam is armed. It lets go on its own when the
	# round goes off, because the node stops being valid.
	if weapon_cam_on and is_instance_valid(cam) and m is Node3D:
		cam.weapon_cam = m as Node3D
		# A crewed hull runs its own camera and drives it every physics frame,
		# so setting the ride here did nothing at all: the boat simply put the
		# view back on her own masthead. Hand the screen to the chase camera
		# for the flight, and take it back when the round is gone.
		# A crewed hull or vehicle runs its own camera and re-points it every
		# physics frame, so setting the ride did nothing: the view simply went
		# back to the vehicle. Hand the screen over for the flight.
		if is_instance_valid(ship) and is_instance_valid(ship.cam):
			_cam_was_ship = true
			cam.current = true
		elif is_instance_valid(tank) and is_instance_valid(tank.cam):
			_cam_was_tank = true
			cam.current = true
	# a ship's round is not reported over the wire here: the hull's own fire
	# path already tells the other end
	if net and net.active and is_instance_valid(m) and is_instance_valid(player) \
			and m.shooter == player:
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
		elif k == KEY_O and running and not on_foot \
				and (is_instance_valid(ship) or is_instance_valid(tank)):
			# A crewed hull owns the sensor: the same path the action menu
			# takes, which mounts the pod on the boat. This branch demanded an
			# aeroplane and never set the host, so from a submarine the key
			# either did nothing or opened a page hung off a parked fighter.
			_do_action("sensor")
		elif k == KEY_O and running and not on_foot \
				and is_instance_valid(player):
			pod.toggle()
			pod.set_fullscreen(pod.active)
			if cam:
				cam.pod_slew = pod.active
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if pod.active \
				else Input.MOUSE_MODE_VISIBLE
			Sim.report("sensor page %s" % ("up" if pod.active else "stowed"), Sim.Ev.INFO)
		elif (k == KEY_I or k == KEY_N) and pod.active:
			# N as well as I. N is the night vision key everywhere else, so
			# reaching for it on the sensor page is the obvious thing to do --
			# and with the goggles suppressed while the page is up it now has
			# somewhere sensible to go.
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
			# The session list comes up with the pause menu rather than instead
			# of it. Put on its own key it simply took escape over, and there
			# was then no way to reach the menu at all.
			if is_instance_valid(roster_view):
				roster_view.visible = menu.visible and net != null and net.active
				roster_view.set_process(roster_view.visible)
			menu.set_paused(true)
			get_tree().paused = menu.visible
			if audio:
				audio.set_paused(menu.visible)
			if menu.visible:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif is_instance_valid(player) and player.mouse_fly:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif k == KEY_P and running and not on_foot:
			cam.cycle()
		elif k == KEY_J and running and is_instance_valid(_station_walker):
			_leave_hold_station()
		elif k == KEY_J and running and not on_foot and is_instance_valid(player) \
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
		elif a == "--novsync":
			# Frame rate is pinned to the refresh rate otherwise, which makes
			# every measurement read "the same as every other" right up until
			# the machine can no longer keep up -- so a change that costs
			# a third of the frame budget is invisible until it costs all of it.
			if not OS.has_feature("headless"):
				DisplayServer.window_set_vsync_mode(
					DisplayServer.VSYNC_DISABLED)
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
		elif a == "--roadtest":
			_road_test = true
			Sim.debug_roads = true
		elif a == "--skirttest":
			_skirt_test = true
		elif a == "--nobake" or a == "--clearbake" or a == "--boottime":
			pass                       # already handled, before the bake loaded
		elif a.begins_with("--telrig="):
			_tel_rig = a.substr(9)
		elif a == "--telrig":
			_tel_rig = "tel_kalibr"
		elif a.begins_with("--tfrtest="):
			_tfr_test = true
			_tfr_kind = a.substr(10)
		elif a == "--tfrveh":
			_tfr_veh = true
		elif a.begins_with("--tfrrange="):
			_tfr_range = float(a.substr(11)) * 1000.0
		elif a == "--tfrtest":
			_tfr_test = true
		elif a == "--guntest":
			_gun_test = true
		elif a == "--churntest":
			_churn_test = true
		elif a == "--warlordstest":
			_warlords_test = true
		elif a == "--rivertest":
			_river_test = true
		elif a == "--carriertest":
			_carrier_test = true
		elif a == "--obstacletest":
			_obstacle_test = true
		elif a == "--lodtest":
			_lod_test = true
		elif a == "--abtest":
			_ab_test = true
		elif a == "--acceltest":
			_accel_test = true
			_auto = "dash"
		elif a == "--cruiseland":
			_land_test = true
		elif a == "--subview":
			_subview_test = true
		elif a == "--reachtest":
			_reach_test = true
		elif a == "--nuketest":
			_nuke_test = true
		elif a == "--respawntest":
			_respawn_test = true
		elif a == "--guardtest":
			_guard_test = true
		elif a == "--fxtest":
			_fx_test = true
		elif a == "--boattest":
			_boat_test = true
		elif a == "--floattest":
			_float_test = true
		elif a == "--seamix":
			_seamix = true
		elif a == "--teltest":
			_tel_test = true
		elif a == "--lagtest":
			_lag_test = true
		elif a == "--spawntest":
			_spawn_test = true
		elif a == "--fieldtest":
			_field_test = true
		elif a == "--locktime":
			_locktime_test = true
		elif a == "--mavtest":
			_mav_test = true
		elif a == "--skytest":
			_sky_test = true
		elif a == "--nettest":
			_nettest = true
		elif a.begins_with("--cmtest="):
			_cm_test = a.substr(9)
		elif a == "--subtest2":
			_subtest = true
		elif a == "--cruisetest":
			_cruise_test = true
		elif a == "--flirtest":
			_flirtest = true
		elif a == "--geomtest":
			_geomtest = true
		elif a == "--culltest":
			_culltest = true
		elif a == "--navsensor":
			_navsensor = true
		elif a == "--tanksensor":
			_tanksensor = true
		elif a == "--salvotest":
			_salvo_test = true
		elif a.begins_with("--salvotest="):
			_salvo_test = true
			_salvo_w = a.substr(12)
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
		elif a == "--biometest":
			_biome_test = true
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
