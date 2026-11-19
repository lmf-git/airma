class_name FlightTests
extends TestSuite
## Aircraft handling, helicopters, cockpit and camera rigs, airframe dressing
## and the AI's flying.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--hgeartest":
		_hgear_test = true
	elif a == "--hftest":
		_hf_test = true
	elif a.begins_with("--turntest="):
		_turn_test = float(a.substr(11))
	elif a == "--gunnertest":
		_gunner_test = true
	elif a == "--camtest":
		_cam_test = true
	elif a == "--hovertest":
		_hover_test = true
	elif a == "--roftest":
		_rof_test = true
	elif a == "--wcamtest":
		_wcam_test = true
	elif a == "--castest":
		_cas_test = true
	elif a == "--formtest":
		_form_test = true
	elif a == "--abtest":
		_ab_test = true
	elif a == "--acceltest":
		_accel_test = true
		world._auto = "dash"
	elif a == "--hoverhold":
		_hover2 = true
	elif a == "--adtest":
		_ad_test = true
	elif a == "--aptest":
		_ap_test = true
	elif a == "--fxtest":
		_fx_test = true
	elif a == "--wingtest":
		_wing_test = true
	elif a == "--lighttest":
		_light_test = true
	elif a.begins_with("--hudtest="):
		_hud_view = a.substr(10)
		_hud_test = true
	elif a == "--viewtest":
		_view_test = true
	elif a == "--flaptest":
		_flap_test = true
	elif a == "--seattest":
		_seat_test = true
	elif a == "--helitest":
		_heli_test = true
	elif a.begins_with("--ctltest="):
		_ctl_test = float(a.substr(10))
	elif a.begins_with("--tvctest="):
		_tvc_test = float(a.substr(10))
	elif a == "--boardtest":
		_board_test = true
	elif a == "--jolttest":
		_jolt_test = true
	elif a == "--overlaptest":
		_overlap_test = true
	else:
		return false
	return true


#region --hgeartest
## Whether the AI helicopters fly with their wheels up.
var _hgear_test := false
var _hgear_t := 0.0

func tick_hgear(delta: float) -> void:
	if _hgear_test and world.running:
		_hgear_t += delta
		if _hgear_t > 25.0:
			_hgear_test = false
			var up := 0
			var hanging := 0
			for n in world.get_tree().get_nodes_in_group("bandits") + world.get_tree().get_nodes_in_group("allies"):
				if not (n is AIHeli) or not (n as AIHeli).alive:
					continue
				var h := n as AIHeli
				var clear: float = h.global_position.y - Sim.height_at(h.global_position.x, h.global_position.z)
				print("[hgear] %s: %.0f m over the ground, gear %s (%.2f)" % [h.name, clear,
					"down" if h.gear_down else "up", h.gear_anim])
				if clear > 60.0:
					if h.gear_anim < 0.05:
						up += 1
					else:
						hanging += 1
			print("[hgear] RESULT: %s — %d flying with it up, %d with it hanging" % [
				"ok" if up > 0 and hanging == 0 else "FAILED", up, hanging])
			world.get_tree().quit()
#endregion


#region --hftest
## Hellfire and Hydra off a hovering helicopter at a lased spot, all round.
var _hf_test := false

func tick_hf() -> void:
	if _hf_test and world.running and is_instance_valid(world.player):
		_hf_test = false
		_run_hf_test()

