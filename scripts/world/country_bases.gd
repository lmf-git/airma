class_name CountryBases
extends RefCounted
## The other countries' airfields: siting them on dry, flat ground clear of the
## towns, dressing them with parked aircraft, and the satellite constellation.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

## The nearest one that is not yours, for the missions that want an opponent.
var opfor_base: Airbase = null
var opfor_field: Dictionary = {}
## The first of each type is built; the rest are copies of it.
##
## Four aircraft are parked on every dispersal and they are the same four on
## every one -- five bases, twenty airframes, four distinct shapes. Each is a
## few hundred surfaces of procedural geometry, and building all twenty from
## scratch was 117 ms of the boot. A duplicate shares the meshes and the
## materials, which is exactly what something that sits there wants; nothing
## tints a parked aeroplane or opens its bays.
##
## Copied from one already standing on a dispersal rather than from a spare kept
## to one side: a node held outside the tree is an orphan, and the engine counts
## those out loud when the game quits.
var _parked: Dictionary = {}


func _init(w: World) -> void:
	world = w


func site_country_fields() -> void:
	# An aerodrome for every country, not a home one and an enemy one.
	#
	# There was a main airfield at the middle of the world and a single
	# "opposing" field sited relative to it. That is the last of the same
	# assumption the theatre was: one privileged place, everything else
	# measured from it. Each of the six countries has a field of its own now,
	# all sited the same way, and the only thing that distinguishes yours is
	# that the chart is centred on it -- because centring the chart on the
	# country you chose is what starting a sortie there means.
	if not Sim.globe:
		_site_flat_opfor()
		return
	# Yours is already registered, at the origin: `Sim.fields[0]` is put there
	# before anything can ask for a height, and the chart is on your country,
	# so the origin is in it.
	if not Sim.fields.is_empty():
		(Sim.fields[0] as Dictionary)["who"] = Sim.home_faction
	for who in Sim.HOMELAND_ORDER:
		var nm := String(who)
		if nm == Sim.home_faction:
			continue
		var centre: Vector2 = Sim.dir_to_chart(Sim.homeland_dir(nm))
		var spot: Vector2 = _dry_field_site(centre)
		if spot == Vector2.INF:
			push_warning("no dry ground for %s's aerodrome" % nm)
			continue
		var fd: Dictionary = Sim.register_field(spot, deg_to_rad(28.0))
		fd["who"] = nm
		if OS.is_debug_build():
			# Above its own sea, not its world `y`: a thousand kilometres out
			# the ground is a hundred kilometres below the tangent plane, and a
			# runway reported at minus a hundred thousand reads as a bug rather
			# than as a hill.
			print("[fields] %s at %s, %.0f m above sea, %.0f km away" % [
				nm, str(spot.round()),
				Sim.field_elev(fd) - Sim.sea_at(spot.x, spot.y),
				spot.length() * 0.001])
	# The nearest country that is not yours, which is who the missions that
	# want an opponent fly against.
	opfor_field = {}
	var best_d := 1e30
	for fd2 in Sim.fields:
		var f2: Dictionary = fd2
		if String(f2.get("who", "")) == Sim.home_faction:
			continue
		var at2: Vector2 = f2["at"]
		if at2.length() < best_d:
			best_d = at2.length()
			opfor_field = f2


## Somewhere inside a country with room for a runway and its approaches.
##
## A field needs more than a dry point: it is levelled over two kilometres by
## four, so a headland that is dry in the middle and sea at both ends gets an
## aerodrome with its approach lights under water. The search is in the
## extension -- it is a spiral of two hundred and sixty stops with an
## eighty-one point footprint tested at each, which written here was twenty-one
## thousand calls across the binding for every country on the planet.
##
## And not on a town. The towns are sited first, so a field that came down on
## one laid its runway through the streets: the search is run again further
## out, from where the last one landed, until it finds open country.
func _dry_field_site(centre: Vector2) -> Vector2:
	var r0 := 0.0
	for _attempt in 8:
		var q: Vector2 = Sim.native.dry_field_site(
			centre.x, centre.y, r0, 1200.0, 0.41, 260, 0.0)
		if is_inf(q.x):
			return Vector2.INF
		if _field_clear_of_towns(q, deg_to_rad(28.0)):
			return q
		r0 = q.distance_to(centre) + 4000.0
	return Vector2.INF


