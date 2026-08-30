class_name Weather
extends Node3D
## Cloud deck plus the environment tuning that goes with each weather state.

const PRESETS := {
	"clear": {
		"cover_frac": 0.30, "density": 0.85, "base_alt": 2400.0, "top_alt": 3500.0, "cirrus": 0.22, "steps": 58, "name": "CLEAR", "hour": 13.2, "spread": 18000.0,
		"fog": 26000.0, "fog_end": 150000.0, "sun": 1.18, "amb": 0.70,
		"top": Color(0.13, 0.28, 0.62), "horizon": Color(0.66, 0.75, 0.87),
		"sun_rot": Vector3(-40, 136, 0), "fog_col": Color(0.68, 0.76, 0.86), "sun_col": Color(1.0, 0.96, 0.90),
	},
	"scattered": {
		"cover_frac": 0.50, "density": 1.0, "base_alt": 2100.0, "top_alt": 3900.0, "cirrus": 0.35, "steps": 62, "name": "SCATTERED", "hour": 10.4, "spread": 22000.0,
		"fog": 21000.0, "fog_end": 130000.0, "sun": 1.05, "amb": 0.78,
		"top": Color(0.16, 0.30, 0.60), "horizon": Color(0.70, 0.77, 0.86),
		"sun_rot": Vector3(-36, 150, 0), "fog_col": Color(0.72, 0.78, 0.86), "sun_col": Color(1.0, 0.95, 0.88),
	},
	"overcast": {
		"cover_frac": 0.80, "density": 1.35, "base_alt": 1400.0, "top_alt": 3200.0, "cirrus": 0.15, "steps": 68, "name": "OVERCAST", "hour": 15.1, "spread": 26000.0,
		"fog": 12000.0, "fog_end": 85000.0, "sun": 0.55, "amb": 0.95,
		"top": Color(0.36, 0.40, 0.46), "horizon": Color(0.62, 0.65, 0.69),
		"sun_rot": Vector3(-52, 120, 0), "fog_col": Color(0.63, 0.66, 0.70), "sun_col": Color(0.85, 0.87, 0.92),
	},
	"dusk": {
		"cover_frac": 0.44, "density": 0.95, "base_alt": 2300.0, "top_alt": 3800.0, "cirrus": 0.45, "steps": 58, "name": "DUSK", "hour": 19.7, "spread": 20000.0,
		"fog": 18000.0, "fog_end": 115000.0, "sun": 0.85, "amb": 0.55,
		"top": Color(0.09, 0.13, 0.34), "horizon": Color(0.86, 0.48, 0.28),
		"sun_rot": Vector3(-9, 104, 0), "fog_col": Color(0.62, 0.44, 0.38), "sun_col": Color(1.0, 0.72, 0.46),
	},
}

var current := "scattered"

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
## Where the cloud actually is: the marched slab, and the cirrus sheet above it
## when the preset carries one.
const FOG_SHADER := """
shader_type fog;

// The near cloud, as real volumetric fog.
//
// The sky shader draws the cloudscape, but a sky is only drawn where there is
// no geometry: fly above the deck, look down, and the cloud vanishes because
// the terrain is in front of it. This is the same density field evaluated in
// Godot's froxel grid, which sits between the camera and whatever it is looking
// at, so the cloud you are actually in behaves like cloud -- it hides the
// ground, it thickens as you enter it, and it goes past the canopy.
uniform float coverage = 0.48;
uniform float base_alt = 2200.0;
uniform float top_alt = 3600.0;
uniform float density_mul = 1.0;
uniform vec3 wind = vec3(1.0, 0.0, 0.35);
uniform float wind_time = 0.0;
uniform vec3 cloud_albedo : source_color = vec3(0.92, 0.94, 0.97);
uniform float emit = 0.06;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
				   mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
				   mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

uniform vec2 slab_centre = vec2(0.0);
uniform float slab_half = 6000.0;

void fog() {
	vec3 p = WORLD_POSITION;
	if (p.y < base_alt || p.y > top_alt) {
		DENSITY = 0.0;
	} else {
		// identical field to the sky pass, so the deck you fly into is the
		// deck you were looking at
		vec3 q = p * 0.00026;
		q += wind * wind_time * 0.00026;
		float h = clamp((p.y - base_alt) / max(top_alt - base_alt, 1.0), 0.0, 1.0);
		float shape = fbm(q) + 0.10 * fbm(q * 2.6);
		float profile = smoothstep(0.0, 0.18, h) * (1.0 - smoothstep(0.55, 1.0, h));
		float d = max(shape * profile - (1.0 - coverage), 0.0);
		// Fade out toward the edge of the slab. The volume is a box that
		// follows you, so without this the cloud simply switched on at its
		// boundary — you flew along watching it assemble itself around you a
		// few kilometres out. Tapered, it thins into the raymarched sky behind
		// it and there is no edge to see.
		vec2 off = (WORLD_POSITION.xz - slab_centre) / max(slab_half, 1.0);
		float edge = 1.0 - smoothstep(0.62, 0.99, length(off));
		DENSITY = d * density_mul * 0.55 * edge;
		ALBEDO = cloud_albedo;
		EMISSION = cloud_albedo * emit;
	}
}
"""

