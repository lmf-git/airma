class_name Walker
extends Node3D
## On-foot pilot. Moves over the analytic terrain (the world has no collision
## mesh), looks with the mouse, and can climb into any jet in the "boardable"
## group.

signal board_requested(jet)
signal hold_requested(jet)
signal station_requested(jet)

const EYE := 1.62
const EYE_CROUCH := 1.02
const WALK := 4.2
const RUN := 8.6
const CROUCH := 2.1
const GRAV := 18.0
const JUMP := 6.6
const MAG := 30

signal died(where)

var cam: Camera3D
var body: Pilot
var weapon: Node3D
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var third := false
var on_floor := true
var crouching := false
var target_jet: Node = null
var ammo := MAG
var reloading := 0.0
var health := 100.0
var dead := false
var _anim := 0.0
var _bob := 0.0
var _eye := EYE
var _shot_cd := 0.0
var _recoil := 0.0
var _fall_peak := 0.0
var _flash: MeshInstance3D
## Under canopy after an ejection. The pilot settles at a steady sink rate,
## steers the drift, and arrives without breaking anything.
var chute := false
const CHUTE_FALL := -6.0
const CHUTE_DRIFT := 7.0
var _canopy: MeshInstance3D = null
# When standing inside an aircraft the walker becomes a child of that hold and
# all of its movement is solved in the hold's local frame. Riding the parent
# transform is what keeps occupants stable no matter what the jet does.
var frame: Node3D = null
var frame_half := Vector3.ZERO
var frame_owner: Node = null

func _ready() -> void:
	body = Pilot.new()
	body.build()
	add_child(body)
	weapon = body.add_weapon()
	_flash = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fm.albedo_texture = Effects.glow_texture()
	fm.albedo_color = Color(1.0, 0.85, 0.45, 0.95)
	qm.material = fm
	_flash.mesh = qm
	_flash.visible = false
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	weapon.add_child(_flash)
	_flash.position = Vector3(0, 0, -0.44)
	cam = Camera3D.new()
	cam.far = 45000.0
	cam.near = 0.12
	cam.fov = 74.0
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	add_to_group("hittable")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Put the canopy up or cut it away. The mesh is made the first time it is
## needed, so a pilot who never ejects never carries one.
func set_chute(on: bool) -> void:
	chute = on
	if on and _canopy == null:
		var dome := SphereMesh.new()
		dome.radius = 3.2
		dome.height = 3.2
		dome.is_hemisphere = true
		dome.radial_segments = 20
		dome.rings = 8
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.86, 0.53, 0.20)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.9
		dome.material = mat
		_canopy = MeshInstance3D.new()
		_canopy.name = "Canopy"
		_canopy.mesh = dome
		_canopy.position = Vector3(0.0, 4.6, 0.0)
		add_child(_canopy)
	if _canopy != null:
		_canopy.visible = on

func activate() -> void:
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if not cam.current or dead:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		yaw -= mm.relative.x * 0.0032
		pitch = clampf(pitch - mm.relative.y * 0.0032, -1.4, 1.35)

## Step into an aircraft hold: reparent, keep the world pose, zero the velocity.
func enter_frame(hold: Node3D, jet: Node) -> void:
	if hold == null or not is_instance_valid(hold):
		return
	var world_xf := global_transform
	get_parent().remove_child(self)
	hold.add_child(self)
	global_transform = world_xf
	frame = hold
	frame_owner = jet
	frame_half = hold.get_meta("half", Vector3(2.0, 2.2, 6.0))
	vel = Vector3.ZERO
	position.y = maxf(position.y, 0.0)
	yaw = rotation.y
	Sim.report("aboard — walk aft off the ramp to jump", Sim.Ev.INFO)

## Step back out into the world, inheriting the aircraft velocity.
func exit_frame(scene: Node) -> void:
	if frame == null:
		return
	var world_xf := global_transform
	var carry := Vector3.ZERO
	if is_instance_valid(frame_owner) and "linear_velocity" in frame_owner:
		carry = frame_owner.linear_velocity
	frame.remove_child(self)
	scene.add_child(self)
	global_transform = world_xf
	yaw = rotation.y
	vel = carry
	frame = null
	frame_owner = null
	on_floor = false

