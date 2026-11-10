class_name Firearm
## What a man on foot carries, and what happens when he pulls the trigger.
##
## The walker had a list of three "weapons" that were one carbine with the
## numbers changed: the same box in the hands, the same report, the same single
## round. Everything here is a weapon in its own right -- its own shape, its own
## sound, its own way of feeding -- and it is shared: the player and the AI
## rifleman fire through the same function, so a round does the same thing
## whoever sent it.
##
## Weapon space: the muzzle points down -Z and the origin sits on the bore line
## above the pistol grip, which is where the trigger hand closes.

const KIT := [
	{"id": "carbine", "name": "M4A1 CARBINE", "mag": 30, "spare": 5, "cd": 0.082,
		"auto": true, "dmg": 26.0, "muzzle": 880.0, "pellets": 1,
		"hip": 0.020, "ads": 0.0016, "fov": 46.0, "reload": 2.2, "kick": 0.011,
		"side": 0.006, "sound": "carbine", "db": -3.0, "work": "bolt",
		"len": 0.46, "stock": 0.24, "mag_len": 0.17, "sight": 0.085, "dot": true,
		"grip_l": Vector3(0.0, -0.045, -0.27), "move": 1.0, "reach": 38.0},
	{"id": "smg", "name": "MP7 SMG", "mag": 40, "spare": 4, "cd": 0.063,
		"auto": true, "dmg": 17.0, "muzzle": 620.0, "pellets": 1,
		"hip": 0.016, "ads": 0.0032, "fov": 54.0, "reload": 1.8, "kick": 0.007,
		"side": 0.006, "sound": "smg", "db": -5.0, "work": "bolt",
		"len": 0.26, "stock": 0.20, "mag_len": 0.20, "sight": 0.075, "dot": true,
		"grip_l": Vector3(0.0, -0.085, -0.15), "move": 1.08, "reach": 16.0},
	{"id": "shotgun", "name": "M870 SHOTGUN", "mag": 6, "spare": 18, "cd": 0.82,
		"auto": false, "dmg": 13.0, "muzzle": 400.0, "pellets": 9,
		"hip": 0.044, "ads": 0.034, "fov": 58.0, "reload": 0.52, "kick": 0.050,
		"side": 0.012, "sound": "shotgun", "db": 0.0, "work": "pump",
		"len": 0.52, "stock": 0.26, "mag_len": 0.0, "sight": 0.045, "dot": false,
		"shells": true,
		"grip_l": Vector3(0.0, -0.05, -0.33), "move": 0.97, "reach": 12.0},
	{"id": "dmr", "name": "M110 MARKSMAN", "mag": 10, "spare": 4, "cd": 0.30,
		"auto": false, "dmg": 64.0, "muzzle": 930.0, "pellets": 1,
		"hip": 0.034, "ads": 0.0004, "fov": 15.0, "reload": 2.9, "kick": 0.030,
		"side": 0.008, "sound": "dmr", "db": -1.0, "work": "bolt",
		"len": 0.62, "stock": 0.27, "mag_len": 0.12, "sight": 0.095, "scope": true,
		"grip_l": Vector3(0.0, -0.045, -0.30), "move": 0.92, "reach": 80.0},
	{"id": "pistol", "name": "M17 PISTOL", "mag": 17, "spare": 3, "cd": 0.13,
		"auto": false, "dmg": 21.0, "muzzle": 375.0, "pellets": 1,
		"hip": 0.018, "ads": 0.0050, "fov": 60.0, "reload": 1.4, "kick": 0.018,
		"side": 0.008, "sound": "pistol", "db": -5.0, "work": "bolt",
		"len": 0.14, "stock": 0.0, "mag_len": 0.0, "sight": 0.045, "dot": false,
		"hand": true,
		"grip_l": Vector3(-0.035, -0.075, 0.035), "move": 1.1, "reach": 14.0},
	# What a man on foot has for the things a rifle does nothing to. A tube
	# on the shoulder: one round up the spout, slow to reload, and heavy.
	{"id": "law", "name": "AT4 ROCKET", "mag": 1, "spare": 3, "cd": 0.6,
		"auto": false, "dmg": 110.0, "muzzle": 150.0, "pellets": 1,
		"hip": 0.030, "ads": 0.004, "fov": 40.0, "reload": 3.6, "kick": 0.060,
		"side": 0.010, "sound": "launch", "db": -2.0, "work": "bolt",
		"len": 0.55, "stock": 0.0, "mag_len": 0.0, "sight": 0.085, "dot": false,
		"launcher": "rocket",
		"grip_l": Vector3(0.0, -0.075, -0.22), "move": 0.86, "reach": 150.0},
	{"id": "stinger", "name": "STINGER SAM", "mag": 1, "spare": 2, "cd": 0.6,
		"auto": false, "dmg": 150.0, "muzzle": 30.0, "pellets": 1,
		"hip": 0.030, "ads": 0.004, "fov": 30.0, "reload": 4.4, "kick": 0.050,
		"side": 0.010, "sound": "launch", "db": -2.0, "work": "bolt",
		"len": 0.75, "stock": 0.0, "mag_len": 0.0, "sight": 0.095, "dot": false,
		"launcher": "sam",
		"grip_l": Vector3(0.0, -0.075, -0.24), "move": 0.84, "reach": 4000.0},
]

