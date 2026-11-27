class_name Tracer
extends Node3D

## Moved out of `effects.gd` (`Effects.Tracer`).

var vel := Vector3.ZERO
var shooter: Node = null
var dmg := 30.0
var team := 0
var life := 2.2
## Burst scale of an explosive shell; 0 is solid shot and puffs dust.
var he := 0.0
## Small arms: drawn thin, stopped by buildings, heard going past.
var small := false
## A vehicle's machine gun: flies and hits as a shell does, drawn slighter.
var light := false
## A picture of a round somebody else's machine fired: drawn, heard and
## bursting like the real one, hurting nothing. The real one, on the
## machine that owns the gun, deals the damage.
var harmless := false
var glow := 1.0
var _whizzed := false
## How much it can still go through, as metres of wall. A round used to
## stop dead on the first thing it met -- a plank, a fence panel, a man --
## whatever had fired it. Now whatever it meets is measured along the line
## it is flying, and if there is less of it than the round has left it
## comes out the far side, slower and worth less, and carries on: through
## a partition and into the man behind it, or through one man and into
## the next. Soft things -- a car door, a kiosk -- cost a third as much as
## masonry, and a man costs `MAN_COST`.
var pen := 0.0
const MAN_COST := 0.3
## An anti-materiel round: marks more than the paint on a vehicle.
var heavy := false
var _struck: Array = []
var _resume := Vector3.ZERO
## Who this round has already gone close past. A round that misses a man
## by an arm's length used to be the same to him as one that missed by a
## street; now it tells him, once, how near it was and how big: see
## `Soldier.suppress` and `Walker.suppress`.
var _scared: Array = []
const NEAR_MISS := 2.4
## How much of its speed it loses to the air per metre: see `Ballistics`.
## A cannon shell keeps it better than a rifle round.
var drag := 0.0005
var _flown := 0.0
## Where it stopped, whatever stopped it. For the harness, and for anything
## that wants to know where a round went in.
var ended_at := Vector3.INF
## What it is, when somebody needs to know: an entry of `Firearm.CAL`.
## Set on the range, where the bullet camera rides it and draws it.
var cal: Dictionary = {}
var _round: Node3D = null

## How close the bullet camera sits. A round is a couple of centimetres
## long: the boom built for a missile put it a pixel in the distance.
func ride_scale() -> float:
	if cal.is_empty():
		return 1.0
	return float(cal["len"]) * 0.30

## The bullet itself, to its own calibre, for the camera riding it: the
## glowing streak a round is drawn as stood in front of the lens instead.
func show_round(on: bool) -> void:
	if on and _round == null and not cal.is_empty():
		_round = Node3D.new()
		var d: float = float(cal["d"])
		var ln: float = float(cal["len"])
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cal.get("col", Color(0.78, 0.52, 0.28))
		mat.metallic = 0.85
		mat.roughness = 0.28
		if cal.get("ball", false):
			var sm := SphereMesh.new()
			sm.radius = d * 0.5
			sm.height = d
			sm.material = mat
			var b := MeshInstance3D.new()
			b.mesh = sm
			_round.add_child(b)
		else:
			# a shank and an ogive, pointed down -Z the way it flies
			var body := CylinderMesh.new()
			body.top_radius = d * 0.5
			body.bottom_radius = d * 0.5
			body.height = ln * 0.55
			body.radial_segments = 16
			body.material = mat
			var bm := MeshInstance3D.new()
			bm.mesh = body
			bm.rotation_degrees = Vector3(90, 0, 0)
			bm.position = Vector3(0, 0, ln * 0.225)
			_round.add_child(bm)
			var nose := CylinderMesh.new()
			nose.top_radius = d * 0.06
			nose.bottom_radius = d * 0.5
			nose.height = ln * 0.45
			nose.radial_segments = 16
			nose.material = mat
			var nm := MeshInstance3D.new()
			nm.mesh = nose
			nm.rotation_degrees = Vector3(-90, 0, 0)
			nm.position = Vector3(0, 0, -ln * 0.275)
			_round.add_child(nm)
		add_child(_round)
	if _round != null:
		_round.visible = on
	for c in get_children():
		if c != _round and c is MeshInstance3D:
			(c as MeshInstance3D).visible = not on

