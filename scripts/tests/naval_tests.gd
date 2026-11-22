class_name NavalTests
extends TestSuite
## Ships, submarines, the carrier and the fleet.
##
## Command-line tests, split out of `world.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--carrierconntest":
		_carrier_conn_test = true
	elif a.begins_with("--shiptest="):
		_shiptest = a.substr(11)
	elif a == "--navaltest":
		_naval_test = true
	elif a.begins_with("--navalship="):
		_naval_ship_kind = a.substr(13)
	elif a == "--navallow":
		_naval_low = true
	elif a.begins_with("--navaltest="):
		_naval_test = true
		_naval_weapon = a.substr(12)
	elif a == "--battletest":
		_bat_test = true
	elif a == "--shipnet":
		_shipnet = true
	elif a == "--vlstest":
		_vls_test = true
	elif a == "--rivertest":
		_river_test = true
	elif a == "--carriertest":
		_carrier_test = true
	elif a == "--conntest":
		_conn_test = true
	elif a == "--fleetfire":
		_fleetfire = true
	elif a == "--guardtest":
		_guard_test = true
	elif a == "--boattest":
		_boat_test = true
	elif a == "--subtest2":
		_subtest = true
	elif a == "--navsensor":
		_navsensor = true
	elif a == "--dctest":
		_dc_test = true
	elif a == "--seatest":
		_sea_test = true
	elif a == "--subtest":
		_sub_test = true
	elif a == "--fleettest":
		_fleet_test = true
	else:
		return false
	return true


#region --carrierconntest
## Take the carrier's conn and press every aeroplane key at it: none of them
## may reach the jet parked back on the ramp.
var _carrier_conn_test := false
var _carrier_conn_t := 0.0

func tick_carrier_conn(delta: float) -> void:
	if _carrier_conn_test:
		_carrier_conn_t += delta
		if _carrier_conn_t > 3.0:
			_carrier_conn_test = false
			_run_carrier_conn_test()

