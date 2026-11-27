class_name StreakTests
extends TestSuite
## Killstreaks in a street fight: called, flown, landed and pictured.
##
## Command-line tests, split out of `infantry_tests.gd`: see `TestHarness`.

## Claims the command-line flags this group owns; false if `a` is not one.
func parse_arg(a: String) -> bool:
	if a == "--sentrytest":
		_sentry_test = true
	elif a == "--droptest":
		_drop_test = true
	elif a.begins_with("--dropshot="):
		_drop_shot = a.substr(11)
	elif a == "--streaktest":
		_streak_test = true
	elif a == "--helistreak":
		_heli_streak = true
	else:
		return false
	return true


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
	cq.streaks.bank["sentry"] = 1
	var ok: bool = cq.streaks.call_in("sentry")
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
			for it in world.cqb.streaks.inbound():
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
	cq.streaks.bank["smoke"] = 1
	cq.streaks.picked("smoke", mark)
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
	cq.streaks.bank["supply"] = 1
	cq.streaks.picked("supply", here + fwd * 1.0)
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
	cq.streaks.bank["vest"] = 1
	cq.streaks.picked("vest", here + fwd * 1.0)
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
	cq.streaks.bank["cuav"] = 1
	var ok: bool = cq.streaks.call_in("cuav")
	print("[drop] counter-UAV: called %s, their side jammed for %.0f s" % [ok, float(Killstreaks.jammed[1])])
	if not ok or float(Killstreaks.jammed[1]) <= 0.0:
		bad.append("counter-UAV did not jam")
	Killstreaks.jammed[0] = 10.0
	var was_pick: Array = Killstreaks.streak_pick.duplicate()
	Killstreaks.streak_pick = ["uav", "smoke", "strike", "supply"]
	cq.streaks.bank["uav"] = 1
	Input.action_press(&"weapon_4")
	await world.get_tree().physics_frame
	await world.get_tree().physics_frame
	Input.action_release(&"weapon_4")
	print("[drop] jammed ourselves: UAV still banked %d (should be 1), drone up %s" % [
		int(cq.streaks.bank["uav"]), is_instance_valid(cq.streaks.uav)])
	if int(cq.streaks.bank["uav"]) != 1:
		bad.append("an air streak went up while jammed")
	Killstreaks.jammed[0] = 0.0
	Killstreaks.streak_pick = was_pick
	# EMP: one of their sentries knocked out, their sights and air down
	var foe_st := SentryTurret.new()
	foe_st.team = 1
	foe_st.arena = cq
	world.add_child(foe_st)
	foe_st.global_position = here + fwd * 40.0
	await world.get_tree().physics_frame
	cq.streaks.bank["emp"] = 1
	var emp_ok: bool = cq.streaks.call_in("emp")
	await world.get_tree().physics_frame
	if _drop_shot != "":
		await world.get_tree().create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		world.get_viewport().get_texture().get_image().save_png(_drop_shot.replace(".png", "_emp.png"))
	print("[drop] EMP: called %s; their sentry %s; their sights dark for %.0f s, air jammed %.0f s" % [
		emp_ok, "knocked out" if not foe_st.alive else "STILL UP", float(Killstreaks.emp_t[1]),
		float(Killstreaks.jammed[1])])
	if not emp_ok or foe_st.alive or float(Killstreaks.emp_t[1]) <= 0.0:
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
		cq.streaks.bank["wp"] = 1
		cq.streaks.wp_from = burn_at - Vector3(20, 0, 0)
		cq.streaks.picked("wp", burn_at + Vector3(20, 0, 0))
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
	cq.streaks.bank["swarm"] = 1
	Killstreaks.jammed[0] = 0.0
	var sw_ok: bool = cq.streaks.call_in("swarm")
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
	cq.streaks.bank["heli"] = 1
	var h_ok: bool = cq.streaks.call_in("heli")
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
	cq.streaks.bank["armour"] = 1
	cq.streaks.picked("armour", here + fwd * 30.0)
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
	cq.streaks.bank["dogs"] = 1
	var dg_ok: bool = cq.streaks.call_in("dogs")
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
	cq.streaks.bank["jugg"] = 1
	w.armour = 0.0
	w.health = 100.0
	var jg_ok: bool = cq.streaks.call_in("jugg")
	var jh0: float = w.health
	w.take_hit(100.0, null)
	print("[drop] juggernaut: suited %s, holding the %s with %d rounds; a 100 hit took %.0f health, %.0f armour left" % [
		jg_ok, String(w.gun_spec()["name"]), w.ammo, jh0 - w.health, w.armour])
	if not jg_ok or String(w.gun_spec()["id"]) != "minigun" or absf((jh0 - w.health) - 20.0) > 0.5:
		bad.append("the juggernaut suit is not right")
	w.health = 100.0
	# the chopper gunner: on the guns, circling low, and the 30 mm on a man
	cq.streaks.bank["chopper"] = 1
	var ch_ok: bool = cq.streaks.call_in("chopper")
	var ch: Aircraft = world.called_gunship
	var c_in := Vector2(cq.centre.x, cq.centre.y)
	var called_from: float = Vector2(ch.global_position.x, ch.global_position.z).distance_to(c_in) \
		if is_instance_valid(ch) else -1.0
	var boarded_at := -1.0
	for i in Engine.physics_ticks_per_second * 20:
		await world.get_tree().physics_frame
		if boarded_at < 0.0 and world.gunning:
			boarded_at = float(i) / float(Engine.physics_ticks_per_second)
	print("[drop] chopper gunner: called up %.0f m out from the town, on the guns after %.1f s" % [
		called_from, boarded_at])
	if called_from < 900.0 or boarded_at < 5.0:
		bad.append("the chopper gunner did not fly in")
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
		# where each rocket comes down, against the spot it was laid on
		var falls: Array = []
		var flying := {}
		ch.store_released.connect(func(m: Node) -> void:
			flying[m] = 1e9
			m.tree_exiting.connect(func() -> void:
				falls.append(float(flying[m]))
				flying.erase(m)))
		for i in Engine.physics_ticks_per_second * 8:
			await world.get_tree().physics_frame
			if not is_instance_valid(mark_man) or not mark_man.alive:
				break
			mark_man.global_position = spot
			if ch.battery.fire(world, Soldier.chest_of(mark_man)):
				shots += 1
			for fm in flying:
				if is_instance_valid(fm):
					flying[fm] = minf(float(flying[fm]), (fm as Node3D).global_position.distance_to(spot))
		for i in Engine.physics_ticks_per_second * 4:
			if flying.is_empty():
				break
			await world.get_tree().physics_frame
			for fm in flying:
				if is_instance_valid(fm):
					flying[fm] = minf(float(flying[fm]), (fm as Node3D).global_position.distance_to(spot))
		falls.sort()
		print("[drop] chopper gunner rockets: %d down, from the spot (m): %s" % [falls.size(),
			", ".join(PackedStringArray(falls.map(func(f: float) -> String: return "%.0f" % f)))])
		var dead: bool = not is_instance_valid(mark_man) or not mark_man.alive
		print("[drop] chopper gunner: %d %s at a man in the street, he is %s" % [
			shots, String(ch.battery.gun().get("name", "rounds")), "dead" if dead else "still up"])
		if not dead:
			bad.append("the chopper gunner could not kill a man in the open")
	_drop_seen.erase("_on")
	var seen: Array = _drop_seen.keys()
	seen.sort()
	print("[drop] on the map along the way: %s" % ", ".join(PackedStringArray(seen)))
	print("[drop] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED -- " + ", ".join(bad)))
	world.get_tree().quit()
