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

## See `WalkerArms`.
var arms := WalkerArms.new(self)

## See `WalkerClimb`.
var climb := WalkerClimb.new(self)

signal board_requested(jet)
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

## Whether the weapon in his hands has one on it. Each weapon of a class is
## fitted on its own; anything picked up off the road, and the sidearm, goes
## by `suppressed`.
func is_quiet() -> bool:
	var g: Dictionary = gun_spec()
	return bool(g.get("quiet", suppressed)) and Firearm.can_suppress(g)

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
## The sights' adjustment on each weapon, by kit index: elevation up and
## windage right, in milliradians. A round leaves the bore so as to cross the
## line of sight at the weapon's zero, and these move where it goes from there
## -- a tenth of a mil a click on an optic, half a mil on irons.
var elev_mil := {}
## How far each slot's variable scope is wound in: 1 is its widest field,
## `zoom_max` its closest. Kept per weapon, like the turrets.
var scope_mag := {}
var wind_mil := {}
## For a harness: the zero to use instead of the weapon's own, in metres.
var zero_override := -1.0
## A ballistic vest's worth of protection left: half of every hit goes into it
## instead of into him until it is used up. See `SupplyCrate`.
var armour := 0.0
## How much of each hit the armour takes: half for a vest, most of it for the
## juggernaut's suit.
var armour_k := 0.5
## In the JUGGERNAUT suit: no sprinting, slower everywhere, the minigun.
var juggernaut := false

## Where a weapon is sighted in: the range at which the round crosses the line
## of sight. A battle zero for irons and dots, further out for a scope.
func zero_of(g: Dictionary) -> float:
	if zero_override > 0.0:
		return zero_override
	return float(g.get("zero", 300.0 if g.get("scope", false) else 100.0))

## A bore direction moved by what is dialled on weapon `i`: elevation about
## the line of sight's across axis, windage about up.
func turrets(aim: Vector3, look: Vector3, i: int) -> Vector3:
	var across: Vector3 = look.cross(Vector3.UP)
	if across.length() > 0.01:
		aim = aim.rotated(across.normalized(), float(elev_mil.get(i, 0.0)) * 0.001)
	return aim.rotated(Vector3.UP, -float(wind_mil.get(i, 0.0)) * 0.001).normalized()

## Where weapon `g` sends a round fired from `from` while the eye at `start`
## looks along `look`: across the line of sight at its zero, then the turrets.
func zeroed_aim(g: Dictionary, i: int, from: Vector3, start: Vector3, look: Vector3) -> Vector3:
	var lay_at: Vector3 = start + look * zero_of(g)
	var aim: Vector3 = arms._lay(from, lay_at, float(g["muzzle"]), 9.81, false, Firearm.drag_of(g))
	return turrets(aim, look, i)

## The size of one click on this weapon's sights, in mils.
func click_of(g: Dictionary) -> float:
	return 0.1 if (g.get("scope", false) or g.get("dot", false)) else 0.5

## Into the JUGGERNAUT suit: the plate, and the minigun in his hands in place of
## his long gun.
const JUGG_ARMOUR := 500.0
func suit_up() -> void:
	juggernaut = true
	armour = JUGG_ARMOUR
	armour_k = 0.8
	var mg: int = Firearm.index_of("minigun")
	_rounds[kit_idx] = ammo
	_spare[kit_idx] = spare
	var into: int = 0
	for i in slots.size():
		if not bool(Firearm.KIT[int(slots[i])].get("hand", false)):
			into = i
			break
	slots[into] = mg
	slot = into
	_rounds[mg] = int(Firearm.KIT[mg]["mag"])
	_spare[mg] = 0
	_take_up(mg)

## The modes a weapon's selector has, best first.
static func modes_of(g: Dictionary) -> Array:
	if g.has("modes"):
		return g["modes"]
	if not bool(g.get("auto", false)) or g.has("launcher"):
		return ["semi"]
	match String(g.get("id", "")):
		"lmg", "minigun", "aa20":
			return ["auto"]
		"glock":
			return ["auto", "semi"]
	return ["auto", "burst", "semi"]

func mode_now() -> String:
	var m: Array = modes_of(gun_spec())
	var cur := String(fire_mode.get(kit_idx, m[0]))
	return cur if m.has(cur) else String(m[0])

## How far the sights wander at rest with this weapon, in radians: a long
## scoped rifle most, a pistol held out at arm's length next, a carbine least.
static func sway_of(g: Dictionary) -> float:
	if g.has("sway"):
		return float(g["sway"])
	if g.get("scope", false):
		return 0.0060
	if g.get("hand", false):
		return 0.0035
	if g.has("launcher"):
		return 0.0040
	return 0.0025