func _run_carrier_conn_test() -> void:
	var bad := PackedStringArray()
	if not world.crew.at_conn():
		print("[conn] RESULT: FAILED — not at the carrier's conn (start with --jet=sea:carrier)")
		world.get_tree().quit()
		return
	var mode0: int = world.cam.mode if is_instance_valid(world.cam) else -1
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	world.controls.shell_input(rmb)
	if world.pod.active:
		bad.append("right click opened a sensor page instead of zooming")
	await world.get_tree().create_timer(0.8).timeout
	if world.carrier.cam.fov > World.HULL_FOV * 0.6:
		bad.append("right click held did not zoom the bridge view (fov %.0f)" % world.carrier.cam.fov)
	var rup := InputEventMouseButton.new()
	rup.button_index = MOUSE_BUTTON_RIGHT
	rup.pressed = false
	world.controls.shell_input(rup)
	await world.get_tree().create_timer(0.8).timeout
	if world.carrier.cam.fov < World.HULL_FOV * 0.9:
		bad.append("letting go did not bring the view back out (fov %.0f)" % world.carrier.cam.fov)
	# and O, which is what every key card says the sensor page is on
	harness._press(KEY_O)
	if world.pod.active and world.pod._armed(world.pod.platform):
		bad.append("the carrier's sensor page offers weapons")
	if not world.pod.active or world.pod.platform != world.carrier:
		bad.append("O did not open the carrier's sensor page (open=%s, map open=%s)" % [
			str(world.pod.active), str(world.map.visible)])
	harness._press(KEY_O)
	if world.pod.active:
		bad.append("O did not close the sensor page")
	harness._press(KEY_J)
	if world.gunning:
		bad.append("J opened a gunner station")
	harness._press(KEY_P)
	if is_instance_valid(world.cam) and world.cam.mode != mode0:
		bad.append("P cycled the parked jet's camera")
	harness._press(KEY_U)
	if world.on_foot or not world.crew.at_conn():
		bad.append("U climbed out of the parked jet")
	harness._press(KEY_TAB)
	var ids := PackedStringArray()
	for it in world.actions.items:
		ids.append(String(it["id"]))
	if not world.actions.visible or ids != PackedStringArray(["sensor", "allstop", "amidships", "dismount"]):
		bad.append("TAB opened %s" % str(ids))
	world.actions.close()
	world.hud._refresh_help()
	if world.hud._card_sig != 64 and world.hud.show_help:
		bad.append("the key card is not the conn's (sig %d)" % world.hud._card_sig)
	# and the menu still works from here: all stop, then hand over
	world.carrier.telegraph = 0.6
	world.controls.do_action("allstop")
	if absf(world.carrier.telegraph) > 0.001:
		bad.append("all stop left the telegraph at %.2f" % world.carrier.telegraph)
	world.controls.do_action("dismount")
	if world.crew.at_conn() or not world.on_foot:
		bad.append("hand over did not put you on the deck")
	for b in bad:
		print("[conn]   ", b)
	print("[conn] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion


#region --shiptest=
var _shiptest := ""
var _shipt := 0.0
var _ship_p0 := Vector3.ZERO

func tick_shiptest(delta: float) -> void:
	if _shiptest != "" and is_instance_valid(world.ship):
		_shipt += delta
		if _shipt < 0.2:
			_ship_p0 = world.ship.global_position
		elif _shipt < 8.0:
			world.ship.telegraph = 1.0
			world.ship.helm = 0.6
			world.ship.aim_yaw = world.ship.heading + deg_to_rad(60.0)
		elif _shipt >= 8.0:
			_shiptest = ""
			var moved: float = world.ship.global_position.distance_to(_ship_p0)
			var g0: float = world.ship.gun_cd
			var fired: bool = world.ship.fire_gun()
			var mnt := 0.0
			if is_instance_valid(world.ship._gun):
				var mf: Vector3 = -world.ship._gun.global_transform.basis.z
				mnt = fmod(rad_to_deg(atan2(mf.x, -mf.z)) + 360.0, 360.0)
			# the pod must sit on the ship, and the context menu must be naval
			world.pod.toggle()
			var podx: float = world.pod._head_origin().distance_to(world.ship.global_position)
			var pody: float = world.pod._head_origin().y - world.ship.global_position.y
			world.pod.toggle()
			world.actions.open_for_vehicle(world.ship)
			var labels := ""
			for it in world.actions.items:
				labels += String(it["label"]) + "; "
			world.actions.close()
			print("[ship] pod head %.1f m from the ship (%.1f m up); menu: %s" % [
				podx, pody, labels])
			print("[ship] %s: made %.0f m in 8 s (%.1f kts), heading %03d, mount bearing %03d vs ordered %03d, gun fired=%s" % [
				world.ship.display_name(), moved, world.ship.speed * 1.94384,
				int(fmod(rad_to_deg(world.ship.heading) + 360.0, 360.0)), int(mnt),
				int(fmod(rad_to_deg(world.ship.aim_yaw) + 360.0, 360.0)), str(fired and g0 <= 0.0)])
			world.get_tree().quit()
#endregion


#region --navaltest --navalship= --navallow --navaltest=
var _naval_test := false
## Which hostile hull to attack, and from where. Blank picks the first one in
## the group, which is always the corvette.
var _naval_ship_kind := ""
var _naval_low := false
## The round in the air and the closest it ever came to the hull, kept because
## the missile is freed the moment it goes off.
var _naval_round: Node = null
var _naval_miss := 1e9
var _naval_t := 0.0
var _naval_hp := 0.0
var _naval_ship: Node3D = null
var _naval_shot := false
var _naval_weapon := "gbu32"
var _naval_said := -1

# Kept running once the bomb is away. Gated on the launcher surviving, the
# test hung with nothing reported every time the ship shot the aeroplane
# down before the round arrived — which read as a flaky harness.
func tick_naval(delta: float) -> bool:
	if _naval_test and (is_instance_valid(world.player) or _naval_shot):
		_naval_t += delta
		if _naval_t > 2.0 and _naval_ship == null:
			for sh in world.get_tree().get_nodes_in_group("ships"):
				if not is_instance_valid(sh) or (sh as Ship).team == 0:
					continue
				# A corvette is the first hostile hull in the group and it is
				# the smallest thing afloat. What a weapon does against a
				# destroyer is a different question, so the test has to be able
				# to ask it.
				if _naval_ship_kind != "" and (sh as Ship).kind != _naval_ship_kind:
					continue
				_naval_ship = sh
				break
			if _naval_ship == null:
				var afloat := PackedStringArray()
				for sh3 in world.get_tree().get_nodes_in_group("ships"):
					if is_instance_valid(sh3):
						afloat.append("%s(team %d)" % [(sh3 as Ship).kind,
							(sh3 as Ship).team])
				print("[naval] no hostile shipping%s; afloat: %s" % [
					"" if _naval_ship_kind == "" else " of kind '%s'" % _naval_ship_kind,
					", ".join(afloat)])
				_naval_test = false
				return true
			_naval_hp = _naval_ship.get("health")
			# and it does not shoot back: this measures what the weapon does to
			# the hull, not how long an F-35 lasts orbiting a warship
			# Nothing else touches the target while a round is in the air: the
			# ambient battle sank her mid-flight and the shot was scored a miss
			# when the round had simply lost something already on the bottom.
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null:
					v2.cells_left = 0
					v2.ai = false
					v2.ciws_enabled = false
			for ac in world.get_tree().get_nodes_in_group("hittable"):
				if ac is Aircraft and ac != world.player:
					(ac as Aircraft).queue_free()
			# High and diving, or low and flat. A Maverick fired from a
			# thousand feet in a dive arrives steeply and has the whole hull
			# under it; fired from the deck it runs in almost level at a target
			# whose origin is AT sea level, which is a very different shot.
			var up: float = 120.0 if _naval_low else 1500.0
			var out: float = 4000.0 if _naval_low else 3000.0
			world.player.global_transform = Transform3D(Basis(),
				_naval_ship.global_position + Vector3(0, up, out))
			world.player.linear_velocity = Vector3(0, 0, -250.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world.player.set_bays(true)
			for k in world.player.bays:
				world.player.bays[k]["anim"] = 1.0
				world.player.bays[k]["open"] = true
			# designate the ship with the pod laser, which is what the player
			# would do, rather than handing the bomb a radar contact
			world.pod.platform = world.player
			if not world.pod.active:
				world.pod.toggle()
			world.pod.mode = world.pod.POINT
			world.pod.tracked = _naval_ship
			if not world.pod.lasing:
				world.pod.toggle_laser()
			world.pod._process(0.016)
			world.player.locked = true
			if not harness._arm_with(_naval_weapon):
				_naval_test = false
				world.get_tree().quit()
				return true
			world.player.fire_cd = 0.0
			world._reset_interp.call_deferred(world.player)
			world.player.target = _naval_ship
			print("[naval] attacking %s with %s, hull %.0f; laser spot %s (sea level %.0f)" % [
				_naval_ship.call("display_name"), _naval_weapon, _naval_hp,
				str(world.player.designated.round()), Sim.sea_at(world.player.designated.x,
				world.player.designated.z)])
		elif _naval_t > 2.0 and _naval_t < 5.0 and is_instance_valid(_naval_ship) \
				and is_instance_valid(world.player):
			if int(_naval_t * 4.0) != _naval_said:
				_naval_said = int(_naval_t * 4.0)
				var rel: Vector3 = _naval_ship.global_position - world.player.global_position
				print("[naval] t=%.2f  target=%s  %.1f deg below the nose, %.0f m  locked=%s lock_t=%.2f" % [
					_naval_t, str(is_instance_valid(world.player.target)),
					rad_to_deg((-world.player.global_transform.basis.z).angle_to(rel)),
					rel.length(), str(world.player.locked), world.player.lock_time])
		elif _naval_t > 5.0 and not _naval_shot and is_instance_valid(world.player):
			_naval_shot = true
			print("[naval] at release: pod active=%s lasing=%s mode=%d tracked=%s designated=%s node=%s" % [
				str(world.pod.active), str(world.pod.lasing), world.pod.mode,
				str(is_instance_valid(world.pod.tracked)), str(world.player.designated.round()),
				str(world.player.designated_node.name) if is_instance_valid(world.player.designated_node) else "none"])
			print("[naval] release: %s" % ("away" if world.player.fire() == "" else "refused"))
			# Hold on to the round, because the hull's health does not tell you
			# whether THIS weapon hit it. A Maverick that went into the sea 1.4
			# km short was scored a hit on the strength of damage the ship took
			# from something else entirely.
			for n in world.get_tree().get_nodes_in_group("missiles"):
				if n is Missile and (n as Missile).shooter == world.player:
					_naval_round = n
		elif is_instance_valid(_naval_round) and is_instance_valid(_naval_ship) \
				and _naval_t <= 40.0:
			# Against the hull's surface, not its origin: a destroyer is a
			# hundred and fifty five metres long and a round striking the bow is
			# seventy metres from the point amidships.
			var mp: Vector3 = (_naval_round as Node3D).global_position
			var gap: float = _naval_ship.surface_gap(mp) \
				if _naval_ship.has_method("surface_gap") \
				else mp.distance_to(_naval_ship.global_position)
			_naval_miss = minf(_naval_miss, maxf(gap, 0.0))
		elif _naval_t > 40.0:
			_naval_test = false
			var now: float = _naval_ship.get("health") if is_instance_valid(_naval_ship) else -1.0
			# How close the round itself ever got, which is the thing being
			# measured. Anything beyond its own fuse radius did not hit,
			# whatever else happened to the ship while it was in the air.
			var miss := _naval_miss
			var fuse: float = float(WeaponSpec.get_spec(_naval_weapon).get("fuse", 10.0))
			var struck: bool = miss <= maxf(fuse, 12.0) and now < _naval_hp
			print("[naval] RESULT: hull %.0f -> %.0f, round's closest approach %.1f m (fuse %.0f m) — %s" % [
				_naval_hp, now, miss, fuse,
				"HIT" if struck else "MISS"])
			world.get_tree().quit()
	return false
#endregion


#region --battletest
var _bat_test := false
var _bat_t := 0.0
var _bat_a: Node3D = null
var _bat_b: Node3D = null
var _bat_hp := [0.0, 0.0]
var _bat_said := 0

# Two hostile warships put within gun range of each other, left to it.
func tick_bat(delta: float) -> bool:
	if _bat_test:
		_bat_t += delta
		if _bat_t > 1.5 and not is_instance_valid(_bat_a):
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null or not v.has_gun():
					continue
				if v.team == 0 and _bat_a == null:
					_bat_a = v
				elif v.team == 1 and _bat_b == null:
					_bat_b = v
			if _bat_a == null or _bat_b == null:
				print("[fleet] need one warship a side")
				_bat_test = false
				return true
			var mid: Vector3 = (_bat_a.global_position + _bat_b.global_position) * 0.5
			_bat_a.global_position = Vector3(mid.x - 4000.0, Sim.sea_surface(mid.x - 4000.0, mid.z), mid.z)
			_bat_b.global_position = Vector3(mid.x + 4000.0, Sim.sea_surface(mid.x + 4000.0, mid.z), mid.z)
			_bat_hp = [_bat_a.get("health"), _bat_b.get("health")]
			print("[fleet] %s (t0, hull %.0f) vs %s (t1, hull %.0f), 8.0 km apart" % [
				_bat_a.call("display_name"), _bat_hp[0],
				_bat_b.call("display_name"), _bat_hp[1]])
		else:
			var tick := int((_bat_t - 3.0) / 30.0) + 1
			if tick > _bat_said:
				_bat_said = tick
				var rng := -1.0
				if is_instance_valid(_bat_a) and is_instance_valid(_bat_b):
					rng = _bat_a.global_position.distance_to(_bat_b.global_position)
				for v in [_bat_a, _bat_b]:
					if is_instance_valid(v):
						print("[fleet] %6.1fs  %-26s %-46s spd %4.1f  fired %2d  rng %5.0f m" % [
							_bat_t, v.call("display_name"), v.call("damage_report"),
							v.get("speed"), int(v.get("rounds")), rng])
			if _bat_t > 150.0:
				_bat_test = false
				for i in 2:
					var v: Node3D = _bat_a if i == 0 else _bat_b
					if not is_instance_valid(v):
						print("[fleet] RESULT: side %d gone from the board" % i)
						continue
					print("[fleet] RESULT: side %d %-26s hull %.0f -> %.0f  %s" % [
						i, v.call("display_name"), _bat_hp[i], v.get("health"),
						"SUNK" if not bool(v.get("alive")) else "afloat"])
				world.get_tree().quit()
	return false
#endregion


#region --shipnet
var _shipnet := false
var _shipnet_t := 0.0
var _shipnet_said := 0

# What each end of a session thinks the fleet is doing.
func tick_shipnet(delta: float) -> void:
	if _shipnet:
		_shipnet_t += delta
		var mark := int(_shipnet_t / 10.0)
		if mark > _shipnet_said:
			_shipnet_said = mark
			var side0 := "single"
			if world.net != null and world.net.active:
				side0 = "host" if world.net.is_host else "client"
			var afloat := 0
			var sunk := 0
			var broken := 0
			var going := 0
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 == null:
					continue
				if v2.alive:
					afloat += 1
				else:
					sunk += 1
				if v2.is_broken():
					broken += 1
				if v2.is_sinking():
					going += 1
			print("[shipnet] %-8s sky: %s at %05.2f h, sun %+.1f deg, wind_time %.1f, coverage %.2f | fleet: %d afloat, %d sunk, %d broken in two, %d going down" % [
				side0, world.weather.current, world.weather.time_of_day,
				rad_to_deg(world.weather.sun_elevation()),
				float(world._psm.get_shader_parameter("wind_time")),
				float(world._psm.get_shader_parameter("coverage")),
				afloat, sunk, broken, going])
			var side := "single"
			if world.net != null and world.net.active:
				side = "host" if world.net.is_host else "client %d" % world.net.my_id
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null or v.fleet_idx > 2:
					continue
				print("[shipnet] %-12s t=%3.0f  hull %d  %-26s pos %s  hdg %6.1f  hull %6.0f  ghost=%s" % [
					side, _shipnet_t, v.fleet_idx, v.display_name(),
					str(v.global_position.round()), rad_to_deg(v.heading),
					v.health, str(v.ghost)])
#endregion


#region --vlstest
var _vls_test := false
var _vls_t := 0.0
var _vls_step := 0
var _vls_ship: Node3D = null
var _vls_best := 1e9

# Do the tubes actually reach an aeroplane, or does the round climb away.
func tick_vls(delta: float) -> bool:
	if _vls_test and is_instance_valid(world.player):
		_vls_t += delta
		if _vls_t > 2.0 and _vls_step == 0:
			_vls_step = 1
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.has_vls() and v.team != 0:
					_vls_ship = v
					break
			if _vls_ship == null:
				print("[vls] no hostile ship with tubes")
				_vls_test = false
				return true
			# put the aeroplane where a strike aircraft would be: twelve
			# kilometres out and eight thousand feet up, running in
			var sp: Vector3 = _vls_ship.global_position
			world.player.team = 0
			world.player.global_transform = Transform3D(Basis(),
				sp + Vector3(0.0, 2400.0, 12000.0))
			world.player.linear_velocity = Vector3(0, 0, -240.0)
			world.player.gear_down = false
			world.player.gear_anim = 0.0
			world._reset_interp(world.player)
			print("[vls] %s at %s, aeroplane 12.0 km out at 2400 m" % [
				_vls_ship.call("display_name"), str(sp.round())])
		elif _vls_step == 1 and _vls_t > 3.0:
			_vls_step = 2
			print("[vls] launch: %s" % str(_vls_ship.call("fire_vls", world.player)))
		elif _vls_step == 2:
			var live := 0
			for m in world.get_tree().get_nodes_in_group("missiles"):
				if not is_instance_valid(m):
					continue
				live += 1
				_vls_best = minf(_vls_best,
					(m as Node3D).global_position.distance_to(world.player.global_position))
			if int(_vls_t) % 6 == 0 and int(_vls_t * 60.0) % 360 == 0:
				for m in world.get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(m):
						var mp: Vector3 = (m as Node3D).global_position
						print("[vls] t=%5.1f  round at %s  alt %6.0f  %.0f m from the aeroplane" % [
							_vls_t, str(mp.round()), mp.y,
							mp.distance_to(world.player.global_position)])
						break
			if _vls_t > 28.0:
				_vls_test = false
				print("[vls] RESULT: closest approach %.0f m, %d rounds still up, player alive=%s" % [
					_vls_best, live, str(world.player.is_alive())])
				world.get_tree().quit()
	return false
#endregion


#region --rivertest
var _river_test := false

# Can anything that floats actually get off the coast and up a river? A
# channel that is lower than its banks is not a river if it is four hundred
# metres above the sea, so this asks the only question that matters: flood
# fill from open water and see how far inland the water goes.
func tick_river() -> bool:
	if _river_test:
		_river_test = false
		# 400 m, not 1500: a river is a few hundred metres across, and a grid
		# coarser than the channel steps straight over it and reports a
		# perfectly good waterway as unreachable.
		var step := 400.0
		var draught := 5.0
		# Somewhere with a coast on it.
		#
		# This used to sample a fixed window and seed from open water east of
		# `Sim.COAST_X` -- the flat world's coastline, which was a line of
		# constant x. A planet has no such line, and the chart now sits in the
		# middle of a country: the old window held no sea at all, so the test
		# reported no navigable water on a planet that is two thirds ocean.
		# The coast is found instead, and the window put across it.
		var off: Vector3 = world.fleet_yard.deep_water(Vector3.ZERO)
		var shore := Vector2(off.x, off.z)
		if shore.length() > 1.0:
			# Back along the line from the deep water to the middle of the
			# country until the ground comes up: that is the shore.
			var lo := 0.0
			var hi := 1.0
			for _i in 24:
				var mid: float = (lo + hi) * 0.5
				var pm: Vector2 = shore * mid
				if Sim.height_at(pm.x, pm.y) < Sim.sea_at(pm.x, pm.y):
					hi = mid
				else:
					lo = mid
			shore *= (lo + hi) * 0.5
		var nx := 470
		var nz := 500
		var x0: float = shore.x - float(nx) * step * 0.5
		var z0: float = shore.y - float(nz) * step * 0.5
		# Water a hull can float in, and water that is plainly open sea. The
		# second is where a voyage starts; the first is how far it gets.
		var nav := PackedByteArray()
		var open := PackedByteArray()
		nav.resize(nx * nz)
		open.resize(nx * nz)
		var wet := 0
		for j in nz:
			for i in nx:
				var wx: float = x0 + float(i) * step
				var wz: float = z0 + float(j) * step
				var depth: float = Sim.sea_at(wx, wz) - Sim.height_at(wx, wz)
				if depth > draught:
					nav[j * nx + i] = 1
					wet += 1
				if depth > 60.0:
					open[j * nx + i] = 1
		# Flood fill outward from every piece of open sea at once, counting the
		# steps: what comes back is how far up a waterway a hull gets from the
		# sea, following the channel rather than a straight line, which is the
		# distance a boat actually has to make.
		var dist := PackedInt32Array()
		dist.resize(nx * nz)
		dist.fill(-1)
		var queue: Array = []
		for j2 in nz:
			for i2 in nx:
				if open[j2 * nx + i2] == 1 and nav[j2 * nx + i2] == 1:
					dist[j2 * nx + i2] = 0
					queue.append(Vector2i(i2, j2))
		var seeds := queue.size()
		var reached := 0
		var head := 0
		var furthest := 0
		var deep_at := shore
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			reached += 1
			var ci: int = c.x
			var cj: int = c.y
			var dc: int = dist[cj * nx + ci]
			if dc > furthest:
				furthest = dc
				deep_at = Vector2(x0 + float(ci) * step, z0 + float(cj) * step)
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ni: int = ci + int(d[0])
				var nj: int = cj + int(d[1])
				if ni < 0 or ni >= nx or nj < 0 or nj >= nz:
					continue
				var k: int = nj * nx + ni
				if dist[k] >= 0 or nav[k] == 0:
					continue
				dist[k] = dc + 1
				queue.append(Vector2i(ni, nj))
		var inland := 0
		for j3 in nz:
			for i3 in nx:
				var k3: int = j3 * nx + i3
				if dist[k3] > 0 and open[k3] == 0:
					inland += 1
		var up: float = float(furthest) * step
		print("[river] the coast nearest the country is at %s, %.0f km out" % [
			str(shore.round()), shore.length() * 0.001])
		print("[river] %d of %d cells hold %.0f m of water; %d are open sea to start from" % [
			wet, nx * nz, draught, seeds])
		print("[river] a boat drawing %.0f m reaches %d cells, %d of them inland of the coast" % [
			draught, reached, inland])
		print("[river] furthest it gets from open sea: %.0f km, at %s" % [
			up * 0.001, str(deep_at.round())])
		# What the coast is shaped like, walking inland from the shore toward
		# the middle of the country. A river can only be navigable where the
		# ground it has cut is near sea level, so how far inland the country
		# stays low *is* how far a hull can get.
		var prof: Array = []
		var inward: Vector2 = -shore.normalized()
		for km in [1, 3, 6, 10, 20, 40, 80, 160]:
			var pp: Vector2 = shore + inward * (float(km) * 1000.0)
			prof.append("%dkm:%.0f" % [
				km, Sim.height_at(pp.x, pp.y) - Sim.sea_at(pp.x, pp.y)])
		print("[river] the country's height walking inland: %s" % [
			", ".join(PackedStringArray(prof))])
		print("[river] navigable water inland covers %.0f km2" % [
			float(inland) * step * step * 1e-6])
		var ok: bool = up > 40000.0 and inland > 200
		print("[river] RESULT: %s" % ("ok" if ok else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --carriertest
var _carrier_test := false

func tick_carrier() -> bool:
	if _carrier_test:
		_carrier_test = false
		var parts: Dictionary = {}
		var lo := 1e9
		var hi := -1e9
		for c in world.carrier.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var ab: AABB = mi.mesh.get_aabb()
			parts[str(mi.name)] = ab
			lo = minf(lo, world.carrier.global_position.y + ab.position.y)
			hi = maxf(hi, world.carrier.global_position.y + ab.position.y + ab.size.y)
		print("[carrier] parts: %s" % str(parts.keys()))
		# The sea the ship floats in is the one under the ship: out where a
		# carrier sits, the shell has already fallen away from the flat level.
		# The surface under her, swell included: she rides it like anything else
		# afloat, so the water she is measured against is the water she is on.
		var csea: float = Sim.sea_surface(world.carrier.global_position.x,
			world.carrier.global_position.z)
		print("[carrier] sits at y=%.1f, sea is at %.1f" % [
			world.carrier.global_position.y, csea])
		print("[carrier] hull spans %.1f m to %.1f m; keel is %.1f m below the surface" % [
			lo, hi, csea - lo])
		# A tick of swell, not zero. The hull's height is set in the physics
		# step from the surface as it was then; this reads the surface as it is
		# now. On a 17 s swell 1.25 m high the surface moves 0.46 m a second, so
		# a single tick between the two is 8 mm -- which is what a 10 mm bar was
		# failing on whenever the machine was busy enough to stretch a frame.
		var afloat: bool = absf(world.carrier.global_position.y - csea) < 0.05 \
			and lo < csea - 4.0 and lo > csea - 30.0
		# The deck has to be where the deck actually is -- and the honest way
		# to ask is to ask the ground query an approach uses, because the deck
		# is registered in the flat frame and only becomes a world height once
		# `height_at` has dropped it onto the sphere.
		var want_deck: float = csea + Carrier.DECK_Y
		var got_deck: float = Sim.height_at(world.carrier.global_position.x,
			world.carrier.global_position.z)
		print("[carrier] flight deck at %.1f m, registered at %.1f m, %.1f m above the sea" % [
			want_deck, got_deck, want_deck - csea])
		# is there anything holding the port overhang up?
		var port_edge: float = -(Carrier.BEAM + 22.0) * 0.5 - 4.0
		var supported := 0
		var checked := 0
		for zf in [-0.34, -0.10, 0.06, 0.14, 0.32]:
			checked += 1
			var lx: float = port_edge * 0.62
			var lz: float = float(zf) * Carrier.LEN
			var found := false
			for nm in parts:
				if nm == "Deck" or nm == "DeckMarks":
					continue
				var ab2: AABB = parts[nm]
				if lx >= ab2.position.x - 1.0 and lx <= ab2.position.x + ab2.size.x + 1.0 \
						and lz >= ab2.position.z - 1.0 and lz <= ab2.position.z + ab2.size.z + 1.0 \
						and ab2.position.y + ab2.size.y < Carrier.DECK_Y:
					found = true
					break
			if found:
				supported += 1
		print("[carrier] port deck overhang carried at %d of %d stations" % [
			supported, checked])
		# and take the conn
		world.crew.enter_carrier()
		await world.get_tree().process_frame
		var conned: bool = world.carrier.occupied and world.carrier.cam != null and world.carrier.cam.current
		print("[carrier] took the conn: occupied=%s camera=%s" % [
			str(world.carrier.occupied), str(world.carrier.cam != null and world.carrier.cam.current)])
		world.carrier.telegraph = 1.0
		for i in 240:
			world.carrier._physics_process(1.0 / 60.0)
		print("[carrier] under way at %.1f kts after 4 s of full ahead" % (world.carrier.speed * 1.94384))
		var moves: bool = world.carrier.speed > 0.5 \
			and absf(got_deck - want_deck) < 0.05
		world.crew.leave_carrier()
		var listed: bool = false
		for k in world.menu._cards:
			if String(k) == "sea:carrier":
				listed = true
		print("[carrier] listed on the menu: %s" % str(listed))
		print("[carrier] RESULT: %s" % ("ok" if afloat and supported == checked
			and conned and moves and absf(got_deck - want_deck) < 0.01 else "FAILED"))
		world.get_tree().quit()
		return true
	return false
#endregion


#region --conntest
var _conn_test := false
var _conn_t := 0.0
var _conn_step := 0

func tick_conn(delta: float) -> bool:
	if _conn_test:
		_conn_t += delta
		if _conn_step == 0 and _conn_t > 3.0:
			_conn_step = 1
			_conn_t = 0.0
			if not is_instance_valid(world.ship):
				print("[conn] not crewing a ship — use --jet=sea:destroyer")
				_conn_test = false
				world.get_tree().quit()
				return true
			print("[conn] on the bridge of %s" % world.ship.display_name())
			world.crew.leave_ship()
		elif _conn_step == 1 and _conn_t > 1.5:
			_conn_test = false
			var w_ok: bool = world.on_foot and is_instance_valid(world.walker)
			var cam_ok: bool = w_ok and is_instance_valid(world.walker.cam) \
				and world.walker.cam.current
			print("[conn] after handing over: on foot=%s, walker camera live=%s, still crewing a ship=%s" % [
				str(w_ok), str(cam_ok), str(is_instance_valid(world.ship))])
			print("[conn] RESULT: %s" % ("ok" if w_ok and cam_ok
				and not is_instance_valid(world.ship) else
				"FAILED — the view did not go with the man"))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --fleetfire
var _fleetfire := false
var _fleetfire_t := 0.0
var _ff_seen: Dictionary = {}        # instance id -> [wid, best approach, target name]

func tick_fleetfire(delta: float) -> bool:
	if _fleetfire:
		_fleetfire_t += delta
		for m in world.get_tree().get_nodes_in_group("missiles"):
			if not is_instance_valid(m):
				continue
			var key := m.get_instance_id()
			# Keyed on the contact itself. Bucketing by display name put every
			# unnamed contact in one pile and reported "85 rounds at one
			# target", which was the harness, not the fleet.
			var tid := 0
			var tgt: Variant = m.get("target")
			if tgt != null and is_instance_valid(tgt):
				tid = (tgt as Node).get_instance_id()
			var rec: Variant = _ff_seen.get(key)
			# `_min_d` is the round's own record of the closest it ever came to
			# what it was aimed at, so the answer survives the round being freed.
			# It sits at 1e9 until guidance has run once, so a round sampled on
			# its first frame must not be scored as a miss.
			var best: float = float(m.get("_min_d"))
			if rec == null:
				# and the range it was fired at, so the useful envelope can be
				# read off the data rather than guessed at
				var lr := -1.0
				var what := "?"
				if tid != 0:
					lr = (m as Node3D).global_position.distance_to(
						(tgt as Node3D).global_position)
					# Shooting at an inbound round is what the tubes are for and
					# it is a fair shot at long range: a missile flies straight.
					# Shooting at a fighter twenty kilometres out is not. They
					# have to be counted apart or the two hide each other.
					what = "missile" if (tgt is Missile) else (
						"aircraft" if (tgt is Aircraft) else "surface")
				_ff_seen[key] = [String(m.get("wid")), best, tid, lr, what]
			else:
				(rec as Array)[1] = minf(float((rec as Array)[1]), best)
				if tid != 0:
					(rec as Array)[2] = tid
		if _fleetfire_t > 100.0:
			_fleetfire = false
			var per: Dictionary = {}
			var wasted := 0
			var never := 0
			var total := 0
			for k in _ff_seen:
				var r: Array = _ff_seen[k]
				total += 1
				if int(r[2]) != 0:
					per[r[2]] = int(per.get(r[2], 0)) + 1
				if float(r[1]) > 1.0e8:
					never += 1          # guidance never ran: no contact at all
				elif float(r[1]) > 1000.0:
					wasted += 1
			var worst := 0
			for nm in per:
				worst = maxi(worst, int(per[nm]))
			print("[fleetfire] %d round(s) away in %.0f s at %d distinct contact(s)" % [
				total, _fleetfire_t, per.size()])
			print("[fleetfire] %d never got within a kilometre of what they were sent at; %d never had a contact at all" % [
				wasted, never])
			print("[fleetfire] the most rounds at any one contact: %d" % worst)
			# Where the engagement actually works: launch range against how
			# close the round then got.
			var buckets := ["<8 km", "8-15 km", "15-25 km", ">25 km"]
			var fired := [0, 0, 0, 0]
			var closed := [0, 0, 0, 0]
			for k2 in _ff_seen:
				var r2: Array = _ff_seen[k2]
				var lr2: float = float(r2[3]) if r2.size() > 3 else -1.0
				if lr2 < 0.0:
					continue
				var bi := 3
				if lr2 < 8000.0:
					bi = 0
				elif lr2 < 15000.0:
					bi = 1
				elif lr2 < 25000.0:
					bi = 2
				fired[bi] += 1
				if float(r2[1]) < 1000.0:
					closed[bi] += 1
			for bi2 in 4:
				print("[fleetfire]   fired at %-9s %3d round(s), %3d got within a kilometre" % [
					buckets[bi2], fired[bi2], closed[bi2]])
			var kinds := {}
			for k3 in _ff_seen:
				var r3: Array = _ff_seen[k3]
				var w3: String = String(r3[4]) if r3.size() > 4 else "?"
				var e: Array = kinds.get(w3, [0, 0])
				e[0] += 1
				if float(r3[1]) < 1000.0:
					e[1] += 1
				kinds[w3] = e
			for w4 in kinds:
				print("[fleetfire]   at a %-8s %3d round(s), %3d got within a kilometre" % [
					String(w4), int((kinds[w4] as Array)[0]), int((kinds[w4] as Array)[1])])
			# What good looks like: the fleet is not emptying its magazines,
			# no contact is being swarmed, and the shots it does take at
			# aircraft mostly connect. Interceptor shots at an inbound round
			# are allowed to fail — that is a hard shot honestly attempted —
			# but there must not be fifty of them.
			var air: Array = kinds.get("aircraft", [0, 0])
			var ok: bool = total <= 30 and worst <= 4 \
				and (int(air[0]) == 0 or float(air[1]) / float(air[0]) >= 0.5)
			print("[fleetfire] RESULT: %s" % ("ok" if ok else
				"FAILED — the fleet is emptying its tubes at nothing"))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --guardtest
var _guard_test := false
var _guard_t := 0.0
var _guard_step := 0
var _guard_boat: Ship = null
var _guard_shots := 0
var _guard_killed := 0

# A friendly warship covering the aircraft around her: does she see a round
# tracking one of ours, and does she put a cell in the air at it?
# not gated on the aeroplane surviving: whether she shoots at the round is
# the question, and the round may well arrive first
func tick_guard(delta: float) -> bool:
	if _guard_test and (is_instance_valid(world.player) or _guard_step >= 2):
		_guard_t += delta
		if _guard_step == 0 and _guard_t > 2.5:
			_guard_step = 1
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.has_vls() and v.alive:
					_guard_boat = v
					break
			if _guard_boat == null:
				print("[guard] no friendly hull with tubes")
				_guard_test = false
				world.get_tree().quit()
				return true
			# put the aeroplane near her, and a hostile round on its way to it
			var bp: Vector3 = _guard_boat.global_position
			world.player.global_transform = Transform3D(Basis(),
				bp + Vector3(0, 3000.0, -9000.0))
			world.player.linear_velocity = Vector3(0, 0, -180.0)
			world._reset_interp.call_deferred(world.player)
			_guard_boat.cells_left = 24
			print("[guard] %s has %d cells; our aeroplane 9 km off her bow at 3000 m" % [
				_guard_boat.display_name(), _guard_boat.cells_left])
		elif _guard_step == 1 and _guard_t > 4.0:
			_guard_step = 2
			# a hostile round, tracking the player
			var shooter: Ship = null
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh as Ship
				if v2 != null and v2.team != 0 and v2.alive:
					shooter = v2
					break
			var launch: Vector3 = world.player.global_position + Vector3(26000.0, -400.0, 0)
			var m := Missile.new()
			var dir: Vector3 = (world.player.global_position - launch).normalized()
			var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
			m.launch("sm2", Transform3D(Basis.looking_at(dir, up_ref), launch),
				dir * 260.0, shooter, world.player)
			m.team = 1
			world.add_child(m)
			print("[guard] a hostile round is up, 26 km out and tracking us")
		elif _guard_step == 2:
			var cells: int = _guard_boat.cells_left if is_instance_valid(_guard_boat) else 0
			_guard_shots = 24 - cells
			for mm in world.get_tree().get_nodes_in_group("interceptable"):
				if not is_instance_valid(mm) or not ("team" in mm) or int(mm.team) != 0:
					continue
				if not is_instance_valid(mm.target):
					continue
				if mm.target.is_in_group("interceptable"):
					if _guard_killed == 0:
						print("[guard]   %s away at %s — an interceptor" % [
							String(mm.wid), Sim.label_of(mm.target)])
					_guard_killed = 1
			if _guard_t > 40.0:
				_guard_test = false
				var inbound := 0
				for mm2 in world.get_tree().get_nodes_in_group("interceptable"):
					if is_instance_valid(mm2) and ("team" in mm2) and int(mm2.team) != 0:
						inbound += 1
				print("[guard] hostile rounds still in the air: %d" % inbound)
				print("[guard] she fired %d cell(s); an interceptor was sent at the round: %s" % [
					_guard_shots, "yes" if _guard_killed == 1 else "no"])
				print("[guard] RESULT: %s" % ("ok" if _guard_killed == 1
					else "FAILED — nothing was sent after it"))
				world.get_tree().quit()
		return true
	return false
#endregion


#region --boattest
var _boat_test := false
var _boat_t := 0.0

# A submarine's conn: can she hold a contact, can she dive, and does the
# ground stop her.
func tick_boat(delta: float) -> bool:
	if _boat_test:
		_boat_t += delta
		if _boat_t > 2.5:
			_boat_test = false
			var sub: Ship = null
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.can_dive() and v.alive:
					sub = v
					break
			if sub == null:
				print("[boat] no submarine on our side")
				world.get_tree().quit()
				return true
			world.crew.enter_ship(sub)
			print("[boat] %s: guns=%d tubes=%d, mast %.1f m" % [
				sub.display_name(), int(Ship.KINDS[sub.kind]["guns"]), sub.tubes(),
				sub.mast_height()])
			# the radar picture, and stepping through it
			var seen: Array = []
			for _i in 8:
				sub.cycle_target()
				if is_instance_valid(sub.ai_target) and not seen.has(sub.ai_target):
					seen.append(sub.ai_target)
			var names := PackedStringArray()
			for n in seen:
				names.append(Sim.label_of(n))
			print("[boat] target cycling reached %d distinct contact(s): %s" % [
				seen.size(), ", ".join(names)])
			# the weapons, from the conn
			var wseq := PackedStringArray([sub.current_weapon()])
			for _k in 3:
				sub.cycle_weapon()
				wseq.append(sub.current_weapon())
			print("[boat] weapon cycling: %s" % " -> ".join(wseq))
			# torpedoes: who has them, and does one run and hit
			var foe: Ship = null
			for sh3 in world.get_tree().get_nodes_in_group("ships"):
				var v3 := sh3 as Ship
				if v3 != null and v3.team != sub.team and v3.alive:
					foe = v3
					break
			var hp0: float = foe.health if foe != null else 0.0
			var fired := false
			if foe != null:
				sub.global_position = Vector3(foe.global_position.x, Sim.sea_surface(foe.global_position.x, foe.global_position.z + 2600.0), foe.global_position.z + 2600.0)
				sub.ai_target = foe
				sub._torp_cd = 0.0
				fired = sub.fire_torpedo(foe)
			print("[boat] torpedoes: %d aboard, launch=%s, target %s at %.1f km" % [
				sub.torps_left, str(fired),
				Sim.label_of(foe) if foe != null else "none",
				sub.global_position.distance_to(foe.global_position) * 0.001
				if foe != null else 0.0])
			var swam := 0.0
			var deepest := 0.0
			for _f4 in 60 * 150:
				for mm3 in world.get_tree().get_nodes_in_group("missiles"):
					if is_instance_valid(mm3) and String(mm3.wid) == "torpedo":
						var mp3: Vector3 = (mm3 as Node3D).global_position
						swam = maxf(swam, mp3.distance_to(sub.global_position))
						deepest = minf(deepest, mp3.y - Sim.sea_at(mp3.x, mp3.z))
				sub._physics_process(1.0 / 60.0)
				if foe != null and not foe.alive:
					break
			print("[boat] the fish ran %.0f m, %.1f m under the surface at deepest; hull %.0f -> %.0f" % [
				swam, deepest, hp0, foe.health if foe != null else 0.0])
			var views := PackedStringArray()
			for _v in 4:
				views.append("%.0f m" % Ship.VIEW_BOOM[sub.view_mode % Ship.VIEW_BOOM.size()])
				sub.view_mode = (sub.view_mode + 1) % Ship.VIEW_BOOM.size()
			print("[boat] view cycling (C): %s" % " -> ".join(views))
			# the sensor: can it take a patch of ground from the conn
			world.pod.platform = sub
			if not world.pod.active:
				world.pod.toggle()
			# At the coast, not at open water. Aiming six degrees down from a
			# conning tower puts the mark on the sea whatever the sight can do;
			# the claim to test is whether it can take a patch of *ground*.
			# In whatever direction the coast lies, and as far as it takes.
			#
			# This walked 36 km due west, which finds the shore on a world with
			# one authored coast to the west of the fleet. On a planet the boat
			# can be anywhere and so can the land: the sight was reported as
			# unable to take a patch of ground when there simply was not any
			# within thirty-six kilometres of due west.
			var shore := Vector3.INF
			for bi in 24:
				var brg: float = TAU * float(bi) / 24.0
				var dir := Vector3(cos(brg), 0.0, sin(brg))
				for gi in range(2, 200):
					var q: Vector3 = sub.global_position + dir * (float(gi) * 400.0)
					var hh: float = Sim.height_at(q.x, q.z)
					if hh > Sim.sea_at(q.x, q.z) + 25.0:
						shore = Vector3(q.x, hh, q.z)
						break
				if shore != Vector3.INF:
					break
			world.pod.tracked = null
			world.pod.mode = world.pod.SLEW
			if shore != Vector3.INF:
				var rel: Vector3 = shore - world.pod._head_origin()
				var loc: Vector3 = (sub.global_transform.basis.inverse() * rel).normalized()
				world.pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
				world.pod.yaw = atan2(-loc.x, -loc.z)
			else:
				world.pod.pitch = deg_to_rad(-6.0)
				world.pod.yaw = 0.0
			world.pod._process(0.016)
			world.pod.designate()
			var on_land: bool = world.pod.area_point != Vector3.INF \
				and world.pod.area_point.y > Sim.sea_at(world.pod.area_point.x,
					world.pod.area_point.z) + 2.0
			print("[boat] sight aimed at the coast %s (%.1f m elevation, %.1f km off)" % [
				str(shore.round()) if shore != Vector3.INF else "not found",
				shore.y if shore != Vector3.INF else 0.0,
				sub.global_position.distance_to(shore) * 0.001 if shore != Vector3.INF else 0.0])
			# and what the page would actually draw: the aim mark, the weapon
			# line and the selector all used to go straight to the aeroplane
			var aim_ok: bool = world.pod.aim_point() != Vector3.INF
			var holds: bool = world.pod.platform == sub
			print("[boat] page draws: carrier=%s, aim point=%s, weapon line=%s" % [
				str(holds), str(aim_ok),
				sub.weapon_label() if sub.has_method("weapon_label") else "-"])
			print("[boat] sensor from the conn: mode=%d (1=AREA), spot %s, on land=%s, %.1f m up" % [
				world.pod.mode, str(world.pod.area_point.round()), str(on_land),
				world.pod._head_origin().y - sub.global_position.y])
			# what the scope would paint, and whether her own rounds are on it
			sub.fire_vls(sub.ai_target)
			var own := 0
			for mm in world.get_tree().get_nodes_in_group("missiles"):
				if is_instance_valid(mm) and is_instance_valid(mm.shooter) \
						and mm.shooter == sub:
					own += 1
			print("[boat] tubes away: %d of her own rounds in the air for the scope" % own)
			# what the bridge and chase views would actually paint on the sea
			var eye: Camera3D = sub.cam
			var painted := 0
			var friendly := 0
			var hostile := 0
			var masked := 0
			if is_instance_valid(eye):
				sub._physics_process(1.0 / 60.0)
				var reach: float = maxf(Sim.radar_range(), 26000.0)
				for n in world.get_tree().get_nodes_in_group("hittable"):
					if not is_instance_valid(n) or n == sub or not (n is Node3D):
						continue
					if n.is_in_group("no_lock"):
						continue
					if n.has_method("is_alive") and not n.is_alive():
						continue
					var d: float = sub.global_position.distance_to(
						(n as Node3D).global_position)
					if d > reach:
						continue
					painted += 1
					if ("team" in n) and int(n.team) != sub.team:
						hostile += 1
					else:
						friendly += 1
					# is anything actually in the way, and if so what
					var e: Vector3 = sub.global_position \
						+ Vector3(0, sub.mast_height(), 0)
					var tp: Vector3 = (n as Node3D).global_position + Vector3(0, 4, 0)
					if d > 2000.0 and not Sim.line_of_sight(e, tp, 250.0):
						masked += 1
						if masked == 1:
							# walk it and say where, and how deep the water is there
							for k in 40:
								var q: Vector3 = e.lerp(tp, float(k) / 39.0)
								var g2: float = Sim.height_at(q.x, q.z)
								if q.y < g2 - 2.0:
									print("[boat]   %s masked at %s: ray %.1f m, ground %.1f m, sea level %.1f m" % [
										Sim.label_of(n), str(Vector2(q.x, q.z).round()),
										q.y, g2, Sim.sea_at(q.x, q.z)])
									break
			print("[boat] contacts the bridge view can label: %d (%d hostile, %d friendly), %d masked" % [
				painted, hostile, friendly, masked])
			# ground that is under the sea but still above a ship's sight line:
			# this is what used to block two hulls looking at each other
			var shoals := 0
			var probes := 0
			for si in 120:
				for sj in 120:
					var q2 := Vector2(sub.global_position.x - 30000.0 + float(si) * 500.0,
						sub.global_position.z - 30000.0 + float(sj) * 500.0)
					var g3: float = Sim.height_at(q2.x, q2.y)
					if g3 >= Sim.sea_at(q2.x, q2.y):
						continue
					probes += 1
					if g3 > Sim.sea_at(q2.x, q2.y) - 20.0:
						shoals += 1
			print("[boat] sea bed within 20 m of the surface at %d of %d wet samples — ground that used to mask" % [
				shoals, probes])
			print("[boat] she is at %s, %.0f km from the middle of the chart" % [
				str(Vector2(sub.global_position.x,
					sub.global_position.z).round()),
				Vector2(sub.global_position.x,
					sub.global_position.z).length() * 0.001])
			print("[boat] there is %.0f m of water under her" % (
				Sim.sea_at(sub.global_position.x, sub.global_position.z)
				- Sim.height_at(sub.global_position.x, sub.global_position.z)))
			print("[boat] the boat sits at %.1f m, her sight at %.1f m, sea level %.1f m" % [
				sub.global_position.y, sub.global_position.y + sub.mast_height(),
				Sim.sea_at(sub.global_position.x, sub.global_position.z)])
			if world.pod.active:
				world.pod.toggle()
			world.pod.platform = null
			# dive, and the ground under her
			var surf: float = sub.global_position.y
			sub.depth_order = 45.0
			# Long enough for her to get there. She answers her planes at
			# 2.2 m/s, so forty-five metres is twenty seconds; at four this
			# only ever measured the first nine metres of a dive. It passed on
			# the flat world for the wrong reason -- the water there was too
			# shallow to dive properly in, so she reached the bottom limit
			# inside the window and looked as though she had obeyed.
			for _f in 1500:
				sub._physics_process(1.0 / 60.0)
			print("[boat] ordered 45 m: rides at %.1f m (was %.1f), depth %.1f, periscope up=%s" % [
				sub.global_position.y, surf, sub.depth, str(sub.periscope_up())])
			sub.depth_order = 0.0
			for _f2 in 1500:
				sub._physics_process(1.0 / 60.0)
			print("[boat] ordered surface: rides at %.1f m, periscope up=%s" % [
				sub.global_position.y, str(sub.periscope_up())])
			# steam her at the beach and see whether the ground stops her
			# Find a beach and enough water to run at it from, in whatever
			# direction the coast happens to lie.
			#
			# This used to walk due west for the shore and then start 2.5 km due
			# east of it, which is only sound on a world with one authored coast
			# running north-south. On a generated planet a coastline can face
			# any way: walking east off the beach ran straight into more land,
			# and the boat began the run 99 m inside a hill, sat there for the
			# minute and was scored as a hull that would not move. Sixteen
			# bearings, and the first that has land ahead with deep water behind
			# it is the one to run.
			# Find a shore to run at, wherever one is.
			#
			# This used to work from wherever the fleet happened to moor, which
			# on a flat world with one coast was always a few kilometres off it.
			# A planet anchors its fleet in deep water, and deep water is deep
			# because it is far from land: measured, a hundred and fifty-eight
			# kilometres, with no coast inside the search at all. What this test
			# asks -- does the ground stop her -- does not depend on where she
			# was moored, so it looks for a coast and takes her to it.
			var land := Vector3.INF
			var from := Vector3.INF
			for ring in range(1, 200):
				var rr: float = float(ring) * 2000.0
				for bi in 16:
					var brg: float = TAU * (float(bi) / 16.0 + float(ring) * 0.11)
					var dir := Vector3(cos(brg), 0.0, sin(brg))
					var c0: Vector3 = sub.global_position + dir * rr
					if Sim.height_at(c0.x, c0.z) <= Sim.sea_at(c0.x, c0.z) + 2.0:
						continue
					# Dry ground, with water she floats in somewhere back along
					# the bearing. Not deep water: she runs at the beach on the
					# surface, so fifteen metres is plenty, and a shelf that
					# shallows gently has none of the twenty-eight I first asked
					# for anywhere within three kilometres of its own coast.
					for si in range(1, 50):
						var p: Vector3 = c0 - dir * (float(si) * 300.0)
						if Sim.height_at(p.x, p.z) < Sim.sea_at(p.x, p.z) - 15.0:
							land = Vector3(c0.x, 0.0, c0.z)
							from = Vector3(p.x, 0.0, p.z)
							break
					if land != Vector3.INF:
						break
				if land != Vector3.INF:
					break
			if land == Vector3.INF:
				print("[boat] no coast within reach with water to run at it from")
				world.get_tree().quit()
				return true
			sub.global_position = Vector3(from.x,
				Sim.sea_surface(from.x, from.z), from.z)
			sub.depth = 0.0
			sub.depth_order = 0.0
			print("[boat] beach at %s; starting %.1f km off it in %.0f m of water" % [
				str(land.round()), from.distance_to(land) * 0.001,
				Sim.sea_at(from.x, from.z) - Sim.height_at(from.x, from.z)])
			sub.heading = atan2(land.x - sub.global_position.x, -(land.z - sub.global_position.z))
			sub.telegraph = 1.0
			sub.speed = float(Ship.KINDS[sub.kind]["speed"])
			var start := sub.global_position
			var worst_dig := -1e9
			# Long enough to get there, not a fixed minute.
			#
			# The run is over when the ground has stopped her, and how long that
			# takes depends on how far off the beach she could be put. On a
			# gentle shelf the nearest water she floats in is seven kilometres
			# out, which at twelve knots is ten minutes -- so a one-minute run
			# measured a boat still in open water and called it a failure to
			# ground. Capped at twenty minutes so a boat that will never arrive
			# still ends the test.
			for _f3 in 60 * 60 * 20:
				sub._physics_process(1.0 / 60.0)
				if sub.global_position.distance_to(land) < 900.0:
					break
				var bed: float = Sim.height_at(sub.global_position.x, sub.global_position.z)
				worst_dig = maxf(worst_dig, bed - (sub.global_position.y
					- float(Ship.KINDS[sub.kind]["draught"])))
			print("[boat] driven at the shore: moved %.0f m, keel is %.1f m %s the ground at worst" % [
				start.distance_to(sub.global_position), absf(worst_dig),
				"INTO" if worst_dig > 0.0 else "clear of"])
			print("[boat] RESULT: %s" % ("ok" if seen.size() >= 2 and sub.depth < 1.0
				and worst_dig < 1.0 and own > 0 and on_land and painted > 0 else "FAILED"))
			world.get_tree().quit()
		return true
	return false
#endregion


#region --subtest2
var _subtest := false

# Can a submarine be crewed, and can it shoot?
func tick_subtest() -> bool:
	if _subtest:
		_subtest = false
		var boat: Ship = null
		for sh in world.get_tree().get_nodes_in_group("ships"):
			var v := sh as Ship
			if v != null and v.kind == "sub":
				boat = v
				break
		if boat == null:
			print("[sub] no submarine in the fleet")
			world.get_tree().quit()
			return true
		var crewable := PackedStringArray()
		for k in Ship.KINDS:
			var kd2: Dictionary = Ship.KINDS[k]
			if int(kd2["guns"]) > 0 or int(kd2.get("vls", 0)) > 0:
				crewable.append(k)
		print("[sub] crewable hulls in the menu: %s" % ", ".join(crewable))
		print("[sub] %s: boardable=%s, weapons=%s, tubes=%d" % [
			boat.display_name(), str(boat.is_in_group("boardable")),
			str(boat.weapons()), boat.tubes()])
		var mark := Ship.new()
		mark.setup("cargo", 1)
		world.add_child(mark)
		mark.global_position = boat.global_position + Vector3(9000.0, 0, 0)
		var before := world.get_tree().get_nodes_in_group("missiles").size()
		var ok2: bool = boat.fire_vls(mark)
		var after := world.get_tree().get_nodes_in_group("missiles").size()
		var what := ""
		for m in world.get_tree().get_nodes_in_group("missiles"):
			if is_instance_valid(m):
				what = String(m.wid)
		print("[sub] RESULT: fire_vls=%s, rounds %d -> %d, round type=%s, cells left %d" % [
			str(ok2), before, after, what, boat.cells_left])
		world.get_tree().quit()
	return false
#endregion


#region --navsensor
var _navsensor := false
var _navsensor_t := 0.0

# Can a ship's sensor do anything at all: point track, area track, laser.
func tick_navsensor(delta: float) -> bool:
	if _navsensor:
		_navsensor_t += delta
		if _navsensor_t > 2.5:
			_navsensor = false
			var boat: Ship = null
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v != null and v.team == 0 and v.has_gun():
					boat = v
					break
			if boat == null:
				print("[navsensor] no friendly warship")
				world.get_tree().quit()
				return true
			world.crew.enter_ship(boat)
			world.pod.platform = boat
			if not world.pod.active:
				world.pod.toggle()
			print("[navsensor] on %s: pod active=%s, carrier=%s" % [
				boat.display_name(), str(world.pod.active),
				Sim.label_of(world.pod.platform)])
			# point track: aim at the nearest hostile and designate
			var foe: Node3D = null
			var bd := 1e9
			for n in world.get_tree().get_nodes_in_group("ships"):
				var o := n as Ship
				if o == null or o.team == boat.team or not o.alive:
					continue
				var d := boat.global_position.distance_to(o.global_position)
				if d < bd:
					bd = d
					foe = o
			if foe != null:
				# The pod aims in the carrier's own frame: dir = basis * (yaw,
				# pitch). Working the angles off world axes and subtracting the
				# hull's heading is not the same thing, and it put the sight
				# somewhere the corvette was not — point track has been
				# reported as SLEW with nothing held every time this ran.
				var rel: Vector3 = foe.global_position - world.pod._head_origin()
				var loc: Vector3 = (boat.global_transform.basis.inverse() * rel).normalized()
				world.pod.pitch = asin(clampf(loc.y, -1.0, 1.0))
				world.pod.yaw = atan2(-loc.x, -loc.z)
				world.pod.mode = world.pod.SLEW
				world.pod._process(0.016)
				world.pod.designate()
				print("[navsensor] point track: mode=%d tracked=%s, ship target=%s" % [
					world.pod.mode, Sim.label_of(world.pod.tracked), Sim.label_of(boat.ai_target)])
			# area track: aim well down and short, at open ground or water
			world.pod.tracked = null
			world.pod.mode = world.pod.SLEW
			world.pod.pitch = deg_to_rad(-35.0)
			world.pod.yaw = 0.0
			world.pod._process(0.016)
			world.pod.designate()
			print("[navsensor] area track: mode=%d (1=AREA), spot %s, ship target=%s" % [
				world.pod.mode, str(world.pod.area_point.round()), Sim.label_of(boat.ai_target)])
			if not world.pod.lasing:
				world.pod.toggle_laser()
			world.pod._process(0.016)
			print("[navsensor] laser: lasing=%s, aim point %s" % [
				str(world.pod.lasing), str(world.pod.aim_point().round())])
			# and the scope: how many contacts a ship's radar would paint
			world.hud._scope_src = boat
			var painted := 0
			var reach: float = Sim.radar_range()
			for n in world.get_tree().get_nodes_in_group("hittable"):
				if not is_instance_valid(n) or n == boat or n.is_in_group("no_lock"):
					continue
				var dd := boat.global_position.distance_to(n.global_position)
				if dd < reach and (dd <= 2000.0 or Sim.line_of_sight(
						boat.global_position + Vector3(0, 4, 0),
						(n as Node3D).global_position + Vector3(0, 4, 0), 250.0)):
					painted += 1
			world.hud._scope_src = null
			print("[navsensor] radar scope: %d contacts within %.0f km" % [
				painted, reach * 0.001])
			# and the tubes take the designation
			var fired: bool = boat.fire_vls()
			print("[navsensor] tubes on the designation: fired=%s at %s" % [
				str(fired), Sim.label_of(boat.ai_target)])
			# and weapon switching with the sensor page shut, which is where
			# you would normally be standing
			if world.pod.active:
				world.pod.toggle()
			var seq := PackedStringArray([boat.current_weapon()])
			for _i in 3:
				boat.cycle_weapon()
				seq.append(boat.current_weapon())
			boat.set_weapon(0)
			var direct := boat.current_weapon()
			print("[navsensor] weapon switch with the pod shut: cycle %s, key 1 -> %s (pod active=%s)" % [
				" -> ".join(seq), direct, str(world.pod.active)])
			# and the same on a hull with no gun at all
			var boat2: Ship = null
			for sh2 in world.get_tree().get_nodes_in_group("ships"):
				var v2 := sh2 as Ship
				if v2 != null and v2.kind == "sub":
					boat2 = v2
					break
			if boat2 != null:
				print("[navsensor] submarine: weapons=%s, label=%s, gun=%s" % [
					str(boat2.weapons()), boat2.weapon_label(),
					str(boat2.has_gun())])
			world.get_tree().quit()
	return false
#endregion


#region --dctest
var _dc_test := false
var _dc_t := 0.0
var _dc_ship: Node3D = null
var _dc_said := 0

# One ship hurt on purpose, then left alone to see if the party save her.
func tick_dc(delta: float) -> bool:
	if _dc_test:
		_dc_t += delta
		if _dc_t > 1.5 and not is_instance_valid(_dc_ship):
			# nobody fights: this is about the party, not the enemy
			for sh in world.get_tree().get_nodes_in_group("ships"):
				var v := sh as Ship
				if v == null:
					continue
				if v.kind == "destroyer" and _dc_ship == null:
					_dc_ship = v          # she keeps her captain
				else:
					v.ai = false          # nobody else fights, or moves
					v.telegraph = 0.0
					v.speed = 0.0
			if _dc_ship == null:
				print("[dc] no destroyer")
				_dc_test = false
				return true
			_dc_ship.set("telegraph", 1.0)
			print("[dc] %s hull %.0f, full ahead" % [_dc_ship.call("display_name"),
				_dc_ship.get("health")])
		elif is_instance_valid(_dc_ship) and _dc_t > 3.0 and _dc_said == 0:
			_dc_said = 1
			_dc_ship.call("take_hit", 620.0, null)
			_dc_ship.call("take_hit", 380.0, null)
			print("[dc] two hits for 1000 of 2200: %s" % _dc_ship.call("damage_report"))
		elif is_instance_valid(_dc_ship) and _dc_t > 3.0:
			var step := int((_dc_t - 3.0) / 12.0) + 1
			if step > _dc_said and step <= 10:
				_dc_said = step
				print("[dc] %6.1fs  %s  spd %4.1f  list %4.1f deg" % [
					_dc_t, _dc_ship.call("damage_report"), _dc_ship.get("speed"),
					rad_to_deg(float(_dc_ship.get("list_ang")))])
			if _dc_t > 132.0:
				_dc_test = false
				print("[dc] RESULT: hull %.0f, %s" % [_dc_ship.get("health"),
					"afloat" if bool(_dc_ship.get("alive")) else "sunk"])
				world.get_tree().quit()
	return false
#endregion


#region --seatest
var _sea_test := false

func tick_sea() -> void:
	if _sea_test:
		_sea_test = false
		var deep := 0
		var total := 0
		var lo := 1e9
		for gx in range(0, 14):
			var line := ""
			for gz in range(-6, 7):
				var x := 12000.0 + float(gx) * 4000.0
				var z := float(gz) * 6000.0
				var hh := Sim.height_at(x, z)
				lo = minf(lo, hh)
				total += 1
				if hh < Sim.sea_at(x, z) - 15.0:
					deep += 1
					line += "~"
				else:
					line += "#"
			print("[sea] x=%6.0f  %s" % [12000.0 + float(gx) * 4000.0, line])
		print("[sea] %d of %d sample points are deep water; lowest %.0f m (flat datum %.0f)" % [
			deep, total, lo, Sim.WATER_LEVEL])
		world.get_tree().quit()
#endregion


#region --subtest
var _sub_test := false
var _sub_t := 0.0
var _sub_before := 0
var _sub_aim := Vector3.ZERO

func tick_sub(delta: float) -> bool:
	if _sub_test:
		_sub_t += delta
		if _sub_t > 2.0 and _sub_aim == Vector3.ZERO:
			var want := Vector3.ZERO
			var best := 0
			for cx in range(-12, 13):
				for cz in range(-12, 13):
					var q := Vector3(float(cx) * 900.0, 0.0, float(cz) * 900.0)
					var c := world.scenery.count_standing(q, 400.0)
					if c > best:
						best = c
						want = q
			want.y = Sim.height_at(want.x, want.z)
			_sub_aim = want
			_sub_before = world.scenery.count_standing(want, 3000.0)
			var boat: Ship = null
			for sh in world.get_tree().get_nodes_in_group("ships"):
				if is_instance_valid(sh) and (sh as Ship).can_launch():
					boat = sh
					break
			if boat == null:
				print("[sub] no boat able to launch")
				_sub_test = false
				return true
			print("[sub] %s launching at %s, %d structures standing within 3 km" % [
				boat.display_name(), str(want.round()), _sub_before])
			Sim.salvo_watch = true
			Sim.salvo_weapon = "slbm"
			Sim.salvo_mark = want
			Sim.salvo_log.clear()
			boat.launch_strategic(want)
		elif _sub_t > 90.0 or (_sub_t > 12.0
				and world.get_tree().get_nodes_in_group("missiles").is_empty()):
			_sub_test = false
			var after := world.scenery.count_standing(_sub_aim, 3000.0)
			for e in Sim.salvo_log:
				print("[sub]   %s" % String(e))
			print("[sub] RESULT: %d of %d structures within 3 km destroyed" % [
				_sub_before - after, _sub_before])
			world.get_tree().quit()
	return false
#endregion


#region --fleettest
var _fleet_test := false
var _fleet_t := 0.0
var _fleet_p0 := Vector3.ZERO

func tick_fleet(delta: float) -> void:
	if _fleet_test:
		_fleet_t += delta
		var ships := world.get_tree().get_nodes_in_group("ships")
		if _fleet_t > 2.0 and _fleet_p0 == Vector3.ZERO and not ships.is_empty():
			_fleet_p0 = (ships[0] as Node3D).global_position
		elif _fleet_t > 14.0:
			_fleet_test = false
			var moved := 0.0
			var afloat := 0
			var lo := 1e9
			var hi := -1e9
			for sh in ships:
				if not is_instance_valid(sh):
					continue
				afloat += 1
				# Against the sea at THAT hull's position, not against a level
				# plate. The ocean is a shell now: sixty kilometres out its
				# surface is 283 m below the origin's, so a hull floating
				# perfectly reads as 283 m "low" if you measure it against a
				# single number.
				var q: Vector3 = (sh as Node3D).global_position
				var rel: float = q.y - Sim.sea_at(q.x, q.z)
				lo = minf(lo, rel)
				hi = maxf(hi, rel)
			if not ships.is_empty():
				moved = (ships[0] as Node3D).global_position.distance_to(_fleet_p0)
			print("[fleet] %d vessels, %d in the water group; lead ship made %.0f m; hull height above the sea from %.1f to %.1f m (flat datum %.1f)" % [
				world.fleet_yard.fleet_count, afloat, moved, lo, hi, Sim.WATER_LEVEL])
			world.get_tree().quit()
#endregion
