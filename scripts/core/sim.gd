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

## Continents. The world used to be one landmass with an ocean bolted to the
## east of it, which was tolerable across forty kilometres and absurd across six
## hundred: half the map was sea and the half that was not had no coastline in
## it anywhere. This decides, at a scale of a couple of hundred kilometres,
## where there is land at all.
var noise_cont := FastNoiseLite.new()
## Rivers and the basins they run into. A continent with no water in it is a
## wall to anything that floats: the sea stopped at the coast, so a ship could
## never get inland and the only water on the map was around the outside of it.
var noise_river := FastNoiseLite.new()
var noise_river2 := FastNoiseLite.new()
var noise_lo := FastNoiseLite.new()
var noise_hi := FastNoiseLite.new()
var noise_det := FastNoiseLite.new()
## The native extension, when the build is there. It owns the height field:
## see `_natural_field`.
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
var assist := true
var last_landing := {}
var score := 0

# --------------------------------------------------------------------------
func _ready() -> void:
	# Before the noise fields, so nothing can sample the GDScript ones first and
	# then be answered by the native field later in the same run.
	if ClassDB.class_exists("Terra"):
		native = ClassDB.instantiate("Terra")
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

	noise_river.seed = 5150
	noise_river.noise_type = FastNoiseLite.TYPE_SIMPLEX
	# long meandering channels rather than a mesh of streams
	noise_river.frequency = 0.0000135
	noise_river.fractal_octaves = 2
	noise_river.fractal_lacunarity = 2.0
	noise_river.fractal_gain = 0.4

	# A second, independent set of channels, running at a different scale and
	# across a different grain, so the map has more than one river system.
	noise_river2.seed = 8807
	noise_river2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_river2.frequency = 0.0000181
	noise_river2.fractal_octaves = 2
	noise_river2.fractal_lacunarity = 2.0
	noise_river2.fractal_gain = 0.45

	noise_lo.seed = 1337
	noise_lo.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_lo.frequency = 0.000055
	noise_lo.fractal_octaves = 4
	noise_lo.fractal_lacunarity = 2.1
	noise_lo.fractal_gain = 0.5

	noise_hi.seed = 99
	noise_hi.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_hi.frequency = 0.00042
	noise_hi.fractal_octaves = 3

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

	noise_det.seed = 7
	noise_det.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_det.frequency = 0.0035
	noise_det.fractal_octaves = 2

## Water in the channel where it meets the sea, how far inland it stays at that
## depth, and over what distance it then climbs out of it.
const NAV_DEPTH := 16.0
const NAV_FLAT := 95000.0
const NAV_RISE := 150000.0

## Carve one river. `rv` is the channel field at the point, zero on the
## centreline; `home` is 1 near the airfield and 0 out where the continents
## take over.
##
## The old cut was measured against the land it ran through -- deep near the
## sea, shallow in the hills -- which reads correctly and is useless, because a
## channel that is merely lower than its banks is still four hundred metres up
## and bone dry. Nothing could float more than a few kilometres from the coast.
## The bed is set by how far inland it is instead: a fathom under the surface at
## the estuary and level for the best part of a hundred kilometres, then
## climbing. Where the land around it is high that becomes a flooded gorge with
## navigable water at the bottom, which is the point.
func _river(h: float, x: float, _z: float, rv: float, home: float) -> float:
	var out := h
	var chan: float = 1.0 - smoothstep(0.0, 0.045, rv)
	if chan > 0.0 and h > WATER_LEVEL - 120.0:
		var low: float = clampf(1.0 - (h - WATER_LEVEL) / 1100.0, 0.0, 1.0)
		out -= lerpf(14.0, 210.0, low * low) * chan * chan
	if home <= 0.0:
		return out
	var inland: float = maxf(COAST_X - x, 0.0)
	var bed: float = WATER_LEVEL - NAV_DEPTH
	if inland > NAV_FLAT:
		bed += pow((inland - NAV_FLAT) / NAV_RISE, 1.4) * 1300.0
	# flat bottom along the centreline, valley sides out to the rim
	var prof: float = 1.0 - smoothstep(0.022, 0.085, rv)
	var w: float = prof * prof * home
	if w > 0.0 and bed < out:
		out = lerpf(out, bed, w)
	return out

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

## Terrain elevation in metres. Single source of truth: the visual mesh, the
## landing gear and the crash test all sample this.
## The land at a point: the field, then everything built on it.
func height_at(x: float, z: float) -> float:
	return _deform_top(ground_at(x, z), x, z)

## The untouched field. Native when the extension is there, GDScript when it is
## not -- and never a mix of the two in one session: the towns, the roads and
## the colliders are all sited against this, so two answers to the same point
## would tear the world in half.
func _natural_field(x: float, z: float) -> float:
	if native != null:
		return native.natural_height(x, z)
	return _natural_gd(x, z)

func _natural_gd(x: float, z: float) -> float:
	var m := (noise_lo.get_noise_2d(x, z) + 1.0) * 0.5
	m = pow(m, 2.3)
	var h := m * 2100.0
	h += noise_hi.get_noise_2d(x, z) * 150.0 * m
	h += noise_det.get_noise_2d(x, z) * 6.0 * clampf(m * 4.0, 0.15, 1.0)
	h -= 90.0
	# The airfield sits in a north-south valley so both runway approaches and the
	# departure end stay clear of rising ground — but only near the airfield.
	# There was no limit along z at all, so the cap applied at every point in
	# the world and cut a four kilometre trench from one end of the map to the
	# other: a groove running the whole length of it, and the reason the middle
	# of the map had no high ground in it.
	var along: float = 1.0 - smoothstep(5000.0, 24000.0, absf(z))
	if along > 0.0:
		var axis := clampf((absf(x) - 1000.0) / 3400.0, 0.0, 1.0)
		var cap := 55.0 + axis * axis * 2500.0
		if h > cap:
			h = lerpf(h, cap + (h - cap) * 0.12, along)
	# Canyons. Where a second channel field runs across high ground it cuts
	# hard and narrow rather than opening into a valley, which is what makes a
	# gorge worth flying down.
	var cy: float = absf(noise_river.get_noise_2d(z * 1.9 + 31000.0, x * 1.9 - 17000.0))
	var gorge: float = 1.0 - smoothstep(0.0, 0.020, cy)
	if gorge > 0.0 and h > 420.0:
		var bite: float = clampf((h - 420.0) / 700.0, 0.0, 1.0)
		h -= 340.0 * gorge * gorge * bite
	# The land runs out to the east: a coastal shelf dropping into open ocean.
	# Held to the home region — beyond that the continents below decide, or the
	# whole eastern half of a six hundred kilometre world is one flat sea.
	var far: float = smoothstep(55000.0, 150000.0, Vector2(x, z).length())
	var sea := smoothstep(COAST_X, COAST_X + 9000.0, x) * (1.0 - far)
	if sea > 0.0:
		h = lerpf(h, -240.0, sea)
	# Continents. Near home the shape is fixed: the airfield, the towns and the
	# roads are all sited on ground that has to stay where it is. Further out
	# the large scale field takes over and puts oceans, inland seas and islands
	# where it likes.
	if far > 0.0:
		var cont := noise_cont.get_noise_2d(x, z)
		var landness: float = lerpf(1.0, smoothstep(-0.10, 0.16, cont), far)
		if landness < 1.0:
			# a shelf, then the deep: not a cliff straight to the bottom
			var floor_y: float = lerpf(-1500.0, -160.0, smoothstep(0.0, 0.45, landness))
			h = lerpf(floor_y, h, smoothstep(0.0, 0.62, landness))
	# Rivers. The channel is where the field crosses zero, so it runs as a line
	# rather than a patch. Two of them, from two fields, so the country has
	# more than one river in it.
	# The navigable bed reaches a long way out, because a river is measured
	# from the coast it runs to and not from the airfield. Gating it with the
	# same 55 km fade the coastal shelf uses cut every channel off 26 km inland,
	# which is not a river system, it is an inlet.
	var home: float = 1.0 - smoothstep(200000.0, 450000.0, Vector2(x, z).length())
	# Sampled with x squashed, which is what points the rivers at the sea. The
	# channel is the contour where the field crosses zero, and the contours of
	# an isotropic field run in whatever direction they please -- so the map had
	# rivers, and not one of them went anywhere. Compressing the x axis makes
	# the field vary slowly east-west and quickly north-south, and its contours
	# then run predominantly east-west, down the country and into the ocean.
	h = _river(h, x, z, absf(noise_river.get_noise_2d(x * 0.28, z)), home)
	h = _river(h, x, z, absf(noise_river2.get_noise_2d(
		x * 0.34 + z * 0.10, z + x * 0.06)), home)
	return h

