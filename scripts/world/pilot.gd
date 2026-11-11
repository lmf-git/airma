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

var foot_l: Node3D
var foot_r: Node3D

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

## `suit` and `helmet` are what he is wearing; `patch` is a flash on each
## shoulder, which is how you tell whose side a man is on across a street.
func build(suit := SUIT, helmet := HELMET, patch := Color(0, 0, 0, 0)) -> void:
	hips = _joint(self, Vector3(0, 0.92, 0), "Hips")
	hips.add_child(_bit(Vector3(0.34, 0.22, 0.22), Vector3(0, 0.05, 0), suit))

	torso = _joint(hips, Vector3(0, 0.12, 0), "Torso")
	torso.add_child(_bit(Vector3(0.40, 0.52, 0.24), Vector3(0, 0.26, 0), suit))
	torso.add_child(_bit(Vector3(0.42, 0.16, 0.26), Vector3(0, 0.34, 0), HARNESS))
	torso.add_child(_bit(Vector3(0.12, 0.34, 0.06), Vector3(0, 0.30, -0.13), HARNESS))

	head = _joint(torso, Vector3(0, 0.56, 0), "Head")
	head.add_child(_bit(Vector3(0.20, 0.22, 0.22), Vector3(0, 0.11, 0), Color(0.72, 0.58, 0.48)))
	head.add_child(_bit(Vector3(0.26, 0.20, 0.27), Vector3(0, 0.16, 0), helmet))
	head.add_child(_bit(Vector3(0.23, 0.10, 0.06), Vector3(0, 0.12, -0.13), VISOR))
	head.add_child(_bit(Vector3(0.09, 0.10, 0.12), Vector3(-0.13, 0.06, -0.03), Color(0.2, 0.2, 0.2)))
	_head_meshes = head.get_children()

	for s in [-1.0, 1.0]:
		var sh := _joint(torso, Vector3(s * 0.25, 0.44, 0), "Shoulder")
		sh.add_child(_bit(Vector3(0.11, 0.30, 0.12), Vector3(0, -0.15, 0), suit))
		if patch.a > 0.0:
			var pm := _bit(Vector3(0.03, 0.11, 0.10), Vector3(s * 0.05, -0.09, 0), patch)
			var lit := (pm.mesh as ArrayMesh).surface_get_material(0) as StandardMaterial3D
			lit.emission_enabled = true
			lit.emission = patch
			lit.emission_energy_multiplier = 0.6
			sh.add_child(pm)
		var fo := _joint(sh, Vector3(0, -0.30, 0), "Elbow")
		fo.add_child(_bit(Vector3(0.10, 0.28, 0.10), Vector3(0, -0.14, 0), suit))
		fo.add_child(_bit(Vector3(0.10, 0.10, 0.10), Vector3(0, -0.30, 0), Color(0.20, 0.20, 0.22)))
		if s < 0:
			arm_l = sh
			fore_l = fo
		else:
			arm_r = sh
			fore_r = fo

	for s in [-1.0, 1.0]:
		var hp := _joint(hips, Vector3(s * 0.11, -0.04, 0), "Hip")
		hp.add_child(_bit(Vector3(0.15, 0.44, 0.16), Vector3(0, -0.22, 0), suit))
		var kn := _joint(hp, Vector3(0, -0.44, 0), "Knee")
		kn.add_child(_bit(Vector3(0.13, 0.42, 0.14), Vector3(0, -0.21, 0), suit))
		# The boot hangs off an ankle of its own. Fixed to the shin it could
		# only ever point where the shin pointed, so a planted foot stood on
		# its toe whenever the knee was bent.
		var an := _joint(kn, Vector3(0, -0.44, 0), "Ankle")
		an.add_child(_bit(Vector3(0.14, 0.09, 0.28), Vector3(0, 0.0, -0.06), Color(0.12, 0.12, 0.13)))
		if s < 0:
			leg_l = hp
			shin_l = kn
			foot_l = an
		else:
			leg_r = hp
			shin_r = kn
			foot_r = an

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
	# The chest and hips are what the first-person camera sits inside; the
	# arms and legs are separate joints and stay.
	for j in [torso, hips]:
		if is_instance_valid(j):
			for m in j.get_children():
				if m is MeshInstance3D:
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
	# Forward is a NEGATIVE turn about x here: the figure faces -z, so a
	# positive one tips the head back over the heels. These were positive,
	# and he ran leaning backwards like a man being pulled along by a dog.
	_rot(hips, -lean * 0.6, 0, sin(ph * 2.0) * 0.03)
	_rot(torso, -lean, -a * 0.10, 0)         # shoulders counter-rotate the hips
	_rot(head, lean * 0.7, a * 0.05, 0)
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
	_rot(hips, 0.10, 0, 0)
	_rot(torso, -0.30, 0, 0)
	_rot(head, 0.22, 0, 0)
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

