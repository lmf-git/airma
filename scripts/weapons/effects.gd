class_name Effects
## Self-managing throwaway visuals: tracers, explosions, dust and trails.

static var _glow: GradientTexture2D
static var _puff: GradientTexture2D

## Soft round sprite. Without a texture every billboard is a hard-edged square,
## which is what made the flares look like flying paper.
static func glow_texture() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.25, Color(1, 1, 1, 0.82))
		g.add_point(0.6, Color(1, 1, 1, 0.18))
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 96
		_glow.height = 96
	return _glow

## Fatter, flatter falloff for smoke puffs.
static func puff_texture() -> GradientTexture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.55, Color(1, 1, 1, 0.72))
		g.add_point(0.82, Color(1, 1, 1, 0.16))
		_puff = GradientTexture2D.new()
		_puff.gradient = g
		_puff.fill = GradientTexture2D.FILL_RADIAL
		_puff.fill_from = Vector2(0.5, 0.5)
		_puff.fill_to = Vector2(1.0, 0.5)
		_puff.width = 96
		_puff.height = 96
	return _puff

## A soft line rather than a disc: solid across the middle of the narrow axis,
## fading to nothing at both edges, so a stretched quad reads as a filament.
static var _streak: GradientTexture2D = null

static func streak_texture() -> GradientTexture2D:
	if _streak == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 1))
		g.add_point(0.28, Color(1, 1, 1, 0.55))
		g.add_point(0.72, Color(1, 1, 1, 0.55))
		_streak = GradientTexture2D.new()
		_streak.gradient = g
		_streak.fill = GradientTexture2D.FILL_LINEAR
		_streak.fill_from = Vector2(0.0, 0.5)
		_streak.fill_to = Vector2(1.0, 0.5)
		_streak.width = 32
		_streak.height = 4
	return _streak