const BREATH_HOLD := 4.0       # seconds of it
const BREATH_BACK := 5.0       # seconds to get it all back

## A tick of the sights wandering, of holding a breath, and of whether the
## weapon is rested on something.
func _steady(delta: float) -> void:
	var g: Dictionary = gun_spec()
	mounted = _rested(g)
	steadying = _ads > 0.5 and Sim.held(&"throttle_up") and not _gasp and breath > 0.0
	if steadying:
		breath = maxf(breath - delta / BREATH_HOLD, 0.0)
		if breath <= 0.0:
			_gasp = true
	else:
		breath = minf(breath + delta / BREATH_BACK, 1.0)
		if _gasp and breath > 0.35:
			_gasp = false
	var amp: float = sway_of(g)
	amp *= 0.45 if prone else (0.7 if crouching else 1.0)
	# out of wind, and under fire, it wanders more
	amp *= 1.0 + (1.0 - stamina) * 1.6 + suppression * 1.5
	if _gasp:
		amp *= 1.8
	if mounted:
		amp *= 0.15
	if steadying:
		amp *= 0.12
	# only on the sights: from the hip the spread is the wander
	amp *= clampf(_ads, 0.0, 1.0)
	_sway_t += delta
	var t: float = _sway_t
	var want := Vector2(sin(t * 0.83) * 0.85 + sin(t * 2.17 + 1.3) * 0.30,
		sin(t * 1.21 + 0.7) * 0.65 + sin(t * 3.05) * 0.22) * amp
	sway = sway.lerp(want, clampf(delta * 6.0, 0.0, 1.0))

## Whether the weapon is resting on something: lying down with a long gun,
## or on the sights with a ledge, a sill or a wall top just under the
## fore-end -- the right height to put it on.
func _rested(g: Dictionary) -> bool:
	if g.get("hand", false) or g.has("launcher") or _ads < 0.5:
		return false
	if prone:
		return true
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var eye: Vector3 = body.eye_pos()
	for reach in [0.45, 0.65]:
		var fore: Vector3 = eye + fwd * float(reach) + Vector3(0.0, -0.16, 0.0)
		var top: float = Obstacles.top_at(fore.x, fore.z)
		var gap: float = fore.y - top
		if gap > -0.08 and gap < 0.22:
			return true
	return false

func _through_armour(amount: float) -> float:
	if armour <= 0.0:
		return amount
	var taken: float = minf(amount * armour_k, armour)
	armour -= taken
	if armour <= 0.0:
		Sim.report("armour spent" if juggernaut else "vest spent", Sim.Ev.BAD)
	return amount - taken
## Stun grenades, thrown with their own key: see `Firearm.Frag.flash`.
var flashes := 2
## When he can see again, by the clock, and how long he was blinded for, for
## the picture to fade back by.
var _flash_until := 0.0
var flash_span := 1.0

## How suppressed he is, 0 to 1: rounds going close past, or into what he is
## behind. The weapon wanders, the sights come up slower, the edges of the
## world close in and his wounds do not start to mend until it stops. Lying
## down or kneeling he takes less of it.
var suppression := 0.0
var _supp_quiet := 9.0

func suppress(amount: float, _from: Vector3) -> void:
	if not is_alive():
		return
	var low: float = 0.55 if prone else (0.8 if crouching else 1.0)
	suppression = minf(suppression + amount * low, 1.0)
	_supp_quiet = 0.0
	# a flinch, the way a hit is one
	_recoil += randf_range(0.004, 0.010) * amount * 3.0

## A stun grenade went off where he could see it.
func blind(secs: float) -> void:
	if secs > flash_left():
		_flash_until = Time.get_ticks_msec() * 0.001 + secs
		flash_span = secs

## Seconds of not being able to see that he has left.
func flash_left() -> float:
	return maxf(_flash_until - Time.get_ticks_msec() * 0.001, 0.0)
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
	# each as its owner left that weapon, not both as he left the class
	var fit_a: Dictionary = Firearm.setup_for(c, String(c["primary"]))
	_mods = {a: Firearm.fitted(String(c["primary"]), fit_a),
		b: Firearm.fitted(String(c["second"]), Firearm.setup_for(c, String(c["second"])))}
	slots = [a, b, Firearm.index_of("pistol")]
	suppressed = bool(fit_a.get("quiet", false))
	slot = 0
	rearm()
	_take_up(a, false)