## Everything the world has put on top of the field: the settlements' levelled
## platforms, the made roads, the aerodromes and the carrier decks. Split out
## from the field itself so a whole grid of heights can be fetched at once and
## then have this applied to it point by point.
## Everything the world has put on top of the field. Split in two: the ground
## proper -- the settlements' levelled platforms and the made roads, which are
## many and are what a height query spends its time on -- and the handful of
## aerodromes and carrier decks on top of that.
func deform(h: float, x: float, z: float) -> float:
	return _deform_top(_deform_ground(h, x, z), x, z)

## The ground: pads and roads. Native when the extension is there, because this
## is the part whose cost grows with the size of the road network -- a
## continental trunk system made every height query in the game walk it.
func ground_at(x: float, z: float) -> float:
	if native != null:
		return native.ground(x, z, not _in_survey)
	return _deform_ground(_natural_gd(x, z), x, z)

func _deform_ground(h: float, x: float, z: float) -> float:
	# Settlements stand on ground that has been levelled for them. Towns are
	# built where the land is workable, not draped over whatever gradient
	# happens to run through the middle of them — a street grid laid across a
	# hillside is a staircase, and the buildings climb it.
	var pad_w := 0.0
	for pad in _town_pads:
		var pc: Vector2 = pad["c"]
		var pr: float = pad["r"]
		var d := Vector2(x - pc.x, z - pc.y).length()
		if d < pr * 1.60:
			var w: float = 1.0 - smoothstep(pr * 1.06, pr * 1.60, d)
			h = lerpf(h, float(pad["y"]), w)
			pad_w = maxf(pad_w, w)
	# Made road: cut into the rise, filled across the dip, the spoil graded out
	# to either side. Where the fill would be an absurd embankment the road is
	# on a deck instead and the ground underneath is left alone.
	if not _in_survey and not _corr.is_empty():
		var rs := road_surface(x, z)
		if rs.y > 0.0:
			# Eased out rather than switched off. A hard cut off left an eight
			# metre cliff down one side of the carriageway wherever the fill
			# reached the limit, in the middle of the road.
			var carry: float = 1.0 - smoothstep(ROAD_FILL_MAX,
				ROAD_FILL_MAX * 2.2, rs.x - h)
			# And the same limit the other way up. Fill was capped -- an
			# embankment past a certain height becomes a bridge -- but the cut
			# never was, so a road crossing a ridge dug itself in as deep as the
			# surveyed profile wanted and left a slot through the hill with the
			# carriageway at the bottom of it. Past this the corridor lets go
			# and the road climbs over instead, which is what a road does.
			carry *= 1.0 - smoothstep(ROAD_CUT_MAX, ROAD_CUT_MAX * 2.4, h - rs.x)
			# and a town has already been levelled: a road through it runs on
			# the made ground, not through a cutting of its own. Fighting the
			# pad left a fourteen metre step under the buildings.
			carry *= 1.0 - pad_w
			# The carriageway itself is always levelled; only the grading out to
			# either side of it eases off. A road traversing a hillside is a
			# bench cut into the slope -- level across its width, with a little
			# cut above and a little fill below -- and capping the earthworks
			# without this left the surface simply lying on the hill at whatever
			# angle the hill happened to be, which measured 17% across the
			# carriageway and is not a road.
			var core: float = clampf((rs.y - 0.82) / 0.18, 0.0, 1.0)
			var w: float = maxf(rs.y * carry, core)
			# And the bound holds here, at the point being asked about, not only
			# at the survey stations. The profile is clamped to the ground every
			# 110 m; a knoll standing between two of those stations sits above
			# the straight line joining them and was cut clean through -- 152 m
			# deep at worst, which is a gorge with a road at the bottom of it.
			var target: float = clampf(rs.x, rs.z - ROAD_CUT_MAX,
				rs.z + ROAD_FILL_MAX)
			if w > 0.0:
				h = lerpf(h, target, w)
	return h

## The aerodromes and the decks. There are a handful of each, so they stay on
## this side of the boundary.
func _deform_top(h: float, x: float, z: float) -> float:
	# The aerodrome last, and it wins. A town levelled itself on top of the
	# runway and the pavement ended up fifty-seven metres under the ground it
	# was supposed to be lying on: the field is the one surface in the world
	# that other things have to give way to.
	if not _siting:
		for fd in fields:
			var ff := field_factor(fd, x, z)
			if ff > 0.0:
				h = lerpf(h, float(fd["elev"]), ff)
	if not decks.is_empty():
		h = maxf(h, deck_height(x, z))
	return h

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
	_corr_grid = {}
	road_bridges = []
	_rt_jobs = []
	for pair in links:
		_rt_jobs.append([points[pair[0]], points[pair[1]]])
	_rt_out = []
	_rt_out.resize(_rt_jobs.size())
	_rt_gid = -1
	if _rt_jobs.is_empty():
		return
	if native != null:
		# Every leg in one call, searched on every core inside the extension.
		# It goes out to a worker of its own so the loading screen keeps
		# painting while it runs.
		_push_world()
		_rt_gid = WorkerThreadPool.add_group_task(_route_native, 1, -1, true,
			"road routing")
	else:
		_rt_gid = WorkerThreadPool.add_group_task(_route_job, _rt_jobs.size(),
			-1, true, "road routing")

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
	native.set_world(pads, fl)

func _route_native(_i: int) -> void:
	var ends := PackedVector2Array()
	for j in _rt_jobs:
		ends.append(j[0] as Vector2)
		ends.append(j[1] as Vector2)
	var lines: Array = native.route_many(ends)
	for k in mini(lines.size(), _rt_out.size()):
		var pl: PackedVector2Array = lines[k]
		var segs: Array = []
		for m in range(pl.size() - 1):
			segs.append([pl[m], pl[m + 1]])
		_rt_out[k] = segs

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
	for ji in _rt_jobs.size():
		var segs: Array = _rt_out[ji] if _rt_out[ji] != null else []
		var line := PackedVector2Array()
		for i in segs.size():
			ROADS.append(segs[i])
			if i == 0:
				line.append(segs[i][0])
			line.append(segs[i][1])
		if line.size() > 1:
			lines.append(line)
	_rt_jobs = []
	_rt_out = []
	_road_lines = lines
	var t_sv := Time.get_ticks_msec()
	var verts := 0
	for l2 in lines:
		verts += (l2 as PackedVector2Array).size()
	_survey_roads()
	if debug_roads:
		var rs := Vector2.ZERO
		if native != null:
			rs = native.route_stats()
		print("[roads] %d legs, %d waypoints -> search %d nodes in %d ms, survey %d ms" % [
			lines.size(), verts, int(rs.x), int(rs.y),
			Time.get_ticks_msec() - t_sv])

# -------------------------------------------------------------- road corridor
const ROAD_HALF := 7.5           # carriageway half width
const ROAD_SHOULDER := 24.0      # graded shoulder either side of it
const ROAD_GRADE := 0.062        # steepest gradient a trunk road is built to
const SURVEY_STEP := 45.0        # spacing of the profile's stations
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

var _road_lines: Array = []      # trunk network as polylines, in build order
var _road_prof: Array = []       # the made height at each of their vertices
var road_bridges: Array = []     # spans carried on a deck: {a, b, ya, yb}
var _in_survey := false

## Work out what height the made road actually sits at, leg by leg. Routing
## already keeps a road off the worst ground; this is the cut and fill that
## follows. Without it the carriageway is draped over every hummock in the
## noise field and the surface pitches like a switchback.
## The untouched ground under each surveyed vertex, kept so the design profile
## can be held near it.
var _natural: Array = []

## A road may cut into a rise and fill across a dip, but only so far.
##
## Grading alone holds a constant 6.2% whatever the country does, and over a
## range that puts the design surface hundreds of metres under the hill -- at
## worst, measured, a kilometre under it. The corridor then dutifully carved the
## ground down to meet it, which is why the trunk network ran through slots in
## the landscape instead of over it. Beyond a cutting's depth and an
## embankment's height the road gives up and follows the ground, and takes the
## gradient that comes with it.
func _hold_to_ground(li: int, y: PackedFloat32Array,
		cut := ROAD_CUT_MAX, fill := ROAD_FILL_MAX) -> PackedFloat32Array:
	if li >= _natural.size():
		return y
	var g: PackedFloat32Array = _natural[li]
	for i in mini(y.size(), g.size()):
		y[i] = clampf(y[i], g[i] - cut, g[i] + fill)
	return y

