class_name Walker
extends Node3D
## The player on foot. Moves over the analytic terrain (the world has no
## collision mesh), looks with the mouse, fights with what he is carrying, and
## can climb into any jet in the "boardable" group.
##
## One body and one rig in both views: first person puts the eye in the head and
## hides the head, third person pulls the camera back over the right shoulder.
## The weapon is where `Pilot.animate` puts it either way, so what you see in
## your hands is what anyone else sees you holding.

signal board_requested(jet)
signal hold_requested(jet)
signal station_requested(jet)
signal died(where)

const EYE := 1.62
const EYE_CROUCH := 1.02
const WALK := 4.0
const RUN := 7.4
const CROUCH := 2.1
const GRAV := 18.0
const JUMP := 6.6
const MAG := 30
const BASE_FOV := 74.0
const EYE_BACK := 0.27
## Shoulder width, near enough, for deciding what he fits through.
const BODY_R := 0.42

## What he is carrying is `Firearm.KIT`: one entry per weapon, each with its
## own magazine and its own spare rounds.
var kit_idx := 0
## What is actually on him: two long guns and a sidearm, as indices into the
## kit. Anything else has to be picked up off the road, and takes the place of
## whatever is in his hands when he does.
var slots: Array = [0, 1, 4]
## A can on the muzzle of everything that takes one. Quieter, no flash, and
## nobody three streets away turns round; a little off the muzzle velocity.
var suppressed := false

## What to carry: two long guns by name, and whether they are suppressed.
func set_loadout(primary: String, second: String, quiet: bool) -> void:
	var a: int = Firearm.index_of(primary)
	var b: int = Firearm.index_of(second)
	if b == a:
		b = (a + 1) % 4
	_mods = {}
	slots = [a, b, Firearm.index_of("pistol")]
	suppressed = quiet
	slot = 0
	rearm()
	_take_up(a, false)
var slot := 0
var _rounds: Array = []
var _spare: Array = []
var grenades := 2
## Which side he is on. Not called `team`: everything that hunts by `team`
## expects a vehicle on the other end of it.
var side := 0
## The match he is fighting in, if any -- told about noise and deaths.
var arena: Node = null
## Wounds close up when nobody has hit him for a while.
var regen := false

## Weapons as he has them fitted: sight, grip, magazine. Anything not in
## here is as it comes out of the table.
var _mods: Dictionary = {}

func spec_of(i: int) -> Dictionary:
	return _mods.get(i, Firearm.KIT[i % Firearm.KIT.size()])

func gun_spec() -> Dictionary:
	return spec_of(kit_idx)

## Deploy as a class: its two weapons, set up the way its owner left them.
func apply_class(c: Dictionary) -> void:
	var a: int = Firearm.index_of(String(c["primary"]))
	var b: int = Firearm.index_of(String(c["second"]))
	if b == a:
		b = (a + 1) % 4
	_mods = {a: Firearm.fitted(String(c["primary"]), c), b: Firearm.fitted(String(c["second"]), c)}
	slots = [a, b, Firearm.index_of("pistol")]
	suppressed = bool(c.get("quiet", false))
	slot = 0
	rearm()
	_take_up(a, false)

## An aircraft the launcher is looking at, and how long it has been.
var lock_target: Node3D = null
var lock_t := 0.0
const LOCK_TIME := 1.3
## Half the angle the seeker sees, in degrees: what the ring in the sight is.
const SEEK_CONE := 7.0
var _tone_t := 0.0

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
var spare := 0
var reloading := 0.0
var health := 100.0
var dead := false
var last_attacker: Node = null
## True while the deploy screen is up. He is already standing at the start
## line behind it, and the match only took him off the infantry's list: the
## armour, the aircraft and every shell and stray round could still find him,
## so a player could be killed while still choosing a class.
var sheltered := false

## Out of the fight until DEPLOY is pressed: nothing can pick him as a target
## and nothing that lands near him does any harm.
func shelter(on: bool) -> void:
	sheltered = on
	if on:
		remove_from_group("hittable")
	elif not dead and not is_in_group("hittable"):
		add_to_group("hittable")

## Sights held up without the button, for the harness to photograph.
var hold_ads := false
## How far into the sights he is, 0 hip and 1 shouldered.
var _ads := 0.0
## 1 with the weapon lifted clear of a wall it would otherwise be stuck into.
var _block := 0.0
var _lean := 0.0
var _eye := EYE
var _shot_cd := 0.0
var _recoil := 0.0
var _bloom := 0.0
var _fall_peak := 0.0
var _trigger_was := false
var _queued := 0.0
var _reload_span := 1.0
var _reload_mark := 0
var _reload_empty := false
var _pump_in := 0.0
var _cycle_snd := "pump"
var _sprint := false
var _steps_seen := 0
var _since_hit := 99.0
var _yaw_was := 0.0
var _pitch_was := 0.0
## Wind. A sprint spends it and standing gets it back.
var stamina := 1.0
var _winded := false
var _sprint_s := 0.0
## Sliding out of a sprint: seconds left, and which way.
var _slide := 0.0
var _slide_dir := Vector3.ZERO
## Going over or up something: "vault" or "climb", and the path it takes.
var _trav := ""
var _trav_t := 0.0
var _trav_span := 0.5
var _trav_a := Vector3.ZERO
var _trav_b := Vector3.ZERO
var _trav_top := 0.0
var _trav_grip := Vector3.ZERO
## Picking something up: how far through, and what.
var _grab_t := -1.0
var _grab_item: Node3D = null
var _near_drop: Node3D = null
## 0 standing, 1 crouched, 2 prone. Toggled, not held: on a Mac a click with
## CTRL down arrives as the *right* button, so a crouch that had to be held
## turned every shot fired from it into nothing at all.
var stance := 0
var prone := false
## On a wall: which structure, the face he is on, and the view he had before.
var _wall := -1
var _wall_n := Vector3.ZERO
var _wall_speed := 0.0
## On a ladder rather than a bare wall: no going sideways, and quicker.
var _ladder := false
var near_ladder: Array = []
## The harness holding W for him on a wall.
var test_climb := 0.0
var _third_was := false
const VAULT_MAX := 1.3            # higher than this is a climb
const CLIMB_MAX := 2.85           # higher than this is a wall
## What the HUD draws: how wide the weapon is wandering, and what just happened.
var spread_now := 0.0
var hit_t := 0.0
var hit_head := false
var kill_t := 0.0
var hurt_t := 0.0
var hurt_from := Vector3.ZERO

## Under canopy after an ejection. The pilot settles at a steady sink rate,
## steers the drift, and arrives without breaking anything.
var chute := false
const CHUTE_FALL := -6.0
const CHUTE_DRIFT := 7.0
var _canopy: MeshInstance3D = null
var _chute_turn := 0.0
var _chute_sink := -6.0
## Throwing: how far through, or negative.
var _throw_t := -1.0
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
	for i in Firearm.KIT.size():
		_rounds.append(0)
		_spare.append(0)
	rearm()
	_take_up(int(slots[0]), false)
	cam = Camera3D.new()
	cam.far = 45000.0
	cam.near = 0.03
	cam.fov = BASE_FOV
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	add_to_group("hittable")
	# The weapon is placed relative to the eye every tick. With the body
	# interpolated and the camera not, the two were a tick apart and the rifle
	# shivered in the hands whenever the view moved.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## A full load again: what a man has when he walks back out of the armoury.
