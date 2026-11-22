extends Node3D
class_name World
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

## The command-line test harness: see `TestHarness`. Null in a normal game.
var harness: TestHarness = null
## Parts of the world kept in their own scripts; see each class.
var vision_fx := VisionFx.new(self)
var fleet_yard := FleetYard.new(self)
var country_bases := CountryBases.new(self)
var chart_follow := ChartFollow.new(self)
var street_fight := StreetFight.new(self)

var terrain: Terrain
var base: Airbase
var scenery: Scenery
## The planet as a body, for when the ground is too far below to be worth it.
var planet: Planet
## The lakes and inland seas: see `lakes.gd`. Loaded by path rather than by
## class name, so a fresh checkout runs before the editor has scanned it.
const LAKES_SCRIPT := preload("res://scripts/world/lakes.gd")
var lakes: Node3D
## The cloud layer, wrapped round the planet rather than round the camera.
var clouds: CloudShell
## The atmosphere shell.
var atmo: Atmosphere
## The moon: see `Moon` for why it is not where it is.
var moon: Moon
var weather: Weather
var _env: Environment
var _sun: DirectionalLight3D
var _fill: DirectionalLight3D
var _psm: ShaderMaterial
var menu: Menu
## ESC in a match. The hangar used to be the pause menu as well.
var pause_menu: PauseMenu
var hud: HUD
var cam: ChaseCamera
var menu_cam: Camera3D
## The camera the hangar opens on: a slow circuit over the inhabited country,
## which is what the loading screen has just spent its time building.
var cine_cam: Camera3D
var _cine_t := 0.0
## Where it circles, how wide, how high and how fast. Over the home valley, far
## enough up to see the coast and the towns and low enough for the roads to
## read, and slow enough that it is a drift rather than a flypast -- at radius
## times rate it works out at about sixty metres a second, which is also as fast
## as the ground can be built in front of it.
const CINE_AT := Vector2(-1200.0, 1800.0)
const CINE_RADIUS := 7600.0
## Under the cloud deck, which the scattered preset puts at 2100 m: above it the
## camera spends the whole circuit inside the volumetric fog and the hangar
## opens on a grey screen.
const CINE_ALT := 1620.0
const CINE_RATE := 0.008
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
var _view := ""
var _nocockpit := false
var _openbay := false
var _dist := 0.0
var _flight_lead: AIPlane = null
var _cas_lead: AIPlane = null
var _auto_diag := false
var _slot_home := Vector3.INF
var _slot_said := -1
var _mission_started := 0
## --jet= as given, for the tests that should fly what was asked for.
var _jet_arg := ""
var _arty_test := ""
var _dash_alt := 1000.0
var _bank_deg := 0.0
var _net_host := false
var _net_join := ""
var _drive_kind := ""
var _orbit := Vector2.ZERO
var pilot: Pilot
var board_cam: Camera3D
var boarding := false
var audio: AudioRig
var pod: SensorPod
var actions: ActionMenu
var map: MapView
var carrier: Carrier
var obstacles: Obstacles
var weapon_cam_on := false
var _cam_was_ship := false
var _cam_was_tank := false
## On foot, the screen is his own eyes; riding a round it is the chase camera's
## until the round has gone off and been watched going off.
var _cam_was_walker := false
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
var _pre_gun_auto := ""
var _station_walker: Node = null
var _board_t := 0.0
var _board_from := Vector3.ZERO
var _board_ladder := Vector3.ZERO
var _board_seat := Vector3.ZERO
var _skip_board := false
var _shot_at := 0
var _at := Vector3.ZERO
## Right button held on a bridge: the ship's or the carrier's own camera
## narrows, the same as the chase camera does in an aeroplane. Their cameras
## are set to one field of view when they are built and never touched again,
## so the easing in and out is done here.
var _hull_zoom := false
const HULL_FOV := 62.0

func _ease_hull_zoom(delta: float) -> void:
	var c: Camera3D = null
	if is_instance_valid(ship):
		c = ship.cam
	elif _at_conn():
		c = carrier.cam
	else:
		_hull_zoom = false
	if c == null or not is_instance_valid(c):
		return
	var want: float = HULL_FOV * (0.32 if _hull_zoom else 1.0)
	c.fov = lerpf(c.fov, want, clampf(delta * 8.0, 0.0, 1.0))

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
	child_entered_tree.connect(_note_match_child)
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
	# Has to be set before any mesh is built, or there are no wireframe indices
	# to draw when the sonar view asks for them.
	RenderingServer.set_debug_generate_wireframes(true)
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
		if a == "--flat":
			# The old 1200 km height field, for the measurements written against
			# it. Read here because the field, the terrain and the sea all ask
			# which world this is as they come up, and by `_parse_cmdline` they
			# are already built.
			Sim.globe = false
		elif a == "--globe":
			Sim.globe = true
		elif a.begins_with("--faction="):
			# Whose side, and therefore where the world is built. Read here
			# because the chart is put on that country below and everything
			# after it -- the ground, the roads, the towns, the aerodrome -- is
			# laid out from there.
			var who := a.substr(10)
			if Sim.HOMELANDS.has(who):
				Sim.home_faction = who
			else:
				push_warning("no country called '%s'; flying for %s" % [
					who, Sim.home_faction])
		elif a == "--nobake":
			WorldBake.enabled = false
		elif a == "--clearbake":
			WorldBake.clear()
		elif a == "--boottime":
			_boot_verbose = true
		elif a == "--debugroads":
			# Before the network is laid, not after: this is the flag that
			# instruments the survey, and `_parse_cmdline` does not run until
			# the world is already built.
			Sim.debug_roads = true
	# Whichever world it is, the extension has to be told before anything asks
	# it for ground: the router, the survey and the terrain all do, and by the
	# time the bake is opened the answer is already being used.
	# On the country this sortie is flown from. There is no main airfield: the
	# world is built around wherever you begin.
	Sim.set_chart(Sim.home_dir())
	# ...and this is the chart everything built once is laid down in: see
	# `Sim.boot_affine` and `_carry_fixed`.
	Sim.mark_boot_chart()
	# Where the lakes are, before anything is sited: a town, a road and a tree
	# all ask where the water is.
	var _tl := Time.get_ticks_msec()
	Sim.index_lakes()
	if _boot_verbose:
		print("[lakes] %d found round the chart in %d ms" % [Sim.lakes.size() >> 2, Time.get_ticks_msec() - _tl])
	# The chart is on the country now, so the home strip can be put on the
	# ground that is there rather than on the sea level it used to assume.
	Sim.resite_home_field()
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
	country_bases.site_country_fields()
	_mark.call("siting airfields")
	await _paint("Surveying the ground", 0.26)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.prepare()
	# The whole queue to the pool at once, then collected as it lands.
	#
	# Sixty-four at a time was chosen when a chunk was assembled in script and
	# the queue was what took the time. The assembly is in the extension now and
	# all three hundred and forty of them cost fourteen milliseconds of *this*
	# thread; what was left was the round trip -- dispatch, paint, collect, paint
	# -- four frames a batch and twenty-one frames to drain the queue. Measured,
	# 238 ms of waiting for 14 ms of work. Handed over in one go the pool builds
	# them all while the screen keeps painting, which is what the pumping was
	# for in the first place.
	while terrain.pending_count() > 0:
		terrain.build_queued(terrain.pending_count())
		await _paint("Building the ground", lerpf(0.30, 0.50,
			terrain.build_progress()),
			"%d of %d chunks" % [terrain.stats["chunks"],
				int(terrain.stats["chunks"]) + terrain.pending_count()])
	terrain.flush_pending()
	_mark.call("terrain")
	await _paint("Building the airfields", 0.50)
	country_bases.build_country_bases()
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
	# Nothing is put to sea here any more: not the squadron, not the carrier,
	# not even the search for water to float them in. The missions that are
	# fought at sea muster them when they start; see `muster_fleet`.
	for a in OS.get_cmdline_user_args():
		if a == "--fleet" or a.contains("test"):
			_fleet_always = true
	if _fleet_always:
		# a harness may look at the sea before it has started anything
		fleet_yard.build_carrier()
		fleet_yard.build_fleet()

	menu_cam = Camera3D.new()
	menu_cam.far = 45000.0
	menu_cam.fov = 42.0
	add_child(menu_cam)
	# And the camera the hangar actually opens on: a slow circuit over the
	# country rather than a turntable in the middle of nothing. The world is the
	# thing that took nine seconds to build; showing a jet against an empty
	# backdrop was throwing it away.
	cine_cam = Camera3D.new()
	cine_cam.far = 60000.0
	cine_cam.fov = 55.0
	# Moved every frame rather than every physics tick, so it is not the
	# interpolator's business -- left on, the engine warns about being driven
	# from outside `_physics_process` and the drift comes out a frame stale.
	cine_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cine_cam)
	_fly_past(0.0)
	# Not yet. This camera stands on the home airfield looking at the turntable,
	# so anything the airbase parks near the origin -- a tug, a stand, a
	# revetment -- sits in the middle of its view, and it was the current camera
	# for the whole of world generation. Nothing should be rendering the world
	# while the loading screen is up; it is made current when the menu is.

	preview = Node3D.new()
	preview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(preview)
	_stand_rig()

	net = NetLink.new()
	net.name = "NetLink"
	net.world = self
	add_child(net)
	Sim.net = net

	var ui := CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	vision_fx.build_underwater(ui)
	vision_fx.build_nightvision(ui)
	vision_fx.build_flash(ui)
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
	# so the main view can show where the sensor is looking
	hud.pod = pod
	_place_pod()
	get_viewport().size_changed.connect(_place_pod)
	chat = ChatBox.new()
	ui.add_child(chat)
	map = MapView.new()
	map.world = self
	ui.add_child(map)
	hud.map_view = map
	await _paint("Drawing the map", 0.88)
	map.bake()
	_mark.call("map")
	# Painted with the map's own relief, so the ground you fly over and the
	# ground you see from orbit are the same picture. It needs the bake, so it
	# cannot be built before this point.
	planet = Planet.new()
	planet.name = "Planet"
	add_child(planet)
	planet.build(map.relief())
	# The water standing above the sea, faded with the ground into the body.
	lakes = LAKES_SCRIPT.new()
	lakes.name = "Lakes"
	lakes.set("planet", planet)
	add_child(lakes)
	clouds = CloudShell.new()
	clouds.name = "Clouds"
	add_child(clouds)
	clouds.build()
	# The air, over the clouds and under them. Built after the shell because it
	# is sized from the deck it straddles.
	atmo = Atmosphere.new()
	atmo.name = "Atmosphere"
	add_child(atmo)
	atmo.build()
	moon = Moon.new()
	moon.name = "Moon"
	add_child(moon)
	moon.build()
	_mark.call("planet")
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
	# Faded in once the country has been on screen for a moment; see
	# `_reveal_menu`.
	menu.modulate.a = 0.0
	menu.jet_changed.connect(_set_preview)
	menu.weather_changed.connect(set_weather)
	menu.start_requested.connect(_on_launch)
	menu.host_requested.connect(_host_game)
	# the slot depends on the roster, which arrives after the mission starts
	net.roster_changed.connect(_offset_for_peer)
	menu.mission_changed.connect(_on_lobby_mission)
	menu.join_requested.connect(_join_game)
	menu.side_changed.connect(func(sd: int) -> void:
		if net != null:
			net.set_side(sd)
			Sim.report("you are %s" % ("BLUE" if sd == 0 else "RED"), Sim.Ev.INFO))
	menu.resume_requested.connect(_resume)
	menu.settings_requested.connect(func() -> void: pause_menu.open_settings())
	ui.add_child(menu)
	# After the hangar, so it draws over it: the hangar opens the settings page
	# too, and the deploy screen is put in below the hangar.
	pause_menu = PauseMenu.new()
	pause_menu.name = "Pause"
	pause_menu.world = self
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart_match)
	pause_menu.change_mode_requested.connect(_pause_to_hangar)
	ui.add_child(pause_menu)
	# Not yet: this puts a vehicle on the hangar turntable, forty metres in
	# front of the menu camera, and the menu camera is the one running while the
	# world is still being built. Built here it stood there through the rest of
	# the loading screen.
	# Everything generated this run that will be the same the next one.
	WorldBake.put_grown("node_stats", Sim.native.terrain_stats_take())
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
	# The world first, behind the screen that is still up. No turntable and no
	# vehicle on it: the hangar opens on the country, and a model only appears
	# once somebody has asked to look at one.
	cine_cam.current = true
	preview.visible = false
	get_viewport().disable_3d = false
	if _loading != null:
		_loading.finish()
		# Held for a moment on "Ready", then faded. Freed the instant the last
		# phase finished, the screen was cut away mid-frame and the menu behind
		# it appeared out of nowhere -- and with the world already being drawn
		# behind it, whatever the screen did not cover showed through.
		var lp := _loading.get_parent()
		var held := 0.0
		while held < 0.35:
			held += get_process_delta_time()
			await get_tree().process_frame
		var fade := 0.0
		while fade < 1.0:
			fade += get_process_delta_time() / 0.45
			_loading.modulate.a = clampf(1.0 - fade, 0.0, 1.0)
			await get_tree().process_frame
		_loading = null
		if is_instance_valid(lp):
			lp.queue_free()
	_parse_cmdline()
	# The country on its own for a moment, and then the hangar over it. Put up
	# the instant the loading screen came down, the menu covered the view before
	# anyone had seen it.
	#
	# Started rather than awaited, and after the command line: a harness must
	# not sit through three seconds of a fade it is never going to look at, and
	# anything that has already been asked to fly is past the hangar anyway.
	_reveal_menu()