## After the structures are known: everything that is not being carried on a
## deck or driven through a hill goes back to being ordinary earthworks, and is
## held to a cutting and an embankment again.
func _hold_open_ground() -> void:
	for li in _road_prof.size():
		if li >= _natural.size():
			continue
		var y: PackedFloat32Array = _road_prof[li]
		var g: PackedFloat32Array = _natural[li]
		for i in mini(y.size(), g.size()):
			if _in_structure(li, i):
				continue
			y[i] = clampf(y[i], g[i] - ROAD_CUT_MAX, g[i] + ROAD_FILL_MAX)
		_road_prof[li] = y

## Smooth the open-ground profile inside the band it is allowed to sit in.
##
## The last thing done to a profile is a clamp, and a clamp can put a step in
## it: two neighbouring stations pinned to very different ground leave the
## design surface climbing thirty-four metres over a forty-five metre leg, which
## is a wall across the carriageway rather than a gradient. This eases each
## station toward its neighbours without ever letting it outside the cutting and
## embankment band, so the profile comes out as smooth as those limits allow --
## and where they allow nothing better, that is a place the classifier should
## have made a structure of.
func _settle_open(passes: int) -> void:
	for _p in passes:
		for li in _road_prof.size():
			if li >= _natural.size():
				continue
			var y: PackedFloat32Array = _road_prof[li]
			var g: PackedFloat32Array = _natural[li]
			var n: int = mini(y.size(), g.size())
			if n < 3:
				continue
			var was := y.duplicate()
			for i in range(1, n - 1):
				if _in_structure(li, i):
					continue
				var want: float = (was[i - 1] + was[i + 1]) * 0.5
				# How much earth may be moved here. An ordinary cutting or
				# embankment is enough on ordinary ground; where the hillside
				# itself runs steeper than the road is allowed to, holding to
				# that meant the road took the hill's gradient instead of being
				# built. Country like that is where the deep cuttings and the
				# high banks actually go, so the allowance grows exactly where
				# the ground is what forces it.
				var fall: float = absf(g[i + 1] - g[i - 1]) / (SURVEY_STEP * 2.0)
				var hard: float = clampf((fall - ROAD_GRADE) / ROAD_GRADE,
					0.0, 1.0)
				y[i] = clampf(want,
					g[i] - lerpf(ROAD_CUT_MAX * 0.5, ROAD_CUT_MAX, hard),
					g[i] + lerpf(ROAD_FILL_MAX * 0.5, ROAD_FILL_MAX, hard))
			_road_prof[li] = y

func _survey_roads() -> void:
	_in_survey = true
	_leg_idx = []
	_leg_idx_age = 99
	_natural = []
	var dense: Array = []
	for line in _road_lines:
		var pl: PackedVector2Array = line
		# Chained at survey spacing first. Profiled at the routing waypoints the
		# road runs dead straight in elevation for seven hundred metres at a
		# time, and every hummock between them turns into an embankment.
		var fine := PackedVector2Array([pl[0]])
		for i in range(pl.size() - 1):
			var d: float = pl[i].distance_to(pl[i + 1])
			# 45 m, not 110. The profile is held to the ground at its stations,
			# so anything standing between two of them is invisible to that
			# clamp -- and a knoll between stations was cut clean through, a
			# hundred and fifty metres deep at worst.
			var steps: int = maxi(1, int(round(d / SURVEY_STEP)))
			for k in range(1, steps + 1):
				fine.append(pl[i].lerp(pl[i + 1], float(k) / float(steps)))
		# The whole line's ground in one call. A station every forty-five metres
		# over a continental network is a great many points, and asked for one
		# at a time each is a crossing of the extension boundary.
		var y := PackedFloat32Array()
		if native != null:
			y = native.grounds_at(fine, false)
			for i in y.size():
				y[i] = _deform_top(y[i], fine[i].x, fine[i].y)
		else:
			y.resize(fine.size())
			for i in fine.size():
				y[i] = height_at(fine[i].x, fine[i].y)
		# The ground the earthworks start from, read at the same point in the
		# pipeline the corridor runs at -- before the aerodrome levels
		# everything around it. Captured after it instead, the reference near
		# the field was two hundred metres below the ground the corridor was
		# actually cutting into, and the clamp let the road dig straight through
		# the hill it was supposed to be bounding.
		var nat := PackedFloat32Array()
		var was_siting := _siting
		_siting = true
		if native != null:
			nat = native.grounds_at(fine, false)
			for i2 in nat.size():
				nat[i2] = _deform_top(nat[i2], fine[i2].x, fine[i2].y)
		else:
			nat.resize(fine.size())
			for i2 in fine.size():
				nat[i2] = height_at(fine[i2].x, fine[i2].y)
		_siting = was_siting
		dense.append(fine)
		_natural.append(nat)
		_road_prof.append(y)
	for li in dense.size():
		_road_prof[li] = _hold_to_ground(li,
			_rule_grade(dense[li], _road_prof[li], 2), TUNNEL_MAX, VIADUCT_MAX)
	# Where two routes run into or alongside each other they have to agree about
	# the height. Surveyed independently, a pair crossing at a junction came out
	# eight metres apart six metres from one another: a step down the side of
	# the carriageway with no slope in between.
	if debug_roads:
		print("[survey] %d lines, %d vertices, worst neighbour disagreement %.1f m" % [
			dense.size(), _vertex_count(dense), _worst_tie(dense)])
	var _tw := Time.get_ticks_msec()
	if native != null:
		# The whole relaxation in one call: eighty thousand stations, welded,
		# tied, graded and clamped twenty-four times over, with nothing crossing
		# the boundary between passes.
		var fp := PackedVector2Array()
		var fy := PackedFloat32Array()
		var fn := PackedFloat32Array()
		var starts := PackedInt32Array()
		for li4 in dense.size():
			starts.append(fp.size())
			fp.append_array(dense[li4])
			fy.append_array(_road_prof[li4])
			fn.append_array(_natural[li4] if li4 < _natural.size()
				else _road_prof[li4])
		starts.append(fp.size())
		var res: Array = native.survey_relax(fp, fy, fn, starts, 24,
			TUNNEL_MAX, VIADUCT_MAX)
		var op: PackedVector2Array = res[0]
		var oy: PackedFloat32Array = res[1]
		for li5 in dense.size():
			dense[li5] = op.slice(starts[li5], starts[li5 + 1])
			_road_prof[li5] = oy.slice(starts[li5], starts[li5 + 1])
	else:
		_relax_passes(dense)
	if debug_roads:
		print("[survey] relaxation %d ms" % (Time.get_ticks_msec() - _tw))
	var _tt := Time.get_ticks_msec()
	_road_lines = dense
	_relax_tail(dense, _tw, _tt)

## The GDScript relaxation, kept for when the extension is not there.
func _relax_passes(dense: Array) -> void:
	for pass_i in 24:
		_weld_parallels(dense)
		_tie_junctions(dense)
		for li in dense.size():
			# no easing inside the loop: the low pass filter pulled every tie
			# straight back out again and the crossings never converged
			# graded to what a structure allows, so the alignment can hold its
			# gradient through a hill instead of being dragged over the top of
			# it; what is left in the open is pulled back to the ground below
			_road_prof[li] = _hold_to_ground(li,
				_rule_grade(dense[li], _road_prof[li], 1, false),
				TUNNEL_MAX, VIADUCT_MAX)
		if debug_roads:
			print("[survey] pass %d: worst neighbour disagreement %.2f m" % [
				pass_i + 1, _worst_tie(dense)])