## How far along a step the round meets the ground, as a fraction of it, or
## 2.0 if it does not.
##
## The ground was asked about once a step, at its end -- seven metres on
## for a rifle round. A round that skimmed a hump in the middle went
## through it, and one that went into the road was put into it at the end
## of the step, metres past where it struck: lying down, where every line
## of sight grazes the road, the strike landed well beyond the mark. Looked
## for along the step, then pinned down by halving.
func _ground_t(from: Vector3, to: Vector3) -> float:
	var c0: float = from.y - Sim.height_at(from.x, from.z)
	var c1: float = to.y - Sim.height_at(to.x, to.z)
	# well clear at both ends: no hump in a few metres reaches it
	if c0 > 3.0 and c1 > 3.0:
		return 2.0
	var n: int = clampi(int(ceil(from.distance_to(to) / 1.25)), 1, 16)
	var lo := 0.0
	for i in range(1, n + 1):
		var t: float = float(i) / float(n)
		var p: Vector3 = from.lerp(to, t)
		if p.y < Sim.height_at(p.x, p.z):
			var hi: float = t
			for k in 6:
				var m: float = (lo + hi) * 0.5
				var q: Vector3 = from.lerp(to, m)
				if q.y < Sim.height_at(q.x, q.z):
					hi = m
				else:
					lo = m
			return hi
		lo = t
	return 2.0

