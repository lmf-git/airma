class_name MissileBus
extends RefCounted
## A multiple-warhead round's bus: coasting to where it opens, opening, sending each warhead after its mark or the nearest thing to it, and saying in the log where they went. Split out of `missile.gd`; every round has one as `bus`.

var ms: Missile



func _init(owner_node: Missile) -> void:
	ms = owner_node

## Keep flying the last place the target was, for a weapon that is aimed at
## the ground rather than at a thing. A missile has nothing to coast to.
func coast_to_mark(_delta: float) -> void:
	# Bombs and cruise weapons both aim at a place. A cruise missile whose ship
	# is sunk by somebody else on the way in should still arrive; it used to
	# carry straight on and hit the sea.
	# Every kind, not just those two. A ballistic round got no guidance at all
	# here and simply kept thrusting along its nose -- and a Khorramshahr's nose
	# is pointed up, with three hundred metres a second squared behind it for
	# a hundred and forty seconds. Losing the lock on a vehicle sent it to
	# sixteen hundred kilometres and it never came back down. A round sent to a
	# coordinate does not need to see anything to arrive: that is what an
	# inertial mark is for, and `_last_aim` has held one all along.
	var k := String(ms.ws["kind"])
	if ms._last_aim == Vector3.INF:
		return
	# A seduced round is following the decoy, and the decoy is moving: it left
	# the aeroplane at most of the aeroplane's speed and is falling behind it.
	if ms._seduced:
		if ms._decoy_ir:
			ms._decoy_vel = ms._decoy_vel.lerp(Vector3(0, -16.0, 0), clampf(_delta * 0.55, 0.0, 1.0))
		else:
			ms._decoy_vel = ms._decoy_vel.lerp(Vector3.DOWN * 3.0, clampf(_delta * 2.2, 0.0, 1.0))
		ms._last_aim += ms._decoy_vel * _delta
	var v_dir := ms.vel.normalized() if ms.vel.length() > 1.0 else -ms.global_transform.basis.z
	var want_dir := (ms._last_aim - ms.global_position).normalized()
	# A bomb and a cruise round steer hard onto the line. A ballistic round
	# trims the arc it is already flying, the same authority its own guidance
	# uses -- hauling one onto the line of sight at 2.6 would have it fighting
	# its own trajectory the whole way down.
	var gain: float = 2.6 if (k == "bomb" or k == "cruise" or ms._seduced) else 1.1
	var accel := (want_dir - v_dir) * maxf(ms.vel.length(), 90.0) * gain
	var g_max: float = ms.ws["max_g"] * 9.81
	if accel.length() > g_max:
		accel = accel.normalized() * g_max
	ms.vel += accel * _delta