## Would a field at `at`, turned to `yaw`, stand clear of every town?
func _field_clear_of_towns(at: Vector2, yaw: float) -> bool:
	if not is_instance_valid(world.scenery):
		return true
	var fd := {"at": at, "yaw": yaw}
	for t in world.scenery.sites:
		var c: Vector2 = t["c"]
		var l: Vector2 = Sim.field_local(fd, c.x, c.y)
		var need: float = float(t["r"]) * 1.15 + 300.0
		if Sim.rect_gap(l, Vector2(950.0, 2600.0)) < need \
				or Sim.rect_gap(l, Vector2(260.0, 5200.0)) < need * 0.6:
			return false
	return true


## The flat world has no countries in it, so it keeps the single opposing field
## it always had: a slow spiral outward from 74 km looking for room.
func _site_flat_opfor() -> void:
	# The same search, from 74 km out and kept inside the map's own edge.
	var found := Vector2.INF
	var r0 := 74000.0
	for _attempt in 8:
		found = Sim.native.dry_field_site(
			0.0, 0.0, r0, 3500.0, 0.21, 90, Sim.WORLD_HALF * 0.8)
		if is_inf(found.x) or _field_clear_of_towns(found, deg_to_rad(28.0)):
			break
		r0 = found.length() + 3500.0
		found = Vector2.INF
	var spot: Vector2 = Vector2.INF if is_inf(found.x) else found
	if spot == Vector2.INF:
		push_warning("no dry ground found for the opposing field")
		return
	opfor_field = Sim.register_field(spot, deg_to_rad(28.0))
	if OS.is_debug_build():
		print("[fields] opposing field at %s, %.0f m above sea, %.0f km out" % [
			str(spot.round()),
			Sim.field_elev(opfor_field) - Sim.sea_at(spot.x, spot.y),
			spot.length() * 0.001])


## An aerodrome on every country's field, built the same way.
##
## There was one of these for "home" -- added with no transform, so it sat at
## world zero and depended on the home strip being at sea level -- and a second,
## separate one for the opposition, which was the only one placed on its own
## pavement. They are all the opposition to somebody. One routine builds all
## six, and which one you took off from is the only thing that makes it yours.
func build_country_bases() -> void:
	world.bases.clear()
	var _t_build := 0
	var _t_dress := 0
	for fd in Sim.fields:
		var f: Dictionary = fd
		var who := String(f.get("who", ""))
		var spot: Vector2 = f["at"]
		var ab := Airbase.new()
		ab.name = "Airbase %s" % who if who != "" else "Airbase"
		# On the pavement, and lying on it: an airbase is a rigid slab a couple
		# of kilometres across, and a thousand kilometres out the ground it
		# stands on is tilted away from world level. Left upright its far ends
		# were 24 m out; laid on the local tangent plane the worst mismatch is
		# the sagitta over its own length, which is 0.3 m.
		var pos := Vector3(spot.x, Sim.field_elev(f), spot.y)
		var lean: float = Sim.up_at(pos).angle_to(Vector3.UP)
		var ax: Vector3 = Vector3.UP.cross(Sim.up_at(pos))
		var tilt := Basis() if ax.length() < 1e-6 else Basis(ax.normalized(), lean)
		ab.transform = Transform3D(tilt * Basis(Vector3.UP, float(f["yaw"])), pos)
		world.add_child(ab)
		var home: bool = who == Sim.home_faction or (who == "" and f == Sim.fields[0])
		ab.team = 0 if home else 1
		var _tb := Time.get_ticks_msec()
		ab.build()
		_t_build += Time.get_ticks_msec() - _tb
		world.bases.append(ab)
		if home:
			world.base = ab
		else:
			var _td := Time.get_ticks_msec()
			_dress_base(ab, spot)
			_t_dress += Time.get_ticks_msec() - _td
			if f == opfor_field:
				opfor_base = ab
	if world._boot_verbose:
		print("[bases] %d fields: the aerodromes %d ms, what is parked on them %d ms"
			% [Sim.fields.size(), _t_build, _t_dress])
	launch_constellation()