## The loadouts a man can deploy with. Each is a starting point: the gunsmith
## on the deploy screen changes any of it, and what it is changed to is what
## he carries for the rest of the session.
const CLASSES := [
	{"id": "assault", "name": "ASSAULT", "primary": "carbine", "second": "smg",
		"sight": "dot", "quiet": false, "grip": true, "mag": false,
		"note": "Carbine and a submachine gun. The one that does everything."},
	{"id": "at", "name": "ANTI-ARMOUR", "primary": "carbine", "second": "law",
		"sight": "dot", "quiet": false, "grip": false, "mag": false,
		"note": "A carbine and three rockets. Two will stop a tank, one anything lighter."},
	{"id": "aa", "name": "AIR DEFENCE", "primary": "smg", "second": "stinger",
		"sight": "dot", "quiet": false, "grip": false, "mag": false,
		"note": "A shoulder-launched missile. Hold the sights on an aircraft until it locks."},
	{"id": "marksman", "name": "MARKSMAN", "primary": "dmr", "second": "smg",
		"sight": "scope", "quiet": true, "grip": false, "mag": false,
		"note": "The long rifle, suppressed, and something for the stairs."},
	{"id": "breacher", "name": "BREACHER", "primary": "shotgun", "second": "smg",
		"sight": "irons", "quiet": false, "grip": true, "mag": true,
		"note": "For going through doors. Useless across a square."},
]
const SIGHTS := ["irons", "dot", "scope"]

## One weapon as a particular man has it set up: the table entry with his
## sight, grip and magazine worked into the numbers.
static func fitted(id: String, c: Dictionary) -> Dictionary:
	var g: Dictionary = spec(id).duplicate()
	if g.has("launcher") or g.get("hand", false):
		return g
	match String(c.get("sight", "dot")):
		"irons":
			g["dot"] = false
			g["scope"] = false
			g["fov"] = maxf(float(g["fov"]), 52.0)
			g["sight"] = minf(float(g["sight"]), 0.05)
		"scope":
			g["dot"] = false
			g["scope"] = true
			g["sight"] = 0.095
			# a marksman's glass on the marksman's rifle, a 4x on anything else
			g["fov"] = 15.0 if id == "dmr" else 21.0
		_:
			g["dot"] = true
			g["scope"] = false
			g["sight"] = maxf(float(g["sight"]), 0.075)
			g["fov"] = clampf(float(g["fov"]), 44.0, 54.0) if id != "dmr" else 40.0
	if c.get("grip", false):
		g["kick"] = float(g["kick"]) * 0.78
		g["side"] = float(g["side"]) * 0.65
		g["move"] = float(g["move"]) * 0.98
	if c.get("mag", false):
		g["mag"] = int(g["mag"]) + 2 if g.get("shells", false) else int(float(g["mag"]) * 1.5)
		g["reload"] = float(g["reload"]) * (1.0 if g.get("shells", false) else 1.14)
		g["mag_len"] = float(g["mag_len"]) * 1.4
		g["move"] = float(g["move"]) * 0.98
	return g