## Wingtip vortices. These were drawn with the rocket smoke builder: a square
## quad wearing a round puff texture, spun to a random angle and grown to two
## and a half times size — which is a ball, and a wingtip vortex is a line.
## This emits thin filaments laid along the flight path instead.
static func vortex_particles(colour: Color, length := 3.0, amount := 48) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	# a little way aft, so the streak has a direction to lie along and holds it
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 1.5
	pm.initial_velocity_min = 5.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.0
	pm.damping_max = 0.3
	pm.scale_min = 0.85
	pm.scale_max = 1.15
	# no tumbling: a filament that has been spun to a random angle is a smear
	pm.angle_min = 0.0
	pm.angle_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.30, 1.0))
	curve.add_point(Vector2(1.0, 1.25))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	grad.add_point(0.16, Color(1, 1, 1, 0.72))
	grad.add_point(0.62, Color(1, 1, 1, 0.34))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.color = colour
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(length * 0.035, length)     # long and thin, not square
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	# aligns the quad's long axis with the particle's velocity: a streak
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.render_priority = 6
	m.albedo_texture = streak_texture()
	m.albedo_color = Color(1, 1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = amount
	p.lifetime = 1.1
	p.local_coords = false
	p.explosiveness = 0.0
	return p

static func tracer(world: Node, pos: Vector3, vel: Vector3, owner: Node, dmg: float, team: int) -> void:
	var t := Tracer.new()
	t.vel = vel
	t.shooter = owner
	t.dmg = dmg
	t.team = team
	world.add_child(t)
	t.global_position = pos

## A nuclear detonation: white flash, a fireball that expands and rises, and a
## column with a cap on it. Scaled off the lethal radius so a bigger weapon
## genuinely looks bigger.
static func nuke(world: Node, pos: Vector3, lethal: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.96, 0.86)
	flash.light_energy = 240.0
	flash.omni_range = lethal * 3.0
	flash.position = pos + Vector3(0, lethal * 0.10, 0)
	world.add_child(flash)
	# and the screen goes white for anybody who can see it
	if world.has_method("nuke_flash"):
		world.call("nuke_flash", pos, lethal)
	var fb := _NukeBall.new()
	fb.lethal = lethal
	fb.flash = flash
	# so the cap can have a lit top and a dark underside
	if "_sun" in world:
		fb.sun_node = world.get("_sun")
	fb.position = pos
	world.add_child(fb)
	# the ground wave: a ring of dust running outward
	for i in 10:
		var a := TAU * float(i) / 10.0
		dust(world, pos + Vector3(cos(a), 0.0, sin(a)) * lethal * 0.35, lethal * 0.12)
	# black smoke off the firestorm, feeding the column for a good while
	var smoke := trail_particles(Color(0.50, 0.46, 0.42), lethal * 0.26, 120)
	smoke.lifetime = 34.0
	smoke.position = pos
	smoke.emitting = true
	var spm := smoke.process_material as ParticleProcessMaterial
	if spm != null:
		spm.direction = Vector3(0, 1, 0)
		spm.spread = 22.0
		spm.initial_velocity_min = lethal * 0.04
		spm.initial_velocity_max = lethal * 0.11
		# a wide spread of sizes, so they do not read as a row of identical beads
		spm.scale_min = 0.55
		spm.scale_max = 2.2
		spm.angle_min = -180.0
		spm.angle_max = 180.0
		spm.angular_velocity_min = -12.0
		spm.angular_velocity_max = 12.0
		spm.gravity = Vector3(0, lethal * 0.012, 0)
		spm.damping_min = 0.0
		spm.damping_max = 0.4
		# Lighter, and never fully opaque: ninety per cent alpha on a near
		# black puff is a solid dark bead, and a hundred of them is a bag of
		# marbles rather than a cloud.
		var sg := Gradient.new()
		sg.set_color(0, Color(0.85, 0.72, 0.58, 0.0))
		sg.set_color(1, Color(0.42, 0.39, 0.36, 0.0))
		sg.add_point(0.10, Color(0.72, 0.60, 0.48, 0.42))
		sg.add_point(0.45, Color(0.56, 0.52, 0.48, 0.34))
		sg.add_point(0.80, Color(0.46, 0.43, 0.40, 0.18))
		var sgt := GradientTexture1D.new()
		sgt.gradient = sg
		spm.color_ramp = sgt
	_one_shot(world, smoke, 4.0)

class _NukeBall extends Node3D:
	## How long the column stands. A mushroom cloud is a landmark for minutes,
	## not the twenty-six seconds this used to get.
	const LIFE := 165.0
	var lethal := 1000.0
	var flash: OmniLight3D = null
	var _t := 0.0
	var _ball: MeshInstance3D
	var _vol: MeshInstance3D
	var sun_node: Node3D = null
	var _mat: StandardMaterial3D
	var _smoke: ShaderMaterial

	func _ready() -> void:
		top_level = true
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color = Color(1.0, 0.92, 0.70, 1.0)
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 16
		sm.rings = 10
		sm.material = _mat
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
		var ssh := Shader.new()
		ssh.code = """
shader_type spatial;
// Back faces, so the volume still draws when the camera is inside the box, and
// no depth written because a cloud is not a surface to occlude against.
render_mode unshaded, cull_front, blend_mix, depth_draw_never, depth_test_disabled;

uniform vec3 tint : source_color = vec3(0.46, 0.42, 0.38);
uniform vec3 lit : source_color = vec3(1.0, 0.94, 0.86);
uniform vec3 sun_dir = vec3(0.4, 0.8, 0.35);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float t = 0.0;
// The shape, in fractions of the box: where the cap sits, how wide and how
// thick it is, and how fat the column is.
uniform float cap_y = 0.6;
uniform float cap_r = 0.4;
uniform float cap_h = 0.15;
uniform float stem_r = 0.08;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

float h31(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x),
			mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x),
			mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

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

// The cloud, in the box's own space: the unit cube, ground at y = -0.5.
float density(vec3 p) {
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
	float dy = (h - cap_y) / max(cap_h, 0.001);
	float rr = r / max(cap_r, 0.001);
	float dome = smoothstep(1.0, 0.40, length(vec2(rr, dy * 1.15)));
	float roll = smoothstep(0.42, 0.0, abs(rr - 0.76))
		* smoothstep(1.7, 0.2, abs(dy + 0.40));
	float d = max(stem, max(dome, roll * 0.9));
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
	const int STEPS = 34;
	float dt = (t1 - t0) / float(STEPS);
	// An ordered offset, so the march's own steps do not show as shells.
	float jit = fract(sin(dot(SCREEN_UV, vec2(41.7, 289.1))) * 43758.5453);
	vec4 acc = vec4(0.0);
	for (int i = 0; i < STEPS; i++) {
		if (acc.a > 0.985) {
			break;
		}
		vec3 sp = lo + ld * (t0 + (float(i) + jit) * dt);
		float d = density(sp);
		if (d <= 0.002) {
			continue;
		}
		// How much sun reaches this lump, marched a few steps towards it. This
		// is what gives the cap a lit top and a dark underside instead of one
		// flat tone.
		vec3 sl = normalize(mat3(inv_model) * normalize(sun_dir));
		float shade = 1.0;
		float ls = 0.05;
		for (int j = 1; j <= 4; j++) {
			shade *= exp(-density(sp + sl * ls * float(j)) * 2.6);
			ls *= 1.6;
		}
		vec3 col = mix(tint, lit, clamp(shade, 0.0, 1.0) * 0.85);
		float a = clamp(d * dt * 2.4, 0.0, 1.0) * opacity;
		acc.rgb += col * a * (1.0 - acc.a);
		acc.a += a * (1.0 - acc.a);
	}
	if (acc.a < 0.004) {
		discard;
	}
	ALBEDO = acc.rgb / max(acc.a, 0.001);
	ALPHA = clamp(acc.a, 0.0, 1.0);
}
"""
		_smoke = ShaderMaterial.new()
		_smoke.shader = ssh
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
		var cap_th: float = lethal * (0.20 * grow + 0.06 * life)
		var box_h: float = maxf(rise + cap_th * 2.4, lethal * 0.5)
		var box_w: float = maxf(cap_w * 2.6, lethal * 0.6)
		_vol.scale = Vector3(box_w, box_h, box_w)
		_vol.position = Vector3(0, box_h * 0.5, 0)
		_smoke.set_shader_parameter("cap_y", clampf(rise / box_h, 0.08, 0.94))
		_smoke.set_shader_parameter("cap_r",
			clampf(cap_w / (box_w * 0.5), 0.02, 0.95))
		_smoke.set_shader_parameter("cap_h", clampf(cap_th / box_h, 0.02, 0.45))
		_smoke.set_shader_parameter("stem_r",
			clampf(lethal * 0.10 * (1.0 + grow) / (box_w * 0.5), 0.01, 0.40))
		if is_instance_valid(sun_node):
			_smoke.set_shader_parameter("sun_dir",
				-sun_node.global_transform.basis.z)
		# The fireball glows white, cools through orange and goes out.
		var heat: float = clampf(1.0 - _t / 5.0, 0.0, 1.0)
		_mat.albedo_color = Color(1.0, 0.55 + 0.40 * heat, 0.28 + 0.45 * heat,
			clampf(1.0 - grow * 0.9, 0.0, 1.0))
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

## A round entering the sea: a column of spray rather than a fireball.
static func splash(world: Node, pos: Vector3, size: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var col := Color(0.86, 0.92, 0.96)
	var p := trail_particles(col, maxf(size * 0.5, 1.5), 46)
	p.lifetime = 2.2
	p.one_shot = true
	p.emitting = true
	p.position = pos
	var pm := p.process_material as ParticleProcessMaterial
	if pm != null:
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 26.0
		pm.initial_velocity_min = size * 1.8
		pm.initial_velocity_max = size * 4.2
		pm.gravity = Vector3(0, -16.0, 0)
	_one_shot(world, p)
	# and a ring of spray running outward from the entry point
	for i in 8:
		var a := TAU * float(i) / 8.0
		dust(world, pos + Vector3(cos(a), 0.0, sin(a)) * size * 0.7, size * 0.45)

static func explosion(world: Node, pos: Vector3, radius: float, smoke := true) -> void:
	# anything standing inside the blast comes down
	if Scenery.current != null and is_instance_valid(Scenery.current) and radius > 5.0:
		var flattened := Scenery.current.damage_area(pos, radius * 1.6)
		if flattened > 0:
			for i in mini(flattened, 3):
				dust(world, pos + Vector3(randf_range(-radius, radius), 1.0,
					randf_range(-radius, radius)), radius * 0.5)
	Sfx.play_at(world, "boom", pos, clampf(-14.0 + radius * 0.6, -14.0, 4.0),
		clampf(1.5 - radius * 0.03, 0.55, 1.5), 4500.0)
	var e := Boom.new()
	e.radius = radius
	e.smoke = smoke
	world.add_child(e)
	e.global_position = pos
	# where the last fireball was actually drawn, so the harness can check that
	# it was somewhere a player could see it
	Sim.last_burst = pos
	Sim.last_burst_r = radius

static func dust(world: Node, pos: Vector3, scale := 3.0) -> void:
	var e := Boom.new()
	e.radius = scale
	e.tint = Color(0.75, 0.68, 0.55)
	e.smoke = false
	e.life_max = 0.5
	world.add_child(e)
	e.global_position = pos

## How many smoke plumes are allowed to exist at once. Nothing was leaking —
## every piece of wreckage does expire — but a warhead that flattens a town
## spawns one plume per piece, all in the same instant. Measured after a single
## launcher round: 254 live emitters and 182 ms a frame on foot afterwards.
## Past this many, a new piece burns without a plume of its own; the fires you
## can already see are doing the work.
const SMOKE_BUDGET := 40
static var _smoking := 0

static func smoke_slot() -> bool:
	if _smoking >= SMOKE_BUDGET:
		return false
	_smoking += 1
	return true

static func release_smoke_slot() -> void:
	_smoking = maxi(_smoking - 1, 0)

## Put a one-shot emitter into the world and take it out again when it is spent.
## Nothing did the second half: every splash and every column of smoke stayed in
## the tree for the rest of the session with its process material live. Measured
## after one launcher round, 250 of them were parented straight to the world and
## walking around afterwards cost 182 ms a frame.
static func _one_shot(world: Node, p: GPUParticles3D, extra := 2.0) -> void:
	world.add_child(p)
	var tree := world.get_tree()
	if tree == null:
		return
	var t := tree.create_timer(p.lifetime + extra, false)
	t.timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free())

static func trail_particles(colour: Color, size := 0.6, amount := 48) -> GPUParticles3D:
	# Rocket smoke: alpha-blended puffs that expand and fade. Additive smoke reads
	# as a laser beam against a bright sky, which is what we do *not* want.
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.7
	pm.scale_max = 1.5
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 2.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.88, 0.85))
	grad.set_color(1, Color(0.78, 0.79, 0.82, 0.0))
	grad.add_point(0.18, Color(0.92, 0.92, 0.93, 0.55))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	pm.color = colour
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.render_priority = 6      # over the sea; see Boom._ready
	m.albedo_texture = puff_texture()
	m.albedo_color = Color(1, 1, 1, 1)
	m.vertex_color_use_as_albedo = true
	m.disable_receive_shadows = true
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = amount
	p.lifetime = 2.4
	p.local_coords = false
	p.explosiveness = 0.0
	return p