func rearm() -> void:
	for i in Firearm.KIT.size():
		var g: Dictionary = spec_of(i)
		var carried: bool = slots.has(i)
		_rounds[i] = int(g["mag"]) if carried else 0
		_spare[i] = 0
		if carried:
			_spare[i] = int(g["mag"]) * int(g["spare"]) if not g.get("shells", false) \
				else int(g["spare"])
	grenades = 2
	ammo = int(_rounds[kit_idx])
	spare = int(_spare[kit_idx])
	reloading = 0.0

func _take_up(i: int, noisy := true) -> void:
	kit_idx = i
	body.equip(gun_spec(), suppressed)
	weapon = body.gun_node
	ammo = int(_rounds[kit_idx])
	spare = int(_spare[kit_idx])
	reloading = 0.0
	_shot_cd = 0.38                     # bringing it up takes a moment
	_bloom = 0.0
	_pump_in = 0.0
	if noisy and is_inside_tree():
		Sfx.play_ui(get_tree().current_scene, "cloth", -10.0, randf_range(0.9, 1.1))

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
		var mm := Sim.mouse_rel(e as InputEventMouseMotion)
		# slower through the sights, in proportion to how far they magnify
		var k: float = 0.0032 * lerpf(1.0, cam.fov / BASE_FOV, _ads)
		yaw -= mm.x * k
		pitch = clampf(pitch - mm.y * k, -1.4, 1.35)

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
	# riding something that is itself interpolated
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	Sim.report("aboard — walk aft off the ramp to jump", Sim.Ev.INFO)

## Step back out into the world, inheriting the aircraft velocity.
func exit_frame(scene: Node) -> void:
	if frame == null:
		return
	var world_xf := global_transform
	var carry := Vector3.ZERO
	if is_instance_valid(frame_owner) and "linear_velocity" in frame_owner:
		carry = frame_owner.linear_velocity
	# Walking off the ramp of an aeroplane at height is a parachute jump, and
	# it was simply a fall: you inherited the transport's velocity and hit the
	# ground at whatever that came to. A canopy above about fifty metres, which
	# is the height below which one would not open anyway.
	var agl: float = world_xf.origin.y - maxf(
		Sim.height_at(world_xf.origin.x, world_xf.origin.z), Sim.sea_at(world_xf.origin.x, world_xf.origin.z))
	var jump: bool = agl > 50.0
	frame.remove_child(self)
	scene.add_child(self)
	global_transform = world_xf
	yaw = rotation.y
	vel = carry
	frame = null
	frame_owner = null
	on_floor = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if jump:
		# a moment of freefall first, so it reads as stepping out rather than
		# being suspended from the tailgate
		_chute_at = agl - 40.0
		Sim.report("out the ramp — %d m, canopy on the way" % int(agl), Sim.Ev.INFO)

## Height at which the canopy opens after stepping off a ramp. Negative means
## there is no jump in progress.
var _chute_at := -1.0

func _physics_process(delta: float) -> void:
	var _pt := Sim.prof_at()
	_tick_walk_p(delta)
	Sim.prof_end(&"walk.tick", _pt)