## Where the trigger hand closes, in weapon space. The same for all of them:
## that is what the origin means.
const GRIP_R := Vector3(0.0, -0.075, 0.04)

const SOUNDS := ["carbine", "smg", "shotgun", "dmr", "pistol", "shot_far", "dry",
	"mag_out", "mag_in", "bolt", "pump", "shell", "cloth", "step_a", "step_b",
	"step_c", "land", "suppressed", "impact_hard", "impact_soft", "ricochet", "snap", "whiz",
	"hit_body", "hitmark", "killmark", "hurt", "pin", "clink", "frag"]

static func spec(id: String) -> Dictionary:
	for k in KIT:
		if String(k["id"]) == id:
			return k
	return KIT[0]

static func index_of(id: String) -> int:
	for i in KIT.size():
		if String(KIT[i]["id"]) == id:
			return i
	return 0

const CAN_LEN := 0.16
## Everything but the shotgun takes a suppressor.
static func can_suppress(g: Dictionary) -> bool:
	return not g.get("shells", false) and not g.has("launcher")

## How far forward of the origin the muzzle is.
static func muzzle_z(g: Dictionary) -> float:
	return -(float(g["len"]) + 0.02)

# ------------------------------------------------------------------- the model
## Build one. The magazine is its own node so a reload can take it out, and the
## muzzle is a marker so nobody has to know how long the barrel is.
static func build(g: Dictionary, quiet := false) -> Node3D:
	var root := Node3D.new()
	root.name = String(g["id"])
	var dark := MeshKit.mat(Color(0.11, 0.11, 0.12), 0.55, 0.35)
	var poly := MeshKit.mat(Color(0.17, 0.165, 0.15), 0.8, 0.05)
	var ln: float = g["len"]
	var st := MeshKit.begin()
	var fu := MeshKit.begin()       # furniture: stock, grip, handguard
	if g.has("launcher"):
		# a tube, a grip under it and a sight on top
		MeshKit.cone(fu, 0.052, 0.052, -ln, 0.42, Vector3(0, 0.0, 0.0), 10)
		MeshKit.cone(st, 0.060, 0.060, -ln - 0.03, -ln + 0.05, Vector3(0, 0.0, 0.0), 10)
		MeshKit.cone(st, 0.062, 0.075, 0.36, 0.45, Vector3(0, 0.0, 0.0), 10)
		MeshKit.box(st, Vector3(0.03, 0.10, 0.04), Vector3(0, -0.095, 0.04))
		MeshKit.box(st, Vector3(0.03, 0.08, 0.04), Vector3(0, -0.085, -0.22))
		MeshKit.box(st, Vector3(0.012, 0.06, 0.05), Vector3(0, float(g["sight"]) - 0.03, -0.05))
		if String(g["launcher"]) == "sam":
			MeshKit.box(st, Vector3(0.07, 0.07, 0.10), Vector3(0, -0.07, -ln + 0.18))
			MeshKit.box(st, Vector3(0.09, 0.02, 0.09), Vector3(0, 0.075, -ln + 0.12))
	elif g.get("hand", false):
		MeshKit.box(st, Vector3(0.028, 0.034, ln + 0.06), Vector3(0, 0.014, -ln * 0.5 + 0.02))
		MeshKit.box(st, Vector3(0.008, 0.010, 0.008), Vector3(0, 0.036, -ln + 0.005))
		MeshKit.box(st, Vector3(0.016, 0.010, 0.006), Vector3(0, 0.036, 0.04))
		MeshKit.box(fu, Vector3(0.030, 0.105, 0.045), Vector3(0, -0.052, 0.035))
		MeshKit.box(fu, Vector3(0.026, 0.022, 0.07), Vector3(0, -0.008, -0.03))
	else:
		# receiver, barrel, and whatever the support hand holds
		MeshKit.box(st, Vector3(0.044, 0.062, 0.24), Vector3(0, 0.0, -0.03))
		MeshKit.box(st, Vector3(0.018, 0.018, ln * 0.55), Vector3(0, 0.004, -ln * 0.72))
		MeshKit.box(st, Vector3(0.026, 0.026, 0.05), Vector3(0, 0.004, -ln + 0.01))
		MeshKit.box(fu, Vector3(0.042, 0.050, ln * 0.52), Vector3(0, 0.0, -0.15 - ln * 0.26))
		MeshKit.box(fu, Vector3(0.034, 0.095, 0.042), Vector3(0, -0.068, 0.05))
		var sk: float = g["stock"]
		if sk > 0.0:
			MeshKit.box(st, Vector3(0.022, 0.026, sk * 0.6), Vector3(0, 0.004, 0.09 + sk * 0.3))
			MeshKit.box(fu, Vector3(0.036, 0.105, sk * 0.45), Vector3(0, -0.022, 0.09 + sk * 0.78))
		if g.get("shells", false):
			# the tube under the barrel and the fore-end that rides it
			MeshKit.box(st, Vector3(0.022, 0.022, ln * 0.62), Vector3(0, -0.028, -ln * 0.55))
			MeshKit.box(fu, Vector3(0.046, 0.042, 0.15), Vector3(0, -0.032, -0.33))
		var sy: float = g["sight"]
		if g.get("scope", false):
			MeshKit.cone(st, 0.021, 0.021, -0.19, 0.07, Vector3(0, sy, 0.0), 8)
			MeshKit.cone(st, 0.027, 0.027, -0.26, -0.19, Vector3(0, sy, 0.0), 8)
			MeshKit.box(st, Vector3(0.016, sy - 0.03, 0.03), Vector3(0, sy * 0.5 + 0.012, -0.10))
			MeshKit.box(st, Vector3(0.016, sy - 0.03, 0.03), Vector3(0, sy * 0.5 + 0.012, 0.02))
		elif g.get("dot", false):
			# a window to look through: two posts and a hood, open in the middle
			for sx in [-1.0, 1.0]:
				MeshKit.box(st, Vector3(0.005, 0.040, 0.045), Vector3(sx * 0.019, sy - 0.006, -0.05))
			MeshKit.box(st, Vector3(0.043, 0.005, 0.045), Vector3(0, sy + 0.016, -0.05))
			MeshKit.box(st, Vector3(0.043, 0.020, 0.06), Vector3(0, sy - 0.036, -0.05))
		else:
			MeshKit.box(st, Vector3(0.006, 0.014, 0.006), Vector3(0, sy - 0.007, -ln + 0.02))
			MeshKit.box(st, Vector3(0.018, 0.010, 0.008), Vector3(0, sy - 0.009, 0.02))
	var can: bool = quiet and can_suppress(g)
	if can:
		MeshKit.cone(st, 0.021, 0.021, -CAN_LEN, 0.0,
			Vector3(0, 0.004 if not g.get("hand", false) else 0.014, muzzle_z(g) + 0.01), 8)
	root.add_child(MeshKit.mi(MeshKit.finish(st, dark), "Metal"))
	root.add_child(MeshKit.mi(MeshKit.finish(fu, poly), "Furniture"))
	if g.get("dot", false):
		# the dot itself: small, bright, and the only lit thing on the weapon
		var dm := MeshKit.begin()
		MeshKit.box(dm, Vector3(0.0035, 0.0035, 0.001), Vector3(0, float(g["sight"]), -0.05))
		var lit := MeshKit.mat(Color(1.0, 0.1, 0.05), 0.4, 0.0, Color(1.0, 0.12, 0.05))
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(MeshKit.mi(MeshKit.finish(dm, lit), "Dot"))
	var mag_len: float = g["mag_len"]
	var mag := Node3D.new()
	mag.name = "Mag"
	root.add_child(mag)
	if mag_len > 0.0:
		var ms := MeshKit.begin()
		MeshKit.box(ms, Vector3(0.026, mag_len, 0.055), Vector3(0, -0.03 - mag_len * 0.5, -0.075))
		var mm := MeshKit.mi(MeshKit.finish(ms, dark), "M")
		mm.rotation.x = 0.12
		mag.add_child(mm)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mz := Node3D.new()
	mz.name = "Muzzle"
	mz.position = Vector3(0.0, 0.004 if not g.get("hand", false) else 0.014,
		muzzle_z(g) - (CAN_LEN if can else 0.0))
	root.add_child(mz)
	return root

