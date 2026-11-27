class_name TankLaunchers
extends RefCounted
## The launchers a vehicle can carry: surface-to-air rounds (a battery's, a short range air defence vehicle's), the anti-satellite round, and the strategic TELs with their warheads and marks. Split out of `tank.gd`; every vehicle has one as `launchers`.

var tk: Tank

func _init(owner_node: Tank) -> void:
	tk = owner_node

## Where a warhead's mark is now. A mark is either a patch of ground (a
## Vector3) or a unit that was clicked on, and a unit is followed: the warhead
## is locked on it, not on the spot it was standing on when it was picked.
static func mark_at(mk: Variant) -> Vector3:
	if mk is Vector3:
		return mk
	if is_instance_valid(mk) and mk is Node3D:
		return (mk as Node3D).global_position
	return Vector3.INF

## The unit a mark is locked on, or null for a patch of ground.
static func mark_unit(mk: Variant) -> Node3D:
	if mk is Node3D and is_instance_valid(mk):
		return mk
	return null

## Every warhead's mark, primary first: what the fire mission will hand the
## bus. Units that have died since they were picked are dropped.
func warhead_marks() -> Array:
	var out: Array = []
	if is_instance_valid(tk.map_lock):
		out.append(tk.map_lock)
	elif tk.map_target != Vector3.INF:
		out.append(tk.map_target)
	for mk in tk.mirv_marks:
		if mark_at(mk) != Vector3.INF:
			out.append(mk)
	return out

## How many warheads the round on the rail carries; nought for a single one.
func warheads() -> int:
	return int(WeaponSpec.get_spec(String(VehicleSpec.KINDS[tk.kind].get("missile", "kalibr"))).get("mirv", 0))

## Is there anything worth standing the canister up for? It goes back down when
## there is not, because a launcher sitting on the road with its tube in the air
## is a launcher that has already been seen.
func erect_wanted() -> bool:
	if tk.rounds_left <= 0 or not tk.alive:
		return false
	if tk.vclass() == "asat":
		return is_instance_valid(nearest_satellite())
	if tk.map_target != Vector3.INF:
		return true
	if is_instance_valid(tk._ai_target):
		return true
	return tk.occupied

## Sending a round at something in orbit. The only target this vehicle has is a
## satellite: everything in the atmosphere is somebody else's problem, and the
## round is far too large and far too slow to turn to be any use against it.
func fire_asat(world: Node, kd: Dictionary) -> bool:
	if tk.rounds_left <= 0:
		return false
	var tgt: Node3D = nearest_satellite()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in orbit to shoot at" % tk.display_name(), Sim.Ev.BAD)
		return false
	if tk._erect < 0.97:
		Sim.report("%s: erecting — %d%%" % [tk.display_name(), int(tk._erect * 100.0)],
			Sim.Ev.INFO)
		return false
	tk._gun_cd = float(kd["reload"])
	tk.rounds_left -= 1
	var from: Vector3 = tk._muzzle.global_position
	var dir := -tk._muzzle.global_transform.basis.z
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("missile", "asat")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 30.0, tk, tgt)
	world.add_child(m)
	tk.store_released.emit(m)
	Sim.report("%s: ASAT away at %s" % [tk.display_name(),
		tgt.call("display_name") if tgt.has_method("display_name") else "orbital contact"],
		Sim.Ev.BAD)
	return true

## Where the round has to be pointed. The satellite is doing eleven hundred
## metres a second and the round takes the better part of a minute to get up
## there, so the tube is laid on where it WILL be, not where it is.
func _asat_lead(sat: Node3D) -> Vector3:
	var aim: Vector3 = sat.global_position
	var tv := Vector3.ZERO
	if sat.has_method("get_velocity"):
		tv = sat.call("get_velocity")
	# average speed over the climb, which is most of the burn plus the coast
	var tof: float = tk.global_position.distance_to(aim) / 2200.0
	return aim + tv * clampf(tof, 0.0, 120.0)

