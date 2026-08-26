class_name Weather
extends Node3D
## Cloud deck plus the environment tuning that goes with each weather state.

const PRESETS := {
	"clear": {
		"name": "CLEAR", "cover": 0.34, "hour": 13.2, "clouds": 26, "base": 3400.0, "spread": 18000.0,
		"fog": 7500.0, "fog_end": 42000.0, "sun": 1.18, "amb": 0.70,
		"top": Color(0.13, 0.28, 0.62), "horizon": Color(0.66, 0.75, 0.87),
		"sun_rot": Vector3(-40, 136, 0), "fog_col": Color(0.68, 0.76, 0.86),
		"cloud_tint": Color(1.0, 1.0, 1.0, 0.85), "sun_col": Color(1.0, 0.96, 0.90),
	},
	"scattered": {
		"name": "SCATTERED", "cover": 0.80, "hour": 10.4, "clouds": 70, "base": 2300.0, "spread": 22000.0,
		"fog": 5200.0, "fog_end": 33000.0, "sun": 1.05, "amb": 0.78,
		"top": Color(0.16, 0.30, 0.60), "horizon": Color(0.70, 0.77, 0.86),
		"sun_rot": Vector3(-36, 150, 0), "fog_col": Color(0.72, 0.78, 0.86),
		"cloud_tint": Color(1.0, 1.0, 1.0, 0.88), "sun_col": Color(1.0, 0.95, 0.88),
	},
	"overcast": {
		"name": "OVERCAST", "cover": 1.45, "hour": 15.1, "clouds": 130, "base": 1500.0, "spread": 26000.0,
		"fog": 2600.0, "fog_end": 19000.0, "sun": 0.55, "amb": 0.95,
		"top": Color(0.36, 0.40, 0.46), "horizon": Color(0.62, 0.65, 0.69),
		"sun_rot": Vector3(-52, 120, 0), "fog_col": Color(0.63, 0.66, 0.70),
		"cloud_tint": Color(0.72, 0.74, 0.78, 0.94), "sun_col": Color(0.85, 0.87, 0.92),
	},
	"dusk": {
		"name": "DUSK", "cover": 0.72, "hour": 19.7, "clouds": 52, "base": 2800.0, "spread": 20000.0,
		"fog": 4200.0, "fog_end": 28000.0, "sun": 0.85, "amb": 0.55,
		"top": Color(0.09, 0.13, 0.34), "horizon": Color(0.86, 0.48, 0.28),
		"sun_rot": Vector3(-9, 104, 0), "fog_col": Color(0.62, 0.44, 0.38),
		"cloud_tint": Color(1.0, 0.78, 0.62, 0.88), "sun_col": Color(1.0, 0.72, 0.46),
	},
}

var current := "scattered"
var _decks: Array[MultiMeshInstance3D] = []
var _rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ the sun
## Local time in hours. The sun's position is worked out from it properly
## rather than being a fixed rotation per preset, so dawn, noon and dusk are
## the same sky at different times instead of three separate presets.
var time_of_day := 13.5
var time_rate := 1.0 / 240.0          # game hours per real second: a day in 4 h
var _sun_elev := 0.0
var _sun_az := 0.0

const LATITUDE := deg_to_rad(45.0)
const DECLINATION := deg_to_rad(14.0)  # a summer-ish sun

## Elevation and azimuth of the sun for the current time, by the standard solar
## position formulae. Azimuth is measured clockwise from north.
func solar_angles(hours: float) -> Vector2:
	var ha := deg_to_rad((hours - 12.0) * 15.0)
	var sin_e: float = sin(DECLINATION) * sin(LATITUDE) \
		+ cos(DECLINATION) * cos(LATITUDE) * cos(ha)
	var elev := asin(clampf(sin_e, -1.0, 1.0))
	var cos_a: float = (sin(DECLINATION) - sin_e * sin(LATITUDE)) \
		/ maxf(cos(elev) * cos(LATITUDE), 1e-4)
	var az := acos(clampf(cos_a, -1.0, 1.0))
	if ha > 0.0:
		az = TAU - az                  # afternoon: west of south
	return Vector2(elev, az)

