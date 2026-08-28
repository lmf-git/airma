class_name Carrier
extends Node3D

var team := 0
## A carrier parked in the eastern ocean: angled landing deck, four arrestor
## wires, island, catapults and an optical landing aid.

const LEN := 330.0
const BEAM := 41.0
const DECK_Y := 20.5
const ANGLE := deg_to_rad(9.0)      # angled deck offset from the ship axis
const WIRES := [-52.0, -38.0, -24.0, -10.0]   # deck-local Z of each wire

signal dismount_requested()

var deck: Dictionary = {}
var occupied := false
var alive := true
var health := 9000.0
var cam: Camera3D
var helm := 0.0
var telegraph := 0.0
var speed := 0.0
var aim_yaw := 0.0
var aim_pitch := 0.0
const TOP_SPEED := 15.4
var wire_points: Array = []          # [[worldA, worldB], ...] in deck space
var heading := deg_to_rad(-20.0)

## Just the model, for the menu turntable: no deck registered, no groups
## joined, nothing that would have gameplay code find this one and put the
## player on a carrier 256 m above the airfield.
func build_preview() -> void:
	_hull()
	_deck_markings()
	_island()

func build(at: Vector3, hdg: float) -> void:
	heading = hdg
	# On the sea, not above it. The hull was modelled about y = 0 and the ship
	# placed at y = 0 as well, while the water sits at WATER_LEVEL -- so the
	# whole carrier floated twenty-six metres clear of the surface with its
	# bottom on show. Everything else here is measured from the waterline.
	position = Vector3(at.x, Sim.WATER_LEVEL, at.z)
	rotation.y = hdg
	_hull()
	_deck_markings()
	_island()
	_lights()
	deck = Sim.register_deck(Vector3(at.x, 0, at.z), hdg,
		Vector2(BEAM * 0.5 + 12.0, LEN * 0.5), Sim.WATER_LEVEL + DECK_Y)
	for w in WIRES:
		wire_points.append(w)
	# It belongs to somebody. Without this the radar treated it as a contact
	# with no allegiance, which the target filter read as hostile.
	team = 0
	add_to_group("carrier")
	add_to_group("boardable")
	add_to_group("hittable")
	cam = Camera3D.new()
	cam.far = 48000.0
	cam.fov = 62.0
	add_child(cam)
	set_physics_process(true)

## The deck is registered by reference, so a carrier under way keeps working as
## a landing platform: the entry is updated rather than rebuilt.
func _physics_process(delta: float) -> void:
	if occupied:
		_conn(delta)
		heading = wrapf(heading + helm * delta * 0.055, -PI, PI)
		speed = move_toward(speed, telegraph * TOP_SPEED, delta * 0.35)
	if speed != 0.0:
		position += Vector3(sin(heading), 0.0, -cos(heading)) * speed * delta
		rotation.y = heading
	if not deck.is_empty():
		deck["origin"] = Vector3(position.x, 0.0, position.z)
		deck["yaw"] = heading
		deck["cos"] = cos(-heading)
		deck["sin"] = sin(-heading)

