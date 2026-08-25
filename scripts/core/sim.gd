extends Node
## Global services: input map bootstrap, the analytic terrain field, mission
## configuration and scoring. Autoloaded as `Sim`.

const WORLD_HALF := 70000.0      # world extends +/- 70 km
const COAST_X := 15000.0         # open water east of here
const WATER_LEVEL := -35.0
const RUNWAY_LEN := 3000.0       # 36/18, aligned with the Z axis
const RUNWAY_HALF_W := 23.0
const RUNWAY_ELEV := 0.0


signal mission_event(text: String, kind: int)   # kind: 0 info, 1 good, 2 bad

enum Ev { INFO, GOOD, BAD }

var noise_lo := FastNoiseLite.new()
var noise_hi := FastNoiseLite.new()
var noise_det := FastNoiseLite.new()
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
	_setup_noise()
	_setup_input()

func _setup_noise() -> void:
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
	noise_temp.frequency = 0.000028
	noise_temp.fractal_octaves = 2

	noise_moist.seed = 811
	noise_moist.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_moist.frequency = 0.000041
	noise_moist.fractal_octaves = 3

	noise_det.seed = 7
	noise_det.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_det.frequency = 0.0035
	noise_det.fractal_octaves = 2

## How "airfield flat" a spot is: 1 = perfectly level apron, 0 = open terrain.
func flat_factor(x: float, z: float) -> float:
	var dx := maxf(absf(x) - 950.0, 0.0)
	var dz := maxf(absf(z) - 1950.0, 0.0)
	var d := sqrt(dx * dx + dz * dz)
	return 1.0 - smoothstep(0.0, 2600.0, d)

## Terrain elevation in metres. Single source of truth: the visual mesh, the
## landing gear and the crash test all sample this.
func height_at(x: float, z: float) -> float:
	var m := (noise_lo.get_noise_2d(x, z) + 1.0) * 0.5
	m = pow(m, 2.3)
	var h := m * 2100.0
	h += noise_hi.get_noise_2d(x, z) * 150.0 * m
	h += noise_det.get_noise_2d(x, z) * 6.0 * clampf(m * 4.0, 0.15, 1.0)
	h -= 90.0
	# The airfield sits in a north-south valley so both runway approaches and the
	# departure end stay clear of rising ground.
	var axis := clampf((absf(x) - 1000.0) / 3400.0, 0.0, 1.0)
	var cap := 55.0 + axis * axis * 2500.0
	if h > cap:
		h = cap + (h - cap) * 0.12
	# the land runs out to the east: a coastal shelf dropping into open ocean
	var sea := smoothstep(COAST_X, COAST_X + 9000.0, x)
	if sea > 0.0:
		h = lerpf(h, -240.0, sea)
	var f := flat_factor(x, z)
	if f > 0.0:
		h = lerpf(h, RUNWAY_ELEV, f)
	if not decks.is_empty():
		h = maxf(h, deck_height(x, z))
	return h

func normal_at(x: float, z: float) -> Vector3:
	const E := 3.0
	var hl := height_at(x - E, z)
	var hr := height_at(x + E, z)
	var hd := height_at(x, z - E)
	var hu := height_at(x, z + E)
	return Vector3(hl - hr, 2.0 * E, hd - hu).normalized()

func on_runway(x: float, z: float) -> bool:
	return absf(x) <= RUNWAY_HALF_W and absf(z) <= RUNWAY_LEN * 0.5

## Paved surfaces (runway, taxiway loop, apron) roll better than grass.
func surface_grip(x: float, z: float) -> float:
	if deck_height(x, z) > -1e8:
		return 1.0
	if on_runway(x, z):
		return 1.0
	if absf(x) >= 60.0 and absf(x) <= 92.0 and absf(z) <= RUNWAY_LEN * 0.5:
		return 1.0
	if absf(z) <= 1560.0 and absf(x) <= 95.0:
		return 1.0
	return 0.45

## Road network, shared by the terrain painter and the placement rules.
const ROADS := [
	[Vector2(0, 1700), Vector2(-2300, -5200)],
	[Vector2(0, -1700), Vector2(2600, 4200)],
	[Vector2(-2300, -5200), Vector2(2100, -9200)],
	[Vector2(-1900, 3100), Vector2(2600, 4200)],
	[Vector2(-1500, -6600), Vector2(-2300, -5200)],
	[Vector2(2600, 4200), Vector2(4200, 11000)],
	[Vector2(-2300, -5200), Vector2(-5200, -13000)],
]

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

func register_segments(segs: Array) -> void:
	_segments = segs
	_build_road_field()

## Bake a distance-to-road field once. The terrain asks for this at every one of
## a hundred thousand vertices, and walking a hundred-plus segments each time
## was costing more than the rest of world generation put together.
func _build_road_field() -> void:
	_road_field = PackedFloat32Array()
	_road_field.resize(RF_N * RF_N)
	var step := RF_HALF * 2.0 / float(RF_N - 1)
	for j in RF_N:
		var z := -RF_HALF + float(j) * step
		for i in RF_N:
			var x := -RF_HALF + float(i) * step
			_road_field[j * RF_N + i] = _road_distance_exact(x, z)

