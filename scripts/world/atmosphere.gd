class_name Atmosphere
extends Node3D
## The air, as a shell round the planet.
##
## Ported from `reference/PlanetTerrain (Best)/shaders/atmosphere.gdshader`,
## whose comments are a record of everything that goes wrong when you try to
## draw one of these; they are kept because every one of them was paid for.
##
## What it gives: a blue sky dome from the ground that thickens toward the
## horizon, a sunlit rim round the limb from orbit, a warm band at the
## terminator, and nothing at all on the night side, so space shows. Climb and
## it thins out from under you -- which is the whole point, and what the sky
## gradient it replaces could never do, because a sky shader is background and
## has no altitude.
##
## The proportions are not the reference's. That planet is 1500 m across with
## its cloud deck at 240 m -- a sixth of the radius -- so a shell a third of the
## radius thick is in scale. This planet is 6371 km with its deck at 2.2 km,
## which is 0.03 % of the radius, so the shell is sized as a real atmosphere
## instead: a hundred kilometres, with the air falling off over about twenty.

## How far up the air goes. The Karman line, near enough.
const HEIGHT := 100_000.0
## How fast it thins, as e-folds over `HEIGHT`.
##
## The real figure is nearer twelve -- 8.5 km to an e-fold -- which would put
## black sky at twenty-five thousand feet. Five was the first guess and it is
## still too steep to fly through: measured, the sky went from a hundred
## thousand pixels brighter than a third to two thousand between thirty and
## forty-five kilometres, so a rocket crosses the whole transition in a couple
## of seconds and it reads as a switch rather than a climb. The reference's
## shader makes the same trade the other way and says so -- "2.0 keeps usable
## blue through the whole flight envelope while still thinning out toward the
## top of the shell". Three is about thirty-three kilometres to an e-fold: blue
## where aeroplanes are, thinning through the forties and fifties, space by the
## top of the shell.
const RHO_EXP := 3.0
## Rings and segments of the shell. It is a sphere seen from inside or from a
## long way out, so it never needs many.
const SEGS := 96
const RINGS := 48

const SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, depth_test_disabled, unshaded;
// cull_disabled, not cull_front. Which faces `cull_front` leaves depends on the
// winding of the sphere, and the reference's icosphere is not this one's ring
// mesh -- get it the wrong way round and the shell draws nothing at all, which
// is exactly what it did. The camera is always inside the carried sphere, so
// the near hemisphere is behind the near plane and every pixel is covered by
// exactly one face however it is wound.
// depth_test_disabled: the shell's back faces sit BEHIND the planet, so a
// geometric depth test would cull the haze wherever terrain is closer.
// Occlusion is done properly below against the scene depth texture instead.

uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);
uniform float planet_radius = 6371000.0;
uniform float atmo_radius = 6471000.0;
uniform vec3 day_color : source_color = vec3(0.3, 0.52, 0.95);
uniform vec3 sunset_color : source_color = vec3(0.95, 0.48, 0.22);
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
// Representative radius of the cloud deck, and which side of it this pass
// draws. The clouds are their OWN transparent shell that writes no depth, so
// this shader cannot clip against them the way it clips against terrain -- the
// column has to be split geometrically and drawn as two passes straddling the
// deck. See the note in fragment().
uniform float cloud_radius = 6373900.0;
uniform float cloud_band = 1400.0;
uniform bool behind_clouds = false;
// How fast the air thins, as e-folds over the shell. See `Atmosphere.RHO_EXP`.
uniform float rho_exp = 5.0;
// Where the planet is. Handed in rather than taken from `NODE_POSITION_WORLD`,
// because the shell no longer sits on the planet -- see `follow`.
uniform vec3 planet_centre = vec3(0.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Air density at a point as a fraction of the surface value.
float air_at(vec3 rel) {
	float alt01 = clamp((length(rel) - planet_radius)
		/ (atmo_radius - planet_radius), 0.0, 1.0);
	return exp(-alt01 * rho_exp);
}

void fragment() {
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(wpos - cam);
	vec3 oc = cam - planet_centre;

	// interval through the atmosphere sphere
	float b = dot(oc, rd);
	float disc = b * b - (dot(oc, oc) - atmo_radius * atmo_radius);
	if (disc <= 0.0) {
		discard;
	}
	float s = sqrt(disc);
	float t0 = max(-b - s, 0.0);
	float t1 = -b + s;
	// clip the part hidden behind the planet
	float discp = b * b - (dot(oc, oc) - planet_radius * planet_radius);
	if (discp > 0.0) {
		float tp = -b - sqrt(discp);
		if (tp > 0.0) {
			t1 = min(t1, tp);
		}
	}
	// clip against the real scene (terrain, aircraft, ships): haze only
	// integrates up to the nearest opaque surface = true aerial perspective
	float sd = texture(depth_tex, SCREEN_UV).r;
	vec4 sview = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, sd, 1.0);
	t1 = min(t1, length(sview.xyz / sview.w));

	// Split the column at the cloud deck. Haze in FRONT of the clouds must blend
	// OVER them; haze beyond them must be blended UNDER. One pass can only do
	// one of the two, and doing the whole chord in front is what buries the deck
	// under haze when looking across the limb from orbit.
	//
	// The split point must be CONTINUOUS across the tangent cone to the deck.
	// Defaulting rays that miss the deck to "all haze in front" puts a hard edge
	// exactly on that cone -- seen from near the deck that cone IS a giant
	// sphere hanging in the sky. A ray that misses the deck splits at its
	// CLOSEST APPROACH instead, which is the point the crossing converges to at
	// tangency.
	float t_geo = clamp(-b, t0, t1);
	float discc = b * b - (dot(oc, oc) - cloud_radius * cloud_radius);
	if (discc > 0.0) {
		float sc = sqrt(discc);
		// NO BRANCH BETWEEN THE TWO ROOTS. Selecting "whichever crossing is
		// ahead" flips from the near root to the far root the instant the camera
		// crosses the deck, and the two differ by 2*sc. Total opacity does not
		// change, but the clouds are opaque, so all the haze teleports from
		// behind them to in front of them and the view snaps from white to blue.
		// Inside the slab there is no true front or back anyway -- cloud and air
		// are interleaved -- so migrate between the two roots ACROSS the slab.
		float below = smoothstep(cloud_radius + cloud_band * 0.5,
			cloud_radius - cloud_band * 0.5, length(oc));
		t_geo = mix(clamp(-b - sc, t0, t1), clamp(-b + sc, t0, t1), below);
	}
	// Rays that pass well ABOVE the deck meet no cloud, so there is nothing to
	// composite against and splitting them only thins the limb glow. Fade back
	// to a single front-side pass over one deck thickness of clearance.
	float r_min = sqrt(max(dot(oc, oc) - b * b, 0.0));
	float deck_w = 1.0 - smoothstep(cloud_radius, cloud_radius + cloud_band, r_min);
	float t_split = mix(t1, t_geo, deck_w);
	float ta = behind_clouds ? t_split : t0;
	float tb = behind_clouds ? t1 : t_split;
	float path = max(t1 - t0, 0.0);      // the WHOLE column, both passes
	float seg = max(tb - ta, 0.0);       // this pass's share of it
	if (seg <= 0.0) {
		discard;
	}
	float max_chord = 2.0 * sqrt(atmo_radius * atmo_radius
		- planet_radius * planet_radius);
	// Normalising against the horizon chord is right when looking THROUGH the
	// atmosphere from outside, and wrong for looking UP from inside it: the path
	// to the top of the shell is tiny next to max_chord, so the zenith comes out
	// almost transparent -- and over black space that reads as "already out of
	// the atmosphere" a few hundred metres up. Views from inside are normalised
	// against the air REMAINING ABOVE the camera instead, and whichever reads
	// thicker wins. `inside` is 0 at or above the shell top, so the view from
	// orbit is untouched.
	float shell = atmo_radius - planet_radius;
	float cam_h = length(oc) - planet_radius;
	float inside = clamp(1.0 - cam_h / shell, 0.0, 1.0);
	// BOTH normalisers SATURATE, so they can only be measured against the WHOLE
	// column. Measuring each pass's own sub-path makes both halves report full
	// thickness near the horizon and everything under the deck turns blue.
	float depth_up = clamp(path / max(shell - cam_h, 1.0), 0.0, 1.0) * inside;
	float by_chord = clamp(path / max_chord, 0.0, 1.0);
	float by_up = depth_up * 0.8;
	// SOFT max, not `max()`. These are two models of the same thickness and a
	// hard max switches between them per pixel, so the locus where they cross is
	// an edge in the sky. Rounding the corner spreads it over a band.
	float depth_n = mix(by_chord, by_up,
		smoothstep(-0.18, 0.18, by_up - by_chord));

	// THE COLUMN'S OPACITY MUST NOT DEPEND ON WHERE IT IS CUT. Sampled at the
	// whole column's midpoint; every term feeding it is a whole-column quantity.
	// Deriving it from the two SEGMENT midpoints instead leaves a ring of
	// missing haze around the planet: density peaks at the closest approach,
	// which for a limb ray is the column midpoint, and splitting replaces that
	// one sample at the densest point with two thinner ones either side.
	// Sampled where the air is thickest, not at the middle of the column.
	//
	// Density along a ray peaks at its closest approach to the planet -- the
	// reference says so itself, when explaining why splitting the column must
	// not move this sample. For a limb ray that point IS the midpoint, which is
	// why the midpoint worked there; for a ray straight up from the ground it is
	// the ground, and the midpoint is fifty kilometres up. With the reference's
	// deliberately gentle falloff that hardly mattered. With a real one -- five
	// e-folds over the shell instead of two -- the midpoint reports eight per
	// cent of sea-level air for a man standing on the ground, and the sky came
	// out one tenth opaque: a pale wash over black space at noon.
	//
	// Still a whole-column quantity, so it is unchanged by where the column is
	// cut, which is what the split depends on.
	vec3 mid_full = oc + rd * clamp(-b, t0, t1);
	// The night-side fade belongs HERE, folded into the column opacity before it
	// is divided -- not applied to each pass afterwards, which leaves the halves
	// composing brighter than an unsplit ray in the terminator band.
	float gate = clamp(dot(normalize(mid_full), sun_dir) * 1.1 + 0.28, 0.0, 1.0);
	float a_full = clamp(depth_n * air_at(mid_full) * 1.5, 0.0, 0.92)
		* smoothstep(0.0, 0.25, gate);

	// SPLIT THE TRANSMITTANCE, NOT THE ALPHA. Two mix-blended layers compose as
	// 1-(1-a1)(1-a2), which is always less than a1+a2, so dividing the alpha
	// linearly makes a split ray thinner than an unsplit one. Transmittance is
	// multiplicative: raising it to each half's share composes back to exactly
	// a_full.
	vec3 mid_n = oc + rd * (t0 + t_split) * 0.5;
	vec3 mid_f = oc + rd * (t_split + t1) * 0.5;
	float mass_n = max(t_split - t0, 0.0) * air_at(mid_n);
	float mass_f = max(t1 - t_split, 0.0) * air_at(mid_f);
	float w = (behind_clouds ? mass_f : mass_n) / max(mass_n + mass_f, 1e-6);
	float alpha = 1.0 - pow(1.0 - a_full, w);

	// Colour from THIS pass's own midpoint, so each half is lit for where it
	// actually sits. Only ALBEDO may vary per pass.
	vec3 mid = behind_clouds ? mid_f : mid_n;
	float sun_dot = dot(normalize(mid), sun_dir);
	float sunf = clamp(sun_dot * 1.1 + 0.28, 0.0, 1.0);
	float terminator = 1.0 - smoothstep(0.0, 0.45, abs(sun_dot + 0.05));
	vec3 col = mix(day_color, sunset_color, terminator * 0.8);

	ALBEDO = col * sunf;
	ALPHA = alpha;
}
"""

var near_mat: ShaderMaterial
var far_mat: ShaderMaterial
var _mi: MeshInstance3D

func build() -> void:
	position = Vector3.ZERO
	far_mat = _material(true)
	near_mat = _material(false)
	# One shell, two surfaces, so the same geometry is drawn either side of the
	# cloud deck. Order is by `render_priority`, not by distance: the sea is -1,
	# the air under the clouds 0, the clouds 1, the air above them 2.
	var mesh := ArrayMesh.new()
	# A unit sphere, carried by the camera. See `follow`.
	var arrays := _shell_arrays(1.0)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, far_mat)
	mesh.surface_set_material(1, near_mat)
	_mi = MeshInstance3D.new()
	_mi.name = "Atmosphere"
	_mi.mesh = mesh
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It wraps the camera's own planet, so no culling volume the engine works
	# out for it can be right in a useful direction.
	_mi.extra_cull_margin = 16384.0
	add_child(_mi)

func _material(behind: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("planet_radius", Sim.PLANET_R)
	mat.set_shader_parameter("atmo_radius", Sim.PLANET_R + HEIGHT)
	mat.set_shader_parameter("cloud_radius",
		Sim.PLANET_R + (CloudShell.BASE + CloudShell.TOP) * 0.5)
	mat.set_shader_parameter("cloud_band", CloudShell.TOP - CloudShell.BASE)
	mat.set_shader_parameter("behind_clouds", behind)
	mat.set_shader_parameter("rho_exp", RHO_EXP)
	mat.set_shader_parameter("planet_centre", Sim.planet_centre)
	mat.render_priority = 0 if behind else 2
	return mat

## Keep the shell in front of the camera.
##
## It used to be a sphere of the planet's radius plus a hundred kilometres,
## sitting on the planet, drawn `cull_front` so you saw its inside. From the
## ground that inside is its far side -- thirteen thousand kilometres away --
## and the camera's far plane is forty-five. The whole shell was clipped away
## and the atmosphere drew nothing at all: measured, taking it out of the frame
## changed the picture by three thousandths.
##
## The shader never needed the geometry to be there. It works the column out
## analytically from the camera's position, the ray direction and the two radii;
## the mesh only decides which pixels get to ask. So it is a small sphere
## carried along by the camera, always comfortably inside the frustum, with the
## planet handed in as a uniform instead of being the node's own position.
func follow(cam: Camera3D) -> void:
	if _mi == null or cam == null or not is_instance_valid(cam):
		return
	_mi.global_position = cam.global_position
	# Inside the far plane and outside the near one, with room either side.
	var r: float = clampf(cam.far * 0.2, cam.near * 12.0, 2.0e6)
	_mi.scale = Vector3.ONE * r

## Which way the sun is, from the planet's centre.
func aim(sun_dir: Vector3) -> void:
	if near_mat == null:
		return
	near_mat.set_shader_parameter("sun_dir", sun_dir)
	# The half drawn under the clouds is a separate material and would otherwise
	# keep the shader's default sun direction -- a fixed sunlit band on one side.
	far_mat.set_shader_parameter("sun_dir", sun_dir)

func _shell_arrays(r: float) -> Array:
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
	return st.commit_to_arrays()

func _on(theta: float, phi: float, r: float) -> Vector3:
	var s := sin(theta)
	return Vector3(s * cos(phi) * r, cos(theta) * r, s * sin(phi) * r)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_normal((v as Vector3).normalized())
		st.add_vertex(v)