func mount(on: bool) -> void:
	occupied = on
	if on:
		cam.current = true
		aim_yaw = heading
		telegraph = clampf(speed / TOP_SPEED, 0.0, 1.0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func display_name() -> String:
	return "Fleet carrier"

func is_alive() -> bool:
	return alive

func hit_radius() -> float:
	return BEAM * 0.6

func has_gun() -> bool:
	return false

func mast_height() -> float:
	return DECK_Y + 26.0

func take_hit(amount: float, _from: Node = null) -> void:
	health = maxf(health - amount, 0.0)

func _unhandled_input(e: InputEvent) -> void:
	if not occupied:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := e as InputEventMouseMotion
		aim_yaw -= mm.relative.x * 0.0026
		aim_pitch = clampf(aim_pitch - mm.relative.y * 0.0020,
			deg_to_rad(-20.0), deg_to_rad(50.0))

func _conn(delta: float) -> void:
	var w := Sim.strength(&"roll_right") - Sim.strength(&"roll_left")
	helm = move_toward(helm, w, delta * 1.1)
	var t := Sim.strength(&"pitch_down") - Sim.strength(&"pitch_up")
	telegraph = clampf(telegraph + t * delta * 0.28, -0.2, 1.0)
	if Sim.tapped(&"interact"):
		dismount_requested.emit()
	# from the island, looking down the deck
	var eye: Vector3 = global_position + Vector3(0, DECK_Y + 22.0, 0)
	var back := Vector3(-sin(aim_yaw), 0, cos(aim_yaw))
	cam.global_position = eye + back * 44.0 + Vector3(0, 10.0, 0)
	cam.look_at(eye + Vector3(sin(aim_yaw) * cos(aim_pitch), sin(aim_pitch),
		-cos(aim_yaw) * cos(aim_pitch)) * 500.0, Vector3.UP)

## Draught below the waterline. The hull is modelled about y = 0 being the
## surface, and the whole ship is then set down at `Sim.WATER_LEVEL`.
const DRAUGHT := 11.5
## Hangar deck edge: the top of the hull proper, just under the flight deck.
const HULL_TOP := DECK_Y - 1.7

## Stations from transom to stem: z as a fraction of the length, half-breadth
## and flat-of-bottom as fractions of the half beam, and how far the forefoot
## has risen towards the surface. A ship is a series of sections, and the shape
## of those sections is the whole difference between a hull and a tube -- the
## old one was a ten sided extrusion with no flat of bottom, no turn of bilge
## and no forefoot, which is why the underside read as a length of pipe.
const STATIONS := [
	[-0.500, 0.90, 0.70, 0.00],
	[-0.440, 0.97, 0.76, 0.00],
	[-0.300, 1.00, 0.80, 0.00],
	[-0.120, 1.00, 0.80, 0.00],
	[ 0.060, 1.00, 0.78, 0.00],
	[ 0.220, 0.98, 0.68, 0.02],
	[ 0.340, 0.90, 0.46, 0.12],
	[ 0.430, 0.70, 0.22, 0.38],
	[ 0.480, 0.42, 0.08, 0.66],
	[ 0.500, 0.10, 0.02, 0.88],
]

## The wetted section at a station: keel, flat of bottom, turn of bilge, up to
## the waterline, and back across it.
func _under_ring(z: float, hb: float, kw: float, keel: float) -> PackedVector3Array:
	var d: float = -keel
	var r := PackedVector3Array()
	r.append(Vector3(0.0, keel, z))
	r.append(Vector3(kw, keel, z))
	r.append(Vector3(hb * 0.90, keel + d * 0.30, z))
	r.append(Vector3(hb, keel + d * 0.64, z))
	r.append(Vector3(hb, 0.0, z))
	r.append(Vector3(-hb, 0.0, z))
	r.append(Vector3(-hb, keel + d * 0.64, z))
	r.append(Vector3(-hb * 0.90, keel + d * 0.30, z))
	r.append(Vector3(-kw, keel, z))
	return r

## And the topside: waterline to hangar deck edge, with a little flare.
func _top_ring(z: float, hb: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	r.append(Vector3(hb, 0.0, z))
	r.append(Vector3(hb * 0.99, HULL_TOP * 0.45, z))
	r.append(Vector3(hb * 1.04, HULL_TOP, z))
	r.append(Vector3(-hb * 1.04, HULL_TOP, z))
	r.append(Vector3(-hb * 0.99, HULL_TOP * 0.45, z))
	r.append(Vector3(-hb, 0.0, z))
	return r

func _hull() -> void:
	var half := BEAM * 0.5
	var under: Array = []
	var top: Array = []
	for st0 in STATIONS:
		var z: float = float(st0[0]) * LEN
		var hb: float = maxf(half * float(st0[1]), 0.4)
		var kw: float = half * float(st0[2])
		var keel: float = -DRAUGHT * (1.0 - float(st0[3]))
		under.append(_under_ring(z, hb, kw, keel))
		top.append(_top_ring(z, hb))
	# Anti-fouling below the waterline, ship's grey above it. Two lofts sharing
	# the same waterline outline, so they meet on it exactly rather than being
	# one mesh with a stripe painted near the join.
	var su := MeshKit.begin()
	MeshKit.loft(su, under, Vector3(0.0, -DRAUGHT * 0.5, 0.0))
	add_child(MeshKit.mi(MeshKit.finish(su,
		MeshKit.mat(Color(0.30, 0.09, 0.07), 0.85, 0.05)), "Underbody"))
	var stp := MeshKit.begin()
	MeshKit.loft(stp, top, Vector3(0.0, HULL_TOP * 0.5, 0.0))
	add_child(MeshKit.mi(MeshKit.finish(stp,
		MeshKit.mat(Color(0.23, 0.25, 0.27), 0.9, 0.12)), "Hull"))
	# Boot topping: the dark band a ship carries at the waterline. Stood off the
	# plating so it cannot fight with it for the same pixels.
	var sb := MeshKit.begin()
	var band: Array = []
	for st1 in STATIONS:
		var z1: float = float(st1[0]) * LEN
		var hb1: float = maxf(half * float(st1[1]), 0.4) * 1.006
		var r := PackedVector3Array()
		r.append(Vector3(hb1, 1.1, z1))
		r.append(Vector3(hb1, -1.9, z1))
		r.append(Vector3(-hb1, -1.9, z1))
		r.append(Vector3(-hb1, 1.1, z1))
		band.append(r)
	MeshKit.loft(sb, band, Vector3.ZERO, false, false)
	add_child(MeshKit.mi(MeshKit.finish(sb,
		MeshKit.mat(Color(0.07, 0.07, 0.08), 0.8, 0.0)), "BootTopping"))
	# Sponsons. The flight deck is twenty-two metres wider than the hull and
	# overhangs to port; before this there was nothing at all underneath it, so
	# the deck ended in mid-air over the sea.
	var sp := MeshKit.begin()
	var deck_under := DECK_Y - 2.6
	for z2 in [-LEN * 0.34, -LEN * 0.10, LEN * 0.14, LEN * 0.32]:
		MeshKit.box(sp, Vector3(13.0, 5.2, 26.0),
			Vector3(-half - 5.0, deck_under - 2.0, z2))
	for z3 in [-LEN * 0.28, LEN * 0.06]:
		MeshKit.box(sp, Vector3(8.0, 4.4, 20.0),
			Vector3(half + 3.0, deck_under - 1.8, z3))
	# and the knuckle carrying the overhang the length of the port side
	MeshKit.box(sp, Vector3(9.0, 3.0, LEN * 0.80),
		Vector3(-half - 3.5, deck_under, -LEN * 0.02))
	add_child(MeshKit.mi(MeshKit.finish(sp,
		MeshKit.mat(Color(0.21, 0.23, 0.25), 0.9, 0.12)), "Sponsons"))
	# transom: a flat stern with a rounded-down deck edge over it
	var stern := MeshKit.begin()
	MeshKit.box(stern, Vector3(half * 1.8, HULL_TOP + DRAUGHT, 3.0),
		Vector3(0.0, (HULL_TOP - DRAUGHT) * 0.5, -LEN * 0.5 - 1.4))
	add_child(MeshKit.mi(MeshKit.finish(stern,
		MeshKit.mat(Color(0.23, 0.25, 0.27), 0.9, 0.12)), "Transom"))

	# flight deck slab, wider than the hull and overhanging to port
	var d := MeshKit.begin()
	MeshKit.box(d, Vector3(BEAM + 22.0, 1.6, LEN), Vector3(-4.0, DECK_Y - 0.8, 0))
	add_child(MeshKit.mi(MeshKit.finish(d, MeshKit.mat(Color(0.17, 0.17, 0.18), 0.95, 0.0)), "Deck"))

func _quad(st: SurfaceTool, cx: float, cz: float, hw: float, hl: float, rot: float, y: float) -> void:
	var c := cos(rot)
	var s := sin(rot)
	var pts := []
	for p in [Vector2(-hw, -hl), Vector2(hw, -hl), Vector2(hw, hl), Vector2(-hw, hl)]:
		pts.append(Vector3(cx + p.x * c - p.y * s, y, cz + p.x * s + p.y * c))
	for v in [pts[0], pts[1], pts[2], pts[0], pts[2], pts[3]]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)

func _deck_markings() -> void:
	var st := MeshKit.begin()
	var y := DECK_Y + 0.05
	# angled landing strip centreline and edges
	_quad(st, -8.0, -6.0, 0.45, 120.0, ANGLE, y)
	for sx in [-14.0, 14.0]:
		_quad(st, -8.0 + sx, -6.0, 0.30, 118.0, ANGLE, y)
	# touchdown target
	_quad(st, -8.0 + sin(ANGLE) * 30.0, -30.0, 9.0, 0.9, ANGLE, y)
	# arrestor wires
	for w in WIRES:
		_quad(st, -8.0 + sin(ANGLE) * (w + 6.0), w, 13.0, 0.22, ANGLE, y + 0.06)
	# bow catapult tracks
	for cx in [-16.0, 4.0]:
		_quad(st, cx, 96.0, 0.6, 62.0, 0.0, y)
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.88, 0.88, 0.86), 0.9, 0.0)), "DeckMarks"))

