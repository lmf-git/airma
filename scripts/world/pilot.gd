class_name Pilot
extends Node3D
## Low-poly aircrew figure with procedural walk / climb / seated poses, and the
## ability to hand itself over to a physics ragdoll.

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var fore_l: Node3D
var fore_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var shin_l: Node3D
var shin_r: Node3D

var _head_meshes: Array = []
var weapon_mount: Node3D

const SUIT := Color(0.30, 0.33, 0.26)
const HARNESS := Color(0.16, 0.17, 0.15)
const HELMET := Color(0.80, 0.81, 0.83)
const VISOR := Color(0.10, 0.09, 0.06)

func _bit(size: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var st := MeshKit.begin()
	MeshKit.box(st, size, at)
	var mi := MeshKit.mi(MeshKit.finish(st, MeshKit.mat(col, 0.85, 0.0)), "Bit")
	return mi

func _joint(parent: Node3D, at: Vector3, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = at
	parent.add_child(n)
	return n

func build() -> void:
	hips = _joint(self, Vector3(0, 0.92, 0), "Hips")
	hips.add_child(_bit(Vector3(0.34, 0.22, 0.22), Vector3(0, 0.05, 0), SUIT))

	torso = _joint(hips, Vector3(0, 0.12, 0), "Torso")
	torso.add_child(_bit(Vector3(0.40, 0.52, 0.24), Vector3(0, 0.26, 0), SUIT))
	torso.add_child(_bit(Vector3(0.42, 0.16, 0.26), Vector3(0, 0.34, 0), HARNESS))
	torso.add_child(_bit(Vector3(0.12, 0.34, 0.06), Vector3(0, 0.30, -0.13), HARNESS))

	head = _joint(torso, Vector3(0, 0.56, 0), "Head")
	head.add_child(_bit(Vector3(0.20, 0.22, 0.22), Vector3(0, 0.11, 0), Color(0.72, 0.58, 0.48)))
	head.add_child(_bit(Vector3(0.26, 0.20, 0.27), Vector3(0, 0.16, 0), HELMET))
	head.add_child(_bit(Vector3(0.23, 0.10, 0.06), Vector3(0, 0.12, -0.13), VISOR))
	head.add_child(_bit(Vector3(0.09, 0.10, 0.12), Vector3(-0.13, 0.06, -0.03), Color(0.2, 0.2, 0.2)))
	_head_meshes = head.get_children()

	for s in [-1.0, 1.0]:
		var sh := _joint(torso, Vector3(s * 0.25, 0.44, 0), "Shoulder")
		sh.add_child(_bit(Vector3(0.11, 0.30, 0.12), Vector3(0, -0.15, 0), SUIT))
		var fo := _joint(sh, Vector3(0, -0.30, 0), "Elbow")
		fo.add_child(_bit(Vector3(0.10, 0.28, 0.10), Vector3(0, -0.14, 0), SUIT))
		fo.add_child(_bit(Vector3(0.10, 0.10, 0.10), Vector3(0, -0.30, 0), Color(0.20, 0.20, 0.22)))
		if s < 0:
			arm_l = sh
			fore_l = fo
		else:
			arm_r = sh
			fore_r = fo

	for s in [-1.0, 1.0]:
		var hp := _joint(hips, Vector3(s * 0.11, -0.04, 0), "Hip")
		hp.add_child(_bit(Vector3(0.15, 0.44, 0.16), Vector3(0, -0.22, 0), SUIT))
		var kn := _joint(hp, Vector3(0, -0.44, 0), "Knee")
		kn.add_child(_bit(Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), SUIT))
		kn.add_child(_bit(Vector3(0.14, 0.09, 0.28), Vector3(0, -0.44, -0.06), Color(0.12, 0.12, 0.13)))
		if s < 0:
			leg_l = hp
			shin_l = kn
		else:
			leg_r = hp
			shin_r = kn

## Lowest foot in body space. Procedural poses swing the legs, so without this
## the figure hovers whenever neither leg is vertical.
func lowest_foot() -> float:
	# start high, not at zero: if both feet are above the hips the body has to
	# come *down* to meet the ground, and clamping at zero left it hovering
	var lo := 9.0
	for kn in [shin_l, shin_r]:
		if not is_instance_valid(kn):
			continue
		var foot: Vector3 = kn.global_transform * Vector3(0, -0.44, -0.06)
		var local: Vector3 = global_transform.affine_inverse() * foot
		lo = minf(lo, local.y - 0.045)
	return 0.0 if lo > 8.0 else lo

## Hide just the head so the same body and animation can be used in first person.
func set_head_visible(v: bool) -> void:
	for m in _head_meshes:
		if is_instance_valid(m):
			m.visible = v

# --------------------------------------------------------------------------
func pose_idle() -> void:
	_rot(hips, 0, 0, 0)
	_rot(torso, 0, 0, 0)
	_rot(head, 0, 0, 0)
	_rot(arm_l, 0.10, 0, 0.10)
	_rot(arm_r, 0.10, 0, -0.10)
	_rot(fore_l, 0.30, 0, 0)
	_rot(fore_r, 0.30, 0, 0)
	_rot(leg_l, 0, 0, 0)
	_rot(leg_r, 0, 0, 0)
	_rot(shin_l, 0, 0, 0)
	_rot(shin_r, 0, 0, 0)

func pose_walk(t: float) -> void:
	_gait(t, 5.4, 0.52, 1.25, 0.40, 0.05)

## Shared gait. The knee is the thing that was missing: the old cycle only bent
## it behind the body, so the forward leg swung through dead straight and the
## foot skated along the ground looking for somewhere to land. A knee that
## flexes as the leg comes through, and an ankle that rolls with it, is most of
## what separates walking from sliding.
func _gait(t: float, freq: float, hip_amp: float, knee_amp: float,
		arm_amp: float, lean: float) -> void:
	var ph := t * freq
	var a := sin(ph)
	var b := sin(ph + PI)
	# knee flexes through the swing: rectified, phase led so the peak lands just
	# after the foot leaves the ground rather than at full stride
	var ka: float = knee_amp * pow(clampf(sin(ph + 2.0), 0.0, 1.0), 1.25)
	var kb: float = knee_amp * pow(clampf(sin(ph + 2.0 + PI), 0.0, 1.0), 1.25)
	_rot(hips, lean * 0.6, 0, sin(ph * 2.0) * 0.03)
	_rot(torso, lean, -a * 0.10, 0)          # shoulders counter-rotate the hips
	_rot(head, -lean * 0.7, a * 0.05, 0)
	_rot(leg_l, a * hip_amp, 0, 0.02)
	_rot(leg_r, b * hip_amp, 0, -0.02)
	_rot(shin_l, -ka - 0.06, 0, 0)
	_rot(shin_r, -kb - 0.06, 0, 0)
	# arms oppose the legs, and the elbow closes as the arm comes forward
	_rot(arm_l, b * arm_amp + 0.10, 0, 0.12)
	_rot(arm_r, a * arm_amp + 0.10, 0, -0.12)
	_rot(fore_l, 0.42 + clampf(b, 0.0, 1.0) * 0.45, 0, 0)
	_rot(fore_r, 0.42 + clampf(a, 0.0, 1.0) * 0.45, 0, 0)

func pose_climb(t: float) -> void:
	var a := sin(t * 3.4)
	var b := -a
	_rot(hips, 0.12, 0, 0)
	_rot(torso, 0.10, 0, 0)
	_rot(head, -0.25, 0, 0)
	_rot(arm_l, 2.35 + a * 0.35, 0, 0.20)
	_rot(arm_r, 2.35 + b * 0.35, 0, -0.20)
	_rot(fore_l, 0.55, 0, 0)
	_rot(fore_r, 0.55, 0, 0)
	_rot(leg_l, 0.75 + b * 0.55, 0, 0)
	_rot(leg_r, 0.75 + a * 0.55, 0, 0)
	_rot(shin_l, -1.15 - maxf(b, 0.0) * 0.5, 0, 0)
	_rot(shin_r, -1.15 - maxf(a, 0.0) * 0.5, 0, 0)

## Run cycle: longer stride, forward lean, arms driving.
func pose_run(t: float) -> void:
	_gait(t, 8.6, 0.92, 1.95, 0.78, 0.17)

## Crouched: hips down, knees folded, weapon tucked in.
func pose_crouch(t: float, moving: bool) -> void:
	var a := sin(t * 4.4) * (1.0 if moving else 0.0)
	_rot(hips, 0.22, 0, 0)
	_rot(torso, 0.12, 0, 0)
	_rot(head, -0.30, 0, 0)
	_rot(leg_l, 1.05 + a * 0.35, 0, 0.10)
	_rot(leg_r, 1.05 - a * 0.35, 0, -0.10)
	_rot(shin_l, -1.55, 0, 0)
	_rot(shin_r, -1.55, 0, 0)
	_rot(arm_l, 1.10, 0, 0.28)
	_rot(arm_r, 1.10, 0, -0.28)
	_rot(fore_l, 0.75, 0, 0)
	_rot(fore_r, 0.75, 0, 0)

## In the air: legs trailing, arms out for balance.
func pose_air(up: bool) -> void:
	_rot(hips, 0.05, 0, 0)
	_rot(torso, 0.08, 0, 0)
	_rot(head, -0.10, 0, 0)
	_rot(arm_l, 1.25 if up else 0.65, 0, 0.45)
	_rot(arm_r, 1.25 if up else 0.65, 0, -0.45)
	_rot(fore_l, 0.60, 0, 0)
	_rot(fore_r, 0.60, 0, 0)
	_rot(leg_l, 0.55 if up else -0.25, 0, 0.05)
	_rot(leg_r, -0.35 if up else 0.35, 0, -0.05)
	_rot(shin_l, -0.95 if up else -0.35, 0, 0)
	_rot(shin_r, -0.55, 0, 0)

## Weapon up, both hands on it, torso squared to the aim direction.
const TORSO_BACK := 0.10         # back of the chest in torso space
const UPPER_ARM := 0.30          # shoulder to elbow
const FOREARM := 0.30            # elbow to hand
## Grips in weapon space: trigger hand and support hand.
const GRIP_R := Vector3(0.0, -0.07, 0.05)
const GRIP_L := Vector3(0.0, -0.05, -0.21)

func pose_aim(pitch_rad: float) -> void:
	# The weapon leads and the arms follow it, rather than the arms being posed
	# at fixed angles and the weapon hung wherever they happen to end up. Both
	# hands are solved onto the grips with two bone IK, so the elbows change
	# with the aim angle the way they have to.
	_rot(torso, clampf(-pitch_rad * 0.16, -0.20, 0.20), 0, 0)
	_rot(head, clampf(-pitch_rad * 0.34, -0.45, 0.45), 0, 0)
	aim_weapon(pitch_rad)
	if not is_instance_valid(weapon_mount) or not is_instance_valid(torso):
		return
	var to_torso := torso.global_transform.affine_inverse()
	_reach(arm_r, fore_r, to_torso * (weapon_mount.global_transform * GRIP_R), -1.0)
	_reach(arm_l, fore_l, to_torso * (weapon_mount.global_transform * GRIP_L), 1.0)

## Two bone IK. `target` is in the shoulder's parent space; `side` is -1 for the
## right arm and +1 for the left, and decides which way the elbow breaks. The
## limbs are modelled down the local -Y axis, so the solve builds a basis with
## -Y along the bone rather than the usual -Z.
func _reach(sh: Node3D, el: Node3D, target: Vector3, side: float) -> void:
	if not is_instance_valid(sh) or not is_instance_valid(el):
		return
	var v: Vector3 = target - sh.position
	var d: float = clampf(v.length(), 0.06, UPPER_ARM + FOREARM - 0.015)
	if v.length() < 1e-5:
		return
	var dir: Vector3 = v.normalized()
	# interior angle at the elbow, and how far the upper arm sits off the
	# straight line from shoulder to hand
	var ce: float = clampf((UPPER_ARM * UPPER_ARM + FOREARM * FOREARM - d * d)
		/ (2.0 * UPPER_ARM * FOREARM), -1.0, 1.0)
	var cs: float = clampf((UPPER_ARM * UPPER_ARM + d * d - FOREARM * FOREARM)
		/ (2.0 * UPPER_ARM * d), -1.0, 1.0)
	# a basis whose -Y runs to the target; the elbow breaks outward and back
	var ydir: Vector3 = -dir
	var hint := Vector3(side * 0.35, 0.0, 1.0).normalized()
	var xdir: Vector3 = ydir.cross(hint)
	if xdir.length() < 1e-4:
		xdir = Vector3(1, 0, 0)
	xdir = xdir.normalized()
	var zdir: Vector3 = xdir.cross(ydir).normalized()
	var flat := Basis(xdir, ydir, zdir)
	# Two solutions reach the same hand position: the elbow can break either
	# way round the shoulder-to-hand line. Picking by side alone put the right
	# arm's elbow behind the back -- the hand was on the grip and the limb was
	# routed round the wrong side of the body. Take whichever puts the elbow
	# lower, which is how a rifle is actually held.
	var lift := acos(cs)
	var bend := PI - acos(ce)
	# The shoulder swing and the elbow bend are a matched pair: mirroring one
	# without the other moves the hand off the grip entirely. Evaluate both
	# complete solutions and keep the one with the lower elbow.
	var b_neg := flat.rotated(xdir, -lift)
	var b_pos := flat.rotated(xdir, lift)
	var p_neg: Vector3 = sh.position + b_neg * Vector3(0, -UPPER_ARM, 0)
	var p_pos: Vector3 = sh.position + b_pos * Vector3(0, -UPPER_ARM, 0)
	# Score them: an elbow that ends up behind the shoulder blades is wrong
	# whatever else it has going for it, and after that lower is better.
	var e_neg: float = p_neg.y + (3.0 if p_neg.z > TORSO_BACK else 0.0)
	var e_pos: float = p_pos.y + (3.0 if p_pos.z > TORSO_BACK else 0.0)
	if e_pos < e_neg:
		sh.transform.basis = b_pos
		el.rotation = Vector3(-bend, 0, 0)
	else:
		sh.transform.basis = b_neg
		el.rotation = Vector3(bend, 0, 0)

## How far each hand is from its grip, in metres. Zero means the arms are
## actually holding the weapon rather than gesturing near it.
## Elbow positions in torso space, for checking the limb is not routed round
## the back of the body.
func elbow_pos() -> Array:
	return [fore_r.position if not is_instance_valid(fore_r) else
		(torso.global_transform.affine_inverse() * fore_r.global_position),
		fore_l.position if not is_instance_valid(fore_l) else
		(torso.global_transform.affine_inverse() * fore_l.global_position)]

func grip_error() -> Vector2:
	if not is_instance_valid(weapon_mount):
		return Vector2.ZERO
	var hr: Vector3 = fore_r.global_transform * Vector3(0, -FOREARM, 0)
	var hl: Vector3 = fore_l.global_transform * Vector3(0, -FOREARM, 0)
	return Vector2(hr.distance_to(weapon_mount.global_transform * GRIP_R),
		hl.distance_to(weapon_mount.global_transform * GRIP_L))

## A carbine on a mount fixed to the body. Hanging it off the end of the arm
## chain meant the shoulder and elbow angles decided where it pointed, which is
## why it ended up aimed at the sky; the mount is driven by the aim angle
## directly and the arms are posed to meet it.
func add_weapon() -> Node3D:
	weapon_mount = Node3D.new()
	weapon_mount.name = "WeaponMount"
	# Held closer in than it was: the support hand has to be able to reach the
	# foregrip, and at 0.17 out and 0.20 forward the left arm was 65 cm from a
	# shoulder that can only manage 58.
	weapon_mount.position = Vector3(0.10, 1.36, -0.16)
	add_child(weapon_mount)
	var w := Node3D.new()
	w.name = "Carbine"
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0.06, 0.09, 0.62), Vector3(0, 0, -0.10))
	MeshKit.box(st, Vector3(0.05, 0.16, 0.16), Vector3(0, -0.11, 0.14))
	MeshKit.box(st, Vector3(0.04, 0.06, 0.30), Vector3(0, 0.08, -0.02))
	MeshKit.box(st, Vector3(0.05, 0.12, 0.10), Vector3(0, -0.10, -0.12))
	w.add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.13, 0.13, 0.14), 0.7, 0.2)), "M"))
	w.position = Vector3.ZERO
	weapon_mount.add_child(w)
	return w

