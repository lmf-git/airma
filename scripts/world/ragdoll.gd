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
	["torso", "head", Vector3(0, 0.44, 0), 0.6, 0.4],
	["torso", "arm_l", Vector3(-0.28, 0.66, 0), 1.4, 0.9],
	["torso", "arm_r", Vector3(0.28, 0.66, 0), 1.4, 0.9],
	["pelvis", "leg_l", Vector3(-0.12, -0.13, 0), 1.1, 0.5],
	["pelvis", "leg_r", Vector3(0.12, -0.13, 0), 1.1, 0.5],
]

var bodies := {}
var life := 26.0

func spawn_from(xf: Transform3D, velocity: Vector3) -> void:
	set_meta("spawn_xf", xf)
	set_meta("spawn_vel", velocity)

func _ready() -> void:
	var xf: Transform3D = get_meta("spawn_xf", Transform3D.IDENTITY)
	var vel: Vector3 = get_meta("spawn_vel", Vector3.ZERO)
	global_transform = Transform3D(Basis(), xf.origin)
	_ground_patch(xf.origin)
	for l in LIMBS:
		var b := RigidBody3D.new()
		b.name = str(l[0])
		b.mass = float(l[3])
		b.can_sleep = true
		b.continuous_cd = true
		b.collision_layer = 4
		b.collision_mask = 4
		b.physics_material_override = PhysicsMaterial.new()
		b.physics_material_override.friction = 0.9
		b.physics_material_override.bounce = 0.05
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = l[1]
		cs.shape = box
		b.add_child(cs)
		var col := Pilot.SUIT
		if l[0] == "head":
			col = Pilot.HELMET
		b.add_child(MeshKit.mi(_box_mesh(l[1], col), "M"))
		add_child(b)
		b.global_position = xf.origin + xf.basis * (l[2] as Vector3)
		b.linear_velocity = vel + Vector3(randf_range(-2, 2), randf_range(0, 3), randf_range(-2, 2))
		b.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		bodies[l[0]] = b
	for j in JOINTS:
		var joint := ConeTwistJoint3D.new()
		joint.position = (j[2] as Vector3)
		joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, float(j[3]))
		joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, float(j[4]))
		joint.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.7)
		joint.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 0.9)
		add_child(joint)
		joint.node_a = bodies[j[0]].get_path()
		joint.node_b = bodies[j[1]].get_path()

func _box_mesh(size: Vector3, col: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, size, Vector3.ZERO)
	return MeshKit.finish(st, MeshKit.mat(col, 0.85, 0.0))

## The world has no collision mesh, so drop a patch of ground under the ragdoll.
func _ground_patch(at: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 4
	sb.collision_mask = 4
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 4, 160)
	cs.shape = box
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = Vector3(at.x, maxf(Sim.height_at(at.x, at.z), Sim.WATER_LEVEL) - 2.0, at.z)

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
