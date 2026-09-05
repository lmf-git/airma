class_name CloudShell
extends Node3D
## The cloud layer, as a shell round the planet.
##
## Cloud used to be drawn twice and neither half could do the job. A volumetric
## slab followed the camera and reached eight kilometres, which is the cloud you
## can fly into; everything beyond that was raymarched in the *sky* shader,
## which is background only — it can never appear in front of anything solid. So
## between eight kilometres and the horizon there was no cloud at all in front
## of the terrain, and what you saw was a clear sky with weather piled up at the
## far edge of it. That is exactly what it looked like.
##
## This is one layer, geometry rather than background, wrapped round the planet
## rather than round the camera. Being geometry it composites with the ground at
## any range; being a shell about the planet's centre it is in the same place for
## everyone and does not slide when the camera moves — which is what made the
## old one swim when you turned.
##
## The density is a function of the direction from the planet's centre and the
## height within the slab, so it is the same kind of field the ground is: one
## rule, no seams, and cloud over the whole world rather than over your head.

## Where the layer sits, above sea level.
const BASE := 2200.0
const TOP := 3600.0
## Segments and rings of the shell. It is only ever seen from within a few tens
## of kilometres of its own surface, so the silhouette never matters; what this
## has to do is cover the sky without the quads showing.
const SEGS := 128
const RINGS := 64
## How big a cloud is: the noise is sampled this many units to the unit sphere,
## so a feature is about a ninth of a radian across -- a few hundred kilometres
## of weather system.
const NOISE_SCALE := 9.0
## How big one cloud within a system is. The field's finest octave is 8.07
## times this, so the smallest feature in the layer is the planet's radius over
## `8.07 * scale` -- about three kilometres, which is a cloud an aeroplane can
## fly between. On `NOISE_SCALE` alone it was eighty-eight kilometres.
const DETAIL_SCALE := 260.0
## How hard that detail cuts into the weather system. At zero the layer is an
## unbroken sheet again.
const ERODE := 0.45
## How far the noise is stretched before it is thresholded. See `spread` in the
## shader: the field's own spread is 0.093, so this is a little over three of
## them and `coverage` covers the whole range.
const SPREAD_K := 0.30
## How fast cloud puts out the light behind it, per metre.
const EXTINCTION := 0.0045
## What a full-strength cloud is worth. See `density_k`.
const DENSITY_K := 6.5
## The finest thing in the layer, in metres. Written down because it is what
## the white-out was: it has to stay a size you can fly between.
const FINEST_M := 6371000.0 / (8.07 * DETAIL_SCALE)
## The wind that carries it, in metres a second. A brisk day.
const WIND := 14.0
const WIND_DIR := Vector3(1.0, 0.0, 0.38)