## Put the turntable and its camera in the air over the home field.
##
## They were written down as 258 m and 263.5 m, which was a quarter of a
## kilometre of clear air when the ground at the origin was sea level. The home
## strip is on its country's own ground now -- three hundred metres up for some
## of them -- so the rig was inside the hill: the "sky" behind the vehicle was
## the underside of the terrain, green, and the sea shell ran through the
## picture below it. Measured from the ground that is actually there.
const RIG_CLEAR := 256.0
var _rig_y := 258.0

func _stand_rig() -> void:
	_rig_y = maxf(Sim.height_at(0.0, 0.0), Sim.sea_at(0.0, 0.0)) + RIG_CLEAR + 2.0
	if preview != null:
		preview.position = Vector3(0, _rig_y, 0)
	if menu_cam != null:
		menu_cam.position = Vector3(30, _rig_y + 5.5, -30)
		menu_cam.look_at(Vector3(0, _rig_y, 0), Vector3.UP)
		menu_cam.rotate_y(deg_to_rad(19.0))

## Hold on the flypast, then bring the hangar up over it.
func _reveal_menu() -> void:
	if running or _shot != "" or not menu.visible:
		menu.modulate.a = 1.0
		return
	var held := 0.0
	while held < 2.6:
		held += get_process_delta_time()
		await get_tree().process_frame
	var fade := 0.0
	while fade < 1.0:
		fade += get_process_delta_time() / 1.1
		menu.modulate.a = clampf(fade, 0.0, 1.0)
		await get_tree().process_frame
	menu.modulate.a = 1.0

## Where the hangar camera is on its circuit. Anti-clockwise at a walking pace,
## rising and falling a little so the horizon moves.
func _fly_past(t: float) -> void:
	if cine_cam == null:
		return
	var a: float = t * CINE_RATE
	var at := CINE_AT + Vector2(cos(a), sin(a)) * CINE_RADIUS
	var y: float = CINE_ALT + sin(t * 0.03) * 190.0
	cine_cam.position = Vector3(at.x, y, at.y)
	# Aimed at the ground ahead and inward rather than at the middle of the
	# circle: fixed on the centre the whole time it reads as a turntable with a
	# valley on it instead of as flying over a country.
	var ahead := at + Vector2(-sin(a), cos(a)) * 5400.0 \
		+ (CINE_AT - at).normalized() * 5200.0
	cine_cam.look_at(Vector3(ahead.x, Sim.sea_at(ahead.x, ahead.y) + 120.0, ahead.y), Vector3.UP)

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
	# Fill light from a colour, not from the sky.
	#
	# The sky used to be the blue, so taking ambient from it was free. The
	# atmosphere shell is the blue now -- measured, it comes out rgb(0.30, 0.48,
	# 0.75) on its own, which is a sky -- and the gradient behind it has to go
	# dark or the two add up to the flat white this was reported for. A dark sky
	# feeding ambient would take every scrap of fill light with it and leave the
	# ground black, so the fill is named here instead. Its energy still follows
	# the weather and the hour.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.66, 0.85)
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
	# Off. Measured with --fpstest over free flight it was a millisecond of a
	# 12.5 ms frame -- about eight frames a second -- for the bloom round the
	# brightest lights. The tuning is left below, so it is one line to put back.
	env.glow_enabled = false
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
	# Asking to see a vehicle is what ends the flypast. Until then the hangar
	# stands over the country with nothing on the turntable.
	if not booting and cine_cam != null and cine_cam.current:
		# The chart may have moved since the rig was stood up.
		_stand_rig()
		menu_cam.current = true
		preview.visible = true
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
	# Where the planet is in its year. Pushed to everything that colours ground
	# -- the terrain shader, the extension's map rasteriser and `Sim`'s own copy
	# of the biome rule -- from the one clock, so all three agree about what
	# season it is. They are three copies of the same arithmetic and the biome
	# test compares them; a season held in only one of them would fail it.
	if weather != null:
		var sn: float = weather.season()
		if absf(sn - Sim.season) > 0.002:
			Sim.season = sn
			if Sim.native != null:
				Sim.native.set_season(sn)
			if is_instance_valid(terrain):
				terrain.set_season(sn)
	# The haze thins as the air does. Done here rather than in `apply`, because
	# it is a function of where the eye is and that changes every frame.
	#
	# Where the *picture* is taken from, not where you are. It was your own
	# vehicle's height, so riding a launcher's round up its ballistic arc on
	# the weapon camera -- a hundred kilometres up and more -- drew the whole
	# planet through sea-level haze: the fog's far end at a hundred and forty
	# kilometres and everything beyond it a flat grey wash.
	if weather != null and _env != null:
		var eye: Node3D = get_viewport().get_camera_3d()
		if eye == null:
			eye = _me_or_player()
		if eye != null:
			weather.thin_air(_env, Sim.altitude(eye.global_position), _psm)
	var _pw := Sim.prof_at()
	_tick_world(delta)
	Sim.prof_end(&"world.total", _pw)

func _tick_world(delta: float) -> void:
	# `_ready` is a coroutine now, so frames run while the world is still being
	# made and almost nothing in here exists yet.
	if booting:
		return
	if cine_cam != null and cine_cam.current:
		_cine_t += delta
		_fly_past(_cine_t)
	if preview and preview.visible and spin:
		preview.rotate_y(delta * 0.35)
	if harness != null:
		harness.tick_before_sensors(delta)
	# Armour keeps its sight. This used to shut the pod on any frame a tank was
	# crewed, so the commander's sight closed itself the instant it opened.
	if is_instance_valid(tank):
		tank.sight_active = pod != null and pod.active and pod.platform == tank
	if pod and pod.active and is_instance_valid(tank) and pod.platform != tank:
		pod.toggle()
		pod.set_fullscreen(false)
		if cam:
			cam.pod_slew = false
	if pod and pod.active and not gunning and is_instance_valid(pod.platform):
		_sensor_input()
	if gunning:
		_gunner_input(delta)
	# The battery follows the sight whether or not the trigger is down, so the
	# barrels are visibly laid on the mark before the first round leaves them.
	if is_instance_valid(player) and player.has_method("aim_battery") \
			and pod != null and pod.active:
		var lay: Vector3 = pod.aim_point()
		if lay != Vector3.INF and player.has_method("lay_battery"):
			player.lay_battery(lay)
	if pod and pod.active and not gunning \
			and (not running or on_foot or not is_instance_valid(pod.platform)):
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
	# back to his own eyes once it has gone off and been watched going off
	if _cam_was_walker and (not is_instance_valid(cam) or not cam.riding()):
		_cam_was_walker = false
		if on_foot and is_instance_valid(walker) and is_instance_valid(walker.cam) \
				and not walker.dead:
			walker.cam.current = true
	# The ground follows the eye. Rebuilds are metered so crossing a ring
	# boundary at five hundred knots does not stall the frame: a chunk is 289
	# height samples and a mesh, and a boundary crossing can want dozens.
	Sim.prof_frame()
	var _pf := Sim.prof_at()
	# On the planet the chart rides with the player, which is what turns the
	# rest of the world from scenery into somewhere you can go.
	chart_follow.follow_chart()
	# ...and the two pictures a chart move asked for, whenever they land. Here
	# rather than in the map's own `_process`, which only runs while the map is
	# open.
	if is_instance_valid(map):
		map.pump_sheet()
	if is_instance_valid(terrain):
		terrain.pump_climate()
	Sim.prof_end(&"chart", _pf)
	if is_instance_valid(terrain):
		var eye3 := get_viewport().get_camera_3d()
		if eye3 != null:
			# How much planet and how much ground, and how far the eye can see.
			if is_instance_valid(planet):
				var _pp := Sim.prof_at()
				planet.follow(eye3, terrain, scenery)
				Sim.prof_end(&"planet.follow", _pp)
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
			# Nothing to rebuild while the body has it: the chunks are hidden,
			# and the whole point of the sphere is not to be paying for them.
			if not is_instance_valid(planet) or not planet.dormant:
				var _pr := Sim.prof_at()
				terrain.recentre(eye3.global_position + lead)
				Sim.prof_end(&"terrain.recentre", _pr)
		# A bigger bite than it looks: the batch is built on the worker pool and
		# collected on a later frame, so this costs the main thread a dispatch
		# and whatever meshes came back, not the generation. The old chunks stay
		# up until their replacements are in, so falling behind costs memory
		# rather than holes in the ground.
		terrain.flush_pending(24)
		if is_instance_valid(obstacles) and eye3 != null:
			obstacles.follow(eye3.global_position)
		# and the roads painted sharp round wherever you are
		if eye3 != null:
			terrain.follow_roads(eye3.global_position)
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
	vision_fx.update_underwater(delta)
	vision_fx.update_flash(delta)
	if _nvg != null and _nvg.visible:
		_nvg_t += delta
		_nvg_mat.set_shader_parameter("t", _nvg_t)
	if _sonar != null and _sonar.visible:
		_nvg_t += delta
		_sonar_mat.set_shader_parameter("t", _nvg_t)
	# ...unless the sensor page has the key. N steps the pod's channel, and
	# swallowing it here meant the channel could never be changed from inside
	# the very page it belongs to.
	if running and not Sim.ui_modal and not (is_instance_valid(pod) and pod.active) \
			and Sim.tapped(&"night_vision"):
		vision_fx.toggle_nvg()
	Sim.ui_modal = (is_instance_valid(map) and map.visible) \
		or (is_instance_valid(actions) and actions.visible) \
		or (is_instance_valid(chat) and chat.typing) \
		or (is_instance_valid(deploy_ui) and deploy_ui.visible) \
		or get_tree().paused
	if harness != null:
		harness.tick_after_input(delta)
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
		if net.active:
			menu.show_side_counts(net.side_counts())
	# The cloud volume rides with whatever camera is actually current — the
	# cockpit, the chase, the sensor pod, a ship's bridge — not with the
	# aircraft chase camera specifically. Handing the sky the wrong eye position
	# is what made it look welded to the view.
	if is_instance_valid(weather):
		var eye := get_viewport().get_camera_3d()
		if eye != null:
			var _pw := Sim.prof_at()
			weather.follow(eye.global_position)
			Sim.prof_end(&"weather.follow", _pw)
		# The shell takes its weather from the same preset the sky does, so
		# "overcast" means the same thing to both.
		if is_instance_valid(clouds):
			clouds.apply(weather.cloud_cover(), weather.cloud_density(), _sun)
		# The rim, the sky dome and the terminator all follow the sun.
		if is_instance_valid(atmo):
			if is_instance_valid(_sun):
				# Toward the sun, not away from it. A directional light shines
				# along its own -Z, so `-basis.z` is where the light is going;
				# the shader wants where it is coming from. Handed the
				# anti-solar direction the shell's day-side gate reads zero, so
				# the atmosphere was fully transparent exactly where it should
				# have been blue.
				atmo.aim(_sun.global_transform.basis.z)
			# ...and it rides with the camera, or the far plane cuts it away.
			var vc: Camera3D = get_viewport().get_camera_3d()
			if vc != null:
				atmo.follow(vc)
				# After the planet has set this camera's far plane: the moon
				# is carried at a fraction of it.
				if is_instance_valid(moon) and is_instance_valid(_sun):
					moon.follow(vc, _sun.global_transform.basis.z)
		# The same for the cloud: its mesh is only which pixels get to ask.
		if is_instance_valid(clouds):
			clouds.follow(get_viewport().get_camera_3d())
	if is_instance_valid(hud) and is_instance_valid(cam) and running:
		hud.flight_page = (cam.mode == ChaseCamera.Mode.COCKPIT) \
			and not is_instance_valid(cam.weapon_cam)
	if boarding:
		_tick_boarding(delta)
	if running and is_instance_valid(player) and not boarding and not on_foot:
		_watch_landing(delta)
	if harness != null:
		if harness.tick_after_flight(delta):
			return
	# hold the view on something real while following
	if is_instance_valid(admin) and admin.following and is_instance_valid(cam):
		if not is_instance_valid(cam.subject) or not _traffic.has(cam.subject):
			_follow_traffic(true)
	if harness != null:
		if await harness.tick_main(delta):
			return
	street_fight.tick_town_sets(delta)
	if is_instance_valid(cqb):
		street_fight.tick_cqb_support(delta)
	street_fight.tick_bounds(delta)
	if harness != null:
		harness.tick_after_street(delta)
	_ease_hull_zoom(delta)
	if harness != null:
		harness.tick_end(delta)