## What makes a strip of concrete read as somebody's base: aircraft on the
## apron, launchers on the dispersal, and a patrol pair that actually moves.
func _dress_base(ab: Airbase, spot: Vector2) -> void:
	var park := [["su57", Vector3(96, 0, -300), 90.0], ["su35", Vector3(96, 0, -350), 90.0],
		["mig29", Vector3(96, 0, -400), 90.0], ["j20", Vector3(200, 0, -470), -90.0]]
	for pk in park:
		var id := String(pk[0])
		var spec := JetSpec.get_spec(id)
		var gh := 0.0
		for g in spec["gear"]:
			gh = maxf(gh, absf(g["pos"].y) + g["r"])
		var node := _parked_jet(id)
		# In the base's own frame, so it rides the pavement wherever that is.
		node.position = (pk[1] as Vector3) + Vector3(0, gh, 0)
		node.rotation_degrees = Vector3(0, float(pk[2]), 0)
		ab.add_child(node)
	# a couple of launchers on the dispersal, which is what they are for
	for i in 2:
		var at := Vector2(spot.x + 420.0 + float(i) * 60.0, spot.y - 520.0)
		world._spawn_tank(Vector3(at.x, 0, at.y), deg_to_rad(28.0), 1,
			"tel_kalibr" if i == 0 else "tel_fattah")
	# and the vehicles that actually move about a base: a patrol pair by the
	# apron, in this side's own kit rather than the other bloc's
	for i in 2:
		var at2 := Vector2(spot.x + 250.0, spot.y - 300.0 - float(i) * 14.0)
		var pv := world._spawn_tank(Vector3(at2.x, 0, at2.y), deg_to_rad(-62.0), 1,
			Tank.pick_kind("lav", 1, i))
		pv.ai = true


func _parked_jet(id: String) -> Node3D:
	var src: Node3D = _parked.get(id)
	if src != null and is_instance_valid(src):
		return src.duplicate() as Node3D
	var m := JetFactory.build(JetSpec.get_spec(id))
	var node: Node3D = m["root"]
	for h in m["stores"].values():
		h.visible = false
	_parked[id] = node
	return node


## Both sides keep something in orbit. They are not decoration: an ASAT
## launcher has nothing else it can shoot at, and shooting one down is the only
## way to take it away from whoever owns it.
func launch_constellation() -> void:
	# Spread across the sky over the theatre, not right round the planet.
	#
	# The tracks are real great circles about the planet's centre now, so a phase
	# is a place on the globe rather than a place on a forty kilometre loop. At a
	# sixth of a turn apart the constellation was strung round the whole world
	# and the furthest hostile satellite was twelve thousand kilometres from the
	# launcher: a correct orbit and an impossible shot. The reach is what sizes
	# this -- an ASAT that has to be able to make the furthest shot in the
	# constellation, which is what `--asattest` fires. Two hundredths of a radian
	# is about a hundred and thirty kilometres, the same span the old loop
	# covered, but laid out on the planet where it can be seen and flown to.
	var plan := [
		[0, "recon", 0.000, 0.10], [0, "comms", 0.012, -0.22], [0, "nav", -0.017, 0.32],
		[1, "recon", 0.020, -0.14], [1, "comms", -0.008, 0.26], [1, "nav", -0.021, -0.30],
	]
	for p in plan:
		var sat := Satellite.new()
		sat.centre = Vector3.ZERO
		sat.name = "%s %d" % [String(p[1]).capitalize(), int(p[0])]
		# Into the tree first: placing one works in global space and looks along
		# its own track, and neither means anything to a node with no parent.
		world.add_child(sat)
		sat.setup(int(p[0]), String(p[1]), float(p[2]), float(p[3]))
	print("[orbit] %d satellites on station" % plan.size())