func _relax_tail(dense: Array, _tw: int, _tt: int) -> void:
	if debug_roads:
		print("[survey] after tying: worst neighbour disagreement %.1f m" % _worst_tie(dense))
	for li in dense.size():
		var y: PackedFloat32Array = _road_prof[li]
		for i in y.size():
			y[i] = maxf(y[i], WATER_LEVEL + 2.5)
		_road_prof[li] = y
	# Classify, hold the open ground, then grade again and hold again. The last
	# thing every relaxation pass did was clamp, so a station the clamp moved
	# was never re-graded against its neighbours and the profile could step 70 m
	# over a 46 m leg -- a wall across the carriageway, inside a tunnel.
	for settle in 3:
		_classify_structures()
		_hold_open_ground()
		for li3 in _road_prof.size():
			_road_prof[li3] = _rule_grade(dense[li3], _road_prof[li3], 1, false)
	var _ts := Time.get_ticks_msec()
	_classify_structures()
	_hold_open_ground()
	_settle_open(24)
	var _tc := Time.get_ticks_msec()
	_index_corridor()
	if debug_roads:
		print("[survey] weld/tie %d ms | settle loop %d ms | classify+settle %d ms | corridor %d ms" % [
			_tt - _tw, _ts - _tt, _tc - _ts, Time.get_ticks_msec() - _tc])
	# The painted network has to follow the earthworks, or the carriageway is
	# stained across ground that was never levelled for it.
	# Only the legs actually laid on the ground. A tunnel is inside the hill and
	# a bridge is above it, so neither is painted onto the terrain, stained into
	# the ground mask, or drawn as a ribbon lying on the country.
	ROADS = []
	for li2 in dense.size():
		var pl: PackedVector2Array = dense[li2]
		for i in range(pl.size() - 1):
			if _in_structure(li2, i) or _in_structure(li2, i + 1):
				continue
			ROADS.append([pl[i], pl[i + 1]])
	if not _road_field.is_empty():
		_build_road_field()
	_in_survey = false

## Hold the ruling gradient along one road. Cutting first and filling after
## leaves both limits satisfied: nothing rises faster than the gradient, and by
## the second pair nothing falls faster either.
func _rule_grade(pl: PackedVector2Array, src: PackedFloat32Array, passes: int,
		smooth := true) -> PackedFloat32Array:
	var y := PackedFloat32Array(src)
	for _pass in passes:
		for i in range(1, y.size()):
			y[i] = minf(y[i], y[i - 1] + ROAD_GRADE * pl[i - 1].distance_to(pl[i]))
		for i in range(y.size() - 2, -1, -1):
			y[i] = minf(y[i], y[i + 1] + ROAD_GRADE * pl[i].distance_to(pl[i + 1]))
		for i in range(1, y.size()):
			y[i] = maxf(y[i], y[i - 1] - ROAD_GRADE * pl[i - 1].distance_to(pl[i]))
		for i in range(y.size() - 2, -1, -1):
			y[i] = maxf(y[i], y[i + 1] - ROAD_GRADE * pl[i].distance_to(pl[i + 1]))
		if smooth:
			for i in range(1, y.size() - 1):
				y[i] = lerpf(y[i], (y[i - 1] + y[i + 1]) * 0.5, 0.25)
	return y

var debug_roads := false

## Lay the network out again. The command line is parsed after the world has
## already built its roads, so the harness needs a way to watch the survey.
func resurvey_roads() -> void:
	_road_prof = []
	_corr = []
	_survey_roads()

func _vertex_count(lines: Array) -> int:
	var n := 0
	for l in lines:
		n += (l as PackedVector2Array).size()
	return n

const TIE_CELL := 96.0

## Bucket every leg of the network by ground cell, so a point can ask what runs
## near it without walking all eight hundred of them.
func _leg_index(lines: Array) -> Array:
	var legs: Array = []
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		var y: PackedFloat32Array = _road_prof[li]
		for j in range(pl.size() - 1):
			legs.append([li, j, pl[j], pl[j + 1], y[j], y[j + 1]])
	var grid: Dictionary = {}
	for idx in legs.size():
		var a: Vector2 = legs[idx][2]
		var b: Vector2 = legs[idx][3]
		var steps: int = maxi(1, int(a.distance_to(b) / (TIE_CELL * 0.5)))
		for k in steps + 1:
			var q: Vector2 = a.lerp(b, float(k) / float(steps))
			var ci := int(floor(q.x / TIE_CELL))
			var cj := int(floor(q.y / TIE_CELL))
			for oi in [-1, 0, 1]:
				for oj in [-1, 0, 1]:
					var key: int = (ci + oi) * 65536 + (cj + oj)
					if not grid.has(key):
						grid[key] = PackedInt32Array()
					var bucket: PackedInt32Array = grid[key]
					if bucket.is_empty() or bucket[bucket.size() - 1] != idx:
						bucket.append(idx)
						grid[key] = bucket
	return [legs, grid]

## What the network looks like from one point: every stretch of road running
## within `reach` of it, as [height there, distance, the point on it]. Measuring
## vertex to vertex missed the case that actually matters -- two roads crossing
## at a shallow angle, five metres apart, whose nearest waypoints are fifty
## metres from one another and so were never compared at all.
func _legs_near(index: Array, li: int, i: int, p: Vector2, reach: float) -> Array:
	var legs: Array = index[0]
	var grid: Dictionary = index[1]
	var key: int = int(floor(p.x / TIE_CELL)) * 65536 + int(floor(p.y / TIE_CELL))
	if not grid.has(key):
		return []
	var out: Array = []
	for idx in (grid[key] as PackedInt32Array):
		var leg: Array = legs[idx]
		# a road is not a junction with the stretch of itself it stands on
		if int(leg[0]) == li and absi(int(leg[1]) - i) < 6:
			continue
		var a: Vector2 = leg[2]
		var ab: Vector2 = (leg[3] as Vector2) - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var foot: Vector2 = a + ab * t
		var d: float = p.distance_to(foot)
		if d > reach:
			continue
		out.append([lerpf(float(leg[4]), float(leg[5]), t), d, foot])
	return out

## The largest height difference a driver would see between the road under the
## wheels and another stretch of road running alongside it.
func _worst_tie(lines: Array) -> float:
	var index := _leg_index(lines)
	var worst := 0.0
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		var y: PackedFloat32Array = _road_prof[li]
		for i in pl.size():
			for near in _legs_near(index, li, i, pl[i], 40.0):
				worst = maxf(worst, absf(y[i] - float(near[0])))
	return worst

## Two routes that end up running a few metres apart are one road, not two.
## Left alone they each cut their own corridor and the strip between them is a
## step down the middle of the carriageway. This draws them onto each other.
## The leg index, kept across passes. Welding moves a vertex by at most a few
## metres a pass against a thirty-four metre reach, so rebuilding the whole
## index every time -- twice a pass, once here and once for the junctions --
## was most of the cost of surveying a continental network for no accuracy the
## reach could notice.
var _leg_idx: Array = []
var _leg_idx_age := 99

func _survey_index(lines: Array) -> Array:
	_leg_idx_age += 1
	if _leg_idx_age >= 4 or _leg_idx.is_empty():
		_leg_idx = _leg_index(lines)
		_leg_idx_age = 0
	return _leg_idx

func _weld_parallels(lines: Array) -> void:
	const WELD := 34.0
	var index := _survey_index(lines)
	var moved: Array = []
	for li in lines.size():
		moved.append((lines[li] as PackedVector2Array).duplicate())
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		var mi: PackedVector2Array = moved[li]
		for i in pl.size():
			var pull := Vector2.ZERO
			var wsum := 0.0
			for near in _legs_near(index, li, i, pl[i], WELD):
				var w: float = 1.0 - float(near[1]) / WELD
				pull += (near[2] as Vector2) * w
				wsum += w
			if wsum > 0.0:
				mi[i] = mi[i].lerp(pull / wsum, clampf(wsum * 0.35, 0.0, 0.5))
		moved[li] = mi
	for li in lines.size():
		lines[li] = moved[li]

## Pull the surveyed heights of neighbouring stretches together, hardest where
## they are closest, so junctions, parallel runs and switchbacks come out level
## with each other instead of a step apart.
func _tie_junctions(lines: Array) -> void:
	const TIE := 70.0
	var index := _survey_index(lines)
	for li in lines.size():
		var pl: PackedVector2Array = lines[li]
		var y: PackedFloat32Array = _road_prof[li]
		var out := PackedFloat32Array(y)
		for i in y.size():
			var ysum := 0.0
			var wsum := 0.0
			for near in _legs_near(index, li, i, pl[i], TIE):
				var w: float = 1.0 - float(near[1]) / TIE
				w *= w
				ysum += float(near[0]) * w
				wsum += w
			if wsum > 0.0:
				out[i] = lerpf(y[i], ysum / wsum, clampf(wsum * 0.6, 0.0, 0.9))
		_road_prof[li] = out

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
## Marked per surveyed station and then grouped into runs, because a road does
## not tunnel through every hummock -- a structure has to earn its length.
## A structure has to earn itself twice over: it must be long enough to be worth
## building and deep enough that there is no sensible alternative. Length alone
## put a third of the whole network -- 268 km of it -- underground, because a
## grade rule held against rolling country is in cut nearly everywhere.
const TUNNEL_MIN := 420.0        # shorter than this, cut it or climb it
const TUNNEL_DEEP := 38.0        # and the hill has to be at least this thick
const BRIDGE_MIN := 130.0        # shorter than this, fill it
const BRIDGE_HIGH := 24.0        # and the ground has to fall at least this far
const TUNNEL_MAX := 220.0        # deepest a tunnel is allowed to be driven
const VIADUCT_MAX := 110.0       # tallest a viaduct is allowed to stand