# ---------------------------------------------------------------------- firing
## One pull of the trigger: the rounds, the flash, the report. `dir` is where
## the weapon is pointed; `spread` is how far it is allowed to wander from that.
static func fire(world: Node, shooter: Node, team: int, g: Dictionary,
		muzzle: Vector3, dir: Vector3, spread: float, dmg_scale := 1.0,
		quiet := false) -> void:
	if world == null or not world.is_inside_tree():
		return
	var n: int = int(g["pellets"])
	var basis := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	for i in n:
		# a disc, not a box: the corners of a square spread are 40% further
		# out than its sides, and a shotgun pattern does not have corners
		var a := randf() * TAU
		var r: float = sqrt(randf()) * spread
		var d: Vector3 = (basis * Vector3(cos(a) * r, sin(a) * r, -1.0)).normalized()
		Effects.bullet(world, muzzle, d * float(g["muzzle"]) * randf_range(0.97, 1.03)
			* (0.93 if quiet else 1.0),
			shooter, float(g["dmg"]) * dmg_scale, team,
			0.55 if n > 1 else 1.0, 0.45 if n > 1 else 1.4)
	if quiet:
		# no flash to speak of, no crack, and nothing that carries
		Effects.muzzle_flash(world, muzzle + dir * 0.05, dir, 0.045)
		Sfx.play_at(world, "suppressed", muzzle, float(g["db"]) - 4.0,
			randf_range(0.92, 1.08) * (1.25 if g.get("hand", false) else 1.0), 70.0)
		return
	Effects.muzzle_flash(world, muzzle + dir * 0.12, dir, 0.16 if n == 1 else 0.24)
	report(world, g, muzzle)

