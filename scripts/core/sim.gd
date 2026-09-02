extends Node
## Global services: input map bootstrap, the analytic terrain field, mission
## configuration and scoring. Autoloaded as `Sim`.

const WORLD_HALF := 600000.0     # world extends +/- 600 km
const COAST_X := 15000.0         # open water east of here
const WATER_LEVEL := -35.0
const RUNWAY_LEN := 3000.0       # 36/18, aligned with the Z axis
const RUNWAY_HALF_W := 23.0
const RUNWAY_ELEV := 0.0


signal mission_event(text: String, kind: int)   # kind: 0 info, 1 good, 2 bad

enum Ev { INFO, GOOD, BAD }

## Continents, for deciding which side of the map a place belongs to. The
## height field itself -- the continents, the rivers, the ridges, the detail --
## lives in `field.rs` and is the extension's business; this is the one noise
## the game still reads directly.
var noise_cont := FastNoiseLite.new()
## The native extension. It owns the height field: see `height_at`.
var native: Object = null

var noise_temp := FastNoiseLite.new()
var noise_moist := FastNoiseLite.new()

var selected_jet := &"f22"
var mission := &"takeoff"
var weather := "scattered"
var debug_weapons := false        # set by --debugweapons, prints impact data
var net: Node = null              # the live NetLink, or null offline
## True while a full screen page owns the mouse -- the map, the action menu,
## the pause menu. Weapons are polled straight from the input actions rather
## than through the GUI, so without this a click on the map also pulled the
## trigger.
var ui_modal := false
## True while the chat line is open. Held keys keep reporting through
## `Input.is_action_pressed` no matter what consumes the event, so typing "d"
## in the chat rolled the aeroplane right. Every control surface reads through
## the three helpers below instead, and they go quiet while a line is open.
var typing := false
## Where the last explosion was drawn, for the harness.
var salvo_watch := false
var salvo_weapon := "gbu32"
var salvo_mark := Vector3.INF
var salvo_log: Array = []
var last_burst := Vector3.INF
var last_burst_r := 0.0
## Sensor suite state, shared by the HUD, the pod and the map.
const RADAR_RANGES := [10000.0, 20000.0, 40000.0, 80000.0]
var radar_range_idx := 2
var panel_left := 0               # 0 off, 1 sensor, 2 radar, 3 minimap
var panel_right := 2

func radar_range() -> float:
	return RADAR_RANGES[clampi(radar_range_idx, 0, RADAR_RANGES.size() - 1)]

# ---------------------------------------------------------------- settings
## What survives being closed. Nothing did: there was no options page, no
## ConfigFile, no rebinding, so weather, fly-by-wire, radar range and the mouse
## stick were all back to their defaults every single run.
const SETTINGS_PATH := "user://settings.cfg"

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("sim", "weather", weather)
	cf.set_value("sim", "assist", assist)
	cf.set_value("sim", "radar_range_idx", radar_range_idx)
	cf.set_value("sim", "mouse_gain", mouse_gain)
	cf.set_value("sim", "invert_pitch", invert_pitch)
	var err := cf.save(SETTINGS_PATH)
	if err != OK:
		push_warning("could not save settings: %d" % err)

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	weather = String(cf.get_value("sim", "weather", weather))
	assist = bool(cf.get_value("sim", "assist", assist))
	radar_range_idx = int(cf.get_value("sim", "radar_range_idx", radar_range_idx))
	mouse_gain = float(cf.get_value("sim", "mouse_gain", mouse_gain))
	invert_pitch = bool(cf.get_value("sim", "invert_pitch", invert_pitch))

## Pointer scaling and pitch sense, which every simulator has and this had
## hard-coded.
var mouse_gain := 1.0
var invert_pitch := false

# --------------------------------------------------------------------- IFF
## Who a contact is, as far as the observer can actually tell.
##
## Everything filtered on `team` directly, which meant identification was
## perfect and free: there was nothing that could be uncertain, nothing that
## could be got wrong. A radar return is a return — what makes it a friend is
## a transponder answering, and that only carries so far.
enum Iff { FRIEND, HOSTILE, UNKNOWN }

## How far a transponder interrogation is good for. Beyond this the return is
## still painted, it just has no name against it.
const IFF_RANGE := 46_000.0

func iff(observer: Node, contact: Node) -> int:
	if not is_instance_valid(observer) or not is_instance_valid(contact):
		return Iff.UNKNOWN
	if not ("team" in observer) or not ("team" in contact):
		return Iff.UNKNOWN
	# Your own side answers wherever it is: you are on the same net.
	if int(observer.team) == int(contact.team):
		return Iff.FRIEND
	if not (observer is Node3D) or not (contact is Node3D):
		return Iff.HOSTILE
	var d: float = (observer as Node3D).global_position.distance_to(
		(contact as Node3D).global_position)
	# Something that does not answer, close enough to have been asked properly,
	# is hostile. Further out it is simply a contact.
	return Iff.HOSTILE if d <= IFF_RANGE else Iff.UNKNOWN

func iff_label(code: int) -> String:
	match code:
		Iff.FRIEND:
			return "FRIENDLY"
		Iff.HOSTILE:
			return "HOSTILE"
		_:
			return "UNKNOWN"

## Which satellite the ASAT launchers have been assigned, picked on the map.
## Kept here rather than on the map page because the launcher has to read it and
## the map is not always up.
var sat_target: Node = null

## Ask a friendly reconnaissance satellite what it can see. This is what the
## terminal link on the TAB menu does: a satellite that only ever widened a
## number was not something you could *use*.
func satellite_survey(team: int) -> Dictionary:
	var out := {"sat": "", "seen": 0, "centre": Vector3.INF}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	var eye: Node3D = null
	for sat in tree.get_nodes_in_group("satellites"):
		if not is_instance_valid(sat) or not (sat is Node3D):
			continue
		if ("team" in sat) and int(sat.team) != team:
			continue
		if String(sat.get("kind")) != "recon":
			continue
		eye = sat as Node3D
		break
	if eye == null:
		return out
	out["sat"] = String(eye.call("display_name")) if eye.has_method("display_name") \
		else "satellite"
	# Everything hostile under it, and where the weight of it is. A survey is a
	# picture of where they are, not a list.
	var sum := Vector3.ZERO
	var n := 0
	for x in tree.get_nodes_in_group("hittable"):
		if not is_instance_valid(x) or not (x is Node3D):
			continue
		if not ("team" in x) or int(x.team) == team:
			continue
		if x.has_method("is_alive") and not x.is_alive():
			continue
		var q: Vector3 = (x as Node3D).global_position
		if Vector2(q.x - eye.global_position.x, q.z - eye.global_position.z).length() \
				> SAT_REACH:
			continue
		sum += q
		n += 1
	out["seen"] = n
	if n > 0:
		out["centre"] = sum / float(n)
	return out

## How many of something are already in the world. The admin page uses it so
## that asking for a thing twice tops the set up rather than laying down a
## duplicate of everything.
func census(group: String) -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return 0
	var n := 0
	for x in tree.get_nodes_in_group(group):
		if is_instance_valid(x):
			n += 1
	return n

# --------------------------------------------------------------- objective
## Somewhere the player has decided matters. Set with shift and click on the
## tactical map, and deliberately kept here rather than on the map page: the
## whole point of it is that you can see it from the cockpit, from the chase
## camera, from a tank and from a ship's bridge, which means everything that
## draws has to be able to ask for it.
var objective := Vector3.INF

func set_objective(at: Vector3) -> void:
	objective = at
	report("objective marked at %d, %d" % [int(at.x), int(at.z)], Ev.INFO)

func clear_objective() -> void:
	objective = Vector3.INF
	report("objective cleared", Ev.INFO)

# ---------------------------------------------------------------- coverage
## How far a side can actually see, which is not the same as how far its own
## radar reaches. An aeroplane's set is limited by what it can carry; what
## extends it is somebody else's — an early warning aircraft orbiting behind the
## line, or a reconnaissance satellite passing over.
##
## Both existed as objects with nothing attached to them: the E-3 was a large
## aeroplane that did nothing and a satellite was something to shoot at for no
## gain. This is what they are for, and it is why killing one matters.
const AWACS_REACH := 190_000.0
const SAT_REACH := 130_000.0

