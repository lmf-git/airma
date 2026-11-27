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

## `he` is the burst scale of an explosive shell, 0 for solid shot.
## The weapon camera's hook. Every round it might ride -- a gun's, a rocket, a
## shoulder-launched missile -- is offered here with whoever fired it, and the
## world decides. Stores off a pylon, a hull or a launcher already went to it;
## nothing fired from a gun or from a man's shoulder ever did.
static var round_watch := Callable()

static func watch(shot: Node3D, shooter: Node) -> void:
	# the range sees every round first, so it can mark it with what it is
	# before the camera decides whether to ride it
	if round_log.is_valid() and is_instance_valid(shot):
		round_log.call(shot, shooter)
	if round_watch.is_valid() and is_instance_valid(shot):
		round_watch.call(shot, shooter)

## The firing range's ear on every round fired: see `FiringRange`.
static var round_log: Callable = Callable()

static func tracer(world: Node, pos: Vector3, vel: Vector3, owner: Node, dmg: float,
		team: int, he := 0.0) -> Tracer:
	var t := Tracer.new()
	t.vel = vel
	t.shooter = owner
	t.dmg = dmg
	t.team = team
	t.he = he
	world.add_child(t)
	t.global_position = pos
	# A cannon round draws the line it flew, while there are ribbons to spare:
	# the streak is where it is this frame, and this is where it has been.
	var rb := ribbon(Color(1.0, 0.72, 0.36, 0.5), 0.2, 0.12, 4.0, true, 1)
	if rb != null:
		t.add_child(rb)
		rb.call(&"clear")
	watch(t, owner)
	return t

## A machine-gun round from a vehicle: a coaxial, a roof gun.
##
## It was fired as `tracer`, which is the cannon shell -- the same thick yellow
## streak with a ribbon behind it and the same ball of dust where it landed --
## so a fighting vehicle's coaxial and its autocannon could not be told apart
## from the gunner's seat or from the receiving end. The same flight and the
## same hits, drawn as what it is: a thin red line, nothing left hanging in
## the air behind it, and a flick of dirt where it goes in.
static func mg_round(world: Node, pos: Vector3, vel: Vector3, owner: Node, dmg: float,
		team: int) -> Tracer:
	var t := Tracer.new()
	t.vel = vel
	t.shooter = owner
	t.dmg = dmg
	t.team = team
	t.light = true
	world.add_child(t)
	t.global_position = pos
	watch(t, owner)
	return t

## A rifle round rather than a cannon shell. The same projectile -- travel time,
## drop, a streak you can see -- but drawn at the size of the thing, stopped by
## walls, and able to tell a head from a chest. `glow` is how much of it burns:
## not every round in a magazine is tracer.
## Where along a segment a round first meets the skin of an aircraft that has
## a hold, and which aircraft: [t from 0 to 1, aircraft], or [2.0, null].
##
## An aircraft with a hold is hollow. The hold is air, and so is the column
## behind it while the ramp is down -- the way in and out. Everything else
## inside the airframe's box is aircraft: the walls of the hold seen from
## inside, the fuselage, the wings and the tail seen from out. So a round
## fired in the hold leaves over the ramp or hits the aeroplane it is in, and
## one fired from outside reaches the men in the hold only through the back.
static func hull_hit(a: Vector3, b: Vector3) -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return [2.0, null]
	var best_t := 2.0
	var best: Node = null
	var mid: Vector3 = (a + b) * 0.5
	var half_len: float = a.distance_to(b) * 0.5
	for n in tree.get_nodes_in_group("holds"):
		var ac := n as Aircraft
		if ac == null or not is_instance_valid(ac) or not ac.alive:
			continue
		var bb: AABB = ac.bounds
		var reach: float = bb.size.length() * 0.5 + half_len
		if ac.global_position.distance_squared_to(mid) > reach * reach:
			continue
		var inv: Transform3D = ac.global_transform.affine_inverse()
		var la: Vector3 = inv * a
		var lb: Vector3 = inv * b
		# walk it a quarter of a metre at a time for the first point that is
		# aircraft: inside the airframe's box, or in the skin of the hold --
		# which on some airframes runs past the box the model makes -- and
		# not the air of the hold or of the open ramp behind it
		var span: float = la.distance_to(lb)
		var steps: int = maxi(int(ceil(span / 0.25)), 1)
		for k in steps + 1:
			var t: float = float(k) / float(steps)
			if t >= best_t:
				break
			var lp: Vector3 = la.lerp(lb, t)
			var wp: Vector3 = ac.global_transform * lp
			if not bb.has_point(lp) and not _in_hold_skin(ac, wp):
				continue
			if _hold_air(ac, wp):
				continue
			best_t = t
			best = ac
			break
	# whoever fired it: a man can put a round into the aircraft he is riding in
	return [best_t, best]