# ---------------------------------------------------------------- missions
func set_weather(id: String) -> void:
	Sim.weather = id
	if weather:
		weather.apply(id, _env, _sun, _fill, _psm)

func _start(id: String, mission: String) -> void:
	# a "veh:" selection means the player starts in the driver's seat instead
	var drive_kind := ""
	var ship_kind := ""
	# Starting in something other than an aeroplane put you on the ramp
	# whatever mission was picked, so a launcher with STRIKE selected came up
	# on an empty range: no column, no shipping, nothing on the map worth a
	# fire mission. The strike range has nothing that shoots back at anybody,
	# which suits a gun or a launcher as well as it does a jet.
	var keep := mission == "strike" or mission in ["ground", "arms"]
	# "foot" is a choice in the modes that are fought over a town: no vehicle
	_cqb_on_foot = id == "foot" or mission in ["cqb", "range"]
	# ON FOOT in a mode flown from the field: on the flight line beside the
	# aeroplane, the way the ramp walk starts. It was not on offer at all.
	var foot_at_field: bool = id == "foot" and mission not in ["cqb", "ground", "arms", "range", "ramp"]
	if id == "foot":
		# whatever aeroplane was last looked at in the hangar says whose side
		# this is, which is what the deploy screen offers vehicles from
		var last := String(menu.jet_id) if is_instance_valid(menu) else ""
		id = last if (last != "" and last != "foot" and not last.contains(":")) else "f16"
	var kept_mission := mission
	if id.begins_with("sea:"):
		ship_kind = id.substr(4)
		id = "f16"
		mission = "strike" if kept_mission == "strike" else "ramp"
	if id.begins_with("veh:"):
		drive_kind = id.substr(4)
		id = "f16"
		mission = kept_mission if keep else "ramp"
	_drive_kind = drive_kind
	_ship_kind = ship_kind
	Sim.selected_jet = id
	Sim.mission = mission
	# The click that started this is still down. Nothing may read the trigger
	# again until it has been let go, or the first thing a new vehicle does is
	# fire whatever it is holding.
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
	Sim.score = 0
	get_tree().paused = false
	Sim.menu_open = false
	_clear_mission()
	fleet_yard.muster_fleet(kept_mission, ship_kind != "")
	# no fight, no edges, and the whole country back
	_bounds_c = Vector3.INF
	street_fight.show_far_scenery()
	# Every mission opens the map as it always has, on the planet and framing
	# the ground you are on; a street fight puts it on the chart below.
	if is_instance_valid(map):
		map.globe = Sim.globe
		map.zoom = 29.0
		map.follow = true
	menu.visible = false
	# a hangar shown from the pause page said RESUME and LAUNCH NEW; the next
	# time it comes up it is between matches
	menu.set_paused(false)
	menu.set_redeploy(false)
	_redeploy_wait = false
	if is_instance_valid(pause_menu):
		pause_menu.close()
	_show_roster(false)
	preview.visible = false
	hud.visible = true
	running = true
	_audit_spawns.call_deferred()
	_slot_home = Vector3.INF
	_slot_said = -1
	_mission_started = Time.get_ticks_msec()
	_offset_for_peer.call_deferred()
	# Everyone else in the session starts it too: a restart as much as a
	# change of mode. See `NetLink.announce_match`.
	if net != null and net.active and net.is_host:
		net.announce_match(kept_mission)

	_make_player(id)

	var gear_h := 0.0
	for g in player.spec["gear"]:
		gear_h = maxf(gear_h, absf(g["pos"].y) + g["r"])

	match mission:
		"takeoff":
			player.global_transform = Transform3D(Basis(),
				Vector3(0, _apron_y(0.0, 1380.0) + gear_h + 0.02, 1380.0))
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
			player.global_transform = Transform3D(Basis(),
				Vector3(140.0, _apron_y(140.0, z) + 640.0, z))
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
		"sandbox":
			# Everything to play with, in one place. The ramp lays out the
			# flight line and the vehicle park; the rest is what the other
			# no-threat modes never had — something in the air to shoot at, and
			# the orbital picture already overhead.
			_setup_ramp()
			_populate("bandits")
			_populate("choppers")
			_populate("warships")
			_populate("sats")
			Sim.report("SANDBOX — the park, the flight line, hostile aircraft, gunships and shipping, and the satellites.",
				Sim.Ev.INFO)
			Sim.report("F3 opens the admin page: it can add any of them in any mission.",
				Sim.Ev.INFO)
		"conquest", "rush", "warlords", "tdm", "ffa":
			_setup_battle(mission)
		"cqb", "ground", "arms", "range":
			street_fight.setup_cqb(mission)
		"carrier":
			_setup_carrier_approach()
		"launch":
			_setup_launch("orbital")
		"moon":
			_setup_launch("lunar")
		"strike":
			_setup_strike()
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
	if foot_at_field:
		if boarding:
			_end_boarding()
		_foot_at_field()

## On foot on the flight line: the aeroplane parked on the apron, canopy up,
## and the man beside it, free to walk to it or to any other.
func _foot_at_field() -> void:
	if not is_instance_valid(player):
		return
	# one aeroplane on the spot: the one left there by the last time
	var spot := Vector3(150.0, 0.0, -150.0)
	for j in parked.duplicate():
		if is_instance_valid(j) and j != player and (j as Node3D).global_position.distance_to(
				Vector3(spot.x, (j as Node3D).global_position.y, spot.z)) < 15.0:
			parked.erase(j)
			(j as Node).queue_free()
	player.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
		Vector3(150.0, _apron_y(150.0, -150.0) + _stance(player.spec), -150.0))
	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.gear_down = true
	player.gear_anim = 1.0
	player.throttle = 0.0
	player.power = 0.0
	player.active = false
	player.set_canopy(true, true)
	player.add_to_group("boardable")
	if not parked.has(player):
		parked.append(player)
	_reset_interp(player)
	var nose: float = maxf(absf(player.bounds.position.z), absf(player.bounds.end.z))
	_spawn_walker(player.global_transform * Vector3(0.0, 0.0, -(nose + 5.0)))
	# Not stepped out to a spawn slot afterwards: that moved the aeroplane a
	# hundred metres from the man standing beside it. A parked aeroplane is
	# only on its own player's screen, so there is nothing for it to collide
	# with.
	_slot_home = Vector3(1e9, 0, 0)

# ------------------------------------------------------------------ redeploy
## Down, in a mode that is not a street fight: after a moment the hangar comes
## up to choose what to go back in as, and REDEPLOY puts you back into the same
## match. There was nothing at all -- a joiner who was shot down could not
## restart a match that was not his, and sat looking at his wreck.
var _redeploy_wait := false

func _offer_redeploy() -> void:
	if _redeploy_wait or is_instance_valid(cqb) or not running:
		return
	_redeploy_wait = true
	var gen := _mission_started
	await get_tree().create_timer(3.5).timeout
	_redeploy_wait = false
	if not running or gen != _mission_started or not is_inside_tree():
		return
	# still down? something else may already have put him back
	var down: bool = (on_foot and is_instance_valid(walker) and walker.dead) \
		or (is_instance_valid(tank) and not tank.alive) \
		or (not on_foot and not is_instance_valid(tank) and (not is_instance_valid(player)
			or not player.is_alive()))
	if not down:
		return
	Sim.report("choose what to go back in as, and REDEPLOY", Sim.Ev.INFO)
	menu.set_redeploy(true)
	menu.visible = true
	Sim.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_crew_down(who: Node) -> void:
	if who == tank:
		_offer_redeploy()

## LAUNCH, or REDEPLOY when the hangar is up for that.
func _on_launch(id: String, mission: String) -> void:
	if menu.redeploy:
		_redeploy(id)
	else:
		_start(id, mission)

## Back into the match that is running, as `id`: an aeroplane at this mode's
## start, a vehicle at the park, or on foot on the flight line.
var _redeploy_replace := false

func _redeploy(id: String) -> void:
	# chosen in place of what he was in, rather than after losing it: that
	# one goes, rather than standing about on the runway
	if _redeploy_replace and is_instance_valid(player) and player.is_alive() \
			and not parked.has(player):
		player.queue_free()
		player = null
	_redeploy_replace = false
	menu.set_redeploy(false)
	menu.visible = false
	Sim.menu_open = false
	Sim.block_until_released([&"fire", &"gun"])
	if is_instance_valid(tank):
		tank.mount(false)
	tank = null
	hud.tank = null
	if is_instance_valid(walker) and not is_instance_valid(_station_walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	on_foot = false
	var mission := String(Sim.mission)
	var jet := id
	if id == "foot" or id.begins_with("veh:") or id.begins_with("sea:"):
		jet = String(Sim.selected_jet) if not String(Sim.selected_jet).contains(":") else "f16"
	# the wreck stays where it fell; this is a new aeroplane
	if is_instance_valid(player) and player.is_alive() and not parked.has(player):
		parked.append(player)
	player = null
	_make_player(jet)
	player.died.connect(func(_w): _offer_redeploy())
	if id == "foot" or id.begins_with("veh:") or id.begins_with("sea:"):
		_foot_at_field()
		if id.begins_with("veh:"):
			var b: Vector3 = base.global_position if is_instance_valid(base) else Vector3.ZERO
			var t := _spawn_tank(Vector3(b.x + 196.0, 0.0, b.z - 470.0), deg_to_rad(-90.0), 0,
				id.substr(4))
			_enter_tank(t)
	else:
		_place_at_start(mission)
		_slot_home = Vector3.INF
	_slot_said = -1
	_mission_started = Time.get_ticks_msec()
	_offset_for_peer.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Sim.report("back in", Sim.Ev.GOOD)

## Where this mode starts an aeroplane: on the runway, on the approach, or in
## the air over the fight.
func _place_at_start(mission: String) -> void:
	var gear_h := 0.0
	for g in player.spec["gear"]:
		gear_h = maxf(gear_h, absf(g["pos"].y) + g["r"])
	if mission in ["takeoff", "ramp", "sandbox"]:
		player.global_transform = Transform3D(Basis(),
			Vector3(0, _apron_y(0.0, 1380.0) + gear_h + 0.02, 1380.0))
		player.gear_down = true
		player.gear_anim = 1.0
		player.throttle = 0.0
		player.flaps = 1.0
		player.flap_anim = 1.0
		player.set_canopy(false, true)
	elif mission == "landing":
		var z := Airbase.AIM_Z + 12000.0
		player.global_transform = Transform3D(Basis(), Vector3(140.0, _apron_y(140.0, z) + 640.0, z))
		player.rotation = Vector3(deg_to_rad(-3.0), deg_to_rad(-1.2), 0.0)
		player.linear_velocity = -player.global_transform.basis.z * _entry_speed(148.0)
		player.gear_down = true
		player.gear_anim = 1.0
		player.flaps = 1.0
		player.throttle = 0.42
		player.power = 0.42
	else:
		var at := Vector3(-600.0, 2400.0, 7000.0)
		var yaw := deg_to_rad(-4.0)
		if mission in ["conquest", "rush", "warlords", "tdm", "ffa", "combat"]:
			at = Vector3(-500.0, 3600.0, 7200.0)
			if NetLink.local_team(0) == 1:
				at = Vector3(500.0, 3700.0, -12500.0)
				yaw = PI + deg_to_rad(4.0)
		player.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
		player.linear_velocity = -player.global_transform.basis.z * _entry_speed(240.0)
		player.gear_down = false
		player.gear_anim = 0.0
		player.throttle = 0.8
		player.power = 0.8
	_reset_interp(player)

## The player's aircraft, built and wired to every page that reads it. Also
## what a street fight uses to put somebody in the air in the middle of a
## match: see `StreetFight.cqb_fly`.
func _make_player(id: String) -> void:
	# What everyone else draws this player as. It was the aeroplane he had
	# selected when he pressed HOST or JOIN and never again: a host who then
	# chose a C-130 was a fighter on every other screen.
	if net != null and net.active:
		net.set_jet(id)
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
	player.died.connect(func(_w):
		Sim.report("you were shot down", Sim.Ev.BAD)
		_offer_redeploy())

	if cam == null:
		cam = ChaseCamera.new()
		add_child(cam)
		Effects.round_watch = _offer_round
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
		cam.orbit_fixed = true
		cam.orbit = _orbit if _orbit != Vector2.ZERO else Vector2(2.3, 0.18)
	if _openbay:
		player.set_bays(true)
	if _nocockpit:
		for n in player._model.get("cockpit_parts", []):
			n.visible = false
	player.debug_forces = _dump > 0
	cam.subject = player
	cam.current = true
	hud.aircraft = player
	veil.aircraft = player
	hud.cam = cam
	pod.platform = player
	map.aircraft = player
	if "pod" in player:
		player.pod = pod
	for ab in bases:
		if is_instance_valid(ab):
			(ab as Airbase).watcher = player
	if is_instance_valid(base):
		base.watcher = player
	_reset_interp.call_deferred(player)

## A body that was just teleported has stale interpolation history; without this
## it renders a smear from its old position to the new one.
func _reset_interp(n: Node3D) -> void:
	if is_instance_valid(n):
		n.reset_physics_interpolation()

# ------------------------------------------------------------- boarding
## Walk out, climb the ladder, strap in, canopy down. Any key skips it.
func _begin_boarding(from_ladder := false) -> void:
	# Nobody climbs into a drone: it is flown from a ground station.
	if _skip_board or _auto != "" or bool(player.spec.get("unmanned", false)):
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
	if NetLink.local_team(0) == 1:
		# RED, in a session: from behind the far side's sectors, heading south
		# at the BLUE side coming up from the field
		player.global_transform = Transform3D(Basis(), Vector3(500.0, 3700.0, -12500.0))
		player.rotation.y = PI + deg_to_rad(4.0)
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
	# the war is fought over the sectors; the rest of the world waits
	street_fight.hide_beyond_sectors(mode._layout)
	var wings: int = 3 if id in ["tdm", "ffa"] else 3
	_spawn_threats(wings)
	# Somebody on our side. Every battle mode put the player up alone against a
	# flight, a pair of gunships and the ground war -- a team deathmatch with a
	# team of one. Free for all is the one where there is no side to be on.
	if id != "ffa":
		_spawn_allies()

## Our own flight and a pair of gunships, flying our side's hardware. They find
## their own fights the same way the opposition does, by team.
const ALLY_WINGS := 3
func _spawn_allies() -> void:
	if net != null and net.active and not net.is_host:
		return
	var nato: bool = JetSpec.bloc_of(Sim.selected_jet) == "nato"
	var jets: Array = NATO_JETS if nato else OPFOR_JETS
	var rotary: Array = NATO_HELIS if nato else OPFOR_HELIS
	var lead: AIPlane = null
	for i in ALLY_WINGS:
		var b := AIPlane.new()
		b.setup(jets[i % jets.size()])
		b.team = 0
		b.name = "Blue %d" % (i + 1)
		b.home = Vector3(1200.0 * i - 1200.0, 0.0, -2600.0)
		b.patrol_r = 2600.0 + i * 500.0
		add_child(b)
		# off the player's wing, heading the same way into the fight
		var at := Vector3(-500.0 + (i + 1) * 420.0, 3500.0 - i * 120.0, 7500.0 + i * 260.0)
		b.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-4.0)), at)
		b.linear_velocity = -b.global_transform.basis.z * 230.0
		if i % 2 == 1 and is_instance_valid(lead):
			b.leader = lead
			b.slot = Vector3(90.0, -18.0, 120.0)
		else:
			lead = b
		b.died.connect(_on_ally_down)
		_reset_interp.call_deferred(b)
	for i in 2:
		var h := AIHeli.new()
		h.setup(rotary[i % rotary.size()])
		h.team = 0
		h.name = "Blue Gunship %d" % (i + 1)
		h.home = Vector3(-1200.0 + i * 2400.0, 0.0, -3400.0)
		add_child(h)
		var hz: float = 600.0 + i * 300.0
		var hx: float = -800.0 + i * 1600.0
		h.global_transform = Transform3D(Basis(Vector3.UP, 0.0),
			Vector3(hx, Sim.height_at(hx, hz) + 220.0, hz))
		h.died.connect(_on_ally_down)
		_reset_interp.call_deferred(h)
	Sim.report("friendlies up: %d fighters and a pair of gunships on our side" % ALLY_WINGS,
		Sim.Ev.INFO)