## What a shot sounds like from where the listener is. Near, it is the weapon;
## from a few streets off the crack has gone and the thump is all that is left.
static func report(world: Node, g: Dictionary, at: Vector3) -> void:
	var ear := world.get_viewport().get_camera_3d()
	var far: float = 0.0 if ear == null else ear.global_position.distance_to(at)
	var db: float = g["db"]
	if far < 110.0:
		Sfx.play_at(world, String(g["sound"]), at, db, randf_range(0.95, 1.06), 320.0)
	if far > 60.0:
		Sfx.play_at(world, "shot_far", at, db + 5.0 + clampf((far - 60.0) / 50.0, 0.0, 1.0) * 3.0 - 3.0,
			randf_range(0.85, 1.1), 900.0)

# -------------------------------------------------------------------- grenade
## A fragmentation grenade. Thrown, it bounces off the road and the walls and
## goes off when the fuse says so, wherever it has got to by then.
class Frag extends Node3D:
	var vel := Vector3.ZERO
	var fuse := 2.9
	var team := 0
	var thrower: Node = null
	const RADIUS := 8.5
	const DAMAGE := 150.0

	func _ready() -> void:
		var st := MeshKit.begin()
		MeshKit.box(st, Vector3(0.07, 0.09, 0.07), Vector3.ZERO)
		MeshKit.box(st, Vector3(0.03, 0.03, 0.03), Vector3(0, 0.06, 0))
		add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.20, 0.25, 0.16), 0.7, 0.1)), "M"))
		reset_physics_interpolation.call_deferred()

	func _physics_process(delta: float) -> void:
		fuse -= delta
		if fuse <= 0.0:
			_burst()
			return
		vel.y -= 14.0 * delta
		var was := global_position
		var to := was + vel * delta
		# a wall turns it back along whichever axis ran into it
		if Obstacles.blocks(to, 0.08) >= 0:
			var hit_x: bool = Obstacles.blocks(Vector3(to.x, to.y, was.z), 0.08) >= 0
			var hit_z: bool = Obstacles.blocks(Vector3(was.x, to.y, to.z), 0.08) >= 0
			if hit_x or not hit_z:
				vel.x = -vel.x * 0.4
			if hit_z or not hit_x:
				vel.z = -vel.z * 0.4
			to = was
			_clink()
		var floor_y: float = maxf(Sim.height_at(to.x, to.z), Obstacles.floor_under(to.x, to.z, to.y + 0.3)) + 0.05
		if to.y <= floor_y:
			to.y = floor_y
			if vel.y < -1.5:
				_clink()
			vel.y = -vel.y * 0.32
			vel.x *= 0.62
			vel.z *= 0.62
			if absf(vel.y) < 0.6:
				vel.y = 0.0
		global_position = to
		rotation += Vector3(7.0, 3.0, 5.0) * delta * clampf(vel.length() * 0.2, 0.0, 1.0)

	func _clink() -> void:
		if vel.length() > 1.5:
			Sfx.play_at(get_tree().current_scene, "clink", global_position, -8.0,
				randf_range(0.9, 1.2), 60.0)

	func _burst() -> void:
		var world := get_tree().current_scene
		var at := global_position + Vector3(0, 0.25, 0)
		Sfx.play_at(world, "frag", at, 4.0, randf_range(0.92, 1.05), 900.0)
		Effects.mute_blast = true          # the walls are checked below
		Effects.he_impact(world, at, 2.4)
		Effects.mute_blast = false
		# under a vehicle it is the one thing a man on foot has that hurts it
		for v in get_tree().get_nodes_in_group("hittable"):
			if is_instance_valid(v) and v is Tank and (v as Tank).alive \
					and (v as Tank).team != team \
					and (v as Node3D).global_position.distance_to(at) < 5.0:
				v.take_hit(70.0, thrower if is_instance_valid(thrower) else null)
		var seen := {}
		for grp in ["infantry", "hittable"]:
			for n in get_tree().get_nodes_in_group(grp):
				if not is_instance_valid(n) or seen.has(n) or not n.has_method("bullet_hit"):
					continue
				seen[n] = true
				if n.has_method("is_alive") and not n.is_alive():
					continue
				var chest: Vector3 = (n as Node3D).global_position + Vector3(0, 1.0, 0)
				var d: float = chest.distance_to(at)
				if d > RADIUS:
					continue
				# anything solid between the grenade and the man saves him
				if Obstacles.segment(at, chest) < 1.0:
					continue
				# your own grenade is as dangerous to you as to anyone
				var friendly: bool = n != thrower and (("team" in n and n.team == team)
					or ("side" in n and n.side == team))
				if friendly:
					continue
				var was_alive: bool = n.is_alive() if n.has_method("is_alive") else true
				n.take_hit(DAMAGE * pow(1.0 - d / RADIUS, 1.4),
					thrower if is_instance_valid(thrower) else null)
				if n != thrower and is_instance_valid(thrower) \
						and thrower.has_method("hit_confirm"):
					thrower.hit_confirm(false, was_alive and n.has_method("is_alive")
						and not n.is_alive())
		queue_free()

