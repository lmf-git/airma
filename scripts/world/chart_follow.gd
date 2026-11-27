class_name ChartFollow
extends RefCounted
## Keeps the chart under the player: when they travel far enough from its
## centre the world is recharted around them, and everything that holds a
## position is carried across.
##
## Split out of `world.gd`, whose state it works on through `world`.

var world: World

## How far the player may get from the middle of the chart before it is moved
## under them. Far enough that it happens rarely, near enough that the chart's
## own distortion stays negligible: at 150 km the azimuthal projection stretches
## by four parts in a hundred thousand.
const RECHART_AT := 150_000.0
const RECHART_HIGH := 600_000.0
const RECHART_WARP := 2_500_000.0
## Move the chart under a new point, taking the world with it.
##
## This is the floating origin, and it is what makes the rest of the planet
## reachable rather than merely visible. Chart coordinates are offsets from the
## middle of the chart, so moving the chart renumbers every position in the
## game at once. Everything that is somewhere has to be renumbered with it, or
## the world stays still and only the ground moves.
##
## Heights are carried as height *above the local sea* rather than as `y`. The
## sea itself is at a different `y` under the new chart -- that is what the
## planet curving away from the middle means -- so keeping `y` would put an
## aeroplane at 3000 ft into the ground the moment the chart moved.
var _rechart_n := 0
var _rechart_worst := 0
## The aerodromes and the painted-ground spots as they were built: see
## `_carry_fixed`.
var _bases_laid: Array = []
var _mask_laid: Array = []
## The chart has moved and the ground under it has not been rebuilt yet.
var _chart_owed := false


func _init(w: World) -> void:
	world = w


func rechart(dir: Vector3) -> void:
	if not Sim.globe:
		return
	_rechart_n += 1
	# Timed, because it all happens in one frame and it is the largest single
	# thing the game ever does while you are flying: every position in the world
	# renumbered, every terrain chunk rebuilt, and two sheets rasterised.
	var _rc := Time.get_ticks_msec()
	var movers: Array = []
	# The capture zones as well: a zone is a flag and a ring standing over a
	# town, and it stayed at its old numbers while the town was carried away
	# from under it.
	for g in ["hittable", "vehicles", "ships", "satellites", "walkers", "zones"]:
		for n in world.get_tree().get_nodes_in_group(g):
			if n is Node3D and not movers.has(n):
				movers.append(n)
	if is_instance_valid(world.player) and not movers.has(world.player):
		movers.append(world.player)
	# What was built once, as it stands on the chart the world was built on --
	# taken before the first move, while that is still the chart.
	if _bases_laid.is_empty() and not Sim.off_boot_chart():
		for ab in world.bases:
			if is_instance_valid(ab):
				_bases_laid.append([ab, (ab as Node3D).transform])
		_mask_laid = world._mask_spots.duplicate()
	# Read everything in the old chart before the chart moves.
	var was: Array = []
	for m in movers:
		var p: Vector3 = (m as Node3D).global_position
		was.append([Sim.chart_to_dir(p.x, p.z), p.y - Sim.sea_shell(p.x, p.z)])
	# The chart's old frame, so the world's works can be carried across it.
	var o0: Vector3 = Sim.chart_origin
	var e0: Vector3 = Sim.chart_east
	var s0: Vector3 = Sim.chart_south
	Sim.set_chart(dir)
	# Roads, towns and aerodromes are stored as chart pairs, so they move with
	# the chart unless they are moved back.
	Sim.rechart_world(o0, e0, s0)
	# The aerodromes before what is parked on them: a parked jet is a child of
	# its base and may be a mover as well, and a mover is put where it belongs
	# outright below.
	for e in _bases_laid:
		var ab2: Node3D = e[0]
		if is_instance_valid(ab2):
			var bx: Transform3D = e[1]
			ab2.transform = Sim.boot_affine(bx.origin) * bx
	for i in movers.size():
		var m2: Node3D = movers[i]
		var rec: Array = was[i]
		var q: Vector2 = Sim.dir_to_chart(rec[0])
		m2.global_position = Vector3(q.x,
			Sim.sea_shell(q.x, q.y) + float(rec[1]), q.y)
		if m2 is RigidBody3D:
			world._reset_interp.call_deferred(m2)
	# From above the air there is no ground to rebuild and no chart sheet
	# anybody can be looking at the country on: the planet is one sphere with a
	# picture on it. Something in orbit moves the chart every minute or so, and
	# on time warp many times a second, and paying a quarter of a second for
	# terrain that is switched off each time is most of the frame. The world is
	# renumbered now -- that part has to be -- and the ground and the sheets
	# are owed, and paid once when the eye comes back down: see `_settle_chart`.
	var sub: Node3D = _chart_subject()
	# The satellite view the same: panning over the planet from orbit moved the
	# chart every few hundred kilometres and paid the full price each time --
	# the ground, the towns and the map sheet, none of them drawn -- seconds
	# a move.
	if (sub is LaunchVehicle or sub is Icbm or sub is SatView) and is_instance_valid(world.planet) \
			and world.planet.dormant:
		# The towns and the obstacle field with them: nobody can see a street
		# from orbit, and carrying twenty thousand boxes several times a second
		# on time warp is the same waste the ground would be.
		_chart_owed = true
		_rechart_worst = maxi(_rechart_worst, Time.get_ticks_msec() - _rc)
		if world._boot_verbose:
			print("[rechart] in space: %d ms" % (Time.get_ticks_msec() - _rc))
		return
	_chart_owed = false
	var _rc_fixed := Time.get_ticks_msec()
	_carry_fixed()
	_rc_fixed = Time.get_ticks_msec() - _rc_fixed
	# The ground is numbered in the same coordinates, so all of it is stale.
	if is_instance_valid(world.terrain):
		world.terrain.recentre(Vector3.ZERO, true)
	var _rc_ground := Time.get_ticks_msec()
	# ...and so is the map's close-in sheet, which is a picture of the country
	# under the chart rather than of a fixed square of world.
	var _rc_sheet := 0
	if is_instance_valid(world.map):
		var t_s := Time.get_ticks_msec()
		world.map.rechart()
		_rc_sheet = Time.get_ticks_msec() - t_s
	# The ground works its climate out from where it is on the planet, and it
	# has just been told the chart is somewhere else.
	var _rc_clim := 0
	if is_instance_valid(world.terrain):
		var t_c := Time.get_ticks_msec()
		world.terrain.rechart()
		_rc_clim = Time.get_ticks_msec() - t_c
	_rechart_worst = maxi(_rechart_worst, Time.get_ticks_msec() - _rc)
	print("[rechart] %d ms: renumbering and the ground %d (the built works %d), the map sheet %d, the climate %d — the last two are asked for, not waited on" % [
		Time.get_ticks_msec() - _rc, _rc_ground - _rc, _rc_fixed, _rc_sheet, _rc_clim])