## Within the skin of the hold: its box, a little thicker than the air in it.
const HOLD_SKIN := 0.35
static func _in_hold_skin(ac: Aircraft, p: Vector3) -> bool:
	var hold: Node3D = ac.hold_node()
	if hold == null:
		return false
	var h: Vector3 = hold.get_meta("half", Vector3(2.0, 2.2, 6.0))
	var lp: Vector3 = hold.global_transform.affine_inverse() * p
	return absf(lp.x) <= h.x + HOLD_SKIN and lp.y >= -HOLD_SKIN and lp.y <= h.y + HOLD_SKIN \
		and absf(lp.z) <= h.z + HOLD_SKIN

## Is this point inside the hold of `ac`, or in the open column behind its
## ramp while the ramp is down?
static func _hold_air(ac: Aircraft, p: Vector3) -> bool:
	var hold: Node3D = ac.hold_node()
	if hold == null:
		return false
	var h: Vector3 = hold.get_meta("half", Vector3(2.0, 2.2, 6.0))
	var lp: Vector3 = hold.global_transform.affine_inverse() * p
	if absf(lp.x) > h.x or lp.y < 0.0 or lp.y > h.y:
		return false
	if lp.z >= -h.z and lp.z <= h.z:
		return true
	return lp.z > h.z and bool(ac.get("ramp_open"))

## An EMP going off: a shell of blue-white light racing out across the town
## from overhead, the sky lit with it for a moment, the screen going to static
## and a crackle.
static func emp_flash(world: Node, at: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var burst: Vector3 = at + Vector3(0, 120, 0)
	# the shell: an unshaded sphere, added light, swelling and thinning out
	var shell := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 32
	sm.rings = 16
	shell.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.55, 0.75, 1.0, 0.85)
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(shell)
	shell.global_position = burst
	shell.scale = Vector3.ONE * 5.0
	var tw := shell.create_tween().set_parallel(true)
	tw.tween_property(shell, "scale", Vector3.ONE * 900.0, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.6)
	tw.chain().tween_callback(shell.queue_free)
	# the sky lit with it
	var light := OmniLight3D.new()
	light.light_color = Color(0.7, 0.85, 1.0)
	light.light_energy = 16.0
	light.omni_range = 3000.0
	world.add_child(light)
	light.global_position = burst
	var tl := light.create_tween()
	tl.tween_property(light, "light_energy", 0.0, 1.2)
	tl.tween_callback(light.queue_free)
	# and the screen: a flash and then static, thinning out
	var layer := CanvasLayer.new()
	layer.layer = 90
	var flash := ColorRect.new()
	flash.color = Color(0.75, 0.88, 1.0, 0.75)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var noise := _EmpStatic.new()
	noise.set_anchors_preset(Control.PRESET_FULL_RECT)
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(noise)
	world.add_child(layer)
	var tf := flash.create_tween()
	tf.tween_property(flash, "color:a", 0.0, 0.5)
	var tn := noise.create_tween()
	tn.tween_property(noise, "strength", 0.0, 2.2)
	tn.tween_callback(layer.queue_free)
	Sfx.play_at(world, "thump", at, 0.0, 0.45, 4000.0)
	Sfx.play_at(world, "ricochet", at, -6.0, 0.6, 4000.0)

## The static over the screen after an EMP: specks that thin out.
class _EmpStatic extends Control:
	var strength := 1.0
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var n: int = int(500.0 * strength)
		for i in n:
			var q := Vector2(randf() * size.x, randf() * size.y)
			draw_rect(Rect2(q, Vector2(randf_range(2.0, 6.0), 2.0)),
				Color(0.85, 0.92, 1.0, randf_range(0.2, 0.7) * strength))
		if strength > 0.3 and randf() < 0.5:
			var y: float = randf() * size.y
			draw_rect(Rect2(0.0, y, size.x, randf_range(1.0, 4.0)),
				Color(0.8, 0.9, 1.0, 0.35 * strength))

