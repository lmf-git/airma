class_name AirframeDebris
extends Node3D
## A piece of airframe on its way to the ground.
## Moved out of `aircraft.gd` (`Aircraft.Debris`).

var _has_smoke := false

func _exit_tree() -> void:
	if _has_smoke:
		Effects.release_smoke_slot()
		_has_smoke = false
var visual: Node3D
var vel := Vector3.ZERO
var spin := Vector3.ZERO
var smoking := false
var life := 18.0

func _ready() -> void:
	top_level = true
	if visual:
		add_child(visual)
		visual.transform = Transform3D.IDENTITY
	# only if the world can afford another plume
	if smoking and Effects.smoke_slot():
		_has_smoke = true
		var t := Effects.trail_particles(Color(0.32, 0.31, 0.30), 2.4, 24)
		t.lifetime = 2.4
		t.emitting = true
		add_child(t)
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	life -= delta
	vel += Vector3.DOWN * 9.81 * delta
	vel -= vel * vel.length() * 0.0016 * delta
	global_position += vel * delta
	rotation += spin * delta
	spin = spin.lerp(Vector3.ZERO, delta * 0.12)
	var g := Sim.height_at(global_position.x, global_position.z)
	if global_position.y <= g + 0.3:
		Effects.dust(get_tree().current_scene, Vector3(global_position.x, g, global_position.z), 2.6)
		queue_free()
	elif life <= 0.0:
		queue_free()