var road_tunnels: Array = []     # {a, b, ya, yb}
## Per surveyed station, whether the road is inside a structure there. The
## corridor leaves the ground alone across those, and the surface is drawn as a
## deck or not at all rather than painted on the hillside.
var _road_struct: Array = []

func _classify_structures() -> void:
	road_bridges = []
	road_tunnels = []
	_road_struct = []
	for li in _road_lines.size():
		var pl: PackedVector2Array = _road_lines[li]
		var prof: PackedFloat32Array = _road_prof[li]
		var nat: PackedFloat32Array = _natural[li] if li < _natural.size() else prof
		var flags := PackedByteArray()
		flags.resize(pl.size())
		for i in pl.size():
			var over: float = prof[i] - nat[i]          # + fill, - cut
			flags[i] = 1 if over > ROAD_FILL_MAX else (2 if -over > ROAD_CUT_MAX else 0)
		# group the runs, and only keep the ones long enough to be worth building
		var i0 := 0
		while i0 < flags.size():
			if flags[i0] == 0:
				i0 += 1
				continue
			var kind: int = flags[i0]
			var i1 := i0
			while i1 + 1 < flags.size() and flags[i1 + 1] == kind:
				i1 += 1
			var run: float = pl[i0].distance_to(pl[i1])
			var extreme := 0.0
			for k3 in range(i0, i1 + 1):
				extreme = maxf(extreme, absf(prof[k3] - nat[k3]))
			var worth_it: bool = run >= (BRIDGE_MIN if kind == 1 else TUNNEL_MIN) \
				and extreme >= (BRIDGE_HIGH if kind == 1 else TUNNEL_DEEP)
			if worth_it:
				# the whole run, not just its ends: a span follows the
				# alignment, and a deck drawn as one straight beam between the
				# abutments leaves the road beside it
				var pts := PackedVector2Array()
				var ys := PackedFloat32Array()
				for k2 in range(i0, i1 + 1):
					pts.append(pl[k2])
					ys.append(prof[k2])
				var rec := {"a": pl[i0], "b": pl[i1],
					"ya": prof[i0], "yb": prof[i1], "pts": pts, "ys": ys}
				if kind == 1:
					road_bridges.append(rec)
				else:
					road_tunnels.append(rec)
			else:
				for k in range(i0, i1 + 1):
					flags[k] = 0                        # cut or fill it instead
			i0 = i1 + 1
		_road_struct.append(flags)

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
var _corr_grid: Dictionary = {}  # cell key -> PackedInt32Array of leg indices

func _index_corridor() -> void:
	_corr = []
	_corr_grid = {}
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
			if _in_structure(li, i) or _in_structure(li, i + 1):
				continue
			_corr.append([pl[i], pl[i + 1], prof[i], prof[i + 1],
				nat[i], nat[i + 1]])
	if native != null:
		# Over the boundary once, stamped into its own grid there. The GDScript
		# grid below is only built when there is no extension to hold it.
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
		return
	var pad: float = ROAD_HALF + ROAD_SHOULDER
	for idx in _corr.size():
		var a: Vector2 = _corr[idx][0]
		var b: Vector2 = _corr[idx][1]
		var steps: int = maxi(1, int(a.distance_to(b) / (CORR_CELL * 0.5)))
		for k in steps + 1:
			var q: Vector2 = a.lerp(b, float(k) / float(steps))
			var ci := int(floor((q.x - pad) / CORR_CELL))
			var cj := int(floor((q.y - pad) / CORR_CELL))
			for oi in 3:
				for oj in 3:
					var key: int = (ci + oi) * 65536 + (cj + oj)
					if not _corr_grid.has(key):
						_corr_grid[key] = PackedInt32Array()
					var bucket: PackedInt32Array = _corr_grid[key]
					if bucket.is_empty() or bucket[bucket.size() - 1] != idx:
						bucket.append(idx)
						_corr_grid[key] = bucket

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
	# The corridor lives on whichever side is holding it. With the extension in
	# play the grid below is never built, and this used to fall straight through
	# to "no road here" for every point in the world -- which is what tells a
	# road ribbon to lie on the ground instead of riding its embankment.
	if native != null:
		return native.road_surface_at(x, z)
	if _corr.is_empty() or _road_prof.size() != _road_lines.size():
		return Vector3.ZERO
	var reach: float = ROAD_HALF + ROAD_SHOULDER
	var key: int = int(floor(x / CORR_CELL)) * 65536 + int(floor(z / CORR_CELL))
	if not _corr_grid.has(key):
		return Vector3.ZERO
	var p := Vector2(x, z)
	var best := 1e9
	var ysum := 0.0
	var gsum := 0.0
	var wsum := 0.0
	for idx in (_corr_grid[key] as PackedInt32Array):
		var leg: Array = _corr[idx]
		var a: Vector2 = leg[0]
		var ab: Vector2 = (leg[1] as Vector2) - a
		var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		if d < best:
			best = d
		if d < reach:
			# Blended, not nearest wins. Where two routes ran eleven metres
			# apart the carriageway snapped to one or the other and there was
			# a five metre step down the middle of the road.
			var k: float = 1.0 / (d * d + 1.5)
			ysum += lerpf(float(leg[2]), float(leg[3]), t) * k
			gsum += lerpf(float(leg[4]), float(leg[5]), t) * k
			wsum += k
	if best > reach or wsum <= 0.0:
		return Vector3.ZERO
	return Vector3(ysum / wsum, 1.0 - smoothstep(ROAD_HALF, reach, best),
		gsum / wsum)

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
const RT_CELL := 400.0           # search grid
const RT_MARGIN := 9000.0        # how far outside the straight line it may look
const RT_MAX_NODES := 60000      # a hard stop, so a hopeless leg cannot hang
## What the search believes a metre of road still to go will cost it.
##
## This was 0.55, which is exactly the cheapest a metre can be -- flat, dry,
## clear of the field. That makes the estimate admissible, and on level ground
## it is tight. Through hills the real cost of a metre is several times that,
## so the estimate is far too low, the search loses its sense of direction and
## spreads out like Dijkstra until it hits the node cap. A road does not have
## to be provably the shortest one, so the estimate is allowed to run ahead of
## the true cost: it finds a good line in a fraction of the expansions, and
## legs that used to exhaust the budget and fail now finish.
const RT_HEUR := 1.45

var _rt_jobs: Array = []
var _rt_out: Array = []
var _rt_gid := -1

## Runs on a worker. Reads the height field and the airfield keep-out, and
## writes only its own slot.
func _route_job(i: int) -> void:
	var j: Array = _rt_jobs[i]
	_rt_out[i] = route(j[0], j[1])

## A cell as one integer. Offset, not multiplied and added: `ci * N + cj` cannot
## be taken apart again once `cj` is negative -- half the map -- and unwinding
## the path through that arithmetic produced coordinates thousands of kilometres
## from anywhere, which the corridor indexer then tried to build a grid over.
const RT_BIAS := 1048576

func _rt_key(ci: int, cj: int) -> int:
	return (ci + RT_BIAS) * (RT_BIAS * 2) + (cj + RT_BIAS)

## Ground height at a cell, remembered for the length of one route. The cache is
## handed in rather than kept on the object, so several routes can be worked out
## at the same time on different threads.
func _rt_height(ci: int, cj: int, cache: Dictionary, cell: float) -> float:
	var k := _rt_key(ci, cj)
	if cache.has(k):
		return float(cache[k])
	var h := height_at(float(ci) * cell, float(cj) * cell)
	cache[k] = h
	return h

