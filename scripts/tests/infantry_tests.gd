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
	elif a == "--sentrytest":
		_sentry_test = true
	elif a == "--holdfire":
		_holdfire = true
	elif a == "--zerotest":
		_zero_test = true
	elif a == "--droptest":
		_drop_test = true
	elif a.begins_with("--dropshot="):
		_drop_shot = a.substr(11)
	elif a == "--streaktest":
		_streak_test = true
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
	elif a == "--groundprobe":
		_ground_probe = true
	elif a == "--rangetest":
		_range_test = true
	elif a == "--rangelisten":
		_range_listen = true
	elif a == "--rangeafter":
		# come to the range from a busy mission, the way a player does
		_range_after = true
	elif a.begins_with("--rangecam="):
		_range_cam = a.substr(11)
	elif a == "--bridgeprobe":
		_bridge_probe = true
	elif a == "--bridgedrive":
		_bridge_drive = true
	elif a == "--rampground":
		_ramp_ground = true
	elif a == "--junctions":
		_junctions = true
	elif a.begins_with("--junctionshots="):
		_junctions = true
		_junction_shots = a.substr(16)
	elif a.begins_with("--rampshots="):
		_ramp_ground = true
		_ramp_shots = a.substr(12)
	elif a == "--spanbodies":
		_span_bodies = true
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

#region --sentrytest
## A sentry set down facing the other side's start, left to it for forty
## seconds: what it fired, what it hit, and whether they fought back.
## --preset=cqb:foot --sentrytest
var _sentry_test := false

func tick_sentry() -> void:
	if _sentry_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_sentry_test = false
		_run_sentry_test()

