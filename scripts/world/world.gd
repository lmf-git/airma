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
var missions := MissionSetup.new(self)
var admin_desk := AdminDesk.new(self)
var controls := WorldControls.new(self)
var cmdline := CommandLine.new(self)
var crew := Crew.new(self)
var session := MatchSession.new(self)
var sweep := MatchSweep.new(self)

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
var shot_frames := 0
var _stop_t := 0.0
var _auto := ""
var _dump := 0
var _view := ""
var _nocockpit := false
var _openbay := false
var _dist := 0.0
var _auto_diag := false
var _slot_home := Vector3.INF
var _slot_said := -1
var _mission_started := 0
## --jet= as given, for the tests that should fly what was asked for.
var jet_arg := ""
var arty_test := ""
var _dash_alt := 1000.0
var _bank_deg := 0.0
var net_host := false
var net_join := ""
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
var mode: GameMode
var veil: GVeil
var net: NetLink
var walker: Walker
## The planet from orbit, on F4: see `SatView`.
var sat_view: SatView
var _air_cleared := false
var parked: Array = []
var tank: Tank = null
var on_foot := false
var gunning := false
var skip_board := false
var shot_at := 0
var start_at := Vector3.ZERO
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
	elif crew.at_conn():
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
	child_entered_tree.connect(sweep.note_child)
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
	# before `CommandLine.parse`, which does not run until the world is already
	# made. Read the flags that have to be honoured now.
	for a in OS.get_cmdline_user_args():
		if a == "--flat":
			# The old 1200 km height field, for the measurements written against
			# it. Read here because the field, the terrain and the sea all ask
			# which world this is as they come up, and by `CommandLine.parse` they
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
			# instruments the survey, and `CommandLine.parse` does not run until
			# the world is already built.
			Sim.roads.debug_roads = true
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
			"searching %d routes over the hills" % Sim.roads.routes_left())
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
	admin.chose.connect(admin_desk.do_admin)
	ui.add_child(admin)
	actions = ActionMenu.new()
	actions.set_anchors_preset(Control.PRESET_FULL_RECT)
	actions.chose.connect(controls.do_action)
	ui.add_child(actions)
	menu = Menu.new()
	# Faded in once the country has been on screen for a moment; see
	# `_reveal_menu`.
	menu.modulate.a = 0.0
	menu.jet_changed.connect(_set_preview)
	menu.weather_changed.connect(set_weather)
	menu.start_requested.connect(session.on_launch)
	menu.host_requested.connect(session.host_game)
	# the slot depends on the roster, which arrives after the mission starts
	net.roster_changed.connect(session.offset_for_peer)
	menu.mission_changed.connect(session.on_lobby_mission)
	menu.join_requested.connect(session.join_game)
	menu.side_changed.connect(func(sd: int) -> void:
		if net != null:
			net.set_side(sd)
			Sim.report("you are %s" % ("BLUE" if sd == 0 else "RED"), Sim.Ev.INFO))
	menu.resume_requested.connect(controls.resume)
	menu.settings_requested.connect(func() -> void: pause_menu.open_settings())
	ui.add_child(menu)
	# After the hangar, so it draws over it: the hangar opens the settings page
	# too, and the deploy screen is put in below the hangar.
	pause_menu = PauseMenu.new()
	pause_menu.name = "Pause"
	pause_menu.world = self
	pause_menu.resume_requested.connect(controls.resume)
	pause_menu.restart_requested.connect(controls.restart_match)
	pause_menu.change_mode_requested.connect(controls.pause_to_hangar)
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
	cmdline.parse()
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
		# the satellite view with the air cleared away: the ground as a map
		# would show it, no haze over it
		if SatView.clear_air and is_instance_valid(sat_view) and sat_view.active():
			_env.fog_enabled = false
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
		crew.sensor_input()
	if gunning:
		crew.gunner_input(delta)
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
	controls.sync_mouse()
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
	# and the air and the cloud put away for the satellite view's clear air
	# (only when it changes: the planet tests hide them themselves)
	var clear: bool = SatView.clear_air and is_instance_valid(sat_view) and sat_view.active()
	if clear != _air_cleared:
		_air_cleared = clear
		if is_instance_valid(atmo):
			atmo.visible = not clear
		if is_instance_valid(clouds):
			clouds.visible = not clear
	if is_instance_valid(hud) and is_instance_valid(cam) and running:
		hud.flight_page = (cam.mode == ChaseCamera.Mode.COCKPIT) \
			and not is_instance_valid(cam.weapon_cam)
	if boarding:
		crew.tick_boarding(delta)
	if running and is_instance_valid(player) and not boarding and not on_foot:
		_watch_landing(delta)
	if harness != null:
		if harness.tick_after_flight(delta):
			return
	# hold the view on something real while following
	if is_instance_valid(admin) and admin.following and is_instance_valid(cam):
		if not is_instance_valid(cam.subject) or not admin_desk.traffic.has(cam.subject):
			admin_desk.follow_traffic(true)
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
	sweep.clear_mission()
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
	session._redeploy_wait = false
	if is_instance_valid(pause_menu):
		pause_menu.close()
	controls.show_roster(false)
	preview.visible = false
	hud.visible = true
	running = true
	_audit_spawns.call_deferred()
	_slot_home = Vector3.INF
	_slot_said = -1
	_mission_started = Time.get_ticks_msec()
	session.offset_for_peer.call_deferred()
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
			crew.begin_boarding()
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
			missions.setup_ramp()
		"sandbox":
			# Everything to play with, in one place. The ramp lays out the
			# flight line and the vehicle park; the rest is what the other
			# no-threat modes never had — something in the air to shoot at, and
			# the orbital picture already overhead.
			missions.setup_ramp()
			admin_desk.populate("bandits")
			admin_desk.populate("choppers")
			admin_desk.populate("warships")
			admin_desk.populate("sats")
			Sim.report("SANDBOX — the park, the flight line, hostile aircraft, gunships and shipping, and the satellites.",
				Sim.Ev.INFO)
			Sim.report("F3 opens the admin page: it can add any of them in any mission.",
				Sim.Ev.INFO)
		"conquest", "rush", "warlords", "tdm", "ffa":
			missions.setup_battle(mission)
		"cqb", "ground", "arms", "range":
			street_fight.setup_cqb(mission)
		"carrier":
			missions.setup_carrier_approach()
		"launch":
			missions.setup_launch("orbital")
		"moon":
			missions.setup_launch("lunar")
		"strike":
			missions.setup_strike()
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
			missions.spawn_threats()
			Sim.report("Bandits north of the field. Bays open before you shoot.", Sim.Ev.INFO)
	if foot_at_field:
		if boarding:
			crew.end_boarding()
		session.foot_at_field()


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
		session.offer_redeploy())

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
	show_player()
	_reset_interp.call_deferred(player)

