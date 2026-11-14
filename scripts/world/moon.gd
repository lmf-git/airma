class_name Moon
extends Node3D
## The moon.
##
## It is 384 400 km away and the furthest thing the eye can be asked to draw is
## a few thousand, so it cannot simply be put where it is. It does not need to
## be: from anywhere a player can get to it subtends half a degree and nothing
## passes behind it. So it is carried at a fixed fraction of the camera's far
## plane along the line to where it really is, shrunk in the same proportion --
## the same half a degree, in the same place in the sky, at a distance the
## depth buffer can hold. Hills, aeroplanes and the planet's own limb are all
## nearer than that and hide it as they should.
##
## Where it really is comes from `Sim.moon_dir`, which is also what a
## spacecraft's sums pull towards, so the thing in the sky and the thing
## bending an orbit are one body.
##
## It is lit by the same sun as everything else: the phase is not painted on,
## it is the sunward half of a sphere seen from wherever you happen to be.

## Enough that the edge is a curve from its own orbit, where it fills the
## view: at 48 by 24 the limb was a polygon you could count the sides of.
const SEGS := 256
const RINGS := 128

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
// how much of it shows through a daytime sky
uniform float show = 1.0;
varying vec3 onorm;
varying vec3 wnorm;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	onorm = normalize(VERTEX);
	wnorm = normalize((MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(onorm);
	// the seas: broad dark plains, and the highlands between them
	float mare = smoothstep(0.50, 0.66,
		vnoise(n * 2.3) * 0.65 + vnoise(n * 5.1) * 0.35);
	float rough = vnoise(n * 19.0) * 0.4 + vnoise(n * 47.0) * 0.25
		+ vnoise(n * 140.0) * 0.2 + vnoise(n * 520.0) * 0.15;
	// craters: rings of light and shade at three sizes
	for (int o = 0; o < 3; o++) {
		float f = 9.0 * pow(3.1, float(o));
		vec3 cell = floor(n * f);
		vec3 centre = (cell + vec3(hash(cell), hash(cell + 7.0), hash(cell + 13.0))) / f;
		float d = length(n - centre) * f;
		float size = 0.18 + 0.22 * hash(cell + 3.0);
		rough += (smoothstep(size, size * 0.8, d) * -0.35
			+ smoothstep(size * 1.25, size, d) * smoothstep(size * 0.8, size, d) * 0.5)
			* step(0.45, hash(cell + 21.0));
	}
	vec3 high = vec3(0.74, 0.73, 0.70);
	vec3 low = vec3(0.34, 0.34, 0.36);
	vec3 col = mix(high, low, mare) * (0.82 + rough * 0.30);
	// No air to soften the terminator: the lit side is lit and the rest is
	// very nearly not there, with only earthshine to say it is a ball.
	float lit = smoothstep(-0.02, 0.10, dot(normalize(wnorm), sun_dir));
	ALBEDO = col * (0.012 + lit * 1.25) * show;
}
"""

var _mi: MeshInstance3D
var _mat: ShaderMaterial

func build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS:
		var t0: float = PI * float(i) / float(RINGS)
		var t1: float = PI * float(i + 1) / float(RINGS)
		for j in SEGS:
			var p0: float = TAU * float(j) / float(SEGS)
			var p1: float = TAU * float(j + 1) / float(SEGS)
			var a := _on(t0, p0)
			var b := _on(t0, p1)
			var c := _on(t1, p1)
			var d := _on(t1, p0)
			# wound to face outwards
			if i > 0:
				_tri(st, a, c, b)
			if i < RINGS - 1:
				_tri(st, a, d, c)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mi = MeshInstance3D.new()
	_mi.name = "MoonBody"
	_mi.mesh = st.commit()
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 16384.0
	add_child(_mi)

func _on(theta: float, phi: float) -> Vector3:
	var s := sin(theta)
	return Vector3(s * cos(phi), cos(theta), s * sin(phi))

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal(v as Vector3)
		st.add_vertex(v)

## Put it in the sky for this camera, lit from `sun` (the direction the light
## comes from, in the world's frame).
func follow(cam: Camera3D, sun: Vector3) -> void:
	if _mi == null or cam == null or not is_instance_valid(cam):
		return
	var eye: Vector3 = cam.global_position
	var to: Vector3 = Sim.moon_world() - eye
	# From a spacecraft a long way out the eye is not where the world's
	# coordinates say it is -- it is drawn low and the planet shrunk -- so the
	# line to the moon is the one the spacecraft worked out for itself.
	if Sim.view_moon != Vector3.INF:
		to = Sim.planet_to_world_dir(Sim.view_moon)
	var dist: float = maxf(to.length(), 1.0)
	# Inside the far plane it is simply where it is. Outside -- which is always,
	# short of flying there -- it is brought in along the line of sight.
	var carry: float = minf(dist, cam.far * 0.82)
	var k: float = carry / dist
	_mi.global_position = eye + to * k
	_mi.scale = Vector3.ONE * (Sim.MOON_R * k)
	# The same face to the planet all month, as the real one keeps.
	var back: Vector3 = Sim.planet_to_world_dir(-Sim.moon_dir())
	var up: Vector3 = Sim.planet_to_world_dir(Sim.MOON_AXIS.normalized())
	if absf(back.dot(up)) < 0.99:
		_mi.global_basis = Basis.looking_at(-back, up).scaled(_mi.scale)
	_mat.set_shader_parameter("sun_dir", sun.normalized())
	# A daytime moon is a pale thing seen through the lit air; from above the
	# air, or at night, it is as bright as it is. The air shell hazes it by
	# only as much air as fits inside the far plane, so the rest is done here.
	var up_here: Vector3 = Sim.up_at(eye)
	var day: float = smoothstep(-0.12, 0.10, up_here.dot(sun.normalized()))
	var air: float = clampf(1.0 - Sim.altitude(eye) / 60000.0, 0.0, 1.0)
	_mat.set_shader_parameter("show", 1.0 - 0.55 * day * air)