func _run_sentry_test() -> void:
	for i in 20:
		await world.get_tree().physics_frame
	world.street_fight._on_cqb_deploy("foot")
	if is_instance_valid(world.deploy_ui):
		world.deploy_ui.visible = false
	for i in 10:
		await world.get_tree().physics_frame
	var cq: CqbMatch = world.cqb
	var w: Walker = world.walker
	var them: Vector3 = cq.spawn_point(1, 0)
	var to: Vector3 = them - w.global_position
	w.yaw = atan2(-to.x, -to.z)
	for i in 5:
		await world.get_tree().physics_frame
	var kills0: int = cq.kills
	cq.bank["sentry"] = 1
	var ok: bool = cq._call("sentry")
	var st: SentryTurret = null
	for n in world.get_tree().get_nodes_in_group("sentries"):
		st = n
	print("[sentry] set down: %s, %s" % [ok, "there" if is_instance_valid(st) else "missing"])
	var bad: Array = []
	if not ok or not is_instance_valid(st):
		print("[sentry] RESULT: FAILED -- it did not go down")
		world.get_tree().quit()
		return
	# he steps back out of its way and keeps his head down
	w.sheltered = true
	# and one of theirs walks into the open in front of it, wherever along
	# its arc there is a clear line to stand in
	var fw := Vector3(-sin(st.facing), 0.0, -cos(st.facing))
	var spot := Vector3.INF
	for k in 13:
		var a: float = (float(k) - 6.0) * 0.2
		for d in [30.0, 22.0, 15.0]:
			var q: Vector3 = st.global_position + fw.rotated(Vector3.UP, a) * float(d)
			q.y = Sim.height_at(q.x, q.z)
			if Obstacles.blocks(q + Vector3(0, 0.5, 0), 0.5) < 0 \
					and Firearm.can_see(st.global_position + Vector3(0, 1.0, 0), q + Vector3(0, 1.2, 0)):
				spot = q
				break
		if spot != Vector3.INF:
			break
	for sd in cq.soldiers:
		if is_instance_valid(sd) and (sd as Soldier).team == 1 and (sd as Soldier).alive \
				and spot != Vector3.INF:
			(sd as Node3D).global_position = spot
			print("[sentry] one of theirs put %.0f m out in its arc" % spot.distance_to(st.global_position))
			break
	var hp0: float = st.health
	var seen := 0
	for i in Engine.physics_ticks_per_second * 40:
		await world.get_tree().physics_frame
		if not is_instance_valid(st) or not st.alive:
			break
		if is_instance_valid(st._target):
			seen += 1
	var fired: int = SentryTurret.BELT - (st.rounds if is_instance_valid(st) else 0)
	print("[sentry] after 40 s: %d rounds fired, on a target %.1f s of it, %d kills credited to him, it took %.0f damage and is %s" % [
		fired, float(seen) / Engine.physics_ticks_per_second, cq.kills - kills0,
		hp0 - (st.health if is_instance_valid(st) else 0.0),
		"standing" if is_instance_valid(st) and st.alive else "down"])
	if fired <= 0:
		bad.append("it never fired")
	print("[sentry] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
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
	world._spawn_walker(hold.global_position)
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

#region --droptest
## The support streaks: a smoke screen that blinds a line of sight across it,
## a supply crate that comes down and refills him, a vest crate whose armour
## takes half a hit, and a counter-UAV that jams the other side and, turned on
## his own, keeps his air streaks on the ground. --preset=cqb:foot --droptest
var _drop_test := false
## Where to save a picture of the smoke, if anywhere: --dropshot=path.png
var _drop_shot := ""

func tick_drop() -> void:
	if _drop_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_drop_test = false
		_run_drop_test()

## Every label the map has been given while the test ran.
var _drop_seen: Dictionary = {}

func _drop_watch() -> void:
	while _drop_seen.get("_on", false):
		if is_instance_valid(world.cqb):
			for it in world.cqb.inbound():
				var k: String = String((it as Dictionary).get("kind", "")) + ":" \
					+ String((it as Dictionary).get("label", "")).get_slice("  ", 0)
				_drop_seen[k] = true
		await world.get_tree().create_timer(0.25).timeout

func _run_drop_test() -> void:
	_drop_seen = {"_on": true}
	_drop_watch()
	for i in 20:
		await world.get_tree().physics_frame
	var bad: Array = []
	# off the deploy screen and into the street
	world.street_fight._on_cqb_deploy("foot")
	if is_instance_valid(world.deploy_ui):
		world.deploy_ui.visible = false
	for i in 10:
		await world.get_tree().physics_frame
	var cq: CqbMatch = world.cqb
	var w: Walker = world.walker
	# a picture of the street first: the nearest building with a ground floor
	if _drop_shot != "":
		var best_c := Vector3.INF
		for k in world.street_fight._town_sets:
			var ts: TownSet = world.street_fight._town_sets[k]
			if not is_instance_valid(ts):
				continue
			for hv in ts._hollowed:
				var hc: Vector3 = hv[3]
				if best_c == Vector3.INF or hc.distance_to(w.global_position) < best_c.distance_to(w.global_position):
					best_c = hc
		if best_c != Vector3.INF:
			var to_b: Vector3 = best_c - w.global_position
			w.yaw = atan2(-to_b.x, -to_b.z)
			w.pitch = 0.05
			if is_instance_valid(world.hud):
				world.hud.show_help = false
			for i in Engine.physics_ticks_per_second:
				await world.get_tree().physics_frame
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png(_drop_shot.replace(".png", "_street.png"))
			print("[drop] picture of the street, %.0f m to a building with a ground floor" % to_b.length())
	var fwd := Vector3(-sin(w.yaw), 0.0, -cos(w.yaw))
	var here: Vector3 = w.global_position
	# smoke 25 m ahead, across the line of sight
	var mark: Vector3 = here + fwd * 25.0
	cq.bank["smoke"] = 1
	cq._picked("smoke", mark)
	var eye: Vector3 = here + Vector3(0, 1.6, 0)
	var beyond: Vector3 = here + fwd * 45.0 + Vector3(0, 1.6, 0)
	var clear_before: bool = not SmokeScreen.blocks(eye, beyond)
	# it comes by air now: the run in, the canisters down, the banks up
	for i in Engine.physics_ticks_per_second * 40:
		await world.get_tree().physics_frame
		if SmokeScreen.clouds.size() >= 6 and SmokeScreen.blocks(eye, beyond):
			break
	for i in Engine.physics_ticks_per_second * 3:
		await world.get_tree().physics_frame
	var blind: bool = SmokeScreen.blocks(eye, beyond)
	# a picture of it, when one is asked for: what the man sees of the screen
	if _drop_shot != "":
		if is_instance_valid(world.hud):
			world.hud.show_help = false
		w.hold_ads = false
		# facing the screen, from where it was called
		var to_m: Vector3 = mark - w.global_position
		w.yaw = atan2(-to_m.x, -to_m.z)
		w.pitch = 0.12
		for i in Engine.physics_ticks_per_second * 2:
			await world.get_tree().physics_frame
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png(_drop_shot)
		print("[drop] picture of the smoke saved to %s" % _drop_shot)
	print("[drop] smoke: line of sight across the mark clear before %s, blocked once it is down %s, %d banks" % [
		clear_before, blind, SmokeScreen.clouds.size()])
	if not clear_before or not blind:
		bad.append("smoke does not block")
	# supply: empty him out, drop it on his feet, walk him onto it
	w._rounds[w.kit_idx] = 1
	w.ammo = 1
	w.spare = 0
	w._spare[w.kit_idx] = 0
	w.grenades = 0
	w.health = 30.0
	cq.bank["supply"] = 1
	cq._picked("supply", here + fwd * 1.0)
	var crate: SupplyCrate = null
	for n in world.get_children():
		if n is SupplyCrate:
			crate = n
	var landed := false
	for i in Engine.physics_ticks_per_second * 40:
		await world.get_tree().physics_frame
		if is_instance_valid(crate) and crate.is_in_group("pickups"):
			landed = true
			break
	if landed:
		crate.resupply(w)
	print("[drop] supply: landed %s; ammo %d+%d, grenades %d, health %.0f" % [
		landed, w.ammo, w.spare, w.grenades, w.health])
	if not landed or w.spare <= 0 or w.grenades < 2 or w.health < 99.0:
		bad.append("supply did not refill")
	# vest
	cq.bank["vest"] = 1
	cq._picked("vest", here + fwd * 1.0)
	var vest: SupplyCrate = null
	for n in world.get_children():
		if n is SupplyCrate and (n as SupplyCrate).kind == "vest":
			vest = n
	for i in Engine.physics_ticks_per_second * 40:
		await world.get_tree().physics_frame
		if is_instance_valid(vest) and vest.is_in_group("pickups"):
			break
	if is_instance_valid(vest):
		vest.resupply(w)
	var h0: float = w.health
	w.take_hit(40.0, null)
	print("[drop] vest: armour %.0f after a 40 hit, health %.0f -> %.0f" % [w.armour, h0, w.health])
	if absf((h0 - w.health) - 20.0) > 0.5:
		bad.append("vest did not take half")
	# counter-UAV ours jams them; theirs on us keeps an airstrike down
	cq.bank["cuav"] = 1
	var ok: bool = cq._call("cuav")
	print("[drop] counter-UAV: called %s, their side jammed for %.0f s" % [ok, float(CqbMatch.jammed[1])])
	if not ok or float(CqbMatch.jammed[1]) <= 0.0:
		bad.append("counter-UAV did not jam")
	CqbMatch.jammed[0] = 10.0
	var was_pick: Array = CqbMatch.streak_pick.duplicate()
	CqbMatch.streak_pick = ["uav", "smoke", "strike", "supply"]
	cq.bank["uav"] = 1
	Input.action_press(&"weapon_4")
	await world.get_tree().physics_frame
	await world.get_tree().physics_frame
	Input.action_release(&"weapon_4")
	print("[drop] jammed ourselves: UAV still banked %d (should be 1), drone up %s" % [
		int(cq.bank["uav"]), is_instance_valid(cq._uav)])
	if int(cq.bank["uav"]) != 1:
		bad.append("an air streak went up while jammed")
	CqbMatch.jammed[0] = 0.0
	CqbMatch.streak_pick = was_pick
	# EMP: one of their sentries knocked out, their sights and air down
	var foe_st := SentryTurret.new()
	foe_st.team = 1
	foe_st.arena = cq
	world.add_child(foe_st)
	foe_st.global_position = here + fwd * 40.0
	await world.get_tree().physics_frame
	cq.bank["emp"] = 1
	var emp_ok: bool = cq._call("emp")
	await world.get_tree().physics_frame
	if _drop_shot != "":
		await world.get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png(_drop_shot.replace(".png", "_emp.png"))
	print("[drop] EMP: called %s; their sentry %s; their sights dark for %.0f s, air jammed %.0f s" % [
		emp_ok, "knocked out" if not foe_st.alive else "STILL UP", float(CqbMatch.emp_t[1]),
		float(CqbMatch.jammed[1])])
	if not emp_ok or foe_st.alive or float(CqbMatch.emp_t[1]) <= 0.0:
		bad.append("the EMP did not take their systems down")
	# white phosphorus on one of theirs: he burns
	var victim: Soldier = null
	for sd in cq.soldiers:
		if is_instance_valid(sd) and (sd as Soldier).team == 1 and (sd as Soldier).alive:
			victim = sd
			break
	if victim != null:
		var burn_at: Vector3 = here + fwd * 50.0
		burn_at.y = Sim.height_at(burn_at.x, burn_at.z)
		victim.global_position = burn_at
		victim.set_physics_process(false)
		var hp_v: float = victim.health
		cq.bank["wp"] = 1
		cq._wp_from = burn_at - Vector3(20, 0, 0)
		cq._picked("wp", burn_at + Vector3(20, 0, 0))
		victim.set_process(false)
		for i in Engine.physics_ticks_per_second * 35:
			if not is_instance_valid(victim) or not victim.alive:
				break
			await world.get_tree().physics_frame
			if is_instance_valid(victim):
				victim.global_position = burn_at       # he stays in it
		var gone: bool = not is_instance_valid(victim) or not victim.alive
		print("[drop] white phosphorus: a man of theirs in the strip, health %.0f -> %s" % [
			hp_v, "dead" if gone else "%.0f" % victim.health])
		if not gone and victim.health >= hp_v:
			bad.append("the white phosphorus did not burn him")
	# switchblades on two of theirs standing in the open -- once the fire is
	# out, or it is the fire that gets them
	for i in Engine.physics_ticks_per_second * 40:
		if world.find_children("*", "NapalmStrike", true, false).is_empty():
			break
		await world.get_tree().physics_frame
	var marks: Array = []
	for sd in cq.soldiers:
		if marks.size() >= 2:
			break
		if not is_instance_valid(sd) or (sd as Soldier).team != 1 or not (sd as Soldier).alive:
			continue
		# somewhere open: nothing overhead and a clear line to the sky
		for k in 24:
			var q: Vector3 = here + Vector3(cos(k * 0.9) * (40.0 + k * 3.0), 0.0, sin(k * 0.9) * (40.0 + k * 3.0))
			q.y = Sim.height_at(q.x, q.z)
			if Obstacles.blocks(q + Vector3(0, 0.5, 0), 0.5) < 0 \
					and Firearm.can_see(q + Vector3(0, 1.2, 0), q + Vector3(0, 80, 0)):
				marks.append([sd, q])
				sd.set_process(false)
				sd.set_physics_process(false)
				break
	cq.bank["swarm"] = 1
	CqbMatch.jammed[0] = 0.0
	var sw_ok: bool = cq._call("swarm")
	var down := 0
	var took := 0.0
	# the transport has to get here first
	for i in Engine.physics_ticks_per_second * 60:
		await world.get_tree().physics_frame
		took += 1.0 / Engine.physics_ticks_per_second
		down = 0
		for m in marks:
			if is_instance_valid(m[0]) and (m[0] as Soldier).alive:
				(m[0] as Node3D).global_position = m[1]
			else:
				down += 1
		if down == marks.size():
			break
	print("[drop] switchblades: launched %s; %d of %d men in the open down after %.0f s" % [
		sw_ok, down, marks.size(), took])
	if marks.size() > 0 and down == 0:
		bad.append("the switchblades got nobody")
	# the attack helicopter, on two more of theirs in the open -- with the
	# rest of the swarm out of the sky first, or it is the drones that get them
	for n in world.get_tree().get_nodes_in_group("drones"):
		if n is Switchblade:
			(n as Node).queue_free()
	await world.get_tree().physics_frame
	var marks2: Array = []
	for sd in cq.soldiers:
		if marks2.size() >= 2:
			break
		if not is_instance_valid(sd) or (sd as Soldier).team != 1 or not (sd as Soldier).alive:
			continue
		for k in 24:
			var q: Vector3 = here + Vector3(cos(k * 1.3) * (35.0 + k * 3.0), 0.0, sin(k * 1.3) * (35.0 + k * 3.0))
			q.y = Sim.height_at(q.x, q.z)
			if Obstacles.blocks(q + Vector3(0, 0.5, 0), 0.5) < 0 \
					and Firearm.can_see(q + Vector3(0, 1.2, 0), q + Vector3(0, 150, 0)):
				marks2.append([sd, q])
				sd.set_process(false)
				sd.set_physics_process(false)
				break
	cq.bank["heli"] = 1
	var h_ok: bool = cq._call("heli")
	var got := 0
	var took2 := 0.0
	for i in Engine.physics_ticks_per_second * 45:
		await world.get_tree().physics_frame
		took2 += 1.0 / Engine.physics_ticks_per_second
		got = 0
		for m in marks2:
			if is_instance_valid(m[0]) and (m[0] as Soldier).alive:
				(m[0] as Node3D).global_position = m[1]
			else:
				got += 1
		if got == marks2.size():
			break
	print("[drop] attack helicopter: called %s; %d of %d men in the open down after %.0f s" % [
		h_ok, got, marks2.size(), took2])
	if marks2.size() > 0 and got == 0:
		bad.append("the gunship got nobody")
	# armour, dropped on a clear spot near him
	var tanks0: int = world.get_tree().get_nodes_in_group("vehicles").size()
	cq.bank["armour"] = 1
	cq._picked("armour", here + fwd * 30.0)
	var landed_t: Tank = null
	for i in Engine.physics_ticks_per_second * 30:
		await world.get_tree().physics_frame
		for v in world.get_tree().get_nodes_in_group("vehicles"):
			var tv: Tank = v
			if tv.team == 0 and not tv.freeze and tv.global_position.y - Sim.height_at(tv.global_position.x, tv.global_position.z) < 3.0 \
					and world.find_children("*", "VehicleDrop", true, false).is_empty():
				landed_t = tv
		if landed_t != null:
			break
	print("[drop] armour: %d vehicles before, %s" % [tanks0,
		("%s down %.1f m off the ground" % [landed_t.display_name(),
			landed_t.global_position.y - Sim.height_at(landed_t.global_position.x, landed_t.global_position.z)])
		if landed_t != null else "nothing landed"])
	if landed_t == null:
		bad.append("the armour never came down")
	# dogs, on two of theirs held where they stand -- with the gunship sent
	# home first, or it may be the gunship that gets them
	for n in world.get_tree().get_nodes_in_group("hittable"):
		if n is AIHeli and (n as AIHeli).arena == cq:
			(n as Node).queue_free()
	await world.get_tree().physics_frame
	var marks3: Array = []
	for sd in cq.soldiers:
		if marks3.size() >= 2:
			break
		if is_instance_valid(sd) and (sd as Soldier).team == 1 and (sd as Soldier).alive:
			var q3: Vector3 = w.global_position + Vector3(25.0 + marks3.size() * 15.0, 0.0, 10.0)
			q3.y = Sim.height_at(q3.x, q3.z)
			if Obstacles.blocks(q3 + Vector3(0, 0.5, 0), 0.5) >= 0:
				continue
			sd.set_process(false)
			sd.set_physics_process(false)
			marks3.append([sd, q3])
	cq.bank["dogs"] = 1
	var dg_ok: bool = cq._call("dogs")
	var bit := 0
	var took3 := 0.0
	for i in Engine.physics_ticks_per_second * 30:
		await world.get_tree().physics_frame
		took3 += 1.0 / Engine.physics_ticks_per_second
		bit = 0
		for m in marks3:
			if is_instance_valid(m[0]) and (m[0] as Soldier).alive:
				(m[0] as Node3D).global_position = m[1]
			else:
				bit += 1
		if bit == marks3.size():
			break
	print("[drop] attack dogs: called %s; %d of %d men down after %.0f s" % [dg_ok, bit, marks3.size(), took3])
	if marks3.size() > 0 and bit == 0:
		bad.append("the dogs got nobody")
	for n in world.find_children("*", "AttackDog", true, false):
		n.queue_free()
	# juggernaut: the suit and the minigun
	cq.bank["jugg"] = 1
	w.armour = 0.0
	w.health = 100.0
	var jg_ok: bool = cq._call("jugg")
	var jh0: float = w.health
	w.take_hit(100.0, null)
	print("[drop] juggernaut: suited %s, holding the %s with %d rounds; a 100 hit took %.0f health, %.0f armour left" % [
		jg_ok, String(w.gun_spec()["name"]), w.ammo, jh0 - w.health, w.armour])
	if not jg_ok or String(w.gun_spec()["id"]) != "minigun" or absf((jh0 - w.health) - 20.0) > 0.5:
		bad.append("the juggernaut suit is not right")
	w.health = 100.0
	# the chopper gunner: on the guns, circling low, and the 30 mm on a man
	cq.bank["chopper"] = 1
	var ch_ok: bool = cq._call("chopper")
	var ch: Aircraft = world._cqb_gunship
	for i in Engine.physics_ticks_per_second * 20:
		await world.get_tree().physics_frame
	var c2 := Vector2(cq.centre.x, cq.centre.y)
	var agl := -1.0
	var rad := -1.0
	if is_instance_valid(ch):
		agl = ch.global_position.y - Sim.height_at(ch.global_position.x, ch.global_position.z)
		rad = Vector2(ch.global_position.x, ch.global_position.z).distance_to(c2)
	print("[drop] chopper gunner: called %s, gunning %s; after 20 s %.0f m up, %.0f m out from the town's middle" % [
		ch_ok, world.gunning, agl, rad])
	if not ch_ok or not world.gunning or agl < 120.0 or agl > 400.0 or rad > 900.0:
		bad.append("the chopper gunner is not on station")
	var mark_man: Soldier = null
	for sd in cq.soldiers:
		if is_instance_valid(sd) and (sd as Soldier).team == 1 and (sd as Soldier).alive:
			mark_man = sd
			break
	if is_instance_valid(ch) and mark_man != null:
		var spot: Vector3 = Vector3(cq.centre.x, 0.0, cq.centre.y)
		spot.y = Sim.height_at(spot.x, spot.z)
		mark_man.set_process(false)
		mark_man.set_physics_process(false)
		ch.set_weapon(1)
		var shots := 0
		for i in Engine.physics_ticks_per_second * 8:
			await world.get_tree().physics_frame
			if not is_instance_valid(mark_man) or not mark_man.alive:
				break
			mark_man.global_position = spot
			if ch.fire_gunship(world, Soldier.chest_of(mark_man)):
				shots += 1
		var dead: bool = not is_instance_valid(mark_man) or not mark_man.alive
		print("[drop] chopper gunner: %d %s at a man in the street, he is %s" % [
			shots, String(ch.gunship_gun().get("name", "rounds")), "dead" if dead else "still up"])
		if not dead:
			bad.append("the chopper gunner could not kill a man in the open")
	_drop_seen.erase("_on")
	var seen: Array = _drop_seen.keys()
	seen.sort()
	print("[drop] on the map along the way: %s" % ", ".join(PackedStringArray(seen)))
	print("[drop] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion

#region --streaktest
## Killstreaks as chosen: the keys, the ladder, two of them called in.
var _streak_test := false

func tick_streak() -> void:
	if _streak_test and is_instance_valid(world.cqb) and is_instance_valid(world.walker):
		_streak_test = false
		_run_streak_test()

## Four streaks picked out of six; the keys they come on; what a run of kills
## earns, ladder and all; a mortar barrage and a precision bomb laid on a
## street; and the deploy screen refusing a fifth and refusing none at all.
func _run_streak_test() -> void:
	for i in 20:
		await world.get_tree().physics_frame
	var bad: Array = []
	var was_pick: Array = CqbMatch.streak_pick.duplicate()
	CqbMatch.streak_pick = ["gunship", "strafe", "uav", "mortar"]
	var chosen: Array = CqbMatch.chosen_streaks()
	var order := PackedStringArray()
	for k in chosen:
		order.append("%d=%s" % [int(k["key"]), String(k["id"])])
	print("[streak] carried: %s" % " ".join(order))
	if " ".join(order) != "4=uav 5=mortar 6=strafe 7=gunship":
		bad.append("the keys are not cheapest first")
	# kills by him, one at a time, on the enemy side
	var earned: Array = []
	for n in 8:
		var foe: Soldier = null
		# six a side: past the sixth, wait for the next one back in
		for wait in 1200:
			for sd in world.cqb.soldiers:
				if is_instance_valid(sd) and (sd as Soldier).team == 1 and (sd as Soldier).alive:
					foe = sd
					break
			if foe != null:
				break
			await world.get_tree().physics_frame
		if foe == null:
			break
		var before: Dictionary = world.cqb.bank.duplicate()
		foe.take_hit(1000.0, world.walker)
		for id in world.cqb.bank:
			if int(world.cqb.bank[id]) > int(before.get(id, 0)):
				earned.append("%d:%s" % [world.cqb.streak, id])
		await world.get_tree().process_frame
	print("[streak] earned on the way to %d kills: %s" % [world.cqb.streak, ", ".join(PackedStringArray(earned))])
	if not earned.has("3:uav") or not earned.has("4:mortar") or not earned.has("6:strafe") \
			or not earned.has("7:gunship"):
		bad.append("not everything carried was earned at its count")
	# round the ladder from the top: kill eight is the first rung again? no --
	# the ladder is seven long here, so the eighth kill is rung one, and the
	# tenth (rung three) is the next UAV
	for e in earned:
		if String(e).ends_with("strike") or String(e).ends_with("missile"):
			bad.append("earned something not carried: %s" % e)
	# a mortar barrage and the precision bomb, on a street
	var spot := Vector3(world.cqb.centre.x + 30.0, 0.0, world.cqb.centre.y)
	spot.y = Sim.height_at(spot.x, spot.z)
	# The mortar rounds are real rounds in the air now, not timers: counted
	# where they are kept, and given their twelve second flight to land.
	var in_flight := func() -> int:
		var n_live := 0
		for r0 in world.cqb._rounds:
			if is_instance_valid(r0):
				n_live += 1
		return world.cqb._bombs.size() + n_live
	var queued_before: int = in_flight.call()
	world.cqb.bank["mortar"] = 1
	world.cqb._picked("mortar", spot)
	var queued: int = int(in_flight.call()) - queued_before
	print("[streak] mortar called: %d rounds on the way, bank now %s" % [
		queued, str(world.cqb.bank["mortar"])])
	if queued != 10 or int(world.cqb.bank["mortar"]) != 0:
		bad.append("calling it did not queue ten rounds and spend it")
	# and the map has them coming in, not only where they will land
	await world.get_tree().create_timer(3.0).timeout
	var shown_shells := 0
	var shown_gun := false
	for it in world.cqb.inbound():
		if String(it["kind"]) == "shell":
			shown_shells += 1
		elif String(it["kind"]) == "gun":
			shown_gun = true
	print("[streak] three seconds in, the map shows %d mortar rounds in the air and the battery %s" % [
		shown_shells, "too" if shown_gun else "NOT"])
	if shown_shells == 0 or not shown_gun:
		bad.append("the mortar rounds were not on the map coming in")
	var t := 3.0
	while int(in_flight.call()) > queued_before and t < 24.0:
		await world.get_tree().physics_frame
		t += 1.0 / 120.0
	print("[streak] all landed after %.1f s" % t)
	if int(in_flight.call()) > queued_before:
		bad.append("not everything landed")
	# The airstrike: a pair of jets down the line from him to the mark, on the
	# map as they come, and every bomb of the stick landing near the mark.
	var landed_s: Array = []
	var watch_s := func(nd: Node) -> void:
		if nd is CqbMatch.CarpetBomb:
			var cbm: Node3D = nd
			cbm.tree_exiting.connect(func(): landed_s.append(cbm.global_position))
	world.get_tree().node_added.connect(watch_s)
	world.cqb.bank["strike"] = 1
	var sk := Vector3(world.cqb.centre.x - 20.0, 0.0, world.cqb.centre.y + 10.0)
	sk.y = Sim.height_at(sk.x, sk.z)
	world.cqb._picked("strike", sk)
	var srun: Node = null
	for n0 in world.get_children():
		if n0 is CqbMatch.CarpetRun:
			srun = n0
	# taken now: the run frees itself once it has flown out the far side
	var came_over: bool = srun != null
	var plane_on_map := false
	var t_strike := 0.0
	while is_instance_valid(srun) and t_strike < 40.0:
		await world.get_tree().physics_frame
		t_strike += 1.0 / 120.0
		if not plane_on_map:
			for it2 in world.cqb.inbound():
				if String(it2["kind"]) == "plane" and String(it2.get("label", "")) == "AIRSTRIKE":
					plane_on_map = true
	world.get_tree().node_added.disconnect(watch_s)
	var worst_s := 0.0
	for lp in landed_s:
		worst_s = maxf(worst_s, Vector2((lp as Vector3).x - sk.x, (lp as Vector3).z - sk.z).length())
	print("[streak] airstrike: %s, %s on the map, %d bombs down, the furthest %.0f m from the mark" % [
		"jets came over" if came_over else "NOTHING came over",
		"shown" if plane_on_map else "NOT shown", landed_s.size(), worst_s])
	if not came_over or not plane_on_map or landed_s.size() < 8 or worst_s > 90.0:
		bad.append("the airstrike did not come over, show on the map, and put its stick on the mark")
	# The gun run: a line drawn with two picks, two A-10s down it, on the map as
	# they come, and their rounds landing along the line.
	world.cqb.bank["strafe"] = 1
	var g0 := Vector3(world.cqb.centre.x - 90.0, 0.0, world.cqb.centre.y - 30.0)
	var g1 := Vector3(world.cqb.centre.x + 110.0, 0.0, world.cqb.centre.y + 40.0)
	world.cqb._strafe_from = g0
	var hits0: int = world.cqb.cannon_hits
	world.cqb._picked("strafe", g1)
	var grun: Node = null
	for n1 in world.get_children():
		if n1 is CqbMatch.GunRun:
			grun = n1
	var gun_came: bool = grun != null
	var gun_on_map := false
	var t_gun := 0.0
	while is_instance_valid(grun) and t_gun < 45.0:
		await world.get_tree().physics_frame
		t_gun += 1.0 / 120.0
		if not gun_on_map:
			for it3 in world.cqb.inbound():
				if String(it3.get("label", "")) == "A-10 GUN RUN":
					gun_on_map = true
	var gun_hits: int = world.cqb.cannon_hits - hits0
	print("[streak] gun run: %s, %s on the map, %d rounds landed in %.1f s" % [
		"A-10s came over" if gun_came else "NOTHING came over",
		"shown" if gun_on_map else "NOT shown", gun_hits, t_gun])
	if not gun_came or not gun_on_map or gun_hits < 30:
		bad.append("the gun run did not come over, show on the map and put its rounds down")
	# the carpet: a line drawn across the town, a B-2 down it, every bomb
	# landing on the line and spread along it
	var ca := Vector3(world.cqb.centre.x - 120.0, 0.0, world.cqb.centre.y + 40.0)
	ca.y = Sim.height_at(ca.x, ca.z)
	var cb := Vector3(world.cqb.centre.x + 120.0, 0.0, world.cqb.centre.y - 40.0)
	cb.y = Sim.height_at(cb.x, cb.z)
	world.cqb.bank["carpet"] = 1
	world.cqb._carpet_from = ca
	var landed: Array = []
	var bomblets: Array = [0]
	var watch_new := func(n: Node) -> void:
		if n is CqbMatch.CarpetBomb:
			var cbomb := n as CqbMatch.CarpetBomb
			cbomb.tree_exiting.connect(func() -> void:
				if cbomb.bomblet:
					bomblets[0] = int(bomblets[0]) + 1
				else:
					landed.append(cbomb.global_position))
	world.get_tree().node_added.connect(watch_new)
	world.cqb._picked("carpet", cb)
	var run: Node = null
	for n in world.get_children():
		if n is CqbMatch.CarpetRun:
			run = n
	if run == null:
		bad.append("calling the carpet put no B-2 in the sky")
	else:
		var want: int = run.bombs
		var waited := 0.0
		while landed.size() < want and waited < 75.0:
			await world.get_tree().physics_frame
			waited += 1.0 / 120.0
		var worst := 0.0
		var lo := INF
		var hi := -INF
		var line := Vector2(cb.x - ca.x, cb.z - ca.z)
		var ln: float = line.length()
		for p in landed:
			var rel := Vector2((p as Vector3).x - ca.x, (p as Vector3).z - ca.z)
			var along: float = rel.dot(line / ln)
			worst = maxf(worst, absf(rel.cross(line / ln)))
			lo = minf(lo, along)
			hi = maxf(hi, along)
		for i in 600:
			await world.get_tree().physics_frame
		print("[streak] carpet: %d of %d bombs and canisters down after %.1f s, the worst %.1f m off the line, spread from %.0f to %.0f m along a %.0f m line; %d bomblets out of the canisters" % [
			landed.size(), want, waited, worst, lo, hi, ln, int(bomblets[0])])
		if int(bomblets[0]) < 20:
			bad.append("the cluster canisters let out %d bomblets" % int(bomblets[0]))
		if landed.size() < want or worst > 12.0 or hi - lo < ln * 0.8:
			bad.append("the carpet did not land along the line")
	world.get_tree().node_added.disconnect(watch_new)
	# the drone: it is in the sky, it is a contact, and shooting it down takes
	# the picture away
	world.cqb.bank["uav"] = 1
	world.cqb._call("uav")
	var drones: Array = world.get_tree().get_nodes_in_group("drones")
	if drones.is_empty() or world.cqb.uav_t <= 0.0:
		bad.append("calling the UAV put no drone up")
	else:
		var dr: Node3D = drones[0]
		var up: float = dr.global_position.y - Sim.height_at(dr.global_position.x, dr.global_position.z)
		dr.call("take_hit", 500.0, null)
		print("[streak] UAV: a drone %.0f m up, in the lock list %s; shot down, the map has %.0f s left" % [
			up, str(dr.is_in_group("hittable") or not dr.call("is_alive")), world.cqb.uav_t])
		if world.cqb.uav_t > 0.0:
			bad.append("the drone was shot down and the map stayed lit")
	# the small warhead: on the far side of town from him, and what was
	# standing there is not standing afterwards
	var away_dir := Vector3(world.cqb.centre.x - world.walker.global_position.x, 0.0,
		world.cqb.centre.y - world.walker.global_position.z)
	away_dir = away_dir.normalized() if away_dir.length() > 1.0 else Vector3(0, 0, -1)
	var gz: Vector3 = world.walker.global_position + away_dir * 170.0
	gz.y = Sim.height_at(gz.x, gz.z)
	var standing := func() -> int:
		var n := 0
		for ts in world.street_fight._town_sets.values():
			for c in (ts as Node).get_children():
				if c is MeshInstance3D and not c.has_meta("flat") \
						and (c as Node3D).global_position.distance_to(gz) < CqbMatch.TAC_LETHAL:
					n += 1
		return n
	var men_near := func() -> int:
		var n := 0
		for sd in world.cqb.soldiers:
			if is_instance_valid(sd) and (sd as Node3D).global_position.distance_to(gz) < CqbMatch.TAC_LETHAL * 0.9:
				n += 1
		return n
	var props_before: int = standing.call()
	world.cqb.bank["tacnuke"] = 1
	world.cqb._picked("tacnuke", gz)
	var hp_before: float = world.walker.health
	for i in int(11.5 * 120.0):
		await world.get_tree().physics_frame
	var men_before: int = men_near.call()
	for i in 240:
		await world.get_tree().physics_frame
	print("[streak] tactical nuke %.0f m from him: %d props standing inside it before and %d after, %d men inside it at the flash and %d after; his health %.0f -> %.0f, bank %s" % [
		world.walker.global_position.distance_to(gz), props_before, int(standing.call()),
		men_before, int(men_near.call()), hp_before, world.walker.health, str(world.cqb.bank["tacnuke"])])
	if int(world.cqb.bank["tacnuke"]) != 0 or int(standing.call()) > 0 or int(men_near.call()) > 0:
		bad.append("the tactical nuke left something standing inside its radius")
	if Obstacles.segment(gz + Vector3(-60, 1.5, 0.3), gz + Vector3(60, 1.5, 0.3)) < 1.0:
		bad.append("something inside the nuke's radius still stops a round")
	# the deploy screen
	var dm := DeployMenu.new()
	world.add_child(dm)
	dm.open("none", true, "usa")
	(dm._streak_ticks["strike"] as CheckButton).button_pressed = true
	var five_refused: bool = not CqbMatch.streak_pick.has("strike") \
		and CqbMatch.streak_pick.size() == 4
	for id in ["gunship", "strafe", "mortar"]:
		(dm._streak_ticks[id] as CheckButton).button_pressed = false
	(dm._streak_ticks["uav"] as CheckButton).button_pressed = false
	var none_refused: bool = CqbMatch.streak_pick == ["uav"]
	print("[streak] deploy screen: a fifth refused %s, taking off the last refused %s" % [
		str(five_refused), str(none_refused)])
	if not five_refused or not none_refused:
		bad.append("the deploy screen let the count go outside one to four")
	dm.queue_free()
	CqbMatch.streak_pick = was_pick
	for b in bad:
		print("[streak] %s" % b)
	print("[streak] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
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
			world.cqb._bombs.append([0.1 + i * 0.1, mk + Vector3(0, 0, -20.0 + i * 12.0)])
		print("[cqb] airstrike laid on %s with %d hostiles up" % [str(mk.round()), reds])
		print("[cqb] fire mission accepted: %s" % str(world.street_fight.cqb_fire_mission(mk + Vector3(40, 0, -30))))
	if _cqb_sup == 1 and _cqb_t > 14.0:
		_cqb_sup = 2
		print("[cqb] after the stick: player kills %d, streak %d, banked %s" % [world.cqb.kills,
			world.cqb.streak, str(world.cqb.bank)])
		print("[cqb] gunship called: %s" % str(world.street_fight.cqb_gunship(Vector3(world.cqb.centre.x, world.walker.global_position.y, world.cqb.centre.y))))
	if _cqb_sup == 2 and _cqb_t > 24.0:
		_cqb_sup = 3
		if is_instance_valid(world._cqb_gunship):
			var g3 := world._cqb_gunship
			print("[cqb] gunship after 10 s: %.0f m up, %.0f m/s, %.0f m from the town, gunning=%s, pod %s on %s, walker hidden=%s" % [
				g3.global_position.y - world.walker.global_position.y, g3.linear_velocity.length(),
				Vector2(g3.global_position.x - world.cqb.centre.x, g3.global_position.z - world.cqb.centre.y).length(),
				str(world.gunning), str(world.pod.active), str(world.pod.aim_point().round()),
				str(not world._station_walker.visible if is_instance_valid(world._station_walker) else false)])
			world._cqb_gun_t = 0.5
		else:
			print("[cqb] gunship is not there")
	if _cqb_sup == 3 and _cqb_t > 26.0:
		_cqb_sup = 4
		print("[cqb] gunship gone=%s, back on foot=%s, walker camera live=%s, player is the parked jet=%s" % [
			str(not is_instance_valid(world._cqb_gunship)), str(world.on_foot),
			str(is_instance_valid(world.walker) and world.walker.cam.current), str(world.player == world._cqb_parked)])
	if _cqb_sup >= 1 and is_instance_valid(world._cqb_tel) and world.street_fight._cqb_tel_fired and _cqb_sup < 9 \
			and _cqb_t > 30.0:
		_cqb_sup = 9
		print("[cqb] fire support %s fired from %.0f m; last burst %.0f m from the mark" % [
			world._cqb_tel.display_name(), world._cqb_tel.global_position.distance_to(world.walker.global_position),
			Sim.last_burst.distance_to(Vector3(world.cqb.centre.x + 40, Sim.last_burst.y, world.cqb.centre.y - 90))])
	if _cqb_t > 62.0:
		if world.street_fight._cqb_tel_fired:
			print("[cqb] the last thing to go off was %.0f m from the fire mission's mark" % 
				Vector2(Sim.last_burst.x - (world.cqb.centre.x + 40.0), Sim.last_burst.z - (world.cqb.centre.y - 90.0)).length())
		if not world.street_fight._cqb_tel_fired:
			print("[cqb] fire support never fired: lay error %.2f, timer %.1f" % [
				world._cqb_tel.lay_error() if is_instance_valid(world._cqb_tel) else -1.0, world._cqb_tel_t])
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
	world._shot_frames = 1 << 30
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
	world.cqb._pick_at = w.global_position + Vector3(260.0, 0.0, -180.0)
	world.cqb._pick_at.y = Sim.height_at(world.cqb._pick_at.x, world.cqb._pick_at.z)
	world.cqb._call("cruise_at")
	var cm: CqbMatch.CruiseMissile = world.cqb._cruise
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
	world.cqb._pick_at = w.global_position + Vector3(120.0, 0.0, -60.0)
	world.cqb._call("mortar_at")
	world.cqb._strafe_from = w.global_position + Vector3(-80.0, 0.0, 90.0)
	world.cqb._pick_at = w.global_position + Vector3(-80.0, 0.0, 260.0)
	world.cqb._call("strafe_at")
	world.cqb._pick_at = w.global_position + Vector3(400.0, 0.0, 300.0)
	world.cqb._call("tacnuke_at")
	var inbound: Array = world.cqb.inbound()
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
	world.cqb._nukes.clear()
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


#region --groundprobe
## How far the drawn ground -- terrain chunks and road ribbons -- stands above
## the ground a man actually stands on, around where he is. --preset=cqb:f16 --groundprobe
var _ground_probe := false

func tick_ground_probe() -> void:
	if _ground_probe and is_instance_valid(world.walker):
		_ground_probe = false
		_run_ground_probe()

## The highest drawn triangle over (x, z) among `meshes`, or -INF.
func _drawn_top(meshes: Array, x: float, z: float) -> float:
	var best := -INF
	for mi in meshes:
		var m := mi as MeshInstance3D
		var ab: AABB = m.global_transform * m.get_aabb()
		if x < ab.position.x or x > ab.end.x or z < ab.position.z or z > ab.end.z:
			continue
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n: int = idx.size() if not idx.is_empty() else v.size()
			var xf: Transform3D = m.global_transform
			for t in range(0, n - 2, 3):
				var a: Vector3 = xf * v[idx[t] if not idx.is_empty() else t]
				var b: Vector3 = xf * v[idx[t + 1] if not idx.is_empty() else t + 1]
				var c: Vector3 = xf * v[idx[t + 2] if not idx.is_empty() else t + 2]
				var d := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
				if absf(d) < 1e-6:
					continue
				var l1 := ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / d
				var l2 := ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / d
				var l3 := 1.0 - l1 - l2
				if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
					continue
				best = maxf(best, a.y * l1 + b.y * l2 + c.y * l3)
	return best

func _run_ground_probe() -> void:
	for i in 240:
		await world.get_tree().physics_frame
	var w: Walker = world.walker
	var c: Vector3 = w.global_position
	var terr: Array = []
	var roads: Array = []
	for n in world.get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var nm := String(mi.name)
		if nm.begins_with("Roads") or nm.begins_with("Kerbs"):
			roads.append(mi)
		elif nm.begins_with("C") and mi.get_parent() is Terrain:
			terr.append(mi)
	print("[ground] %d terrain chunks, %d road meshes in the scene; man at %s, standing %.2f over height_at" % [
		terr.size(), roads.size(), str(c.round()), c.y - Sim.height_at(c.x, c.z)])
	var worst_t := -INF
	var worst_r := -INF
	var sum_t := 0.0
	var cnt := 0
	var over_t := 0
	var over_r := 0
	var on_road := 0
	for gx in range(-30, 31, 3):
		for gz in range(-30, 31, 3):
			var x: float = c.x + gx
			var z: float = c.z + gz
			var h: float = Sim.height_at(x, z)
			var ht: float = _drawn_top(terr, x, z)
			var hr: float = _drawn_top(roads, x, z)
			if ht > -INF:
				worst_t = maxf(worst_t, ht - h)
				sum_t += ht - h
				cnt += 1
				if ht - h > 0.15:
					over_t += 1
			if hr > -INF:
				on_road += 1
				worst_r = maxf(worst_r, hr - h)
				if hr - h > 0.15:
					over_r += 1
	print("[ground] terrain drawn over the ground: worst %+.2f m, mean %+.2f m, %d of %d points more than 15 cm up" % [
		worst_t, sum_t / maxf(cnt, 1), over_t, cnt])
	print("[ground] road drawn over the ground: worst %+.2f m, %d of %d road points more than 15 cm up" % [
		worst_r, over_r, on_road])
	# and every town's streets, not just this one
	var streets: Array = world.scenery.get("_streets") if is_instance_valid(world.scenery) else []
	var rw := -INF
	var rn := 0
	var rover := 0
	var tw := -INF
	var tover := 0
	for k in mini(streets.size(), 1500):
		var st: Array = streets[(k * 7919) % streets.size()]
		var a: Vector2 = st[0]
		var b: Vector2 = st[1]
		var q: Vector2 = a.lerp(b, randf())
		var h2: float = Sim.height_at(q.x, q.y)
		var hr2: float = _drawn_top(roads, q.x, q.y)
		if hr2 > -INF:
			rn += 1
			rw = maxf(rw, hr2 - h2)
			if hr2 - h2 > 0.15:
				rover += 1
		var ht2: float = _drawn_top(terr, q.x, q.y)
		if ht2 > -INF:
			tw = maxf(tw, ht2 - h2)
			if ht2 - h2 > 0.15:
				tover += 1
	print("[ground] across %d street points in every town: road worst %+.2f m (%d over 15 cm); terrain worst %+.2f m (%d over 15 cm)" % [
		rn, rw, rover, tw, tover])
	world.get_tree().quit()
#endregion


#region --rangetest
## Ten aimed rounds at every board on the range, and how many it counted.
## --preset=range:f16 --rangetest
var _range_test := false

func tick_range() -> void:
	if _range_test and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		_range_test = false
		_run_range_test()

func _run_range_test() -> void:
	for i in 120:
		await world.get_tree().physics_frame
	# the readout's numbers against the round's own path, for one shot
	var gd: Dictionary = Firearm.spec("fifty")
	var e0: Vector3 = world.walker.global_position + Vector3(0, 1.5, 0)
	var dd: Vector3 = (world.firing_range.targets[5].global_position + Vector3(0, 1.25, 0) - e0).normalized()
	Engine.time_scale = 0.05
	var real0 := Time.get_ticks_msec()
	Firearm.fire(world, world.walker, 0, gd, e0, dd, 0.0)
	var rr0: Dictionary = world.firing_range.rounds[world.firing_range.rounds.size() - 1]
	var ticks := 0
	while float(rr0["t"]) < 0.2:
		await world.get_tree().physics_frame
		ticks += 1
	Engine.time_scale = 1.0
	print("[range] slow motion: 0.2 s of flight took %d physics ticks and %.1f s of real time" % [
		ticks, float(Time.get_ticks_msec() - real0) * 0.001])
	var p0: Vector3 = rr0["muzzle"]
	var pn: Vector3 = rr0["pos"]
	var along0: float = (pn - p0).dot(dd)
	var side0: Vector3 = (pn - p0) - dd * along0
	print("[range] one .50 round, %.0f m out: off the line it was fired along by %.3f m (%s); fired from %s, recorded from %s; dir0 vs dd %.4f deg" % [
		along0, side0.length(), str(side0), str(e0), str(p0), rad_to_deg((rr0["dir0"] as Vector3).angle_to(dd))])
	var g: Dictionary = Firearm.spec("dmr")
	var eye: Vector3 = world.walker.global_position + Vector3(0, 1.5, 0)
	var bad := 0
	for t in world.firing_range.targets:
		var rt: FiringRange.RangeTarget = t
		var aim_at: Vector3 = rt.global_position + Vector3(0, rt.cy, 0)
		for k in 10:
			# held up for the drop, the way the walker lays a shot
			var d: Vector3 = world.walker._lay(eye, aim_at, float(g["muzzle"]), 9.81, false, Firearm.drag_of(g))
			Firearm.fire(world, world.walker, 0, g, eye, d, 0.0)
			for f in 3:
				await world.get_tree().physics_frame
		# until every round is down: physics here is 120 a second, so "sixty
		# frames" was half a second and the long rounds were still flying
		for f in 600:
			await world.get_tree().physics_frame
			var flying := false
			for rr in world.firing_range.rounds:
				if bool(rr["live"]):
					flying = true
					break
			if not flying:
				break
		if not world.firing_range.rounds.is_empty():
			var lr: Dictionary = world.firing_range.rounds[world.firing_range.rounds.size() - 1]
			var lp: Vector3 = lr["pos"]
			print("[range]     last round: %.2f s, %.0f m flown, ended %.1f m short of the board, %+.2f m vs its middle, %.0f m/s; %s" % [
				float(lr["t"]), float(lr["flown"]), eye.distance_to(aim_at) - eye.distance_to(lp),
				lp.y - aim_at.y, (lr["vel"] as Vector3).length(), String(lr["hit"])])
		var los: float = Firearm.sight_range(eye, (aim_at - eye).normalized(), eye.distance_to(aim_at) + 5.0)
		print("[range] %3d m board: %d of 10 counted (line of sight clear to %.0f of %.0f m; ground at board %+.1f m vs line)" % [
			int(rt.distance), rt.hits, los, eye.distance_to(aim_at),
			Sim.height_at(rt.global_position.x, rt.global_position.z) - rt.global_position.y])
		if rt.hits < 8:
			bad += 1
	print("[range] RESULT: %s" % ("ok" if bad == 0 else "FAILED — %d boards missed rounds" % bad))
	world.get_tree().quit()
#endregion


#region --rangelisten --rangeafter
## Forty seconds on the range doing nothing, and every round and every gunshot
## that happens anyway, with who or where. --preset=range:f16 --rangelisten
var _range_listen := false
var _range_after := false

func tick_range_listen() -> void:
	if _range_listen and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		_range_listen = false
		_run_range_listen()

func _run_range_listen() -> void:
	if _range_after:
		_range_after = false
		world._start("f16", "sandbox")
		for i in 120 * 15:
			await world.get_tree().physics_frame
		world._start("f16", "range")
		for i in 240:
			await world.get_tree().physics_frame
	var heard: Dictionary = {}
	var shots: Dictionary = {}
	var me: Walker = world.walker
	if not is_instance_valid(me):
		print("[listen] no walker")
		world.get_tree().quit()
		return
	var keep_log: Callable = Effects.round_log
	Effects.round_log = func(shot: Node3D, shooter: Node) -> void:
		var who: String = "nobody" if shooter == null or not is_instance_valid(shooter) \
			else "%s (%s)" % [shooter.name, shooter.get_class()]
		if shooter == me:
			who = "the player"
		var k: String = "%s: %s" % [who, shot.get_script().get_global_name() if shot.get_script() else shot.get_class()]
		shots[k] = int(shots.get(k, 0)) + 1
		if keep_log.is_valid():
			keep_log.call(shot, shooter)
	Sfx.listen = func(id: String, pos: Vector3) -> void:
		var d: float = 0.0 if pos == Vector3.INF else pos.distance_to(me.global_position)
		var k: String = "%s, %s" % [id, "within 100 m" if d < 100.0 else ("%d km off" % int(d / 1000.0) if d > 1000.0 else "%d m off" % int(d))]
		heard[k] = int(heard.get(k, 0)) + 1
	var playing: Dictionary = {}
	for i in 120 * 40:
		await world.get_tree().physics_frame
		# hold the trigger for two seconds in the middle, as he would
		if i == 120 * 10:
			world.weapon_cam_on = true
			Input.action_press(&"fire")
		if i == 120 * 12:
			Input.action_release(&"fire")
		if i % 30 != 0:
			continue
		# anything at all making a noise, however it was started
		for n in world.get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
			var ap := n as AudioStreamPlayer3D
			if ap.playing and ap.stream != null:
				var nm: String = ap.stream.resource_path.get_file() if ap.stream.resource_path != "" else String(ap.name)
				var k2: String = "3D %s under %s, %d m off" % [nm, ap.get_parent().name,
					int(ap.global_position.distance_to(me.global_position))]
				playing[k2] = int(playing.get(k2, 0)) + 1
		for n in world.get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
			var ap2 := n as AudioStreamPlayer
			if ap2.playing and ap2.stream != null and ap2.volume_db > -50.0:
				var k3: String = "flat %s under %s at %.0f dB" % [ap2.name, ap2.get_parent().name, ap2.volume_db]
				playing[k3] = int(playing.get(k3, 0)) + 1
	print("[listen] players found playing (sampled 4x a second):")
	for k in playing:
		print("[listen]   %4d  %s" % [int(playing[k]), k])
	Sfx.listen = Callable()
	Effects.round_log = keep_log
	print("[listen] rounds fired in 40 s:")
	for k in shots:
		print("[listen]   %4d  %s" % [int(shots[k]), k])
	print("[listen] sounds played in 40 s:")
	for k in heard:
		print("[listen]   %4d  %s" % [int(heard[k]), k])
	world.get_tree().quit()
#endregion


#region --rangecam=
## The bullet camera on the range, photographed: riding a round in slow motion,
## and the traces after. --preset=range:f16 --rangecam=DIR
var _range_cam := ""

func tick_range_cam() -> void:
	if _range_cam != "" and is_instance_valid(world.walker) and is_instance_valid(world.firing_range):
		var rc := _range_cam
		_range_cam = ""
		_run_range_cam(rc)

func _run_range_cam(arg: String) -> void:
	var parts := arg.split(",")
	var dir: String = parts[0]
	var kit: String = parts[1] if parts.size() > 1 else "fifty"
	for i in 240:
		await world.get_tree().physics_frame
	world.weapon_cam_on = true
	var rt: FiringRange.RangeTarget = world.firing_range.targets[5]
	var g: Dictionary = Firearm.spec(kit)
	world.walker._take_up(Firearm.index_of(kit), false)
	var eye: Vector3 = world.walker.cam.global_position
	var aim_at: Vector3 = rt.global_position + Vector3(0, rt.cy, 0)
	var d: Vector3 = world.walker._lay(eye, aim_at, float(g["muzzle"]), 9.81, false, Firearm.drag_of(g))
	var t0 := Time.get_ticks_msec()
	Firearm.fire(world, world.walker, 0, g, eye + d * 1.2, d, 0.0)
	var shot_mid := false
	while Time.get_ticks_msec() - t0 < 20000:
		await world.get_tree().process_frame
		var real: float = float(Time.get_ticks_msec() - t0) * 0.001
		if not shot_mid and real > 1.5:
			shot_mid = true
			await RenderingServer.frame_post_draw
			world.get_viewport().get_texture().get_image().save_png("%s/range_chase_%s.png" % [dir, kit])
			var ridden: Variant = world.cam.get("weapon_cam")
			if ridden != null and is_instance_valid(ridden):
				var rn: Node3D = ridden
				print("[rangecam] riding %s: cal %s, ride scale %.4f, camera %.3f m off it, near %.3f, round model %s" % [
					kit, str((rn as Effects.Tracer).cal.get("name", "none")), float(rn.call("ride_scale")),
					world.cam.global_position.distance_to(rn.get_global_transform_interpolated().origin), world.cam.near,
					str((rn as Effects.Tracer)._round != null and (rn as Effects.Tracer)._round.visible)])
			print("[rangecam] mid-flight: time scale %.3f, physics %d a second, riding %s" % [
				Engine.time_scale, Engine.physics_ticks_per_second, str(world.cam.riding())])
			print("[rangecam] panel:\n%s" % world.firing_range._panel.text)
		if shot_mid and not world.cam.riding() and Engine.time_scale == 1.0:
			break
	print("[rangecam] back to full speed after %.1f s real; time scale %.2f" % [
		float(Time.get_ticks_msec() - t0) * 0.001, Engine.time_scale])
	for i in 30:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	world.get_viewport().get_texture().get_image().save_png("%s/range_traces.png" % dir)
	print("[rangecam] panel after:\n%s" % world.firing_range._panel.text)
	world.get_tree().quit()
#endregion


#region --bridgeprobe
## The ground at every bridge end, walked out along the road: how steep, how
## rough and how far below the deck. --preset=free:f16 --bridgeprobe
var _bridge_probe := false

func tick_bridge_probe() -> void:
	if _bridge_probe and world.running:
		_bridge_probe = false
		_run_bridge_probe()

func _run_bridge_probe() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var ends: Array = []
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 2:
			continue
		for e in 2:
			var a: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var inner: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			var ya: float = ys[0] if e == 0 else ys[ys.size() - 1]
			var out: Vector2 = (a - inner).normalized()
			var side := Vector2(-out.y, out.x)
			var hs: Array = []
			var worst_g := 0.0
			var worst_x := 0.0
			var rough := 0.0
			# along the road itself, not a straight line off the end of the deck:
			# the surveyed line through this end, walked away from the span
			var path := PackedVector2Array()
			var lines: Array = Sim.road_lines()
			for ln in lines:
				var pl: PackedVector2Array = ln
				for si in pl.size():
					if pl[si].distance_to(a) < 0.5:
						var stepdir: int = -1 if (si + 1 < pl.size() and pl[si + 1].distance_to(inner) < 0.5) else 1
						var at_i: int = si
						path.append(pl[si])
						while path.size() < 40 and at_i + stepdir >= 0 and at_i + stepdir < pl.size():
							at_i += stepdir
							path.append(pl[at_i])
						break
				if path.size() > 0:
					break
			var walk: Array = []
			if path.size() >= 2:
				for pi2 in path.size() - 1:
					var p0: Vector2 = path[pi2]
					var p1: Vector2 = path[pi2 + 1]
					var seg: float = p0.distance_to(p1)
					var d2 := 0.0
					while d2 < seg and walk.size() < 151:
						walk.append([p0.lerp(p1, d2 / maxf(seg, 0.001)), (p1 - p0).normalized()])
						d2 += 2.0
			else:
				for k in 151:
					walk.append([a + out * float(k) * 2.0, out])
			for k in walk.size():
				var q: Vector2 = walk[k][0]
				side = Vector2(-(walk[k][1] as Vector2).y, (walk[k][1] as Vector2).x)
				hs.append(Sim.height_at(q.x, q.y))
				var l: Vector2 = q + side * 5.0
				var r: Vector2 = q - side * 5.0
				worst_x = maxf(worst_x, absf(Sim.height_at(l.x, l.y) - Sim.height_at(r.x, r.y)) / 10.0)
			for k in range(5, hs.size()):
				worst_g = maxf(worst_g, absf(float(hs[k]) - float(hs[k - 5])) / 10.0)
			for k in range(1, hs.size() - 1):
				rough = maxf(rough, absf(float(hs[k + 1]) - 2.0 * float(hs[k]) + float(hs[k - 1])))
			var town: float = sqrt(Sim.pad_weight(a.x, a.y))
			# the bank's sides: off the road either way, a little way out
			var side_worst := 0.0
			for along in [10.0, 40.0, 80.0]:
				var c0: Vector2 = a + out * along
				for sgn in [-1.0, 1.0]:
					var prev: float = Sim.height_at(c0.x, c0.y)
					for st in range(2, 46):
						var q1: Vector2 = c0 + side * sgn * float(st) * 2.0
						var hq: float = Sim.height_at(q1.x, q1.y)
						if st >= 5:
							side_worst = maxf(side_worst, absf(hq - prev) / 2.0)
						prev = hq
			ends.append({"at": a, "step": ya - float(hs[0]) - Sim.planet_drop(a.x, a.y), "grade": worst_g,
				"cross": worst_x, "rough": rough, "town": town, "side": side_worst})
	ends.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x["grade"]) > float(y["grade"]))
	var steep := 0
	for e2 in ends:
		if float(e2["grade"]) > 0.15:
			steep += 1
	var walls := 0
	var wall_tris := 0
	if is_instance_valid(world.scenery):
		for n in world.scenery.get_children():
			if String(n.name).begins_with("Walls") and n is MeshInstance3D:
				walls += 1
				wall_tris += int(((n as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	print("[bridge] %d retaining wall meshes, %d triangles" % [walls, wall_tris])
	print("[bridge] %d bridge ends; %d with ground steeper than 15%% within 300 m" % [ends.size(), steep])
	for i in mini(ends.size(), 10):
		var e3: Dictionary = ends[i]
		print("[bridge]   at %s: deck %+.1f m over the ground at the abutment, grade %.0f%%, cross fall %.0f%%, bank sides up to %.0f%%, roughness %.2f m, town weight %.2f" % [
			str((e3["at"] as Vector2).round()), float(e3["step"]), float(e3["grade"]) * 100.0,
			float(e3["cross"]) * 100.0, float(e3["side"]) * 100.0, float(e3["rough"]), float(e3["town"])])
	world.get_tree().quit()
#endregion


#region --rampground
## Round every bridge end in a town: is the ground a man stands on the ground
## that is drawn, is the road on it, and does the drawn ramp reach the deck --
## across the deck's width, where its end panel laps over the ramp? Drawn at
## the finest cell, too: nothing coarser can hold the seat under the deck.
## --preset=free:f16 --rampground
var _ramp_ground := false
## With --rampshots=DIR, a picture of each end from up the road and one from
## beside the deck end, low: not headless.
var _ramp_shots := ""

func tick_ramp_ground() -> void:
	if _ramp_ground and world.running:
		_ramp_ground = false
		_run_ramp_ground()

## The height of whatever triangle of `tris` lies over (x, z), or NAN.
static func _tri_y(tris: PackedVector3Array, x: float, z: float) -> float:
	var best := NAN
	for t in range(0, tris.size() - 2, 3):
		var a: Vector3 = tris[t]
		var b: Vector3 = tris[t + 1]
		var c: Vector3 = tris[t + 2]
		var den: float = (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
		if absf(den) < 1e-6:
			continue
		var l1: float = ((b.z - c.z) * (x - c.x) + (c.x - b.x) * (z - c.z)) / den
		var l2: float = ((c.z - a.z) * (x - c.x) + (a.x - c.x) * (z - c.z)) / den
		var l3: float = 1.0 - l1 - l2
		if l1 < -1e-4 or l2 < -1e-4 or l3 < -1e-4:
			continue
		var y: float = a.y * l1 + b.y * l2 + c.y * l3
		if is_nan(best) or y > best:
			best = y
	return best

## The meshes under `root` named with `prefix` whose box comes within `r` of
## `at`, each as [its box, its triangles in world space, its depth if a terrain
## chunk].
static func _tris_near(root: Node, prefix: String, at: Vector2, r: float) -> Array:
	var out: Array = []
	for n in root.get_children():
		if not (n is MeshInstance3D):
			continue
		# a retired terrain chunk stays drawn until its replacement stands
		if not String(n.name).begins_with(prefix) and not (prefix == "C" and String(n.name).begins_with("X")):
			continue
		var mi := n as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if at.x < ab.position.x - r or at.x > ab.end.x + r \
				or at.y < ab.position.z - r or at.y > ab.end.z + r:
			continue
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var xf: Transform3D = mi.global_transform
		var tris := PackedVector3Array()
		if idx.is_empty():
			for q in v:
				tris.append(xf * q)
		else:
			for i in idx:
				tris.append(xf * v[i])
		var depth := -1
		if prefix == "C":
			depth = int(round(log(Terrain.ROOT_SPAN / maxf(ab.size.x, 1.0)) / log(2.0)))
		out.append([ab, tris, depth])
	return out

## The highest surface of `meshes` over (x, z); for terrain chunks only the
## finest one there, which is the one drawn.
static func _meshes_y(meshes: Array, x: float, z: float) -> float:
	var best := NAN
	var best_depth := -2
	for m in meshes:
		var ab: AABB = m[0]
		if x < ab.position.x or x > ab.end.x or z < ab.position.z or z > ab.end.z:
			continue
		var d: int = m[2]
		if d < best_depth:
			continue
		var y: float = _tri_y(m[1], x, z)
		if is_nan(y):
			continue
		if d > best_depth or is_nan(best) or y > best:
			best = y if d > best_depth else maxf(best, y)
			best_depth = d
	return best

## Two pictures of one bridge end, for --rampshots.
func _ramp_photos(a: Vector2, out: Vector2, side: Vector2, n: int) -> void:
	var top: float = Sim.bridge_floor(a.x, a.y, 1e6)
	if top < -1e8:
		top = Sim.height_at(a.x, a.y)
	var at := Vector3(a.x, top, a.y)
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	if is_instance_valid(world.hud):
		world.hud.visible = false
	# `out` points from the deck down the ramp
	var views := [
		["road", out * 50.0 + side * 14.0, 6.0],
		["side", out * 12.0 + side * 60.0, 4.0],
	]
	for v in views:
		# a stray Escape pauses the match, and the picture is of the menu
		if world.get_tree().paused:
			world._resume()
		var off: Vector2 = v[1]
		cam.global_position = at + Vector3(off.x, float(v[2]), off.y)
		cam.look_at(at + Vector3(0.0, -1.0, 0.0), Vector3.UP)
		cam.current = true
		world.terrain.paint_roads_now(cam.global_position)
		for i in 45:
			await world.get_tree().process_frame
		world.terrain.flush_pending()
		for i in 15:
			await world.get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := world.get_viewport().get_texture().get_image()
		var path := "%s/end%02d_%s.png" % [_ramp_shots, n, v[0]]
		img.save_png(path)
		print("[rampground]   picture: ", path)
	cam.queue_free()

func _run_ramp_ground() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var worst_sink := 0.0
	var worst_meet := 0.0
	var coarse := 0
	var ends := 0
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		if pts.size() < 2:
			continue
		for e in 2:
			var a: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var inner: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			if Sim.pad_weight(a.x, a.y) < 0.3:
				continue
			ends += 1
			var out: Vector2 = (a - inner).normalized()
			var side := Vector2(-out.y, out.x)
			var eye := Vector3(a.x, Sim.height_at(a.x, a.y) + 1.7, a.y)
			# Until the chunks the tree wants here are the ones drawn: the old
			# coarse ones stay up until their replacements are in, and measured
			# in the meantime they read as metres of gap that is not there. The
			# eye is put back every time -- the world points the tree at its
			# camera each frame, which is somewhere else.
			var want_depth: int = world.terrain.depth_at(a.x, a.y, eye)
			var ground: Array = []
			for tries in 12:
				world.terrain.recentre(eye, true)
				world.terrain.flush_pending()
				await world.get_tree().process_frame
				ground = _tris_near(world.terrain, "C", a, 80.0)
				var have := -1
				for m0 in ground:
					var ab0: AABB = m0[0]
					if a.x >= ab0.position.x and a.x <= ab0.end.x and a.y >= ab0.position.z and a.y <= ab0.end.z:
						have = maxi(have, int(m0[2]))
				if have >= want_depth:
					break
			var sink := 0.0
			var sink_at := Vector2.ZERO
			var bad_pts := 0
			for along in range(-30, 61, 3):
				for across in range(-40, 41, 3):
					var q: Vector2 = a + out * float(along) + side * float(across)
					var drawn: float = _meshes_y(ground, q.x, q.y)
					if is_nan(drawn):
						continue
					# the chunks are drawn flat and bent by their shader
					if not Sim.globe:
						drawn -= Sim.planet_drop(q.x, q.y)
					var stood: float = Terrain.drawn_ground(q.x, q.y, eye)
					# a man stands on the deck where there is one over him
					var deck: float = Sim.bridge_floor(q.x, q.y, drawn + 1.0)
					var foot: float = maxf(stood, deck)
					if drawn - foot > sink:
						sink = drawn - foot
						sink_at = Vector2(along, across)
					if drawn - foot > 0.3:
						bad_pts += 1
			var drawn_depth := -1
			for m in ground:
				var ab3: AABB = m[0]
				if a.x >= ab3.position.x and a.x <= ab3.end.x and a.y >= ab3.position.z and a.y <= ab3.end.z:
					drawn_depth = maxi(drawn_depth, int(m[2]))
			# is this end one the corridor knows as an abutment -- what the
			# terrain tree is told to draw at the finest cell round?
			var flagged := 0
			for leg in Sim._corr:
				var fl: int = int(leg[6]) if leg.size() > 6 else 0
				if (fl & 1 and (leg[0] as Vector2).distance_to(a) < 3.0) \
						or (fl & 2 and (leg[1] as Vector2).distance_to(a) < 3.0):
					flagged += 1
			print("[rampground] end %s: globe %s, drawn at depth %d, the quadtree wants %d; %d corridor legs flag it an abutment" % [
				str(a.round()), str(Sim.globe), drawn_depth, world.terrain.depth_at(a.x, a.y, eye), flagged])
			if is_nan(_meshes_y(ground, a.x, a.y)):
				var names: Array = []
				for n in world.terrain.get_children():
					if n is MeshInstance3D:
						var ab2: AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb()
						if a.x >= ab2.position.x and a.x <= ab2.end.x and a.y >= ab2.position.z and a.y <= ab2.end.z:
							names.append("%s vis=%s" % [n.name, str((n as MeshInstance3D).visible)])
				print("[rampground] end %s: no terrain chunk drawn there; over it: %s; %d meshes near" % [str(a.round()), str(names), ground.size()])
			print("[rampground] end %s: drawn ground over where he stands by up to %.2f m (at %s along/across, %d points > 0.3 m)" % [
				str(a.round()), sink, str(sink_at), bad_pts])
			# Where the deck's end panel meets the road it laps onto, across the
			# width of the deck: what a man stands on there (the panel falls to
			# the road, see `Scenery._deck_lap`) against the ground drawn under
			# it. Above it, the panel stands proud of the road; below, the road
			# comes up through it.
			var meet := 0.0
			var meet_at := Vector2.ZERO
			# (out along `out`, which points from the deck onto the ramp: the
			# panel laps over the ramp, not back over the deck)
			for along2 in [2.4]:
				for across2 in range(-8, 9, 2):
					var q2: Vector2 = a + out * float(along2) + side * float(across2)
					var dk: float = Sim.bridge_floor(q2.x, q2.y, 1e6)
					var dg: float = _meshes_y(ground, q2.x, q2.y)
					if dk < -1e8 or is_nan(dg):
						continue
					if not Sim.globe:
						dg -= Sim.planet_drop(q2.x, q2.y)
					if absf(dk - dg) > absf(meet):
						meet = dk - dg
						meet_at = Vector2(along2, across2)
			print("[rampground]   the deck's end panel %.2f m off the road where it meets it (at %s)" % [
				meet, str(meet_at)])
			# and the road it meets, painted: asphalt out along the approach,
			# and how many of the drawn network's legs come to this end at all
			var patch: PackedByteArray = Sim.native.road_paint(256, 32.0, a, false)
			var legs_here := 0
			var lines_up: Array = []
			for li in range(0, Sim.road_draw.size() - 7, 8):
				var la := Vector2(Sim.road_draw[li], Sim.road_draw[li + 1])
				var lb := Vector2(Sim.road_draw[li + 2], Sim.road_draw[li + 3])
				if la.distance_to(a) < 3.0 or lb.distance_to(a) < 3.0:
					legs_here += 1
					# which way it runs into the deck, against the deck's own
					var far2: Vector2 = lb if la.distance_to(a) < 3.0 else la
					lines_up.append("%.2f" % (a - far2).normalized().dot(-out))
			var ys2: PackedFloat32Array = br.get("ys", PackedFloat32Array())
			var own_deck: float = (ys2[0] if e == 0 else ys2[ys2.size() - 1]) - Sim.planet_drop(a.x, a.y)
			print("[rampground]   this deck %.2f, the highest deck read here %.2f; legs arriving line up with it %s" % [
				own_deck, Sim.bridge_floor(a.x, a.y, 1e6), str(lines_up)])
			print("[rampground]   asphalt painted %.2f at 10 m out, %.2f at 30 m; %d drawn legs end here" % [
				_paint_at(patch, 256, 32.0, a, a + out * 10.0, 0),
				_paint_at(patch, 256, 32.0, a, a + out * 30.0, 0), legs_here])
			if drawn_depth < 13:
				coarse += 1
			if _ramp_shots != "" and ends <= 4:
				await _ramp_photos(a, out, side, ends)
			worst_meet = maxf(worst_meet, absf(meet))
			worst_sink = maxf(worst_sink, sink)
	print("[rampground] RESULT: %s — %d town bridge ends, %d drawn coarser than the finest cell; drawn ground over his feet by up to %.2f m, the deck's end panel off the road it meets by up to %.2f m" % [
		"ok" if worst_sink < 0.35 and worst_meet < 0.1 and coarse == 0 else "FAILED",
		ends, coarse, worst_sink, worst_meet])
	world.get_tree().quit()
#endregion


#region --junctions
## Where the town streets meet the roads of the network: does a street that
## climbs to meet a road climb on drawn ground with its road on it, is there a
## kerb laid across any junction, and does a street that stops at a bank stop
## at its foot? --preset=free:f16 --junctions [--junctionshots=DIR, windowed]
var _junctions := false
var _junction_shots := ""

func tick_junctions() -> void:
	if _junctions and world.running:
		_junctions = false
		_run_junctions()

## Is any drawn street piece (`Scenery.street_draw`) within a metre of `q`?
## A street cut back from a bank or a low deck is not drawn there by design.
static func _street_drawn(sc: Node, q: Vector2) -> bool:
	for sd in sc.street_draw:
		if Geometry2D.get_closest_point_to_segment(q, sd[0], sd[1]).distance_to(q) < 1.0:
			return true
	return false

## One channel of a painted patch at a point: 0 to 1, or -1 off the patch.
static func _paint_at(buf: PackedByteArray, n: int, half: float, c: Vector2,
		q: Vector2, ch: int) -> float:
	var i := int(floor((q.x - c.x + half) * n / (half * 2.0)))
	var j := int(floor((q.y - c.y + half) * n / (half * 2.0)))
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1.0
	return float(buf[(j * n + i) * 4 + ch]) / 255.0

func _run_junctions() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	# painted as the eye goes, without being asked?
	for i in 240:
		await world.get_tree().process_frame
	var cam3: Camera3D = world.get_viewport().get_camera_3d()
	var lvs: Array = []
	for lv in world.terrain._road_lv:
		lvs.append("%s at %s, task %d" % [lv["u"], str(lv["centre"]), int(lv["task"])])
	print("[junctions] following the eye at %s: painted %d times; %s" % [
		str(cam3.global_position.round()) if cam3 != null else "none",
		world.terrain.roads_painted, ", ".join(lvs)])
	var sc: Node = world.scenery
	var all: Array = sc.junctions
	var kinds := {"level": 0, "join": 0, "stop": 0}
	for j in all:
		kinds[j["kind"]] = int(kinds[j["kind"]]) + 1
	print("[junctions] %d places a street meets a road: %d level, %d climbing to it, %d stopping at its bank; %d road pieces painted" % [
		all.size(), kinds["level"], kinds["join"], kinds["stop"], int(sc._stats.get("road_pieces", 0))])
	# what a full near square costs to paint, somewhere busy
	if not all.is_empty():
		var t0 := Time.get_ticks_usec()
		Sim.native.road_paint(2048, 256.0, all[0]["p"], true)
		print("[junctions] a near square, 2048 texels a side: %.1f ms" % [
			(Time.get_ticks_usec() - t0) / 1000.0])
	const PN := 512
	const PH := 64.0
	var worst_grade := 0.0
	var bare := 0
	var probed := 0
	var kerbs_across := 0
	var gaps := 0
	var crossings := 0
	var worst_stop := 0.0
	var stops := 0
	var shots := 0
	for j in all:
		var p: Vector2 = j["p"]
		var dir: Vector2 = j["dir"]
		var side := Vector2(-dir.y, dir.x)
		var kind: String = j["kind"]
		var buf: PackedByteArray = Sim.native.road_paint(PN, PH, p, false)
		var street: Array = sc._streets[int(j["street"])]
		var t: float = j["t"]
		var run: float = (street[0] as Vector2).distance_to(street[1])
		# (under a deck too low to go under, the street is cut on purpose)
		var decked: bool = Sim.bridge_headroom(p.x, p.y, 20.0, NAN, false) < sc.STREET_HEADROOM
		if kind != "stop" and not decked:
			crossings += 1
			# a kerb across the junction: on the street's line, inside the
			# road it meets and its kerbs, on whichever side the street goes
			var across := false
			var drawn_side := {-1: _street_drawn(sc, p - dir * 14.0), 1: _street_drawn(sc, p + dir * 14.0)}
			for s2 in range(-11, 12):
				var room2: float = t * run if s2 < 0 else (1.0 - t) * run
				if room2 < 12.0 or not drawn_side[-1 if s2 < 0 else 1]:
					continue
				for o in [-3.0, 0.0, 3.0]:
					if _paint_at(buf, PN, PH, p, p + dir * float(s2) + side * o, 1) > 0.5:
						across = true
			if across:
				kerbs_across += 1
				if kerbs_across <= 3:
					print("[junctions]   a kerb across the junction at %s (%s), fill %.2f" % [
						str(p.round()), kind, float(j["fill"])])
				if kerbs_across <= 1:
					# what is painted along the street's line, and what the
					# ground is doing there against the town's own level
					var town0: float = Sim.height_at(p.x + dir.x * 60.0, p.y + dir.y * 60.0)
					for s5 in range(-11, 12):
						for o5 in [-3.0, 0.0, 3.0]:
							var q5: Vector2 = p + dir * float(s5) + side * o5
							if _paint_at(buf, PN, PH, p, q5, 1) <= 0.5:
								continue
							print("[junctions]     s=%+d o=%+.0f asphalt %.2f kerb %.2f; trunk %.1f m off; ground %+.2f on the town" % [
								s5, o5, _paint_at(buf, PN, PH, p, q5, 0), _paint_at(buf, PN, PH, p, q5, 1),
								Sim.native.trunk_distance(q5.x, q5.y), Sim.height_at(q5.x, q5.y) - town0])
			# and the asphalt unbroken from the road out along the street, on
			# whichever side it goes -- where it meets the road at all: one that
			# runs into it at a shallow angle merges along it, and has no mouth
			var shallow: bool = absf(dir.cross(j.get("along", side) as Vector2)) < 0.5
			for sgn in ([] if shallow else [-1.0, 1.0]):
				var room: float = t * run if sgn < 0.0 else (1.0 - t) * run
				if room < 25.0 or decked or not _street_drawn(sc, p + dir * sgn * 14.0):
					continue
				var broke := false
				for s3 in range(0, 24):
					if _paint_at(buf, PN, PH, p, p + dir * sgn * float(s3), 0) < 0.5:
						broke = true
				if broke:
					gaps += 1
					if gaps <= 3:
						print("[junctions]   the asphalt breaks between the road and the street at %s (%s), street %d at t %.3f of %.0f m" % [
							str(p.round()), kind, int(j["street"]), t, run])
						var row := ""
						for s6 in range(0, 24, 2):
							var q6: Vector2 = p + dir * sgn * float(s6)
							row += " %d:%.1f/%.0f/%s" % [s6, _paint_at(buf, PN, PH, p, q6, 0),
								Sim.native.trunk_distance(q6.x, q6.y), "d" if _street_drawn(sc, q6) else "-"]
						print("[junctions]     along it, asphalt / road distance / drawn:%s" % row)
		if kind == "join":
			var sides_drawn := 0
			for sgn2 in [-1.0, 1.0]:
				if _street_drawn(sc, p + dir * sgn2 * 20.0):
					sides_drawn += 1
			print("[junctions]   climb at %s: fill %.2f, crossing at %.0f deg, street drawn on %d sides" % [
				str(p.round()), float(j["fill"]), rad_to_deg(absf(asin(clampf(dir.cross(
					Vector2(cos(0.0), 0.0)), -1.0, 1.0)))), sides_drawn])
			for sgn in [-1.0, 1.0]:
				if not _street_drawn(sc, p + dir * sgn * 20.0):
					continue
				var prev := NAN
				for s3 in range(12, 50):
					var q: Vector2 = p + dir * sgn * float(s3)
					var g: float = Sim.native.surfaces_at(PackedVector2Array([q]), Terrain.BASE_CELL)[0]
					if not is_nan(prev):
						worst_grade = maxf(worst_grade, absf(g - prev))
					prev = g
					var a: float = _paint_at(buf, PN, PH, p, q, 0)
					if a < 0.0:
						continue
					probed += 1
					if a < 0.5:
						bare += 1
		elif kind == "stop":
			var town_y: float = Sim.height_at(p.x + dir.x * 80.0, p.y + dir.y * 80.0)
			for sgn in [-1.0, 1.0]:
				var toe := -1.0
				var end := -1.0
				for s4 in range(0, 64):
					var q: Vector2 = p + dir * sgn * float(s4)
					if toe < 0.0 and absf(Sim.height_at(q.x, q.y) - town_y) < 0.3:
						toe = float(s4)
					if end < 0.0 and Sim.native.trunk_distance(q.x, q.y) > 9.0 \
							and _paint_at(buf, PN, PH, p, q, 0) > 0.5:
						end = float(s4)
				if toe >= 0.0 and end >= 0.0:
					stops += 1
					worst_stop = maxf(worst_stop, absf(end - toe))
		if _junction_shots != "" and shots < 8 and (kind != "level" or shots < 4):
			shots += 1
			await _junction_photo(p, dir, shots, kind)
	print("[junctions] climbs: worst %.2f m a metre as drawn; %d of %d points along them without asphalt" % [
		worst_grade, bare, probed])
	print("[junctions] %d streets cut back to a junction from a bank or a low deck" % int(sc._stats.get("streets_cut", 0)))
	print("[junctions] %d of %d junctions with a kerb across them, %d sides where the asphalt breaks; streets stopping at a bank end within %.1f m of its foot (%d ends)" % [
		kerbs_across, crossings, gaps, worst_stop, stops])
	var ok: bool = kerbs_across == 0 and gaps == 0 and worst_grade < 0.2 \
		and (probed == 0 or bare * 10 < probed) and worst_stop <= 3.0
	print("[junctions] RESULT: %s" % ("ok" if ok else "FAILED"))
	world.get_tree().quit()

func _junction_photo(p: Vector2, dir: Vector2, n: int, kind: String) -> void:
	var side := Vector2(-dir.y, dir.x)
	var eye2: Vector2 = p + dir * 45.0 + side * 25.0
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	if is_instance_valid(world.hud):
		world.hud.visible = false
	cam.global_position = Vector3(eye2.x, Sim.height_at(eye2.x, eye2.y) + 14.0, eye2.y)
	cam.look_at(Vector3(p.x, Sim.height_at(p.x, p.y), p.y), Vector3.UP)
	cam.current = true
	world.terrain.paint_roads_now(cam.global_position)
	for i in 45:
		if world.get_tree().paused:
			world._resume()
		await world.get_tree().process_frame
	world.terrain.flush_pending()
	for i in 15:
		await world.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/junction%02d_%s.png" % [_junction_shots, n, kind]
	world.get_viewport().get_texture().get_image().save_png(path)
	print("[junctions]   picture: ", path)
	cam.queue_free()
#endregion


#region --spanbodies
## The bridge decks' physics bodies, which only the spans near the viewer get:
## over every bridge in turn, does a ray dropped on the deck land on its top,
## and far from all of them are there none? --preset=free:f16 --spanbodies
var _span_bodies := false

func tick_span_bodies() -> void:
	if _span_bodies and world.running:
		_span_bodies = false
		_run_span_bodies()

func _run_span_bodies() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var obs: Obstacles = world.obstacles
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var tried := 0
	var landed := 0
	var worst := 0.0
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br.get("pts", PackedVector2Array())
		var ys: PackedFloat32Array = br.get("ys", PackedFloat32Array())
		if pts.size() < 3:
			continue
		# the middle of a middle span, where the deck is over nothing
		var k: int = int(pts.size() / 2.0) - 1
		var q: Vector2 = (pts[k] + pts[k + 1]) * 0.5
		var deck: float = (ys[k] + ys[k + 1]) * 0.5 - Sim.planet_drop(q.x, q.y)
		obs.pin(Vector3(q.x, deck + 2.0, q.y))
		await world.get_tree().physics_frame
		await world.get_tree().physics_frame
		var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, deck + 10.0, q.y),
			Vector3(q.x, deck - 10.0, q.y), 4)
		var hit: Dictionary = space.intersect_ray(rq)
		tried += 1
		if hit.is_empty():
			print("[spanbodies] deck at %s: nothing under the ray (%d spans live)" % [
				str(q.round()), obs.live_spans()])
			continue
		var off: float = absf((hit["position"] as Vector3).y - deck)
		worst = maxf(worst, off)
		if off < 0.25:
			landed += 1
		else:
			print("[spanbodies] deck at %s: hit %.2f m off the deck top" % [str(q.round()), off])
		if tried >= 20:
			break
	# and somewhere no bridge is near
	obs.pin(Vector3(1e6, 0.0, 1e6))
	await world.get_tree().physics_frame
	var far: int = obs.live_spans()
	obs.unpin()
	print("[spanbodies] RESULT: %s — %d of %d decks caught the ray, worst %.2f m off the top; %d span bodies live far from any bridge" % [
		"ok" if tried > 0 and landed == tried and far == 0 else "FAILED", landed, tried, worst, far])
	world.get_tree().quit()
#endregion


#region --bridgedrive
## An AI tank sent across every road bridge: does it ride the deck or fall
## through it? --preset=free:f16 --bridgedrive
var _bridge_drive := false

func tick_bridge_drive() -> void:
	if _bridge_drive and world.running:
		_bridge_drive = false
		_run_bridge_drive()

func _run_bridge_drive() -> void:
	for i in 30:
		await world.get_tree().physics_frame
	var ok := 0
	var tried := 0
	for br in Sim.road_bridges:
		var pts: PackedVector2Array = br["pts"]
		var ys: PackedFloat32Array = br["ys"]
		if pts.size() < 2:
			continue
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[pts.size() - 1]
		var out_a: Vector2 = (a - pts[1]).normalized()
		var out_b: Vector2 = (b - pts[pts.size() - 2]).normalized()
		var start2: Vector2 = a + out_a * 45.0
		var goal2: Vector2 = b + out_b * 300.0
		var start := Vector3(start2.x, Sim.height_at(start2.x, start2.y), start2.y)
		var head: float = atan2(out_a.x, out_a.y)          # facing back along -out
		var t := world._spawn_tank(start, head, 0, "humvee")
		t.ai = true
		t.ai_goal = Vector3(goal2.x, Sim.height_at(goal2.x, goal2.y), goal2.y)
		tried += 1
		var mid: Vector2 = pts[int(pts.size() / 2.0)]
		var mid_deck: float = ys[int(ys.size() / 2.0)] - Sim.planet_drop(mid.x, mid.y)
		var crossed := false
		var fell := false
		var worst := 0.0
		for f in 60 * 90:
			await world.get_tree().physics_frame
			if not is_instance_valid(t):
				break
			var p: Vector3 = t.global_position
			if f % 300 == 0:
				print("[bridgedrive]   t=%ds at %s, %.0f m to go; speed %.1f throttle %.2f steer %+.2f brake %s; building %d; floor %.1f deck %.1f" % [
					int(f / 60.0), str(p.round()), Vector2(p.x, p.z).distance_to(goal2),
					t.speed, t.in_throttle, t.in_steer, str(t.in_brake),
					Obstacles.hit(p, t.hull_radius()), Sim.height_at(p.x, p.z),
					Sim.bridge_floor(p.x, p.z, p.y)])
			var deck: float = Sim.bridge_floor(p.x, p.z, p.y)
			var on_span: bool = Sim.height_at(p.x, p.z) < mid_deck - 4.0 \
				and Vector2(p.x, p.z).distance_to(mid) < a.distance_to(b) * 0.5
			if on_span:
				if deck < -1e8 or p.y < deck - 1.5:
					fell = true
					break
				worst = maxf(worst, absf(p.y - deck - t.rest_height()))
			# across: at the far abutment, still up at the deck's level
			if Vector2(p.x, p.z).distance_to(b) < 25.0:
				crossed = true
				break
		print("[bridgedrive] bridge %s -> %s (%.0f m, ground under the middle %.0f m below the deck): %s, rode the deck within %.2f m" % [
			str(a.round()), str(b.round()), a.distance_to(b),
			mid_deck - Sim.height_at(mid.x, mid.y),
			"FELL THROUGH" if fell else ("crossed" if crossed else "did not get across"), worst])
		if crossed and not fell:
			ok += 1
		if is_instance_valid(t):
			t.queue_free()
	print("[bridgedrive] RESULT: %s — %d of %d crossed" % ["ok" if ok == tried else "FAILED", ok, tried])
	world.get_tree().quit()
#endregion
