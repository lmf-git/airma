class_name SentryTurret
extends Node3D
## The SENTRY TURRET streak: a machine gun on a tripod that watches a street
## for its side and shoots whatever of the other side walks into its arc,
## until it is knocked out or has fired its belt.
##
## It sees as the men do (`Firearm.can_see`, so smoke blinds it too), shoots
## as they do (`Firearm.fire`), and is shot at as they are: the other side's
## riflemen find it in `CqbMatch.targets_of` and it takes hits like a man.

var team := 0
## Who put it down, for the kill feed.
var owner_node: Node = null
var arena: Node = null

## Where it is set to look, and how far either side of that it will turn.
var facing := 0.0
const ARC := deg_to_rad(75.0)
const RANGE := 70.0
const TURN := 2.6                     # radians a second
const BELT := 300
const CYCLE := 0.085                  # seconds a round
const SPREAD := 0.012
const BURST := 8
const PAUSE := 0.45
const HEALTH := 180.0
const GUN := "lmg"

var health := HEALTH
var alive := true
var rounds := BELT
var _yaw := 0.0
var _pitch := 0.0
var _target: Node3D = null
var _scan := 0.0
var _cd := 0.0
var _burst := 0
var _head: Node3D = null
var _gun: Node3D = null
var _muzzle: Node3D = null
var _dead_t := 0.0

func _ready() -> void:
	add_to_group("sentries")
	_yaw = facing
	var dark := MeshKit.mat(Color(0.18, 0.19, 0.17), 0.7, 0.3)
	var olive := MeshKit.mat(Color(0.29, 0.31, 0.22), 0.8, 0.1)
	# tripod: three legs out to the feet
	var legs := MeshKit.begin()
	for k in 3:
		var a: float = TAU * float(k) / 3.0
		var foot := Vector3(sin(a) * 0.42, 0.0, cos(a) * 0.42)
		MeshKit.box(legs, Vector3(0.05, 0.80, 0.05), foot * 0.75 + Vector3(0, 0.40, 0))
		MeshKit.box(legs, Vector3(0.09, 0.04, 0.09), foot)
	add_child(MeshKit.mi(MeshKit.finish(legs, dark), "Tripod"))
	# the head that turns, with the box of ammunition and the gun on it
	_head = Node3D.new()
	_head.position = Vector3(0, 0.78, 0)
	add_child(_head)
	var body := MeshKit.begin()
	MeshKit.box(body, Vector3(0.34, 0.26, 0.42), Vector3(0, 0.12, 0.05))
	MeshKit.box(body, Vector3(0.24, 0.20, 0.22), Vector3(0.24, 0.08, 0.10))
	_head.add_child(MeshKit.mi(MeshKit.finish(body, olive), "Body"))
	_gun = Node3D.new()
	_gun.position = Vector3(0, 0.22, 0)
	_head.add_child(_gun)
	var barrel := MeshKit.begin()
	MeshKit.box(barrel, Vector3(0.12, 0.12, 0.55), Vector3(0, 0, -0.10))
	MeshKit.box(barrel, Vector3(0.05, 0.05, 0.70), Vector3(0, 0.01, -0.70))
	MeshKit.box(barrel, Vector3(0.20, 0.03, 0.12), Vector3(0, 0.08, -0.05))  # sight
	_gun.add_child(MeshKit.mi(MeshKit.finish(barrel, dark), "Gun"))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.01, -1.07)
	_gun.add_child(_muzzle)
	_apply()

## As a man is, for anyone who asks.
func is_alive() -> bool:
	return alive

func hit_radius() -> float:
	return 0.7

func take_hit(amount: float, from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		_destroyed(from)

func _destroyed(_by: Node) -> void:
	alive = false
	_target = null
	var world := get_tree().current_scene
	Effects.explosion(world, global_position + Vector3(0, 0.8, 0), 3.0, true)
	Sim.report("%s sentry knocked out" % ("your" if team == 0 else "their"),
		Sim.Ev.BAD if team == 0 else Sim.Ev.GOOD)
	# it slumps on its tripod, and is gone a little after
	if is_instance_valid(_head):
		_head.rotation = Vector3(-0.6, _head.rotation.y, 0.4)

func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		if _dead_t > 12.0:
			queue_free()
		return
	_cd = maxf(_cd - delta, 0.0)
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.25
		_target = _pick()
	var want_yaw := facing
	var want_pitch := 0.0
	var aim_at := Vector3.INF
	if is_instance_valid(_target):
		aim_at = _chest(_target)
		var to: Vector3 = aim_at - _muzzle_root()
		want_yaw = atan2(-to.x, -to.z)
		want_pitch = atan2(to.y, Vector2(to.x, to.z).length())
	else:
		# sweeping its arc while there is nothing to shoot
		want_yaw = facing + sin(Time.get_ticks_msec() * 0.0006) * ARC * 0.8
	var dy: float = clampf(wrapf(want_yaw - _yaw, -PI, PI), -TURN * delta, TURN * delta)
	_yaw = _clamp_arc(_yaw + dy)
	_pitch = move_toward(_pitch, clampf(want_pitch, -0.5, 0.6), TURN * delta)
	_apply()
	if aim_at == Vector3.INF or rounds <= 0:
		return
	var dir: Vector3 = -_gun.global_transform.basis.z
	var off: float = dir.angle_to(aim_at - _muzzle.global_position)
	if off > 0.06 or _cd > 0.0:
		return
	var world := get_tree().current_scene
	Firearm.fire(world, owner_node if is_instance_valid(owner_node) else self, team,
		Firearm.spec(GUN), _muzzle.global_position, dir, SPREAD)
	rounds -= 1
	_burst += 1
	_cd = CYCLE
	if _burst >= BURST:
		_burst = 0
		_cd = PAUSE
	if rounds <= 0:
		Sim.report("%s sentry is out of ammunition" % ("your" if team == 0 else "their"),
			Sim.Ev.INFO)
		alive = false

func _apply() -> void:
	if is_instance_valid(_head):
		_head.global_rotation = Vector3(0.0, _yaw, 0.0)
	if is_instance_valid(_gun):
		_gun.rotation = Vector3(_pitch, 0.0, 0.0)

func _muzzle_root() -> Vector3:
	return global_position + Vector3(0, 1.0, 0)

func _clamp_arc(y: float) -> float:
	var off: float = wrapf(y - facing, -PI, PI)
	return facing + clampf(off, -ARC, ARC)

func _chest(n: Node3D) -> Vector3:
	return Soldier.chest_of(n)

## The nearest of the other side in its arc and in sight.
func _pick() -> Node3D:
	if arena == null or not is_instance_valid(arena):
		return null
	var from: Vector3 = _muzzle_root()
	var best: Node3D = null
	var best_d := RANGE
	for n in arena.enemies_of(team):
		if not is_instance_valid(n) or not n.is_alive():
			continue
		var at: Vector3 = _chest(n)
		var d: float = from.distance_to(at)
		if d > best_d:
			continue
		var to: Vector3 = at - from
		var y: float = atan2(-to.x, -to.z)
		if absf(wrapf(y - facing, -PI, PI)) > ARC:
			continue
		if not Firearm.can_see(from, at):
			continue
		best = n
		best_d = d
	return best
