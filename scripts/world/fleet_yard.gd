class_name FleetYard
extends RefCounted
## The ships: where there is water deep enough to put them, and building the
## carrier, the strike group and the fleets for a mission.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

## Water deep enough to float a hull in, near a wanted point.
##
## This used to walk due east in 900 m steps, which finds the sea on a world
## with one authored coast running north-south and nothing else. On a generated
## planet the water can be in any direction, and walking east off a continent
## walks 54 km further inland: the fleet was spawned on dry ground, the
## submarine among it, and every test that borrowed that submarine failed on a
## hull that would not move because it was buried in a hill.
##
## An outward spiral instead -- nearest first, so a hull still lands about where
## it was asked for -- and the deepest thing found if nothing is deep enough.
## Water a submarine can work in, not merely water: her ordered depth runs to
## 45 m, she draws about ten, and she keeps her keel two metres off the bottom.
## Sixty would do; eighty leaves a margin. A hundred and forty was over-cautious
## and put the fleet a hundred and seventy kilometres offshore, which is a long
## way from anything a boat has business being near.
const DEEP_ENOUGH := 80.0
## The missions that have a sea in them: the strike range hunts shipping, the
## sandbox is everything at once, and the boat does not sail alone.
const FLEET_MISSIONS := ["strike", "sandbox", "carrier"]
var fleet_count := 0
## Where the fleet is lying. Worked out once, when the carrier is put to sea,
## and used by everything that wants to be near her.
var fleet_anchor := Vector3(INF, INF, INF)


func _init(w: World) -> void:
	world = w


## The same search, but only a little way out: for a berth inside a formation
## that has already been anchored in deep water.
func deep_water_near(at: Vector3, rings: int) -> Vector3:
	if Sim.height_at(at.x, at.z) < Sim.sea_at(at.x, at.z) - 40.0:
		return at
	for ring in range(1, rings + 1):
		var r: float = float(ring) * 600.0
		for bi in 10:
			var a: float = TAU * (float(bi) / 10.0 + float(ring) * 0.17)
			var p := Vector3(at.x + cos(a) * r, at.y, at.z + sin(a) * r)
			if Sim.height_at(p.x, p.z) < Sim.sea_at(p.x, p.z) - 40.0:
				return p
	return at


## The nearest water deep enough to float a fleet in.
##
## The old search was a spiral of point samples out to 170 km, which was a long
## way when the world was a 1200 km square with a sea down one side. On a planet
## the chart sits on a country and a country has an interior: the fleet's berth
## came back 395 m *above* sea level with no ocean anywhere in range, and the
## ships were left standing on a hill. That is the "vessels are not in water"
## report, and no amount of widening the spiral fixes it -- 1680 samples cannot
## be spread over a million square kilometres.
##
## So: one batched sweep for the coast, then a walk back in toward the berth.
## The extension will answer a few thousand points in a single call, which buys
## a 1600 km reach for less time than the spiral took to fail at a tenth of it.
func deep_water(at: Vector3) -> Vector3:
	if Sim.height_at(at.x, at.z) < Sim.sea_at(at.x, at.z) - DEEP_ENOUGH:
		return at
	if not Sim.globe:
		return _deep_water_spiral(at)
	# Rings outward, so the first ring holding water is the nearest coast on any
	# bearing. Twenty kilometres between rings and 48 bearings is 3840 points --
	# fine enough that no strait narrower than a ring spacing is missed at the
	# range where it would matter.
	const STEP := 20_000.0
	const RINGS := 80
	const BEARINGS := 48
	var pts := PackedVector2Array()
	for ring in range(1, RINGS + 1):
		var r: float = float(ring) * STEP
		for bi in BEARINGS:
			# Bearings twisted ring by ring, so the samples do not line up into
			# spokes with unlooked-at wedges between them.
			var a: float = TAU * (float(bi) / float(BEARINGS)
				+ float(ring) * 0.041)
			pts.append(Vector2(at.x + cos(a) * r, at.z + sin(a) * r))
	var hit := _deepest_of(pts, DEEP_ENOUGH)
	if hit.x == INF:
		if OS.is_debug_build():
			print("[fleet] no water %.0f m deep within %.0f km of %s" % [
				DEEP_ENOUGH, STEP * RINGS * 0.001, str(Vector2(at.x, at.z).round())])
		return at
	# Back in along the bearing at a tenth of the ring spacing: the coarse sweep
	# found *a* deep patch, and the one worth anchoring in is the nearest edge
	# of it rather than wherever the ring happened to land.
	var line := PackedVector2Array()
	var here := Vector2(at.x, at.z)
	var span: float = here.distance_to(hit)
	var steps := int(span / (STEP * 0.1))
	for k in range(steps, 0, -1):
		line.append(here.lerp(hit, float(k) / float(steps + 1)))
	var closer := _deepest_of(line, DEEP_ENOUGH)
	var pick: Vector2 = hit if closer.x == INF else closer
	return Vector3(pick.x, at.y, pick.y)