## Carry everything built once into the chart there is now.
##
## The towns and everything else the scenery put down, the obstacle field that
## makes them solid, the aerodromes and where the painted ground is centred.
## None of these were ever moved by a chart move, so all of them were left at
## their old numbers -- which in the new chart are another place, at a height
## that belonged to other ground. That is what put towns in the sea. All of it
## is carried from where it was built rather than from wherever the last move
## left it, so it cannot drift however many times the chart moves.
func _carry_fixed() -> void:
	if is_instance_valid(world.scenery):
		world.scenery.rechart()
	Obstacles.recharted()
	if is_instance_valid(world.obstacles):
		# the few real bodies near the eye are rebuilt on the next look round,
		# and the bridge spans' from the moved decks
		world.obstacles._near_at = Vector3(1e12, 0.0, 1e12)
		world.obstacles._span_src = []
	for i in mini(world._mask_spots.size(), _mask_laid.size()):
		var m: Vector2 = _mask_laid[i]
		var w: Vector3 = Sim.boot_to_world(Vector3(m.x, 0.0, m.y))
		world._mask_spots[i] = Vector2(w.x, w.z)


## Keep the chart under the player. Called every frame; does nothing almost
## every frame, which is the point of the threshold.
func follow_chart() -> void:
	if not Sim.globe:
		return
	_settle_chart()
	var who: Node3D = _chart_subject()
	if who == null:
		return
	var p: Vector3 = who.global_position
	# Above the air the ground is one sphere with a picture on it and there is
	# nothing to line up against, so the chart can be let run further before
	# it is moved -- which matters, because something in orbit covers the
	# usual hundred and fifty kilometres every nineteen seconds.
	var reach: float = RECHART_AT
	if p.y + Sim.planet_drop(p.x, p.z) > 100000.0:
		# and further still on time warp, when it would otherwise be moved
		# several times a second
		reach = RECHART_HIGH if Sim.space_rate < 10.0 else RECHART_WARP
		# and the satellite view, which pans thousands of kilometres a minute,
		# as far as the chart holds true (`Sim.dir_to_chart` is exact over the
		# near hemisphere)
		if who is SatView:
			reach = RECHART_WARP
	if Vector2(p.x, p.z).length() < reach:
		return
	rechart(Sim.chart_to_dir(p.x, p.z))


## Pay what a chart move in space left owing, once the ground is wanted again.
func _settle_chart() -> void:
	if not _chart_owed or (is_instance_valid(world.planet) and world.planet.dormant):
		return
	_chart_owed = false
	_carry_fixed()
	if is_instance_valid(world.terrain):
		world.terrain.recentre(Vector3.ZERO, true)
		world.terrain.rechart()
	if is_instance_valid(world.map):
		world.map.rechart()


## What the chart is kept under: the thing the view is on. That was always the
## aeroplane, which is right for as long as the aeroplane is what goes
## somewhere. A spacecraft goes round the planet, and a warhead being ridden
## down onto another continent arrives over ground that would otherwise never
## have been built -- the far side of the world, seen from a camera standing
## in nothing.
func _chart_subject() -> Node3D:
	# the satellite view, while it is up: the ground has to be built where it
	# is looking, not where the player was left
	if is_instance_valid(world.sat_view) and world.sat_view.active():
		return world.sat_view
	if is_instance_valid(world.rocket) and world.rocket.occupied:
		return world.rocket
	if is_instance_valid(world.cam):
		var ridden: Variant = (world.cam as Node).get("weapon_cam")
		if ridden != null and is_instance_valid(ridden) and ridden is Icbm:
			return ridden
	if is_instance_valid(world.player):
		return world.player
	return null


## Whose aerodrome the opposition flies from: the nearest country that is not
## the one this sortie began in.
func _nearest_other() -> String:
	var best := ""
	var best_d := 1e30
	for who in Sim.HOMELANDS.keys():
		if String(who) == Sim.home_faction:
			continue
		var d: float = Sim.dir_to_chart(Sim.homeland_dir(String(who))).length()
		if d < best_d:
			best_d = d
			best = String(who)
	return best