## What the legs are being asked to do, in his own frame: x right, z forward.
func _wish() -> Vector3:
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := Vector3.ZERO
	wish += fwd * (Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up"))
	wish += right * (Sim.strength(&"roll_right") - Sim.strength(&"roll_left"))
	if wish.length() > 1.0:
		wish = wish.normalized()
	return wish

func _tick_walk_p(delta: float) -> void:
	if not cam.current or dead:
		return
	if frame != null:
		if not is_instance_valid(frame):
			frame = null
		else:
			_step_in_frame(delta)
			return
	# Falling out of a transport: a few seconds of freefall, then the canopy.
	if _chute_at >= 0.0:
		var agl2: float = global_position.y - maxf(
			Sim.height_at(global_position.x, global_position.z), Sim.sea_at(global_position.x, global_position.z))
		if agl2 <= _chute_at or agl2 < 60.0:
			_chute_at = -1.0
			set_chute(true)
			Sim.report("canopy", Sim.Ev.GOOD)
	if Sim.tapped(&"camera"):
		third = not third
	# Halfway over a wall there is nothing to decide: the move finishes.
	if _trav != "":
		_traverse(delta)
		return
	if _wall >= 0:
		_on_wall(delta)
		return
	var wish := _wish()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var crouch_tap: bool = Sim.tapped(&"crouch")
	# Dropping out of a sprint is a slide: the legs go out from under him and
	# he keeps the speed for a couple of paces, low, with the weapon coming up.
	if crouch_tap and _sprint and on_floor and _slide <= 0.0:
		_slide = 0.85
		_slide_dir = Vector3(vel.x, 0, vel.z).normalized()
		stance = 1
		Sfx.play_at(get_tree().current_scene, "land", global_position, -12.0, 0.8, 40.0)
	elif crouch_tap:
		stance = 0 if stance == 1 else 1
	if Sim.tapped(&"prone") and on_floor and _grab_t < 0.0:
		stance = 1 if stance == 2 else 2
		Sfx.play_at(get_tree().current_scene, "cloth", global_position, -9.0, 0.7, 40.0)
	# running is done standing up
	if stance > 0 and Sim.held(&"throttle_up") and wish.dot(fwd) > 0.5 and _slide <= 0.0:
		stance = 0
	_slide = maxf(_slide - delta, 0.0)
	if _slide > 0.0 and not on_floor:
		_slide = 0.0
	var want_crouch: bool = stance > 0
	prone = stance == 2 and on_floor
	crouching = want_crouch or _slide > 0.0
	# A sprint is forwards, upright and with the weapon down. Pulling the
	# trigger or bringing the sights up ends it, and so does running out of
	# wind -- after which he has to get some back before he can go again.
	if stamina <= 0.0:
		_winded = true
	elif stamina > 0.3:
		_winded = false
	_sprint = Sim.held(&"throttle_up") and not crouching and on_floor and not _winded \
		and wish.dot(fwd) > 0.5 and not Sim.held(&"ads") and not _trigger() \
		and _grab_t < 0.0
	stamina = clampf(stamina + delta * (-1.0 / 8.0 if _sprint else
		(1.0 / 4.5 if wish.length() < 0.1 else 1.0 / 7.0)), 0.0, 1.0)
	_sprint_s = lerpf(_sprint_s, 1.0 if _sprint else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var g: Dictionary = gun_spec()
	var speed: float = CROUCH if crouching else (RUN if _sprint else WALK)
	speed *= float(g["move"]) * lerpf(1.0, 0.62, _ads)
	if prone:
		speed = 0.95
	if _grab_t >= 0.0:
		speed *= 0.15
	if chute:
		speed = CHUTE_DRIFT          # under canopy you steer a drift, not a run
	var flat := Vector3(vel.x, 0, vel.z)
	if chute:
		# A canopy flies. It goes forward the way he is facing whether he
		# likes it or not, turns with the risers, and trades height for
		# distance: W lets it run and sink, S brakes it and holds it up.
		# It was a hover that drifted the way the keys said -- sideways and
		# backwards as readily as forwards -- which is a balloon.
		var ahead_in: float = Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up")
		var turn_in: float = Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
		_chute_turn = lerpf(_chute_turn, turn_in, clampf(delta * 3.0, 0.0, 1.0))
		yaw -= _chute_turn * 1.1 * delta
		var glide: float = 6.5 + ahead_in * 3.5
		flat = flat.lerp(Vector3(-sin(yaw), 0, -cos(yaw)) * glide, clampf(delta * 1.8, 0.0, 1.0))
		_chute_sink = CHUTE_FALL * (1.0 + ahead_in * 0.45) * (1.0 + absf(_chute_turn) * 0.35)
	elif _slide > 0.0:
		# carried, not walked: the speed bleeds off and he can barely steer it
		var k: float = _slide / 0.85
		flat = (_slide_dir + wish * 0.12).normalized() * lerpf(CROUCH, RUN * 1.12, k * k)
	else:
		flat = flat.lerp(wish * speed, clampf(delta * (13.0 if on_floor else 2.2), 0.0, 1.0))
	vel.x = flat.x
	vel.z = flat.z
	vel.y -= GRAV * delta
	if chute:
		# A canopy is a terminal velocity, not a force to fight: whatever the
		# seat threw you out with bleeds away and you settle to a steady sink.
		vel.y = lerpf(vel.y, _chute_sink, clampf(delta * 1.6, 0.0, 1.0))
	# A ladder within reach: walk onto it, or jump at it.
	near_ladder = TownSet.ladder_at(global_position)
	if not near_ladder.is_empty() and on_floor and _grab_t < 0.0 \
			and (Sim.tapped(&"interact") or (wish.dot(-(near_ladder[1] as Vector3)) > 0.6
				and Sim.held(&"jump"))):
		_take_ladder(near_ladder)
		return
	# Jump at something and he goes over it or up it rather than into it.
	if on_floor and Sim.tapped(&"jump") and _grab_t < 0.0:
		if stance > 0:
			# getting up comes first
			stance -= 1
		elif _begin_traverse(wish if wish.length() > 0.3 else fwd, false):
			return
		else:
			_slide = 0.0
			vel.y = JUMP
			on_floor = false
	var was := global_position
	global_position += vel * delta

	# Buildings are solid. Try the move; if it puts you inside a wall, keep
	# whichever axis of it is clear, so you slide along the face instead of
	# sticking to it. Anything low enough to get a foot on top of is not a
	# wall, which is what lets a barricade be jumped.
	var held_by: int = Obstacles.blocks(was, BODY_R)
	if held_by >= 0 and Obstacles.blocks(global_position, BODY_R) >= 0:
		# Already inside something's margin before he moved -- set down a hand's
		# breadth too close to a wall by a climb, say. Every step from there is
		# "into a wall", so he could not take one. Let him walk out: any move
		# that takes him further from what is holding him is allowed.
		var away: Vector3 = was - Obstacles.centre_of(held_by)
		away.y = 0.0
		if away.dot(Vector3(vel.x, 0.0, vel.z)) <= 0.0:
			var out: Vector3 = (Obstacles.face_of(held_by, was)["n"] as Vector3)
			global_position = Vector3(was.x, global_position.y, was.z) + out * delta * 1.5
	elif Obstacles.blocks(global_position, BODY_R) >= 0:
		var try_x := Vector3(global_position.x, global_position.y, was.z)
		var try_z := Vector3(was.x, global_position.y, global_position.z)
		if Obstacles.blocks(try_x, BODY_R) < 0:
			global_position = try_x
		elif Obstacles.blocks(try_z, BODY_R) < 0:
			global_position = try_z
		else:
			global_position = Vector3(was.x, global_position.y, was.z)
		# flat out into something waist high: he does not stop and think
		if (_sprint or _slide > 0.0) and on_floor and wish.dot(fwd) > 0.5 \
				and _begin_traverse(fwd, true):
			return
		# and jumped at a wall, he catches it
		if not on_floor and Sim.held(&"jump") and wish.dot(fwd) > 0.3 and not chute \
				and _begin_traverse(fwd, false):
			return

	# ground contact, with a landing that can hurt
	_fall_peak = minf(_fall_peak, vel.y)
	# A roof is a floor. `top_at` only answers for a point actually over a
	# footprint, and you cannot walk into the side of one, so this only ever
	# catches you coming down onto it.
	var ground := maxf(Sim.height_at(global_position.x, global_position.z),
		Obstacles.floor_under(global_position.x, global_position.z, global_position.y))
	if global_position.y <= ground:
		global_position.y = ground
		if not on_floor and _fall_peak < -13.0 and not chute:
			var hurt: float = (-_fall_peak - 13.0) * 7.5
			take_hit(hurt)
			Sfx.play_at(get_tree().current_scene, "thump", global_position, -10.0, 1.4)
		elif not on_floor and _fall_peak < -3.0:
			Sfx.play_at(get_tree().current_scene, "land", global_position,
				clampf(-16.0 - _fall_peak * 1.2, -16.0, -4.0), randf_range(0.9, 1.1), 50.0)
			_recoil -= 0.03
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
	rotation.y = yaw

	_reach_for(delta)
	_fight(delta)
	_animate(delta, flat, true)
	_view(delta, Basis.IDENTITY)

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
	_sprint = false
	var wish := _wish()
	var speed: float = CROUCH if crouching else (RUN * 0.6 if Sim.held(&"throttle_up") else WALK * 0.8)
	var flat := Vector3(vel.x, 0, vel.z).lerp(wish * speed, clampf(delta * 14.0, 0.0, 1.0))
	vel.x = flat.x
	vel.z = flat.z
	vel.y -= GRAV * delta
	if on_floor and Sim.tapped(&"jump"):
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
	_fight(delta)
	_animate(delta, flat, false)
	_view(delta, frame.global_transform.basis.orthonormalized())
	# G takes the gun station on a gunship; U steps back out of the hold
	if Sim.tapped(&"gunner_station") and is_instance_valid(frame_owner) \
			and frame_owner.spec.get("gunship", false):
		station_requested.emit(frame_owner)
	elif Sim.tapped(&"interact"):
		exit_frame(get_tree().current_scene)

## A click on the map, or any other screen with a pointer, is not a pull of
## the trigger -- and nor is the same click still held as that screen closes:
## the button has to come up once before it counts again.
var _ui_click := false

func _trigger() -> bool:
	var down: bool = Sim.held(&"foot_fire") or Sim.held(&"gun")
	if Sim.ui_pointer:
		_ui_click = true
		return false
	if _ui_click:
		_ui_click = down
		return false
	return down

# ------------------------------------------------------- over, up, and down for
## Is there something in the way that he can get over or onto? `auto` is the
## version that happens without being asked -- running flat out into a low
## wall -- and only ever vaults: nobody climbs a container by accident.
func _begin_traverse(dir_in: Vector3, auto: bool) -> bool:
	var dir := Vector3(dir_in.x, 0.0, dir_in.z).normalized()
	var feet := global_position
	var id := -1
	var face := 0.0
	for step in 5:
		face = 0.3 + step * 0.2
		id = Obstacles.blocks(feet + dir * face + Vector3(0, 0.25, 0), 0.05)
		if id >= 0:
			break
	if id < 0 and not auto:
		# nothing at his shins: perhaps something to catch hold of overhead
		face = 0.6
		id = Obstacles.blocks(feet + dir * face + Vector3(0, 2.0, 0), 0.05)
	if id < 0:
		return false
	var top: float = Obstacles.top_of(id)
	var rise: float = top - feet.y
	if rise < 0.45 or (auto and rise > VAULT_MAX):
		return false
	if rise > CLIMB_MAX:
		# too tall to haul up onto in one go, so it is a climb in the other
		# sense: onto the face of it, and up
		return _take_wall(id, feet + dir * face)
	var world := get_tree().current_scene
	_trav_top = top
	_trav_a = feet
	_trav_grip = feet + dir * face + Vector3(0, rise, 0)
	if rise <= VAULT_MAX:
		# Over it, if it is thin enough to get over: look for clear ground on
		# the far side within a stride and a half.
		for step in 9:
			var reach: float = face + 0.7 + step * 0.25
			var land: Vector3 = feet + dir * reach
			land.y = Sim.height_at(land.x, land.z)
			if land.y > feet.y + 0.5 or land.y < feet.y - 2.5:
				continue
			if Obstacles.blocks(land, BODY_R) < 0 \
					and Obstacles.floor_under(land.x, land.z, land.y + 1.0) < land.y + 0.3:
				# whatever is tallest along the way is what has to be cleared,
				# and if that is more than a vault this is not one
				var crest: float = top
				for k in 5:
					var q: Vector3 = feet.lerp(land, (k + 1) / 6.0)
					crest = maxf(crest, Obstacles.floor_under(q.x, q.z, feet.y + CLIMB_MAX))
				if crest - feet.y > VAULT_MAX:
					break
				_trav_top = crest
				_trav = "vault"
				_trav_b = land
				_trav_span = 0.42 + reach * 0.09
				_trav_t = 0.0
				vel = dir * (reach / _trav_span)
				Sfx.play_at(world, "cloth", feet, -9.0, 0.8, 40.0)
				return true
	if auto:
		return false
	# Onto it. There has to be somewhere to stand once he is up.
	# Whatever is a pace in from the edge is what he ends up standing on, and
	# that is not always the thing his shins found: a car's bonnet is the way
	# onto its roof.
	var up: Vector3 = feet + dir * (face + 0.55)
	up.y = Obstacles.floor_under(up.x, up.z, feet.y + CLIMB_MAX)
	rise = up.y - feet.y
	if rise < 0.45 or rise > CLIMB_MAX or Obstacles.blocks(up, BODY_R * 0.6) >= 0:
		return false
	_trav_top = up.y
	_trav_grip = feet + dir * face + Vector3(0, rise, 0)
	_trav = "climb"
	_trav_b = up
	_trav_span = 0.55 + rise * 0.36
	_trav_t = 0.0
	vel = Vector3.ZERO
	Sfx.play_at(world, "cloth", feet, -8.0, 0.7, 40.0)
	return true

## Carry him along the move. A vault is one arc over the top; a climb is up
## the face and then forward onto the edge.
func _traverse(delta: float) -> void:
	_trav_t += delta / _trav_span
	var t: float = clampf(_trav_t, 0.0, 1.0)
	var p: Vector3
	if _trav == "vault":
		var s: float = t * t * (3.0 - 2.0 * t)
		p = _trav_a.lerp(_trav_b, s)
		# straight line between the two ends, lifted to clear the top
		var base_y: float = lerpf(_trav_a.y, _trav_b.y, s)
		p.y = base_y + maxf(_trav_top + 0.12 - base_y, 0.0) * sin(t * PI)
	else:
		var lift: float = smoothstep(0.0, 0.68, t)
		var over: float = smoothstep(0.55, 1.0, t)
		var face: Vector3 = _trav_a.lerp(Vector3(_trav_b.x, _trav_a.y, _trav_b.z), 0.25)
		p = Vector3(lerpf(face.x, _trav_b.x, over), lerpf(_trav_a.y, _trav_b.y, lift),
			lerpf(face.z, _trav_b.z, over))
	global_position = p
	rotation.y = yaw
	on_floor = false
	crouching = false
	_slide = 0.0
	_sprint = false
	_shot_cd = maxf(_shot_cd, 0.15)
	_fight_idle(delta)
	body.in_action = _trav
	body.in_action_t = t
	body.in_point = _trav_grip
	_animate(delta, vel, false)
	_view(delta, Basis.IDENTITY)
	if t >= 1.0:
		var done := _trav
		_trav = ""
		body.in_action = ""
		on_floor = true
		_fall_peak = 0.0
		vel = Vector3(vel.x, 0.0, vel.z) * (0.6 if done == "vault" else 0.0)
		Sfx.play_at(get_tree().current_scene, "land", global_position, -13.0,
			randf_range(0.95, 1.1), 40.0)
		if done == "climb":
			_shot_cd = 0.3
			body._draw = 0.8         # the weapon comes back off the sling

# ------------------------------------------------------------------ on a wall
## Take hold of a face. Anything built can be climbed: a building, a crane's
## mast, a container stack. He goes where the keys say -- up, down, along --
## for as long as he stays on that face, and comes off it over the top, onto
## the ground, or by letting go.
func _take_wall(id: int, at: Vector3) -> bool:
	var f: Dictionary = Obstacles.face_of(id, at)
	var n: Vector3 = f["n"]
	var foot: Vector3 = f["foot"]
	# onto the plane of the face, a shoulder's width out from it
	var rel: Vector3 = global_position - foot
	var p: Vector3 = global_position - n * (rel.dot(n) - (BODY_R + 0.06))
	p.y = global_position.y
	_wall = id
	_wall_n = n
	_ladder = false
	_third_was = third
	third = true                    # you climb by looking at the wall, not out of it
	global_position = p
	vel = Vector3.ZERO
	on_floor = false
	stance = 0
	_slide = 0.0
	_sprint = false
	reloading = 0.0
	Sfx.play_at(get_tree().current_scene, "cloth", p, -8.0, 0.8, 40.0)
	return true

## Step onto a ladder: [where its foot is, which way it faces, structure].
func _take_ladder(l: Array) -> void:
	var foot: Vector3 = l[0]
	var n: Vector3 = l[1]
	var keep_y: float = global_position.y
	global_position = Vector3(foot.x, keep_y, foot.z) + n * 0.3
	if _take_wall(int(l[2]), foot - n * 0.2):
		_ladder = true
		# square on to it, whatever part of the face that is
		global_position = Vector3(foot.x, keep_y, foot.z) + n * (BODY_R + 0.06)

func _leave_wall() -> void:
	body.position = Vector3.ZERO
	_ladder = false
	_wall = -1
	third = _third_was
	body.in_action = ""
	body._draw = 0.8
	_shot_cd = 0.35
	_fall_peak = 0.0

func _on_wall(delta: float) -> void:
	var n := _wall_n
	var right := Vector3(n.z, 0.0, -n.x)            # his right, facing the wall
	var up_in: float = Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up") + test_climb
	var side_in: float = Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	var fast: bool = Sim.held(&"throttle_up") and stamina > 0.05
	stamina = clampf(stamina + delta * (-1.0 / 9.0 if fast else 1.0 / 12.0), 0.0, 1.0)
	var rate: float = 3.3 if fast else 2.2
	if _ladder:
		side_in = 0.0
		rate *= 1.3
	var p := global_position
	var f: Dictionary = Obstacles.face_of(_wall, p - n * (BODY_R + 0.06))
	var top: float = f["top"]
	var step: Vector3 = Vector3.UP * up_in * rate * delta + right * side_in * rate * 0.8 * delta
	# stay on the face: at its edge there is no more wall to hold
	var along: float = float(f["along"])
	var half: float = float(f["half"]) - 0.25
	var q: Vector3 = p + step
	var f2: Dictionary = Obstacles.face_of(_wall, q - n * (BODY_R + 0.06))
	if absf(float(f2["along"])) > half and absf(float(f2["along"])) > absf(along):
		q = p + Vector3.UP * up_in * rate * delta
	# something else built against this wall is in the way
	var other: int = Obstacles.blocks(q + Vector3(0, 0.9, 0), 0.2)
	if other >= 0 and other != _wall:
		q = p
		# Unless it is something overhead he can get onto: a crane's jib
		# across the top of its mast, a deck. Then that is the top.
		var lip: float = Obstacles.top_of(other)
		if up_in > 0.1 and lip > p.y and lip - p.y < 4.3:
			_trav_a = p
			_trav_b = Vector3(p.x, lip, p.z) - n * 0.25
			_trav_top = lip
			_trav_grip = Vector3(p.x, lip, p.z) - n * 0.3
			_trav = "climb"
			_trav_span = 1.3
			_trav_t = 0.0
			_leave_wall()
			body.in_action = "climb"
			return
	_wall_speed = (q - p).length() / maxf(delta, 0.001)
	global_position = q
	rotation.y = atan2(n.x, n.z)                     # chest to the wall
	# in close: the figure's arms are not long enough to climb at arm's length
	body.position = Vector3(0.0, 0.0, -0.17)
	crouching = false
	prone = false
	_fight_idle(delta)
	var world := get_tree().current_scene
	# over the top
	if q.y + 1.5 >= top and up_in > 0.1:
		var roof: Vector3 = q - n * (BODY_R + 0.7)
		roof.y = top
		_trav_a = q
		_trav_b = roof
		_trav_top = top
		_trav_grip = Vector3(q.x, top, q.z) - n * (BODY_R + 0.06)
		_trav = "climb"
		_trav_span = 0.75
		_trav_t = 0.0
		_leave_wall()
		body.in_action = "climb"
		return
	# back on the ground
	var floor_y: float = maxf(Sim.height_at(q.x, q.z), Obstacles.floor_under(q.x, q.z, q.y + 0.2))
	if q.y <= floor_y + 0.02 and up_in < 0.0:
		global_position.y = floor_y
		on_floor = true
		vel = Vector3.ZERO
		_leave_wall()
		return
	if Sim.tapped(&"jump"):
		# kicked off backwards
		vel = n * 4.6 + Vector3.UP * 4.2
		_leave_wall()
		Sfx.play_at(world, "cloth", q, -8.0, 1.0, 40.0)
		return
	if Sim.tapped(&"crouch"):
		vel = n * 0.6
		_leave_wall()
		return
	if _wall_speed > 0.4 and fmod(Time.get_ticks_msec() * 0.001, 0.42) < delta:
		Sfx.play_at(world, "step_a", q + Vector3(0, 1.6, 0) - n * 0.4, -17.0,
			randf_range(1.2, 1.5), 30.0)
	body.in_action = "ladder" if _ladder else "wall"
	body.in_action_t = 0.0
	body.in_point = q + Vector3(0, 1.70, 0) - n * (BODY_R + 0.04)
	body.in_move = Vector2(0.0, _wall_speed * (signf(up_in) if absf(up_in) > 0.05
		else (1.0 if absf(side_in) > 0.05 else 0.0)))
	body.in_crouch = false
	body.in_prone = false
	body.in_air = 0
	body.in_ready = 0.0
	body.in_ads = 0.0
	body.in_lean = 0.0
	body.in_reload = -1.0
	body.in_foot_ik = false
	_ads = 0.0
	body.animate(delta)
	_view(delta, Basis.IDENTITY)

## The timers that run whether or not the hands are free.
func _fight_idle(delta: float) -> void:
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	_recoil = lerpf(_recoil, 0.0, clampf(delta * 8.0, 0, 1))
	hit_t = maxf(hit_t - delta, 0.0)
	kill_t = maxf(kill_t - delta, 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	_since_hit += delta
	_trigger_was = _trigger()

## Weapons lying about. Find the nearest in reach; F goes down for it.
func _reach_for(delta: float) -> void:
	if _grab_t >= 0.0:
		_grab_t += delta / 0.75
		if _grab_t >= 0.5 and is_instance_valid(_grab_item):
			_take(_grab_item)
			_grab_item = null
		if _grab_t >= 1.0:
			_grab_t = -1.0
		return
	_near_drop = null
	var best := 2.1
	for n in get_tree().get_nodes_in_group("pickups"):
		if not is_instance_valid(n):
			continue
		var d: float = (n as Node3D).global_position.distance_to(global_position)
		if d < best:
			best = d
			_near_drop = n
	if _near_drop != null and on_floor and reloading <= 0.0 and Sim.tapped(&"pickup"):
		_grab_t = 0.0
		_grab_item = _near_drop
		_shot_cd = 0.8
		Sfx.play_at(get_tree().current_scene, "cloth", global_position, -9.0, 0.9, 40.0)

## It is in his hand now. A weapon he already carries is ammunition for it;
## anything else replaces what he was holding, which goes on the road in turn.
func _take(item: Node3D) -> void:
	var world := get_tree().current_scene
	var id: int = Firearm.index_of(String(item.get("kit")))
	var g: Dictionary = Firearm.KIT[id]
	var got: int = int(item.get("rounds"))
	_rounds[kit_idx] = ammo
	_spare[kit_idx] = spare
	if slots.has(id):
		_spare[id] = int(_spare[id]) + got
		spare = int(_spare[kit_idx])
		Sim.report("+%d rounds for the %s" % [got, String(g["name"])], Sim.Ev.INFO)
		Sfx.play_ui(world, "mag_in", -8.0)
	else:
		# a sidearm goes where the sidearm is, a long gun where a long gun is
		var into: int = slot
		if bool(g.get("hand", false)) != bool(Firearm.KIT[int(slots[into])].get("hand", false)):
			for i in slots.size():
				if bool(Firearm.KIT[int(slots[i])].get("hand", false)) == bool(g.get("hand", false)):
					into = i
					break
		var old: int = int(slots[into])
		Firearm.drop(world, String(Firearm.KIT[old]["id"]), int(_rounds[old]),
			global_position + Vector3(-sin(yaw), 0, -cos(yaw)) * 0.9)
		_spare[old] = 0
		_rounds[old] = 0
		slots[into] = id
		slot = into
		_rounds[id] = mini(got, int(g["mag"]))
		_spare[id] = int(_spare[id]) + maxi(got - int(g["mag"]), 0) \
			+ (int(g["mag"]) * 2 if not g.get("shells", false) else 10)
		_take_up(id)
		Sim.report("picked up the %s" % String(g["name"]), Sim.Ev.GOOD)
		Sfx.play_ui(world, String(g["work"]), -8.0)
	item.queue_free()

# -------------------------------------------------------------------- weapons
## Everything the hands do in a tick: change weapon, reload, throw, shoot.
func _fight(delta: float) -> void:
	_shot_cd = maxf(_shot_cd - delta, 0.0)
	_queued = maxf(_queued - delta, 0.0)
	_bloom = maxf(_bloom - delta * 0.035, 0.0)
	_recoil = lerpf(_recoil, 0.0, clampf(delta * 8.0, 0, 1))
	hit_t = maxf(hit_t - delta, 0.0)
	kill_t = maxf(kill_t - delta, 0.0)
	hurt_t = maxf(hurt_t - delta, 0.0)
	_since_hit += delta
	if regen and _since_hit > 5.0 and health < 100.0:
		health = minf(health + delta * 22.0, 100.0)
	var world := get_tree().current_scene
	var g: Dictionary = gun_spec()

	for wi in slots.size():
		if Sim.tapped(StringName("weapon_%d" % (wi + 1))) and wi != slot and _grab_t < 0.0:
			_rounds[kit_idx] = ammo
			_spare[kit_idx] = spare
			slot = wi
			_take_up(int(slots[wi]))
			return
	if Sim.tapped(&"grenade") and grenades > 0 and _shot_cd < 0.2 and _throw_t < 0.0 \
			and reloading <= 0.0:
		_throw_t = 0.0
		_shot_cd = 0.75
		Sfx.play_ui(world, "pin", -6.0)
	if _throw_t >= 0.0:
		# it leaves the hand when the arm comes through, not when the key
		# goes down
		var was_t := _throw_t
		_throw_t += delta / 0.62
		if was_t < 0.62 and _throw_t >= 0.62:
			_throw()
		if _throw_t >= 1.0:
			_throw_t = -1.0

	# The shotgun has to be worked between shots.
	if _pump_in > 0.0:
		_pump_in -= delta
		if _pump_in <= 0.0:
			Sfx.play_at(world, _cycle_snd, global_position + Vector3(0, 1.4, 0), -8.0,
				randf_range(0.95, 1.05), 60.0)

	var full: int = int(g["mag"])
	var pulled: bool = _trigger() and _block < 0.4
	var edge: bool = pulled and not _trigger_was
	_trigger_was = pulled
	if Sim.tapped(&"reload") and reloading <= 0.0 and ammo < full and spare > 0:
		_begin_reload(g)
	if reloading > 0.0:
		_work_reload(delta, g, edge)
		return

	# Down the sights it goes where it is pointed; from the hip it does not.
	var s: float = lerpf(float(g["hip"]), float(g["ads"]), _ads)
	var loose: float = 1.0 - 0.75 * _ads
	if prone:
		s *= 0.45
	elif crouching:
		s *= 0.7
	s += clampf(Vector2(vel.x, vel.z).length() / RUN, 0.0, 1.0) * float(g["hip"]) * 1.4 * loose
	if not on_floor:
		s += float(g["hip"]) * 2.0
	s += _bloom * loose
	spread_now = s

	if edge:
		_queued = 0.12
	_seek(delta, g)
	var want: bool = pulled if g["auto"] else _queued > 0.0
	if not want or _shot_cd > 0.0 or body._ready_s < 0.75:
		return
	_queued = 0.0
	if ammo <= 0:
		if edge or not g["auto"]:
			Sfx.play_ui(world, "dry", -6.0)
		if spare > 0:
			_begin_reload(g)
		else:
			_shot_cd = 0.25
		return
	_shot_cd = float(g["cd"])
	ammo -= 1
	_rounds[kit_idx] = ammo
	var from: Vector3 = body.muzzle_pos()
	# The round leaves the muzzle but it goes where the eye is looking: find
	# what is under the crosshair and send it there. Fired parallel to the
	# view instead, a rifle held beside the head puts every shot a hand's
	# width off, and a camera over the shoulder puts them a pace off.
	var look := -cam.global_transform.basis.z
	var eye := cam.global_position
	var skip: float = maxf((body.eye_pos() - eye).dot(look), 0.0) + 0.6
	var start: Vector3 = eye + look * skip
	# What is under the crosshair: the first wall, prop or piece of ground the
	# line of sight meets.
	#
	# Ground under the crosshair used to be pushed out to sixty metres, to
	# keep a fold in the road from catching the rounds -- which put the mark
	# underground, and from a muzzle lower than the eye every round aimed at
	# the road came down metres short of it. Lying down that is every shot.
	# The fold is dealt with below, for what it is.
	var seen: float = Firearm.sight_range(start, look, 600.0)
	var mark: Vector3 = start + look * seen
	# And held up for the drop over that distance, so it lands where it is
	# pointed. Laid flat on the crosshair, a rifle round at three hundred
	# metres is half a metre low, and along a line skimming the road that is
	# a hundred metres short.
	# Only for something actually there: with nothing under the crosshair the
	# "mark" is just how far the look was taken, and holding up for six
	# hundred metres lobs the round over the line of sight on the way.
	# What it falls under: a rifle round all of it, a rocket a little (its
	# motor holds it up), a guided missile none. The launcher table calls the
	# AT4 a "rocket" -- this asked for "law" and so held an AT4 up for a
	# rifle round's drop.
	var launcher := String(g.get("launcher", ""))
	var fall: float = 3.0 if launcher == "rocket" else (0.0 if launcher == "sam" else 9.81)
	var speed: float = float(g["muzzle"])
	# rounds and the 40 mm fly the whole model; the AT4's motor holds it up
	var air_k: float = Firearm.drag_of(g) if launcher != "rocket" else -1.0
	var aim: Vector3 = _lay(from, mark, speed, fall, seen >= 599.0, air_k)
	# a grenade launcher is laid well above the line of sight at range
	var off_line: float = 0.0 if launcher == "gl" else 0.5
	if mark.distance_to(from) < 1.6 or aim.dot(look) < off_line:
		aim = look
	elif _fouled(from, mark) and not _fouled(start, mark):
		# The muzzle cannot see what the eye can: a hump in the road a few
		# metres in front of a man lying down, the sill a rifle is rested on,
		# or anything below an over-the-shoulder view. The round goes from the
		# line of sight, which on the screen is clear all the way, instead of
		# into the ground in front of him.
		from = start
		aim = _lay(start, mark, speed, fall, seen >= 599.0, air_k)
	var quiet: bool = suppressed and Firearm.can_suppress(g)
	if g.has("launcher"):
		if String(g["launcher"]) == "sam":
			if not is_instance_valid(lock_target) or lock_t < LOCK_TIME:
				# no tone, no shot: it will not leave the tube without a lock
				ammo += 1
				_rounds[kit_idx] = ammo
				_shot_cd = 0.3
				Sfx.play_ui(world, "dry", -6.0)
				Sim.report("no lock — hold the sights on an aircraft", Sim.Ev.BAD)
				return
			Firearm.sam(world, self, side, from, look, lock_target)
			lock_t = 0.0
		elif String(g["launcher"]) == "gl":
			Firearm.grenade40(world, self, side, g, from, aim)
		else:
			Firearm.rocket(world, self, side, g, from, aim)
	else:
		Firearm.fire(world, self, side, g, from, aim, s, 1.0, quiet)
	if is_instance_valid(arena) and arena.has_method("heard"):
		# a suppressed shot is heard by whoever is in the same yard, no further
		arena.heard(from, side, 14.0 if quiet else 75.0)
	# The kick: most of it comes back on its own, some of it you have to pull
	# down yourself, and it never climbs quite straight.
	var k: float = float(g["kick"]) * (1.0 - 0.35 * _ads) \
		* (0.55 if prone else (0.8 if crouching else 1.0))
	pitch = minf(pitch + k * 0.45, 1.35)
	_recoil = minf(_recoil + k * 0.9, 0.12)
	yaw += randf_range(-1.0, 1.0) * float(g["side"]) * (1.0 - 0.3 * _ads)
	_bloom = minf(_bloom + float(g["hip"]) * 0.22, float(g["hip"]) * 1.6)
	body.kick(clampf(float(g["kick"]) * 34.0, 0.3, 1.5))
	# Working the action between shots: a pump, a bolt, or nothing -- a drum
	# launcher is loaded one round at a time but fires straight off the next.
	var cyc := String(g.get("cycle", "pump" if g.get("shells", false) else ""))
	if cyc != "":
		_cycle_snd = cyc
		_pump_in = 0.24 if cyc == "pump" else 0.40

## The seeker. With the missile up and the sights on something that flies,
## it takes a moment to settle; look away and it lets go.
## Which way to send a round so it comes down on the mark: the arc for its
## speed and what it falls under, or as far as it will go toward the mark if
## the mark is out of reach. With nothing under the crosshair there is no
## distance to allow for, and it goes the way it is pointed.
func _lay(from: Vector3, mark: Vector3, speed: float, fall: float, open_sky: bool,
		k := -1.0) -> Vector3:
	if open_sky or fall <= 0.0:
		return (mark - from).normalized()
	var d: Vector3 = Firearm.lob(from, mark, speed, fall)
	if d != Vector3.ZERO:
		if k >= 0.0:
			# The vacuum arc is the first guess; the round flies through air on
			# a turning planet, so the guess is corrected against that until it
			# comes down on the mark. Inside the first thirty metres the two are
			# the same and this costs a step or two.
			var sol: Dictionary = Ballistics.solve(from, mark, speed, k, d)
			if not sol.is_empty():
				return sol["dir"]
		return d
	var h := Vector3(mark.x - from.x, 0.0, mark.z - from.z)
	return (h.normalized() + Vector3.UP).normalized() if h.length() > 0.01 \
		else (mark - from).normalized()

## Whether something stands between two points: a wall or a prop anywhere
## along it, or the ground in the first stretch of it, where a line from a man
## lying down is closest to the road. The far end is the mark itself, which is
## on whatever it hit, so the last few per cent do not count.
func _fouled(a: Vector3, b: Vector3) -> bool:
	var span: float = a.distance_to(b)
	if span < 0.5:
		return false
	if Obstacles.segment(a, b) < 0.97:
		return true
	var dir: Vector3 = (b - a) / span
	var near: float = minf(span * 0.97, 25.0)
	var s := 0.4
	while s < near:
		var p: Vector3 = a + dir * s
		if p.y < Sim.height_at(p.x, p.z):
			return true
		s += 0.5
	return false

func _seek(delta: float, g: Dictionary) -> void:
	if String(g.get("launcher", "")) != "sam" or _ads < 0.6 or ammo <= 0:
		lock_target = null
		lock_t = 0.0
		return
	var eye := cam.global_position
	var look := -cam.global_transform.basis.z
	var best: Node3D = null
	var best_a := deg_to_rad(SEEK_CONE)
	Sim.hit_scan()
	for i in Sim.hit_nodes.size():
		if Sim.hit_team[i] == side:
			continue
		var n: Variant = Sim.hit_nodes[i]
		if not is_instance_valid(n) or not (n is Aircraft) or not n.is_alive():
			continue
		var to: Vector3 = (n as Node3D).global_position - eye
		if to.length() > 5500.0 or to.length() < 60.0:
			continue
		var ang: float = look.angle_to(to)
		if ang < best_a and Firearm.can_see(eye, (n as Node3D).global_position) \
				and Sim.line_of_sight(eye, (n as Node3D).global_position):
			best_a = ang
			best = n
	if best != lock_target:
		lock_t = 0.0
	lock_target = best
	if best != null:
		var before := lock_t
		lock_t += delta
		if before < LOCK_TIME and lock_t >= LOCK_TIME:
			Sfx.play_ui(get_tree().current_scene, "killmark", -6.0, 1.4)
		# The seeker's tone: a slow tick while it is working on something,
		# quick and higher once it has it. The eye is on the aeroplane, not on
		# the words under the ring, and this is what says "now".
		_tone_t -= delta
		if _tone_t <= 0.0:
			var has_it: bool = lock_t >= LOCK_TIME
			_tone_t = 0.27 if has_it else 0.6
			Sfx.play_ui(get_tree().current_scene, "beep", -14.0 if has_it else -20.0,
				2.0 if has_it else 1.0)
	else:
		_tone_t = 0.0

func _begin_reload(g: Dictionary) -> void:
	_reload_span = maxf(float(g["reload"]), 0.05)
	reloading = _reload_span
	_reload_mark = 0
	_reload_empty = ammo <= 0
	_pump_in = 0.0

## A reload is something the hands do in stages, each of which you can hear.
func _work_reload(delta: float, g: Dictionary, trigger_edge: bool) -> void:
	var world := get_tree().current_scene
	var at := global_position + Vector3(0, 1.35, 0)
	reloading -= delta
	var p: float = 1.0 - clampf(reloading / _reload_span, 0.0, 1.0)
	if g.get("shells", false):
		# one at a time into the tube, and the trigger breaks off the loading
		if _reload_mark == 0 and p > 0.55:
			_reload_mark = 1
			ammo += 1
			spare -= 1
			Sfx.play_at(world, "shell", at, -9.0, randf_range(0.95, 1.1), 40.0)
		if reloading <= 0.0:
			_rounds[kit_idx] = ammo
			_spare[kit_idx] = spare
			if ammo < int(g["mag"]) and spare > 0 and not trigger_edge and not _trigger():
				reloading = _reload_span
				_reload_mark = 0
			else:
				reloading = 0.0
				if _reload_empty and String(g.get("cycle", "pump")) != "":
					Sfx.play_at(world, String(g.get("cycle", "pump")), at, -8.0, 1.0, 60.0)
					_shot_cd = 0.3
		return
	if _reload_mark == 0 and p > 0.22:
		_reload_mark = 1
		Sfx.play_at(world, "mag_out", at, -9.0, randf_range(0.95, 1.05), 40.0)
	elif _reload_mark == 1 and p > 0.66:
		_reload_mark = 2
		Sfx.play_at(world, "mag_in", at, -8.0, randf_range(0.95, 1.05), 40.0)
	elif _reload_mark == 2 and p > 0.86:
		_reload_mark = 3
		if _reload_empty:
			Sfx.play_at(world, String(g["work"]), at, -8.0, randf_range(0.95, 1.05), 40.0)
	if reloading <= 0.0:
		reloading = 0.0
		var take: int = mini(int(g["mag"]) - ammo, spare)
		ammo += take
		spare -= take
		_rounds[kit_idx] = ammo
		_spare[kit_idx] = spare

func _throw() -> void:
	grenades -= 1
	var world := get_tree().current_scene
	var look := -cam.global_transform.basis.z
	var f := Firearm.Frag.new()
	f.team = side
	f.thrower = self
	f.vel = look * 17.0 + Vector3(0, 3.2, 0) + Vector3(vel.x, 0, vel.z) * 0.6
	world.add_child(f)
	# out of the hand that threw it
	var hand: Vector3 = body.fore_l.global_transform * Vector3(0, -Pilot.ARM_2, 0)
	f.global_position = hand if hand.distance_to(body.eye_pos()) < 1.2 \
		else body.eye_pos() + look * 0.5
	Sfx.play_at(world, "cloth", f.global_position, -8.0, 1.3, 30.0)

## A round of yours landed.
func hit_confirm(head: bool, killed: bool) -> void:
	hit_t = 0.22
	hit_head = head
	var world := get_tree().current_scene
	if killed:
		kill_t = 0.6
		Sfx.play_ui(world, "killmark", -9.0)
	else:
		Sfx.play_ui(world, "hitmark", -9.0, 1.25 if head else 1.0)

## True while looking through glass rather than over iron.
func scoped() -> bool:
	return not third and _ads > 0.9 and gun_spec().get("scope", false)

# ------------------------------------------------------------------ the figure
func _animate(delta: float, flat: Vector3, on_ground_ik: bool) -> void:
	var g: Dictionary = gun_spec()
	var moving := flat.length() > 0.4
	# Down the sights while the button is held, and never while reloading or
	# sprinting -- both of which take the weapon off the shoulder.
	# A muzzle that would be inside a wall is not pointed at it: the weapon
	# comes up out of the way, and cannot be fired until there is room.
	var jam := false
	if frame == null and not dead and not g.get("hand", false):
		var e0: Vector3 = body.eye_pos()
		var ld: Vector3 = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3.FORWARD
		jam = Obstacles.segment(e0, e0 + ld * (float(g["len"]) + 0.35)) < 1.0
	_block = move_toward(_block, 1.0 if jam else 0.0, delta * 6.0)
	body.in_block = _block
	var want_ads: float = 1.0 if ((Sim.held(&"ads") or hold_ads) and reloading <= 0.0
		and not _sprint and not chute and _block < 0.3) else 0.0
	_ads = move_toward(_ads, want_ads, delta * (7.5 if not g.get("scope", false) else 5.0))
	# Leaning out round a corner. Q and E are the rudder in a cockpit and
	# nothing at all on the ground.
	var want_lean: float = 0.0 if (_sprint or not on_floor or prone) else \
		Sim.strength(&"yaw_right") - Sim.strength(&"yaw_left")
	_lean = lerpf(_lean, clampf(want_lean, -1.0, 1.0), clampf(delta * 9.0, 0.0, 1.0))
	if is_instance_valid(cam):
		var zoom: float = float(g["fov"])
		if third:
			zoom = maxf(zoom, 44.0)
		# the world opens out a little at a run
		cam.fov = lerpf(BASE_FOV + 6.0 * _sprint_s, zoom, _ads * _ads * (3.0 - 2.0 * _ads))
	# his own frame: x to the right, y forward
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	body.in_move = Vector2(flat.dot(right), flat.dot(fwd))
	body.in_crouch = crouching and on_floor
	body.in_prone = prone and _slide <= 0.0
	body.in_air = 0 if on_floor else (1 if vel.y > 0.0 else -1)
	body.in_pitch = pitch + _recoil * 0.5
	body.in_ready = 0.0 if (_sprint and moving) or chute or _grab_t >= 0.0 else 1.0
	body.in_ads = _ads
	body.in_lean = _lean if not chute else _chute_turn
	if is_instance_valid(_canopy) and chute:
		# the canopy banks into the turn
		_canopy.rotation = Vector3(0.0, 0.0, -_chute_turn * 0.28)
	body.in_reload = (1.0 - clampf(reloading / _reload_span, 0.0, 1.0)) if reloading > 0.0 else -1.0
	if _trav == "":
		if _grab_t >= 0.0:
			body.in_action = "grab"
			body.in_action_t = _grab_t
			if is_instance_valid(_grab_item):
				body.in_point = _grab_item.global_position + Vector3(0, 0.08, 0)
		elif _slide > 0.0:
			body.in_action = "slide"
			body.in_action_t = 1.0 - _slide / 0.85
		elif chute:
			body.in_action = "chute"
		elif _throw_t >= 0.0:
			body.in_action = "throw"
			body.in_action_t = _throw_t
		else:
			body.in_action = ""
	body.in_turn = Vector2(wrapf(yaw - _yaw_was, -PI, PI), pitch - _pitch_was) / maxf(delta, 0.001)
	body.in_foot_ik = on_ground_ik
	_yaw_was = yaw
	_pitch_was = pitch
	body.position = Vector3.ZERO
	body.animate(delta)
	_eye = lerpf(_eye, 0.55 if prone else (EYE_CROUCH + 0.25 if crouching else EYE),
		clampf(delta * 9.0, 0, 1))
	# your own boots on the road
	if body.steps != _steps_seen:
		_steps_seen = body.steps
		if on_floor and moving:
			var loud: float = -9.0 if _sprint else (-22.0 if crouching else -15.0)
			Sfx.play_at(get_tree().current_scene, ["step_a", "step_b", "step_c"][randi() % 3],
				global_position, loud, randf_range(0.9, 1.12), 45.0)
			if _sprint and is_instance_valid(arena) and arena.has_method("heard"):
				arena.heard(global_position, side, 14.0)

## Where the camera is. `ref` is the frame the view angles are measured in:
## the world, or the hold of whatever he is riding in.
func _view(_delta: float, ref: Basis) -> void:
	body.visible = not scoped()
	body.set_head_visible(third)
	var up: Basis = ref * Basis(Vector3.UP, yaw)
	var look: Basis = up * Basis(Vector3.RIGHT, pitch + _recoil)
	if third:
		# Over the right shoulder, close enough to shoot from. A camera four
		# metres back and centred looked at the back of his head: the thing
		# you were aiming at was behind him.
		var pivot: Vector3 = global_position + ref * Vector3(0, _eye - 0.05, 0) \
			+ up * Vector3(_lean * 0.35, 0, 0)
		var boom := Vector3(0.62, 0.22, lerpf(2.6, 1.55, _ads))
		var want: Vector3 = pivot + look * boom
		# walls stop cameras too
		var clear: float = Obstacles.segment(pivot, want)
		if clear < 1.0:
			want = pivot.lerp(want, maxf(clear - 0.12, 0.08))
		if frame == null:
			want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 0.25)
		cam.global_transform = Transform3D(look, want)
	else:
		# One body, one animation set, both views: the eye is in the head.
		# Set a hand's breadth back along the line of sight, though. The
		# figure's arms are only so long, so the weapon sits closer to his
		# face than a screen can show without it filling the bottom third;
		# moving the eye straight back along its own axis keeps the sights on
		# the line and puts the rifle at the distance it looks right at.
		var roll: Basis = look * Basis(Vector3.BACK, -_lean * 0.10)
		cam.global_transform = Transform3D(roll, body.eye_pos() + look.z * EYE_BACK)

func hit_radius() -> float:
	return 0.9

func is_alive() -> bool:
	return not dead

## Rifle rounds ask this instead of `hit_radius`: a body and a head, not a ball
## at the ankles.
func bullet_hit(from: Vector3, to: Vector3) -> Vector2:
	var r: Vector2 = Firearm.prone_hit(global_position, yaw, from, to) if prone \
		else Firearm.body_hit(global_position, crouching, from, to)
	if r.x > 0.0:
		_last_head = r.x > 1.5
		_last_low = r.x < 0.9
	return r

## What the last thing to hit him was, for what is left of him afterwards.
var _last_amount := 0.0
var _last_head := false
var _last_low := false

func take_hit(amount: float, from: Node = null) -> void:
	if dead or sheltered:
		return
	health -= amount
	_last_amount = amount
	if amount >= 120.0:
		_last_head = false
	_since_hit = 0.0
	if from != null and is_instance_valid(from) and from is Node3D and from != self:
		last_attacker = from
		hurt_from = (from as Node3D).global_position
		hurt_t = 1.1
	if amount > 2.0 and is_inside_tree():
		Sfx.play_ui(get_tree().current_scene, "hurt", -5.0, randf_range(0.9, 1.1))
		_recoil += randf_range(0.01, 0.025)
	if health <= 0.0:
		_go_ragdoll(vel)

func _go_ragdoll(v: Vector3) -> void:
	dead = true
	# The same as anybody else: what killed him decides what is left.
	var from_dir := Vector3.ZERO
	if is_instance_valid(last_attacker) and last_attacker is Node3D and last_attacker != self:
		from_dir = (global_position - (last_attacker as Node3D).global_position).normalized()
	Ragdoll.fall(get_parent(), global_transform, Vector3(v.x, 0.0, v.z), Pilot.SUIT, Pilot.HELMET,
		_last_amount, _last_head, _last_low, from_dir, 26.0)
	body.visible = false
	# and he sees it: the view goes out over the shoulder as he goes down
	third = true
	if not is_instance_valid(arena):
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
	if frame == null and not near_ladder.is_empty() and _wall < 0:
		return "U   climb the ladder   (or SPACE while walking into it)"
	if frame == null and is_instance_valid(_near_drop) and _grab_t < 0.0:
		var id: int = Firearm.index_of(String(_near_drop.get("kit")))
		if slots.has(id):
			return "F   take the rounds from the %s" % String(Firearm.KIT[id]["name"])
		return "F   swap for the %s" % String(Firearm.KIT[id]["name"])
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