func _road_distance_exact(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := 1e9
	for r in ROADS:
		best = minf(best, _seg_dist(p, r[0], r[1]))
		if best < 1.0:
			return best
	for r in _segments:
		best = minf(best, _seg_dist(p, r[0], r[1]))
		if best < 1.0:
			return best
	return best

## Distance in metres from (x, z) to the nearest road or street centreline,
## bilinearly sampled from the baked field.
func road_distance(x: float, z: float) -> float:
	if _road_field.is_empty():
		return _road_distance_exact(x, z)
	if absf(x) >= RF_HALF or absf(z) >= RF_HALF:
		return 9999.0
	var step := RF_HALF * 2.0 / float(RF_N - 1)
	var fx := (x + RF_HALF) / step
	var fz := (z + RF_HALF) / step
	var i := int(fx)
	var j := int(fz)
	if i >= RF_N - 1:
		i = RF_N - 2
	if j >= RF_N - 1:
		j = RF_N - 2
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
func buildable(x: float, z: float, flat := 0.86, clearance := 4.0) -> bool:
	var y := height_at(x, z)
	if y < WATER_LEVEL + clearance:
		return false
	if normal_at(x, z).y < flat:
		return false
	if road_distance(x, z) < 16.0:
		return false
	if absf(x) < 340.0 and absf(z) < 2100.0:
		return false
	return true

## A wider keep-out for anything tall: pylons, masts and turbines must not stand
## in the approach path or on the airfield itself.
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
func biome_weights(x: float, z: float, y: float, slope: float) -> PackedFloat32Array:
	var temp: float = clampf((noise_temp.get_noise_2d(x, z) + 1.0) * 0.5
		- clampf((y - 300.0) / 2200.0, 0.0, 1.0) * 0.85, 0.0, 1.0)
	var moist: float = clampf((noise_moist.get_noise_2d(x, z) + 1.0) * 0.5
		+ clampf(1.0 - absf(y - WATER_LEVEL) / 900.0, 0.0, 1.0) * 0.25, 0.0, 1.0)
	var steep: float = clampf((0.90 - slope) / 0.34, 0.0, 1.0)
	_bw[B_SNOW] = clampf((y - 1500.0) / 700.0, 0.0, 1.0) * (1.0 - steep * 0.7) \
		* clampf(1.0 - temp * 1.4, 0.0, 1.0) + clampf((y - 2400.0) / 500.0, 0.0, 1.0)
	_bw[B_ROCK] = steep + clampf((y - 1100.0) / 1400.0, 0.0, 1.0) * 0.5
	_bw[B_FOREST] = clampf(moist * 1.5 - 0.35, 0.0, 1.0) * clampf(temp * 1.6, 0.0, 1.0) \
		* clampf(1.0 - (y - 200.0) / 1500.0, 0.0, 1.0)
	_bw[B_GRASS] = clampf(1.0 - absf(moist - 0.55) * 2.4, 0.0, 1.0) \
		* clampf(1.0 - (y - 400.0) / 1600.0, 0.0, 1.0)
	_bw[B_STEPPE] = clampf(0.62 - moist, 0.0, 1.0) * 1.7 * clampf(temp * 1.3, 0.0, 1.0)
	_bw[B_SAND] = clampf(1.0 - absf(y - WATER_LEVEL) / 26.0, 0.0, 1.0) * 1.4 \
		+ clampf(0.30 - moist, 0.0, 1.0) * clampf(temp - 0.55, 0.0, 1.0) * 3.0
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

func biome_colour(x: float, z: float, y: float, slope: float) -> Color:
	var w := biome_weights(x, z, y, slope)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	for i in 7:
		var c: Color = BIOME_COLOURS[i]
		var k: float = w[i]
		r += c.r * k
		g += c.g * k
		b += c.b * k
	return Color(r, g, b)

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
	_add(&"camera",       [_key(KEY_C)])
	_add(&"look_back",    [_key(KEY_Z)])
	_add(&"freelook",     [_key(KEY_ALT), _key(KEY_META)])
	_add(&"interact",     [_key(KEY_U)])
	_add(&"crouch",       [_key(KEY_CTRL), _key(KEY_C)])
	_add(&"panel_left",   [_key(KEY_BRACKETLEFT)])
	_add(&"panel_right",  [_key(KEY_BRACKETRIGHT)])
	_add(&"laser",        [_key(KEY_L)])
	_add(&"gunner_station", [_key(KEY_G)])
	_add(&"radar_out",    [_key(KEY_EQUAL)])
	_add(&"radar_in",     [_key(KEY_MINUS)])
	_add(&"respawn",      [_key(KEY_R)])
	_add(&"pause_menu",   [_key(KEY_ESCAPE)])
	_add(&"assist",       [_key(KEY_H)])
	_add(&"flare",        [_key(KEY_N)])
	_add(&"mouse_fly",    [_key(KEY_SEMICOLON)])
	_add(&"map",          [_key(KEY_M), _key(KEY_F1)])
	_add(&"time_slow",    [_key(KEY_BACKSLASH)])
