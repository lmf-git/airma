class_name AttackDog
extends Node3D
## The ATTACK DOGS streak: military working dogs let loose on the other side.
## Fast, low and hard to hit, they run the same routes the riflemen plan on --
## along the streets and in through the doors of the buildings that have them
## -- to the nearest man of the other side, and bring him down. Which is how
## you get somebody out of a room the aircraft cannot see into.

var team := 0
var arena: Node = null
var owner_node: Node = null
## Which of the pack this is: they spread over different men.
var slot := 0

const RUN := 9.0
const BITE_REACH := 1.4
const BITE := 45.0
const BITE_CD := 0.8
const SEEK := 140.0
const LIFE := 60.0
const HEALTH := 60.0

var health := HEALTH
var alive := true
var _life := LIFE
var _target: Node3D = null
var _path := PackedVector2Array()
var _path_i := 0
var _repath := 0.0
var _bite_cd := 0.0
var _gait := 0.0
var _legs: Array = []
var _yaw := 0.0

## Which man each dog has, so the pack does not all go for one.
static var claimed: Dictionary = {}

func _ready() -> void:
	add_to_group("sentries")       # fights for its side: see `CqbMatch.targets_of`
	var fur := MeshKit.mat(Color(0.30, 0.24, 0.17), 0.95, 0.0)
	var dark := MeshKit.mat(Color(0.12, 0.10, 0.08), 0.95, 0.0)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.30, 0.30, 0.85), Vector3(0, 0.55, 0))
	MeshKit.box(st, Vector3(0.22, 0.24, 0.30), Vector3(0, 0.78, -0.50))
	MeshKit.box(st, Vector3(0.12, 0.12, 0.18), Vector3(0, 0.72, -0.70))
	add_child(MeshKit.mi(MeshKit.finish(st, fur), "Body"))
	var vest := MeshKit.begin()
	MeshKit.box(vest, Vector3(0.33, 0.20, 0.45), Vector3(0, 0.62, -0.05))
	add_child(MeshKit.mi(MeshKit.finish(vest, dark), "Vest"))
	for i in 4:
		var leg := Node3D.new()
		leg.position = Vector3(0.11 if i % 2 == 0 else -0.11, 0.42, -0.30 if i < 2 else 0.30)
		var lm := MeshKit.begin()
		MeshKit.box(lm, Vector3(0.07, 0.42, 0.07), Vector3(0, -0.21, 0))
		leg.add_child(MeshKit.mi(MeshKit.finish(lm, fur), "Leg"))
		add_child(leg)
		_legs.append(leg)

func is_alive() -> bool:
	return alive

func hit_radius() -> float:
	return 0.5

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		alive = false
		_let_go()
		Effects.blood(get_tree().current_scene, global_position + Vector3(0, 0.5, 0))
		rotation.z = PI * 0.5
		get_tree().create_timer(8.0).timeout.connect(queue_free)

func _let_go() -> void:
	if is_instance_valid(_target):
		claimed.erase(_target.get_instance_id())

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_life -= delta
	if _life <= 0.0:
		_let_go()
		queue_free()
		return
	_bite_cd = maxf(_bite_cd - delta, 0.0)
	_repath -= delta
	if not is_instance_valid(_target) or not _target.is_alive():
		_let_go()
		_target = _pick()
		_repath = 0.0
		if _target != null:
			claimed[_target.get_instance_id()] = true
	var here: Vector3 = global_position
	var goal: Vector3 = here
	if is_instance_valid(_target):
		var at: Vector3 = _target.global_position
		if here.distance_to(at) < BITE_REACH:
			if _bite_cd <= 0.0:
				_bite_cd = BITE_CD
				_target.take_hit(BITE, owner_node if is_instance_valid(owner_node) else self)
				if _target.has_method("suppress"):
					_target.suppress(0.8, here)
				Sfx.play_at(get_tree().current_scene, "hit_body", here, -6.0, 1.4, 60.0)
			_face(at)
			_animate(delta, 0.0)
			return
		if _repath <= 0.0 and arena != null and is_instance_valid(arena):
			_repath = 1.0
			_path = arena.path(here, at)
			_path_i = 0
		# along the route, or straight in over the last few metres
		goal = at
		while _path_i < _path.size():
			var p: Vector2 = _path[_path_i]
			if Vector2(here.x, here.z).distance_to(p) < 1.2:
				_path_i += 1
				continue
			if here.distance_to(at) > 6.0:
				goal = Vector3(p.x, here.y, p.y)
			break
	var flat := Vector3(goal.x - here.x, 0.0, goal.z - here.z)
	var speed := 0.0
	if flat.length() > 0.2:
		var step: Vector3 = flat.normalized() * minf(RUN * delta, flat.length())
		var nxt: Vector3 = here + step
		# round what it would run into, the way a man slides along a wall
		if Obstacles.blocks(nxt + Vector3(0, 0.3, 0), 0.25) >= 0:
			var try_x := Vector3(nxt.x, here.y, here.z)
			var try_z := Vector3(here.x, here.y, nxt.z)
			if Obstacles.blocks(try_x + Vector3(0, 0.3, 0), 0.25) < 0:
				nxt = try_x
			elif Obstacles.blocks(try_z + Vector3(0, 0.3, 0), 0.25) < 0:
				nxt = try_z
			else:
				nxt = here
		nxt.y = Sim.height_at(nxt.x, nxt.z)
		speed = here.distance_to(nxt) / maxf(delta, 0.0001)
		global_position = nxt
		_face(here + flat)
	_animate(delta, speed)

func _face(at: Vector3) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), 0.3)
		rotation.y = _yaw

func _animate(delta: float, speed: float) -> void:
	_gait += delta * (2.0 + speed * 1.6)
	for i in _legs.size():
		var ph: float = _gait + (PI if i == 1 or i == 2 else 0.0)
		(_legs[i] as Node3D).rotation.x = sin(ph) * clampf(speed / RUN, 0.0, 1.0) * 0.9

## The nearest of theirs within reach that no other dog has.
func _pick() -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var best: Node3D = null
	var best_d := SEEK
	var spare: Node3D = null
	for n in arena.enemies_of(team):
		if not is_instance_valid(n) or not n.is_alive():
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d > SEEK:
			continue
		if claimed.has(n.get_instance_id()):
			if spare == null:
				spare = n
			continue
		if d < best_d:
			best_d = d
			best = n
	return best if best != null else spare