## An aircraft the launcher is looking at, and how long it has been.
var lock_target: Node3D = null
var lock_t := 0.0
const LOCK_TIME := 1.3
## Half the angle the seeker sees, in degrees: what the ring in the sight is.
const SEEK_CONE := 7.0

var cam: Camera3D
## Where the view would be with nobody looking round: what the rounds, the
## glasses and the throw go along. Holding ALT in third person swings the
## camera round him (`_free_yaw`, `_free_pitch`) without turning him, so
## shooting has to be taken from here and not from the camera.
var _aim_xf := Transform3D.IDENTITY
var _free_yaw := 0.0
var _free_pitch := 0.0
var _freeing := false
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
## Sights latched up: ALT and the right button put them up and leave them
## there, so a long watch down a street is not a finger held on a button. The
## same again takes them down, and so does breaking into a run. The right
## button on its own is still held to aim, as it always was.
var ads_latched := false
## How far into the sights he is, 0 hip and 1 shouldered.
var _ads := 0.0
## Field glasses, on B: the bomb bay lever in a cockpit and nothing at all out
## here. Up to the eyes they are eight power, and they come down again for
## anything the hands are wanted for -- the trigger, the sights, a reload, a run.
const BINO_FOV := 9.0
var binos := false
var _bino := 0.0
var _glass_rng := -1.0
var _glass_t := 0.0

## True while looking through the glasses.
func glassing() -> bool:
	return _bino > 0.9 and not dead

## How far off the ground under the cross is, or -1 for sky. Asked a few times
## a second, not every frame.
func glass_range() -> float:
	return _glass_rng

func _range_glass() -> void:
	var from: Vector3 = _aim_xf.origin
	var dir: Vector3 = -_aim_xf.basis.z
	var t := 4.0
	_glass_rng = -1.0
	while t < 12000.0:
		var q := from + dir * t
		if q.y <= maxf(Sim.height_at(q.x, q.z), Sim.sea_at(q.x, q.z)):
			_glass_rng = t
			break
		t += maxf(2.0, t * 0.03)
	var wall: float = Obstacles.segment(from, from + dir * 600.0)
	if wall < 1.0 and (_glass_rng < 0.0 or wall * 600.0 < _glass_rng):
		_glass_rng = wall * 600.0
## 1 with the weapon lifted clear of a wall it would otherwise be stuck into.
var _block := 0.0
var _lean := 0.0
var _eye := EYE
var _shot_cd := 0.0
var _recoil := 0.0
var _bloom := 0.0
## The sights wandering on their own -- heartbeat, breathing, arms that are
## not a tripod -- as an offset on where he is looking, yaw and pitch.
var sway := Vector2.ZERO
var _sway_t := 0.0
## Holding his breath to steady it: how much breath is left, 0 to 1, and
## whether he has run out and is shaking until he has some back.
var breath := 1.0
var _gasp := false
var steadying := false
## The weapon rested on something -- a sill, a wall top, the ground prone.
var mounted := false
## Fire select, by kit index: "auto", "burst" or "semi".
var fire_mode := {}
var _fall_peak := 0.0
var _trigger_was := false
var _reload_span := 1.0
var _pump_in := 0.0
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
var near_ladder: Array = []
## The harness holding W for him on a wall.
var test_climb := 0.0
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
	# A centimetre. On the sights the receiver and the stock run back under
	# the eye to the cheek, and at three the near plane sliced them open: a
	# hard-edged hole in the bottom of every sight picture, worst on the short
	# guns. The depth buffer is reversed, so the far ground does not pay for it.
	cam.near = 0.01
	# and `Planet.follow`, which sets every frame's planes, keeps it
	cam.set_meta(&"near_need", 0.01)
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
	flashes = 2
	suppression = 0.0
	_flash_until = 0.0
	ammo = int(_rounds[kit_idx])
	spare = int(_spare[kit_idx])
	reloading = 0.0

func _take_up(i: int, noisy := true) -> void:
	arms._pack_tube()
	kit_idx = i
	body.equip(gun_spec(), is_quiet())
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
	if on and _rigging == null:
		_rigging = MeshInstance3D.new()
		_rigging.name = "Rigging"
		_rigging.mesh = ImmediateMesh.new()
		_rigging.top_level = true
		_rigging.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(0.82, 0.80, 0.74)
		_rigging.material_override = lm
		add_child(_rigging)
	if _rigging != null:
		_rigging.visible = on
		if not on:
			(_rigging.mesh as ImmediateMesh).clear_surfaces()