## What one step of road costs, in the same terms the surveyor thinks in.
func _rt_step(ci: int, cj: int, ni: int, nj: int, run: float,
		cache: Dictionary, cell: float) -> float:
	var ha := _rt_height(ci, cj, cache, cell)
	var hb := _rt_height(ni, nj, cache, cell)
	var climb: float = absf(hb - ha)
	var grade: float = climb / run
	var cost: float = run * 0.55 + climb * 1.6 + grade * grade * run * 260.0
	var over: float = maxf(grade - ROAD_GRADE, 0.0)
	cost += over * over * run * 9000.0
	var wx := float(ni) * cell
	var wz := float(nj) * cell
	# Water is crossable -- that is what a bridge is for -- but it is the last
	# resort, not a shortcut across a bay.
	if hb < WATER_LEVEL + 6.0:
		cost += run * 260.0
	if not clear_of_airfield(wx, wz):
		cost += run * 400.0
	if on_runway(wx, wz):
		cost += run * 4000.0
	return cost

func route(a: Vector2, b: Vector2) -> Array:
	# The grid has to suit the leg. At a flat 400 m a hundred kilometre link
	# between two regions needs more cells than the whole node budget just to
	# reach the far end, so it could never finish -- it spent sixty thousand
	# expansions going nowhere, failed, and then did it again for the retry.
	# A long road is not surveyed at the same resolution as a short one.
	var span: float = a.distance_to(b)
	var cell: float = clampf(span / 140.0, RT_CELL, 2600.0)
	var pts := _search(a, b, {}, RT_MARGIN, RT_MAX_NODES, cell)
	if pts.size() < 2:
		# Try harder before giving up. A search fails because it ran out of
		# room to look sideways or out of nodes to expand, and both are just
		# budgets -- a wider box and a bigger allowance usually finds the pass
		# it was one ridge short of.
		pts = _search(a, b, {}, RT_MARGIN * 2.0, RT_MAX_NODES * 2, cell * 1.8)
	if pts.size() < 2:
		# and if there is genuinely no route, there is no road. Drawing the
		# straight line instead put a trunk road through whatever the search
		# had just spent sixty thousand nodes proving it could not cross --
		# mountains and open water included.
		return []
	pts = _pull_straight(pts)
	var out: Array = []
	for i in range(pts.size() - 1):
		out.append([pts[i], pts[i + 1]])
	return out

## A* from a to b over the grid. Returns the cell centres it went through.
func _search(a: Vector2, b: Vector2, cache: Dictionary,
		margin := RT_MARGIN, budget := RT_MAX_NODES,
		cell := RT_CELL) -> PackedVector2Array:
	var ai := int(round(a.x / cell))
	var aj := int(round(a.y / cell))
	var bi := int(round(b.x / cell))
	var bj := int(round(b.y / cell))
	if ai == bi and aj == bj:
		return PackedVector2Array([a, b])
	# the box it may search in: the two ends plus room to go round something
	var m := int(ceil(margin / cell))
	var lo_i: int = mini(ai, bi) - m
	var hi_i: int = maxi(ai, bi) + m
	var lo_j: int = mini(aj, bj) - m
	var hi_j: int = maxi(aj, bj) + m
	var start := _rt_key(ai, aj)
	var goal := _rt_key(bi, bj)
	var came: Dictionary = {}
	# what each key actually is, so the path never has to be decoded back
	var cells: Dictionary = {start: Vector2i(ai, aj), goal: Vector2i(bi, bj)}
	var g: Dictionary = {start: 0.0}
	# A binary heap, not a scan. Taking the cheapest node by looking at every
	# node on the frontier is quadratic in the size of the frontier, and on a
	# thirty kilometre leg that frontier runs to tens of thousands: the search
	# never finished.
	var open_i := PackedInt32Array([ai])
	var open_j := PackedInt32Array([aj])
	var open_f := PackedFloat32Array([0.0])
	var closed: Dictionary = {}
	var expanded := 0
	while open_f.size() > 0 and expanded < budget:
		var ci: int = open_i[0]
		var cj: int = open_j[0]
		var ck := _rt_key(ci, cj)
		var last := open_f.size() - 1
		open_i[0] = open_i[last]
		open_j[0] = open_j[last]
		open_f[0] = open_f[last]
		open_i.resize(last)
		open_j.resize(last)
		open_f.resize(last)
		# sift the replacement back down
		var pos := 0
		while true:
			var l := pos * 2 + 1
			var r := l + 1
			var sm := pos
			if l < open_f.size() and open_f[l] < open_f[sm]:
				sm = l
			if r < open_f.size() and open_f[r] < open_f[sm]:
				sm = r
			if sm == pos:
				break
			var ti := open_i[pos]
			var tj := open_j[pos]
			var tf := open_f[pos]
			open_i[pos] = open_i[sm]
			open_j[pos] = open_j[sm]
			open_f[pos] = open_f[sm]
			open_i[sm] = ti
			open_j[sm] = tj
			open_f[sm] = tf
			pos = sm
		if closed.has(ck):
			continue
		closed[ck] = true
		expanded += 1
		if ck == goal:
			break
		for d in RT_NEIGHBOURS:
			var ni: int = ci + int(d[0])
			var nj: int = cj + int(d[1])
			if ni < lo_i or ni > hi_i or nj < lo_j or nj > hi_j:
				continue
			var nk := _rt_key(ni, nj)
			if closed.has(nk):
				continue
			var run: float = float(d[2]) * cell
			var ng: float = float(g[ck]) + _rt_step(ci, cj, ni, nj, run, cache, cell)
			if g.has(nk) and float(g[nk]) <= ng:
				continue
			g[nk] = ng
			came[nk] = ck
			cells[nk] = Vector2i(ni, nj)
			var hx: float = float(bi - ni) * cell
			var hz: float = float(bj - nj) * cell
			open_i.append(ni)
			open_j.append(nj)
			open_f.append(ng + sqrt(hx * hx + hz * hz) * RT_HEUR)
			# and sift it up into place
			var up := open_f.size() - 1
			while up > 0:
				var par: int = int(floor(float(up - 1) * 0.5))
				if open_f[par] <= open_f[up]:
					break
				var si := open_i[up]
				var sj := open_j[up]
				var sf := open_f[up]
				open_i[up] = open_i[par]
				open_j[up] = open_j[par]
				open_f[up] = open_f[par]
				open_i[par] = si
				open_j[par] = sj
				open_f[par] = sf
				up = par
	if not came.has(goal) and start != goal:
		return PackedVector2Array()
	# unwind
	var rev: Array = []
	var cur := goal
	var guard := 0
	while cur != start and came.has(cur) and guard < 200000:
		rev.append(cur)
		cur = came[cur]
		guard += 1
	rev.append(start)
	rev.reverse()
	var out := PackedVector2Array([a])
	for k in rev:
		var at: Vector2i = cells[k]
		var p := Vector2(float(at.x) * cell, float(at.y) * cell)
		if p.distance_to(out[out.size() - 1]) > cell * 0.5:
			out.append(p)
	out.append(b)
	return out

const RT_NEIGHBOURS := [
	[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0],
	[1, 1, 1.41421], [1, -1, 1.41421], [-1, 1, 1.41421], [-1, -1, 1.41421],
	[2, 1, 2.23607], [2, -1, 2.23607], [-2, 1, 2.23607], [-2, -1, 2.23607],
	[1, 2, 2.23607], [-1, 2, 2.23607], [1, -2, 2.23607], [-1, -2, 2.23607],
]

## Pull the staircase out of a grid path.
##
## A* on a grid can only leave a cell in sixteen directions, so its output is a
## zigzag even across ground that wants a straight road. This drops any waypoint
## that the two either side of it can be joined through no more expensively.
func _pull_straight(pts: PackedVector2Array) -> PackedVector2Array:
	var cur := pts
	for _pass in 4:
		if cur.size() < 3:
			break
		var out := PackedVector2Array([cur[0]])
		var i := 1
		while i < cur.size() - 1:
			var a: Vector2 = out[out.size() - 1]
			var b: Vector2 = cur[i]
			var c: Vector2 = cur[i + 1]
			var bent: float = _leg_cost(a, b) + _leg_cost(b, c)
			var direct: float = _leg_cost(a, c)
			if direct <= bent * 1.02:
				i += 1                      # b earns nothing: leave it out
				continue
			out.append(b)
			i += 1
		out.append(cur[cur.size() - 1])
		if out.size() == cur.size():
			break
		cur = out
	return cur

