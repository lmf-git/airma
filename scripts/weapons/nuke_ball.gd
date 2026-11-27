class_name NukeBall
extends Node3D

## Moved out of `effects.gd` (`Effects._NukeBall`).

## How long the column stands. A mushroom cloud is a landmark for minutes,
## not the twenty-six seconds this used to get.
const LIFE := 165.0
var lethal := 1000.0
var flash: OmniLight3D = null
var _t := 0.0
var _ball: MeshInstance3D
var _vol: MeshInstance3D
var sun_node: Node3D = null
var _fire: ShaderMaterial
var _smoke: ShaderMaterial
static var _fire_sh: Shader = null
static var _smoke_sh: Shader = null

func _ready() -> void:
	top_level = true
	# The fireball is light, not a painted ball.
	#
	# A sphere with one flat colour on it has a hard silhouette and reads as
	# a solid object however it is blended -- no amount of tinting fixes
	# that, because what gives a luminous ball its shape is that it is
	# brightest through the middle, where you are looking through the most
	# of it, and falls away at the limb. That falloff, a boiling surface and
	# a temperature that cools from white through orange is the whole
	# effect.
	# Built once and kept. Each burst made its own pair of shaders, so
	# each burst compiled them, on the frame it went off.
	if _fire_sh == null:
		_fire_sh = Shader.new()
		_fire_sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;

uniform float t = 0.0;
// 1 the instant it goes off, 0 once it has cooled to nothing.
uniform float heat = 1.0;
varying vec3 lp;

""" + Effects.NOISE_GLSL + """
void vertex() {
	lp = VERTEX;
}

void fragment() {
	// Limb darkening. Facing the eye you look through the whole depth of the
	// ball; at the edge you look through almost none of it, so the brightness
	// falls away and the silhouette stops being a circle cut out of the sky.
	float face = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float core = pow(face, 1.7);
	// boiling: the surface turns over as it rises
	float n = vnoise(lp * 3.1 + vec3(0.0, -t * 0.35, 0.0)) * 0.55
		+ vnoise(lp * 7.4 + vec3(0.0, -t * 0.70, 0.0)) * 0.45;
	float glow = core * (0.70 + 0.60 * n);
	// and it cools: white hot, then yellow, then orange, then a dull red that
	// the smoke swallows
	vec3 white = vec3(1.00, 0.97, 0.90);
	vec3 amber = vec3(1.00, 0.62, 0.22);
	vec3 dull  = vec3(0.72, 0.14, 0.05);
	vec3 col = mix(dull, mix(amber, white, clamp(heat * 1.7 - 0.7, 0.0, 1.0)),
		clamp(heat * 1.4, 0.0, 1.0));
	ALBEDO = col * (0.30 + 2.2 * heat);
	ALPHA = clamp(glow * heat, 0.0, 1.0);
}
"""
	_fire = ShaderMaterial.new()
	_fire.shader = _fire_sh
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 16
	sm.material = _fire
	_ball = MeshInstance3D.new()
	_ball.mesh = sm
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ball)
	# The column and the cap are a volume, not a shape. A tapered cylinder
	# with a sphere on top is a cone and a ball however the surface is
	# painted -- the silhouette gives it away from every angle, and a
	# mushroom cloud is the one thing in the game whose whole character is
	# that it has no surface. This is a box with the cloud raymarched
	# inside it: the density field is the mushroom, and what you see is how
	# much of it the light got through.
	if _smoke_sh == null:
		_smoke_sh = Shader.new()
		_smoke_sh.code = """
shader_type spatial;
// Back faces, so the volume still draws when the camera is inside the box, and
// no depth written because a cloud is not a surface to occlude against.
render_mode unshaded, cull_front, blend_mix, depth_draw_never, depth_test_disabled;

uniform vec3 tint : source_color = vec3(0.46, 0.42, 0.38);
uniform vec3 lit : source_color = vec3(1.0, 0.94, 0.86);
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.35);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform vec3 haze_col : source_color = vec3(0.70, 0.78, 0.90);
uniform float t = 0.0;
// The shape, in fractions of the box: where the cap sits, how wide and how
// thick it is, and how fat the column is.
uniform float cap_y = 0.6;
uniform float cap_r = 0.4;
uniform float cap_h = 0.15;
uniform float stem_r = 0.08;
// How many steps the march takes: fewer when the cloud fills the screen.
uniform int steps = 34;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