## How far a ray actually gets before it runs out of steps.
##
## The march grows its step geometrically, so the reach is a sum, not a
## multiplication — and getting that wrong is silent. A fixed 55 m step with a
## bounded count reached three kilometres out of twenty-six, so everything
## beyond it was never sampled and the sky rearranged itself as you flew. This
## mirrors the shader's stepping exactly so the harness can say when a preset no
## longer covers the distance it claims to.
const MARCH_STEP := 38.0
const MARCH_GROWTH := 1.105
const MARCH_STEP_CAP := 300.0
const MARCH_FAR := 13000.0

func march_reach(id: String) -> float:
	var p: Dictionary = PRESETS[id if PRESETS.has(id) else "scattered"]
	var t := 0.0
	var dt := MARCH_STEP
	for i in int(p["steps"]):
		t += dt
		dt = minf(dt * MARCH_GROWTH, MARCH_STEP_CAP)
	return t

func cloud_band() -> Vector2:
	var p: Dictionary = PRESETS[current]
	var hi := float(p["top_alt"])
	if float(p["cirrus"]) > 0.01:
		hi = 9400.0
	return Vector2(float(p["base_alt"]), hi)

## What the sky costs now. Both are zero, and they are kept so the harness can
## assert that rather than the old numbers quietly disappearing: sixteen
## thousand billboards in a hundred and sixty-six batches became none of either.
func puff_count() -> int:
	return 0

func deck_count() -> int:
	return 0

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