func asat_bearing(sat: Node3D) -> float:
	var to: Vector3 = _asat_lead(sat) - tk.global_position
	return atan2(to.x, -to.z)

## Launch elevation, from the geometry rather than from a constant. Steep, but
## not vertical unless the thing is actually overhead.
func asat_elevation() -> float:
	var sat := nearest_satellite()
	if not is_instance_valid(sat):
		return Tank.ERECT_ANGLE
	var to: Vector3 = _asat_lead(sat) - tk.global_position
	var flat: float = Vector2(to.x, to.z).length()
	return clampf(atan2(to.y, maxf(flat, 1.0)), deg_to_rad(35.0), deg_to_rad(88.0))

## The hostile satellite that is easiest to reach: the one nearest overhead.
func nearest_satellite() -> Node3D:
	# Whatever was picked on the map wins: that is the whole point of being able
	# to pick one. Only if nothing is assigned does the crew choose for itself.
	var told: Node = Sim.sat_target
	if is_instance_valid(told) and (told is Node3D) \
			and (not ("team" in told) or int(told.team) != tk.team) \
			and (not told.has_method("is_alive") or told.is_alive()):
		return told as Node3D
	var best: Node3D = null
	var bd := 1e9
	for n in tk.get_tree().get_nodes_in_group("satellites"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		if ("team" in n) and n.team == tk.team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = tk.global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

## A battery sending a round. Unlike a launcher it has something to aim at —
## an aeroplane — and unlike a gun it does not have to be laid on it: the round
## leaves the rail on the launch elevation and turns onto the target itself.
func fire_sam(world: Node, kd: Dictionary) -> bool:
	if tk.rounds_left <= 0:
		return false
	var tgt: Node3D = tk._ai_target
	if not is_instance_valid(tgt):
		tgt = _nearest_air()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in the air to shoot at" % tk.display_name(), Sim.Ev.BAD)
		return false
	# never further than the round itself can fly
	var reach: float = minf(float(kd.get("reach", 60000.0)),
		float(WeaponSpec.get_spec(String(kd.get("missile", "sam_med"))).get("range", 60000.0)))
	# a radar-guided round: what its radar can see of the target is the limit
	if String(WeaponSpec.get_spec(String(kd.get("missile", "sam_med"))).get("kind", "")) == "radar":
		reach = Sim.radar_reach(reach, tgt)
	var rng: float = tk.global_position.distance_to(tgt.global_position)
	if rng > reach:
		Sim.report("%s: contact is %.0f km out, the round reaches %.0f" % [
			tk.display_name(), rng * 0.001, reach * 0.001], Sim.Ev.BAD)
		return false
	tk._gun_cd = float(kd["reload"])
	tk.rounds_left -= 1
	var from: Vector3 = tk._muzzle.global_position
	var dir := -tk._muzzle.global_transform.basis.z
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("missile", "sam_med")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 40.0, tk, tgt)
	world.add_child(m)
	tk.store_released.emit(m)
	Sim.report("%s: round away — %d on the rails" % [tk.display_name(), tk.rounds_left],
		Sim.Ev.GOOD)
	return true

## A gun vehicle's missile. Short ranged and infrared — it is the round you use
## on what the cannon cannot reach, not a substitute for a battery.
func fire_shorad(world: Node, kd: Dictionary) -> bool:
	if tk.sam_left <= 0:
		Sim.report("%s: no missiles left" % tk.display_name(), Sim.Ev.BAD)
		return false
	var tgt: Node3D = tk._ai_target if is_instance_valid(tk._ai_target) else _nearest_air()
	if not is_instance_valid(tgt):
		Sim.report("%s: nothing in the air to shoot at" % tk.display_name(), Sim.Ev.BAD)
		return false
	var reach: float = minf(float(kd.get("sam_reach", 4800.0)),
		float(WeaponSpec.get_spec(String(kd.get("sam_missile", "manpads"))).get("range", 5000.0)))
	var rng: float = tk.global_position.distance_to(tgt.global_position)
	if rng > reach:
		Sim.report("%s: contact is %.1f km out, the round reaches %.1f" % [
			tk.display_name(), rng * 0.001, reach * 0.001], Sim.Ev.BAD)
		return false
	tk.sam_left -= 1
	tk._gun_cd = 1.6
	var from: Vector3 = tk._muzzle.global_position
	var dir := (tgt.global_position - from).normalized()
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	m.launch(String(kd.get("sam_missile", "manpads")),
		Transform3D(Basis.looking_at(dir, up_ref), from), dir * 40.0, tk, tgt)
	world.add_child(m)
	tk.store_released.emit(m)
	Sim.report("%s: missile away — %d left" % [tk.display_name(), tk.sam_left], Sim.Ev.GOOD)
	return true