# ============================================================================
# The armed rig.
#
# The poses above are fixed angles: a walk is a walk whatever the ground is
# doing, and the weapon was a box bolted to the chest that the arms were posed
# to meet. Seen from outside that is a man holding a rifle. Seen from inside his
# head it is a rifle that stays where the chest is while the view goes
# somewhere else -- look up and it drops out of the bottom of the screen, bring
# the sights up and nothing comes up.
#
# So the order is turned round. The eye leads: the weapon is placed where the
# eye needs it (on the sight line when aiming, down and across the body when
# running), the hands are solved onto it, and the feet are solved onto whatever
# is actually under them. The owner says what the man is doing by setting the
# `in_` values and calls `animate` once a frame; nothing else here needs to
# know whether he is a player or an AI.
# ============================================================================

const ARM_1 := 0.30              # shoulder to elbow
const ARM_2 := 0.33              # elbow to the middle of the fist
const LEG_1 := 0.44
const LEG_2 := 0.44
const HIP_Y := 0.92
const SOLE := 0.045
## Where the eye is, in the head joint's space.
const EYE_AT := Vector3(0.0, 0.15, -0.08)

var gun: Dictionary = {}
var gun_node: Node3D = null
var muzzle: Node3D = null
var _mag: Node3D = null

## Planar velocity in the body's own frame: x to his right, y forward.
var in_move := Vector2.ZERO
var in_crouch := false
## Flat on his front.
var in_prone := false
## 0 on the ground, +1 going up, -1 coming down.
var in_air := 0
var in_pitch := 0.0
## 1 with the weapon up and ready, 0 carried low: sprinting, or nothing to do.
var in_ready := 1.0
var in_ads := 0.0
## 1 with the muzzle lifted clear of a wall in front of him.
var in_block := 0.0
## -1 leaning left round a corner, +1 right.
var in_lean := 0.0
## How far through a reload, 0 to 1, or negative when not reloading.
var in_reload := -1.0
## How fast the view is turning (yaw, pitch), for the weapon to lag behind.
var in_turn := Vector2.ZERO
var in_foot_ik := true

## Something the whole body is doing, start to finish: "vault" over a low
## wall, "climb" onto a high one, "grab" a weapon off the ground, "slide" out
## of a sprint. `in_action_t` runs 0 to 1 through it and `in_point` is the
## place in the world the hands are going to -- the top of the wall, the rifle.
var in_action := ""
var in_action_t := 0.0
var in_point := Vector3.ZERO

## Counts footfalls. The owner watches it change and makes the noise.
var steps := 0

var _phase := 0.0
var _gait_ph := 0.0
var _ready_s := 1.0
var _kick := 0.0
var _draw := 0.0
var _hips_yaw := 0.0
var _pelvis := 0.0
var _g_l := 0.0
var _g_r := 0.0
var _sway := Vector2.ZERO
var _breath := 0.0
var _blend: Dictionary = {}
var _step_sign := 1.0
var _eye_s := Vector3(0.0, 1.74, -0.07)
var _climb_ph := 0.0
var _pull := Vector3.ZERO
var _sh_r := Vector3.INF
var _sh_l := Vector3.INF

## Put a weapon in his hands, replacing whatever was there.
func equip(g: Dictionary, quiet := false) -> void:
	if not is_instance_valid(weapon_mount):
		weapon_mount = Node3D.new()
		weapon_mount.name = "WeaponMount"
		add_child(weapon_mount)
	if is_instance_valid(gun_node):
		gun_node.queue_free()
	gun = g
	gun_node = Firearm.build(g, quiet)
	weapon_mount.add_child(gun_node)
	muzzle = gun_node.get_node("Muzzle") as Node3D
	_mag = gun_node.get_node("Mag") as Node3D
	_draw = 1.0

func has_gun() -> bool:
	return is_instance_valid(gun_node)

## The shot going off: the weapon comes back into the shoulder and settles.
func kick(amount: float) -> void:
	_kick = minf(_kick + amount, 1.6)

func muzzle_pos() -> Vector3:
	return muzzle.global_position if is_instance_valid(muzzle) \
		else global_transform * Vector3(0.1, 1.4, -0.6)

## Where he is looking from.
##
## Not the head joint. The head rides the torso and the torso rides the gait,
## so an eye fixed in it comes down with every footfall and swings with every
## counter-rotation of the shoulders -- and the weapon, which is placed from
## the eye, shook in step whenever he walked with the sights up. The eye is a
## steady point for the stance he is in; the body moves underneath it and the
## arms take up the difference, which is what a man holding a rifle on a
## target while he walks is doing with his own.
func eye_pos() -> Vector3:
	return global_transform * _eye_s

func _eye_target() -> Vector3:
	# over, up and down for something: there the body really is leading
	if in_action in ["vault", "climb", "wall", "ladder", "grab"]:
		return global_transform.affine_inverse() * (head.global_transform * EYE_AT)
	var e := Vector3(0.0, 1.74, -0.07)
	if in_prone:
		e = Vector3(0.0, 0.46, -0.10)
	elif in_action == "slide":
		e = Vector3(0.0, 0.80, 0.02)
	elif in_crouch:
		e = Vector3(0.0, 1.34, -0.13)
	e.x += in_lean * 0.26
	e.y -= absf(in_lean) * 0.04
	return e

