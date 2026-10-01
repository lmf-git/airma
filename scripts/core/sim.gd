extends Node
## Global services: input map bootstrap, the analytic terrain field, mission
## configuration and scoring. Autoloaded as `Sim`.

const WORLD_HALF := 600000.0     # world extends +/- 600 km
const COAST_X := 15000.0         # open water east of here
# ------------------------------------------------------------------ planet
## The world is a cap of a sphere, not a plane.
##
## The centre sits one radius BELOW the origin, so a point on the surface is
## near y = 0 and every position in the world stays inside a hundred kilometres
## or so. That is the whole trick: a real 6371 km radius expressed directly in
## 32-bit floats leaves well under a metre of precision, which is why curved
## worlds normally need a floating origin. Put the centre underneath instead and
## the numbers stay small while the geometry stays honest.
##
## Everything else follows from one function: how far the surface falls below
## the tangent plane at a horizontal distance, which for small angles is exactly
## the sagitta d^2/2R. Subtract it in `height_at` and every one of the two
## hundred odd places that ask where the ground is gets a curved world without
## knowing anything about it.
const PLANET_R := 6_371_000.0
var planet_centre := Vector3(0.0, -PLANET_R, 0.0)

func planet_drop(x: float, z: float) -> float:
	if globe:
		# Exact, because on the planet this is asked at any range. The parabola
		# is the first term of it and holds to thirty metres over the theatre;
		# fifteen thousand kilometres out it is wrong by seven thousand.
		return PLANET_R * (1.0 - cos(sqrt(x * x + z * z) / PLANET_R))
	return (x * x + z * z) / (2.0 * PLANET_R)

## Which way is up here. Away from the centre, which over this world tilts by
## about eight tenths of a degree at the far edge.
## Which way the planet's north pole lies.
##
## Not the same axis the world is a cap on. The theatre sits at the *top* of the
## sphere in world coordinates, but that is a fact about where the cap was put,
## not about the planet's geography: `z` is north-south -- it is what the
## climate bands run along -- so the pole is on the z axis and the airfield is
## on the equator, which is what it has always been climatically.
##
## Negative z, because the flat chart draws increasing z *down* the screen. Get
## this backwards and the globe comes out with the world's north at the bottom.
const PLANET_NORTH := Vector3(0.0, 0.0, -1.0)

# ------------------------------------------------------------------ the chart
#
# Everything in this game asks the world for ground with two numbers, `x` and
# `z`, and there are thousands of those calls. On a flat world they are world
# coordinates. On a planet they cannot be -- a sphere has no flat coordinates --
# but they can be something almost as convenient: *surface offsets from a chart
# origin*, measured along the ground.
#
# That is the hinge the whole spherical world turns on. `height_at(x, z)` keeps
# its signature and its meaning ("the ground this far east and this far south of
# where the chart is centred"), so the aeroplane, the missiles, the vehicles and
# the AI do not have to know the world is round. What changes is only what the
# pair is turned into before the field is asked: a direction from the planet's
# centre, which is what a planetary field is a function of.
#
# The projection is azimuthal equidistant about the origin -- distances along the
# ground from the middle of the chart are exact, which is the property every
# range readout, weapon envelope and turn radius in the game depends on. Away
# from the origin it stretches, like every projection; over the 1200 km the
# theatre covers, that stretch is under a tenth of a per cent.
#
# The origin is fixed at the theatre for now, so `chart_to_dir` reproduces the
# existing world exactly and nothing moves. Making it follow the player is what
# turns the rest of the planet into somewhere you can fly to, and it is the next
# thing this needs.
var chart_origin := Vector3.UP
var chart_east := Vector3.RIGHT
var chart_south := Vector3(0.0, 0.0, 1.0)

## The world is a planet.
##
## It was a flag and a second world for as long as the planet was being built
## next to the flat one; it is the world now. The same `(x, z)` pair is read on
## the chart, the ground under it comes from the planetary field, and what has
## been built on it is carved in wherever it stands.
##
## `--flat` still gets the old 1200 km height field with nothing outside it,
## because a good deal of measurement is written against it and a world you can
## compare against is worth keeping.
var globe := true

## Put the chart somewhere else on the planet. East and south are worked out
## from the planet's own axis, so the chart is always the right way up.
func set_chart(dir: Vector3) -> void:
	chart_origin = dir.normalized()
	var north: Vector3 = -PLANET_NORTH
	# At the poles the axis and the origin are the same line and there is no
	# bearing; any consistent frame will do there.
	var e: Vector3 = chart_origin.cross(north)
	if e.length() < 1e-6:
		e = chart_origin.cross(Vector3.RIGHT)
	chart_east = e.normalized()
	chart_south = chart_east.cross(chart_origin).normalized()
	# The extension does the conversion on its own side, once per call rather
	# than once per sample, so it has to be told where the chart is.
	if native == null and globe:
		push_warning("chart set before the extension exists: the router will "
			+ "survey the flat field while the ground is a planet")
	if native != null:
		native.set_globe(globe)
		native.set_chart(chart_origin, chart_east, chart_south, PLANET_R)