## An Apache in a low hover, a spot lased fifteen hundred metres out at a few
## bearings off the nose, and a Hellfire and a Hydra at each: which way each
## goes off the rail and how close it comes.
func _run_hf_test() -> void:
	var bad: Array = []
	var heli: Aircraft = world.player
	var g0: float = Sim.height_at(heli.global_position.x, heli.global_position.z)
	# two of each aboard: dead ahead, and well off the nose
	for brg_deg in [0.0, 40.0]:
		for wid in ["agm114", "hydra"]:
			# a hover a hundred and fifty metres up, nose north, still
			var at := Vector3(heli.global_position.x, g0 + 150.0, heli.global_position.z)
			heli.global_transform = Transform3D(Basis(), at)
			heli.linear_velocity = Vector3.ZERO
			heli.angular_velocity = Vector3.ZERO
			if heli.has_method("set_hover_hold"):
				heli.call("set_hover_hold", true)
			await world.get_tree().physics_frame
			var b: float = deg_to_rad(brg_deg)
			var spot := Vector3(at.x + sin(b) * 1500.0, 0.0, at.z - cos(b) * 1500.0)
			spot.y = Sim.height_at(spot.x, spot.z)
			world.pod.platform = heli
			if not world.pod.active:
				world.pod.toggle()
			world.pod.mode = SensorPod.AREA
			world.pod.area_point = spot
			world.pod.tracked = null
			world.pod.designate()
			if not world.pod.lasing:
				world.pod.toggle_laser()
			for i in 6:
				await world.get_tree().process_frame
			var wi: int = heli.weapon_types.find(wid)
			if wi < 0:
				bad.append("no %s aboard" % wid)
				continue
			heli.set_weapon(wi)
			heli.target = world.pod._marker
			heli.fire_cd = 0.0
			var before := {}
			for n in world.get_tree().get_nodes_in_group("missiles"):
				before[n.get_instance_id()] = true
			var why: String = heli.fire()
			var m: Node3D = null
			for i in 30:
				for n in world.get_tree().get_nodes_in_group("missiles"):
					if not before.has(n.get_instance_id()):
						m = n
				if m != null:
					break
				await world.get_tree().physics_frame
			if m == null:
				print("[hf] %-6s at %+4.0f deg: did not go (%s)" % [wid, brg_deg, why])
				continue
			var p0: Vector3 = m.global_position
			var best := INF
			var first_dir := Vector3.ZERO
			var last: Vector3 = p0
			for f in 120 * 25:
				if not is_instance_valid(m):
					break
				var p: Vector3 = m.global_position
				if first_dir == Vector3.ZERO and p.distance_to(p0) > 30.0:
					first_dir = (p - p0).normalized()
				best = minf(best, p.distance_to(spot))
				last = p
				await world.get_tree().physics_frame
			var want := (spot - p0)
			var off: float = rad_to_deg(Vector2(first_dir.x, first_dir.z).angle_to(Vector2(want.x, want.z))) \
				if first_dir != Vector3.ZERO else 999.0
			print("[hf] %-6s at %+4.0f deg: left %+.0f deg off the line to the spot, came within %.0f m, last seen %.0f m from it" % [
				wid, brg_deg, off, best, last.distance_to(spot)])
			if best > 25.0:
				bad.append("%s at %.0f deg missed by %.0f m" % [wid, brg_deg, best])
	for x in bad:
		print("[hf] %s" % x)
	print("[hf] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --turntest=
var _turn_test := 0.0
var _turn_t := 0.0
var _turn_hdg := 0.0
var _turn_n := 0
var _turn_sum_g := 0.0
var _turn_sum_r := 0.0
var _turn_sum_a := 0.0
var _turn_sum_v := 0.0

func tick_turn(delta: float) -> void:
	if _turn_test > 0.0 and is_instance_valid(world.player):
		if _turn_t == 0.0:
			world.player.global_transform = Transform3D(Basis(), Vector3(0, 6000, 20000))
			world.player.linear_velocity = Vector3(0, 0, -_turn_test)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.throttle = 1.0
			world.player.power = 1.0
			world.player.auto = "turn"
			world.player.bank_deg = world._bank_deg if world._bank_deg != 0.0 else 80.0
			world.player.turn_speed = _turn_test
		_turn_t += delta
		var hb := world.player.global_transform.basis
		var hdg := atan2(hb.z.x, hb.z.z)
		var rate := rad_to_deg(wrapf(hdg - _turn_hdg, -PI, PI)) / maxf(delta, 1e-6)
		_turn_hdg = hdg
		# sample the steady part of the turn only: the first few seconds are the
		# roll-in, and anything past ten is a different aeroplane by then
		if _turn_t > 4.0 and _turn_t < 12.0:
			_turn_n += 1
			_turn_sum_g += world.player.g_load
			_turn_sum_r += absf(rate)
			_turn_sum_a += rad_to_deg(world.player.aoa)
			_turn_sum_v += world.player.linear_velocity.length()
		if _turn_t >= 12.0:
			var n := maxf(float(_turn_n), 1.0)
			var mv := _turn_sum_v / n
			var mr := _turn_sum_r / n
			print("[turn] %s assist=%-5s entry=%3.0f m/s -> mean tas=%5.1f  g=%4.2f  rate=%5.2f deg/s  radius=%6.0f m  aoa=%4.1f  bank=%5.1f  peak g=%4.2f  grey-out=%3.0f%%" % [
				str(world.player.spec["name"]), str(world.player.assist), _turn_test, mv,
				_turn_sum_g / n, mr, mv / maxf(deg_to_rad(mr), 1e-4),
				_turn_sum_a / n, rad_to_deg(atan2(-hb.x.y, hb.y.y)),
				world.player.g_peak, world.player.g_strain * 100.0])
			world.get_tree().quit()
#endregion


#region --gunnertest
var _gunner_test := false
var _gt := 0.0

func tick_gunner(delta: float) -> void:
	if _gunner_test and is_instance_valid(world.player):
		_gt += delta
		if _gt > 2.0 and not world.gunning:
			world.toggle_gunner()
		elif world.gunning and _gt > 3.0 and world.pod.mode == SensorPod.SLEW:
			# hold a spot on the ground, the way a gunner does before shooting:
			# it is the area track the rounds have to land on
			world.pod.designate()
		elif world.gunning and fmod(_gt, 3.0) < delta:
			var b := world.player.global_transform.basis
			var aim: Vector3 = world.pod.aim_point()
			# ...and whether the barrels can actually get there. The battery is
			# on trunnions with a real arc, so a sight that is holding a mark
			# the mount cannot train onto is a shot that will not be taken.
			var laid: bool = aim != Vector3.INF and world.player.lay_battery(aim)
			print("[gunner] t=%4.1f alt=%6.1f bank=%+5.1f spd=%5.1f  pod=%s  battery=%s  gun=%s" % [
				_gt, world.player.global_position.y, rad_to_deg(atan2(-b.x.y, b.y.y)),
				world.player.linear_velocity.length(),
				"locked" if aim != Vector3.INF else "no point",
				("on the mark" if laid else "cannot train (needs az %+.0f el %+.0f)" % [
					world.player.battery_need(aim).x, world.player.battery_need(aim).y]) if aim != Vector3.INF else "-",
				world.player.weapon_label(world.player.current_weapon())])
			if aim != Vector3.INF:
				world.player.fire_gunship(world, aim)
#endregion


#region --camtest
var _cam_test := false
var _cam_t := 0.0

func tick_cam(delta: float) -> void:
	if _cam_test and is_instance_valid(world.player) and world.cam:
		_cam_t += delta
		# sweep the look angles and report how the rig behaves
		world.cam.free_yaw = clampf(sin(_cam_t * 0.30) * 2.6, -2.7, 2.7)
		world.cam.free_pitch = clampf(sin(_cam_t * 0.19) * 1.1, -1.25, 1.25)
		world.cam.diag = true
		if fmod(_cam_t, 0.8) < delta and not world.cam.last_diag.is_empty():
			var d: Dictionary = world.cam.last_diag
			print("[cam] yaw=%+6.1f pitch=%+6.1f  boom=%5.1f m  jet off-centre=%5.2f deg" % [
				d["yaw"], d["pitch"], d["boom"], d["off"]])
#endregion


#region --hovertest
var _hover_test := false
var _hov_t := 0.0
var _hov_y0 := 0.0

func tick_hover(delta: float) -> void:
	if _hover_test and is_instance_valid(world.player):
		_hov_t += delta
		if _hov_t > 2.0 and world.player.auto != "hover":
			# well clear of the ground, and only once the mission has finished
			# putting the aeroplane where it wants it
			world.player.global_transform = Transform3D(Basis(), Vector3(0, 600, 4000))
			world.player.linear_velocity = Vector3(0, 0, -40.0)
			world.player.gear_down = true
			world.player.gear_anim = 1.0
			world._reset_interp(world.player)
			_hov_y0 = 600.0
			world.player.auto = "hover"
			world.player.hover_alt = _hov_y0
			world.player.hover_cmd = true
		elif _hov_t > 26.0:
			_hover_test = false
			var b := world.player.global_transform.basis
			print("[hover] %s: jetborne=%.2f  alt %.0f (target %.0f)  speed %.1f m/s  pitch %+.1f bank %+.1f  alive=%s" % [
				str(world.player.spec["name"]), world.player.jetborne, world.player.global_position.y, _hov_y0,
				world.player.linear_velocity.length(),
				rad_to_deg(asin(clampf(-b.z.y, -1.0, 1.0))),
				rad_to_deg(atan2(-b.x.y, b.y.y)), str(world.player.alive)])
			world.get_tree().quit()
#endregion


#region --roftest
## Hold each of the gunship's guns down for six seconds and count what leaves:
## --rofltest, with --preset=free:ac130.
var _rof_test := false
var _rof_t := 0.0

func tick_rof(delta: float) -> void:
	if _rof_test and world.running and is_instance_valid(world.player):
		_rof_t += delta
		if _rof_t > 3.0:
			_rof_test = false
			_run_rof_test()

func _run_rof_test() -> void:
	for gid in ["g105", "g40", "g25"]:
		# off the port beam, from wherever the aeroplane has got to, so every gun
		# is measured inside the battery's arc
		var aim: Vector3 = world.player.global_position + (-world.player.global_transform.basis.x) * 2500.0
		aim.y = Sim.height_at(aim.x, aim.z)
		var wi: int = world.player.weapon_types.find(gid)
		if wi < 0:
			print("[rof] %s not carried" % gid)
			continue
		world.player.set_weapon(wi)
		world.player.gun_cd = 0.0
		world.player.battery_cd.clear()
		var before: int = world.get_tree().get_nodes_in_group("shells").size()
		var shots := 0
		var t := 0.0
		while t < 6.0:
			if world.player.fire_gunship(world, aim):
				shots += 1
			await world.get_tree().physics_frame
			t += 1.0 / float(Engine.physics_ticks_per_second)
		var g: Dictionary = world.player.gunship_gun()
		print("[rof] %s held 6 s: %d shots fired (table %d rpm = %.1f in 6 s), %d shells in the air" % [
			gid, shots, int(g.get("rpm", 0)), float(g.get("rpm", 0)) / 10.0,
			world.get_tree().get_nodes_in_group("shells").size() - before])
	world.get_tree().quit()
#endregion


#region --wcamtest
var _wcam_test := false
var _wcam_t := 0.0

func tick_wcam(delta: float) -> void:
	if _wcam_test and is_instance_valid(world.player) and world.cam:
		_wcam_t += delta
		if _wcam_t > 2.5 and not world.weapon_cam_on:
			world.weapon_cam_on = true
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			world.player.locked = true
			world.player.fire_cd = 0.0
			world.player.set_weapon(maxi(world.player.weapon_types.find("aim120"), 0))
			world.player.fire()
			world.cam.diag = true
			world.cam.wcam_jitter = 0.0
			world.cam.wcam_jsum = 0.0
			world.cam.wcam_jn = 0
		elif _wcam_t > 12.0:
			_wcam_test = false
			var riding: bool = world.cam.weapon_cam != null and is_instance_valid(world.cam.weapon_cam)
			var d := -1.0
			if riding:
				d = world.cam.global_position.distance_to((world.cam.weapon_cam as Node3D).global_position)
			# How steady the ride is: the frame-to-frame change in the boom
			# vector from the round to the camera. A rigid follow holds it near
			# zero; a camera stepping at the physics rate while the round is
			# drawn interpolated moves a whole tick of travel every frame.
			print("[wcam] armed=%s riding a round=%s, camera %.1f m from it" % [
				str(world.weapon_cam_on), str(riding), d])
			print("[wcam] boom wobble over %d frames: mean %.3f m, worst %.3f m" % [
				world.cam.wcam_jn, world.cam.wcam_jsum / maxf(float(world.cam.wcam_jn), 1.0),
				world.cam.wcam_jitter])
			world.get_tree().quit()
#endregion


#region --castest
var _cas_test := false
var _cas_t := 0.0
var _cas_said := 0
var _cas_hp := {}

# What the aeroplanes that are not fighters actually do: does the mud mover
# find something on the ground, roll in on it and hurt it, and does the
# transport get anywhere.
func tick_cas(delta: float) -> void:
	if _cas_test:
		_cas_t += delta
		if _cas_t > 2.0 and _cas_hp.is_empty():
			# Its own scenario: the shipping is stood down so the movers are not
			# spending the whole run defending against naval SAMs, and the mud
			# is put where an aeroplane can get at it.
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
					v.cells_left = 0
			var seed_at := Vector3(2000.0, 0.0, -6000.0)
			for i in 4:
				var g := GroundTarget.new()
				g.team = 0
				g.setup(["sam", "radar", "fuel", "hangar"][i])
				world.add_child(g)
				var gp := seed_at + Vector3(float(i) * 260.0 - 400.0, 0, float(i) * 190.0)
				g.global_position = Vector3(gp.x, Sim.height_at(gp.x, gp.z), gp.z)
				g.name = "CAS target %d" % (i + 1)
			for n in world.get_tree().get_nodes_in_group("bandits"):
				var a := n as AIPlane
				if a == null or a.role != "cas":
					continue
				# put them fifteen kilometres out, pointed at the target area
				var start := seed_at + Vector3(-13000.0, 0, -7000.0 + float(a._runs) * 900.0)
				a.global_transform = Transform3D(Basis(),
					Vector3(start.x, Sim.height_at(start.x, start.z) + 3200.0, start.z))
				a.look_at_from_position(a.global_position, seed_at, Vector3.UP)
				a.linear_velocity = -a.global_transform.basis.z * 180.0
				world._reset_interp(a)
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if is_instance_valid(n) and not (n is Aircraft) and ("team" in n):
					_cas_hp[n.get_instance_id()] = [n, float(n.get("health"))]
			print("[cas] watching %d ground and surface targets" % _cas_hp.size())
		elif _cas_t > 2.0:
			var step := int(_cas_t / 12.0)
			if step > _cas_said:
				_cas_said = step
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or a.role == "fighter":
						continue
					var hr := -1.0
					if is_instance_valid(a.target):
						hr = Vector2(a.target.global_position.x - a.global_position.x,
							a.target.global_position.z - a.global_position.z).length()
					print("[cas] %6.1fs %-14s %-9s st=%d runs=%d alt %5.0f rng %6.0f spd %3.0f pit %+.2f rol %+.2f aoa %+4.1f stall=%s gun %d near %.0f ang %.1f tgt=%s" % [
						_cas_t, a.name, a.role, a.state, a._runs,
						a.global_position.y, hr, a.linear_velocity.length(),
						a.in_pitch, a.in_roll, rad_to_deg(a.aoa), str(a.stalling), a.ammo,
						a.min_slant, a.min_ang,
						String(a.target.name) if is_instance_valid(a.target) else "none"])
			if _cas_t > 150.0:
				_cas_test = false
				var hurt := 0
				var killed := 0
				for k in _cas_hp:
					var e: Array = _cas_hp[k]
					if not is_instance_valid(e[0]):
						killed += 1
					elif float(e[0].get("health")) < float(e[1]) - 0.5:
						hurt += 1
				var movers := 0
				var hauls := 0
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null:
						continue
					if a.role == "cas":
						movers += 1
						print("[cas] RESULT: %s made %d attack runs, %d rounds left; closest %.0f m, best nose-on %.1f deg" % [
							a.name, a._runs, a.ammo, a.min_slant, a.min_ang])
					elif a.role == "transport":
						hauls += 1
						print("[cas] RESULT: %s on leg %d at %.0f m, %.0f m agl" % [
							a.name, a._leg, a.global_position.y, a.agl])
				print("[cas] RESULT: %d movers and %d transports still up; %d targets damaged, %d destroyed" % [
					movers, hauls, hurt, killed])
				world.get_tree().quit()
#endregion


#region --formtest
var _form_test := false
var _form_t := 0.0
var _form_said := 0
var _form_sum := 0.0
var _form_n := 0
var _form_worst := 0.0

# Do the wingmen actually sit in the slot, and does the AI use the terrain.
func tick_form(delta: float) -> void:
	if _form_test:
		_form_t += delta
		if _form_t > 1.5 and _form_said == 0:
			_form_said = -1
			# Nothing to fight: the point of this test is the slot, not the
			# engagement, and a flight that splits for a bandit is measuring
			# how far apart two aeroplanes in a dogfight get.
			if is_instance_valid(world.player):
				world.player.global_position = Vector3(0.0, 9000.0, 62000.0)
				world.player.team = 9
				world._reset_interp(world.player)
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null:
					v.ai = false
					v.cells_left = 0
			for g in world.get_tree().get_nodes_in_group("ground_targets"):
				if is_instance_valid(g):
					g.queue_free()
		if _form_t > 3.0:
			var step := int((_form_t - 3.0) / 15.0) + 1
			if step > maxi(_form_said, 0):
				_form_said = step
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or not is_instance_valid(a.leader):
						continue
					var want: Vector3 = a.leader.global_transform * a.slot
					var lcl: Vector3 = a.leader.global_transform.affine_inverse() \
						* a.global_position - a.slot
					print("[form] %6.1fs %-12s slot err %6.1f m form=%s st=%d  dx %+6.0f dy %+6.0f dz %+6.0f  thr %.2f rol %+.2f pit %+.2f  spd %3.0f/%3.0f" % [
						_form_t, a.name, a.global_position.distance_to(want),
						str(a.formating), a.state, lcl.x, lcl.y, lcl.z,
						a.throttle, a.in_roll, a.in_pitch,
						a.linear_velocity.length(), a.leader.linear_velocity.length()])
			# sample the settled error continuously, not just at the marks
			if _form_t > 40.0:      # after the rejoin: what it actually holds
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a == null or not is_instance_valid(a.leader):
						continue
					# only while he is actually flying the slot: a wingman who
					# has broken off to attack something is not station keeping
					# badly, he is doing his job
					if not a.formating:
						continue
					var e: float = a.global_position.distance_to(
						a.leader.global_transform * a.slot)
					_form_sum += e
					_form_worst = maxf(_form_worst, e)
					_form_n += 1
			if _form_t > 75.0:
				_form_test = false
				var n_wings := 0
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a != null and is_instance_valid(a.leader):
						n_wings += 1
				var busy := 0
				for n in world.get_tree().get_nodes_in_group("bandits"):
					var a := n as AIPlane
					if a != null and is_instance_valid(a.leader) and not a.formating:
						busy += 1
				print("[form] RESULT: %d wingmen (%d off doing something else); while in the slot, over %d samples mean error %.1f m, worst %.1f m" % [
					n_wings, busy, _form_n, _form_sum / maxf(float(_form_n), 1.0),
					_form_worst])
				world.get_tree().quit()
#endregion


#region --abtest
var _ab_test := false

func tick_ab() -> bool:
	if _ab_test:
		_ab_test = false
		var bad := 0
		for id in JetSpec.ids():
			var sp := JetSpec.get_spec(id)
			var reheat: bool = float(sp.get("thrust_ab", 0.0)) \
				> float(sp.get("thrust_mil", 1.0)) * 1.04
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			world.add_child(root)
			var plumes: int = (m["ab"] as Array).size()
			var lit: int = (m["burners"] as Array).size()
			# and does anything in the exhaust actually emit
			var glow := 0.0
			for n in root.find_children("Burner", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
					continue
				var sm := mi.mesh.surface_get_material(0) as StandardMaterial3D
				if sm != null and sm.emission_enabled:
					glow = maxf(glow, sm.emission.get_luminance())
			var wrong: bool = (not reheat) and (plumes > 0 or lit > 0 or glow > 0.001)
			if wrong:
				bad += 1
			print("[ab] %-8s reheat=%-5s  plume cones %d, lit exhausts %d, exhaust emission %.3f%s" % [
				id, str(reheat), plumes, lit, glow, "   <- SHOULD NOT GLOW" if wrong else ""])
			root.queue_free()
		print("[ab] RESULT: %s" % ("ok" if bad == 0 else
			"FAILED — %d airframe(s) glow without reheat" % bad))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --acceltest
var _accel_test := false

# Which aeroplanes light up at the back. A turbofan with no reheat should
# have nothing glowing in its exhaust and no plume behind it.
func tick_accel() -> bool:
	if _accel_test:
		_accel_test = false
		# Full burner, level, from a standing start in the air: how long the
		# aeroplane actually takes to get up to speed, and what it tops out at.
		await world.get_tree().physics_frame
		if not is_instance_valid(world.player):
			print("[accel] no aeroplane")
			world.get_tree().quit()
			return true
		# An empty sky. This is a measurement of what the airframe can do, and
		# the first three attempts were measuring how long it survives: a SAM
		# killed it at twenty-eight seconds, and a dead aeroplane stops running
		# its force model, so the frozen readouts looked exactly like a speed
		# it could not pass.
		for n in world.get_tree().get_nodes_in_group("hittable"):
			if n != world.player and is_instance_valid(n):
				n.queue_free()
		for m2 in world.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m2):
				m2.queue_free()
		await world.get_tree().physics_frame
		world.player.global_position = Vector3(0.0, world._dash_alt, 0.0)
		world.player.linear_velocity = -world.player.global_transform.basis.z * 180.0
		world.player.fuel = maxf(world.player.fuel, 1000.0)
		# clean: a dash test with the gear hanging out is measuring the gear
		world.player.gear_down = false
		world.player.flaps = 0.0
		if "airbrake" in world.player:
			world.player.airbrake = false
		var t_start := -1.0
		var t_mach1 := -1.0
		var best_m := 0.0
		var best_v := 0.0
		var clock := 0.0
		for f in 36000:                                   # five minutes
			await world.get_tree().physics_frame
			if not is_instance_valid(world.player):
				break
			clock += 1.0 / 120.0
			# Nothing is allowed to shoot the test article down. The first run
			# of this had it killed by a SAM at twenty-eight seconds, and since
			# the force model stops running on a dead aeroplane the readouts
			# froze -- which read exactly like the aircraft hitting a speed it
			# could not pass.
			world.player.health = 100.0
			var m: float = world.player.mach
			if t_start < 0.0 and m >= 0.60:
				t_start = clock
			if t_mach1 < 0.0 and m >= 1.20:
				t_mach1 = clock
			if m > best_m:
				best_m = m
				best_v = world.player.linear_velocity.length()
			if f % 1200 == 0:
				print("[accel] t=%5.1f s  mach %.2f  %4.0f m/s  %4.0f kt IAS  alt %5.0f  agl %5.0f  thr %.2f  alive=%s ghost=%s hp %.0f  aoa %.1f  pitch %.1f" % [
					clock, m, world.player.linear_velocity.length(),
					world.player.ias * 1.94384, world.player.global_position.y,
					world.player.agl, world.player.power, str(world.player.alive),
					str(world.player.ghost), world.player.health,
					rad_to_deg(world.player.aoa),
					rad_to_deg(asin(clampf(
						-world.player.global_transform.basis.z.y, -1.0, 1.0)))])
		print("[accel] mach 0.6 at %.1f s, mach 1.2 at %.1f s -> %.1f s to accelerate" % [
			t_start, t_mach1, t_mach1 - t_start])
		print("[accel] best mach %.2f (%.0f m/s) at %.0f m" % [
			best_m, best_v, world._dash_alt])
		world.get_tree().quit()
		return true
	return false
#endregion


#region --hoverhold
var _hover2 := false
var _hover2_t := 0.0
var _hover2_step := 0
var _hover2_at := Vector3.ZERO
var _hover2_drift := 0.0
var _hover2_bank := 0.0
var _hover2_alt := 0.0

func tick_hover2(delta: float) -> bool:
	if _hover2 and is_instance_valid(world.player):
		_hover2_t += delta
		match _hover2_step:
			0:
				if _hover2_t > 2.5:
					if not (world.player is PlayerHeli):
						print("[hover] not a helicopter — use --jet=ah64")
						_hover2 = false
						world.get_tree().quit()
						return true
					_hover2_step = 1
					_hover2_t = 0.0
					# Thrown at it: twenty degrees of bank, a shove sideways and
					# forwards, and a climb on. A hover that only works from
					# straight and level is not a hover.
					var g0: float = Sim.height_at(0.0, -400.0)
					world.player.global_transform = Transform3D(
						Basis(Vector3(0, 0, -1), deg_to_rad(20.0)),
						Vector3(0.0, g0 + 260.0, -400.0))
					world.player.linear_velocity = Vector3(14.0, 3.0, -11.0)
					world.player.angular_velocity = Vector3(0.2, 0.0, 0.15)
					world._reset_interp.call_deferred(world.player)
			1:
				if _hover2_t > 0.6:
					_hover2_step = 2
					_hover2_t = 0.0
					(world.player as PlayerHeli).set_hover_hold(true)
					_hover2_at = world.player.global_position
					# deviations, not absolutes: seeding this with the altitude
					# itself scored a perfect hover as 262 m out
					_hover2_alt = 0.0
					_hover2_drift = 0.0
					_hover2_bank = 0.0
			2:
				if fmod(_hover2_t, 2.0) < delta:
					var hh := world.player as PlayerHeli
					var bb := world.player.global_transform.basis
					var fw := -bb.z
					fw.y = 0.0
					fw = fw.normalized() if fw.length_squared() > 0.01 else Vector3.FORWARD
					var rr2 := bb.x
					rr2.y = 0.0
					rr2 = rr2.normalized() if rr2.length_squared() > 0.01 else Vector3.RIGHT
					var of := world.player.global_position - hh._hover_at
					print("[hov] t=%4.1f  ahead=%6.1f stbd=%6.1f  v=%5.2f  bank=%5.1f pitch=%5.1f  in_roll=%5.2f in_pitch=%5.2f thr=%.2f" % [
						_hover2_t, of.dot(fw), of.dot(rr2),
						world.player.linear_velocity.length(),
						rad_to_deg(atan2(-bb.x.y, bb.y.y)),
						rad_to_deg(asin(clampf(-bb.z.y, -1.0, 1.0))),
						world.player.in_roll, world.player.in_pitch, world.player.throttle])
				# Judge the steady state, not the settling. It is arresting
				# eighteen metres a second when the hold is engaged and the
				# recovery takes the better part of twenty seconds, so a window
				# opening at fifteen was still measuring the return: it scored
				# a hover that finished 1.3 m from the spot as 33 m out.
				if _hover2_t > 26.0:
					var b3 := world.player.global_transform.basis
					_hover2_bank = maxf(_hover2_bank,
						absf(rad_to_deg(atan2(-b3.x.y, b3.y.y))))
					_hover2_drift = maxf(_hover2_drift, Vector2(
						world.player.global_position.x - _hover2_at.x,
						world.player.global_position.z - _hover2_at.z).length())
					_hover2_alt = maxf(_hover2_alt,
						absf(world.player.global_position.y - _hover2_at.y))
				if _hover2_t > 32.0:
					_hover2 = false
					var spd: float = world.player.linear_velocity.length()
					print("[hover] steady state (last 6 s): %.1f m off the spot, %.1f deg of bank, %.1f m of height, %.2f m/s" % [
						_hover2_drift, _hover2_bank, _hover2_alt, spd])
					var ok: bool = _hover2_drift < 8.0 and _hover2_bank < 8.0 \
						and _hover2_alt < 6.0 and spd < 1.0
					print("[hover] RESULT: %s" % ("ok" if ok else
						"FAILED — it does not hold"))
					world.get_tree().quit()
		return true
	return false
#endregion


#region --adtest
var _ad_test := false
var _ad_t := 0.0
var _ad_step := 0
var _ad_veh: Array = []
var _ad_hp0 := 0.0
var _ad_shots := 0
var _ad_erect := 0.0

func tick_ad(delta: float) -> bool:
	if _ad_test:
		_ad_t += delta
		if _ad_step == 0 and not is_instance_valid(world.player):
			return true
		if _ad_step == 0 and _ad_t > 2.5:
			_ad_step = 1
			# a battery and a gun, hostile, with the player flying at them
			var at := Vector3(2400.0, 0.0, -3200.0)
			for pair in [["s400", -160.0], ["shilka", 160.0]]:
				var v := world._spawn_tank(at + Vector3(float(pair[1]), 0.0, 0.0),
					0.0, 1, String(pair[0]))
				v.ai = true
				_ad_veh.append(v)
			_ad_hp0 = world.player.health
			# put the aeroplane where both of them can reach it: three
			# kilometres out at fifteen hundred feet, running in
			# Height above the GROUND, not above the sea: this valley floor is
			# not at zero, and the first cut of this put the aeroplane at 2252 m
			# agl, well above the gun's reach.
			var gy: float = Sim.height_at(at.x, at.z + 3000.0)
			world.player.global_transform = Transform3D(Basis(),
				Vector3(at.x, gy + 700.0, at.z + 3000.0))
			world.player.linear_velocity = Vector3(0, 0, -170.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.throttle = 0.7
			world._reset_interp.call_deferred(world.player)
			print("[ad] %s and %s up, aeroplane %.0f m out at %.0f m agl" % [
				(_ad_veh[0] as Tank).display_name(),
				(_ad_veh[1] as Tank).display_name(),
				world.player.global_position.distance_to(at), world.player.agl])
		elif _ad_step == 1:
			for v in _ad_veh:
				if is_instance_valid(v):
					_ad_shots = maxi(_ad_shots,
						int(KINDS_ROUNDS_FIRED(v as Tank)))
					# Peak, not final. A battery lowers its rails again once the
					# magazine is empty — which is correct, and meant the end of
					# this test read 0.00 on a launcher that had just fired
					# everything it had.
					_ad_erect = maxf(_ad_erect, float((v as Tank)._erect))
			var gone: bool = not is_instance_valid(world.player) or not world.player.alive
			if _ad_t > 50.0 or gone:
				_ad_test = false
				var missiles := 0
				for m in world.get_tree().get_nodes_in_group("missiles"):
					if m is Missile and String(m.wid) == "sam_med":
						missiles += 1
				var hurt: float = _ad_hp0
				if is_instance_valid(world.player) and world.player.alive:
					hurt = _ad_hp0 - world.player.health
				print("[ad] rails reached %.2f, %d round(s) sent, %d still up, the aeroplane lost %.0f hp (alive=%s)" % [
					_ad_erect, _ad_shots, missiles, hurt,
					str(is_instance_valid(world.player) and world.player.alive)])
				var ok: bool = _ad_erect > 0.9 and _ad_shots > 0 and hurt > 0.0
				print("[ad] RESULT: %s" % ("ok" if ok else
					"FAILED — the air defence did nothing"))
				world.get_tree().quit()
		return true
	return false

## Every external station and every navigation lamp, measured against the wing
## planform it is supposed to be attached to. A store is on the wing when its
## mounting point is inboard of the tip and between the leading and trailing
## edges at that station; a lamp when it is at the tip.
## Rounds a launcher has sent, which is its magazine minus what is left.
func KINDS_ROUNDS_FIRED(t: Tank) -> int:
	var kd: Dictionary = Tank.KINDS[t.kind]
	return maxi(int(kd.get("rounds", kd.get("salvo", 1))) - t.rounds_left, 0)
#endregion


#region --aptest
var _ap_test := false
var _ap_t := 0.0
var _ap_step := 0
var _ap_alt0 := 0.0
var _ap_drift := 0.0
var _ap_swept := 0.0
var _ap_last_hdg := 0.0
var _ap_note: Array = []
var _ap_hold_drift := 0.0
var _ap_right := 0.0
var _ap_left := 0.0
var _ap_orbit_drift := 0.0

func tick_ap(delta: float) -> bool:
	if _ap_test and is_instance_valid(world.player):
		_ap_t += delta
		match _ap_step:
			0:
				if _ap_t > 2.0:
					_ap_step = 1
					_ap_t = 0.0
					world.player.global_transform = Transform3D(Basis(),
						world.player.global_position + Vector3(0, 1200.0, 0))
					world.player.linear_velocity = -world.player.global_transform.basis.z * 90.0
					world.player.gear_down = false
					world.player.gear_anim = 0.0
					world.player.throttle = 0.6
					world._reset_interp.call_deferred(world.player)
			1:
				if _ap_t > 6.0:
					_ap_step = 2
					_ap_t = 0.0
					_ap_alt0 = world.player.global_position.y
					_ap_drift = 0.0
					world.player.set_autopilot("hold")
			2:
				_ap_drift = maxf(_ap_drift,
					absf(world.player.global_position.y - _ap_alt0))
				if _ap_t > 45.0:
					_ap_hold_drift = _ap_drift
					_ap_note.append("hold: %.0f m of drift over 45 s from %.0f m" % [
						_ap_drift, _ap_alt0])
					_ap_step = 3
					_ap_t = 0.0
					_ap_alt0 = world.player.global_position.y
					_ap_drift = 0.0
					_ap_swept = 0.0
					_ap_last_hdg = world.player.global_rotation.y
					world.player.ap_turn = 1.0
					world.player.set_autopilot("loiter")
			3:
				_ap_drift = maxf(_ap_drift,
					absf(world.player.global_position.y - _ap_alt0))
				# signed, so a turn that reverses cancels instead of accruing
				var h: float = world.player.global_rotation.y
				_ap_swept += wrapf(h - _ap_last_hdg, -PI, PI)
				_ap_last_hdg = h
				if _ap_t > 60.0:
					_ap_right = rad_to_deg(_ap_swept)
					_ap_orbit_drift = _ap_drift
					_ap_note.append("orbit right: %.0f deg of yaw swept in 60 s (right hand is negative about +Y), %.0f m of height lost or gained" % [
						_ap_right, _ap_drift])
					_ap_step = 4
					_ap_t = 0.0
					_ap_swept = 0.0
					_ap_last_hdg = world.player.global_rotation.y
					world.player.toggle_orbit_direction()
			4:
				var h2: float = world.player.global_rotation.y
				_ap_swept += wrapf(h2 - _ap_last_hdg, -PI, PI)
				_ap_last_hdg = h2
				if _ap_t > 60.0:
					_ap_left = rad_to_deg(_ap_swept)
					_ap_note.append("orbit reversed: %.0f deg swept in 60 s" % _ap_left)
					_ap_test = false
					for n in _ap_note:
						print("[ap] %s" % String(n))
					# A hold that wanders more than a hundred metres is not a
					# hold.
					#
					# The orbit rate is not a free choice: at thirty degrees of
					# bank a turn comes out at g*tan(30)/V, which for a drone
					# at ninety metres a second is 3.6 degrees a second, or
					# about 216 in a minute. That is what to expect, and a fast
					# aeroplane will sweep less for the same bank.
					#
					# Sign, not magnitude, is what tells the two directions
					# apart — and a right hand turn *decreases* yaw about +Y,
					# so a right orbit sweeps negative.
					var held: bool = _ap_hold_drift < 100.0
					# An orbit to a radius is a slow, wide circle by design —
					# a couple of minutes a lap — so this asks that it goes
					# round steadily and in the right direction, not that it
					# whips round.
					var circled: bool = _ap_right < -90.0 and _ap_orbit_drift < 250.0
					var reversed: bool = _ap_left > 90.0
					print("[ap] RESULT: %s" % ("ok" if held and circled and reversed
						else "FAILED — %s%s%s" % [
							"" if held else "the hold drifts; ",
							"" if circled else "the orbit does not go round; ",
							"" if reversed else "reversing it did not"]))
					world.get_tree().quit()
		return true
	return false
#endregion


#region --fxtest
var _fx_test := false

# What comes off a wingtip: a filament, or a bag of balls.
func tick_fx() -> bool:
	if _fx_test:
		_fx_test = false
		var bad := 0
		for id in ["f22", "f16", "su35", "a320"]:
			var sp := JetSpec.get_spec(id)
			var m := JetFactory.build(sp)
			var root: Node3D = m["root"]
			world.add_child(root)
			var jet := Aircraft.new()
			jet.spec = sp
			var tips: Array = m.get("tips", [])
			root.queue_free()
			if tips.is_empty():
				print("[fx] %-6s has no wingtips" % id)
				continue
			var p := Effects.vortex_particles(Color(1, 1, 1), 3.2, 40)
			var qm := p.draw_pass_1 as QuadMesh
			var mat := qm.material as StandardMaterial3D
			var pm := p.process_material as ParticleProcessMaterial
			var aspect: float = qm.size.y / maxf(qm.size.x, 0.0001)
			var spun: float = absf(pm.angle_max - pm.angle_min)
			var lined: bool = mat.billboard_mode == BaseMaterial3D.BILLBOARD_PARTICLES
			var wrong: bool = aspect < 6.0 or spun > 1.0 or not lined
			if wrong:
				bad += 1
			print("[fx] %-6s %d tip(s): quad %.2f x %.2f (aspect %.1f), spin %.0f deg, %s%s" % [
				id, tips.size(), qm.size.x, qm.size.y, aspect, spun,
				"aligned to travel" if lined else "camera facing only",
				"   <- READS AS A BALL" if wrong else ""])
			jet.free()
		print("[fx] RESULT: %s" % ("ok" if bad == 0 else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --wingtest
## Do the things bolted to the wing actually touch it? Pylon and wingtip
## stations, and the navigation lamps, were placed by eye and from half the span
## in the data table, so on a swept planform they finished up outboard of the
## tip and well ahead of the chord -- Sidewinders and a red lamp hanging in
## clear air beside the F-16.
var _wing_test := false
var _wing_t := 0.0

func tick_wing(delta: float) -> bool:
	if _wing_test:
		_wing_t += delta
		if _wing_t > 1.0:
			_wing_test = false
			_run_wing_test()
			world.get_tree().quit()
		return true
	return false

func _run_wing_test() -> void:
	var bad := 0
	for id in JetSpec.ids():
		var spec := JetSpec.get_spec(id)
		var poly: Array = spec["shape"]["wing"]["poly"]
		var tip_x: float = JetFactory._tip_x(poly)
		var root_x: float = float((poly[0] as Vector2).x)
		var m := JetFactory.build(spec)
		var worst := 0.0
		var worst_what := ""
		var checked := 0
		for bay in spec.get("bays", []):
			if String(bay.get("kind", "internal")) != "external":
				continue               # internal, and none of this applies
			for si in (bay["stations"] as Array).size():
				var stn: Dictionary = bay["stations"][si]
				var key := str(bay["id"], "#", si)
				var h: Node3D = m["stores"][key]
				var ax: float = absf(h.position.x)
				if ax + 0.05 < root_x:
					continue           # a fuselage or centreline station
				checked += 1
				var c: Vector2 = JetFactory._chord_at(poly, minf(ax, tip_x))
				# A pylon store hangs from the point it is bolted to, so that
				# point has to be on the wing. A wingtip rail is short and the
				# round is long: what has to touch the wing there is the body
				# of the round, which properly overhangs forward.
				var z0: float = h.position.z
				var z1: float = h.position.z
				if bool(stn.get("tip", false)):
					var ln: float = float(WeaponSpec.get_spec(
						String(stn["weapon"])).get("length", 3.0)) * 0.5
					z0 -= ln
					z1 += ln
				var off: float = maxf(ax - tip_x, 0.0) \
					+ maxf(c.x - z1, 0.0) + maxf(z0 - c.y, 0.0)
				if off > worst:
					worst = off
					worst_what = key
		for lm in m["lights"]:
			checked += 1
			var ax2: float = absf((lm as Node3D).position.x)
			var c2: Vector2 = JetFactory._chord_at(poly, minf(ax2, tip_x))
			var off2: float = absf(ax2 - tip_x) \
				+ maxf(c2.x - lm.position.z, 0.0) + maxf(lm.position.z - c2.y, 0.0)
			if off2 > worst:
				worst = off2
				worst_what = "nav lamp"
		(m["root"] as Node3D).queue_free()
		var ok: bool = worst < 0.20
		if not ok:
			bad += 1
		print("[wing] %-8s %2d fitting(s), worst %5.2f m clear of the wing%s%s" % [
			id, checked, worst,
			"" if worst_what == "" else " (%s)" % worst_what,
			"" if ok else "   <- OFF THE WING"])
	print("[wing] RESULT: %s" % ("ok" if bad == 0 else
		"FAILED — %d aircraft carry something that is not on the wing" % bad))
#endregion


#region --lighttest
## Can the pilot switch the navigation lights off? They were always on and
## there was nothing anywhere -- key or menu -- that turned them off, so going
## dark for a night ingress was not something the aeroplane could do.
var _light_test := false
var _light_t := 0.0

# Every crewable vehicle the menu offers: pick it, and see what you get.
func tick_light(delta: float) -> bool:
	if _light_test:
		_light_t += delta
		# The switches live on the aeroplane, so put one in the air first: the
		# harness is not run from a preset.
		if _light_t > 1.0 and not is_instance_valid(world.player):
			world._start("f16", "free")
			return true
		if _light_t > 2.5 and is_instance_valid(world.player):
			_light_test = false
			_run_light_test()
			world.get_tree().quit()
		return true
	return false

## The TAB menu offers the lights, and choosing them actually works them.
func _run_light_test() -> void:
	var bad := 0
	world.actions.open_for(world.player)
	var ids := PackedStringArray()
	for it in world.actions.items:
		ids.append(String(it["id"]))
	for want in ["nav", "lamp"]:
		if not ids.has(want):
			bad += 1
			print("[light] the TAB menu has no '%s' entry" % want)
	# lit to begin with, as a real aeroplane is
	var lit := 0
	for l in world.player._nav:
		if is_instance_valid(l) and (l as Node3D).visible:
			lit += 1
	for b in world.player._nav_bulbs:
		if is_instance_valid(b) and (b as Node3D).visible:
			lit += 1
	print("[light] %d lamp(s) burning with the navigation lights on" % lit)
	if lit < 5:
		bad += 1                    # three lights and at least two bulbs
	world._do_action("nav")
	var still := 0
	for l in world.player._nav:
		if is_instance_valid(l) and (l as Node3D).visible:
			still += 1
	for b in world.player._nav_bulbs:
		if is_instance_valid(b) and (b as Node3D).visible:
			still += 1
	print("[light] %d still burning after switching them off" % still)
	if still != 0 or world.player.nav_on:
		bad += 1
	world._do_action("nav")
	if not world.player.nav_on:
		bad += 1
		print("[light] they would not come back on")
	# and the landing lamp, which had a key but no menu entry
	var was: bool = world.player.lights_on
	world._do_action("lamp")
	if world.player.lights_on == was:
		bad += 1
		print("[light] the landing lamp did not answer the menu")
	print("[light] RESULT: %s" % ("ok" if bad == 0 else
		"FAILED — %d fault(s) in the lighting controls" % bad))
#endregion


#region --hudtest=
var _hud_test := false
var _hud_view := ""
var _hud_t := 0.0

func tick_hud(delta: float) -> void:
	if _hud_test and is_instance_valid(world.player) and world.cam:
		_hud_t += delta
		if _hud_t > 2.5:
			_hud_test = false
			world.cam.mode = {"cockpit": 0, "chase": 1, "orbit": 2}.get(_hud_view, 0)
			# let the gate run one more frame with the new mode
			world.hud.flight_page = (world.cam.mode == ChaseCamera.Mode.COCKPIT) \
			and not is_instance_valid(world.cam.weapon_cam)
			print("[hud] view=%s -> flight page drawn: %s" % [_hud_view, str(world.hud.flight_page)])
			_check_hud_keys()
			world.get_tree().quit()

## Every control the HUD names, against the binding it is actually on. These
## labels are written out by hand in the help tables, so when a key moves the
## page has to be edited to match -- and when the countermeasures moved, the
## help page was edited and the flight strip was not. It went on telling you to
## press N for flares and B for chaff long after they were C and V.
func _check_hud_keys() -> void:
	# what the page says a control is called -> the action it is really bound to
	var want := {
		"flares": &"flare", "chaff": &"chaff", "gun burst": &"gun",
		"cycle target": &"cycle_target", "cycle weapon": &"cycle_weapon",
		"night vision": &"night_vision", "tactical map": &"map",
		"laser": &"laser", "fly-by-wire on / off": &"assist",
		"cockpit / chase / orbit": &"camera",
	}
	var bad := 0
	var seen := 0
	for group in world.hud._air_keys():
		for row in (group[1] as Array):
			var desc := String(row[1])
			if not want.has(desc):
				continue
			seen += 1
			var shown := String(row[0])
			var real: String = Sim.key_label(want[desc])
			var ok: bool = shown == real
			if not ok:
				bad += 1
			print("[hud] %-24s page says %-4s binding is %-4s%s" % [
				desc, shown, real, "" if ok else "   <- STALE"])
	print("[hud] %d control(s) checked" % seen)
	print("[hud] RESULT: %s" % ("ok" if bad == 0 else
		"FAILED — %d label(s) name a key the control is not on" % bad))
#endregion


#region --viewtest
var _view_test := false
var _view_t := 0.0

func tick_view(delta: float) -> void:
	if _view_test and is_instance_valid(world.player) and world.cam:
		_view_t += delta
		if _view_t > 2.0:
			_view_test = false
			# Anything in the cockpit that reaches above the eye line and sits
			# ahead of it is in the way. Measured off the meshes rather than by
			# raycast: the furniture is decoration and carries no collider.
			var eye: Vector3 = world.player.cockpit_offset()
			var worst := -9.0
			var worst_nm := "-"
			var n_above := 0
			for part in world.player._model.get("cockpit_parts", []):
				var mi := part as MeshInstance3D
				if not is_instance_valid(mi):
					continue
				var ab: AABB = mi.transform * mi.get_aabb()
				# only what is forward of the eye, where the view is
				if ab.position.z > eye.z:
					continue
				if ab.end.y > worst:
					worst = ab.end.y
					worst_nm = str(mi.name)
				if ab.end.y > eye.y:
					n_above += 1
			print("[view] %s: eye y=%.2f, highest forward furniture %.2f (%s), %d parts above the eye line" % [
				str(world.player.spec["name"]), eye.y, worst, worst_nm, n_above])
			# and the glazing: a bubble stands proud of the spine, a flight deck
			# window follows it
			var cnode: Node = world.player._model["root"].find_child("Canopy", true, false)
			if cnode == null:
				cnode = world.player._model["root"].find_child("CanopyHinge", true, false)
			if cnode != null:
				var mi2 := cnode as MeshInstance3D
				if mi2 == null:
					for c in (cnode as Node).get_children():
						if c is MeshInstance3D:
							mi2 = c
							break
				if mi2 != null:
					var gab: AABB = world.player.global_transform.affine_inverse() \
						* (mi2.global_transform * mi2.get_aabb())
					var secs: Array = world.player.spec["shape"]["sections"]
					var zc: float = gab.position.z + gab.size.z * 0.5
					var top := -9.0
					for i in secs.size() - 1:
						if zc >= minf(secs[i][0], secs[i+1][0]) and zc <= maxf(secs[i][0], secs[i+1][0]):
							var f: float = (zc - secs[i][0]) / maxf(secs[i+1][0] - secs[i][0], 0.001)
							top = lerpf(secs[i][2] + secs[i][3], secs[i+1][2] + secs[i+1][3], f)
							break
					print("[view]   glazing top y=%.2f, fuselage top y=%.2f -> %s" % [
						gab.end.y, top,
						"stands %.2f m proud (bubble)" % (gab.end.y - top) if gab.end.y > top + 0.05
						else "flush with the nose (flight deck)"])
			world.get_tree().quit()
#endregion


#region --flaptest
var _flap_test := false
var _flap_t := 0.0

func tick_flap(delta: float) -> void:
	if _flap_test and is_instance_valid(world.player):
		_flap_t += delta
		if _flap_t < 3.0:
			world.player.flaps = 1.0
		elif _flap_t >= 3.0:
			_flap_test = false
			var fl: Array = world.player._model.get("flaps", [])
			var out := []
			for f in fl:
				var n := f as Node3D
				# a point on the trailing edge of each flap, in body coordinates
				var tip: Vector3 = world.player.global_transform.affine_inverse() \
					* (n.global_transform * Vector3(0.0, 0.0, 0.9))
				out.append("x=%+.2f dy=%+.3f" % [n.position.x, tip.y - n.position.y])
			print("[flap] %s flaps at full: %s" % [str(world.player.spec["name"]), ", ".join(out)])
			world.get_tree().quit()
#endregion


#region --seattest
var _seat_test := false
var _seat_t := 0.0

func tick_seat(delta: float) -> void:
	if _seat_test and is_instance_valid(world.player) and is_instance_valid(world.pilot):
		_seat_t += delta
		# only once he is actually down on the pan, not part way down the rail
		if _seat_t > 1.0 and world.pilot.global_position.distance_to(world._board_seat) < 0.02:
			_seat_test = false
			var inv := world.player.global_transform.affine_inverse()
			var seat: Vector3 = world.player.seat_offset()
			var hips_l: Vector3 = inv * world.pilot.hips.global_position
			var head_l: Vector3 = inv * world.pilot.head.global_position
			# the un-cut fuselage top at this station, from the raw section data
			var secs: Array = world.player.spec["shape"]["sections"]
			var top := -9.0
			for i in secs.size() - 1:
				var z0: float = secs[i][0]
				var z1: float = secs[i + 1][0]
				if seat.z >= minf(z0, z1) and seat.z <= maxf(z0, z1):
					var f: float = (seat.z - z0) / maxf(z1 - z0, 0.001)
					top = lerpf(float(secs[i][2]) + float(secs[i][3]),
						float(secs[i + 1][2]) + float(secs[i + 1][3]), f)
			print("[seat] %s: pan y=%.2f  hips y=%.2f  head y=%.2f  skin top y=%.2f  -> hips %s skin, head %+.2f above" % [
				str(world.player.spec["name"]), seat.y, hips_l.y, head_l.y, top,
				"BELOW" if hips_l.y < top else "ABOVE", head_l.y - top])
			world.get_tree().quit()
#endregion


#region --helitest
var _heli_test := false
var _heli_t := 0.0
var _heli_lo := 1e9
var _heli_hi := -1e9
var _heli_up := 0.0
## How far the machine sank through the height it was at when the collective
## centred, and where it settled.
var _heli_sag := 0.0
var _heli_settled := 0.0

func tick_heli(delta: float) -> bool:
	if _heli_test and is_instance_valid(world.player):
		_heli_t += delta
		# The lever is driven from here rather than through the input map. A
		# headless session reports the shift key as held from the moment it
		# starts, so a test that presses actions is measuring the operating
		# system -- and the chain below used to fall through to "collective up"
		# for the four seconds before the hands-off window and never let go, so
		# the twenty seconds this exists to measure were flown on full up
		# collective. It has never once measured the altitude hold.
		if _heli_t < 0.05:
			world.player.lever = 0.0
			world.player.global_transform = Transform3D(Basis(), Vector3(0, 500, 5000))
			world.player.linear_velocity = Vector3(0, 0, -30.0)
			world.player.auto = ""
			world.player.throttle = 0.5
			world.player.power = 0.5
			if "hold_alt" in world.player:
				world.player.hold_alt = 500.0
		elif _heli_t < 24.0:
			# hands off: it should simply stay where it is
			world.player.lever = 0.0
			if _heli_t < 4.0:
				return true                     # a moment to settle before measuring
			_heli_lo = minf(_heli_lo, world.player.global_position.y)
			_heli_hi = maxf(_heli_hi, world.player.global_position.y)
			if fmod(_heli_t, 3.0) < delta:
				print("[heli]   t=%4.1f alt=%6.1f vs=%+5.1f hold=%6.1f thr=%.2f lever=%.2f gnd=%s assist=%s" % [
					_heli_t, world.player.global_position.y, world.player.linear_velocity.y,
					float(world.player.get("hold_alt")), world.player.throttle,
					float(world.player.get("lever")),
					str(world.player.on_ground), str(world.player.assist)])
		elif _heli_t < 32.0:
			world.player.lever = 1.0                     # SHIFT, collective up
			_heli_up = world.player.global_position.y
		elif _heli_t < 40.0:
			# Let go after a climb. What a pilot notices here is whether the
			# machine settles at the height it was at when the lever centred, or
			# sags through it first -- and the sag is the thing that reads as
			# "it drops when I let go of shift".
			world.player.lever = 0.0
			_heli_sag = minf(_heli_sag, world.player.global_position.y - _heli_up)
			_heli_settled = world.player.global_position.y
		elif _heli_t < 48.0:
			world.player.lever = -1.0                    # Z / CTRL, collective down
		elif _heli_t >= 48.0:
			world.player.lever = 0.0
			_heli_test = false
			print("[heli]   climbed to %.0f m on the up lever; on release it settled at %.0f m, sagging %.1f m first" % [
				_heli_up, _heli_settled, -_heli_sag])
			print("[heli]   then down to %.0f m on the down lever" % world.player.global_position.y)
			# Hands off it holds; on release it settles where the lever left it
			# rather than sinking through that height first.
			print("[heli] RESULT: %s" % ("ok"
				if _heli_hi - _heli_lo < 5.0 and -_heli_sag < 3.0
				and world.player.global_position.y < _heli_settled - 20.0 else "FAILED"))
			print("[heli] %s hands off for 20 s: altitude %.1f to %.1f m (drift %.1f m), throttle %.2f" % [
				str(world.player.spec["name"]), _heli_lo, _heli_hi, _heli_hi - _heli_lo, world.player.throttle])
			world.get_tree().quit()
	return false
#endregion


#region --ctltest=
var _ctl_test := 0.0
var _ctl_t := 0.0
var _ctl_roll := 0.0
var _ctl_pitch := 0.0
var _ctl_racc := 0.0
var _ctl_pacc := 0.0
var _ctl_pr := 0.0
var _ctl_rr := 0.0

func tick_ctl(delta: float) -> void:
	if _ctl_test > 0.0 and is_instance_valid(world.player):
		_ctl_t += delta
		if _ctl_t < 0.05:
			world.player.global_transform = Transform3D(Basis(), Vector3(0, 4000, 9000))
			world.player.linear_velocity = Vector3(0, 0, -_ctl_test)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.auto = "hold"
			world.player.throttle = 0.7
			world.player.power = 0.7
		elif _ctl_t < 5.0:
			world.player.in_roll = 1.0            # full lateral stick
			world.player.in_pitch = 0.0
		elif _ctl_t < 9.0:
			world.player.in_roll = 0.0
			world.player.in_pitch = 1.0           # then full aft
		else:
			print("[ctl] %-20s assist=%-5s at %3.0f m/s: peak roll %6.1f deg/s (accel %5.0f deg/s2), peak pitch %5.1f deg/s (accel %5.0f deg/s2)" % [
				str(world.player.spec["name"]), str(world.player.assist), _ctl_test,
				rad_to_deg(_ctl_roll), rad_to_deg(_ctl_racc),
				rad_to_deg(_ctl_pitch), rad_to_deg(_ctl_pacc)])
			_ctl_test = 0.0
			world.get_tree().quit()
		if _ctl_t > 0.1:
			var b := world.player.global_transform.basis
			var av := world.player.angular_velocity
			var rr := av.dot(-b.z)
			var pr := av.dot(b.x)
			if _ctl_t < 5.0:
				_ctl_roll = maxf(_ctl_roll, absf(rr))
				_ctl_racc = maxf(_ctl_racc, absf(rr - _ctl_rr) / maxf(delta, 1e-5))
			else:
				_ctl_pitch = maxf(_ctl_pitch, absf(pr))
				_ctl_pacc = maxf(_ctl_pacc, absf(pr - _ctl_pr) / maxf(delta, 1e-5))
			_ctl_rr = rr
			_ctl_pr = pr
#endregion


#region --tvctest=
var _tvc_test := 0.0
var _tvc_t := 0.0
var _tvc_peak := 0.0
var _tvc_aoa := 0.0
var _tvc_defl := 0.0

func tick_tvc(delta: float) -> void:
	if _tvc_test > 0.0 and is_instance_valid(world.player):
		_tvc_t += delta
		if _tvc_t < 0.05:
			world.player.global_transform = Transform3D(Basis(), Vector3(0, 3000, 12000))
			world.player.linear_velocity = Vector3(0, 0, -_tvc_test)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.auto = "wait"
			world.player.throttle = 1.0
			world.player.power = 1.0
		elif _tvc_t < 4.0:
			# full aft stick at low speed: what can the aeroplane still do?
			world.player.in_pitch = 1.0
			world.player.throttle = 1.0
			var q: float = world.player.angular_velocity.dot(world.player.global_transform.basis.x)
			_tvc_peak = maxf(_tvc_peak, q)
			_tvc_aoa = maxf(_tvc_aoa, rad_to_deg(world.player.aoa))
			_tvc_defl = maxf(_tvc_defl, rad_to_deg(absf(world.player.nozzle_pitch)))
		else:
			var pivots: Array = world.player._nozzles
			var pv_deg := 0.0
			for pv in pivots:
				if is_instance_valid(pv):
					pv_deg = maxf(pv_deg, rad_to_deg(absf((pv as Node3D).rotation.x)))
			print("[tvc] %-20s at %3.0f m/s: peak pitch rate %5.1f deg/s, max AoA %5.1f, nozzle %4.1f deg, %d pivots at %4.1f deg" % [
				str(world.player.spec["name"]), _tvc_test,
				rad_to_deg(_tvc_peak), _tvc_aoa, _tvc_defl, pivots.size(), pv_deg])
			_tvc_test = 0.0
			world.get_tree().quit()
#endregion


#region --boardtest
var _board_test := false
var _boardtest_t := 0.0

func tick_board(delta: float) -> void:
	if _board_test and is_instance_valid(world.walker):
		_boardtest_t += delta
		if _boardtest_t > 3.0:
			_board_test = false
			var ok := 0
			var miss := 0
			for n in world.get_tree().get_nodes_in_group("boardable"):
				if not is_instance_valid(n) or not n.has_method("hull_distance"):
					continue
				# stand two metres off the left flank of this machine
				var half: float = maxf(absf(n.bounds.position.x), absf(n.bounds.end.x))
				var spot: Vector3 = n.global_transform * Vector3(-(half + 2.0), 0, 0)
				world.walker.position = Vector3(spot.x, Sim.height_at(spot.x, spot.z), spot.z)
				world.walker._scan()
				var got = world.walker.target_jet
				var want_nm := world._label_of(n)
				var got_nm := world._label_of(got) if got != null else "nothing"
				if got == n:
					ok += 1
				else:
					miss += 1
					print("[board]  standing at %s but offered %s" % [want_nm, got_nm])
			print("[board] %d correct, %d wrong" % [ok, miss])
			world.get_tree().quit()
#endregion


#region --jolttest
var _jolt_test := false
var _jolt_t := 0.0
var _jolt_prev := Vector3.ZERO
var _jolt_worst := 0.0
var _jolt_when := 0.0
var _jolt_n := 0
var _jolt_sum := 0.0
var _jolt_gmin := 99.0
var _jolt_gmax := -99.0

func tick_jolt(delta: float) -> void:
	if _jolt_test and is_instance_valid(world.player) and world.cam:
		_jolt_t += delta
		if _jolt_t < 1.0:
			world.player.auto = "tumble"
		# where the camera sits in the aircraft's own frame, as rendered. A rig
		# that is solid on the airframe holds this constant however hard the jet
		# manoeuvres; anything else is the jolt the pilot sees.
		world.cam.diag = true
		var axf: Transform3D = world.player.get_global_transform_interpolated()
		var loc: Vector3 = axf.affine_inverse() * world.cam.global_position
		if _jolt_t > 2.0:
			_jolt_gmin = minf(_jolt_gmin, world.player.g_load)
			_jolt_gmax = maxf(_jolt_gmax, world.player.g_load)
		if _jolt_prev != Vector3.ZERO and _jolt_t > 2.0:
			var d: float = (loc - _jolt_prev).length()
			_jolt_n += 1
			_jolt_sum += d
			if d > _jolt_worst:
				_jolt_worst = d
				_jolt_when = _jolt_t
		_jolt_prev = loc
		if _jolt_t > 14.0:
			_jolt_test = false
			print("[jolt] %s: boom %.2f m, mean step %.4f m, worst %.4f m at t=%.1f over %d frames, ground-clamped %d, agl %.0f" % [
				str(world.player.spec["name"]), loc.length(),
				_jolt_sum / maxf(float(_jolt_n), 1.0), _jolt_worst, _jolt_when, _jolt_n,
				world.cam.clamped_frames, world.player.agl])
			print("[jolt]   worst camera roll step %.2f deg at t=%.1f" % [
				world.cam.worst_roll, world.cam.worst_roll_t])
			print("[jolt]   g through the tumble: min %+.2f max %+.2f, grey-out %.0f%% red-out %.0f%%" % [
				_jolt_gmin, _jolt_gmax, world.player.g_strain * 100.0, world.player.g_red * 100.0])
			world.get_tree().quit()
#endregion


#region --overlaptest
var _overlap_test := false
var _overlap_t := 0.0

func tick_overlap(delta: float) -> void:
	if _overlap_test:
		_overlap_t += delta
		if _overlap_t > 14.0:
			_overlap_test = false
			# Real world-space footprints, not circles round an origin: a
			# transport is far longer than it is wide and it is parked across
			# the apron, so a radius from the wingspan says nothing useful.
			var items: Array = []
			var seen := {}
			for grp in ["vehicles", "hittable", "ground_targets"]:
				for n in world.get_tree().get_nodes_in_group(grp):
					if not is_instance_valid(n) or not (n is Node3D):
						continue
					if seen.has(n.get_instance_id()):
						continue      # a tank is in "vehicles" AND "hittable"
					seen[n.get_instance_id()] = true
					var box := world._footprint(n as Node3D)
					if box != Rect2():
						items.append([world._label_of(n), box])
			# every aircraft in the tree, group membership or not
			for n in world.get_tree().get_root().find_children("*", "Node3D", true, false):
				var a := n as Node3D
				if not is_instance_valid(a) or not ("spec" in a):
					continue
				var sp = a.get("spec")
				if not (sp is Dictionary) or not (sp as Dictionary).has("name"):
					continue
				print("[aircraft] %-24s at %s  boardable=%s hittable=%s parent=%s" % [
					String((sp as Dictionary)["name"]), str(a.global_position.round()),
					str(a.is_in_group("boardable")), str(a.is_in_group("hittable")),
					str(a.get_parent().name)])
			print("[overlap] %d bodies on the ramp" % items.size())
			for it in items:
				var rr: Rect2 = it[1]
				print("[overlap]   %-28s centre (%7.1f,%8.1f) size %5.1f x %5.1f" % [
					it[0], rr.position.x + rr.size.x * 0.5,
					rr.position.y + rr.size.y * 0.5, rr.size.x, rr.size.y])
			var bad := 0
			for i in items.size():
				for j in range(i + 1, items.size()):
					var ra: Rect2 = items[i][1]
					var rb: Rect2 = items[j][1]
					if ra.intersects(rb):
						bad += 1
						var ov := ra.intersection(rb)
						print("[overlap]  %s overlaps %s by %.1f x %.1f m" % [
							items[i][0], items[j][0], ov.size.x, ov.size.y])
			print("[overlap] %d overlapping pairs" % bad)
#endregion