## Shoulder width, near enough, for deciding what he fits through.
const BODY_R := 0.42

func _physics_process(delta: float) -> void:
	if not cam.current or dead:
		return
	if frame != null:
		if not is_instance_valid(frame):
			frame = null
		else:
			_step_in_frame(delta)
			return
	if Sim.tapped(&"camera"):
		third = not third
	crouching = Sim.held(&"crouch")

	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := Vector3.ZERO
	wish += fwd * (Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up"))
	wish += right * (Sim.strength(&"roll_right") - Sim.strength(&"roll_left"))
	if wish.length() > 1.0:
		wish = wish.normalized()
	var running: bool = Sim.held(&"throttle_up") and not crouching
	var speed: float = CROUCH if crouching else (RUN if running else WALK)
	if chute:
		speed = CHUTE_DRIFT          # under canopy you steer a drift, not a run
	var flat := Vector3(vel.x, 0, vel.z)
	flat = flat.lerp(wish * speed, clampf(delta * (13.0 if on_floor else 2.2), 0.0, 1.0))
	vel.x = flat.x
	vel.z = flat.z
	vel.y -= GRAV * delta
	if chute:
		# A canopy is a terminal velocity, not a force to fight: whatever the
		# seat threw you out with bleeds away and you settle to a steady sink.
		vel.y = lerpf(vel.y, CHUTE_FALL, clampf(delta * 1.6, 0.0, 1.0))
	if on_floor and not crouching and Sim.tapped(&"fire"):
		vel.y = JUMP
		on_floor = false
	var was := global_position
	global_position += vel * delta

	# Buildings are solid. Try the move; if it puts you inside a wall, keep
	# whichever axis of it is clear, so you slide along the face instead of
	# sticking to it.
	if Obstacles.hit(global_position, BODY_R) >= 0:
		var try_x := Vector3(global_position.x, global_position.y, was.z)
		var try_z := Vector3(was.x, global_position.y, global_position.z)
		if Obstacles.hit(try_x, BODY_R) < 0:
			global_position = try_x
		elif Obstacles.hit(try_z, BODY_R) < 0:
			global_position = try_z
		else:
			global_position = Vector3(was.x, global_position.y, was.z)

	# ground contact, with a landing that can hurt
	_fall_peak = minf(_fall_peak, vel.y)
	# A roof is a floor. `top_at` only answers for a point actually over a
	# footprint, and you cannot walk into the side of one, so this only ever
	# catches you coming down onto it.
	var ground := maxf(Sim.height_at(global_position.x, global_position.z),
		Obstacles.top_at(global_position.x, global_position.z))
	if global_position.y <= ground:
		global_position.y = ground
		if not on_floor and _fall_peak < -13.0 and not chute:
			var hurt: float = (-_fall_peak - 13.0) * 7.5
			take_hit(hurt)
			Sfx.play_at(get_tree().current_scene, "thump", global_position, -10.0, 1.4)
		if chute:
			set_chute(false)
			Sim.report("down safe — canopy cut", Sim.Ev.GOOD)
		vel.y = 0.0
		on_floor = true
		_fall_peak = 0.0
	else:
		on_floor = global_position.y - ground < 0.05
	if dead:
		return

	_shoot(delta)

	# pose selection
	var moving := flat.length() > 0.4
	_anim += delta * clampf(flat.length() / WALK, 0.0, 2.2)
	rotation.y = yaw
	var aiming: bool = Sim.held(&"gun") or Sim.held(&"fire")
	if not on_floor:
		body.pose_air(vel.y > 0.0)
	elif crouching:
		body.pose_crouch(_anim, moving)
	elif moving and running:
		body.pose_run(_anim)
	elif moving:
		body.pose_walk(_anim * 1.5)
	else:
		body.pose_idle()
	if aiming and on_floor:
		body.pose_aim(pitch)
	else:
		body.aim_weapon(pitch * 0.35)
	_bob = lerpf(_bob, sin(_anim * 10.8) * (0.05 if (moving and running) else (0.03 if moving else 0.0)),
		clampf(delta * 8.0, 0, 1))
	# plant the feet: lift the body by however far the lowest foot has sunk, so
	# the figure never hovers and crouch height falls out of the pose itself
	body.position.y = lerpf(body.position.y, -body.lowest_foot(), clampf(delta * 18.0, 0, 1))
	_eye = lerpf(_eye, EYE_CROUCH if crouching else EYE, clampf(delta * 9.0, 0, 1))

	_recoil = lerpf(_recoil, 0.0, clampf(delta * 7.0, 0, 1))

	# One body, one animation set, both views. First person simply puts the eye
	# inside the head joint and hides the head so it does not fill the screen.
	body.visible = true
	body.set_head_visible(third)
	if third:
		var back := Vector3(sin(yaw), 0, cos(yaw))
		var want := global_position + Vector3(0, 1.9, 0) + back * 4.4 - Vector3(0, sin(pitch) * 2.4, 0)
		want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 0.7)
		cam.global_position = want
		cam.look_at(global_position + Vector3(0, _eye * 0.85, 0), Vector3.UP)
	else:
		var eye: Vector3 = body.head.global_transform * Vector3(0.0, 0.15, -0.08)
		cam.global_position = eye
		cam.global_transform.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch + _recoil)

	_scan()
	if target_jet and Sim.tapped(&"interact"):
		if target_jet.has_method("has_hold") and target_jet.has_hold() and target_jet.get("ramp_open"):
			hold_requested.emit(target_jet)
		else:
			board_requested.emit(target_jet)