func _on_ally_down(who: Node) -> void:
	if mode and mode.running:
		mode.register_kill(0)
	Sim.report("%s is down" % who.name, Sim.Ev.BAD)

## The range with nothing on it that can hurt an aeroplane: armour columns,
## shipping and helicopters to find and hit, wave after wave.
func _setup_strike() -> void:
	if _drive_kind != "" or _ship_kind != "":
		# in a vehicle or a boat: the ramp parks the aeroplanes and puts you
		# in the seat, and the range is laid out round it the same as ever
		_setup_ramp()
	else:
		player.global_transform = Transform3D(Basis(), Vector3(-500.0, 3000.0, 6000.0))
		player.rotation.y = deg_to_rad(-4.0)
		player.linear_velocity = -player.global_transform.basis.z * _entry_speed(230.0)
		player.gear_down = false
		player.gear_anim = 0.0
		player.throttle = 0.8
		player.power = 0.8
	mode = GameMode.new()
	mode.name = "GameMode"
	add_child(mode)
	mode.start("strike")
	mode.finished.connect(_on_mode_finished)
	hud.mode = mode
	Sim.report("the column is up the valley, the shipping is offshore east; M for the map",
		Sim.Ev.INFO)

func _on_mode_finished(_win: bool, _text: String) -> void:
	pass

# ------------------------------------------------------------------- CQB
## The street fight, if one is running.
var cqb: CqbMatch = null
var _cqb_gunship: Aircraft = null
var _cqb_gun_t := 0.0
var _cqb_parked: Aircraft = null
var _cqb_tel: Tank = null
var _cqb_tel_t := 0.0

## Kept here for the scripts that reach it by name: see `StreetFight.cqb_gunship`.
func cqb_gunship(centre: Vector3, kind := "ac130") -> bool:
	return street_fight.cqb_gunship(centre, kind)


## Kept here for the scripts that reach it by name: see `StreetFight.cqb_fire_mission`.
func cqb_fire_mission(mark: Vector3) -> bool:
	return street_fight.cqb_fire_mission(mark)

var _bounds_c := Vector3.INF
var _cqb_on_foot := false
var firing_range: FiringRange = null

## The deploy screen: class, gunsmith and what to go in as.
var deploy_ui: DeployMenu = null

var _cqb_parked_at: Array = []

# ------------------------------------------------------------------ the rocket
var _pad: Node3D = null

func _in_rocket() -> bool:
	return is_instance_valid(rocket) and rocket.occupied

## Somewhere level and dry near the field to stand a rocket on: east of the
## runway for choice, so the first thing it flies over is not the flight line.
func _pad_site() -> Vector3:
	var best := Vector3(2800.0, 0.0, -400.0)
	var best_rough := 1e9
	for o in [Vector2(2800, -400), Vector2(3600, 900), Vector2(2800, -2400),
			Vector2(4800, 0), Vector2(-2800, -400), Vector2(-3600, 1200),
			Vector2(0, -5200), Vector2(0, 5200)]:
		var c: Vector2 = o
		var h: float = Sim.height_at(c.x, c.y)
		if h < Sim.sea_at(c.x, c.y) + 3.0:
			continue
		var rough := 0.0
		for d in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
			rough = maxf(rough, absf(Sim.height_at(c.x + d.x, c.y + d.y) - h))
		if rough < best_rough:
			best_rough = rough
			best = Vector3(c.x, 0.0, c.y)
		if rough < 2.0:
			break
	return best

## On the pad, in the capsule, with everything still to do.
func _setup_launch(which := "orbital") -> void:
	_setup_ramp()
	var at := _pad_site()
	var ground: float = maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z))
	_pad = Node3D.new()
	_pad.name = "LaunchPad"
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(70.0, 8.0, 70.0), Vector3(0.0, -4.0, 0.0))
	# the flame trench, and the tower beside it
	MeshKit.box(st, Vector3(9.0, 108.0, 9.0), Vector3(22.0, 54.0, 0.0))
	for arm_y in [28.0, 58.0, 82.0, 96.0]:
		MeshKit.box(st, Vector3(16.0, 1.6, 2.4), Vector3(12.0, arm_y, 0.0))
	_pad.add_child(MeshKit.mi(MeshKit.finish(st,
		MeshKit.mat(Color(0.52, 0.50, 0.47), 0.85, 0.1)), "Pad"))
	add_child(_pad)
	_pad.global_position = Vector3(at.x, ground, at.z)
	rocket = LaunchVehicle.new()
	rocket.name = "LaunchVehicle"
	rocket.setup(Vector3(at.x, ground, at.z), which)
	add_child(rocket)
	_enter_rocket()

func _enter_rocket() -> void:
	if not is_instance_valid(rocket):
		return
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	if not rocket.dismount_requested.is_connected(_leave_rocket):
		rocket.dismount_requested.connect(_leave_rocket)
	rocket.mount(true)
	hud.rocket = rocket
	Sim.report("%s — hold SHIFT for full throttle; it lifts when thrust beats weight, or H flies it" %
		rocket.display_name().to_upper(), Sim.Ev.GOOD)
	Sim.report("straight up first, then lean east a little at a time. T sets the attitude hold; SPACE drops a dry stage",
		Sim.Ev.INFO)
	Sim.report("orbit is about 7.8 km/s ACROSS at 200 km, not up. The panel shows the orbit's high and low points",
		Sim.Ev.INFO)

func _leave_rocket() -> void:
	if not is_instance_valid(rocket):
		return
	if rocket.alive and (not rocket.landed or rocket.throttle > 0.01):
		Sim.report("not from up here: put it on the ground first", Sim.Ev.BAD)
		return
	var at: Vector3 = rocket.global_position + Vector3(16.0, 0.0, 6.0)
	rocket.mount(false)
	hud.rocket = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_spawn_walker(Vector3(at.x, maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z)) + 1.2, at.z))

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
		Vector3(150.0, _apron_y(150.0, float(slot[1])) + _stance(player.spec),
			float(slot[1])))
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
			Vector3(150.0, _apron_y(150.0, float(row[i][1])) + _stance(j.spec),
				float(row[i][1])))
		j.gear_down = true
		j.gear_anim = 1.0
		j.set_canopy(true, true)
		j.add_to_group("boardable")
		j.add_to_group("hittable")
		_reset_interp.call_deferred(j)
		parked.append(j)
	player.set_canopy(true, true)
	# The apron parks OUR vehicles, and only ours. It used to lay out a T-90, a
	# ZTZ-99 and a Msta on the home flight line alongside the Abrams and hand
	# them all to the player on team 0 — a Russian tank in American markings
	# parked outside an American hangar, friendly to the side it belongs to the
	# other of. Everybody else's kit belongs in their own country, and this
	# world already knows where that is: `Sim.region_faction` says whose ground
	# any point on the map is.
	var mine := String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa"))
	var garage := PackedStringArray()
	var abroad := PackedStringArray()
	for k in Tank.KINDS:
		var f := String(Tank.KINDS[k].get("faction", ""))
		if f == mine:
			garage.append(String(k))
		elif f != "":
			abroad.append(String(k))
	var lot: Array[Tank] = []
	for i in garage.size():
		# Twenty-four metres apart, not fifteen: an ASAT launcher is over
		# fourteen metres long and a Patriot not much less, so at the old
		# spacing the long vehicles sat almost nose to tail.
		lot.append(_spawn_tank(Vector3(196.0, 0, -424.0 - i * 24.0),
			deg_to_rad(-90.0), 0, garage[i]))
	_apron_count = garage.size()
	_deploy_abroad(abroad)
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
			var at := fleet_yard.deep_water(Vector3(26000.0, 0, 2400.0))
			pick.global_position = Vector3(at.x, Sim.sea_surface(at.x, at.z), at.z)
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

## Where the player actually is, whatever they are in.
##
## The map was handed the aeroplane and nothing else, so the moment you climbed
## out of it -- onto a ship, into a tank, up to the carrier's bridge or onto
## your own feet -- your position stopped being drawn on it. You are always in
## something; this is that thing, and it is what anything wanting to mark "you"
## should ask for.
func controlled() -> Node3D:
	if _in_rocket():
		return rocket
	if is_instance_valid(carrier) and carrier.occupied:
		return carrier
	if is_instance_valid(ship) and ship.occupied:
		return ship
	if is_instance_valid(tank) and tank.occupied:
		return tank
	if on_foot and is_instance_valid(walker):
		return walker
	if is_instance_valid(player):
		return player
	return null

## Whatever the view is from: the weapon camera's round if one is riding,
## otherwise whatever the player is in.
func _me_or_player() -> Node3D:
	if is_instance_valid(cam):
		var riding: Variant = (cam as Node).get("weapon_cam")
		if riding != null and is_instance_valid(riding) and riding is Node3D:
			return riding
	return controlled()