## What a straight leg between two points would cost, sampled along it.
func _leg_cost(a: Vector2, b: Vector2) -> float:
	var d := a.distance_to(b)
	if d < 1.0:
		return 0.0
	var steps: int = clampi(int(d / 120.0), 2, 40)
	var cost: float = d * 0.55
	var last := height_at(a.x, a.y)
	var run: float = d / float(steps)
	for i in range(1, steps + 1):
		var q: Vector2 = a.lerp(b, float(i) / float(steps))
		var h := height_at(q.x, q.y)
		var climb: float = absf(h - last)
		var grade: float = climb / run
		cost += climb * 1.6 + grade * grade * run * 260.0
		var over: float = maxf(grade - ROAD_GRADE, 0.0)
		cost += over * over * run * 9000.0
		if h < WATER_LEVEL + 6.0:
			cost += run * 260.0
		if not clear_of_airfield(q.x, q.y):
			cost += run * 400.0
		if on_runway(q.x, q.y):
			cost += run * 4000.0
		last = h
	return cost


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

const RF_HALF := 18000.0     # road field covers the inhabited part of the map
const RF_N := 256

var _road_field := PackedFloat32Array()

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
		"grid": _corr_grid, "segs": _segments, "tunnels": road_tunnels,
		"struct": _road_struct, "natural": _natural}

func load_road_state(d: Dictionary) -> void:
	_town_pads = d["pads"]
	ROADS = d["roads"]
	_road_lines = d["lines"]
	_road_prof = d["prof"]
	road_bridges = d["bridges"]
	_corr = d["corr"]
	_corr_grid = d["grid"]
	_segments = d["segs"]
	road_tunnels = d.get("tunnels", [])
	_road_struct = d.get("struct", [])
	_natural = d.get("natural", [])
	_index_segments()
	# cached in its own right, so this is a read rather than a bake
	_build_road_field()

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
	_index_segments()
	_build_road_field()

## Bake a distance-to-road field once. The terrain asks for this at every one of
## a hundred thousand vertices, and walking a hundred-plus segments each time
## was costing more than the rest of world generation put together.
##
## 256 x 256 texels against 164 segments is ten and a half million distance
## tests, and in GDScript that was thirteen and a half seconds of a twenty-four
## second start -- the single largest thing between launching the game and
## seeing it. Three things fixed it, in order of what they were worth: the rows
## go out to the worker pool, the segments are flattened into a float array so
## the inner loop is not unboxing Variants out of an array of arrays, and a
## bounding box reject skips the projection for segments that cannot win.
const RF_STRIDE := 9             # ax az dx dz 1/len2 minx maxx minz maxz

var _rf_segs := PackedFloat32Array()
var _rf_rows: Array = []
var _rf_count := 0

func _build_road_field() -> void:
	var t0 := Time.get_ticks_msec()
	var cached: Variant = WorldBake.get_baked("road_field")
	if cached is PackedFloat32Array and (cached as PackedFloat32Array).size() == RF_N * RF_N:
		_road_field = cached
		road_field_ms = Time.get_ticks_msec() - t0
		return
	# Only the roads that can possibly be the nearest one.
	#
	# The field covers eighteen kilometres around home; the network now runs to
	# the far side of a twelve hundred kilometre map. Every one of those distant
	# segments was being projected against every texel of a box it is four
	# hundred kilometres outside of. The bounding-box reject skipped the
	# arithmetic but not the loop, and at a hundred and thirty million of them
	# that was sixty-seven seconds.
	var reach: float = RF_HALF + 4000.0
	var all: Array = []
	for src in [ROADS, _segments]:
		for r in src:
			var a0: Vector2 = r[0]
			var b0: Vector2 = r[1]
			if minf(a0.x, b0.x) > reach or maxf(a0.x, b0.x) < -reach:
				continue
			if minf(a0.y, b0.y) > reach or maxf(a0.y, b0.y) < -reach:
				continue
			all.append(r)
	_rf_segs = PackedFloat32Array()
	_rf_segs.resize(all.size() * RF_STRIDE)
	for i in all.size():
		var a: Vector2 = all[i][0]
		var b: Vector2 = all[i][1]
		var d := b - a
		var k := i * RF_STRIDE
		_rf_segs[k] = a.x
		_rf_segs[k + 1] = a.y
		_rf_segs[k + 2] = d.x
		_rf_segs[k + 3] = d.y
		_rf_segs[k + 4] = 1.0 / maxf(d.length_squared(), 1e-9)
		_rf_segs[k + 5] = minf(a.x, b.x)
		_rf_segs[k + 6] = maxf(a.x, b.x)
		_rf_segs[k + 7] = minf(a.y, b.y)
		_rf_segs[k + 8] = maxf(a.y, b.y)
	_rf_count = all.size()
	if native != null:
		# Flat pairs for the extension, which brute-forces what is left across
		# every core.
		var flat := PackedFloat32Array()
		flat.resize(all.size() * 4)
		for i3 in all.size():
			var a3: Vector2 = all[i3][0]
			var b3: Vector2 = all[i3][1]
			flat[i3 * 4] = a3.x
			flat[i3 * 4 + 1] = a3.y
			flat[i3 * 4 + 2] = b3.x
			flat[i3 * 4 + 3] = b3.y
		_road_field = native.road_field(flat, RF_N, RF_HALF)
		_rf_segs = PackedFloat32Array()
		WorldBake.put("road_field", _road_field)
		road_field_ms = Time.get_ticks_msec() - t0
		return
	_rf_rows = []
	_rf_rows.resize(RF_N)
	# One task per row, each writing only its own slot of a pre-sized array and
	# reading only immutable input. Nothing here touches the scene tree, which
	# is the line that matters for doing this off the main thread at all.
	var gid := WorkerThreadPool.add_group_task(_rf_row, RF_N, -1, true,
		"road distance field")
	WorkerThreadPool.wait_for_group_task_completion(gid)
	_road_field = PackedFloat32Array()
	_road_field.resize(RF_N * RF_N)
	for j in RF_N:
		var row: PackedFloat32Array = _rf_rows[j]
		for i2 in RF_N:
			_road_field[j * RF_N + i2] = row[i2]
	_rf_rows = []
	_rf_segs = PackedFloat32Array()
	WorldBake.put("road_field", _road_field)
	road_field_ms = Time.get_ticks_msec() - t0

var road_field_ms := 0

func _rf_row(j: int) -> void:
	var step := RF_HALF * 2.0 / float(RF_N - 1)
	var z := -RF_HALF + float(j) * step
	var row := PackedFloat32Array()
	row.resize(RF_N)
	var m := _rf_count
	for i in RF_N:
		var x := -RF_HALF + float(i) * step
		var best2 := 1e18
		for s in m:
			var k := s * RF_STRIDE
			var ox: float = maxf(maxf(_rf_segs[k + 5] - x, x - _rf_segs[k + 6]), 0.0)
			var oz: float = maxf(maxf(_rf_segs[k + 7] - z, z - _rf_segs[k + 8]), 0.0)
			if ox * ox + oz * oz >= best2:
				continue
			var px: float = x - _rf_segs[k]
			var pz: float = z - _rf_segs[k + 1]
			var dx: float = _rf_segs[k + 2]
			var dz: float = _rf_segs[k + 3]
			var t: float = clampf((px * dx + pz * dz) * _rf_segs[k + 4], 0.0, 1.0)
			var qx: float = px - dx * t
			var qz: float = pz - dz * t
			var d2: float = qx * qx + qz * qz
			if d2 < best2:
				best2 = d2
		row[i] = sqrt(best2)
	_rf_rows[j] = row

const SEG_CELL := 256.0
var _seg_grid: Dictionary = {}   # cell key -> Array of [a, b]

## A cell as one integer, offset so a negative coordinate cannot collide with a
## positive one.
##
## This was `ci * 1048576 + cj`, which is only unique while `|cj|` stays under
## half the multiplier: cell (0, -1) and cell (-1, 1048575) both come out as
## -1. At 256 m cells over a twelve hundred kilometre map the indices reach a
## couple of thousand, so nothing actually collided -- this is a guard against
## the arithmetic, not a fix for an observed fault. The sixty-five seconds that
## indexing the network used to cost was `_build_road_field` brute-forcing the
## whole continental network against a box eighteen kilometres wide; see the
## cull there.
func _seg_key(ci: int, cj: int) -> int:
	return (ci + RT_BIAS) * (RT_BIAS * 2) + (cj + RT_BIAS)

