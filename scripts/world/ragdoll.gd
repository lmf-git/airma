class_name Ragdoll
extends Node3D
## A jointed rigid-body pilot. Used when the aircraft is destroyed: the crew
## tumbles clear instead of vanishing with the wreck.

const LIMBS := [
	# name, size, offset from the pelvis, mass
	["pelvis", Vector3(0.34, 0.26, 0.22), Vector3(0, 0.00, 0), 14.0],
	["torso", Vector3(0.40, 0.52, 0.24), Vector3(0, 0.42, 0), 26.0],
	["head", Vector3(0.26, 0.28, 0.27), Vector3(0, 0.86, 0), 6.0],
	["arm_l", Vector3(0.12, 0.56, 0.12), Vector3(-0.28, 0.42, 0), 4.0],
	["arm_r", Vector3(0.12, 0.56, 0.12), Vector3(0.28, 0.42, 0), 4.0],
	["leg_l", Vector3(0.16, 0.84, 0.16), Vector3(-0.12, -0.50, 0), 9.0],
	["leg_r", Vector3(0.16, 0.84, 0.16), Vector3(0.12, -0.50, 0), 9.0],
]
const JOINTS := [
	["pelvis", "torso", Vector3(0, 0.21, 0), 0.7, 0.5],
	["torso", "head", Vector3(0, 0.70, 0), 0.6, 0.4],
	["torso", "arm_l", Vector3(-0.28, 0.66, 0), 1.4, 0.9],
	["torso", "arm_r", Vector3(0.28, 0.66, 0), 1.4, 0.9],
	["pelvis", "leg_l", Vector3(-0.12, -0.13, 0), 1.1, 0.5],
	["pelvis", "leg_r", Vector3(0.12, -0.13, 0), 1.1, 0.5],
]

## One physics material for every limb of every body: they were a new one per
## limb per death, all with the same two numbers in them.
static var _grip: PhysicsMaterial = null

## Each body lies on a floor of its own, on a collision layer nobody else's
## limbs look at. The floors were all on the shared layer, a hundred and sixty
## metres across, so every limb in the street was tested against every body's
## floor -- forty men down was six thousand pairs -- and on a slope a man killed
## beside another started with his boots inside the other's floor, which the
## solver answered by throwing him thirty metres. Bits 9 to 32, handed out in
## turn; the first twenty-four bodies alive at once never share one.
const FLOOR_BITS := 24
static var _floor_next := 0
var _floor_bit := 0

var bodies := {}
var life := 26.0
## A man who has been shot falls down. The tumble below is for crew thrown
## out of an aeroplane that has just come apart, and on someone standing in a
## street it is a body that spins on the spot like a dropped firework.
var calm := false
## Limbs he no longer has: "head", "arm_l", "arm_r", "leg_l", "leg_r".
var lost: Array = []

## What is left of a man who has just been killed, and where it goes.
##
## What did it decides. A shell, a grenade or a tank track leaves nothing to
## fall over. A round through the head takes the head. A round low down takes
## a leg and one higher up an arm, when it was heavy enough to or some of the
## time when it was not. Otherwise he falls whole. The player and the AI both
## come through here, so the same thing happens to either.
static func fall(world: Node, feet: Transform3D, velocity: Vector3, suit: Color, helmet: Color,
		amount: float, head: bool, low: bool, from_dir: Vector3, lasts := 16.0) -> void:
	if world == null or not world.is_inside_tree():
		return
	var _pr := Sim.prof_at()
	_fall(world, feet, velocity, suit, helmet, amount, head, low, from_dir, lasts)
	Sim.prof_end(&"fx.death", _pr)

static func _fall(world: Node, feet: Transform3D, velocity: Vector3, suit: Color, helmet: Color,
		amount: float, head: bool, low: bool, from_dir: Vector3, lasts: float) -> void:
	var at: Vector3 = feet.origin
	var right: Vector3 = feet.basis.orthonormalized().x
	if amount >= 120.0 and not head:
		Effects.gib(world, at, velocity + from_dir * 4.0, suit)
		return
	var rd := Ragdoll.new()
	rd.set_meta("suit", suit)
	rd.set_meta("helmet", helmet)
	rd.life = lasts
	if head:
		rd.lost = ["head"]
		Effects.chunk(world, at + Vector3(0, 1.75, 0), from_dir * 5.0 + Vector3(0, 3.5, 0),
			Vector3(0.26, 0.28, 0.27), helmet, 30.0)
		Effects.gore_burst(world, at + Vector3(0, 1.6, 0), from_dir + Vector3.UP, 8, 5.0)
	elif amount >= 40.0 or randf() < 0.3:
		var sgn: float = -1.0 if randf() < 0.5 else 1.0
		var leg: bool = low or randf() < 0.25
		var limb: String = ("leg" if leg else "arm") + ("_l" if sgn < 0.0 else "_r")
		rd.lost = [limb]
		var stump: Vector3 = at + right * sgn * (0.12 if leg else 0.28) \
			+ Vector3(0, 0.8 if leg else 1.35, 0)
		Effects.chunk(world, stump, from_dir * 3.0 + right * sgn * 2.5 + Vector3(0, 2.5, 0),
			Vector3(0.16, 0.84, 0.16) if leg else Vector3(0.12, 0.56, 0.12), suit, 30.0)
		Effects.gore_burst(world, stump, from_dir + right * sgn, 6, 4.0)
	else:
		Effects.gore_burst(world, at + Vector3(0, 1.2, 0), from_dir, 4, 3.5)
	Effects.blood_pool(world, at, randf_range(0.8, 1.3))
	rd.spawn_standing(feet, velocity * 0.7 + from_dir * 1.5)
	world.add_child(rd)

