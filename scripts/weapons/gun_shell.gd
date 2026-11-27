class_name GunShell
extends Node3D
## A gun or rocket-launcher round in flight -- the gunship's, a ship's, a
## tank's or a battery's: ballistic, explodes on impact.
## Moved out of `aircraft.gd`, where it was `Aircraft.Shell`.

var _has_smoke := false
## Only the look of it: see `Effects.Tracer.harmless`.
var harmless := false

func _exit_tree() -> void:
	if _has_smoke:
		Effects.release_smoke_slot()
		_has_smoke = false
var vel := Vector3.ZERO
var damage := 120.0
var blast := 8.0
## How far its fragments reach men in the open, where that is further than
## the fireball: nothing, unless whoever fires it says so.
var frag := 0.0
var shooter: Node = null
var team := 0
var life := 140.0          # artillery arcs can be a minute in the air
var arm_dist := 12.0       # fuse arming distance: see _physics_process
var rocket := false        # launcher round: drawn as one, and pointed
var _flown := 0.0
var _ground_in := 0.0      # seconds before the ground is worth asking about
## What the air takes off it per metre: see `Ballistics`. A shell keeps its
## speed far better than a bullet does, but over twenty kilometres of
## artillery arc even this is the difference between hitting and not.
var drag := 0.00002

func _ready() -> void:
	top_level = true
	add_to_group("shells")
	var mi := MeshInstance3D.new()
	if rocket:
		# a launcher round is a metre and a half of motor, and it is meant to
		# be watched off the rails: body, nose and a burning throat
		var body := CapsuleMesh.new()
		body.radius = 0.16
		body.height = 2.6
		body.radial_segments = 8
		body.rings = 2
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.30, 0.31, 0.33)
		bm.metallic = 0.5
		bm.roughness = 0.55
		body.material = bm
		mi.mesh = body
		mi.rotation.x = deg_to_rad(90.0)     # capsule is built along Y
		var flame := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.30
		fm.height = 1.5
		fm.radial_segments = 8
		fm.rings = 3
		var em := StandardMaterial3D.new()
		em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		em.albedo_color = Color(1.0, 0.72, 0.30)
		fm.material = em
		flame.mesh = fm
		flame.position = Vector3(0, 0, 1.5)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flame)
		if Effects.smoke_slot():
			_has_smoke = true
			var trail := Effects.trail_particles(Color(0.78, 0.78, 0.80), 1.6, 40)
			trail.lifetime = 2.6
			trail.emitting = true
			add_child(trail)
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		sm.radial_segments = 6
		sm.rings = 3
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.75, 0.35)
		sm.material = m
		mi.mesh = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# The arc it flies, drawn: grey behind a rocket, a hot thread behind a
	# shell, which until now was a dot you could not follow across the sky.
	var rb: GeometryInstance3D = Effects.ribbon(Color(0.8, 0.8, 0.82, 0.4), 0.7, 4.0, 8.0) \
		if rocket else Effects.ribbon(Color(1.0, 0.66, 0.3, 0.45), 0.3, 0.7, 6.0, true)
	if rb != null:
		add_child(rb)
		_ribbon = rb
	reset_physics_interpolation()

## The ribbon starts where the round does. Whoever makes one puts it in the
## tree first and at the muzzle second, and a strip begun in between runs
## from the middle of the world.
var _ribbon: GeometryInstance3D = null
var _ribbon_new := true

func _physics_process(delta: float) -> void:
	if _ribbon_new:
		_ribbon_new = false
		if _ribbon != null:
			_ribbon.call(&"clear")
	var _ps := Sim.prof_at()
	_fly(delta)
	Sim.prof_end(&"fx.shell", _ps)

