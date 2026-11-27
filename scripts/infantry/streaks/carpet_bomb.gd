class_name CarpetBomb
extends Node3D
## One of the carpet: a cluster canister that falls, opens over the line and
## lets its bomblets go, each of which goes off on whatever it meets first -- a
## roof or the road. All of it falls in the same flight model a round flies.

## A picture of a strike called on another machine: flies and goes off
## here, and hurts nobody. See `Killstreaks.call_picture`.
var picture := false
## What the air takes off it per metre. A canister with its fins out is a
## draggy thing: it sheds the bomber's two hundred and thirty metres a
## second inside the first few hundred metres and comes down steepening, at
## about eighty a second and most of the way to vertical by the time it
## opens -- which is the thing you recognise as bombs falling. At a sixth
## of this it kept its forward speed all the way down and came in flat and
## fast like a missile. The run works its release point out with this same
## figure, so the carpet still lands where it was drawn.
const DRAG := 0.0015
## A canister on a drogue -- smoke, white phosphorus -- braked to come
## down nearly straight. Thrown off a low pass at bomb drag they flew on
## for hundreds of metres at a shallow slant, and all of them went into
## the first wall along the run instead of onto their stretch of street.
const RETARDED := 0.03
static func drag_for(payload_kind: String) -> float:
	return DRAG if payload_kind == "" else RETARDED
## The short streak a bomblet trails: one mesh and one material for all of
## them. The canisters trail nothing -- a long white line behind a falling
## bomb is what made a stick of them read as rockets.
static var trail_mesh: BoxMesh = null

## Put it where it starts. Set down and left, a new body is drawn for its
## first tick somewhere between the middle of the world and where it was
## put -- every bomb of the stick arrived as a line flashed across the map.
func place(at: Vector3) -> void:
	global_position = at
	if vel.length_squared() > 1.0:
		look_at(at + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)
	reset_physics_interpolation()
## Where a cluster canister opens, above the ground, and what is in it.
const OPEN_AT := 250.0
const BOMBLETS := 8
var arena: CqbMatch = null
var vel := Vector3.ZERO
var cluster := false
## See `CarpetRun.payload`.
var payload := ""
## A bomblet out of a canister rather than a bomb.
var bomblet := false
## The store it is, off the aeroplane's own load: see `CarpetRun.load_weapon`.
var weapon := ""
var _flown := 0.0

func _ready() -> void:
	top_level = true
	# The bomb the aeroplane was carrying, as it is drawn on its pylon and
	# in the hangar. They were made up here instead -- a fat cylinder with
	# a pair of fins the size of doors -- and a stick of them coming off an
	# A-10 looked like oil drums next to the stores it had just let go of.
	var store: String = "bomblet" if bomblet else ("cbu97" if cluster else weapon)
	WeaponSpec.get_spec(store)
	if payload == "" and WeaponSpec._table.has(store):
		var mi := MeshInstance3D.new()
		mi.name = "Bomb"
		mi.mesh = WeaponSpec.build_mesh(store)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	else:
		# a drogue canister of smoke or phosphorus: body, and the fins that
		# slow it. A metre and a half by fifteen centimetres -- it was over two
		# metres long and forty across with fins the width of a door, bigger
		# than the thousand-pound bombs off the same aeroplane.
		var st := MeshKit.begin()
		MeshKit.cone(st, 0.075, 0.075, -0.8, 0.7, Vector3.ZERO, 8)
		MeshKit.box(st, Vector3(0.34, 0.02, 0.28), Vector3(0, 0, 0.62))
		MeshKit.box(st, Vector3(0.02, 0.34, 0.28), Vector3(0, 0, 0.62))
		add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(
			Color(0.42, 0.40, 0.22), 0.6, 0.3)), "Bomb"))
	if not bomblet:
		return
	if CarpetBomb.trail_mesh == null:
		var tm := BoxMesh.new()
		tm.size = Vector3(0.16, 0.16, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.92, 0.93, 0.95, 0.32)
		tm.material = mat
		CarpetBomb.trail_mesh = tm
	var trail := MeshInstance3D.new()
	trail.mesh = CarpetBomb.trail_mesh
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# behind it: the body points down -Z along the way it is falling
	trail.scale = Vector3(0.5, 0.5, 3.0)
	trail.position = Vector3(0.0, 0.0, 1.8)
	add_child(trail)

func _physics_process(delta: float) -> void:
	vel = Ballistics.step(global_position, vel, drag_for(payload), delta, _flown)
	var nxt: Vector3 = global_position + vel * delta
	_flown += vel.length() * delta
	var floor_y: float = maxf(Sim.height_at(nxt.x, nxt.z), Obstacles.top_at(nxt.x, nxt.z))
	if cluster and nxt.y - floor_y < OPEN_AT:
		# the canister opens and the bomblets go their own ways over the
		# street below
		var fwd := Vector3(vel.x, 0.0, vel.z)
		fwd = fwd.normalized() if fwd.length() > 0.5 else Vector3.FORWARD
		var side: Vector3 = fwd.cross(Vector3.UP)
		for i in BOMBLETS:
			var c := CarpetBomb.new()
			c.arena = arena
			c.picture = picture
			c.bomblet = true
			# strung out along the run and kept narrow across it: thrown
			# evenly all round, each canister made a patch ninety metres
			# wide and the carpet was broader than the line it was drawn on
			c.vel = vel + fwd * randf_range(-12.0, 12.0) + side * randf_range(-3.5, 3.5) \
				+ Vector3(0.0, randf_range(-4.0, 4.0), 0.0)
			get_parent().add_child(c)
			c.place(nxt)
		Effects.dust(get_tree().current_scene, nxt, 4.0)
		queue_free()
		return
	if nxt.y <= floor_y and payload != "":
		var hit := Vector3(nxt.x, floor_y, nxt.z)
		var world0 := get_tree().current_scene
		if payload == "smoke":
			var sm := SmokeScreen.new()
			sm.from = hit
			sm.to = hit
			sm.delay = 0.0
			world0.add_child(sm)
		else:
			var ns := NapalmStrike.new()
			ns.from = hit
			ns.to = hit
			ns.delay = 0.0
			ns.picture = picture
			ns.owner_node = arena.player if is_instance_valid(arena) else null
			world0.add_child(ns)
		queue_free()
		return
	if nxt.y <= floor_y:
		if is_instance_valid(arena):
			arena.streaks.bomb(Vector3(nxt.x, floor_y, nxt.z), 1.0 if bomblet else 1.25, bomblet,
				"carpet", picture)
		else:
			Effects.explosion(get_tree().current_scene, Vector3(nxt.x, floor_y, nxt.z), 6.0)
		queue_free()
		return
	global_position = nxt
	if vel.length_squared() > 1.0:
		look_at(nxt + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.FORWARD)