# ------------------------------------------------------------- hits and sight
## Does a round travelling `from` -> `to` go through a man standing at `feet`?
## Returns (damage multiplier, how far along the segment), multiplier 0 for a
## miss. A capsule for the body and a sphere for the head, because one sphere
## at the ankles -- which is what `hit_radius` gives a walker -- is hit by
## rounds into the road and missed by rounds into the face.
static func body_hit(feet: Vector3, crouched: bool, from: Vector3, to: Vector3) -> Vector2:
	var top: float = 0.98 if crouched else 1.46
	var span: float = from.distance_to(to)
	if span < 1e-4:
		return Vector2.ZERO
	var head := feet + Vector3(0.0, top + 0.17, 0.0)
	var ch: Vector3 = Geometry3D.get_closest_point_to_segment(head, from, to)
	if ch.distance_to(head) < 0.15:
		return Vector2(2.4, from.distance_to(ch) / span)
	var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
		from, to, feet + Vector3(0.0, 0.28, 0.0), feet + Vector3(0.0, top - 0.2, 0.0))
	if pts.size() == 2 and pts[0].distance_to(pts[1]) < 0.29:
		# legs take less than the chest
		var low: bool = pts[1].y - feet.y < (0.45 if crouched else 0.75)
		return Vector2(0.75 if low else 1.0, from.distance_to(pts[0]) / span)
	return Vector2.ZERO