## The home field's pavement at a point, as a world height.
##
## Everything laid out on the aerodrome -- the flight line, the vehicle park,
## the takeoff and landing starts, the airfield traffic -- was written as an
## absolute world `y`. That was the pavement's height for as long as the home
## strip sat at sea level by definition, and there was nothing to add. The
## strip is now sited on its country's own ground, so an absolute height puts
## an aeroplane under the apron by however high that country is.
func _apron_y(x: float, z: float) -> float:
	if Sim.fields.is_empty():
		return 0.0
	return Sim.field_elev(Sim.fields[0], x, z)

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


## Kept here for the scripts that reach it by name: see `FleetYard.deep_water_near`.
func _deep_water_near(at: Vector3, rings: int) -> Vector3:
	return fleet_yard.deep_water_near(at, rings)

## A measurement run. The harnesses were written against a sea that always had
## the squadron on it, whatever mission they happened to start.
var _fleet_always := false

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
	if _slot_home != Vector3.INF and _slot_home.x >= 1e8:
		return                          # on foot on the flight line: see `_foot_at_field`
	if _slot_home == Vector3.INF:
		_slot_home = player.global_position
	if Time.get_ticks_msec() - _mission_started > 15000:
		return                          # the roster has settled; leave it alone
	var slot: int = net.spawn_slot()
	var off: Vector3 = net.spawn_offset()
	if off == Vector3.ZERO:
		return
	# On the ground by where it is, not by `on_ground`: an aeroplane made this
	# frame says it is on the ground until its first physics step, so every
	# joiner in an airborne start -- free flight, a battle, an approach -- was
	# set down on the terrain at flying speed and destroyed before the first
	# frame was drawn. The host, slot 0, is never moved, so only joiners met
	# it: two players in a session who could not see each other.
	var agl: float = _slot_home.y - Sim.height_at(_slot_home.x, _slot_home.z)
	if agl < 30.0 or Sim.mission == "ramp" or Sim.mission == "takeoff":
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

## Put everybody else's vehicles where they belong: on ground that is actually
## theirs. The map is generated with a nationality per region, so this walks out
## looking for a patch that answers to the right country and leaves the vehicle
## standing on it — friendly or hostile according to which bloc it is from,
## rather than everything being handed to the player.
func _deploy_abroad(kinds: PackedStringArray) -> void:
	var placed := 0
	for k in kinds:
		var want := String(Tank.KINDS[k].get("faction", ""))
		if want == "":
			continue
		var at := Vector3.INF
		# A ring search out from the field: near enough to find on a sortie,
		# far enough to be somebody else's country. Widened after measuring —
		# a narrower ring left about a third of the foreign kit unplaced,
		# because a given nationality does not necessarily hold much ground
		# within thirty kilometres of this particular airfield.
		# Across the world, not across a theatre.
		#
		# The ring used to stop at 120 km because that was as far as the
		# authored square went, and a nationality that held no ground inside it
		# simply had no kit anywhere. There is no square now: the terrain, the
		# coastlines and the borders all run to the far side of the planet, so
		# the search does too. It walks outward -- near ground first, because
		# kit you can reach on a sortie is worth more than kit you cannot -- and
		# only goes long if the near country belongs to somebody else.
		for attempt in 1400:
			var a := randf() * TAU
			var reach: float = lerpf(20_000.0, 2_400_000.0,
				pow(float(attempt) / 1400.0, 2.0))
			var r: float = randf_range(8000.0, reach)
			var q := Vector3(cos(a) * r, 0.0, sin(a) * r)
			if Sim.region_faction(q.x, q.z) != want:
				continue
			# not in the sea, and not up a cliff
			var h := Sim.height_at(q.x, q.z)
			if h < Sim.sea_at(q.x, q.z) + 6.0:
				continue
			var n := Sim.normal_at(q.x, q.z)
			if n.dot(Vector3.UP) < 0.93:
				continue
			at = Vector3(q.x, h, q.z)
			break
		if at == Vector3.INF:
			_abroad_missed[want] = int(_abroad_missed.get(want, 0)) + 1
			continue
		# Hostile or not according to which side WE are on, not according to a
		# fixed idea of who the good guys are. Flying for Russia, an Abrams
		# standing in Kansas is the enemy; `Tank.team_of` alone would have
		# handed it to the player as a friend.
		var mine_bloc := String(JetSpec.FACTIONS.get(
			String(JetSpec.get_spec(Sim.selected_jet).get("faction", "usa")), {}
			).get("bloc", "nato"))
		var their_bloc := String(JetSpec.FACTIONS.get(want, {}).get("bloc", "nato"))
		var t := _spawn_tank(at, randf() * TAU,
			0 if their_bloc == mine_bloc else 1, k)
		t.ai = true
		placed += 1
	var miss := PackedStringArray()
	for f2 in _abroad_missed:
		miss.append("%s x%d" % [String(f2), int(_abroad_missed[f2])])
	print("[garage] flying %s (%s): %d of ours on the apron, %d foreign vehicle(s) in their own country%s"
		% [Sim.selected_jet,
			String(JetSpec.get_spec(Sim.selected_jet).get("faction", "?")),
			_apron_count, placed,
			"" if miss.is_empty() else
			"; no ground found for " + ", ".join(miss)])

var _apron_count := 0
## Which nationalities the search could not find ground for. A map generated
## from noise does not guarantee every country holds territory within reach of
## this particular airfield, and saying so is better than quietly dropping them.
var _abroad_missed: Dictionary = {}

func _spawn_tank(at: Vector3, yaw: float, team: int, kind := "m1a2") -> Tank:
	var t := Tank.new()
	t.setup(team, kind)
	t.name = "Tank"
	add_child(t)
	# A launcher is fourteen metres long, so the clearance is generous.
	var spot := _free_spot(at, 16.0, t)
	t.global_transform = Tank.ground_pose(spot, yaw, t.rest_height())
	t.dismount_requested.connect(_leave_tank)
	_reset_interp.call_deferred(t)
	return t

## `thrown` puts the man in the air with that velocity and a canopy over him,
## which is what an ejection is. Left at zero he is simply stood on the ground.
func _spawn_walker(at: Vector3, thrown := Vector3.ZERO) -> void:
	# A man put on his feet does not fire until the trigger has been let go.
	# The left button and K fire his rifle, and they are the cockpit's fire
	# and cannon too -- and the action menu's EJECT is clicked with the left
	# button -- so whatever was held as he left the aircraft went straight on
	# firing his rifle, for nothing, until it was released: phantom gunfire
	# after ejecting, after a crash, and from the LAUNCH click on the range.
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
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
	hud.aircraft = null
	veil.aircraft = null
	if audio:
		audio.aircraft = null

## Hand the aircraft to the orbit autopilot and move the player back to the
## gun sight. Leaving puts them back in the front seat.
func toggle_gunner() -> void:
	if not is_instance_valid(player) or not player.spec.get("gunship", false):
		return
	gunning = not gunning
	if gunning:
		_pre_gun_auto = player.auto
		player.auto = "orbit"
		if "orbit_alt" in player and player is PlayerHeli:
			# a helicopter's is height above the ground, and low
			player.orbit_alt = float(player.spec.get("orbit_agl", 250.0))
			player.orbit_speed = float(player.spec.get("orbit_speed", 30.0))
		elif "orbit_alt" in player:
			player.orbit_alt = maxf(player.global_position.y, 1200.0)
			# Slow, the way a gunship works. Kept at the entry speed -- usually
			# a hundred and forty-odd metres a second -- the circle round the
			# mark was so wide that, banked to fly it, the sight line ran along
			# the port wing and the battery, which points below it, could not
			# reach. At a hundred it orbits a mark three kilometres out at
			# twenty degrees of bank with the mark well under the wing, and
			# still has a third over its stall in the turn.
			player.orbit_speed = float(player.spec.get("orbit_speed", 100.0))
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
				and i < player.weapon_types.size() and not Sim.menu_keys:
			player.set_weapon(i)
			Sim.report(player.weapon_label(player.current_weapon()), Sim.Ev.INFO)
	# The page says "L laser" at the gun station as well, and L was only ever
	# read on the pilot's sensor page: once it was on here it stayed on.
	if Input.is_action_just_pressed(&"laser") and not Sim.ui_modal:
		pod.toggle_laser()
	if (Input.is_action_pressed(&"gun") or Input.is_action_pressed(&"fire")) \
			and not Sim.ui_modal:
		var aim: Vector3 = pod.aim_point()
		if aim != Vector3.INF:
			player.fire_gunship(self, aim)

## The sensor page doubles as a weapon station: pick a store, shoot at whatever
## the pod is holding. Helicopters and gunships live here.
func _sensor_input() -> void:
	# The rest of this reads the aeroplane's stores. A tank commander's sight
	# has none of that -- it lases, and the laid piece is fired from the normal
	# gunnery controls -- so take that path out before touching `player`.
	if not is_instance_valid(player) or (pod.platform != null and pod.platform != player):
		if Input.is_action_just_pressed(&"laser"):
			pod.toggle_laser()
		return
	for i in 8:
		if Input.is_action_just_pressed(StringName("weapon_%d" % (i + 1))) \
				and i < player.weapon_types.size() and not Sim.menu_keys:
			player.set_weapon(i)
			Sim.report(player.weapon_label(player.current_weapon()), Sim.Ev.INFO)
	if Input.is_action_just_pressed(&"laser"):
		pod.toggle_laser()
	# The gun is held, the stores are not. The whole block was entered on the
	# press of the fire button, so with the chin gun selected and the trigger
	# squeezed on the sensor page an Apache put out one shot and stopped until
	# the button was let go and pulled again.
	var gun_sel: bool = player.current_weapon() == "gun" \
		or player.is_gunship_weapon(player.current_weapon())
	if Input.is_action_just_pressed(&"fire") or Input.is_action_pressed(&"gun") \
			or (gun_sel and Input.is_action_pressed(&"fire")):
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
			# On the fire button as well as the gun key, and for as long as it
			# is down: see below. Reaching this branch on the press alone gave
			# a chin gun one shot per click.
			player.fire_gun(self)
		elif Input.is_action_just_pressed(&"fire"):
			var res: String = player.fire()
			if res != "":
				Sim.report(res, Sim.Ev.INFO)