## The rigging under the canopy: the suspension lines fanned down from the
## skirt to a riser each side, and the risers down through his hands to the
## harness at his shoulders. The canopy hung over him with nothing joining the
## two, so he was a man falling slowly under an orange dome.
var _rigging: MeshInstance3D = null
const RIG_LINES := 14
func _rig_lines() -> void:
	if not chute or _rigging == null or not is_instance_valid(_canopy) \
			or body.risers.size() < 2:
		return
	_rigging.global_transform = Transform3D.IDENTITY
	var im := _rigging.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var cxf: Transform3D = _canopy.global_transform
	var up: Vector3 = global_transform.basis.y
	for sgn in [-1.0, 1.0]:
		var hand: Vector3 = body.risers[0 if sgn < 0.0 else 1]
		# the confluence links, a hand's span over the grip
		var link: Vector3 = hand + up * 0.45
		var sh: Node3D = body.arm_l if sgn < 0.0 else body.arm_r
		# riser: harness at the shoulder, up through the hand to the link
		im.surface_add_vertex(sh.global_position)
		im.surface_add_vertex(hand)
		im.surface_add_vertex(hand)
		im.surface_add_vertex(link)
		# this side's half of the skirt
		for i in RIG_LINES:
			var a: float = PI * (float(i) + 0.5) / float(RIG_LINES)
			# x across the canopy: the left lines go to the left riser
			var rim := Vector3(sgn * sin(a) * 3.15, 0.0, cos(a) * 3.15)
			im.surface_add_vertex(link)
			im.surface_add_vertex(cxf * rim)
	im.surface_end()

func activate() -> void:
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(e: InputEvent) -> void:
	if Sim.menu_open:
		return
	if not cam.current or dead:
		return
	# On the sights the arrow keys are the turrets: up and down elevation,
	# left and right windage, a click at a time.
	if e is InputEventKey and (e as InputEventKey).pressed and _ads > 0.5 \
			and not gun_spec().has("launcher"):
		var kc: Key = (e as InputEventKey).keycode
		var click: float = click_of(gun_spec())
		var de := 0.0
		var dw := 0.0
		match kc:
			KEY_UP:
				de = click
			KEY_DOWN:
				de = -click
			KEY_RIGHT:
				dw = click
			KEY_LEFT:
				dw = -click
		if de != 0.0 or dw != 0.0:
			elev_mil[kit_idx] = clampf(float(elev_mil.get(kit_idx, 0.0)) + de, -20.0, 40.0)
			wind_mil[kit_idx] = clampf(float(wind_mil.get(kit_idx, 0.0)) + dw, -20.0, 20.0)
			Sfx.play_ui(get_tree().current_scene, "clink", -16.0, 1.6)
			get_viewport().set_input_as_handled()
			return
	# On a variable scope the wheel winds the power up and down.
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and _ads > 0.5:
		var bi: MouseButton = (e as InputEventMouseButton).button_index
		var top: float = float(gun_spec().get("zoom_max", 1.0))
		if top > 1.0 and (bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_DOWN):
			var m: float = float(scope_mag.get(kit_idx, 1.0))
			m = clampf(m * (1.2 if bi == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2), 1.0, top)
			# land on the ends exactly rather than a hair off them
			if absf(m - top) < 0.02:
				m = top
			elif absf(m - 1.0) < 0.02:
				m = 1.0
			scope_mag[kit_idx] = m
			Sfx.play_ui(get_tree().current_scene, "clink", -20.0, 2.2)
			get_viewport().set_input_as_handled()
			return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := Sim.mouse_rel(e as InputEventMouseMotion)
		if _freeing:
			_free_yaw = clampf(_free_yaw - mm.x * 0.0042, -PI, PI)
			_free_pitch = clampf(_free_pitch - mm.y * 0.0042, -1.1, 1.1)
			return
		# slower through the sights, in proportion to how far they magnify
		var k: float = 0.0032 * lerpf(1.0, cam.fov / BASE_FOV, maxf(_ads, _bino))
		yaw -= mm.x * k
		pitch = clampf(pitch - mm.y * k, -1.4, 1.35)