## The first of `pts` with more than `want` metres of water under it, or an
## x of INF if none of them has. Order matters: the callers hand these in from
## nearest outward and take the first hit.
func _deepest_of(pts: PackedVector2Array, want: float) -> Vector2:
	var g: PackedFloat32Array = Sim.native.grounds_at_globe(pts)
	for i in pts.size():
		var p: Vector2 = pts[i]
		if Sim.sea_at(p.x, p.y) - g[i] > want:
			return p
	return Vector2(INF, INF)


## The original spiral, kept for the flat world, where 170 km really is most of
## the map and there is no batched planetary query to ask instead.
func _deep_water_spiral(at: Vector3) -> Vector3:
	var best := at
	var best_d := -1e9
	for ring in range(1, 140):
		var r: float = float(ring) * 1200.0
		for bi in 12:
			var a: float = TAU * (float(bi) / 12.0 + float(ring) * 0.13)
			var p := Vector3(at.x + cos(a) * r, at.y, at.z + sin(a) * r)
			var d: float = Sim.sea_at(p.x, p.z) - Sim.height_at(p.x, p.z)
			if d > DEEP_ENOUGH:
				return p
			if d > best_d:
				best_d = d
				best = p
	if OS.is_debug_build():
		print("[fleet] no water %.0f m deep within 170 km of %s; best was %.0f m" % [
			DEEP_ENOUGH, str(Vector2(at.x, at.z).round()), best_d])
	return best


## Put the squadron to sea, or take it off.
##
## It used to be built once at load and left there for good: ten hulls, each
## with its captain, its sensors and its guns, steaming round an anchorage
## twenty-four kilometres from a street fight that had no use for them -- and
## the hostile half of them a threat in missions that say they have none.
## Now it is there when the mission is fought at sea, or when you take a ship
## out yourself, and gone otherwise.
##
## Decided from the mission alone once a session is up, so every peer musters
## the same hulls under the same indices; what you chose to crew is your own
## business and must not change what the others have afloat.
func muster_fleet(mission: String, crewing: bool) -> void:
	var online: bool = world.net != null and world.net.active
	var want: bool = world._fleet_always or mission in FLEET_MISSIONS \
		or (crewing and not online)
	var have := false
	for sh in world.get_tree().get_nodes_in_group("ships"):
		var v := sh as Ship
		if v == null or v.fleet_idx < 0 or v.is_queued_for_deletion():
			continue
		have = true
		if not want:
			# out of the group now, not at the end of the frame: the mission
			# being set up in this same call must not find her
			v.remove_from_group("ships")
			v.remove_from_group("hittable")
			v.remove_from_group("boardable")
			v.queue_free()
	# The carrier before her screen, so the squadron forms on her anchorage.
	if want and not is_instance_valid(world.carrier):
		build_carrier()
	elif not want and is_instance_valid(world.carrier):
		_strike_carrier()
	if want and not have:
		build_fleet()
	elif not want:
		fleet_count = 0
	if world._boot_verbose:
		print("[fleet] %s: %d hulls at sea" % [mission,
			world.get_tree().get_nodes_in_group("ships").size()])


## One anchorage, found once, for the carrier and everything sailing with
## her. Her position was written down and never checked: on the flat world
## (24000, 1200) was open sea, and on the planet it is a country's interior.
## She was built on dry land with the terrain drawn over her -- which is
## what "spawned under sand" is -- while the fleet, which does look for
## water, put to sea somewhere else entirely and left her behind.
func build_carrier() -> void:
	if fleet_anchor.x == INF:
		fleet_anchor = deep_water(Vector3(24000.0, 0.0, 1200.0))
	world.carrier = Carrier.new()
	world.carrier.name = "Carrier"
	world.add_child(world.carrier)
	world.carrier.build(fleet_anchor, deg_to_rad(-18.0))