func _k(delta: float, rate: float) -> float:
	return 1.0 - exp(-delta * rate)

## Feet apart, one ahead of the other, weight forward: standing to shoot.
func pose_stance() -> void:
	_rot(hips, -0.03, 0, 0)
	_rot(torso, -0.08, 0, 0)
	_rot(head, 0.05, 0, 0)
	_rot(leg_l, 0.20, 0, 0.07)
	_rot(leg_r, -0.13, 0, -0.08)
	_rot(shin_l, -0.24, 0, 0)
	_rot(shin_r, -0.16, 0, 0)

## One knee nearly down, the other up: small behind cover and steady to shoot.
func pose_kneel(t: float, moving: bool) -> void:
	if moving:
		pose_crouch(t, true)
		return
	_rot(hips, 0.0, 0, 0)
	_rot(torso, -0.14, 0, 0)
	_rot(head, 0.08, 0, 0)
	_rot(leg_l, 1.30, 0, 0.10)
	_rot(shin_l, -1.50, 0, 0)
	_rot(leg_r, 0.22, 0, -0.12)
	_rot(shin_r, -1.75, 0, 0)

## Drive the whole figure for one frame from the `in_` values.
func animate(delta: float) -> void:
	if not is_instance_valid(hips):
		return
	var speed: float = in_move.length()
	var moving: bool = speed > 0.4
	# Which way the legs are going. They can only swing fore and aft, so the
	# hips turn to face the way he is moving and the chest turns back to face
	# the way he is looking; past side-on he is walking backwards instead.
	var ang: float = atan2(in_move.x, in_move.y) if moving else 0.0
	var backward: bool = absf(ang) > deg_to_rad(105.0)
	if backward:
		ang = wrapf(ang + PI, -PI, PI)
	_hips_yaw = lerp_angle(_hips_yaw, clampf(-ang, -1.15, 1.15), _k(delta, 10.0))
	_phase += delta * clampf(speed / 4.2, 0.0, 2.2) * (-1.0 if backward else 1.0)

	var armed: bool = has_gun()
	var act: float = clampf(in_action_t, 0.0, 1.0)
	if in_action == "chute":
		# Hanging in the harness: legs together and a little forward, knees
		# soft for the landing, head up to the canopy. It was the jump pose --
		# arms out, one knee up -- held for the whole descent, with a rifle at
		# the shoulder.
		var sway: float = sin(_breath * 1.3) * 0.05
		_rot(hips, 0.10, 0, sway)
		_rot(torso, -0.06, in_lean * -0.25, -in_lean * 0.18)
		_rot(head, -0.30, 0, 0)
		_rot(leg_l, 0.30, 0, 0.03)
		_rot(leg_r, 0.24, 0, -0.03)
		_rot(shin_l, -0.42, 0, 0)
		_rot(shin_r, -0.36, 0, 0)
		_breath += delta
		_gait_ph = 0.0
	elif in_action == "wall" or in_action == "ladder":
		# On a wall or a ladder. The pose is only where the limbs start from:
		# every hand and foot is then solved onto the face, or onto a rung.
		_climb_ph += delta * clampf(speed, 0.0, 3.5) * 1.5 * signf(in_move.y + 0.001)
		pose_climb(0.0)
		_rot(hips, 0.06, 0, sin(_climb_ph * 3.4) * 0.07)
		_rot(torso, 0.04, sin(_climb_ph * 3.4) * 0.10, 0)
		_rot(head, -0.35, 0, 0)
		_gait_ph = 0.0
	elif in_prone and in_action == "" and in_air == 0:
		# flat, chest propped on the elbows, and a leopard crawl to move
		var crawl: float = sin(_phase * 7.0) * (1.0 if moving else 0.0)
		_rot(hips, -1.44, 0, crawl * 0.10)
		_rot(torso, 0.20, crawl * -0.12 * (1.0 - clampf(in_ads, 0.0, 1.0)), 0)
		_rot(head, 1.00, 0, 0)
		_rot(leg_l, 0.06 + maxf(crawl, 0.0) * 0.55, 0, 0.16)
		_rot(leg_r, 0.06 + maxf(-crawl, 0.0) * 0.55, 0, -0.16)
		_rot(shin_l, -maxf(crawl, 0.0) * 0.9, 0, 0)
		_rot(shin_r, -maxf(-crawl, 0.0) * 0.9, 0, 0)
		_rot(arm_l, 2.2, 0, 0.3)
		_rot(arm_r, 2.2, 0, -0.3)
		_gait_ph = _phase * 3.5
	elif in_action == "vault":
		# one hand on the top, both knees up and through
		pose_air(true)
		_rot(hips, 0.25, 0, -0.30 * sin(act * PI))
		_rot(torso, -0.40 * sin(act * PI), 0, 0)
		_rot(leg_l, 1.25, 0, 0.10)
		_rot(leg_r, 1.05, 0, -0.10)
		_rot(shin_l, -1.50, 0, 0)
		_rot(shin_r, -1.25, 0, 0)
		_gait_ph = 0.0
	elif in_action == "climb":
		# hauling up on the arms, then a knee over the edge
		pose_climb(act * 3.2)
		if act > 0.62:
			var over: float = smoothstep(0.62, 1.0, act)
			_rot(leg_l, lerpf(0.75, 1.55, over), 0, 0.15)
			_rot(shin_l, -1.65, 0, 0)
			_rot(torso, -0.10 - 0.45 * sin(over * PI), 0, 0)
		_gait_ph = 0.0
	elif in_action == "slide":
		# on one hip with the lead leg out, weapon still up
		_rot(hips, 0.55, 0, 0.16)
		_rot(torso, -0.30, 0, 0)
		_rot(head, -0.20, 0, 0)
		_rot(leg_l, 1.20, 0, 0.06)
		_rot(shin_l, -0.22, 0, 0)
		_rot(leg_r, 1.15, 0, -0.30)
		_rot(shin_r, -1.70, 0, 0)
		_gait_ph = 0.0
	elif in_action == "grab":
		# down on a knee and a hand to the ground
		pose_kneel(0.0, false)
		_rot(torso, -0.10 - 0.55 * sin(act * PI), 0, 0)
		_gait_ph = 0.0
	elif in_air != 0:
		pose_air(in_air > 0)
		_gait_ph = 0.0
	elif in_crouch:
		if armed:
			pose_kneel(_phase, moving)
		else:
			pose_crouch(_phase, moving)
		_gait_ph = _phase * 4.4
	elif moving and speed > 6.2:
		pose_run(_phase)
		_gait_ph = _phase * 8.6
	elif moving:
		pose_walk(_phase * 1.5)
		_gait_ph = _phase * 8.1
	else:
		if armed:
			pose_stance()
		else:
			pose_idle()
		_gait_ph = 0.0
	# a footfall each time the stride passes through the middle
	if moving and in_air == 0:
		var sg: float = signf(sin(_gait_ph))
		if sg != 0.0 and sg != _step_sign:
			_step_sign = sg
			steps += 1

	# Ease between poses. Each of those functions writes angles outright, so
	# stopping, crouching or leaving the ground was a single-frame snap.
	var kb: float = _k(delta, 18.0)
	for n in [hips, torso, head, leg_l, leg_r, shin_l, shin_r, arm_l, arm_r, fore_l, fore_r]:
		var q: Quaternion = (n as Node3D).quaternion
		var was: Quaternion = _blend.get(n, q)
		q = was.slerp(q, kb)
		_blend[n] = q
		(n as Node3D).quaternion = q

	if in_action == "throw":
		var wind: float = sin(clampf(act / 0.5, 0.0, 1.0) * PI * 0.5) if act < 0.5 \
			else 1.0 - smoothstep(0.5, 0.75, act) * 1.6
		torso.quaternion = torso.quaternion * Quaternion(Vector3.UP, wind * 0.45) \
			* Quaternion(Vector3.RIGHT, -0.18 * maxf(-wind, 0.0))
	_ready_s = lerpf(_ready_s, in_ready if armed else 0.0, _k(delta, 9.0))
	# With the weapon up the top half stops swinging. A walk throws the
	# shoulders about, and a man carrying a rifle at the ready holds his chest
	# still over legs that are doing all of it.
	if armed and not in_prone and in_action == "":
		var still: float = _ready_s * 0.8
		torso.quaternion = torso.quaternion.slerp(Quaternion(Vector3.RIGHT, -0.08), still)
		var hq: Quaternion = hips.quaternion
		hips.quaternion = hq.slerp(Quaternion(Vector3.RIGHT, hq.get_euler().x), still * 0.7)
	var long_gun: bool = armed and not gun.get("hand", false)
	var blade: float = (-0.40 if long_gun else 0.0) * _ready_s
	var look: float = in_pitch * lerpf(0.35, 1.0, _ready_s)

	# Layer the look and the lean over the gait.
	if in_prone and in_action == "" and in_air == 0:
		# lying down: no turning at the hips, and he looks by lifting the chest
		hips.position = Vector3(0.0, 0.20, 0.55)
		torso.transform.basis = Basis(Vector3.RIGHT, clampf(look, -0.2, 0.5) * 0.5) \
			* torso.transform.basis
		for f in [foot_l, foot_r]:
			(f as Node3D).transform.basis = Basis(Vector3.RIGHT, -1.2)
	else:
		hips.transform.basis = Basis(Vector3.UP, _hips_yaw) \
			* Basis(Vector3.BACK, -in_lean * 0.22) * hips.transform.basis
		hips.position = Vector3(in_lean * 0.13, HIP_Y, 0.0)
		torso.transform.basis = Basis(Vector3.UP, -_hips_yaw + blade) \
			* Basis(Vector3.RIGHT, look * 0.30) * torso.transform.basis
		head.transform.basis = Basis(Vector3.UP, -blade) * Basis(Vector3.RIGHT, look * 0.42)
		_plant_feet(delta)
	if in_action == "slide":
		hips.position.y = 0.36
	# the eye settles to where this stance puts it, with only a breath of the
	# stride left in it
	var want_eye: Vector3 = _eye_target()
	if moving and in_air == 0 and in_action == "":
		var bob: float = 0.011 * (1.0 - 0.85 * clampf(in_ads, 0.0, 1.0)) \
			* (1.8 if speed > 6.2 else 1.0)
		want_eye.y -= absf(sin(_gait_ph)) * bob
		want_eye.x += sin(_gait_ph) * bob * 0.5
	_eye_s = _eye_s.lerp(want_eye, _k(delta, 13.0))

	if not armed:
		return
	if in_action == "chute":
		# weapon on its sling, hands up on the risers: the one he is pulling
		# down on comes lower than the other
		_sling_weapon()
		var to_t := torso.global_transform.affine_inverse()
		var up: Vector3 = global_transform.basis.y
		var rt: Vector3 = global_transform.basis.x
		for sgn in [-1.0, 1.0]:
			var pull: float = clampf(in_lean * sgn, 0.0, 1.0)
			var riser: Vector3 = global_transform.origin + up * (2.02 - pull * 0.22) \
				+ rt * sgn * 0.27 - global_transform.basis.z * 0.02
			_two_bone(arm_r if sgn > 0.0 else arm_l, fore_r if sgn > 0.0 else fore_l,
				to_t * riser, ARM_1, ARM_2, Vector3(sgn * 0.9, -0.3, -0.5))
		return
	if in_action == "wall" or in_action == "ladder":
		_sling_weapon()
		_climb_limbs()
		return
	if in_action == "climb":
		_sling_weapon()
		_hands_to_ledge(act)
		return
	_place_weapon(delta, look, moving, speed)
	_hold_weapon()
	if in_action == "throw":
		# The support hand: off the weapon, to the pouch, back past the ear,
		# and through. The rifle stays in the other one.
		var tt := torso.global_transform.affine_inverse()
		var held: Vector3 = tt * (weapon_mount.global_transform * _grip_l())
		var pouch := Vector3(-0.17, 0.04, -0.15)
		var cocked := Vector3(-0.34, 0.60, 0.24)
		var thrown := Vector3(-0.10, 0.52, -0.56)
		var hand: Vector3
		if act < 0.22:
			hand = held.lerp(pouch, smoothstep(0.0, 0.22, act))
		elif act < 0.50:
			hand = pouch.lerp(cocked, smoothstep(0.22, 0.50, act))
		elif act < 0.68:
			hand = cocked.lerp(thrown, smoothstep(0.50, 0.68, act))
		else:
			hand = thrown.lerp(held, smoothstep(0.68, 1.0, act))
		_two_bone(arm_l, fore_l, hand, ARM_1, ARM_2,
			Vector3(-0.8, -0.2 if act > 0.3 and act < 0.7 else -1.0, 0.4))
	if in_action == "vault" or in_action == "grab":
		# the support hand leaves the weapon for the wall, or the ground
		var w: float = sin(act * PI)
		w = clampf(w * 1.6, 0.0, 1.0)
		var to_torso := torso.global_transform.affine_inverse()
		var on_gun: Vector3 = to_torso * (weapon_mount.global_transform * _grip_l())
		var side: Vector3 = global_transform.basis.x * (-0.22 if in_action == "vault" else 0.0)
		_two_bone(arm_l, fore_l, on_gun.lerp(to_torso * (in_point + side), w), ARM_1, ARM_2,
			Vector3(-0.45, -1.0, 0.15))