const SHADER := """
shader_type spatial;
// Never occludes and never writes depth: it is weather, and the ground behind
// it has already been drawn. Cull disabled because you can be under it, in it
// or above it, and all three have to work.
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec3 centre = vec3(0.0);
uniform float r_base = 6373200.0;
uniform float r_top = 6374600.0;
uniform float coverage = 0.48;
uniform float density_mul = 1.0;
uniform float wind_time = 0.0;
// How big a cloud is, as a fraction of the planet, and how fast the layer
// drifts across it.
//
// The drift is worked out from a wind in metres a second rather than written
// down in texture units, because the two are related by the noise scale and the
// planet's radius and nobody can eyeball that. Written down directly it was
// 0.0018 -- which on a 6374 km shell sampled at nine units to the radius is an
// angular rate of 2e-4 a second, and clouds crossing the sky at **1275 m/s**.
uniform float noise_scale = 9.0;
// ...and how big one cloud in it is. See `density`.
uniform float detail_scale = 260.0;
uniform float erode = 0.62;
// How fast cloud puts out the light behind it, per metre of it.
//
// The layer is fourteen hundred metres thick, so at the 0.0016 this had, a
// sample of solid cloud could not reach opacity even through the whole of it:
// the densest ray up through the layer came out about half clear, and the sky
// read as haze. This is the number that makes a cloud a cloud, and the gaps
// stay gaps either way -- nothing times anything is nothing.
uniform float extinction = 0.0045;
// What a full-strength cloud is worth. `shape` is bounded by `coverage`, so
// half cover can never produce more than a half of this however dense the
// weather is -- and at the 3.4 this had, a solid cloud came to about half
// opacity through the whole depth of the layer, which is haze rather than
// cloud.
uniform float density_k = 6.5;
uniform vec3 wind_uv = vec3(0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 tint : source_color = vec3(0.92, 0.94, 0.97);
uniform vec3 shade : source_color = vec3(0.48, 0.52, 0.60);
uniform int steps = 28;

varying vec3 wpos;

// Noise out of a texture, not out of arithmetic.
//
// Written as a hash this cost the frame rate half of itself: a trilinear value
// noise is eight hashes, four octaves is thirty-two, and two samples a step over
// twenty steps is thirteen hundred hash evaluations for every pixel of sky. A
// 64-cube of random bytes sampled with linear filtering *is* value noise -- the
// hardware does the interpolation for free -- so an octave becomes one fetch.
uniform sampler3D vol : filter_linear, repeat_enable;

// The noise, stretched so a threshold on it means something.
//
// `fbm` is a sum of trilinear samples of a volume of random bytes: the
// interpolation averages eight neighbours and the octaves average again, so it
// clusters hard about a half. Measured, it runs 0.214 to 0.810 with a spread of
// 0.093 -- and `coverage` is a threshold on it. At 0.5 that threshold sits on
// the mean, where a hundredth either way is the difference between an unbroken
// overcast and no cloud at all, and this layer has been both. Stretched to fill
// 0..1, half cover means half the sky.
uniform float spread_k = 0.30;

float spread(float v) {
	return clamp((v - 0.5) / spread_k + 0.5, 0.0, 1.0);
}

float fbm(vec3 p) {
	return texture(vol, p).r * 0.5
		+ texture(vol, p * 2.03).r * 0.25
		+ texture(vol, p * 4.11).r * 0.15
		+ texture(vol, p * 8.07).r * 0.10;
}

// How much cloud there is at a point, from the direction it lies in and how far
// it is up the slab. A direction has no edges, so the field wraps the planet
// with nothing to seam and nothing to repeat.
float density(vec3 p) {
	vec3 up = normalize(p - centre);
	float r = length(p - centre);
	float h = clamp((r - r_base) / max(r_top - r_base, 1.0), 0.0, 1.0);
	// flat-bottomed and billowed on top, which is what a cumulus layer is
	float profile = smoothstep(0.0, 0.16, h) * (1.0 - smoothstep(0.42, 1.0, h));
	// The weather system: a few hundred kilometres of it, which is what
	// `noise_scale` is for.
	vec3 q = up * noise_scale + wind_uv * wind_time;
	float shape = spread(fbm(q)) * profile - (1.0 - coverage);
	if (shape <= 0.0) {
		return 0.0;
	}
	// ...and the clouds in it, which this had none of.
	//
	// The finest octave of the shape field is 8.07 times `noise_scale`, so at
	// nine units to the radian the smallest thing in the layer was the radius
	// over seventy-three -- eighty-eight kilometres. That is not a cloud, it is
	// an overcast: fly into one and you are inside it for as long as you care
	// to fly, and a ray marched sideways through the layer never leaves it.
	// Every windscreen was white, and so was every seeker looking through one.
	//
	// This erodes the system into cloud a few kilometres across, which is a
	// size an aeroplane can fly between. The lookup is warped by the shape
	// field so the detail does not repeat with the texture's own period.
	vec3 qd = up * detail_scale + vec3(shape * 0.7) + wind_uv * wind_time * 3.0;
	float detail = spread(fbm(qd));
	return max(shape - (1.0 - detail) * erode, 0.0) * density_mul * density_k;
}

// Where a ray crosses a sphere about the planet's centre; x is the near root and
// y the far one, and x > y means it misses.
vec2 shell_hit(vec3 o, vec3 d, float r) {
	vec3 oc = o - centre;
	float b = dot(oc, d);
	float c = dot(oc, oc) - r * r;
	float disc = b * b - c;
	if (disc < 0.0) {
		return vec2(1.0, -1.0);
	}
	float s = sqrt(disc);
	return vec2(-b - s, -b + s);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 eye = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 dir = normalize(wpos - eye);
	vec2 inner = shell_hit(eye, dir, r_base);
	vec2 outer = shell_hit(eye, dir, r_top);
	if (outer.x > outer.y) {
		discard;
	}
	// The slab is the outer sphere minus the inner one. Looking up from below
	// that is inner.y to outer.y; from inside it, the eye to whichever comes
	// first; from above, outer.x to inner.x. Taking the overlap of the outer
	// span with everything in front of the eye, and then cutting out the part
	// inside the inner sphere, covers all three without branching on where the
	// camera happens to be.
	float t0 = max(outer.x, 0.0);
	float t1 = outer.y;
	if (inner.x < inner.y) {
		if (t0 < inner.x) {
			t1 = min(t1, inner.x);
		} else {
			t0 = max(t0, inner.y);
		}
	}
	if (t1 <= t0) {
		discard;
	}
	// Bounded, or looking along the layer marches to the horizon and costs the
	// whole screen. Beyond this the sky's own gradient takes over.
	t1 = min(t1, t0 + 52000.0);
	// A march that is fine where you are and coarse where you are looking.
	//
	// Spread evenly, twenty steps over fifty kilometres is two and a half
	// kilometres a step, which cannot see a three kilometre cloud at all: from
	// inside the layer the gaps between the clouds fell between the samples and
	// the whole thing read as solid. Growing the step geometrically puts the
	// first few hundred metres of the ray -- the part being flown through -- at
	// a couple of hundred metres a sample, and still reaches the horizon.
	float span = t1 - t0;
	// Geometric only where it buys something.
	//
	// Growing the step is right for a ray along the layer, where the near few
	// hundred metres are what you are flying through and the far forty
	// kilometres are background. It is wrong for a ray straight up through
	// fourteen hundred metres of slab: it crowds the samples into the bottom of
	// the layer, where the profile is zero and there is no cloud, and leaves the
	// band in the middle that holds all of it to three or four samples. Looking
	// up, that read as haze.
	float g = span > float(steps) * 220.0 ? 1.14 : 1.0;
	float dt = g > 1.0
		? span * (g - 1.0) / (pow(g, float(steps)) - 1.0)
		: span / float(steps);
	float t = t0;
	float alpha = 0.0;
	float lit = 0.0;
	for (int i = 0; i < steps; i++) {
		if (alpha > 0.985) {
			break;
		}
		vec3 p = eye + dir * (t + dt * 0.5);
		float step_len = dt;
		t += dt;
		dt *= g;
		float d = density(p);
		if (d <= 0.0) {
			continue;
		}
		// Shading from where the sample sits in the slab rather than from a
		// second march toward the sun. A cloud is bright on top and grey
		// underneath because the light comes from above and is absorbed on the
		// way down, and how far down a sample is is already known -- it cost a
		// whole second density evaluation to rediscover it.
		float up_r = length(p - centre);
		float hgt = clamp((up_r - r_base) / max(r_top - r_base, 1.0), 0.0, 1.0);
		float face = clamp(dot(normalize(p - centre), sun_dir) * 0.5 + 0.72,
			0.0, 1.0);
		float a = 1.0 - exp(-d * step_len * extinction);
		lit = mix(lit, mix(0.18, 1.0, hgt * hgt) * face, a * (1.0 - alpha));
		alpha += a * (1.0 - alpha);
	}
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = mix(shade, tint, clamp(lit, 0.0, 1.0));
	ALPHA = clamp(alpha, 0.0, 1.0);
}
"""