## The nearest hostile aircraft this battery can see.
func _nearest_air() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for n in tk.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(n) or not (n is Aircraft):
			continue
		if ("team" in n) and n.team == tk.team:
			continue
		if n.has_method("is_alive") and not n.is_alive():
			continue
		var d: float = tk.global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n as Node3D
	return best

## Send one. A TEL does not need to be laid the way a gun does — the round is
## guided and will turn onto the bearing itself — so all this has to do is get
## it off the rail cleanly and pointed up.
func fire_tel(world: Node, kd: Dictionary) -> bool:
	var mark: Vector3 = tk.map_target
	if is_instance_valid(tk.map_lock):
		mark = (tk.map_lock as Node3D).global_position
	# warheads marked but no primary: the bus goes for the first of them
	if mark == Vector3.INF and not tk.mirv_marks.is_empty():
		var rv0: Array = warhead_marks()
		if not rv0.is_empty():
			mark = mark_at(rv0[0])
	if mark == Vector3.INF:
		mark = tk.ground_aim()
	if mark == Vector3.INF and is_instance_valid(tk._ai_target):
		mark = tk._ai_target.global_position
	if mark == Vector3.INF:
		Sim.report("%s: no aiming point" % tk.display_name(), Sim.Ev.BAD)
		return false
	# the round's reach, not a shell's
	var spec := WeaponSpec.get_spec(String(kd.get("missile", "kalibr")))
	var rng := tk.global_position.distance_to(mark)
	if bool(spec.get("icbm", false)):
		# Over the ground, not through it. A quarter of the way round the
		# planet the straight line between two points in the world's own
		# coordinates is a third longer than the journey, and a round that
		# reaches thirteen thousand kilometres was refused a shot of that.
		rng = Vector2(mark.x - tk.global_position.x, mark.z - tk.global_position.z).length()
	if rng > float(spec.get("range", 100000.0)):
		Sim.report("%s: mark is %.0f km away, the round reaches %.0f" % [
			tk.display_name(), rng * 0.001,
			float(spec.get("range", 100000.0)) * 0.001], Sim.Ev.BAD)
		return false
	if tk._erect < 0.97:
		Sim.report("%s: erecting — %d%%" % [tk.display_name(), int(tk._erect * 100.0)],
			Sim.Ev.INFO)
		return false
	tk._gun_cd = float(kd["reload"])
	tk.rounds_left -= 1
	var id: String = String(kd.get("missile", "kalibr"))
	# Out of the tube it is actually sitting in, along the tube's own axis.
	# Spawning it in the air on a computed bearing meant the round never
	# appeared to leave the vehicle — it simply existed, already flying.
	var from: Vector3 = tk.global_position + Vector3(0, 3.0, 0)
	# Straight out of the tube, wherever the tube happens to be pointing, and
	# the tube points up. No lean onto the bearing: the round does that itself
	# once it is clear, and a canister launch that comes out already heading
	# for the target is the thing that made these look like guns.
	var dir := Vector3.UP
	if is_instance_valid(tk._muzzle):
		from = tk._muzzle.global_position
		dir = -tk._muzzle.global_transform.basis.z
	if bool(spec.get("icbm", false)):
		return _fire_icbm(world, id, from, mark, rng)
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var m := Missile.new()
	# Guide onto the unit itself when one was locked; onto a bare mark otherwise.
	var aim: Node3D = tk.map_lock as Node3D if is_instance_valid(tk.map_lock) else null
	if aim == null:
		var mk := _TelMark.new()
		mk.team = 1 if tk.team == 0 else 0
		world.add_child(mk)
		mk.global_position = mark
		aim = mk
	m.launch(id, Transform3D(Basis.looking_at(dir, up_ref), from), dir * 22.0,
		tk, aim)
	# The primary mark first, then whatever else has been assigned, so a bus
	# given two extra points still puts a warhead on the one you laid to begin
	# with rather than leaving it alone.
	var units := 0
	var rvs: Array = []
	if not tk.mirv_marks.is_empty() or (warheads() > 0 and is_instance_valid(tk.map_lock)):
		rvs = warhead_marks()
		if rvs.is_empty() or mark_at(rvs[0]) == Vector3.INF:
			rvs.push_front(mark)
		m.programmed = rvs
		for mk in rvs:
			if mark_unit(mk) != null:
				units += 1
	
	m.team = tk.team
	world.add_child(m)
	tk.store_released.emit(m)
	# Where it is going, not just that it has gone. A canister launch goes
	# straight up and turns over out of sight, so without this there is nothing
	# to tell you whether it is on its way to the mark or simply leaving.
	var brg: float = rad_to_deg(atan2(mark.x - from.x, -(mark.z - from.z)))
	Sim.report("%s: %s away — %.0f km on %03d, %d left" % [tk.display_name(),
		String(WeaponSpec.get_spec(id)["short"]), rng * 0.001,
		int(wrapf(brg, 0.0, 360.0)), tk.rounds_left], Sim.Ev.BAD)
	if not rvs.is_empty():
		Sim.report("%d warhead marks: %d locked on units, %d on ground points" % [
			rvs.size(), units, rvs.size() - units], Sim.Ev.INFO)
	# Spent with the round, so the next one's first click is RV1 again
	if warheads() > 0:
		tk.mirv_marks.clear()
		tk.map_lock = null
		tk.map_target = Vector3.INF
	return true