## Raymarched cloud, in the sky itself.
##
## The billboard deck this replaces could not be made to look like weather. It
## was sixteen thousand quads that you saw through rather than into, it needed a
## hand-built LOD scheme and 166 draw calls to be affordable, and every peer had
## to be handed the same random seed to see the same sky. A slab marched in the
## sky shader has none of those problems: it is one pass at a quarter
## resolution, it has no instances at all, and it is a pure function of position
## and a wind offset — so two machines given the same clock draw the same cloud
## without a single byte crossing the wire about it.
const SKY_SHADER := """
shader_type sky;
// Clouds are raymarched in the half resolution pass. A quarter of the pixels is
// cheaper and fine for the body of a cloud, but an edge drawn at a quarter
// resolution and filtered back up is a staircase, and the edge is the part you
// look at.
render_mode use_half_res_pass;

group_uniforms sky_colour;
uniform vec3 top_colour : source_color = vec3(0.13, 0.28, 0.62);
uniform vec3 horizon_colour : source_color = vec3(0.66, 0.75, 0.87);
uniform vec3 ground_colour : source_color = vec3(0.30, 0.32, 0.30);
uniform float night = 0.0;
uniform float dusk = 0.0;

group_uniforms cloud;
uniform float coverage = 0.48;      // 0 clear, 1 solid
uniform float base_alt = 2200.0;
uniform float top_alt = 3600.0;
uniform float density_mul = 1.0;
uniform vec3 wind = vec3(1.0, 0.0, 0.35);
uniform float wind_time = 0.0;      // metres of drift, not seconds: see Weather
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_dark : source_color = vec3(0.42, 0.46, 0.55);
uniform int steps = 28;
uniform int light_steps = 4;
// The camera, handed in rather than taken from the sky shader's own POSITION.
// Relying on that built-in left the cloud locked to the view: swing the head
// round with free-look and the whole sky came with it. A uniform set from the
// camera every frame is unambiguous.
uniform vec3 cam_pos = vec3(0.0);
uniform float march_far = 30000.0;

group_uniforms high_cloud;
uniform float cirrus = 0.35;
uniform float cirrus_alt = 9400.0;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

// `lod` fades the fine octaves out. A sample taken with a three hundred metre
// step is standing in for three hundred metres of cloud, so resolving detail
// finer than that is not extra quality — it is the thing that makes distant
// cloud crawl and band, because which side of a small feature a big step lands
// on changes with every metre the camera moves.
float fbm(vec3 p, float lod) {
	float v = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 4; i++) {
		// Octave i has features 1/2^i across, so the fine ones go first as the
		// step widens and the coarsest always stays. Written the other way
		// round it drops the *base* octave first, which removes the cloud and
		// leaves the grain — precisely backwards.
		float w = clamp((1.0 - lod) * 3.0 + 1.0 - float(i), 0.0, 1.0);
		if (w > 0.001) {
			v += a * w * vnoise(p);
			norm += a * w;
		}
		p *= 2.03;
		a *= 0.5;
	}
	if (norm < 0.0001) {
		return 0.0;
	}
	return v / norm * 0.9375;
}

// Billow noise: the same field folded about its midpoint, so instead of smooth
// hills it makes rounded lumps with creases between them.
//
// This is what was missing. A cloud built by thresholding plain fractal noise
// against a coverage level is a set of large smooth blobs -- the boundary is
// wherever a slowly varying field crosses a constant, so it is soft, round and
// featureless at every scale. What makes cloud read as cloud is the
// cauliflower: lumps piled on lumps, with the small ones carried on the
// shoulders of the big ones. Folding the noise gives exactly that, and it costs
// three octaves rather than a Worley field's twenty-seven taps per sample.
float billow(vec3 p, float lod) {
	float v = 0.0;
	float a = 0.5;
	float norm = 0.0;
	for (int i = 0; i < 3; i++) {
		float w = clamp((1.0 - lod) * 3.0 + 1.0 - float(i), 0.0, 1.0);
		if (w > 0.001) {
			v += a * w * (1.0 - abs(vnoise(p) * 2.0 - 1.0));
			norm += a * w;
		}
		p *= 2.13;
		a *= 0.5;
	}
	if (norm < 0.0001) {
		return 0.5;
	}
	return v / norm;
}

// Density inside the slab. The vertical profile is what stops it looking like
// fog in a box: thin at the base, full through the middle, eroded at the top,
// which is the shape a cumulus actually has.
float cloud_density(vec3 p, float lod) {
	vec3 q = p * 0.00026;                   // wider features: less like static
	q += wind * wind_time * 0.00026;
	float h = clamp((p.y - base_alt) / max(top_alt - base_alt, 1.0), 0.0, 1.0);
	// The broad field decides where there is cloud at all; the billows decide
	// what it looks like. Mixed rather than multiplied, so the billows shape
	// the mass instead of punching holes through it.
	float shape = mix(fbm(q, lod), billow(q * 2.7, lod), 0.42);
	float profile = smoothstep(0.0, 0.18, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float d = shape * profile - (1.0 - coverage);
	if (d <= 0.0) {
		return 0.0;
	}
	// Erode the edges, and only the edges. A boundary where a smooth field
	// crosses a constant is a smooth curve however lumpy the inside is; biting
	// finer billows out of the last of the density is what makes the outline
	// ragged, which is most of what you actually see of a cloud.
	float edge = 1.0 - smoothstep(0.0, 0.22, d);
	d -= edge * 0.16 * (1.0 - billow(q * 7.3, lod));
	return max(d, 0.0) * density_mul * 2.6;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 cam = cam_pos;
	// The cubemap pass is generating radiance, not a picture. It sweeps the
	// whole sphere from a position that is not the camera's, so marching cloud
	// in it is both wrong and expensive; the gradient alone lights the world.
	if (AT_HALF_RES_PASS && !AT_CUBEMAP_PASS) {
		// --- the cloud layer -------------------------------------------
		vec4 acc = vec4(0.0);
		// Where the ray crosses the slab. Looking level or down from below it
		// there is nothing to march, which is most of the screen most of the
		// time and is why this is cheap.
		float lo = base_alt;
		float hi = top_alt;
		float t0 = 0.0;
		float t1 = 0.0;
		bool inside = cam.y > lo && cam.y < hi;
		if (abs(dir.y) < 0.0015) {
			t0 = 0.0;
			t1 = inside ? 42000.0 : -1.0;
		} else {
			float ta = (lo - cam.y) / dir.y;
			float tb = (hi - cam.y) / dir.y;
			t0 = min(ta, tb);
			t1 = max(ta, tb);
			t0 = max(t0, 0.0);
		}
		if (t1 > t0 && t0 < march_far) {
			t1 = min(t1, march_far);
			float span = t1 - t0;
			// Steps that grow with distance. Two wrong answers came before
			// this one. Dividing the span by a step count made the samples
			// kilometres apart when looking along the slab, and they slid about
			// with every small movement of the camera, which was the distant
			// shimmer. Replacing that with a fixed 55 m step fixed the shimmer
			// and broke something worse: a bounded number of 55 m steps only
			// reaches three kilometres, so everything beyond that was never
			// sampled at all and the whole sky changed as you flew through it.
			// Growing the step geometrically gives fine sampling close in,
			// where a step has to be small against a cloud, and coarse sampling
			// far out, where it does not — the same reasoning as any level of
			// detail, applied along the ray.
			float dt = 38.0;
			int n = steps;
			// An ordered dither. A random one sparkles, because it re-rolls
			// every frame the camera moves; no dither at all leaves the march's
			// own steps visible as horizontal layers in the distance, which is
			// worse. A 4x4 Bayer pattern is fixed to the screen, so a still
			// camera gives a still image, and it breaks the banding up into a
			// texture too fine to read as steps.
			// Built arithmetically rather than from a table: a shader-stage
			// array literal is not something this language will take, and a
			// sky shader that fails to compile reports no uniforms and draws
			// nothing rather than saying so.
			int bx = int(SCREEN_UV.x * 1920.0) & 3;
			int by = int(SCREEN_UV.y * 1080.0) & 3;
			int ba = bx ^ by;
			int bidx = ((ba & 1) << 3) | ((by & 1) << 2)
				| (((ba >> 1) & 1) << 1) | ((by >> 1) & 1);
			float jitter = float(bidx) / 16.0;
			vec3 sun = LIGHT0_DIRECTION;
			float t = t0;
			for (int i = 0; i < n; i++) {
				if (acc.a > 0.985 || t > t1) { break; }
				vec3 p = cam + dir * (t + jitter * dt);
				// the step this sample stands for, as a fraction of the
				// coarsest step the march ever takes
				float lod = clamp(dt / 300.0, 0.0, 1.0);
				float d = cloud_density(p, lod);
				t += dt;
				// capped, so the far steps stay short enough that what they
				// land on does not change as the camera drifts
				// Capped well under the slab's own thickness. At 1200 m a step
				// cut a fifteen-hundred-metre deck into three, and you could
				// count them on the horizon.
				dt = min(dt * 1.105, 300.0);
				if (d <= 0.001) { continue; }
				// How much sun reaches this point. Marched with a growing
				// step so a few samples cover a useful depth of cloud rather
				// than five hundred metres of it.
				float shade = 1.0;
				float ls = 90.0;
				for (int j = 1; j <= light_steps; j++) {
					vec3 lp = p - sun * ls * float(j);
					shade *= exp(-cloud_density(lp, lod) * ls * 0.85);
					ls *= 1.7;
				}
				shade = clamp(shade, 0.0, 1.0);
				// Forward scattering. Cloud is bright toward the sun and dark
				// away from it, and without this every cloud is the same flat
				// tone from every angle -- a grey blob with an outline.
				float mu = dot(dir, -sun);
				float g = 0.55;
				float hg = (1.0 - g * g)
					/ (12.566 * pow(1.0 + g * g - 2.0 * g * mu, 1.5));
				hg = 0.35 + 5.5 * hg;
				// Beer-powder: thin edges lit through, thick cores dark, which
				// is what gives a cumulus its shape rather than its silhouette.
				float powder = 1.0 - exp(-d * 5.0);
				// Ambient is not one colour either: the top of a cloud sees the
				// sky and the bottom sees the ground.
				float hgt = clamp((p.y - base_alt) / max(top_alt - base_alt, 1.0),
					0.0, 1.0);
				vec3 amb = mix(cloud_dark, mix(cloud_dark, cloud_lit, 0.55), hgt);
				vec3 col = amb * (0.55 + 0.45 * hgt)
					+ cloud_lit * LIGHT0_COLOR * shade * hg * powder * 1.35;
				float alpha = 1.0 - exp(-d * dt * 0.9);
				// ease the last few kilometres away so the march's own limit
				// is not a visible edge across the sky
				alpha *= 1.0 - smoothstep(march_far * 0.55, march_far, t);
				acc.rgb += col * alpha * (1.0 - acc.a);
				acc.a += alpha * (1.0 - acc.a);
			}
		}
		// a thin cirrus sheet, flat and far above everything
		if (dir.y > 0.02) {
			float tc = (cirrus_alt - cam.y) / dir.y;
			if (tc > 0.0 && tc < 200000.0) {
				vec3 cp = cam + dir * tc;
				vec2 cq = cp.xz * 0.000045 + wind.xz * wind_time * 0.00002;
				float s = fbm(vec3(cq * 2.0, 0.0), 0.0);
				s = smoothstep(0.52 - cirrus * 0.3, 0.78, s) * cirrus;
				s *= smoothstep(0.02, 0.25, dir.y);
				vec3 ccol = mix(cloud_dark, cloud_lit, 0.85);
				acc.rgb += ccol * s * (1.0 - acc.a);
				acc.a += s * (1.0 - acc.a);
			}
		}
		COLOR = acc.rgb;
		ALPHA = acc.a;
	} else {
		// --- the sky behind them ---------------------------------------
		float up = clamp(dir.y, -1.0, 1.0);
		vec3 sky_col = mix(horizon_colour, top_colour, pow(clamp(up, 0.0, 1.0), 0.55));
		if (up < 0.0) {
			sky_col = mix(horizon_colour, ground_colour, pow(-up, 0.35));
		}
		// the sun's own disc and the glow around it
		float sd = max(dot(dir, -LIGHT0_DIRECTION), 0.0);
		sky_col += LIGHT0_COLOR * pow(sd, 320.0) * 6.0 * (1.0 - night);
		sky_col += LIGHT0_COLOR * pow(sd, 8.0) * 0.16 * (1.0 - night);
		// a warm band low down when the sun is on the horizon
		sky_col = mix(sky_col, sky_col * vec3(1.25, 0.86, 0.66),
			dusk * (1.0 - smoothstep(0.0, 0.35, abs(up))));
		// stars, once it is dark enough to see them
		if (night > 0.02 && up > -0.05) {
			vec3 sp = floor(dir * 780.0);
			float star = hash13(sp);
			star = pow(max(star - 0.9965, 0.0) * 285.0, 2.2);
			sky_col += vec3(0.85, 0.88, 1.0) * star * night
				* smoothstep(-0.05, 0.15, up);
		}
		vec4 cl = HALF_RES_COLOR;
		COLOR = mix(sky_col, cl.rgb, clamp(cl.a, 0.0, 1.0));
	}
}
"""