## Step into an aircraft hold: reparent, keep the world pose, zero the velocity.
func enter_frame(hold: Node3D, jet: Node) -> void:
	if hold == null or not is_instance_valid(hold):
		return
	var world_xf := global_transform
	get_parent().remove_child(self)
	hold.add_child(self)
	# Where he was, but standing square to the floor: keeping his world
	# orientation kept the bank the aircraft had as he stepped in, and with
	# only his heading set from then on he leaned with it for the whole ride.
	var local: Transform3D = hold.global_transform.affine_inverse() * world_xf
	var face: Vector3 = -local.basis.z
	var local_yaw: float = atan2(-face.x, -face.z) if Vector2(face.x, face.z).length() > 0.01 else 0.0
	transform = Transform3D(Basis(Vector3.UP, local_yaw), local.origin)
	frame = hold
	frame_owner = jet
	frame_half = hold.get_meta("half", Vector3(2.0, 2.2, 6.0))
	vel = Vector3.ZERO
	position.y = maxf(position.y, 0.0)
	yaw = local_yaw
	# riding something that is itself interpolated
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	Sim.report("aboard — walk aft off the ramp to jump", Sim.Ev.INFO)

## How far an open ramp comes down: see `JetFactory` and `Aircraft._animate`.
const RAMP_ANGLE := deg_to_rad(22.0)
var _boarding_ramp := false
## Standing on a transport's ramp from outside (see `_ramp_floor`).
var _on_ramp := false

## How far either side of the middle of `hold`'s ramp a man can stand, a
## fraction `t` of the way down it: the deck narrows to the tail
## (`JetFactory`), and he was held up over the air beside the narrow end.
static func _ramp_half(hold: Node, t: float, fallback: float) -> float:
	var r: Node = hold.get_node_or_null("Ramp") if hold != null else null
	if r == null or not r.has_meta("deck_w"):
		return fallback
	var w: PackedFloat32Array = r.get_meta("deck_w")
	var f: float = clampf(t, 0.0, 1.0) * float(w.size() - 1)
	var i: int = mini(int(f), w.size() - 2)
	return lerpf(w[i], w[i + 1], f - float(i)) - 0.3

## The ramp of a transport standing open with its hold behind it: a floor up
## into the aircraft. It had nothing under it, and the hold had no way in but
## a key pressed somewhere near the tail -- the ramp was a picture you walked
## through. Walked up, it puts him in the hold at the top. Another player's
## transport too, when its ramp is down on every screen.
## How far down the ramp of `hold` is tipped, part way open: from lying along
## the belly, shut (rising, so negative), to `RAMP_ANGLE` open. The same as the
## aircraft turns the ramp it draws.
static func _ramp_tilt(hold: Node, anim: float) -> float:
	var r: Node = hold.get_node_or_null("Ramp") if hold != null else null
	var shut: float = float(r.get_meta("shut_angle", 0.0)) if r != null else 0.0
	return lerpf(-shut, RAMP_ANGLE, anim)

func _ramp_floor(feet: Vector3) -> float:
	var best := -1e9
	for n in get_tree().get_nodes_in_group("boardable"):
		if not is_instance_valid(n) or not n.has_method("has_hold") or not n.has_hold() \
				or not n.get("ramp_open"):
			continue
		if (n as Node3D).global_position.distance_squared_to(feet) > 1600.0:
			continue
		var hold: Node3D = n.hold_node()
		if hold == null:
			continue
		var half: Vector3 = hold.get_meta("half", Vector3(2.0, 2.2, 6.0))
		var local: Vector3 = hold.global_transform.affine_inverse() * feet
		var run: float = half.z * 0.62
		if local.z < half.z - 0.6 or local.z > half.z + run + 0.3:
			continue
		if absf(local.x) > _ramp_half(hold, (local.z - half.z) / run, half.x * 0.85):
			continue
		var ang: float = _ramp_tilt(hold, float(n.get("ramp_anim")))
		var along: float = clampf(local.z - half.z, 0.0, run)
		var y: float = (hold.global_transform * Vector3(local.x, -along * tan(ang), local.z)).y
		# about at it, coming up from the ground or along it, not under it
		if feet.y > y + 1.0 or feet.y < y - 1.4:
			continue
		best = maxf(best, y)
		# at the top of it: aboard
		if local.z < half.z + 0.3 and not _boarding_ramp and frame == null:
			_boarding_ramp = true
			_step_aboard.call_deferred(hold, n)
	return best