func sun_elevation() -> float:
	return _sun_elev

## 0 at night, 1 in full day, with the twilight band in between. Everything
## that has to fade with the light hangs off this.
func daylight() -> float:
	return clampf((_sun_elev + deg_to_rad(6.0)) / deg_to_rad(21.0), 0.0, 1.0)

## How much of the sky is sunset-coloured: strongest with the sun on the
## horizon, gone by the time it is well up or well down.
func twilight() -> float:
	return clampf(1.0 - absf(_sun_elev) / deg_to_rad(12.0), 0.0, 1.0)

static func ids() -> PackedStringArray:
	return PackedStringArray(["clear", "scattered", "overcast", "dusk"])

## Cloud layers, in the order they are built. Bases are where weather actually
## sits: fair-weather cumulus around six or seven thousand feet with real
## vertical development above it, altocumulus in the middle teens, and cirrus up
## where a jet cruises. The old single deck put everything between 1500 m and
## 3400 m, which is below the tops of the hills in places and means you climb
## through the entire sky in the first thirty seconds.
const LAYERS := [
	{"name": "cumulus", "base": 2200.0, "depth": 1400.0, "puff": 520.0,
	 "flat": 0.62, "density": 1.0, "cell": 12000.0},
	{"name": "altocumulus", "base": 5200.0, "depth": 700.0, "puff": 780.0,
	 "flat": 0.38, "density": 0.7, "cell": 16000.0},
	{"name": "cirrus", "base": 9400.0, "depth": 500.0, "puff": 1600.0,
	 "flat": 0.16, "density": 0.5, "cell": 22000.0},
]

## How far the field reaches, and how the detail is banded. A cell close enough
## to matter is drawn from its detailed batch; past that a coarse batch of
## fewer, larger puffs stands in for it, and past the last range nothing is
## drawn at all. Godot's visibility range works per node against that node's own
## bounds, so the field has to be cut into cells for any of this to do
## anything — one node covering the whole sky is always in range of everything.
const FIELD := 46000.0
const NEAR_RANGE := 14000.0
const FAR_RANGE := 52000.0

func apply(id: String, env: Environment, sun: DirectionalLight3D,
		fill: DirectionalLight3D, psm: ProceduralSkyMaterial) -> void:
	current = id if PRESETS.has(id) else "scattered"
	var p: Dictionary = PRESETS[current]
	psm.sky_top_color = p["top"]
	psm.sky_horizon_color = p["horizon"]
	psm.ground_horizon_color = p["horizon"].darkened(0.05)
	env.fog_light_color = p["fog_col"]
	env.fog_depth_begin = p["fog"]
	env.fog_depth_end = p["fog_end"]
	env.ambient_light_energy = p["amb"]
	sun.light_energy = p["sun"]
	sun.light_color = p["sun_col"]
	sun.rotation_degrees = p["sun_rot"]
	fill.light_energy = 0.3 if current != "overcast" else 0.5
	if p.has("hour"):
		time_of_day = float(p["hour"])
	_env = env
	_sun_node = sun
	_fill_node = fill
	_psm = psm
	_build_decks(p)
	_apply_sun(true)
	set_process(true)

var _env: Environment
var _sun_node: DirectionalLight3D
var _fill_node: DirectionalLight3D
var _psm: ProceduralSkyMaterial

func _process(delta: float) -> void:
	if _sun_node == null or not is_instance_valid(_sun_node):
		return
	if time_rate > 0.0:
		time_of_day = fposmod(time_of_day + delta * time_rate, 24.0)
	_apply_sun(false)