## Bright, short-lived embers — used for flare pyrotechnics and gun impacts.
static func ember_particles(colour: Color, size := 0.5, amount := 24) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -4.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.96, 0.80, 1.0))
	grad.set_color(1, Color(1.0, 0.35, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = glow_texture()
	m.albedo_color = colour
	m.vertex_color_use_as_albedo = true
	m.render_priority = 6      # over the sea; see Boom._ready
	qm.material = m
	p.draw_pass_1 = qm
	p.amount = amount
	p.lifetime = 0.9
	p.local_coords = false
	return p

## Short bright flash at a gun muzzle, with a matching stab of light.
static func muzzle_flash(world: Node, pos: Vector3, dir: Vector3, size := 1.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var f := Flash.new()
	f.size = size
	f.dir = dir
	world.add_child(f)
	f.global_position = pos

# ---------------------------------------------------------------------------
class Flash extends Node3D:
	var size := 1.0
	var dir := Vector3.FORWARD
	var life := 0.06
	var _mi: MeshInstance3D
	var _light: OmniLight3D

	func _ready() -> void:
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_mi = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(size * 2.2, size * 2.2)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = Effects.glow_texture()
		m.albedo_color = Color(1.0, 0.86, 0.52, 1.0)
		qm.material = m
		_mi.mesh = qm
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mi.scale = Vector3.ONE * randf_range(0.8, 1.25)
		add_child(_mi)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.82, 0.5)
		_light.light_energy = 6.0 * size
		_light.omni_range = 14.0 * size
		add_child(_light)

	func _process(delta: float) -> void:
		life -= delta
		var t: float = clampf(life / 0.06, 0.0, 1.0)
		_mi.scale = Vector3.ONE * size * (0.6 + t * 0.8)
		_light.light_energy = 6.0 * size * t
		if life <= 0.0:
			queue_free()

# ---------------------------------------------------------------------------
class Tracer extends Node3D:
	var vel := Vector3.ZERO
	var shooter: Node = null
	var dmg := 30.0
	var team := 0
	var life := 2.2

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		# A cross of two quads along the flight axis. Billboarding fought the
		# look_at that keeps the round pointed along its travel, which is what
		# made the bolts sit at the wrong angle.
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.74, 0.30, 0.95)
		mat.albedo_texture = Effects.glow_texture()
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var cst := MeshKit.begin()
		for roll in [0.0, PI * 0.5]:
			var up := Vector3(cos(roll), sin(roll), 0.0)
			MeshKit.quad(cst,
				up * 0.55 + Vector3(0, 0, -4.5), up * -0.55 + Vector3(0, 0, -4.5),
				up * -0.55 + Vector3(0, 0, 4.5), up * 0.55 + Vector3(0, 0, 4.5),
				Vector3(0, 0, 40.0))
		var m := MeshKit.finish(cst, mat)
		mi.mesh = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		top_level = true
		reset_physics_interpolation.call_deferred()

	func _physics_process(delta: float) -> void:
		life -= delta
		var from := global_position
		vel += Vector3.DOWN * 9.81 * delta
		var to := from + vel * delta
		global_position = to
		if vel.length_squared() > 1.0:
			look_at(to + vel, Vector3.UP)
		for n in get_tree().get_nodes_in_group("hittable"):
			if n == shooter or not is_instance_valid(n):
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if "team" in n and n.team == team:
				continue
			var r: float = n.hit_radius() if n.has_method("hit_radius") else 6.0
			if Geometry3D.get_closest_point_to_segment(n.global_position, from, to).distance_to(n.global_position) < r:
				if n.has_method("take_hit"):
					n.take_hit(dmg, shooter if is_instance_valid(shooter) else null)
				Effects.dust(get_tree().current_scene, to, 1.2)
				queue_free()
				return
		if to.y < Sim.height_at(to.x, to.z):
			Effects.dust(get_tree().current_scene, to, 1.6)
			queue_free()
		elif life <= 0.0:
			queue_free()

class Boom extends Node3D:
	var radius := 12.0
	var life := 0.0
	var life_max := 0.85
	var tint := Color(1.0, 0.62, 0.22)
	var smoke := true
	var _mi: MeshInstance3D
	var _light: OmniLight3D
	var _mat: StandardMaterial3D

	func _ready() -> void:
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_mi = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		_mi.mesh = sm
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.albedo_color = tint
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Transparent surfaces do not write depth; they are sorted, and the sort
		# key is the object's origin. The sea is one mesh sixty kilometres wide
		# whose origin is the middle of the world, so from anywhere out over the
		# water it sorted in front of a fireball at the surface and composited
		# 86% opaque sea over the top of it. A bomb into the water looked like a
		# dud. Explosions are drawn last, over everything transparent.
		_mat.render_priority = 8
		sm.material = _mat
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
		# Every burst lights the ground, not just the ones that also make smoke.
		# Rocket artillery and missile warheads asked for no smoke and therefore
		# got no light either, so at night a salvo arriving was a few grey
		# puffs: the one time of day an explosion should be the brightest thing
		# for miles.
		_light = OmniLight3D.new()
		_light.light_color = tint
		_light.light_energy = 14.0 + radius * 2.6
		_light.omni_range = maxf(radius * 11.0, 90.0)
		add_child(_light)

	func _process(delta: float) -> void:
		life += delta
		var t := life / life_max
		if t >= 1.0:
			queue_free()
			return
		# and it fades with the fireball rather than switching off with it
		if is_instance_valid(_light):
			_light.light_energy = (14.0 + radius * 2.6) * maxf(1.0 - t * t, 0.0)
		_mi.scale = Vector3.ONE * radius * (0.25 + 1.4 * t)
		_mat.albedo_color = tint * (1.0 - t) + Color(0, 0, 0, 0)
		_mat.albedo_color.a = 1.0 - t
		if _light:
			_light.light_energy = 12.0 * (1.0 - t) * (1.0 - t)

# ---------------------------------------------------------------------------
## A piece of something that has come apart. There is no physics terrain in this
## project — the ground is a height field and every vehicle does its own contact
## against it — so a RigidBody3D thrown off a wreck has nothing to land on and
## falls for ever. Measured: 640 m below the airfield and still accelerating.
## This does the same job the honest way: ballistic, bounces once or twice, and
## comes to rest on the surface it was thrown onto.
class Debris extends Node3D:
	var vel := Vector3.ZERO
	var spin := Vector3.ZERO
	var bounce := 0.28
	var rest_offset := 0.3        # how far the centre sits above the ground
	var life := 90.0
	var floats := false           # settles on the sea instead of the seabed
	var _still := 0.0

	func _ready() -> void:
		top_level = true
		add_to_group("wreckage")
		reset_physics_interpolation()

	func at_rest() -> bool:
		return _still > 0.4

	func _physics_process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		if at_rest():
			return
		vel += Vector3.DOWN * 9.81 * delta
		global_position += vel * delta
		rotation += spin * delta
		var floor_y := Sim.height_at(global_position.x, global_position.z)
		if floats:
			floor_y = maxf(floor_y, Sim.WATER_LEVEL)
		floor_y += rest_offset
		if global_position.y <= floor_y:
			global_position.y = floor_y
			if vel.y < -1.2:
				vel.y = -vel.y * bounce
				vel.x *= 0.55
				vel.z *= 0.55
				spin *= 0.5
			else:
				vel = Vector3.ZERO
				spin = Vector3.ZERO
				_still = 1.0
