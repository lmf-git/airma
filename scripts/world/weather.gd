class_name Weather
extends Node3D
## Cloud deck plus the environment tuning that goes with each weather state.

const PRESETS := {
	"clear": {
		"name": "CLEAR", "clouds": 26, "base": 3400.0, "spread": 18000.0,
		"fog": 7500.0, "fog_end": 42000.0, "sun": 1.18, "amb": 0.70,
		"top": Color(0.13, 0.28, 0.62), "horizon": Color(0.66, 0.75, 0.87),
		"sun_rot": Vector3(-40, 136, 0), "fog_col": Color(0.68, 0.76, 0.86),
		"cloud_tint": Color(1.0, 1.0, 1.0, 0.85), "sun_col": Color(1.0, 0.96, 0.90),
	},
	"scattered": {
		"name": "SCATTERED", "clouds": 70, "base": 2300.0, "spread": 22000.0,
		"fog": 5200.0, "fog_end": 33000.0, "sun": 1.05, "amb": 0.78,
		"top": Color(0.16, 0.30, 0.60), "horizon": Color(0.70, 0.77, 0.86),
		"sun_rot": Vector3(-36, 150, 0), "fog_col": Color(0.72, 0.78, 0.86),
		"cloud_tint": Color(1.0, 1.0, 1.0, 0.88), "sun_col": Color(1.0, 0.95, 0.88),
	},
	"overcast": {
		"name": "OVERCAST", "clouds": 130, "base": 1500.0, "spread": 26000.0,
		"fog": 2600.0, "fog_end": 19000.0, "sun": 0.55, "amb": 0.95,
		"top": Color(0.36, 0.40, 0.46), "horizon": Color(0.62, 0.65, 0.69),
		"sun_rot": Vector3(-52, 120, 0), "fog_col": Color(0.63, 0.66, 0.70),
		"cloud_tint": Color(0.72, 0.74, 0.78, 0.94), "sun_col": Color(0.85, 0.87, 0.92),
	},
	"dusk": {
		"name": "DUSK", "clouds": 52, "base": 2800.0, "spread": 20000.0,
		"fog": 4200.0, "fog_end": 28000.0, "sun": 0.85, "amb": 0.55,
		"top": Color(0.09, 0.13, 0.34), "horizon": Color(0.86, 0.48, 0.28),
		"sun_rot": Vector3(-9, 104, 0), "fog_col": Color(0.62, 0.44, 0.38),
		"cloud_tint": Color(1.0, 0.78, 0.62, 0.88), "sun_col": Color(1.0, 0.72, 0.46),
	},
}

var current := "scattered"
var _deck: MultiMeshInstance3D
var _rng := RandomNumberGenerator.new()

static func ids() -> PackedStringArray:
	return PackedStringArray(["clear", "scattered", "overcast", "dusk"])

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
	_build_deck(p)

func _build_deck(p: Dictionary) -> void:
	if _deck:
		_deck.queue_free()
	_rng.seed = 4242
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_texture = Effects.puff_texture()
	m.albedo_color = p["cloud_tint"]
	m.disable_receive_shadows = true
	m.no_depth_test = false
	qm.material = m

	var xf: Array[Transform3D] = []
	var clouds: int = p["clouds"]
	for c in clouds:
		var cx: float = _rng.randf_range(-1.0, 1.0) * float(p["spread"])
		var cz: float = _rng.randf_range(-1.0, 1.0) * float(p["spread"])
		var cy: float = float(p["base"]) + _rng.randf_range(-320.0, 620.0)
		var puffs := _rng.randi_range(7, 14)
		var w := _rng.randf_range(600.0, 1500.0)
		for i in puffs:
			var o := Vector3(_rng.randf_range(-w, w), _rng.randf_range(-90.0, 130.0),
				_rng.randf_range(-w * 0.7, w * 0.7))
			var sz := _rng.randf_range(420.0, 1000.0) * (1.0 - 0.4 * absf(o.x) / maxf(w, 1.0))
			xf.append(Transform3D(Basis().scaled(Vector3(sz, sz * 0.62, sz)),
				Vector3(cx, cy, cz) + o))
	_deck = MultiMeshInstance3D.new()
	_deck.name = "CloudDeck"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = qm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	_deck.multimesh = mm
	_deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_deck)
