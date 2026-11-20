class_name SupplyCrate
extends Node3D
## A crate dropped under a parachute onto a spot on the map: the SUPPLY DROP
## and BALLISTIC VEST streaks.
##
## It comes down slowly enough to be seen coming, lands, and stays for a
## couple of minutes. Each man on its side gets what is in it once: the player
## by walking up to it and pressing the pickup key (it is in "pickups" with
## the dropped weapons), his own side's riflemen by passing within a few metres.

## "supply": every magazine, both grenades and his health back.
## "vest": a plate carrier's worth of armour, which takes half of every hit
## until it has taken `VEST` of them.
var kind := "supply"
## Whose it is.
var team := 0
## Where it lands.
var target := Vector3.ZERO

const FALL_FROM := 220.0
const FALL_SPEED := 9.0
const LIFE := 150.0
const SHARE := 6.0
const VEST := 100.0

var _landed := false
var _life := LIFE
var _served: Dictionary = {}
var _chute: Node3D = null

func _ready() -> void:
	var col := Color(0.30, 0.34, 0.24) if kind == "supply" else Color(0.22, 0.24, 0.30)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(1.2, 0.8, 0.8), Vector3(0.0, 0.4, 0.0))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(col, 0.85, 0.0)), "Crate"))
	# a stripe on the lid to tell the two apart at a glance
	var lid := MeshKit.begin()
	MeshKit.box(lid, Vector3(1.22, 0.05, 0.22), Vector3(0.0, 0.81, 0.0))
	var lid_col := Color(0.85, 0.75, 0.25) if kind == "supply" else Color(0.35, 0.65, 0.95)
	add_child(MeshKit.mi(MeshKit.finish(lid, MeshKit.mat(lid_col, 0.6, 0.0)), "Stripe"))
	_chute = Node3D.new()
	add_child(_chute)
	var canopy := MeshKit.begin()
	MeshKit.cone(canopy, 3.2, 0.4, 0.0, 1.6, Vector3.ZERO, 10)
	var cm := MeshKit.mi(MeshKit.finish(canopy, MeshKit.mat(Color(0.75, 0.72, 0.62), 0.9, 0.0)), "Canopy")
	# the cone is built along z; stood up, wide end down
	cm.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	cm.position = Vector3(0.0, 6.0, 0.0)
	_chute.add_child(cm)
	global_position = target + Vector3(0.0, FALL_FROM, 0.0)

## Walked up to and taken from. Called by `Walker._take`.
func resupply(who: Node) -> void:
	if not _landed:
		return
	if _served.has(who.get_instance_id()):
		Sim.report("you have had what is in this one", Sim.Ev.INFO)
		return
	_served[who.get_instance_id()] = true
	_give(who)

func _give(who: Node) -> void:
	if kind == "vest":
		if "armour" in who:
			who.set("armour", VEST)
		if who.has_method("rearm") and who is Walker:
			Sim.report("ballistic vest on — it takes half of every hit until it is spent",
				Sim.Ev.GOOD)
	else:
		if who.has_method("rearm"):
			who.call("rearm")
		if "health" in who:
			who.set("health", 100.0)
		if who is Walker:
			Sim.report("resupplied — every magazine, both grenades, and patched up",
				Sim.Ev.GOOD)
	if who is Walker:
		Sfx.play_ui(get_tree().current_scene, "mag_in", -6.0)

func _physics_process(delta: float) -> void:
	if not _landed:
		var ground: float = Sim.height_at(global_position.x, global_position.z)
		global_position.y -= FALL_SPEED * delta
		rotation.y += delta * 0.3
		if global_position.y <= ground:
			global_position.y = ground
			_landed = true
			if is_instance_valid(_chute):
				_chute.queue_free()
			add_to_group("pickups")
			Sfx.play_at(get_tree().current_scene, "thump", global_position, -6.0, 0.8, 120.0)
			Sim.report("%s is down" % ("supply drop" if kind == "supply" else "vest drop"),
				Sim.Ev.INFO)
		return
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	# his own side helps itself as it goes by
	for n in get_tree().get_nodes_in_group("infantry"):
		var sd := n as Node3D
		if sd == null or not ("team" in sd) or int(sd.get("team")) != team:
			continue
		if sd is Walker or _served.has(sd.get_instance_id()):
			continue
		if sd.global_position.distance_to(global_position) < SHARE:
			_served[sd.get_instance_id()] = true
			_give(sd)

## The pickup ring a dropped weapon has, so `_reach_for` can treat it alike.
var kit := ""
var rounds := 0