## Not cached. The first cut of this held the answer for a frame, keyed on
## `Engine.get_frames_drawn()` — which does not advance in a headless run, so
## the very first answer was returned for the rest of the session and an E-3
## taking off changed nothing. It is two small groups and it is asked once per
## page draw, not once per contact, so there is nothing here worth caching.
func coverage(team: int) -> float:
	var reach: float = radar_range()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		# An early warning aircraft has to be up and alive to be any use.
		for n in tree.get_nodes_in_group("awacs"):
			if not is_instance_valid(n) or not (n is Node3D):
				continue
			if ("team" in n) and int(n.team) != team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			reach = maxf(reach, AWACS_REACH)
		for sat in tree.get_nodes_in_group("satellites"):
			if not is_instance_valid(sat):
				continue
			if ("team" in sat) and int(sat.team) != team:
				continue
			if String(sat.get("kind")) != "recon":
				continue
			reach = maxf(reach, SAT_REACH)
		# Ground based air defence. A battery is a radar with rounds attached
		# and it was contributing nothing to the picture — the side it belongs
		# to could not see any further for having one, which is most of what a
		# battery is actually for.
		for v in tree.get_nodes_in_group("air_radar"):
			if not is_instance_valid(v):
				continue
			if ("team" in v) and int(v.team) != team:
				continue
			if v.has_method("is_alive") and not v.is_alive():
				continue
			if v.has_method("radar_range"):
				reach = maxf(reach, float(v.call("radar_range")))
	return reach

## Is this side's picture being helped by something other than its own radar?
## The HUD says so, because a picture that quietly doubles and then quietly
## halves again when a satellite is shot down is a mystery rather than a system.
func coverage_source(team: int) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return ""
	var got := ""
	for v in tree.get_nodes_in_group("air_radar"):
		if is_instance_valid(v) and (not ("team" in v) or int(v.team) == team) \
				and (not v.has_method("is_alive") or v.is_alive()):
			got = "GCI"
	for sat in tree.get_nodes_in_group("satellites"):
		if is_instance_valid(sat) and (not ("team" in sat) or int(sat.team) == team) \
				and String(sat.get("kind")) == "recon":
			got = "SAT"
	# An early warning aircraft reaches further than the satellite does, so if
	# both are up it is the one carrying the picture.
	for n in tree.get_nodes_in_group("awacs"):
		if is_instance_valid(n) and (not ("team" in n) or int(n.team) == team) \
				and (not n.has_method("is_alive") or n.is_alive()):
			got = "AWACS"
	return got
var assist := true
var last_landing := {}
var score := 0

# --------------------------------------------------------------------------
func _ready() -> void:
	# Whatever the player chose last time, before anything reads a default.
	load_settings()
	# Before the noise fields, so nothing can sample the GDScript ones first and
	# then be answered by the native field later in the same run.
	if ClassDB.class_exists("Terra"):
		native = ClassDB.instantiate("Terra")
	else:
		# There is no GDScript path any more. The height field, the road
		# router, the corridor and the survey all live in the extension, and
		# keeping a second implementation of each in here meant two answers to
		# the same question that could drift apart -- which, for a field the
		# towns, roads and colliders are all sited against, tears the world in
		# half. Better to fail here, loudly, than to run half a world.
		push_error("flight_native is missing. Build it with: "
			+ "cd native && GODOT4_BIN=<godot> cargo build --release")
	if native != null:
		var lim: PackedFloat32Array = native.survey_limits()
		road_grade_max = lim[1]
		road_grade_hairpin = lim[2]
		road_cut_hard = lim[5]
		road_fill_hard = lim[6]
	_setup_noise()
	_setup_input()

func _setup_noise() -> void:
	# The home field, before anything can ask for a height. Registering it from
	# the world's _ready was too late: the terrain had already been built by
	# then, with no fields in the list at all, so nothing flattened the airfield
	# and the runway ended up buried under the ground it was supposed to be on.
	fields.clear()
	register_field(Vector2.ZERO, 0.0, RUNWAY_ELEV)

	noise_cont.seed = 20260827
	noise_cont.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# a shade over two hundred kilometres to a lobe, so a continent is a day's
	# flying across and the seas between them are real seas
	noise_cont.frequency = 0.0000047
	noise_cont.fractal_octaves = 3
	noise_cont.fractal_lacunarity = 2.3
	noise_cont.fractal_gain = 0.45

	noise_temp.seed = 515
	noise_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# Thirty-six kilometres to a lobe gave mottling, not regions: across a
	# twelve hundred kilometre world every biome was a patch a few minutes wide
	# and there was no such thing as "the desert" or "the northern forest".
	noise_temp.frequency = 0.0000062
	noise_temp.fractal_octaves = 2

	noise_moist.seed = 811
	noise_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moist.frequency = 0.0000085
	noise_moist.fractal_octaves = 3


## How "airfield flat" a spot is: 1 = perfectly level apron, 0 = open terrain.
## Airfields. There was exactly one, at the origin, hard-wired into the height
## field and into every question about what you are rolling on — so the other
## side had nowhere to operate from and every aeroplane in the world staged off
## the same strip.
var fields: Array = []           # {"at": Vector2, "yaw": float, "elev": float}
var _siting := false

## Put a field on the map. Its elevation is read from the land as it is *before*
## the field is there, so it sits at the natural height of its site instead of
## dragging the country up or down to meet it.
func register_field(at: Vector2, yaw: float, elev := INF) -> Dictionary:
	var e := elev
	if e == INF:
		_siting = true
		e = height_at(at.x, at.y)
		_siting = false
	var f := {"at": at, "yaw": yaw, "elev": e}
	fields.append(f)
	# Straight over to the extension: the aerodrome is part of the height field
	# now, and everything that asks for a block of ground -- a terrain chunk, a
	# road profile, the map -- gets it applied there rather than looping over
	# the list again on this side.
	_push_world()
	return f

## How much of a given field applies at a point, in that field's own frame.
func field_factor(fd: Dictionary, x: float, z: float) -> float:
	var d: Vector2 = Vector2(x, z) - (fd["at"] as Vector2)
	var c := cos(-float(fd["yaw"]))
	var sn := sin(-float(fd["yaw"]))
	var lx: float = d.x * c - d.y * sn
	var lz: float = d.x * sn + d.y * c
	# The levelled area has to be big enough for the mesh to draw it. Out where
	# the rings are coarse a cell is kilometres across, so a strip two by four
	# was smaller than one triangle and the flattening was invisible: the
	# pavement sat thirteen metres under the ground it was supposed to be on.
	var cell: float = Terrain.cell_at(x, z)
	var pad: float = maxf(cell * 2.5, 0.0)
	var dx := maxf(absf(lx) - (950.0 + pad), 0.0)
	var dz := maxf(absf(lz) - (1950.0 + pad), 0.0)
	return 1.0 - smoothstep(0.0, maxf(2600.0, cell * 4.0), sqrt(dx * dx + dz * dz))

func flat_factor(x: float, z: float) -> float:
	var best := 0.0
	for fd in fields:
		best = maxf(best, field_factor(fd, x, z))
	return best

## Where a point sits in a field's own frame, so runway and taxiway tests can be
## written once and asked of any of them.
func field_local(fd: Dictionary, x: float, z: float) -> Vector2:
	var d: Vector2 = Vector2(x, z) - (fd["at"] as Vector2)
	var c := cos(-float(fd["yaw"]))
	var sn := sin(-float(fd["yaw"]))
	return Vector2(d.x * c - d.y * sn, d.x * sn + d.y * c)

## What a height query wants applied, matching the extension's own flags: the
## made roads, the aerodromes, or both. The town platforms are always in --
## they are part of the land as soon as a town is sited.
const G_ROADS := 1
const G_FIELDS := 2
const G_ALL := 3

## What the finished ground includes at this point in the pipeline. The
## corridor is invisible while the network is being surveyed, and the
## aerodromes while one of them is being sited.
func _ground_flags() -> int:
	var f := 0
	if not _in_survey:
		f |= G_ROADS
	if not _siting:
		f |= G_FIELDS
	return f

## Terrain elevation in metres. Single source of truth: the visual mesh, the
## landing gear and the crash test all sample this.
## The land at a point: the field, then everything built on it.
func height_at(x: float, z: float) -> float:
	# The field, the town platforms, the made roads and the aerodromes all come
	# back from the extension. The carrier decks are the one thing left on this
	# side: there are two of them and they move every frame.
	return _deck_top(native.ground(x, z, _ground_flags()), x, z)