## Movement solved entirely in the hold's local space: flat floor at y = 0,
## walls at the hull, and the open ramp as the way out.
func _step_in_frame(delta: float) -> void:
	if Sim.tapped(&"camera"):
		third = not third
	crouching = Sim.held(&"crouch")
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := Vector3.ZERO
	wish += fwd * (Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up"))
	wish += right * (Sim.strength(&"roll_right") - Sim.strength(&"roll_left"))
	if wish.length() > 1.0:
		wish = wish.normalized()
	var speed: float = CROUCH if crouching else (RUN * 0.6 if Sim.held(&"throttle_up") else WALK * 0.8)
	var flat := Vector3(vel.x, 0, vel.z).lerp(wish * speed, clampf(delta * 14.0, 0.0, 1.0))
	vel.x = flat.x
	vel.z = flat.z
	vel.y -= GRAV * delta
	if on_floor and Sim.tapped(&"fire"):
		vel.y = JUMP * 0.7
		on_floor = false
	position += vel * delta
	# hull limits
	var lim := frame_half.x - 0.35
	position.x = clampf(position.x, -lim, lim)
	position.z = maxf(position.z, -frame_half.z + 0.35)
	if position.y <= 0.0:
		position.y = 0.0
		vel.y = 0.0
		on_floor = true
	else:
		on_floor = position.y < 0.02
	rotation.y = yaw
	# aft end: step off the open ramp
	var ramp_open: bool = is_instance_valid(frame_owner) and frame_owner.get("ramp_open")
	var aft := frame_half.z + (frame_half.z * 0.55 if ramp_open else 0.0)
	if position.z > aft:
		if ramp_open:
			exit_frame(get_tree().current_scene)
			return
		position.z = aft
	_shoot(delta)
	var moving := flat.length() > 0.4
	_anim += delta * clampf(flat.length() / WALK, 0.0, 2.2)
	if not on_floor:
		body.pose_air(vel.y > 0.0)
	elif crouching:
		body.pose_crouch(_anim, moving)
	elif moving:
		body.pose_walk(_anim * 1.5)
	else:
		body.pose_idle()
	if Sim.held(&"gun"):
		body.pose_aim(pitch)
	_eye = lerpf(_eye, EYE_CROUCH if crouching else EYE, clampf(delta * 9.0, 0, 1))
	body.visible = true
	body.set_head_visible(third)
	if third:
		var back := Vector3(sin(yaw), 0, cos(yaw))
		cam.position = position + Vector3(0, 1.9, 0) + back * 3.2
		cam.look_at(global_transform * Vector3(0, _eye * 0.85, 0), frame.global_transform.basis.y)
	else:
		cam.global_position = body.head.global_transform * Vector3(0.0, 0.15, -0.08)
		cam.global_transform.basis = frame.global_transform.basis \
			* (Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch))
	# G takes the gun station on a gunship; U steps back out of the hold
	if Sim.tapped(&"gunner_station") and is_instance_valid(frame_owner) \
			and frame_owner.spec.get("gunship", false):
		station_requested.emit(frame_owner)
	elif Sim.tapped(&"interact"):
		exit_frame(get_tree().current_scene)