func _island() -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(11.0, 16.0, 34.0), Vector3(23.0, DECK_Y + 8.0, -14.0))
	MeshKit.box(st, Vector3(13.0, 4.0, 16.0), Vector3(23.0, DECK_Y + 18.0, -20.0))
	MeshKit.box(st, Vector3(1.2, 26.0, 1.2), Vector3(23.0, DECK_Y + 30.0, -8.0))
	MeshKit.box(st, Vector3(8.0, 0.6, 0.6), Vector3(23.0, DECK_Y + 40.0, -8.0))
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.30, 0.32, 0.33), 0.9, 0.1)), "Island"))
	var g := MeshKit.begin()
	MeshKit.box(g, Vector3(12.0, 3.2, 15.0), Vector3(23.0, DECK_Y + 18.4, -20.0))
	add_child(MeshKit.mi(MeshKit.finish(g, MeshKit.mat(Color(0.18, 0.26, 0.30), 0.2, 0.7)), "Bridge"))

func _lights() -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.42
	bulb.height = 0.84
	bulb.radial_segments = 5
	bulb.rings = 3
	var edge := []
	var z := -LEN * 0.5 + 6.0
	while z < LEN * 0.5 - 6.0:
		edge.append(Vector3(-BEAM * 0.5 - 14.0, DECK_Y + 0.4, z))
		edge.append(Vector3(BEAM * 0.5 + 5.0, DECK_Y + 0.4, z))
		z += 14.0
	var mm := MultiMeshInstance3D.new()
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = bulb
	m.instance_count = edge.size()
	for i in edge.size():
		m.set_instance_transform(i, Transform3D(Basis(), edge[i]))
	mm.multimesh = m
	mm.material_override = MeshKit.mat(Color.BLACK, 0.4, 0.0, Color(0.35, 0.75, 1.0))
	mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm)

## Deck-local position of a world point (x forward-right of the ship axis).
func to_deck(p: Vector3) -> Vector3:
	return to_local(p)

## The four wires as deck-local Z values; a hook crossing one gets trapped.
func wire_zs() -> Array:
	return WIRES