## How far apart a ladder's rungs are.
const RUNG := 0.30

## All four limbs onto what he is climbing. `in_point` is a point on the face
## in front of his chest. On a wall each limb reaches in turn, opposite hand
## and foot together; on a ladder they go to the rungs, which do not move, so a
## hand stays where it is until it lets go for the next one up -- that is what
## makes it read as climbing rather than as paddling at the wall.
func _climb_limbs() -> void:
	var up: Vector3 = global_transform.basis.y
	var right: Vector3 = global_transform.basis.x
	var to_torso := torso.global_transform.affine_inverse()
	var to_hips := hips.global_transform.affine_inverse()
	var ladder: bool = in_action == "ladder"
	var beat: float = _climb_ph * 3.4
	for lr in [-1.0, 1.0]:
		var sgn: float = lr
		# the hand on this side, and the foot on the other, move together
		var reach: float = sin(beat) * sgn
		var hand: Vector3 = in_point + right * sgn * (0.20 if ladder else 0.24) \
			+ up * reach * 0.19
		var foot: Vector3 = in_point + right * sgn * (0.13 if ladder else 0.17) \
			- up * (1.52 + reach * 0.19)
		if ladder:
			# onto the rungs: the nearest one, held until the next is nearer
			hand.y = snappedf(hand.y, RUNG)
			foot.y = snappedf(foot.y, RUNG)
		else:
			# the foot stands off the wall a little; it is on a hold, not in it
			foot += global_transform.basis.z * 0.06
		var arm: Node3D = arm_r if sgn > 0.0 else arm_l
		var fore: Node3D = fore_r if sgn > 0.0 else fore_l
		var leg: Node3D = leg_r if sgn > 0.0 else leg_l
		var shin: Node3D = shin_r if sgn > 0.0 else shin_l
		var boot: Node3D = foot_r if sgn > 0.0 else foot_l
		_two_bone(arm, fore, to_torso * hand, ARM_1, ARM_2, Vector3(sgn * 0.9, -0.5, 0.3))
		# knees out and forward, the way they go against a wall
		_two_bone(leg, shin, to_hips * (foot + up * SOLE), LEG_1, LEG_2, Vector3(sgn * 0.7, 0.3, -1.0))
		# toes to the wall, heel dropped
		boot.transform.basis = shin.global_transform.basis.orthonormalized().inverse() \
			* (global_transform.basis.orthonormalized() * Basis(Vector3.RIGHT, 0.25))