## For a figure whose origin is at its feet. `spawn_from` wants the pelvis:
## handed the feet, the legs start a metre underground and the solver throws
## the whole thing into the air getting them out.
func spawn_standing(feet: Transform3D, velocity: Vector3) -> void:
	calm = true
	var xf := feet
	xf.basis = xf.basis.orthonormalized()
	xf.origin += xf.basis.y * 0.96
	spawn_from(xf, velocity)

func spawn_from(xf: Transform3D, velocity: Vector3) -> void:
	set_meta("spawn_xf", xf)
	set_meta("spawn_vel", velocity)

func _ready() -> void:
	var xf: Transform3D = get_meta("spawn_xf", Transform3D.IDENTITY)
	var vel: Vector3 = get_meta("spawn_vel", Vector3.ZERO)
	global_transform = Transform3D(Basis(), xf.origin)
	_floor_bit = 1 << (8 + _floor_next % FLOOR_BITS)
	_floor_next += 1
	_ground_patch(xf.origin)
	for l in LIMBS:
		if lost.has(l[0]):
			continue
		var b := RigidBody3D.new()
		b.name = str(l[0])
		b.mass = float(l[3])
		b.can_sleep = true
		# Continuous collision only costs anything while a limb is moving
		# fast, which is exactly when it is needed: crew thrown clear of a
		# wreck, or a limb kicked loose when two bodies fall together.
		b.continuous_cd = true
		# buildings and other bodies on 4, and this body's own floor
		b.collision_layer = 4
		b.collision_mask = 4 | _floor_bit
		if _grip == null:
			_grip = PhysicsMaterial.new()
			_grip.friction = 0.9
			_grip.bounce = 0.05
		b.physics_material_override = _grip
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = l[1]
		cs.shape = box
		b.add_child(cs)
		# dressed as whoever fell: a figure that changed uniform as it went
		# down read as a different man
		var col: Color = get_meta("suit", Pilot.SUIT)
		if l[0] == "head":
			col = get_meta("helmet", Pilot.HELMET)
		b.add_child(_limb(l[1], col, "M"))
		add_child(b)
		# Facing the way the figure faced. Placed by position alone, every
		# limb was square to the world whatever way he had been standing.
		b.global_transform = Transform3D(xf.basis.orthonormalized(),
			xf.origin + xf.basis * (l[2] as Vector3))
		if calm:
			b.linear_velocity = vel + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
			b.angular_velocity = Vector3(randf_range(-0.8, 0.8), randf_range(-0.4, 0.4),
				randf_range(-0.8, 0.8))
			b.angular_damp = 1.2
			b.linear_damp = 0.15
		else:
			b.linear_velocity = vel + Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-2, 2))
			b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		bodies[l[0]] = b
	for j in JOINTS:
		if bodies.has(j[0]) and not bodies.has(j[1]):
			# the raw end of it, on whatever it used to be joined to
			var owner_body: RigidBody3D = bodies[j[0]]
			var cap := _limb(Vector3(0.15, 0.07, 0.15) if j[1] != "head"
				else Vector3(0.16, 0.06, 0.16), Color(0.40, 0.03, 0.03), "Stump")
			owner_body.add_child(cap)
			cap.global_position = xf.origin + xf.basis * (j[2] as Vector3)
		if not bodies.has(j[0]) or not bodies.has(j[1]):
			continue
		var joint := ConeTwistJoint3D.new()
		# Turned with the body. The anchors were laid out for a figure facing
		# north and left there, so anyone facing another way had his shoulders
		# and hips pinned to points in space beside him: the limbs were dragged
		# to them on the first step and the figure folded up.
		joint.transform = Transform3D(xf.basis.orthonormalized(), xf.basis * (j[2] as Vector3))
		joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, float(j[3]))
		joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, float(j[4]))
		joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.7)
		joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.9)
		add_child(joint)
		joint.node_a = bodies[j[0]].get_path()
		joint.node_b = bodies[j[1]].get_path()

## A limb: the shared unit cube at the limb's size, in the shared material for
## its colour. Each was a mesh and a material built for the one body.
func _limb(size: Vector3, col: Color, nm: String) -> MeshInstance3D:
	var mi := MeshKit.mi(Effects.unit_box(), nm)
	mi.material_override = Effects.bit_mat(col)
	mi.scale = size
	return mi

## The world has no collision mesh, so drop a patch of ground under the ragdoll.
## Only this body's limbs can touch it: see `FLOOR_BITS`.
func _ground_patch(at: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = _floor_bit
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Deep, not a sheet. A limb knocked more than half way into a slab four
	# metres thick is nearer the bottom face than the top, and the solver
	# pushes it out the way that is shortest -- down, through the floor, for
	# ever. Forty metres deep, the shortest way out is always up.
	box.size = Vector3(160, 40, 160)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = Vector3(at.x, maxf(Sim.height_at(at.x, at.z), Sim.sea_at(at.x, at.z)) - 20.0, at.z)

## The pool where he has come to rest, not where he was hit, and then gone
## when his time is up. Two timers: this was a frame callback for every body
## for the whole of its life, to do two things once each.
func _enter_tree() -> void:
	if is_inside_tree() and not has_meta("timed"):
		set_meta("timed", true)
		get_tree().create_timer(2.2, false).timeout.connect(_bleed)
		get_tree().create_timer(maxf(life, 0.05), false).timeout.connect(queue_free)

func _bleed() -> void:
	if (calm or not lost.is_empty()) and bodies.has("torso") \
			and is_instance_valid(bodies["torso"]):
		Effects.blood_pool(get_parent(), (bodies["torso"] as Node3D).global_position, 1.2)