## An intercontinental round. It is not guided onto anything: every warhead it
## carries is given its own mark before it leaves, and the bus puts each on
## the arc that falls there. See `Icbm`.
func _fire_icbm(world: Node, id: String, from: Vector3, mark: Vector3, rng: float) -> bool:
	var targets: Array = warhead_marks()
	if targets.is_empty():
		targets = [mark]
	var live: Array = []
	for t in targets:
		# a unit is followed; a patch of ground is where it was put
		if t is Node:
			if is_instance_valid(t):
				live.append(t)
		elif mark_at(t) != Vector3.INF:
			live.append(mark_at(t))
	if live.is_empty():
		live = [mark]
	var m := Icbm.launch(world, id, from, tk, tk.team, live)
	tk.store_released.emit(m)
	var brg: float = rad_to_deg(atan2(mark.x - from.x, -(mark.z - from.z)))
	var spec := WeaponSpec.get_spec(id)
	Sim.report("%s: %s away — %.0f km on %03d, %d warheads on %d marks" % [
		tk.display_name(), String(spec["short"]), rng * 0.001,
		int(wrapf(brg, 0.0, 360.0)), int(spec.get("mirv", 1)), live.size()], Sim.Ev.BAD)
	Sim.report("three stages, then it coasts: . and , change the time warp while it is above the air",
		Sim.Ev.INFO)
	tk.mirv_marks.clear()
	tk.map_lock = null
	tk.map_target = Vector3.INF
	return true

## A place for the round to guide onto. A patch of ground is not a contact, so
## it is deliberately not lockable and not a radar return.
class _TelMark extends Node3D:
	var team := 1
	func _ready() -> void:
		add_to_group("no_lock")
	func hit_radius() -> float:
		return 6.0
	func is_alive() -> bool:
		return true
	func take_hit(_a: float, _f: Node = null) -> void:
		pass