## Chart coordinates to a direction from the planet's centre. `x` is metres east
## along the ground and `z` metres south, which is the sense the flat map has
## always drawn.
func chart_to_dir(x: float, z: float) -> Vector3:
	var s: float = sqrt(x * x + z * z)
	if s < 1e-6:
		return chart_origin
	var ang: float = s / PLANET_R
	var t: Vector3 = (chart_east * (x / s) + chart_south * (z / s)).normalized()
	return (chart_origin * cos(ang) + t * sin(ang)).normalized()

## And back again. Exact inverse of `chart_to_dir` over the near hemisphere.
func dir_to_chart(d: Vector3) -> Vector2:
	var u := d.normalized()
	var c: float = u.dot(chart_origin)
	var t: Vector3 = u - chart_origin * c
	var tl: float = t.length()
	if tl < 1e-12:
		return Vector2.ZERO
	# atan2 of the perpendicular against the parallel, not acos of the parallel.
	# Near the origin `c` is within a float's last digit of 1 and acos throws the
	# answer away: a point one kilometre out came back as the origin itself.
	var ang: float = atan2(tl, c)
	t /= tl
	var s: float = ang * PLANET_R
	return Vector2(t.dot(chart_east) * s, t.dot(chart_south) * s)

## How cold a place is for being where it is, from 0 at the equator to 1 at the
## pole. What the climate bands are cut from.
##
## On the flat world this was `|z|` over most of the map's half width, which is
## the last piece of the authored square in the biome system: it is a function
## of the *chart*, so moving the chart under a fixed piece of ground changes its
## climate, and 1200 km of world was made to span pole to equator.
##
## On the planet it is the real latitude -- so the poles are cold, the equator
## is hot, and a place keeps its climate whoever is looking at it -- multiplied
## by a compression that is written down rather than hidden.
##
## Barely compressed at all, in the end. The tempting number is a large one --
## the whole 1200 km world is 5.4 degrees of a real planet, and 5.4 degrees of
## anywhere is one climate, so squeezing hard gives the ground the variety the
## flat world had. Seven and a half does that and it makes the *planet* absurd:
## snow beyond six degrees of latitude, which is 89 per cent of the surface, and
## a globe that is white from pole to pole with a green fleck on it.
##
## At 1.15 the snow line sits at 44 degrees and the ice covers 30 per cent, which
## is a cold but believable world. The country you fly over is then warm, and its
## variety comes from moisture and from height -- which is where a real place's
## variety comes from over 1200 km, latitude having almost nothing to say across
## five degrees of it.
## Where the climate scale reaches 1, as a fraction of the way to the pole.
##
## The scale is the sine of the latitude times this, so 1 lands at the polar
## circle -- and where the polar circle is, is a fact about the axial tilt: it
## is the latitude beyond which the sun does not set at midsummer, which is
## ninety degrees less the obliquity. This was 1.15, chosen because it looked
## right; it is now the same number the planet's tilt says it should be, so the
## climate bands and the seasons come from one fact instead of two.
##
## Mirrored in `sphere::CLIMATE_SQUEEZE`, which `--suntest` checks.
const CLIMATE_SQUEEZE := 1.0899
## How much warmer midsummer is than midwinter at the pole, on the 0..1 scale
## the biome rule works in. Mirrored in `sphere::SEASON_AMP`.
const SEASON_AMP := 0.12
## Where the planet is in its year: +1 at northern midsummer, -1 at northern
## midwinter. Set from the clock, which is what owns the sun.
var season := 0.0

## What the season is worth in temperature at a place.
##
## Nothing at the equator, most at the poles, and opposite signs either side of
## the line -- which is the whole of the difference between one hemisphere
## having winter and both of them having it at once.
func season_warmth(x: float, z: float) -> float:
	if not globe:
		return 0.0
	return season * chart_to_dir(x, z).dot(PLANET_NORTH) * SEASON_AMP

func climate_lat(x: float, z: float) -> float:
	if not globe:
		return clampf(absf(z) / (WORLD_HALF * 0.85), 0.0, 1.0)
	var d := chart_to_dir(x, z)
	return clampf(absf(d.dot(PLANET_NORTH)) * CLIMATE_SQUEEZE, 0.0, 1.0)

