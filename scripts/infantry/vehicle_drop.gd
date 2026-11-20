class_name VehicleDrop
extends Node3D
## The ARMOUR DROP streak: a tank, or for the lighter call an infantry fighting
## vehicle, comes down under a cluster of canopies on a spot picked on the map
## and is his to board (U) once it is on the ground.

## The vehicle being lowered. Made by the world's own spawner, stood where
## there is room for it, then lifted to the drop height and let down.
var vehicle: Tank = null
const FROM := 160.0
const SINK := 9.0

var _ground := 0.0
var _canopies: Node3D = null
var _down := false

func _ready() -> void:
	if not is_instance_valid(vehicle):
		queue_free()
		return
	_ground = vehicle.global_position.y
	vehicle.freeze = true
	vehicle.global_position += Vector3(0, FROM, 0)
	# three canopies over it on risers
	_canopies = Node3D.new()
	add_child(_canopies)
	var cloth := MeshKit.mat(Color(0.72, 0.70, 0.60), 0.9, 0.0)
	for k in 3:
		var a: float = TAU * float(k) / 3.0
		var st := MeshKit.begin()
		MeshKit.cone(st, 5.5, 0.6, 0.0, 2.6, Vector3.ZERO, 12)
		var mi := MeshKit.mi(MeshKit.finish(st, cloth), "Canopy")
		mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		mi.position = Vector3(sin(a) * 5.0, 22.0, cos(a) * 5.0)
		_canopies.add_child(mi)
	Sfx.play_at(get_tree().current_scene, "shot_far", vehicle.global_position, 4.0, 0.3, 5000.0)

func _physics_process(delta: float) -> void:
	if _down or not is_instance_valid(vehicle):
		if not _down:
			queue_free()
		return
	var p: Vector3 = vehicle.global_position
	p.y -= SINK * delta
	if p.y <= _ground:
		p.y = _ground
		_land()
	vehicle.global_position = p
	vehicle.linear_velocity = Vector3.ZERO
	if is_instance_valid(_canopies):
		_canopies.global_position = p

func _land() -> void:
	_down = true
	vehicle.freeze = false
	Effects.dust(get_tree().current_scene, vehicle.global_position + Vector3(0, 0.5, 0), 6.0)
	Sfx.play_at(get_tree().current_scene, "thump", vehicle.global_position, -2.0, 0.6, 400.0)
	Sim.report("%s is down — walk up to it and press U to board" % vehicle.display_name(),
		Sim.Ev.GOOD)
	# the canopies collapse and are cut away
	if is_instance_valid(_canopies):
		var tw := _canopies.create_tween()
		tw.tween_property(_canopies, "scale", Vector3(1.4, 0.05, 1.4), 1.2)
		tw.tween_callback(queue_free)
	else:
		queue_free()
