class_name InfantryTests
extends TestSuite
## On foot: the street fight, small arms, the firing range and walking.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--obstest":
		_obs_test = true
	elif a == "--gibtest":
		_gib_test = true
	elif a == "--roundtest":
		_round_test = true
	elif a == "--pronetest":
		_prone_test = true
	elif a == "--yawtest":
		_yaw_test = true
	elif a == "--zoomtest":
		_zoom_test = true
	elif a == "--armstest":
		_arms_test = true
	elif a == "--steadytest":
		_steady_test = true
	elif a == "--holdfire":
		_holdfire = true
	elif a == "--zerotest":
		_zero_test = true
	elif a == "--ladderfall":
		_ladder_fall = true
	elif a == "--ruintest":
		_wreck_test = true
	elif a == "--mortartest":
		_mortar_test = true
	elif a == "--balltest":
		_ball_test = true
	elif a == "--boundstest":
		_bounds_test = true
	elif a == "--steertest":
		# with --preset=ground:veh:KIND --cqbtest: which way does right turn it
		_steer_test = true
		world.street_fight._cqb_test = true
	elif a == "--cqbtest":
		# with --preset=cqb: watch a street fight run and say what happened
		world.street_fight._cqb_test = true
	elif a.begins_with("--cqbfix="):
		_cqb_fix = a.substr(9)
	elif a == "--aimtest":
		_aim_test = true
	elif a == "--sighttest":
		_sight_test = true
	else:
		return false
	return true


#region --obstest
## The obstacle grid against every box, one by one, round a real town.
var _obs_test := false

func tick_obs() -> void:
	if _obs_test and is_instance_valid(world.cqb):
		_obs_test = false
		_run_obs_test()

## The obstacle grid answers from the cells a query touches; this asks the same
## questions of every box in the field, one at a time, and compares. Points,
## padded points, feet, floors, roofs, rifle-round steps and sight lines across
## the town, plus a few long lines out of it.
func _run_obs_test() -> void:
	var c := Vector3(world.cqb.centre.x, 0.0, world.cqb.centre.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad: Array = []
	var n_ent: int = Obstacles._dead.size()
	var inside := func(id: int, p: Vector3, r: float, feet: bool) -> bool:
		var b: int = id * Obstacles.STRIDE
		var e: PackedFloat32Array = Obstacles._ent
		var dy: float = p.y - e[b + 1]
		if feet:
			if dy < -1.85 or dy >= e[b + 4] - 0.02:
				return false
		elif dy < -r or dy > e[b + 4] + r:
			return false
		var dx: float = p.x - e[b]
		var dz: float = p.z - e[b + 2]
		var lx: float = dx * e[b + 6] + dz * e[b + 7]
		var lz: float = -dx * e[b + 7] + dz * e[b + 6]
		return absf(lx) <= e[b + 3] + r and absf(lz) <= e[b + 5] + r
	var seg_ref := func(a: Vector3, z: Vector3) -> float:
		var best := 1.0
		var d: Vector3 = z - a
		var e: PackedFloat32Array = Obstacles._ent
		for id in n_ent:
			# rounds and sight stop on soft entries too
			if Obstacles._dead[id] == Obstacles.GONE:
				continue
			var b: int = id * Obstacles.STRIDE
			var cs: float = e[b + 6]
			var sn: float = e[b + 7]
			var ox: float = a.x - e[b]
			var oz: float = a.z - e[b + 2]
			var p3 := Vector3(ox * cs + oz * sn, a.y - e[b + 1], -ox * sn + oz * cs)
			var v3 := Vector3(d.x * cs + d.z * sn, d.y, -d.x * sn + d.z * cs)
			var lo := Vector3(-e[b + 3], 0.0, -e[b + 5])
			var hi := Vector3(e[b + 3], e[b + 4], e[b + 5])
			var t0 := 0.0
			var t1 := best
			var miss := false
			for ax in 3:
				if absf(v3[ax]) < 1e-7:
					if p3[ax] < lo[ax] or p3[ax] > hi[ax]:
						miss = true
						break
				else:
					var ta: float = (lo[ax] - p3[ax]) / v3[ax]
					var tb: float = (hi[ax] - p3[ax]) / v3[ax]
					t0 = maxf(t0, minf(ta, tb))
					t1 = minf(t1, maxf(ta, tb))
					if t0 > t1:
						miss = true
						break
			if not miss:
				best = t0
		return best
	var counts := {"hit": 0, "blocks": 0, "floor": 0, "top": 0, "step": 0, "sight": 0, "long": 0}
	var t_new := 0
	for i in 3000:
		var p := Vector3(c.x + rng.randf_range(-150, 150), 0.0, c.z + rng.randf_range(-150, 150))
		p.y = Sim.height_at(p.x, p.z) + rng.randf_range(-0.5, 14.0)
		var r: float = [0.0, 0.36, 1.0, 4.2, 9.0][i % 5]
		var want_hit := false
		var want_feet := false
		var want_top := -1e9
		var want_floor := -1e9
		for id in n_ent:
			if Obstacles._dead[id] != 0:
				continue
			if not want_hit and inside.call(id, p, r, false):
				want_hit = true
			if not want_feet and inside.call(id, p, r, true):
				want_feet = true
			var b: int = id * Obstacles.STRIDE
			var e: PackedFloat32Array = Obstacles._ent
			if inside.call(id, Vector3(p.x, e[b + 1] + 0.01, p.z), 0.0, false):
				var top: float = e[b + 1] + e[b + 4]
				want_top = maxf(want_top, top)
				if top <= p.y + 0.55:
					want_floor = maxf(want_floor, top)
		var t0 := Time.get_ticks_usec()
		var got_hit: bool = Obstacles.hit(p, r) >= 0
		var got_feet: bool = Obstacles.blocks(p, r) >= 0
		var got_top: float = Obstacles.top_at(p.x, p.z)
		var got_floor: float = Obstacles.floor_under(p.x, p.z, p.y)
		t_new += Time.get_ticks_usec() - t0
		counts["hit"] += int(got_hit)
		counts["blocks"] += int(got_feet)
		counts["top"] += int(got_top > -1e8)
		counts["floor"] += int(got_floor > -1e8)
		if got_hit != want_hit:
			bad.append("hit(%s, %.2f): grid %s, every box %s" % [str(p), r, got_hit, want_hit])
		if got_feet != want_feet:
			bad.append("blocks(%s, %.2f): grid %s, every box %s" % [str(p), r, got_feet, want_feet])
		if absf(got_top - want_top) > 1e-3:
			bad.append("top_at(%s): grid %.3f, every box %.3f" % [str(p), got_top, want_top])
		if absf(got_floor - want_floor) > 1e-3:
			bad.append("floor_under(%s): grid %.3f, every box %.3f" % [str(p), got_floor, want_floor])
		# a rifle round's step, a sight line across town, and a long line out
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)).normalized()
		var q: Vector3 = Vector3(c.x + rng.randf_range(-150, 150), 0.0, c.z + rng.randf_range(-150, 150))
		q.y = Sim.height_at(q.x, q.z) + rng.randf_range(0.5, 10.0)
		var lines: Array = [["step", p, p + dir * 7.5], ["sight", p, q],
			["long", p, p + dir * 2500.0]]
		for ln in lines:
			var a: Vector3 = ln[1]
			var z: Vector3 = ln[2]
			var t1 := Time.get_ticks_usec()
			var got: float = Obstacles.segment(a, z)
			t_new += Time.get_ticks_usec() - t1
			var want: float = seg_ref.call(a, z)
			if want < 1.0:
				counts[ln[0]] += 1
			if absf(got - want) > 1e-4:
				bad.append("segment %s %s -> %s: grid %.5f, every box %.5f" % [ln[0], str(a), str(z), got, want])
	var n_soft := 0
	for id in n_ent:
		if Obstacles._dead[id] == Obstacles.SOFT:
			n_soft += 1
	print("[obs] %d boxes in the field, %d of them soft; 3000 points and 9000 lines round %s" % [
		n_ent, n_soft, str(c.round())])
	print("[obs] found: %s" % str(counts))
	print("[obs] the grid took %.1f ms for all of it" % (float(t_new) * 0.001))
	for b in bad.slice(0, 12):
		print("[obs] MISMATCH %s" % b)
	print("[obs] %d mismatches" % bad.size())
	print("[obs] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --gibtest
## Forty men down at once, every way there is to go down.
var _gib_test := false

func tick_gib() -> void:
	if _gib_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_gib_test = false
		_run_gib_test()

## What dying costs. Forty men killed in one frame in front of the player --
## shells, heads, limbs and plain falls, ten of each -- and then what is lying
## about: how long the frame took, how many separate meshes and materials the
## pieces brought with them, and what the physics step cost while it settled.
func _run_gib_test() -> void:
	world.cqb.set_process(false)
	for sd in world.cqb.soldiers:
		if is_instance_valid(sd):
			(sd as Node).set_process(false)
	for i in 30:
		await world.get_tree().physics_frame
	var front: Vector3 = world.walker.global_position + Vector3(0, 0, -14)
	var before: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var t0 := Time.get_ticks_usec()
	for i in 40:
		var kind: int = i % 4
		var amount: float = [300.0, 30.0, 55.0, 20.0][kind]
		var at := front + Vector3(float(i % 8) * 1.6 - 5.6, 0.0, float(i / 8.0) * 1.6)
		at.y = Sim.height_at(at.x, at.z)
		Ragdoll.fall(world, Transform3D(Basis(), at), Vector3.ZERO,
			Color(0.27, 0.31, 0.22), Color(0.24, 0.27, 0.20), amount, kind == 1, false,
			Vector3(0, 0, -1))
	var spent: float = float(Time.get_ticks_usec() - t0) * 0.001
	var made: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) - before
	var meshes := {}
	var mats := {}
	var pieces := 0
	for n in world.get_children():
		if n is Ragdoll or n is Effects.Debris:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				pieces += 1
				if m.mesh != null:
					meshes[m.mesh.get_rid()] = true
					var sm: Material = m.material_override if m.material_override != null \
						else m.mesh.surface_get_material(0)
					if sm != null:
						mats[sm.get_rid()] = true
	var nf := 0
	var wall := 0.0
	var worst := 0.0
	var pairs := 0
	var last := Time.get_ticks_usec()
	for i in 240:
		await world.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ft: float = float(now - last) * 0.001
		last = now
		wall += ft
		worst = maxf(worst, ft)
		pairs = maxi(pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		nf += 1
	var still := 0
	var moving := 0
	var bodies := 0
	var sunk := 0
	for n in world.get_children():
		if n is Ragdoll:
			for limb in (n as Ragdoll).bodies.values():
				if not is_instance_valid(limb):
					continue
				bodies += 1
				var lp: Vector3 = (limb as Node3D).global_position
				# through the floor, not pressed into it: a pile of forty
				# leaves a limb or two half buried for a moment, which the
				# floor pushes back out
				if lp.y < Sim.height_at(lp.x, lp.z) - 2.0:
					sunk += 1
					if sunk <= 6:
						var o: Vector3 = (n as Ragdoll).global_position
						print("[gib]   sunk %s: y %.2f, ground there %.2f, ground under the body %.2f, %.1f m from it" % [
							String((limb as Node).name), lp.y, Sim.height_at(lp.x, lp.z),
							Sim.height_at(o.x, o.z), Vector2(lp.x - o.x, lp.z - o.z).length()])
		if n is Effects.Debris:
			if (n as Node).is_physics_processing():
				moving += 1
			else:
				still += 1
	print("[gib] 40 deaths in one frame: %.1f ms, %d nodes made" % [spent, made])
	print("[gib] %d drawn pieces using %d distinct meshes and %d distinct materials" % [
		pieces, meshes.size(), mats.size()])
	print("[gib] the next %d frames: %.2f ms a frame on average, worst %.1f ms; up to %d collision pairs" % [
		nf, wall / float(nf), worst, pairs])
	print("[gib] debris after 2 s: %d still being ticked, %d asleep" % [moving, still])
	print("[gib] %d limbs lying about, %d of them under the ground" % [bodies, sunk])
	print("[gib] RESULT: %s" % ("ok" if sunk == 0 and bodies > 0 else "FAILED"))
	world.get_tree().quit()
#endregion


#region --roundtest
## Rounds against a wall and a parked car, and the weapon camera on his own.
var _round_test := false

func tick_round() -> void:
	if _round_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker) and is_instance_valid(world.cam):
		_round_test = false
		_run_round_test()