## Carry the built world across when the chart moves.
##
## The floating origin renumbers everything that is *somewhere*, and the roads,
## the towns and the aerodromes are somewhere. They are stored as chart pairs,
## which means that left alone they do not stay where they are when the chart
## moves -- they move with it, and the airfield ends up a hundred and fifty
## kilometres from the airfield. Measured before this existed: 44 of 120 places
## came back with a different biome after a rechart, because the carving under
## them had walked off across the planet.
##
## Only positions are carried. A profile height is an elevation above sea level
## in the flat frame, and that is the same number wherever the chart is.
func rechart_world(o: Vector3, e: Vector3, s2: Vector3) -> void:
	var move := func(p: Vector2) -> Vector2:
		var d: float = sqrt(p.x * p.x + p.y * p.y)
		if d < 1e-6:
			return dir_to_chart(o)
		var ang: float = d / PLANET_R
		var t: Vector3 = (e * (p.x / d) + s2 * (p.y / d)).normalized()
		return dir_to_chart((o * cos(ang) + t * sin(ang)).normalized())
	for i in ROADS.size():
		var r: Array = ROADS[i]
		ROADS[i] = [move.call(r[0]), move.call(r[1])]
	for li in _road_lines.size():
		var line: PackedVector2Array = _road_lines[li]
		var out := PackedVector2Array()
		for p in line:
			out.append(move.call(p))
		_road_lines[li] = out
	for pad in _town_pads:
		pad["c"] = move.call(pad["c"] as Vector2)
	for f in fields:
		f["at"] = move.call(f["at"] as Vector2)
	for coll in [road_bridges, road_tunnels]:
		for b in coll:
			b["a"] = move.call(b["a"] as Vector2)
			b["b"] = move.call(b["b"] as Vector2)
			var pts: PackedVector2Array = b.get("pts", PackedVector2Array())
			var np := PackedVector2Array()
			for p2 in pts:
				np.append(move.call(p2))
			b["pts"] = np
	_index_corridor()
	_push_segments()
	_push_world()

## Latitude of a point on the ground, in radians: zero at the airfield, positive
## toward the top of the chart. Real, in the sense that it is the angle at the
## planet's centre -- the whole 1200 km world is inside five and a half degrees
## of the equator, which is what a 1200 km world on a 6371 km planet is.
func latitude_at(x: float, z: float) -> float:
	var u := Vector3(x, sqrt(maxf(PLANET_R * PLANET_R - x * x - z * z, 0.0)), z)
	return asin(clampf(u.normalized().dot(PLANET_NORTH), -1.0, 1.0))

func up_at(p: Vector3) -> Vector3:
	return (p - planet_centre).normalized()

## Height above the sphere, not above the y = 0 plane. Sixty kilometres out
## those differ by 283 m.
func altitude(p: Vector3) -> float:
	return p.distance_to(planet_centre) - PLANET_R

func gravity_at(p: Vector3) -> Vector3:
	return -up_at(p) * 9.81

## Sea level at a point. The ocean is a shell, so it falls away with everything
## else — a flat sea plane against curved ground would flood the far half of the
## map. This is the MEAN surface: the swell rides on top of it.
func sea_at(x: float, z: float) -> float:
	return WATER_LEVEL - planet_drop(x, z)

# -------------------------------------------------------------------- swell
## Two long crossing swells, five hundred metres from crest to crest and a
## couple of metres high. Defined here and nowhere else: the water shader is
## handed the same constants and the same clock, so what a hull rides is exactly
## what you can see it riding. A sea drawn by one formula and floated on by
## another is worse than a flat one.
## Three components, because a real sea is a spectrum and one wavelength is
## not. Two long swells crossing at 450 and 400 m carry the heave; a 70 m chop
## on top of them is what a small hull actually pitches to. Without the short
## one every ship behaved the same — a 500 m swell is so long that a 47 m boat
## and a 257 m assault ship both simply follow it, and the size of the hull
## stopped meaning anything.
##
## The frequencies are not free: in deep water omega = sqrt(g*k), so a long wave
## is slow and a short one quick. Setting them by eye gives a sea where the big
## swell hurries and the chop crawls, which reads as wrong even if you cannot
## say why.
const SWELL_A := 1.25            # metres, the long swell    (454 m, 17.1 s)
const SWELL_B := 0.75            # crossing it               (401 m, 16.0 s)
const SWELL_C := 0.42            # the chop on top           ( 70 m,  6.7 s)
const SWELL_KA := Vector2(0.01210, 0.00670)
const SWELL_KB := Vector2(-0.00740, 0.01380)
const SWELL_KC := Vector2(0.06200, 0.06500)
const SWELL_WA := 0.368
const SWELL_WB := 0.392
const SWELL_WC := 0.939
## Advanced by the world, not read from the engine's clock, so the shader and
## the physics cannot drift apart across a pause or a frame spike.
var sea_time := 0.0