## A landable platform standing over the ground. Applied here rather than in
## the extension because it is the one part of the world that is not fixed once
## it is built -- a carrier under way carries its deck with it.
func _deck_top(h: float, x: float, z: float) -> float:
	if decks.is_empty():
		return h
	return maxf(h, deck_height(x, z))

## How much of a settlement's levelled platform applies at a point. Zero is
## open country, one is inside the town proper.
func pad_weight(x: float, z: float) -> float:
	var w := 0.0
	for pad in _town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		var d := Vector2(x - pc.x, z - pc.y).length()
		if d < pr * 1.60:
			w = maxf(w, 1.0 - smoothstep(pr * 1.06, pr * 1.60, d))
	return w

func normal_at(x: float, z: float) -> Vector3:
	const E := 3.0
	var hl := height_at(x - E, z)
	var hr := height_at(x + E, z)
	var hd := height_at(x, z - E)
	var hu := height_at(x, z + E)
	return Vector3(hl - hr, 2.0 * E, hd - hu).normalized()

func on_runway(x: float, z: float) -> bool:
	for fd in fields:
		var l := field_local(fd, x, z)
		if absf(l.x) <= RUNWAY_HALF_W and absf(l.y) <= RUNWAY_LEN * 0.5:
			return true
	return false

## Paved surfaces (runway, taxiway loop, apron) roll better than grass.
func surface_grip(x: float, z: float) -> float:
	if deck_height(x, z) > -1e8:
		return 1.0
	if on_runway(x, z):
		return 1.0
	for fd in fields:
		var l := field_local(fd, x, z)
		if absf(l.x) >= 60.0 and absf(l.x) <= 92.0 and absf(l.y) <= RUNWAY_LEN * 0.5:
			return 1.0
		if absf(l.y) <= 1560.0 and absf(l.x) <= 95.0:
			return 1.0
	return 0.45

## Road network, shared by the terrain painter and the placement rules. It is
## rebuilt once the towns have been sited, because the towns move: a trunk road
## drawn to where a town was originally wanted ends somewhere in a field.
var ROADS: Array = [
	[Vector2(0, 1700), Vector2(-2300, -5200)],
	[Vector2(0, -1700), Vector2(2600, 4200)],
	[Vector2(-2300, -5200), Vector2(2100, -9200)],
	[Vector2(-1900, 3100), Vector2(2600, 4200)],
	[Vector2(-1500, -6600), Vector2(-2300, -5200)],
	[Vector2(2600, 4200), Vector2(4200, 11000)],
	[Vector2(-2300, -5200), Vector2(-5200, -13000)],
]

## Lay the trunk network between the airfield and wherever the towns ended up,
## each leg routed round the worst of the ground rather than driven straight
## over it. `link` is a list of index pairs into `points`.
## The whole thing in one blocking go, for anything that is not the loading
## screen -- the harnesses, mostly.
func build_roads(points: Array, links: Array) -> void:
	# Collected apart and only published at the end: routing calls height_at,
	# and a half filled network is a road with no surveyed height to read.
	begin_roads(points, links)
	finish_roads()

## Send every link out to be searched. None of this touches the scene tree, so
## they all go at once -- and, more to the point, the caller can keep drawing
## while they run. Routing is the longest single thing in world generation, and
## doing it one leg at a time on the main thread is what made the window stop
## answering: the machine decides a program that has not drawn for a minute has
## hung, and offers to kill it.
func begin_roads(points: Array, links: Array) -> void:
	ROADS = []
	_road_lines = []
	_road_prof = []
	_corr = []
	road_bridges = []
	_rt_jobs = []
	for pair in links:
		_rt_jobs.append([points[pair[0]], points[pair[1]]])
	_rt_out = []
	_rt_out.resize(_rt_jobs.size())
	_rt_gid = -1
	if _rt_jobs.is_empty():
		return
	# Every leg in one call, searched on every core inside the extension. It
	# goes out to a worker of its own so the loading screen keeps painting
	# while it runs.
	_push_world()
	_rt_gid = WorkerThreadPool.add_group_task(_route_native, 1, -1, true,
		"road routing")

## What the router has to know about the world before it surveys anything: the
## platforms the towns have been levelled onto, and where the runways are.
func _push_world() -> void:
	var pads := PackedFloat32Array()
	for pad in _town_pads:
		var c: Vector2 = pad["c"]
		pads.append(c.x)
		pads.append(c.y)
		pads.append(float(pad["r"]))
		pads.append(float(pad["y"]))
	var fl := PackedFloat32Array()
	for fd in fields:
		var at: Vector2 = fd["at"]
		fl.append(at.x)
		fl.append(at.y)
		fl.append(float(fd["yaw"]))
		fl.append(float(fd["elev"]))
	native.set_world(pads, fl)

func _route_native(_i: int) -> void:
	var ends := PackedVector2Array()
	for j in _rt_jobs:
		ends.append(j[0] as Vector2)
		ends.append(j[1] as Vector2)
	var lines: Array = native.route_many(ends)
	for k in mini(lines.size(), _rt_out.size()):
		_rt_out[k] = lines[k]

## Are the searches done? Asked once a frame by the loading screen.
func roads_routed() -> bool:
	return _rt_gid == -1 or WorkerThreadPool.is_group_task_completed(_rt_gid)

func routes_left() -> int:
	return _rt_jobs.size()

## Collect the routes and survey them into a built network.
func finish_roads() -> void:
	var t_wait := Time.get_ticks_msec()
	if _rt_gid != -1:
		WorkerThreadPool.wait_for_group_task_completion(_rt_gid)
		_rt_gid = -1
	var _routed := Time.get_ticks_msec() - t_wait
	var lines: Array = []
	var failed := 0
	for ji in _rt_jobs.size():
		var line: Variant = _rt_out[ji]
		if line is PackedVector2Array and (line as PackedVector2Array).size() > 1:
			lines.append(line)
		else:
			failed += 1
	_rt_jobs = []
	_rt_out = []
	_road_lines = _drop_orphans(lines)
	var t_sv := Time.get_ticks_msec()
	var verts := 0
	for l2 in lines:
		verts += (l2 as PackedVector2Array).size()
	_survey_roads()
	if debug_roads:
		var rs := Vector2.ZERO
		if native != null:
			rs = native.route_stats()
		print("[roads] %d legs (%d unroutable), %d waypoints -> search %d nodes in %d ms, survey %d ms" % [
			lines.size(), failed, verts, int(rs.x), int(rs.y),
			Time.get_ticks_msec() - t_sv])

# -------------------------------------------------------------- road corridor
const ROAD_HALF := 7.5           # carriageway half width
const ROAD_SHOULDER := 24.0      # graded shoulder either side of it
const ROAD_GRADE := 0.062        # steepest gradient a trunk road is built to
const SURVEY_STEP := 45.0        # spacing of the profile's stations
## How many weld-and-tie rounds the relaxation runs. Roads that meet have to
## agree about the height, and one pass moves a station by a few metres against
## a thirty-four metre reach.
const SURVEY_PASSES := 24
## What the survey actually builds to, read from the extension rather than
## written down again here: the ruling gradient, what it may be pushed to, the
## hairpin nothing may exceed, and the deepest cutting and tallest embankment
## a run that wanted a structure and did not earn one is allowed. Anything
## measuring the road has to measure it against the numbers it was built to.
var road_grade_max := 0.10
var road_grade_hairpin := 0.15
var road_cut_hard := 45.0
var road_fill_hard := 32.0
## Tallest embankment before it becomes a bridge.
##
## This was 14, and the span rule below only builds a bridge once the ground
## falls 24 -- so no embankment could ever reach the height that would hand the
## job over. Between the two the road simply gave up and lay on the ground at
## whatever gradient the ground had. The two numbers have to meet: fill up to
## here, and a bridge from here on.
const ROAD_FILL_MAX := 22.0
## Deepest cutting, on the same reasoning against TUNNEL_DEEP: dig to here, and
## bore from here on. Over a 31.5 m graded half-width, 34 m is about a one in
## one batter at the ends and shallower along the sides, which is a cutting
## through rock -- steep, but a real thing that gets built where the alternative
## is a road that cannot be driven.
const ROAD_CUT_MAX := 34.0