var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _t := 0.0

func build() -> void:
	position = Sim.planet_centre
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("centre", Sim.planet_centre)
	_mat.set_shader_parameter("r_base", Sim.PLANET_R + BASE)
	_mat.set_shader_parameter("r_top", Sim.PLANET_R + TOP)
	_mat.set_shader_parameter("vol", _noise_volume())
	_mat.set_shader_parameter("noise_scale", NOISE_SCALE)
	_mat.set_shader_parameter("detail_scale", DETAIL_SCALE)
	_mat.set_shader_parameter("erode", ERODE)
	_mat.set_shader_parameter("spread_k", SPREAD_K)
	_mat.set_shader_parameter("extinction", EXTINCTION)
	_mat.set_shader_parameter("density_k", DENSITY_K)
	# metres a second -> radians a second -> the texture space the noise is in
	_mat.set_shader_parameter("wind_uv",
		WIND_DIR.normalized() * (WIND / (Sim.PLANET_R + TOP) * NOISE_SCALE))
	_mi = MeshInstance3D.new()
	_mi.name = "CloudShell"
	_mi.mesh = _shell()
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It wraps the camera's own planet, so no culling volume the engine works
	# out for it can be right in a useful direction.
	_mi.extra_cull_margin = 16384.0
	# Between the two halves of the atmosphere: the air under the deck is drawn
	# at 0, the deck at 1, the air above it at 2. Order by priority rather than
	# by distance, because all three are transparent shells about the same
	# centre and their distances are meaningless against each other.
	_mat.render_priority = 1
	_mi.sorting_offset = -64.0
	add_child(_mi)