## Index every road and street into a coarse grid. Walking all of them for one
## answer was affordable while everything was inside an 18 km box; with
## settlements spread across the map it is thousands of segments per call.
func _index_segments() -> void:
	_seg_grid = {}
	for src in [ROADS, _segments]:
		for r in src:
			var a: Vector2 = r[0]
			var b: Vector2 = r[1]
			var steps: int = maxi(1, int(a.distance_to(b) / (SEG_CELL * 0.5)))
			var seen: Dictionary = {}
			for k in steps + 1:
				var q: Vector2 = a.lerp(b, float(k) / float(steps))
				var key: int = _seg_key(int(floor(q.x / SEG_CELL)),
					int(floor(q.y / SEG_CELL)))
				if seen.has(key):
					continue
				seen[key] = true
				if not _seg_grid.has(key):
					_seg_grid[key] = []
				(_seg_grid[key] as Array).append(r)

func _road_distance_exact(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	if _seg_grid.is_empty():
		for r0 in ROADS:
			best = minf(best, _seg_dist(p, r0[0], r0[1]))
		for r1 in _segments:
			best = minf(best, _seg_dist(p, r1[0], r1[1]))
		return best
	# the nine cells around the point: a segment further away than a cell and a
	# half cannot be the nearest one to anything in the middle cell
	var ci := int(floor(x / SEG_CELL))
	var cj := int(floor(z / SEG_CELL))
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var key2: int = _seg_key(ci + di, cj + dj)
			if not _seg_grid.has(key2):
				continue
			for r in (_seg_grid[key2] as Array):
				best = minf(best, _seg_dist(p, r[0], r[1]))
				if best < 1.0:
					return best
	return best if best < SEG_CELL else 9999.0

## Distance in metres from (x, z) to the nearest road or street centreline,
## bilinearly sampled from the baked field.
func road_distance(x: float, z: float) -> float:
	if _road_field.is_empty():
		return _road_distance_exact(x, z)
	if absf(x) >= RF_HALF or absf(z) >= RF_HALF:
		# outside the baked box the segments are walked directly, which the
		# grid makes cheap -- otherwise every settlement beyond it would be
		# built as though it had no streets
		return _road_distance_exact(x, z)
	# The baked field is a broad phase and nothing more. It is 256 samples over
	# 36 km — 141 m to a cell — and a carriageway is fifteen metres wide, so it
	# cannot resolve a road at all: measured standing on the centreline it
	# reported a mean of 30 m away and up to 85 m, and at one point in five it
	# said far enough that the terrain painted no road there. The network came
	# out as a faint broken smear instead of roads. Anywhere the coarse answer
	# is close enough to matter, the segments are walked properly. The threshold is
	# the stain radius plus the worst error the coarse field was measured making.
	var coarse := _sample_road_field(x, z)
	if coarse > 170.0:
		return coarse
	return _road_distance_exact(x, z)

func _sample_road_field(x: float, z: float) -> float:
	var step := RF_HALF * 2.0 / float(RF_N - 1)
	var fx := (x + RF_HALF) / step
	var fz := (z + RF_HALF) / step
	# Clamped both ways. Asked about somewhere outside the baked box -- which
	# happens now that there are settlements beyond it -- this indexed the array
	# four hundred thousand elements before its start.
	var i: int = clampi(int(fx), 0, RF_N - 2)
	var j: int = clampi(int(fz), 0, RF_N - 2)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var a: float = _road_field[j * RF_N + i]
	var b: float = _road_field[j * RF_N + i + 1]
	var c: float = _road_field[(j + 1) * RF_N + i]
	var d: float = _road_field[(j + 1) * RF_N + i + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Can something be built here? Rejects water, steep ground, roads and the field.
## `road_clear` is the half-width of the thing being placed. Each road is then
## checked against its own width rather than against one number for everything:
## the old flat sixteen metres was the carriageway and its kerbs and nothing
## else, so a twenty-four metre building placed at exactly sixteen had four
## metres of itself in the road — 62 of 3641 town buildings. Making that one
## number big enough for a motorway then deleted more than half the town,
## because a ten metre street was demanding a motorway's clearance.
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
	if _road_field.is_empty() and _seg_grid.is_empty():
		return true
	# Through the guarded, grid-indexed distance rather than a walk of every
	# road on the map: this used to sample the baked field with no bounds check
	# and then compare against all nine thousand legs, which was tolerable while
	# everything built stood inside one box and is not now.
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
	var pick := int(floor((n * 0.5 + m * 0.5 + 1.0) * 3.0))
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
func _add(action: StringName, events: Array) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action, 0.15)
	for e in events:
		InputMap.action_add_event(action, e)

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e

func _mb(idx: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	return e

func _setup_input() -> void:
	_add(&"pitch_up",     [_key(KEY_S), _key(KEY_DOWN)])
	_add(&"pitch_down",   [_key(KEY_W), _key(KEY_UP)])
	_add(&"roll_left",    [_key(KEY_A), _key(KEY_LEFT)])
	_add(&"roll_right",   [_key(KEY_D), _key(KEY_RIGHT)])
	_add(&"yaw_left",     [_key(KEY_Q)])
	_add(&"yaw_right",    [_key(KEY_E)])
	_add(&"throttle_up",  [_key(KEY_SHIFT)])
	_add(&"throttle_down",[_key(KEY_CTRL), _key(KEY_Z)])
	_add(&"brakes",       [_key(KEY_X)])
	_add(&"gear",         [_key(KEY_G)])
	_add(&"bay",          [_key(KEY_B)])
	_add(&"flaps",        [_key(KEY_F)])
	# Left click is the trigger, everywhere. Right click is deliberately NOT a
	# weapon: it is the sensor page chord with ALT, and having it also launch
	# meant reaching for the pod put a missile off the rail.
	_add(&"fire",         [_key(KEY_SPACE), _mb(MOUSE_BUTTON_LEFT)])
	# V is the dedicated cannon key. It is off the mouse: left click already
	# pulls the trigger, and having both meant one click fired the gun and a
	# missile at the same time.
	_add(&"gun",          [_key(KEY_V)])
	_add(&"cycle_weapon", [_key(KEY_BACKSLASH)])
	_add(&"action_menu",  [_key(KEY_TAB)])
	_add(&"weapon_1",     [_key(KEY_1)])
	_add(&"weapon_2",     [_key(KEY_2)])
	_add(&"weapon_3",     [_key(KEY_3)])
	_add(&"weapon_4",     [_key(KEY_4)])
	# a loaded strike aircraft carries more than four types now
	_add(&"weapon_5",     [_key(KEY_5)])
	_add(&"weapon_6",     [_key(KEY_6)])
	_add(&"weapon_7",     [_key(KEY_7)])
	_add(&"weapon_8",     [_key(KEY_8)])
	_add(&"cycle_target", [_key(KEY_T)])
	# C is flares now, so the view moved to P. Night vision wanted a key that
	# works in every seat and every view, and N was the obvious one.
	_add(&"camera",       [_key(KEY_P)])
	_add(&"night_vision", [_key(KEY_N)])
	_add(&"look_back",    [_key(KEY_Z)])
	_add(&"freelook",     [_key(KEY_ALT), _key(KEY_META)])
	_add(&"interact",     [_key(KEY_U)])
	_add(&"crouch",       [_key(KEY_CTRL), _key(KEY_C)])
	_add(&"panel_left",   [_key(KEY_BRACKETLEFT)])
	_add(&"panel_right",  [_key(KEY_BRACKETRIGHT)])
	_add(&"laser",        [_key(KEY_L)])
	# Not G: that is the landing gear, and on the gunship the two fought over
	# the same key — you could not raise the gear without being thrown into the
	# battery, or take the battery without cycling the gear.
	_add(&"gunner_station", [_key(KEY_J)])
	_add(&"radar_out",    [_key(KEY_EQUAL)])
	_add(&"radar_in",     [_key(KEY_MINUS)])
	_add(&"dive",         [_key(KEY_PAGEDOWN)])
	_add(&"surface",      [_key(KEY_PAGEUP)])
	_add(&"pause_menu",   [_key(KEY_ESCAPE)])
	_add(&"assist",       [_key(KEY_H)])
	_add(&"flare",        [_key(KEY_C)])
	_add(&"chaff",        [_key(KEY_B)])
	_add(&"mouse_fly",    [_key(KEY_SEMICOLON)])
	_add(&"map",          [_key(KEY_M), _key(KEY_F1)])
	# Not backslash: `cycle_weapon` is already there, and `tapped` erases the
	# press when it is read, so whichever of the two was polled first that frame
	# ate the other. Cycling the weapon and slowing time fought over one key.
	_add(&"time_slow",    [_key(KEY_APOSTROPHE)])