## How far a line of sight runs before it meets a wall or the ground.
static func sight_range(from: Vector3, dir: Vector3, limit: float) -> float:
	var d: float = Obstacles.segment(from, from + dir * limit) * limit
	var step := 2.5
	var s := step
	while s < d:
		var p: Vector3 = from + dir * s
		if p.y < Sim.height_at(p.x, p.z):
			return s - step * 0.5
		s += step
		step = minf(step * 1.15, 12.0)
	return d

## Can one point see another: nothing built in the way.
static func can_see(a: Vector3, b: Vector3) -> bool:
	return Obstacles.segment(a, b) >= 1.0

# ------------------------------------------------------------------ on the road
## A weapon somebody is no longer holding. It lies where it fell until someone
## picks it up or it has been there long enough not to matter.
class Drop extends Node3D:
	var kit := "carbine"
	var rounds := 0
	var life := 60.0

	func _ready() -> void:
		add_to_group("pickups")
		var g: Dictionary = Firearm.spec(kit)
		var m := Firearm.build(g)
		# on its side, the way a dropped rifle ends up
		m.rotation = Vector3(0.0, randf() * TAU, PI * 0.5)
		m.position = Vector3(0.0, 0.03, 0.0)
		add_child(m)
		# a mark to find it by: a dropped carbine on a grey road is four
		# centimetres of dark grey
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.30
		tm.outer_radius = 0.34
		tm.rings = 20
		tm.ring_segments = 4
		var lit := StandardMaterial3D.new()
		lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lit.albedo_color = Color(1.0, 0.8, 0.3, 0.55)
		lit.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tm.material = lit
		ring.mesh = tm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0.0, 0.02, 0.0)
		add_child(ring)

	func label() -> String:
		return String(Firearm.spec(kit)["name"])

	func _process(delta: float) -> void:
		life -= delta
		if life <= 0.0:
			queue_free()