""" + Effects.NOISE_GLSL + """
float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

// The outline of the cloud, in the box's own space: the unit cube, ground at
// y = -0.5. One noise lookup; the billows, which are eight, are `density`.
float shape(vec3 p) {
	float h = clamp(p.y + 0.5, 0.0, 1.0);
	float r = length(p.xz);
	// The column: narrow at the base, widening as it rises, and thinning out
	// where it feeds into the cap.
	float sr = stem_r * (0.55 + 0.9 * h);
	float stem = smoothstep(sr, sr * 0.25, r)
		* smoothstep(0.0, 0.10, h)
		* smoothstep(cap_y + 0.05, cap_y - 0.28, h);
	// The cap: a dome on top of the column, undercut underneath, with the rim
	// rolled outward and down. That undercut is the whole difference between a
	// mushroom and a tree.
	//
	// A round dome, and under its edge a rim that is a torus -- a tube of
	// cloud rolling outward and down -- rather than a ring that ran most of the
	// cap's height. Drawn with soft edges that ring was a cylinder, and the
	// whole cap a puck.
	float dy = (h - cap_y) / max(cap_h, 0.001);
	float rr = r / max(cap_r, 0.001);
	// Lumps in the outline itself, not just in the density inside it: a
	// cauliflower edge rather than a smooth plastic one.
	float lump = vnoise(p * 9.0 + vec3(0.0, -t * 0.04, 0.0)) - 0.5;
	float dome = smoothstep(1.0, 0.55, length(vec2(rr, dy)) + lump * 0.40);
	float tube = length(vec2((rr - 0.80) / 0.32, (dy + 0.25) / 0.55)) + lump * 0.55;
	float roll = smoothstep(1.0, 0.35, tube);
	return max(stem, max(dome, roll * 0.95));
}