## Across the back, out of the way of both hands.
func _sling_weapon() -> void:
	var to_body := global_transform.affine_inverse()
	var back: Transform3D = to_body * torso.global_transform
	weapon_mount.transform = back * Transform3D(
		Basis(Vector3.BACK, 0.9) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0.02, 0.30, 0.17))

## Both hands on the edge while he hauls, then pressing down on it as the
## chest comes level.
func _hands_to_ledge(act: float) -> void:
	var to_torso := torso.global_transform.affine_inverse()
	var right: Vector3 = global_transform.basis.x
	for pair in [[arm_l, fore_l, -1.0], [arm_r, fore_r, 1.0]]:
		var sgn: float = pair[2]
		var hold: Vector3 = in_point + right * sgn * 0.22
		if in_action == "wall":
			# one hand going up as the other takes the weight
			hold += global_transform.basis.y * sgn * sin(_climb_ph * 3.4) * 0.17
		_two_bone(pair[0] as Node3D, pair[1] as Node3D, to_torso * hold, ARM_1, ARM_2,
			Vector3(sgn * 0.8, -0.4 if act < 0.6 else 0.6, 0.5))

## Stand him on what is actually there. The gait swings the legs through the
## air as if the ground were a table; this finds the ground under each foot,
## drops the pelvis until the lower one reaches, and bends the other knee.
func _plant_feet(delta: float) -> void:
	if in_action in ["wall", "ladder", "chute"]:
		hips.position.y = HIP_Y
		for f in [foot_l, foot_r]:
			(f as Node3D).transform.basis = Basis(Vector3.RIGHT, -0.3) if in_action == "chute" \
				else Basis.IDENTITY
		return
	if in_air != 0 or not is_inside_tree() or in_action in ["vault", "climb", "slide"]:
		_pelvis = lerpf(_pelvis, 0.0, _k(delta, 12.0))
		hips.position.y = HIP_Y + _pelvis
		for f in [foot_l, foot_r]:
			(f as Node3D).transform.basis = Basis(Vector3.RIGHT, -0.45)
		return
	var inv := global_transform.affine_inverse()
	var a_l: Vector3 = inv * foot_l.global_position
	var a_r: Vector3 = inv * foot_r.global_position
	# how far the gait left the lower foot off the floor, with the hips at
	# their nominal height
	# (the ankle rides half a boot above the sole)
	var lift: float = SOLE - minf(a_l.y, a_r.y)
	var g_l := 0.0
	var g_r := 0.0
	if in_foot_ik:
		g_l = _floor_under(global_transform * a_l)
		g_r = _floor_under(global_transform * a_r)
	_g_l = lerpf(_g_l, g_l, _k(delta, 16.0))
	_g_r = lerpf(_g_r, g_r, _k(delta, 16.0))
	# the pelvis comes down for the lower foot, never up for the higher one
	_pelvis = lerpf(_pelvis, lift + minf(minf(_g_l, _g_r), 0.0), _k(delta, 14.0))
	hips.position.y = HIP_Y + _pelvis
	var to_hips := hips.transform.affine_inverse()
	var swing_l: float = a_l.y + lift
	var swing_r: float = a_r.y + lift
	a_l.y = swing_l + _g_l
	a_r.y = swing_r + _g_r
	_two_bone(leg_l, shin_l, to_hips * a_l, LEG_1, LEG_2, Vector3(-0.14, 0.0, -1.0))
	_two_bone(leg_r, shin_r, to_hips * a_r, LEG_1, LEG_2, Vector3(0.14, 0.0, -1.0))
	# Flat on the ground when it is on the ground, toe down as it comes
	# through the air.
	var flat := global_transform.basis.orthonormalized() * Basis(Vector3.UP, _hips_yaw)
	for pair in [[foot_l, shin_l, swing_l], [foot_r, shin_r, swing_r]]:
		var toe: float = -clampf(float(pair[2]) * 3.0, 0.0, 0.75)
		var want: Basis = flat * Basis(Vector3.RIGHT, toe)
		(pair[0] as Node3D).transform.basis = \
			(pair[1] as Node3D).global_transform.basis.orthonormalized().inverse() * want

