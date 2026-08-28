class_name CaptureZone
extends Node3D
## A contested ground objective: mast, ring marker, garrison assets and capture
## state. Used by every battle mode.

signal captured(zone, team)

const NEUTRAL := -1

var label := "A"
var radius := 220.0
var owner_team := NEUTRAL
var progress := 0.0          # -1 = fully hostile, +1 = fully friendly
var contested := false
var locked := false          # Rush / Warlords gate zones until they are live
var assets: Array = []
var _flag: MeshInstance3D
var _ring: MeshInstance3D
var _mat_flag: StandardMaterial3D
var _mat_ring: StandardMaterial3D

## What the sector is called on the map, when it stands on something.
var place := ""
## Command points a minute this sector pays whoever holds it.
var income := 30.0
## Garrisons are built when the sector matters, not when the match starts.
## Twenty sectors laid out at once meant a hundred and twenty crewed assets
## standing in fields nobody had flown over yet.
var _wants_garrison := false
var _has_garrison := false

func build(nm: String, at: Vector3, r: float, team: int, garrison := true) -> void:
	label = nm
	radius = r
	owner_team = team
	progress = 1.0 if team == 0 else (-1.0 if team == 1 else 0.0)
	position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
	_build_mast()
	_build_ring()
	_wants_garrison = garrison
	add_to_group("zones")

## Stand the garrison up, once. Called when the sector goes live or when
## somebody gets near enough to see that it is empty.
func ensure_garrison() -> void:
	if _has_garrison or not _wants_garrison:
		return
	_has_garrison = true
	_build_garrison()

func has_garrison() -> bool:
	return _has_garrison

func _build_mast() -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(6.0, 1.0, 6.0), Vector3(0, 0.5, 0))
	MeshKit.cone(st, 0.30, 0.22, 0.0, 18.0, Vector3.ZERO, 6)
	add_child(MeshKit.mi(MeshKit.finish(st, MeshKit.mat(Color(0.55, 0.55, 0.52), 0.9, 0.2)), "Mast"))
	var f := MeshKit.begin()
	MeshKit.box(f, Vector3(0.12, 2.4, 4.0), Vector3(0, 15.4, 2.1))
	_mat_flag = MeshKit.mat(Color(0.6, 0.6, 0.6), 0.9, 0.0)
	_flag = MeshKit.mi(MeshKit.finish(f, _mat_flag), "Flag")
	add_child(_flag)

func _build_ring() -> void:
	var st := MeshKit.begin()
	var seg := 48
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		for pair in [[radius - 4.0, radius]]:
			var r0: float = pair[0]
			var r1: float = pair[1]
			var p := [
				Vector3(cos(a0) * r0, 0, sin(a0) * r0), Vector3(cos(a0) * r1, 0, sin(a0) * r1),
				Vector3(cos(a1) * r1, 0, sin(a1) * r1), Vector3(cos(a1) * r0, 0, sin(a1) * r0)]
			for v in [p[0], p[1], p[2], p[0], p[2], p[3]]:
				var y := Sim.height_at(global_position.x + v.x, global_position.z + v.z) \
					- global_position.y + 0.5
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v.x, y, v.z))
	_mat_ring = MeshKit.mat(Color.BLACK, 0.6, 0.0, Color(0.6, 0.6, 0.6))
	_mat_ring.emission_energy_multiplier = 2.5
	_ring = MeshKit.mi(MeshKit.finish(st, _mat_ring), "Ring")
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

func _build_garrison() -> void:
	# Only a sector that actually belongs to someone gets a crewed garrison. An
	# unclaimed sector with hostile armour parked in it flips to them the moment
	# the match starts, which is not what "neutral" means.
	for i in (2 if owner_team != NEUTRAL else 0):
		var a := TAU * (float(i) / 2.0) + 1.1
		var off := Vector3(cos(a), 0, sin(a)) * (radius * 0.35)
		var t := Tank.new()
		t.setup(1 if owner_team != 0 else 0, "t90" if owner_team != 0 else "m1a2")
		t.ai = true
		t.name = "%s armour %d" % [label, i + 1]
		add_child(t)
		# Both ends build the same garrison in the same order, so the sector
		# label plus the slot number is a key neither side has to be told.
		t.set_meta("zone_asset", [label, assets.size()])
		t.global_transform = Transform3D(Basis(Vector3.UP, a),
			Vector3(global_position.x + off.x,
				Sim.height_at(global_position.x + off.x, global_position.z + off.z) + 1.1,
				global_position.z + off.z))
		assets.append(t)
	var kinds := ["sam", "radar", "fuel", "hangar"]
	for i in kinds.size():
		var a := TAU * float(i) / float(kinds.size()) + 0.4
		var off := Vector3(cos(a), 0, sin(a)) * (radius * 0.55)
		var g := GroundTarget.new()
		g.team = 1 if owner_team != 0 else 0
		g.setup(kinds[i])
		add_child(g)
		g.position = Vector3(off.x, Sim.height_at(global_position.x + off.x,
			global_position.z + off.z) - global_position.y, off.z)
		g.name = "%s %s" % [label, kinds[i]]
		g.set_meta("zone_asset", [label, assets.size()])
		assets.append(g)

func alive_assets() -> int:
	var n := 0
	for a in assets:
		if is_instance_valid(a) and a.is_alive():
			n += 1
	return n

## Advance capture from whoever is standing in the ring.
##
## `holders` is the list of everything that can hold ground, gathered once for
## the whole match rather than once per sector: this used to walk the entire
## `hittable` group itself, which with five sectors was five passes a frame and
## with twenty would have been twenty.
func tick(delta: float, holders: Array) -> void:
	if locked:
		return
	var friendly := 0
	var hostile := 0
	var r2 := radius * radius
	for h in holders:
		var p: Vector3 = h[0]
		var dx: float = p.x - global_position.x
		var dz: float = p.z - global_position.z
		if dx * dx + dz * dz > r2:
			continue
		if int(h[1]) == 0:
			friendly += 1
		else:
			hostile += 1
	# losing the garrison flips a point on its own
	var wrecked := _has_garrison and assets.size() > 0 and alive_assets() == 0
	contested = friendly > 0 and hostile > 0
	var rate := 0.0
	if wrecked and owner_team != 0:
		rate = 0.45
	elif not contested:
		rate = (0.22 * friendly) if friendly > 0 else (-0.22 * hostile)
	if rate != 0.0:
		var was := owner_team
		progress = clampf(progress + rate * delta, -1.0, 1.0)
		if progress >= 1.0:
			owner_team = 0
		elif progress <= -1.0:
			owner_team = 1
		elif absf(progress) < 0.999:
			owner_team = NEUTRAL
		if owner_team != was and owner_team != NEUTRAL:
			captured.emit(self, owner_team)
	_paint()

func _paint() -> void:
	var c := Color(0.85, 0.85, 0.85)
	if owner_team == 0:
		c = Color(0.30, 0.75, 1.0)
	elif owner_team == 1:
		c = Color(1.0, 0.32, 0.26)
	if contested:
		c = Color(1.0, 0.80, 0.20)
	if locked:
		c = Color(0.35, 0.35, 0.38)
	_mat_flag.albedo_color = c
	_mat_ring.emission = c
	if _flag:
		_flag.position.y = lerpf(-14.0, 0.0, (progress + 1.0) * 0.5) if owner_team == CaptureZone.NEUTRAL else 0.0