## Take her off the sea, and her deck out of the ground with her: a deck is
## part of `Sim.height_at`, and one left registered is a slab of invisible
## flight deck standing in the ocean for the next mission to land on.
func _strike_carrier() -> void:
	if not is_instance_valid(world.carrier):
		world.carrier = null
		return
	if world.carrier.occupied:
		world.carrier.mount(false)
	if is_instance_valid(world.hud) and world.hud.carrier == world.carrier:
		world.hud.carrier = null
	if is_instance_valid(world.pod) and world.pod.platform == world.carrier:
		world.pod.platform = null
	Sim.decks.erase(world.carrier.deck)
	for g in ["carrier", "boardable", "hittable"]:
		world.carrier.remove_from_group(g)
	world.carrier.queue_free()
	world.carrier = null


func build_fleet() -> void:
	# The anchorage the carrier is already lying in, so the squadron forms on
	# her instead of searching for water of its own and finding a different sea.
	var grp: Vector3 = fleet_anchor if fleet_anchor.x < INF \
		else Vector3(24000.0, 0.0, 1200.0)
	var plan := [
		["destroyer", Vector3(2600, 0, -1800), -18.0, 0],
		["type45",    Vector3(-2200, 0, 2400), -18.0, 0],
		["frigate",   Vector3(3800, 0, 3100), -18.0, 0],
		["sub",       Vector3(-4200, 0, -3400), -22.0, 0],
		["patrol",    Vector3(900, 0, 4200), -10.0, 0],
		["corvette",  Vector3(12000, 0, -9000), 140.0, 1],
		["type45",    Vector3(15500, 0, -12500), 140.0, 1],
		["patrol",    Vector3(9500, 0, -14000), 155.0, 1],
		["cargo",     Vector3(-6000, 0, 16000), 95.0, 2],
		["cargo",     Vector3(20000, 0, 12000), 265.0, 2],
	]
	# One anchorage for the squadron, and the ships laid out around it. Deep
	# water can be a long way from where the fleet was asked for on a planet, so
	# it is found once and the formation carried to it whole.
	var anchor: Vector3 = grp if fleet_anchor.x < INF else deep_water(grp)
	for i in plan.size():
		var e: Array = plan[i]
		var sh := Ship.new()
		sh.setup(String(e[0]), int(e[3]))
		# Unique, so a second ship of the same class does not have its name
		# thrown away by the tree and replaced with "@Node3D@194".
		sh.name = "%s %d" % [sh.name, i + 1]
		sh.fleet_idx = i
		# every peer lays the same fleet down in the same order, so the index is
		# the whole address the network needs
		sh.ghost = world.net != null and world.net.active and not world.net.is_host
		world.add_child(sh)
		var at: Vector3 = anchor + (e[1] as Vector3)
		# The coast is ragged and the shelf runs out to about 24 km, so a berth
		# has to be checked rather than assumed: a boat on a shoal is inside the
		# terrain, and a missile leaving its tube detonates on the seabed.
		# A short look for a berth, not a long one. The anchorage was found
		# once for the whole group above; searching again from each ship, out to
		# 170 km, scattered a squadron that is supposed to be in company across
		# a quarter of an ocean -- and a submarine that cannot see one of her
		# own is a submarine with no side.
		at = deep_water_near(at, 4)
		# ...and if that found nothing, in toward the anchorage rather than
		# staying put. The formation reaches 24 km from its centre and the
		# short search covers 2.4 km of that, so on a ragged coast a berth can
		# be on a headland with no water within reach of it. The anchorage is
		# known to be deep, so walking back along the line to it always ends
		# somewhere wet, and ends as near the ship's station as the sea allows.
		if Sim.height_at(at.x, at.z) >= Sim.sea_at(at.x, at.z) - 40.0:
			for k in range(1, 13):
				var t: float = 1.0 - float(k) / 13.0
				var q := anchor + (at - anchor) * t
				if Sim.height_at(q.x, q.z) < Sim.sea_at(q.x, q.z) - 40.0:
					at = q
					break
		sh.global_position = Vector3(at.x, Sim.sea_surface(at.x, at.z), at.z)
		sh.heading = deg_to_rad(float(e[2]))
	fleet_count = plan.size()
