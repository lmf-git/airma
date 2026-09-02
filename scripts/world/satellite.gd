class_name Satellite
extends Node3D
## Something in orbit. A bus, two solar wings and a dish, going round a long way
## up and a long way faster than anything with wings.
##
## Deliberately NOT in the "hittable" group. That group is the radar picture,
## the lock list and the blast loop all at once: putting a satellite in it would
## have every fighter's AMRAAM and every warhead's damage sweep considering
## something a hundred kilometres up. It carries `hit_radius()` instead, which
## is the path a round already uses to fuse on a target that is not a radar
## contact — the same way an interceptor kills a missile.

signal died(who)

## What it is for, which is what you lose when it is shot down.
const KINDS := {
	"recon": {"name": "Reconnaissance satellite", "hp": 60.0,
			  "body": Color(0.78, 0.76, 0.70), "note": "imaging"},
	"comms": {"name": "Communications satellite", "hp": 55.0,
			  "body": Color(0.72, 0.74, 0.78), "note": "relay"},
	"nav":   {"name": "Navigation satellite", "hp": 50.0,
			  "body": Color(0.80, 0.78, 0.72), "note": "timing"},
}

## Orbit. Real low orbit is 7.5 km/s at 400 km, which crosses this whole world
## in eight seconds — you would never see one, let alone shoot at one. The
## numbers here are chosen so that the shot is takeable: a launcher on the
## ground has to be able to put a round up there inside a minute and still have
## the energy to correct onto a crossing target. Seventy kilometres is
## unambiguously above everything — there is no terrain within eighty of it —
## and eight hundred metres a second is fast enough that the lead matters and
## slow enough that it can be led.
const ALT := 70_000.0
const ORBIT_R := 40_000.0
const SPEED := 800.0

var kind := "recon"
var team := 0
var health := 60.0
var alive := true
var phase := 0.0                  # where round the orbit it starts
var incl := 0.0                   # which way the ground track runs
var centre := Vector3.ZERO
var _t := 0.0
var _panels: Node3D

func setup(t := 0, k := "recon", start_phase := 0.0, inclination := 0.0) -> void:
	team = t
	kind = k if KINDS.has(k) else "recon"
	health = float(KINDS[kind]["hp"])
	phase = start_phase
	incl = inclination
	add_to_group("satellites")
	_build()
	# Not placed here: `_place` works in global space and looks along the track,
	# and neither is meaningful before the node is in the tree. Callers set it
	# up and then add it, so the first placement happens on entering the tree.
	_placed = false

var _placed := false

func _enter_tree() -> void:
	if not _placed:
		_placed = true
		_place(0.0)

func display_name() -> String:
	return String(KINDS[kind]["name"])

func _build() -> void:
	var body: Color = KINDS[kind]["body"]
	var st := MeshKit.begin()
	# the bus
	MeshKit.box(st, Vector3(2.2, 2.0, 3.0), Vector3.ZERO)
	# the dish it does its work with
	MeshKit.cone(st, 1.55, 0.35, -0.2, 1.5, Vector3(0, -1.1, 0), 12)
	add_child(MeshKit.mi(MeshKit.finish(st,
		MeshKit.mat(body, 0.45, 0.35)), "Bus"))
	# solar wings, which are the thing you actually recognise at a distance
	_panels = Node3D.new()
	_panels.name = "Panels"
	add_child(_panels)
	var pst := MeshKit.begin()
	for sx in [-1.0, 1.0]:
		MeshKit.box(pst, Vector3(0.30, 0.05, 2.6), Vector3(sx * 1.4, 0, 0))
		MeshKit.box(pst, Vector3(6.4, 0.08, 2.8), Vector3(sx * 5.0, 0, 0))
	_panels.add_child(MeshKit.mi(MeshKit.finish(pst,
		MeshKit.mat(Color(0.06, 0.09, 0.22), 0.25, 0.55,
			Color(0.02, 0.05, 0.12))), "Wings"))
	# It is a hundred kilometres away. At that range the geometry is a couple of
	# pixels, so what makes it findable is that it catches the sun — the same
	# reason you can see one from the ground.
	var glint := OmniLight3D.new()
	glint.light_color = Color(1.0, 0.98, 0.92)
	glint.light_energy = 6.0
	glint.omni_range = 260.0
	glint.shadow_enabled = false
	add_child(glint)

## Where it is now. A circle about the world centre, tipped by the inclination
## so the tracks are not all the same line.
func _place(dt: float) -> void:
	if not is_inside_tree():
		return
	_t += dt
	var a: float = phase + _t * SPEED / ORBIT_R
	var flat := Vector3(cos(a) * ORBIT_R, 0.0, sin(a) * ORBIT_R)
	flat = flat.rotated(Vector3(0, 0, 1), incl)
	global_position = centre + Vector3(flat.x, ALT + flat.y, flat.z)
	# nose along the track, wings across it
	var ahead := Vector3(-sin(a), 0.0, cos(a)).rotated(Vector3(0, 0, 1), incl)
	if ahead.length_squared() > 0.001:
		look_at(global_position + ahead, Vector3.UP)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	_place(delta)

## Where a round has to get to. A bus with a twelve metre wingspan is a small
## thing to hit, but not a point.
func hit_radius() -> float:
	return 7.0

func is_alive() -> bool:
	return alive

func get_velocity() -> Vector3:
	var a: float = phase + _t * SPEED / ORBIT_R
	return Vector3(-sin(a), 0.0, cos(a)).rotated(Vector3(0, 0, 1), incl) * SPEED

func take_hit(amount: float, _from: Node = null) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		_break_up()

## Nothing burns in orbit — there is nothing to burn with. What a kill looks
## like is the thing coming apart and the pieces carrying on along the track.
func _break_up() -> void:
	alive = false
	remove_from_group("satellites")
	Sim.report("%s destroyed in orbit" % display_name(),
		Sim.Ev.GOOD if team != 0 else Sim.Ev.BAD)
	var parent := get_parent()
	var vel := get_velocity()
	if parent != null:
		for i in 7:
			var d := Effects.Debris.new()
			d.life = 26.0
			d.rest_offset = 0.4
			# no air and no ground up here: the pieces simply keep going
			d.floats = false
			var sz := Vector3(randf_range(0.4, 1.6), randf_range(0.2, 0.9),
				randf_range(0.4, 1.8))
			var db := MeshKit.begin()
			MeshKit.box(db, sz, Vector3.ZERO)
			d.add_child(MeshKit.mi(MeshKit.finish(db,
				MeshKit.mat(Color(0.55, 0.55, 0.52), 0.5, 0.4)), "Piece"))
			parent.add_child(d)
			d.global_position = global_position
			d.vel = vel + Vector3(randf_range(-60, 60), randf_range(-60, 60),
				randf_range(-60, 60))
			d.spin = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	died.emit(self)
	queue_free()