## Let the load go. Each child is thrown off the bus with a little sideways
## velocity, so by the time they are down they cover a footprint rather than
## all arriving at the same point — which would be a very expensive way of
## building one crater.
func open_up() -> void:
	if ms._split:
		return
	ms._split = true
	var _kids: Array = []
	var count: int = int(ms.ws.get("mirv", 0))
	var child: String = String(ms.ws.get("mirv_child", ""))
	if count <= 0 or child == "":
		return
	var spread: float = float(ms.ws.get("mirv_spread", 400.0))
	# how long the children have left to fall decides how much sideways speed
	# it takes to cover the footprint
	var bed: float = maxf(Sim.height_at(ms.global_position.x, ms.global_position.z),
		Sim.sea_at(ms.global_position.x, ms.global_position.z))
	var fall: float = sqrt(maxf(2.0 * maxf(ms.global_position.y - bed, 10.0) / 9.81, 0.5))
	var lateral: float = spread / maxf(fall, 0.5)
	var fwd := ms.vel.normalized() if ms.vel.length() > 1.0 else -ms.global_transform.basis.z
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.1:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	# One aim point per warhead.
	#
	# Every child was launched at the bus's own target, so a dozen of them flew
	# the same intercept onto the same coordinate: they arrived as a column
	# rather than a footprint, and anything standing fifty metres to the side of
	# the mark was untouched by all twelve. Each one takes a hostile of its own
	# where there are enough of them, and a distinct patch of the footprint
	# where there are not.
	var marks: Array = []
	var centre: Vector3 = ms.target.global_position if is_instance_valid(ms.target) \
		else ms.global_position
	# Programmed points first, where somebody has laid them. This is the whole
	# difference between a cluster and a MIRV: one scatters over a footprint,
	# the other is aimed, warhead by warhead.
	#
	# A programmed mark is a patch of ground or a unit. A unit is handed to the
	# warhead as its target -- locked on and followed -- rather than the point
	# it was standing on when it was picked.
	var aimed := not ms.programmed.is_empty()
	if aimed:
		for i2 in count:
			var pm: Variant = ms.programmed[i2 % ms.programmed.size()]
			var live: bool = is_instance_valid(pm) and pm is Node3D \
				and (not pm.has_method("is_alive") or pm.is_alive())
			# A spare warhead -- more of them than marks -- looks round its
			# mark for something nobody has yet, so one click on a vehicle in
			# a column spreads the load down the column rather than putting
			# all of it on the one hull.
			if live and i2 >= ms.programmed.size():
				var spare: Node3D = _acquire_near((pm as Node3D).global_position,
					maxf(spread, 1500.0), marks)
				marks.append(spare if spare != null else pm)
				continue
			if live:
				marks.append(pm)
				continue
			var spot: Vector3 = pm if pm is Vector3 else centre
			# A point laid next to something is a point laid *on* it: the click
			# that was meant for a ship and landed a few hundred metres off it
			# put the warhead in the water beside her. The warhead's seeker
			# takes the nearest enemy close to its point, one each where there
			# are enough to go round.
			var near: Node3D = _acquire_near(spot, maxf(spread, 1500.0), marks)
			if near != null:
				marks.append(near)
				continue
			var pt2 := _Submark.new()
			pt2.team = 1 if ms.team == 0 else 0
			ms.get_tree().current_scene.add_child(pt2)
			pt2.global_position = spot
			marks.append(pt2)
	for n in (ms.get_tree().get_nodes_in_group("hittable") if marks.is_empty() else []):
		if not is_instance_valid(n) or n.is_in_group("no_lock") or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if ("team" in n) and int(n.team) == ms.team:
			continue
		if (n as Node3D).global_position.distance_to(centre) < spread * 1.6:
			marks.append(n)
	# nearest first when the bus picked them itself; in the order laid when
	# somebody laid them, so RV1 is the first warhead out
	if not aimed:
		marks.sort_custom(func(x: Node3D, y: Node3D) -> bool:
			return x.global_position.distance_to(centre) \
				< y.global_position.distance_to(centre))
	for i in count:
		var a := TAU * float(i) / float(count) + randf() * 0.3
		var rad: float = lerpf(0.35, 1.0, randf())
		var kick: Vector3 = (right * cos(a) + up * sin(a)) * lateral * rad
		var m := Missile.new()
		m.harmless = ms.harmless
		var dir: Vector3 = (ms.vel + kick).normalized()
		var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
		var xf := Transform3D(Basis.looking_at(dir, up_ref), ms.global_position)
		# its own warhead, its own target
		var mine: Node = ms.target
		if i < marks.size():
			mine = marks[i]
		elif not marks.is_empty():
			mine = marks[i % marks.size()]
		else:
			# nothing to pick from: spread them over the footprint instead
			var off := Vector3(cos(a), 0.0, sin(a)) * spread * rad
			var pt := _Submark.new()
			pt.team = 1 if ms.team == 0 else 0
			ms.get_tree().current_scene.add_child(pt)
			pt.global_position = centre + off
			mine = pt
		m.launch(child, xf, ms.vel + kick, ms.shooter, mine)
		m.team = ms.team
		ms.get_tree().current_scene.add_child(m)
		_kids.append(m)
	for k in _kids:
		(k as Missile).siblings = _kids
	_report_split(_kids)
	# Hand the camera on. The bus frees itself here, so anything riding it lost
	# its subject the moment the load went — the view cut back to the launcher
	# and you never saw the warheads arrive, which reads as the round simply
	# never landing.
	var scn := ms.get_tree().current_scene
	if scn != null and scn.has_method("hand_weapon_cam") and not _kids.is_empty():
		scn.call("hand_weapon_cam", ms, _kids[0])
	if Sim.debug_weapons:
		print("[msl] %s opened at %.0f m: %d x %s over about %.0f m" % [
			ms.wid, ms.global_position.y - bed, count, child, spread])
	Effects.explosion(ms.get_tree().current_scene, ms.global_position, 5.0, false)
	ms.queue_free()