## Point the weapon where the eye is looking.
func aim_weapon(pitch_rad: float) -> void:
	if is_instance_valid(weapon_mount):
		weapon_mount.rotation = Vector3(pitch_rad, 0.0, 0.0)

func pose_seated() -> void:
	_rot(hips, 0, 0, 0)
	_rot(torso, -0.14, 0, 0)
	_rot(head, 0.05, 0, 0)
	_rot(arm_l, 1.05, 0, 0.20)
	_rot(arm_r, 1.05, 0, -0.20)
	_rot(fore_l, 0.55, 0, 0)
	_rot(fore_r, 0.55, 0, 0)
	_rot(leg_l, 1.52, 0, 0.05)
	_rot(leg_r, 1.52, 0, -0.05)
	_rot(shin_l, -1.25, 0, 0)
	_rot(shin_r, -1.25, 0, 0)

func _rot(n: Node3D, x: float, y: float, z: float) -> void:
	if is_instance_valid(n):
		n.rotation = Vector3(x, y, z)

## Hand the current pose over to a physics ragdoll and remove this figure.
func make_ragdoll(velocity: Vector3) -> Node3D:
	var rd := Ragdoll.new()
	rd.spawn_from(global_transform, velocity)
	var parent := get_parent()
	if parent:
		parent.add_child(rd)
	queue_free()
	return rd