static func bullet(world: Node, pos: Vector3, vel: Vector3, owner: Node, dmg: float,
		team: int, glow := 1.0, life := 1.4, drag := 0.0011, pen := 0.0) -> Tracer:
	var t := Tracer.new()
	t.pen = pen
	t.heavy = pen >= 1.0
	t.vel = vel
	t.shooter = owner
	t.dmg = dmg
	t.team = team
	t.drag = drag
	t.small = true
	t.glow = glow
	t.life = life
	world.add_child(t)
	t.global_position = pos
	watch(t, owner)
	return t

## Where a round went in: a chip of dust, a spark, and the sound of it.
static func bullet_impact(world: Node, pos: Vector3, hard: bool) -> void:
	if world == null or not world.is_inside_tree():
		return
	var e := Boom.new()
	# A puff of dust or grit, not a flash. Drawn as every burst is -- a
	# glowing ball that swells -- each round that landed read as a small
	# explosive going off.
	e.radius = 0.07 if hard else 0.11
	e.tint = Color(0.70, 0.67, 0.61) if hard else Color(0.50, 0.43, 0.34)
	e.smoke = false
	e.lit = false
	e.dusty = true
	e.life_max = 0.22
	world.add_child(e)
	e.global_position = pos
	if randf() < 0.6:
		Sfx.play_at(world, "ricochet" if (hard and randf() < 0.3) else
			("impact_hard" if hard else "impact_soft"), pos, -9.0,
			randf_range(0.85, 1.25), 90.0)

## One cube a metre a side, scaled to whatever piece is wanted, and one
## material per colour. Every piece of a man used to be a mesh and a material
## of its own, built while he fell: twenty of each for a man caught by a shell,
## none of which the renderer could draw together.
static var _unit_box: ArrayMesh = null
static var _bit_mats := {}

static func unit_box() -> ArrayMesh:
	if _unit_box == null:
		var st := MeshKit.begin()
		MeshKit.box(st, Vector3.ONE, Vector3.ZERO)
		_unit_box = MeshKit.finish(st)
	return _unit_box

static func bit_mat(col: Color) -> StandardMaterial3D:
	var k: int = col.to_rgba32()
	var m: Variant = _bit_mats.get(k)
	if m == null:
		m = MeshKit.mat(col, 0.7, 0.0)
		_bit_mats[k] = m
	return m

## The gore bits a burst may still throw. Bodies, heads and limbs always come
## off; the spray is the part that piles up, fourteen seconds a piece, and in a
## street fight it piled up faster than it went away.
const GORE_BUDGET := 120
static var _gore_live := 0

## One piece of something, thrown: a box that flies, bounces and stays.
static func chunk(world: Node, at: Vector3, vel: Vector3, size: Vector3, col: Color,
		life := 30.0) -> Debris:
	if world == null or not world.is_inside_tree():
		return null
	var d := Debris.new()
	var bit := MeshKit.mi(unit_box(), "Bit")
	bit.material_override = bit_mat(col)
	bit.scale = size
	# a few centimetres of red is not going to throw a shadow anyone sees
	if size.x < 0.1:
		bit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.add_child(bit)
	d.vel = vel
	d.spin = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
	d.rest_offset = maxf(size.y * 0.5, 0.04)
	d.bounce = 0.2
	d.life = life
	world.add_child(d)
	d.global_position = at
	return d

static var _pools := 0
const POOL_BUDGET := 48

## What is left on the road. It spreads for a couple of seconds and stays.
static func blood_pool(world: Node, at: Vector3, size := 1.0) -> void:
	if world == null or not world.is_inside_tree() or _pools >= POOL_BUDGET:
		return
	var p := Pool.new()
	p.size = size
	world.add_child(p)
	p.global_position = Vector3(at.x, Sim.height_at(at.x, at.z) + 0.03, at.z)

static var pool_mesh: CylinderMesh = null