float density(vec3 p) {
	float d = shape(p);
	if (d <= 0.002) {
		return 0.0;
	}
	// Billows, turning over slowly as the thing stands there.
	vec3 q = p * 5.5 + vec3(0.0, -t * 0.05, 0.0);
	float n = fbm(q) * 0.72 + fbm(q * 2.7) * 0.28;
	d *= smoothstep(0.30, 0.74, n * 0.6 + 0.42);
	return clamp(d, 0.0, 1.0);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	mat4 inv_model = inverse(MODEL_MATRIX);
	vec3 wdir = normalize(wpos - CAMERA_POSITION_WORLD);
	// Into the box's space. The direction is deliberately not renormalised:
	// as the image of a unit world vector it keeps distances in world units,
	// so one step here is one metre out there and the depth test below can be
	// compared against it directly.
	vec3 lo = (inv_model * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 ld = mat3(inv_model) * wdir;
	// Guarded one component at a time. Building a vec3 out of the bvec3 that
	// equal() returns is a GLSL conversion Godot's shader language does not
	// take, and a sky shader that fails to compile reports nothing and simply
	// draws none of this.
	ld.x = abs(ld.x) < 1e-9 ? 1e-9 : ld.x;
	ld.y = abs(ld.y) < 1e-9 ? 1e-9 : ld.y;
	ld.z = abs(ld.z) < 1e-9 ? 1e-9 : ld.z;
	vec3 ta = (vec3(-0.5) - lo) / ld;
	vec3 tb = (vec3(0.5) - lo) / ld;
	vec3 tmin = min(ta, tb);
	vec3 tmax = max(ta, tb);
	float t0 = max(max(tmin.x, tmin.y), max(tmin.z, 0.0));
	float t1 = min(min(tmax.x, tmax.y), tmax.z);
	if (t1 <= t0) {
		discard;
	}
	// Stop at whatever is already drawn there, so a hillside in front of the
	// column hides it instead of the column being painted over the hill.
	float raw = texture(depth_tex, SCREEN_UV).r;
	if (raw > 0.0) {
		vec4 vw = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
		t1 = min(t1, length(vw.xyz / vw.w));
	}
	if (t1 <= t0) {
		discard;
	}
	float dt = (t1 - t0) / float(steps);
	// How much cloud one step crosses, in the box's units. The march runs in
	// metres, and the opacity used to be taken straight from that: a step a
	// hundred metres long made anything above a two-hundred-and-fiftieth of
	// full density opaque, so every soft edge in the shape -- the dome's
	// shoulder, the rim's long tails -- drew as a hard surface at its outermost
	// reach, and the cloud came out a flat-topped puck with vertical sides.
	float seg = dt * length(ld);
	// An ordered offset, so the march's own steps do not show as shells.
	float jit = fract(sin(dot(SCREEN_UV, vec2(41.7, 289.1))) * 43758.5453);
	vec4 acc = vec4(0.0);
	float first = -1.0;
	vec3 sl = normalize(mat3(inv_model) * normalize(sun_dir));
	for (int i = 0; i < 34; i++) {
		if (i >= steps || acc.a > 0.985) {
			break;
		}
		float ti = t0 + (float(i) + jit) * dt;
		vec3 sp = lo + ld * ti;
		float d = density(sp);
		if (d <= 0.002) {
			continue;
		}
		if (first < 0.0) {
			first = ti;
		}
		// How much sun reaches this lump, marched a few steps towards it. This
		// is what gives the cap a lit top and a dark underside instead of one
		// flat tone.
		//
		// Against the outline, not the billowed density. Each of these was
		// the full nine noise lookups, four times over at every one of
		// thirty-four steps: fifteen hundred a pixel. From fifteen kilometres
		// that is a few thousand pixels. A tactical one goes off eighty
		// metres away and is the whole screen, and the frame rate went with
		// it for as long as the column stood.
		float shade = 1.0;
		float ls = 0.05;
		for (int j = 1; j <= 3; j++) {
			shade *= exp(-shape(sp + sl * ls * float(j)) * 2.8);
			ls *= 1.9;
		}
		vec3 col = mix(tint, lit, clamp(shade, 0.0, 1.0) * 0.85);
		// Extinction over the step: crossing the full cap through its core
		// is nearly opaque, its thin edges and the rim's tails are not.
		float a = (1.0 - exp(-d * seg * 22.0)) * opacity;
		acc.rgb += col * a * (1.0 - acc.a);
		acc.a += a * (1.0 - acc.a);
	}
	if (acc.a < 0.004) {
		discard;
	}
	// Its own aerial perspective, to the cloud rather than past it. The air
	// shell is drawn after this and used to haze it for the whole distance to
	// the sky behind, which washed a cloud fifteen kilometres off out to a
	// pale ghost; this is drawn after the air now and hazes itself.
	vec3 col = acc.rgb / max(acc.a, 0.001);
	float haze = clamp(1.0 - exp(-max(first, 0.0) / 60000.0), 0.0, 0.75);
	ALBEDO = mix(col, haze_col, haze);
	ALPHA = clamp(acc.a, 0.0, 1.0);
}
"""
	_smoke = ShaderMaterial.new()
	_smoke.shader = _smoke_sh
	# after the air, which is 0 to 2: see the note on the haze above
	_smoke.render_priority = 3
	var bx := BoxMesh.new()
	bx.size = Vector3.ONE
	bx.material = _smoke
	_vol = MeshInstance3D.new()
	_vol.mesh = bx
	_vol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# it is a volume, so it must not be culled by its own flat box bounds
	_vol.extra_cull_margin = 16384.0
	add_child(_vol)

func _process(delta: float) -> void:
	_t += delta
	# Two clocks. The column takes about half a minute to climb and spread;
	# it then *stands there*. Running the shape and the fade off one
	# twenty-six second timer meant the whole thing was gone before the
	# blast had finished settling, and it faded out white.
	var grow: float = clampf(_t / 30.0, 0.0, 1.0)
	var life: float = clampf(_t / LIFE, 0.0, 1.0)
	# fireball: fast expansion, then it cools and lifts into the cap
	var br: float = lethal * (0.10 + 0.30 * clampf(_t / 3.0, 0.0, 1.0))
	var rise: float = lethal * 1.1 * pow(grow, 0.65)
	_ball.scale = Vector3.ONE * br * (1.0 - 0.55 * grow)
	_ball.position = Vector3(0, br * 0.6 + rise * 0.25, 0)
	# The box the cloud is marched in, and where the shape sits inside it.
	# The cap keeps spreading long after it has stopped climbing.
	var spread: float = 0.42 * grow + 0.30 * life
	var cap_w: float = lethal * spread
	# Thick enough to be a dome: at 0.20 of the lethal radius against a
	# cap 0.72 wide it was a disc three times as wide as it was tall.
	var cap_th: float = lethal * (0.30 * grow + 0.08 * life)
	var box_h: float = maxf(rise + cap_th * 2.4, lethal * 0.5)
	var box_w: float = maxf(cap_w * 2.6, lethal * 0.6)
	_vol.scale = Vector3(box_w, box_h, box_w)
	_vol.position = Vector3(0, box_h * 0.5, 0)
	_smoke.set_shader_parameter("cap_y", clampf(rise / box_h, 0.08, 0.94))
	# In the box's own units, where its sides are at +-0.5. These were
	# handed over as fractions of the *half* width, so the shader drew the
	# cap at twice the radius meant -- 0.77 of a box whose walls are at 0.5
	# -- and the walls cut it off: from above, the top of the cloud was the
	# square top of its box, and from the side its rim was a vertical face.
	# The column was twice as fat for the same reason.
	_smoke.set_shader_parameter("cap_r",
		clampf(cap_w / box_w, 0.02, 0.42))
	_smoke.set_shader_parameter("cap_h", clampf(cap_th / box_h, 0.02, 0.45))
	_smoke.set_shader_parameter("stem_r",
		clampf(lethal * 0.10 * (1.0 + grow) / box_w, 0.01, 0.20))
	# Half the steps from underneath it, all of them from across the map:
	# the nearer it is the more of the screen it is, and the less any one
	# step shows.
	var eye := get_viewport().get_camera_3d()
	if eye != null:
		var away: float = eye.global_position.distance_to(_vol.global_position) \
			/ maxf(maxf(box_w, box_h), 1.0)
		_smoke.set_shader_parameter("steps",
			int(lerpf(16.0, 34.0, clampf((away - 1.0) / 4.0, 0.0, 1.0))))
	if is_instance_valid(sun_node):
		_smoke.set_shader_parameter("sun_dir",
			-sun_node.global_transform.basis.z)
	# Cooling. Gone in a few seconds rather than thirty: tied to the growth
	# clock the fireball was still faintly visible once the column had
	# fully formed, so the cloud had a lamp buried in it for its whole life.
	var heat: float = clampf(1.0 - _t / 4.5, 0.0, 1.0)
	_fire.set_shader_parameter("heat", heat * heat)
	_fire.set_shader_parameter("t", _t)
	# The column is smoke, and smoke off a firestorm is black. It was
	# painted the same cooling orange as the fireball and faded to nothing
	# with it, so there was never any smoke to see.
	var soot: float = clampf(_t / 7.0, 0.0, 1.0)
	# Cooling to a lit grey-brown, not to soot. A column painted near black
	# is what smoke looks like in shadow; in daylight a cloud that size is
	# a bright dirty grey on the sunward side, and setting the albedo to
	# 0.08 meant no amount of sun could make it read as anything but a hole
	# cut in the sky.
	_smoke.set_shader_parameter("tint", Vector3(
		lerpf(0.90, 0.20, soot), lerpf(0.52, 0.18, soot), lerpf(0.24, 0.16, soot)))
	# what the sunlit side of it looks like, which is most of what you see
	_smoke.set_shader_parameter("lit", Vector3(
		lerpf(1.0, 0.78, soot), lerpf(0.80, 0.74, soot), lerpf(0.52, 0.68, soot)))
	_smoke.set_shader_parameter("opacity",
		clampf(minf(_t / 1.5, 1.0) * (1.0 - pow(life, 2.4)), 0.0, 0.94))
	_smoke.set_shader_parameter("t", _t)
	if is_instance_valid(flash):
		flash.light_energy = 240.0 * pow(clampf(1.0 - _t / 1.6, 0.0, 1.0), 2.0)
		if _t > 1.7:
			flash.queue_free()
	if life >= 1.0:
		queue_free()