func wave_at(x: float, z: float) -> float:
	return SWELL_A * sin(SWELL_KA.x * x + SWELL_KA.y * z + sea_time * SWELL_WA) \
		+ SWELL_B * sin(SWELL_KB.x * x + SWELL_KB.y * z + sea_time * SWELL_WB) \
		+ SWELL_C * sin(SWELL_KC.x * x + SWELL_KC.y * z + sea_time * SWELL_WC)

## The surface a hull actually floats on: the shell plus the swell riding on it.
func sea_surface(x: float, z: float) -> float:
	return sea_at(x, z) + wave_at(x, z)

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
## Whose ground it is. Deliberately not the continental field: that one carries
## three fractal octaves because coastlines want the detail, and an *angle*
## taken from a field with detail in it flips every few kilometres. Nations came
## out as a 16 km checkerboard rather than as territories.
var noise_faction := FastNoiseLite.new()
## And whose ground it is on the planet.
##
## A separate field because it has to be sampled on the *direction*, not on the
## chart pair. Territory belongs to the planet: read off the pair it would move
## under your feet every time the chart did, and the country you were standing
## in would change because you flew a hundred and fifty kilometres.
var noise_faction3 := FastNoiseLite.new()
## Temperature and moisture on the planet, matching `sphere::climate` in the
## extension exactly: same seeds, same octaves, same frequencies on the unit
## sphere. Two copies of one rule, and they have to stay one rule.
var noise_temp3 := FastNoiseLite.new()
var noise_moist3 := FastNoiseLite.new()
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
	noise_faction.seed = 20260903
	noise_faction.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# One octave, and slow: a feature is most of the width of the world, so a
	# nation holds a piece of ground you can fly across rather than a patch.
	# Measured by walking lines across the world and counting how far one flag
	# lasts, this takes the mean run from 22 km to 95 km and the median from
	# 16 km to 80 km, with the six shares still even -- 13 to 20 per cent each.
	noise_faction.frequency = 0.0000024
	noise_faction.fractal_octaves = 1
	noise_faction3.seed = 20260903
	noise_faction3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# On the unit sphere, so a frequency is a number of features round the
	# planet rather than a size in metres. Measured rather than derived: 19.5
	# puts a border about every 89 km of surface, against the 95 km the flat
	# world was tuned to. The first estimate of 68 was out by three and a half
	# times and gave 27 km -- a checkerboard again, on a planet this time.
	noise_faction3.frequency = 19.5
	noise_faction3.fractal_octaves = 1
	noise_temp3.seed = 515
	noise_temp3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_temp3.frequency = 40.0
	noise_temp3.fractal_octaves = 2
	noise_moist3.seed = 811
	noise_moist3.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moist3.frequency = 29.0
	noise_moist3.fractal_octaves = 3

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
	# In the flat frame, like the decks and for the same reason: this number is
	# handed to the extension, which levels the field on the plane and knows
	# nothing about the planet. `height_at` drops the result afterwards, so a
	# curved elevation stored here would have the drop taken off it twice --
	# and it was, leaving the opposing airfield's pavement in a 471 m crater.
	var e := elev
	if e == INF:
		_siting = true
		e = height_at(at.x, at.y) + planet_drop(at.x, at.y)
		_siting = false
	var f := {"at": at, "yaw": yaw, "elev": e}
	fields.append(f)
	# Straight over to the extension: the aerodrome is part of the height field
	# now, and everything that asks for a block of ground -- a terrain chunk, a
	# road profile, the map -- gets it applied there rather than looping over
	# the list again on this side.
	_push_world()
	return f

## Put the home field back on the land it is actually standing on.
##
## `RUNWAY_ELEV` is zero, which was right for as long as the world was flat and
## the home strip sat at sea level by definition. On the planet the chart is put
## on a country, and that country's ground is wherever the generator left it --
## 516 m up for the one this started on. Levelling the field to zero there does
## not lower the runway, it tells the extension to cut the whole aerodrome down
## through half a kilometre of hill, and the road network then runs down into
## the hole to meet it. Both the field test and the road test were reading the
## same 516 m.
##
## Called once the chart is on the chosen country, because until then there is
## no land under (0, 0) to ask about.
func resite_home_field() -> void:
	if not globe or fields.is_empty():
		return
	var f: Dictionary = fields[0]
	var at: Vector2 = f["at"]
	# As `register_field` samples: with the fields held off, so the strip takes
	# the natural height of its site rather than the height it has already been
	# levelled to.
	_siting = true
	f["elev"] = height_at(at.x, at.y) + planet_drop(at.x, at.y)
	_siting = false
	_push_world()