func _fly(delta: float) -> void:
	life -= delta
	var from := global_position
	vel = Ballistics.step(from, vel, drag, delta, _flown)
	var to := from + vel * delta
	global_position = to
	if rocket and vel.length_squared() > 4.0:
		# nose follows the trajectory, so it arcs over rather than sliding
		# sideways down the sky
		var up_ref := Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD
		look_at(to + vel, up_ref)
	_flown += from.distance_to(to)
	# A fuse does not arm at the muzzle. Without this a howitzer parked in a
	# line of vehicles detonated its own round nine metres out, on the tank
	# standing beside it, every single time it fired.
	if _flown < arm_dist:
		return
	# Against the shared picture of what can be hit, and only what the step
	# could reach is asked anything: see `Sim.hit_scan`.
	Sim.hit_scan()
	var pos: PackedVector3Array = Sim.hit_pos
	var rad: PackedFloat32Array = Sim.hit_rad
	var mid: Vector3 = (from + to) * 0.5
	var fuse: float = blast * 0.4
	var span: float = from.distance_to(to) * 0.5 + fuse
	for i in pos.size():
		var reach: float = rad[i] + span
		if pos[i].distance_squared_to(mid) > reach * reach:
			continue
		var n: Variant = Sim.hit_nodes[i]
		if not is_instance_valid(n) or n == shooter:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var np: Vector3 = n.global_position
		if Geometry3D.get_closest_point_to_segment(np, from, to).distance_to(np) < rad[i] + fuse:
			_burst(to)
			return
	# The ground is not asked about while the round is nowhere near it. An
	# artillery arc spends most of a minute kilometres up, and that was two
	# crossings into the extension a tick to be told so. Clearance cannot
	# close faster than the round flies plus the ground rising under it at
	# forty-five degrees, so a round with height in hand is left alone for
	# the time that would take, less a margin.
	_ground_in -= delta
	if _ground_in > 0.0:
		if life <= 0.0:
			queue_free()
		return
	var bed := Sim.height_at(to.x, to.z)
	var sea_b: float = Sim.sea_at(to.x, to.z)
	var clear_by: float = to.y - maxf(bed, sea_b)
	if clear_by > 400.0:
		_ground_in = (clear_by - 250.0) / maxf(vel.length() * 2.0, 50.0)
	if to.y <= sea_b and bed < sea_b:
		# a shell striking the sea goes off at the surface
		Effects.splash(get_tree().current_scene,
			Vector3(to.x, sea_b, to.z), maxf(blast * 0.8, 5.0))
		_burst(Vector3(to.x, sea_b, to.z))
	elif to.y <= bed:
		_burst(Vector3(to.x, bed, to.z))
	elif life <= 0.0:
		queue_free()

func _burst(at: Vector3) -> void:
	if Sim.debug_weapons and has_meta("aim"):
		var aim: Vector3 = get_meta("aim")
		var org: Vector3 = get_meta("origin", at)
		print("[shell] impact %.0f m from aim (range %.1f km); flew %.0f m, at=%s aim=%s life=%.1f" % [
			Vector2(at.x - aim.x, at.z - aim.z).length(),
			Vector2(aim.x - org.x, aim.z - org.z).length() * 0.001,
			Vector2(at.x - org.x, at.z - org.z).length(),
			str(at.round()), str(aim.round()), 140.0 - life])
	if harmless:
		var was_m: bool = Effects.mute_blast
		Effects.mute_blast = true
		Effects.explosion(get_tree().current_scene, at, blast)
		Effects.mute_blast = was_m
		queue_free()
		return
	Effects.explosion(get_tree().current_scene, at, blast)
	# The fireball is not what a shell kills men with. A soldier is not in
	# the list below -- he is not a radar contact -- so all he ever took was
	# the explosion's own share, which reaches four fifths of the blast and
	# falls away from the middle: a 105 killed inside ten metres and a
	# forty inside four, and a gunship put round after round among men who
	# walked out of it.
	if frag > 0.0:
		Effects._blast_infantry(get_tree().current_scene, at, frag)
	for n in get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n == shooter:
			continue
		var d: float = n.global_position.distance_to(at)
		if d < blast * 2.2 and n.has_method("take_hit"):
			n.take_hit(damage * clampf(1.0 - d / (blast * 2.2), 0.15, 1.0),
				shooter if is_instance_valid(shooter) else null)
	queue_free()