func _shell() -> ArrayMesh:
	var r: float = Sim.PLANET_R + TOP
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RINGS:
		var t0: float = PI * float(i) / float(RINGS)
		var t1: float = PI * float(i + 1) / float(RINGS)
		for j in SEGS:
			var p0: float = TAU * float(j) / float(SEGS)
			var p1: float = TAU * float(j + 1) / float(SEGS)
			var a := _on(t0, p0, r)
			var b := _on(t0, p1, r)
			var c := _on(t1, p1, r)
			var d := _on(t1, p0, r)
			if i > 0:
				_tri(st, a, b, c)
			_tri(st, a, c, d)
	return st.commit()

func _on(theta: float, phi: float, r: float) -> Vector3:
	var s := sin(theta)
	return Vector3(s * cos(phi) * r, cos(theta) * r, s * sin(phi) * r)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal((v as Vector3).normalized())
		st.add_vertex(v)

## The weather sets how much cloud there is; the sun says which way is up.
func apply(cover: float, density: float, sun: Node3D) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("coverage", cover)
	_mat.set_shader_parameter("density_mul", density)
	if sun != null and is_instance_valid(sun):
		_mat.set_shader_parameter("sun_dir", -sun.global_transform.basis.z)

func _process(delta: float) -> void:
	if _mat == null:
		return
	_t += delta
	_mat.set_shader_parameter("wind_time", _t)

## A 64-cube of random bytes. Sampled with linear filtering and repeat it is
## tiling value noise, and the interpolation the hardware does for nothing is
## the part that used to cost eight hashes a sample.
func _noise_volume() -> ImageTexture3D:
	const N := 64
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260904
	var slices: Array[Image] = []
	for z in N:
		var buf := PackedByteArray()
		buf.resize(N * N)
		for i in N * N:
			buf[i] = rng.randi() & 255
		slices.append(Image.create_from_data(N, N, false, Image.FORMAT_R8, buf))
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_R8, N, N, N, false, slices)
	return t
