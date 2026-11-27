class_name Decoys
extends RefCounted
## What an aircraft throws out to spoil a seeker: flares for the heat seekers,
## chaff for the radar ones. Moved out of `aircraft.gd`.

## A bundle of dipoles that blooms into a cloud. It is not bright — the whole
## point is that it is invisible and enormous on a radar scope — so it is drawn
## as a dull expanding puff rather than the firework a flare is.
class Chaff extends Node3D:
	var vel := Vector3.ZERO
	var life := 7.0
	var _age := 0.0
	var _puff: GPUParticles3D

	func _ready() -> void:
		top_level = true
		add_to_group("chaff")
		_puff = Effects.trail_particles(Color(0.72, 0.74, 0.78), 2.2, 26)
		_puff.lifetime = 3.0
		_puff.emitting = true
		add_child(_puff)
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		_age += delta
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		# it sheds its launch speed almost immediately and then just hangs
		vel = vel.lerp(Vector3.DOWN * 3.0, clampf(delta * 2.2, 0.0, 1.0))
		global_position += vel * delta
		if _age > 3.4 and is_instance_valid(_puff):
			_puff.emitting = false

## Decoy flare: a hot billboard that flickers and tumbles away trailing embers
## and smoke, rather than the plain white ball it used to be.
class Flare extends Node3D:
	var vel := Vector3.ZERO
	var life := 5.0
	var _burn := 0.0
	var _core: MeshInstance3D
	var _mat: StandardMaterial3D
	var _spin := Vector3.ZERO

	func _ready() -> void:
		top_level = true
		_core = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.5, 1.5)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_mat.albedo_texture = Effects.glow_texture()
		_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.95)
		_mat.render_priority = 6
		qm.material = _mat
		_core.mesh = qm
		_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_core)
		var embers := Effects.ember_particles(Color(1.0, 0.7, 0.25), 0.55, 20)
		embers.emitting = true
		add_child(embers)
		var smoke := Effects.trail_particles(Color(0.9, 0.9, 0.92), 1.1, 22)
		smoke.lifetime = 1.8
		smoke.emitting = true
		add_child(smoke)
		_spin = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		life -= delta
		_burn += delta
		vel = vel.lerp(Vector3(0, -16.0, 0), delta * 0.55)
		global_position += vel * delta
		rotation += _spin * delta
		var fade: float = clampf(life / 2.2, 0.0, 1.0)
		var flick := 0.72 + 0.28 * sin(_burn * 47.0) * randf_range(0.6, 1.0)
		_core.scale = Vector3.ONE * (0.7 + 0.7 * fade) * flick
		_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.95 * fade)
		if life <= 0.0:
			queue_free()