## Carbine: real projectiles with travel time and drop, fired from the muzzle.
func _shoot(delta: float) -> void:
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	if reloading > 0.0:
		reloading -= delta
		if reloading <= 0.0:
			ammo = MAG
		return
	if _flash.visible and _shot_cd < 0.085:
		_flash.visible = false
	if not Sim.held(&"gun"):
		return
	if ammo <= 0:
		reloading = 2.1
		Sfx.play_at(get_tree().current_scene, "servo", global_position, -12.0, 1.4)
		return
	if _shot_cd > 0.0:
		return
	_shot_cd = 0.105
	ammo -= 1
	var muzzle: Vector3 = _flash.global_position
	var aim := -cam.global_transform.basis.z
	var spread: float = 0.006 if crouching else (0.026 if vel.length() > 3.0 else 0.012)
	aim = (aim + Vector3(randf_range(-spread, spread), randf_range(-spread, spread),
		randf_range(-spread, spread))).normalized()
	Effects.tracer(get_tree().current_scene, muzzle, aim * 880.0, self, 18.0, 0)
	_flash.visible = true
	Effects.muzzle_flash(get_tree().current_scene, muzzle, aim, 0.55)
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	_recoil = minf(_recoil + 0.02, 0.10)
	Sfx.play_at(get_tree().current_scene, "rifle", muzzle, -6.0, randf_range(0.94, 1.08), 420.0)

func hit_radius() -> float:
	return 0.9

func is_alive() -> bool:
	return not dead

func take_hit(amount: float, _from: Node = null) -> void:
	if dead:
		return
	health -= amount
	if health <= 0.0:
		_go_ragdoll(vel)

func _go_ragdoll(v: Vector3) -> void:
	dead = true
	var rd := Ragdoll.new()
	rd.spawn_from(global_transform, v * 0.8 + Vector3(0, 1.5, 0))
	get_parent().add_child(rd)
	body.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	died.emit(global_position)

## Closest boardable jet within reach and roughly in front of you.
func _scan() -> void:
	target_jet = null
	# Reach is measured to the hull, not to the origin. Measuring to the origin
	# means a transport parked nearby beats the tank you are standing against,
	# because its centre happens to be closer than the tank's -- and on a big
	# enough aeroplane you can be under the wing and still out of "reach".
	var best := 4.5
	for n in get_tree().get_nodes_in_group("boardable"):
		if not is_instance_valid(n):
			continue
		var d: float = n.hull_distance(global_position) if n.has_method("hull_distance") \
			else global_position.distance_to(n.global_position) - 6.0
		if d < best:
			best = d
			target_jet = n

func prompt() -> String:
	if frame != null:
		if is_instance_valid(frame_owner) and frame_owner.spec.get("gunship", false):
			return "G   gun station        U   step out"
		return "U   step out"
	if target_jet != null and target_jet.has_method("has_hold") and target_jet.has_hold() \
			and target_jet.get("ramp_open"):
		return "U   walk into the hold"
	if target_jet == null:
		return ""
	var nm := "aircraft"
	if target_jet.has_method("display_name"):
		nm = target_jet.display_name()
	elif "spec" in target_jet:
		nm = String(target_jet.spec["name"])
	return "U   climb into %s" % nm