## Put the sun where the clock says it is, and colour the world to match.
func _apply_sun(_force: bool) -> void:
	var sa := solar_angles(time_of_day)
	_sun_elev = sa.x
	_sun_az = sa.y
	var p: Dictionary = PRESETS[current]
	# A directional light shines down its own -Z. Pitch it down by the sun's
	# elevation and swing it to the sun's bearing plus half a turn, so the light
	# travels *from* the sun rather than towards it.
	_sun_node.rotation = Vector3(-_sun_elev, _sun_az + PI, 0.0)
	var day := daylight()
	var dusk := twilight()
	# Below the horizon there is no sun, only what the sky scatters back.
	_sun_node.light_energy = float(p["sun"]) * day
	var warm := Color(1.0, 0.62, 0.34)
	_sun_node.light_color = Color(p["sun_col"]).lerp(warm, dusk * 0.85)
	_sun_node.shadow_enabled = day > 0.06
	# Moonlight stands in for the fill once the sun has gone.
	var night := 1.0 - day
	_fill_node.light_energy = lerpf(0.3 if current != "overcast" else 0.5, 0.10, night)
	_fill_node.light_color = Color(0.72, 0.82, 1.0).lerp(Color(0.55, 0.66, 0.95), night)
	if _psm != null:
		var top := Color(p["top"])
		var horizon := Color(p["horizon"])
		var night_top := Color(0.012, 0.017, 0.045)
		var night_horizon := Color(0.045, 0.055, 0.10)
		var dusk_horizon := Color(0.86, 0.42, 0.24)
		_psm.sky_top_color = top.lerp(night_top, night)
		_psm.sky_horizon_color = horizon.lerp(dusk_horizon, dusk * 0.8) \
			.lerp(night_horizon, night * 0.9)
		_psm.ground_horizon_color = _psm.sky_horizon_color.darkened(0.15)
		_psm.sun_angle_max = 6.0
	if _env != null:
		_env.ambient_light_energy = lerpf(float(p["amb"]), 0.16, night)
		_env.fog_light_color = Color(p["fog_col"]) \
			.lerp(Color(0.55, 0.30, 0.22), dusk * 0.7) \
			.lerp(Color(0.05, 0.06, 0.11), night * 0.9)
	# and the clouds are lit by whatever is lighting everything else
	var tint := Color(p["cloud_tint"])
	var lit := tint.lerp(Color(1.0, 0.66, 0.42, tint.a), dusk * 0.8) \
		.lerp(Color(0.16, 0.19, 0.30, tint.a), night * 0.88)
	for d in _decks:
		if is_instance_valid(d) and d.material_override is StandardMaterial3D:
			(d.material_override as StandardMaterial3D).albedo_color = lit


func _cloud_material(p: Dictionary) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = Effects.puff_texture()
	m.albedo_color = p["cloud_tint"]
	m.disable_receive_shadows = true
	# Clouds sort behind everything else that is transparent, for the same
	# reason the sea does: they are enormous and their origins are nowhere near
	# what you are looking at.
	m.render_priority = -6
	return m

## Build the sky, layer by layer, cell by cell.
##
## Each cell gets two batches: a detailed one of many small puffs that is drawn
## while you are near it, and a coarse one of a few large puffs that stands in
## once you are not. The swap is Godot's own visibility range, so it costs
## nothing per frame — but it only works because the field is cut into cells.
func _build_decks(p: Dictionary) -> void:
	for d in _decks:
		if is_instance_valid(d):
			# out of the tree now, not at the end of the frame: anything that
			# counts the sky between a rebuild and the next frame otherwise
			# sees the old deck and the new one at once
			remove_child(d)
			d.queue_free()
	_decks.clear()
	_rng.seed = 4242
	_band = Vector2(1e9, -1e9)
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var mat := _cloud_material(p)
	var cover: float = float(p["cover"]) if p.has("cover") else 1.0
	var puffs_total := 0
	for layer in LAYERS:
		var cell: float = float(layer["cell"])
		var n: int = int(FIELD / cell)
		for gx in range(-n, n + 1):
			for gz in range(-n, n + 1):
				var origin := Vector2(float(gx) * cell, float(gz) * cell)
				if origin.length() > FIELD:
					continue
				puffs_total += _build_cell(qm, mat, layer, origin, cell, cover)
	_stat_puffs = puffs_total
	if _band.x > 1e8:
		_band = Vector2.ZERO

var _stat_puffs := 0
var _band := Vector2.ZERO

func puff_count() -> int:
	return _stat_puffs

## Lowest and highest puff in the sky, for the harness.
## Lowest and highest puff in the sky. Recorded as the field is built, not read
## back off the MultiMesh: `get_instance_transform` goes through the rendering
## server, which is a stub in headless, so every instance reads as identity
## there and any measurement taken that way is measuring nothing.
func cloud_band() -> Vector2:
	return _band

