class_name WeaponTests
extends TestSuite
## Air-launched weapons, sensors and countermeasures: locks, pods, missiles,
## cruise and strategic rounds.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a.begins_with("--weapontest="):
		_wtest = a.substr(13)
	elif a.begins_with("--podch="):
		_pod_want = int(a.substr(8))
		_pod_test = true
	elif a == "--decoytest":
		_decoy_test = true
	elif a == "--apkwstest":
		_apkws_test = true
	elif a == "--masktest":
		_mask_test = true
	elif a == "--splashtest":
		_splash_test = true
	elif a.begins_with("--tfrtest="):
		_tfr_test = true
		_tfr_kind = a.substr(10)
	elif a == "--tfrveh":
		_tfr_veh = true
	elif a.begins_with("--tfrrange="):
		_tfr_range = float(a.substr(11)) * 1000.0
	elif a == "--tfrtest":
		_tfr_test = true
	elif a == "--cruiseland":
		_land_test = true
	elif a == "--reachtest":
		_reach_test = true
	elif a == "--wavetest":
		_wave_test = true
	elif a == "--manpadstest":
		_mp_test = true
	elif a == "--asattest":
		_asat_test = true
	elif a == "--tacnukesea":
		_tacnuke = true
		_tacnuke_sea = true
	elif a == "--tacnukenociws":
		_tacnuke = true
		_tacnuke_sea = true
		_tacnuke_ciws_off = true
	elif a == "--tacnuke":
		_tacnuke = true
	elif a == "--nuketest":
		_nuke_test = true
	elif a == "--lagtest":
		_lag_test = true
	elif a == "--tracertest":
		_tracer_test = true
	elif a == "--locktime":
		_locktime_test = true
	elif a == "--mavtest":
		_mav_test = true
	elif a.begins_with("--cmtest="):
		_cm_test = a.substr(9)
	elif a == "--cruisetest":
		_cruise_test = true
	elif a == "--flirtest":
		_flirtest = true
	elif a == "--salvotest":
		_salvo_test = true
	elif a.begins_with("--salvotest="):
		_salvo_test = true
		_salvo_w = a.substr(12)
	elif a == "--shaketest":
		_shake_test = true
	elif a.begins_with("--breaktest="):
		# range[,altitude[,weapon]]
		var bits := a.substr(12).split(",")
		_break_rng = float(bits[0])
		if bits.size() > 1:
			_break_alt = float(bits[1])
		if bits.size() > 2:
			_break_w = String(bits[2])
		_break_test = true
	elif a.begins_with("--cluttertest="):
		_clutter_agl = float(a.substr(14))
		_clutter_test = true
	elif a == "--triggertest":
		_trig_test = true
	elif a == "--lasertest":
		_laser_test = true
	elif a == "--firetest":
		_fire_test = true
	elif a == "--locktest":
		_lock_test = true
	elif a == "--podtest":
		_pod_test = true
	else:
		return false
	return true


#region --weapontest=
var _wtest := ""
var _wt_t := 0.0
var _wt_stage := 0
var _nuke_before := 0
var _nuke_aim := Vector3.ZERO
var _wt_mark: Node = null

func tick_wtest(delta: float) -> void:
	if _wtest != "":
		# the checks must outlive the shooter: a bomb keeps guiding after the
		# aircraft that dropped it has been shot down
		if _wt_stage > 1 or is_instance_valid(world.player):
			_run_weapon_test(delta)

## How many things that can be shot are still alive inside a radius.
func _count_standing(at: Vector3, radius: float) -> int:
	var n := 0
	for x in world.get_tree().get_nodes_in_group("hittable"):
		if not is_instance_valid(x) or not (x is Node3D):
			continue
		if x.has_method("is_alive") and not x.is_alive():
			continue
		if (x as Node3D).global_position.distance_to(at) < radius:
			n += 1
	return n

## End to end checks for the weapon chains, driven from the command line.
func _run_weapon_test(delta: float) -> void:
	_wt_t += delta
	match _wtest:
		"bomb":
			if _wt_stage == 0 and _wt_t > 1.0:
				for sam in world.get_tree().get_nodes_in_group("hittable"):
					if sam is GroundTarget and (sam as GroundTarget).kind == "sam":
						(sam as GroundTarget).alive = false     # quiet range
				for n in world.get_tree().get_nodes_in_group("ground_targets"):
					if is_instance_valid(n) and n.is_alive() and n.is_in_group("hittable") \
							and n.team != 0:
						_wt_mark = n
						break
				if _wt_mark == null:
					print("[wt] no ground target in this mission")
					_wtest = ""
					return
				var tp: Vector3 = _wt_mark.global_position
				var from := tp + Vector3(0, 700.0, 1500.0)
				world.player.global_transform = Transform3D(Basis(), from)
				world.player.look_at(tp, Vector3.UP)
				world.player.linear_velocity = -world.player.global_transform.basis.z * 240.0
				world.player.gear_down = false
				world.player.gear_anim = 0.0
				world.player.throttle = 0.8
				world.player.power = 0.8
				world.player.set_bays(true)
				world.player.target = _wt_mark
				world._reset_interp.call_deferred(world.player)
				print("[wt] bomb run: %s at %.0f m, health %.0f" % [
					_wt_mark.name, from.distance_to(tp), _wt_mark.health])
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 3.5:
				world.player.selected = maxi(world.player.weapon_types.find("gbu32"), 0)
				var res: String = world.player.fire()
				print("[wt] release: %s  (bay %s)" % [
					"away" if res == "" else res,
					"open" if world.player.any_bay_open() else "shut"])
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2:
				if not is_instance_valid(_wt_mark) or not _wt_mark.is_alive():
					print("[wt] RESULT: target destroyed at t=%.1f" % _wt_t)
					_wtest = ""
					return
				var live := world.get_tree().get_nodes_in_group("missiles")
				if fmod(_wt_t, 2.0) < delta:
					var d := -1.0
					for m in live:
						if is_instance_valid(m) and m.wid == "gbu32":
							d = m.global_position.distance_to(_wt_mark.global_position)
					print("[wt]   t=%4.1f  bombs airborne=%d  miss distance=%.0f m  target hp=%.0f"
						% [_wt_t, live.size(), d, _wt_mark.health])
				if _wt_t > 30.0:
					print("[wt] RESULT: no kill, target health %.0f" % _wt_mark.health)
					_wtest = ""
		"aamground":
			# put a Sidewinder into a built-up area and see what it does
			if _wt_stage == 0 and _wt_t > 1.0:
				# find somewhere actually built up rather than assuming
				var want := Vector3.ZERO
				var best := 0
				for cx in range(-12, 13):
					for cz in range(-12, 13):
						var q := Vector3(float(cx) * 900.0, 0.0, float(cz) * 900.0)
						var c := world.scenery.count_standing(q, 120.0)
						if c > best:
							best = c
							want = q
				want.y = Sim.height_at(want.x, want.z)
				_nuke_aim = want
				# count at the SAME point the after-count uses, or the two
				# radii are measured from different heights and disagree
				_nuke_before = world.scenery.count_standing(want, 120.0)
				world.player.global_transform = Transform3D(Basis(), want + Vector3(0, 900.0, 2600.0))
				world.player.rotation = Vector3(deg_to_rad(-19.0), 0.0, 0.0)
				world.player.linear_velocity = -world.player.global_transform.basis.z * 250.0
				world.player.gear_down = false
				world.player.gear_anim = 0.0
				world.player.throttle = 0.8
				world.player.power = 0.8
				world.player.set_bays(true)
				world.player.target = null
				world._reset_interp.call_deferred(world.player)
				print("[wt] AAM into the ground: %d structures standing within 120 m" % _nuke_before)
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 4.0:
				world.player.selected = maxi(world.player.weapon_types.find("aim9"), 0)
				world.player.locked = true
				var res: String = world.player.fire()
				print("[wt] release: %s" % ("away" if res == "" else res))
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2 and _wt_t > 12.0:
				var after := world.scenery.count_standing(_nuke_aim, 120.0)
				print("[wt] RESULT: %d of %d structures within 120 m brought down" % [
					_nuke_before - after, _nuke_before])
				_wtest = ""
		"nuke", "nuke2":
			if _wt_stage == 0 and _wt_t > 1.0:
				# designate something real: a guided bomb needs a target, and
				# without one it simply falls where it was let go
				var best: Node3D = null
				var bd := 1e9
				var want := Vector3(2600.0, 0, 4200.0)
				for g in world.get_tree().get_nodes_in_group("ground_targets"):
					if not is_instance_valid(g):
						continue
					var dd: float = Vector2(g.global_position.x - want.x,
						g.global_position.z - want.z).length()
					if dd < bd:
						bd = dd
						best = g
				if best == null:
					print("[wt] no ground target to aim at")
					_wtest = ""
					return
				_wt_mark = best
				var tgt: Vector3 = best.global_position
				_nuke_before = _count_standing(tgt, 1400.0)
				world.player.global_transform = Transform3D(Basis(),
					tgt + Vector3(0, 700.0, 2400.0))
				world.player.rotation.y = 0.0        # facing -Z, which is toward the target
				world.player.linear_velocity = -world.player.global_transform.basis.z * 190.0
				world.player.gear_down = false
				world.player.gear_anim = 0.0
				world.player.throttle = 0.6
				world.player.power = 0.6
				world.player.set_bays(true)
				world.player.target = _wt_mark
				_nuke_aim = tgt
				world._reset_interp.call_deferred(world.player)
				print("[wt] nuclear run (%s): aim %s, %d units standing within 1400 m" % [
					"b83 strategic" if _wtest == "nuke2" else "b61 tactical",
					str(tgt.round()), _nuke_before])
				_wt_stage = 1
			elif _wt_stage == 1 and _wt_t > 4.0:
				var wid := "b83" if _wtest == "nuke2" else "b61"
				world.player.selected = maxi(world.player.weapon_types.find(wid), 0)
				world.player.locked = true
				var res: String = world.player.fire()
				print("[wt] release: %s" % ("away" if res == "" else res))
				if res == "":
					_wt_stage = 2
			elif _wt_stage == 2 and _wt_t > 8.0 \
					and world.get_tree().get_nodes_in_group("missiles").is_empty():
				var after := _count_standing(_nuke_aim, 1400.0)
				print("[wt] RESULT: %d of %d units within 1400 m destroyed" % [
					_nuke_before - after, _nuke_before])
				_wtest = ""
		"gun":
			if _wt_stage == 0 and _wt_t > 1.0:
				for n in world.get_tree().get_nodes_in_group("bandits"):
					if is_instance_valid(n) and n.is_alive():
						_wt_mark = n
						break
				if _wt_mark == null:
					print("[wt] no bandit to shoot at")
					_wtest = ""
					return
				print("[wt] gun run on %s, health %.0f" % [_wt_mark.name, _wt_mark.health])
				_wt_stage = 1
			elif _wt_stage >= 1 and is_instance_valid(_wt_mark):
				# sit 500 m astern and hose it
				var tp: Vector3 = _wt_mark.global_position
				var tb: Basis = _wt_mark.global_transform.basis
				world.player.global_transform = Transform3D(tb, tp + tb.z * 500.0)
				world.player.linear_velocity = _wt_mark.linear_velocity
				world.player.fire_gun(world)
				if not _wt_mark.is_alive():
					print("[wt] RESULT: bandit shot down with the gun at t=%.1f" % _wt_t)
					_wtest = ""
				elif _wt_t > 25.0:
					print("[wt] RESULT: gun did %.0f damage in 25 s" % (100.0 - _wt_mark.health))
					_wtest = ""
		"capture":
			if _wt_stage == 0 and _wt_t > 1.0:
				for z in world.get_tree().get_nodes_in_group("zones"):
					if is_instance_valid(z) and z.owner_team == 1:
						_wt_mark = z
						break
				if _wt_mark == null:
					print("[wt] no hostile sector")
					_wtest = ""
					return
				print("[wt] sector %s: owner=%d progress=%.2f assets=%d" % [
					_wt_mark.label, _wt_mark.owner_team, _wt_mark.progress,
					_wt_mark.alive_assets()])
				for a in _wt_mark.assets:
					if is_instance_valid(a) and a.has_method("take_hit"):
						a.take_hit(9999.0)
				print("[wt] garrison flattened, assets alive: %d" % _wt_mark.alive_assets())
				_wt_stage = 1
			elif _wt_stage == 1:
				if not is_instance_valid(_wt_mark):
					_wtest = ""
				elif _wt_mark.owner_team == 0:
					print("[wt] RESULT: sector %s captured at t=%.1f" % [_wt_mark.label, _wt_t])
					_wtest = ""
				elif fmod(_wt_t, 2.0) < delta:
					print("[wt]   progress %.2f owner=%d assets alive=%d" % [
						_wt_mark.progress, _wt_mark.owner_team, _wt_mark.alive_assets()])
				elif _wt_t > 30.0:
					print("[wt] RESULT: sector not taken, progress %.2f" % _wt_mark.progress)
					_wtest = ""
		"trap":
			if _wt_stage == 0 and _wt_t > 1.0:
				var deck: Vector3 = world.carrier.global_position
				var hdg: float = world.carrier.rotation.y + Carrier.ANGLE
				var back := Vector3(sin(hdg), 0, cos(hdg))
				world.player.global_transform = Transform3D(Basis(Vector3.UP, hdg),
					deck + back * 260.0 + Vector3(0, Carrier.DECK_Y + 16.0, 0))
				world.player.linear_velocity = (-world.player.global_transform.basis.z * 66.0
					+ Vector3(0, -3.4, 0))
				world.player.gear_down = true
				world.player.gear_anim = 1.0
				world.player.hook_down = true
				world.player.hook_anim = 1.0
				world.player.flaps = 1.0
				world.player.throttle = 0.45
				world.player.power = 0.45
				world._reset_interp.call_deferred(world.player)
				print("[wt] carrier approach: 260 m out, 16 m above the deck, hook down")
				_wt_stage = 1
			elif _wt_stage == 1:
				if world.player.trapped:
					print("[wt] RESULT: TRAPPED at t=%.1f, speed %.1f m/s" % [
						_wt_t, world.player.linear_velocity.length()])
					_wt_stage = 2
				elif _wt_t > 25.0:
					print("[wt] RESULT: no trap. on ground=%s alt=%.1f speed=%.1f" % [
						str(world.player.on_ground), world.player.global_position.y,
						world.player.linear_velocity.length()])
					_wtest = ""
			elif _wt_stage == 2 and world.player.linear_velocity.length() < 2.0:
				print("[wt] stopped on deck at %.1f m, %.1f s after touchdown" % [
					world.player.global_position.y, _wt_t])
				_wtest = ""