## Air traffic: put an aeroplane in the circuit and let its own pilot fly it.
## Put a set of things into the world, in whatever mission is running, and do
## it idempotently: what is already there is counted first and only the
## shortfall is spawned. Asking twice tops the set up; it does not lay down a
## second one on top of the first.
func _populate(what: String) -> void:
	match what:
		"garage":
			var want := ["m1a2", "t90", "type99", "m109", "msta", "m270", "bm30",
				"humvee", "jackal", "vbl", "bradley", "shilka", "patriot"]
			var have := {}
			for v in get_tree().get_nodes_in_group("vehicles"):
				if is_instance_valid(v) and v is Tank:
					have[(v as Tank).kind] = true
			var n := 0
			var b: Vector3 = base.global_position if is_instance_valid(base) \
				else Vector3.ZERO
			for k in want:
				if have.has(k):
					continue
				_spawn_tank(Vector3(b.x + 196.0, 0.0, b.z - 424.0 - float(n) * 16.0),
					deg_to_rad(-90.0), 0, k)
				n += 1
			Sim.report("vehicle park: %d added, %d already there" % [n,
				want.size() - n], Sim.Ev.INFO)
		"parked":
			var rows := ["f22", "f35", "f16", "f15", "a10", "fa18", "mq9"]
			var here := {}
			for pjt in get_tree().get_nodes_in_group("parked"):
				if is_instance_valid(pjt) and "spec" in pjt:
					here[String(pjt.spec.get("name", ""))] = true
			var m := 0
			for i in rows.size():
				var sp := JetSpec.get_spec(rows[i])
				if here.has(String(sp.get("name", ""))):
					continue
				var j: Aircraft
				if JetSpec.is_rotary(rows[i]):
					j = PlayerHeli.new()
				else:
					j = PlayerJet.new()
				j.setup(rows[i])
				j.team = 0
				j.active = false
				j.name = "Parked %s" % rows[i]
				add_child(j)
				# Its own row, well west of the vehicle park. At x=150 running
				# from z=-520 this walked straight into the armour parked at
				# x=196 from z=-424 down, and left an aeroplane standing
				# between the launchers with no room to walk up to it.
				j.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-90.0)),
					Vector3(60.0,
						_apron_y(60.0, -170.0 - float(i) * 46.0)
							+ _stance(j.spec),
						-170.0 - float(i) * 46.0))
				j.gear_down = true
				j.gear_anim = 1.0
				j.set_canopy(true, true)
				j.add_to_group("boardable")
				j.add_to_group("hittable")
				j.add_to_group("parked")
				_reset_interp.call_deferred(j)
				m += 1
			Sim.report("flight line: %d added, %d already there" % [m,
				rows.size() - m], Sim.Ev.INFO)
		"choppers":
			var want_h := 2
			var up_h := 0
			for h0 in get_tree().get_nodes_in_group("bandits"):
				if is_instance_valid(h0) and h0 is AIHeli:
					up_h += 1
			var rotary := ["mi28", "z10"]
			var org_h: Vector3 = player.global_position if is_instance_valid(player) \
				else Vector3.ZERO
			var add_h := 0
			for i in maxi(want_h - up_h, 0):
				var h := AIHeli.new()
				h.setup(rotary[i % rotary.size()])
				h.team = 1
				h.name = "Gunship %d" % (i + 1)
				h.home = org_h + Vector3(-1200.0 + float(i) * 2400.0, 0.0, -5200.0)
				add_child(h)
				var hx: float = h.home.x
				var hz: float = h.home.z + 400.0
				h.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)),
					Vector3(hx, Sim.height_at(hx, hz) + 260.0, hz))
				_reset_interp.call_deferred(h)
				add_h += 1
			Sim.report("hostile helicopters: %d added, %d already up" % [add_h, up_h],
				Sim.Ev.INFO)
		"warships":
			var want_s := 3
			var up_s := 0
			for s0 in get_tree().get_nodes_in_group("ships"):
				if is_instance_valid(s0) and (s0 as Ship).team != 0:
					up_s += 1
			var hulls := ["corvette", "type052d", "moudge"]
			var add_s := 0
			for i in maxi(want_s - up_s, 0):
				var sv2 := Ship.new()
				sv2.setup(hulls[i % hulls.size()], 1)
				sv2.ai = true
				add_child(sv2)
				var sea2 := fleet_yard.deep_water(Vector3(30000.0 + float(i) * 2600.0, 0.0,
					-4000.0 + float(i) * 3000.0))
				sv2.global_position = Vector3(sea2.x, Sim.sea_surface(sea2.x, sea2.z), sea2.z)
				add_s += 1
			Sim.report("hostile shipping: %d added, %d already at sea" % [add_s, up_s],
				Sim.Ev.INFO)
		"bandits":
			var want_up := 4
			var up: int = Sim.census("bandits")
			var added := 0
			var pick := ["su57", "su35", "mig29", "j20"]
			var org: Vector3 = player.global_position if is_instance_valid(player) \
				else Vector3.ZERO
			for i in maxi(want_up - up, 0):
				var b2 := AIPlane.new()
				b2.setup(pick[i % pick.size()])
				b2.team = 1
				b2.role = "fighter"
				add_child(b2)
				var a4 := TAU * float(i) / float(want_up)
				b2.global_position = org + Vector3(cos(a4) * 12000.0, 1800.0,
					sin(a4) * 12000.0)
				b2.linear_velocity = -b2.global_transform.basis.z * 220.0
				_reset_interp.call_deferred(b2)
				added += 1
			Sim.report("hostile aircraft: %d added, %d already up" % [added, up],
				Sim.Ev.INFO)
		"sats":
			if Sim.census("satellites") > 0:
				Sim.report("satellites: %d already in orbit" %
					Sim.census("satellites"), Sim.Ev.INFO)
			else:
				country_bases.launch_constellation()

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
		"add_garage":
			_populate("garage")
		"add_parked":
			_populate("parked")
		"add_bandits":
			_populate("bandits")
		"add_choppers":
			_populate("choppers")
		"add_ships":
			_populate("warships")
		"add_sats":
			_populate("sats")
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
		craft.global_transform = Transform3D(Basis(), Vector3(0.0,
			_apron_y(0.0, 1340.0 - float(slot) * 90.0) + stance + 0.02,
			1340.0 - float(slot) * 90.0))
		craft.gear_down = true
		craft.gear_anim = 1.0
		craft.flaps = 1.0
		craft.flap_anim = 1.0
	else:
		# spaced down the approach so a flight arrives in trail
		var z: float = Airbase.AIM_Z + 12000.0 + float(slot) * 2600.0
		craft.global_transform = Transform3D(Basis(),
			Vector3(140.0, _apron_y(140.0, z) + 640.0 + slot * 60.0, z))
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

## Image intensification. A screen effect rather than a camera mode, so it works
## from every seat and every view — cockpit, chase, mast head, driver, on foot —
## which a per-vehicle version would not.
var _nvg: ColorRect = null
var _nvg_mat: ShaderMaterial = null
var nvg_on := false
var _nvg_t := 0.0

## The sonar overlay. Green, noisy, swept, and it works from every seat rather
## than only through the sensor page -- the boat is conned from the third
## person view, so that is where it has to be usable.
var _sonar: ColorRect = null
var _sonar_mat: ShaderMaterial = null

## Unaided, image intensifier, sonar. One key rather than three: they are the
## same decision -- what you are looking through -- and there is no key left.
const VIEW_PLAIN := 0

## Kept here for the scripts that reach it by name: see `VisionFx.nuke_flash`.
func nuke_flash(at: Vector3, lethal: float) -> void:
	vision_fx.nuke_flash(at, lethal)

## The other side's airfield. Everything in the world used to stage off the one
## strip at the origin, which made the opposing faction an air force with no
## aerodrome — their aircraft had to be conjured into the air because there was
## nowhere for them to be parked.
##
## Sited by walking out along a bearing until there is a stretch of dry ground
## far enough away to be a different theatre, then levelled to its own height
## the same way the home field is.
## Every country's aerodrome. There is no main airfield and no home base:
## each side has one, all six are built the same way, and the chart is centred
## on whichever one this sortie took off from.
var bases: Array = []
func _do_action(id: String) -> void:
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
			for n in get_tree().get_nodes_in_group("satellites"):
				if is_instance_valid(n) and (not ("team" in n) or int(n.team) != 0):
					sats.append(n)
			if sats.is_empty():
				Sim.report("nothing hostile in orbit", Sim.Ev.BAD)
			else:
				var at := sats.find(Sim.sat_target)
				Sim.sat_target = sats[(at + 1) % sats.size()] if at >= 0 else sats[0]
				if is_instance_valid(map):
					map.sat_target = Sim.sat_target
				Sim.report("ASAT target: %s" % Sim.label_of(Sim.sat_target),
					Sim.Ev.INFO)
		"satlink":
			# Ask the satellite what it can see, and put the answer somewhere
			# useful: the objective marker goes on the weight of it, so the
			# survey is something you can then fly to.
			var sv := Sim.satellite_survey(
				int(player.team) if is_instance_valid(player) else 0)
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
			if is_instance_valid(ship) or is_instance_valid(tank) or _at_conn():
				var mount: Node3D = tank
				if is_instance_valid(ship):
					mount = ship
				elif _at_conn():
					mount = carrier
				pod.platform = mount
				pod.toggle()
				pod.set_fullscreen(pod.active)
			return
		"allstop":
			if is_instance_valid(ship):
				ship.telegraph = 0.0
			elif _at_conn():
				carrier.telegraph = 0.0
			return
		"amidships":
			if is_instance_valid(ship):
				ship.helm = 0.0
			elif _at_conn():
				carrier.helm = 0.0
			return
		"dismount":
			if is_instance_valid(ship):
				_leave_ship()
				return
			if is_instance_valid(tank):
				_leave_tank()
				return
			if _at_conn():
				actions.close()
				_leave_carrier()
				return
			# otherwise it is the aeroplane's "climb out", below -- which
			# returning here unconditionally made a menu item that did nothing
		"weapon":
			if is_instance_valid(tank):
				tank.cycle_weapon()
			return
		"gunner":
			if is_instance_valid(tank):
				tank.gunner = not tank.gunner
				return
			# the gunship's station, below: the same id, and it never got there
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
		"rwy":
			Airbase.cycle_pick(get_tree(), player.global_position)
			player.say("landing aid: " + Airbase.pick_label(get_tree(), player.global_position))
		"canopy":
			player.set_canopy(not player.canopy_open)
		"ramp":
			player.toggle_ramp()
			player.say("cargo ramp " + ("opening" if player.ramp_open else "closing"))
		"fbw":
			player.assist = not player.assist
			Sim.assist = player.assist
		"hover":
			if player is PlayerHeli:
				(player as PlayerHeli).toggle_hover_hold()
		"aphold":
			player.set_autopilot("hold")
		"aploiter":
			player.set_autopilot("loiter")
		"apgoto":
			player.set_autopilot("goto")
		"apturn":
			player.toggle_orbit_direction()
		"jammer":
			player.toggle_jammer()
		"nav":
			player.toggle_nav_lights()
		"lamp":
			player.toggle_lights()
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
	pod.platform = sh
	hud.ship = sh
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse lays the battery, left click fires, U to hand over", Sim.Ev.INFO)

func _leave_ship() -> void:
	if not is_instance_valid(ship):
		return
	ship.mount(false)
	if net != null and net.active:
		net.take_ship_conn(ship.fleet_idx, false)
	pod.platform = null
	if pod.active:
		pod.toggle()
		pod.set_fullscreen(false)
	var at: Vector3 = ship.global_position
	hud.ship = null
	map.ship = null
	ship = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# ...and nothing else after it. `_spawn_walker` makes the man's own camera
	# current, and forcing the chase camera live again immediately afterwards
	# handed the view back to whatever it was still following — the aeroplane
	# parked on the apron. Handing over the conn put you in a jet you were not
	# in and could not fly. Leaving a tank has never done this because it does
	# not touch the camera at all.
	_spawn_walker(at + Vector3(0, 12.0, 0))

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
	# The sensor is hers while she is crewed. Left alone it stayed hung off the
	# aeroplane parked on the ramp, and the page that opened from the bridge
	# was that jet's -- its gun, its stores, its weapon select.
	pod.platform = carrier
	Sim.report("you have the conn — W/S engine order, A/D helm", Sim.Ev.INFO)
	Sim.report("mouse looks out from the island, RMB sensor page, U to hand over",
		Sim.Ev.INFO)

## At the carrier's conn. She has no gun and no seat to climb out of, and the
## aeroplane left parked on the ramp is not what is being commanded -- but the
## aeroplane's keys went on reaching it from here: the sensor page opened on a
## jet two hundred kilometres away with its gun and stores, J put you in a
## gunship's gunner station, TAB listed its stores and U climbed out of it.
func _at_conn() -> bool:
	return is_instance_valid(carrier) and carrier.occupied

func _leave_carrier() -> void:
	if not is_instance_valid(carrier):
		return
	carrier.mount(false)
	hud.carrier = null
	if pod.active:
		pod.toggle()
		pod.set_fullscreen(false)
	pod.platform = null
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
	# knocked out with him in it, outside a street fight (which has its own
	# way back): the choice of what to go back in as
	if not is_instance_valid(cqb) and not t.died.is_connected(_on_crew_down):
		t.died.connect(_on_crew_down)
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
	# A light 4x4 has no main gun and no coaxial: it has the thing on the roof.
	if t.vclass() == "lav":
		Sim.report("SPACE roof gun, C sight, U to get out", Sim.Ev.INFO)
	else:
		Sim.report("SPACE main gun, V coax, C gunner sight, U to get out", Sim.Ev.INFO)

func _leave_tank() -> void:
	if not is_instance_valid(tank):
		return
	var out: Vector3 = tank.global_transform * Vector3(-3.4, 0.5, 0.0)
	tank.mount(false)
	tank.in_throttle = 0.0
	tank.in_steer = 0.0
	tank.in_brake = true
	tank.sight_active = false
	if pod and pod.platform == tank:
		if pod.active:
			pod.toggle()
		pod.set_fullscreen(false)
		pod.platform = null
		if cam:
			cam.pod_slew = false
	hud.tank = null
	map.tank = null
	tank = null
	_spawn_walker(out)