## A field's pavement as a world height. `elev` is stored flat because the
## extension levels the field there; this is that pavement once it has been
## dropped onto the sphere, which is what anything standing on it wants. Pass a
## point to get the height under that point: a runway follows the curve, so a
## strip three kilometres long is 37 m lower at the ends 78 km out -- tilted by
## the same eight tenths of a degree that gravity is.
func field_elev(fd: Dictionary, x := INF, z := INF) -> float:
	var at: Vector2 = fd["at"]
	var px: float = at.x if is_inf(x) else x
	var pz: float = at.y if is_inf(z) else z
	return float(fd["elev"]) - planet_drop(px, pz)

## The countries, and which one you are flying for.
##
## There is no centre to this planet and no main airfield on it. Each side has a
## country somewhere on the globe -- the same six the ground is divided between
## -- and starting a mission means starting in one of them. The chart is then
## centred on that country's aerodrome, which is what makes it *the* aerodrome
## for that sortie: the world is built around wherever you began.
##
## Where they are is `sphere::HOMELANDS` in the extension, which is also what
## raises the land under them; this side keeps only the names and their order.
## It was two tables once, and the copies disagreed about which way north was.
## The names, in the order the extension has them. Positions live there; this
## side only needs to know which country is which.
const HOMELAND_ORDER := ["usa", "uk", "france", "russia", "china", "iran"]
const HOMELANDS := {
	"usa": 0, "uk": 1, "france": 2, "russia": 3, "china": 4, "iran": 5,
}
## Whose side you are on. Chosen before the world is built, because the world is
## built around it.
var home_faction := "usa"

## A country's direction from the planet's centre.
##
## Asked of the extension rather than worked out here. This was a second copy of
## `sphere::HOMELANDS` with its own trigonometry, and the copy had north's sign
## the other way round: every country came out at the mirror of its own
## latitude, so the game asked about six places the generator had never raised
## land at and found three of them under the sea. The list below is names and
## the order they are in; where they *are* is the extension's business.
func homeland_dir(who: String) -> Vector3:
	if native == null:
		return Vector3.UP
	return native.homeland_dir(HOMELAND_ORDER.find(who) if HOMELAND_ORDER.has(who)
		else 0)

## Where this sortie begins. The chart is put here before anything is built.
func home_dir() -> Vector3:
	return homeland_dir(home_faction) if globe else Vector3.UP

## The landmass the world is built on.
##
## A settlement is not merely somewhere dry. On a flat world with one continent
## in it that distinction never came up; on a planet it is the difference
## between a trunk network and a trunk network that crosses an ocean, because
## the router will dutifully connect any two towns it is given and the survey
## does something desperate when it has to. Measured, towns on separate
## landmasses gave a design surface 280 m off the ground and gradients over
## 300 %.
##
## A flood fill over a coarse grid, out from the airfield, across land. One
## batched call to the extension for the heights and then a breadth-first walk:
## a few hundred thousand cells is nothing once the heights are not fetched one
## at a time.
const LAND_N := 512
const LAND_HALF := 768_000.0
var _land_mask := PackedByteArray()

func build_landmass() -> void:
	# The grid, the waterline and the fill, in one call.
	#
	# It was a quarter of a million cells thresholded here and then a flood fill
	# over the same quarter million that built a fresh array of the four
	# neighbour offsets for every cell it visited. Measured, 334 ms of a four
	# second cold start, and not one decision in any of it.
	_land_mask = native.landmass(LAND_HALF, LAND_N)
	if _land_mask.is_empty():
		push_warning("the airfield is not on land: no landmass to build on")

## Is this point on the same land as the airfield? True everywhere if the fill
## has not been run, so nothing is refused a site for want of an answer.
func on_home_land(x: float, z: float) -> bool:
	if _land_mask.is_empty():
		return true
	if absf(x) >= LAND_HALF or absf(z) >= LAND_HALF:
		return false
	var cell: float = LAND_HALF * 2.0 / float(LAND_N)
	var i := int((x + LAND_HALF) / cell)
	var j := int((z + LAND_HALF) / cell)
	return _land_mask[clampi(j, 0, LAND_N - 1) * LAND_N
		+ clampi(i, 0, LAND_N - 1)] == 1

