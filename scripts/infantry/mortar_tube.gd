class_name MortarTube
extends Node3D
## A light mortar set up on the ground: baseplate down, bipod out, laid on a
## fire mission plotted on the map. It was carried like a rocket launcher --
## crosshair on a street, pull the trigger -- which is not how a mortar is
## worked: it goes down, it is laid on a grid, and it fires from where it
## stands. Walk away from it and it is packed up again.
##
## Owned by the `Walker` carrying it; see `Walker._work_mortar`.

## Seconds to bring it into action, and how close the man has to stay.
const SETUP := 2.6
const STAY := 2.4
## What it can be laid on, across the ground.
const MIN_RANGE := 80.0
const MAX_RANGE := 820.0

var spec: Dictionary = {}
## 0 to 1 while it is being set up; 1 is ready to fire.
var setup := 0.0
## Where the fire mission is laid, or INF for none yet.
var mission := Vector3.INF
var _gun: Node3D = null
var _yaw := 0.0
var _elev := deg_to_rad(60.0)

func _init() -> void:
	top_level = true

func _ready() -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.46, 0.05, 0.46), Vector3(0, 0.025, 0))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.22, 0.24, 0.20), 0.8, 0.3)), "Plate"))
	# the tube as it is carried, stood on the plate and pointed up
	_gun = Firearm.build(spec, false)
	add_child(_gun)
	_lay()

func ready_to_fire() -> bool:
	return setup >= 1.0

## Bring it into action a little more; true on the tick it is ready.
func work(delta: float) -> bool:
	if setup >= 1.0:
		return false
	setup = minf(setup + delta / SETUP, 1.0)
	_lay()
	return setup >= 1.0

## Can it be laid on `at`? An empty string if so, otherwise why not.
func cannot_reach(at: Vector3) -> String:
	var flat: float = Vector2(at.x - global_position.x, at.z - global_position.z).length()
	if flat < MIN_RANGE:
		return "too close — %d m at least" % int(MIN_RANGE)
	if flat > MAX_RANGE:
		return "out of range — %d m at most, that is %d m" % [int(MAX_RANGE), int(flat)]
	return ""

func lay_on(at: Vector3) -> void:
	mission = at
	_lay()

## How long a round is in the air to the mission: a high-angle shot, about as
## long as the range wants.
func flight() -> float:
	var flat: float = Vector2(mission.x - global_position.x, mission.z - global_position.z).length()
	return clampf(5.0 + flat / 70.0, 6.0, 16.0)

## One round down the tube onto the mission, spread as a real tube's are.
func fire(shooter: Node3D, arena: Node) -> MortarRound:
	var flat: float = Vector2(mission.x - global_position.x, mission.z - global_position.z).length()
	var spread: float = 2.0 + flat * 0.012
	var a: float = randf() * TAU
	var r: float = spread * sqrt(randf())
	var mr := MortarRound.new()
	mr.arena = arena as CqbMatch if is_instance_valid(arena) and arena is CqbMatch else null
	mr.shooter = shooter
	mr.from = muzzle()
	mr.to = MortarRound.lands_at(mission.x + cos(a) * r, mission.z + sin(a) * r)
	mr.flight = flight()
	mr.delay = 0.0
	return mr

func muzzle() -> Vector3:
	if is_instance_valid(_gun) and _gun.has_node("Muzzle"):
		return (_gun.get_node("Muzzle") as Node3D).global_position
	return global_position + Vector3(0, 1.0, 0)

## Turn and raise the tube: toward the mission once there is one, and up
## from flat on the ground as it is set up.
func _lay() -> void:
	if mission != Vector3.INF:
		var d := Vector3(mission.x - global_position.x, 0.0, mission.z - global_position.z)
		if d.length() > 1.0:
			_yaw = atan2(-d.x, -d.z)
		# the further out, the flatter the tube: 85 degrees close in, 45 at full range
		var k: float = clampf((d.length() - MIN_RANGE) / (MAX_RANGE - MIN_RANGE), 0.0, 1.0)
		_elev = deg_to_rad(lerpf(85.0, 45.0, k))
	if not is_instance_valid(_gun):
		return
	var up: float = lerpf(0.1, _elev, clampf(setup * 1.4, 0.0, 1.0))
	# the breech on the plate (the carried model's breech is a third of a
	# metre behind its origin) and the muzzle up and out along the bearing
	var bs := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, up)
	_gun.transform = Transform3D(bs, Vector3(0, 0.07, 0) - bs * Vector3(0, 0, 0.34))