## A patch of ground for one warhead of a cluster, when there is nothing there
## worth naming. Deliberately not lockable and not a radar return.
## The enemy unit nearest a point, within `reach`, preferring one that none of
## `taken` is already going for.
func _acquire_near(spot: Vector3, reach: float, taken: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in ms.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or n.is_in_group("no_lock") or not (n is Node3D):
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		if ("team" in n) and int(n.team) == ms.team:
			continue
		# neutral shipping is not an enemy
		if ("team" in n) and int(n.team) != 0 and int(n.team) != 1:
			continue
		var p: Vector3 = (n as Node3D).global_position
		var d: float = Vector2(p.x - spot.x, p.z - spot.z).length()
		if d > reach:
			continue
		# one already spoken for counts as twice as far, so the load spreads
		# over what is there before it doubles up
		if taken.has(n):
			d = d * 2.0 + reach
		if d < best_d:
			best_d = d
			best = n
	return best

## Say where the load has gone, in the event log, when it is the player's.
##
## The log said the round was away and how far, and nothing after it: once
## the bus opened there was no telling whether its warheads had found the
## vehicles they were given or were coming down on empty ground. One line for
## the opening and one per unit locked on, naming the warheads going for it.
func _report_split(kids: Array) -> void:
	if not is_instance_valid(ms.shooter) or not ("occupied" in ms.shooter) \
			or not bool(ms.shooter.get("occupied")):
		return
	var by_unit := {}
	var order: Array = []
	var ground := PackedStringArray()
	for i in kids.size():
		var k: Missile = kids[i]
		var tag := "RV%d" % (i + 1)
		if k.locked_on_unit():
			var key: int = k.target.get_instance_id()
			if not by_unit.has(key):
				by_unit[key] = []
				order.append(k.target)
			# an Array, not a PackedStringArray: those are values, and appending
			# to one taken out of a dictionary appends to a copy
			(by_unit[key] as Array).append(tag)
		else:
			ground.append(tag)
	Sim.report("%s opened: %d warheads — %d locked on %d unit(s), %d on ground points" % [
		String(ms.ws["short"]), kids.size(), kids.size() - ground.size(), order.size(),
		ground.size()], Sim.Ev.INFO)
	for u in order:
		var tags := PackedStringArray(by_unit[(u as Node).get_instance_id()])
		Sim.report("%s locked on %s — %.1f km" % [", ".join(tags), Sim.label_of(u),
			ms.global_position.distance_to((u as Node3D).global_position) * 0.001],
			Sim.Ev.GOOD)
	if not ground.is_empty() and not order.is_empty():
		Sim.report("%s on ground points" % ", ".join(ground), Sim.Ev.INFO)

class _Submark extends Node3D:
	var team := 1
	func _ready() -> void:
		add_to_group("no_lock")
	func hit_radius() -> float:
		return 4.0
	func is_alive() -> bool:
		return true
	func take_hit(_a: float, _f: Node = null) -> void:
		pass