## How much of the world is the landmass the airfield stands on, as a fraction
## of everything above water. Reported rather than gated: a world whose one
## continent is a tenth of its land is a world where most towns have nowhere to
## be, and that is worth seeing.
func landmass_share() -> float:
	if _land_mask.is_empty():
		return 1.0
	var on := 0
	for v in _land_mask:
		if v == 1:
			on += 1
	return float(on) / float(LAND_N * LAND_N)

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
	# ...and then dropped onto the sphere. The extension builds the field on a
	# plane and knows nothing about the planet; this is the single point where
	# a flat height becomes a height on a curved world.
	if globe:
		# The planetary field already carries the curve, so there is no drop to
		# take off here: it is a height on a round world, not a flat one bent.
		#
		# With the flags, like the flat world. Asked without them, a surveyor
		# siting an aerodrome read the ground with that aerodrome already
		# levelled into it and got back the elevation it was trying to choose.
		var fl: int = _ground_flags()
		if fl == G_ALL:
			return _deck_top(native.ground_globe(x, z), x, z)
		return _deck_top(native.ground_globe_flags(x, z, fl), x, z)
	return _deck_top(native.ground(x, z, _ground_flags()), x, z) - planet_drop(x, z)

## Ground height in the flat frame -- the height a surveyor works in, taken from
## the local horizontal rather than from world level. On a sphere the two part
## company by the drop, and the difference is not a slope anybody has to climb:
## a dead level road 138 km out reads as a 2.2 % gradient in world coordinates
## and the whole network reads as 1.5 % off camber. Gradients, cross falls and
## earthworks are set out against local up, so they are measured here.
func survey_height_at(x: float, z: float) -> float:
	return height_at(x, z) + planet_drop(x, z)

## A landable platform standing over the ground. Applied here rather than in
## the extension because it is the one part of the world that is not fixed once
## it is built -- a carrier under way carries its deck with it.
func _deck_top(h: float, x: float, z: float) -> float:
	if decks.is_empty():
		return h
	# A deck is registered in the flat frame, because on the flat world the drop
	# is taken off everything afterwards. On the planet nothing is taken off --
	# the field already carries the curve -- so the deck has to be dropped here
	# instead, or a carrier forty kilometres out lands aeroplanes forty-five
	# metres above its own flight deck.
	if globe:
		return maxf(h, deck_height(x, z) - planet_drop(x, z))
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

## Ground, slope and grip under a set of wheels at once: five numbers each --
## the height, the three of the normal, and the grip -- in the order they came
## in. `radii` says how big each wheel is, which is what decides whether it is
## touching: one in the air is given its height and nothing else.
##
## This is `height_at`, `normal_at` and `surface_grip` asked together, because
## asked apart they are six crossings of the extension boundary per wheel. A
## tank has fourteen road wheels and a sector holds forty-five vehicles, all of
## them integrating at 120 Hz: measured, forty-five thousand crossings a frame
## and 87 ms of a hundred millisecond frame, which the physics then spends
## twelve steps catching up on. One crossing a vehicle a step instead.
func wheel_ground(pts: PackedVector3Array,
		radii: PackedFloat64Array) -> PackedFloat64Array:
	return native.wheel_ground(pts, radii)

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

## The routed trunk lines, as chart polylines. Read-only to everything outside;
## the map and the tests both want to see the network as it was laid.
func road_lines() -> Array:
	return _road_lines
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
	var r: Vector3 = native.road_surface_at(x, z)
	# x is the corridor's running surface and comes back in the extension's flat
	# frame; everything that compares it against the ground wants it on the
	# sphere, the same as `height_at`. y is a weight and is left alone.
	r.x -= planet_drop(x, z)
	return r

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

## Hand the decks to the extension, which is where the terrain mesh is built.
##
## A deck is the one part of the world that moves, so it cannot be published
## once with the roads and the aerodromes: it is pushed over just before the
## work that reads it goes out. Cheap -- there are never more than a handful --
## and the alternative is the mesher crossing back into script for every one of
## the nine hundred heights a chunk asks for.
func push_decks() -> void:
	var flat := PackedFloat32Array()
	flat.resize(decks.size() * 7)
	var at := 0
	for d in decks:
		var o: Vector3 = d["origin"]
		var hf: Vector2 = d["half"]
		flat[at] = o.x
		flat[at + 1] = o.z
		flat[at + 2] = d["cos"]
		flat[at + 3] = d["sin"]
		flat[at + 4] = hf.x
		flat[at + 5] = hf.y
		flat[at + 6] = d["y"]
		at += 7
	native.set_decks(flat)

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

