class_name UavDrone
extends Node3D
## The drone a UAV streak puts up. It is there: it circles the town where it
## can be seen, it is a contact like any other aircraft, and anything that can
## reach it -- a man with a missile, a gun, another aeroplane -- can bring it
## down, which takes the picture off the map with it.

const HEIGHT := 650.0
const RADIUS := 520.0
const SPEED := 58.0
var arena: CqbMatch = null
var team := 0
var health := 30.0
var alive := true
var linear_velocity := Vector3.ZERO
var _mid := Vector3.ZERO
var _a := 0.0

func _init() -> void:
	top_level = true

func _ready() -> void:
	add_to_group("hittable")
	add_to_group("drones")
	var m: Dictionary = JetFactory.build(JetSpec.get_spec("mq9"))
	for g in m["gear"]:
		(g as Node3D).visible = false
	add_child(m["root"])

func station(over: Vector3) -> void:
	_mid = over
	_a = randf() * TAU
	_fly(0.0)
	reset_physics_interpolation()

func display_name() -> String:
	return "UAV"

func is_alive() -> bool:
	return alive

func hit_radius() -> float:
	return 6.0

func get_velocity() -> Vector3:
	return linear_velocity

func _fly(delta: float) -> void:
	_a += SPEED / RADIUS * delta
	var at := _mid + Vector3(cos(_a) * RADIUS, HEIGHT, sin(_a) * RADIUS)
	linear_velocity = Vector3(-sin(_a), 0.0, cos(_a)) * SPEED
	global_position = at
	look_at(at + linear_velocity, Vector3.UP)
	# banked into its circle
	rotate_object_local(Vector3.FORWARD, -atan(SPEED * SPEED / (9.81 * RADIUS)))

func _physics_process(delta: float) -> void:
	if alive:
		_fly(delta)

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	if health > 0.0:
		return
	alive = false
	remove_from_group("hittable")
	Effects.explosion(get_tree().current_scene, global_position, 9.0)
	if is_instance_valid(arena):
		arena.streaks.uav_lost()
	queue_free()