## Two things that were wrong together. A shell or a machine-gun round went
## straight through a house, and every round went through a car; and the
## weapon camera rode stores but never a round from a gun or from a man's
## shoulder. A building and a soft prop near the town are each shot at, end
## on, with a rifle round and a cannon round, and where each stops is checked
## against the face; then the player fires his rifle and a rocket with the
## camera armed, and each is checked for being ridden and for handing the
## screen back.
func _run_round_test() -> void:
	world.cqb.set_process(false)
	for sd in world.cqb.soldiers:
		if is_instance_valid(sd):
			(sd as Node).set_process(false)
	for i in 20:
		await world.get_tree().physics_frame
	var bad: Array = []
	var c := Vector3(world.cqb.centre.x, 0.0, world.cqb.centre.y)
	var e: PackedFloat32Array = Obstacles._ent
	var picks := {}
	for id in Obstacles._dead.size():
		var b: int = id * Obstacles.STRIDE
		if Vector2(e[b] - c.x, e[b + 2] - c.z).length() > 400.0:
			continue
		var st: int = Obstacles._dead[id]
		if st == Obstacles.LIVE and e[b + 4] > 4.0 and minf(e[b + 3], e[b + 5]) > 2.0 \
				and not picks.has("building"):
			picks["building"] = id
		if st == Obstacles.SOFT and e[b + 4] > 0.8 and minf(e[b + 3], e[b + 5]) > 0.25 \
				and not picks.has("prop"):
			picks["prop"] = id
	for what in ["building", "prop"]:
		if not picks.has(what):
			bad.append("no %s near the town to shoot at" % what)
			continue
		var id: int = picks[what]
		var b: int = id * Obstacles.STRIDE
		var mid := Vector3(e[b], e[b + 1] + minf(e[b + 4] * 0.5, 1.2), e[b + 2])
		var dir := Vector3(e[b + 6], 0.0, e[b + 7])        # the box's own x axis
		# from open ground: back out from the face until nothing is standing there
		var back_off := 12.0
		while back_off < 60.0 and Obstacles.hit(mid - dir * (e[b + 3] + back_off), 0.3) >= 0:
			back_off += 1.0
		var from: Vector3 = mid - dir * (e[b + 3] + back_off)
		var far: Vector3 = mid + dir * (e[b + 3] + 30.0)
		var t_wall: float = Obstacles.segment(from, far)
		var face: Vector3 = from.lerp(far, t_wall)
		for kind in ["rifle", "cannon"]:
			var r: Node3D = Effects.bullet(world, from, dir * 880.0, null, 10.0, 7) \
				if kind == "rifle" else Effects.tracer(world, from, dir * 1000.0, null, 10.0, 7)
			var last: Vector3 = from
			for f in 90:
				if not is_instance_valid(r):
					break
				last = r.global_position
				await world.get_tree().physics_frame
			var went: float = from.distance_to(last)
			var to_face: float = from.distance_to(face)
			var stopped: bool = not is_instance_valid(r)
			print("[round] %s round at a %s (%.1f m tall): wall %.1f m out, the round got %.1f m%s" % [
				kind, what, e[b + 4], to_face, went, "" if stopped else " and was still going"])
			if t_wall >= 1.0:
				bad.append("the line at the %s does not meet it" % what)
			elif not stopped or went > to_face + 0.5:
				bad.append("a %s round went through the %s" % [kind, what])
	# The weapon camera, on foot.
	world.weapon_cam_on = true
	var eye: Vector3 = world.walker.cam.global_position
	var look: Vector3 = -world.walker.cam.global_transform.basis.z
	# somebody else's round is not his to ride
	if not world.cqb.soldiers.is_empty() and is_instance_valid(world.cqb.soldiers[0]):
		Effects.bullet(world, eye + Vector3(0, 0, 3), look * 880.0, world.cqb.soldiers[0], 1.0, 1)
		if world.cam.riding():
			bad.append("the camera rode a round somebody else fired")
	for kind in ["rifle", "rocket"]:
		if kind == "rifle":
			Firearm.fire(world, world.walker, world.walker.side, Firearm.spec("carbine"), eye, look, 0.0)
		else:
			Firearm.rocket(world, world.walker, world.walker.side, Firearm.spec("law"), eye, look)
		var on: Variant = world.cam.weapon_cam
		var took: bool = on != null and is_instance_valid(on) and world.cam.current \
			and not world.walker.cam.current
		# a second round straight after is not taken off the first
		Firearm.fire(world, world.walker, world.walker.side, Firearm.spec("carbine"), eye, look, 0.0)
		var kept: bool = world.cam.weapon_cam == on
		var waited := 0
		while world.cam.riding() and waited < 900:
			await world.get_tree().physics_frame
			waited += 1
		await world.get_tree().process_frame
		await world.get_tree().process_frame
		var back: bool = world.walker.cam.current
		print("[round] %s with the weapon camera armed: ridden %s, kept over the next round %s, screen back to his eyes %s after %.1f s" % [
			kind, str(took), str(kept), str(back), float(waited) / 120.0])
		if not took:
			bad.append("his %s was not ridden" % kind)
		if not kept:
			bad.append("the ride on his %s was cut by the next round" % kind)
		if not back:
			bad.append("the screen did not come back to him after the %s" % kind)
	world.weapon_cam_on = false
	for b2 in bad:
		print("[round] %s" % b2)
	print("[round] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --pronetest
## Lying down and shooting: where the rounds start and where they go.
var _prone_test := false

func tick_prone() -> void:
	if _prone_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_prone_test = false
		_run_prone_test()

## Lying in the road and shooting. For each of a few lines of sight, from the
## hip and down the sights, the round is followed from the muzzle to wherever
## it stops, and compared with where the line of sight meets the world: how
## far along, how far off it, and how close to the road it ran on the way.
func _run_prone_test() -> void:
	world.cqb.set_process(false)
	for sd in world.cqb.soldiers:
		if is_instance_valid(sd):
			(sd as Node).set_process(false)
			(sd as Node3D).global_position += Vector3(0, -500, 0)
	var w: Walker = world.walker
	w.stance = 2
	for i in 120:
		await world.get_tree().physics_frame
	# down the longest open line from where he lies
	var best_yaw := 0.0
	var best_reach := 0.0
	for k in 24:
		var yv: float = TAU * float(k) / 24.0
		var dirv := Vector3(-sin(yv), 0.0, -cos(yv))
		var e0: Vector3 = w.global_position + Vector3(0, 0.46, 0)
		var r0: float = Firearm.sight_range(e0, dirv, 300.0)
		if r0 > best_reach:
			best_reach = r0
			best_yaw = yv
	w.yaw = best_yaw
	print("[prone] lying facing %.0f deg, %.0f m of open line" % [rad_to_deg(best_yaw), best_reach])
	# every round as it leaves, where it leaves from
	var spawned: Array = []
	var was_watch: Callable = Effects.round_watch
	Effects.round_watch = func(shot: Node3D, shooter: Node) -> void:
		if shooter == w:
			spawned.append([shot, shot.global_position])
	var bad: Array = []
	for view in ["first", "third"]:
		w.third = view == "third"
		for ads in [false, true]:
			w.hold_ads = ads
			for p in [-0.10, -0.04, 0.0, 0.04]:
				w.pitch = p
				w._recoil = 0.0
				w._bloom = 0.0
				for i in 90:
					await world.get_tree().physics_frame
				var eye: Vector3 = w.cam.global_position
				var look: Vector3 = -w.cam.global_transform.basis.z
				var muzzle: Vector3 = w.body.muzzle_pos()
				var gm: float = Sim.height_at(muzzle.x, muzzle.z)
				# where the crosshair is: the first thing the line of sight meets
				var reach: float = Firearm.sight_range(eye, look, 600.0)
				var mark: Vector3 = eye + look * reach
				spawned.clear()
				Input.action_press(&"foot_fire")
				await world.get_tree().physics_frame
				Input.action_release(&"foot_fire")
				var tag := "%s %s pitch %+.2f" % [view, "ADS" if ads else "hip", p]
				if spawned.is_empty():
					for i in 4:
						await world.get_tree().physics_frame
				if spawned.is_empty():
					bad.append("%s: no round came out" % tag)
					continue
				var shot: Variant = spawned[0][0]
				var start: Vector3 = spawned[0][1]
				# read as it leaves: it says where it stopped on the tick it frees itself
				var ends: Array = []
				if is_instance_valid(shot):
					var rnd := shot as Effects.Tracer
					rnd.tree_exiting.connect(func() -> void: ends.append(rnd.ended_at))
				for f in 300:
					if not is_instance_valid(shot) or not ends.is_empty():
						break
					await world.get_tree().physics_frame
				var end: Vector3 = ends[0] if not ends.is_empty() else Vector3.INF
				if end == Vector3.INF:
					bad.append("%s: round never said where it stopped" % tag)
					continue
				var miss: float = end.distance_to(mark) if reach < 599.0 else -1.0
				# how far off the line from the eye to the mark the round ended
				var along: float = (end - eye).dot(look)
				var off: float = ((end - eye) - look * along).length()
				print("[prone] %s: muzzle %.2f m off the road, round from %.2f m off the muzzle; crosshair on the world at %.1f m, round ended %.1f m along, %.2f m off the line%s" % [
					tag, muzzle.y - gm, start.distance_to(muzzle), reach, along, off,
					(", %.2f m from the mark" % miss) if miss >= 0.0 else ""])
				# from the muzzle, or -- when the muzzle could not see the mark --
				# from the line of sight itself
				var on_line: float = ((start - eye) - look * (start - eye).dot(look)).length()
				if start.distance_to(muzzle) > 0.3 and on_line > 0.05:
					bad.append("%s: the round started %.2f m from the muzzle and %.2f m off the line of sight" % [
						tag, start.distance_to(muzzle), on_line])
				# From the hip it scatters by design, and along a line skimming the
				# road a fraction of a degree is a long way: only an aimed round
				# is held to landing on the mark.
				if not ads:
					pass
				elif reach < 599.0 and absf(along - reach) > maxf(1.5, reach * 0.06):
					bad.append("%s: crosshair on the world at %.1f m, the round stopped at %.1f m" % [tag, reach, along])
				elif reach >= 599.0 and along < 300.0:
					bad.append("%s: nothing under the crosshair, the round stopped at %.1f m" % [tag, along])
				if ads and reach < 599.0 and off > 0.25 + along * 0.004:
					bad.append("%s: down the sights, the round ended %.2f m off the line" % [tag, off])
	# A sill in front of him: 0.62 m of wall four metres out, over the muzzle
	# lying down and under the view over his shoulder. Aimed over it, the
	# round has to go over it too.
	w.third = true
	w.hold_ads = true
	w.pitch = -0.02
	var fwd := Vector3(-sin(w.yaw), 0.0, -cos(w.yaw))
	var sill_at: Vector3 = w.global_position + fwd * 4.0
	var sill: int = Obstacles.add_box(Vector3(sill_at.x, Sim.height_at(sill_at.x, sill_at.z), sill_at.z),
		3.0, 0.62, 0.15, w.yaw)
	for i in 90:
		await world.get_tree().physics_frame
	var eye2: Vector3 = w.cam.global_position
	var look2: Vector3 = -w.cam.global_transform.basis.z
	var reach2: float = Firearm.sight_range(eye2, look2, 600.0)
	var muz2: Vector3 = w.body.muzzle_pos()
	spawned.clear()
	var ends2: Array = []
	Input.action_press(&"foot_fire")
	await world.get_tree().physics_frame
	Input.action_release(&"foot_fire")
	for i in 4:
		if not spawned.is_empty():
			break
		await world.get_tree().physics_frame
	if spawned.is_empty():
		bad.append("over the sill: no round came out")
	else:
		var r2 := spawned[0][0] as Effects.Tracer
		var from2: Vector3 = spawned[0][1]
		if is_instance_valid(r2):
			r2.tree_exiting.connect(func() -> void: ends2.append(r2.ended_at))
		for f in 300:
			if not ends2.is_empty() or not is_instance_valid(r2):
				break
			await world.get_tree().physics_frame
		var end2: Vector3 = ends2[0] if not ends2.is_empty() else Vector3.INF
		var along2: float = (end2 - eye2).dot(look2)
		print("[prone] over a 0.62 m sill 4 m out, third person: muzzle %.2f m up, round left %.2f m from the muzzle; crosshair on the world at %.1f m, round ended %.1f m along" % [
			muz2.y - Sim.height_at(muz2.x, muz2.z), from2.distance_to(muz2), reach2, along2])
		if along2 < 6.0:
			bad.append("over the sill: the round went into it at %.1f m" % along2)
		elif reach2 < 599.0 and absf(along2 - reach2) > maxf(1.5, reach2 * 0.06):
			bad.append("over the sill: crosshair at %.1f m, round stopped at %.1f m" % [reach2, along2])
	Obstacles.remove(sill)
	Effects.round_watch = was_watch
	w.third = false
	for b in bad:
		print("[prone] %s" % b)
	print("[prone] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --yawtest
## Whether a turned building's obstacle box is turned the way its mesh is.
var _yaw_test := false

func tick_yaw() -> void:
	if _yaw_test and is_instance_valid(world.cqb) and is_instance_valid(world.cqb.dressing):
		_yaw_test = false
		_run_yaw_test()

## Every prop the town put down at an angle, against the box it filed for
## itself: points well inside the drawn mesh, near its corners, should be
## inside the obstacle box. A box turned the other way from its mesh puts the
## corners outside, and the wall is somewhere it is not drawn.
func _run_yaw_test() -> void:
	var ts: Node = world.cqb.dressing
	var tried := 0
	var inside := 0
	var props := 0
	for mi in ts.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var yaw: float = m.global_rotation.y
		var turn: float = absf(fmod(absf(yaw), PI * 0.5))
		if turn < 0.15 or turn > PI * 0.5 - 0.15:
			continue
		var ab: AABB = m.mesh.get_aabb()
		if ab.size.x < 1.2 or ab.size.z < 1.2 or ab.size.y < 0.6:
			continue
		props += 1
		# the corners of the footprint, pulled in a fifth, half way up
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var lp := ab.get_center() + Vector3(cx * ab.size.x * 0.4, 0.0, cz * ab.size.z * 0.4)
				var wp: Vector3 = m.global_transform * lp
				tried += 1
				if Obstacles.hit(wp, 0.0) >= 0:
					inside += 1
		if props >= 60:
			break
	print("[yaw] %d props set at an angle; %d of %d points well inside their meshes are inside an obstacle box" % [
		props, inside, tried])
	print("[yaw] RESULT: %s" % ("ok" if tried > 0 and inside >= int(tried * 0.9) else "FAILED"))
	world.get_tree().quit()
#endregion


#region --zoomtest
## The map from the street out to the planet and back, and the corner map.
var _zoom_test := false

func tick_zoom() -> void:
	if _zoom_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker) and is_instance_valid(world.map):
		_zoom_test = false
		_run_zoom_test()

## In a street fight the map opens on the street; the wheel takes it out to the
## whole planet and back in again, keeping the same place in the middle of the
## screen across each handover; and the corner map has the buildings round him.
func _run_zoom_test() -> void:
	for i in 30:
		await world.get_tree().process_frame
	var bad: Array = []
	world.map.toggle()
	await world.get_tree().process_frame
	var vp: Vector2 = world.map.get_viewport_rect().size
	var me := Vector2(world.walker.global_position.x, world.walker.global_position.z)
	print("[map] opened: globe %s, zoom %.0f, %.0f m from him" % [str(world.map.globe), world.map.zoom,
		world.map.centre.distance_to(me)])
	if world.map.globe or world.map.zoom < 1000.0 or world.map.centre.distance_to(me) > 30.0:
		bad.append("a street fight's map did not open on the street on him")
	var wheel := func(up: bool) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = vp * 0.5
		world.map._gui_input(e)
	# out to the planet
	var before: Vector2 = world.map.centre
	var n := 0
	while not world.map.globe and n < 200:
		wheel.call(false)
		n += 1
	if not world.map.globe:
		bad.append("zooming out never reached the planet (zoom %.2f)" % world.map.zoom)
	else:
		var mid: Vector2 = world.map._globe_point(vp * 0.5)
		print("[map] out to the planet after %d notches; the middle of the globe is %.1f km from where the chart was" % [
			n, mid.distance_to(before) * 0.001])
		if mid.distance_to(before) > 2000.0:
			bad.append("the globe opened %.0f km away from where the chart was" % (mid.distance_to(before) * 0.001))
	var m2 := 0
	while world.map.globe_zoom > 0.7 and m2 < 200:
		wheel.call(false)
		m2 += 1
	print("[map] all the way out: globe zoom %.2f, the planet %s on screen" % [world.map.globe_zoom,
		"wholly" if world.map.globe_zoom <= 1.0 else "partly"])
	if world.map.globe_zoom > 1.0:
		bad.append("could not zoom out to see the whole planet")
	# and back in to the street
	var g_mid: Vector2 = world.map._globe_point(vp * 0.5)
	var k := 0
	while world.map.globe and k < 400:
		wheel.call(true)
		k += 1
	if world.map.globe:
		bad.append("zooming back in never reached the street map")
	else:
		print("[map] back to the chart after %d notches, %.1f km from the globe's middle" % [
			k, world.map.centre.distance_to(g_mid) * 0.001])
		if world.map.centre.distance_to(g_mid) > 2000.0:
			bad.append("the chart came back %.0f km from where the globe was looking" % (
				world.map.centre.distance_to(g_mid) * 0.001))
		var j := 0
		while world.map.zoom < 2400.0 and j < 200:
			wheel.call(true)
			j += 1
		print("[map] street level again (zoom %.0f) after %d more" % [world.map.zoom, j])
	world.map.toggle()
	# the corner map
	for i in 10:
		world.hud.queue_redraw()
		await world.get_tree().process_frame
	var cm: Variant = world.hud.get("_cqb_map")
	if cm == null or not is_instance_valid(cm):
		bad.append("no corner map")
	else:
		var tris: int = 0
		var mesh: Variant = cm.get("_mesh")
		if mesh != null:
			tris = int((mesh as ArrayMesh).surface_get_array_len(0) / 3.0)
		print("[map] corner map: %d footprint triangles round him, %.0f m across" % [tris,
			float(cm.get("SPAN"))])
		if tris == 0:
			bad.append("the corner map has no buildings on it")
	for b in bad:
		print("[map] %s" % b)
	print("[map] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --armstest
## Every class, every weapon in it fired at a mark, and every sight.
var _arms_test := false

func tick_arms() -> void:
	if _arms_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_arms_test = false
		_run_arms_test()

## Every class deployed, and both its weapons taken up and fired at a mark on
## the road down the longest open line: where each round comes down against
## where it was laid. Then each sight's magnification, and the deploy screen
## with every class on it.
func _run_arms_test() -> void:
	world.cqb.set_process(false)
	for sd in world.cqb.soldiers:
		if is_instance_valid(sd):
			(sd as Node).set_process(false)
			(sd as Node3D).global_position += Vector3(0, -500, 0)
	var w: Walker = world.walker
	w.stance = 0
	w.hold_ads = true
	for i in 30:
		await world.get_tree().physics_frame
	# A heading down which the road itself is the mark, 45 and 90 m out: the
	# line from the eye to each meets nothing on the way, so what is under the
	# crosshair is the road and not the top edge of something in front of it.
	var best_yaw := 0.0
	var found := false
	var e0: Vector3 = w.global_position + Vector3(0, 1.6, 0)
	for k in 72:
		var yv: float = TAU * float(k) / 72.0
		var fl := Vector3(-sin(yv), 0.0, -cos(yv))
		var ok := true
		for dd in [45.0, 90.0]:
			var sp: Vector3 = e0 + fl * dd
			sp.y = Sim.height_at(sp.x, sp.z)
			var dl: Vector3 = (sp - e0).normalized()
			if absf(Firearm.sight_range(e0, dl, 200.0) - e0.distance_to(sp)) > 0.6:
				ok = false
		if ok:
			best_yaw = yv
			found = true
			break
	w.yaw = best_yaw
	print("[arms] facing %.0f deg, %s" % [rad_to_deg(best_yaw),
		"road clear to 90 m" if found else "NO clear heading found"])
	var spawned: Array = []
	var was_watch: Callable = Effects.round_watch
	Effects.round_watch = func(shot: Node3D, shooter: Node) -> void:
		if shooter == w:
			spawned.append(shot)
	var bad: Array = []
	var tried := {}
	for ci in Firearm.CLASSES.size():
		var c: Dictionary = (Firearm.CLASSES[ci] as Dictionary).duplicate()
		w.apply_class(c)
		for si in 2:
			var idx: int = int(w.slots[si])
			var id := String(Firearm.KIT[idx]["id"])
			if tried.has(id):
				continue
			tried[id] = true
			w._take_up(idx, false)
			w.ammo = int(w.gun_spec()["mag"])
			var g: Dictionary = w.gun_spec()
			var launcher := String(g.get("launcher", ""))
			if launcher == "sam":
				continue                # needs an aircraft to lock; flown elsewhere
			# a mark on the road: 45 m out, or 90 for the launcher
			var want: float = 90.0 if launcher == "gl" else 45.0
			var eye: Vector3 = w.cam.global_position
			var flat := Vector3(-sin(w.yaw), 0.0, -cos(w.yaw))
			var spot: Vector3 = eye + flat * want
			spot.y = Sim.height_at(spot.x, spot.z)
			w.pitch = atan2(spot.y - eye.y, want)
			w._recoil = 0.0
			w._bloom = 0.0
			w._shot_cd = 0.0
			for i in 90:
				await world.get_tree().physics_frame
			eye = w.cam.global_position
			var look: Vector3 = -w.cam.global_transform.basis.z
			var mark: Vector3 = eye + look * Firearm.sight_range(eye, look, 600.0)
			# sighted in at the mark's range, as a shooter would dial it
			w.zero_override = eye.distance_to(mark)
			spawned.clear()
			Input.action_press(&"foot_fire")
			await world.get_tree().physics_frame
			await world.get_tree().physics_frame
			Input.action_release(&"foot_fire")
			for i in 4:
				if not spawned.is_empty():
					break
				await world.get_tree().physics_frame
			if spawned.is_empty():
				bad.append("%s (%s): nothing came out" % [id, String(c["name"])])
				continue
			# every pellet of a shotgun's load, and where the load centred
			var ends: Array = []
			for sh in spawned:
				var shot: Node = sh
				shot.tree_exiting.connect(func() -> void: ends.append(shot.get("ended_at")))
			for f in 900:
				if ends.size() >= spawned.size():
					break
				await world.get_tree().physics_frame
			var end: Variant = null
			var n_end := 0
			var sum := Vector3.ZERO
			for e in ends:
				if e != null and e != Vector3.INF:
					sum += e as Vector3
					n_end += 1
			if n_end > 0:
				end = sum / float(n_end)
			if end == null:
				bad.append("%s: never said where it came down" % id)
				continue
			var miss: float = (end as Vector3).distance_to(mark)
			var rel: Vector3 = (end as Vector3) - eye
			var along: float = rel.dot(look)
			print("[arms] %-22s %s: laid on %.1f m, came down %.2f m from the mark (%.1f m along the line, %.2f m off it; ads %.2f, spread %.4f)" % [
				String(g["name"]), String(c["name"]), eye.distance_to(mark), miss, along,
				(rel - look * along).length(), w._ads, w.spread_now])
			# a 40 mm round is a lob; a rifle round from the shoulder is not
			# Judged off the line of sight, not along it: onto a flat road
			# forty-five metres out the line meets the ground at two degrees,
			# and there the ordinary spread of a burst is metres along it. A
			# lob is judged on the mark itself.
			var off: float = (rel - look * along).length()
			var allow: float = 0.15 + along * w.spread_now * 2.5
			if launcher == "gl":
				if miss > 2.5:
					bad.append("%s: %.1f m off the mark" % [id, miss])
			elif off > allow:
				bad.append("%s: %.2f m off the line of sight at %.0f m (allowed %.2f)" % [id, off, along, allow])
	Effects.round_watch = was_watch
	# the sights, on the carbine
	for sg in Firearm.SIGHTS:
		var fg: Dictionary = Firearm.fitted("carbine", {"sight": sg})
		print("[arms] carbine with %-6s %.1fx  (%s)" % [sg, 74.0 / float(fg["fov"]),
			String(fg.get("reticle", "dot" if fg.get("dot", false) else "irons"))])
	var f2x: Dictionary = Firearm.fitted("carbine", {"sight": "2x"})
	var facog: Dictionary = Firearm.fitted("carbine", {"sight": "acog"})
	if not (f2x.get("scope", false) and facog.get("scope", false) \
			and absf(74.0 / float(f2x["fov"]) - 2.0) < 0.3 and absf(74.0 / float(facog["fov"]) - 4.0) < 0.4):
		bad.append("the 2x and the ACOG are not 2x and 4x")
	# the deploy screen, with every class
	var dm := DeployMenu.new()
	world.add_child(dm)
	dm.open("any", true, "usa")
	for ci2 in CqbMatch.kit_classes().size():
		dm._pick(ci2)
	if dm._sight.item_count != Firearm.SIGHTS.size():
		bad.append("the deploy screen offers %d sights of %d" % [dm._sight.item_count, Firearm.SIGHTS.size()])
	dm.queue_free()
	for b in bad:
		print("[arms] %s" % b)
	print("[arms] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --steadytest
## How far the sights wander: a sniper rifle on its scope standing, holding a
## breath, lying down (rested) -- and fire select: a burst is three rounds a
## pull. --preset=range:f16 --steadytest
var _steady_test := false

func tick_steady() -> void:
	if _steady_test and is_instance_valid(world.walker):
		_steady_test = false
		_run_steady_test()

func _wander(w: Walker, secs: float) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in int(Engine.physics_ticks_per_second * secs):
		await world.get_tree().physics_frame
		lo = Vector2(minf(lo.x, w.sway.x), minf(lo.y, w.sway.y))
		hi = Vector2(maxf(hi.x, w.sway.x), maxf(hi.y, w.sway.y))
	return (hi - lo).length() * 1000.0     # mils, peak to peak

func _run_steady_test() -> void:
	for i in 120:
		await world.get_tree().physics_frame
	var w: Walker = world.walker
	var bad: Array = []
	var sn: int = Firearm.index_of("sniper")
	w.slots[0] = sn
	w._rounds[sn] = 5
	w._take_up(sn)
	w.hold_ads = true
	for i in 90:
		await world.get_tree().physics_frame
	var stand: float = await _wander(w, 4.0)
	Input.action_press(&"throttle_up")
	for i in 20:
		await world.get_tree().physics_frame
	var held: float = await _wander(w, 2.5)
	Input.action_release(&"throttle_up")
	for i in Engine.physics_ticks_per_second * 6:
		await world.get_tree().physics_frame
	w.stance = 2                  # lying down, the way the Z key puts him
	for i in Engine.physics_ticks_per_second * 2:
		await world.get_tree().physics_frame
	var lying: float = await _wander(w, 4.0)
	print("[steady] sniper on the scope, wander peak to peak: standing %.1f mil, holding breath %.1f, prone and rested (%s) %.1f" % [
		stand, held, "rested" if w.mounted else "NOT rested", lying])
	if not (held < stand * 0.4 and lying < stand * 0.4 and w.mounted):
		bad.append("steadying or resting does not steady it")
	w.stance = 0
	w.hold_ads = false
	# fire select on the carbine
	var cb: int = Firearm.index_of("carbine")
	w.slots[0] = cb
	w._rounds[cb] = 30
	w._spare[cb] = 90
	w._take_up(cb)
	for i in 60:
		await world.get_tree().physics_frame
	w.fire_mode[cb] = "burst"
	var a0: int = w.ammo
	Input.action_press(&"foot_fire")
	await world.get_tree().physics_frame
	await world.get_tree().physics_frame
	Input.action_release(&"foot_fire")
	for i in Engine.physics_ticks_per_second:
		await world.get_tree().physics_frame
	var burst: int = a0 - w.ammo
	w.fire_mode[cb] = "semi"
	a0 = w.ammo
	Input.action_press(&"foot_fire")
	for i in Engine.physics_ticks_per_second:
		await world.get_tree().physics_frame
	Input.action_release(&"foot_fire")
	var semi: int = a0 - w.ammo
	print("[steady] carbine: modes %s; a pull on BURST fired %d, a held trigger on SEMI fired %d" % [
		str(Walker.modes_of(w.gun_spec())), burst, semi])
	if burst != 3 or semi != 1:
		bad.append("fire select is wrong")
	print("[steady] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --holdfire
## Shooting in and out of an aircraft's hold, in flight. From inside: at the
## side wall and the shut ramp the round hits the aircraft; out over the open
## ramp it goes, carrying the aircraft's speed; up at the tail from the ramp
## it hits the aircraft. From outside: at the side of the fuselage it hits the
## aircraft and not the man behind it; up the open ramp it hits him.
## --preset=free:c130 --holdfire
var _holdfire := false

func tick_holdfire() -> void:
	if _holdfire and world.running and is_instance_valid(world.player):
		_holdfire = false
		_run_holdfire()

func _tracers() -> Array:
	var out: Array = []
	for n in world.get_children():
		if n is Effects.Tracer:
			out.append(n)
	return out

## One round from `from` along `dir` (world space), with the aircraft's speed;
## what it hit after a second: [aircraft health lost, man health lost, metres
## the round got from where it started before it ended].
func _hf_round(p: Aircraft, w: Walker, from: Vector3, dir: Vector3, carried: bool) -> Array:
	# fired by him from inside, so it does not start in his own head; from
	# outside, by nobody in particular on the other side
	var hp_a: float = p.health
	var hp_m: float = w.health
	var g: Dictionary = Firearm.spec("carbine")
	var before: Array = _tracers()
	# from inside the hold itself, not merely from the open air behind it
	var lf: Vector3 = p.hold_node().global_transform.affine_inverse() * from
	var hh: Vector3 = p.hold_node().get_meta("half")
	var inside: bool = carried and absf(lf.z) <= hh.z and absf(lf.x) <= hh.x
	Firearm.fire(world, w if inside else null, 1, g, from, dir, 0.0, 1.0, false,
		p.linear_velocity if carried else Vector3.ZERO)
	var mine: Effects.Tracer = null
	for t in _tracers():
		if not before.has(t):
			mine = t
	var far := 0.0
	for i in Engine.physics_ticks_per_second:
		await world.get_tree().physics_frame
		if is_instance_valid(mine):
			# against the aircraft: how far from it the round has got
			far = maxf(far, mine.global_position.distance_to(p.global_position))
	var lost_a: float = hp_a - p.health
	var lost_m: float = hp_m - w.health
	p.health = hp_a
	w.health = 100.0
	return [lost_a, lost_m, far]

func _run_holdfire() -> void:
	for i in 60:
		await world.get_tree().physics_frame
	var p: Aircraft = world.player
	var at := Vector3(0.0, Sim.height_at(0.0, -6000.0) + 1500.0, -6000.0)
	p.global_transform = Transform3D(Basis.IDENTITY, at)
	p.linear_velocity = Vector3(0, 0, -105.0)
	p.gear_down = false
	p.throttle = 0.7
	p.power = 0.7
	p.active = true
	p.set_autopilot("hold")
	for i in 120:
		await world.get_tree().physics_frame
	var hold: Node3D = p.hold_node()
	world.crew.spawn_walker(hold.global_position)
	var w: Walker = world.walker
	w.global_transform = hold.global_transform
	w.enter_frame(hold, p)
	w.activate()
	w.position = Vector3(0.0, 0.0, 0.0)
	w.side = 0
	for i in 10:
		await world.get_tree().physics_frame
	var bad: Array = []
	var hb: Basis = hold.global_transform.basis.orthonormalized()
	var eye: Vector3 = hold.global_transform * Vector3(0.0, 1.5, 0.0)
	var half: Vector3 = hold.get_meta("half")
	# from inside, at the side wall
	p.ramp_open = false
	hb = hold.global_transform.basis.orthonormalized()
	eye = hold.global_transform * Vector3(0.0, 1.5, 0.0)
	var r1: Array = await _hf_round(p, w, eye, hb * Vector3(1, 0, 0), true)
	print("[holdfire] inside, at the side wall: aircraft -%.0f, the round got %.0f m from it" % [r1[0], r1[2]])
	if float(r1[0]) <= 0.0 or float(r1[2]) > 30.0:
		bad.append("the side wall did not stop it and take the hit")
	# from inside, aft at the shut ramp
	eye = hold.global_transform * Vector3(0.0, 1.5, 0.0)
	hb = hold.global_transform.basis.orthonormalized()
	var r2: Array = await _hf_round(p, w, eye, hb * Vector3(0, -0.05, 1).normalized(), true)
	print("[holdfire] inside, aft at the shut ramp: aircraft -%.0f, %.0f m" % [r2[0], r2[2]])
	if float(r2[0]) <= 0.0 or float(r2[2]) > 30.0:
		bad.append("the shut ramp did not stop it and take the hit")
	# out over the open ramp
	p.ramp_open = true
	for i in 30:
		await world.get_tree().physics_frame
	eye = hold.global_transform * Vector3(0.0, 1.5, 0.0)
	hb = hold.global_transform.basis.orthonormalized()
	var r3: Array = await _hf_round(p, w, eye, hb * Vector3(0, -0.04, 1).normalized(), true)
	print("[holdfire] inside, out over the open ramp: aircraft -%.0f, %.0f m clear of it" % [r3[0], r3[2]])
	if float(r3[0]) > 0.0 or float(r3[2]) < 100.0:
		bad.append("it did not get out over the open ramp")
	# from the ramp, up at the tail
	eye = hold.global_transform * Vector3(0.0, 1.5, 0.0)
	hb = hold.global_transform.basis.orthonormalized()
	var on_ramp: Vector3 = hold.global_transform * Vector3(0.0, 1.0, half.z + 1.0)
	var tail: Vector3 = p.global_transform * Vector3(0.0, p.bounds.end.y - 1.0, p.bounds.end.z - 2.0)
	var r4: Array = await _hf_round(p, w, on_ramp, (tail - on_ramp).normalized(), true)
	print("[holdfire] from the ramp up at the tail: aircraft -%.0f" % r4[0])
	if float(r4[0]) <= 0.0:
		bad.append("a round into its own tail did not hit it")
	# from outside, at the side of the fuselage, the man behind it
	# (where he is now: the aeroplane has flown on a hundred metres since)
	var side_out: Vector3 = hold.global_transform * Vector3(half.x + 25.0, 1.2, 0.0)
	var man: Vector3 = w.global_position + Vector3(0, 1.1, 0)
	var r5: Array = await _hf_round(p, w, side_out, (man - side_out).normalized(), false)
	print("[holdfire] outside, through the side at the man: aircraft -%.0f, man -%.0f" % [r5[0], r5[1]])
	if float(r5[0]) <= 0.0 or float(r5[1]) > 0.0:
		bad.append("a round from outside went through the hull into him")
	# from behind, up the open ramp at him
	var behind: Vector3 = hold.global_transform * Vector3(0.0, 1.1, half.z + 25.0)
	man = w.global_position + Vector3(0, 1.1, 0)
	print("[holdfire]   (he is %s)" % ("alive" if w.is_alive() else "dead"))
	# from someone keeping station behind it -- a shooter standing still on
	# the ground has to lead an aeroplane doing a hundred metres a second, and
	# this is not a test of that
	var r6: Array = await _hf_round(p, w, behind, (man - behind).normalized(), true)
	print("[holdfire] outside, up the open ramp at the man: aircraft -%.0f, man -%.0f" % [r6[0], r6[1]])
	if float(r6[1]) <= 0.0:
		bad.append("a round up the open ramp did not reach him")
	print("[holdfire] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --zerotest
## Sighted in, not ranged: a carbine zeroed at 100 m fired along its sight line
## at each board, from a muzzle under the eye. Where each round strikes against
## the point of aim -- on it at the zero, a little high short of it, low past
## it -- and then the same at 300 m with elevation dialled on.
## --preset=range:f16 --zerotest
var _zero_test := false

func tick_zero() -> void:
	if _zero_test and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		_zero_test = false
		_run_zero_test()

func _fire_and_read(w: Walker, g: Dictionary, from: Vector3, d: Vector3, aim_at: Vector3) -> float:
	var n0: int = world.firing_range.rounds.size()
	Firearm.fire(world, w, 0, g, from, d, 0.0)
	for f in 1200:
		await world.get_tree().physics_frame
		if world.firing_range.rounds.size() > n0 \
				and not bool((world.firing_range.rounds[world.firing_range.rounds.size() - 1] as Dictionary)["live"]):
			break
	var lr: Dictionary = world.firing_range.rounds[world.firing_range.rounds.size() - 1]
	var lp: Vector3 = lr["pos"]
	# its height against the point of aim, where it struck the board
	return (lp - aim_at).dot(Vector3.UP)

func _run_zero_test() -> void:
	for i in 120:
		await world.get_tree().physics_frame
	var w: Walker = world.walker
	var g: Dictionary = Firearm.spec("carbine")
	var ki: int = Firearm.index_of("carbine")
	w.zero_override = -1.0
	w.elev_mil[ki] = 0.0
	w.wind_mil[ki] = 0.0
	var eye: Vector3 = w.global_position + Vector3(0, 1.5, 0)
	# the muzzle a sight height under the eye and a little ahead
	var bad: Array = []
	var at_zero := INF
	var at_300 := INF
	for t in world.firing_range.targets:
		var rt: FiringRange.RangeTarget = t
		if rt.distance > 310.0:
			continue
		var aim_at: Vector3 = rt.global_position + Vector3(0, rt.cy, 0)
		var look: Vector3 = (aim_at - eye).normalized()
		var from: Vector3 = eye + look * 0.6 + Vector3(0, -float(g["sight"]), 0)
		var d: Vector3 = w.zeroed_aim(g, ki, from, eye + look * 0.6, look)
		var off: float = await _fire_and_read(w, g, from, d, aim_at)
		print("[zero] carbine zeroed at %d m, board at %3d m: struck %+.3f m off the point of aim" % [
			int(w.zero_of(g)), int(rt.distance), off])
		if absf(rt.distance - 100.0) < 5.0:
			at_zero = off
		if absf(rt.distance - 300.0) < 10.0:
			at_300 = off
	if absf(at_zero) > 0.05:
		bad.append("not on at the zero (%+.3f)" % at_zero)
	if at_300 > -0.2:
		bad.append("no drop at 300 m (%+.3f)" % at_300)
	# dial the drop out at 300 m: the mils it fell, rounded to clicks
	for t2 in world.firing_range.targets:
		var rt2: FiringRange.RangeTarget = t2
		if absf(rt2.distance - 300.0) > 10.0:
			continue
		var clicks: float = roundf(-at_300 / rt2.distance * 1000.0 / w.click_of(g))
		w.elev_mil[ki] = clicks * w.click_of(g)
		var aim2: Vector3 = rt2.global_position + Vector3(0, rt2.cy, 0)
		var look2: Vector3 = (aim2 - eye).normalized()
		var from2: Vector3 = eye + look2 * 0.6 + Vector3(0, -float(g["sight"]), 0)
		var off2: float = await _fire_and_read(w, g, from2,
			w.zeroed_aim(g, ki, from2, eye + look2 * 0.6, look2), aim2)
		print("[zero] at 300 m with %+.1f mil dialled: struck %+.3f m" % [w.elev_mil[ki], off2])
		var right0: Vector3 = look2.cross(Vector3.UP).normalized()
		var lp2: Vector3 = (world.firing_range.rounds[world.firing_range.rounds.size() - 1] as Dictionary)["pos"]
		# as an angle, in mils: a round moved off the board flies on past it
		var side0: float = (lp2 - from2).dot(right0) / maxf((lp2 - from2).dot(look2), 1.0) * 1000.0
		if absf(off2) > 0.06:
			bad.append("elevation did not bring it on (%+.3f)" % off2)
		# and windage: two mils right is sixty centimetres at three hundred
		w.wind_mil[ki] = 2.0
		var n0: int = world.firing_range.rounds.size()
		Firearm.fire(world, w, 0, g, from2, w.zeroed_aim(g, ki, from2, eye + look2 * 0.6, look2), 0.0)
		for f in 1200:
			await world.get_tree().physics_frame
			if world.firing_range.rounds.size() > n0 \
					and not bool((world.firing_range.rounds[world.firing_range.rounds.size() - 1] as Dictionary)["live"]):
				break
		var lp3: Vector3 = (world.firing_range.rounds[world.firing_range.rounds.size() - 1] as Dictionary)["pos"]
		var right: Vector3 = look2.cross(Vector3.UP).normalized()
		var side: float = (lp3 - from2).dot(right) / maxf((lp3 - from2).dot(look2), 1.0) * 1000.0 - side0
		print("[zero] at 300 m: drift with nothing dialled %+.2f mil (the wind); 2.0 mil right moves it %+.2f mil more" % [side0, side])
		if absf(side - 2.0) > 0.15:
			bad.append("windage off (%+.3f)" % side)
		w.elev_mil[ki] = 0.0
		w.wind_mil[ki] = 0.0
		break
	print("[zero] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --ruintest
## What is drawn and what is solid after things are blown up, in a street
## fight: a bomb into a block, onto the props in a street, and a tank knocked
## out. Each should be a heap you can see and that stops a round, with nothing
## left standing whole that rounds go through. --preset=ground:foot --ruintest
var _wreck_test := false

func tick_wreck_test() -> void:
	if not _wreck_test or not is_instance_valid(world.cqb):
		return
	_wreck_test = false
	_run_wreck_test()

func _run_wreck_test() -> void:
	var ts: TownSet = world.cqb.dressing
	var c := Vector3(world.cqb.centre.x, 0.0, world.cqb.centre.y)
	var bad: Array = []
	# the nearest proper block to the middle of town
	var block := -1
	var bd := 1e9
	for id in Obstacles.ids_in(Vector2(c.x - 120, c.z - 120), Vector2(c.x + 120, c.z + 120)):
		if Obstacles.gone(id) or not Obstacles._squash.has(id):
			continue
		var h: Vector2 = Obstacles.half_of(id)
		if minf(h.x, h.y) < 6.0:
			continue
		var d: float = Vector2(Obstacles.centre_of(id).x - c.x, Obstacles.centre_of(id).z - c.z).length()
		if d < bd:
			bd = d
			block = id
	# and the props standing near it, before
	var bc: Vector3 = Obstacles.centre_of(block)
	var props_near := 0
	for id2 in ts._box_mesh.keys():
		if Obstacles.centre_of(int(id2)).distance_to(bc) < 30.0:
			props_near += 1
	var top_before: float = Obstacles.top_of(block)
	world.scenery.damage_area(Vector3(bc.x, Sim.height_at(bc.x, bc.z) + 2.0, bc.z), 30.0)
	for i in Engine.physics_ticks_per_second:
		await world.get_tree().physics_frame
	var heap: int = Obstacles.rubble_of(block)
	var g: float = Sim.height_at(bc.x, bc.z)
	var heap_top: float = Obstacles.top_of(heap) - g if heap >= 0 else -1.0
	var h2: Vector2 = Obstacles.half_of(block)
	var low_a: Vector3 = bc + Vector3(-h2.x - 20.0, 0.0, 0.0)
	var low_b: Vector3 = bc + Vector3(h2.x + 20.0, 0.0, 0.0)
	var low_y: float = g + minf(heap_top * 0.5, 0.6)
	var stops_low: bool = Obstacles.segment(Vector3(low_a.x, low_y, low_a.z), Vector3(low_b.x, low_y, low_b.z)) < 1.0
	print("[ruin] block %.0f m tall: gone %s, heap %.1f m (drawn at %.1f), stops a round at %.1f m: %s" % [
		top_before - g, str(Obstacles.gone(block)), heap_top, (top_before - g) * Scenery.BLOCK_HEAP - 0.4,
		low_y - g, str(stops_low)])
	if not Obstacles.gone(block) or heap < 0 or not stops_low:
		bad.append("the block left no solid heap")
	# props: every one whose box came out is drawn down, and has a heap
	var standing_ghosts := 0
	var downed := 0
	# a prop whose box went and whose mesh did not is the bug
	for mi in ts.get_children():
		if mi is MeshInstance3D and String(mi.name).begins_with("Prop") and not mi.has_meta("flat") \
				and (mi as Node3D).global_position.distance_to(bc) < 30.0 - 2.0:
			if Obstacles.blocks((mi as Node3D).global_position + Vector3(0, 0.3, 0), 0.3) < 0 \
					and Obstacles.hit((mi as Node3D).global_position + Vector3(0, 0.8, 0), 0.3) < 0:
				standing_ghosts += 1
		if mi is MeshInstance3D and mi.has_meta("flat"):
			downed += 1
	print("[ruin] %d props near it before; %d drawn down after, %d still drawn standing with nothing solid there" % [
		props_near, downed, standing_ghosts])
	if standing_ghosts > 0:
		bad.append("props left standing with no collider")
	# a tank knocked out: its hull stops a round and a man
	var t: Tank = null
	for v in world.get_tree().get_nodes_in_group("vehicles"):
		if v is Tank and (v as Tank).alive:
			t = v
			break
	if t != null:
		t.apply_damage(1.0e6)
		for i2 in 10:
			await world.get_tree().physics_frame
		var tp: Vector3 = t.global_position
		var side: Vector3 = t.global_transform.basis.x
		var through: float = Obstacles.segment(tp + side * 8.0, tp - side * 8.0)
		var man: int = Obstacles.blocks(Vector3(tp.x, Sim.height_at(tp.x, tp.z), tp.z), 0.3)
		print("[ruin] %s knocked out: a round across the hull stops %s, a man in it is blocked %s" % [
			t.display_name(), str(through < 1.0), str(man >= 0)])
		if through >= 1.0 or man < 0:
			bad.append("the wreck is not solid")
	print("[ruin] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --mortartest
## The mortar worked as it is meant to be: set up on the ground, laid on a
## block a few hundred metres off, and rounds put onto it until it comes down.
## --preset=cqb:foot --mortartest
var _mortar_test := false

func tick_mortar_test() -> void:
	if not _mortar_test or not is_instance_valid(world.cqb) or not is_instance_valid(world.walker):
		return
	_mortar_test = false
	_run_mortar_test()

func _run_mortar_test() -> void:
	var w: Walker = world.walker
	var bad: Array = []
	# a block a fair way from him, big enough to want several rounds
	var at: Vector3 = w.global_position
	var block := -1
	for id in Obstacles.ids_in(Vector2(at.x - 400, at.z - 400), Vector2(at.x + 400, at.z + 400)):
		if Obstacles.gone(id) or not Obstacles._squash.has(id):
			continue
		var h: Vector2 = Obstacles.half_of(id)
		var c: Vector3 = Obstacles.centre_of(id)
		var flat: float = Vector2(c.x - at.x, c.z - at.z).length()
		if minf(h.x, h.y) >= 6.0 and flat > 120.0 and flat < 380.0:
			block = id
			break
	if block < 0:
		print("[mortar] RESULT: FAILED -- no block in range to shell")
		world.get_tree().quit()
		return
	var tube := MortarTube.new()
	tube.spec = Firearm.spec("mortar")
	world.add_child(tube)
	tube.global_position = at
	while not tube.work(0.1):
		pass
	var bc: Vector3 = Obstacles.centre_of(block)
	var why: String = tube.cannot_reach(bc)
	if why != "":
		bad.append("could not lay on a block in range: " + why)
	tube.lay_on(bc)
	print("[mortar] block %d, %.0f m off, takes %.1f hits" % [block,
		Vector2(bc.x - at.x, bc.z - at.z).length(), Obstacles.toughness(block)])
	# too close is refused
	if tube.cannot_reach(at + Vector3(20, 0, 0)) == "":
		bad.append("a mission twenty metres off was accepted")
	var fired := 0
	for i in 12:
		var mr: MortarRound = tube.fire(w, world.cqb)
		# dead on, so the count says what the wear does, not the spread
		mr.to = MortarRound.lands_at(bc.x, bc.z)
		mr.flight = 1.0
		world.add_child(mr)
		fired += 1
		for k in Engine.physics_ticks_per_second * 2:
			await world.get_tree().physics_frame
		if Obstacles.gone(block):
			break
		print("[mortar] round %d: block worn %.0f%%" % [fired, Obstacles.wear_of(block) * 100.0])
	var down: bool = Obstacles.gone(block)
	print("[mortar] %d rounds: block %s, heap %d" % [fired, "DOWN" if down else "standing",
		Obstacles.rubble_of(block)])
	if not down:
		bad.append("twelve rounds on it and the block still stands")
	elif fired < 2:
		bad.append("one 60 mm round flattened a whole block")
	tube.queue_free()
	print("[mortar] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --ladderfall
## Shell the buildings that have scaffolding and ladders on them, and see what
## is left standing against nothing: --preset=cqb:foot --ladderfall
var _ladder_fall := false

func tick_ladder_fall() -> void:
	if not _ladder_fall or not is_instance_valid(world.cqb):
		return
	_ladder_fall = false
	_run_ladder_fall()

func _run_ladder_fall() -> void:
	var ts: TownSet = world.cqb.dressing
	if not is_instance_valid(ts):
		print("[ladderfall] RESULT: FAILED -- no town set")
		world.get_tree().quit()
		return
	var sc_before: int = ts.scaffolds.size()
	var ld_before: int = ts.ladders.size()
	# every building with something on it, from the scaffolds and the ladders
	var targets: Array = []
	for sc in ts.scaffolds:
		targets.append(Obstacles.centre_of(int(sc[5])))
	for l in ts.ladders:
		if not Obstacles.gone(int(l[2])) and Obstacles.top_of(int(l[2])) - (l[0] as Vector3).y > 6.0:
			targets.append(Obstacles.centre_of(int(l[2])))
	var climbable_before := 0
	for l2 in ts.ladders:
		if not TownSet.ladder_at((l2[0] as Vector3) + (l2[1] as Vector3) * 0.5 + Vector3(0, 0.5, 0)).is_empty():
			climbable_before += 1
	for c in targets:
		world.scenery.damage_area(c, 14.0)
	for i in Engine.physics_ticks_per_second * 2:
		await world.get_tree().physics_frame
	var standing_meshes := 0
	for l3 in ts.ladders:
		if l3.size() > 4 and is_instance_valid(l3[4]) and not (l3[4] as Node).has_meta("flat"):
			standing_meshes += 1
	var climbable_after := 0
	for l4 in ts.ladders:
		if not TownSet.ladder_at((l4[0] as Vector3) + (l4[1] as Vector3) * 0.5 + Vector3(0, 0.5, 0)).is_empty():
			climbable_after += 1
	print("[ladderfall] %d buildings shelled: scaffolds %d -> %d, ladders %d -> %d (climbable %d -> %d, %d upright meshes left)" % [
		targets.size(), sc_before, ts.scaffolds.size(), ld_before, ts.ladders.size(),
		climbable_before, climbable_after, standing_meshes])
	var bad := ts.scaffolds.size() > 0 and sc_before > 0
	for l5 in ts.ladders:
		if Obstacles.gone(int(l5[2])):
			bad = true
	print("[ladderfall] RESULT: %s" % ("FAILED -- dressing left against nothing" if bad else "ok"))
	world.get_tree().quit()
#endregion


#region --balltest
## The flight model itself: what the air takes, what the turn does, and
## whether the solver puts a round on its mark.
var _ball_test := false

func tick_ball() -> void:
	if _ball_test and world.running:
		_ball_test = false
		_run_ball_test()

## The flight model on its own, away from any weapon: speed kept against
## range, the solver against marks out to six hundred metres, the turn of the
## planet over an artillery shot, gravity with height, and the plain-gravity
## stretch at the muzzle.
func _run_ball_test() -> void:
	var bad: Array = []
	var o: Vector3 = Vector3(0.0, Sim.height_at(0.0, 0.0) + 2.0, 0.0)
	# speed kept: a carbine round and a sniper's, flown flat at 120 Hz
	for pair in [["carbine", 880.0, 0.0011], ["sniper", 870.0, 0.0005]]:
		var p: Vector3 = o
		var v := Vector3(0, 0, -float(pair[1]))
		var flown := 0.0
		var at300 := 0.0
		var at600 := 0.0
		while flown < 600.0:
			v = Ballistics.step(p, v, float(pair[2]), 1.0 / 120.0, flown)
			p += v / 120.0
			flown += v.length() / 120.0
			if at300 == 0.0 and flown >= 300.0:
				at300 = v.length()
		at600 = v.length()
		print("[ball] %-8s %.0f m/s at the muzzle, %.0f at 300 m (%.0f%%), %.0f at 600 m" % [
			pair[0], float(pair[1]), at300, at300 / float(pair[1]) * 100.0, at600])
	# the solver: lay on marks and fly the answer at 120 Hz, as a round flies
	for case in [[100.0, 880.0, 0.0011], [300.0, 880.0, 0.0011], [600.0, 870.0, 0.0005],
			[150.0, 76.0, 0.0006], [300.0, 76.0, 0.0006]]:
		var rng: float = case[0]
		var spd: float = case[1]
		var kk: float = case[2]
		var mark := Vector3(rng * 0.6, o.y - 3.0, -rng * 0.8)
		var guess: Vector3 = Firearm.lob(o, mark, spd, 9.81)
		var sol: Dictionary = Ballistics.solve(o, mark, spd, kk, guess)
		if sol.is_empty():
			bad.append("no solution at %.0f m for %.0f m/s" % [rng, spd])
			continue
		var p2: Vector3 = o
		var v2: Vector3 = (sol["dir"] as Vector3) * spd
		var flown2 := 0.0
		var best := INF
		for t in 120 * 30:
			v2 = Ballistics.step(p2, v2, kk, 1.0 / 120.0, flown2)
			var p3: Vector3 = p2 + v2 / 120.0
			flown2 += v2.length() / 120.0
			best = minf(best, Geometry3D.get_closest_point_to_segment(mark, p2, p3).distance_to(mark))
			p2 = p3
			if p2.y < mark.y - 50.0:
				break
		var vac: float = asin(clampf(guess.y, -1.0, 1.0))
		var real: float = asin(clampf((sol["dir"] as Vector3).y, -1.0, 1.0))
		print("[ball] %4.0f m at %3.0f m/s: laid %.3f deg (vacuum %.3f), passes %.2f m from the mark" % [
			rng, spd, rad_to_deg(real), rad_to_deg(vac), best])
		# a 40 mm round bursts over three metres; a rifle round has to be on it
		if best > (0.6 if spd < 200.0 else 0.2):
			bad.append("the solution at %.0f m for %.0f m/s misses by %.2f m" % [rng, spd, best])
	# the planet's turn over a long artillery arc
	var mk2 := Vector3(0.0, o.y, -18000.0)
	var v0 := Vector3(0.0, sin(deg_to_rad(40.0)), -cos(deg_to_rad(40.0))) * 560.0
	var spun: Array = Ballistics.fly(o, v0, 0.00001, mk2, 200.0)
	print("[ball] the planet's turn: %s rad/s, %.1f%% of it about the local vertical" % [
		str(Ballistics.spin().length()), Ballistics.spin().normalized().y * 100.0])
	if not spun.is_empty():
		var at: Vector3 = spun[0]
		print("[ball] a 40 degree shell at 560 m/s, crossing 18 km down range after %.1f s, is %.0f m to one side and %.0f m off the height" % [
			float(spun[1]), at.x - o.x, at.y - o.y])
	# gravity with height
	var g0: float = Ballistics.accel(Vector3(0, 0, 0), Vector3.ZERO, 0.0, Vector3.ZERO).length()
	var g10k: float = Ballistics.accel(Vector3(0, 10000, 0), Vector3.ZERO, 0.0, Vector3.ZERO).length()
	print("[ball] gravity at the surface %.3f, ten kilometres up %.3f" % [g0, g10k])
	if absf(g0 - 9.81) > 0.01 or g10k >= g0:
		bad.append("gravity is not 9.81 at the surface and less above it")
	# the muzzle stretch is plain gravity
	var vn: Vector3 = Ballistics.step(o, Vector3(0, 0, -880), 0.0011, 1.0 / 120.0, 10.0)
	if absf(vn.z + 880.0) > 1e-3 or absf(vn.y + 9.81 / 120.0) > 1e-4:
		bad.append("the first thirty metres are not plain gravity")
	for b in bad:
		print("[ball] %s" % b)
	print("[ball] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --boundstest
## The edges of a street fight, and the country hidden beyond them.
var _bounds_test := false

func tick_bounds() -> void:
	if _bounds_test and world.running and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_bounds_test = false
		_run_bounds_test()

# ---------------------------------------------------------------- shell
## What a street fight hides of the country, what it does to a man who walks
## out of it, and that the country comes back for the next mission.
func _run_bounds_test() -> void:
	for sd in world.cqb.soldiers:
		if is_instance_valid(sd):
			(sd as Node).set_process(false)
	for i in 30:
		await world.get_tree().physics_frame
	var bad: Array = []
	var hidden: int = world.street_fight._hidden_far.size()
	var insts := 0
	for gi in world.street_fight._hidden_far:
		if gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			insts += (gi as MultiMeshInstance3D).multimesh.instance_count
	var shown := 0
	for n in world.scenery.find_children("*", "GeometryInstance3D", true, false):
		if (n as GeometryInstance3D).visible:
			shown += 1
	print("[bounds] street fight: %d scenery batches hidden (%d instances), %d still drawn" % [
		hidden, insts, shown])
	if hidden == 0:
		bad.append("nothing beyond the fight was hidden")
	# out, and back in before the time is up
	var home: Vector3 = world.walker.global_position
	var out := Vector3(world._bounds_c.x + StreetFight.BOUNDS_CQB + 60.0, 0.0, world._bounds_c.z)
	out.y = Sim.height_at(out.x, out.z)
	world.walker.global_position = out
	for i in 120 * 3:
		await world.get_tree().physics_frame
	var warned: float = world.hud.oob_left
	world.walker.global_position = home
	for i in 30:
		await world.get_tree().physics_frame
	var cleared: bool = world.hud.oob_left < 0.0
	print("[bounds] three seconds out: %.1f s left on the warning; back in, warning gone %s" % [
		warned, str(cleared)])
	if warned < 0.0 or warned > 8.0 or not cleared:
		bad.append("the warning did not count down and clear")
	# out, and staying out
	world.walker.global_position = out
	var dead := false
	for i in 120 * 12:
		await world.get_tree().physics_frame
		if not is_instance_valid(world.walker) or world.walker.dead:
			dead = true
			break
		world.walker.global_position = out
	print("[bounds] staying out: %s" % ("killed" if dead else "still standing after twelve seconds"))
	if not dead:
		bad.append("staying out of bounds did not end him")
	# the next mission has its country back: everything the fight hid
	var was_hidden: Array = world.street_fight._hidden_far.duplicate()
	world._start("f16", "free")
	await world.get_tree().physics_frame
	var back := 0
	for n in was_hidden:
		if is_instance_valid(n) and not (n as GeometryInstance3D).visible:
			back += 1
	print("[bounds] next mission: %d scenery batches still hidden" % back)
	if back > 0 or world._bounds_c != Vector3.INF:
		bad.append("the country did not come back")
	for b in bad:
		print("[bounds] %s" % b)
	print("[bounds] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --steertest --cqbtest
var _cqb_sup := 0
var _cqb_los_said := false
var _steer_test := false
var _steer_t0 := -1.0
var _steer_h0 := 0.0
var _cqb_moved_said := false
var _cqb_dummy: Tank = null
var _cqb_dummy_hp := 0.0
var _cqb_t := 0.0
var _cqb_said := 0

func tick_cqb(delta: float) -> void:
	if world.street_fight._cqb_test and is_instance_valid(world.cqb):
		_tick_cqb_test(delta)

## Does the street fight actually happen? Run with --preset=cqb --cqbtest.
##
## Nothing here drives the player: it stands him where he spawned and watches
## the two squads. What it wants to know is whether the set was built, whether
## the men can find their way through it, whether they find each other, and
## whether the rig is holding the weapon and standing on the ground while they
## do. Each of those has a way of failing silently -- a squad that cannot route
## stands at its start line for ever and the match simply never begins.
func _tick_cqb_test(delta: float) -> void:
	_cqb_t += delta
	if _steer_test and is_instance_valid(world.tank):
		# Which way does "right" turn it? Hold the key and watch the nose.
		if _steer_t0 < 0.0 and _cqb_t > 4.0:
			_steer_t0 = _cqb_t
			var f0: Vector3 = -world.tank.global_transform.basis.z
			_steer_h0 = atan2(f0.x, -f0.z)
			Input.action_press(&"roll_right")
			Input.action_press(&"pitch_down")
		elif _steer_t0 >= 0.0 and _cqb_t > _steer_t0 + 1.5:
			var f1: Vector3 = -world.tank.global_transform.basis.z
			var turned: float = rad_to_deg(wrapf(atan2(f1.x, -f1.z) - _steer_h0, -PI, PI))
			Input.action_release(&"roll_right")
			Input.action_release(&"pitch_down")
			print("[steer] %s, forward and RIGHT held for 4 s: nose went %+.0f degrees (%s), %.1f m/s" % [
				world.tank.display_name(), turned, "to the right" if turned > 0.0 else "TO THE LEFT",
				world.tank.linear_velocity.length()])
			world.get_tree().quit()
		return
	if not is_instance_valid(world.walker):
		# in a vehicle or an aeroplane: nothing of his to measure, so just
		# watch the fight
		if _cqb_t > 38.0 and not _cqb_moved_said:
			_cqb_moved_said = true
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if n is Tank and (n as Tank).ai and n.has_meta("cqb_from"):
					var tk := n as Tank
					print("[cqb] %s: %.0f m from where it started, %.1f m/s, alive=%s, in a building=%s" % [
						tk.name, tk.global_position.distance_to(tk.get_meta("cqb_from")),
						tk.linear_velocity.length(), str(tk.alive),
						str(Obstacles.hit(tk.global_position, 1.0) >= 0)])
		if not _cqb_los_said and _cqb_t > 0.3:
			_cqb_los_said = true
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if n is Tank:
					n.set_meta("cqb_from", (n as Tank).global_position)
			var sees := 0
			var pairs := 0
			for a in world.get_tree().get_nodes_in_group("hittable"):
				for b in world.get_tree().get_nodes_in_group("hittable"):
					if a is Tank and b is Tank and (a as Tank).team == 0 and (b as Tank).team == 1:
						pairs += 1
						if Obstacles.segment((a as Tank).global_position + Vector3(0, 2.2, 0),
								(b as Tank).global_position + Vector3(0, 2.2, 0)) >= 1.0:
							sees += 1
			print("[cqb] vehicles at the start: %d of %d opposing pairs can see each other" % [sees, pairs])
		if _cqb_t > float(_cqb_said + 1) * 20.0:
			_cqb_said += 1
			var sv: Dictionary = world.mode.hud_state()
			var tanks := 0
			var planes := 0
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if n is Tank and (n as Tank).alive:
					tanks += 1
				elif n is Aircraft and (n as Aircraft).alive and n != world.player:
					planes += 1
			print("[cqb] t=%3.0f  kills us %d them %d   %d men, %d vehicles and %d aircraft up; in a %s" % [
				_cqb_t, int((sv["kills"] as Dictionary).get(0, 0)), int((sv["kills"] as Dictionary).get(1, 0)),
				world.cqb.soldiers.size(), tanks, planes,
				world.tank.display_name() if is_instance_valid(world.tank) else (String(world.player.spec["name"])
				if is_instance_valid(world.player) else "nothing: shot down")])
		if _cqb_t > 62.0:
			world.get_tree().quit()
		return
	if _cqb_said == 0 and _cqb_t > 0.5:
		_cqb_said = 1
		print("[cqb] %s, %s: %d cranes (top at %s), %d scaffolds" % [String(world.cqb.stats.get("faction", "?")),
			String(world.cqb.stats.get("biome", "?")), int(world.cqb.stats.get("cranes", 0)),
			str(world.cqb.crane_at.round()), int(world.cqb.stats.get("scaffolds", 0))])
		print("[cqb] arena at %s: %d props, %d ruins, %d of %d grid points walkable, %d obstacle boxes of our own" % [
			str(world.cqb.centre), int(world.cqb.stats["props"]), int(world.cqb.stats["ruins"]),
			int(world.cqb.stats["free_cells"]), world.cqb._n * world.cqb._n, world.cqb.dressing._boxes.size()])
		var a: Vector3 = world.cqb.spawn_point(0)
		var b: Vector3 = world.cqb.spawn_point(1)
		# The buildings that were opened up: can a man on the start line walk
		# into each of them?
		var ts_in: TownSet = world.cqb.dressing
		var walk_in := 0
		var a_piece: int = world.cqb._comp[world.cqb._cell(a).y * world.cqb._n + world.cqb._cell(a).x]
		for hb in ts_in._hollowed:
			var mid_c: Vector2i = world.cqb._cell(hb[3] + Vector3(1.6, 0, 1.6))
			if not world.cqb._nav.is_point_solid(mid_c) \
					and world.cqb._comp[mid_c.y * world.cqb._n + mid_c.x] == a_piece:
				walk_in += 1
		print("[cqb] buildings: %d of %d with a ground floor to go into (%d on too much of a slope), %d doors cut, %d of them reachable on foot from the start line" % [
			int(ts_in.stats.get("interiors", 0)), int(ts_in.stats.get("blocks", 0)),
			int(ts_in.stats.get("too_steep", 0)), int(ts_in.stats.get("doors", 0)), walk_in])
		var route: PackedVector2Array = world.cqb.path(a, b)
		var walked := 0.0
		for i in range(1, route.size()):
			walked += route[i].distance_to(route[i - 1])
		print("[cqb] start line to start line: %.0f m apart, route of %d points and %.0f m" % [
			a.distance_to(b), route.size(), walked])
		print("[cqb] %d soldiers up; player at %s with %s, %d rounds" % [
			world.cqb.soldiers.size(), str(world.walker.global_position.round()),
			String(world.walker.gun_spec()["name"]), world.walker.ammo])
		# the rig, swept through the whole of its travel with every weapon
		var body: Pilot = world.walker.body
		for g in Firearm.KIT:
			body.equip(g)
			var worst_r := 0.0
			var worst_l := 0.0
			var worst_f := 0.0
			for step in 60:
				body.in_pitch = deg_to_rad(lerpf(-75.0, 75.0, float(step % 20) / 19.0))
				body.in_ads = 1.0 if step >= 20 else 0.0
				body.in_crouch = step >= 40
				body.in_lean = 0.0 if step < 50 else 1.0
				body.in_move = Vector2.ZERO
				body.in_air = 0
				body.in_ready = 1.0
				body.in_reload = -1.0
				for settle in 30:
					body.animate(0.05)
				var e: Dictionary = body.rig_error()
				worst_r = maxf(worst_r, float(e["hand_r"]))
				worst_l = maxf(worst_l, float(e["hand_l"]))
				worst_f = maxf(worst_f, maxf(absf(float(e["foot_l"])), absf(float(e["foot_r"]))))
			print("[cqb] rig %-14s worst hand off grip: right %.3f m, left %.3f m; worst foot off floor %.3f m" % [
				String(g["name"]), worst_r, worst_l, worst_f])
		body.equip(world.walker.gun_spec())
		world.walker.take_hit(0.0)
		# Getting over and onto things. Stand him square in front of one of
		# each and ask; then run the move to its end and see where he is.
		for want in [["barrier", "vault"], ["sandbags", "vault"], ["container", "climb"],
				["crates", "climb"], ["car", "climb"]]:
			var found := false
			for pr in world.cqb.props:
				if String(pr[0]) != String(want[0]) or found:
					continue
				var at: Vector3 = pr[1]
				var across := Basis(Vector3.UP, float(pr[2])) * Vector3(0, 0, 1)
				if String(want[0]) in ["container", "car"]:
					across = Basis(Vector3.UP, float(pr[2])) * Vector3(1, 0, 0)
				var thick: float = {"barrier": 0.31, "sandbags": 0.40, "crates": 0.65,
					"car": 0.93, "container": 1.22}[String(want[0])]
				var stand: Vector3 = at + across * (thick + 0.75)
				stand.y = Sim.height_at(stand.x, stand.z)
				if Obstacles.blocks(stand, Walker.BODY_R) >= 0:
					continue
				found = true
				world.walker.global_position = stand
				world.walker.on_floor = true
				var began: bool = world.walker._begin_traverse(-across, false)
				var kind: String = world.walker._trav
				var span: float = world.walker._trav_span
				var steps := 0
				while world.walker._trav != "" and steps < 600:
					world.walker._traverse(1.0 / 120.0)
					steps += 1
				print("[cqb] %-9s (top %.2f m): %s%s, %.2f s, ends %.2f m above where he started and %.2f m on" % [
					String(want[0]), Obstacles.top_at(at.x, at.z) - stand.y,
					kind if began else "REFUSED", "" if kind == String(want[1]) or not began
					else " (expected %s)" % String(want[1]), span,
					world.walker.global_position.y - stand.y,
					Vector2(world.walker.global_position.x - stand.x, world.walker.global_position.z - stand.z).length()])
			if not found:
				print("[cqb] no %s to try" % String(want[0]))
		# Up the crane, the way anybody would: jump at the mast, climb, and
		# walk out along the jib.
		if world.cqb.crane_at != Vector3.INF:
			var mast := Vector3(world.cqb.crane_at.x, 0.0, world.cqb.crane_at.z)
			var from_side := mast + Vector3(0, 0, 1.9)
			from_side.y = Sim.height_at(from_side.x, from_side.z)
			world.walker.global_position = from_side
			world.walker.on_floor = true
			var took: bool = world.walker._begin_traverse(Vector3(0, 0, -1), false)
			var ticks := 0
			world.walker.test_climb = 1.0
			while (world.walker._wall >= 0 or world.walker._trav != "") and ticks < 6000:
				if world.walker._wall >= 0:
					world.walker._on_wall(1.0 / 120.0)
				else:
					world.walker._traverse(1.0 / 120.0)
				ticks += 1
			world.walker.test_climb = 0.0
			var up_y: float = world.walker.global_position.y
			# along the jib, a pace at a time, the way the ground code would
			var jib_ok := 0
			for stepn in 20:
				var q := world.walker.global_position + (Vector3(1, 0, 0) if stepn >= 0 else Vector3.ZERO)
				if absf(Obstacles.floor_under(q.x, q.z, up_y) - up_y) < 0.2:
					jib_ok += 1
			var q2 := world.walker.global_position + Vector3(0, 0, 1)
			var jz := 0
			for stepn in 20:
				if absf(Obstacles.floor_under(q2.x, q2.z + stepn, up_y) - up_y) < 0.2:
					jz += 1
			print("[cqb] crane: took hold=%s, %.1f s to the top, now %.1f m up (mast is %.1f); jib underfoot for %d m; and standing under the jib the floor is %.1f m up" % [
				str(took), ticks / 120.0, up_y - from_side.y, world.cqb.crane_at.y - from_side.y,
				maxi(jib_ok, jz), Obstacles.floor_under(mast.x + 8.0, mast.z, from_side.y) - from_side.y
				if Obstacles.floor_under(mast.x + 8.0, mast.z, from_side.y) > -1e8 else 0.0])
			world.walker.third = false
			world.walker._wall = -1
		# A ladder: step onto it, go up it, and check the hands and feet are
		# on the face the whole way.
		print("[cqb] %d ladders" % world.cqb.ladders.size())
		if not world.cqb.ladders.is_empty():
			var lad: Array = world.cqb.ladders[world.cqb.ladders.size() - 1]
			var lfoot: Vector3 = lad[0]
			var ln2: Vector3 = lad[1]
			world.walker.global_position = lfoot + ln2 * 0.7
			world.walker.global_position.y = Sim.height_at(world.walker.global_position.x, world.walker.global_position.z)
			world.walker.on_floor = true
			var seen_l: Array = TownSet.ladder_at(world.walker.global_position)
			var y0: float = world.walker.global_position.y
			if not seen_l.is_empty():
				world.walker._take_ladder(seen_l)
			var on_it: bool = world.walker._ladder
			world.walker.test_climb = 1.0
			var worst_h := 0.0
			var worst_f := 0.0
			var lt := 0
			while (world.walker._wall >= 0 or world.walker._trav != "") and lt < 6000:
				if world.walker._wall >= 0:
					world.walker._on_wall(1.0 / 120.0)
					if lt > 60 and world.walker._wall >= 0:
						var le: Dictionary = world.walker.body.rig_error()
						worst_h = maxf(worst_h, maxf(float(le["hand_l"]), float(le["hand_r"])))
						worst_f = maxf(worst_f, maxf(float(le["foot_l"]), float(le["foot_r"])))
				else:
					world.walker._traverse(1.0 / 120.0)
				lt += 1
			world.walker.test_climb = 0.0
			print("[cqb] ladder: found=%s, on it=%s, %.1f s, ends %.1f m up of %.1f; worst hand %.0f mm and worst foot %.0f mm off the face" % [
				str(not seen_l.is_empty()), str(on_it), lt / 120.0, world.walker.global_position.y - y0,
				float(lad[3]) - y0, worst_h * 1000.0, worst_f * 1000.0])
			world.walker.third = false
			world.walker._wall = -1
			world.walker.body.in_action = ""
		# How steady the sights are on the move: walk with them up and measure
		# how far the eye and the weapon wander from each other and in space.
		body.equip(world.walker.gun_spec())
		for case in [["standing, walking", false, false], ["crouched, walking", true, false],
				["prone, crawling", false, true]]:
			body.in_crouch = case[1]
			body.in_prone = case[2]
			body.in_ads = 1.0
			body.in_pitch = 0.0
			body.in_lean = 0.0
			body.in_action = ""
			body.in_move = Vector2(0.6, 2.2) if not case[2] else Vector2(0.0, 0.9)
			for settle in 480:
				body.animate(1.0 / 120.0)
			var e0: Vector3 = world.walker.to_local(body.eye_pos())
			var w0: Vector3 = body.weapon_mount.position - e0
			var eye_w := 0.0
			var gun_w := 0.0
			var hand_w := 0.0
			for tick in 360:
				body.animate(1.0 / 120.0)
				var e1: Vector3 = world.walker.to_local(body.eye_pos())
				eye_w = maxf(eye_w, e1.distance_to(e0))
				gun_w = maxf(gun_w, (body.weapon_mount.position - e1).distance_to(w0))
				var re: Dictionary = body.rig_error()
				hand_w = maxf(hand_w, maxf(float(re["hand_r"]), float(re["hand_l"])))
			print("[cqb] sights up, %-18s eye moves %.1f mm, weapon moves %.1f mm against the eye, worst hand off grip %.1f mm; eye height %.2f m" % [
				String(case[0]) + ":", eye_w * 1000.0, gun_w * 1000.0, hand_w * 1000.0, e0.y])
		body.in_crouch = false
		body.in_prone = false
		body.in_move = Vector2.ZERO
		# The tube and the missile. A tank put down in front of him for the
		# rocket; for the missile, whatever of theirs is flying.
		world.walker.global_position = world.cqb.spawn_point(0, 0)
		var here: Vector3 = world.walker.global_position
		var dummy := world._spawn_tank(here + Vector3(0, 0, -45.0), 0.0, 1, "bmp3")
		dummy.ai = false
		var hp0: float = dummy.health
		var fwd0 := (dummy.global_position + Vector3(0, 1.2, 0) - (here + Vector3(0, 1.6, 0))).normalized()
		Firearm.rocket(world, world.walker, 0, Firearm.spec("law"), here + Vector3(0, 1.6, 0), fwd0)
		_cqb_dummy = dummy
		_cqb_dummy_hp = hp0
		world.walker.apply_class(CqbMatch.kit_classes()[1])
		print("[cqb] anti-armour class: slots %s, holding %s (%d + %d), second %s" % [str(world.walker.slots),
			String(world.walker.gun_spec()["name"]), world.walker.ammo, world.walker.spare,
			String(world.walker.spec_of(int(world.walker.slots[1]))["name"])])
		var mk4: Dictionary = Firearm.fitted("carbine", {"sight": "scope", "grip": true, "mag": true})
		# Each weapon of a class fitted on its own: a scope and a can on the
		# rifle, and neither on the submachine gun beside it.
		var own: Dictionary = (CqbMatch.kit_classes()[0] as Dictionary).duplicate(true)
		own["primary"] = "carbine"
		own["second"] = "smg"
		own["fit"] = {"carbine": {"sight": "scope", "quiet": true, "grip": false, "mag": false},
			"smg": {"sight": "dot", "quiet": false, "grip": true, "mag": true}}
		world.walker.apply_class(own)
		var own_a: Dictionary = world.walker.spec_of(Firearm.index_of("carbine"))
		var own_b: Dictionary = world.walker.spec_of(Firearm.index_of("smg"))
		print("[cqb] gunsmith, each on its own: carbine fov %.0f quiet=%s magazine %d; smg fov %.0f quiet=%s magazine %d -> %s" % [
			float(own_a["fov"]), str(own_a["quiet"]), int(own_a["mag"]),
			float(own_b["fov"]), str(own_b["quiet"]), int(own_b["mag"]),
			"ok" if (bool(own_a["quiet"]) and not bool(own_b["quiet"]) and int(own_a["mag"]) == 30
				and int(own_b["mag"]) == 60 and float(own_a["fov"]) < 25.0 and float(own_b["fov"]) > 40.0)
			else "FAILED"])
		# ...and the bench itself, worked the way a hand works it: fit the
		# second weapon, look at the first, swap the first for another.
		var bench_ui := DeployMenu.new()
		world.add_child(bench_ui)
		var pick_was: int = CqbMatch.class_pick
		bench_ui.open("none", true, "usa")
		bench_ui._pick(3)
		var bc: Dictionary = CqbMatch.kit_classes()[3]
		var bc_was: Dictionary = bc.duplicate(true)
		bench_ui._to_bench(1)
		bench_ui._sight.select(1)
		bench_ui._sight.item_selected.emit(1)
		bench_ui._grip.button_pressed = true
		bench_ui._to_bench(0)
		var fit_1: Dictionary = Firearm.setup_for(bc, String(bc["primary"]))
		var fit_2: Dictionary = Firearm.setup_for(bc, String(bc["second"]))
		bench_ui._primary.select(DeployMenu.LONG.find("fifty"))
		bench_ui._primary.item_selected.emit(DeployMenu.LONG.find("fifty"))
		print("[cqb] bench: %s keeps sight %s grip=%s; %s now sight %s grip=%s; swapped the first for %s, and the bench shows weapon %d -> %s" % [
			String(bc_was["primary"]), String(fit_1["sight"]), str(fit_1["grip"]),
			String(bc["second"]), String(fit_2["sight"]), str(fit_2["grip"]),
			String(bc["primary"]), bench_ui._bench,
			"ok" if (String(fit_1["sight"]) == String(bc_was["sight"]) and not bool(fit_1["grip"])
				and String(fit_2["sight"]) == "dot" and bool(fit_2["grip"])
				and String(bc["primary"]) == "fifty" and bench_ui._bench == 0) else "FAILED"])
		print("[cqb] bench reads:\n%s" % bench_ui._stats.text)
		bc.clear()
		bc.merge(bc_was)
		CqbMatch.class_pick = pick_was
		bench_ui.queue_free()
		# What goes through what: a wall of each thickness put up in clear air,
		# and a round of each kind fired square at it.
		var pen_bad := PackedStringArray()
		var sky: Vector3 = world.walker.global_position + Vector3(0, 400.0, 0)
		for pcase in [["pistol", 0.30, false], ["carbine", 0.14, true], ["carbine", 0.40, false],
				["dmr", 0.40, true], ["sniper", 1.0, false], ["fifty", 1.0, true], ["fifty", 3.0, false]]:
			var slab: int = Obstacles.add_box(sky + Vector3(0, -2.0, -20.0), 3.0, 4.0, float(pcase[1]) * 0.5)
			var pg: Dictionary = Firearm.spec(String(pcase[0]))
			var rd: Effects.Tracer = Effects.bullet(world, sky, Vector3(0, 0, -float(pg["muzzle"])), null,
				float(pg["dmg"]), 0, 1.0, 1.4, Firearm.drag_of(pg), Firearm.pen_of(pg))
			var went := false
			for tick in 40:
				if rd.is_queued_for_deletion():
					break
				rd._fly(1.0 / 240.0)
				if rd.global_position.z < sky.z - 24.0:
					went = true
					break
			if not rd.is_queued_for_deletion():
				rd.queue_free()
			Obstacles.remove(slab)
			if went != bool(pcase[2]):
				pen_bad.append("%s against %.2f m: through=%s" % [String(pcase[0]), float(pcase[1]), str(went)])
		print("[cqb] penetration, seven cases of round against wall: %s" % (
			"ok" if pen_bad.is_empty() else "FAILED " + "; ".join(pen_bad)))
		# And through men: two of theirs stood one behind the other, and a
		# round sent down the line of them.
		var line_up: Array = []
		for sd in world.cqb.soldiers:
			if is_instance_valid(sd) and sd.alive and sd.team == 1 and line_up.size() < 2:
				line_up.append(sd)
		if line_up.size() == 2:
			var was_at: Array = [line_up[0].global_position, line_up[1].global_position]
			var was_hp: Array = [line_up[0].health, line_up[1].health]
			var men_out := PackedStringArray()
			for mcase in [["pistol", 1], ["carbine", 2], ["fifty", 2]]:
				for mi2 in 2:
					line_up[mi2].global_position = sky + Vector3(0, -1.2, -10.0 - 4.0 * mi2)
					line_up[mi2].health = 100.0
				Sim._hit_tick = -1
				var mg: Dictionary = Firearm.spec(String(mcase[0]))
				var mr: Effects.Tracer = Effects.bullet(world, sky, Vector3(0, 0, -300.0), null, 1.0, 0,
					1.0, 1.4, 0.0, Firearm.pen_of(mg))
				for tick2 in 30:
					if mr.is_queued_for_deletion():
						break
					mr._fly(1.0 / 240.0)
				if not mr.is_queued_for_deletion():
					mr.queue_free()
				var struck_n := 0
				for mi3 in 2:
					if line_up[mi3].health < 100.0:
						struck_n += 1
				men_out.append("%s %d%s" % [String(mcase[0]), struck_n,
					"" if struck_n == int(mcase[1]) else " (FAILED, wanted %d)" % int(mcase[1])])
			for mi4 in 2:
				line_up[mi4].global_position = was_at[mi4]
				line_up[mi4].health = was_hp[mi4]
			Sim._hit_tick = -1
			print("[cqb] one round down a line of two men, how many it hit: %s" % ", ".join(men_out))
		# Being shot at and missed: a burst a metre past one of theirs, and
		# one past him.
		if line_up.size() == 2:
			var pin_at: Vector3 = line_up[0].global_position
			line_up[0].global_position = sky + Vector3(1.0, -0.9, -12.0)
			line_up[0]._pinned = 0.0
			var me_at: Vector3 = world.walker.global_position
			world.walker.suppression = 0.0
			for side_n in 2:
				if side_n == 1:
					line_up[0].global_position = pin_at
					world.walker.global_position = sky + Vector3(1.0, -0.9, -12.0)
				Sim._hit_tick = -1
				for shot in 6:
					var sr: Effects.Tracer = Effects.bullet(world, sky, Vector3(0, 0, -600.0), null, 26.0,
						side_n, 1.0, 1.4, 0.0, 0.3)
					for tick3 in 12:
						if sr.is_queued_for_deletion():
							break
						sr._fly(1.0 / 240.0)
					if not sr.is_queued_for_deletion():
						sr.queue_free()
			print("[cqb] six rifle rounds a metre wide: their man pinned %.2f (takes cover past %.2f), ours suppressed %.2f, nobody hit=%s" % [
				line_up[0]._pinned, Soldier.PINNED, world.walker.suppression,
				str(line_up[0].health >= 100.0)])
			world.walker.global_position = me_at
			world.walker.suppression = 0.0
			line_up[0].global_position = pin_at
			line_up[0]._pinned = 0.0
			Sim._hit_tick = -1
		# A stun grenade at his feet.
		var bang := Firearm.Frag.new()
		bang.flash = true
		world.add_child(bang)
		bang.global_position = world.walker.global_position + Vector3(0, 0.2, -1.5)
		bang._dazzle()
		print("[cqb] flashbang at his feet: blind for %.1f s, %d to throw" % [world.walker.flash_left(), world.walker.flashes])
		world.walker._flash_until = 0.0
		print("[cqb] gunsmith: carbine with scope, grip and long magazine: fov %.0f, magazine %d, kick %.4f (stock %.4f)" % [
			float(mk4["fov"]), int(mk4["mag"]), float(mk4["kick"]), float(Firearm.spec("carbine")["kick"])])
		world.walker.apply_class(CqbMatch.kit_classes()[0])
		# Lying down and shooting level: how high the muzzle is, and whether a
		# round fired along the sight line clears the ground for 80 metres.
		world.walker.global_position = world.cqb.spawn_point(0, 0)
		body.equip(world.walker.gun_spec())
		body.in_prone = true
		body.in_crouch = true
		body.in_air = 0
		body.in_ads = 1.0
		body.in_pitch = 0.0
		body.in_move = Vector2.ZERO
		body.in_action = ""
		for settle2 in 240:
			body.animate(1.0 / 120.0)
		var mz: Vector3 = body.muzzle_pos()
		var ey: Vector3 = body.eye_pos()
		var fwdp := Vector3(-sin(world.walker.yaw), 0, -cos(world.walker.yaw))
		var clear_m := 0.0
		for stepp in 80:
			var q3: Vector3 = mz + fwdp * float(stepp)
			if q3.y < Sim.height_at(q3.x, q3.z):
				break
			clear_m = float(stepp)
		print("[cqb] prone: eye %.2f m and muzzle %.2f m above the ground; a level round clears the ground for %.0f m" % [
			ey.y - Sim.height_at(ey.x, ey.z), mz.y - Sim.height_at(mz.x, mz.z), clear_m])
		body.in_prone = false
		body.in_crouch = false
		# What is left of a man, each way of killing him.
		var before_nodes: int = world.get_child_count()
		for case in [["blast", 300.0, false, false], ["head shot", 60.0, true, false],
				["heavy round, low", 64.0, false, true], ["heavy round, high", 64.0, false, false],
				["rifle round", 26.0, false, false]]:
			var n0: int = world.get_child_count()
			Ragdoll.fall(world, Transform3D(Basis(Vector3.UP, 1.1), world.walker.global_position + Vector3(6, 0, 0)),
				Vector3.ZERO, Pilot.SUIT, Pilot.HELMET, float(case[1]), bool(case[2]), bool(case[3]),
				Vector3(0, 0, -1))
			var doll: Ragdoll = null
			for ch in world.get_children():
				if ch is Ragdoll and ch.get_index() >= n0:
					doll = ch
			print("[cqb] killed by %-18s -> %s, %d pieces thrown" % [String(case[0]) + ":",
				("a body missing %s" % str(doll.lost) if not doll.lost.is_empty() else "a whole body")
				if doll != null else "nothing left to fall", world.get_child_count() - n0 - (1 if doll != null else 0)])
		print("[cqb] %d things on the ground after five deaths" % (world.get_child_count() - before_nodes))
		# and a weapon off the road
		var home: Vector3 = world.cqb.spawn_point(0, 0)
		world.walker.global_position = home
		Firearm.drop(world, "shotgun", 4, home + Vector3(0.8, 0, -0.8))
		var before: String = String(world.walker.gun_spec()["id"])
		world.walker._near_drop = null
		for n in world.get_tree().get_nodes_in_group("pickups"):
			world.walker._grab_item = n
		world.walker._grab_t = 0.0
		for i in 120:
			world.walker._reach_for(1.0 / 120.0)
		print("[cqb] pick-up: was holding %s, now %s with %d + %d; slots %s; %d weapon(s) left on the road" % [
			before, String(world.walker.gun_spec()["id"]), world.walker.ammo, world.walker.spare,
			str(world.walker.slots), world.get_tree().get_nodes_in_group("pickups").size()])
	if _cqb_t > float(_cqb_said) * 10.0 and _cqb_said >= 1:
		_cqb_said += 1
		var st: Dictionary = world.mode.hud_state()
		var moved := 0
		var fighting := 0
		var far := 0.0
		for s in world.cqb.soldiers:
			if not is_instance_valid(s):
				continue
			var sd := s as Soldier
			if sd.vel.length() > 0.5:
				moved += 1
			if sd.state == Soldier.FIGHT:
				fighting += 1
			far = maxf(far, absf(sd.global_position.z - world.cqb.centre.y))
		print("[cqb] t=%3.0f  kills us %d them %d   %d up, %d moving, %d in contact; player health %.0f, deaths %d" % [
			_cqb_t, int((st["kills"] as Dictionary).get(0, 0)),
			int((st["kills"] as Dictionary).get(1, 0)), world.cqb.soldiers.size(), moved,
			fighting, world.walker.health if is_instance_valid(world.walker) else -1.0, world.cqb.deaths])
	if _cqb_dummy != null and _cqb_t > 3.0:
		print("[cqb] rocket at a BMP-3 at 45 m: health %.0f -> %.0f, alive=%s" % [_cqb_dummy_hp,
			_cqb_dummy.health if is_instance_valid(_cqb_dummy) else -1.0,
			str(_cqb_dummy.alive) if is_instance_valid(_cqb_dummy) else "gone"])
		if is_instance_valid(_cqb_dummy):
			_cqb_dummy.queue_free()
		_cqb_dummy = null
	# the support, called the way a streak calls it
	if _cqb_said >= 2 and _cqb_sup == 0 and _cqb_t > 12.0:
		_cqb_sup = 1
		var mk := Vector3(world.cqb.centre.x, Sim.height_at(world.cqb.centre.x, world.cqb.centre.y - 60.0), world.cqb.centre.y - 60.0)
		var reds: int = world.cqb.enemies_of(0).size()
		for i in 7:
			world.cqb.streaks.bombs.append([0.1 + i * 0.1, mk + Vector3(0, 0, -20.0 + i * 12.0)])
		print("[cqb] airstrike laid on %s with %d hostiles up" % [str(mk.round()), reds])
		print("[cqb] fire mission accepted: %s" % str(world.street_fight.cqb_fire_mission(mk + Vector3(40, 0, -30))))
	if _cqb_sup == 1 and _cqb_t > 14.0:
		_cqb_sup = 2
		print("[cqb] after the stick: player kills %d, streak %d, banked %s" % [world.cqb.kills,
			world.cqb.streaks.streak, str(world.cqb.streaks.bank)])
		print("[cqb] gunship called: %s" % str(world.street_fight.cqb_gunship(Vector3(world.cqb.centre.x, world.walker.global_position.y, world.cqb.centre.y))))
	if _cqb_sup == 2 and _cqb_t > 24.0:
		_cqb_sup = 3
		if is_instance_valid(world.called_gunship):
			var g3 := world.called_gunship
			print("[cqb] gunship after 10 s: %.0f m up, %.0f m/s, %.0f m from the town, gunning=%s, pod %s on %s, walker hidden=%s" % [
				g3.global_position.y - world.walker.global_position.y, g3.linear_velocity.length(),
				Vector2(g3.global_position.x - world.cqb.centre.x, g3.global_position.z - world.cqb.centre.y).length(),
				str(world.gunning), str(world.pod.active), str(world.pod.aim_point().round()),
				str(not world.crew.station_walker.visible if is_instance_valid(world.crew.station_walker) else false)])
			world.cqb_gun_t = 0.5
		else:
			print("[cqb] gunship is not there")
	if _cqb_sup == 3 and _cqb_t > 26.0:
		_cqb_sup = 4
		print("[cqb] gunship gone=%s, back on foot=%s, walker camera live=%s, player is the parked jet=%s" % [
			str(not is_instance_valid(world.called_gunship)), str(world.on_foot),
			str(is_instance_valid(world.walker) and world.walker.cam.current), str(world.player == world.cqb_parked)])
	if _cqb_sup >= 1 and is_instance_valid(world.cqb_tel) and world.street_fight._cqb_tel_fired and _cqb_sup < 9 \
			and _cqb_t > 30.0:
		_cqb_sup = 9
		print("[cqb] fire support %s fired from %.0f m; last burst %.0f m from the mark" % [
			world.cqb_tel.display_name(), world.cqb_tel.global_position.distance_to(world.walker.global_position),
			Sim.last_burst.distance_to(Vector3(world.cqb.centre.x + 40, Sim.last_burst.y, world.cqb.centre.y - 90))])
	if _cqb_t > 62.0:
		if world.street_fight._cqb_tel_fired:
			print("[cqb] the last thing to go off was %.0f m from the fire mission's mark" % 
				Vector2(Sim.last_burst.x - (world.cqb.centre.x + 40.0), Sim.last_burst.z - (world.cqb.centre.y - 90.0)).length())
		if not world.street_fight._cqb_tel_fired:
			print("[cqb] fire support never fired: lay error %.2f, timer %.1f" % [
				world.cqb_tel.lay_error() if is_instance_valid(world.cqb_tel) else -1.0, world.cqb_tel_t])
		var st2: Dictionary = world.mode.hud_state()
		var total: int = int((st2["kills"] as Dictionary).get(0, 0)) \
			+ int((st2["kills"] as Dictionary).get(1, 0))
		print("[cqb] RESULT: %s — %d kills in a minute" % [
			"the fight happens" if total > 0 else "FAILED, nobody found anybody", total])
		world.get_tree().quit()
#endregion


#region --cqbfix=
## The things a street fight kept getting wrong, each checked against the real
## code paths: a grenade through a window and a doorway, a vault through a
## window, a walk along inside a scaffold, a block's footprint against its
## walls, the cruise missile's fins and steering, and what is coming in drawn
## on the map. --cqbfix=DIR, with --preset=cqb; pictures go in DIR.
var _cqb_fix := ""

func tick_cqb_fix() -> void:
	if _cqb_fix != "" and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		var cf := _cqb_fix
		_cqb_fix = ""
		_run_cqb_fix(cf)

func _run_cqb_fix(dir: String) -> void:
	world.shot_frames = 1 << 30
	for i in 60:
		await world.get_tree().physics_frame
	var bad := PackedStringArray()
	var w: Walker = world.walker
	# A wall with a window and a doorway in it, built the way a ground floor
	# is, out in the open well clear of the town.
	# somewhere level, with nothing standing on it
	var wall0 := Vector3.INF
	for k in 400:
		var a: float = float(k) * 2.399
		var rr: float = 30.0 + float(k) * 1.5
		var c := Vector3(w.global_position.x + cos(a) * rr, 0.0, w.global_position.z + sin(a) * rr)
		var h0: float = Sim.height_at(c.x, c.z)
		var flat := true
		for dx in [0.0, 6.0, 12.0]:
			for dz in [-5.0, 0.0, 5.0]:
				if absf(Sim.height_at(c.x + dx, c.z + dz) - h0) > 0.12 \
						or Obstacles.hit(Vector3(c.x + dx, h0 + 1.0, c.z + dz), 1.5) >= 0:
					flat = false
		if flat:
			wall0 = Vector3(c.x, h0, c.z)
			break
	if wall0 == Vector3.INF:
		print("[cqbfix] RESULT: FAILED — nowhere level to build the test wall")
		world.get_tree().quit()
		return
	var made: Array = []
	# along x, 0.4 thick; window from 2 to 3.6 along it, door from 6 to 8.4
	for seg in [[0.0, 2.0, 0.0, 2.25], [2.0, 3.6, 0.0, 1.0], [3.6, 6.0, 0.0, 2.25],
			[8.4, 12.0, 0.0, 2.25], [0.0, 12.0, 2.25, 3.4]]:
		var mid := wall0 + Vector3((float(seg[0]) + float(seg[1])) * 0.5, float(seg[2]), 0.0)
		made.append(Obstacles.add_box(mid, (float(seg[1]) - float(seg[0])) * 0.5,
			float(seg[3]) - float(seg[2]), 0.2, 0.0))
	# grenades: thrown at the window from four metres out, and at the doorway
	# thrown from four metres out so as to cross the wall at the middle of
	# the opening: 1.6 m up for the window, 1.1 for the door
	for case in [["window", 2.8, 1.6], ["doorway", 7.2, 1.1]]:
		var f := Firearm.Frag.new()
		f.fuse = 3.0
		f.thrower = w
		world.add_child(f)
		f.global_position = wall0 + Vector3(float(case[1]), float(case[2]) + 0.6, 4.0)
		# 0.4 s to the wall at 10 m/s, falling 7 * 0.16 = 1.12 against a 1.6 m/s rise
		f.vel = Vector3(0.0, 1.3, -10.0)
		var went := false
		for i in 150:
			await world.get_tree().physics_frame
			if not is_instance_valid(f):
				break
			if f.global_position.z < wall0.z - 0.5:
				went = true
		var end_at: Vector3 = f.global_position - wall0 if is_instance_valid(f) else Vector3.INF
		if not went and is_instance_valid(f):
			var gp: Vector3 = f.global_position
			var tt: float = Obstacles.segment(gp + Vector3(0, 0, 0.6), gp - Vector3(0, 0, 0.6))
			var sid: int = Obstacles.seg_id
			if sid >= 0:
				print("[cqbfix]   in the way at %.2f: box %d centre %s half %s base %.2f top %.2f (ours: %s); vel %s" % [
					tt, sid, str((Obstacles.centre_of(sid) - wall0).snapped(Vector3.ONE * 0.01)),
					str(Obstacles.half_of(sid)), Obstacles.centre_of(sid).y - wall0.y,
					Obstacles.top_of(sid) - wall0.y, str(made.has(sid)), str(f.vel.snapped(Vector3.ONE * 0.01))])
			else:
				print("[cqbfix]   nothing in the way along z; vel %s" % str(f.vel.snapped(Vector3.ONE * 0.01)))
		if is_instance_valid(f):
			f.queue_free()
		print("[cqbfix] grenade through the %s: %s (ended at %s from the wall)" % [case[0],
			"went through" if went else "BOUNCED", str(end_at.snapped(Vector3.ONE * 0.01))])
		if not went:
			bad.append("grenade bounced off the %s" % case[0])
	# and one at the solid wall beside the window still comes back
	var f2 := Firearm.Frag.new()
	f2.fuse = 3.0
	world.add_child(f2)
	f2.global_position = wall0 + Vector3(1.0, 1.5, 3.0)
	f2.vel = Vector3(0.0, 0.5, -9.0)
	var through_wall := false
	for i in 150:
		await world.get_tree().physics_frame
		if is_instance_valid(f2) and f2.global_position.z < wall0.z - 0.5:
			through_wall = true
	if is_instance_valid(f2):
		f2.queue_free()
	print("[cqbfix] grenade at the wall: %s" % ("WENT THROUGH" if through_wall else "bounced"))
	if through_wall:
		bad.append("grenade went through a solid wall")
	# a vault through the window, from in front of it
	var keep: Vector3 = w.global_position
	w.global_position = wall0 + Vector3(2.8, 0.0, 0.2 + 0.42 + 0.15)
	w.global_position.y = Sim.height_at(w.global_position.x, w.global_position.z)
	var vaulted: bool = w._begin_traverse(Vector3(0, 0, -1), false)
	print("[cqbfix] at the window: %s" % (w._trav if vaulted else "nothing"))
	if not vaulted or w._trav != "vault":
		bad.append("could not vault through the window (%s)" % (w._trav if vaulted else "nothing"))
	w._trav = ""
	w.global_position = keep
	for id in made:
		Obstacles.remove(int(id))
	# walking along inside a scaffold
	var walked := 0
	var tried := 0
	for t in TownSet.live:
		if not is_instance_valid(t):
			continue
		for sc in (t as TownSet).scaffolds:
			var mid: Vector3 = sc[0]
			var axis: Vector3 = sc[1]
			var run: float = sc[2]
			var ok := true
			var u := -run * 0.5 + 0.6
			while u < run * 0.5 - 0.6:
				var p: Vector3 = mid + axis * u
				p.y = Sim.height_at(p.x, p.z)
				if Obstacles.blocks(p, Walker.BODY_R) >= 0:
					ok = false
				u += 0.3
			tried += 1
			if ok:
				walked += 1
	print("[cqbfix] scaffolds walked along inside: %d of %d" % [walked, tried])
	if tried > 0 and walked < tried:
		bad.append("%d of %d scaffolds cannot be walked through" % [tried - walked, tried])
	# town blocks: does the obstacle stop at the wall?
	var worst := 0.0
	var n_blocks := 0
	for b in world.scenery._breakable:
		if not (b as Dictionary).has("town_kind"):
			continue
		for xf in (b["xforms"] as Array):
			var x: Transform3D = xf
			if Vector2(x.origin.x - world.cqb.centre.x, x.origin.z - world.cqb.centre.y).length() > 200.0:
				continue
			var id: int = Obstacles.hit(x.origin + Vector3(0, 6.0, 0), 0.0)
			if id < 0:
				continue
			var half: Vector2 = Obstacles.half_of(id)
			worst = maxf(worst, absf(half.x - x.basis.x.length() * 0.5))
			worst = maxf(worst, absf(half.y - x.basis.z.length() * 0.5))
			n_blocks += 1
	print("[cqbfix] %d town blocks: the obstacle stands at most %.2f m off the wall" % [n_blocks, worst])
	if worst > 0.05:
		bad.append("block obstacles stand %.2f m off their walls" % worst)
	# the pictures want the street, not the deploy screen that is up over it
	if is_instance_valid(world.deploy_ui):
		world.deploy_ui.visible = false
	if is_instance_valid(world.hud):
		world.hud.show_help = false
	# the cruise missile, flown: handed over, then aimed hard right and down
	world.cqb.streaks.pick_at = w.global_position + Vector3(260.0, 0.0, -180.0)
	world.cqb.streaks.pick_at.y = Sim.height_at(world.cqb.streaks.pick_at.x, world.cqb.streaks.pick_at.z)
	world.cqb.streaks.call_in("cruise_at")
	var cm: CruiseMissile = world.cqb.streaks.cruise
	Engine.time_scale = 3.0
	while is_instance_valid(cm) and not cm._held:
		await world.get_tree().physics_frame
	Engine.time_scale = 1.0
	if not is_instance_valid(cm):
		bad.append("the cruise missile never reached the handover")
	else:
		for i in 20:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png("%s/cruise_level.png" % dir)
		var most_fin := 0.0
		var most_bank := 0.0
		for i in 50:
			cm._turn_aim(-0.012, -0.006)
			await world.get_tree().physics_frame
			if not is_instance_valid(cm):
				break
			for d in cm._defl:
				most_fin = maxf(most_fin, absf(float(d)))
			most_bank = maxf(most_bank, absf(cm._bank))
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png("%s/cruise_turning.png" % dir)
		print("[cqbfix] cruise missile aimed right and down: fins up to %.0f deg, bank up to %.0f deg, aim %.0f deg off the flight" % [
			rad_to_deg(most_fin), rad_to_deg(most_bank),
			rad_to_deg(cm.vel.angle_to(cm._aim)) if is_instance_valid(cm) else -1.0])
		if most_fin < deg_to_rad(8.0):
			bad.append("the fins hardly moved")
	# what is coming in, on the map: mortars, a gun run and a nuke
	world.cqb.streaks.pick_at = w.global_position + Vector3(120.0, 0.0, -60.0)
	world.cqb.streaks.call_in("mortar_at")
	world.cqb.streaks.strafe_from = w.global_position + Vector3(-80.0, 0.0, 90.0)
	world.cqb.streaks.pick_at = w.global_position + Vector3(-80.0, 0.0, 260.0)
	world.cqb.streaks.call_in("strafe_at")
	world.cqb.streaks.pick_at = w.global_position + Vector3(400.0, 0.0, 300.0)
	world.cqb.streaks.call_in("tacnuke_at")
	var inbound: Array = world.cqb.streaks.inbound()
	print("[cqbfix] inbound for the map: %s" % ", ".join(PackedStringArray(
		inbound.map(func(d: Dictionary) -> String: return "%s %s" % [d["kind"], d.get("label", "")]))))
	if inbound.size() < 3:
		bad.append("the map was given only %d inbound" % inbound.size())
	world.map.toggle()
	world.map.globe = false
	world.map.zoom = 2200.0
	world.map.centre = Vector2(w.global_position.x + 120.0, w.global_position.z + 60.0)
	world.map.follow = false
	for i in 10:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("%s/map_inbound.png" % dir)
	# the nuke is not something to leave going off in the test
	world.cqb.streaks.nukes.clear()
	print("[cqbfix] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED — " + "; ".join(bad)))
	world.get_tree().quit()
#endregion


#region --aimtest
var _aim_test := false
var _aim_t := 0.0

func tick_aim(delta: float) -> void:
	if _aim_test and is_instance_valid(world.walker) and is_instance_valid(world.walker.body):
		_aim_t += delta
		if _aim_t > 2.0:
			_aim_test = false
			var body: Pilot = world.walker.body
			var worst := Vector2.ZERO
			var worst_at := 0.0
			for i in 37:
				var pitch := deg_to_rad(lerpf(-80.0, 80.0, float(i) / 36.0))
				body.pose_aim(pitch)
				body.force_update_transform()
				for c in body.find_children("*", "Node3D", true, false):
					(c as Node3D).force_update_transform()
				var e: Vector2 = body.grip_error()
				if e.x + e.y > worst.x + worst.y:
					worst = e
					worst_at = rad_to_deg(pitch)
			print("[aim] worst hand-to-grip error: right %.3f m, left %.3f m at %.0f deg pitch" % [
				worst.x, worst.y, worst_at])
			var zr := -9.0
			var zl := -9.0
			var yr := 9.0
			var yl := 9.0
			for i2 in 37:
				var pit := deg_to_rad(lerpf(-80.0, 80.0, float(i2) / 36.0))
				body.pose_aim(pit)
				body.force_update_transform()
				for c in body.find_children("*", "Node3D", true, false):
					(c as Node3D).force_update_transform()
				var eb: Array = body.elbow_pos()
				zr = maxf(zr, (eb[0] as Vector3).z)
				zl = maxf(zl, (eb[1] as Vector3).z)
				yr = minf(yr, (eb[0] as Vector3).y)
				yl = minf(yl, (eb[1] as Vector3).y)
			# torso half-depth is 0.12, so anything past that is outside the body
			print("[aim] elbow worst aft: right %+.2f, left %+.2f (torso back at +0.12); lowest y right %.2f left %.2f" % [
				zr, zl, yr, yl])
			world.get_tree().quit()
#endregion


#region --sighttest
## Every weapon brought up to the eye: how far its sight line is off the line
## the rounds are sent down. --preset=cqb:f16 --sighttest
var _sight_test := false

func tick_sight() -> void:
	if _sight_test and is_instance_valid(world.walker) and is_instance_valid(world.walker.body):
		_sight_test = false
		_run_sight_test()

func _run_sight_test() -> void:
	for i in 90:
		await world.get_tree().physics_frame
	var w: Walker = world.walker
	w.hold_ads = true
	var worst := 0.0
	var pitch_worst := 0.0
	var near_worst := INF
	for i in Firearm.KIT.size():
		var g: Dictionary = Firearm.KIT[i]
		w._take_up(i, false)
		for f in 70:
			await world.get_tree().physics_frame
		var res: Array = []
		for phase in ["still", "recoil"]:
			if phase == "recoil":
				w.body.kick(1.0)
				var k: float = float(g["kick"])
				w.pitch += k * 0.45
				w._recoil = minf(w._recoil + k * 0.9, 0.12)
				await world.get_tree().physics_frame
				await world.get_tree().physics_frame
			await world.get_tree().process_frame
			var cam_xf: Transform3D = w.cam.global_transform
			var gx: Transform3D = w.body.gun_node.global_transform
			var look: Vector3 = -cam_xf.basis.z
			var bore: Vector3 = -gx.basis.z
			var ang: float = rad_to_deg(look.angle_to(bore)) * 60.0   # minutes of angle
			# the sight line: `sight` above the bore, along it
			var sp: Vector3 = gx * Vector3(0, float(g["sight"]), -0.05)
			var rel: Vector3 = cam_xf.affine_inverse() * sp
			res.append("%s %.0f MOA, sight %+.1f/%+.1f cm off the eye" % [phase, ang,
				rel.x * 100.0, rel.y * 100.0])
			if phase == "still":
				worst = maxf(worst, ang)
		print("[sight] %-10s %s" % [String(g["id"]), "; ".join(PackedStringArray(res))])
		w._recoil = 0.0
		# and with the view up and down: the arms are only so long, and the
		# weapon must stay on the line of sight and clear of the lens
		var pres: Array = []
		for pv in [0.9, 0.5, -0.5, -0.9]:
			w.pitch = pv
			for f in 50:
				await world.get_tree().physics_frame
			await world.get_tree().process_frame
			var cx: Transform3D = w.cam.global_transform
			var gx2: Transform3D = w.body.gun_node.global_transform
			var sp2: Vector3 = cx.affine_inverse() * (gx2 * Vector3(0, float(g["sight"]), -0.05))
			var near := INF
			for mi in w.body.gun_node.find_children("*", "MeshInstance3D", true, false):
				var m := mi as MeshInstance3D
				var ab: AABB = m.get_aabb()
				for c in 8:
					var q: Vector3 = cx.affine_inverse() * (m.global_transform * ab.get_endpoint(c))
					near = minf(near, -q.z)
			pres.append("%+.1f: off %+.1f/%+.1f cm, nearest %.0f cm" % [pv, sp2.x * 100.0, sp2.y * 100.0, near * 100.0])
			pitch_worst = maxf(pitch_worst, Vector2(sp2.x, sp2.y).length())
			near_worst = minf(near_worst, near)
		w.pitch = 0.0
		print("[sight]            pitched %s" % "; ".join(PackedStringArray(pres)))
	print("[sight] worst at rest: %.0f MOA; worst off the eye pitched %.1f cm; nearest to the lens %.0f cm" % [worst, pitch_worst * 100.0, near_worst * 100.0])
	world.get_tree().quit()
#endregion