func _step_aboard(hold: Node3D, jet: Node) -> void:
	_boarding_ramp = false
	if frame == null and is_instance_valid(hold) and is_instance_valid(jet):
		enter_frame(hold, jet)

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
	# upright in the world again, facing the way he was
	var face: Vector3 = -world_xf.basis.z
	var wy: float = atan2(-face.x, -face.z) if Vector2(face.x, face.z).length() > 0.01 else yaw
	global_transform = Transform3D(Basis(Vector3.UP, wy), world_xf.origin)
	yaw = wy
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
	var ahead: float = Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up")
	var strafe: float = Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	# on the sights the arrows are the turrets, and only WASD walks
	if _ads > 0.5:
		ahead = float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)) \
			+ Input.get_joy_axis(0, JOY_AXIS_LEFT_Y) * -1.0
		strafe = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)) \
			+ Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
		ahead = clampf(ahead if absf(ahead) > 0.15 else 0.0, -1.0, 1.0)
		strafe = clampf(strafe if absf(strafe) > 0.15 else 0.0, -1.0, 1.0)
	wish += fwd * ahead
	wish += right * strafe
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
	if Sim.tapped(&"bay"):
		binos = not binos
	# Halfway over a wall there is nothing to decide: the move finishes.
	if _trav != "":
		climb._traverse(delta)
		return
	if _wall >= 0:
		climb._on_wall(delta)
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
	# (on the sights SHIFT is holding his breath, not running)
	_sprint = Sim.held(&"throttle_up") and not crouching and on_floor and not _winded \
		and wish.dot(fwd) > 0.5 and not Sim.held(&"ads") and not _trigger() \
		and _grab_t < 0.0 and _ads < 0.5 and not hold_ads and not ads_latched
	stamina = clampf(stamina + delta * (-1.0 / 8.0 if _sprint else
		(1.0 / 4.5 if wish.length() < 0.1 else 1.0 / 7.0)), 0.0, 1.0)
	_sprint_s = lerpf(_sprint_s, 1.0 if _sprint else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var g: Dictionary = gun_spec()
	if juggernaut:
		_sprint = false           # a hundredweight of plate does not sprint
	var speed: float = CROUCH if crouching else (RUN if _sprint else WALK)
	speed *= float(g["move"]) * lerpf(1.0, 0.62, _ads)
	if juggernaut:
		speed *= 0.75
	if prone:
		speed = 0.95
	# getting down or getting up, he is not also going anywhere
	var down_s: float = body.prone_amount() if is_instance_valid(body) else 0.0
	if down_s > 0.02 and down_s < 0.98:
		speed = minf(speed, 0.6)
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
		climb._take_ladder(near_ladder)
		return
	# Jump at something and he goes over it or up it rather than into it.
	if on_floor and Sim.tapped(&"jump") and _grab_t < 0.0:
		if stance > 0:
			# getting up comes first
			stance -= 1
		elif climb._begin_traverse(wish if wish.length() > 0.3 else fwd, false):
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
				and climb._begin_traverse(fwd, true):
			return
		# and jumped at a wall, he catches it
		if not on_floor and Sim.held(&"jump") and wish.dot(fwd) > 0.3 and not chute \
				and climb._begin_traverse(fwd, false):
			return

	# ground contact, with a landing that can hurt
	_fall_peak = minf(_fall_peak, vel.y)
	# A roof is a floor. `top_at` only answers for a point actually over a
	# footprint, and you cannot walk into the side of one, so this only ever
	# catches you coming down onto it.
	# On the ground as it is drawn, not as it is sampled: see
	# `Terrain.drawn_ground`. The roads are laid on the same drawn ground, so
	# on a road he is on the road.
	var gx: float = global_position.x
	var gz: float = global_position.z
	# ...and whatever is within a step of his feet on top of it: see
	# `Terrain.foot_ground`.
	var ground: float = Terrain.foot_ground(gx, gz, global_position.y,
		cam.global_position if is_instance_valid(cam) else global_position)
	# and the ramp of a transport standing open, which is a floor to walk up
	var ramp_y: float = _ramp_floor(global_position)
	_on_ramp = ramp_y > ground and ramp_y > -1e8
	ground = maxf(ground, ramp_y)
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
	arms._fight(delta)
	# On a ramp the feet stand on the ramp. Left reaching for the ground, they
	# went down through it to the grass underneath on the way up; on the way
	# down, inside the hold's frame, they never reach for anything.
	_animate(delta, flat, not _on_ramp)
	_view(delta, Basis.IDENTITY)

	_scan()
	# Into the cockpit. A hold is not got into with a key: up the open ramp
	# on foot, or not at all (`_ramp_floor`).
	if target_jet and Sim.tapped(&"interact"):
		board_requested.emit(target_jet)

## Movement solved entirely in the hold's local space: flat floor at y = 0,
## walls at the hull, and the open ramp as the way out.
func _step_in_frame(delta: float) -> void:
	if Sim.tapped(&"camera"):
		third = not third
	if Sim.tapped(&"bay"):
		binos = not binos
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
	# The floor, and past the end of it the ramp going down: it was flat to
	# the end of the ramp and then nothing, so a man walked out level into
	# the air and dropped.
	var floor_y := 0.0
	if position.z > frame_half.z and is_instance_valid(frame_owner) and frame_owner.get("ramp_open"):
		floor_y = -(position.z - frame_half.z) * tan(_ramp_tilt(frame, float(frame_owner.get("ramp_anim"))))
		# and the ramp is narrower than the hold, and narrows as it goes
		var rl: float = maxf(_ramp_half(frame, (position.z - frame_half.z) / (frame_half.z * 0.62),
			lim), 0.2)
		position.x = clampf(position.x, -rl, rl)
	if position.y <= floor_y:
		position.y = floor_y
		vel.y = 0.0
		on_floor = true
	else:
		on_floor = position.y < floor_y + 0.02
	rotation.y = yaw
	# aft end: step off the open ramp
	var ramp_open: bool = is_instance_valid(frame_owner) and frame_owner.get("ramp_open")
	var aft := frame_half.z + (frame_half.z * 0.55 if ramp_open else 0.0)
	if position.z > aft:
		if ramp_open:
			exit_frame(get_tree().current_scene)
			return
		position.z = aft
	arms._fight(delta)
	_animate(delta, flat, false)
	_view(delta, frame.global_transform.basis.orthonormalized())
	# G takes the gun station on a gunship. There is no key out of the hold:
	# down the open ramp and off the end of it, as he came in.
	if Sim.tapped(&"gunner_station") and is_instance_valid(frame_owner) \
			and frame_owner.spec.get("gunship", false):
		station_requested.emit(frame_owner)

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
	# a crate is helped from, not picked up
	if item.has_method("resupply"):
		item.call("resupply", self)
		return
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
	if Sim.tapped(&"ads") and Sim.held(&"freelook"):
		ads_latched = not ads_latched
	if _sprint or chute or dead:
		ads_latched = false
	var want_ads: float = 1.0 if ((Sim.held(&"ads") or hold_ads or ads_latched)
		and reloading <= 0.0 and not _sprint and not chute and _block < 0.3) else 0.0
	if binos and (want_ads > 0.0 or _sprint or chute or reloading > 0.0 or _trav != ""
			or _throw_t >= 0.0):
		binos = false
	if binos:
		want_ads = 0.0
	_bino = move_toward(_bino, 1.0 if binos else 0.0, delta * 5.0)
	_ads = move_toward(_ads, want_ads, delta * (7.5 if not g.get("scope", false) else 5.0))
	# Leaning out round a corner. Q and E are the rudder in a cockpit and
	# nothing at all on the ground.
	var want_lean: float = 0.0 if (_sprint or not on_floor or prone) else \
		Sim.strength(&"yaw_right") - Sim.strength(&"yaw_left")
	_lean = lerpf(_lean, clampf(want_lean, -1.0, 1.0), clampf(delta * 9.0, 0.0, 1.0))
	if is_instance_valid(cam):
		var zoom: float = arms.scope_fov(g)
		if third:
			zoom = maxf(zoom, 44.0)
		# the world opens out a little at a run
		cam.fov = lerpf(BASE_FOV + 6.0 * _sprint_s, zoom, _ads * _ads * (3.0 - 2.0 * _ads))
		if _bino > 0.0:
			cam.fov = lerpf(cam.fov, BINO_FOV, _bino * _bino * (3.0 - 2.0 * _bino))
			_glass_t -= delta
			if _glass_t <= 0.0 and _bino > 0.9:
				_glass_t = 0.2
				_range_glass()
	# his own frame: x to the right, y forward
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	body.in_move = Vector2(flat.dot(right), flat.dot(fwd))
	body.in_crouch = crouching and on_floor
	body.in_prone = prone and _slide <= 0.0
	body.in_air = 0 if on_floor else (1 if vel.y > 0.0 else -1)
	# the weapon follows the whole of the climb the view takes, or the sights
	# sit below the crosshair while it settles
	body.in_pitch = pitch + _recoil
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
	_rig_lines()
	# the view goes down with the body: see `Pilot._prone_s`
	_eye = lerpf(_eye, lerpf(EYE_CROUCH + 0.25 if crouching else EYE, 0.55,
		body.prone_amount()), clampf(delta * 9.0, 0, 1))
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
func _view(delta: float, ref: Basis) -> void:
	# through the glasses there is no rifle in the way, and no shoulder either
	var glass: bool = _bino > 0.5
	body.visible = not arms.scoped() and not glass
	body.set_head_visible(third and not glass)
	var up: Basis = ref * Basis(Vector3.UP, yaw + sway.x)
	var look: Basis = up * Basis(Vector3.RIGHT, pitch + _recoil + sway.y)
	# ALT in third person: the camera goes round him, he keeps facing where he
	# was, and it swings back behind him when let go. Not through the sights,
	# and not while a screen has the pointer.
	_freeing = third and not glass and _ads < 0.5 and Sim.held(&"freelook") \
		and not Sim.ui_pointer and not dead
	if not _freeing:
		var back_k: float = 1.0 - exp(-8.0 * delta)
		_free_yaw = lerpf(_free_yaw, 0.0, back_k)
		_free_pitch = lerpf(_free_pitch, 0.0, back_k)
		if absf(_free_yaw) < 0.001 and absf(_free_pitch) < 0.001:
			_free_yaw = 0.0
			_free_pitch = 0.0
	if third and not glass:
		# Over the right shoulder, close enough to shoot from. A camera four
		# metres back and centred looked at the back of his head: the thing
		# you were aiming at was behind him.
		var pivot: Vector3 = global_position + ref * Vector3(0, _eye - 0.05, 0) \
			+ up * Vector3(_lean * 0.35, 0, 0)
		var boom := Vector3(0.62, 0.22, lerpf(2.6, 1.55, _ads))
		_aim_xf = Transform3D(look, _boom_end(pivot, look * boom))
		if _free_yaw == 0.0 and _free_pitch == 0.0:
			cam.global_transform = _aim_xf
		else:
			# Round him rather than round the shoulder: a little further out
			# and centred, so looking back shows him and not his ear.
			var free_k: float = clampf((absf(_free_yaw) + absf(_free_pitch)) / 0.4, 0.0, 1.0)
			var fpit: float = clampf(pitch + _free_pitch, -1.35, 1.35)
			var fl: Basis = up * Basis(Vector3.UP, _free_yaw) * Basis(Vector3.RIGHT, fpit)
			var fboom: Vector3 = boom.lerp(Vector3(0.0, 0.25, 2.9), free_k)
			cam.global_transform = Transform3D(fl, _boom_end(pivot, fl * fboom))
	else:
		# One body, one animation set, both views: the eye is in the head,
		# and only the head is hidden. The camera used to sit a hand's breadth
		# back along the line of sight to make the rifle look far enough away,
		# which put it inside the chest -- or behind the back looking down --
		# and the butt of every long gun in the lens. The weapon is now placed
		# out on the shoulder where it belongs (`Pilot.BUTT_ADS`), so the eye
		# can be where the eye is.
		var roll: Basis = look * Basis(Vector3.BACK, -_lean * 0.10)
		cam.global_transform = Transform3D(roll, body.eye_pos())
		_aim_xf = cam.global_transform

## Where a camera on the end of `arm` from `pivot` can actually go: walls stop
## it, and so does the ground.
func _boom_end(pivot: Vector3, arm: Vector3) -> Vector3:
	var want: Vector3 = pivot + arm
	var clear: float = Obstacles.segment(pivot, want)
	if clear < 1.0:
		want = pivot.lerp(want, maxf(clear - 0.12, 0.08))
	if frame == null:
		want.y = maxf(want.y, Sim.height_at(want.x, want.z) + 0.25)
	return want

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

## What the last thing to hurt him was, for the kill feed.
var last_cause := ""

func take_hit(amount: float, from: Node = null) -> void:
	if dead or sheltered:
		return
	last_cause = KillFeed.weapon_of(from)
	amount = _through_armour(amount)
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
	arms._pack_tube()
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
		# somebody else's aircraft: not its cockpit, and its hold is walked
		# into up the ramp, not boarded with a key
		if n.is_in_group("remote"):
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
		var way_out: String = "down the ramp to get out" if is_instance_valid(frame_owner) \
			and frame_owner.get("ramp_open") else "ramp shut"
		if is_instance_valid(frame_owner) and frame_owner.spec.get("gunship", false):
			return "G   gun station        %s" % way_out
		return way_out
	if target_jet == null:
		return ""
	var nm := "aircraft"
	if target_jet.has_method("display_name"):
		nm = target_jet.display_name()
	elif "spec" in target_jet:
		nm = String(target_jet.spec["name"])
	return "U   climb into %s" % nm

func _exit_tree() -> void:
	arms._pack_tube()

## See `WalkerArms.hit_confirm`.
func hit_confirm(head: bool, killed: bool) -> void:
	arms.hit_confirm(head, killed)

## See `WalkerArms.scope_fov`.
func scope_fov(g: Dictionary) -> float:
	return arms.scope_fov(g)

## See `WalkerArms.scoped`.
func scoped() -> bool:
	return arms.scoped()