#endregion


#region --podch= --podtest
var _pod_test := false
var _pod_t := 0.0
var _pod_want := -1

func tick_pod(delta: float) -> void:
	if _pod_test and is_instance_valid(world.player):
		_pod_t += delta
		if _pod_t > 2.0 and not world.pod.active:
			world.pod.toggle()
			world.pod.set_fullscreen(true)
			if _pod_want >= 0:
				while world.pod.channel != _pod_want:
					world.pod.cycle_channel()
				print("[pod] channel forced to %s" % SensorPod.CHANNEL_NAMES[world.pod.channel])
		elif _pod_t > 4.0 and world._shot == "":
			_pod_test = false
			var tex_behind: bool = world.pod._tex.show_behind_parent
			# how many radar contacts the pod page would box
			var boxed := 0
			var reach: float = maxf(Sim.radar_range(), 26000.0)
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == world.player or not (n is Node3D):
					continue
				if n.has_method("is_alive") and not n.is_alive():
					continue
				var wp: Vector3 = (n as Node3D).global_position
				if world.player.global_position.distance_to(wp) > reach:
					continue
				if world.pod._cam.is_position_behind(wp):
					continue
				var sp: Vector2 = world.pod._cam.unproject_position(wp)
				if sp.x > 4.0 and sp.y > 4.0 and sp.x < world.pod.size.x - 4.0 and sp.y < world.pod.size.y - 4.0:
					boxed += 1
			print("[pod] contacts boxed on the sensor page: %d; head AZ %+.0f EL %+.0f" % [
				boxed, rad_to_deg(world.pod.yaw), rad_to_deg(world.pod.pitch)])
			var mp = (world.pod._tex.material as ShaderMaterial).get_shader_parameter("channel")
			print("[pod] shader channel param = %s (pod.channel=%d)" % [str(mp), world.pod.channel])
			var ho: Vector3 = world.player.global_transform.affine_inverse() * world.pod._head_origin()
			var secs: Array = world.player.spec["shape"]["sections"]
			var bot := 0.0
			for i in secs.size() - 1:
				if -1.8 >= minf(secs[i][0], secs[i+1][0]) and -1.8 <= maxf(secs[i][0], secs[i+1][0]):
					var f: float = (-1.8 - secs[i][0]) / maxf(secs[i+1][0] - secs[i][0], 0.001)
					bot = lerpf(secs[i][3], secs[i+1][3], f) - lerpf(secs[i][2], secs[i+1][2], f)
					break
			print("[pod] head at %s, hull bottom y=%.2f -> %s the fuselage" % [
				str(ho.snapped(Vector3.ONE * 0.01)), bot,
				"CLEAR of" if ho.y < bot else "INSIDE"])
			print("[pod] active=%s fullscreen=%s size=%s picture behind overlay=%s channel=%s" % [
				str(world.pod.active), str(world.pod.fullscreen), str(world.pod.size), str(tex_behind),
				SensorPod.CHANNEL_NAMES[world.pod.channel]])
			world.get_tree().quit()
#endregion


#region --decoytest
## How often a salvo of flares or chaff breaks an air defence round's track,
## by geometry and by how late it goes, and what holding the button down buys:
## --decoytest.
var _decoy_test := false

func tick_decoy() -> void:
	if _decoy_test and world.running:
		_decoy_test = false
		_run_decoy_test()