## How far above or below his own origin the floor is at a point.
func _floor_under(at: Vector3) -> float:
	var y: float = Sim.height_at(at.x, at.z)
	# a roof counts only if he could be standing on it
	y = maxf(y, Obstacles.floor_under(at.x, at.z, global_position.y + 0.1))
	return clampf(y - global_position.y, -0.45, 0.45)

## Where the weapon goes: built in the eye's frame, so that wherever he looks
## it is where the eye expects it.
func _place_weapon(delta: float, look: float, moving: bool, speed: float) -> void:
	var inv := global_transform.affine_inverse()
	var eye: Vector3 = _eye_s
	var hand: bool = gun.get("hand", false)
	var sight: float = gun.get("sight", 0.08)
	var hip := Vector3(0.09, -0.15, -0.36) if hand else Vector3(0.125, -0.150, -0.25)
	var ads := Vector3(0.0, -sight, -0.40) if hand else Vector3(0.0, -sight, -0.235)
	var low := Vector3(0.10, -0.42, -0.22) if hand else Vector3(0.03, -0.37, -0.20)
	if in_prone:
		# propped on the elbows: the weapon is up at the eye, not down at a
		# hip he is lying on, or the muzzle is in the dirt
		hip.y = -0.09
		low.y = -0.12
	var a: float = clampf(in_ads, 0.0, 1.0)
	a = a * a * (3.0 - 2.0 * a)
	var r: float = _ready_s
	var off: Vector3 = low.lerp(hip.lerp(ads, a), r)
	var yaw_r: float = (0.0 if hand else 0.70) * (1.0 - r)
	var pitch_r: float = (-0.95 if hand else -0.62) * (1.0 - r)
	var roll_r := 0.0
	var loose: float = 1.0 - 0.8 * a
	# the weapon has weight: it trails the view as it turns
	_sway = _sway.lerp(Vector2(clampf(in_turn.x, -6.0, 6.0), clampf(in_turn.y, -6.0, 6.0)),
		_k(delta, 9.0))
	off.x += _sway.x * 0.010 * loose
	off.y += _sway.y * 0.008 * loose
	yaw_r += _sway.x * 0.018 * loose
	pitch_r -= _sway.y * 0.014 * loose
	roll_r += _sway.x * 0.020 * loose
	# and it rides the stride
	if moving and in_air == 0:
		var amp: float = (0.013 if speed > 6.2 else 0.006) * loose
		off.y -= absf(sin(_gait_ph)) * amp
		off.x += sin(_gait_ph) * amp * 0.7
		roll_r += sin(_gait_ph) * amp * 1.4
	_breath += delta
	off.y += sin(_breath * 1.7) * 0.0022 * (1.0 - 0.5 * a)
	off.x += sin(_breath * 1.1) * 0.0014 * (1.0 - 0.5 * a)
	# recoil: back into the shoulder, muzzle up
	_kick = lerpf(_kick, 0.0, _k(delta, 15.0))
	off.z += _kick * (0.030 if not hand else 0.022)
	pitch_r += _kick * (0.035 if not hand else 0.16)
	off.y += _kick * 0.004
	# reloading: the weapon rolls over and tips up so the magazine well is
	# where the other hand can get at it
	if in_reload >= 0.0:
		var dip: float = sin(clampf(in_reload, 0.0, 1.0) * PI)
		dip = pow(dip, 0.6)
		off += Vector3(-0.03, -0.055, 0.02) * dip
		roll_r -= 0.55 * dip
		pitch_r += 0.30 * dip
		yaw_r += 0.18 * dip
	if is_instance_valid(_mag):
		_mag.visible = not (in_reload > 0.26 and in_reload < 0.70) \
			or gun.get("shells", false)
	# coming up out of the holster or off the sling
	_draw = move_toward(_draw, 0.0, delta * 3.2)
	var dr: float = _draw * _draw
	off.y -= 0.26 * dr
	pitch_r -= 0.9 * dr

	# up against a wall: muzzle to the sky, weapon drawn in to the chest
	var bl: float = in_block * in_block * (3.0 - 2.0 * in_block)
	off += Vector3(-0.02, -0.10, 0.10) * bl
	pitch_r += 1.15 * bl

	var aim := Basis(Vector3.BACK, -in_lean * 0.10) * Basis(Vector3.RIGHT, look)
	var wb: Basis = aim * Basis(Vector3.UP, yaw_r) * Basis(Vector3.RIGHT, pitch_r) \
		* Basis(Vector3.BACK, roll_r)
	var at: Vector3 = eye + aim * off
	# Arms are only so long. If the trigger hand cannot get there the weapon
	# comes to the hand, not the other way about -- otherwise looking straight
	# up leaves a rifle floating a hand's breadth beyond the fingers.
	# Where the shoulders are on average, not where this instant of the
	# stride has thrown them. They move with every step, so a weapon pulled in
	# to suit them exactly brings the stride into the sights by another road.
	var ks: float = _k(delta, 3.0)
	if _sh_r == Vector3.INF:
		ks = 1.0
		_sh_r = Vector3.ZERO
		_sh_l = Vector3.ZERO
	_sh_r = _sh_r.lerp(inv * arm_r.global_position, ks)
	_sh_l = _sh_l.lerp(inv * arm_l.global_position, ks)
	var sh_r: Vector3 = _sh_r
	var v: Vector3 = at + wb * Firearm.GRIP_R - sh_r
	var reach: float = ARM_1 + ARM_2 - 0.035
	var pull := Vector3.ZERO
	if v.length() > reach:
		pull = v.normalized() * (v.length() - reach)
	var sh_l: Vector3 = _sh_l
	var v2: Vector3 = at - pull + wb * _grip_l() - sh_l
	if v2.length() > reach and in_reload < 0.0:
		pull += v2.normalized() * (v2.length() - reach) * 0.85
	_pull = pull
	weapon_mount.transform = Transform3D(wb, at - _pull)