func _ready() -> void:
	var mi := MeshInstance3D.new()
	# A cross of two quads along the flight axis. Billboarding fought the
	# look_at that keeps the round pointed along its travel, which is what
	# made the bolts sit at the wrong angle.
	# Hotter than the old orange, and over-bright so it blooms: a tracer is
	# a burning pellet, and what the eye picks out at two kilometres is the
	# glare rather than the colour.
	var colour := Color(2.4, 1.35, 0.55, 0.95)
	# Stretched along the way it is going, by how fast it is going.
	#
	# The round was a fixed nine metres of quad. A cannon shell leaves the
	# muzzle at a kilometre a second and covers sixteen metres in a frame,
	# so nine metres is shorter than the gap between one drawn position and
	# the next: it reads as a dot flickering across the sky, which is why
	# neither the gun nor the anti-aircraft cannon looked like it was firing
	# tracer. A streak longer than the step joins up into a line, which is
	# what tracer actually looks like.
	var speed: float = vel.length()
	var half: float = clampf(speed * 0.013, 4.5, 30.0)
	var wide: float = clampf(speed * 0.0009, 0.55, 1.5)
	if small:
		# A cannon streak is nine metres by one, which across a street is
		# a searchlight. A rifle round is a line you half see.
		half = clampf(speed * 0.0032, 0.7, 2.8)
		wide = 0.035
		colour = Color(2.2, 1.5, 0.7, 0.9 * glow)
	elif light:
		# Between the two: a third of a shell's streak and a fifth of its
		# width, and red where the shell is yellow-white.
		half = clampf(speed * 0.0045, 2.0, 6.0)
		wide = 0.18
		colour = Color(2.6, 0.42, 0.22, 0.9)
	# A handful of shapes rather than one per round: the length to a
	# quarter metre on a rifle round and a metre on a shell, which is
	# less than the streak moves in a frame.
	half = snappedf(half, 0.25 if small else 1.0)
	wide = snappedf(wide, 0.005 if small else 0.05)
	var ckey: int = colour.to_rgba64()
	var mat: Variant = Effects.streak_mats.get(ckey)
	if mat == null:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = colour
		sm.albedo_texture = Effects.glow_texture()
		sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.render_priority = 6
		Effects.streak_mats[ckey] = sm
		mat = sm
	var mkey := Vector2(half, wide)
	var cached: Variant = Effects.streaks.get(mkey)
	if cached != null:
		mi.mesh = cached
		mi.material_override = mat
		_finish_ready(mi, half)
		return
	# Built by hand, with texture coordinates. It was two MeshKit quads,
	# and MeshKit writes none: every vertex sampled the glow at (0, 0),
	# which is the transparent corner of a radial gradient, so the streak
	# was added to the screen as black -- every gun in the game fired
	# invisible rounds. Across the streak the glow falls off to the edges;
	# along it the core is hottest in the middle and the ends taper.
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for roll in [0.0, PI * 0.5]:
		var up := Vector3(cos(roll), sin(roll), 0.0) * wide
		var b := verts.size()
		# All of it behind the round, none of it ahead. Centred on the
		# round, half the streak stuck out backwards from the muzzle the
		# moment it was fired -- thirteen metres of it for a cannon shell
		# -- which from a chase camera, a turret camera or over a man's
		# shoulder is a line of fire that starts at the lens.
		verts.append_array(PackedVector3Array([
			up, -up,
			-up + Vector3(0, 0, half * 2.0), up + Vector3(0, 0, half * 2.0)]))
		uvs.append_array(PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	Effects.streaks[mkey] = m
	mi.mesh = m
	mi.material_override = mat
	_finish_ready(mi, half)

func _finish_ready(mi: MeshInstance3D, half: float) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_mi = mi
	_len = half * 2.0
	# nothing to draw until it has gone somewhere
	mi.scale = Vector3(1.0, 1.0, 0.001)
	top_level = true
	reset_physics_interpolation.call_deferred()

var _mi: MeshInstance3D = null
var _len := 1.0
## Where it left the barrel. The streak is never longer than the distance
## the round has actually covered, so it grows out of the muzzle instead of
## appearing full length across it.
var _born := Vector3.INF

## Kept a few pixels wide however far off it is. A metre and a half of
## streak is a sliver at a kilometre and nothing at two, and a tracer is
## a thing you see from a long way: the eye picks out the glare, not the
## size of the pellet. Widened, never lengthened -- the length is how far
## it travels in a frame, and that is what makes it read as a line.
func _process(_dt: float) -> void:
	if _mi == null:
		return
	var eye := get_viewport().get_camera_3d()
	if eye == null:
		return
	var far: float = eye.global_position.distance_to(global_position)
	var s: float = clampf(far / 420.0, 1.0, 7.0)
	if light:
		s = clampf(far / 160.0, 1.0, 9.0)
	if small:
		s = clampf(far / 22.0, 1.0, 24.0)
	var gone: float = 0.0 if _born == Vector3.INF else _born.distance_to(global_position)
	_mi.scale = Vector3(s, s, clampf(gone / _len, 0.001, 1.0))

func _physics_process(delta: float) -> void:
	var _pb := Sim.prof_at()
	_fly(delta)
	Sim.prof_end(&"fx.bullet", _pb)

func _fly(delta: float) -> void:
	life -= delta
	var from := global_position
	if _born == Vector3.INF:
		_born = from
	vel = Ballistics.step(from, vel, drag, delta, _flown)
	var to := from + vel * delta
	_flown += vel.length() * delta
	# through a window on the way: the pane goes, the round carries on
	if not harmless:
		TownSet.glass_hit(from, to)
	if small:
		if _small_step(from, to):
			return
		global_position = to
		if vel.length_squared() > 1.0:
			look_at(to + vel, Vector3.UP)
		if to.y < Sim.height_at(to.x, to.z):
			ended_at = to
			Effects.bullet_impact(get_tree().current_scene, to, false)
			queue_free()
		elif life <= 0.0:
			ended_at = to
			queue_free()
		return
	# Buildings and what stands in the street, the same as a rifle round.
	# Shells and machine-gun rounds were tested against the ground and
	# against targets and nothing else: a coaxial, an aeroplane's cannon,
	# the chin gun and the anti-aircraft guns all fired straight through
	# houses, and the man behind the wall was hit through it.
	var wall_t: float = Obstacles.segment(from, to)
	var dirt_t: float = _ground_t(from, to)
	var end: Vector3 = to if minf(wall_t, dirt_t) >= 1.0 else from.lerp(to, minf(wall_t, dirt_t))
	global_position = end
	if vel.length_squared() > 1.0:
		look_at(end + vel, Vector3.UP)
	# men on foot as well as everything on the radar picture: a coaxial
	# machine gun that could not hit a rifleman was no use in a street
	#
	# Read from the picture `Sim` keeps for the tick: where everything is,
	# how big and whose, as plain arrays. This used to join the two groups
	# into a fresh array for every round on every tick and then ask each
	# thing in it five questions; now what the step cannot reach, and what
	# is on the round's own side, costs a subtraction and a compare.
	Sim.hit_scan()
	var mid: Vector3 = (from + end) * 0.5
	var half_step: float = from.distance_to(end) * 0.5
	for pass_i in 2:
		var men: bool = pass_i == 1
		var pos: PackedVector3Array = Sim.man_pos if men else Sim.hit_pos
		var whose: PackedInt32Array = Sim.man_team if men else Sim.hit_team
		var nodes: Array = Sim.man_nodes if men else Sim.hit_nodes
		var rads: PackedFloat32Array = Sim.hit_rad
		for i in pos.size():
			if whose[i] == team:
				continue
			var r: float = Effects.REACH_MAN if men else rads[i]
			var reach: float = half_step + r
			if pos[i].distance_squared_to(mid) > reach * reach:
				continue
			var n: Variant = nodes[i]
			if not is_instance_valid(n) or n == shooter:
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if men:
				r = n.hit_radius() if n.has_method("hit_radius") else 6.0
			var np: Vector3 = n.global_position
			if Geometry3D.get_closest_point_to_segment(np, from, end).distance_to(np) < r:
				if n.has_method("take_hit") and not harmless:
					n.take_hit(dmg, shooter if is_instance_valid(shooter) else null)
				ended_at = end
				if he > 0.0:
					_he(end, he, 0.0)
				else:
					Effects.dust(get_tree().current_scene, end, 0.4 if light else 1.2)
				queue_free()
				return
	if wall_t < 1.0 and wall_t <= dirt_t:
		ended_at = end
		# just short of the face, so the burst is on this side of it
		var face: Vector3 = end - vel.normalized() * 0.08
		if he > 0.0:
			_he(face, he * 0.85, dmg)
		else:
			Effects.bullet_impact(get_tree().current_scene, face, true)
		queue_free()
		return
	if dirt_t < 1.0 or end.y < Sim.height_at(end.x, end.z):
		ended_at = end
		if he > 0.0:
			_he(end, he * 0.85, dmg)
		else:
			Effects.dust(get_tree().current_scene, end, 0.5 if light else 1.6)
		queue_free()
	elif life <= 0.0:
		queue_free()

## One tick of a rifle round. Walls first, because whatever is behind one
## is safe from it; then anyone standing in what is left of the path; and
## last, whether it went close enough past the listener to be heard.
func _small_step(from: Vector3, to_in: Vector3) -> bool:
	var a := from
	for layer in 6:
		if a.distance_squared_to(to_in) < 1e-4:
			return false
		var r: int = _small_leg(a, to_in)
		if r == 0:
			return false
		if r != 2:
			return true
		a = _resume
	# six things in one step is a round that has found a seam to run along
	ended_at = a
	queue_free()
	return true

## One stretch of that tick, as far as the first thing in the way: 0 if
## nothing was, 1 if the round ended there, 2 if it went through and goes
## on from `_resume`, and 3 if it went through and is where it comes out.
func _small_leg(from: Vector3, to_in: Vector3) -> int:
	var world := get_tree().current_scene
	var stop := to_in
	var wall: float = Obstacles.segment(from, stop)
	var wall_exit: float = Obstacles.seg_exit
	var wall_soft: bool = Obstacles.seg_soft
	# and the ground, on the same footing: whatever is behind a fold in
	# the road is as safe from the round as whatever is behind a wall
	var dirt: float = _ground_t(from, to_in)
	var cut: float = minf(wall, dirt)
	if cut < 1.0:
		stop = from.lerp(to_in, cut)
	var best: Node = null
	var best_t := 2.0
	var best_k := 0.0
	var best_rotor := -1
	Sim.hit_scan()
	var step_mid: Vector3 = (from + stop) * 0.5
	var half_len: float = from.distance_to(stop) * 0.5
	for pass_i in 2:
		var men: bool = pass_i == 0
		var pos: PackedVector3Array = Sim.man_pos if men else Sim.hit_pos
		var whose: PackedInt32Array = Sim.man_team if men else Sim.hit_team
		var nodes: Array = Sim.man_nodes if men else Sim.hit_nodes
		var near: float = half_len + (Effects.REACH_MAN if men else Effects.REACH_HIT)
		near *= near
		for i in pos.size():
			# its own side, and everything the step cannot reach, before
			# anything is asked of it
			if whose[i] == team or pos[i].distance_squared_to(step_mid) > near:
				continue
			var n: Variant = nodes[i]
			if not is_instance_valid(n) or n == shooter or _struck.has(n) \
					or (n is Aircraft and (n as Node).is_in_group("holds")):
				# an aircraft with a hold is hollow: it is asked below, by
				# its shape, rather than as a ball round its middle
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			var k := 0.0
			var at := 0.0
			if n.has_method("bullet_hit"):
				var r: Vector2 = n.bullet_hit(from, stop)
				k = r.x
				at = r.y
			elif not men:
				var rad: float = Sim.hit_rad[i]
				var c: Vector3 = Geometry3D.get_closest_point_to_segment(
					n.global_position, from, stop)
				if c.distance_to(n.global_position) < rad:
					k = 1.0
					at = from.distance_to(c) / maxf(from.distance_to(stop), 0.001)
			# a helicopter's rotors reach well past the ball round its
			# middle, and a blade is not armour: asked of on their own
			if n is Helicopter and not harmless:
				var rc: Vector2 = (n as Helicopter).rotor_cross(from, stop)
				if rc.x >= 0.0 and rc.x < best_t and (k <= 0.0 or rc.x < at):
					best = n
					best_t = rc.x
					best_k = 1.0
					best_rotor = int(rc.y)
					continue
			if k > 0.0 and at < best_t:
				best = n
				best_t = at
				best_k = k
				best_rotor = -1
			elif k <= 0.0 and n.has_method("suppress") and not _scared.has(n):
				# past his chest, or into the wall he is behind
				var chest: Vector3 = n.global_position + Vector3(0, 0.9, 0)
				var miss: float = Geometry3D.get_closest_point_to_segment(
					chest, from, stop).distance_to(chest)
				if miss < NEAR_MISS:
					_scared.append(n)
					n.suppress(clampf(dmg / 110.0, 0.10, 0.6)
						* (1.0 - 0.6 * miss / NEAR_MISS),
						from if _born == Vector3.INF else _born)
	# The airframes with someone inside them, by their shape: into the
	# skin anywhere but through the open ramp is a hit on the aircraft --
	# from outside, or from a man in its own hold.
	var hh: Array = Effects.hull_hit(from, stop)
	if hh[1] != null and float(hh[0]) < best_t:
		best = hh[1]
		best_t = float(hh[0])
		best_k = 1.0
		best_rotor = -1
	if best != null:
		var where := from.lerp(stop, clampf(best_t, 0.0, 1.0))
		ended_at = where
		var was_alive: bool = not best.has_method("is_alive") or best.is_alive()
		# a rifle round does nothing to armour plate but mark the paint
		var plate: bool = best is Tank or best is Ship
		if best is Aircraft:
			# A rifle round into an aeroplane is a hole, not a kill. It took
			# the full damage it does to a man, and an airframe has the
			# health of one: three rounds brought a jet down, and the bigger
			# hits blew parts off it as a rocket does. A helicopter, low and
			# slow and full of things that matter, takes more of it; half an
			# inch of steel core three times as much again.
			#
			# Still too much: a magazine took two fifths of a fighter and
			# three brought it down; a helicopter went in one. Fractions of
			# a point a round now -- a man with a rifle marks the paint.
			var frac: float = 0.012 if best is Helicopter else 0.006
			if heavy:
				frac *= 1.5
			# a blade is not armour: through the disc it is the rotor hit
			if best_rotor >= 0 and best is Helicopter:
				(best as Helicopter).rotor_damage(best_rotor, dmg * (1.5 if heavy else 1.0))
			else:
				best.take_hit(dmg * best_k * frac, shooter if is_instance_valid(shooter) else null)
		elif best.has_method("take_hit") and not plate:
			best.take_hit(dmg * best_k, shooter if is_instance_valid(shooter) else null)
		elif heavy and best is Tank:
			# half an inch of steel core does not stop on a scout car
			best.take_hit(dmg * 0.3, shooter if is_instance_valid(shooter) else null)
		# a range board is paper on a post, not a man
		var flesh: bool = best.has_method("bullet_hit") and not best.is_in_group("range_target")
		if flesh:
			Effects.blood(world, where)
		else:
			# paper on a board takes a round with a thwack, not a ricochet
			Effects.bullet_impact(world, where, not best.is_in_group("range_target"))
		if is_instance_valid(shooter) and shooter.has_method("hit_confirm"):
			var dead_now: bool = was_alive and best.has_method("is_alive") \
				and not best.is_alive()
			shooter.hit_confirm(best_k > 1.5, dead_now)
		# through him and on, if it has it left to give
		if flesh and pen >= MAN_COST:
			pen -= MAN_COST
			dmg *= 0.7
			_struck.append(best)
			_resume = where
			return 2
		queue_free()
		return 1
	if cut < 1.0:
		var dir: Vector3 = vel.normalized()
		Effects.bullet_impact(world, stop - dir * 0.05, wall <= dirt)
		if wall <= dirt and pen > 0.0:
			var span: float = from.distance_to(to_in)
			var thick: float = (wall_exit - wall) * span * (0.3 if wall_soft else 1.0)
			if is_finite(thick) and thick <= pen:
				pen -= thick
				dmg *= 0.8
				vel *= 0.92
				var out: Vector3 = from.lerp(to_in, wall_exit) + dir * 0.03
				Effects.bullet_impact(world, out, true)
				if wall_exit >= 1.0:
					# it comes out past where this tick would have left it
					global_position = out
					return 3
				_resume = out
				return 2
		ended_at = stop
		queue_free()
		return 1
	if not _whizzed:
		var eye := get_viewport().get_camera_3d()
		# His own rounds never crack past him. Asked of the camera alone,
		# the bullet camera -- which is nobody's -- had every follow-up
		# round snap past the lens, and it was shooting from nowhere.
		if eye != null and is_instance_valid(shooter) and not (shooter is Walker) \
				and not shooter.is_ancestor_of(eye):
			var c2: Vector3 = Geometry3D.get_closest_point_to_segment(
				eye.global_position, from, stop)
			var miss: float = c2.distance_to(eye.global_position)
			if miss < 3.2 and from.distance_to(eye.global_position) > 4.0:
				_whizzed = true
				Sfx.play_at(world, "whiz" if miss > 1.2 else "snap", c2,
					-3.0, randf_range(0.85, 1.3), 40.0)
	return 0

## An explosive round's burst: the real thing, or only the look of it.
func _he(at: Vector3, size: float, d: float) -> void:
	var was: bool = Effects.mute_blast
	if harmless:
		Effects.mute_blast = true
	Effects.he_impact(get_tree().current_scene, at, size, 0.0 if harmless else d,
		shooter, team)
	Effects.mute_blast = was