func apply(id: String, env: Environment, sun: DirectionalLight3D,
		fill: DirectionalLight3D, psm: ShaderMaterial) -> void:
	current = id if PRESETS.has(id) else "scattered"
	_env_ref = env
	var p: Dictionary = PRESETS[current]
	# Haze, not soup. These distances were a few kilometres, so the country
	# faded out before you could see any of it and every view was the inside of
	# a grey bag. Pushed right out, the fog only softens the horizon -- which is
	# what atmosphere actually does over tens of kilometres.
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
	_ensure_fog(env)
	_apply_sun(true)
	set_process(true)

var _env: Environment
var _sun_node: DirectionalLight3D
var _fill_node: DirectionalLight3D
var _psm: ShaderMaterial

var _fog: FogVolume
var _env_ref: Environment = null
var _fog_mat: ShaderMaterial

## The volumetric slab, made once and then carried along with the camera. It is
## a box rather than the whole sky because Godot's froxel grid only reaches as
## far as `volumetric_fog_length`; past that the sky shader takes over, and the
## two use the same density field so the join does not show.
## The near volume. This is the cloud you can actually fly into -- the sky
## shader's raymarch is background only, so with this off there is nothing in
## front of the terrain and the sky reads as a painted backdrop.
##
## Turning it off was the wrong answer to "I hate the fog": the haze that was
## closing the view in is the depth fog below, and that is what has been pushed
## out. This is a separate thing and it is kept short, where its depth slices
## are fine enough to be stable.
const FOG_VOLUME := true

