class_name SmokeScreen
extends Node3D
## A line of smoke laid across a spot on the map: the SMOKE BARRAGE streak.
##
## A few seconds after the call the shells land one after another along the
## line, each blooms into a bank of smoke, and the banks hang there for most of
## a minute before thinning out. While they stand nobody sees through them:
## every line of sight in the fight goes through `Firearm.can_see`, which asks
## `blocks` here as well as the buildings.

## The banks standing anywhere in the world: [centre, radius]. Static, so a
## line of sight can be asked about without a reference to any one screen.
static var clouds: Array = []

## The line it is laid along, on the ground.
var from := Vector3.ZERO
var to := Vector3.ZERO
## Seconds from the call to the first shell landing.
var delay := 4.0
## How long a bank stands at full thickness, and how long it takes to thin.
const HOLD := 40.0
const THIN := 8.0
## How far apart the shells land along the line, and how big a bank is.
const SPACING := 7.0
const RADIUS := 6.5
## How long a bank takes to grow to full size.
const BLOOM := 2.5

var _t := 0.0
var _banks: Array = []          # [node, centre, landed at, entry in clouds]
var _spots: Array = []
static var _mat: StandardMaterial3D = null
static var _mesh: SphereMesh = null

## Does a straight line from `a` to `b` pass through standing smoke? Taken a
## little inside each bank's edge, so the thin outside of one is see-through.
static func blocks(a: Vector3, b: Vector3) -> bool:
	if clouds.is_empty():
		return false
	var ab: Vector3 = b - a
	var len2: float = ab.length_squared()
	for c in clouds:
		var centre: Vector3 = c[0]
		var r: float = float(c[1]) * 0.8
		if r <= 0.5:
			continue
		var t: float = 0.0 if len2 < 1e-6 else clampf((centre - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_squared_to(centre) < r * r:
			return true
	return false

func _ready() -> void:
	if _mat == null:
		# Opaque. Drawn as see-through, even nearly so, it went into the
		# transparent pass -- after the atmosphere -- and the haze of the air
		# was laid over it, so at any distance the screen read as a faint
		# smudge you could see the street through. Solid, it is drawn with
		# the buildings and the air lies over it the way it lies over them.
		# Lit by the sky as everything else is it came out blue; smoke is
		# the colour of smoke whatever is over it, so it carries its own light.
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_mat.albedo_color = Color(0.62, 0.62, 0.60)
		_mat.emission_enabled = true
		_mat.emission = Color(0.42, 0.42, 0.41)
		_mat.cull_mode = BaseMaterial3D.CULL_BACK
		_mat.roughness = 1.0
		_mesh = SphereMesh.new()
		_mesh.radius = 1.0
		_mesh.height = 2.0
		_mesh.radial_segments = 10
		_mesh.rings = 6
	var run: float = from.distance_to(to)
	var n: int = maxi(int(ceil(run / SPACING)), 1)
	for i in n + 1:
		var p: Vector3 = from.lerp(to, float(i) / float(n))
		p.y = Sim.height_at(p.x, p.z)
		_spots.append([p, delay + float(i) * 0.35])

func _process(delta: float) -> void:
	_t += delta
	for s in _spots.duplicate():
		if _t >= float(s[1]):
			_spots.erase(s)
			_land(s[0])
	var done := _spots.is_empty()
	for b in _banks:
		var age: float = _t - float(b[2])
		var grow: float = clampf(age / BLOOM, 0.0, 1.0)
		var thin: float = clampf((age - HOLD) / THIN, 0.0, 1.0)
		var r: float = RADIUS * (0.35 + 0.65 * grow) * (1.0 - thin * 0.3)
		(b[3] as Array)[1] = r * (1.0 - thin)
		(b[4] as Array)[1] = r * 0.85 * (1.0 - thin)
		var node: Node3D = b[0]
		if is_instance_valid(node):
			# thinning, it shrinks away rather than fading: see `_mat`
			node.scale = Vector3.ONE * maxf(r / RADIUS * (1.0 - thin * 0.95), 0.001)
		if thin < 1.0:
			done = false
	if done:
		queue_free()

func _exit_tree() -> void:
	for b in _banks:
		clouds.erase(b[3])
		clouds.erase(b[4])
	_banks.clear()

func _land(at: Vector3) -> void:
	var world := get_tree().current_scene
	Effects.explosion(world, at, 2.0, false)
	Sfx.play_at(world, "thump", at, -8.0, randf_range(1.3, 1.6), 400.0)
	var bank := Node3D.new()
	add_child(bank)
	bank.global_position = at + Vector3(0.0, RADIUS * 0.45, 0.0)
	# Overlapping balls rather than one, lumpy the way smoke is, and in two
	# layers: one layer was four metres high, and the house it was laid in
	# front of stood over it from the first floor up.
	for k in 12:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var upper: bool = k >= 7
		var s: float = RADIUS * (randf_range(0.6, 0.9) if not upper else randf_range(0.5, 0.75))
		mi.scale = Vector3(s, s * randf_range(0.75, 1.0), s)
		mi.position = Vector3(randf_range(-0.4, 0.4),
			(randf_range(1.0, 1.5) if upper else randf_range(-0.1, 0.35)),
			randf_range(-0.4, 0.4)) * RADIUS
		bank.add_child(mi)
	# for the lines of sight: the bank as two balls, low and high
	var entry: Array = [bank.global_position, RADIUS * 0.35]
	var entry_hi: Array = [bank.global_position + Vector3(0.0, RADIUS * 1.2, 0.0), RADIUS * 0.3]
	clouds.append(entry)
	clouds.append(entry_hi)
	_banks.append([bank, at, _t, entry, entry_hi])