func _grip_l() -> Vector3:
	return gun.get("grip_l", Vector3(0.0, -0.05, -0.22))

## Both hands onto it. The support hand leaves the fore-end during a reload and
## goes to the magazine, to the pouch on his belt, and back.
func _hold_weapon() -> void:
	var to_torso := torso.global_transform.affine_inverse()
	var wm := weapon_mount.global_transform
	_two_bone(arm_r, fore_r, to_torso * (wm * Firearm.GRIP_R), ARM_1, ARM_2,
		Vector3(0.55, -1.0, 0.35))
	var grip: Vector3 = to_torso * (wm * _grip_l())
	if in_reload >= 0.0:
		var well: Vector3 = to_torso * (wm * Vector3(0.0, -0.16, -0.07))
		if gun.get("shells", false):
			well = to_torso * (wm * Vector3(0.0, -0.06, -0.10))
		var pouch := Vector3(-0.17, 0.04, -0.15)
		var p: float = clampf(in_reload, 0.0, 1.0)
		if p < 0.22:
			grip = grip.lerp(well, smoothstep(0.0, 0.22, p))
		elif p < 0.46:
			grip = well.lerp(pouch, smoothstep(0.22, 0.46, p))
		elif p < 0.72:
			grip = pouch.lerp(well, smoothstep(0.46, 0.72, p))
		else:
			grip = well.lerp(grip, smoothstep(0.72, 1.0, p))
	_two_bone(arm_l, fore_l, grip, ARM_1, ARM_2, Vector3(-0.45, -1.0, 0.15))