class Pool extends MeshInstance3D:
	var size := 1.0
	var age := 0.0
	const LIFE := 50.0
	const SPREAD := 2.5

	func _ready() -> void:
		Effects._pools += 1
		# One disc for all of them: they were a mesh and a material each,
		# identical down to the colour.
		if Effects.pool_mesh == null:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.01
			cm.radial_segments = 9
			cm.rings = 1
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.30, 0.02, 0.02, 0.92)
			m.roughness = 0.25
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cm.material = m
			Effects.pool_mesh = cm
		mesh = Effects.pool_mesh
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotation.y = randf() * TAU
		scale = Vector3(0.05, 1.0, 0.05)
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		# Spreads for a couple of seconds and then only waits: the wait is a
		# timer, not fifty seconds of frames doing nothing.
		get_tree().create_timer(LIFE, false).timeout.connect(queue_free)

	func _exit_tree() -> void:
		Effects._pools -= 1

	func _process(delta: float) -> void:
		age += delta
		var k: float = clampf(age / SPREAD, 0.0, 1.0)
		k = 1.0 - (1.0 - k) * (1.0 - k)
		scale = Vector3(size * (0.2 + 1.3 * k), 1.0, size * (0.2 + 1.0 * k))
		if age >= SPREAD:
			set_process(false)

## A spray of it: where a round came out, or where a limb was.
static func gore_burst(world: Node, at: Vector3, dir: Vector3, bits := 5, speed := 4.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	for i in mini(bits, GORE_BUDGET - _gore_live):
		var v: Vector3 = dir * randf_range(0.4, 1.0) * speed + Vector3(randf_range(-1.5, 1.5),
			randf_range(0.5, 3.0), randf_range(-1.5, 1.5))
		var s: float = randf_range(0.03, 0.09)
		var bit := chunk(world, at, v, Vector3(s, s, s), Color(0.42, 0.03, 0.03), 14.0)
		if bit != null:
			_gore_live += 1
			# counted down when it goes, whichever way it goes
			bit.tree_exited.connect(func() -> void: Effects._gore_live -= 1)
	var e := Boom.new()
	e.radius = 0.32
	e.tint = Color(0.60, 0.04, 0.03)
	e.smoke = false
	e.lit = false
	e.life_max = 0.35
	world.add_child(e)
	e.global_position = at

## Nothing left to fall down: what a shell, a grenade or a tank track leaves.
static func gib(world: Node, at: Vector3, vel: Vector3, suit: Color) -> void:
	if world == null or not world.is_inside_tree():
		return
	var mid := at + Vector3(0, 1.0, 0)
	var parts := [[Vector3(0.26, 0.28, 0.27), suit.darkened(0.3)], [Vector3(0.12, 0.50, 0.12), suit],
		[Vector3(0.12, 0.50, 0.12), suit], [Vector3(0.16, 0.42, 0.16), suit],
		[Vector3(0.16, 0.42, 0.16), suit], [Vector3(0.36, 0.30, 0.22), Color(0.45, 0.05, 0.04)],
		[Vector3(0.14, 0.09, 0.28), Color(0.12, 0.12, 0.13)], [Vector3(0.20, 0.16, 0.16), Color(0.5, 0.06, 0.05)],
		[Vector3(0.18, 0.12, 0.12), Color(0.55, 0.08, 0.06)], [Vector3(0.10, 0.10, 0.10), Color(0.6, 0.1, 0.08)]]
	for p in parts:
		var v: Vector3 = vel * 0.5 + Vector3(randf_range(-5, 5), randf_range(2.5, 8.0), randf_range(-5, 5))
		chunk(world, mid + Vector3(randf_range(-0.3, 0.3), randf_range(-0.5, 0.5), randf_range(-0.3, 0.3)),
			v, p[0], p[1], 40.0)
	gore_burst(world, mid, Vector3.UP, 10, 6.0)
	for k in 3:
		blood_pool(world, at + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.2, 1.2)),
			randf_range(0.6, 1.4))
	Sfx.play_at(world, "hit_body", mid, 2.0, 0.6, 120.0)

