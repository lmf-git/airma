class_name Shockwave
extends Node3D
## The blast wave from a nuclear burst, seen: a wall of dust and dirty air
## running out along the ground, and for the first moments the white dome of
## condensation that shows the front in the air. It travels at the same speed
## the town comes down at (`Scenery.SHOCK_SPEED`), so the wave reaches each
## building as it falls.

## How far the wave is drawn out to, and how fast it goes.
var reach := 1000.0
var speed := 500.0
var _t := 0.0
var _band: MeshInstance3D = null
var _dome: MeshInstance3D = null
var _band_mat: ShaderMaterial = null
var _dome_mat: ShaderMaterial = null
var _dust_r := 0.0

const BAND_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 colour : source_color = vec4(0.66, 0.60, 0.52, 0.8);
uniform float fade = 1.0;
varying float h;
void vertex() {
	h = VERTEX.y + 0.5;
}
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	// billows round the ring and up the wall, rolling as it goes, so the top
	// is a ragged edge of dust and not the rim of a glass
	vec2 q = vec2(UV.x * 90.0, h * 4.0 - TIME * 0.6);
	float n = vn(q) * 0.6 + vn(q * 2.3 + 7.0) * 0.4;
	float top = 1.0 - smoothstep(0.15 + n * 0.45, 0.55 + n * 0.45, h);
	float a = smoothstep(0.0, 0.08, h) * top * (0.55 + 0.45 * n);
	ALBEDO = colour.rgb * (0.85 + 0.25 * n);
	ALPHA = colour.a * a * fade;
}
"""

const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float fade = 1.0;
void fragment() {
	// seen edge-on it is a bright rim, face-on almost nothing
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	ALBEDO = vec3(0.95, 0.96, 0.98);
	ALPHA = rim * 0.75 * fade;
}
"""

static var _band_sh: Shader = null
static var _dome_sh: Shader = null

func _ready() -> void:
	if _band_sh == null:
		_band_sh = Shader.new()
		_band_sh.code = BAND_SHADER
		_dome_sh = Shader.new()
		_dome_sh.code = DOME_SHADER
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_band_mat = ShaderMaterial.new()
	_band_mat.shader = _band_sh
	_band = MeshInstance3D.new()
	_band.mesh = cyl
	_band.material_override = _band_mat
	_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_band)
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 1.0
	sph.is_hemisphere = true
	sph.radial_segments = 48
	sph.rings = 12
	_dome_mat = ShaderMaterial.new()
	_dome_mat.shader = _dome_sh
	_dome = MeshInstance3D.new()
	_dome.mesh = sph
	_dome.material_override = _dome_mat
	_dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dome)
	_place(0.0)

func _process(delta: float) -> void:
	_t += delta
	var r: float = _t * speed
	if r > reach * 1.15:
		queue_free()
		return
	_place(r)
	# dust thrown up along the front as it goes, a ring at a time
	if r - _dust_r > maxf(reach * 0.12, 20.0):
		_dust_r = r
		var n: int = clampi(int(r / 25.0), 6, 18)
		var world := get_tree().current_scene
		for i in n:
			var a: float = TAU * (float(i) + randf() * 0.5) / float(n)
			var p: Vector3 = global_position + Vector3(cos(a), 0.0, sin(a)) * r
			p.y = Sim.height_at(p.x, p.z)
			Effects.dust(world, p, clampf(reach * 0.05, 4.0, 40.0))

func _place(r: float) -> void:
	var k: float = clampf(r / reach, 0.0, 1.0)
	# the wall: as tall as a tenth of the reach to start, settling lower
	var tall: float = maxf(reach * lerpf(0.14, 0.06, k), 8.0)
	_band.scale = Vector3(maxf(r, 1.0), tall, maxf(r, 1.0))
	_band.position = Vector3(0.0, tall * 0.5 - tall * 0.1, 0.0)
	_band_mat.set_shader_parameter("fade", 1.0 - k * k)
	# the dome is quick and brief: gone by a third of the way out
	var dk: float = clampf(r / (reach * 0.35), 0.0, 1.0)
	_dome.visible = dk < 1.0
	_dome.scale = Vector3.ONE * maxf(r, 1.0)
	_dome_mat.set_shader_parameter("fade", 1.0 - dk)