## The trunk network as polylines and the made height at each of their
## stations, in build order. Both come back from the extension's survey.
var _road_lines: Array = []
var _road_prof: Array = []
## The untouched ground under each station, so a cutting can be told from a
## road running along the floor of a valley.
var _natural: Array = []
var road_bridges: Array = []     # spans carried on a deck: {a, b, ya, yb, pts, ys}
## The trunk network as it is drawn, leg by leg: ax, az, bx, bz, half width,
## design height at each end, and whether it is a structure approach. Not the
## same list as `ROADS`, which is what is painted into the ground -- the terrain
## under a bridge is untouched, but the road still has to reach the deck.
var road_draw := PackedFloat32Array()
var _in_survey := false

## Lay out the whole alignment: stations at survey spacing, a design profile
## for each line, the relaxation that makes roads meeting at a junction agree
## about the height, and the classification of what has to be carried on a deck
## or bored through the hill.
##
## One call. This used to be a dozen passes over eighty thousand stations
## alternating between here and the extension -- chain, sample, grade, weld,
## tie, classify, hold, settle, float -- and marshalling the network across the
## boundary between each of them cost more than the arithmetic did. It is also
## the only place the profile is decided now, so the ruling gradient and the cut
## and fill limits are written down once, in `survey.rs`, instead of in both
## languages and drifting apart.
func _survey_roads() -> void:
	_in_survey = true
	_road_prof = []
	_natural = []
	_road_struct = []
	var flat := PackedVector2Array()
	var starts := PackedInt32Array()
	for line in _road_lines:
		starts.append(flat.size())
		flat.append_array(line as PackedVector2Array)
	starts.append(flat.size())
	var res: Array = native.survey(flat, starts, SURVEY_PASSES)
	var op: PackedVector2Array = res[0]
	var oy: PackedFloat32Array = res[1]
	var og: PackedFloat32Array = res[2]
	var of: PackedByteArray = res[3]
	var os: PackedInt32Array = res[4]
	for li in _road_lines.size():
		var a0: int = os[li]
		var a1: int = os[li + 1]
		_road_lines[li] = op.slice(a0, a1)
		_road_prof.append(oy.slice(a0, a1))
		_natural.append(og.slice(a0, a1))
		_road_struct.append(of.slice(a0, a1))
	_group_structures()
	_index_corridor()
	_push_segments()
	# The painted network has to follow the earthworks, or the carriageway is
	# stained across ground that was never levelled for it. Only the legs
	# actually laid on the ground: a tunnel is inside the hill and a bridge is
	# above it, so neither is painted onto the terrain or drawn as a ribbon
	# lying on the country.
	ROADS = []
	road_draw = PackedFloat32Array()
	for li2 in _road_lines.size():
		var pl: PackedVector2Array = _road_lines[li2]
		var pf: PackedFloat32Array = _road_prof[li2]
		for i in range(pl.size() - 1):
			var sa := _in_structure(li2, i)
			var sb := _in_structure(li2, i + 1)
			if sa and sb:
				continue                      # inside the bore or on the deck
			if not sa and not sb:
				ROADS.append([pl[i], pl[i + 1]])
			# The approach: one end on the ground and the other at an abutment
			# or a portal. Left out of the drawn network the carriageway simply
			# stopped short of every structure on the map and the deck floated
			# clear of it, so it is drawn -- on the alignment, which is
			# continuous, rather than on the ground, which is not.
			road_draw.append_array(PackedFloat32Array([
				pl[i].x, pl[i].y, pl[i + 1].x, pl[i + 1].y, ROAD_HALF,
				pf[i], pf[i + 1], 1.0 if (sa or sb) else 0.0]))
	if debug_roads:
		print("[survey] %d lines, %d stations, worst neighbour disagreement %.1f m"
			% [_road_lines.size(), op.size(), native.worst_tie(op, oy, of, os)])
	_in_survey = false

## Throw away any road that leads nowhere.
##
## A leg the router could not solve -- or refused to solve, because the only way
## across was a causeway over open sea -- leaves whatever was joined through it
## standing on its own. Some of that is rubbish: a single stretch of road
## between two points with no way in and no way out. Some of it is not: a
## cluster of towns three hundred kilometres away, joined to each other and cut
## off from home by an ocean, has exactly the road network it ought to have, and
## throwing it away left ten towns on the map with no road in them at all.
##
## So the test is whether a component is a network rather than whether it
## reaches the airfield. Endpoints are shared exactly between legs that meet, so
## joining them up is a matter of matching coordinates.
func _drop_orphans(lines: Array) -> Array:
	if lines.size() < 2:
		return lines
	var root: Array = []
	root.resize(lines.size())
	for i in lines.size():
		root[i] = i
	var find := func(a: int) -> int:
		var r: int = a
		while int(root[r]) != r:
			r = int(root[r])
		return r
	var at: Dictionary = {}
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		if pl.size() < 2:
			continue
		for p in [pl[0], pl[pl.size() - 1]]:
			var k := "%d:%d" % [int(round(p.x / 60.0)), int(round(p.y / 60.0))]
			if at.has(k):
				var ra: int = find.call(li)
				var rb: int = find.call(int(at[k]))
				if ra != rb:
					root[ra] = rb
			else:
				at[k] = li
	var size: Dictionary = {}
	for li2 in lines.size():
		var r: int = find.call(li2)
		size[r] = int(size.get(r, 0)) + 1
	# the component the airfield is in is always kept, however small
	var home := -1
	var best := 1e18
	for li3 in lines.size():
		var pl3: PackedVector2Array = lines[li3]
		if pl3.size() < 2:
			continue
		var d: float = (pl3[0] as Vector2).length_squared()
		if d < best:
			best = d
			home = li3
	var keep_root: int = find.call(home) if home >= 0 else -1
	var out: Array = []
	var dropped := 0
	for li4 in lines.size():
		var r2: int = find.call(li4)
		if r2 == keep_root or int(size[r2]) >= 2:
			out.append(lines[li4])
		else:
			dropped += 1
	if dropped > 0 and debug_roads:
		print("[roads] dropped %d road(s) of %d that led nowhere; %d network(s) left"
			% [dropped, lines.size(), size.size()])
	return out

var debug_roads := false

## Lay the network out again. The command line is parsed after the world has
## already built its roads, so the harness needs a way to watch the survey.
func resurvey_roads() -> void:
	_road_prof = []
	_corr = []
	_survey_roads()

## Where the made height stands too far above the land to be an embankment, the
## road is carried instead. Recorded as spans so the scenery can put a deck and
## piers under them.
## Where the alignment cannot simply be cut or filled into the country, the road
## needs a structure: a bridge over the low ground, a tunnel through the high.
##
## Without them a road has exactly two options, both wrong. Carve, and it leaves
## a slot through the hill with the carriageway at the bottom. Refuse to carve,
## and it climbs the hill instead, which is where the 22% gradients came from.
## A structure is the third answer: the alignment holds its grade and the ground
## is left completely alone underneath it.
##
## Which stations are inside one is decided by the survey, in `survey.rs`,
## because it is decided *with* the profile rather than after it: what has to be
## carried depends on where the alignment ended up, and where the alignment ends
## up depends on which stations are held to the ground. This side only groups
## the marked stations into the runs the scenery builds decks and portals over.
var road_tunnels: Array = []     # {a, b, ya, yb, pts, ys}
## Per surveyed station, whether the road is inside a structure there. The
## corridor leaves the ground alone across those, and the surface is drawn as a
## deck or not at all rather than painted on the hillside.
var _road_struct: Array = []

const F_BRIDGE := 1
const F_TUNNEL := 2

func _group_structures() -> void:
	road_bridges = []
	road_tunnels = []
	for li in _road_lines.size():
		var pl: PackedVector2Array = _road_lines[li]
		var prof: PackedFloat32Array = _road_prof[li]
		var flags: PackedByteArray = _road_struct[li]
		var i0 := 0
		while i0 < flags.size():
			if flags[i0] == 0:
				i0 += 1
				continue
			var kind: int = flags[i0]
			var i1 := i0
			while i1 + 1 < flags.size() and flags[i1 + 1] == kind:
				i1 += 1
			# the whole run, not just its ends: a span follows the alignment,
			# and a deck drawn as one straight beam between the abutments
			# leaves the road beside it
			var pts := PackedVector2Array()
			var ys := PackedFloat32Array()
			for k in range(i0, i1 + 1):
				pts.append(pl[k])
				ys.append(prof[k])
			var rec := {"a": pl[i0], "b": pl[i1],
				"ya": prof[i0], "yb": prof[i1], "pts": pts, "ys": ys}
			if kind == F_BRIDGE:
				road_bridges.append(rec)
			else:
				road_tunnels.append(rec)
			i0 = i1 + 1