## Level the ground under each settlement, and report which sites survived it.
func register_town_pads(sites: Array) -> Array:
	_town_pads.clear()
	var kept: Array = []
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
				# In the flat frame, because this platform is handed to the
				# extension and stamped into the field there -- the same reason
				# an aerodrome's elevation is. Levelled to a curved height it
				# was dug in by the drop: a town 130 km out sat at the bottom
				# of a 1330 m pit, and the trunk roads reaching it inherited
				# gradients that no survey had asked for.
				total += survey_height_at(q.x, q.y)
				n += 1
		var y: float = (total / maxf(float(n), 1.0)) if n > 0 \
			else survey_height_at(c.x, c.y)
		# A town is not a reason to raise land out of the sea.
		#
		# This used to clamp the platform to at least eight metres above the
		# water, which on a world where every site was dry by construction was a
		# harmless floor. On a generated planet it is a licence to build: a site
		# whose ground averages below sea level got a pad above it anyway, and
		# the field obligingly lifted an island out of the ocean to stand one
		# small town on. Sites that are not already land are dropped, and the
		# caller is told which so it does not build a town on a pad that is not
		# there.
		if y < WATER_LEVEL + 8.0:
			continue
		kept.append(site)
		_town_pads.append({"c": c, "r": r, "y": y})

## Mean gradient over a footprint, as a fraction. Used to choose where a town
## goes: the flattest workable ground within reach of where it was wanted.
	return kept

func site_roughness(c: Vector2, r: float) -> float:
	return site_roughness_many(PackedVector2Array([c]),
		PackedFloat64Array([r]))[0]

## The same for a whole list of candidates, which is how it is actually asked.
##
## The measure is 49 stations, each a normal, each of those four heights: 196
## crossings of the extension boundary for one candidate, and siting the world's
## settlements tries forty-nine candidates for each of forty-eight of them.
## Measured, four hundred and sixty thousand crossings and 550 ms of a four
## second cold start -- the largest single thing in laying out the road network.
## Asked as a list it is one crossing and the stations run across every core.
func site_roughness_many(centres: PackedVector2Array,
		radii: PackedFloat64Array) -> PackedFloat64Array:
	return native.roughness_at(centres, radii)