## A round going into a man.
static func blood(world: Node, pos: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var e := Boom.new()
	e.radius = 0.2
	e.tint = Color(0.55, 0.05, 0.04)
	e.smoke = false
	e.lit = false
	e.life_max = 0.32
	world.add_child(e)
	e.global_position = pos
	Sfx.play_at(world, "hit_body", pos, -7.0, randf_range(0.9, 1.15), 60.0)
	if randf() < 0.5:
		gore_burst(world, pos, Vector3.ZERO, 2, 2.0)

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
	var fb := NukeBall.new()
	fb.lethal = lethal
	fb.flash = flash
	# so the cap can have a lit top and a dark underside
	if "_sun" in world:
		fb.sun_node = world.get("_sun")
	fb.position = pos
	world.add_child(fb)
	# the ground wave: a ring of dust at the burst, and the wave itself
	# running out past everything it knocks down (`Shockwave`)
	for i in 10:
		var a := TAU * float(i) / 10.0
		dust(world, pos + Vector3(cos(a), 0.0, sin(a)) * lethal * 0.35, lethal * 0.12)
	var sw := Shockwave.new()
	sw.reach = lethal * 1.8
	sw.speed = Scenery.SHOCK_SPEED
	world.add_child(sw)
	sw.global_position = pos
	# No smoke particles. The column used to be fed by a hundred and twenty
	# billboards climbing out of the fireball, which is what a mushroom cloud
	# was made of before it became a volume -- and against a raymarched column
	# they are just a swarm of dark quads crawling up through it, each one
	# turning to face the camera. The volume is the smoke now.

## Value noise for the fire and smoke shaders, shared by both.
const NOISE_GLSL := """
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
"""

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

## Men on foot are not in "hittable", so nothing that works by blast ever
## touched them: a 105 mm shell landing in a squad was a light show. Every burst
## comes through one of two functions, so this is asked from both. `credit` is
## who called the fire in, `spare_team` the side it is not meant for, and
## `mute_blast` is for a caller that has already done its own sums.
static var credit: Node = null
static var spare_team := -1
static var mute_blast := false

static func _blast_infantry(world: Node, pos: Vector3, r: float) -> void:
	if mute_blast or world == null or not world.is_inside_tree():
		return
	# a blast nobody has named is a blast
	var was_cause: String = KillFeed.cause
	if was_cause == "":
		KillFeed.cause = "explosion"
	for n in world.get_tree().get_nodes_in_group("infantry"):
		if not is_instance_valid(n) or not n.has_method("take_hit"):
			continue
		if spare_team >= 0 and "team" in n and n.team == spare_team:
			continue
		var d: float = ((n as Node3D).global_position + Vector3(0, 0.9, 0)).distance_to(pos)
		if d < r:
			n.take_hit(280.0 * pow(1.0 - d / r, 1.2), credit if is_instance_valid(credit) else null)
	KillFeed.cause = was_cause

## `flatten` false: the blast hurts and is seen, but leaves buildings to
## whoever set it off -- a mortar bomb wears them down (`Scenery.batter`)
## rather than levelling whatever its middle is near.
static func explosion(world: Node, pos: Vector3, radius: float, smoke := true,
		flatten := true) -> void:
	TownSet.glass_blast(pos, radius * 3.0)
	_blast_infantry(world, pos, maxf(radius * 0.8, 5.0))
	# anything standing inside the blast comes down
	if flatten and Scenery.current != null and is_instance_valid(Scenery.current) and radius > 5.0:
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

## A high explosive shell going off where it lands.
##
## Every cannon round in the game hit with a puff of dust, which is right for a
## solid shot and wrong for the one gun the A-10 was built around: a GAU-8 fires
## 30 mm high explosive incendiary, and a burst of it walking across a target
## is a string of small detonations. The flash, a fireball, and the dirty smoke
## that hangs afterwards -- built from the same cheap pieces a bomb burst uses,
## because a hundred rounds a second of these have to stay affordable.
## `dmg` and `shooter`, when given, are the shell's own: a burst also catches
## anything with a hull that it lands beside. Without that a cannon shell did
## nothing at all to a vehicle unless it struck it squarely -- a GAU-8 burst
## walked across a column a metre short of every tank left them all untouched.
static func he_impact(world: Node, pos: Vector3, scale := 1.0, dmg := 0.0,
		shooter: Node = null, team := -1) -> void:
	if world == null or not is_instance_valid(world):
		return
	TownSet.glass_blast(pos, 6.0 * scale)
	_blast_infantry(world, pos, 3.2 * scale)
	if dmg > 0.0 and world.is_inside_tree():
		var rv: float = 2.4 * scale
		for n in world.get_tree().get_nodes_in_group("hittable"):
			if not is_instance_valid(n) or n == shooter or not (n is Node3D) \
					or n.is_in_group("infantry") or not n.has_method("take_hit"):
				continue
			if team >= 0 and ("team" in n) and int(n.team) == team:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			var d: float = (n as Node3D).global_position.distance_to(pos)
			if n.has_method("surface_gap"):
				d = maxf(float(n.call("surface_gap", pos)), 0.0)
			elif n.has_method("hit_radius"):
				d = maxf(d - float(n.call("hit_radius")), 0.0)
			if d < rv:
				n.take_hit(dmg * 0.55 * (1.0 - d / rv), shooter if is_instance_valid(shooter) else null)
	var f := Flash.new()
	f.size = 0.85 * scale
	f.dir = Vector3.UP
	world.add_child(f)
	f.global_position = pos
	var e := Boom.new()
	e.radius = 1.35 * scale
	e.tint = Color(1.0, 0.70, 0.30)
	e.life_max = 0.30
	world.add_child(e)
	e.global_position = pos
	# what is left standing in the air after it
	var sm := Boom.new()
	sm.radius = 2.1 * scale
	sm.tint = Color(0.20, 0.19, 0.18)
	sm.lit = false
	sm.life_max = 1.05
	world.add_child(sm)
	sm.global_position = pos + Vector3(0.0, 0.55 * scale, 0.0)

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

## A ribbon laid along wherever a thing has been: the engine's `Trail3D`,
## which arrived in 4.8.
##
## Puffs of smoke are the right picture of a fire and the wrong one of a
## rocket. Forty-eight of them over two seconds behind a round doing eight
## hundred metres a second are thirty metres apart -- a dotted line -- where
## what a motor actually leaves is one unbroken thread, curved the way the
## round turned. A ribbon is that thread, and the puffs go on doing the first
## few metres behind the nozzle where there is something to billow.
##
## Not free, and measured rather than assumed: about twenty microseconds of
## the frame for each one alive, whatever its length, because the strip is
## rebuilt as it moves. So they are counted, like the plumes above, in two
## pools -- one for what flies for seconds and is worth watching, a smaller
## one for cannon rounds, of which there can be a great many -- and past the
## count a round simply flies without one. Sections are kept long: at the
## default a fifth of a metre a missile's trail is ten thousand of them.
##
## One colour and one width along its length. The node takes a gradient and
## a width curve as well, but at beta 3 neither is documented and neither did
## what its name says when it was tried, so nothing here leans on them.
const RIBBON_BUDGET := [56, 16]
static var ribbons := [0, 0]

static func ribbon(colour: Color, width: float, life: float, section := 6.0,
		additive := false, pool := 0) -> GeometryInstance3D:
	if int(ribbons[pool]) >= int(RIBBON_BUDGET[pool]) or not ClassDB.class_exists(&"Trail3D"):
		return null
	var r := ClassDB.instantiate(&"Trail3D") as GeometryInstance3D
	if r == null:
		return null
	r.set(&"limit_mode", 0)                     # by time
	r.set(&"lifetime", life)
	r.set(&"width", width)
	r.set(&"min_section_length", section)
	r.set(&"mesh_alignment", 1)                 # facing the camera
	r.set(&"material_mode", 1 if additive else 0)
	r.set(&"color", colour)
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ribbons[pool] = int(ribbons[pool]) + 1
	r.tree_exited.connect(func() -> void:
		ribbons[pool] = maxi(int(ribbons[pool]) - 1, 0), CONNECT_ONE_SHOT)
	return r

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
	# Bound to the emitter itself, not a lambda holding it: a match sweep frees
	# it first as often as not, and a freed capture is an engine error each
	# time; a connection to a freed object is simply dropped.
	t.timeout.connect(p.queue_free)

# ----------------------------------------------------------------- re-entry
## How hot the air is being made by something going `speed` through it at
## `alt`, from 0 to 1: the stagnation heating, half rho v cubed, on a log
## scale. A capsule coming in from orbit is barely warm at a hundred
## kilometres, white at sixty-five and out by thirty; a warhead, which keeps
## its speed, is white from fifty to the ground. A rocket climbing out is not
## going fast enough low enough to light up at all, which is right.
static func reentry_heat(alt: float, speed: float) -> float:
	if alt > 125000.0 or speed < 900.0:
		return 0.0
	var rho: float = 1.225 * exp(-maxf(alt, 0.0) / 8500.0)
	var q: float = 0.5 * rho * speed * speed * speed
	if q <= 1.0:
		return 0.0
	return smoothstep(6.8, 8.6, log(q) / log(10.0))

## The glow round something coming in hot, for `reentry_heat`: a sheath of
## plasma bunched on the face meeting the air, a trail of it streaming off
## behind, and the light it throws. Hung on whatever is coming in and told
## each frame how fast, which way and how hot; it points itself.
static func plasma(on: Node3D, size: float) -> Plasma:
	var p := Plasma.new()
	p.size = size
	on.add_child(p)
	return p

class Plasma extends Node3D:
	const SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform float heat = 0.0;
uniform float plume = 0.0;
varying float along;
varying vec3 lpos;
void vertex() {
	along = VERTEX.z;
	lpos = VERTEX;
}
vec3 ramp(float h) {
	vec3 c = mix(vec3(0.5, 0.05, 0.01), vec3(1.0, 0.36, 0.05), smoothstep(0.0, 0.4, h));
	return mix(c, vec3(1.0, 0.7, 0.32), smoothstep(0.45, 1.0, h));
}
float n3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
void fragment() {
	float edge = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	float flick = 0.8 + 0.2 * sin(TIME * 47.0 + along * 9.0)
		+ 0.15 * (n3(floor(lpos * 6.0 + TIME * 20.0)) - 0.5);
	float a;
	if (plume > 0.5) {
		// bright at the body, gone at the tail, hottest down the middle
		float t = clamp(along, 0.0, 1.0);
		float k = 1.0 - t;
		a = k * k * k * (1.0 - edge) * 0.9;
		ALBEDO = ramp(heat * (1.0 - t * 0.5)) * heat * a * flick;
	} else {
		// A cap on the face meeting the air, not a bubble round the whole of
		// it: hottest at the front (-z), gone by the back, where the trail
		// takes over. Brightest at the rim, where you look through most of it.
		float front = smoothstep(0.7, -0.9, lpos.z);
		a = (pow(edge, 1.6) * 0.9 + 0.3) * front;
		ALBEDO = mix(ramp(heat), vec3(1.0, 0.9, 0.75), smoothstep(0.85, 1.0, heat) * 0.5)
			* heat * a * flick;
	}
}
"""
	var size := 1.0
	var heat := 0.0
	var _sheath: MeshInstance3D
	var _plume: MeshInstance3D
	var _light: OmniLight3D
	var _ms: ShaderMaterial
	var _mp: ShaderMaterial

	func _ready() -> void:
		top_level = true
		var sh := Shader.new()
		sh.code = SHADER
		_ms = ShaderMaterial.new()
		_ms.shader = sh
		_ms.render_priority = 6
		_mp = ShaderMaterial.new()
		_mp.shader = sh
		_mp.set_shader_parameter("plume", 1.0)
		_mp.render_priority = 6
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 20
		sm.rings = 10
		_sheath = MeshInstance3D.new()
		_sheath.mesh = sm
		_sheath.material_override = _ms
		_sheath.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_sheath)
		# a unit cone, base at the body and point one unit back; scaled to length
		var st := MeshKit.begin()
		MeshKit.cone(st, 1.0, 0.04, 0.0, 1.0, Vector3.ZERO, 14, false)
		_plume = MeshInstance3D.new()
		_plume.mesh = MeshKit.finish(st)
		_plume.material_override = _mp
		_plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_plume)
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.6, 0.3)
		_light.shadow_enabled = false
		add_child(_light)
		visible = false

	## Where the body is, which way the air is coming from, and how hot.
	func feed(at: Vector3, vel: Vector3, h: float) -> void:
		heat = lerpf(heat, h, 0.25)
		visible = heat > 0.01 and vel.length() > 1.0
		if not visible:
			return
		var fwd: Vector3 = vel.normalized()
		var up_ref := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT
		# -Z along the flight, so +Z, where the plume runs, is behind it
		global_transform = Transform3D(Basis.looking_at(fwd, up_ref), at)
		var r: float = size
		_sheath.position = Vector3(0.0, 0.0, -r * 0.2)
		_sheath.scale = Vector3(r * 1.1, r * 1.1, r * (1.1 + heat * 0.6))
		_plume.position = Vector3(0.0, 0.0, -r * 0.2)
		var long: float = r * (4.0 + heat * 30.0) * (0.92 + 0.16 * randf())
		_plume.scale = Vector3(r * 0.85, r * 0.85, long)
		_ms.set_shader_parameter("heat", heat)
		_mp.set_shader_parameter("heat", heat)
		_light.light_color = Color(1.0, 0.45 + heat * 0.4, 0.25 + heat * 0.55)
		_light.light_energy = heat * 18.0
		_light.omni_range = r * 40.0 + 60.0

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
		m.render_priority = 6
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
## Streaks, one per shape, and their materials, one per colour. Every round
## built a mesh and a material of its own as it left the barrel: a dozen new
## GPU resources a second for each man firing, none of which could be drawn
## alongside another.
static var streaks := {}
static var streak_mats := {}

## Further than this from a round's step and nothing can be touched by it: the
## widest thing that can be hit is a carrier, about 27 m either side.
const REACH_HIT := 40.0
## and a man, from the feet the distance is measured from to the top of his head
const REACH_MAN := 2.5

static var boom_sphere: SphereMesh = null

class Boom extends Node3D:
	var radius := 12.0
	var life := 0.0
	var life_max := 0.85
	var tint := Color(1.0, 0.62, 0.22)
	var smoke := true
	## Whether the burst lights what is around it. A fireball does; the dirty
	## smoke left hanging behind one does not, and a grey lamp under a shell
	## burst reads as fog rather than as soot.
	var lit := true
	## Dust rather than fire: laid over the picture, not added to it as light.
	var dusty := false
	var _mi: MeshInstance3D
	var _light: OmniLight3D
	var _mat: StandardMaterial3D

	func _ready() -> void:
		top_level = true
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_mi = MeshInstance3D.new()
		# One sphere for every burst: each made its own, and a new mesh is
		# built the first time it is drawn -- a blood puff for every round
		# that hit anybody. The material stays its own, because it fades.
		if Effects.boom_sphere == null:
			var sm := SphereMesh.new()
			sm.radius = 1.0
			sm.height = 2.0
			sm.radial_segments = 10
			sm.rings = 6
			Effects.boom_sphere = sm
		_mi.mesh = Effects.boom_sphere
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if dusty \
			else BaseMaterial3D.BLEND_MODE_ADD
		_mat.albedo_color = tint
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Transparent surfaces do not write depth; they are sorted, and the sort
		# key is the object's origin. The sea is one mesh sixty kilometres wide
		# whose origin is the middle of the world, so from anywhere out over the
		# water it sorted in front of a fireball at the surface and composited
		# 86% opaque sea over the top of it. A bomb into the water looked like a
		# dud. Explosions are drawn last, over everything transparent.
		_mat.render_priority = 8
		_mi.material_override = _mat
		_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mi)
		# Every burst lights the ground, not just the ones that also make smoke.
		# Rocket artillery and missile warheads asked for no smoke and therefore
		# got no light either, so at night a salvo arriving was a few grey
		# puffs: the one time of day an explosion should be the brightest thing
		# for miles.
		if lit:
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
		if dusty:
			_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.4 * (1.0 - t))
		else:
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
		var _pd := Sim.prof_at()
		_settle(delta)
		Sim.prof_end(&"fx.debris", _pd)

	func _settle(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		if at_rest():
			return
		vel += Vector3.DOWN * 9.81 * delta
		global_position += vel * delta
		rotation += spin * delta
		# whatever is under it: a roof, a heap of rubble, a wall top -- not
		# only the ground, which a piece landing on a heap sank through
		var floor_y: float = maxf(Sim.height_at(global_position.x, global_position.z),
			Obstacles.floor_under(global_position.x, global_position.z, global_position.y + 0.3))
		if floats:
			floor_y = maxf(floor_y, Sim.sea_surface(global_position.x,
				global_position.z))
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
				# Nothing moves it again once it is down, so stop asking. It
				# was a call a tick for every piece on the ground for as long
				# as it lay there -- forty seconds for what a shell leaves.
				set_physics_process(false)
				get_tree().create_timer(maxf(life, 0.05), false).timeout.connect(queue_free)