## Is the road inside a structure at this station?
func _in_structure(li: int, i: int) -> bool:
	if li >= _road_struct.size():
		return false
	var f: PackedByteArray = _road_struct[li]
	return i < f.size() and f[i] != 0

const CORR_CELL := 64.0

## Every corridor leg, and which cells of a coarse grid each one touches.
## height_at asks for this on every call, and walking eight hundred legs to
## answer it cost more than the rest of the height field put together.
var _corr: Array = []            # [a, b, ya, yb]

func _index_corridor() -> void:
	_corr = []
	for li in _road_lines.size():
		var pl: PackedVector2Array = _road_lines[li]
		var prof: PackedFloat32Array = _road_prof[li]
		# and the ground the earthworks started from, so the cut can be bounded
		# against the centreline rather than against whatever is under the point
		# being asked about -- which differs across the width of the road and
		# tips the carriageway over as soon as the bound bites
		var nat: PackedFloat32Array = _natural[li] if li < _natural.size() \
			else prof
		for i in range(pl.size() - 1):
			# A leg inside a structure moves no earth at all: the deck is above
			# the ground or the bore is inside the hill, and either way the
			# country under it is untouched.
			#
			if _in_structure(li, i) or _in_structure(li, i + 1):
				continue
			_corr.append([pl[i], pl[i + 1], prof[i], prof[i + 1],
				nat[i], nat[i + 1]])
	_push_corridor()

## Hand the corridor to the extension, which is where its index lives.
func _push_corridor() -> void:
	var flat := PackedFloat32Array()
	for leg in _corr:
		var la: Vector2 = leg[0]
		var lb: Vector2 = leg[1]
		flat.append(la.x)
		flat.append(la.y)
		flat.append(lb.x)
		flat.append(lb.y)
		flat.append(float(leg[2]))
		flat.append(float(leg[3]))
		flat.append(float(leg[4]))
		flat.append(float(leg[5]))
	native.set_corridor(flat)

## The land as it was before any road was built on it. The corridor is the only
## thing `_in_survey` switches off, which is exactly the difference between the
## finished ground and the ground the earthworks started from -- so this is what
## a cutting or an embankment should be measured against. Comparing the road
## against the hillside beside it instead cannot tell a road running along the
## floor of a valley from a road in a ninety metre trench.
func natural_height_at(x: float, z: float) -> float:
	var was := _in_survey
	_in_survey = true
	var h := height_at(x, z)
	_in_survey = was
	return h

## The made surface at a point: its height and how much of it applies here,
## falling from the whole carriageway out to nothing at the edge of the graded
## shoulder. Zero weight means the land is left as it was.
## Returns (made height, how much of it applies, the ground it was cut from).
func road_surface(x: float, z: float) -> Vector3:
	# The corridor is stamped into a grid inside the extension, which is the
	# only place it exists: `_corr` here is just the list handed over to it.
	if _corr.is_empty() or _road_prof.size() != _road_lines.size():
		return Vector3.ZERO
	return native.road_surface_at(x, z)

## A road between two places that goes round the hills instead of over them.
##
## This used to seed a straight line and slide each waypoint sideways along that
## line's normal, keeping whatever was cheapest. Greedy, local, one degree of
## freedom, and no way back: it could bow round a spur but it could not
## switchback, double back, or take a dogleg through a pass that lay behind it.
## Terrain it could not get round had to be solved with a tunnel instead, which
## is why a third of the network ended up bored through hills.
##
## This is a real search: A* over a coarse grid, with the edge cost being what a
## road actually costs -- length, climb, the square of the gradient, a heavy
## penalty past what a trunk road is built to, water, and the airfield keep-out.
## The result is then pulled straight, because a grid path arrives full of
## forty-five degree staircases that no surveyor would set out.
var _rt_jobs: Array = []
var _rt_out: Array = []
var _rt_gid := -1

var _segments: Array = []          # every road and street, filled by Scenery
var decks: Array = []              # landable platforms: {origin, basis, half, y}

## Register a flight deck. `half` is the half extent in deck-local X/Z.
func register_deck(origin: Vector3, yaw: float, half: Vector2, deck_y: float) -> Dictionary:
	var d := {"origin": origin, "yaw": yaw, "half": half, "y": deck_y,
		"cos": cos(-yaw), "sin": sin(-yaw)}
	decks.append(d)
	return d

## Deck-local coordinates of a world point, or INF when it is not over the deck.
func deck_local(d: Dictionary, x: float, z: float) -> Vector2:
	var dx: float = x - d["origin"].x
	var dz: float = z - d["origin"].z
	var lx: float = dx * d["cos"] - dz * d["sin"]
	var lz: float = dx * d["sin"] + dz * d["cos"]
	return Vector2(lx, lz)

func deck_height(x: float, z: float) -> float:
	for d in decks:
		var l := deck_local(d, x, z)
		if absf(l.x) <= d["half"].x and absf(l.y) <= d["half"].y:
			return d["y"]
	return -1e9

## Level ground for the settlements. Each pad is worked out from the land as it
## is before any of them exist, so the platform sits at the natural height of
## the site and the shoulders blend out over the last fifth of the radius.
var _town_pads: Array = []

## Everything the height field and the road drawing depend on that comes out of
## routing the network: the pads the towns stand on, the trunk legs, the
## surveyed profile, the bridges and the corridor index. All of it is the same
## every run, and arriving at it costs the better part of three seconds, so it
## goes to disk with the rest of the bake.
func road_state() -> Dictionary:
	return {"pads": _town_pads, "roads": ROADS, "lines": _road_lines,
		"prof": _road_prof, "bridges": road_bridges, "corr": _corr,
		"segs": _segments, "tunnels": road_tunnels, "draw": road_draw,
		"struct": _road_struct, "natural": _natural}

func load_road_state(d: Dictionary) -> void:
	_town_pads = d["pads"]
	ROADS = d["roads"]
	_road_lines = d["lines"]
	_road_prof = d["prof"]
	road_bridges = d["bridges"]
	_corr = d["corr"]
	_segments = d["segs"]
	road_tunnels = d.get("tunnels", [])
	road_draw = d.get("draw", PackedFloat32Array())
	_road_struct = d.get("struct", [])
	_natural = d.get("natural", [])
	# The corridor's grid is not baked -- it is stamped inside the extension,
	# so a run that loads the network from disk has to hand the legs over just
	# as a run that surveyed them does.
	_push_corridor()
	_push_segments()

func register_town_pads(sites: Array) -> void:
	_town_pads.clear()
	for site in sites:
		var c: Vector2 = site["c"]
		var r: float = site["r"]
		# the mean of the land under the footprint, not the height at the middle
		var total := 0.0
		var n := 0
		for i in 9:
			for j in 9:
				var q := c + Vector2(float(i - 4), float(j - 4)) * (r * 0.22)
				if q.distance_to(c) > r:
					continue
				total += height_at(q.x, q.y)
				n += 1
		var y: float = (total / maxf(float(n), 1.0)) if n > 0 else height_at(c.x, c.y)
		_town_pads.append({"c": c, "r": r, "y": maxf(y, WATER_LEVEL + 8.0)})

## Mean gradient over a footprint, as a fraction. Used to choose where a town
## goes: the flattest workable ground within reach of where it was wanted.
func site_roughness(c: Vector2, r: float) -> float:
	var total := 0.0
	var n := 0
	for i in 7:
		for j in 7:
			var q := c + Vector2(float(i - 3), float(j - 3)) * (r * 0.30)
			if q.distance_to(c) > r:
				continue
			total += 1.0 - normal_at(q.x, q.y).y
			n += 1
	return total / maxf(float(n), 1.0)

func register_segments(segs: Array) -> void:
	_segments = segs
	_push_segments()