## Which trunk road each of these points would run out to meet.
##
## The whole network against every point, which is what it has to be -- but the
## network is twenty-nine thousand legs and walking it in script once per town
## was 156 ms of every launch, cached network or not.
func nearest_trunk_many(pts: PackedVector2Array) -> PackedVector2Array:
	var flat := PackedFloat32Array()
	flat.resize(ROADS.size() * 4)
	var w := 0
	for r in ROADS:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		flat[w] = a.x
		flat[w + 1] = a.y
		flat[w + 2] = b.x
		flat[w + 3] = b.y
		w += 4
	return native.nearest_on_lines(flat, pts)

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
func biome_weights(x: float, z: float, y_in: float, slope: float,
		cl: Vector2 = Vector2(-1.0, -1.0)) -> PackedFloat32Array:
	# Height above the sea under this point, not the world `y`.
	#
	# The two are the same on a flat world and they are not on a planet: the
	# ground falls away from the middle of the chart, so a fixed place has a
	# different `y` depending on where the chart is centred, and its climate
	# moved with it. Measured, 44 of 120 places came back with a different
	# biome after the chart was moved 150 km. Elevation above the local sea is
	# the same number from any chart.
	var y: float = y_in - sea_at(x, z) + WATER_LEVEL
	# Latitude first, weather second. Without a band running with the map there
	# is no reason for the far north to be colder than the middle, so climate
	# was noise alone and the world had no geography to it — the same patchwork
	# everywhere. `z` is north-south, so this is the only term that can make a
	# pole cold and a middle latitude hot.
	var lat: float = climate_lat(x, z)
	var band: float = 1.0 - lat * 1.25
	# the dry belts sit either side of the hot middle, the way they do on Earth
	var belt: float = clampf(1.0 - absf(lat - 0.32) * 3.0, 0.0, 1.0)
	# The same pair the ground shader reads, and on the planet the same field:
	# sampled on the chart the climate slides out from under a place whenever
	# the chart moves off it.
	var nt: float = cl.x
	var nm: float = cl.y
	if nt < 0.0 or nm < 0.0:
		if globe:
			# Their own fields, at their own frequencies.
			#
			# Scaling the *coordinates* by forty and handing them to the flat
			# world's noise -- which carries a frequency of 6.2e-6 -- asks for
			# features a hundred and sixty thousand times too large, and gets
			# back very nearly a constant. The extension bakes the texture with
			# a frequency of forty on the unit sphere, so this has to be the
			# same field or the map and the ground disagree about the weather.
			var cd := chart_to_dir(x, z)
			nt = (noise_temp3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
			nm = (noise_moist3.get_noise_3d(cd.x, cd.y, cd.z) + 1.0) * 0.5
		else:
			nt = (noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
			nm = (noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
	var temp: float = clampf(band * 0.70 + nt * 0.42
		- clampf((y - 300.0) / 2200.0, 0.0, 1.0) * 0.85
		+ season_warmth(x, z), 0.0, 1.0)
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
	var n: float
	var m: float
	if globe:
		# On the planet, and of the planet: the same piece of ground answers the
		# same way whatever chart is looking at it.
		var d := chart_to_dir(x, z)
		n = noise_faction3.get_noise_3d(d.x, d.y, d.z)
		m = noise_faction3.get_noise_3d(d.z + 4.0, d.x - 2.0, d.y + 7.0)
	else:
		n = noise_faction.get_noise_2d(x + 90000.0, z - 40000.0)
		m = noise_faction.get_noise_2d(z - 15000.0, x + 62000.0)
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
	return native.sight_lines(PackedVector3Array([from]),
		PackedVector3Array([to]), skip)[0] != 0

## The same for a whole list of sight lines at once.
##
## The march is up to forty-eight height queries, and asked one line at a time
## each of those is its own crossing of the extension boundary. The head-up
## display's radar scope asks it of every contact on the scope every frame:
## fourteen aircraft in a fight is seven hundred crossings a frame, and measured
## that one panel was 1.0 ms of a 13 ms frame. Asked as a list it is one
## crossing and the marches run across every core.
func lines_of_sight(from: PackedVector3Array, to: PackedVector3Array,
		skip := 0.0) -> PackedByteArray:
	return native.sight_lines(from, to, skip)

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

## The sea's own clock, advanced with the physics rather than with the frame.
##
## A hull floats in `_physics_process` and reads the swell there. Advanced on
## render frames, the clock could be several frames ahead or behind of what the
## hull last saw -- headless especially, where the two rates are not tied -- and
## a test that asks where the surface is *now* disagrees with a hull that
## settled to where it was *then*. Measured, that drift reached 0.1 m against a
## swell that only moves 8 mm in a tick. One clock, stepped once, and the
## question has one answer.
func _physics_process(delta: float) -> void:
	sea_time += delta

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
# ------------------------------------------------------------- the frame budget
#
# Where the frame goes, measured rather than guessed.
#
# A profiler that is always on is a tax on every frame it measures, and one that
# is never on means optimising by argument. This is two `Time.get_ticks_usec()`
# calls around a block, skipped entirely unless something asked for them, and it
# reports in the same units the frame is spent in.
var profiling := false
var _prof: Dictionary = {}
var _prof_n: Dictionary = {}
var _prof_frames := 0

## Start timing a block. Returns the stamp to hand back to `prof_end`.
func prof_at() -> int:
	return Time.get_ticks_usec() if profiling else 0

## Close one. Named at this end so the name sits with the number it produced.
func prof_end(tag: StringName, t0: int) -> void:
	if not profiling or t0 == 0:
		return
	_prof[tag] = float(_prof.get(tag, 0.0)) + float(Time.get_ticks_usec() - t0)
	_prof_n[tag] = int(_prof_n.get(tag, 0)) + 1

func prof_frame() -> void:
	if profiling:
		_prof_frames += 1

func prof_reset() -> void:
	_prof.clear()
	_prof_n.clear()
	_prof_frames = 0

## What each block cost per frame, in microseconds, worst first.
func prof_report() -> Array:
	var out: Array = []
	var f: float = maxf(float(_prof_frames), 1.0)
	for k in _prof.keys():
		out.append([String(k), float(_prof[k]) / f, int(_prof_n[k])])
	out.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	return out

func prof_frames() -> int:
	return _prof_frames

## A screen is up that wants the pointer, so nothing may capture the mouse.
##
## Freelook is on ALT and CMD, and the map plants an objective on CTRL or CMD
## and click. Holding CMD over the map therefore engaged freelook, which
## captures the mouse -- and a captured cursor is parked in the middle of the
## screen, so the marker could only ever be dropped dead centre.
var ui_pointer := false

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
	# The same map drawn on the planet. Not on a modifier and not on M twice:
	# it is a mode you sit in, and cycling through it to close the map would
	# mean pressing M three times to put the chart away.
	_add(&"map_globe",    [_key(KEY_O), _key(KEY_F2)])
	# Not backslash: `cycle_weapon` is already there, and `tapped` erases the
	# press when it is read, so whichever of the two was polled first that frame
	# ate the other. Cycling the weapon and slowing time fought over one key.
	_add(&"time_slow",    [_key(KEY_APOSTROPHE)])