func _on_walker_died(where: Vector3) -> void:
	var fight := cqb
	if is_instance_valid(fight):
		var by: Node = walker.last_attacker if is_instance_valid(walker) else null
		# In a session the round that did it was fired on the host, and only
		# its name came over with the damage.
		var net_by: String = String(walker.get_meta("net_by", "")) \
			if is_instance_valid(walker) else ""
		var by_name := "your own grenade"
		if is_instance_valid(by) and by is Soldier:
			by_name = String(by.get("callsign"))
		elif net_by != "":
			by_name = net_by
		Sim.report("you were dropped by %s" % by_name, Sim.Ev.BAD)
		var cause := String(walker.last_cause) if is_instance_valid(walker) else "explosion"
		fight.feed_player(by if by != walker else null, cause)
		fight.player_down()
		if net != null and net.active:
			net.report_down(net.name_of(net.my_id),
				by_name if by_name != "your own grenade" else "", cause,
				bool(walker._last_head) if is_instance_valid(walker) else false)
	else:
		Sim.report("pilot down", Sim.Ev.BAD)
		# outside a street fight: choose what to go back in as
		_offer_redeploy()
		return
	await get_tree().create_timer(3.5).timeout
	if not on_foot or not is_inside_tree():
		return
	if is_instance_valid(walker):
		walker.queue_free()
	# Back in with the rest of the side, not six paces from where it happened:
	# in a street fight that is six paces from whoever did it.
	if is_instance_valid(fight) and fight == cqb:
		_spawn_walker(fight.spawn_point(0, 0))
		walker.yaw = 0.0
		fight.set_player(walker)
		street_fight.cqb_deploy(false)
		return
	if is_instance_valid(cqb) or is_instance_valid(fight):
		return
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
	hud.aircraft = player
	veil.aircraft = player
	pod.platform = player
	map.aircraft = player
	if "pod" in player:
		player.pod = pod
	if audio:
		audio.aircraft = player
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
	hud.aircraft = null
	veil.aircraft = null
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
	if jet.is_in_group("remote"):
		return                     # another player's: its hold, never its seat
	on_foot = false
	if is_instance_valid(walker):
		walker.queue_free()
	walker = null
	hud.walker = null
	player = jet as Aircraft
	player.active = true
	player.remove_from_group("boardable")
	# into another aeroplane on the line: that is what the others now see
	if net != null and net.active:
		net.set_jet(net._kind_of(player))
	for j in parked:
		if is_instance_valid(j) and j != player:
			j.set_canopy(false)
	cam.subject = player
	cam.current = true
	hud.aircraft = player
	veil.aircraft = player
	hud.cam = cam
	pod.platform = player
	map.aircraft = player
	if "pod" in player:
		player.pod = pod
	for ab in bases:
		if is_instance_valid(ab):
			(ab as Airbase).watcher = player
	if is_instance_valid(base):
		base.watcher = player
	if audio:
		audio.aircraft = player
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
	# U is getting out and getting in. The press that got him out was still
	# latched as "interact", and the man stood beside the aircraft read it on
	# his first step and climbed straight back in: the boarding sequence again,
	# every time.
	Sim.block_until_released([&"interact"])
	_spawn_walker(out)

func _host_game(jet_id: String, _address: String) -> void:
	Sim.selected_jet = jet_id
	if net.host(jet_id):
		# Into a lobby, not into a match. HOST started whatever mode happened
		# to be selected the moment it was pressed; now the host stays in the
		# hangar, people join it there, and LAUNCH starts the match for all of
		# them. Hosting from a match already running keeps it running.
		net.announce_lobby(String(menu.mission_id))
		if running:
			net.running_mission = String(Sim.mission)
		else:
			Sim.report("hosting — choose a mode and press LAUNCH when everyone is in", Sim.Ev.GOOD)

## The host started a match: this client starts the same one, in whatever it
## picked in the hangar -- its own aeroplane, a vehicle or on foot.
func _start_from_host(mission: String) -> void:
	var id := String(menu.jet_id) if is_instance_valid(menu) else ""
	if id == "":
		id = String(Sim.selected_jet)
	_start(id, mission)
	# He has not chosen anything: the host chose the mode and the match began
	# with whatever happened to be highlighted in his hangar -- a fighter, for
	# anyone who had not touched it. The hangar comes up to choose in, the
	# aeroplane held where it is until he has, then replaced by his choice.
	# (A street fight asks on its own deploy screen.)
	if mission not in ["cqb", "ground", "arms", "range"]:
		_choose_in_match("DEPLOY")

## The hangar over a running match, to choose what to be in: on arriving in a
## match the host started, and for a joiner who asks to change mid-match. What
## he is in now is held still and goes when the choice is made.
func _choose_in_match(label: String) -> void:
	_redeploy_replace = true
	if is_instance_valid(player) and not on_foot and not is_instance_valid(tank):
		player.set_meta("choosing", true)
		player.freeze = true
	menu.set_redeploy(true, label)
	menu.visible = true
	Sim.menu_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Let go of an aeroplane held while choosing, if the choice was not made.
func _unhold_choice() -> void:
	if is_instance_valid(player) and player.has_meta("choosing"):
		player.remove_meta("choosing")
		player.freeze = false
	_redeploy_replace = false
	if menu.redeploy:
		menu.set_redeploy(false)

func _join_game(jet_id: String, address: String) -> void:
	Sim.selected_jet = jet_id
	if net.join(address, jet_id):
		# Waits in the hangar for the host's match: it is started as soon as
		# the host says what it is running (`NetLink.net_match`). A placeholder
		# free flight was started here, which put the joiner in the air over
		# nothing until the host got round to launching.
		Sim.report("joined — waiting in the hangar for the host to launch", Sim.Ev.INFO)

## Everything put straight into the world while a match is running: rounds in
## flight, shells, bombs, warheads and their mushroom clouds, wrecks, debris,
## smoke, the men of a street fight and whatever they called in. Each kind used
## to be tidied up by its own line in `_clear_mission`, and every kind that
## nobody had written a line for -- a nuke still climbing, a burst of tracer, a
## gunship called in over the town -- carried on into the next match. Recording
## them as they arrive means a new kind is swept up without anyone having to
## remember to.
var _match_spawn: Array = []

func _note_match_child(n: Node) -> void:
	if running and n.get_parent() == self:
		_match_spawn.append(n)

## Not the match's to sweep: other players and what the network layer built for
## them, the fleet and the carrier (furniture, refitted instead), and the
## camera, which is made once on the first launch and kept.
func _sweep_keeps(n: Node) -> bool:
	if n == cam or n == menu_cam or n == cine_cam:
		return true
	# a town's dressing is built once and kept for every visit: see
	# `StreetFight.town_set`
	if n is TownSet:
		return true
	# A strike wave's shipping is the match's; the standing fleet is not.
	if n.is_in_group(&"ships") and not n.has_meta("strike"):
		return true
	for g in [&"remote", &"carrier", &"persistent"]:
		if n.is_in_group(g):
			return true
	if net != null and n == net:
		return true
	if net != null and (net.ghosts.values().has(n) or net.foot_ghosts.values().has(n)):
		return true
	return false