## Hand the whole network to the extension, where it is indexed on a uniform
## grid and every distance query is answered exactly.
##
## What was here before was a 256 x 256 raster of the distance field over an
## eighteen kilometre box, and the reason it existed was that walking the
## segments in script cost more than the rest of world generation put together.
## It was also wrong: 141 m to a cell against a fifteen metre carriageway, so
## standing on the centreline it reported a mean of 30 m away and up to 85, and
## the answer had to be guarded by walking the segments properly wherever it
## mattered. An indexed exact query is both faster than the guard and right
## everywhere, and it covers the whole map rather than a box around home.
func _push_segments() -> void:
	var flat := PackedFloat32Array()
	var n := 0
	for src in [ROADS, _segments]:
		n += (src as Array).size()
	flat.resize(n * 4)
	var w := 0
	for src in [ROADS, _segments]:
		for r in (src as Array):
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			flat[w] = a.x
			flat[w + 1] = a.y
			flat[w + 2] = b.x
			flat[w + 3] = b.y
			w += 4
	native.set_segments(flat)
	segments_indexed = n

## How many road and street legs the distance index holds.
var segments_indexed := 0

## How far it is worth looking for a road before answering "nowhere near one".
## The ring search widens until it can prove nothing closer exists, so this only
## caps how much empty country it will sweep for a point in the middle of it.
const ROAD_REACH := 4000.0

## Distance in metres from (x, z) to the nearest road or street centreline.
func road_distance(x: float, z: float) -> float:
	return native.road_distance_at(x, z, ROAD_REACH)

## The same, for a batch of points -- which is how anything scattering over the
## country should ask, so the whole set is answered across every core at once.
func road_distances(pts: PackedVector2Array) -> PackedFloat32Array:
	return native.road_distances_at(pts, ROAD_REACH)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func buildable(x: float, z: float, flat := 0.86, clearance := 4.0,
		road_clear := 4.0) -> bool:
	var y := height_at(x, z)
	if y < WATER_LEVEL + clearance:
		return false
	if normal_at(x, z).y < flat:
		return false
	if not clear_of_roads(x, z, road_clear):
		return false
	if absf(x) < 340.0 and absf(z) < 2100.0:
		return false
	return true

## A wider keep-out for anything tall: pylons, masts and turbines must not stand
## in the approach path or on the airfield itself.
## True when nothing of the given half-width would be standing in a road here.
func clear_of_roads(x: float, z: float, half: float) -> bool:
	if segments_indexed == 0:
		return true
	if road_distance(x, z) < 13.0 + half:            # carriageway plus kerbs
		return false
	return true

func clear_of_airfield(x: float, z: float) -> bool:
	if absf(x) < 620.0 and absf(z) < 2600.0:
		return false
	# and clear of the extended centreline where the approach lights run
	if absf(x) < 260.0 and absf(z) < 5200.0:
		return false
	return true

# ---------------------------------------------------------------- biomes
## Blended biome weights at a spot. Everything that dresses the ground - terrain
## colour, scatter species, density - reads from here so they always agree.
## Written without allocations: this runs a few hundred thousand times during
## terrain generation and a Dictionary per vertex was costing seconds.
const B_SNOW := 0
const B_ROCK := 1
const B_FOREST := 2
const B_GRASS := 3
const B_STEPPE := 4
const B_SAND := 5
const B_MARSH := 6
const BIOME_NAMES := ["snow", "rock", "forest", "grass", "steppe", "sand", "marsh"]
const BIOME_COLOURS := [
	Color(0.93, 0.95, 0.98),   # snow
	Color(0.31, 0.28, 0.26),   # rock
	Color(0.13, 0.24, 0.12),   # forest
	Color(0.22, 0.33, 0.15),   # grass
	Color(0.44, 0.41, 0.23),   # steppe
	Color(0.60, 0.55, 0.38),   # sand
	Color(0.19, 0.28, 0.20),   # marsh
]

var _bw := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])

