class_name DesignatedSpot
extends Node3D
## A laser spot standing in for a target the seeker can hold. It is not a thing
## that can be shot, it is a place on the ground.
## Moved out of `aircraft.gd` (`Aircraft.DesignatedSpot`).

var team := -1
func _ready() -> void:
	# in "hittable" so the fuse sweep finds it: a bomb that flies through
	# its own designation and carries on is no use to anybody
	add_to_group("hittable")
	# ...but it is a place, not a contact. Without this the radar cycled
	# onto the player's own laser spot.
	add_to_group("no_lock")
var _life := 140.0
func is_alive() -> bool:
	return true
func hit_radius() -> float:
	return 2.0
func take_hit(_a: float, _f: Node = null) -> void:
	pass
func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
