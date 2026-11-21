class_name Switchblade
extends Node3D
## One of the SWITCHBLADE SWARM: a small loitering munition. It climbs out
## over the man who launched it, circles while it looks for someone of the
## other side it can see from up there -- in the open, not under a roof or
## behind a wall -- and dives on him. The swarm spreads itself: two of them do
## not go for the same man while there is another to go for.

var team := 0
## Only the look of it: see `CqbMatch.call_picture`.
var picture := false
var arena: Node = null
var owner_node: Node = null
## Where it circles while it looks: over the man who launched it.
var centre := Vector3.ZERO
## Its place in the swarm, which staggers the orbits.
var slot := 0

const CLIMB := 70.0
const ORBIT_R := 60.0
const CRUISE := 32.0
const DIVE := 55.0
const LOOK := 160.0
const LIFE := 50.0
const FUSE := 3.0          # metres from the man it goes off
const BLAST := 0.55        # the arena's bomb, scaled

var vel := Vector3.ZERO
var health := 30.0
var _life := LIFE
var _target: Node3D = null
var _angle := 0.0
var _look_t := 0.0
var _gone := false

## Who each drone of the swarm has, so two do not take the same man.
static var claimed: Dictionary = {}

func _ready() -> void:
	add_to_group("drones")
	add_to_group("hittable")
	_angle = TAU * float(slot) / 4.0
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.14, 0.14, 0.75), Vector3.ZERO)
	MeshKit.box(st, Vector3(1.1, 0.02, 0.12), Vector3(0, 0.04, -0.12))
	MeshKit.box(st, Vector3(0.7, 0.02, 0.10), Vector3(0, 0.04, 0.28))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.33, 0.35, 0.30), 0.7, 0.2)), "Body"))
	vel = Vector3(0, 18.0, 0)

func is_alive() -> bool:
	return not _gone

func hit_radius() -> float:
	return 0.6

func take_hit(amount: float, _from: Node = null) -> void:
	if _gone:
		return
	health -= amount
	if health <= 0.0:
		_gone = true
		Effects.explosion(get_tree().current_scene, global_position, 1.2, true)
		_release()
		queue_free()

func _release() -> void:
	if is_instance_valid(_target):
		claimed.erase(_target.get_instance_id())

func _physics_process(delta: float) -> void:
	if _gone:
		return
	_life -= delta
	if _life <= 0.0:
		# out of battery: it comes down where it is, and goes off
		_detonate()
		return
	var pos: Vector3 = global_position
	var want: Vector3
	if is_instance_valid(_target) and _target.is_alive():
		var aim: Vector3 = Soldier.chest_of(_target)
		var to: Vector3 = aim - pos
		if to.length() < FUSE:
			_detonate()
			return
		want = to.normalized() * DIVE
	else:
		if is_instance_valid(_target):
			_release()
		_target = null
		# circle at height over the launch point, looking
		_angle += delta * CRUISE / ORBIT_R
		var orbit: Vector3 = centre + Vector3(cos(_angle) * ORBIT_R,
			CLIMB + float(slot) * 6.0, sin(_angle) * ORBIT_R)
		want = (orbit - pos).normalized() * CRUISE
		_look_t -= delta
		if _look_t <= 0.0 and pos.y > centre.y + CLIMB * 0.6:
			_look_t = 0.5
			_target = _pick(pos)
			if _target != null:
				claimed[_target.get_instance_id()] = true
	vel = vel.lerp(want, clampf(delta * 2.5, 0.0, 1.0))
	var nxt: Vector3 = pos + vel * delta
	# into the ground or a wall on the way: that is where it goes off
	if nxt.y < Sim.height_at(nxt.x, nxt.z) + 0.3 or Obstacles.segment(pos, nxt) < 1.0:
		_detonate()
		return
	global_position = nxt
	if vel.length() > 0.5:
		look_at(nxt + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)

## The nearest of theirs it can see from up here, and that no other drone of
## the swarm already has.
func _pick(from: Vector3) -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var best: Node3D = null
	var best_d := LOOK
	var spare: Node3D = null
	for n in arena.enemies_of(team):
		if not is_instance_valid(n) or not n.is_alive():
			continue
		var at: Vector3 = Soldier.chest_of(n)
		var d: float = from.distance_to(at)
		if d > LOOK:
			continue
		if not Firearm.can_see(from, at):
			continue
		if claimed.has(n.get_instance_id()):
			spare = n
			continue
		if d < best_d:
			best = n
			best_d = d
	return best if best != null else spare

func _detonate() -> void:
	if _gone:
		return
	_gone = true
	_release()
	if arena != null and is_instance_valid(arena) and arena.has_method("_bomb"):
		arena._bomb(global_position, BLAST, false, "switchblade", picture)
	else:
		Effects.explosion(get_tree().current_scene, global_position, 3.0, true)
	queue_free()
