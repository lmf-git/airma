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
	var fb := _NukeBall.new()
	fb.lethal = lethal
	fb.flash = flash
	fb.position = pos
	world.add_child(fb)
	# the ground wave: a ring of dust running outward
	for i in 10:
		var a := TAU * float(i) / 10.0
		dust(world, pos + Vector3(cos(a), 0.0, sin(a)) * lethal * 0.35, lethal * 0.12)

class _NukeBall extends Node3D:
	var lethal := 1000.0
	var flash: OmniLight3D = null
	var _t := 0.0
	var _ball: MeshInstance3D
	var _stem: MeshInstance3D
	var _cap: MeshInstance3D
	var _mat: StandardMaterial3D

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
		var cy := CylinderMesh.new()
		cy.top_radius = 1.0
		cy.bottom_radius = 1.0
		cy.height = 2.0
		cy.radial_segments = 14
		cy.material = _mat
		_stem = MeshInstance3D.new()
		_stem.mesh = cy
		_stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_stem)
		_cap = MeshInstance3D.new()
		_cap.mesh = sm
		_cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_cap)

	func _process(delta: float) -> void:
		_t += delta
		var f: float = clampf(_t / 26.0, 0.0, 1.0)
		# fireball: fast expansion, then it cools and lifts into the cap
		var br: float = lethal * (0.10 + 0.30 * clampf(_t / 3.0, 0.0, 1.0))
		var rise: float = lethal * 1.1 * pow(f, 0.65)
		_ball.scale = Vector3.ONE * br * (1.0 - 0.55 * f)
		_ball.position = Vector3(0, br * 0.6 + rise * 0.25, 0)
		_stem.scale = Vector3(lethal * 0.10 * (1.0 + f), maxf(rise, 1.0) * 0.5, lethal * 0.10 * (1.0 + f))
		_stem.position = Vector3(0, rise * 0.5, 0)
		_cap.scale = Vector3(lethal * 0.42 * f, lethal * 0.20 * f, lethal * 0.42 * f)
		_cap.position = Vector3(0, rise, 0)
		# glowing white, cooling through orange to a grey column
		var heat: float = clampf(1.0 - _t / 5.0, 0.0, 1.0)
		_mat.albedo_color = Color(1.0, 0.55 + 0.40 * heat, 0.28 + 0.45 * heat,
			clampf(1.0 - f * 0.85, 0.0, 1.0))
		if is_instance_valid(flash):
			flash.light_energy = 240.0 * pow(clampf(1.0 - _t / 1.6, 0.0, 1.0), 2.0)
			if _t > 1.7:
				flash.queue_free()
		if f >= 1.0:
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
	world.add_child(p)
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
		if smoke:
			_light = OmniLight3D.new()
			_light.light_color = tint
			_light.light_energy = 12.0
			_light.omni_range = radius * 8.0
			add_child(_light)

	func _process(delta: float) -> void:
		life += delta
		var t := life / life_max
		if t >= 1.0:
			queue_free()
			return
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