static func drop(world: Node, kit_id: String, rounds: int, at: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var d := Drop.new()
	d.kit = kit_id
	d.rounds = rounds
	world.add_child(d)
	d.global_position = Vector3(at.x, maxf(Sim.height_at(at.x, at.z), at.y), at.z)

## The same question for a man lying down: a low capsule along the way he is
## facing, with the head at the front of it.
static func prone_hit(at: Vector3, yaw: float, from: Vector3, to: Vector3) -> Vector2:
	var span: float = from.distance_to(to)
	if span < 1e-4:
		return Vector2.ZERO
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var head := at + fwd * 0.30 + Vector3(0.0, 0.30, 0.0)
	var ch: Vector3 = Geometry3D.get_closest_point_to_segment(head, from, to)
	if ch.distance_to(head) < 0.15:
		return Vector2(2.4, from.distance_to(ch) / span)
	var pts: PackedVector3Array = Geometry3D.get_closest_points_between_segments(
		from, to, at - fwd * 1.35 + Vector3(0.0, 0.18, 0.0), at + fwd * 0.1 + Vector3(0.0, 0.2, 0.0))
	if pts.size() == 2 and pts[0].distance_to(pts[1]) < 0.24:
		return Vector2(1.0, from.distance_to(pts[0]) / span)
	return Vector2.ZERO

# ------------------------------------------------------------------- rockets
## An unguided anti-armour rocket. It goes where the tube was pointed, drops
## a little on the way, and whatever it meets first gets all of it.
class Rocket extends Node3D:
	var vel := Vector3.ZERO
	var team := 0
	var shooter: Node = null
	var dmg := 110.0
	var life := 3.5

	func _ready() -> void:
		var st := MeshKit.begin()
		MeshKit.cone(st, 0.04, 0.04, -0.25, 0.25, Vector3.ZERO, 6)
		add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.25, 0.27, 0.22), 0.6, 0.2)), "M"))
		var glow := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.7, 0.7)
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		gm.albedo_texture = Effects.glow_texture()
		gm.albedo_color = Color(1.6, 1.0, 0.5, 0.9)
		qm.material = gm
		glow.mesh = qm
		glow.position = Vector3(0, 0, 0.3)
		add_child(glow)
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	func _physics_process(delta: float) -> void:
		life -= delta
		var from := global_position
		vel.y -= 3.0 * delta
		var to := from + vel * delta
		var wall: float = Obstacles.segment(from, to)
		if wall < 1.0:
			to = from.lerp(to, wall)
		var struck: Node = null
		var span: float = maxf(from.distance_to(to), 0.001)
		var best := 2.0
		for n in get_tree().get_nodes_in_group("hittable") + get_tree().get_nodes_in_group("infantry"):
			if n == shooter or not is_instance_valid(n):
				continue
			if n.has_method("is_alive") and not n.is_alive():
				continue
			if ("team" in n and n.team == team) or ("side" in n and n.side == team):
				continue
			var r: float = 0.6 if n.has_method("bullet_hit") else \
				(n.hit_radius() if n.has_method("hit_radius") else 4.0)
			var mid: Vector3 = (n as Node3D).global_position + Vector3(0, 1.0, 0)
			var c: Vector3 = Geometry3D.get_closest_point_to_segment(mid, from, to)
			if c.distance_to(mid) < minf(r, 4.5) and from.distance_to(c) / span < best:
				best = from.distance_to(c) / span
				struck = n
		if struck != null:
			_burst(from.lerp(to, clampf(best, 0.0, 1.0)), struck)
			return
		if wall < 1.0 or to.y < Sim.height_at(to.x, to.z) or life <= 0.0:
			_burst(to, null)
			return
		global_position = to
		look_at(to + vel, Vector3.UP)

	func _burst(at: Vector3, struck: Node) -> void:
		var world := get_tree().current_scene
		if struck != null and struck.has_method("take_hit"):
			struck.take_hit(dmg, shooter if is_instance_valid(shooter) else null)
		# the blast belongs to whoever fired it, for as long as it takes
		var was_credit: Node = Effects.credit
		var was_spare: int = Effects.spare_team
		Effects.credit = shooter if is_instance_valid(shooter) else null
		Effects.spare_team = team
		Effects.explosion(world, at, 4.6, false)
		Effects.he_impact(world, at, 2.6)
		Effects.credit = was_credit
		Effects.spare_team = was_spare
		if is_instance_valid(shooter) and shooter.has_method("hit_confirm") and struck != null:
			shooter.hit_confirm(false, struck.has_method("is_alive") and not struck.is_alive())
		queue_free()

## Send one. Used by the player and by the AI alike.
static func rocket(world: Node, shooter: Node, team: int, g: Dictionary, from: Vector3,
		dir: Vector3) -> void:
	var r := Rocket.new()
	r.team = team
	r.shooter = shooter
	r.dmg = float(g["dmg"])
	r.vel = dir * float(g["muzzle"])
	world.add_child(r)
	r.global_position = from + dir * 0.4
	Sfx.play_at(world, "launch", from, 2.0, 1.5, 900.0)
	Effects.dust(world, from - dir * 1.4, 1.6)        # the backblast

## A shoulder-launched missile onto an aircraft: the same round the manpads
## teams on the ground fire.
static func sam(world: Node, shooter: Node, team: int, from: Vector3, dir: Vector3,
		target: Node3D) -> void:
	var m := Missile.new()
	m.launch("manpads", Transform3D(Basis.looking_at(dir, Vector3.UP), from + dir * 0.6),
		dir * 30.0, shooter, target)
	m.team = team
	world.add_child(m)
	Sfx.play_at(world, "launch", from, 2.0, 1.1, 1400.0)
	Effects.dust(world, from - dir * 1.4, 1.8)