func _sweep_match() -> void:
	var swept := {}
	for n in _match_spawn:
		if not is_instance_valid(n) or n.is_queued_for_deletion() or _sweep_keeps(n):
			continue
		var k: String = n.get_class()
		if n.get_script() != null:
			k = n.get_script().get_global_name()
			if k == "":
				var props: Array = []
				for pr in n.get_script().get_script_property_list():
					if props.size() < 2 and not String(pr["name"]).contains(" "):
						props.append(String(pr["name"]))
				k = "(%s)" % ",".join(props)
		swept[k] = int(swept.get(k, 0)) + 1
		n.queue_free()
	_match_spawn.clear()
	# Anything parented somewhere else that still belongs to the match.
	for n in get_tree().get_nodes_in_group(&"transient"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
	if sweep_log and not swept.is_empty():
		print("[sweep] %s" % str(swept))

## Print what each restart sweeps up: --sweeplog.
var sweep_log := false

func _clear_mission() -> void:
	# The rocket and its pad go with the mission, and time goes back to normal.
	if is_instance_valid(rocket):
		rocket.mount(false)
		rocket.queue_free()
	rocket = null
	if is_instance_valid(hud):
		hud.rocket = null
	if is_instance_valid(_pad):
		_pad.queue_free()
	_pad = null
	Sim.space_warp = 1.0
	Sim.space_rate = 1.0
	Sim.view_scale = 1.0
	Sim.view_moon = Vector3.INF
	# and nothing called down in the last match is still marked on the map
	if is_instance_valid(map):
		map.pick_marks.clear()
	# the next mission decides for itself whether the range is a safe one
	Sim.no_air_threat = false
	if is_instance_valid(firing_range):
		firing_range.queue_free()
	firing_range = null
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
		pod.platform = null
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
	hud.aircraft = null
	if is_instance_valid(veil):
		veil.aircraft = null
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
	if is_instance_valid(cqb):
		cqb.queue_free()
	cqb = null
	if is_instance_valid(deploy_ui):
		deploy_ui.queue_free()
	deploy_ui = null
	_cqb_gunship = null
	_cqb_parked = null
	_cqb_parked_at.clear()
	_cqb_tel = null
	_cqb_tel_t = 0.0
	_cqb_gun_t = 0.0
	for z in get_tree().get_nodes_in_group("zones"):
		if is_instance_valid(z):
			z.queue_free()
	if boarding:
		_end_boarding()
	_sweep_match()
	# What the last match left set rather than standing: a jammer or an EMP
	# still counting down, the range's slow motion, and a nuclear flash still
	# whiting the screen out as the next match opened.
	for tm in CqbMatch.jammed:
		CqbMatch.jammed[tm] = 0.0
	for tm in CqbMatch.emp_t:
		CqbMatch.emp_t[tm] = 0.0
	Engine.time_scale = 1.0
	vision_fx.clear_flash()
	if net != null and net.active:
		net.match_reset()

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

func hand_weapon_cam(from: Node3D, to: Node3D) -> void:
	if not is_instance_valid(cam) or not is_instance_valid(to):
		return
	if cam.weapon_cam == from:
		cam.weapon_cam = to

func _on_store_released(m: Node) -> void:
	# Ride it out if the weapon cam is armed. It lets go on its own when the
	# round goes off, because the node stops being valid.
	if weapon_cam_on and is_instance_valid(cam) and m is Node3D:
		_ride(m as Node3D)
	# a ship's round is not reported over the wire here: the hull's own fire
	# path already tells the other end
	if net and net.active and is_instance_valid(m) and is_instance_valid(player) \
			and m.shooter == player:
		# as a picture with what it is after, not as a second live round on
		# every other machine that hit things there as well
		net.share_launch(player, m)

## Every round fired anywhere, offered to the weapon camera by `Effects.watch`.
## It takes the player's own -- from his gun on foot, his rocket or his
## missile, the aeroplane's cannon, the vehicle's guns -- one at a time. A gun
## puts rounds out far faster than a camera can follow them, so the one being
## ridden is ridden to the end and its impact watched, and the next one fired
## after that is the next one ridden.
func _offer_round(shot: Node3D, shooter: Node) -> void:
	if not weapon_cam_on or not running or not is_instance_valid(cam) \
			or not is_instance_valid(shot) or shooter == null:
		return
	var mine: bool = (on_foot and shooter == walker) \
		or (not on_foot and shooter == player) \
		or (is_instance_valid(tank) and shooter == tank) \
		or (is_instance_valid(ship) and shooter == ship)
	if not mine or cam.riding():
		return
	_ride(shot)

## Put the chase camera on a round, taking the screen from whatever camera has
## it -- the vehicle's, the hull's, or his own eyes -- for as long as the ride
## lasts.
func _ride(m: Node3D) -> void:
	if not is_instance_valid(cam) or not is_instance_valid(m):
		return
	cam.weapon_cam = m
	# A crewed hull runs its own camera and drives it every physics frame,
	# so setting the ride here did nothing at all: the boat simply put the
	# view back on her own masthead. Hand the screen to the chase camera
	# for the flight, and take it back when the round is gone.
	# A crewed hull or vehicle runs its own camera and re-points it every
	# physics frame, so setting the ride did nothing: the view simply went
	# back to the vehicle. Hand the screen over for the flight.
	if is_instance_valid(ship) and is_instance_valid(ship.cam):
		_cam_was_ship = true
		# From where the view is, not from wherever the chase camera was
		# last left: it eases across from its own pose, and one that has
		# not had the screen since the hull was boarded is nowhere near.
		if not cam.current:
			cam.global_transform = ship.cam.global_transform
		cam.current = true
	elif is_instance_valid(tank) and is_instance_valid(tank.cam):
		_cam_was_tank = true
		if not cam.current:
			cam.global_transform = tank.cam.global_transform
		cam.current = true
	elif on_foot and is_instance_valid(walker) and is_instance_valid(walker.cam):
		_cam_was_walker = true
		if not cam.current:
			cam.global_transform = walker.cam.global_transform
		cam.current = true

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

func _resume() -> void:
	Sim.menu_open = false
	_unhold_choice()
	menu.visible = false
	if is_instance_valid(pause_menu):
		pause_menu.close()
	_show_roster(false)
	get_tree().paused = false
	# RESUME on the hangar left the cockpit sound paused: only ESC undid it.
	if audio:
		audio.set_paused(false)
	# the click on RESUME is still down, and SPACE on a focused button is fire
	Sim.block_until_released([&"foot_fire", &"fire", &"gun"])
	var crewed: bool = is_instance_valid(tank) or is_instance_valid(ship) or _at_conn()
	if on_foot and is_instance_valid(walker):
		# his own eyes, not the camera on the aeroplane parked back at the field
		walker.activate()
	elif is_instance_valid(player) and not crewed:
		cam.current = true
	# Whatever had the mouse before the pause gets it back. Only the walker and
	# the mouse stick did: a tank, a ship or the sensor page came back with the
	# pointer free, and the gun would not lay until something captured it again.
	var grab: bool = (on_foot and is_instance_valid(walker) and not walker.dead) \
		or crewed or gunning or (is_instance_valid(pod) and pod.active) \
		or (is_instance_valid(player) and not on_foot and "mouse_fly" in player and player.mouse_fly)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if grab else Input.MOUSE_MODE_VISIBLE
	_deploy_yield(false)

func _pause() -> void:
	var can_restart: bool = menu.net_role != "client"
	pause_menu.open(_pause_context(), can_restart)
	# The session list comes up with the pause menu rather than instead of it.
	# Put on its own key it simply took escape over, and there was then no way
	# to reach the menu at all.
	_show_roster(true)
	# In a session the match goes on: one player cannot stop everybody else's
	# game, and freezing his own copy of it while theirs ran put the two out of
	# step. His controls are let go of instead (`Sim.menu_open`).
	var online: bool = net != null and net.active
	Sim.menu_open = true
	if not online:
		get_tree().paused = true
		if audio:
			audio.set_paused(true)
	else:
		Sim.report("menu open — the match goes on around you", Sim.Ev.INFO)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_deploy_yield(true)

## ESC, one step at a time: out of the settings page, out of the hangar back to
## the pause page, and out of the pause page back into the match.
func _on_escape() -> void:
	if pause_menu.visible:
		if not pause_menu.back() and running:
			_resume()
		return
	if not running:
		return
	if menu.visible:
		# the hangar was opened from the pause page: back to it
		menu.visible = false
		pause_menu.open(_pause_context(), menu.net_role != "client")
		_show_roster(true)
		return
	_pause()

## CHANGE MODE: the hangar, over the paused match. Its RESUME goes back to the
## match and its LAUNCH ends it for whatever is picked there.
func _pause_to_hangar() -> void:
	pause_menu.close()
	_show_roster(false)
	menu.set_paused(true)
	menu.visible = true
	# A joiner cannot change the mode, but he can change what he is in.
	if net != null and net.active and not net.is_host and running \
			and not is_instance_valid(cqb):
		_choose_in_match("CHANGE")

## The same mode and the same vehicle, from the top.
func _restart_match() -> void:
	pause_menu.close()
	_show_roster(false)
	if audio:
		audio.set_paused(false)
	var a: Array = menu.launch_args()
	_start(String(a[0]), String(a[1]))

func _show_roster(on: bool) -> void:
	if is_instance_valid(roster_view):
		roster_view.visible = on and net != null and net.active
		roster_view.set_process(roster_view.visible)

## The line under PAUSED: what is being played, and with whom.
func _pause_context() -> String:
	var mode_name := String(Sim.mission)
	for m in Menu.MISSIONS:
		if String(m[0]) == String(menu.mission_id):
			mode_name = String(m[1])
	var what := ""
	if on_foot:
		what = "on foot"
	elif is_instance_valid(tank):
		what = tank.display_name()
	elif is_instance_valid(ship):
		what = ship.display_name()
	elif is_instance_valid(player):
		what = String(player.spec.get("name", ""))
	var line := mode_name if what == "" else "%s  ·  %s" % [mode_name, what]
	if net != null and net.active:
		line += "\n" + net.status_line()
	return line

## The deploy screen and the pause menu cannot both be up: the deploy screen
## sat over the top of the menu and took every click meant for it, so with it
## open there was no getting at the menu at all. The pause menu wins. The
## deploy screen steps aside while it is up and comes back when it goes.
var _deploy_held := false

func _deploy_yield(to_menu: bool) -> void:
	if not is_instance_valid(deploy_ui):
		_deploy_held = false
		return
	if to_menu:
		if deploy_ui.visible:
			_deploy_held = true
			deploy_ui.visible = false
	elif _deploy_held:
		_deploy_held = false
		deploy_ui.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	# Letting go of the right button lets the view back out.
	if e is InputEventMouseButton and not (e as InputEventMouseButton).pressed \
			and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_hull_zoom = false
		if is_instance_valid(cam):
			cam.zoom = false
	# ALT + right click raises the targeting pod; the wheel zooms it.
	if e is InputEventMouseButton and _in_rocket():
		return
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and running \
			and not on_foot and not Sim.ui_modal:
		var mb := e as InputEventMouseButton
		# Not while driving: right click is the gun there, and META counts as
		# freelook on a Mac, so firing a howitzer threw the player into the
		# sensor camera. This guard belongs on the pod alone -- putting it at
		# the top of the handler took the map, the radar ranges, the side
		# panels and the action menu with it.
		# ...and not on foot, where the right button is the sights.
		# Plain right click zooms the view while it is held; the sensor page is
		# on O, or ALT with the right button.
		if mb.button_index == MOUSE_BUTTON_RIGHT and not is_instance_valid(tank) \
				and not on_foot and not Input.is_action_pressed(&"freelook") \
				and not pod.active:
			if is_instance_valid(ship) or _at_conn():
				# a bridge's own camera, eased in by `_ease_hull_zoom`
				_hull_zoom = true
				return
			if is_instance_valid(cam) and cam.current:
				cam.zoom = true
				return
		if mb.button_index == MOUSE_BUTTON_RIGHT and gunning:
			# At a gun station the sight is the seat. Right click stowed it,
			# which left the gunner looking out of whatever camera was behind
			# it -- from a gunship called in over a street fight, his own eyes
			# back on the ground.
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT and not is_instance_valid(tank) \
				and not on_foot:
			if _at_conn():
				# her own masthead, not the jet parked back on the ramp
				pod.platform = carrier
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
	# At a gun station the mouse has nothing else to do -- the aircraft is flying
	# itself -- and the station says "mouse slews". It needed ALT held as well,
	# so the sight sat wherever the station had laid it and felt locked there.
	if pod.active and e is InputEventMouseMotion \
			and (Input.is_action_pressed(&"freelook") or gunning):
		pod.slew(Sim.mouse_rel(e as InputEventMouseMotion))
		return
	if boarding and ((e is InputEventKey and e.pressed and not e.echo) \
			or (e is InputEventMouseButton and e.pressed)):
		_end_boarding()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var k := (e as InputEventKey).physical_keycode
		# In the capsule the keyboard is the rocket's. The aeroplane left on the
		# ramp must not hear any of it: P would cycle its camera away from the
		# rocket, U would climb out of it, TAB would open its stores.
		if _in_rocket() and not k in [KEY_ESCAPE, KEY_M, KEY_F1, KEY_F2, KEY_F3,
				KEY_PERIOD, KEY_COMMA, KEY_SLASH, KEY_APOSTROPHE]:
			return
		if (k == KEY_PERIOD or k == KEY_COMMA) and running and not Sim.typing:
			# Time warp, for whatever of yours is coasting above the air.
			Sim.warp_step(1 if k == KEY_PERIOD else -1)
			Sim.report("time warp x%d — applies above the air, in free fall" % int(Sim.space_warp),
				Sim.Ev.INFO)
		elif k == KEY_EQUAL and running:
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
		elif k == KEY_H and running and is_instance_valid(player) and not _at_conn() \
				and bool(player.spec.get("stovl", false)):
			player.hover_cmd = not player.hover_cmd
			Sim.report("STOVL: %s" % ("converting to jetborne" if player.hover_cmd
				else "converting to wingborne"), Sim.Ev.INFO)
		elif k == KEY_M and running:
			map.toggle()
		elif k == KEY_O and running:
			# The sensor page, which is what every key card says O is. This
			# opened the map -- M already does -- and being first in the chain
			# it took the key from both sensor branches below it, so O never
			# raised the sensor anywhere: not in a cockpit, not on a bridge,
			# not in a turret.
			if gunning:
				# At the guns the sensor *is* the station. O stowed it, which
				# dropped a man called up to a gunship back to the camera in
				# the street with the guns still his; J is the way out.
				pass
			elif on_foot:
				# nothing to look through on foot; the map is what it did
				map.toggle_globe()
			elif is_instance_valid(ship) or is_instance_valid(tank) or _at_conn():
				# whatever is crewed owns the sensor: the action menu's path,
				# which hangs the head off the hull
				_do_action("sensor")
			elif is_instance_valid(player):
				pod.platform = player
				pod.toggle()
				pod.set_fullscreen(pod.active)
				if cam:
					cam.pod_slew = pod.active
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if pod.active \
					else Input.MOUSE_MODE_VISIBLE
				Sim.report("sensor page %s" % ("up" if pod.active else "stowed"),
					Sim.Ev.INFO)
		elif k == KEY_TAB and running:
			if actions.visible:
				actions.close()
			elif on_foot:
				# On foot there is no aeroplane and no vehicle, but there is
				# still the orbital picture to command. TAB used to do nothing
				# at all out here.
				actions.open_for_foot()
			elif is_instance_valid(ship):
				actions.open_for_vehicle(ship)
			elif is_instance_valid(tank):
				actions.open_for_vehicle(tank)
			elif _at_conn():
				actions.open_for_vehicle(carrier)
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
		elif k == KEY_L and running and not pod.active and not _at_conn() \
				and is_instance_valid(player) and player.has_method("toggle_lights"):
			player.toggle_lights()
		elif (k == KEY_I or k == KEY_N) and pod.active:
			# N as well as I. N is the night vision key everywhere else, so
			# reaching for it on the sensor page is the obvious thing to do --
			# and with the goggles suppressed while the page is up it now has
			# somewhere sensible to go.
			pod.cycle_channel()
			Sim.report("sensor: %s" % SensorPod.CHANNEL_NAMES[pod.channel], Sim.Ev.INFO)
		elif k == KEY_T and pod.active and (Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)):
			# again on what is held lets it go; see `SensorPod.toggle_track`
			pod.toggle_track()
		elif k == KEY_F3 and running:
			if admin.visible:
				admin.close()
			else:
				admin.open()
		elif k == KEY_F2:
			hud.show_help = not hud.show_help
		elif k == KEY_ESCAPE and (running or pause_menu.visible):
			_on_escape()
		elif k == KEY_P and running and not on_foot and not _at_conn():
			cam.cycle()
		elif k == KEY_J and running and is_instance_valid(_station_walker):
			_leave_hold_station()
		elif k == KEY_J and running and not on_foot and not _at_conn() \
				and is_instance_valid(player) and player.spec.get("gunship", false):
			toggle_gunner()
		elif k == KEY_U and running and not on_foot and not boarding \
				and not _at_conn():
			# The carrier takes U herself, from the conn. Let through here as
			# well it reached the aeroplane parked back on the ramp and climbed
			# out of that, two hundred kilometres from the bridge.
			if is_instance_valid(ship):
				_leave_ship()
			else:
				_try_dismount()
		# R used to restart the mission outright. That is far too easy to hit by
		# accident mid-sortie; restarting belongs behind the pause menu.

# -------------------------------------------------------------- command line
func _parse_cmdline() -> void:
	var preset := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--weather="):
			set_weather(a.substr(10))
		elif a.begins_with("--jet="):
			menu._select(a.substr(6))
			_jet_arg = a.substr(6)
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
			_net_host = true
		elif a.begins_with("--join="):
			_net_join = a.substr(7)
		elif a == "--noassist":
			Sim.assist = false
		elif a.begins_with("--mission="):
			# through the menu's own door, so what it lists follows the mode
			menu._select_mission(a.substr(10))
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
		elif a == "--debugweapons":
			Sim.debug_weapons = true
		elif a.begins_with("--orbit="):
			var pv := a.substr(8).split(",")
			if pv.size() == 2:
				_orbit = Vector2(float(pv[0]), float(pv[1]))
		else:
			# Anything else is for the test harness, built on first use.
			if harness == null:
				harness = TestHarness.new(self)
			harness.parse_arg(a)
	if _net_host:
		_host_game(menu.jet_id, "")
		# from the command line there is nobody to press LAUNCH
		_start(menu.jet_id, String(menu.mission_id))
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
			# The hangar as it opens, or as it looks some way into the flypast.
			if _shot_at > 0:
				_shot_frames = _shot_at
		"hangar":
			menu.visible = false
			_set_preview(menu.jet_id)
			menu_cam.current = true
			preview.visible = true
			spin = false
			preview.rotation.y = deg_to_rad(215.0)
			_stand_rig()
			menu_cam.position = Vector3(13, _rig_y + 3.5, -15)
			menu_cam.look_at(Vector3(0, _rig_y + 0.4, 0), Vector3.UP)
			_shot_frames = 20
		_:
			var parts := preset.split(":")
			_start(menu.jet_id if parts.size() < 2 else parts[1], parts[0])
			if _at != Vector3.ZERO and is_instance_valid(player):
				player.global_position = _at
				player.linear_velocity = -player.global_transform.basis.z * 170.0
				_reset_interp.call_deferred(player)
			_shot_frames = _shot_at if _shot_at > 0 else 140


class Shell extends Node:
	var world: Node = null

	func _input(e: InputEvent) -> void:
		if world:
			world._shell_input(e)

## The crewed launch vehicle, if there is one on the pad or in the sky.
var rocket: LaunchVehicle = null