#endregion


#region --helistreak
## The ATTACK HELICOPTER streak over a ground fight: once a second, how far it
## is from the middle of the town, how far its nose is off whatever it is
## after, what that is, and what it has fired. --preset=ground:foot --helistreak
var _heli_streak := false
var _hs_heli: AIHeli = null
var _hs_t := 0.0
var _hs_fired := {}

func tick_heli_streak(delta: float) -> void:
	if not _heli_streak or not is_instance_valid(world.cqb) or not is_instance_valid(world.walker):
		return
	var cq: CqbMatch = world.cqb
	if _hs_heli == null:
		cq.set_away(false)
		cq.streaks.bank["heli"] = 1
		if not cq.streaks.call_in("heli"):
			print("[helistreak] could not call it")
			world.get_tree().quit()
			return
		for n in world.get_children():
			if n is AIHeli and n.team == 0:
				_hs_heli = n
		if _hs_heli == null:
			print("[helistreak] no helicopter appeared")
			world.get_tree().quit()
			return
		_hs_heli.store_released.connect(func(m: Node) -> void:
			var k: String = String(m.get("wid")) if m != null else "?"
			_hs_fired[k] = int(_hs_fired.get(k, 0)) + 1)
		return
	_hs_t += delta
	if fmod(_hs_t, 1.0) < delta and is_instance_valid(_hs_heli):
		var h := _hs_heli
		var c := Vector3(cq.centre.x, h.global_position.y, cq.centre.y)
		var foe: Node3D = h.target as Node3D if is_instance_valid(h.target) else null
		var off := -1.0
		var what := "-"
		if foe != null:
			var to: Vector3 = foe.global_position - h.global_position
			to.y = 0.0
			var nose: Vector3 = -h.global_transform.basis.z
			nose.y = 0.0
			off = rad_to_deg(nose.angle_to(to))
			what = "%s %.0fm" % [foe.get_class() if foe.get_script() == null
				else String(foe.get_script().get_global_name()), to.length()]
		print("[helistreak] t=%2.0f centre %4.0fm agl %3.0f state %d nose-off %4.0f deg  target %s  gun %s fired %s hp=%.0f spd=%.0f vy=%.1f pitch=%.0f thr=%.2f" % [
			_hs_t, h.global_position.distance_to(c),
			h.global_position.y - Sim.height_at(h.global_position.x, h.global_position.z),
			h.state, off, what, str(h.ammo), str(_hs_fired), float(h.health),
			h.linear_velocity.length(), h.linear_velocity.y,
			rad_to_deg(asin(clampf(-h.global_transform.basis.z.y, -1.0, 1.0))), h.throttle])
	if _hs_t > 45.0 or not is_instance_valid(_hs_heli):
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
	var was_pick: Array = Killstreaks.streak_pick.duplicate()
	Killstreaks.streak_pick = ["gunship", "strafe", "uav", "mortar"]
	var chosen: Array = Killstreaks.chosen_streaks()
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
		var before: Dictionary = world.cqb.streaks.bank.duplicate()
		foe.take_hit(1000.0, world.walker)
		for id in world.cqb.streaks.bank:
			if int(world.cqb.streaks.bank[id]) > int(before.get(id, 0)):
				earned.append("%d:%s" % [world.cqb.streaks.streak, id])
		await world.get_tree().process_frame
	print("[streak] earned on the way to %d kills: %s" % [world.cqb.streaks.streak, ", ".join(PackedStringArray(earned))])
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
		for r0 in world.cqb.streaks.rounds:
			if is_instance_valid(r0):
				n_live += 1
		return world.cqb.streaks.bombs.size() + n_live
	var queued_before: int = in_flight.call()
	world.cqb.streaks.bank["mortar"] = 1
	world.cqb.streaks.picked("mortar", spot)
	var queued: int = int(in_flight.call()) - queued_before
	print("[streak] mortar called: %d rounds on the way, bank now %s" % [
		queued, str(world.cqb.streaks.bank["mortar"])])
	if queued != 10 or int(world.cqb.streaks.bank["mortar"]) != 0:
		bad.append("calling it did not queue ten rounds and spend it")
	# and the map has them coming in, not only where they will land
	await world.get_tree().create_timer(3.0).timeout
	var shown_shells := 0
	var shown_gun := false
	for it in world.cqb.streaks.inbound():
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
		if nd is CarpetBomb:
			var cbm: Node3D = nd
			cbm.tree_exiting.connect(func(): landed_s.append(cbm.global_position))
	world.get_tree().node_added.connect(watch_s)
	world.cqb.streaks.bank["strike"] = 1
	var sk := Vector3(world.cqb.centre.x - 20.0, 0.0, world.cqb.centre.y + 10.0)
	sk.y = Sim.height_at(sk.x, sk.z)
	world.cqb.streaks.picked("strike", sk)
	var srun: Node = null
	for n0 in world.get_children():
		if n0 is CarpetRun:
			srun = n0
	# taken now: the run frees itself once it has flown out the far side
	var came_over: bool = srun != null
	var plane_on_map := false
	var t_strike := 0.0
	while is_instance_valid(srun) and t_strike < 40.0:
		await world.get_tree().physics_frame
		t_strike += 1.0 / 120.0
		if not plane_on_map:
			for it2 in world.cqb.streaks.inbound():
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
	world.cqb.streaks.bank["strafe"] = 1
	var g0 := Vector3(world.cqb.centre.x - 90.0, 0.0, world.cqb.centre.y - 30.0)
	var g1 := Vector3(world.cqb.centre.x + 110.0, 0.0, world.cqb.centre.y + 40.0)
	world.cqb.streaks.strafe_from = g0
	var hits0: int = world.cqb.streaks.cannon_hits
	world.cqb.streaks.picked("strafe", g1)
	var grun: Node = null
	for n1 in world.get_children():
		if n1 is GunRun:
			grun = n1
	var gun_came: bool = grun != null
	var gun_on_map := false
	var t_gun := 0.0
	while is_instance_valid(grun) and t_gun < 45.0:
		await world.get_tree().physics_frame
		t_gun += 1.0 / 120.0
		if not gun_on_map:
			for it3 in world.cqb.streaks.inbound():
				if String(it3.get("label", "")) == "A-10 GUN RUN":
					gun_on_map = true
	var gun_hits: int = world.cqb.streaks.cannon_hits - hits0
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
	world.cqb.streaks.bank["carpet"] = 1
	world.cqb.streaks.carpet_from = ca
	var landed: Array = []
	var bomblets: Array = [0]
	var watch_new := func(n: Node) -> void:
		if n is CarpetBomb:
			var cbomb := n as CarpetBomb
			cbomb.tree_exiting.connect(func() -> void:
				if cbomb.bomblet:
					bomblets[0] = int(bomblets[0]) + 1
				else:
					landed.append(cbomb.global_position))
	world.get_tree().node_added.connect(watch_new)
	world.cqb.streaks.picked("carpet", cb)
	var run: Node = null
	for n in world.get_children():
		if n is CarpetRun:
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
	world.cqb.streaks.bank["uav"] = 1
	world.cqb.streaks.call_in("uav")
	var drones: Array = world.get_tree().get_nodes_in_group("drones")
	if drones.is_empty() or world.cqb.streaks.uav_t <= 0.0:
		bad.append("calling the UAV put no drone up")
	else:
		var dr: Node3D = drones[0]
		var up: float = dr.global_position.y - Sim.height_at(dr.global_position.x, dr.global_position.z)
		dr.call("take_hit", 500.0, null)
		print("[streak] UAV: a drone %.0f m up, in the lock list %s; shot down, the map has %.0f s left" % [
			up, str(dr.is_in_group("hittable") or not dr.call("is_alive")), world.cqb.streaks.uav_t])
		if world.cqb.streaks.uav_t > 0.0:
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
						and (c as Node3D).global_position.distance_to(gz) < Killstreaks.TAC_LETHAL:
					n += 1
		return n
	var men_near := func() -> int:
		var n := 0
		for sd in world.cqb.soldiers:
			if is_instance_valid(sd) and (sd as Node3D).global_position.distance_to(gz) < Killstreaks.TAC_LETHAL * 0.9:
				n += 1
		return n
	var props_before: int = standing.call()
	world.cqb.streaks.bank["tacnuke"] = 1
	world.cqb.streaks.picked("tacnuke", gz)
	var hp_before: float = world.walker.health
	for i in int(11.5 * 120.0):
		await world.get_tree().physics_frame
	var men_before: int = men_near.call()
	for i in 240:
		await world.get_tree().physics_frame
	print("[streak] tactical nuke %.0f m from him: %d props standing inside it before and %d after, %d men inside it at the flash and %d after; his health %.0f -> %.0f, bank %s" % [
		world.walker.global_position.distance_to(gz), props_before, int(standing.call()),
		men_before, int(men_near.call()), hp_before, world.walker.health, str(world.cqb.streaks.bank["tacnuke"])])
	if int(world.cqb.streaks.bank["tacnuke"]) != 0 or int(standing.call()) > 0 or int(men_near.call()) > 0:
		bad.append("the tactical nuke left something standing inside its radius")
	# Nothing left standing: what is still solid in there is the heap a
	# block or a prop was brought down to, drawn as that heap, and no more.
	var heaps := {}
	for k in Obstacles._rubble_of:
		heaps[int(Obstacles._rubble_of[k])] = true
	var standing_solid := 0
	for id in Obstacles.ids_in(Vector2(gz.x - 60, gz.z - 60), Vector2(gz.x + 60, gz.z + 60)):
		if Obstacles.gone(id) or heaps.has(id):
			continue
		var oc: Vector3 = Obstacles.centre_of(id)
		if Vector2(oc.x - gz.x, oc.z - gz.z).length() < Killstreaks.TAC_LETHAL * 0.9 \
				and Obstacles.top_of(id) - Sim.height_at(oc.x, oc.z) > 1.0:
			standing_solid += 1
	print("[streak] inside the nuke's radius after: %d solid things that are not a heap" % standing_solid)
	if standing_solid > 0:
		bad.append("something inside the nuke's radius still stands")
	# the deploy screen
	var dm := DeployMenu.new()
	world.add_child(dm)
	dm.open("none", true, "usa")
	(dm._streak_ticks["strike"] as CheckButton).button_pressed = true
	var five_refused: bool = not Killstreaks.streak_pick.has("strike") \
		and Killstreaks.streak_pick.size() == 4
	for id in ["gunship", "strafe", "mortar"]:
		(dm._streak_ticks[id] as CheckButton).button_pressed = false
	(dm._streak_ticks["uav"] as CheckButton).button_pressed = false
	var none_refused: bool = Killstreaks.streak_pick == ["uav"]
	print("[streak] deploy screen: a fifth refused %s, taking off the last refused %s" % [
		str(five_refused), str(none_refused)])
	if not five_refused or not none_refused:
		bad.append("the deploy screen let the count go outside one to four")
	dm.queue_free()
	Killstreaks.streak_pick = was_pick
	for b in bad:
		print("[streak] %s" % b)
	print("[streak] RESULT: %s" % ("ok" if bad.is_empty() else "FAILED"))
	world.get_tree().quit()
#endregion