## The sensor page shut, full screen off, and let go of whatever it was on.
func stow_pod() -> void:
	if pod.active:
		pod.toggle()
	pod.set_fullscreen(false)
	pod.platform = null

## The player's aircraft on every page that reads it: the camera, the HUD,
## the sensor, the map, and the airfields that watch for it.
func show_player() -> void:
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

## A body that was just teleported has stale interpolation history; without this
## it renders a smear from its old position to the new one.
func _reset_interp(n: Node3D) -> void:
	if is_instance_valid(n):
		n.reset_physics_interpolation()


func _on_mode_finished(_win: bool, _text: String) -> void:
	pass

# ------------------------------------------------------------------- CQB
## The street fight, if one is running.
var cqb: CqbMatch = null
var called_gunship: Aircraft = null
var cqb_gun_t := 0.0
var cqb_parked: Aircraft = null
var cqb_tel: Tank = null
var cqb_tel_t := 0.0

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

var cqb_parked_at: Array = []


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
	if missions.in_rocket():
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


## A measurement run. The harnesses were written against a sea that always had
## the squadron on it, whatever mission they happened to start.
var _fleet_always := false


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
	t.global_transform = Tank.ground_pose(spot, yaw, t.rest_height())
	t.dismount_requested.connect(crew.leave_tank)
	_reset_interp.call_deferred(t)
	return t


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
		net.launches.share(player, m)

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


class Shell extends Node:
	var world: Node = null

	func _input(e: InputEvent) -> void:
		if world:
			world.controls.shell_input(e)

	func _notification(what: int) -> void:
		if world and (what == NOTIFICATION_APPLICATION_FOCUS_IN \
				or what == NOTIFICATION_WM_WINDOW_FOCUS_IN):
			world.controls.regrab()

## The crewed launch vehicle, if there is one on the pad or in the sky.
var rocket: LaunchVehicle = null