func _run_decoy_test() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var tv := Vector3(0, 0, -220.0)          # the aeroplane, flying north
	var cases := [["tail", Vector3(0, 0, 1)], ["beam", Vector3(1, 0, 0)],
		["head-on", Vector3(0, 0, -1)]]
	var bad := PackedStringArray()
	for wid in ["manpads", "aim9", "sam_med", "aim120", "sm2"]:
		var spec := WeaponSpec.get_spec(wid)
		var ir: bool = float(spec.get("flare_bait", 0.0)) > 0.0
		var bait: float = float(spec.get("flare_bait", 0.0)) if ir \
			else float(spec.get("chaff_bait", 0.0))
		var row := PackedStringArray()
		var worst := 0.0
		for c in cases:
			for tgo in [2.0, 8.0]:
				var dirv: Vector3 = c[1]
				var sp: float = float(spec.get("ref_speed", 700.0))
				var mpos: Vector3 = dirv * sp * tgo
				var mvel: Vector3 = -dirv * sp
				var p1: float = Missile.decoy_chance(bait, ir, mpos, mvel, Vector3.ZERO, tv)
				# three salvos a half second apart, the button held down
				var broke := 0
				for k in 2000:
					var wary := 1.0
					for _j in 3:
						if rng.randf() < Missile.decoy_chance(bait, ir, mpos, mvel,
								Vector3.ZERO, tv, wary):
							broke += 1
							break
						wary *= Missile.DECOY_WARY
				var p3: float = float(broke) / 2000.0
				worst = maxf(worst, p3)
				row.append("%s %ds %2.0f%%/%2.0f%%" % [c[0], int(tgo), p1 * 100.0, p3 * 100.0])
		print("[decoy] %-8s %s: %s" % [wid, "flares" if ir else "chaff ", "  ".join(row)])
		if worst > 0.85:
			bad.append("%s: three salvos at the best moment still break it %.0f%% of the time" % [
				wid, worst * 100.0])
	print("[decoy] (one salvo / three salvos held down)")
	for b in bad:
		print("[decoy]   ", b)
	print("[decoy] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --apkwstest
## Put the pod's laser on a spot, select it, and send a rocket at it -- then one
## more with the laser off, to show what the laser bought.
var _apkws_test := false
var _apkws_t := 0.0

func tick_apkws(delta: float) -> void:
	if _apkws_test and world.running and is_instance_valid(world.player):
		_apkws_t += delta
		if _apkws_t > 2.0:
			_apkws_test = false
			_run_apkws_test()

## Walk a berth seaward until it is over water deep enough to float in.
func _run_apkws_test() -> void:
	var bad := PackedStringArray()
	var hi: int = world.player.weapon_types.find("hydra")
	if hi < 0:
		print("[laser] RESULT: FAILED — %s carries no rockets (use --preset=free:a10)" % world.player.name)
		world.get_tree().quit()
		return
	# the head on a spot four kilometres ahead of the nose
	world.pod.platform = world.player
	if not world.pod.active:
		world.pod.toggle()
	var h: float = world.player.global_position.y - Sim.height_at(world.player.global_position.x,
		world.player.global_position.z)
	world.pod.yaw = 0.0
	world.pod.pitch = -atan2(h, 4000.0)
	await world.get_tree().process_frame
	world.pod.designate()
	# where "straight ahead" on the sensor put the spot, against the nose
	var nose: Vector3 = -world.player.global_transform.basis.z
	var to_spot: Vector3 = world.pod.area_point - world.player.global_position
	print("[laser] head at yaw 0: the spot is %.0f deg off the nose, %.0f m away (%.0f m up)" % [
		rad_to_deg(Vector2(nose.x, nose.z).angle_to(Vector2(to_spot.x, to_spot.z))),
		Vector2(to_spot.x, to_spot.z).length(), h])
	world.pod.toggle_laser()
	for i in 6:
		await world.get_tree().process_frame
	var spot: Node3D = world.pod._marker
	if not is_instance_valid(spot) or not bool(spot.get("on")) or not bool(spot.get("lasing")):
		bad.append("no lit spot after the laser came on")
	elif world.player.target != spot:
		bad.append("the spot was not selected when the laser came on (target %s)" % Sim.label_of(world.player.target))
	# T: off the spot and back onto it, like any other contact
	var visits := 0
	var others := 0
	for i in 10:
		world.player.cycle_target()
		if world.player.target == spot:
			visits += 1
		elif world.player.target != null:
			others += 1
	print("[laser] T walked %d time(s) onto the spot and %d onto other contacts in 10 presses" % [
		visits, others])
	if visits == 0:
		bad.append("T never selected the spot")
	var guard := 0
	while world.player.target != spot and guard < 20:
		world.player.cycle_target()
		guard += 1
	world.player.set_weapon(hi)
	var waited := 0.0
	while not world.player.locked and waited < 3.0:
		await world.get_tree().physics_frame
		waited += 1.0 / float(Engine.physics_ticks_per_second)
	print("[laser] %s on the spot after %.2f s; release cue: %s" % [
		"LOCK" if world.player.locked else "no lock", waited,
		world.player.shot_blocked("hydra", spot) if world.player.shot_blocked("hydra", spot) != "" else "clear"])
	var guided: float = await _apkws_shot(spot.global_position)
	world.pod.toggle_laser()
	world.player.target = null
	await world.get_tree().physics_frame
	var plain: float = await _apkws_shot(spot.global_position)
	print("[laser] rocket on the laser landed %.1f m from the spot; with the laser off, %.1f m" % [
		guided, plain])
	if guided > 25.0:
		bad.append("the guided rocket missed by %.0f m" % guided)
	for b in bad:
		print("[laser]   ", b)
	print("[laser] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()

## Fire the selected store and follow it down: how far from `aim` it ended.
func _apkws_shot(aim: Vector3) -> float:
	var before: Array = world.get_tree().get_nodes_in_group("missiles")
	var why: String = world.player.fire()
	if why != "":
		print("[laser]   release refused: ", why)
		return INF
	await world.get_tree().physics_frame
	var m: Node3D = null
	for n in world.get_tree().get_nodes_in_group("missiles"):
		if not before.has(n) and is_instance_valid(n) and n.get("shooter") == world.player:
			m = n
	if m == null:
		return INF
	var last: Vector3 = m.global_position
	var t := 0.0
	while is_instance_valid(m) and t < 30.0:
		last = m.global_position
		await world.get_tree().physics_frame
		t += 1.0 / float(Engine.physics_ticks_per_second)
	return Vector2(last.x - aim.x, last.z - aim.z).length()
#endregion


#region --masktest
var _mask_test := false
var _mask_t := 0.0
var mask_seeker_ok := false

# Does the terrain actually block a line, and does the radar respect it.
func tick_mask(delta: float) -> void:
	if _mask_test and is_instance_valid(world.player):
		_mask_t += delta
		if _mask_t > 2.0:
			_mask_test = false
			# a pair of points either side of the highest ground we can find
			var best := Vector3.ZERO
			var bh := -1e9
			for i in 40:
				for j in 40:
					var q := Vector3(float(i - 20) * 700.0, 0.0, float(j - 20) * 700.0)
					var h := Sim.height_at(q.x, q.z)
					if h > bh:
						bh = h
						best = Vector3(q.x, h, q.z)
			print("[mask] highest ground nearby: %s at %.0f m" % [
				str(best.round()), bh])
			var a := best + Vector3(-3500.0, 0, 0)
			var b := best + Vector3(3500.0, 0, 0)
			a.y = Sim.height_at(a.x, a.z) + 40.0
			b.y = Sim.height_at(b.x, b.z) + 40.0
			print("[mask] low either side of it: clear=%s (expect false), depth %.0f m" % [
				str(Sim.line_of_sight(a, b)), Sim.masking_depth(a, b)])
			var ha := Vector3(a.x, bh + 2500.0, a.z)
			var hb := Vector3(b.x, bh + 2500.0, b.z)
			print("[mask] both well above it: clear=%s (expect true),  depth %.0f m" % [
				str(Sim.line_of_sight(ha, hb)), Sim.masking_depth(ha, hb)])
			# and what the radar does about it
			var ghost := AIPlane.new()
			ghost.setup("su35")
			ghost.team = 1
			ghost.name = "Masked bandit"
			world.add_child(ghost)
			ghost.global_position = b
			ghost.freeze = true
			world.player.global_position = a
			world.player.team = 0
			world._reset_interp(world.player)
			world.player.target = null
			world.player.cycle_target()
			var got_masked: bool = is_instance_valid(world.player.target)
			ghost.global_position = Vector3(b.x, bh + 2500.0, b.z)
			world.player.global_position = Vector3(a.x, bh + 2500.0, a.z)
			world.player.target = null
			world.player.cycle_target()
			var got_clear: bool = is_instance_valid(world.player.target)
			print("[mask] radar lock: behind the ridge=%s (expect false), over it=%s (expect true)" % [
				str(got_masked), str(got_clear)])
			# and the scope, not just the lock: count what the radar page would
			# actually paint from behind the ridge and from over it
			ghost.global_position = b
			world.player.global_position = a
			var paint_masked := _radar_paints(ghost)
			ghost.global_position = Vector3(b.x, bh + 2500.0, b.z)
			world.player.global_position = Vector3(a.x, bh + 2500.0, a.z)
			var paint_clear := _radar_paints(ghost)
			print("[mask] radar scope: paints it behind the ridge=%s (expect false), over it=%s (expect true)" % [
				str(paint_masked), str(paint_clear)])
			# and what shoots at you. The battery stands on the ridge's far
			# side; the ship is at sea, with the player put behind the highest
			# ground on the line running inland from her.
			var sam := GroundTarget.new()
			sam.team = 1
			sam.setup("sam")
			world.add_child(sam)
			sam.global_position = Vector3(b.x, Sim.height_at(b.x, b.z), b.z)
			var fired_masked := 0
			var fired_clear := 0
			for phase in 2:
				var y: float = (bh + 2500.0) if phase == 1 else (Sim.height_at(a.x, a.z) + 40.0)
				world.player.global_position = Vector3(a.x, y, a.z)
				world.player.team = 0
				world._reset_interp(world.player)
				sam._cool = 0.0
				var before := world.get_tree().get_nodes_in_group("missiles").size()
				for _i in 240:                     # two seconds of engagement
					sam._physics_process(1.0 / 120.0)
				var shots: int = world.get_tree().get_nodes_in_group("missiles").size() - before
				if phase == 0:
					fired_masked = shots
				else:
					fired_clear = shots
			print("[mask] battery launches: behind the ridge=%d (expect 0), over it=%d (expect 1)" % [
				fired_masked, fired_clear])
			# the ship's own acquisition, from her masthead over open water
			var sh := Ship.new()
			sh.setup("destroyer", 1)
			world.add_child(sh)
			var sea := world.fleet_yard.deep_water(Vector3(26000.0, 0.0, 2000.0))
			sh.global_position = Vector3(sea.x, Sim.sea_surface(sea.x, sea.z), sea.z)
			sh.ai = false
			# walk inland and find the highest ground on that bearing
			var peak := Vector3.ZERO
			var peak_h := -1e9
			var peak_t := 0.0
			for k in 220:
				var t := float(k) * 90.0
				var q := Vector3(sea.x - t, 0.0, sea.z)
				var hh := Sim.height_at(q.x, q.z)
				if hh > peak_h:
					peak_h = hh
					peak = q
					peak_t = t
			var behind := Vector3(peak.x - 3000.0, 0.0, peak.z)
			var ship_masked := 0
			var ship_clear := 0
			for phase2 in 2:
				var py: float = (peak_h + 3000.0) if phase2 == 1 \
					else (Sim.height_at(behind.x, behind.z) + 60.0)
				world.player.global_position = Vector3(behind.x, py, behind.z)
				world._reset_interp(world.player)
				sh.vls_cd = 0.0
				var before2 := world.get_tree().get_nodes_in_group("missiles").size()
				if sh._pick_air() == world.player:
					sh.fire_vls(world.player)
				var shots2: int = world.get_tree().get_nodes_in_group("missiles").size() - before2
				if phase2 == 0:
					ship_masked = shots2
				else:
					ship_clear = shots2
			print("[mask] ship at %s, ridge %.0f m at %.1f km inland, player %.1f km beyond it" % [
				str(Vector2(sea.x, sea.z).round()), peak_h, peak_t * 0.001, 3.0])
			print("[mask] ship launches: player behind the ridge=%d (expect 0), above it=%d (expect 1)" % [
				ship_masked, ship_clear])
			# And a round already in the air: duck behind the ridge and it should
			# lose the track rather than fly through the hill. Built on its own
			# rather than borrowed from the engagement above — the rounds fired
			# there go off almost immediately at these ranges, and a detonated
			# missile answers every question with whatever it last held.
			var probe := Missile.new()
			# Low, and close in on the seaward side: a round at five thousand
			# metres looks down over a ridge and is not masked by it at all,
			# which is correct and makes for a useless test.
			var launch_at := Vector3(peak.x + 2400.0, peak_h - 450.0, peak.z)
			world.player.global_position = Vector3(behind.x, peak_h + 3000.0, behind.z)
			world._reset_interp(world.player)
			var pdir := (world.player.global_position - launch_at).normalized()
			probe.launch("sm2", Transform3D(Basis.looking_at(pdir, Vector3.UP), launch_at),
				pdir * 300.0, null, world.player)
			world.add_child(probe)
			for _i in 48:                      # kept short: it is under boost
				probe._physics_process(1.0 / 120.0)
			var probe_before: bool = probe.target == world.player
			# now down behind the ridge
			world.player.global_position = Vector3(behind.x,
				Sim.height_at(behind.x, behind.z) + 60.0, behind.z)
			world._reset_interp(world.player)
			for _i in 300:
				if probe.dead:
					break
				probe._physics_process(1.0 / 120.0)
			var probe_after: bool = probe.target == world.player
			mask_seeker_ok = probe_before and not probe_after and not probe.dead
			print("[mask] seeker: holding with a clear line=%s, still holding once masked=%s (round %.0f m up, its line to you clear=%s, detonated=%s)" % [
				str(probe_before), str(probe_after), probe.global_position.y,
				str(Sim.line_of_sight(probe.global_position, world.player.global_position)),
				str(probe.dead)])
			if is_instance_valid(probe):
				probe.queue_free()
			print("[mask] RESULT: %s" % ("ok" if not got_masked and got_clear \
				and not paint_masked and paint_clear \
				and fired_masked == 0 and fired_clear > 0 \
				and ship_masked == 0 and ship_clear > 0 \
				and mask_seeker_ok else "FAILED"))
			world.get_tree().quit()

## What the radar page would draw for one contact: the same masking test the
## scope itself applies.
func _radar_paints(n: Node3D) -> bool:
	if not is_instance_valid(world.player) or not is_instance_valid(n):
		return false
	var d := world.player.global_position.distance_to(n.global_position)
	if d > Sim.radar_range():
		return false
	return d <= 2000.0 or Sim.line_of_sight(world.player.global_position + Vector3(0, 4, 0),
		n.global_position + Vector3(0, 4, 0))
#endregion


#region --splashtest
var _splash_test := false
var _splash_t := 0.0
var _splash_step := 0
var _splash_aim := Vector3.INF
var _splash_hit := Vector3.INF
var _splash_r := 0.0

# A bomb into open water: is the fireball anywhere a player could see it.
func tick_splash(delta: float) -> bool:
	if _splash_test and is_instance_valid(world.player):
		_splash_t += delta
		if _splash_t > 2.0 and _splash_step == 0:
			_splash_step = 1
			var sea := world.fleet_yard.deep_water(Vector3(26000.0, 0.0, 3000.0))
			world.player.global_transform = Transform3D(Basis(),
				Vector3(sea.x, Sim.sea_at(sea.x, sea.z + 2600.0) + 1400.0, sea.z + 2600.0))
			world.player.linear_velocity = Vector3(0, 0, -230.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			# the shipping stands down, so the only thing going off out here is
			# the bomb rather than somebody's five inch practice
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
			# lase the water, the way a pilot would: without the pod running,
			# `designated` is cleared every frame and the bomb leaves unguided
			# Deliberately NOT lased. A bomb that reaches the water with nothing
			# to detonate on is the case that was broken: it falls through the
			# proximity fuse to the terminal water check, and that is where the
			# fireball used to be drawn under the sea.
			if world.pod.active:
				world.pod.toggle()
			_splash_aim = Vector3(sea.x, Sim.sea_at(sea.x, sea.z), sea.z)
			world.player.locked = true
			if not harness._arm_with("gbu32"):
				world.get_tree().quit()
				return true
			world.player.fire_cd = 0.0
			Sim.last_burst = Vector3.INF
			world._reset_interp.call_deferred(world.player)
			print("[splash] aiming at open water %s, sea level %.0f" % [
				str(world.player.designated.round()), Sim.sea_at(world.player.designated.x,
				world.player.designated.z)])
		elif _splash_t > 4.5 and _splash_step == 1:
			_splash_step = 2
			print("[splash] release: %s" % ("away" if world.player.fire() == "" else "refused"))
		elif _splash_step == 2:
			# latch the burst that belongs to this bomb, not whatever else in the
			# world happened to go off last
			if Sim.last_burst != Vector3.INF \
					and Sim.last_burst.distance_to(_splash_aim) < 2500.0:
				_splash_hit = Sim.last_burst
				_splash_r = Sim.last_burst_r
			if _splash_t < 40.0:
				return true
			_splash_test = false
			Sim.last_burst = _splash_hit
			Sim.last_burst_r = _splash_r
			if Sim.last_burst == Vector3.INF:
				print("[splash] RESULT: FAILED — nothing ever went off")
			else:
				# Against the sea where the burst actually was. The ocean is a
				# shell: measuring a splash twenty-six kilometres offshore
				# against the level at the origin makes a fireball sitting
				# neatly on the surface look fifty metres under it.
				var above: float = Sim.last_burst.y - Sim.sea_at(
					Sim.last_burst.x, Sim.last_burst.z)
				print("[splash] last fireball at %s, radius %.0f — %.1f m %s the surface" % [
					str(Sim.last_burst.round()), Sim.last_burst_r, absf(above),
					"above" if above >= 0.0 else "BELOW"])
				# and the reason it was invisible in the first place: the sea is
				# a transparent mesh sixty kilometres across, so it has to be
				# told to sort behind everything drawn at the surface
				var sea_pri := -99
				var boom_pri := -99
				for n in world.terrain.get_children():
					if n.name == "Water" and n is MeshInstance3D:
						var wm := (n as MeshInstance3D).material_override as StandardMaterial3D
						if wm != null:
							sea_pri = wm.render_priority
				var probe := Effects.Boom.new()
				world.add_child(probe)
				boom_pri = probe._mat.render_priority
				probe.queue_free()
				print("[splash] render order: sea %d, explosion %d (sea must be lower)" % [
					sea_pri, boom_pri])
				print("[splash] RESULT: %s" % ("ok" if above >= -0.5 \
					and sea_pri < boom_pri else "FAILED"))
			world.get_tree().quit()
	return false
#endregion


#region --tfrtest= --tfrveh --tfrrange= --tfrtest
var _tfr_test := false
var _tfr_range := 0.0
var _tfr_veh := false
var _tfr_kind := "tel_kalibr"

# Does a cruise round actually follow the ground, or does it fly into the
# first hill it meets? Asked on its own, with nothing else shooting: in a
# live mission the round was being destroyed in flight by friendly air
# defence, which looks identical from the outside and is not the same fault.
func tick_tfr() -> bool:
	if _tfr_test:
		_tfr_test = false
		var boat: Ship = null
		for sh in world.get_tree().get_nodes_in_group("ships"):
			if is_instance_valid(sh):
				boat = sh
				break
		var mark: Vector3 = boat.global_position if is_instance_valid(boat) \
			else world.fleet_yard.fleet_anchor
		# Against a vehicle instead of a ship. A cluster round scatters
		# submunitions over an area, and whether that works against something
		# ten metres long sitting on the ground is a different question from
		# whether it works against a hundred and fifty metres of hull at sea.
		var foe: Node3D = boat
		if _tfr_veh:
			# On land. The ship the mark comes from is at sea, so putting a tank
			# four hundred metres from it put it in the water, where it sank --
			# and a round whose target vanishes is a different test from a round
			# shooting at a vehicle.
			var spot := Vector2(mark.x, mark.z)
			for ring in 60:
				var probe := Vector2(mark.x - float(ring) * 600.0, mark.z)
				if Sim.height_at(probe.x, probe.y) > Sim.sea_at(probe.x, probe.y) + 8.0:
					spot = probe
					break
			var gy: float = Sim.height_at(spot.x, spot.y)
			var quarry := world._spawn_tank(Vector3(spot.x, gy, spot.y),
				0.0, 1, "t72")
			quarry.ai = false
			foe = quarry
			mark = quarry.global_position
		var from := Vector3(-34000.0, 0.0, 6000.0)
		# A shot can be short as well as long, and the two are not the same
		# problem: over sixty kilometres a round has time to climb, cruise and
		# let down, and over twenty-five it has to do all three at once.
		if _tfr_range > 0.0:
			var away := Vector3(from.x - mark.x, 0.0, from.z - mark.z).normalized()
			from = mark + away * _tfr_range
			from.y = 0.0
		var t := world._spawn_tank(from, 0.0, 0, _tfr_kind)
		t.ai = false
		await world.get_tree().physics_frame
		t.map_lock = foe
		t.map_target = mark
		var hp0: float = foe.health if is_instance_valid(foe) else 0.0
		print("[cruise] %s at %s, target %s, %.1f km apart" % [_tfr_kind,
			str(Vector2(from.x, from.z).round()), str(Vector2(mark.x, mark.z).round()),
			Vector2(mark.x - from.x, mark.z - from.z).length() * 0.001])
		var waited := 0
		while t._erect < 0.97 and waited < 1200:
			await world.get_tree().physics_frame
			waited += 1
		t._gun_cd = 0.0
		print("[cruise] launch: %s" % str(t.fire_main(world)))
		var shot: Missile = null
		var near := 1e18
		var want_id := String(VehicleSpec.KINDS[_tfr_kind]["missile"])
		for m in world.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m) and String(m.wid) == want_id:
				var d: float = (m as Node3D).global_position.distance_to(t.global_position)
				if d < near:
					near = d
					shot = m
		if shot == null:
			print("[cruise] nothing left the rail")
			print("[cruise] RESULT: FAILED")
			world.get_tree().quit()
			return true
		var worst_clear := 1e18
		var worst_at := Vector3.ZERO
		var lived := 0
		var closed := 1e18
		var closed3 := 1e18
		var high_at := 0.0
		# Six minutes. A subsonic cruise missile holds Mach 0.8, so sixty
		# kilometres is four minutes in the air -- cutting the clock at two
		# called a round that was tracking perfectly a failure.
		for f in 43200:
			await world.get_tree().physics_frame
			if not is_instance_valid(shot):
				# A cluster round stops existing halfway down on purpose: the
				# bus opens and eight submunitions carry on without it. Follow
				# whichever of them is nearest the target, or the test scores
				# the load's release point as the miss distance -- eighteen
				# kilometres short and twelve up, for a weapon that was doing
				# exactly what it is supposed to.
				var heir: Missile = null
				var heir_d := 1e18
				var aim_at: Vector3 = foe.global_position \
					if is_instance_valid(foe) else mark
				for m2 in world.get_tree().get_nodes_in_group("missiles"):
					if not is_instance_valid(m2):
						continue
					var dd2: float = (m2 as Node3D).global_position.distance_to(aim_at)
					if dd2 < heir_d:
						heir_d = dd2
						heir = m2
				if heir == null:
					break
				shot = heir
			lived = f
			var p: Vector3 = shot.global_position
			var g: float = maxf(Sim.height_at(p.x, p.z), Sim.sea_at(p.x, p.z))
			var clear: float = p.y - g
			if clear < worst_clear:
				worst_clear = clear
				worst_at = p
			# against where the ship *is*, not where it was when we fired
			var now_at: Vector3 = foe.global_position if is_instance_valid(foe) \
				else mark
			closed = minf(closed, Vector2(p.x - now_at.x, p.z - now_at.z).length())
			# In three dimensions. Measured in plan a round that crossed the
			# ship five hundred metres overhead read as a ten metre miss, and
			# a profile that never got down was scored as tracking perfectly.
			var sep: float = p.distance_to(now_at)
			if sep < closed3:
				closed3 = sep
				high_at = p.y - now_at.y
			if f % 1200 == 0:
				print("[cruise]   t=%5.1f s  alt %6.0f  ground %6.0f  clear %5.0f  %5.1f km to run  vy %6.0f  spd %5.0f  at %s" % [
					float(f) / 120.0, p.y, g, clear, closed * 0.001,
					shot.vel.y, shot.vel.length(),
					(String(shot.target.name) if is_instance_valid(shot.target) else "NOTHING")])
		print("[cruise] flew %.1f s, closest to the mark %.2f km in plan, %.0f m in all" % [
			float(lived) / 120.0, closed * 0.001, closed3])
		print("[cruise] at that point it was %.0f m above the target" % high_at)
		print("[cruise] least ground clearance %.1f m at %s" % [
			worst_clear, str(worst_at.round())])
		var hurt: float = hp0 - (foe.health if is_instance_valid(foe) else 0.0)
		print("[cruise] the target took %.0f damage of %.0f (%s)" % [hurt, hp0,
			"hit" if hurt > 0.0 else "MISS"])
		# Damage alone is not proof: there is a battle going on and the ship
		# takes hits from other people. The round has to have arrived.
		# A hit is arriving *at* the target, not over the top of it.
		print("[cruise] RESULT: %s" % ("ok" if closed3 < 120.0 and hurt > 0.0
			else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --cruiseland
var _land_test := false
var _land_t := 0.0
var _land_tgt: Node3D = null
var _land_step := 0
var _land_low := 1e9
var _land_lowat := Vector3.ZERO
var _land_close := 1e9

# A cruise weapon fired across high ground. Over the sea the terrain
# following never has to do anything; inland it is the whole job.
func tick_land(delta: float) -> bool:
	if _land_test and (is_instance_valid(world.player) or _land_step > 0):
		_land_t += delta
		if _land_t > 2.0 and _land_tgt == null:
			# something inland, with real ground between it and the launcher
			# The AI sites all sit near the field, which is in a valley the
			# height field deliberately caps. Put a target on the high ground
			# instead, so the run in has to cross something.
			var best_rise := -1.0
			var spot := Vector2.ZERO
			for gi in 40:
				for gj in 40:
					var q := Vector2(-18000.0 + float(gi) * 900.0,
						-18000.0 + float(gj) * 900.0)
					var rise: float = Sim.height_at(q.x, q.y)
					if rise > best_rise:
						best_rise = rise
						spot = q
			_land_tgt = world._spawn_tank(Vector3(spot.x, 0.0, spot.y), 0.0, 1, "t90")
			var tp: Vector3 = _land_tgt.global_position
			# launch from over the sea, so the run in crosses the coast and
			# whatever stands behind it
			# from the sea, at cruise height, so the whole run in is over land
			var from := Vector3(tp.x + 26000.0, 2400.0, tp.z)
			world.player.global_transform = Transform3D(Basis(), from)
			world.player.linear_velocity = Vector3(-250.0, 0, 0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			world.player.target = _land_tgt
			world.player.locked = true
			if not harness._arm_with("agm84"):
				_land_test = false
				world.get_tree().quit()
				return true
			world.player.fire_cd = 0.0
			world._reset_interp.call_deferred(world.player)
			# the highest ground on the line between the two
			var ridge := -1e9
			for k in 60:
				var q: Vector3 = from.lerp(tp, float(k) / 59.0)
				ridge = maxf(ridge, Sim.height_at(q.x, q.z))
			print("[land] %s at %s, ground there %.0f m; launcher 26 km out at 3000 m" % [
				Sim.label_of(_land_tgt), str(tp.round()), Sim.height_at(tp.x, tp.z)])
			print("[land] highest ground on the run in: %.0f m" % ridge)
		elif _land_tgt != null and _land_step == 0 and _land_t > 4.0:
			_land_step = 1
			var why: String = world.player.fire()
			print("[land] release: %s" % ("away" if why == "" else "refused — " + why))
		elif _land_step == 1:
			var live := 0
			if _land_t < 8.0 and fmod(_land_t, 1.0) < delta:
				for m in world.get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(m) and String(m.wid) == "agm84":
						print("[land]   t=%.1f target=%s kind=%s alt=%.0f agl=%.0f spd=%.0f" % [
							_land_t, Sim.label_of(m.target), String(m.ws.get("kind", "?")),
							(m as Node3D).global_position.y,
							(m as Node3D).global_position.y - maxf(Sim.height_at(
								(m as Node3D).global_position.x,
								(m as Node3D).global_position.z), Sim.sea_at(
								(m as Node3D).global_position.x,
								(m as Node3D).global_position.z)),
							(m.get_velocity() as Vector3).length()])
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "agm84":
					continue
				live += 1
				var mp: Vector3 = (m as Node3D).global_position
				var agl: float = mp.y - maxf(Sim.height_at(mp.x, mp.z), Sim.sea_at(mp.x, mp.z))
				if agl < _land_low:
					_land_low = agl
					_land_lowat = mp
				if is_instance_valid(_land_tgt):
					_land_close = minf(_land_close,
						mp.distance_to(_land_tgt.global_position))
			if live == 0 and _land_t > 12.0 or _land_t > 220.0:
				_land_test = false
				print("[land] lowest the round ever got: %.1f m above the ground, at %s" % [
					_land_low, str(_land_lowat.round())])
				print("[land] closest it came to the target: %.0f m; target alive=%s" % [
					_land_close, str(is_instance_valid(_land_tgt)
						and (not _land_tgt.has_method("is_alive") or _land_tgt.is_alive()))])
				print("[land] RESULT: %s" % ("ok" if _land_close < 40.0 and _land_low > 0.0
					else "FAILED — it hit the ground short" if _land_low <= 0.0
					else "FAILED — never arrived"))
				world.get_tree().quit()
		return true
	return false
#endregion


#region --reachtest
var _reach_test := false

# What each weapon can actually get to, against what its entry claims.
func tick_reach() -> bool:
	if _reach_test and is_instance_valid(world.player):
		_reach_test = false
		var alt := 3000.0
		var spd := 250.0
		var here := Vector3(0.0, alt, 0.0)
		var v0 := Vector3(0, 0, -spd)
		print("[reach] launched at %.0f m doing %.0f m/s, target on the deck" % [alt, spd])
		for w in ["agm65", "agm84", "agm88", "aim9", "aim120", "sm2"]:
			var ws := WeaponSpec.get_spec(w)
			var claim: float = float(ws["range"])
			# walk out until it can no longer make it
			var made := 0.0
			var d := 500.0
			while d < claim * 1.2:
				var tgt := Vector3(0, Sim.height_at(0.0, -d), -d)
				if WeaponSpec.can_reach(w, here, v0, tgt):
					made = d
				d += 500.0
			print("[reach] %-7s claims %5.1f km, actually gets to %5.1f km (%.0f%% of the claim)" % [
				w, claim * 0.001, made * 0.001, 100.0 * made / maxf(claim, 1.0)])
		world.get_tree().quit()
		return true
	return false
#endregion


#region --wavetest
## A tactical nuclear bomb against what it is actually dropped on: a group of
## armour and installations on the ground, locked, rather than a strategic round
## at a town. "It goes off over them and they are still there" is a question
## about where the burst happens and what the blast is allowed to reach.
## What the fleet actually does with its tubes. "Friendly ships launching loads
## of interceptors at nothing, and in the wrong direction" is two numbers: how
## many rounds go up, and how close they ever get to what they were sent at.
## Does the autopilot actually hold what it says it holds, and does the orbit go
## round the way it was asked to?
## Can a launcher on the ground actually reach something in orbit, and does
## killing it take it off the plot? A hundred and eighteen kilometres straight
## up is a very different shot from anything else in this game.
## Do the new air defence vehicles actually engage an aeroplane? A battery that
## erects and never fires, or a gun that cannot elevate onto a target, is worse
## than not having one.
## The support systems: taking fuel from a tanker, being rearmed on the ground,
## and whether an early warning aircraft or a reconnaissance satellite actually
## widens the picture. All three had an object in the world and nothing behind
## it until now.
## Lowering a tracked vehicle's lateral resistance so it can actually turn has
## an obvious risk on the other side: a tank that slides down every hill it is
## parked on. This measures that directly.
## Does the hover actually hold the machine? Not "does the number stop moving"
## — put the helicopter somewhere with a shove on and a bank on and see whether
## it comes back to level, stops drifting and stays at the height it was given.
## A shoulder-launched team is defined by the envelope it does NOT cover: it
## has to punish an aeroplane down in the weeds and be useless against one that
## has climbed out of reach. Both halves are the test.
## Handing over the conn should put you on the deck on your own feet, not in
## somebody else's aeroplane.
## Do the hulls ride the sea that is actually drawn? Two things have to hold:
## the ship sits on the swell rather than through it, and a short hull feels it
## more than a long one.
var _wave_test := false
var _wave_t := 0.0
var _wave_ships: Array = []
var _wave_err := 0.0
var _wave_pitch: Dictionary = {}

# The strategic round: aimed on the map, off the rail, up and over, down on
# the mark. It was reported as exploding the moment it launched.
# Not gated on the player surviving: if the air defence works, the aeroplane
# it is shooting at may well not be there at the end, and a harness that
# stops running when its target dies never reports anything.
func tick_wave(delta: float) -> bool:
	if _wave_test:
		_wave_t += delta
		if _wave_t > 2.5 and _wave_ships.is_empty():
			for k in ["patrol", "corvette", "destroyer", "lhd"]:
				var sv3 := Ship.new()
				sv3.setup(k, 0)
				sv3.ai = false
				world.add_child(sv3)
				var at3 := world.fleet_yard.deep_water(Vector3(26000.0 + float(_wave_ships.size())
					* 900.0, 0.0, 1200.0))
				# On the water, not at the mean level of it: spawned at `sea_at`
				# a hull starts up to a swell's amplitude off the surface and
				# stays there until its first physics tick. Under load this test
				# measured that gap and read 1.65 m of it as ships failing to
				# ride the sea.
				sv3.global_position = Vector3(at3.x,
					Sim.sea_surface(at3.x, at3.z), at3.z)
				_wave_ships.append(sv3)
				_wave_pitch[k] = 0.0
		elif not _wave_ships.is_empty() and _wave_t < 26.0:
			for sv4 in _wave_ships:
				if not is_instance_valid(sv4):
					continue
				var sp: Vector3 = (sv4 as Node3D).global_position
				# where the drawn surface is under her, against where she is
				var want: float = Sim.sea_surface(sp.x, sp.z)
				_wave_err = maxf(_wave_err, absf(sp.y - want))
				var kk: String = (sv4 as Ship).kind
				_wave_pitch[kk] = maxf(float(_wave_pitch[kk]),
					absf(rad_to_deg((sv4 as Node3D).rotation.x)))
		elif _wave_t >= 26.0:
			_wave_test = false
			var line := PackedStringArray()
			for kk2 in _wave_pitch:
				line.append("%s %.1f deg" % [String(kk2), float(_wave_pitch[kk2])])
			print("[wave] worst pitch: %s" % ", ".join(line))
			print("[wave] worst gap between a hull and the drawn surface: %.2f m" % _wave_err)
			# She must sit ON it, and a short hull must feel it more than a long
			# one — otherwise the sea is decoration.
			var small: float = float(_wave_pitch.get("patrol", 0.0))
			var big: float = float(_wave_pitch.get("lhd", 0.0))
			var ok: bool = _wave_err < 0.6 and small > big * 1.4 and small > 1.0
			print("[wave] RESULT: %s" % ("ok" if ok else
				"FAILED — the hulls are not riding the sea that is drawn"))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --manpadstest
var _mp_test := false
var _mp_t := 0.0
var _mp_step := 0
var _mp_site: GroundTarget = null
var _mp_low := 0
var _mp_high := 0

func tick_mp(delta: float) -> bool:
	if _mp_test and is_instance_valid(world.player):
		_mp_t += delta
		match _mp_step:
			0:
				if _mp_t > 2.5:
					_mp_step = 1
					_mp_t = 0.0
					var at := Vector3(600.0, 0.0, -2600.0)
					_mp_site = GroundTarget.new()
					_mp_site.team = 1
					_mp_site.setup("manpads")
					world.add_child(_mp_site)
					_mp_site.global_position = Vector3(at.x,
						Sim.height_at(at.x, at.z), at.z)
					# down in the weeds, right over the top of it
					world.player.global_transform = Transform3D(Basis(),
						Vector3(at.x, Sim.height_at(at.x, at.z) + 320.0, at.z + 1400.0))
					world.player.linear_velocity = Vector3(0, 0, -170.0)
					world.player.gear_down = false
					world.player.gear_anim = 0.0
					world._reset_interp.call_deferred(world.player)
					print("[manpads] team in, aeroplane at %d m agl" % int(world.player.agl))
			1:
				# hold it low across the site
				world.player.global_position.y = Sim.height_at(world.player.global_position.x,
					world.player.global_position.z) + 320.0
				for m in world.get_tree().get_nodes_in_group("missiles"):
					if m is Missile and String(m.wid) == "manpads":
						_mp_low = maxi(_mp_low, 1)
				if _mp_t > 16.0:
					_mp_step = 2
					_mp_t = 0.0
					# now climb out of its envelope and go round again
					world.player.global_transform = Transform3D(Basis(),
						Vector3(_mp_site.global_position.x,
							Sim.height_at(_mp_site.global_position.x,
								_mp_site.global_position.z) + 3400.0,
							_mp_site.global_position.z + 1400.0))
					world.player.linear_velocity = Vector3(0, 0, -170.0)
					world._reset_interp.call_deferred(world.player)
					for m2 in world.get_tree().get_nodes_in_group("missiles"):
						if m2 is Missile and String(m2.wid) == "manpads":
							(m2 as Node).queue_free()
			2:
				world.player.global_position.y = Sim.height_at(world.player.global_position.x,
					world.player.global_position.z) + 3400.0
				for m3 in world.get_tree().get_nodes_in_group("missiles"):
					if m3 is Missile and String(m3.wid) == "manpads":
						_mp_high += 1
				if _mp_t > 16.0:
					_mp_test = false
					print("[manpads] at 320 m agl: %s" % (
						"engaged" if _mp_low > 0 else "did not shoot"))
					print("[manpads] at 3400 m agl: %s" % (
						"engaged" if _mp_high > 0 else "did not shoot"))
					var ok: bool = _mp_low > 0 and _mp_high == 0
					print("[manpads] RESULT: %s" % ("ok" if ok else
						"FAILED — the envelope is wrong"))
					world.get_tree().quit()
		return true
	return false
#endregion


#region --asattest
var _asat_test := false
var _asat_t := 0.0
var _asat_step := 0
var _asat_veh: Tank = null
var _asat_tgt: Node = null
var _asat_top := 0.0
var _asat_gap := 1e9

func tick_asat(delta: float) -> bool:
	if _asat_test:
		_asat_t += delta
		if _asat_step == 0 and _asat_t > 2.5:
			_asat_step = 1
			var here := Vector3(1200.0, 0.0, -1800.0)
			_asat_veh = world._spawn_tank(here, 0.0, 0, "asat_usa")
			_asat_veh.ai = true
			var sats := world.get_tree().get_nodes_in_group("satellites")
			# Assign the FURTHEST hostile one, which is the shot the round has
			# to be sized for. Left to itself the crew takes the nearest, and
			# passing on the easy shot says nothing about the hard one.
			var far_sat: Node = null
			var fd := 0.0
			for sx in sats:
				if not is_instance_valid(sx) or not (sx is Node3D):
					continue
				if ("team" in sx) and int(sx.team) == 0:
					continue
				var dd: float = here.distance_to((sx as Node3D).global_position)
				if dd > fd:
					fd = dd
					far_sat = sx
			Sim.sat_target = far_sat
			print("[asat] %s on the pad; %d satellite(s) in orbit; assigned %s at %.0f km" % [
				_asat_veh.display_name(), sats.size(),
				Sim.label_of(far_sat) if is_instance_valid(far_sat) else "-",
				fd * 0.001])
		elif _asat_step == 1 and _asat_t > 5.0:
			if not is_instance_valid(_asat_veh):
				print("[asat] the launcher is gone")
				_asat_test = false
				world.get_tree().quit()
				return true
			# it stands its tube up on its own, then sends the round
			if _asat_veh.rounds_left <= 0:
				_asat_step = 2
				_asat_t = 0.0
				for m in world.get_tree().get_nodes_in_group("missiles"):
					if m is Missile and String(m.wid) == "asat":
						_asat_tgt = m.get("target")
				print("[asat] round away at %s" % [
					Sim.label_of(_asat_tgt) if is_instance_valid(_asat_tgt) else "?"])
			elif _asat_t > 60.0:
				print("[asat] the launcher never fired (erect %.2f, rounds %d)" % [
					_asat_veh._erect, _asat_veh.rounds_left])
				print("[asat] RESULT: FAILED — it would not shoot")
				_asat_test = false
				world.get_tree().quit()
		elif _asat_step == 2:
			var live := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not (m is Missile) or String(m.wid) != "asat":
					continue
				live += 1
				var mp: Vector3 = (m as Node3D).global_position
				_asat_top = maxf(_asat_top, mp.y)
				if is_instance_valid(_asat_tgt):
					_asat_gap = minf(_asat_gap,
						mp.distance_to((_asat_tgt as Node3D).global_position))
			if (live == 0 and _asat_t > 6.0) or _asat_t > 260.0:
				_asat_test = false
				var killed: bool = not is_instance_valid(_asat_tgt)
				print("[asat] the round reached %.0f km up and passed %.0f m from the satellite" % [
					_asat_top * 0.001, _asat_gap])
				print("[asat] target %s" % ("destroyed" if killed else "still in orbit"))
				print("[asat] RESULT: %s" % ("ok" if killed else
					"FAILED — the round could not reach it"))
				world.get_tree().quit()
		return true
	return false
#endregion


#region --tacnukesea --tacnukenociws --tacnuke
var _tacnuke := false
var _tacnuke_t := 0.0
var _tacnuke_step := 0
var _tacnuke_mob: Array = []
var _tacnuke_at := Vector3.INF
## The round itself, and where it was on the last frame it existed — which is
## where it went off. "It bursts over them" is a height above the ground, so the
## harness has to report that rather than whatever exploded most recently.
## Against shipping instead of armour, which is what the round was actually
## being used on.
var _tacnuke_sea := false
## Whether the squadron is allowed to defend itself. A close-in weapon system
## that shoots the round down before it arrives is a perfectly good answer to
## being bombed, and it has to be ruled in or out before anything else about
## the burst means much.
var _tacnuke_ciws_off := false
var _tacnuke_round: Node = null
var _tacnuke_burst := Vector3.INF
var _tacnuke_fall := 0.0

# A tactical nuke onto a locked group on the ground.
func tick_tacnuke(delta: float) -> bool:
	if _tacnuke and (is_instance_valid(world.player) or _tacnuke_step >= 2):
		_tacnuke_t += delta
		if _tacnuke_step == 0 and _tacnuke_t > 2.5:
			_tacnuke_step = 1
			# a company of armour and a few installations, in a 600 m box: well
			# inside the 1400 m the round claims
			var here: Vector3 = world.player.global_position
			_tacnuke_at = Vector3(here.x, 0.0, here.z - 6000.0)
			_tacnuke_at.y = Sim.height_at(_tacnuke_at.x, _tacnuke_at.z)
			if _tacnuke_sea:
				# A squadron in company: five hulls inside six hundred metres,
				# which is well inside the round's own 1400 m lethal radius.
				var sea := world.fleet_yard.deep_water(Vector3(26000.0, 0.0, 2400.0))
				_tacnuke_at = Vector3(sea.x, Sim.sea_at(sea.x, sea.z), sea.z)
				for other in world.get_tree().get_nodes_in_group("ships"):
					var ov := other as Ship
					if ov != null:
						ov.ai = false
						ov.cells_left = 0
						ov.ciws_enabled = false
				var fleet := ["destroyer", "type45", "frigate", "corvette", "patrol"]
				for i2 in fleet.size():
					var a3 := TAU * float(i2) / float(fleet.size())
					var off3 := Vector3(cos(a3), 0, sin(a3)) * (120.0 + float(i2) * 90.0)
					var sh3 := Ship.new()
					sh3.setup(fleet[i2], 1)
					sh3.ai = false
					sh3.cells_left = 0
					sh3.ciws_enabled = not _tacnuke_ciws_off
					world.add_child(sh3)
					sh3.global_position = Vector3(_tacnuke_at.x + off3.x, Sim.sea_surface(_tacnuke_at.x + off3.x, _tacnuke_at.z + off3.z), _tacnuke_at.z + off3.z)
					_tacnuke_mob.append(sh3)
				world.player.global_transform = Transform3D(Basis(),
					_tacnuke_at + Vector3(0, 2400.0, 7000.0))
				world.player.linear_velocity = Vector3(0, 0, -240.0)
				world.player.gear_down = false
				world.player.gear_anim = 0.0
				world.player.set_bays(true)
				for k3 in world.player.bays:
					world.player.bays[k3]["anim"] = 1.0
					world.player.bays[k3]["open"] = true
				if not harness._arm_with("b61"):
					_tacnuke = false
					world.get_tree().quit()
					return true
				world._reset_interp.call_deferred(world.player)
				print("[tacnuke] %d hull(s) in company around %s" % [
					_tacnuke_mob.size(), str(_tacnuke_at.round())])
				return true
			for i in 8:
				var a := TAU * float(i) / 8.0
				var off := Vector3(cos(a), 0, sin(a)) * (120.0 + float(i) * 55.0)
				var t := world._spawn_tank(_tacnuke_at + off, a, 1,
					Tank.pick_kind("mbt" if i % 2 == 0 else "lav", 1, i))
				_tacnuke_mob.append(t)
			for j in 4:
				var a2 := TAU * float(j) / 4.0 + 0.7
				var off2 := Vector3(cos(a2), 0, sin(a2)) * (200.0 + float(j) * 90.0)
				var g := GroundTarget.new()
				g.team = 1
				g.setup(["sam", "radar", "fuel", "hangar"][j])
				world.add_child(g)
				g.global_position = Vector3(_tacnuke_at.x + off2.x,
					Sim.height_at(_tacnuke_at.x + off2.x, _tacnuke_at.z + off2.z),
					_tacnuke_at.z + off2.z)
				_tacnuke_mob.append(g)
			# put the aeroplane on a run at them with the round selected
			world.player.global_transform = Transform3D(Basis(),
				_tacnuke_at + Vector3(0, 2400.0, 7000.0))
			world.player.linear_velocity = Vector3(0, 0, -240.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			if not harness._arm_with("b61"):
				_tacnuke = false
				world.get_tree().quit()
				return true
			world._reset_interp.call_deferred(world.player)
			print("[tacnuke] %d units laid out around %s" % [
				_tacnuke_mob.size(), str(_tacnuke_at.round())])
		elif _tacnuke_step == 1 and _tacnuke_t > 6.0:
			_tacnuke_step = 2
			# lock the nearest of them, which is what a pilot would do
			var pick: Node3D = null
			var best := 1e9
			for u in _tacnuke_mob:
				if not is_instance_valid(u):
					continue
				var d: float = world.player.global_position.distance_to(
					(u as Node3D).global_position)
				if d < best:
					best = d
					pick = u
			world.player.target = pick
			world.player.locked = true
			world.player.fire_cd = 0.0
			print("[tacnuke] locked %s at %.0f m; release: %s" % [
				Sim.label_of(pick), best,
				"away" if world.player.fire() == "" else "REFUSED"])
			for n in world.get_tree().get_nodes_in_group("missiles"):
				if n is Missile and (n as Missile).shooter == world.player:
					_tacnuke_round = n
		elif _tacnuke_step == 2 and is_instance_valid(_tacnuke_round) \
				and _tacnuke_t <= 110.0:
			_tacnuke_burst = (_tacnuke_round as Node3D).global_position
			_tacnuke_fall = float(_tacnuke_round.get("age"))
		elif _tacnuke_step == 2 and _tacnuke_t > 110.0:
			_tacnuke = false
			var alive_n := 0
			var far := 0.0
			for u in _tacnuke_mob:
				if is_instance_valid(u) and u.has_method("is_alive") and u.is_alive():
					alive_n += 1
					far = maxf(far, (u as Node3D).global_position.distance_to(_tacnuke_at))
			print("[tacnuke] %d of %d still alive; the furthest one was %.0f m from the aiming point" % [
				alive_n, _tacnuke_mob.size(), far])
			print("[tacnuke] the round went off at %s — %.0f m above the ground, %.0f m from the aiming point, after %.0f s of flight" % [
				str(_tacnuke_burst.round()) if _tacnuke_burst != Vector3.INF else "nowhere",
				(_tacnuke_burst.y - Sim.height_at(_tacnuke_burst.x, _tacnuke_burst.z))
				if _tacnuke_burst != Vector3.INF else -1.0,
				_tacnuke_burst.distance_to(_tacnuke_at)
				if _tacnuke_burst != Vector3.INF else -1.0, _tacnuke_fall])
			# A nuclear round that goes off hundreds of metres up and a mile
			# short has failed even if something else sank the target while it
			# was in the air.
			var high: float = (_tacnuke_burst.y - maxf(Sim.height_at(
				_tacnuke_burst.x, _tacnuke_burst.z), Sim.sea_at(
				_tacnuke_burst.x, _tacnuke_burst.z))) \
				if _tacnuke_burst != Vector3.INF else 1e9
			var wide: float = _tacnuke_burst.distance_to(_tacnuke_at) \
				if _tacnuke_burst != Vector3.INF else 1e9
			# Two different right answers. Against a squadron that is allowed
			# to defend itself, the round being shot down short is a win for
			# the ships and the warhead must not go off — so what is checked
			# there is that nothing took nuclear damage, not that everything
			# died. With the close-in guns off, the round has to arrive.
			var ok2 := false
			var why := ""
			if _tacnuke_sea and not _tacnuke_ciws_off:
				ok2 = alive_n == _tacnuke_mob.size()
				why = "the squadron shot it down and the warhead did not function" \
					if ok2 else "%d hull(s) lost to a round that was intercepted" % (
						_tacnuke_mob.size() - alive_n)
			else:
				ok2 = alive_n == 0 and high < 150.0 and wide < 800.0
				why = "" if ok2 else \
					"%d unit(s) left, burst %.0f m up and %.0f m short" % [
						alive_n, high, wide]
			print("[tacnuke] RESULT: %s%s" % ["ok" if ok2 else "FAILED — ",
				why if not ok2 else (" — " + why if why != "" else "")])
			world.get_tree().quit()
		return true
	return false
#endregion


#region --nuketest
var _nuke_test := false
var _nuke_t := 0.0
var _nuke_boat: Ship = null
var _nuke_step := 0
var _nuke_low := 1e9
var _nuke_top := -1e9
var _nuke_at := Vector3.INF
var _nuke_miss := 1e9

func tick_nuke(delta: float) -> bool:
	if _nuke_test:
		_nuke_t += delta
		if _nuke_t > 2.5 and _nuke_boat == null:
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.can_launch():
					_nuke_boat = v
					break
			if _nuke_boat == null:
				print("[nuke] no boat on station with a round aboard")
				_nuke_test = false
				world.get_tree().quit()
				return true
			world.crew.enter_ship(_nuke_boat)
			# aim it the way a player would: right click on the map
			# at a town, so the result means something
			var bp: Vector3 = _nuke_boat.global_position
			_nuke_at = Vector3(bp.x - 30000.0, 0.0, bp.z - 20000.0)
			if is_instance_valid(world.scenery) and world.scenery.sites.size() > 0:
				var pick: Dictionary = world.scenery.sites[0]
				var pc: Vector2 = pick["c"]
				_nuke_at = Vector3(pc.x, 0.0, pc.y)
			_nuke_at.y = Sim.height_at(_nuke_at.x, _nuke_at.z)
			world.map.ship = _nuke_boat
			world.map.strategic_mark = _nuke_at
			print("[nuke] %s, %d round(s); map aiming point %s, %.0f km away" % [
				_nuke_boat.display_name(), _nuke_boat.missiles_left,
				str(_nuke_at.round()), bp.distance_to(_nuke_at) * 0.001])
			print("[nuke] map hands back: %s" % str(world.map.target_point().round()))
		elif _nuke_boat != null and _nuke_step == 0 and _nuke_t > 4.0:
			_nuke_step = 1
			var before: int = _nuke_boat.missiles_left
			world.missions.strategic_strike()
			print("[nuke] strike ordered: rounds %d -> %d" % [
				before, _nuke_boat.missiles_left])
		elif _nuke_step == 1:
			var live := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "slbm":
					continue
				live += 1
				var mp: Vector3 = (m as Node3D).global_position
				_nuke_top = maxf(_nuke_top, mp.y)
				_nuke_miss = minf(_nuke_miss, mp.distance_to(_nuke_at))
				var agl: float = mp.y - maxf(Sim.height_at(mp.x, mp.z), Sim.sea_at(mp.x, mp.z))
				if _nuke_t > 6.0:
					_nuke_low = minf(_nuke_low, agl)
				if fmod(_nuke_t, 10.0) < delta:
					print("[nuke]   t=%5.1f  alt %7.0f m  %6.1f km to run  %4.0f m/s" % [
						_nuke_t, mp.y, mp.distance_to(_nuke_at) * 0.001,
						(m.get_velocity() as Vector3).length()])
			if live == 0 and _nuke_t > 8.0 or _nuke_t > 400.0:
				_nuke_test = false
				print("[nuke] apogee %.0f m; flight ended at t=%.1f" % [_nuke_top, _nuke_t])
				print("[nuke] it went off %.0f m from the aiming point (warhead reaches %.0f m)" % [
					_nuke_miss, 4200.0])
				print("[nuke] RESULT: %s" % ("ok" if _nuke_miss < 4200.0 and _nuke_t > 8.0
					else "FAILED — %.0f m off the mark" % _nuke_miss))
				world.get_tree().quit()
		return true
	return false
#endregion


#region --lagtest
var _lag_test := false
var _lag_t := 0.0
var _lag_step := 0
var _lag_before := {}

# What a launch leaves behind. "Laggy after the round goes" is a node count
# question before it is anything else.
func tick_lag(delta: float) -> bool:
	if _lag_test:
		_lag_t += delta
		if _lag_step == 0 and _lag_t > 3.0:
			_lag_step = 1
			world._start("veh:tel_oreshnik", "free")
			await world.get_tree().process_frame
			await world.get_tree().physics_frame
			_lag_before = _census()
			print("[lag] before the launch: %s" % _census_line(_lag_before))
			if is_instance_valid(world.tank):
				var mk := world.tank.global_position + Vector3(-60000.0, 0, -40000.0)
				mk.y = Sim.height_at(mk.x, mk.z)
				world.tank.map_target = mk
				world.tank._gun_cd = 0.0
				world.tank.fire_main(world)
			_lag_t = 0.0
		elif _lag_step == 1 and _lag_t > 140.0:
			_lag_step = 2
			var after := _census()
			print("[lag] after it has landed: %s" % _census_line(after))
			for k in after.keys():
				var was := int(_lag_before.get(k, 0))
				var now := int(after[k])
				if now - was > 40:
					print("[lag]   %s grew by %d" % [String(k), now - was])
			# and *what* they are, by owner, so the leak has a name
			var tally := {}
			var stack: Array = [world.get_tree().root]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is GPUParticles3D:
					var owner_name := "(root)"
					var par := n.get_parent()
					if par != null:
						var scr: Variant = par.get_script()
						var where := String(par.get_class())
						if scr != null:
							where = String((scr as Script).resource_path).get_file()
							var gname := String((scr as Script).get_global_name())
							if gname != "":
								where = gname
						owner_name = "%s (parent %s)" % [where, String(par.name)]
					tally[owner_name] = int(tally.get(owner_name, 0)) + 1
				for c in n.get_children():
					stack.append(c)
			var rows: Array = []
			for kk in tally:
				rows.append([int(tally[kk]), String(kk)])
			rows.sort_custom(func(x, y): return x[0] > y[0])
			for i in mini(6, rows.size()):
				print("[lag]   particles: %4d x %s" % [rows[i][0], rows[i][1]])
			# and what a frame costs on foot afterwards
			world.crew.leave_tank()
			await world.get_tree().process_frame
			var t0 := Time.get_ticks_usec()
			for _f in 30:
				await world.get_tree().process_frame
			var per := float(Time.get_ticks_usec() - t0) / 30000.0
			print("[lag] on foot afterwards: %.2f ms a frame" % per)
			print("[lag] RESULT: %s" % ("ok" if per < 40.0 else "SLOW"))
			world.get_tree().quit()
		return true
	return false

## A round that splits hands the camera to one of its children, so the ride
## carries on through the separation instead of ending at it.
## A headcount of the things that accumulate, so "it got slow" can be answered
## with a number rather than a guess.
func _census() -> Dictionary:
	var out := {"nodes": 0, "missiles": 0, "hittable": 0, "interceptable": 0,
		"particles": 0, "lights": 0, "meshes": 0, "multimesh": 0}
	var stack: Array = [world.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out["nodes"] = int(out["nodes"]) + 1
		if n is GPUParticles3D:
			out["particles"] = int(out["particles"]) + 1
		elif n is Light3D:
			out["lights"] = int(out["lights"]) + 1
		elif n is MultiMeshInstance3D:
			out["multimesh"] = int(out["multimesh"]) + 1
		elif n is MeshInstance3D:
			out["meshes"] = int(out["meshes"]) + 1
		for c in n.get_children():
			stack.append(c)
	out["missiles"] = world.get_tree().get_nodes_in_group("missiles").size()
	out["hittable"] = world.get_tree().get_nodes_in_group("hittable").size()
	out["interceptable"] = world.get_tree().get_nodes_in_group("interceptable").size()
	return out

func _census_line(c: Dictionary) -> String:
	return "%d nodes, %d meshes, %d multimesh, %d particles, %d lights, %d missiles" % [
		int(c["nodes"]), int(c["meshes"]), int(c["multimesh"]), int(c["particles"]),
		int(c["lights"]), int(c["missiles"])]
#endregion


#region --tracertest
var _tracer_test := false

# Do the guns draw tracer, and does it read as tracer?
func tick_tracer() -> bool:
	if _tracer_test:
		_tracer_test = false
		_run_tracer_test()
		world.get_tree().quit()
		return true
	return false

## Tracer, from the guns that fire it.
##
## What is checked is not that a tracer exists — it always did — but that it is
## long enough to be one. A round is drawn where it is each frame, and if the
## drawn streak is shorter than the distance it travels between frames the eye
## gets a dotted line of separate flecks instead of a burning streak. That is
## why the cannon and the anti-aircraft gun did not look like they were firing
## tracer even though both were.
func _run_tracer_test() -> void:
	var step := 1.0 / 60.0
	var worst_ratio := 1e9
	var rows := PackedStringArray()
	for speed in [180.0, 900.0, 1030.0, 1600.0]:
		var t := Tracer.new()
		t.vel = Vector3(0, 0, -float(speed))
		world.add_child(t)
		var mi := t.get_child(0) as MeshInstance3D
		var length: float = mi.mesh.get_aabb().size.z if mi != null \
			and mi.mesh != null else 0.0
		var travel: float = float(speed) * step
		worst_ratio = minf(worst_ratio, length / maxf(travel, 0.001))
		rows.append("%.0f m/s: %.1f m of streak against %.1f m a frame" % [
			speed, length, travel])
		t.queue_free()
	for r in rows:
		print("[tracer] %s" % String(r))
	# Every gun in the game that puts rounds in the air has to go through it.
	var guns := 0
	for src in ["scripts/aircraft/aircraft.gd", "scripts/vehicles/tank.gd",
			"scripts/world/ship.gd", "scripts/world/walker.gd"]:
		var f := FileAccess.open("res://" + String(src), FileAccess.READ)
		if f != null:
			if f.get_as_text().contains("Effects.tracer("):
				guns += 1
	print("[tracer] %d of 4 gun-carrying scripts fire it" % guns)
	print("[tracer] RESULT: %s" % ("ok" if worst_ratio > 1.0 and guns == 4
		else "FAILED — the streak is %.2f of a frame's travel" % worst_ratio))
#endregion


#region --locktime
var _locktime_test := false
var _lt_t := 0.0

# Does the lock actually complete on a weapon that can make the shot?
func tick_locktime(delta: float) -> bool:
	if _locktime_test and is_instance_valid(world.player):
		_lt_t += delta
		if _lt_t > 2.5:
			_locktime_test = false
			var boat: Ship = null
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.alive:
					boat = v
					break
			if boat == null:
				print("[locktime] no hostile shipping")
				world.get_tree().quit()
				return true
			for rng in [8000.0, 18000.0, 34000.0]:
				for w in ["agm84", "agm65", "aim120"]:
					if world.player.weapon_types.find(w) < 0:
						continue
					world.player.global_transform = Transform3D(Basis(),
						boat.global_position + Vector3(0, 3500.0, rng))
					world.player.linear_velocity = Vector3(0, 0, -240.0)
					world.player.look_at(boat.global_position, Vector3.UP)
					world.player.set_weapon(world.player.weapon_types.find(w))
					world.player.target = boat
					world.player.locked = false
					world.player.lock_time = 0.0
					world.player._reach_cache.clear()
					var took := -1.0
					for step in 400:
						world.player._update_lock(0.02)
						if world.player.locked:
							took = float(step) * 0.02
							break
					var why: String = world.player.shot_blocked(w, boat)
					print("[locktime] %-7s at %5.1f km: %s%s" % [w, rng * 0.001,
						"locked in %.2f s" % took if took >= 0.0 else "NEVER LOCKED",
						"" if why == "" else "   (%s)" % why])
			print("[locktime] done")
			world.get_tree().quit()
		return true
	return false
#endregion


#region --mavtest
var _mav_test := false
var _mav_t := 0.0
var _mav_step := 0
var _mav_ship: Ship = null
var _mav_rngs := [8000.0, 12000.0, 16000.0, 20000.0]
var _mav_i := 0
var _mav_closest := 1e9
var _mav_locked := false

# Where the towns ended up, how level they are, and whether the streets are
# on the surface or buried in it.
# What a Maverick actually does against a ship, range by range, against what
# the head-up display promised before it was fired.
func tick_mav(delta: float) -> bool:
	if _mav_test and is_instance_valid(world.player):
		_mav_t += delta
		if _mav_step == 0 and _mav_t > 2.5:
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.alive:
					_mav_ship = v
					break
			if _mav_ship == null:
				print("[mav] no target shipping")
				_mav_test = false
				world.get_tree().quit()
				return true
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.cells_left = 0
					v2.ai = false
					v2.ciws_enabled = false
			_mav_step = 1
			_mav_t = 0.0
		elif _mav_step == 1:
			# set up the next shot
			if _mav_i >= _mav_rngs.size():
				_mav_test = false
				print("[mav] done")
				world.get_tree().quit()
				return true
			var rng: float = float(_mav_rngs[_mav_i])
			world.player.global_transform = Transform3D(Basis(),
				_mav_ship.global_position + Vector3(0, 3000.0, rng))
			world.player.linear_velocity = Vector3(0, 0, -250.0)
			world.player.look_at(_mav_ship.global_position, Vector3.UP)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			# A fresh target each time. Reusing one hull meant the shots at the
			# short ranges sank her, and every range after that was scored as a
			# miss when what actually happened was the round losing a target
			# that was already on the bottom.
			_mav_ship.health = float(Ship.KINDS[_mav_ship.kind]["hp"])
			_mav_ship.alive = true
			_mav_ship.flood = 0.0
			# reload between shots: the aeroplane carries two, and the later
			# ranges were coming back "winchester" rather than measured
			for st in world.player.stores:
				st["gone"] = false
				if is_instance_valid(st["node"]):
					(st["node"] as Node3D).visible = true
			world.player.target = _mav_ship
			world.player.lock_time = 0.0
			world.player.locked = false
			world.player._reach_cache.clear()
			if not harness._arm_with("agm65"):
				_mav_test = false
				world.get_tree().quit()
				return true
			for _s in 200:
				world.player._update_lock(0.02)
			_mav_locked = world.player.locked
			world.player.fire_cd = 0.0
			world._reset_interp.call_deferred(world.player)
			_mav_closest = 1e9
			_mav_step = 2
			_mav_t = 0.0
		elif _mav_step == 2 and _mav_t > 0.5:
			_mav_step = 3
			var why: String = world.player.fire()
			if why != "":
				print("[mav] %5.1f km: HUD lock=%s, release refused (%s)" % [
					float(_mav_rngs[_mav_i]) * 0.001, str(_mav_locked), why])
				_mav_i += 1
				_mav_step = 1
				_mav_t = 0.0
		elif _mav_step == 3:
			var live := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m) or String(m.wid) != "agm65":
					continue
				live += 1
				_mav_closest = minf(_mav_closest,
					(m as Node3D).global_position.distance_to(_mav_ship.global_position))
			if (live == 0 and _mav_t > 3.0) or _mav_t > 90.0:
				var r2: float = float(_mav_rngs[_mav_i])
				print("[mav] %5.1f km: HUD lock=%-5s  round came within %6.0f m  -> %s" % [
					r2 * 0.001, str(_mav_locked), _mav_closest,
					"HIT" if _mav_closest < 40.0 else "MISS"])
				_mav_i += 1
				_mav_step = 1
				_mav_t = 0.0
		return true
	return false
#endregion


#region --cmtest= --cluttertest=
var _cm_test := ""
var _cm_t := 0.0
var _cm_step := 0
var _cm_sam: Node3D = null
var _clutter_test := false
var _clutter_agl := 200.0
var _clutter_t2 := 0.0
var _clutter_step := 0

# Fly the same profile at different heights and see what the battery can do
# about it.
func tick_clutter(delta: float) -> void:
	if _clutter_test and is_instance_valid(world.player):
		_clutter_t2 += delta
		if _clutter_t2 > 1.5 and _clutter_step == 0:
			_clutter_step = 1
			var at := Vector3(2000.0, 0.0, -3000.0)
			_cm_sam = GroundTarget.new()
			_cm_sam.team = 1
			_cm_sam.setup("sam")
			world.add_child(_cm_sam)
			_cm_sam.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
			world.player.team = 0
			var px := at.x
			var pz := at.z + 6000.0
			world.player.global_transform = Transform3D(Basis(),
				Vector3(px, Sim.height_at(px, pz) + _clutter_agl, pz))
			world.player.linear_velocity = Vector3(0, 0, -220.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.flares = 0
			world.player.chaff = 0             # no countermeasures: clutter alone
			world._reset_interp(world.player)
			print("[clutter] running in at %.0f m agl, 6.0 km out, no countermeasures" % _clutter_agl)
		elif _clutter_step == 1 and _clutter_t2 > 30.0:
			_clutter_step = 2
			var fired := 0
			var tracking := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				fired += 1
				if m.target == world.player:
					tracking += 1
			print("[clutter] RESULT: %.0f m agl — %d rounds up, %d still tracking, player alive=%s, agl now %.0f" % [
				_clutter_agl, fired, tracking, str(world.player.is_alive()), world.player.agl])
			world.get_tree().quit()

# Does a countermeasure actually break a shot? A SAM site fires at the
# player from close range; the aeroplane either dispenses or does not.
func tick_cm(delta: float) -> void:
	if _cm_test != "" and is_instance_valid(world.player):
		_cm_t += delta
		if _cm_t > 1.5 and _cm_step == 0:
			_cm_step = 1
			var at := Vector3(2000.0, 0.0, -3000.0)
			_cm_sam = GroundTarget.new()
			_cm_sam.team = 1
			_cm_sam.setup("sam")
			world.add_child(_cm_sam)
			_cm_sam.global_position = Vector3(at.x, Sim.height_at(at.x, at.z), at.z)
			world.player.team = 0
			world.player.global_transform = Transform3D(Basis(),
				at + Vector3(0.0, Sim.height_at(at.x, at.z) + 2000.0, 6000.0))
			world.player.linear_velocity = Vector3(0, 0, -230.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.flares = 240
			world.player.chaff = 240
			world._reset_interp(world.player)
			print("[cm] SAM at %s, aeroplane 6.0 km out at 2000 m agl, mode=%s" % [
				str(_cm_sam.global_position.round()), _cm_test])
		elif _cm_step == 1 and _cm_t > 2.5:
			# let it shoot, then run the defence for the whole flight time
			var live := 0
			var tracking := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				live += 1
				if m.target == world.player:
					tracking += 1
			if live > 0:
				match _cm_test:
					"chaff":
						world.player.drop_chaff()
					"flare":
						world.player.drop_flare()
					"both":
						world.player.dispense_all()
					_:
						pass
			if _cm_t > 26.0:
				_cm_step = 2
				print("[cm] RESULT: %s — %d rounds up, %d still tracking; player alive=%s (flares %d, chaff %d left)" % [
					_cm_test, live, tracking, str(world.player.is_alive()),
					world.player.flares, world.player.chaff])
				world.get_tree().quit()
#endregion


#region --cruisetest
var _cruise_test := false
var _cruise_t := 0.0
var _cruise_step := 0
var _cruise_ship: Node3D = null
var _cruise_hp := 0.0
var _cruise_low := 1e9

# A Harpoon at a ship from long range: does it run in on the deck.
func tick_cruise(delta: float) -> bool:
	if _cruise_test and is_instance_valid(world.player):
		_cruise_t += delta
		if _cruise_t > 2.0 and _cruise_ship == null:
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team != 0 and v.has_gun():
					_cruise_ship = v
					break
			if _cruise_ship == null:
				print("[cruise] no hostile warship")
				_cruise_test = false
				return true
			# nothing else sinks the target while the round is in the air, and
			# the target does not sink the launcher either: at sixteen
			# kilometres and four thousand metres its tubes had the F-16 down
			# thirty-three seconds after release and the test never finished
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 == null:
					continue
				if v2 != _cruise_ship:
					v2.ai = false
				v2.cells_left = 0
			_cruise_hp = float(_cruise_ship.get("health"))
			var sp: Vector3 = _cruise_ship.global_position
			# Out where a Harpoon is actually employed. From 4200 m only 16 km
			# out there are 13 km of cruise to lose 4 km of height — seventeen
			# degrees, the whole let-down budget — so it arrives at the pop-up
			# still high and never gets near the deck. That is the geometry,
			# not the guidance.
			world.player.global_transform = Transform3D(Basis(),
				sp + Vector3(0, 4200.0, 42000.0))
			world.player.linear_velocity = Vector3(0, 0, -250.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			world.player.target = _cruise_ship
			world.player.locked = true
			if not harness._arm_with("agm84"):
				_cruise_test = false
				world.get_tree().quit()
				return true
			world.player.fire_cd = 0.0
			world._reset_interp.call_deferred(world.player)
			print("[cruise] %s at 42 km, launching from 4200 m" % [
				_cruise_ship.call("display_name")])
		elif _cruise_ship != null and _cruise_step == 0 and _cruise_t > 4.0:
			_cruise_step = 1
			var why: String = world.player.fire()
			print("[cruise] %s carrying %s, selected %s" % [
				world.player.spec.get("name", "?"), str(world.player.weapon_types),
				world.player.current_weapon()])
			print("[cruise] release: %s" % ("away" if why == "" else "refused — " + why))
		elif _cruise_step == 1 and not _cruise_ship.alive:
			_cruise_test = false
			print("[cruise] RESULT: %s sunk at t=%.0f s; cruised as low as %.0f m above the sea" % [
				_cruise_ship.call("display_name"), _cruise_t, _cruise_low])
			world.get_tree().quit()
		elif _cruise_step == 1:
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m) and String(m.wid) == "agm84":
					var mp: Vector3 = (m as Node3D).global_position
					var sea: float = maxf(Sim.height_at(mp.x, mp.z), Sim.sea_at(mp.x, mp.z))
					if mp.distance_to(_cruise_ship.global_position) > 4000.0:
						_cruise_low = minf(_cruise_low, mp.y - sea)
			if _cruise_t > 190.0:
				_cruise_test = false
				var now: float = _cruise_ship.get("health") \
					if is_instance_valid(_cruise_ship) else -1.0
				print("[cruise] RESULT: cruised as low as %.0f m above the sea; hull %.0f -> %.0f" % [
					_cruise_low, _cruise_hp, now])
				world.get_tree().quit()
	return false
#endregion


#region --flirtest
var _flirtest := false

# What the thermal channels make of a scene. Mirrors the shader exactly, so
# a change to one that is not made to the other shows up as a mismatch here.
func tick_flirtest() -> void:
	if _flirtest:
		_flirtest = false
		var scene := {
			"clear sky": Color(0.35, 0.55, 0.90), "cloud": Color(0.85, 0.87, 0.92),
			"grass": Color(0.24, 0.34, 0.18), "tarmac": Color(0.13, 0.13, 0.14),
			"sea": Color(0.07, 0.19, 0.28), "engine plume": Color(1.0, 0.72, 0.30),
			"aircraft skin": Color(0.36, 0.38, 0.36),
		}
		var hot_name := ""
		var cold_name := ""
		var hot_v := -1.0
		var cold_v := 2.0
		var ws: Array = []
		for k in scene:
			var t: float = _flir(scene[k])
			ws.append(t)
			if t > hot_v:
				hot_v = t
				hot_name = k
			if t < cold_v:
				cold_v = t
				cold_name = k
			print("[flir] %-14s white hot %.2f   black hot %.2f" % [k, t, 1.0 - t])
		print("[flir] hottest thing on screen: %s; coldest: %s" % [hot_name, cold_name])
		var ok_hot: bool = hot_name == "engine plume"
		var ok_cold: bool = cold_name == "clear sky" or cold_name == "sea"
		print("[flir] RESULT: %s" % ("ok" if ok_hot and ok_cold else
			"FAILED — a thermal picture whose hottest thing is %s is not one" % hot_name))
		world.get_tree().quit()

## Self check at mission start: anything that has spawned inside something else
## names itself in the log rather than waiting to be noticed on screen.
## Move this peer's aeroplane off the shared start point. Everybody loads the
## same mission, so without this two players who chose the same type begin
## inside one another.
## Move this peer off the shared start point.
##
## This cannot be done at mission start. A joiner launches its mission before
## the connection has finished — its own id is still the default 1 and the
## roster is empty, so it works out slot 0 and stays exactly where the host is.
## Measured with four peers: all four on the same coordinates. It is worked out
## when the roster arrives instead, which is a second or so later and long
## before anyone has flown anywhere.
## The host changed its mind in the hangar; tell everyone waiting in it.
## The sensor's thermal transfer, mirroring the shader.
func _flir(c: Color) -> float:
	var l: float = 0.30 * c.r + 0.59 * c.g + 0.11 * c.b
	var sat: float = maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)
	var sky: float = smoothstep(0.03, 0.22, c.b - c.r)
	var cloudy: float = smoothstep(0.72, 0.95, l) * (1.0 - smoothstep(0.02, 0.20, sat))
	var cold: float = clampf(sky + cloudy, 0.0, 1.0)
	var hot: float = smoothstep(0.12, 0.45, c.r - c.b) * smoothstep(0.30, 0.75, l)
	var t: float = clampf(pow(l, 0.75), 0.0, 1.0)
	t = lerpf(t, 0.05, cold)
	return maxf(t, hot)
#endregion


#region --salvotest --salvotest=
var _salvo_w := "gbu32"
var _salvo_test := false
var _salvo_away := 0
var _salvo_t := 0.0
var _salvo_dropped := 0
var _salvo_aim := Vector3.INF

# Several JDAMs at one lased point, released a couple of seconds apart.
# Not gated on the aeroplane surviving: the rounds are away, and whether
# they arrive has nothing to do with whether the launcher is still flying.
# It was, and a shot down F-35 left the test hanging with nothing reported.
func tick_salvo(delta: float) -> bool:
	if _salvo_test and (is_instance_valid(world.player) or _salvo_dropped > 0):
		_salvo_t += delta
		if _salvo_t > 2.0 and _salvo_aim == Vector3.INF and is_instance_valid(world.player):
			var gx := 2400.0
			var gz := -5200.0
			_salvo_aim = Vector3(gx, Sim.height_at(gx, gz), gz)
			var mark := GroundTarget.new()
			mark.team = 1
			mark.setup("radar")
			world.add_child(mark)
			mark.global_position = _salvo_aim
			world.player.global_transform = Transform3D(Basis(),
				_salvo_aim + Vector3(0, 2600.0, 7000.0))
			world.player.linear_velocity = Vector3(0, 0, -240.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			world.pod.platform = world.player
			if not world.pod.active:
				world.pod.toggle()
			world.pod.mode = world.pod.POINT
			world.pod.tracked = mark
			if not world.pod.lasing:
				world.pod.toggle_laser()
			world.pod._process(0.016)
			world.player.locked = true
			if not harness._arm_with(_salvo_w):
				_salvo_test = false
				world.get_tree().quit()
				return true
			world._reset_interp.call_deferred(world.player)
			Sim.salvo_watch = true
			Sim.salvo_weapon = _salvo_w
			Sim.salvo_mark = _salvo_aim
			Sim.salvo_log.clear()
			print("[salvo] lasing %s; %s, two seconds apart" % [
				str(_salvo_aim.round()), _salvo_w])
		elif _salvo_aim != Vector3.INF and _salvo_dropped < 3 and is_instance_valid(world.player) \
				and _salvo_t > 4.0 + float(_salvo_dropped) * 2.0:
			_salvo_dropped += 1
			world.player.fire_cd = 0.0
			var r := world.player.fire()
			if r == "":
				_salvo_away += 1
			print("[salvo] release %d: %s (selected %s of %s)" % [_salvo_dropped,
				"away" if r == "" else r, world.player.current_weapon(),
				str(world.player.weapon_types)])
		elif _salvo_dropped >= 2 and _salvo_t > 60.0:
			_salvo_test = false
			for entry in Sim.salvo_log:
				print("[salvo]   %s" % String(entry))
			# one line per round, not per log entry: the watch writes two of
			# them for every round and the tally read four out of three
			var gone := 0
			for entry in Sim.salvo_log:
				if String(entry).contains("died at"):
					gone += 1
			print("[salvo] RESULT: %d attempted, %d away, %d detonated" % [
				_salvo_dropped, _salvo_away, gone])
			world.get_tree().quit()
	return false
#endregion


#region --shaketest
var _shake_test := false
var _shake_t := 0.0

# How steady the sensor head is on the aeroplane carrying it.
func tick_shake(delta: float) -> void:
	if _shake_test and is_instance_valid(world.player):
		_shake_t += delta
		if _shake_t > 2.0 and not world.pod.active:
			world.pod.platform = world.player
			world.pod.toggle()
			world.pod.diag = true
			world.pod.shake_worst = 0.0
			world.pod.shake_sum = 0.0
			world.pod.shake_n = 0
			world.player.in_roll = 0.35        # keep it manoeuvring, not gliding
			world.player.in_pitch = 0.2
		elif _shake_t > 26.0:
			_shake_test = false
			print("[pod] head against the aeroplane over %d frames: mean %.4f m, worst %.4f m" % [
				world.pod.shake_n, world.pod.shake_sum / maxf(float(world.pod.shake_n), 1.0),
				world.pod.shake_worst])
			world.get_tree().quit()
#endregion


#region --breaktest=
var _break_test := false
var _break_rng := 8000.0
var _break_t := 0.0
var _break_step := 0
var _break_min := 1e9
var _break_alt := 6000.0
var _break_w := "aim120"

# A missile launched from a given range at an aeroplane that then breaks
# hard at full power: how close does it get?
func tick_break(delta: float) -> void:
	if _break_test and is_instance_valid(world.player):
		_break_t += delta
		if _break_t > 1.5 and _break_step == 0:
			_break_step = 1
			var shooter := AIPlane.new()
			shooter.setup("su35")
			shooter.team = 1
			shooter.name = "Shooter"
			world.add_child(shooter)
			var spot := Vector3(0.0, _break_alt, 0.0)
			shooter.global_transform = Transform3D(Basis(),
				spot + Vector3(0, 0, _break_rng))
			shooter.look_at_from_position(shooter.global_position, spot, Vector3.UP)
			shooter.linear_velocity = -shooter.global_transform.basis.z * 300.0
			world.player.team = 0
			world.player.global_transform = Transform3D(Basis(), spot)
			world.player.rotation.y = deg_to_rad(180.0)
			world.player.linear_velocity = -world.player.global_transform.basis.z * 380.0
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.flares = 0
			world.player.chaff = 0
			world.player.throttle = 1.0
			world.player.power = 1.0
			world._reset_interp(world.player)
			world._reset_interp(shooter)
			# Nothing else in the world gets a vote. With the fleet left running
			# there were twenty-one rounds in the air and the closest approach
			# was whichever of them happened to be nearest — the measurement
			# came out identical whatever the missile physics were doing.
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.ai = false
					v2.cells_left = 0
			for g2 in world.get_tree().get_nodes_in_group("ground_targets"):
				if is_instance_valid(g2):
					g2.queue_free()
			for m2 in world.get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m2):
					m2.queue_free()
			shooter.target = world.player
			shooter.locked = true
			shooter.selected = maxi(shooter.weapon_types.find(_break_w), 0)
			shooter.fire_cd = 0.0
			print("[break] %s from %.1f km at %.0f m; the target then breaks at full power" % [
				_break_w, _break_rng * 0.001, _break_alt])
			shooter.fire()
		elif _break_step == 1 and _break_t > 2.0:
			# hard break, wings level nowhere near the missile
			world.player.in_roll = 1.0
			world.player.in_pitch = 1.0
			world.player.throttle = 1.0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(m) and m.target == world.player \
						and String(m.wid) == _break_w:
					_break_min = minf(_break_min,
						(m as Node3D).global_position.distance_to(world.player.global_position))
			if _break_t > 34.0:
				_break_step = 2
				print("[break] RESULT: %s from %.1f km at %.0f m — closest %.0f m (fuse %.0f), player alive=%s" % [
					_break_w, _break_rng * 0.001, _break_alt, _break_min,
					float(WeaponSpec.get_spec(_break_w)["fuse"]),
					str(world.player.is_alive())])
				world.get_tree().quit()
#endregion


#region --triggertest
var _trig_test := false
var _trig_t := 0.0

func tick_trig(delta: float) -> void:
	if _trig_test and is_instance_valid(world.player):
		_trig_t += delta
		if _trig_t > 2.5:
			_trig_test = false
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			world.player.set_weapon(maxi(world.player.weapon_types.find("aim120"), 0))
			world.player.locked = true
			# right click must NOT launch anything: it is the sensor page now
			var n0 := world.player.count_remaining("aim120")
			world.player.fire_cd = 0.0
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_RIGHT
			ev.pressed = true
			world.controls.shell_input(ev)
			world.player._pilot(0.016)
			var n1 := world.player.count_remaining("aim120")
			var opened: bool = world.pod.active
			if world.pod.active:
				world.pod.toggle()
				world.pod.set_fullscreen(false)
			print("[trigger] right click opened the sensor page: %s" % str(opened))
			# and with the map up, a click must do nothing to the weapons
			world.map.visible = true
			Sim.ui_modal = true
			var nm0 := world.player.count_remaining("aim120")
			world.player.fire_cd = 0.0
			Input.action_press(&"fire")
			world.player._pilot(0.016)
			Input.action_release(&"fire")
			var ev2 := InputEventMouseButton.new()
			ev2.button_index = MOUSE_BUTTON_RIGHT
			ev2.pressed = true
			world.controls.shell_input(ev2)
			print("[trigger] with the map up: fired=%s, sensor toggled=%s" % [
				str(world.player.count_remaining("aim120") < nm0), str(world.pod.active)])
			world.map.visible = false
			Sim.ui_modal = false
			# left click must
			world.player.fire_cd = 0.0
			Input.action_press(&"fire")
			world.player._pilot(0.016)
			Input.action_release(&"fire")
			var n2 := world.player.count_remaining("aim120")
			print("[trigger] stores %d -> right click %d -> left click %d  (right fired=%s, left fired=%s)" % [
				n0, n1, n2, str(n1 < n0), str(n2 < n1)])
			world.get_tree().quit()
#endregion


#region --lasertest
var _laser_test := false
var _laser_t := 0.0

func tick_laser(delta: float) -> void:
	if _laser_test and is_instance_valid(world.player):
		_laser_t += delta
		if _laser_t > 2.5:
			_laser_test = false
			world.pod.toggle()
			world.pod.set_fullscreen(true)
			world.pod.pitch = -0.5
			world.pod.toggle_laser()
			world.pod._process(0.016)
			var lit: bool = world.pod._beam != null and world.pod._beam.visible
			# lock something, then leave the page
			world.pod.designate()
			var mode1: int = world.pod.mode
			var trk = world.pod.tracked
			world.pod.toggle()
			world.pod._process(0.016)
			var lit_after: bool = world.pod._beam != null and world.pod._beam.visible
			var des2: bool = world.player.designated != Vector3.INF
			# and come back to it
			world.pod.toggle()
			world.pod._process(0.016)
			print("[laser] lit while up=%s; after closing: beam visible=%s, designation held=%s" % [
				str(lit), str(lit_after), str(des2)])
			print("[laser] track mode before=%d after reopening=%d (%s), tracked kept=%s" % [
				mode1, world.pod.mode, "PRESERVED" if world.pod.mode == mode1 else "LOST",
				str(world.pod.tracked == trk)])
			world.get_tree().quit()
#endregion


#region --firetest
var _fire_test := false
var _fire_t := 0.0

func tick_fire(delta: float) -> void:
	if _fire_test and is_instance_valid(world.player):
		_fire_t += delta
		if _fire_t > 2.0:
			_fire_test = false
			var p2 := world.player
			# (1) a radar round with nothing locked must still leave the rail
			p2.target = null
			p2.locked = false
			p2.set_bays(true)
			p2.bays[p2.bays.keys()[0]]["anim"] = 1.0
			for k in p2.bays:
				p2.bays[k]["anim"] = 1.0
				p2.bays[k]["open"] = true
			p2.set_weapon(maxi(p2.weapon_types.find("aim120"), 0))
			p2.fire_cd = 0.0
			var n0 := p2.count_remaining("aim120")
			var r1: String = p2.fire()
			var n1 := p2.count_remaining("aim120")
			print("[fire] unlocked radar shot: result=%s, stores %d -> %d (%s)" % [
				"away" if r1 == "" else r1, n0, n1,
				"LAUNCHED" if n1 < n0 else "REFUSED"])
			# (2) ask for a shot with the doors shut, then change your mind
			for k in p2.bays:
				if String(p2.bays[k]["kind"]) == "internal":
					p2.bays[k]["anim"] = 0.0
					p2.bays[k]["open"] = false
			p2.fire_cd = 0.0
			p2.set_weapon(maxi(p2.weapon_types.find("aim120"), 0))
			var before := p2.count_remaining("aim9")
			var r2: String = p2.fire()
			var queued: bool = p2._pending_fire
			p2.set_weapon(maxi(p2.weapon_types.find("aim9"), 0))
			var still: bool = p2._pending_fire
			# let the doors finish and see whether anything goes off by itself
			for k in p2.bays:
				p2.bays[k]["anim"] = 1.0
				p2.bays[k]["open"] = true
			p2.fire_cd = 0.0
			var after := p2.count_remaining("aim9")
			print("[fire] queued behind doors: %s -> queued=%s; after switching queued=%s; aim9 %d -> %d (%s)" % [
				"waiting" if r2 != "" else "away", str(queued), str(still), before, after,
				"CANCELLED" if not still and after == before else "STILL ARMED"])
			world.get_tree().quit()
#endregion


#region --locktest
var _lock_test := false
var _lock_t := 0.0

func tick_lock(delta: float) -> bool:
	if _lock_test and is_instance_valid(world.player):
		_lock_t += delta
		if _lock_t > 2.0:
			_lock_test = false
			# The key path, not just the lock logic: an action that is unbound,
			# or a typing gate stuck open, stops T dead however well
			# cycle_target works when called directly.
			var evs := InputMap.action_get_events(&"cycle_target")
			var names := PackedStringArray()
			for ev in evs:
				names.append(ev.as_text())
			print("[lock] T path: action exists=%s bound to [%s]; Sim.typing=%s; chat open=%s" % [
				str(InputMap.has_action(&"cycle_target")), ", ".join(names),
				str(Sim.typing), str(is_instance_valid(world.chat) and world.chat.typing)])
			print("[lock] Sim.tapped would return %s (it is gated on typing)" % [
				str(not Sim.typing)])
			# and the whole path for real: a T event through Godot's own input
			# system, which is what `Input.is_action_just_pressed` reads
			# Press it repeatedly: acquiring once is not cycling.
			world.player.target = null
			world.player.lock_presses_seen = 0
			for press in 12:
				var kd := InputEventKey.new()
				kd.physical_keycode = KEY_T
				kd.keycode = KEY_T
				kd.pressed = true
				Input.parse_input_event(kd)
				# A whole frame between press and release, and more between
				# presses: a person cannot press T twice inside one frame, and
				# `parse_input_event` batches per frame, so doing it faster
				# measures the queue rather than the game.
				await world.get_tree().process_frame
				await world.get_tree().process_frame
				var ku := InputEventKey.new()
				ku.physical_keycode = KEY_T
				ku.keycode = KEY_T
				ku.pressed = false
				Input.parse_input_event(ku)
				await world.get_tree().process_frame
				await world.get_tree().process_frame
				pass
			var shipnames := PackedStringArray()
			for shn in world.get_tree().get_nodes_in_group("ships"):
				shipnames.append("%s(%s)" % [String(shn.name),
					String(shn.call("display_name")) if shn.has_method("display_name")
					else "?"])
			print("[lock] ship node names: %s" % ", ".join(shipnames))
			print("[lock] RELIABILITY: 12 presses sent, %d reached the handler" % [
				world.player.lock_presses_seen])
			# Does it actually walk the list? Calling it repeatedly and turning
			# toward whatever it hands back is what a pilot does, and it is the
			# case that used to trap the radar between two contacts.
			# Somewhere with a radar picture. Cycling is meaningless with one
			# contact in range, and where the harness starts there is one.
			var fleet: Array = []
			for shx in world.get_tree().get_nodes_in_group("ships"):
				var vx := shx as Ship
				if vx != null and vx.team != 0 and vx.alive:
					fleet.append(vx)
			if fleet.size() > 0:
				var anchor: Vector3 = (fleet[0] as Ship).global_position
				world.player.global_transform = Transform3D(Basis(),
					anchor + Vector3(0, 5000.0, 15000.0))
				world.player.linear_velocity = Vector3(0, 0, -220.0)
				world._reset_interp.call_deferred(world.player)
				await world.get_tree().physics_frame
				await world.get_tree().physics_frame
			world.player.target = null
			var seen: Array = []
			var distinct: Array = []
			for turn in 14:
				world.player.cycle_target()
				if not is_instance_valid(world.player.target):
					continue
				seen.append(Sim.label_of(world.player.target))
				if not distinct.has(world.player.target):
					distinct.append(world.player.target)
				# fly at it, the way you would
				var rel: Vector3 = world.player.target.global_position - world.player.global_position
				world.player.global_transform.basis = Basis.looking_at(rel.normalized(), Vector3.UP)
			var reach2: float = float(Sim.RADAR_RANGES[Sim.radar_range_idx])
			var avail := 0
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == world.player or n.is_in_group("no_lock"):
					continue
				if not ("team" in n) or int(n.team) == world.player.team:
					continue
				if n.has_method("is_alive") and not n.is_alive():
					continue
				if world.player.global_position.distance_to((n as Node3D).global_position) < reach2:
					avail += 1
			print("[lock] cycling while turning onto each: %d presses reached %d distinct of %d in range" % [
				seen.size(), distinct.size(), avail])
			print("[lock] order: %s" % " -> ".join(PackedStringArray(seen)))
			print("[lock] CYCLE: %s" % ("ok" if distinct.size() >= mini(avail, 4)
				else "FAILED — the radar is stuck between %d contacts" % distinct.size()))
			world.player.target = null
			var down := InputEventKey.new()
			down.physical_keycode = KEY_T
			down.keycode = KEY_T
			down.pressed = true
			Input.parse_input_event(down)
			await world.get_tree().physics_frame
			await world.get_tree().physics_frame
			var up := InputEventKey.new()
			up.physical_keycode = KEY_T
			up.keycode = KEY_T
			up.pressed = false
			Input.parse_input_event(up)
			if is_instance_valid(world.player.target):
				var gs := PackedStringArray()
				for g in world.player.target.get_groups():
					gs.append(String(g))
				print("[lock] after a real T press: target=%s  class=%s  groups=[%s]  team=%s" % [
					String(world.player.target.name), world.player.target.get_class(),
					", ".join(gs),
					str(world.player.target.get("team")) if "team" in world.player.target else "none"])
			else:
				print("[lock] after a real T press: NONE")
			var ships := world.get_tree().get_nodes_in_group("ships")
			var tgt: Node3D = null
			for sh in ships:
				if is_instance_valid(sh) and (sh as Ship).team != 0:
					tgt = sh
					break
			if tgt == null:
				print("[lock] no hostile shipping found")
				world.get_tree().quit()
				return true
			# sit the aeroplane off the target and try to lock it
			world.player.global_transform = Transform3D(Basis(),
				tgt.global_position + Vector3(0, 2000, 9000))
			world.player.linear_velocity = Vector3(0, 0, -240.0)
			world.player.target = null
			# with a BOMB selected, which is how you would attack a ship
			world.player.selected = maxi(world.player.weapon_types.find("gbu32"), 0)
			world.player.cycle_target()
			var got := "nothing"
			if world.player.target != null and is_instance_valid(world.player.target):
				got = "%s at %.1f km" % [str(world.player.target.name),
					world.player.global_position.distance_to(world.player.target.global_position) * 0.001]
			print("[lock] weapon=%s" % world.player.weapon_label(world.player.current_weapon()))
			# would the HUD actually draw a box on it?
			var d2: float = world.player.global_position.distance_to(tgt.global_position)
			var in_reach: bool = d2 <= maxf(Sim.radar_range(), 26000.0)
			var los: bool = world.hud._los_clear(world.player.global_position, tgt.global_position)
			# and a contact deliberately put behind a hill
			var hill := Vector3(2600.0, 0, 4200.0)
			hill.y = Sim.height_at(hill.x, hill.z) - 30.0
			var blocked: bool = world.hud._los_clear(
				Vector3(hill.x, hill.y + 5.0, hill.z + 4000.0), hill)
			print("[lock] box drawn: in radar reach=%s (%.1f km, radar %.0f km), line of sight=%s; a target dug in behind terrain reads clear=%s" % [
				str(in_reach), d2 * 0.001, Sim.radar_range() * 0.001, str(los), str(blocked)])
			print("[lock] %d ships in the world; nearest hostile %s at %.1f km; cycle_target picked %s" % [
				ships.size(), tgt.display_name(),
				world.player.global_position.distance_to(tgt.global_position) * 0.001, got])
			print("[lock]   ship groups: hittable=%s team=%d alive=%s" % [
				str(tgt.is_in_group("hittable")), tgt.team, str(tgt.is_alive())])
			world.get_tree().quit()
	return false
#endregion
