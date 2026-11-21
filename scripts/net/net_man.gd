class_name NetMan
extends Node3D
## A player on foot on another machine, as something on this one can shoot.
##
## A remote man used to be a picture: a `Pilot` posed where his packets said he
## was, and in no group anything looks in. The AI in a street fight could not
## see him, so in a session it only ever fought the host; and nobody's rounds or
## grenades could touch him. This rides on that picture (it is a child of the
## ghost, so it goes where he goes, into holds included) and answers to the same
## calls a `Soldier` does -- `is_alive`, `bullet_hit`, `take_hit`, `eye` -- so
## every round, blast and AI rifleman treats him as a man. What lands on him is
## not decided here: it is sent to the machine he is playing on, which owns his
## health, and his death comes back in his own packets.

var peer := 0
var team := 0
var crouching := false
var dead := false
var yaw := 0.0
var callsign := ""
var _last_head := false

func _ready() -> void:
	add_to_group("infantry")
	add_to_group("net_men")

func is_alive() -> bool:
	return not dead and is_inside_tree()

func hit_radius() -> float:
	return 0.9

func bullet_hit(from: Vector3, to: Vector3) -> Vector2:
	if dead:
		return Vector2.ZERO
	var r: Vector2 = Firearm.body_hit(global_position, crouching, from, to)
	if r.x > 0.0:
		_last_head = r.x > 1.5
	return r

func eye() -> Vector3:
	return global_position + Vector3(0.0, 1.15 if crouching else 1.68, 0.0)

func take_hit(amount: float, from: Node = null) -> void:
	if dead or amount <= 0.0 or Sim.net == null or not Sim.net.active:
		return
	Sim.net.report_man_hit(peer, amount, KillFeed.weapon_of(from), _last_head,
		from)
	_last_head = false

func display_name() -> String:
	return callsign if callsign != "" else "P%d" % peer