func deck_count() -> int:
	return _decks.size()

## One cell of one layer, as a detailed batch and a coarse stand-in.
func _build_cell(qm: QuadMesh, mat: StandardMaterial3D, layer: Dictionary,
		origin: Vector2, cell: float, cover: float) -> int:
	var density: float = float(layer["density"]) * cover
	# Cells are large — a dozen kilometres or more — because each one is two
	# draw calls and the field covers ninety kilometres across. Cutting it into
	# five kilometre cells produced four thousand batches, which is a worse
	# problem than the one the cells were there to solve.
	var clumps: int = int(round(_rng.randf_range(5.0, 11.0) * density))
	if clumps <= 0:
		return 0
	var near_xf: Array[Transform3D] = []
	var far_xf: Array[Transform3D] = []
	for c in clumps:
		var cx: float = origin.x + _rng.randf_range(-0.5, 0.5) * cell
		var cz: float = origin.y + _rng.randf_range(-0.5, 0.5) * cell
		var cy: float = float(layer["base"]) \
			+ _rng.randf_range(0.0, float(layer["depth"]))
		var w: float = _rng.randf_range(0.30, 0.75) * cell
		var flat: float = float(layer["flat"])
		var base_puff: float = float(layer["puff"])
		# the detailed version: a heap of small puffs with real vertical build
		var count: int = _rng.randi_range(11, 20)
		for i in count:
			var o := Vector3(_rng.randf_range(-w, w),
				_rng.randf_range(-0.12, 1.0) * float(layer["depth"]) * 0.55,
				_rng.randf_range(-w * 0.75, w * 0.75))
			# puffs get smaller and sparser toward the top, which is what gives
			# a cumulus its cauliflower rather than a flat slab
			var lift: float = clampf(o.y / maxf(float(layer["depth"]) * 0.55, 1.0), 0.0, 1.0)
			var sz: float = base_puff * _rng.randf_range(0.65, 1.5) * (1.0 - 0.45 * lift)
			near_xf.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					.scaled(Vector3(sz, sz * flat * (1.0 + lift * 0.5), sz)),
				Vector3(cx, cy, cz) + o))
		# and the stand-in: a handful of big ones covering the same volume
		for i in 4:
			var o2 := Vector3(_rng.randf_range(-w, w),
				_rng.randf_range(0.0, float(layer["depth"]) * 0.4),
				_rng.randf_range(-w * 0.75, w * 0.75))
			var sz2: float = base_puff * _rng.randf_range(2.4, 3.6)
			far_xf.append(Transform3D(
				Basis().scaled(Vector3(sz2, sz2 * flat, sz2)),
				Vector3(cx, cy, cz) + o2))
	# The cell is in the name: Godot renames colliding siblings, and anything
	# classifying batches by a trailing "_near"/"_far" then sees one of each and
	# several hundred it cannot place.
	var tag := "%s_%d_%d" % [layer["name"], int(origin.x / cell), int(origin.y / cell)]
	_add_batch(qm, mat, near_xf, "near_" + tag, 0.0, NEAR_RANGE)
	_add_batch(qm, mat, far_xf, "far_" + tag, NEAR_RANGE, FAR_RANGE)
	return near_xf.size() + far_xf.size()

func _add_batch(qm: QuadMesh, mat: StandardMaterial3D, xf: Array[Transform3D],
		nm: String, from: float, to: float) -> void:
	if xf.is_empty():
		return
	for t in xf:
		_band.x = minf(_band.x, t.origin.y)
		_band.y = maxf(_band.y, t.origin.y)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nm
	var mm := MultiMesh.new()
	# Order matters: the transform format sizes the buffer, the count allocates
	# it, and the mesh goes on last. Assigning the mesh in the middle threw the
	# transforms away and left every puff sitting at the world origin.
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = qm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_begin = from
	mmi.visibility_range_end = to
	mmi.visibility_range_begin_margin = 900.0 if from > 0.0 else 0.0
	mmi.visibility_range_end_margin = 1400.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	_decks.append(mmi)