func _ensure_fog(env: Environment) -> void:
	if not FOG_VOLUME:
		env.volumetric_fog_enabled = false
		return
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0          # the volume supplies all of it
	# Cloud is drawn twice, and each half has to do the job it is good at.
	#
	# This grid is the half you can fly into, and it is a fixed number of
	# slices however long it is made. Stretched to twenty-two kilometres each
	# slice was hundreds of metres deep, so cloud detail inside one aliased
	# against it and the whole sky shook and swam with any movement of the
	# camera. Kept short the slices are fine enough to be stable, and the sky
	# shader's own raymarch -- which is in world space and does not care where
	# the camera is -- draws everything beyond it.
	env.volumetric_fog_length = 8000.0
	env.volumetric_fog_detail_spread = 2.4
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	# Held high. This is what averages the grid's noise out across frames, and
	# dropping it to a half to make the cloud settle faster after a turn simply
	# uncovered that noise: the sky then shook in every weather. The lag it
	# causes is a symptom of the grid being too long, which is fixed above, not
	# of the smoothing being too strong.
	env.volumetric_fog_temporal_reprojection_amount = 0.90
	if is_instance_valid(_fog):
		return
	_fog_mat = ShaderMaterial.new()
	var fsh := Shader.new()
	fsh.code = FOG_SHADER
	_fog_mat.shader = fsh
	_fog = FogVolume.new()
	_fog.name = "CloudVolume"
	_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	# Big enough that its edge is past anything you can pick out. At twelve
	# kilometres the boundary sat inside visual range and the cloud built
	# itself around you as you flew.
	# wide enough that its taper sits outside the grid's reach, and no wider:
	# the box costs nothing to make big, but it is the grid inside it that
	# decides both the cost and the stability
	_fog.size = Vector3(22000.0, 6000.0, 22000.0)
	_fog.material = _fog_mat
	add_child(_fog)