## Fills the shared weight buffer and returns it. Do not hold on to the result.
## `cl` overrides the two climate lookups with values from somewhere else --
## the baked texture the ground shader reads. Only the harness passes it, and it
## is what lets the fidelity of that texture be measured against this, the
## arithmetic both sides share, rather than against a second copy of it.
func biome_weights(x: float, z: float, y: float, slope: float,
		cl: Vector2 = Vector2(-1.0, -1.0)) -> PackedFloat32Array:
	# Latitude first, weather second. Without a band running with the map there
	# is no reason for the far north to be colder than the middle, so climate
	# was noise alone and the world had no geography to it — the same patchwork
	# everywhere. `z` is north-south, so this is the only term that can make a
	# pole cold and a middle latitude hot.
	var lat: float = clampf(absf(z) / (WORLD_HALF * 0.85), 0.0, 1.0)
	var band: float = 1.0 - lat * 1.25
	# the dry belts sit either side of the hot middle, the way they do on Earth
	var belt: float = clampf(1.0 - absf(lat - 0.32) * 3.0, 0.0, 1.0)
	var nt: float = cl.x if cl.x >= 0.0 \
		else (noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
	var nm: float = cl.y if cl.y >= 0.0 \
		else (noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
	var temp: float = clampf(band * 0.70 + nt * 0.42
		- clampf((y - 300.0) / 2200.0, 0.0, 1.0) * 0.85, 0.0, 1.0)
	var moist: float = clampf(nm
		+ clampf(1.0 - absf(y - WATER_LEVEL) / 900.0, 0.0, 1.0) * 0.25
		- belt * 0.66, 0.0, 1.0)
	var steep: float = clampf((0.90 - slope) / 0.34, 0.0, 1.0)
	# Snow keyed on height alone, so a polar plain at sea level was grass and
	# the only white in the world was on the mountains. Cold is cold.
	_bw[B_SNOW] = clampf((y - 1500.0) / 700.0, 0.0, 1.0) * (1.0 - steep * 0.7) \
		* clampf(1.0 - temp * 1.4, 0.0, 1.0) + clampf((y - 2400.0) / 500.0, 0.0, 1.0) \
		+ clampf((0.18 - temp) / 0.18, 0.0, 1.0) * 1.6
	_bw[B_ROCK] = steep + clampf((y - 1100.0) / 1400.0, 0.0, 1.0) * 0.5
	_bw[B_FOREST] = clampf(moist * 1.5 - 0.35, 0.0, 1.0) * clampf(temp * 1.6, 0.0, 1.0) \
		* clampf(1.0 - (y - 200.0) / 1500.0, 0.0, 1.0)
	# and grass was drawn so broadly that it won nearly everywhere it was not
	# outright excluded, which is why the map read as one green sheet
	_bw[B_GRASS] = clampf(1.0 - absf(moist - 0.55) * 3.2, 0.0, 1.0) * 0.85 \
		* clampf(1.0 - (y - 400.0) / 1600.0, 0.0, 1.0)
	_bw[B_STEPPE] = clampf(0.62 - moist, 0.0, 1.0) * 1.7 * clampf(temp * 1.3, 0.0, 1.0)
	# Desert wanted moisture under 0.30 *and* temperature over 0.55 at once,
	# which almost never happened: there was no desert anywhere in the world,
	# only the thin band of beach sand along the shore.
	_bw[B_SAND] = clampf(1.0 - absf(y - WATER_LEVEL) / 26.0, 0.0, 1.0) * 1.4 \
		+ clampf(0.40 - moist, 0.0, 1.0) * clampf(temp - 0.30, 0.0, 1.0) * 7.0
	_bw[B_MARSH] = clampf(moist - 0.72, 0.0, 1.0) * 2.2 \
		* clampf(1.0 - absf(y - WATER_LEVEL) / 140.0, 0.0, 1.0)
	var total := 0.0
	for i in 7:
		if _bw[i] < 0.0:
			_bw[i] = 0.0
		total += _bw[i]
	if total < 0.001:
		_bw[B_GRASS] = 1.0
		total = 1.0
	for i in 7:
		_bw[i] /= total
	return _bw

func biome_colour(x: float, z: float, y: float, slope: float,
		cl: Vector2 = Vector2(-1.0, -1.0)) -> Color:
	var w := biome_weights(x, z, y, slope, cl)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for i in 7:
		var c: Color = BIOME_COLOURS[i]
		var k: float = w[i]
		r += c.r * k
		g += c.g * k
		b += c.b * k
	var out := Color(r, g, b)
	# Under the sea. The biome field is a function of height, moisture and
	# slope, and knows nothing about the waterline -- so the seabed came out as
	# grassland, and there was meadow under three hundred metres of water. Sand
	# in the shallows, grading to silt and then to bare rock as it drops away.
	if y < WATER_LEVEL:
		var deep: float = clampf((WATER_LEVEL - y) / 150.0, 0.0, 1.0)
		var bed := Color(0.46, 0.42, 0.33).lerp(Color(0.17, 0.18, 0.19), deep)
		out = out.lerp(bed, clampf((WATER_LEVEL - y) / 10.0, 0.0, 1.0))
	return out

## Dominant biome name, used by the scatter to pick a species.
func biome_kind(x: float, z: float, y: float, slope: float) -> String:
	var w := biome_weights(x, z, y, slope)
	var best := 3
	var bv := -1.0
	for i in 7:
		if w[i] > bv:
			bv = w[i]
			best = i
	return BIOME_NAMES[best]

func report(text: String, kind: int = Ev.INFO) -> void:
	mission_event.emit(text, kind)
	if OS.has_feature("headless") or OS.is_debug_build():
		print("[mission %6.1f] %s" % [Time.get_ticks_msec() * 0.001, text])

## Terrain masking. True when nothing between the two points is inside the
## height field — the test a radar, a seeker head and a pair of eyes all need,
## and previously duplicated inside the HUD where nothing else could reach it.
## The step is fine enough to catch a ridge line and coarse enough that a whole
## radar sweep's worth of calls costs nothing.
## `skip` ignores the first stretch of the ray. A radar is not blocked by the
## ground its own aeroplane is standing on: with the eye four metres up and the
## march starting immediately, every contact read as masked the moment you were
## at low level or on the runway, and the answer to pressing T was "no radar
## contacts" wherever you pointed it.
## Who is already being shot at, and by how many. Without this every hull in
## the fleet picked the same inbound round -- the nearest one -- and emptied
## cells at it together while everything else came through untouched.
var _engaged: Dictionary = {}

func engage_count(threat: Node) -> int:
	if not is_instance_valid(threat):
		return 0
	var rec: Variant = _engaged.get(threat.get_instance_id())
	if rec == null:
		return 0
	# an assignment goes stale: the round it was fired at arrives or is killed
	if Time.get_ticks_msec() - int((rec as Array)[0]) > 9000:
		return 0
	return int((rec as Array)[1])

func claim_engagement(threat: Node) -> void:
	if not is_instance_valid(threat):
		return
	var key := threat.get_instance_id()
	var n := engage_count(threat)
	_engaged[key] = [Time.get_ticks_msec(), n + 1]

## Whose part of the world this is. Culture varies by region rather than by
## anything the mission declares, so the props and the paint in a town match
## the country it stands in — and the country changes as you fly across the map.
func region_faction(x: float, z: float) -> String:
	var n := noise_cont.get_noise_2d(x * 1.7 + 90000.0, z * 1.7 - 40000.0)
	var m := noise_cont.get_noise_2d(z * 1.3 - 15000.0, x * 1.3 + 62000.0)
	# Which way the pair of noise fields points, not what they add up to.
	#
	# Averaging two noise samples and cutting the result into six equal value
	# bands looks even and is not: the sum of two roughly independent fields is
	# triangular, piled up in the middle, so the middle bands get nearly all the
	# map and the end ones get none. Measured over 20000 samples of the old
	# expression: Russia 45.7%, France 31.5%, China 12.5%, Britain 9.8%, the
	# United States 0.6% and Iran **zero**. Two of the six nationalities did not
	# exist anywhere in the world — no Iranian town, no Iranian ground, nowhere
	# for Iranian kit to be.
	#
	# The angle of the pair is very nearly uniform, because the joint
	# distribution is roughly radially symmetric, and it still moves smoothly
	# with position — so the regions stay large and organic instead of becoming
	# a checkerboard.
	var ang := atan2(m, n) / TAU + 0.5          # 0..1
	var pick := int(floor(ang * 6.0))
	match clampi(pick, 0, 5):
		0:
			return "usa"
		1:
			return "uk"
		2:
			return "france"
		3:
			return "russia"
		4:
			return "china"
		_:
			return "iran"

## Places worth flying to, and whose they are. Filled by the scenery.
var landmarks: Array = []

func register_landmark(nm: String, faction: String, at: Vector3, h: float) -> void:
	landmarks.append({"name": nm, "faction": faction, "at": at, "h": h})

## The stone a country builds in, near enough. Used for the landmarks so each
## one reads as belonging somewhere before you are close enough to see what it
## is.
func faction_colour(faction: String) -> Color:
	match faction:
		"france":
			return Color(0.42, 0.38, 0.34)
		"uk":
			return Color(0.58, 0.52, 0.40)
		"usa":
			return Color(0.52, 0.66, 0.60)
		"russia":
			return Color(0.66, 0.60, 0.52)
		"china":
			return Color(0.60, 0.46, 0.36)
		"iran":
			return Color(0.44, 0.56, 0.62)
		"free":
			# Independent towns: whitewash and pale timber, deliberately not
			# any of the national palettes.
			return Color(0.74, 0.71, 0.64)
		_:
			return Color(0.72, 0.68, 0.56)

func line_of_sight(from: Vector3, to: Vector3, skip := 0.0) -> bool:
	var span := from.distance_to(to)
	if span < 1.0:
		return true
	var t0: float = clampf(skip / span, 0.0, 0.9)
	var steps := clampi(int(span / 180.0), 6, 48)
	for i in range(1, steps):
		var f := float(i) / float(steps)
		if f < t0:
			continue
		var q: Vector3 = from.lerp(to, f)
		var g := height_at(q.x, q.z)
		# Ground under the sea masks nothing. Everything afloat sits at the
		# water line, so a sight line between two ships runs *below* it — and
		# the seabed is terrain, so a shoal a few metres proud of the ray
		# blocked two ships looking at each other across open water. What is
		# under the sea is under the sea; only what stands above it is in the
		# way.
		if g <= WATER_LEVEL:
			continue
		if q.y < g - 2.0:
			return false
	return true

## How far down a contact would have to go to break the line. Negative when it
## is already masked. Used by the AI to decide whether the terrain is worth
## hiding behind or whether it would just be flying into a valley for nothing.
func masking_depth(from: Vector3, to: Vector3) -> float:
	var span := from.distance_to(to)
	if span < 1.0:
		return 0.0
	var worst := 1e9
	var steps := clampi(int(span / 180.0), 6, 48)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var q: Vector3 = from.lerp(to, t)
		worst = minf(worst, q.y - height_at(q.x, q.z))
	return worst if worst < 1e8 else 0.0

## What to call a thing on screen. A node's `name` is not it: set before the
## node joins the tree, a name that collides with a sibling is replaced by Godot
## with a generated one, so the second Type 45 and the second patrol boat showed
## up on the radar as "@Node3D@194" and "@Node3D@197".
func label_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "—"
	if n.has_method("display_name"):
		return String(n.call("display_name"))
	var nm := String(n.name)
	return "contact" if nm.begins_with("@") else nm

func strength(action: StringName) -> float:
	return 0.0 if typing else Input.get_action_strength(action)

func held(action: StringName) -> bool:
	if _blocked.has(action):
		return false
	return not typing and Input.is_action_pressed(action)

## Discrete key presses, latched from the input event rather than polled.
##
## `Input.is_action_just_pressed` is true only during the frame the press was
## registered, and everything that reads it here does so from
## `_physics_process`. Physics runs at 120 Hz and the renderer does not, so a
## press could land between physics ticks and be gone before anyone looked —
## which is why T cycled targets *sometimes*. Latching the press when the event
## arrives and clearing it when somebody consumes it makes it exact: every press
## is seen once, and no press is seen twice.
var _taps := {}

## Buttons that were already down when something changed under them. A mouse
## press that launched the mission is still held on the first frame of it, and
## everything that reads the trigger by polling saw a shoot command the instant
## you arrived — so choosing a vehicle fired its weapon.
var _blocked: Dictionary = {}

func block_until_released(actions: Array) -> void:
	for a in actions:
		_blocked[a] = true
		_taps.erase(a)

func _process(_delta: float) -> void:
	if _blocked.is_empty():
		return
	for a in _blocked.keys():
		if not Input.is_action_pressed(a):
			_blocked.erase(a)

func _input(e: InputEvent) -> void:
	if typing or not (e is InputEventKey or e is InputEventMouseButton):
		return
	if e is InputEventKey and (e as InputEventKey).echo:
		return
	for a in InputMap.get_actions():
		if e.is_action_pressed(a):
			_taps[a] = Time.get_ticks_msec()

func tapped(action: StringName) -> bool:
	if typing or _blocked.has(action):
		return false
	var at: int = _taps.get(action, 0)
	if at == 0:
		return false
	_taps.erase(action)
	# A press nobody looked at for a quarter of a second was meant for a screen
	# that is no longer up; do not let it fire late.
	return Time.get_ticks_msec() - at < 250

# --------------------------------------------------------------------------
## What key an action is actually on, for anything that prints a control on the
## screen. The HUD carried its key labels as literal text, so when the
## countermeasures moved -- flares off N onto C, chaff off B onto V, to get the
## chaff off the bomb bay key -- the help page was updated and the flight strip
## was not. It went on telling you to press N and B for the rest of the sortie.
## Read the binding instead and it cannot drift again.
func key_label(action: StringName, fallback := "?") -> String:
	if not InputMap.has_action(action):
		return fallback
	for e in InputMap.action_get_events(action):
		var k := e as InputEventKey
		if k != null:
			return _key_name(k.physical_keycode)
	# nothing on the keyboard: say so rather than naming a key that is not bound
	for e2 in InputMap.action_get_events(action):
		if e2 is InputEventMouseButton:
			return "LMB" if (e2 as InputEventMouseButton).button_index \
				== MOUSE_BUTTON_LEFT else "RMB"
	return fallback

## Godot spells these out -- "Space", "Backslash", "BracketLeft" -- and a HUD
## strip has room for a glyph.
const _KEY_NAMES := {
	KEY_SPACE: "SPACE", KEY_ESCAPE: "ESC", KEY_TAB: "TAB",
	KEY_BACKSLASH: "\\", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]",
	KEY_APOSTROPHE: "'", KEY_SEMICOLON: ";", KEY_MINUS: "-", KEY_EQUAL: "=",
	KEY_SHIFT: "SHIFT", KEY_CTRL: "CTRL", KEY_ALT: "ALT", KEY_META: "CMD",
}

func _key_name(code: int) -> String:
	if _KEY_NAMES.has(code):
		return String(_KEY_NAMES[code])
	return OS.get_keycode_string(code).to_upper()

func _add(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.15)
	for e in events:
		InputMap.action_add_event(action, e)

## A gamepad button, and a stick axis with the half of it that is wanted.
## There was no joypad support at all: `InputEventJoypad` appeared nowhere, so a
## flight simulator was keyboard and mouse only.
func _btn(idx: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = idx
	return e

func _axis(idx: JoyAxis, sign_of: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = idx
	e.axis_value = sign_of
	return e

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mb(idx: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	return e

func _setup_input() -> void:
	# The stick, on the keyboard and on an actual stick. Left stick flies,
	# right stick looks, triggers work the guns, and the shoulders are the
	# throttle — the layout anything with two sticks already expects.
	_add(&"pitch_up",     [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_add(&"pitch_down",   [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_add(&"roll_left",    [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_add(&"roll_right",   [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_add(&"yaw_left",     [_key(KEY_Q), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)])
	_add(&"yaw_right",    [_key(KEY_E), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add(&"throttle_up",  [_key(KEY_SHIFT), _btn(JOY_BUTTON_RIGHT_SHOULDER)])
	_add(&"throttle_down",[_key(KEY_CTRL), _key(KEY_Z), _btn(JOY_BUTTON_LEFT_SHOULDER)])
	_add(&"brakes",       [_key(KEY_X)])
	_add(&"gear",         [_key(KEY_G)])
	_add(&"bay",          [_key(KEY_B)])
	_add(&"flaps",        [_key(KEY_F)])
	# Left click is the trigger, everywhere. Right click is deliberately NOT a
	# weapon: it is the sensor page chord with ALT, and having it also launch
	# meant reaching for the pod put a missile off the rail.
	_add(&"fire",         [_key(KEY_SPACE), _mb(MOUSE_BUTTON_LEFT), _btn(JOY_BUTTON_A)])
	# On foot the two have to come apart. `fire` carries both the space bar and
	# the left button because that is what a cockpit wants, but a man on the
	# ground jumps with one and shoots with the other -- bound together,
	# clicking made him jump instead of firing.
	_add(&"jump",         [_key(KEY_SPACE)])
	_add(&"foot_fire",    [_mb(MOUSE_BUTTON_LEFT)])
	# Sights and reload, on foot. The right button is the sensor page in a
	# cockpit and R is a submarine's ballast -- neither of which a man on the
	# ground has, so the keys are free where he is standing.
	_add(&"ads",          [_mb(MOUSE_BUTTON_RIGHT)])
	_add(&"reload",       [_key(KEY_R)])
	# V is the dedicated cannon key. It is off the mouse: left click already
	# pulls the trigger, and having both meant one click fired the gun and a
	# missile at the same time.
	# Moved off V, which the chaff now has. K is the only letter left free.
	_add(&"gun",          [_key(KEY_K), _btn(JOY_BUTTON_X)])
	_add(&"cycle_weapon", [_key(KEY_BACKSLASH), _btn(JOY_BUTTON_B)])
	_add(&"action_menu",  [_key(KEY_TAB), _btn(JOY_BUTTON_BACK)])
	_add(&"weapon_1",     [_key(KEY_1)])
	_add(&"weapon_2",     [_key(KEY_2)])
	_add(&"weapon_3",     [_key(KEY_3)])
	_add(&"weapon_4",     [_key(KEY_4)])
	# a loaded strike aircraft carries more than four types now
	_add(&"weapon_5",     [_key(KEY_5)])
	_add(&"weapon_6",     [_key(KEY_6)])
	_add(&"weapon_7",     [_key(KEY_7)])
	_add(&"weapon_8",     [_key(KEY_8)])
	_add(&"cycle_target", [_key(KEY_T), _btn(JOY_BUTTON_Y)])
	# C is flares now, so the view moved to P. Night vision wanted a key that
	# works in every seat and every view, and N was the obvious one.
	_add(&"camera",       [_key(KEY_P), _btn(JOY_BUTTON_RIGHT_STICK)])
	_add(&"night_vision", [_key(KEY_N)])
	_add(&"look_back",    [_key(KEY_Z)])
	_add(&"freelook",     [_key(KEY_ALT), _key(KEY_META)])
	_add(&"interact",     [_key(KEY_U)])
	_add(&"crouch",       [_key(KEY_CTRL), _key(KEY_C)])
	_add(&"panel_left",   [_key(KEY_BRACKETLEFT)])
	_add(&"panel_right",  [_key(KEY_BRACKETRIGHT)])
	_add(&"laser",        [_key(KEY_L)])
	# Lights share the laser's key. The laser is only meaningful with the sensor
	# page up, and the lamp only matters when it is not, so the one key does
	# whichever of the two makes sense where you are.
	_add(&"lights",       [_key(KEY_L)])
	# Not G: that is the landing gear, and on the gunship the two fought over
	# the same key — you could not raise the gear without being thrown into the
	# battery, or take the battery without cycling the gear.
	_add(&"gunner_station", [_key(KEY_J)])
	_add(&"radar_out",    [_key(KEY_EQUAL)])
	_add(&"radar_in",     [_key(KEY_MINUS)])
	# Depth, on the two keys directly above one another: R rises, F floods.
	# Page Up and Page Down are nowhere near the hand that is already on the
	# helm. A submarine reads none of the aircraft actions these share a key
	# with -- it has no flaps and no gun -- and an aeroplane never dives or
	# surfaces, so the pairs cannot both be live on the same vehicle.
	_add(&"dive",         [_key(KEY_F)])
	_add(&"surface",      [_key(KEY_R)])
	_add(&"pause_menu",   [_key(KEY_ESCAPE), _btn(JOY_BUTTON_START)])
	_add(&"assist",       [_key(KEY_H)])
	# Countermeasures together under the left hand. Chaff was on B, which is
	# also the bomb bay -- so every bundle of chaff opened the bay doors.
	_add(&"flare",        [_key(KEY_C), _btn(JOY_BUTTON_DPAD_UP)])
	_add(&"chaff",        [_key(KEY_V), _btn(JOY_BUTTON_DPAD_DOWN)])
	_add(&"mouse_fly",    [_key(KEY_SEMICOLON)])
	_add(&"map",          [_key(KEY_M), _key(KEY_F1)])
	# Not backslash: `cycle_weapon` is already there, and `tapped` erases the
	# press when it is read, so whichever of the two was polled first that frame
	# ate the other. Cycling the weapon and slowing time fought over one key.
	_add(&"time_slow",    [_key(KEY_APOSTROPHE)])