## Two bone IK with a pole. `root` and `mid` are a limb modelled down its own
## -Y; `target` is in the root's parent space; `pole` says which way the joint
## in the middle should point, in that same space. Arms and legs both come
## through here -- the only difference between an elbow and a knee is the pole.
func _two_bone(root: Node3D, mid: Node3D, target: Vector3, l1: float, l2: float,
		pole: Vector3) -> void:
	var v: Vector3 = target - root.position
	var dist: float = v.length()
	if dist < 1e-4:
		return
	var dir: Vector3 = v / dist
	var d: float = clampf(dist, absf(l1 - l2) + 0.02, l1 + l2 - 0.003)
	var p: Vector3 = pole - dir * pole.dot(dir)
	if p.length() < 1e-3:
		p = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	if p.length() < 1e-3:
		p = Vector3.RIGHT
	p = p.normalized()
	var ca: float = clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sa: float = sqrt(1.0 - ca * ca)
	var upper: Vector3 = dir * ca + p * sa
	var joint: Vector3 = root.position + upper * l1
	var lower: Vector3 = (root.position + dir * d - joint).normalized()
	var x_axis: Vector3 = dir.cross(p).normalized()
	var y_axis: Vector3 = -upper
	var b := Basis(x_axis, y_axis, x_axis.cross(y_axis))
	root.transform.basis = b
	var ll: Vector3 = b.inverse() * lower
	mid.rotation = Vector3(atan2(-ll.z, -ll.y), 0.0, 0.0)

## How far each hand is from where it should be on the current weapon, and how
## far each foot is from the floor: what the rig is for, as numbers.
func rig_error() -> Dictionary:
	var out := {"hand_r": 0.0, "hand_l": 0.0, "foot_l": 0.0, "foot_r": 0.0}
	if has_gun():
		var wm := weapon_mount.global_transform
		out["hand_r"] = (fore_r.global_transform * Vector3(0, -ARM_2, 0)).distance_to(
			wm * Firearm.GRIP_R)
		out["hand_l"] = (fore_l.global_transform * Vector3(0, -ARM_2, 0)).distance_to(
			wm * _grip_l())
	# on a wall: how far each hand and foot is from the face it should be on
	if in_action in ["wall", "ladder"]:
		var fwd: Vector3 = -global_transform.basis.z
		out["hand_r"] = absf((fore_r.global_transform * Vector3(0, -ARM_2, 0) - in_point).dot(fwd))
		out["hand_l"] = absf((fore_l.global_transform * Vector3(0, -ARM_2, 0) - in_point).dot(fwd))
		out["foot_l"] = absf((foot_l.global_position - in_point).dot(fwd))
		out["foot_r"] = absf((foot_r.global_position - in_point).dot(fwd))
		return out
	for pair in [["foot_l", foot_l], ["foot_r", foot_r]]:
		var at: Vector3 = (pair[1] as Node3D).global_position
		out[pair[0]] = at.y - SOLE - (global_position.y + _floor_under(at))
	return out