## Keep the slab centred on whoever is looking, in the horizontal only: moving
## it vertically would slide the cloud up and down with the aeroplane.
func has_volume() -> bool:
	return is_instance_valid(_fog)

func volume_size() -> Vector3:
	return _fog.size if is_instance_valid(_fog) else Vector3.ZERO

func follow(eye: Vector3) -> void:
	if _psm != null:
		# the sky needs to know where it is being looked at from
		_psm.set_shader_parameter("cam_pos", eye)
	if is_instance_valid(_fog):
		var p: Dictionary = PRESETS[current]
		var mid: float = (float(p["base_alt"]) + float(p["top_alt"])) * 0.5
		_fog.global_position = Vector3(eye.x, mid, eye.z)
		if _fog_mat != null:
			# Faded against the froxel grid's own reach, not the box. The
			# volumetric buffer only renders a few kilometres however big the
			# volume is, so that reach — not the boundary of the slab — is
			# where cloud stops being drawn and where the edge was showing.
			var reach: float = 6000.0
			if _env_ref != null and is_instance_valid(_env_ref):
				reach = maxf(_env_ref.volumetric_fog_length, 1000.0)
			_fog_mat.set_shader_parameter("slab_centre", Vector2(eye.x, eye.z))
			_fog_mat.set_shader_parameter("slab_half", reach)

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
		_psm.set_shader_parameter("top_colour", top.lerp(night_top, night))
		_psm.set_shader_parameter("horizon_colour",
			horizon.lerp(dusk_horizon, dusk * 0.8).lerp(night_horizon, night * 0.9))
		_psm.set_shader_parameter("ground_colour",
			Color(0.30, 0.32, 0.30).lerp(Color(0.03, 0.04, 0.06), night))
		_psm.set_shader_parameter("night", night)
		_psm.set_shader_parameter("dusk", dusk)
		# The cloud drifts on a distance derived from the clock, not from the
		# frame timer: every peer given the same time of day marches the same
		# sky, so the weather needs no replication of its own beyond the clock
		# that is already synchronised.
		# Slow. The clock runs a day in four hours, so anything scaled off it
		# directly moves six times faster than it looks like it should.
		_psm.set_shader_parameter("wind_time", time_of_day * 3600.0 * 0.22)
		_psm.set_shader_parameter("coverage", float(p["cover_frac"]))
		_psm.set_shader_parameter("density_mul", float(p["density"]))
		_psm.set_shader_parameter("base_alt", float(p["base_alt"]))
		_psm.set_shader_parameter("top_alt", float(p["top_alt"]))
		_psm.set_shader_parameter("cirrus", float(p["cirrus"]))
		_psm.set_shader_parameter("cloud_lit",
			Color(1.0, 0.98, 0.95).lerp(Color(1.0, 0.62, 0.36), dusk * 0.85)
				.lerp(Color(0.20, 0.24, 0.36), night * 0.9))
		_psm.set_shader_parameter("cloud_dark",
			Color(0.42, 0.46, 0.55).lerp(Color(0.40, 0.24, 0.24), dusk * 0.7)
				.lerp(Color(0.05, 0.06, 0.11), night * 0.9))
		_psm.set_shader_parameter("steps", int(p["steps"]))
		# set explicitly rather than left on the shader's own default: an unset
		# uniform reads back as null, which is a trap for anything inspecting it
		# Everything past the froxel grid is this shader's job now, so it has to
		# reach far enough to be the horizon rather than an edge in the middle
		# distance.
		_psm.set_shader_parameter("march_far", 30000.0)
		_psm.set_shader_parameter("light_steps", 5)
		_psm.set_shader_parameter("wind", Vector3(1.0, 0.0, 0.35))
		_psm.set_shader_parameter("cirrus_alt", 9400.0)
	if _fog_mat != null:
		for k in ["coverage", "base_alt", "top_alt", "density_mul", "wind_time"]:
			_fog_mat.set_shader_parameter(k, _psm.get_shader_parameter(k))
		_fog_mat.set_shader_parameter("cloud_albedo",
			Color(0.92, 0.94, 0.97).lerp(Color(1.0, 0.70, 0.44), dusk * 0.8)
				.lerp(Color(0.18, 0.21, 0.32), night * 0.9))
		_fog_mat.set_shader_parameter("emit", lerpf(0.06, 0.01, night))
	if _env != null:
		_env.ambient_light_energy = lerpf(float(p["amb"]), 0.16, night)
		_env.fog_light_color = Color(p["fog_col"]) \
			.lerp(Color(0.55, 0.30, 0.22), dusk * 0.7) \
			.lerp(Color(0.05, 0.06, 0.11), night * 0.9)


